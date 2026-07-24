//
//  HttpResponseReadOnlyEditor.swift
//  Reqeast
//

import SwiftUI
#if os(macOS)
import CodeEditLanguages
#endif

/// Read-only editor used to display a response body (pretty JSON, raw text, highlighted HTML).
/// Centralizes the macOS `CodeEditSourceEditor` + iOS native branches and forces a rebuild via
/// `ResponseEditorIdentity.id` so jq-filter text changes actually replace the editor content
/// (CodeEditSourceEditor does not sync a re-bound `.constant` value without view replacement).
struct HttpResponseReadOnlyEditor: View {
    enum Mode {
        case json
        case html
        case plain
    }

    let text: String
    let mode: Mode
    let responseTimestamp: Date

    var body: some View {
        #if os(macOS)
        SourceEditorView(
            text: .constant(text),
            language: macOSLanguage,
            isEditable: true,
            isResponse: true
        )
        .clipped()
        .id(ResponseEditorIdentity.id(timestamp: responseTimestamp, text: text))
        #else
        SourceEditorView(
            text: .constant(text),
            isEditable: false,
            isResponse: true,
            jsonHighlight: mode == .json,
            htmlHighlight: mode == .html
        )
        .id(ResponseEditorIdentity.id(timestamp: responseTimestamp, text: text))
        #endif
    }

    #if os(macOS)
    private var macOSLanguage: CodeLanguage {
        switch mode {
        case .json: .json
        case .html: .html
        case .plain: .default
        }
    }
    #endif
}
