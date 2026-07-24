//
//  HttpParamsEditor.swift
//  Reqeast
//

import SwiftUI

struct HttpParamsEditor: View {
    @Binding var entries: [KeyValueEntry]
    @State private var bulkEdit = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Query Parameters")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    bulkEdit.toggle()
                } label: {
                    Label(
                        bulkEdit ? String(localized: "Key-Value") : String(localized: "Bulk Edit"),
                        systemImage: bulkEdit ? "list.bullet" : "text.alignleft"
                    )
                    .font(.caption)
                }
                .buttonStyle(.glass)
                .controlSize(.small)
            }

            if bulkEdit {
                BulkEditView(entries: $entries)
            } else {
                ForEach($entries) { $entry in
                    HStack(spacing: 8) {
                        #if os(macOS)
                        Toggle("", isOn: $entry.enabled)
                            .labelsHidden()
                            .toggleStyle(.checkbox)
                        #else
                        CompactCheckboxToggle(isOn: $entry.enabled)
                        #endif

                        TextField("Key", text: $entry.key.strippingNewlines())
                            .textFieldStyle(.roundedBorder)
                            .devTextInput()

                        TextField("Value", text: $entry.value.strippingNewlines())
                            .textFieldStyle(.roundedBorder)
                            .devTextInput()

                        Button {
                            entries.removeAll { $0.id == entry.id }
                            ensureEmptyRow()
                        } label: {
                            Image(systemName: "minus.circle")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .disabled(entries.count == 1 && entry.isEmpty)
                    }
                }
            }
        }
        .onAppear { ensureEmptyRow() }
        .onChange(of: entries) { _, _ in ensureEmptyRow() }
    }

    private func ensureEmptyRow() {
        if entries.isEmpty || !entries.last!.isEmpty {
            entries.append(KeyValueEntry())
        }
    }
}
