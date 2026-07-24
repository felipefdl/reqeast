//
//  EnvironmentManagerView.swift
//  Reqeast
//

import SwiftUI

struct EnvironmentManagerView: View {
    @Binding var environments: [ApiEnvironment]
    let projectId: UUID
    @Environment(\.dismiss) private var dismiss

    @State private var newEnvName = ""

    var body: some View {
        #if os(macOS)
        VStack(spacing: 0) {
            HStack {
                Text("Environments")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if environments.isEmpty {
                        environmentEmptyState
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ForEach($environments) { $env in
                            EnvironmentEditorView(environment: $env)
                            Divider()
                        }
                    }

                    HStack(spacing: 8) {
                        TextField("New Environment", text: $newEnvName)
                            .devTextInput()
                        Button("Add") {
                            let env = ApiEnvironment(projectId: projectId, name: newEnvName)
                            environments.append(env)
                            newEnvName = ""
                        }
                        .disabled(newEnvName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                .padding(16)
            }

            Divider()

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(width: 500, height: 500)
        #else
        NavigationStack {
            List {
                if environments.isEmpty {
                    Section {
                        environmentEmptyState
                    }
                } else {
                    ForEach($environments) { $env in
                        EnvironmentEditorView(environment: $env)
                    }
                }

                Section {
                    HStack {
                        TextField("New Environment", text: $newEnvName)
                            .devTextInput()
                        Button("Add") {
                            let env = ApiEnvironment(projectId: projectId, name: newEnvName)
                            environments.append(env)
                            newEnvName = ""
                        }
                        .disabled(newEnvName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .navigationTitle("Environments")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #endif
    }

    private var environmentEmptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Environments let you define reusable variables for your requests.")

            VStack(alignment: .leading, spacing: 4) {
                Text("Variable:  host = api.example.com")
                Text("URL:       https://{{host}}/users")
            }
            .font(.system(.callout, design: .monospaced))

            Text("Use {{variable}} in URLs, headers, body, and auth fields.")
        }
        .foregroundStyle(.secondary)
    }
}
