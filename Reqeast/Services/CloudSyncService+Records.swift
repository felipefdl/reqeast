//
//  CloudSyncService+Records.swift
//  Reqeast
//

import CloudKit
import Foundation
import os

private let logger = Logger(subsystem: "app.reqeast", category: "CloudSync.Records")

/// Outcome of a last-writer-wins conflict comparison between a local and server record.
/// `.undecidable` fires when either side is missing the `updatedAt` field or its payload fails to decode;
/// callers should surface the reason and default to server wins rather than silently picking a winner.
enum ConflictOutcome: Equatable {
    case localNewer
    case serverNewer
    case undecidable(reason: String)
}

extension CloudSyncService {

    /// CloudKit's per-record limit is 1 MB; 900 KB leaves headroom for the `updatedAt` field
    /// and CKRecord system metadata, so a payload passing this check cannot be rejected
    /// server-side for size.
    static let maxRecordPayloadBytes = 900_000

    func recordID(for item: some CloudSyncable) -> CKRecord.ID {
        let name = "\(type(of: item).syncRecordType.rawValue)/\(item.id.uuidString)"
        return CKRecord.ID(recordName: name, zoneID: zoneID)
    }

    func buildRecord(for item: some CloudSyncable) -> CKRecord? {
        if let document = item as? SpecDocument {
            return buildSpecDocumentRecord(for: document)
        }
        if let bundle = item as? ProtoBundle {
            return buildProtoBundleRecord(for: bundle)
        }
        return buildJSONRecord(for: item)
    }

    private func buildJSONRecord(for item: some CloudSyncable) -> CKRecord? {
        let id = recordID(for: item)
        let record = cachedRecord(for: id) ?? CKRecord(recordType: type(of: item).syncRecordType.rawValue, recordID: id)

        let jsonData: Data
        do {
            jsonData = try JSONEncoder().encode(item)
        } catch {
            logger.fault("Failed to encode \(type(of: item).syncRecordType.rawValue)/\(item.id.uuidString): \(error)")
            syncEngine?.state.remove(pendingRecordZoneChanges: [.saveRecord(id)])
            syncState.report(RequestError(
                kind: .cloudPermanentFailure,
                message: "\(type(of: item).syncRecordType.rawValue)/\(item.id.uuidString): \(error.localizedDescription)"
            ))
            return nil
        }

        if jsonData.count > Self.maxRecordPayloadBytes {
            let recordName = "\(type(of: item).syncRecordType.rawValue)/\(item.id.uuidString)"
            logger.fault("Record too large for CloudKit: \(recordName) is \(jsonData.count) bytes")
            syncEngine?.state.remove(pendingRecordZoneChanges: [.saveRecord(id)])
            oversizedRecordIDs.insert(id.recordName)
            persistOversizedRecordIDs()
            syncState.report(RequestError(
                kind: .cloudRecordTooLarge,
                message: String(localized: "\(recordName) (\(jsonData.count) bytes) exceeds the 900 KB iCloud record limit. This item will not sync. Reduce the body size or move large content to a file.")
            ))
            return nil
        }

        record["data"] = jsonData as NSData
        record["updatedAt"] = item.updatedAt as NSDate
        return record
    }

