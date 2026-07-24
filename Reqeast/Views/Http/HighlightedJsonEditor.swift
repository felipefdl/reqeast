//
//  HighlightedJsonEditor.swift
//  Reqeast
//

#if !os(macOS)
import SwiftUI

struct HighlightedJsonEditor: View {
    @Binding var text: String
    let theme: JSONHighlightTheme

    @State private var attributedText: AttributedString = AttributedString()
    @State private var selection = AttributedTextSelection()
    @State private var isUpdatingFromPlainText = false
    @State private var highlightVersion = 0

    var body: some View {
        TextEditor(text: $attributedText, selection: $selection)
            .font(.system(.body, design: .monospaced))
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .keyboardType(.asciiCapable)
            .devTextInput()
            .onAppear {
                attributedText = JSONHighlighter.highlight(text, theme: theme)
            }
            .onChange(of: attributedText) {
                let plain = String(attributedText.characters)
                guard plain != text else { return }
                isUpdatingFromPlainText = true
                text = plain
                isUpdatingFromPlainText = false
                highlightVersion &+= 1
            }
            .onChange(of: text) {
                guard !isUpdatingFromPlainText else { return }
                attributedText = JSONHighlighter.highlight(text, theme: theme)
            }
            .task(id: highlightVersion) {
                // Debounce re-highlight during typing bursts. Cancels if the user keeps typing.
                try? await Task.sleep(for: .milliseconds(120))
                guard !Task.isCancelled else { return }
                let snapshot = String(attributedText.characters)
                guard snapshot == text else { return }
                let new = JSONHighlighter.highlight(snapshot, theme: theme)
                guard String(new.characters) == snapshot else { return }
                isUpdatingFromPlainText = true
                attributedText = new
                isUpdatingFromPlainText = false
            }
    }
}
#endif
