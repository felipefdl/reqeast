//
//  EnvironmentEditorView.swift
//  Reqeast
//

import SwiftUI

struct EnvironmentEditorView: View {
    @Binding var environment: ApiEnvironment

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Environment Name", text: $environment.name)
                    .font(.headline)
                    .devTextInput()

                Spacer()

                Toggle("Active", isOn: $environment.isActive)
                    .toggleStyle(.switch)
            }

            ForEach($environment.variables) { $variable in
                HStack(spacing: 8) {
                    Toggle("", isOn: $variable.enabled)
                        .labelsHidden()
                        #if os(macOS)
                        .toggleStyle(.checkbox)
                        #endif

                    TextField("Key", text: $variable.key)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .devTextInput()

                    if variable.isSecret {
                        SecureField("Value", text: $variable.value)
                            .textFieldStyle(.roundedBorder)
                            .devTextInput()
                    } else {
                        TextField("Value", text: $variable.value)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                            .devTextInput()
                    }

                    Toggle("Secret", isOn: $variable.isSecret)
                        #if os(macOS)
                        .toggleStyle(.checkbox)
                        #endif

                    Button {
                        environment.variables.removeAll { $0.id == variable.id }
                        ensureEmptyRow()
                    } label: {
                        Image(systemName: "minus.circle")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .onAppear { ensureEmptyRow() }
        .onChange(of: environment.variables) { _, _ in ensureEmptyRow() }
    }

    private func ensureEmptyRow() {
        if environment.variables.isEmpty || !environment.variables.last!.isEmpty {
            environment.variables.append(EnvironmentVariable())
        }
    }
}