    func buildSpecDocumentRecord(for document: SpecDocument) -> CKRecord? {
        let id = recordID(for: document)
        let cached = cachedRecord(for: id)
        let record = cached ?? CKRecord(recordType: SpecDocument.syncRecordType.rawValue, recordID: id)
        let payload = document.syncedRepresentation()

        let jsonData: Data
        do {
            jsonData = try JSONEncoder().encode(payload)
        } catch {
            logger.fault("Failed to encode SpecDocument/\(document.id.uuidString): \(error)")
            syncEngine?.state.remove(pendingRecordZoneChanges: [.saveRecord(id)])
            syncState.report(RequestError(
                kind: .cloudPermanentFailure,
                message: "SpecDocument/\(document.id.uuidString): \(error.localizedDescription)"
            ))
            return nil
        }

        if jsonData.count > Self.maxRecordPayloadBytes {
            let recordName = "SpecDocument/\(document.id.uuidString)"
            logger.fault("Record too large for CloudKit: \(recordName) is \(jsonData.count) bytes")
            syncEngine?.state.remove(pendingRecordZoneChanges: [.saveRecord(id)])
            oversizedRecordIDs.insert(id.recordName)
            persistOversizedRecordIDs()
            syncState.report(RequestError(
                kind: .cloudRecordTooLarge,
                message: String(localized: "\(recordName) (\(jsonData.count) bytes) exceeds the 900 KB iCloud record limit. This item will not sync.")
            ))
            return nil
        }

        record["data"] = jsonData as NSData
        record["updatedAt"] = document.updatedAt as NSDate
        record[SpecDocument.fingerprintField] = document.contentFingerprint as NSString

        if document.uploadsAsset {
            if shouldUploadSpecAsset(for: document) {
                guard let specURL = document.resolvedLocalSpecFileURL() else {
                    logger.fault("SpecDocument/\(document.id.uuidString) missing on-disk spec for upload")
                    syncEngine?.state.remove(pendingRecordZoneChanges: [.saveRecord(id)])
                    syncState.report(RequestError(
                        kind: .cloudPermanentFailure,
                        message: String(localized: "Spec file is missing on disk and cannot be uploaded to iCloud.")
                    ))
                    return nil
                }

                do {
                    let attributes = try FileManager.default.attributesOfItem(atPath: specURL.path)
                    let byteCount = attributes[.size] as? Int ?? 0
                    guard byteCount <= SpecDocument.maxSpecBytes else {
                        logger.fault("SpecDocument/\(document.id.uuidString) exceeds 5 MiB upload cap (\(byteCount) bytes)")
                        syncEngine?.state.remove(pendingRecordZoneChanges: [.saveRecord(id)])
                        syncState.report(RequestError(
                            kind: .cloudRecordTooLarge,
                            message: String(localized: "Spec file exceeds the 5 MiB iCloud asset limit and will not sync.")
                        ))
                        return nil
                    }
                } catch {
                    logger.fault("SpecDocument/\(document.id.uuidString) failed spec size check: \(error)")
                    syncEngine?.state.remove(pendingRecordZoneChanges: [.saveRecord(id)])
                    return nil
                }

                record[SpecDocument.ckAssetField] = CKAsset(fileURL: specURL)
            }
        } else {
            record[SpecDocument.ckAssetField] = nil
        }

        return record
    }

    /// Uploads CKAsset only when the fingerprint changed since the last confirmed upload.
    func shouldUploadSpecAsset(for document: SpecDocument) -> Bool {
        document.lastUploadedFingerprint != document.contentFingerprint
    }

    func buildProtoBundleRecord(for bundle: ProtoBundle) -> CKRecord? {
        let id = recordID(for: bundle)
        let record = cachedRecord(for: id) ?? CKRecord(recordType: ProtoBundle.syncRecordType.rawValue, recordID: id)

        let jsonData: Data
        do {
            jsonData = try JSONEncoder().encode(bundle)
        } catch {
            logger.fault("Failed to encode ProtoBundle/\(bundle.id.uuidString): \(error)")
            syncEngine?.state.remove(pendingRecordZoneChanges: [.saveRecord(id)])
            syncState.report(RequestError(
                kind: .cloudPermanentFailure,
                message: "ProtoBundle/\(bundle.id.uuidString): \(error.localizedDescription)"
            ))
            return nil
        }

        if jsonData.count > Self.maxRecordPayloadBytes {
            let recordName = "ProtoBundle/\(bundle.id.uuidString)"
            logger.fault("Record too large for CloudKit: \(recordName) is \(jsonData.count) bytes")
            syncEngine?.state.remove(pendingRecordZoneChanges: [.saveRecord(id)])
            oversizedRecordIDs.insert(id.recordName)
            persistOversizedRecordIDs()
            syncState.report(RequestError(
                kind: .cloudRecordTooLarge,
                message: String(localized: "\(recordName) (\(jsonData.count) bytes) exceeds the 900 KB iCloud record limit. This item will not sync.")
            ))
            return nil
        }

        record["data"] = jsonData as NSData
        record["updatedAt"] = bundle.updatedAt as NSDate
        record[ProtoBundle.fingerprintField] = bundle.contentFingerprint as NSString

        if shouldUploadProtoAsset(for: bundle) {
            let zipURL = bundle.resolvedUploadAssetURL()
            guard FileManager.default.fileExists(atPath: zipURL.path) else {
                logger.fault("ProtoBundle/\(bundle.id.uuidString) missing on-disk bundle.zip for upload")
                syncEngine?.state.remove(pendingRecordZoneChanges: [.saveRecord(id)])
                syncState.report(RequestError(
                    kind: .cloudPermanentFailure,
                    message: String(localized: "Proto bundle is missing on disk and cannot be uploaded to iCloud.")
                ))
                return nil
            }

            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: zipURL.path)
                let byteCount = attributes[.size] as? Int ?? 0
                guard byteCount <= ProtoBundle.maxBundleBytes else {
                    logger.fault("ProtoBundle/\(bundle.id.uuidString) exceeds 5 MiB upload cap (\(byteCount) bytes)")
                    syncEngine?.state.remove(pendingRecordZoneChanges: [.saveRecord(id)])
                    syncState.report(RequestError(
                        kind: .cloudRecordTooLarge,
                        message: String(localized: "Proto bundle exceeds the 5 MiB iCloud asset limit and will not sync.")
                    ))
                    return nil
                }
            } catch {
                logger.fault("ProtoBundle/\(bundle.id.uuidString) failed bundle size check: \(error)")
                syncEngine?.state.remove(pendingRecordZoneChanges: [.saveRecord(id)])
                return nil
            }

