//
//  FormDataEntryRow.swift
//  Reqeast
//

import SwiftUI
import UniformTypeIdentifiers

struct FormDataEntryRow: View {
    @Binding var entry: FormDataEntry
    var onDelete: () -> Void
    var onFileSelected: ((Data) -> Void)?

    @State private var showingFilePicker = false

    var body: some View {
        HStack(spacing: 8) {
            #if os(macOS)
            Toggle("", isOn: $entry.enabled)
                .labelsHidden()
                .toggleStyle(.checkbox)
            #else
            CompactCheckboxToggle(isOn: $entry.enabled)
            #endif

            Picker("", selection: $entry.fieldType) {
                Text("Text").tag(FormDataFieldType.text)
                Text("File").tag(FormDataFieldType.file)
            }
            .pickerStyle(.menu)
            .tint(.primary)
            .fixedSize()

            TextField("Key", text: $entry.key)
                .textFieldStyle(.roundedBorder)
                .devTextInput()

            if entry.fieldType == .file {
                fileValueField
            } else {
                TextField("Value", text: $entry.value)
                    .textFieldStyle(.roundedBorder)
                    .devTextInput()
            }

            Button(action: onDelete) {
                Image(systemName: "minus.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    private var fileValueField: some View {
        HStack(spacing: 4) {
            if entry.fileName.isEmpty {
                Button {
                    showingFilePicker = true
                } label: {
                    Label("Select File", systemImage: "doc.badge.plus")
                        .font(.caption)
                }
                .buttonStyle(.glass)
            } else {
                Image(systemName: "doc.fill")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                Text(entry.fileName)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Button {
                    showingFilePicker = true
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }
        }
        .fileImporter(isPresented: $showingFilePicker, allowedContentTypes: [.data]) { result in
            if case .success(let url) = result {
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                if let data = try? Data(contentsOf: url) {
                    entry.fileName = url.lastPathComponent
                    entry.mimeType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
                    onFileSelected?(data)
                }
            }
        }
    }
}
