//
//  SpecReadOnlyBanner.swift
//  Reqeast
//

import SwiftUI

/// Shown when a linked project's spec bytes are missing and CKAsset + source re-fetch both failed.
struct SpecReadOnlyBanner: View {
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lock.fill")
                .foregroundStyle(.secondary)
                .padding(.top, 1)
            Text(
                String(
                    localized: "Spec file is unavailable on this device. Requests are read-only until the spec can be downloaded from iCloud or the source URL."
                )
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5))
        .accessibilityIdentifier(SpecSyncAccessibility.specReadOnlyBanner)
    }
}