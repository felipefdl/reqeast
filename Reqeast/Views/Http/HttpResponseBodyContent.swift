//
//  HttpResponseBodyContent.swift
//  Reqeast
//

import SwiftUI

struct HttpResponseBodyContent: View {
    let responseBody: Data
    let response: HttpResponseData
    let effectiveType: ResponseContentType
    let prettyPrintedJson: String?
    let filteredJsonText: String?
    @Binding var showFullText: Bool

    var body: some View {
        let viewMode = UIStateStore.shared.globalResponseViewMode
        let isHtml: Bool = {
            if case .html = effectiveType { return true }
            return false
        }()

        if viewMode == .preview && isHtml {
            HttpResponsePreview(htmlData: responseBody)
        } else {
            switch viewMode {
            case .pretty:
                HttpResponsePrettyView(
                    responseBody: responseBody,
                    response: response,
                    effectiveType: effectiveType,
                    prettyPrintedJson: prettyPrintedJson,
                    filteredJsonText: filteredJsonText,
                    showFullText: $showFullText
                )
            case .raw, .preview:
                HttpResponseRawView(
                    responseBody: responseBody,
                    response: response,
                    filteredText: filteredJsonText,
                    showFullText: $showFullText
                )
            }
        }
    }
}
