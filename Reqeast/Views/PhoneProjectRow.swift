//
//  PhoneProjectRow.swift
//  Reqeast
//

import SwiftUI

struct PhoneProjectRow: View {
    let project: Project
    @Bindable var store: ProjectStore
    @Binding var selectedProjectId: Project.ID?
    @Binding var editingProject: Project?
    var onExportProject: ((Project) -> Void)?
    var onExportSpec: ((Project, SpecExportKind) -> Void)?

    var body: some View {
        Button {
            selectedProjectId = project.id
        } label: {
            ProjectRowView(
                project: project,
                requestCount: store.requests(for: project.id).count
            )
        }
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
