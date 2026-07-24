//
//  HttpResponseBodyView.swift
//  Reqeast
//

import SwiftUI

struct HttpResponseBodyView: View {
    let responseBody: Data
    let headers: [KeyValueEntry]
    let requestId: UUID
    let response: HttpResponseData
    let requestMethod: String
    let requestUrl: String
    let requestName: String?

    @AppStorage("jqUnquoteStrings") private var jqUnquoteStrings = true
    @State private var showFullText = false
    @State private var jqFilterText = ""
    @State private var jqFilterResult: JqFilterResult?
    /// Display-ready (unquoted + prettified) jq output. Produced in the filter task, never in
    /// `body`: prettifying a multi-MB result during view evaluation froze the main thread on
    /// every re-render.
    @State private var filteredDisplayText: String?
    @State private var prettyPrintedJson: String?
    @State private var shareMarkdown: String = ""
    @State private var shareDetailedMarkdown: String = ""

    /// Cached per response: when the Content-Type header is missing, `detect` falls back to
    /// parsing the entire body with JSONSerialization, which is too expensive to repeat on
    /// every body re-evaluation (each keystroke in the jq filter field).
    @State private var detectedTypeCache: (timestamp: Date, type: ResponseContentType)?

    private var detectedType: ResponseContentType {
        if let cache = detectedTypeCache, cache.timestamp == response.timestamp { return cache.type }
        return ResponseContentDetector.detect(headers: headers, body: responseBody)
    }

    private var effectiveType: ResponseContentType {
        switch UIStateStore.shared.globalResponseFormatOverride {
        case .auto: detectedType
        case .json: .json
        case .html: .html
        case .xml:  .xml
        case .text: .text
        }
    }

    private var isHtml: Bool {
        if case .html = effectiveType { return true }
        return false
    }

    private var isJson: Bool {
        if case .json = effectiveType { return true }
        return false
    }

    var body: some View {
        VStack(spacing: 0) {
            HttpResponseBodyToolbar(
                isHtml: isHtml,
                shareMarkdown: shareMarkdown,
                shareDetailedMarkdown: shareDetailedMarkdown
            )
            Divider()
            if isJson {
                JqFilterBar(filterExpression: $jqFilterText, filterResult: jqFilterResult)
            }
            HttpResponseBodyContent(
                responseBody: responseBody,
                response: response,
                effectiveType: effectiveType,
                prettyPrintedJson: prettyPrintedJson,
                filteredJsonText: filteredDisplayText,
                showFullText: $showFullText
            )
            .clipped()
        }
        .onAppear { showFullText = false }
        .task(id: response.timestamp) {
            detectedTypeCache = (response.timestamp, ResponseContentDetector.detect(headers: headers, body: responseBody))
            if let raw = String(data: responseBody, encoding: .utf8) {
                prettyPrintedJson = JsonBeautifier.prettify(raw)
            } else {
                prettyPrintedJson = nil
            }
            shareMarkdown = ResponseShareService.generateMarkdown(
                response: response,
                method: requestMethod,
                url: requestUrl,
                requestName: requestName
            )
            shareDetailedMarkdown = ResponseShareService.generateDetailedMarkdown(
                response: response,
                method: requestMethod,
                url: requestUrl,
                requestName: requestName
            )
        }
        .task(id: "\(jqFilterText)-\(jqUnquoteStrings)-\(response.timestamp)") {
            guard !jqFilterText.isEmpty else {
                jqFilterResult = nil
                filteredDisplayText = nil
                return
            }
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            // @concurrent pipeline: the heavy lifting (UTF-8 decode, deep parse, the
            // synchronous UniFFI call, unquoting) runs off the main actor.
            let outcome = await JqFilterService.filteredOutput(
                body: responseBody,
                expression: jqFilterText,
                unquote: jqUnquoteStrings
            )
            guard !Task.isCancelled, let outcome else { return }
            jqFilterResult = outcome.result
            filteredDisplayText = outcome.display.map { JsonBeautifier.prettify($0) ?? $0 }
        }
    }
}
