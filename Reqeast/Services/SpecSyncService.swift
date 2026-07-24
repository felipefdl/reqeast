//
//  SpecSyncService.swift
//  Reqeast
//

import Foundation
import os

private let syncLogger = Logger(subsystem: "app.reqeast", category: "SpecSync")

/// User-selected operations to apply from a `SpecSyncDiff` review sheet.
struct SpecSyncSelections: Equatable {
    var addedPrimaryKeys: Set<String> = []
    var modifiedRequestIDs: Set<String> = []
    var removedRequestIDs: Set<String> = []
    var identityChangedRequestIDs: Set<String> = []

    var hasSelection: Bool {
        !addedPrimaryKeys.isEmpty
            || !modifiedRequestIDs.isEmpty
            || !removedRequestIDs.isEmpty
            || !identityChangedRequestIDs.isEmpty
    }
}

enum SpecSyncApplyError: Error, Equatable, LocalizedError {
    case projectNotFound(id: UUID)
    case missingSpecLink(id: UUID)
    case diskWriteFailed

    var errorDescription: String? {
        switch self {
        case .projectNotFound:
            String(localized: "The project could not be found.")
        case .missingSpecLink:
            String(localized: "This project has no linked spec.")
        case .diskWriteFailed:
            String(localized: "Could not save spec file to disk.")
        }
    }
}

enum SpecSyncService {

    /// Full sync-apply pipeline: Rule A merge, bump `specRevision`, persist locally, then
    /// `queueSaveBatch` with child records first and `Project` last. Holds `syncApplyInProgress`
    /// for the entire operation so remote upserts are deferred (separate from `importInProgress`).
    @MainActor
    static func apply(
        diff: SpecSyncDiff,
        selections: SpecSyncSelections,
        projectId: UUID,
        newContentFingerprint: String,
        specBytes: Data,
        store: ProjectStore,
        options: SpecImportOptions = .default
    ) throws {
        store.syncApplyInProgress = true
        defer { store.syncApplyInProgress = false }

        guard let projectIndex = store.projects.firstIndex(where: { $0.id == projectId }) else {
            throw SpecSyncApplyError.projectNotFound(id: projectId)
        }
        guard store.projects[projectIndex].specLink != nil else {
            throw SpecSyncApplyError.missingSpecLink(id: projectId)
        }

        let snapshot = SyncApplySnapshot(
            projects: store.projects,
            requests: store.requests
        )

        let affectedRequestIDs: Set<UUID>
        do {
            affectedRequestIDs = try applyRuleA(
                diff: diff,
                selections: selections,
                projectId: projectId,
                store: store,
                options: options
            )

            var project = store.projects[projectIndex]
            var specLink = project.specLink!
            specLink.specRevision += 1
            specLink.contentFingerprint = newContentFingerprint
            specLink.lastSyncedAt = Date()
            project.specLink = specLink
            project.touch()
            store.projects[projectIndex] = project

            try writeSyncedSpecToDisk(
                projectId: projectId,
                specBytes: specBytes,
                specFileName: specFileName(for: specBytes),
                contentFingerprint: newContentFingerprint
            )
            try store.saveLocalOrThrow()
        } catch let error as SpecSyncApplyError {
            restoreSyncApplySnapshot(snapshot, to: store)
            throw error
        } catch {
            restoreSyncApplySnapshot(snapshot, to: store)
            throw error
        }

        let affectedRequests = store.requests.filter {
            $0.projectId == projectId && affectedRequestIDs.contains($0.id)
        }
        let project = store.projects[projectIndex]
        let specDocument = SpecSnapshotService.upsertLinkedSpecDocument(
            project: project,
            specFileName: specFileName(for: specBytes),
            store: store
        )

        CloudSyncService.shared.queueSaveBatch(
            project: project,
            requests: affectedRequests,
            specDocument: specDocument
        )
    }

