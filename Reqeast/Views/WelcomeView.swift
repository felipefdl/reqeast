//
//  WelcomeView.swift
//  Reqeast
//

import SwiftUI

struct WelcomeView: View {
    var onNewProject: () -> Void
    var onImportSpec: () -> Void = {}

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 20) {
                AppLogoView(size: 96, breathing: true)

                VStack(spacing: 6) {
                    HStack(spacing: 0) {
                        Text("Welcome to ")
                            .font(.largeTitle)
                            .fontWeight(.semibold)
                        AppNameText(size: .largeTitle)
                    }

                    #if os(macOS)
                    Text("Your API companion for macOS")
                        .font(.body)
                        .foregroundStyle(.secondary)
                    #else
                    Text("Your API companion")
                        .font(.body)
                        .foregroundStyle(.secondary)
                    #endif
                }
            }

            HStack(spacing: 12) {
                Button(action: onNewProject) {
                    Label("New Project", systemImage: "plus.circle")
                }
                .buttonStyle(.glass)

                Button(action: onImportSpec) {
                    Label(String(localized: "Import Spec"), systemImage: "doc.text")
                }
                .buttonStyle(.glass)
                .accessibilityIdentifier("welcome-import-spec-button")
            }

            Spacer()

            Text(Bundle.main.appVersion)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension Bundle {
    var appVersion: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return String(localized: "Version \(version) (\(build))")
    }
}
