//
//  ProjectIconPreview.swift
//  Reqeast
//

import SwiftUI

struct ProjectIconPreview: View {
    var project: Project
    var emoji: String?
    var iconURLText: String
    var color: FolderColor

    var body: some View {
        ProjectIconView(
            project: previewProject,
            size: 64,
            cornerRadius: 16,
            emojiSize: 32,
            symbolSize: 28
        )
    }

    private var previewProject: Project {
        var p = project
        p.emoji = emoji
        p.iconURL = iconURLText.isEmpty ? nil : project.iconURL
        p.color = color
        return p
    }
}

struct IconURLField: View {
    @Binding var iconURLText: String
    @Binding var iconError: String?
    var projectId: UUID

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                TextField("https://example.com/icon.png", text: $iconURLText)
                    #if os(macOS)
                    .textFieldStyle(.roundedBorder)
                    #endif
                    .onChange(of: iconURLText) {
                        iconError = nil
                    }
                    .devTextInput()

                if !iconURLText.isEmpty {
                    Button {
                        iconURLText = ""
                        iconError = nil
                        ProjectIconService.shared.deleteIcon(for: projectId)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            Text("PNG, JPG, GIF, WebP, SVG, ICO")
                .font(.caption)
                .foregroundStyle(.tertiary)

            if let iconError {
                Text(iconError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }
}