    /// Applies Rule A merge for the selected diff rows. Mutates `store.requests` in memory.
    /// Returns IDs of requests touched by the apply (for proportional CloudKit batching).
    @MainActor
    static func applyRuleA(
        diff: SpecSyncDiff,
        selections: SpecSyncSelections,
        projectId: UUID,
        store: ProjectStore,
        options: SpecImportOptions = .default
    ) throws -> Set<UUID> {
        var affectedRequestIDs = Set<UUID>()
        var mergeOptions = options
        mergeOptions.scaffoldAuth = false

        for removed in diff.removed where selections.removedRequestIDs.contains(removed.requestId) {
            if let requestId = applyRemoved(removed, projectId: projectId, store: store) {
                affectedRequestIDs.insert(requestId)
            }
        }

        for operationDiff in diff.modified where selections.modifiedRequestIDs.contains(operationDiff.requestId) {
            if let requestId = try applyModified(
                operationDiff,
                projectId: projectId,
                store: store,
                options: mergeOptions
            ) {
                affectedRequestIDs.insert(requestId)
            }
        }

        for identityDiff in diff.identityChanged
            where selections.identityChangedRequestIDs.contains(identityDiff.requestId) {
            if let requestId = try applyIdentityChanged(
                identityDiff,
                projectId: projectId,
                store: store,
                options: mergeOptions
            ) {
                affectedRequestIDs.insert(requestId)
            }
        }

        let nextSortOrder = (store.requests.filter { $0.projectId == projectId }.map(\.sortOrder).max() ?? -1) + 1
        var addedSortOrder = nextSortOrder
        for added in diff.added where selections.addedPrimaryKeys.contains(added.primaryKey) {
            if let requestId = try applyAdded(
                added,
                projectId: projectId,
                store: store,
                sortOrder: addedSortOrder,
                options: options
            ) {
                affectedRequestIDs.insert(requestId)
            }
            addedSortOrder += 1
        }

        return affectedRequestIDs
    }

    /// Enriches Rust `diff_spec` output with `isConflict` flags from stored snapshots.
    static func enrichDiffWithConflicts(_ diff: SpecSyncDiff, store: ProjectStore) -> SpecSyncDiff {
        var enriched = diff

        enriched.modified = diff.modified.map { operationDiff in
            var copy = operationDiff
            guard
                let request = request(for: operationDiff.requestId, projectId: nil, store: store),
                let httpData = request.httpData
            else {
                return copy
            }
            var fieldDeltas = copy.fieldDeltas
            _ = SpecSnapshotService.markConflicts(on: &fieldDeltas, request: request, httpData: httpData)
            copy.fieldDeltas = fieldDeltas
            return copy
        }

        enriched.identityChanged = diff.identityChanged.map { identityDiff in
            var copy = identityDiff
            guard
                let request = request(for: identityDiff.requestId, projectId: nil, store: store),
                let httpData = request.httpData
            else {
                return copy
            }
            var fieldDeltas = copy.fieldDeltas
            _ = SpecSnapshotService.markConflicts(on: &fieldDeltas, request: request, httpData: httpData)
            copy.fieldDeltas = fieldDeltas
            return copy
        }

        return enriched
    }

    // MARK: - Removed (AC7)

    private static func applyRemoved(
        _ removed: MatchedOperation,
        projectId: UUID,
        store: ProjectStore
    ) -> UUID? {
        guard
            let requestId = UUID(uuidString: removed.requestId),
            let index = store.requests.firstIndex(where: { $0.id == requestId && $0.projectId == projectId })
        else {
            syncLogger.warning("Removed op \(removed.requestId) not found in store")
            return nil
        }

        store.requests[index].isSpecStale = true
        store.requests[index].touch()
        return requestId
    }

    // MARK: - Modified

    private static func applyModified(
        _ operationDiff: OperationDiff,
        projectId: UUID,
        store: ProjectStore,
        options: SpecImportOptions
    ) throws -> UUID? {
        guard
            let requestId = UUID(uuidString: operationDiff.requestId),
            let index = store.requests.firstIndex(where: { $0.id == requestId && $0.projectId == projectId }),
            var httpData = store.requests[index].httpData
        else {
            syncLogger.warning("Modified op \(operationDiff.requestId) not found in store")
            return nil
        }

        guard let baseline = SpecSnapshotService.baselineSnapshot(for: store.requests[index]) else {
            syncLogger.warning("Missing baseline snapshot for \(operationDiff.requestId)")
            return nil
        }

        let merged = mergeRuleA(
            current: httpData,
            operation: operationDiff.newOperation,
            baseline: baseline,
            options: options
        )
        httpData = merged
        store.requests[index].httpData = httpData

        if !store.requests[index].isRenamed {
            store.requests[index].name = operationDiff.newOperation.name
        }

        store.requests[index].isSpecStale = false
        store.requests[index].touch()

        try refreshSnapshot(for: &store.requests[index])
        return requestId
    }

    // MARK: - Identity change

