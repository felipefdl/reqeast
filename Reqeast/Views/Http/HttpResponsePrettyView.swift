//
//  HttpResponsePrettyView.swift
//  Reqeast
//

import SwiftUI

struct HttpResponsePrettyView: View {
    let responseBody: Data
    let response: HttpResponseData
    let effectiveType: ResponseContentType
    let prettyPrintedJson: String?
    let filteredJsonText: String?
    @Binding var showFullText: Bool

    var body: some View {
        switch effectiveType {
        case .json:
            if let filtered = filteredJsonText {
                HttpResponseReadOnlyEditor(
                    text: filtered,
                    mode: .json,
                    responseTimestamp: response.timestamp
                )
            } else if let jsonString = prettyPrintedJson {
                HttpResponseReadOnlyEditor(
                    text: jsonString,
                    mode: .json,
                    responseTimestamp: response.timestamp
                )
            } else {
                fallbackRaw
            }

        case .html, .xml:
            if let text = String(data: responseBody, encoding: .utf8) {
                let isTruncated = !showFullText && text.count > HttpResponseRawView.textTruncateThreshold
                let displayText = isTruncated
                    ? String(text.prefix(HttpResponseRawView.textTruncateThreshold))
                    : text

                VStack(spacing: 0) {
                    HttpResponseReadOnlyEditor(
                        text: displayText,
                        mode: .html,
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
                fallbackRaw
            }

        case .image(let subtype):
            HttpResponseImageView(responseBody: responseBody, subtype: subtype)

        default:
            fallbackRaw
        }
    }

    private var fallbackRaw: some View {
        HttpResponseRawView(
            responseBody: responseBody,
            response: response,
            filteredText: filteredJsonText,
            showFullText: $showFullText
        )
    }
}
