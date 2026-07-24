//
//  CloudSyncStatusButton.swift
//  Reqeast
//

import SwiftUI

struct CloudSyncStatusButton: View {
    @State private var showingErrorSheet = false
    private let state = CloudSyncService.shared.syncState

    var body: some View {
        Button(action: handleTap) {
            CloudSyncStatusIcon(phase: state.phase)
                .labelStyle(.iconOnly)
        }
        .buttonStyle(.glass)
        .help(helpText)
        .sheet(isPresented: $showingErrorSheet) {
            CloudSyncErrorSheet()
        }
    }

    private func handleTap() {
        if case .error = state.phase {
            showingErrorSheet = true
        } else {
            Task { await CloudSyncService.shared.syncChanges() }
        }
    }

    private var helpText: String {
        switch state.phase {
        case .idle:
            if let last = state.lastSuccessfulSync {
                return String(localized: "iCloud synced \(last.formatted(.relative(presentation: .named)))")
            }
            return String(localized: "iCloud sync")
        case .syncing:
            return String(localized: "Syncing with iCloud")
        case .error(let err):
            return err.localizedTitle
        }
    }
}
