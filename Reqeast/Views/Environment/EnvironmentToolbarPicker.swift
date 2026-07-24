//
//  EnvironmentToolbarPicker.swift
//  Reqeast
//

import SwiftUI

struct EnvironmentToolbarPicker: View {
    @Binding var environments: [ApiEnvironment]
    let projectId: UUID

    @State private var showingManager = false

    private var activeEnvironment: ApiEnvironment? {
        environments.first { $0.isActive }
    }

    var body: some View {
        Menu {
            Button {
                for i in environments.indices {
                    environments[i].isActive = false
                }
            } label: {
                HStack {
                    if activeEnvironment == nil {
                        Image(systemName: "checkmark")
                    }
                    Text("No Environment")
                }
            }

            Divider()

            ForEach(environments) { env in
                Button {
                    for i in environments.indices {
                        environments[i].isActive = environments[i].id == env.id
                    }
                } label: {
                    HStack {
                        if env.isActive {
                            Image(systemName: "checkmark")
                        }
                        Text(env.name)
                    }
                }
            }

            Divider()

            Button {
                showingManager = true
            } label: {
                Label("Manage Environments", systemImage: "gearshape.2")
            }
        } label: {
            Label(
                activeEnvironment?.name ?? String(localized: "No Env"),
                systemImage: "gearshape.2"
            )
        }
        .sheet(isPresented: $showingManager) {
            EnvironmentManagerView(
                environments: $environments,
                projectId: projectId
            )
        }
    }
}
