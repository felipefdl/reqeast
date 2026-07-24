//
//  SpecExportReviewHelpers.swift
//  Reqeast
//

import Foundation

enum SpecExportReviewHelpers {

    static func reviewSummaryLabel(diff: SpecSyncDiff) -> String {
        let (changedModified, changedIdentity) = changedOperations(from: diff)
        let (conflictModified, conflictIdentity) = conflictOperations(from: diff)
        return String(
            format: String(
                localized: "%lld only in project, %lld only in spec, %lld changed, %lld conflicts"
            ),
            locale: .current,
            diff.added.count,
            diff.removed.count,
            changedModified.count + changedIdentity.count,
            conflictModified.count + conflictIdentity.count
        )
    }

    static func segmentLabel(_ segment: SpecExportReviewSegment, diff: SpecSyncDiff) -> String {
        let count: Int
        switch segment {
        case .projectOnly:
            count = diff.added.count
        case .specOnly:
            count = diff.removed.count
        case .changed:
            let (modified, identity) = changedOperations(from: diff)
            count = modified.count + identity.count
        case .conflicts:
            let (modified, identity) = conflictOperations(from: diff)
            count = modified.count + identity.count
        }
        return "\(segment.localizedTitle) (\(count))"
    }

    static func defaultSelections(from diff: SpecSyncDiff) -> SpecExportSelections {
        SpecExportService.defaultSelections(from: diff)
    }

    static func preferredInitialSegment(for diff: SpecSyncDiff) -> SpecExportReviewSegment {
        if !diff.added.isEmpty { return .projectOnly }
        if !diff.removed.isEmpty { return .specOnly }
        let (conflictModified, conflictIdentity) = conflictOperations(from: diff)
        if !conflictModified.isEmpty || !conflictIdentity.isEmpty { return .conflicts }
        if !diff.modified.isEmpty || !diff.identityChanged.isEmpty { return .changed }
        return .projectOnly
    }

    static func requestName(for requestId: String, projectId: UUID, store: ProjectStore) -> String {
        guard let id = UUID(uuidString: requestId),
              let request = store.requests.first(where: { $0.id == id && $0.projectId == projectId }) else {
            return requestId
        }
        return request.name
    }

    static func fieldLabel(_ field: SpecSyncField) -> String {
        switch field {
        case .method: "Method"
        case .url: "URL"
        case .params: String(localized: "Params")
        case .headers: String(localized: "Headers")
        case .body: String(localized: "Body")
        case .name: String(localized: "Name")
        }
    }

    static func changedOperations(
        from diff: SpecSyncDiff
    ) -> (modified: [OperationDiff], identity: [IdentityChangeDiff]) {
        let modified = diff.modified.filter { !$0.fieldDeltas.contains(where: \.isConflict) }
        let identity = diff.identityChanged.filter { !$0.fieldDeltas.contains(where: \.isConflict) }
        return (modified, identity)
    }

    static func conflictOperations(
        from diff: SpecSyncDiff
    ) -> (modified: [OperationDiff], identity: [IdentityChangeDiff]) {
        let modified = diff.modified.filter { $0.fieldDeltas.contains(where: \.isConflict) }
        let identity = diff.identityChanged.filter { $0.fieldDeltas.contains(where: \.isConflict) }
        return (modified, identity)
    }
}