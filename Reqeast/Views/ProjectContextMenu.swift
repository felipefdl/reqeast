//
//  ProjectContextMenu.swift
//  Reqeast
//

import SwiftUI

struct ProjectContextMenu: View {
    @Bindable var store: ProjectStore
    let project: Project
    @Binding var selectedProjectId: Project.ID?
    @Binding var editingProject: Project?
    var onExportProject: ((Project) -> Void)?
    var onExportSpec: ((Project, SpecExportKind) -> Void)?

    var body: some View {
        Button {
            editingProject = project
        } label: {
            Label("Edit", systemImage: "pencil")
        }

        Button {
            let duplicate = store.duplicateProject(project)
            selectedProjectId = duplicate.id
        } label: {
            Label("Duplicate", systemImage: "plus.square.on.square")
        }

        Button {
            onExportProject?(project)
        } label: {
            Label("Export Project...", systemImage: "square.and.arrow.up")
        }

        Button {
            onExportSpec?(project, .openapi)
        } label: {
            Label(String(localized: "Export as OpenAPI..."), systemImage: "doc.text")
        }

        Button {
            onExportSpec?(project, .postman)
        } label: {
            Label(String(localized: "Export as Postman..."), systemImage: "doc.richtext")
        }

        Menu("Move to Folder") {
            Button {
                store.moveProject(project, to: nil)
            } label: {
                HStack {
                    if project.folderId == nil {
                        Image(systemName: "checkmark")
                    }
                    Text("None")
                }
            }

            Divider()

            ForEach(store.sortedFolders) { folder in
                Button {
                    store.moveProject(project, to: folder)
                } label: {
                    HStack {
                        if project.folderId == folder.id {
                            Image(systemName: "checkmark")
                        }
                        Circle()
                            .fill(folder.color.color)
                            .frame(width: 8, height: 8)
                        Text(folder.name)
                    }
                }
            }
        }

        Divider()

        Button(role: .destructive) {
            if selectedProjectId == project.id {
                selectedProjectId = nil
            }
            store.deleteProject(project)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }
}
