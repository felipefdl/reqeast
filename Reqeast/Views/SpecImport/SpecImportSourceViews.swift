//
//  SpecImportSourceViews.swift
//  Reqeast
//

import SwiftUI

struct SpecImportSourcePickView: View {
    @Binding var sourceTab: SpecImportSourceTab
    @Binding var urlText: String
    @Binding var pasteText: String
    var onChooseFile: () -> Void
    var onChooseFolder: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SpecImportSourceTabBar(selection: $sourceTab)

            Group {
                switch sourceTab {
                case .file:
                    SpecImportFileSourceView(
                        onChooseFile: onChooseFile,
                        onChooseFolder: onChooseFolder
                    )
                case .url:
                    SpecImportURLSourceView(urlText: $urlText)
                case .paste:
                    SpecImportPasteSourceView(pasteText: $pasteText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct SpecImportFileSourceView: View {
    var onChooseFile: () -> Void
    var onChooseFolder: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Import an OpenAPI spec or Postman collection from a file on your device.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button(action: onChooseFile) {
                Label("Choose File", systemImage: "doc")
            }
            .buttonStyle(.glass)
            .accessibilityLabel("Choose spec file")
            .accessibilityIdentifier(SpecImportAccessibility.chooseFileButton)

            Button(action: onChooseFolder) {
                Label("Choose Folder", systemImage: "folder")
            }
            .buttonStyle(.glass)
            .accessibilityLabel("Choose spec bundle folder")
            .accessibilityIdentifier(SpecImportAccessibility.chooseFolderButton)

            Text("Supported formats: OpenAPI (YAML, YML, JSON), Postman Collection (JSON). Choose a folder for multi-file OpenAPI bundles with local $ref files, or a folder with multiple independent *.openapi.json specs.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}

struct SpecImportURLSourceView: View {
    @Binding var urlText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Fetch a spec over HTTPS. The import is a one-time snapshot.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TextField("https://example.com/openapi.yaml", text: $urlText)
                #if os(macOS)
                .textFieldStyle(.roundedBorder)
                #endif
                .devTextInput()
                .accessibilityLabel("Spec URL")
                .accessibilityIdentifier(SpecImportAccessibility.urlField)

            Text("Only HTTPS URLs are supported. Maximum download size is 5 MiB.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}

struct SpecImportPasteSourceView: View {
    @Binding var pasteText: String

    private var byteCount: Int {
        pasteText.utf8.count
    }

    private var isOverLimit: Bool {
        byteCount > SpecImportHelpers.maxBytes
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Paste OpenAPI YAML/JSON or Postman Collection JSON directly.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TextEditor(text: $pasteText)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 160)
                #if os(macOS)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: 8))
                #endif
                .accessibilityLabel("Paste spec content")
                .accessibilityIdentifier(SpecImportAccessibility.pasteEditor)

            HStack {
                Text(SpecImportHelpers.byteCountLabel(byteCount))
                    .font(.caption)
                    .foregroundStyle(isOverLimit ? .red : .secondary)
                    .accessibilityLabel(SpecImportHelpers.byteCountLabel(byteCount))
                    .accessibilityIdentifier(SpecImportAccessibility.pasteByteCount)
                Spacer()
            }
        }
    }
}