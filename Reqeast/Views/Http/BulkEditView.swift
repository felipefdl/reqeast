//
//  BulkEditView.swift
//  Reqeast
//

import SwiftUI

struct BulkEditView: View {
    @Binding var entries: [KeyValueEntry]
    @State private var bulkText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("One entry per line, format: key:value")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextEditor(text: $bulkText)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: 120)
                .background(.fill.tertiary, in: .rect(cornerRadius: 8))
                .devTextInput()
        }
        .onAppear { bulkText = entriesToText(entries) }
        .onChange(of: bulkText) { _, newText in
            entries = textToEntries(newText)
        }
    }

    private func entriesToText(_ entries: [KeyValueEntry]) -> String {
        entries
            .filter { !$0.isEmpty }
            .map { entry in
                let prefix = entry.enabled ? "" : "// "
                return "\(prefix)\(entry.key):\(entry.value)"
            }
            .joined(separator: "\n")
    }

    private func textToEntries(_ text: String) -> [KeyValueEntry] {
        var result = text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .compactMap { line -> KeyValueEntry? in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { return nil }

                var enabled = true
                var content = trimmed
                if content.hasPrefix("// ") {
                    enabled = false
                    content = String(content.dropFirst(3))
                }

                guard let colonIndex = content.firstIndex(of: ":") else {
                    return KeyValueEntry(key: content, value: "", enabled: enabled)
                }

                let key = String(content[content.startIndex..<colonIndex])
                let value = String(content[content.index(after: colonIndex)...])
                return KeyValueEntry(key: key, value: value, enabled: enabled)
            }
        result.append(KeyValueEntry())
        return result
    }
}
