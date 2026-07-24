//
//  CloudSyncable.swift
//  Reqeast
//

import Foundation

/// Version of the JSON blob format for iCloud-synced records. Bump only on breaking changes.
/// Older clients reject blobs with a `schemaVersion` higher than `currentVersion` (see
/// `decodeVersion(from:forKey:)`) so they cannot round-trip and truncate unknown fields on upload.
enum CloudSyncableSchema {
    static let currentVersion: Int = 1

    /// Blobs written before the field existed decode as version 1, the first format. This must
    /// stay pinned to 1 when `currentVersion` is bumped, or legacy blobs would be misread as
    /// the newest format and skip future migrations.
    static let legacyVersion: Int = 1

    /// Decodes the `schemaVersion` field with a validity guard. Missing field defaults to
    /// `legacyVersion` for backward compatibility with pre-versioning blobs. Versions greater
    /// than `currentVersion` throw `DecodingError.dataCorruptedError`, preventing the caller
    /// from re-encoding a truncated payload and uploading it as the new newest copy. Versions
    /// below `legacyVersion` (zero, negative) are corrupt data and are rejected the same way.
    static func decodeVersion<K: CodingKey>(
        from container: KeyedDecodingContainer<K>,
        forKey key: K
    ) throws -> Int {
        let version = try container.decodeIfPresent(Int.self, forKey: key) ?? legacyVersion
        guard version >= legacyVersion, version <= currentVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: container,
                debugDescription: "schemaVersion \(version) is outside the supported range (\(legacyVersion)...\(currentVersion))"
            )
        }
        return version
    }
}

/// Maps CloudKit record type strings to Swift types for compile-time exhaustiveness.
enum SyncRecordType: String, CaseIterable {
    case project = "Project"
    case projectFolder = "ProjectFolder"
    case request = "Request"
    case requestFolder = "RequestFolder"
    case apiEnvironment = "ApiEnvironment"
    case specDocument = "SpecDocument"
    case protoBundle = "ProtoBundle"
}

/// Types that can be synced via CKSyncEngine as JSON-encoded CKRecord payloads.
/// Each record stores the full Codable encoding in a `data` field, with `updatedAt`
/// used for last-writer-wins conflict resolution.
protocol CloudSyncable: Codable, Identifiable where ID == UUID {
    var updatedAt: Date { get set }
    var deletedAt: Date? { get set }
    static var syncRecordType: SyncRecordType { get }
}

extension CloudSyncable {
    /// Stamps `updatedAt` to now. Call immediately before `queueSave` so last-writer-wins
    /// conflict resolution treats this copy as the newest. Skipping `touch()` undermines LWW:
    /// a concurrent remote change with a newer timestamp will silently win the conflict.
    mutating func touch() {
        self.updatedAt = Date()
    }

    /// Marks the item as soft-deleted with the same timestamp applied to `updatedAt` and
    /// `deletedAt` so conflict resolution treats the tombstone as the latest edit.
    mutating func tombstone() {
        let now = Date()
        self.updatedAt = now
        self.deletedAt = now
    }
}

extension Project: CloudSyncable {
    static var syncRecordType: SyncRecordType { .project }
}

extension ProjectFolder: CloudSyncable {
    static var syncRecordType: SyncRecordType { .projectFolder }
}

extension Request: CloudSyncable {
    static var syncRecordType: SyncRecordType { .request }
}

extension RequestFolder: CloudSyncable {
    static var syncRecordType: SyncRecordType { .requestFolder }
}

extension ApiEnvironment: CloudSyncable {
    static var syncRecordType: SyncRecordType { .apiEnvironment }
}

extension SpecDocument: CloudSyncable {
    static var syncRecordType: SyncRecordType { .specDocument }
}

extension ProtoBundle: CloudSyncable {
    static var syncRecordType: SyncRecordType { .protoBundle }
}
