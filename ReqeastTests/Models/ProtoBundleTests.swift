//
//  ProtoBundleTests.swift
//  ReqeastTests
//

import Foundation
import Testing
@testable import Reqeast

@Suite("ProtoBundle", .serialized)
struct ProtoBundleTests {

    @Test func protoBundleMaxBytesMatchesSafeFetch() {
        #expect(ProtoBundle.maxBundleBytes == SafeFetchLimits.maxBodyBytes)
    }

    @Test func protoBundleRoundTripCodable() throws {
        let bundle = ProtoBundle(
            projectId: UUID(),
            name: "Greeter",
            contentFingerprint: "abc123",
            entryFile: "hello.proto",
            fileCount: 1,
            assetHydrated: true
        )
        let decoded = try JSONDecoder().decode(ProtoBundle.self, from: JSONEncoder().encode(bundle))
        #expect(decoded.name == "Greeter")
        #expect(decoded.contentFingerprint == "abc123")
        #expect(decoded.entryFile == "hello.proto")
        #expect(decoded.schemaVersion == CloudSyncableSchema.currentVersion)
    }

    @Test func isReadOnlyDueToMissingAssetWhenNotHydrated() {
        let bundle = ProtoBundle(
            projectId: UUID(),
            name: "Greeter",
            contentFingerprint: "abc",
            entryFile: "hello.proto",
            fileCount: 1,
            assetHydrated: false
        )
        #expect(bundle.isReadOnlyDueToMissingAsset)
    }

    @Test @MainActor func importProtoBundleWritesDiskAndZip() async throws {
        guard let fixtureRoot = Self.fixtureRootPath() else {
            Issue.record("hello.proto fixture not found")
            return
        }

        try await withTempProtosRoot { _ in
            let compiled = try await GrpcService.compileBundle(rootPath: fixtureRoot, entryFiles: ["hello.proto"])
            let projectId = UUID()
            let store = ProjectStore.mock()

            let bundle = try store.importProtoBundle(
                projectId: projectId,
                name: "Greeter",
                protoSourceDirectory: URL(fileURLWithPath: fixtureRoot, isDirectory: true),
                entryFile: "hello.proto",
                compiled: compiled
            )

            #expect(store.protoBundles.count == 1)
            #expect(bundle.assetHydrated)
            #expect(bundle.contentFingerprint == compiled.contentFingerprint)
            #expect(bundle.hasLocalProtoBytes())

            let zipURL = bundle.resolvedUploadAssetURL()
            #expect(FileManager.default.fileExists(atPath: zipURL.path))
            let zipSize = try FileManager.default.attributesOfItem(atPath: zipURL.path)[.size] as? Int ?? 0
            #expect(zipSize <= ProtoBundle.maxBundleBytes)
        }
    }

    @Test @MainActor func saveBundleFromReflectionWritesDescriptorsOnly() throws {
        try withTempProtosRoot { _ in
            let projectId = UUID()
            let store = ProjectStore.mock()
            let descriptorBytes = Data([0x0A, 0x03, 0x66, 0x6F, 0x6F])

            let bundle = try store.saveBundleFromReflection(
                projectId: projectId,
                name: "Reflection",
                descriptorBytes: descriptorBytes,
                contentFingerprint: "deadbeef"
            )

            #expect(bundle.fileCount == 0)
            #expect(bundle.entryFile == "reflection")
            let loaded = ProtoBundle.loadDescriptorBytes(projectId: projectId, bundleId: bundle.id)
            #expect(loaded == descriptorBytes)
        }
    }

    @Test @MainActor func deleteProtoBundleRemovesDiskAndMetadata() async throws {
        guard let fixtureRoot = Self.fixtureRootPath() else {
            Issue.record("hello.proto fixture not found")
            return
        }

        try await withTempProtosRoot { _ in
            let compiled = try await GrpcService.compileBundle(rootPath: fixtureRoot, entryFiles: ["hello.proto"])
            let store = ProjectStore.mock()
            let projectId = UUID()
            let bundle = try store.importProtoBundle(
                projectId: projectId,
                name: "Greeter",
                protoSourceDirectory: URL(fileURLWithPath: fixtureRoot, isDirectory: true),
                entryFile: "hello.proto",
                compiled: compiled
            )

            store.deleteProtoBundle(id: bundle.id)
            #expect(store.protoBundles.isEmpty)
            #expect(store.isGrpcProtoReady(protoBundleId: bundle.id) == false)
            #expect(!FileManager.default.fileExists(atPath: bundle.resolvedUploadAssetURL().path))
        }
    }

    @Test @MainActor func isGrpcProtoReadyRequiresHydratedBundle() throws {
        let projectId = UUID()
        let bundleId = UUID()
        let bundle = ProtoBundle(
            id: bundleId,
            projectId: projectId,
            name: "Remote",
            contentFingerprint: "fp",
            entryFile: "hello.proto",
            fileCount: 1,
            assetHydrated: false
        )
        let store = ProjectStore.mock(protoBundles: [bundle])
        #expect(store.isGrpcProtoReady(protoBundleId: bundleId) == false)
    }

    private func withTempProtosRoot(
        _ body: @escaping @MainActor (URL) throws -> Void
    ) throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("proto-bundle-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        try ProtoBundleService.$protosRootDirectoryOverride.withValue(tempRoot) {
            try body(tempRoot)
        }
    }

    private func withTempProtosRoot(
        _ body: @escaping @MainActor (URL) async throws -> Void
    ) async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("proto-bundle-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        try await ProtoBundleService.$protosRootDirectoryOverride.withValue(tempRoot) {
            try await body(tempRoot)
        }
    }

    private static func fixtureRootPath() -> String? {
        let relative = "rust/tests/fixtures/grpc"
        if let srcRoot = ProcessInfo.processInfo.environment["SRCROOT"] {
            let path = (srcRoot as NSString).appendingPathComponent(relative)
            if FileManager.default.fileExists(atPath: path) { return path }
        }

        let cwd = FileManager.default.currentDirectoryPath
        let fromCwd = (cwd as NSString).appendingPathComponent(relative)
        if FileManager.default.fileExists(atPath: fromCwd) { return fromCwd }

        var url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<6 {
            url.deleteLastPathComponent()
            let candidate = url.appendingPathComponent(relative)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate.path
            }
        }
        return nil
    }
}