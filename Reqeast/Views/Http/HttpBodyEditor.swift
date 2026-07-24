//
//  HttpBodyEditor.swift
//  Reqeast
//

import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import CodeEditLanguages
#endif

struct HttpBodyEditor: View {
    @Binding var bodyType: HttpBodyType
    @Binding var bodyContent: String
    @Binding var bodyFormData: [KeyValueEntry]
    @Binding var bodyFormDataEntries: [FormDataEntry]
    @Binding var rawContentType: HttpRawContentType?
    @Binding var binaryFileName: String
    var onBinaryFileSelected: ((Data) -> Void)?
    var onFormDataFileSelected: ((UUID, Data) -> Void)?

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var showingFilePicker = false
    @State private var editorRefreshId = 0
    @State private var lastEditorContent: String?

    private var editorContentProxy: Binding<String> {
        Binding(
            get: { bodyContent },
            set: { newValue in
                lastEditorContent = newValue
                bodyContent = newValue
            }
        )
    }

    var body: some View {
        VStack(spacing: 12) {
            bodyTypePicker

            switch bodyType {
            case .none:
                ContentUnavailableView {
                    Label("No Body", systemImage: "doc")
                        .foregroundStyle(.secondary)
                } description: {
                    Text("This request has no body")
                }

            case .json:
                jsonEditor

            case .raw:
                rawEditor

            case .urlencoded:
                keyValueEditor(entries: $bodyFormData)

            case .formData:
                formDataEditor

            case .binary:
                binaryEditor
            }
        }
        .onAppear {
            ensureEmptyRows()
            lastEditorContent = bodyContent
        }
        .onChange(of: bodyFormData) { _, _ in ensureEmptyKeyValueRow() }
        .onChange(of: bodyFormDataEntries) { _, _ in ensureEmptyFormDataRow() }
        .onChange(of: bodyContent) { _, newValue in
            if lastEditorContent != newValue {
                lastEditorContent = newValue
                editorRefreshId += 1
            }
        }
        #if os(macOS)
        .focusedSceneValue(\.prettifyBody, canPrettify ? { beautifyJson() } : nil)
        #endif
    }

    @ViewBuilder
    private var bodyTypePicker: some View {
        let picker = Picker("", selection: $bodyType) {
            ForEach(HttpBodyType.allCases, id: \.self) { type in
                Text(type.localizedName).tag(type)
            }
        }
        if horizontalSizeClass == .compact {
            picker.pickerStyle(.menu).tint(.primary)
        } else {
            picker.pickerStyle(.segmented)
        }
    }

    // MARK: - JSON

    private var jsonEditor: some View {
        VStack(spacing: 0) {
            jsonSourceEditor
            jsonValidationBar(bodyContent)
        }
        .clipShape(.rect(cornerRadius: 8))
        .overlay(alignment: .topTrailing) {
            beautifyButton.padding(8)
        }
    }

    #if os(macOS)
    private var jsonSourceEditor: some View {
        SourceEditorView(text: editorContentProxy, language: .json)
            .clipped()
            .id(editorRefreshId)
    }
    #else
    private var jsonSourceEditor: some View {
        SourceEditorView(text: editorContentProxy, jsonHighlight: true)
            .id(editorRefreshId)
    }
    #endif

    // MARK: - Raw

    private var rawEditor: some View {
        VStack(spacing: 0) {
            HStack {
                rawContentTypePicker
                Spacer()
            }
            .padding([.top, .horizontal], 8)

            rawSourceEditor
            if rawContentType == .json {
                jsonValidationBar(bodyContent)
            }
        }
        .clipShape(.rect(cornerRadius: 8))
        .overlay(alignment: .topTrailing) {
            if rawContentType == .json {
                beautifyButton.padding(8)
            }
        }
    }

    #if os(macOS)
    private var rawSourceEditor: some View {
        SourceEditorView(text: editorContentProxy, language: rawCodeLanguage)
            .clipped()
            .id(editorRefreshId)
    }

