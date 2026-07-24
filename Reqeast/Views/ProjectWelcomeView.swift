//
//  ProjectWelcomeView.swift
//  Reqeast
//

import SwiftUI

struct ProjectWelcomeView: View {
    let project: Project
    var store: ProjectStore
    var onNewRequest: () -> Void
    var onEditProject: () -> Void
    var onExportProject: () -> Void

    @State private var appeared = false

    private var requestCount: Int {
        store.requests(for: project.id).count
    }

    private var folderCount: Int {
        store.requestFolders(for: project.id).count
    }

    private var environmentCount: Int {
        store.environments(for: project.id).count
    }

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            headerSection
                .staggeredEntrance(appeared: appeared, delay: 0)

            statsRow
                .staggeredEntrance(appeared: appeared, delay: 0.1)

            actionButtons
                .staggeredEntrance(appeared: appeared, delay: 0.2)

            Spacer()

            footer
                .staggeredEntrance(appeared: appeared, delay: 0.3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { appeared = true }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 16) {
            ProjectIconView(
                project: project,
                size: 80,
                cornerRadius: 16,
                emojiSize: 40,
                symbolSize: 32
            )

            VStack(spacing: 4) {
                Text(project.name)
                    .font(.largeTitle)
                    .fontWeight(.semibold)

                Text("Created \(project.createdAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Stats

    private var statsRow: some View {
        HStack(spacing: 24) {
            statItem(count: requestCount, label: String(localized: "Requests"), icon: "arrow.up.arrow.down")
            statItem(count: folderCount, label: String(localized: "Folders"), icon: "folder")
            statItem(count: environmentCount, label: String(localized: "Environments"), icon: "globe")
        }
    }

    private func statItem(count: Int, label: String, icon: String) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(count)")
                    .font(.title3)
                    .fontWeight(.semibold)
            }
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Actions

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button(action: onNewRequest) {
                Label("New Request", systemImage: "plus.circle")
            }
            .buttonStyle(.glass)

            Button(action: onEditProject) {
                Label("Edit Project", systemImage: "pencil")
            }
            .buttonStyle(.glass)

            Button(action: onExportProject) {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.glass)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        Text(Bundle.main.appVersion)
            .font(.caption)
            .foregroundStyle(.tertiary)
            .padding(.bottom, 6)
    }
}
