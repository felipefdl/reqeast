//
//  ExportSpecSheet.swift
//  Reqeast
//

import SwiftUI
import UniformTypeIdentifiers

struct ExportSpecSheet: View {
    var store: ProjectStore
    let project: Project
    let initialKind: SpecExportKind

    @Environment(\.dismiss) private var dismiss

    @State private var kind: SpecExportKind
    @State private var options = SpecExportOptions.default
    @State private var exportFile: SpecExportFile?
    @State private var showingExporter = false
    @State private var exportError: String?
    @State private var isExporting = false
    @State private var exportReviewContext: SpecExportReviewContext?

    init(store: ProjectStore, project: Project, kind: SpecExportKind) {
        self.store = store
        self.project = project
        self.initialKind = kind
        _kind = State(initialValue: kind)
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
                Text(String(localized: "Export Spec")).font(.headline)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            ScrollView {
                sheetContent
                    .padding(16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            footerButtons
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
        }
        .frame(width: 420, height: 400)
        .sheet(item: $exportReviewContext) { review in
            SpecExportReviewSheet(
                store: store,
                project: project,
                review: review,
                onExportReady: { data in
                    exportFile = SpecExportFile(data: data)
                    showingExporter = true
                }
            )
        }
        .fileExporter(
            isPresented: $showingExporter,
            document: exportFile,
            contentType: SpecExportHelpers.contentType(for: kind, options: options),
            defaultFilename: SpecExportService.defaultFilename(for: project, kind: kind, options: options)
        ) { result in
            if case .success = result {
                dismiss()
            }
        }
    }
    #endif

    // MARK: - iOS

    #if !os(macOS)
    private var iOSBody: some View {
        NavigationStack {
            Form {
                Section { sheetContent }
            }
            .navigationTitle(String(localized: "Export Spec"))
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isExporting)
                        .accessibilityIdentifier(SpecExportAccessibility.sheetCancelButton)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Export...") { prepareExport() }
                        .disabled(isExporting)
                        .accessibilityIdentifier(SpecExportAccessibility.sheetExportButton)
                }
            }
            .sheet(item: $exportReviewContext) { review in
                SpecExportReviewSheet(
                    store: store,
                    project: project,
                    review: review,
                    onExportReady: { data in
                        exportFile = SpecExportFile(data: data)
                        showingExporter = true
                    }
                )
            }
            .fileExporter(
                isPresented: $showingExporter,
                document: exportFile,
                contentType: SpecExportHelpers.contentType(for: kind, options: options),
                defaultFilename: SpecExportService.defaultFilename(for: project, kind: kind, options: options)
            ) { result in
                if case .success = result {
                    dismiss()
                }
            }
        }
    }
    #endif

    // MARK: - Content

    @ViewBuilder
    private var sheetContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                ProjectIconView(project: project, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(project.name).font(.headline)
                    Text(SpecExportHelpers.summaryText(store: store, project: project, kind: kind))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Picker(String(localized: "Export format"), selection: $kind) {
                Text("OpenAPI").tag(SpecExportKind.openapi)
                Text(String(localized: "Postman Collection")).tag(SpecExportKind.postman)
            }
            .pickerStyle(.segmented)

            if kind == .openapi {
                Picker(String(localized: "OpenAPI format"), selection: $options.openApiFormat) {
                    ForEach(SpecExportOpenApiFormat.allCases, id: \.self) { format in
                        Text(format.localizedName).tag(format)
                    }
                }
                .tint(.primary)
            }

            Toggle(String(localized: "Include environments"), isOn: $options.includeEnvironments)

            Toggle(
                String(localized: "Include deprecated and stale operations"),
                isOn: $options.includeDeprecatedAndStale
            )

            if let exportError {
                Text(exportError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
        }
    }

    #if os(macOS)
    private var footerButtons: some View {
        HStack {
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
                .disabled(isExporting)
                .accessibilityIdentifier(SpecExportAccessibility.sheetCancelButton)

            Spacer()

            Button("Export...") { prepareExport() }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(isExporting)
                .accessibilityIdentifier(SpecExportAccessibility.sheetExportButton)
        }
    }
    #endif

    private func prepareExport() {
        exportError = nil
        isExporting = true

        Task {
            do {
                if let review = try await SpecExportService.buildExportReviewContext(
                    project: project,
                    store: store,
                    kind: kind,
                    options: options
                ) {
                    await MainActor.run {
                        exportReviewContext = review
                        isExporting = false
                    }
                } else {
                    let data = try await SpecExportService.exportData(
                        project: project,
                        store: store,
                        kind: kind,
                        options: options
                    )
                    await MainActor.run {
                        #if DEBUG
                        if SpecExportUITestSupport.isEnabled,
                           kind == .openapi,
                           let yaml = String(data: data, encoding: .utf8) {
                            SpecExportUITestSupport.recordExport(yaml)
                            isExporting = false
                            dismiss()
                            return
                        }
                        #endif
                        exportFile = SpecExportFile(data: data)
                        showingExporter = true
                        isExporting = false
                    }
                }
            } catch {
                await MainActor.run {
                    exportError = error.localizedDescription
                    isExporting = false
                }
            }
        }
    }
}