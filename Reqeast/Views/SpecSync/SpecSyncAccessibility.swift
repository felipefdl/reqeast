//
//  SpecSyncAccessibility.swift
//  Reqeast
//

import Foundation

enum SpecSyncAccessibility {
    static let toolbarBadge = "sync-review-toolbar-badge"
    static let specLinkPanel = "sync-review-spec-link-panel"
    static let checkForUpdatesButton = "sync-review-check-for-updates"
    static let backgroundCheckToggle = "sync-review-background-check-toggle"
    static let segmentPicker = "sync-review-segment-picker"
    static let summaryCounts = "sync-review-summary-counts"
    static let applyButton = "sync-review-apply-button"
    static let cancelButton = "sync-review-cancel-button"

    static func segment(_ segment: SpecSyncReviewSegment) -> String {
        "sync-review-segment-\(segment.rawValue)"
    }

    static func operationToggle(_ id: String) -> String {
        "sync-review-operation-toggle-\(id)"
    }

    static func operationRow(_ id: String) -> String {
        "sync-review-operation-row-\(id)"
    }

    static let specReadOnlyBanner = "spec-read-only-banner"

    static let staleFilterToggle = "stale-ops-filter-toggle"
    static let dismissAllStaleButton = "stale-ops-dismiss-all"
    static let deleteAllStaleButton = "stale-ops-delete-all"
    static let dismissStaleContextMenu = "stale-ops-dismiss-context"
}