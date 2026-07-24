//
//  SidebarEmptyState.swift
//  Reqeast
//

import SwiftUI

struct SidebarEmptyState: View {
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

                    Text("Your API companion")
                        .font(.body)
                        .foregroundStyle(.secondary)
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
