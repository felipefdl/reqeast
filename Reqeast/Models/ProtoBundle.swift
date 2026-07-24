//
//  ProtoBundle.swift
//  Reqeast
//

import Foundation

/// Project-level gRPC proto library synced via iCloud (zip CKAsset). One bundle per import/reflection save.
struct ProtoBundle: Codable, Identifiable, Hashable {
    static let ckAssetField = "protoAsset"
    static let fingerprintField = "contentFingerprint"
    static let maxBundleBytes = SafeFetchLimits.maxBodyBytes
    static let descriptorsFileName = "descriptors.bin"
    static let fingerprintFileName = "fingerprint.txt"
    static let uploadZipFileName = "bundle.zip"

    var id: UUID
    var projectId: UUID
    var name: String
    var contentFingerprint: String
    /// Fingerprint last confirmed uploaded to CloudKit; used to skip redundant CKAsset uploads.
    var lastUploadedFingerprint: String?
    /// Root `.proto` file within the bundle (or reflection placeholder name).
    var entryFile: String
    var fileCount: Int
    /// False when the device lacks on-disk proto bytes and no CKAsset was hydrated.
    var assetHydrated: Bool
    var updatedAt: Date
    var deletedAt: Date?
    var schemaVersion: Int = CloudSyncableSchema.currentVersion

    init(
        id: UUID = UUID(),
        projectId: UUID,
        name: String,
        contentFingerprint: String,
        lastUploadedFingerprint: String? = nil,
        entryFile: String,
        fileCount: Int,
        assetHydrated: Bool = true,
        updatedAt: Date = Date(),
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.projectId = projectId
        self.name = name
        self.contentFingerprint = contentFingerprint
        self.lastUploadedFingerprint = lastUploadedFingerprint
        self.entryFile = entryFile
        self.fileCount = fileCount
        self.assetHydrated = assetHydrated
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        projectId = try container.decode(UUID.self, forKey: .projectId)
        name = try container.decode(String.self, forKey: .name)
        contentFingerprint = try container.decode(String.self, forKey: .contentFingerprint)
        lastUploadedFingerprint = try container.decodeIfPresent(String.self, forKey: .lastUploadedFingerprint)
        entryFile = try container.decode(String.self, forKey: .entryFile)
        fileCount = try container.decodeIfPresent(Int.self, forKey: .fileCount) ?? 0
        assetHydrated = try container.decodeIfPresent(Bool.self, forKey: .assetHydrated) ?? true
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .distantPast
        deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
        schemaVersion = try CloudSyncableSchema.decodeVersion(from: container, forKey: .schemaVersion)
    }

    /// gRPC is read-only when descriptor bytes are missing and cannot be hydrated yet.
    var isReadOnlyDueToMissingAsset: Bool {
        !assetHydrated
    }

    static func hasLocalProtoBytes(projectId: UUID, bundleId: UUID) -> Bool {
        loadDescriptorBytes(projectId: projectId, bundleId: bundleId) != nil
    }

    static func loadDescriptorBytes(projectId: UUID, bundleId: UUID) -> Data? {
        ProtoBundleService.loadDescriptorBytes(projectId: projectId, bundleId: bundleId)
    }

    static func localBundleDirectoryURL(projectId: UUID, bundleId: UUID) -> URL {
        ProtoBundleService.bundleDirectory(projectId: projectId, bundleId: bundleId)
    }

    func resolvedUploadAssetURL() -> URL {
        Self.localBundleDirectoryURL(projectId: projectId, bundleId: id)
            .appendingPathComponent(Self.uploadZipFileName)
    }

    func hasLocalProtoBytes() -> Bool {
        Self.hasLocalProtoBytes(projectId: projectId, bundleId: id)
    }
}