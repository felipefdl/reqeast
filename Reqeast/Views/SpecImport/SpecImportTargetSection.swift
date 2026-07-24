//
//  SpecImportTargetSection.swift
//  Reqeast
//

import SwiftUI

struct SpecImportTargetSection: View {
    @Bindable var store: ProjectStore
    @Binding var importTarget: SpecImportTarget
    @Binding var targetProjectId: UUID?
    var preferredTargetProjectId: UUID?

    private var importableProjects: [Project] {
        SpecImportHelpers.sortedImportableProjects(in: store)
    }

    /// iOS uses native `Picker` in production; UITest launch args use explicit buttons/menus for stable automation.
    private var usesAccessibleImportTargetControls: Bool {
        #if os(macOS)
        true
        #elseif DEBUG
        SpecImportUITestSupport.isPasteFixtureEnabled || SpecImportUITestSupport.isURLFixtureEnabled
        #else
        false
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            importTargetPicker
                .onChange(of: importTarget) { _, newValue in
                    applyImportTargetChange(newValue)
                }

            if importTarget == .existingProject {
                existingProjectPicker
            }
        }
    }

    @ViewBuilder
    private var importTargetPicker: some View {
        if usesAccessibleImportTargetControls {
            VStack(alignment: .leading, spacing: 8) {
                Text("Import target")
                    .font(.subheadline.weight(.medium))
                HStack(spacing: 8) {
                    ForEach(SpecImportTarget.allCases) { target in
                        importTargetButton(for: target)
                    }
                }
                .accessibilityIdentifier(SpecImportAccessibility.importTarget)
            }
        } else {
            Picker("Import target", selection: $importTarget) {
                ForEach(SpecImportTarget.allCases) { target in
                    Text(target.localizedName)
                        .tag(target)
                        .accessibilityIdentifier(SpecImportAccessibility.importTargetOption(target))
                }
            }
            .tint(.primary)
            .accessibilityIdentifier(SpecImportAccessibility.importTarget)
        }
    }

    private var selectedProjectName: String {
        guard let targetProjectId,
              let project = importableProjects.first(where: { $0.id == targetProjectId }) else {
            return importableProjects.first?.name ?? String(localized: "Project")
        }
        return project.name
    }

    @ViewBuilder
    private var existingProjectPicker: some View {
        if importableProjects.isEmpty {
            Text("No projects available. Create a project first.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier(SpecImportAccessibility.importTargetNote)
        } else {
            if usesAccessibleImportTargetControls {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Project")
                        .font(.subheadline.weight(.medium))
                    #if os(iOS)
                    ForEach(importableProjects) { project in
                        importExistingProjectButton(for: project)
                    }
                    .accessibilityIdentifier(SpecImportAccessibility.existingProjectPicker)
                    #else
                    Menu {
                        ForEach(importableProjects) { project in
                            Button(project.name) {
                                targetProjectId = project.id
                            }
                        }
                    } label: {
                        Label(selectedProjectName, systemImage: "folder")
                    }
                    .accessibilityLabel("Existing project")
                    .accessibilityIdentifier(SpecImportAccessibility.existingProjectPicker)
                    #endif
                }
            } else {
                Picker("Project", selection: $targetProjectId) {
                    ForEach(importableProjects) { project in
                        Text(project.name).tag(Optional(project.id))
                    }
                }
                .tint(.primary)
                .accessibilityLabel("Existing project")
                .accessibilityIdentifier(SpecImportAccessibility.existingProjectPicker)
            }

            Text("Merges folders by name, appends new requests, and skips operations that already exist.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier(SpecImportAccessibility.importTargetNote)
        }
    }

    @ViewBuilder
    private func importExistingProjectButton(for project: Project) -> some View {
        let button = Button(project.name) {
            targetProjectId = project.id
        }
        .accessibilityIdentifier(SpecImportAccessibility.existingProjectOption(project.name))

        if targetProjectId == project.id {
            button.buttonStyle(.glassProminent)
        } else {
            button.buttonStyle(.glass)
        }
    }

    @ViewBuilder
    private func importTargetButton(for target: SpecImportTarget) -> some View {
        let button = Button(target.localizedName) {
            importTarget = target
        }
        .accessibilityIdentifier(SpecImportAccessibility.importTargetOption(target))

        if importTarget == target {
            button.buttonStyle(.glassProminent)
        } else {
            button.buttonStyle(.glass)
        }
    }

    private func applyImportTargetChange(_ newValue: SpecImportTarget) {
        switch newValue {
        case .newProject:
            targetProjectId = nil
        case .existingProject:
            if targetProjectId == nil {
                if let preferredTargetProjectId,
                   importableProjects.contains(where: { $0.id == preferredTargetProjectId }) {
                    targetProjectId = preferredTargetProjectId
                } else {
                    targetProjectId = importableProjects.first?.id
                }
            }
        }
    }
}