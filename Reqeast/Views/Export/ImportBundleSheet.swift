//
//  ImportBundleSheet.swift
//  Reqeast
//

import SwiftUI

struct ImportBundleSheet: View {
    var store: ProjectStore
    var result: ImportBundleResult
    var onImported: ([Project]) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var importCredentials = true
    @State private var importSecrets = true
    @State private var folderStrategy: ImportFolderStrategy = .createNew

    private var bundle: ExportBundle { result.bundle }

    private var hasCredentials: Bool {
        bundle.projects.contains { doc in
            doc.requests.contains { $0.credentials != nil }
        }
    }

    private var hasSecrets: Bool {
        bundle.projects.contains { doc in
            doc.environments.contains { $0.includesSecrets }
        }
    }

    private var hasFolders: Bool {
        bundle.projects.contains { !$0.requestFolders.isEmpty }
    }

    private var totalRequestCount: Int {
        bundle.projects.reduce(0) { $0 + $1.requests.count }
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
                Text("Import Projects").font(.headline)
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
                Button("Import All") { performImport() }
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
            .navigationTitle("Import Projects")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import All") { performImport() }
                }
            }
        }
    }
    #endif

    // MARK: - Content

    @ViewBuilder
    private var sheetContent: some View {
        bundleInfoSection
        versionWarning
        projectList
        optionsSection
    }

    @ViewBuilder
    private var bundleInfoSection: some View {
        HStack(spacing: 12) {
            Image(systemName: "shippingbox")
                .font(.title2)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(bundle.projects.count) \(bundle.projects.count == 1 ? "project" : "projects")")
                    .font(.headline)
                Text("\(totalRequestCount) \(totalRequestCount == 1 ? "request" : "requests") total")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var versionWarning: some View {
        if bundle.version > ExportBundle.currentVersion {
            Label(
                "This file was created with a newer version of Reqeast. Some data may not import correctly.",
                systemImage: "exclamationmark.triangle.fill"
            )
            .font(.caption)
            .foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private var projectList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Projects")
                .font(.subheadline.weight(.medium))

            ScrollView {
                VStack(spacing: 4) {
                    ForEach(bundle.projects.indices, id: \.self) { index in
                        let doc = bundle.projects[index]
                        HStack(spacing: 8) {
                            if let emoji = doc.project.emoji {
                                Text(emoji)
                                    .font(.caption)
                            } else {
                                Image(systemName: "folder.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            Text(doc.project.name)
                                .font(.caption)
                                .lineLimit(1)

                            Spacer()

                            Text("\(doc.requests.count)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.quaternary.opacity(0.3), in: .rect(cornerRadius: 4))
                    }
                }
            }
            .frame(maxHeight: 160)
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
        let imported = ImportExportService.performBundleImport(
            bundle: bundle,
            store: store,
            importCredentials: importCredentials && hasCredentials,
            importSecrets: importSecrets,
            folderStrategy: folderStrategy
        )
        dismiss()
        onImported(imported)
    }
}
