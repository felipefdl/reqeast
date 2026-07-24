//
//  ResetDataSheetContent.swift
//  Reqeast
//

import SwiftUI

struct ResetDataSheetContent: View {
    let failures: [DataResetFailure]
    @Binding var confirmText: String
    var onSubmit: () -> Void

    private var hasFailures: Bool { !failures.isEmpty }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.title2)
            VStack(alignment: .leading, spacing: 8) {
                Text("This will permanently delete all projects, requests, credentials, sessions, and settings.")
                Text("This applies to all devices signed into the same iCloud account.")
                    .foregroundStyle(.secondary)
            }
        }

        if hasFailures {
            ResetDataFailureList(failures: failures)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("Type DELETE to confirm:")
                    .font(.callout)
                ResetDataConfirmField(confirmText: $confirmText, onSubmit: onSubmit)
            }
        }
    }
}
