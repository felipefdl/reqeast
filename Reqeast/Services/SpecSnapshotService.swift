//
//  SpecSnapshotService.swift
//  Reqeast
//

import CryptoKit
import Foundation
import os
import zlib

private let snapshotLogger = Logger(subsystem: "app.reqeast", category: "SpecSnapshot")

enum SpecSnapshotService {

    /// Maximum gzip-compressed `specSnapshotPayload` size synced on `Request`.
    static let maxSnapshotPayloadBytes = 96_000

    #if DEBUG
    /// Overrides `maxSnapshotPayloadBytes` in unit tests.
    static var maxSnapshotPayloadBytesForTesting: Int?
    #endif

    static let snapshotsDirectoryName = "snapshots"

    private static var effectiveMaxSnapshotPayloadBytes: Int {
        #if DEBUG
        maxSnapshotPayloadBytesForTesting ?? maxSnapshotPayloadBytes
        #else
        maxSnapshotPayloadBytes
        #endif
    }

    // MARK: - Paths

    static func snapshotsDirectory(projectId: UUID) -> URL {
        SpecImportService.specsDirectory(for: projectId)
            .appendingPathComponent(snapshotsDirectoryName, isDirectory: true)
    }

    static func snapshotFileURL(projectId: UUID, requestId: UUID) -> URL {
        snapshotsDirectory(projectId: projectId)
            .appendingPathComponent("\(requestId.uuidString).json")
    }

    // MARK: - Spec bytes hydration (multi-device)

    enum SpecBytesHydrationOutcome: Equatable {
        case notNeeded
        case hydrated
        case missingSource
        case fetchFailed
        case fingerprintMismatch
        case diskWriteFailed
    }

    /// Writes linked spec bytes and fingerprint into the on-disk spec directory.
    static func writeSpecBytesToDisk(
        bytes: Data,
        projectId: UUID,
        specFileName: String,
        contentFingerprint: String
    ) throws {
        let projectDir = SpecImportService.specsDirectory(for: projectId)
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)

