//
//  SourceEditorView.swift
//  Reqeast
//

import SwiftUI

#if os(macOS)
import CodeEditSourceEditor
import CodeEditLanguages
import CodeEditTextView

struct SourceEditorView: View {
    @Binding var text: String
    var language: CodeLanguage = .default
    var isEditable: Bool = true
    var isResponse: Bool = false

    @AppStorage("jsonIndentSpaces") private var jsonIndentSpaces: Int = 2
    @Environment(\.colorScheme) private var colorScheme
    @State private var editorState = SourceEditorState()
    @State private var readOnlyGuard = ReadOnlyCoordinator()

    private var theme: EditorTheme {
        if isResponse {
            return colorScheme == .dark ? ReqeastEditorTheme.responseDark : ReqeastEditorTheme.responseLight
        }
        return colorScheme == .dark ? ReqeastEditorTheme.dark : ReqeastEditorTheme.light
    }

    var body: some View {
        SourceEditor(
            $text,
            language: language,
            configuration: SourceEditorConfiguration(
                appearance: .init(
                    theme: theme,
                    useThemeBackground: true,
                    font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                    wrapLines: true
                ),
                behavior: .init(
                    isEditable: true,
                    indentOption: .spaces(count: jsonIndentSpaces)
                ),
                peripherals: .init(
                    showGutter: true,
                    showMinimap: false,
                    showFoldingRibbon: true
                )
            ),
            state: $editorState,
            coordinators: isResponse ? [readOnlyGuard] : []
        )
    }
}
#else
struct SourceEditorView: View {
    @Binding var text: String
    var isEditable: Bool = true
    var isResponse: Bool = false
    var jsonHighlight: Bool = false
    var htmlHighlight: Bool = false

    @Environment(\.colorScheme) private var colorScheme

    private var jsonTheme: JSONHighlightTheme {
        if isResponse {
            return colorScheme == .dark ? .responseDarkSwiftUI : .responseLightSwiftUI
        }
        return colorScheme == .dark ? .darkSwiftUI : .lightSwiftUI
    }

    private var htmlNSTheme: HTMLHighlightNSTheme {
        colorScheme == .dark ? .responseDark : .responseLight
    }

    private var jsonNSTheme: JSONHighlightNSTheme {
        if isResponse {
            return colorScheme == .dark ? .responseDark : .responseLight
        }
        return colorScheme == .dark ? .dark : .light
    }

    var body: some View {
        if isEditable && jsonHighlight {
            HighlightedJsonEditor(text: $text, theme: jsonTheme)
        } else if isEditable {
            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .devTextInput()
        } else if jsonHighlight {
            ReadOnlyAttributedTextView(text: text) { JSONHighlighter.highlightNS($0, theme: jsonNSTheme) }
        } else if htmlHighlight {
            ReadOnlyAttributedTextView(text: text) { HTMLHighlighter.highlightNS($0, theme: htmlNSTheme) }
        } else {
            ScrollView {
                Text(text)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }
}
#endif
