//
//  SpecDocument.swift
//  Reqeast
//

import Foundation

/// Controls whether raw spec bytes are synced via CKAsset and how `sourceURL` is encoded.
enum SpecClassification: String, Codable, Hashable {
    /// Linked spec bytes may sync via CKAsset; `sourceURL` is included in synced metadata.
    case standard
    /// Skips CKAsset upload and redacts `sourceURL` in synced metadata (internal specs).
    case `internal`
}

/// CloudKit record for linked spec file bytes (P3). One per linked project; `id` matches `projectId`.
struct SpecDocument: Codable, Identifiable, Hashable {
    static let ckAssetField = "specAsset"
    static let fingerprintField = "contentFingerprint"
    static let maxSpecBytes = SafeFetchLimits.maxBodyBytes

    var id: UUID
    var projectId: UUID
    var contentFingerprint: String
    /// Fingerprint last confirmed uploaded to CloudKit; used to skip redundant CKAsset uploads.
    var lastUploadedFingerprint: String?
    var specFileName: String
    var sourceURL: String?
    var classification: SpecClassification
    var isDetached: Bool
    /// False when the device lacks on-disk spec bytes and no CKAsset was hydrated.
    var assetHydrated: Bool
    var updatedAt: Date
    var deletedAt: Date?
    var schemaVersion: Int = CloudSyncableSchema.currentVersion

    init(
        id: UUID,
        projectId: UUID,
        contentFingerprint: String,
        specFileName: String,
        lastUploadedFingerprint: String? = nil,
        sourceURL: String? = nil,
        classification: SpecClassification = .standard,
        isDetached: Bool = false,
        assetHydrated: Bool = true,
        updatedAt: Date = Date(),
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.projectId = projectId
        self.contentFingerprint = contentFingerprint
        self.lastUploadedFingerprint = lastUploadedFingerprint
        self.specFileName = specFileName
        self.sourceURL = sourceURL
        self.classification = classification
        self.isDetached = isDetached
        self.assetHydrated = assetHydrated
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        projectId = try container.decode(UUID.self, forKey: .projectId)
        contentFingerprint = try container.decode(String.self, forKey: .contentFingerprint)
        lastUploadedFingerprint = try container.decodeIfPresent(String.self, forKey: .lastUploadedFingerprint)
        specFileName = try container.decode(String.self, forKey: .specFileName)
        sourceURL = try container.decodeIfPresent(String.self, forKey: .sourceURL)
        classification = try container.decodeIfPresent(SpecClassification.self, forKey: .classification) ?? .standard
        isDetached = try container.decodeIfPresent(Bool.self, forKey: .isDetached) ?? false
        assetHydrated = try container.decodeIfPresent(Bool.self, forKey: .assetHydrated) ?? true
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .distantPast
        deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
        schemaVersion = try CloudSyncableSchema.decodeVersion(from: container, forKey: .schemaVersion)
    }

    /// Whether this project should attempt CKAsset upload on sync.
    var uploadsAsset: Bool {
        !isDetached && classification != .internal
    }

    /// Linked project is read-only when spec bytes are missing and cannot be hydrated yet.
    var isReadOnlyDueToMissingAsset: Bool {
        uploadsAsset && !assetHydrated
    }

    /// Payload encoded into the CKRecord `data` field. Internal specs never sync `sourceURL`.
    func syncedRepresentation() -> SpecDocument {
        guard classification == .internal else { return self }
        var copy = self
        copy.sourceURL = nil
        return copy
    }

    static func from(
        project: Project,
        specFileName: String,
        classification: SpecClassification = .standard
    ) -> SpecDocument? {
        guard let specLink = project.specLink else { return nil }
        return SpecDocument(
            id: project.id,
            projectId: project.id,
            contentFingerprint: specLink.contentFingerprint,
            specFileName: specFileName,
            sourceURL: specLink.sourceURL,
            classification: classification,
            isDetached: specLink.isDetached,
            assetHydrated: hasLocalSpecBytes(projectId: project.id)
        )
    }

    static func hasLocalSpecBytes(projectId: UUID) -> Bool {
        localSpecFileURL(projectId: projectId) != nil
    }

    static func localSpecFileURL(projectId: UUID, preferredFileName: String? = nil) -> URL? {
        let directory = SpecImportService.specsDirectory(for: projectId)
        if let preferredFileName {
            let preferred = directory.appendingPathComponent(preferredFileName)
            if FileManager.default.fileExists(atPath: preferred.path) {
                return preferred
            }
        }

        let bundleDirectory = directory.appendingPathComponent("bundle", isDirectory: true)
        if FileManager.default.fileExists(atPath: bundleDirectory.path),
           let entryURL = SpecImportHelpers.findBundleEntry(in: bundleDirectory) {
            return entryURL
        }

        for fileName in ["spec.yaml", "spec.json"] {
            let fileURL = directory.appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                return fileURL
            }
        }
        return nil
    }

    func resolvedLocalSpecFileURL() -> URL? {
        Self.localSpecFileURL(projectId: projectId, preferredFileName: specFileName)
    }
}