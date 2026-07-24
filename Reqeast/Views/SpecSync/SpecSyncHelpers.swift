//
//  SpecSyncHelpers.swift
//  Reqeast
//

import Foundation

enum SpecSyncReviewSegment: String, CaseIterable, Identifiable {
    case added
    case modified
    case removed
    case unchanged

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .added: String(localized: "Added")
        case .modified: String(localized: "Modified")
        case .removed: String(localized: "Removed")
        case .unchanged: String(localized: "Unchanged")
        }
    }
}

enum SpecSyncHelpers {

    static func staleCount(for projectId: UUID, store: ProjectStore) -> Int {
        store.requests(for: projectId).filter(\.isSpecStale).count
    }

    static func compactBadgeLabel(staleCount: Int) -> String {
        if staleCount == 0 {
            return String(localized: "Spec")
        }
        return String(
            format: String(localized: "Spec · %lld stale"),
            locale: .current,
            staleCount
        )
    }

    static func regularBadgeLabel(staleCount: Int, isLinked: Bool) -> String {
        if staleCount == 0 {
            return isLinked
                ? String(localized: "Linked spec")
                : String(localized: "Spec snapshot")
        }
        return String(
            format: String(localized: "Spec · %lld stale requests"),
            locale: .current,
            staleCount
        )
    }

    static func reviewSummaryLabel(diff: SpecSyncDiff) -> String {
        String(
            format: String(
                localized: "%lld added, %lld modified, %lld removed, %lld unchanged"
            ),
            locale: .current,
            diff.added.count,
            diff.modified.count,
            diff.removed.count,
            diff.unchanged.count
        )
    }

    static func segmentLabel(_ segment: SpecSyncReviewSegment, diff: SpecSyncDiff) -> String {
        let count: Int
        switch segment {
        case .added: count = diff.added.count
        case .modified: count = diff.modified.count + diff.identityChanged.count
        case .removed: count = diff.removed.count
        case .unchanged: count = diff.unchanged.count
        }
        return "\(segment.localizedTitle) (\(count))"
    }

    static func defaultSelections(from diff: SpecSyncDiff) -> SpecSyncSelections {
        SpecSyncSelections(
            addedPrimaryKeys: Set(diff.added.map(\.primaryKey)),
            modifiedRequestIDs: Set(diff.modified.map(\.requestId)),
            removedRequestIDs: Set(diff.removed.map(\.requestId)),
            identityChangedRequestIDs: Set(diff.identityChanged.map(\.requestId))
        )
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

    static func requestName(for requestId: String, projectId: UUID, store: ProjectStore) -> String {
        guard let id = UUID(uuidString: requestId),
              let request = store.requests.first(where: { $0.id == id && $0.projectId == projectId }) else {
            return requestId
        }
        return request.name
    }

    static func truncatedFingerprint(_ fingerprint: String) -> String {
        guard fingerprint.count > 16 else { return fingerprint }
        return "\(fingerprint.prefix(8))…\(fingerprint.suffix(8))"
    }

    static func fingerprintsMatch(_ lhs: String, _ rhs: String) -> Bool {
        lhs == rhs
    }

    static func fingerprintMatchLabel(matches: Bool) -> String {
        matches
            ? String(localized: "Matches local fingerprint")
            : String(localized: "Differs from local fingerprint")
    }

    static func dismissAllStaleLabel(count: Int) -> String {
        String(
            format: String(localized: "Dismiss All Stale (%lld)"),
            locale: .current,
            count
        )
    }

    static func deleteAllStaleLabel(count: Int) -> String {
        String(
            format: String(localized: "Delete All Stale (%lld)"),
            locale: .current,
            count
        )
    }

    static func deleteStaleConfirmationButton(count: Int) -> String {
        String(
            format: String(localized: "Delete %lld Requests"),
            locale: .current,
            count
        )
    }
}