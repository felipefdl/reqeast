//
//  SpecImportAdvancedOptionsView.swift
//  Reqeast
//

import SwiftUI

struct SpecImportAdvancedOptionsView: View {
    @Binding var options: SpecImportOptions
    var isDisabled: Bool = false

    @State private var isExpanded = StorageEnvironment.isScreenshotMode || StorageEnvironment.isRunningTests

    var body: some View {
        Group {
            if showsExpandedAdvancedOptions {
                advancedOptionsLabel
                advancedOptionsContent
            } else {
                DisclosureGroup(isExpanded: $isExpanded) {
                    advancedOptionsContent
                } label: {
                    advancedOptionsLabel
                }
            }
        }
        .accessibilityLabel("Advanced import options")
        .accessibilityValue(SpecImportHelpers.optionsSummary(options))
        .accessibilityIdentifier(SpecImportAccessibility.advancedOptions)
    }

    private var showsExpandedAdvancedOptions: Bool {
        StorageEnvironment.isScreenshotMode || StorageEnvironment.isRunningTests
    }

    private var advancedOptionsLabel: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Advanced")
                .font(.subheadline.weight(.medium))
            Text(SpecImportHelpers.optionsSummary(options))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private var advancedOptionsContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Folder strategy", selection: $options.folderStrategy) {
                ForEach(SpecFolderStrategy.allCases, id: \.self) { strategy in
                    Text(strategy.localizedName).tag(strategy)
                }
            }
            .tint(.primary)

            Picker("Request naming", selection: $options.requestNaming) {
                ForEach(SpecRequestNaming.allCases, id: \.self) { naming in
                    Text(naming.localizedName).tag(naming)
                }
            }
            .tint(.primary)

            Picker("Preferred body content type", selection: $options.preferredBodyContentType) {
                ForEach(SpecPreferredBodyContentType.allCases, id: \.self) { contentType in
                    Text(contentType.localizedName).tag(contentType)
                }
            }
            .tint(.primary)
            .accessibilityIdentifier(SpecImportAccessibility.preferredBodyContentType)

            Picker("Link to spec after import", selection: $options.linkToSpec) {
                ForEach(SpecLinkPreference.allCases, id: \.self) { preference in
                    Text(preference.localizedName).tag(preference)
                }
            }
            .tint(.primary)
            .accessibilityIdentifier(SpecImportAccessibility.linkToSpec)

            Toggle("Synthesize values from schema", isOn: $options.enableSchemaSynthesis)
                .accessibilityIdentifier(SpecImportAccessibility.enableSchemaSynthesis)

            Toggle("Include deprecated operations", isOn: $options.includeDeprecated)
            Toggle("Enable optional parameters", isOn: $options.enableOptionalParameters)
            Toggle("Scaffold auth from spec", isOn: $options.scaffoldAuth)
            Toggle("Create environments from servers", isOn: $options.createEnvironments)
            Toggle("Import HAR credentials as placeholders", isOn: $options.importHarCredentialsAsPlaceholders)
                .accessibilityIdentifier(SpecImportAccessibility.importHarCredentialsAsPlaceholders)
        }
        .disabled(isDisabled)
    }
}