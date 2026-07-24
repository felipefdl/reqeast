//
//  ImportSheet.swift
//  Reqeast
//

import SwiftUI

struct ImportSheet: View {
    var store: ProjectStore
    var result: ImportResult
    var onImported: (Project) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var importCredentials = true
    @State private var importSecrets = true
    @State private var folderStrategy: ImportFolderStrategy = .mergeByName

    private var document: ExportDocument { result.document }
    private var hasCredentials: Bool { document.requests.contains { $0.credentials != nil } }
    private var hasSecrets: Bool { document.environments.contains { $0.includesSecrets } }
    private var hasFolders: Bool { !document.requestFolders.isEmpty }

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
                Text("Import Project").font(.headline)
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
                Button("Import Project") { performImport() }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(width: 440, height: 480)
    }
    #endif

    // MARK: - iOS

    #if !os(macOS)
    private var iOSBody: some View {
        NavigationStack {
            Form {
                sheetContent
            }
            .navigationTitle("Import Project")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") { performImport() }
                }
            }
        }
    }
    #endif

    // MARK: - Content

    @ViewBuilder
    private var sheetContent: some View {
        fileInfoSection
        versionWarning
        requestPreview
        optionsSection
    }

    @ViewBuilder
    private var fileInfoSection: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.fill")
                .font(.title2)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(document.project.name).font(.headline)
                Text(result.fileName).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var versionWarning: some View {
        if document.version > ExportDocument.currentVersion {
            Label(
                "This file was created with a newer version of Reqeast. Some data may not import correctly.",
                systemImage: "exclamationmark.triangle.fill"
            )
            .font(.caption)
            .foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private var requestPreview: some View {
        if !document.requests.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Requests (\(document.requests.count))")
                    .font(.subheadline.weight(.medium))

                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(document.requests.indices, id: \.self) { index in
                            requestPreviewRow(document.requests[index], index: index)
                        }
                    }
                }
                .frame(maxHeight: 180)
            }
        }
    }

    private func requestPreviewRow(_ exported: ExportedRequest, index: Int) -> some View {
        HStack(spacing: 8) {
            requestBadge(exported.request)

            Text(exported.request.name)
                .font(.caption)
                .lineLimit(1)

            Spacer()

            if exported.credentials != nil {
                Image(systemName: "key.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.quaternary.opacity(0.3), in: .rect(cornerRadius: 4))
    }

    @ViewBuilder
    private func requestBadge(_ request: Request) -> some View {
        if request.type == .http, let httpData = request.httpData {
            Text(httpData.method.rawLabel)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(httpData.method.color)
        } else {
            Image(systemName: request.type.iconName)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if hasCredentials {
                Toggle("Import credentials", isOn: $importCredentials)
            }

            if hasSecrets {
                Toggle("Import secret values", isOn: $importSecrets)
            }

            if hasFolders {
                Picker("Folder strategy", selection: $folderStrategy) {
                    ForEach(ImportFolderStrategy.allCases, id: \.self) { strategy in
                        Text(strategy.localizedName).tag(strategy)
                    }
                }
                .tint(.primary)
            }
        }
    }

    private func performImport() {
        let imported = ImportExportService.performImport(
            document: document,
            store: store,
            importCredentials: importCredentials && hasCredentials,
            importSecrets: importSecrets,
            folderStrategy: folderStrategy
        )
        dismiss()
        onImported(imported)
    }
}
