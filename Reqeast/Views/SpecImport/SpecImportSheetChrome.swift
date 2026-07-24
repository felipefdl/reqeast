//
//  SpecImportSheetChrome.swift
//  Reqeast
//

import SwiftUI

extension SpecImportSheet {

    var sheetTitle: LocalizedStringKey {
        switch phase {
        case .sourcePick, .parsing: "Import Spec"
        case .preview, .batchPreview, .importing, .importingBatch: "Import Preview"
        case .error: "Import Failed"
        }
    }

    var isBusy: Bool {
        switch phase {
        case .parsing, .importing, .importingBatch: true
        default: isRefreshingPreview
        }
    }

    @ViewBuilder
    var sheetContent: some View {
        switch phase {
        case .sourcePick:
            SpecImportSourcePickView(
                sourceTab: $sourceTab,
                urlText: $urlText,
                pasteText: $pasteText,
                onChooseFile: chooseSpecFile,
                onChooseFolder: chooseSpecFolder
            )
        case .parsing:
            SpecImportLoadingView(
                title: String(localized: "Parsing Spec"),
                subtitle: String(localized: "Reading operations and building a preview.")
            )
        case .preview(let preview):
            SpecImportPreviewView(
                preview: preview,
                store: store,
                projectName: $projectName,
                options: $importOptions,
                importTarget: $importTarget,
                targetProjectId: $targetProjectId,
                preferredTargetProjectId: preferredTargetProjectId,
                urlSnapshotDate: urlSnapshotDate,
                isRefreshing: isRefreshingPreview
            )
        case .batchPreview(let batch):
            SpecImportBatchPreviewView(
                batch: batch,
                projectName: $projectName,
                environmentName: $batchEnvironmentName,
                environmentBindings: $batchEnvironmentBindings,
                groupSpecsInOneProject: $groupSpecsInOneProject,
                options: $importOptions,
                isRefreshing: isRefreshingPreview
            )
        case .importing:
            SpecImportLoadingView(
                title: String(localized: "Importing"),
                subtitle: importTarget == .existingProject
                    ? String(localized: "Merging folders and requests into the selected project.")
                    : String(localized: "Creating project, folders, and requests.")
            )
        case .importingBatch(let batch):
            SpecImportLoadingView(
                title: String(localized: "Importing"),
                subtitle: groupSpecsInOneProject
                    ? String(localized: "Creating one project with folders and requests.")
                    : String(localized: "Creating \(batch.specCount) projects, folders, and requests.")
            )
        case .error(let error):
            SpecImportErrorView(error: error)
        }
    }

    @ViewBuilder
    var footerButtons: some View {
        HStack {
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
                .disabled(isBusy)
                .accessibilityIdentifier(SpecImportAccessibility.cancelButton)

            Spacer()

            switch phase {
            case .sourcePick:
                if sourceTab != .file {
                    Button(primarySourceActionTitle) { performPrimarySourceAction() }
                        .buttonStyle(.glassProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(!canContinueFromSource)
                        .accessibilityIdentifier(primarySourceActionAccessibilityIdentifier)
                }
            case .preview(let preview):
                Button("Import") { commitImport(preview: preview) }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canCommitImport)
                    .accessibilityLabel("Import spec")
                    .accessibilityIdentifier(SpecImportAccessibility.importButton)
            case .batchPreview(let batch):
                batchImportButton(batch: batch)
            case .error:
                Button("Try Again") { retryAfterError() }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
            case .parsing, .importing, .importingBatch:
                EmptyView()
            }
        }
    }

    #if !os(macOS)
    @ToolbarContentBuilder
    var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
                .disabled(isBusy)
                .accessibilityIdentifier(SpecImportAccessibility.cancelButton)
        }

        ToolbarItem(placement: .confirmationAction) {
            switch phase {
            case .sourcePick where sourceTab != .file:
                Button(primarySourceActionTitle) { performPrimarySourceAction() }
                    .disabled(!canContinueFromSource)
                    .accessibilityIdentifier(primarySourceActionAccessibilityIdentifier)
            case .preview(let preview):
                Button("Import") { commitImport(preview: preview) }
                    .disabled(!canCommitImport)
                    .accessibilityLabel("Import spec")
                    .accessibilityIdentifier(SpecImportAccessibility.importButton)
            case .batchPreview(let batch):
                batchImportButton(batch: batch, usesProminentStyle: false)
            case .error:
                Button("Try Again") { retryAfterError() }
            default:
                EmptyView()
            }
        }
    }
    #endif

    @ViewBuilder
    private func batchImportButton(batch: SpecImportBatchPreview, usesProminentStyle: Bool = true) -> some View {
        let button = Button(groupSpecsInOneProject ? "Import" : "Import All") {
            commitBatchImport(batch: batch)
        }
        .keyboardShortcut(.defaultAction)
        .disabled(!canCommitBatchImport)
        .accessibilityLabel(groupSpecsInOneProject ? "Import grouped specs" : "Import all specs")
        .accessibilityIdentifier(
            groupSpecsInOneProject
                ? SpecImportAccessibility.importButton
                : SpecImportAccessibility.importAllButton
        )

        if usesProminentStyle {
            button.buttonStyle(.glassProminent)
        } else {
            button
        }
    }
}