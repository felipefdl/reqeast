//
//  HttpResponseServerSection.swift
//  Reqeast
//

import SwiftUI

struct HttpResponseServerSection: View {
    let response: HttpResponseData

    var body: some View {
        if let server = response.headerValue("server") {
            HttpResponseInfoSection(String(localized: "Server")) {
                HttpResponseInfoRow(String(localized: "Server"), server)
                if let poweredBy = response.headerValue("x-powered-by") {
                    HttpResponseInfoRow(String(localized: "Powered By"), poweredBy)
                }
            }
        }
    }
}
