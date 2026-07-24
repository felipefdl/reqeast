//
//  SpecLink.swift
//  Reqeast
//

import Foundation

enum SpecFormat: String, Codable, Hashable {
    case openapi
    case postman
    case insomnia
    case bruno
    case graphql
    case har
    case asyncApi
}

enum SpecSource: String, Codable, Hashable {
    case file
    case url
    case paste
    case gitHTTPS
    case gitProvider
    case localBookmark
}

struct SpecLink: Codable, Hashable {
    var format: SpecFormat
    var source: SpecSource
    var sourceURL: String?
    var gitRef: GitSourceRef?
    var contentFingerprint: String
    var specRevision: Int
    var importedAt: Date
    var lastCheckedAt: Date?
    var lastSyncedAt: Date?
    var isDetached: Bool
    /// Per-project opt-in for scheduled background fingerprint checks (AC28).
    var backgroundCheckEnabled: Bool

    /// Live sources the spec panel can fetch for fingerprint comparison.
    var isEligibleForRemoteCheck: Bool {
        switch source {
        case .url:
            return sourceURL != nil
        case .gitHTTPS, .gitProvider:
            return gitRef != nil
        case .localBookmark:
            return true
        case .file, .paste:
            return false
        }
    }

    /// Linked live sources that the background scheduler may poll when opted in.
    var isEligibleForBackgroundCheck: Bool {
        guard !isDetached else { return false }
        return isEligibleForRemoteCheck
    }

    init(
        format: SpecFormat,
        source: SpecSource,
        contentFingerprint: String,
        importedAt: Date,
        sourceURL: String? = nil,
        gitRef: GitSourceRef? = nil,
        specRevision: Int = 0,
        lastCheckedAt: Date? = nil,
        lastSyncedAt: Date? = nil,
        isDetached: Bool = true,
        backgroundCheckEnabled: Bool = false
    ) {
        self.format = format
        self.source = source
        self.sourceURL = sourceURL
        self.gitRef = gitRef
        self.contentFingerprint = contentFingerprint
        self.specRevision = specRevision
        self.importedAt = importedAt
        self.lastCheckedAt = lastCheckedAt
        self.lastSyncedAt = lastSyncedAt
        self.isDetached = isDetached
        self.backgroundCheckEnabled = backgroundCheckEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        format = try container.decode(SpecFormat.self, forKey: .format)
        source = try container.decode(SpecSource.self, forKey: .source)
        sourceURL = try container.decodeIfPresent(String.self, forKey: .sourceURL)
        gitRef = try container.decodeIfPresent(GitSourceRef.self, forKey: .gitRef)
        contentFingerprint = try container.decode(String.self, forKey: .contentFingerprint)
        specRevision = try container.decodeIfPresent(Int.self, forKey: .specRevision) ?? 0
        importedAt = try container.decode(Date.self, forKey: .importedAt)
        lastCheckedAt = try container.decodeIfPresent(Date.self, forKey: .lastCheckedAt)
        lastSyncedAt = try container.decodeIfPresent(Date.self, forKey: .lastSyncedAt)
        isDetached = try container.decodeIfPresent(Bool.self, forKey: .isDetached) ?? true
        backgroundCheckEnabled = try container.decodeIfPresent(Bool.self, forKey: .backgroundCheckEnabled) ?? false
    }
}