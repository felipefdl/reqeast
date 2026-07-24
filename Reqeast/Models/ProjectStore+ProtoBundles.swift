//
//  ProjectStore+ProtoBundles.swift
//  Reqeast
//

import Foundation
import os

private let protoBundleStoreLogger = Logger(subsystem: "app.reqeast", category: "ProjectStore.ProtoBundles")

extension ProjectStore {

    func protoBundles(for projectId: UUID) -> [ProtoBundle] {
        protoBundles.filter { $0.projectId == projectId && $0.deletedAt == nil }
    }

    func protoBundle(id: UUID) -> ProtoBundle? {
        protoBundles.first { $0.id == id && $0.deletedAt == nil }
    }

    /// True when the referenced bundle exists, is not tombstoned, and has hydrated descriptor bytes on disk.
    func isGrpcProtoReady(protoBundleId: UUID?) -> Bool {
        guard let protoBundleId,
              let bundle = protoBundle(id: protoBundleId) else {
            return false
        }
        return bundle.assetHydrated && bundle.hasLocalProtoBytes()
    }

    @discardableResult
    func importProtoBundle(
        projectId: UUID,
        name: String,
        protoSourceDirectory: URL,
        entryFile: String,
        compiled: CompiledProtoBundle
    ) throws -> ProtoBundle {
        try validateProtoBundleMetadata(
            name: name,
            contentFingerprint: compiled.contentFingerprint,
            entryFile: entryFile,
            fileCount: Int(compiled.fileCount)
        )

        let bundleId = UUID()
        let bundleDirectory = ProtoBundleService.bundleDirectory(projectId: projectId, bundleId: bundleId)
        do {
            try ProtoBundleService.writeBundleContents(
                bundleDirectory: bundleDirectory,
                protoSourceDirectory: protoSourceDirectory,
                descriptorBytes: compiled.descriptorBytes,
                fingerprint: compiled.contentFingerprint
            )
        } catch let error as ProtoBundleError {
            ProtoBundleService.deleteBundleDirectory(projectId: projectId, bundleId: bundleId)
            throw error
        } catch {
            ProtoBundleService.deleteBundleDirectory(projectId: projectId, bundleId: bundleId)
            throw ProtoBundleError.diskWriteFailed
        }

        var bundle = ProtoBundle(
            id: bundleId,
            projectId: projectId,
            name: name,
            contentFingerprint: compiled.contentFingerprint,
            entryFile: entryFile,
            fileCount: Int(compiled.fileCount),
            assetHydrated: true
        )
        bundle.touch()
        protoBundles.append(bundle)
        try saveLocalOrThrow()
        CloudSyncService.shared.queueSave(bundle)
        return bundle
    }

    @discardableResult
    func saveBundleFromReflection(
        projectId: UUID,
        name: String,
        descriptorBytes: Data,
        contentFingerprint: String,
        entryFile: String = "reflection"
    ) throws -> ProtoBundle {
        try validateProtoBundleMetadata(
            name: name,
            contentFingerprint: contentFingerprint,
            entryFile: entryFile,
            fileCount: 0
        )

        let bundleId = UUID()
        let bundleDirectory = ProtoBundleService.bundleDirectory(projectId: projectId, bundleId: bundleId)
        do {
            try ProtoBundleService.writeBundleContents(
                bundleDirectory: bundleDirectory,
                protoSourceDirectory: nil,
                descriptorBytes: descriptorBytes,
                fingerprint: contentFingerprint
            )
        } catch let error as ProtoBundleError {
            ProtoBundleService.deleteBundleDirectory(projectId: projectId, bundleId: bundleId)
            throw error
        } catch {
            ProtoBundleService.deleteBundleDirectory(projectId: projectId, bundleId: bundleId)
            throw ProtoBundleError.diskWriteFailed
        }

        var bundle = ProtoBundle(
            id: bundleId,
            projectId: projectId,
            name: name,
            contentFingerprint: contentFingerprint,
            entryFile: entryFile,
            fileCount: 0,
            assetHydrated: true
        )
        bundle.touch()
        protoBundles.append(bundle)
        try saveLocalOrThrow()
        CloudSyncService.shared.queueSave(bundle)
        return bundle
    }

    func renameProtoBundle(id: UUID, name: String) throws {
        guard let index = protoBundles.firstIndex(where: { $0.id == id && $0.deletedAt == nil }) else {
            return
        }
        try validateProtoBundleMetadata(
            name: name,
            contentFingerprint: protoBundles[index].contentFingerprint,
            entryFile: protoBundles[index].entryFile,
            fileCount: protoBundles[index].fileCount
        )
        protoBundles[index].name = name
        protoBundles[index].touch()
        try saveLocalOrThrow()
        CloudSyncService.shared.queueSave(protoBundles[index])
    }

    func deleteProtoBundle(id: UUID) {
        guard let index = protoBundles.firstIndex(where: { $0.id == id && $0.deletedAt == nil }) else {
            return
        }
        var bundle = protoBundles[index]
        bundle.tombstone()
        DeletionTombstoneStore.shared.add(ids: [id])
        ProtoBundleService.deleteBundleDirectory(projectId: bundle.projectId, bundleId: bundle.id)
        protoBundles.removeAll { $0.id == id }
        do {
            try saveLocalOrThrow()
        } catch {
            protoBundleStoreLogger.fault("deleteProtoBundle save failed: \(error)")
        }
        CloudSyncService.shared.queueDelete(recordType: .protoBundle, id: id)
    }

    /// Copies selected `.proto` files into a temp directory, compiles, and imports a bundle.
    func importProtoBundleFromFiles(
        projectId: UUID,
        name: String,
        entryFile: String,
        protoFileURLs: [URL]
    ) async throws -> ProtoBundle {
        guard !protoFileURLs.isEmpty else {
            throw ProtoBundleError.zipFailed("No .proto files selected.")
        }

        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("proto-import-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        var securityScopedURLs: [URL] = []
        defer {
            for url in securityScopedURLs {
                url.stopAccessingSecurityScopedResource()
            }
        }

        for url in protoFileURLs {
            if url.startAccessingSecurityScopedResource() {
                securityScopedURLs.append(url)
            }
            let destination = tempRoot.appendingPathComponent(url.lastPathComponent)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: url, to: destination)
        }

        let compiled = try await GrpcService.compileBundle(
            rootPath: tempRoot.path,
            entryFiles: [entryFile]
        )
        return try importProtoBundle(
            projectId: projectId,
            name: name,
            protoSourceDirectory: tempRoot,
            entryFile: entryFile,
            compiled: compiled
        )
    }

    private func validateProtoBundleMetadata(
        name: String,
        contentFingerprint: String,
        entryFile: String,
        fileCount: Int
    ) throws {
        let draft = ProtoBundle(
            projectId: UUID(),
            name: name,
            contentFingerprint: contentFingerprint,
            entryFile: entryFile,
            fileCount: fileCount
        )
        let jsonData = try JSONEncoder().encode(draft)
        guard jsonData.count <= CloudSyncService.maxRecordPayloadBytes else {
            throw BulkImportError.recordTooLarge(
                recordType: .protoBundle,
                id: draft.id,
                byteCount: jsonData.count
            )
        }
    }
}