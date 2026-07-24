//
//  SpecImportPreviewView.swift
//  Reqeast
//

import SwiftUI

struct SpecImportPreviewView: View {
    let preview: SpecImportPreview
    @Bindable var store: ProjectStore
    @Binding var projectName: String
    @Binding var options: SpecImportOptions
    @Binding var importTarget: SpecImportTarget
    @Binding var targetProjectId: UUID?
    var preferredTargetProjectId: UUID?
    var urlSnapshotDate: Date?
    var isRefreshing: Bool = false

    private var folders: [RequestFolder] {
        preview.mapped.folders.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var mergePreview: SpecImportMergePreview? {
        guard importTarget == .existingProject, let targetProjectId else { return nil }
        return SpecImportService.mergePreview(
            preview: preview,
            in: store,
            targetProjectId: targetProjectId
        )
    }

    private var displayedWarnings: [SpecWarning] {
        preview.warnings + (mergePreview?.duplicateWarnings ?? [])
    }

    private var displayedOperationCount: Int {
        mergePreview?.importableOperationCount ?? preview.operationCount
    }

    private var selectedProjectName: String? {
        guard let targetProjectId else { return nil }
        return store.projects.first(where: { $0.id == targetProjectId })?.name
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if preview.source == .url {
                urlSnapshotDisclaimer
            }

            formatSection

            SpecImportTargetSection(
                store: store,
                importTarget: $importTarget,
                targetProjectId: $targetProjectId,
                preferredTargetProjectId: preferredTargetProjectId
            )

            if importTarget == .newProject {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Project name")
                        .font(.subheadline.weight(.medium))
                    TextField("Project name", text: $projectName)
                        #if os(macOS)
                        .textFieldStyle(.roundedBorder)
                        #endif
                        .devTextInput()
                        .accessibilityLabel("Project name")
                        .accessibilityIdentifier(SpecImportAccessibility.projectNameField)
                }
            } else if let selectedProjectName {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Import into")
                        .font(.subheadline.weight(.medium))
                    Label(selectedProjectName, systemImage: "folder")
                        .font(.subheadline)
                        .accessibilityLabel("Import into \(selectedProjectName)")
                }
            }

            HStack(spacing: 6) {
                Image(systemName: "arrow.down.doc")
                Text(SpecImportHelpers.operationCountLabel(displayedOperationCount))
            }
            .font(.subheadline.weight(.medium))
            .accessibilityElement(children: .combine)
            .accessibilityLabel(SpecImportHelpers.operationCountLabel(displayedOperationCount))
            .accessibilityIdentifier(SpecImportAccessibility.operationCount)

            folderSampleSection

            if !displayedWarnings.isEmpty {
                warningsSection
            }

            SpecImportAdvancedOptionsView(
                options: $options,
                isDisabled: isRefreshing
            )

            if isRefreshing {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Updating preview…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var formatSection: some View {
        Label {
            Text(SpecImportHelpers.formatLabel(preview.format))
                .font(.subheadline.weight(.medium))
        } icon: {
            Image(systemName: SpecImportHelpers.formatSystemImage(preview.format))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Detected format, \(SpecImportHelpers.formatLabel(preview.format))")
        .accessibilityIdentifier(SpecImportAccessibility.detectedFormat)
    }

    @ViewBuilder
    private var urlSnapshotDisclaimer: some View {
        if let urlString = preview.sourceURL,
           let host = URL(string: urlString)?.host {
            if options.linkToSpec == .linked {
                Label {
                    Text("Linked to \(host). Use Check for updates to sync changes from the live spec.")
                        .font(.caption)
                } icon: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
                .foregroundStyle(.secondary)
                .accessibilityIdentifier(SpecImportAccessibility.urlLinkedDisclaimer)
            } else {
                let timestamp = urlSnapshotDate ?? Date()
                Label {
                    Text("Snapshot from \(host) at \(timestamp.formatted(date: .abbreviated, time: .shortened)). Changes to the spec won't appear automatically.")
                        .font(.caption)
                } icon: {
                    Image(systemName: "clock.arrow.circlepath")
                }
                .foregroundStyle(.secondary)
                .accessibilityIdentifier(SpecImportAccessibility.urlSnapshotDisclaimer)
            }
        }
    }

    @ViewBuilder
    private var folderSampleSection: some View {
        if !folders.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Folders (\(folders.count))")
                    .font(.subheadline.weight(.medium))
                    .accessibilityLabel("Folders, \(folders.count)")
                    .accessibilityIdentifier(SpecImportAccessibility.folderCount)

                VStack(alignment: .leading, spacing: 4) {
                    ForEach(folders.prefix(5)) { folder in
                        Label(folder.name, systemImage: "folder")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    let remaining = folders.count - 5
                    if remaining > 0 {
                        Text("and \(remaining) more")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var warningsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(
                "\(displayedWarnings.count) warnings",
                systemImage: "exclamationmark.triangle.fill"
            )
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(displayedWarnings.prefix(5).enumerated()), id: \.offset) { _, warning in
                    Text(warning.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                let remaining = displayedWarnings.count - 5
                if remaining > 0 {
                    Text("and \(remaining) more warnings")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}