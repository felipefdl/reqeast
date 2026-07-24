//
//  HttpResponseRawView.swift
//  Reqeast
//

import SwiftUI

struct HttpResponseRawView: View {
    let responseBody: Data
    let response: HttpResponseData
    let filteredText: String?
    @Binding var showFullText: Bool

    static let textTruncateThreshold = 100_000

    var body: some View {
        if let filtered = filteredText {
            HttpResponseReadOnlyEditor(
                text: filtered,
                mode: .plain,
                responseTimestamp: response.timestamp
            )
        } else if let text = String(data: responseBody, encoding: .utf8) {
            let isTruncated = !showFullText && text.count > Self.textTruncateThreshold
            let displayText = isTruncated
                ? String(text.prefix(Self.textTruncateThreshold))
                : text

            VStack(spacing: 0) {
                HttpResponseReadOnlyEditor(
                    text: displayText,
                    mode: .plain,
                    responseTimestamp: response.timestamp
                )

                if isTruncated {
                    HttpResponseTruncationBanner(
                        totalCharacters: text.count,
                        showAll: { showFullText = true }
                    )
                }
            }
        } else {
            Text("\(responseBody.count) bytes (binary)")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct HttpResponseTruncationBanner: View {
    let totalCharacters: Int
    let showAll: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text("Response truncated (\(totalCharacters) characters total)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Show All", action: showAll)
                .font(.caption)
                .buttonStyle(.glass)
        }
        .padding(8)
    }
}
