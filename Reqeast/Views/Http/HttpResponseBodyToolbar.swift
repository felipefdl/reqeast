//
//  HttpResponseBodyToolbar.swift
//  Reqeast
//

import SwiftUI

struct HttpResponseBodyToolbar: View {
    let isHtml: Bool
    let shareMarkdown: String
    let shareDetailedMarkdown: String

    var body: some View {
        @Bindable var uiState = UIStateStore.shared
        HStack(spacing: 6) {
            Picker("", selection: $uiState.globalResponseViewMode) {
                Text("Pretty").tag(ResponseViewMode.pretty)
                Text("Raw").tag(ResponseViewMode.raw)
                if isHtml {
                    Text("Preview").tag(ResponseViewMode.preview)
                }
            }
            .pickerStyle(.segmented)
            .fixedSize()

            Spacer(minLength: 0)

            Picker("Format", selection: $uiState.globalResponseFormatOverride) {
                Text("Auto").tag(ResponseFormatOverride.auto)
                Text("JSON").tag(ResponseFormatOverride.json)
                Text("HTML").tag(ResponseFormatOverride.html)
                Text("XML").tag(ResponseFormatOverride.xml)
                Text("Text").tag(ResponseFormatOverride.text)
            }
            .labelsHidden()
            .tint(.primary)

            ShareLink(item: shareMarkdown) {
                Image(systemName: "square.and.arrow.up")
            }
            .buttonStyle(.glass)
            .font(.caption)
            .accessibilityLabel("Share response")
            #if !os(macOS)
            .contextMenu {
                ShareLink(item: shareDetailedMarkdown) {
                    Label("Share Detailed", systemImage: "doc.richtext")
                }
            }
            #endif
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
