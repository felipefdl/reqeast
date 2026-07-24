//
//  MCPSetupGuideView.swift
//  Reqeast
//

#if os(macOS)
import SwiftUI

struct MCPSetupGuideView: View {
    @AppStorage("lastMCPSetupClient") private var selectedClient: MCPClientSetup = .claudeCode
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 500, height: 380)
    }

    private var header: some View {
        HStack {
            Text("MCP Setup Guide").font(.headline)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("AI Client", selection: $selectedClient) {
                ForEach(MCPClientSetup.allCases) { client in
                    Text(client.displayName).tag(client)
                }
            }
            .tint(.primary)

            Text(selectedClient.setupDescription)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            codeBlock
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var codeBlock: some View {
        let theme = CodeHighlightTheme(colorScheme: colorScheme)
        let highlighted = CodeHighlighter.highlight(
            selectedClient.setupSnippet,
            language: selectedClient.highlightLanguage,
            theme: theme
        )

        return ScrollView([.horizontal, .vertical]) {
            Text(highlighted)
                .textSelection(.enabled)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var footer: some View {
        HStack {
            Button("Close") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Spacer()
            copyButton
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @State private var copied = false

    private var copyButton: some View {
        Button {
            PlatformClipboard.copy(selectedClient.setupSnippet)
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(2))
                copied = false
            }
        } label: {
            Label(copied ? "Copied" : "Copy", systemImage: "doc.on.doc")
        }
        .buttonStyle(.glassProminent)
    }
}
#endif
