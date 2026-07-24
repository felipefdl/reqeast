//
//  HttpAuthComingSoonView.swift
//  Reqeast
//

import SwiftUI

struct HttpAuthComingSoonView: View {
    let authType: HttpAuthType

    var body: some View {
        ContentUnavailableView {
            Label("Coming Soon", systemImage: "clock")
                .foregroundStyle(.secondary)
        } description: {
            Text("\(authType.localizedName) support is planned for a future update.")
        }
    }
}
