//
//  HttpResponseGeneralSection.swift
//  Reqeast
//

import SwiftUI

struct HttpResponseGeneralSection: View {
    let response: HttpResponseData

    var body: some View {
        HttpResponseInfoSection(String(localized: "General")) {
            HttpResponseInfoRow(String(localized: "Status"), "\(response.statusCode) \(response.statusText)")
            HttpResponseInfoRow("URL", response.finalUrl)
            HttpResponseInfoRow(String(localized: "Protocol"), response.httpVersion)
            if let addr = response.remoteAddr {
                HttpResponseInfoRow(String(localized: "Remote"), addr)
            }
        }
    }
}
