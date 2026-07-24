//
//  SpecExportUITestSupport.swift
//  Reqeast
//

import Foundation
#if os(macOS)
import AppKit
#endif

#if DEBUG
/// Deterministic export fixtures for macOS UITests (bypasses `fileExporter` save panel).
enum SpecExportUITestSupport {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-specExportUITest")
    }

    private static var exportedYAML: String?
    private static var awaitingReimport = false

    static func recordExport(_ yaml: String) {
        exportedYAML = yaml
        awaitingReimport = true
        #if os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(yaml, forType: .string)
        #endif
    }

    static func prefilledReimportPasteText() -> String? {
        guard awaitingReimport, let exportedYAML else { return nil }
        return exportedYAML
    }

    static func clearReimportState() {
        exportedYAML = nil
        awaitingReimport = false
    }
}
#endif