//
//  ProjectRowView.swift
//  Reqeast
//

import SwiftUI

struct ProjectRowView: View {
    let project: Project
    let requestCount: Int

    var body: some View {
        HStack(spacing: 12) {
            ProjectIconView(project: project)

            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .accessibilityIdentifier("project-\(project.name)")

                Text("\(requestCount) requests")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
    }
}
