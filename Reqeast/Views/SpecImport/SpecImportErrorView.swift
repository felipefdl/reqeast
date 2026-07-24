//
//  SpecImportErrorView.swift
//  Reqeast
//

import SwiftUI

struct SpecImportErrorView: View {
    let error: SpecImportError

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(error.localizedTitle, systemImage: error.iconName)
                .font(.headline)
                .foregroundStyle(.red)

            ScrollView {
                Text(error.fullMessage)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 220)
        }
    }
}