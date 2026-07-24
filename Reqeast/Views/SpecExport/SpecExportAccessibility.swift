//
//  SpecExportAccessibility.swift
//  Reqeast
//

import Foundation

enum SpecExportAccessibility {
    static let sheetExportButton = "spec-export-export-button"
    static let sheetCancelButton = "spec-export-cancel-button"

    static let segmentPicker = "export-review-segment-picker"
    static let summaryCounts = "export-review-summary-counts"
    static let exportButton = "export-review-export-button"
    static let cancelButton = "export-review-cancel-button"

    static func segment(_ segment: SpecExportReviewSegment) -> String {
        "export-review-segment-\(segment.rawValue)"
    }

    static func operationToggle(_ id: String) -> String {
        "export-review-operation-toggle-\(id)"
    }

    static func operationRow(_ id: String) -> String {
        "export-review-operation-row-\(id)"
    }
}