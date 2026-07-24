//
//  HttpResponseInfoSection.swift
//  Reqeast
//

import SwiftUI

struct HttpResponseInfoSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
            content
        }
        .padding(.bottom, 8)
    }
}
