//
//  ProjectEditFormContent.swift
//  Reqeast
//

import SwiftUI

struct ProjectEditFormContent: View {
    var project: Project
    @Binding var name: String
    @Binding var emoji: String?
    @Binding var iconURLText: String
    @Binding var iconError: String?
    @Binding var color: FolderColor

    var body: some View {
        ProjectIconPreview(project: project, emoji: emoji, iconURLText: iconURLText, color: color)
            .frame(maxWidth: .infinity)

        TextField("Project name", text: $name)
            .devTextInput()

        VStack(alignment: .leading, spacing: 8) {
            Text("Image URL (optional)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            IconURLField(iconURLText: $iconURLText, iconError: $iconError, projectId: project.id)
        }

        VStack(alignment: .leading, spacing: 8) {
            Text("Icon (fallback)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            EmojiGridPicker(selection: $emoji, highlightColor: color.color)
        }

        VStack(alignment: .leading, spacing: 8) {
            Text("Color")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            FolderColorPicker(selection: $color)
        }
    }
}