    private static func applyIdentityChanged(
        _ identityDiff: IdentityChangeDiff,
        projectId: UUID,
        store: ProjectStore,
        options: SpecImportOptions
    ) throws -> UUID? {
        guard
            let requestId = UUID(uuidString: identityDiff.requestId),
            let index = store.requests.firstIndex(where: { $0.id == requestId && $0.projectId == projectId }),
            var httpData = store.requests[index].httpData
        else {
            syncLogger.warning("Identity-changed op \(identityDiff.requestId) not found in store")
            return nil
        }

        rotateIdentity(
            on: &store.requests[index],
            oldPrimaryKey: identityDiff.oldPrimaryKey,
            newPrimaryKey: identityDiff.newPrimaryKey
        )

        guard let baseline = SpecSnapshotService.baselineSnapshot(for: store.requests[index]) else {
            syncLogger.warning("Missing baseline snapshot for \(identityDiff.requestId)")
            return nil
        }

        let merged = mergeRuleA(
            current: httpData,
            operation: identityDiff.newOperation,
            baseline: baseline,
            options: options
        )
        httpData = merged
        store.requests[index].httpData = httpData

        if !store.requests[index].isRenamed {
            store.requests[index].name = identityDiff.newOperation.name
        }

        store.requests[index].isSpecStale = false
        store.requests[index].touch()

        try refreshSnapshot(for: &store.requests[index])
        return requestId
    }

    private static func rotateIdentity(
        on request: inout Request,
        oldPrimaryKey: String,
        newPrimaryKey: String
    ) {
        guard var identity = request.specIdentity else {
            request.specIdentity = SpecOperationIdentity(primaryKey: newPrimaryKey)
            return
        }

        guard identity.primaryKey != newPrimaryKey else {
            return
        }

        if !identity.alternateKeys.contains(identity.primaryKey) {
            identity.alternateKeys.append(identity.primaryKey)
        }
        if oldPrimaryKey != newPrimaryKey, !identity.alternateKeys.contains(oldPrimaryKey) {
            identity.alternateKeys.append(oldPrimaryKey)
        }
        identity.primaryKey = newPrimaryKey
        request.specIdentity = identity
    }

    // MARK: - Added

    private static func applyAdded(
        _ operation: NormalizedOperation,
        projectId: UUID,
        store: ProjectStore,
        sortOrder: Int,
        options: SpecImportOptions
    ) throws -> UUID? {
        guard var request = SpecImportMapper.mapLinkedRequest(
            operation,
            projectId: projectId,
            sortOrder: sortOrder,
            options: options
        ) else {
            return nil
        }

        request.isSpecStale = false
        request.touch()
        let requestId = request.id
        store.requests.append(request)

        if let index = store.requests.indices.last {
            try refreshSnapshot(for: &store.requests[index])
        }
        return requestId
    }

    // MARK: - Rule A merge

    private static func mergeRuleA(
        current: HttpRequestData,
        operation: NormalizedOperation,
        baseline: SpecOperationSnapshot,
        options: SpecImportOptions
    ) -> HttpRequestData {
        let specData = SpecImportMapper.mapHttpData(from: operation, options: options)
        let locallyModifiedFields = Set(
            SpecSnapshotService.hasLocalModifications(baseline: baseline, httpData: current).map(\.field)
        )

        var merged = current

        // Method: spec always wins.
        merged.method = specData.method

        // URL: spec unless locally modified (conflict).
        if !locallyModifiedFields.contains(.url) {
            merged.url = specData.url
        }

        // Body: spec unless locally modified (conflict).
        if !locallyModifiedFields.contains(.body) {
            applyBody(from: specData, to: &merged)
        }

        // Params: spec values with user-disabled and user-added rows preserved.
        merged.params = mergeParams(
            spec: specData.params,
            current: current.params,
            baseline: baseline.params
        )

        // Headers: spec values plus user-added headers not in baseline.
        merged.headers = mergeHeaders(
            spec: specData.headers,
            current: current.headers,
            baseline: baseline.headers,
            auth: current
        )

        // Auth fields and Keychain credentials remain from `current` (user wins).
        return merged
    }

