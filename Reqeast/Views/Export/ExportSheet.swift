//
//  ExportSheet.swift
//  Reqeast
//

import SwiftUI
import UniformTypeIdentifiers

struct ExportSheet: View {
    var store: ProjectStore
    var project: Project
    @Environment(\.dismiss) private var dismiss

    @State private var includeCredentials = false
    @State private var includeSecrets = false
    @State private var exportFile: ReqeastExportFile?
    @State private var showingExporter = false
    @State private var exportError: String?

    private var requestCount: Int { store.requests(for: project.id).count }
    private var folderCount: Int { store.requestFolders(for: project.id).count }
    private var environmentCount: Int { store.environments(for: project.id).count }

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
                Text("Export Project").font(.headline)
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
            defaultFilename: "\(project.name).reqeast"
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
            .navigationTitle("Export Project")
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
                defaultFilename: "\(project.name).reqeast"
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
            ProjectIconView(project: project, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(project.name).font(.headline)
                Text(summaryText).font(.caption).foregroundStyle(.secondary)
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
        parts.append("\(requestCount) \(requestCount == 1 ? "request" : "requests")")
        if folderCount > 0 {
            parts.append("\(folderCount) \(folderCount == 1 ? "folder" : "folders")")
        }
        if environmentCount > 0 {
            parts.append("\(environmentCount) \(environmentCount == 1 ? "environment" : "environments")")
        }
        return parts.joined(separator: ", ")
    }

    private func prepareExport() {
        do {
            let data = try ImportExportService.prepareExportData(
                project: project,
                requests: store.requests(for: project.id),
                requestFolders: store.requestFolders(for: project.id),
                environments: store.environments(for: project.id),
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