            record[ProtoBundle.ckAssetField] = CKAsset(fileURL: zipURL)
        }

        return record
    }

    /// Uploads CKAsset only when the fingerprint changed since the last confirmed upload.
    func shouldUploadProtoAsset(for bundle: ProtoBundle) -> Bool {
        bundle.lastUploadedFingerprint != bundle.contentFingerprint
    }

    func decodeRecord<T: CloudSyncable>(_ record: CKRecord, as type: T.Type) -> T? {
        guard let data = record["data"] as? Data else {
            logger.error("No data field in record \(record.recordID.recordName)")
            return nil
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            logger.error("Failed to decode \(record.recordID.recordName): \(error)")
            return nil
        }
    }

    func parseRecordName(_ name: String) -> (type: SyncRecordType, id: UUID)? {
        let parts = name.split(separator: "/", maxSplits: 1)
        guard parts.count == 2,
              let type = SyncRecordType(rawValue: String(parts[0])),
              let id = UUID(uuidString: String(parts[1])) else {
            logger.warning("Failed to parse record name: \(name)")
            return nil
        }
        return (type: type, id: id)
    }

    func cachedRecord(for recordID: CKRecord.ID) -> CKRecord? {
        let recordName = recordID.recordName
        if lastKnownRecordData[recordName] == nil,
           let diskData = CloudSyncLastKnownRecordStore.load(recordName: recordName) {
            lastKnownRecordData[recordName] = diskData
        }
        guard let data = lastKnownRecordData[recordName] else { return nil }
        let unarchiver: NSKeyedUnarchiver
        do {
            unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
        } catch {
            logger.fault("Failed to unarchive cached record \(recordID.recordName), clearing cache: \(error)")
            dropCachedRecord(recordName: recordID.recordName)
            return nil
        }
        unarchiver.requiresSecureCoding = true
        let record = CKRecord(coder: unarchiver)
        unarchiver.finishDecoding()
        if let decodeError = unarchiver.error ?? (record == nil ? NSError(domain: "Reqeast.CloudSync", code: -1) : nil) {
            logger.fault("Invalid cached record \(recordID.recordName), clearing cache: \(decodeError)")
            dropCachedRecord(recordName: recordID.recordName)
            return nil
        }
        return record
    }

    func cacheSystemFields(of record: CKRecord) {
        let recordName = record.recordID.recordName
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: archiver)
        archiver.finishEncoding()
        let data = archiver.encodedData
        lastKnownRecordData[recordName] = data
        do {
            try CloudSyncLastKnownRecordStore.save(recordName: recordName, data: data)
            confirmedRecordNames.insert(recordName)
        } catch {
            logger.fault("Failed to persist last-known record \(recordName): \(error)")
        }
    }

    /// Field-based last-writer-wins comparison. Reads `updatedAt` from each record's top-level
    /// field (set by `buildRecord`), avoiding JSON-decoding the full blob. Ties go to the server
    /// to prevent ping-pong when clocks align.
    static func localIsNewer(localRecord: CKRecord, serverRecord: CKRecord) -> ConflictOutcome {
        let local = localRecord["updatedAt"] as? Date
        let server = serverRecord["updatedAt"] as? Date
        if let local, let server {
            return local > server ? .localNewer : .serverNewer
        }
        let missing: String
        switch (local, server) {
        case (nil, nil): missing = String(localized: "Both records are missing the updatedAt field.")
        case (nil, _):   missing = String(localized: "Local record is missing the updatedAt field.")
        default:         missing = String(localized: "Server record is missing the updatedAt field.")
        }
        return .undecidable(reason: missing)
    }

    /// Last-writer-wins comparison on JSON-encoded `updatedAt` timestamps.
    /// Ties go to the server (strict `>` favors local only when strictly newer) to avoid
    /// infinite ping-pong when clocks are equal across devices. See `ProjectStore+RemoteSync.applyRemoteUpsert`
    /// which uses `>=` from the opposite direction — both rules reduce to "server wins a tie".
    static func localIsNewer(localData: Data, serverData: Data) -> ConflictOutcome {
        struct TimestampOnly: Decodable {
            let updatedAt: Date
        }

        var localTimestamp: Date?
        var serverTimestamp: Date?
        var failureReason: String?

        do {
            localTimestamp = try JSONDecoder().decode(TimestampOnly.self, from: localData).updatedAt
        } catch {
            logger.fault("Conflict: failed to decode local updatedAt: \(error)")
            failureReason = String(localized: "Local record payload could not be decoded.")
        }

        do {
            serverTimestamp = try JSONDecoder().decode(TimestampOnly.self, from: serverData).updatedAt
        } catch {
            logger.fault("Conflict: failed to decode server updatedAt: \(error)")
            let serverMessage = String(localized: "Server record payload could not be decoded.")
            failureReason = failureReason.map { "\($0) \(serverMessage)" } ?? serverMessage
        }

        if let local = localTimestamp, let server = serverTimestamp {
            return local > server ? .localNewer : .serverNewer
        }
        return .undecidable(reason: failureReason ?? String(localized: "Missing timestamp data."))
    }

    /// Returns the conflict outcome for a pending local save vs an incoming server record.
    /// Prefers the top-level `updatedAt` field; falls back to JSON-decoding the blob when either
    /// side lacks the field (legacy records). If the server record is malformed (no `data` blob)
    /// and the local side has one, local wins to prevent a broken server record from overwriting
    /// the user's edits. Caller policy for `.undecidable`: surface to user and default to server.
    func resolveConflict(localRecord: CKRecord, serverRecord: CKRecord) -> ConflictOutcome {
        let fieldOutcome = Self.localIsNewer(localRecord: localRecord, serverRecord: serverRecord)
        if case .undecidable = fieldOutcome {
            let localData = localRecord["data"] as? Data
            let serverData = serverRecord["data"] as? Data
            if serverData == nil, localData != nil {
                let name = serverRecord.recordID.recordName
                logger.fault("Conflict: server record \(name) has no data blob; local wins")
                syncState.report(RequestError(
                    kind: .cloudConflictUnresolvable,
                    message: String(localized: "\(name): server record is missing its data payload. Local edits were preserved.")
                ))
                return .localNewer
            }
            guard let localData, let serverData else { return fieldOutcome }
            return Self.localIsNewer(localData: localData, serverData: serverData)
        }
        return fieldOutcome
    }

    /// Decodes a CKRecord and applies it as a remote upsert. Returns true on success.
    @discardableResult
    func decodeAndApplyUpsert(record: CKRecord, type: SyncRecordType, store: ProjectStore) -> Bool {
        switch type {
        case .project:
            if let item: Project = decodeRecord(record, as: Project.self) {
                store.applyRemoteUpsert(item)
                return true
            }
        case .projectFolder:
            if let item = decodeRecord(record, as: ProjectFolder.self) {
                store.applyRemoteUpsert(item)
                return true
            }
        case .request:
            if let item = decodeRecord(record, as: Request.self) {
                store.applyRemoteUpsert(item)
                return true
            }
        case .requestFolder:
            if let item = decodeRecord(record, as: RequestFolder.self) {
                store.applyRemoteUpsert(item)
                return true
            }
        case .apiEnvironment:
            if let item = decodeRecord(record, as: ApiEnvironment.self) {
                store.applyRemoteUpsert(item)
                return true
            }
        case .specDocument:
            return applySpecDocumentUpsert(record: record, store: store)
        case .protoBundle:
            return applyProtoBundleUpsert(record: record, store: store)
        }
        return false
    }

    @discardableResult
    func applySpecDocumentUpsert(record: CKRecord, store: ProjectStore) -> Bool {
        guard var document = decodeRecord(record, as: SpecDocument.self) else {
            return false
        }

        if let asset = record[SpecDocument.ckAssetField] as? CKAsset,
           let assetURL = asset.fileURL {
            do {
                try writeSpecAssetToDisk(assetURL: assetURL, document: document)
                document.assetHydrated = true
            } catch {
                logger.fault("Failed to write SpecDocument asset for \(document.projectId): \(error)")
                document.assetHydrated = SpecDocument.hasLocalSpecBytes(projectId: document.projectId)
                syncState.report(RequestError(
                    kind: .cloudDecodeError,
                    message: String(localized: "Could not save the synced spec file to disk.")
                ))
            }
        } else if document.uploadsAsset {
            document.assetHydrated = SpecDocument.hasLocalSpecBytes(projectId: document.projectId)
            if !document.assetHydrated {
                logger.warning("SpecDocument/\(document.id.uuidString) arrived without CKAsset and no local bytes")
            }
        } else {
            document.assetHydrated = SpecDocument.hasLocalSpecBytes(projectId: document.projectId)
        }

        store.applyRemoteUpsert(document)
        return true
    }

    func writeSpecAssetToDisk(assetURL: URL, document: SpecDocument) throws {
        let projectDir = SpecImportService.specsDirectory(for: document.projectId)
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)

        let destination = projectDir.appendingPathComponent(document.specFileName)
        let destinationDir = destination.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: destinationDir.path) {
            try FileManager.default.createDirectory(at: destinationDir, withIntermediateDirectories: true)
        }
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: assetURL, to: destination)

        let fingerprintURL = projectDir.appendingPathComponent("fingerprint.txt")
        try document.contentFingerprint.write(to: fingerprintURL, atomically: true, encoding: .utf8)
    }

    @discardableResult
    func applyProtoBundleUpsert(record: CKRecord, store: ProjectStore) -> Bool {
        guard var bundle = decodeRecord(record, as: ProtoBundle.self) else {
            return false
        }

        if let asset = record[ProtoBundle.ckAssetField] as? CKAsset,
           let assetURL = asset.fileURL {
            do {
                try writeProtoAssetToDisk(assetURL: assetURL, bundle: bundle)
                bundle.assetHydrated = true
            } catch {
                logger.fault("Failed to write ProtoBundle asset for \(bundle.id): \(error)")
                bundle.assetHydrated = ProtoBundle.hasLocalProtoBytes(
                    projectId: bundle.projectId,
                    bundleId: bundle.id
                )
                syncState.report(RequestError(
                    kind: .cloudDecodeError,
                    message: String(localized: "Could not save the synced proto bundle to disk.")
                ))
            }
        } else {
            bundle.assetHydrated = ProtoBundle.hasLocalProtoBytes(
                projectId: bundle.projectId,
                bundleId: bundle.id
            )
            if !bundle.assetHydrated {
                logger.warning("ProtoBundle/\(bundle.id.uuidString) arrived without CKAsset and no local bytes")
            }
        }

        store.applyRemoteUpsert(bundle)
        return true
    }

    func writeProtoAssetToDisk(assetURL: URL, bundle: ProtoBundle) throws {
        let bundleDirectory = ProtoBundle.localBundleDirectoryURL(
            projectId: bundle.projectId,
            bundleId: bundle.id
        )
        try ProtoBundleService.extractBundleZip(assetURL: assetURL, bundleDirectory: bundleDirectory)

        let fingerprintURL = bundleDirectory.appendingPathComponent(ProtoBundle.fingerprintFileName)
        try bundle.contentFingerprint.write(to: fingerprintURL, atomically: true, encoding: .utf8)
    }
}
