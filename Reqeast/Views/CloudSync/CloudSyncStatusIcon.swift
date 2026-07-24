//
//  CloudSyncStatusIcon.swift
//  Reqeast
//

import SwiftUI

struct CloudSyncStatusIcon: View {
    let phase: CloudSyncState.Phase

    var body: some View {
        switch phase {
        case .idle:
            Label("iCloud sync idle", systemImage: "icloud")
        case .syncing:
            Label {
                Text("iCloud syncing")
            } icon: {
                ProgressView()
                    #if os(macOS)
                    .controlSize(.small)
                    #endif
            }
        case .error(let err):
            Label(err.localizedTitle, systemImage: err.iconName)
                .foregroundStyle(.red)
        }
    }
}
