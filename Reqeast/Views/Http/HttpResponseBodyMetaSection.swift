//
//  HttpResponseBodyMetaSection.swift
//  Reqeast
//

import SwiftUI

struct HttpResponseBodyMetaSection: View {
    let response: HttpResponseData

    var body: some View {
        HttpResponseInfoSection(String(localized: "Body")) {
            HttpResponseInfoRow(String(localized: "Size"), response.formattedBodySize)
            if let ct = response.headerValue("content-type") {
                HttpResponseInfoRow(String(localized: "Type"), ct)
            }
            if let enc = response.headerValue("content-encoding") {
                HttpResponseInfoRow(String(localized: "Encoding"), enc)
            }
            if let si = response.sizeInfo {
                HttpResponseInfoRow(String(localized: "Request"), formatBytes(si.totalRequestSize))
                HttpResponseInfoRow(String(localized: "Response"), formatBytes(si.totalResponseSize))
                if si.isCompressed {
                    HttpResponseInfoRow(String(localized: "Compressed"), formatBytes(si.responseCompressedSize))
                }
            }
        }
    }
}
