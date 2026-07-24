//
//  HttpResponseInfoView.swift
//  Reqeast
//

import SwiftUI

struct HttpResponseInfoView: View {
    let response: HttpResponseData

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                HttpResponseGeneralSection(response: response)
                HttpResponseCertificateSection(certificate: response.certificate)
                HttpResponseTimingSection(response: response)
                HttpResponseBodyMetaSection(response: response)
                HttpResponseRedirectsSection(redirectChain: response.redirectChain)
                HttpResponseServerSection(response: response)
            }
            .padding(12)
        }
    }
}
