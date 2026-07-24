//
//  HttpNetworkBadge.swift
//  Reqeast
//

import SwiftUI

struct HttpNetworkBadge: View {
    let response: HttpResponseData
    @State private var showPopover = false

    var body: some View {
        Button { showPopover.toggle() } label: {
            Image(systemName: response.isHttps ? "lock.fill" : "globe")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(response.isHttps ? "HTTPS secure connection" : "HTTP connection")
        #if os(macOS)
        .popover(isPresented: $showPopover) {
            HttpNetworkPopover(response: response)
        }
        #else
        .sheet(isPresented: $showPopover) {
            HttpNetworkPopover(response: response)
                .presentationDetents([.medium])
        }
        #endif
    }
}
