//
//  CodeSnippetCodeView.swift
//  Reqeast
//

import SwiftUI

struct CodeSnippetCodeView: View {
    let code: String
    let language: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let theme = CodeHighlightTheme(colorScheme: colorScheme)
        let highlighted = CodeHighlighter.highlight(code, language: language, theme: theme)
        ScrollView([.horizontal, .vertical]) {
            Text(highlighted)
                .textSelection(.enabled)
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
