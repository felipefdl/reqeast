//
//  SpecImportBatchPreviewView.swift
//  Reqeast
//

import SwiftUI

struct SpecImportBatchPreviewView: View {
    let batch: SpecImportBatchPreview
    @Binding var projectName: String
    @Binding var environmentName: String
    @Binding var environmentBindings: [SpecImportEnvironmentBinding]
    @Binding var groupSpecsInOneProject: Bool
    @Binding var options: SpecImportOptions
    var isRefreshing: Bool = false

    private var sortedItems: [SpecImportPreview] {
        batch.items.sorted {
            SpecImportHelpers.sourceFileName(for: $0.sourceURL)
                .localizedStandardCompare(SpecImportHelpers.sourceFileName(for: $1.sourceURL)) == .orderedAscending
        }
    }

    private var groupedMapped: SpecImportMappedResult? {
        guard groupSpecsInOneProject else { return nil }
        return SpecImportService.combineGroupedBatch(
            from: batch.items,
            projectId: UUID(),
            projectName: projectName,
            environmentName: environmentName,
            environmentBindings: environmentBindings
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerSection

            Toggle("Group specs in one project", isOn: $groupSpecsInOneProject)
                .accessibilityIdentifier(SpecImportAccessibility.batchGroupInOneProject)

            if groupSpecsInOneProject {
                projectNameSection
                SpecImportBatchEnvironmentSection(
                    environmentName: $environmentName,
                    environmentBindings: $environmentBindings
                )
            }

            operationCountSection

            if groupSpecsInOneProject, let groupedMapped {
                groupedFolderSection(folders: groupedMapped.folders)
            }

            if !groupSpecsInOneProject {
                specListSection
            }

            if !batch.allWarnings.isEmpty {
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
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Found \(batch.specCount) OpenAPI specs in “\(batch.sourceFolderName)”.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(
                groupSpecsInOneProject
                    ? "All specs import into one project."
                    : "Each spec becomes its own project."
            )
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(SpecImportAccessibility.batchSpecCount)
    }

    @ViewBuilder
    private var projectNameSection: some View {
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
    }

    @ViewBuilder
    private var operationCountSection: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.down.doc")
            Text(SpecImportHelpers.operationCountLabel(batch.totalOperationCount))
        }
        .font(.subheadline.weight(.medium))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(SpecImportHelpers.operationCountLabel(batch.totalOperationCount))
        .accessibilityIdentifier(SpecImportAccessibility.operationCount)
    }

    @ViewBuilder
    private func groupedFolderSection(folders: [RequestFolder]) -> some View {
        let sortedFolders = folders.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        VStack(alignment: .leading, spacing: 6) {
            Text("Folders (\(folders.count))")
                .font(.subheadline.weight(.medium))

            VStack(alignment: .leading, spacing: 4) {
                ForEach(sortedFolders.prefix(5)) { folder in
                    Label(folder.name, systemImage: "folder")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
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

    @ViewBuilder
    private var specListSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Projects (\(batch.specCount))")
                .font(.subheadline.weight(.medium))

            VStack(alignment: .leading, spacing: 4) {
                ForEach(sortedItems, id: \.projectId) { preview in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Label(preview.projectName, systemImage: "folder")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(SpecImportHelpers.operationCountLabel(preview.operationCount))
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
                "\(batch.allWarnings.count) warnings",
                systemImage: "exclamationmark.triangle.fill"
            )
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(batch.allWarnings.prefix(5).enumerated()), id: \.offset) { _, warning in
                    Text(warning.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                let remaining = batch.allWarnings.count - 5
                if remaining > 0 {
                    Text("and \(remaining) more warnings")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}