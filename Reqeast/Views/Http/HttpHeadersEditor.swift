//
//  HttpHeadersEditor.swift
//  Reqeast
//

import SwiftUI

struct HttpHeadersEditor: View {
    @Binding var entries: [KeyValueEntry]
    var autoHeaders: [KeyValueEntry] = []
    @Binding var disabledAutoHeaders: Set<String>
    @State private var bulkEdit = false
    @State private var showAutoHeaders = false
    @FocusState private var focusedField: HeaderField?

    private enum HeaderField: Hashable {
        case key(UUID)
        case value(UUID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Headers")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                let totalCount = entries.filter({ !$0.isEmpty }).count + autoHeaders.count
                if totalCount > 0 {
                    Text("(\(totalCount))")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                if !autoHeaders.isEmpty {
                    Button {
                        showAutoHeaders.toggle()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: showAutoHeaders ? "eye.slash" : "eye")
                            Text(showAutoHeaders
                                ? String(localized: "Hide auto-generated headers")
                                : String(localized: "Show auto-generated headers"))
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

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

            if showAutoHeaders && !autoHeaders.isEmpty {
                autoHeadersSection
            }

            if bulkEdit {
                BulkEditView(entries: $entries)
            } else {
                ForEach($entries) { $entry in
                    headerRow($entry)
                }
            }
        }
        .onAppear { ensureEmptyRow() }
        .onChange(of: entries) { _, _ in ensureEmptyRow() }
    }

    private func headerRow(_ entry: Binding<KeyValueEntry>) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                #if os(macOS)
                Toggle("", isOn: entry.enabled)
                    .labelsHidden()
                    .toggleStyle(.checkbox)
                #else
                CompactCheckboxToggle(isOn: entry.enabled)
                #endif

                TextField("Header Name", text: entry.key.strippingNewlines())
                    .textFieldStyle(.roundedBorder)
                    .devTextInput()
                    .focused($focusedField, equals: .key(entry.wrappedValue.id))
                    #if os(macOS)
                    .textInputSuggestions {
                        ForEach(
                            HttpHeaderSuggestions.filterHeaders(matching: entry.wrappedValue.key),
                            id: \.name
                        ) { header in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(header.name)
                                    .font(.system(.body, design: .monospaced))
                                Text(header.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .textInputCompletion(header.name)
                        }
                    }
                    #endif
                    .onChange(of: entry.wrappedValue.key) { _, newKey in
                        if HttpHeaderSuggestions.isKnownHeader(newKey) {
                            focusedField = .value(entry.wrappedValue.id)
                        }
                    }

                TextField("Value", text: entry.value.strippingNewlines())
                    .textFieldStyle(.roundedBorder)
                    .devTextInput()
                    .focused($focusedField, equals: .value(entry.wrappedValue.id))
                    #if os(macOS)
                    .textInputSuggestions {
                        ForEach(
                            HttpHeaderSuggestions.filterValues(
                                forHeader: entry.wrappedValue.key,
                                matching: entry.wrappedValue.value
                            ),
                            id: \.self
                        ) { value in
                            Text(value)
                                .font(.system(.body, design: .monospaced))
                                .textInputCompletion(value)
                        }
                    }
                    #endif

                Button {
                    entries.removeAll { $0.id == entry.wrappedValue.id }
                    ensureEmptyRow()
                } label: {
                    Image(systemName: "minus.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(entries.count == 1 && entry.wrappedValue.isEmpty)
            }

            #if !os(macOS)
            headerSuggestions(for: entry)
            #endif
        }
    }

    #if !os(macOS)
    @ViewBuilder
    private func headerSuggestions(for entry: Binding<KeyValueEntry>) -> some View {
        let entryId = entry.wrappedValue.id
        if focusedField == .key(entryId) {
            let suggestions = HttpHeaderSuggestions.filterHeaders(matching: entry.wrappedValue.key)
            if !suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(suggestions, id: \.name) { header in
                            Button {
                                entry.wrappedValue.key = header.name
                                focusedField = .value(entryId)
                            } label: {
                                Text(header.name)
                                    .font(.system(.caption, design: .monospaced))
                            }
                            .buttonStyle(.glass)
                            .controlSize(.small)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        } else if focusedField == .value(entryId) {
            let suggestions = HttpHeaderSuggestions.filterValues(
                forHeader: entry.wrappedValue.key,
                matching: entry.wrappedValue.value
            )
            if !suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(suggestions, id: \.self) { value in
                            Button {
                                entry.wrappedValue.value = value
                                focusedField = nil
                            } label: {
                                Text(value)
                                    .font(.system(.caption, design: .monospaced))
                            }
                            .buttonStyle(.glass)
                            .controlSize(.small)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }
    #endif

    private var autoHeadersSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(autoHeaders) { header in
                let isEnabled = !disabledAutoHeaders.contains(header.key)
                HStack(spacing: 8) {
                    #if os(macOS)
                    Toggle("", isOn: Binding(
                        get: { isEnabled },
                        set: { enabled in
                            if enabled {
                                disabledAutoHeaders.remove(header.key)
                            } else {
                                disabledAutoHeaders.insert(header.key)
                            }
                        }
                    ))
                    .labelsHidden()
                    .toggleStyle(.checkbox)
                    #else
                    CompactCheckboxToggle(isOn: Binding(
                        get: { isEnabled },
                        set: { enabled in
                            if enabled {
                                disabledAutoHeaders.remove(header.key)
                            } else {
                                disabledAutoHeaders.insert(header.key)
                            }
                        }
                    ))
                    #endif

                    Text(header.key)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(isEnabled ? .secondary : .tertiary)
                        .frame(minWidth: 120, alignment: .leading)

                    Text(header.value)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .padding(.vertical, 2)
            }
            Divider()
                .padding(.vertical, 4)
        }
    }

    private func ensureEmptyRow() {
        if entries.isEmpty || !entries.last!.isEmpty {
            entries.append(KeyValueEntry())
        }
    }
}
