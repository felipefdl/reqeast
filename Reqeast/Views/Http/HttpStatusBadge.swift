//
//  HttpStatusBadge.swift
//  Reqeast
//

import SwiftUI

struct HttpStatusBadge: View {
    let response: HttpResponseData
    @State private var showPopover = false

    var body: some View {
        Button { showPopover.toggle() } label: {
            HStack(spacing: 8) {
                Text("\(response.statusCode)")
                    .font(.system(.headline, design: .monospaced))
                    .foregroundStyle(response.statusColor)
                Text(response.statusText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Status \(response.statusCode) \(response.statusText)"))
        #if os(macOS)
        .popover(isPresented: $showPopover) {
            HttpStatusCodePopover(
                statusCode: response.statusCode,
                statusText: response.statusText,
                statusColor: response.statusColor
            )
        }
        #else
        .sheet(isPresented: $showPopover) {
            HttpStatusCodePopover(
                statusCode: response.statusCode,
                statusText: response.statusText,
                statusColor: response.statusColor
            )
            .presentationDetents([.medium])
        }
        #endif
    }
}
