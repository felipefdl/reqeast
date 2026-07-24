//
//  ProjectEditSheet.swift
//  Reqeast
//

import SwiftUI

struct ProjectEditSheet: View {
    enum Mode {
        case create(onCreate: (Project) -> Void)
        case edit
    }

    @Bindable var store: ProjectStore
    var project: Project
    var mode: Mode = .edit
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var emoji: String? = nil
    @State private var iconURLText: String = ""
    @State private var color: FolderColor = .gray
    @State private var isSaving = false
    @State private var iconError: String?

    private var isCreateMode: Bool {
        if case .create = mode { return true }
        return false
    }

    private var sheetTitle: LocalizedStringKey {
        isCreateMode ? "New Project" : "Edit Project"
    }

    private var confirmButtonTitle: LocalizedStringKey {
        isCreateMode ? "Create" : "Save"
    }

    private var isSaveDisabled: Bool {
        name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving
    }

    var body: some View {
        #if os(macOS)
        macOSBody
        #else
        iOSBody
        #endif
    }

    // MARK: - macOS Body

    #if os(macOS)
    private var macOSBody: some View {
        VStack(spacing: 0) {
            HStack {
                Text(sheetTitle).font(.headline)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ProjectEditFormContent(
                        project: project, name: $name, emoji: $emoji,
                        iconURLText: $iconURLText, iconError: $iconError, color: $color
                    )
                }
                .padding(16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(confirmButtonTitle) { save() }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isSaveDisabled)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(width: 420, height: 480)
        .onAppear { populateState() }
    }
    #endif

    // MARK: - iOS Body

    #if !os(macOS)
    private var iOSBody: some View {
        NavigationStack {
            Form {
                Section {
                    ProjectIconPreview(project: project, emoji: emoji, iconURLText: iconURLText, color: color)
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                }
                Section { TextField("Project name", text: $name) }
                Section("Image URL (optional)") {
                    IconURLField(iconURLText: $iconURLText, iconError: $iconError, projectId: project.id)
                }
                Section("Icon (fallback)") {
                    EmojiGridPicker(selection: $emoji, highlightColor: color.color)
                }
                Section("Color") { FolderColorPicker(selection: $color) }
            }
            .navigationTitle(sheetTitle)
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(confirmButtonTitle) { save() }
                        .disabled(isSaveDisabled)
                }
            }
        }
        .onAppear { populateState() }
    }
    #endif

    // MARK: - Helpers

    private func populateState() {
        name = project.name
        emoji = project.emoji
        iconURLText = project.iconURL ?? ""
        color = project.color
    }

    private func save() {
        let trimmedURL = iconURLText.trimmingCharacters(in: .whitespaces)
        let urlChanged = trimmedURL != (project.iconURL ?? "")

        isSaving = true
        iconError = nil

        Task {
            var resolvedIconURL: String? = nil

            if !trimmedURL.isEmpty {
                guard let url = URL(string: trimmedURL),
                      let scheme = url.scheme,
                      ["http", "https"].contains(scheme.lowercased()) else {
                    iconError = "Enter a valid HTTP or HTTPS URL"
                    isSaving = false
                    return
                }

                let ext = url.pathExtension.lowercased()
                if !ext.isEmpty && !Project.allowedIconExtensions.contains(ext) {
                    iconError = "Unsupported format. Use: PNG, JPG, GIF, WebP, SVG, ICO"
                    isSaving = false
                    return
                }

                if urlChanged {
                    let image = await ProjectIconService.shared.downloadIcon(from: trimmedURL, for: project.id)
                    if image == nil {
                        iconError = "Failed to download image from URL"
                        isSaving = false
                        return
                    }
                }
                resolvedIconURL = trimmedURL
            } else if project.iconURL != nil {
                ProjectIconService.shared.deleteIcon(for: project.id)
            }

            var updated = project
            updated.name = name.trimmingCharacters(in: .whitespaces)
            updated.emoji = emoji
            updated.iconURL = resolvedIconURL
            updated.color = color
            updated.updatedAt = Date()
            switch mode {
            case .create(let onCreate):
                store.addProject(updated)
                onCreate(updated)
            case .edit:
                store.updateProject(updated)
            }
            isSaving = false
            dismiss()
        }
    }
}
