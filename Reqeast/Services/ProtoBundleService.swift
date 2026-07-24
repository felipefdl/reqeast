//
//  ProtoBundleService.swift
//  Reqeast
//

import Foundation
import os

private let protoBundleLogger = Logger(subsystem: "app.reqeast", category: "ProtoBundle")

enum ProtoBundleError: Error, Equatable {
    case bundleTooLarge(byteCount: Int)
    case missingDescriptorBytes
    case zipFailed(String)
    case diskWriteFailed
}

enum ProtoBundleService {

    #if DEBUG
    /// Task-local protos root for isolated unit tests. Prefer over a process-global
    /// override so parallel Swift Testing suites cannot clobber each other's disk paths.
    @TaskLocal static var protosRootDirectoryOverride: URL?
    #endif

    static func protosRootDirectory() -> URL {
        #if DEBUG
        if let override = protosRootDirectoryOverride {
            return override
        }
        #endif

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return appSupport
            .appendingPathComponent("reqeast", isDirectory: true)
            .appendingPathComponent(StorageEnvironment.protoDirName, isDirectory: true)
    }

    static func bundleDirectory(projectId: UUID, bundleId: UUID) -> URL {
        protosRootDirectory()
            .appendingPathComponent(projectId.uuidString, isDirectory: true)
            .appendingPathComponent(bundleId.uuidString, isDirectory: true)
    }

    static func loadDescriptorBytes(projectId: UUID, bundleId: UUID) -> Data? {
        let url = bundleDirectory(projectId: projectId, bundleId: bundleId)
            .appendingPathComponent(ProtoBundle.descriptorsFileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try? Data(contentsOf: url)
    }

    static func hasLocalProtoBytes(projectId: UUID, bundleId: UUID) -> Bool {
        loadDescriptorBytes(projectId: projectId, bundleId: bundleId) != nil
    }

    @discardableResult
    static func packBundleZip(bundleDirectory: URL) throws -> URL {
        let zipURL = bundleDirectory.appendingPathComponent(ProtoBundle.uploadZipFileName)
        try ProtoZipArchive.packDirectory(
            bundleDirectory,
            to: zipURL,
            excluding: [ProtoBundle.uploadZipFileName]
        )
        let byteCount = try FileManager.default.attributesOfItem(atPath: zipURL.path)[.size] as? Int ?? 0
        guard byteCount <= ProtoBundle.maxBundleBytes else {
            throw ProtoBundleError.bundleTooLarge(byteCount: byteCount)
        }
        return zipURL
    }

    static func extractBundleZip(assetURL: URL, bundleDirectory: URL) throws {
        try FileManager.default.createDirectory(at: bundleDirectory, withIntermediateDirectories: true)
        try ProtoZipArchive.extract(zipURL: assetURL, to: bundleDirectory)
    }

    static func deleteBundleDirectory(projectId: UUID, bundleId: UUID) {
        let directory = bundleDirectory(projectId: projectId, bundleId: bundleId)
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        do {
            try FileManager.default.removeItem(at: directory)
        } catch {
            protoBundleLogger.error("Failed to delete proto bundle directory \(bundleId): \(error)")
        }
    }

    static func writeBundleContents(
        bundleDirectory: URL,
        protoSourceDirectory: URL?,
        descriptorBytes: Data,
        fingerprint: String
    ) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: bundleDirectory.path) {
            try fileManager.removeItem(at: bundleDirectory)
        }
        try fileManager.createDirectory(at: bundleDirectory, withIntermediateDirectories: true)

        if let protoSourceDirectory {
            try copyProtoTree(from: protoSourceDirectory, to: bundleDirectory)
        }

        try descriptorBytes.write(
            to: bundleDirectory.appendingPathComponent(ProtoBundle.descriptorsFileName),
            options: .atomic
        )
        try fingerprint.write(
            to: bundleDirectory.appendingPathComponent(ProtoBundle.fingerprintFileName),
            atomically: true,
            encoding: .utf8
        )
        _ = try packBundleZip(bundleDirectory: bundleDirectory)
    }

    static func countProtoFiles(in directory: URL) -> Int {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var count = 0
        for case let fileURL as URL in enumerator {
            guard (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                continue
            }
            let name = fileURL.lastPathComponent
            if name == ProtoBundle.descriptorsFileName
                || name == ProtoBundle.fingerprintFileName
                || name == ProtoBundle.uploadZipFileName {
                continue
            }
            if fileURL.pathExtension == "proto" {
                count += 1
            }
        }
        return count
    }

    private static func copyProtoTree(from source: URL, to destination: URL) throws {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: source,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw ProtoBundleError.diskWriteFailed
        }

        let prefix = source.path.hasSuffix("/") ? source.path : source.path + "/"
        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            let relativePath = String(fileURL.path.dropFirst(prefix.count))
            let target = destination.appendingPathComponent(relativePath)
            let parent = target.deletingLastPathComponent()
            if !fileManager.fileExists(atPath: parent.path) {
                try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
            }
            if fileManager.fileExists(atPath: target.path) {
                try fileManager.removeItem(at: target)
            }
            try fileManager.copyItem(at: fileURL, to: target)
        }
    }
}