        let specURL = projectDir.appendingPathComponent(specFileName)
        let specDir = specURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: specDir.path) {
            try FileManager.default.createDirectory(at: specDir, withIntermediateDirectories: true)
        }
        try bytes.write(to: specURL, options: .atomic)

        let fingerprintURL = projectDir.appendingPathComponent("fingerprint.txt")
        try contentFingerprint.write(to: fingerprintURL, atomically: true, encoding: .utf8)
    }

    /// Builds a `SpecDocument` for linked projects that sync raw spec bytes via CKAsset.
    static func makeLinkedSpecDocument(project: Project, specFileName: String) -> SpecDocument? {
        guard let specLink = project.specLink, !specLink.isDetached else { return nil }
        return SpecDocument.from(project: project, specFileName: specFileName)
    }

    /// Upserts the linked project's `SpecDocument` in the store (caller persists / queues sync).
    @MainActor
    @discardableResult
    static func upsertLinkedSpecDocument(
        project: Project,
        specFileName: String,
        store: ProjectStore
    ) -> SpecDocument? {
        guard var document = makeLinkedSpecDocument(project: project, specFileName: specFileName) else {
            return nil
        }
        document.touch()
        if let index = store.specDocuments.firstIndex(where: { $0.projectId == project.id }) {
            store.specDocuments[index] = document
        } else {
            store.specDocuments.append(document)
        }
        return document
    }

    /// Secondary-device fallback: re-fetch spec bytes from the linked source when CKAsset is missing.
    @MainActor
    static func hydrateSpecBytesFromSourceIfNeeded(
        document: SpecDocument,
        specLink: SpecLink?,
        store: ProjectStore
    ) async -> SpecBytesHydrationOutcome {
        guard document.uploadsAsset else { return .notNeeded }
        if SpecDocument.hasLocalSpecBytes(projectId: document.projectId) {
            markSpecDocumentHydrated(projectId: document.projectId, store: store)
            return .notNeeded
        }

        guard let specLink, !specLink.isDetached else { return .missingSource }

        let bytes: Data
        do {
            bytes = try await fetchLinkedSpecBytes(specLink: specLink, projectId: document.projectId)
        } catch {
            snapshotLogger.warning("Spec hydration re-fetch failed for \(document.projectId): \(error)")
            return .fetchFailed
        }

        let fetchedFingerprint = canonicalFingerprint(resolvedBytes: bytes)
        guard fetchedFingerprint == document.contentFingerprint else {
            snapshotLogger.warning(
                "Spec hydration fingerprint mismatch for \(document.projectId): expected \(document.contentFingerprint), got \(fetchedFingerprint)"
            )
            return .fingerprintMismatch
        }

        do {
            try writeSpecBytesToDisk(
                bytes: bytes,
                projectId: document.projectId,
                specFileName: document.specFileName,
                contentFingerprint: document.contentFingerprint
            )
        } catch {
            snapshotLogger.error("Spec hydration disk write failed for \(document.projectId): \(error)")
            return .diskWriteFailed
        }

        markSpecDocumentHydrated(projectId: document.projectId, store: store)
        return .hydrated
    }

    @MainActor
    private static func markSpecDocumentHydrated(projectId: UUID, store: ProjectStore) {
        guard let index = store.specDocuments.firstIndex(where: { $0.projectId == projectId }) else {
            return
        }
        var document = store.specDocuments[index]
        guard !document.assetHydrated else { return }
        document.assetHydrated = true
        document.touch()
        store.specDocuments[index] = document
        store.saveLocal()
    }

    @MainActor
    private static func fetchLinkedSpecBytes(specLink: SpecLink, projectId: UUID) async throws -> Data {
        switch specLink.source {
        case .url:
            guard let sourceURL = specLink.sourceURL, let url = URL(string: sourceURL) else {
                throw SpecImportError.from(
                    message: String(localized: "This project is not linked to a live spec URL."),
                    kind: .invalidSpec
                )
            }
            #if DEBUG
            if let fixture = SpecSyncUITestSupport.fetchData(for: url) {
                return fixture
            }
            #endif
            return try await SafeFetchService.shared.fetch(url: url)

        case .gitHTTPS, .gitProvider, .localBookmark:
            #if DEBUG
            if let sourceURL = specLink.sourceURL,
               let url = URL(string: sourceURL),
               let fixture = SpecSyncUITestSupport.fetchData(for: url) {
                return fixture
            }
            #endif

            switch specLink.source {
            case .localBookmark:
                return try SpecBookmarkStore.readSpecBytes(projectId: projectId).bytes
            default:
                return try await GitSpecSourceService.fetchLinkedSpec(
                    specLink: specLink,
                    projectId: projectId
                )
            }

        case .file, .paste:
            throw SpecImportError.from(
                message: String(localized: "This project is not linked to a live spec source."),
                kind: .invalidSpec
            )
        }
    }

    // MARK: - Import / sync apply

    /// Writes disk snapshots and populates `specFieldFingerprint` / `specSnapshotPayload` for HTTP spec requests.
    static func applySnapshots(to requests: inout [Request], projectId: UUID) throws {
        let syncedAt = Date()
        for index in requests.indices {
            guard requests[index].type == .http, let httpData = requests[index].httpData else {
                continue
            }

            let snapshot = makeSnapshot(from: httpData)
            try writeSnapshotToDisk(snapshot, projectId: projectId, requestId: requests[index].id)
            requests[index].specFieldFingerprint = fingerprint(for: snapshot)
            requests[index].specSnapshotPayload = encodePayload(snapshot)
            requests[index].specLastSyncedAt = syncedAt
        }
    }

    // MARK: - Disk I/O

    static func writeSnapshotToDisk(
        _ snapshot: SpecOperationSnapshot,
        projectId: UUID,
        requestId: UUID
    ) throws {
        let directory = snapshotsDirectory(projectId: projectId)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let encoder = Self.diskEncoder
        let data = try encoder.encode(snapshot)
        let fileURL = snapshotFileURL(projectId: projectId, requestId: requestId)
        try data.write(to: fileURL, options: .atomic)
    }

    static func readSnapshotFromDisk(projectId: UUID, requestId: UUID) -> SpecOperationSnapshot? {
        let fileURL = snapshotFileURL(projectId: projectId, requestId: requestId)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: fileURL)
            return try Self.diskDecoder.decode(SpecOperationSnapshot.self, from: data)
        } catch {
            snapshotLogger.error("Failed to read snapshot for \(requestId): \(error)")
            return nil
        }
    }

    /// Hydrates `snapshots/{requestId}.json` from `specSnapshotPayload` when the disk file is missing.
    static func hydrateFromPayloadIfNeeded(for request: Request) throws {
        let fileURL = snapshotFileURL(projectId: request.projectId, requestId: request.id)
        guard !FileManager.default.fileExists(atPath: fileURL.path) else {
            return
        }
        guard let payload = request.specSnapshotPayload else {
            return
        }

        let snapshot = try decodePayload(payload)
        try writeSnapshotToDisk(snapshot, projectId: request.projectId, requestId: request.id)
    }

    // MARK: - Fingerprint + payload

    static func fingerprint(for snapshot: SpecOperationSnapshot) -> String {
        let data = (try? canonicalJSONData(for: snapshot)) ?? Data()
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func canonicalJSONData(for snapshot: SpecOperationSnapshot) throws -> Data {
        try canonicalEncoder.encode(snapshot)
    }

    static func encodePayload(_ snapshot: SpecOperationSnapshot) -> Data? {
        guard let json = try? canonicalEncoder.encode(snapshot) else {
            return nil
        }
        guard let compressed = try? gzipCompress(json) else {
            return nil
        }
        guard compressed.count <= effectiveMaxSnapshotPayloadBytes else {
            snapshotLogger.warning("Snapshot payload exceeds cap (\(compressed.count) bytes)")
            return nil
        }
        return compressed
    }

    static func decodePayload(_ payload: Data) throws -> SpecOperationSnapshot {
        let json = try gzipDecompress(payload)
        return try canonicalDecoder.decode(SpecOperationSnapshot.self, from: json)
    }

    // MARK: - Snapshot extraction

    static func makeSnapshot(from httpData: HttpRequestData) -> SpecOperationSnapshot {
        SpecOperationSnapshot(
            method: httpData.method.rawLabel,
            urlTemplate: httpData.url,
            params: mapKeyValues(httpData.params),
            headers: mapHeaders(httpData.headers, auth: httpData),
            body: mapBody(httpData)
        )
    }

    // MARK: - Local modifications

    /// Resolves the stored baseline snapshot from disk, falling back to `specSnapshotPayload`.
    static func baselineSnapshot(for request: Request) -> SpecOperationSnapshot? {
        if let diskSnapshot = readSnapshotFromDisk(projectId: request.projectId, requestId: request.id) {
            return diskSnapshot
        }
        guard let payload = request.specSnapshotPayload else {
            return nil
        }
        return try? decodePayload(payload)
    }

    /// Compares the stored baseline against live `HttpRequestData` and returns per-field deltas.
    static func hasLocalModifications(
        baseline: SpecOperationSnapshot,
        httpData: HttpRequestData
    ) -> [SpecFieldDelta] {
        hasLocalModifications(baseline: baseline, live: makeSnapshot(from: httpData))
    }

    /// Compares two snapshots using key-based fields (not `KeyValueEntry.id`).
    static func hasLocalModifications(
        baseline: SpecOperationSnapshot,
        live: SpecOperationSnapshot
    ) -> [SpecFieldDelta] {
        fieldDeltas(between: baseline, and: live)
    }

    /// Returns whether live request fields differ from the synced `specFieldFingerprint`.
    static func hasAnyLocalModifications(request: Request, httpData: HttpRequestData) -> Bool {
        guard let storedFingerprint = request.specFieldFingerprint else {
            return false
        }
        return fingerprint(for: makeSnapshot(from: httpData)) != storedFingerprint
    }

    /// Marks `isConflict` on spec diff rows when the same field was locally modified since sync.
    static func markConflicts(
        on fieldDeltas: inout [SpecFieldDelta],
        baseline: SpecOperationSnapshot,
        httpData: HttpRequestData
    ) {
        let locallyModifiedFields = Set(
            hasLocalModifications(baseline: baseline, httpData: httpData).map(\.field)
        )
        guard !locallyModifiedFields.isEmpty else {
            return
        }

        for index in fieldDeltas.indices {
            if locallyModifiedFields.contains(fieldDeltas[index].field) {
                fieldDeltas[index].isConflict = true
            }
        }
    }

    /// Marks conflicts using the request's stored baseline snapshot and live HTTP data.
    @discardableResult
    static func markConflicts(
        on fieldDeltas: inout [SpecFieldDelta],
        request: Request,
        httpData: HttpRequestData
    ) -> Bool {
        guard let baseline = baselineSnapshot(for: request) else {
            return false
        }
        markConflicts(on: &fieldDeltas, baseline: baseline, httpData: httpData)
        return fieldDeltas.contains(where: \.isConflict)
    }

    // MARK: - Private helpers

    private static func fieldDeltas(
        between baseline: SpecOperationSnapshot,
        and live: SpecOperationSnapshot
    ) -> [SpecFieldDelta] {
        var deltas: [SpecFieldDelta] = []
        pushDeltaIfChanged(&deltas, field: .method, oldValue: baseline.method, newValue: live.method)
        pushDeltaIfChanged(
            &deltas,
            field: .url,
            oldValue: baseline.urlTemplate,
            newValue: live.urlTemplate
        )
        pushDeltaIfChanged(
            &deltas,
            field: .params,
            oldValue: fieldValueString(for: baseline.params),
            newValue: fieldValueString(for: live.params)
        )
        pushDeltaIfChanged(
            &deltas,
            field: .headers,
            oldValue: fieldValueString(for: baseline.headers),
            newValue: fieldValueString(for: live.headers)
        )
        pushDeltaIfChanged(
            &deltas,
            field: .body,
            oldValue: fieldValueString(for: baseline.body),
            newValue: fieldValueString(for: live.body)
        )
        return deltas
    }

    private static func pushDeltaIfChanged(
        _ deltas: inout [SpecFieldDelta],
        field: SpecSyncField,
        oldValue: String,
        newValue: String
    ) {
        guard oldValue != newValue else {
            return
        }
        deltas.append(
            SpecFieldDelta(field: field, oldValue: oldValue, newValue: newValue, isConflict: false)
        )
    }

    private static func fieldValueString(for params: [SpecKeyValue]) -> String {
        guard let data = try? canonicalEncoder.encode(params),
              let string = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return string
    }

    private static func fieldValueString(for body: SpecBodySnapshot) -> String {
        guard let data = try? canonicalEncoder.encode(body),
              let string = String(data: data, encoding: .utf8) else {
            return #"{"none":{}}"#
        }
        return string
    }

    private static let canonicalEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private static let canonicalDecoder = JSONDecoder()

    private static let diskEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let diskDecoder = JSONDecoder()

    private static func mapKeyValues(_ entries: [KeyValueEntry]) -> [SpecKeyValue] {
        entries
            .filter { !$0.isEmpty }
            .map { SpecKeyValue(key: $0.key, value: $0.value, enabled: $0.enabled) }
            .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
    }

    private static func mapHeaders(_ entries: [KeyValueEntry], auth: HttpRequestData) -> [SpecKeyValue] {
        entries
            .filter { !$0.isEmpty && !isAuthScaffoldHeader($0, in: auth) }
            .map { SpecKeyValue(key: $0.key, value: $0.value, enabled: $0.enabled) }
            .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
    }

    private static func mapBody(_ httpData: HttpRequestData) -> SpecBodySnapshot {
        switch httpData.bodyType {
        case .none:
            return .none
        case .json:
            return .json(content: httpData.bodyContent)
        case .urlencoded:
            return .urlencoded(fields: mapKeyValues(httpData.bodyFormData))
        case .formData:
            let entries = httpData.bodyFormDataEntries
                .filter { !$0.isEmpty }
                .map { entry in
                    SpecFormDataEntry(
                        key: entry.key,
                        value: entry.value,
                        enabled: entry.enabled,
                        fieldType: entry.fieldType,
                        fileName: entry.fileName,
                        mimeType: entry.mimeType
                    )
                }
                .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
            return .formData(entries: entries)
        case .raw:
            let contentType = httpData.rawContentType?.mimeType ?? HttpRawContentType.text.mimeType
            return .raw(content: httpData.bodyContent, contentType: contentType)
        case .binary:
            return .binary(fileName: httpData.binaryFileName)
        }
    }

    static func isAuthScaffoldHeader(_ header: KeyValueEntry, in httpData: HttpRequestData) -> Bool {
        guard httpData.authType != .none, !header.key.isEmpty else {
            return false
        }

        switch httpData.authType {
        case .none:
            return false
        case .apiKey:
            guard httpData.authApiKeyLocation == "header" else {
                return false
            }
            return header.key.caseInsensitiveCompare(httpData.authApiKeyName) == .orderedSame
        case .bearer, .basic, .jwtBearer, .oauth2, .hawkAuth, .awsSignature,
             .akamaiEdgeGrid, .digestAuth, .oauth1, .ntlm:
            return header.key.caseInsensitiveCompare("Authorization") == .orderedSame
        }
    }

    private static func gzipCompress(_ data: Data) throws -> Data {
        try gzipProcess(data, operation: .compress)
    }

    private static func gzipDecompress(_ data: Data) throws -> Data {
        try gzipProcess(data, operation: .decompress)
    }

    private enum GzipOperation {
        case compress
        case decompress
    }

    private static func gzipProcess(_ data: Data, operation: GzipOperation) throws -> Data {
        guard !data.isEmpty else { return Data() }

        var stream = z_stream()
        stream.zalloc = nil
        stream.zfree = nil
        stream.opaque = nil
        stream.avail_in = 0
        stream.next_in = nil

        let windowBits: Int32 = operation == .compress ? (MAX_WBITS + 16) : (MAX_WBITS + 32)
        let status: Int32
        switch operation {
        case .compress:
            status = deflateInit2_(
                &stream,
                Z_DEFAULT_COMPRESSION,
                Z_DEFLATED,
                windowBits,
                MAX_MEM_LEVEL,
                Z_DEFAULT_STRATEGY,
                ZLIB_VERSION,
                Int32(MemoryLayout<z_stream>.size)
            )
        case .decompress:
            status = inflateInit2_(
                &stream,
                windowBits,
                ZLIB_VERSION,
                Int32(MemoryLayout<z_stream>.size)
            )
        }

        guard status == Z_OK else {
            throw GzipError.initializationFailed
        }

        defer {
            switch operation {
            case .compress:
                deflateEnd(&stream)
            case .decompress:
                inflateEnd(&stream)
            }
        }

        var output = Data()
        let chunkSize = 65_536

        try data.withUnsafeBytes { inputBuffer in
            guard let inputPointer = inputBuffer.bindMemory(to: Bytef.self).baseAddress else {
                throw GzipError.invalidInput
            }

            stream.next_in = UnsafeMutablePointer(mutating: inputPointer)
            stream.avail_in = uInt(data.count)

            var code: Int32 = Z_OK
            repeat {
                let produced = Int(stream.total_out)
                if output.count < produced + chunkSize {
                    output.count = produced + chunkSize
                }

                try output.withUnsafeMutableBytes { outputBuffer in
                    guard let outputPointer = outputBuffer.bindMemory(to: Bytef.self).baseAddress else {
                        throw GzipError.invalidOutput
                    }

                    stream.next_out = outputPointer.advanced(by: produced)
                    stream.avail_out = uInt(outputBuffer.count) - uInt(produced)

                    switch operation {
                    case .compress:
                        code = deflate(&stream, Z_FINISH)
                    case .decompress:
                        code = inflate(&stream, Z_NO_FLUSH)
                    }
                }

                guard code != Z_STREAM_ERROR, code != Z_DATA_ERROR, code != Z_MEM_ERROR else {
                    throw GzipError.processingFailed
                }
            } while code != Z_STREAM_END
        }

        output.count = Int(stream.total_out)
        return output
    }

    private enum GzipError: Error {
        case initializationFailed
        case invalidInput
        case invalidOutput
        case processingFailed
    }
}