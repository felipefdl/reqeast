//
//  GrpcReadOnlyBanner.swift
//  Reqeast
//

import SwiftUI

/// Shown when a gRPC request references a proto bundle that is missing or not yet hydrated from iCloud.
struct GrpcReadOnlyBanner: View {
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lock.fill")
                .foregroundStyle(.secondary)
                .padding(.top, 1)
            Text(
                String(
                    localized: "Proto descriptors are unavailable on this device. gRPC requests are read-only until the bundle can be downloaded from iCloud."
                )
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(Color.primary.opacity(0.12)), in: .rect)
        .accessibilityIdentifier("grpcReadOnlyBanner")
    }
}
