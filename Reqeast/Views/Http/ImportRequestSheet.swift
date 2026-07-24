//
//  ImportRequestSheet.swift
//  Reqeast
//

import SwiftUI

struct ImportRequestSheet: View {
    let store: ProjectStore
    var request: Request
    @Environment(\.dismiss) private var dismiss

    @State private var inputText = ""
    @State private var detectedFormat: ImportFormat?
    @State private var forcedFormat: ImportFormat?
    @State private var parseError: String?
    @State private var isAiParsing = false
    @State private var debounceTask: Task<Void, Never>?

    private var effectiveFormat: ImportFormat? {
        forcedFormat ?? detectedFormat
    }

    var body: some View {
        #if os(macOS)
        macOSBody
        #else
        iOSBody
        #endif
    }

    // MARK: - macOS

    #if os(macOS)
    private var macOSBody: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Import Request").font(.headline)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            sharedContent
                .padding(16)

            Divider()

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                importButton
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(width: 600, height: 500)
    }
    #endif

    // MARK: - iOS

    #if !os(macOS)
    private var iOSBody: some View {
        NavigationStack {
            sharedContent
                .padding(16)
                .navigationTitle("Import Request")
                .toolbarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        importButton
                    }
                }
        }
    }
    #endif

    // MARK: - Shared Content

    private var sharedContent: some View {
        VStack(spacing: 12) {
            descriptionSection
            if isAiParsing {
                AiProcessingView()
            } else {
                textArea
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            statusBar
        }
    }

    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Paste a command to populate the current request.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                FormatBadge(label: "cURL", isActive: effectiveFormat == .curl) {
                    toggleForced(.curl)
                }
                FormatBadge(label: "wget", isActive: effectiveFormat == .wget) {
                    toggleForced(.wget)
                }
                FormatBadge(label: "HTTPie", isActive: effectiveFormat == .httpie) {
                    toggleForced(.httpie)
                }
                AiOrbBadge(
                    isActive: effectiveFormat == .appleIntelligence,
                    isDisabled: !AiImportParser.isAvailable
                ) {
                    toggleForced(.appleIntelligence)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func toggleForced(_ format: ImportFormat) {
        if forcedFormat == format {
            forcedFormat = nil
        } else {
            forcedFormat = format
        }
        parseError = nil
    }

    @ViewBuilder
    private var statusBar: some View {
        if let error = parseError {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.subheadline)
                .lineLimit(2)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .background(.ultraThinMaterial, in: .rect(cornerRadius: 8))
                .padding(8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.default, value: parseError)
        }
    }

    private var textArea: some View {
        TextEditor(text: $inputText)
            .font(.system(.body, design: .monospaced))
            .scrollContentBackground(.hidden)
            .padding(8)
            .background(.fill.tertiary, in: .rect(cornerRadius: 8))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .devTextInput()
            .onChange(of: inputText) {
                debounceTask?.cancel()
                debounceTask = Task {
                    try? await Task.sleep(for: .milliseconds(200))
                    guard !Task.isCancelled else { return }
                    detectFormat()
                }
            }
    }

    private var importButton: some View {
        Button("Import") { performImport() }
            .buttonStyle(.glassProminent)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAiParsing)
    }

    // MARK: - Actions

    private func detectFormat() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            detectedFormat = nil
            parseError = nil
            return
        }
        let builtin = ImportRequestService.detectFormat(trimmed)
        if let builtin {
            detectedFormat = builtin
        } else if AiImportParser.isAvailable {
            detectedFormat = .appleIntelligence
        } else {
            detectedFormat = nil
        }
        if forcedFormat == nil {
            parseError = nil
        }
    }

    private func performImport() {
        let format = effectiveFormat
        if format == .appleIntelligence {
            performAiImport()
        } else {
            performBuiltInImport()
        }
    }

    private func performBuiltInImport() {
        do {
            let result = try ImportRequestService.parse(inputText)
            let httpData = ImportRequestMapper.map(result.data)
            var updatedRequest = request
            updatedRequest.httpData = httpData
            store.updateRequest(updatedRequest)
            if !result.cookies.isEmpty {
                CookieStore.shared.addCookiesFromImport(result.cookies, url: result.data.url)
            }
            dismiss()
        } catch {
            parseError = error.localizedDescription
        }
    }

    private func performAiImport() {
        let input = inputText
        isAiParsing = true
        parseError = nil
        Task {
            do {
                let imported = try await AiImportParser.parse(input)
                let httpData = ImportRequestMapper.map(imported)
                var updatedRequest = request
                updatedRequest.httpData = httpData
                store.updateRequest(updatedRequest)
                isAiParsing = false
                dismiss()
            } catch {
                isAiParsing = false
                parseError = error.localizedDescription
            }
        }
    }
}

// MARK: - Format Badge

private struct FormatBadge: View {
    let label: String
    let isActive: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(label)
                .font(.caption)
                .fontWeight(.medium)
                .fontDesign(.monospaced)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(isActive ? AnyShapeStyle(.tint) : AnyShapeStyle(.fill.quaternary), in: .capsule)
        }
        .buttonStyle(.plain)
    }
}