    private var rawCodeLanguage: CodeLanguage {
        switch rawContentType {
        case .json:        return .json
        case .javascript:  return .javascript
        case .html:        return .html
        case .xml:         return .html
        case .text, .none: return .default
        }
    }
    #else
    private var rawSourceEditor: some View {
        SourceEditorView(text: editorContentProxy)
            .id(editorRefreshId)
    }
    #endif

    private var rawContentTypePicker: some View {
        Picker("", selection: Binding(
            get: { rawContentType ?? .text },
            set: { rawContentType = $0 }
        )) {
            ForEach(HttpRawContentType.allCases, id: \.self) { type in
                Text(type.localizedName).tag(type)
            }
        }
        .pickerStyle(.menu)
        .tint(.primary)
    }

    // MARK: - Key-Value

    private func keyValueEditor(entries: Binding<[KeyValueEntry]>) -> some View {
        ForEach(entries) { $entry in
            HStack(spacing: 8) {
                #if os(macOS)
                Toggle("", isOn: $entry.enabled)
                    .labelsHidden()
                    .toggleStyle(.checkbox)
                #else
                CompactCheckboxToggle(isOn: $entry.enabled)
                #endif

                TextField("Key", text: $entry.key)
                    .textFieldStyle(.roundedBorder)
                    .devTextInput()

                TextField("Value", text: $entry.value)
                    .textFieldStyle(.roundedBorder)
                    .devTextInput()

                Button {
                    bodyFormData.removeAll { $0.id == entry.id }
                    ensureEmptyKeyValueRow()
                } label: {
                    Image(systemName: "minus.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Form Data (multipart)

    private var formDataEditor: some View {
        ForEach($bodyFormDataEntries) { $entry in
            FormDataEntryRow(
                entry: $entry,
                onDelete: {
                    bodyFormDataEntries.removeAll { $0.id == entry.id }
                    ensureEmptyFormDataRow()
                },
                onFileSelected: { data in
                    onFormDataFileSelected?(entry.id, data)
                }
            )
        }
    }

    // MARK: - Binary

    private var binaryEditor: some View {
        VStack(spacing: 12) {
            if binaryFileName.isEmpty {
                Button {
                    showingFilePicker = true
                } label: {
                    Label("Select File", systemImage: "doc.badge.plus")
                }
                .buttonStyle(.glass)
            } else {
                HStack(spacing: 12) {
                    Image(systemName: "doc.fill")
                        .foregroundStyle(.secondary)
                    Text(binaryFileName)
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()

                    Button {
                        showingFilePicker = true
                    } label: {
                        Label("Change", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.glass)

                    Button {
                        binaryFileName = ""
                        onBinaryFileSelected?(Data())
                    } label: {
                        Image(systemName: "xmark.circle")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .fileImporter(isPresented: $showingFilePicker, allowedContentTypes: [.data]) { result in
            if case .success(let url) = result {
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                if let data = try? Data(contentsOf: url) {
                    binaryFileName = url.lastPathComponent
                    onBinaryFileSelected?(data)
                }
            }
        }
    }

    // MARK: - Helpers

    private func ensureEmptyRows() {
        ensureEmptyKeyValueRow()
        ensureEmptyFormDataRow()
    }

    private func ensureEmptyKeyValueRow() {
        if bodyFormData.isEmpty || !bodyFormData.last!.isEmpty {
            bodyFormData.append(KeyValueEntry())
        }
    }

    private func ensureEmptyFormDataRow() {
        if bodyFormDataEntries.isEmpty || !bodyFormDataEntries.last!.isEmpty {
            bodyFormDataEntries.append(FormDataEntry())
        }
    }

    @ViewBuilder
    private func jsonValidationBar(_ text: String) -> some View {
        if let error = JsonBeautifier.validate(text) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(error)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }

    private var beautifyButton: some View {
        Button { beautifyJson() } label: {
            Image(systemName: "curlybraces")
        }
        .buttonStyle(.glass)
        .font(.caption)
        .help("Prettify")
    }

    private var canPrettify: Bool {
        bodyType == .json || (bodyType == .raw && rawContentType == .json)
    }

    private func beautifyJson() {
        guard let result = JsonBeautifier.prettify(bodyContent) else { return }
        lastEditorContent = result
        bodyContent = result
        editorRefreshId += 1
    }
}
