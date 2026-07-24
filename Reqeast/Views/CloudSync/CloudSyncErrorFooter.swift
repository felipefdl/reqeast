//
//  CloudSyncErrorFooter.swift
//  Reqeast
//

import SwiftUI

struct CloudSyncErrorFooter: View {
    @Environment(\.dismiss) private var dismiss
    private let state = CloudSyncService.shared.syncState

    var body: some View {
        HStack {
            Button("Dismiss", action: dismissAction)
                .buttonStyle(.glass)
            Spacer()
            Button("Retry Sync", action: retryAction)
                .buttonStyle(.glassProminent)
        }
        .padding()
    }

    private func dismissAction() {
        state.clearError()
        dismiss()
    }

    private func retryAction() {
        state.clearError()
        Task { await CloudSyncService.shared.syncChanges() }
        dismiss()
    }
}
