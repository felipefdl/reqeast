//
//  SpecLinkPanelView.swift
//  Reqeast
//

import SwiftUI

struct SpecLinkPanelView: View {
    @Bindable var store: ProjectStore
    let project: Project
    var onReviewReady: (SpecSyncDiff, String, Data) -> Void

    @State private var isChecking = false
    @State private var statusMessage: String?
    @State private var checkError: SpecImportError?
    @State private var remoteFingerprint: String?
    @State private var remoteMatchesLocal: Bool?

    private var specLink: SpecLink? { project.specLink }
    private var canCheckRemote: Bool {
        specLink?.isEligibleForRemoteCheck ?? false
    }

    private var backgroundCheckBinding: Binding<Bool> {
        Binding(
            get: {
                store.projects.first(where: { $0.id == project.id })?
                    .specLink?.backgroundCheckEnabled ?? false
            },
            set: { setBackgroundCheckEnabled($0) }
        )
    }

    private var isSpecReadOnly: Bool {
        store.isSpecProjectReadOnly(projectId: project.id)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                panelContent
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }

            if showsPinnedFooter {
                Divider()
                pinnedFooter
                    .padding()
            }
        }
        .frame(minWidth: 280)
        .accessibilityIdentifier(SpecSyncAccessibility.specLinkPanel)
    }

    private var showsPinnedFooter: Bool {
        canCheckRemote || isChecking
    }

    private var panelContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            if isSpecReadOnly {
                SpecReadOnlyBanner()
            }

            if let specLink {
                specInfoSection(specLink)
            }

            if let checkError {
                SpecSyncInlineErrorView(error: checkError)
            } else if let statusMessage {
                Label(statusMessage, systemImage: statusIconName)
                    .font(.subheadline)
                    .foregroundStyle(statusForegroundStyle)
            }

            if canCheckRemote, specLink?.isDetached == false {
                Toggle(isOn: backgroundCheckBinding) {
                    Text("Background spec check")
                    Text("Notify when the linked spec changes. Updates are never applied automatically.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .accessibilityIdentifier(SpecSyncAccessibility.backgroundCheckToggle)
            } else if specLink?.isDetached == true {
                Label {
                    Text("Detached snapshot with no live source. Re-import the spec to refresh.")
                        .font(.caption)
                } icon: {
                    Image(systemName: "clock.arrow.circlepath")
                }
                .foregroundStyle(.secondary)
            }
        }
    }

    private var pinnedFooter: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isChecking {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Fetching spec…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if canCheckRemote {
                Button(action: { Task { await checkForUpdates() } }) {
                    Label("Check for updates", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.glassProminent)
                .disabled(isChecking)
                .accessibilityIdentifier(SpecSyncAccessibility.checkForUpdatesButton)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statusIconName: String {
        if remoteMatchesLocal == false {
            return "exclamationmark.arrow.triangle.2.circlepath"
        }
        return "checkmark.circle"
    }

    private var statusForegroundStyle: AnyShapeStyle {
        if remoteMatchesLocal == false {
            return AnyShapeStyle(Color.orange)
        }
        return AnyShapeStyle(.secondary)
    }

    @ViewBuilder
    private func specInfoSection(_ specLink: SpecLink) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(SpecImportHelpers.formatLabel(specLink.format))
                    .font(.subheadline.weight(.medium))
            } icon: {
                Image(systemName: SpecImportHelpers.formatSystemImage(specLink.format))
            }

            if specLink.isDetached {
                infoRow(
                    title: String(localized: "Mode"),
                    value: String(localized: "Detached snapshot")
                )
            } else {
                infoRow(
                    title: String(localized: "Mode"),
                    value: String(localized: "Linked spec")
                )
            }

            if let sourceURL = specLink.sourceURL, let host = URL(string: sourceURL)?.host {
                infoRow(title: String(localized: "Source"), value: host)
            }

            fingerprintRow(
                title: String(localized: "Local fingerprint"),
                fingerprint: specLink.contentFingerprint
            )

            if let remoteFingerprint {
                fingerprintRow(
                    title: String(localized: "Remote fingerprint"),
                    fingerprint: remoteFingerprint
                )
                if let remoteMatchesLocal {
                    Label {
                        Text(SpecSyncHelpers.fingerprintMatchLabel(matches: remoteMatchesLocal))
                            .font(.caption)
                    } icon: {
                        Image(systemName: remoteMatchesLocal ? "equal.circle" : "exclamationmark.circle")
                    }
                    .foregroundStyle(remoteMatchesLocal ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.orange))
                }
            } else if canCheckRemote {
                Text("Not checked yet")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            infoRow(
                title: String(localized: "Imported"),
                value: specLink.importedAt.formatted(date: .abbreviated, time: .shortened)
            )

            if let lastChecked = specLink.lastCheckedAt {
                infoRow(
                    title: String(localized: "Last checked"),
                    value: lastChecked.formatted(date: .abbreviated, time: .shortened)
                )
            }

            if let lastSynced = specLink.lastSyncedAt {
                infoRow(
                    title: String(localized: "Last synced"),
                    value: lastSynced.formatted(date: .abbreviated, time: .shortened)
                )
            }

            infoRow(
                title: String(localized: "Revision"),
                value: "\(specLink.specRevision)"
            )

            fingerprintRow(
                title: String(localized: "SHA-256"),
                fingerprint: specLink.contentFingerprint,
                truncated: false
            )
        }
    }

    private func fingerprintRow(title: String, fingerprint: String, truncated: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(truncated ? SpecSyncHelpers.truncatedFingerprint(fingerprint) : fingerprint)
                .font(.system(.subheadline, design: .monospaced))
                .textSelection(.enabled)
                .accessibilityLabel(fingerprint)
        }
    }

    private func infoRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
        }
    }

    @MainActor
    private func setBackgroundCheckEnabled(_ enabled: Bool) {
        guard let index = store.projects.firstIndex(where: { $0.id == project.id }) else {
            return
        }
        var updatedProject = store.projects[index]
        guard var specLink = updatedProject.specLink else { return }

        specLink.backgroundCheckEnabled = enabled
        updatedProject.specLink = specLink
        updatedProject.touch()
        store.projects[index] = updatedProject
        store.saveLocal()
        CloudSyncService.shared.queueSave(updatedProject)

        if enabled {
            Task {
                _ = await SpecSyncScheduler.shared.requestNotificationAuthorizationIfNeeded()
                SpecSyncScheduler.shared.refreshScheduling()
            }
        } else {
            SpecSyncScheduler.shared.refreshScheduling()
        }
    }

    @MainActor
    private func checkForUpdates() async {
        isChecking = true
        checkError = nil
        statusMessage = nil
        defer { isChecking = false }

        guard let currentProject = store.projects.first(where: { $0.id == project.id }) else {
            return
        }

        do {
            switch try await SpecSyncService.checkForUpdates(project: currentProject, store: store) {
            case .upToDate:
                if let fingerprint = store.projects.first(where: { $0.id == project.id })?
                    .specLink?.contentFingerprint {
                    remoteFingerprint = fingerprint
                    remoteMatchesLocal = true
                }
                statusMessage = String(localized: "Spec is up to date.")
            case .diff(let diff, let fingerprint, let bytes):
                remoteFingerprint = fingerprint
                remoteMatchesLocal = false
                statusMessage = String(localized: "Update available. Review changes to refresh.")
                onReviewReady(diff, fingerprint, bytes)
            }
        } catch {
            checkError = SpecImportError.from(error)
            remoteFingerprint = nil
            remoteMatchesLocal = nil
        }
    }
}