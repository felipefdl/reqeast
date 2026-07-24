//
//  SpecImportBatchEnvironmentSection.swift
//  Reqeast
//

import SwiftUI

struct SpecImportBatchEnvironmentSection: View {
    @Binding var environmentName: String
    @Binding var environmentBindings: [SpecImportEnvironmentBinding]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Environment name")
                    .font(.subheadline.weight(.medium))
                TextField("Environment name", text: $environmentName)
                    #if os(macOS)
                    .textFieldStyle(.roundedBorder)
                    #endif
                    .devTextInput()
                    .accessibilityLabel("Environment name")
                    .accessibilityIdentifier(SpecImportAccessibility.batchEnvironmentNameField)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Base URLs")
                    .font(.subheadline.weight(.medium))

                VStack(alignment: .leading, spacing: 10) {
                    ForEach($environmentBindings) { $binding in
                        SpecImportEnvironmentBindingRow(binding: $binding)
                    }
                }
            }
        }
    }
}

private struct SpecImportEnvironmentBindingRow: View {
    @Binding var binding: SpecImportEnvironmentBinding

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(binding.sourceFileName)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text(binding.specTitle)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Variable")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 52, alignment: .leading)
                TextField("Variable name", text: $binding.variableName)
                    #if os(macOS)
                    .textFieldStyle(.roundedBorder)
                    #endif
                    .devTextInput()
                    .font(.system(.caption, design: .monospaced))
                    .accessibilityLabel("Base URL variable for \(binding.specTitle)")
                    .accessibilityIdentifier(
                        SpecImportAccessibility.batchEnvironmentVariable(binding.sourceKey)
                    )
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("URL")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 52, alignment: .leading)
                Text(binding.baseURL)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: 8))
    }
}