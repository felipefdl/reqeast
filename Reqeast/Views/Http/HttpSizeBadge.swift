//
//  HttpSizeBadge.swift
//  Reqeast
//

import SwiftUI

struct HttpSizeBadge: View {
    let response: HttpResponseData
    @State private var showPopover = false

    var body: some View {
        Button {
            if response.sizeInfo != nil { showPopover.toggle() }
        } label: {
            Text(response.formattedBodySize)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Size \(response.formattedBodySize)"))
        #if os(macOS)
        .popover(isPresented: $showPopover) {
            if let sizeInfo = response.sizeInfo {
                HttpSizePopover(sizeInfo: sizeInfo)
            }
        }
        #else
        .sheet(isPresented: $showPopover) {
            if let sizeInfo = response.sizeInfo {
                HttpSizePopover(sizeInfo: sizeInfo)
                    .presentationDetents([.medium])
            }
        }
        #endif
    }
}
