//
//  ExportAllSheet.swift
//  Reqeast
//

import SwiftUI
import UniformTypeIdentifiers

struct ExportAllSheet: View {
    var store: ProjectStore
    @Environment(\.dismiss) private var dismiss

    @State private var includeCredentials = false
    @State private var includeSecrets = false
    @State private var exportFile: ReqeastExportFile?
    @State private var showingExporter = false
    @State private var exportError: String?

    private var projectCount: Int { store.projects.filter { $0.deletedAt == nil }.count }

    private var totalRequestCount: Int {
        store.projects.filter { $0.deletedAt == nil }.reduce(0) { $0 + store.requests(for: $1.id).count }
    }

    private var totalEnvironmentCount: Int {
        store.projects.filter { $0.deletedAt == nil }.reduce(0) { $0 + store.environments(for: $1.id).count }
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
                Text("Export All Projects").font(.headline)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    sheetContent
                }
                .padding(16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Export...") { prepareExport() }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(width: 420, height: 380)
        .fileExporter(
            isPresented: $showingExporter,
            document: exportFile,
            contentType: .reqeastExport,
            defaultFilename: "reqeast-projects.reqeast"
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
            .navigationTitle("Export All Projects")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Export...") { prepareExport() }
                }
            }
            .fileExporter(
                isPresented: $showingExporter,
                document: exportFile,
                contentType: .reqeastExport,
                defaultFilename: "reqeast-projects.reqeast"
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
        HStack(spacing: 12) {
            Image(systemName: "shippingbox")
                .font(.title2)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(projectCount) \(projectCount == 1 ? "project" : "projects")")
                    .font(.headline)
                Text(summaryText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        if let exportError {
            Text(exportError)
                .font(.caption)
                .foregroundStyle(.red)
        }

        Toggle("Include credentials", isOn: $includeCredentials)

        if includeCredentials {
            Text("Credentials will be stored in plain text. Share this file carefully.")
                .font(.caption)
                .foregroundStyle(.orange)
        }

        Toggle("Include secret environment values", isOn: $includeSecrets)

        if includeSecrets {
            Text("Secret values will be stored in plain text. Share this file carefully.")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    private var summaryText: String {
        var parts: [String] = []
        parts.append("\(totalRequestCount) \(totalRequestCount == 1 ? "request" : "requests")")
        if totalEnvironmentCount > 0 {
            parts.append("\(totalEnvironmentCount) \(totalEnvironmentCount == 1 ? "environment" : "environments")")
        }
        return parts.joined(separator: ", ")
    }

    private func prepareExport() {
        do {
            let data = try ImportExportService.prepareExportAllData(
                store: store,
                includeCredentials: includeCredentials,
                includeSecrets: includeSecrets
            )
            exportFile = ReqeastExportFile(data: data)
            showingExporter = true
        } catch {
            exportError = error.localizedDescription
        }
    }
}
