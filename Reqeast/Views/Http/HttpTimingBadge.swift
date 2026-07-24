//
//  HttpTimingBadge.swift
//  Reqeast
//

import SwiftUI

struct HttpTimingBadge: View {
    let response: HttpResponseData
    @State private var showPopover = false

    var body: some View {
        Button {
            if response.timing != nil { showPopover.toggle() }
        } label: {
            Text(response.formattedElapsed)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Duration \(response.formattedElapsed)"))
        #if os(macOS)
        .popover(isPresented: $showPopover) {
            if let timing = response.timing {
                HttpTimingPopover(timing: timing)
            }
        }
        #else
        .sheet(isPresented: $showPopover) {
            if let timing = response.timing {
                HttpTimingPopover(timing: timing)
                    .presentationDetents([.medium])
            }
        }
        #endif
    }
}