    private static func mergeParams(
        spec: [KeyValueEntry],
        current: [KeyValueEntry],
        baseline: [SpecKeyValue]
    ) -> [KeyValueEntry] {
        let baselineByKey = Dictionary(
            baseline.map { ($0.key.lowercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let currentByKey = Dictionary(
            current.filter { !$0.isEmpty }.map { ($0.key.lowercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var merged: [KeyValueEntry] = []
        for specParam in spec.filter({ !$0.isEmpty }).sorted(by: keySort) {
            var entry = specParam
            let keyLower = specParam.key.lowercased()

            if let baselineParam = baselineByKey[keyLower],
               let currentParam = currentByKey[keyLower],
               baselineParam.enabled,
               !currentParam.enabled {
                entry.enabled = false
            }

            merged.append(entry)
        }

        for currentParam in current.filter({ !$0.isEmpty }) {
            let keyLower = currentParam.key.lowercased()
            if baselineByKey[keyLower] == nil {
                merged.append(currentParam)
            }
        }

        return merged.isEmpty ? [KeyValueEntry()] : merged
    }

    private static func mergeHeaders(
        spec: [KeyValueEntry],
        current: [KeyValueEntry],
        baseline: [SpecKeyValue],
        auth: HttpRequestData
    ) -> [KeyValueEntry] {
        let baselineKeys = Set(baseline.map { $0.key.lowercased() })

        var merged = spec.filter {
            !$0.isEmpty && !SpecSnapshotService.isAuthScaffoldHeader($0, in: auth)
        }

        for header in current where !header.isEmpty {
            let keyLower = header.key.lowercased()
            guard !baselineKeys.contains(keyLower) else { continue }
            guard !SpecSnapshotService.isAuthScaffoldHeader(header, in: auth) else { continue }
            merged.append(header)
        }

        return merged.isEmpty ? [KeyValueEntry()] : merged
    }

    private static func applyBody(from spec: HttpRequestData, to target: inout HttpRequestData) {
        target.bodyType = spec.bodyType
        target.bodyContent = spec.bodyContent
        target.bodyFormData = spec.bodyFormData
        target.bodyFormDataEntries = spec.bodyFormDataEntries
        target.rawContentType = spec.rawContentType
        target.binaryFileName = spec.binaryFileName
    }

    private static func refreshSnapshot(for request: inout Request) throws {
        var batch = [request]
        try SpecSnapshotService.applySnapshots(to: &batch, projectId: request.projectId)
        request = batch[0]
    }

    private static func request(
        for requestId: String,
        projectId: UUID?,
        store: ProjectStore
    ) -> Request? {
        guard let id = UUID(uuidString: requestId) else {
            return nil
        }
        return store.requests.first {
            $0.id == id && (projectId == nil || $0.projectId == projectId)
        }
    }

    private static func keySort(_ lhs: KeyValueEntry, _ rhs: KeyValueEntry) -> Bool {
        lhs.key.localizedCaseInsensitiveCompare(rhs.key) == .orderedAscending
    }

    // MARK: - Sync apply persistence

    private struct SyncApplySnapshot {
        let projects: [Project]
        let requests: [Request]
    }

    private static func restoreSyncApplySnapshot(_ snapshot: SyncApplySnapshot, to store: ProjectStore) {
        store.projects = snapshot.projects
        store.requests = snapshot.requests
    }

    static func specFileName(for bytes: Data) -> String {
        bytes.firstNonWhitespaceByte == UInt8(ascii: "{") ? "spec.json" : "spec.yaml"
    }

    private static func writeSyncedSpecToDisk(
        projectId: UUID,
        specBytes: Data,
        specFileName: String,
        contentFingerprint: String
    ) throws {
        let projectDir = SpecImportService.specsDirectory(for: projectId)
        let fingerprintURL = projectDir.appendingPathComponent("fingerprint.txt")

        do {
            try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
            let specURL = projectDir.appendingPathComponent(specFileName)
            try specBytes.write(to: specURL, options: .atomic)
            try contentFingerprint.write(to: fingerprintURL, atomically: true, encoding: .utf8)
        } catch {
            syncLogger.error("Failed to write synced spec for \(projectId): \(error)")
            throw SpecSyncApplyError.diskWriteFailed
        }
    }
}

private extension Data {
    var firstNonWhitespaceByte: UInt8? {
        var offset = startIndex
        while offset < endIndex {
            let byte = self[offset]
            if byte == UInt8(ascii: " ") || byte == UInt8(ascii: "\n")
                || byte == UInt8(ascii: "\r") || byte == UInt8(ascii: "\t") {
                offset = offset + 1
                continue
            }
            return byte
        }
        return nil
    }
}