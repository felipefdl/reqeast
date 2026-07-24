//
//  HttpResponseCertificateSection.swift
//  Reqeast
//

import SwiftUI

struct HttpResponseCertificateSection: View {
    let certificate: StoredCertificateInfo?

    var body: some View {
        if let cert = certificate {
            HttpResponseInfoSection(String(localized: "Certificate")) {
                if let subject = cert.subjectCn {
                    HttpResponseInfoRow(String(localized: "Subject"), subject)
                }
                if let issuer = cert.issuerCn {
                    HttpResponseInfoRow(String(localized: "Issuer"), issuer)
                }
                if let until = cert.validUntil {
                    HttpResponseInfoRow(String(localized: "Valid Until"), until)
                }
            }
        }
    }
}
