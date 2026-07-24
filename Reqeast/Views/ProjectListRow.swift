//
//  ProjectListRow.swift
//  Reqeast
//

import SwiftUI

struct ProjectListRow: View {
    let project: Project
    @Bindable var store: ProjectStore
    @Binding var selectedProjectId: Project.ID?
    @Binding var editingProject: Project?
    var onExportProject: ((Project) -> Void)?
    var onExportSpec: ((Project, SpecExportKind) -> Void)?

    var body: some View {
        ProjectRowView(
            project: project,
            requestCount: store.requests(for: project.id).count
        )
        .tag(project.id)
        .contextMenu {
            ProjectContextMenu(
                store: store,
                project: project,
                selectedProjectId: $selectedProjectId,
                editingProject: $editingProject,
                onExportProject: onExportProject,
                onExportSpec: onExportSpec
            )
        }
    }
}
