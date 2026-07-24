//
//  SpecSyncInlineErrorView.swift
//  Reqeast
//

import SwiftUI

struct SpecSyncInlineErrorView: View {
    let error: SpecImportError

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(error.localizedTitle, systemImage: error.iconName)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.red)

            Text(error.message)
                .font(.caption)
                .textSelection(.enabled)
                .foregroundStyle(.secondary)
        }
    }
}