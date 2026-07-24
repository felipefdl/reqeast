//
//  HttpResponseRedirectsSection.swift
//  Reqeast
//

import SwiftUI

struct HttpResponseRedirectsSection: View {
    let redirectChain: [StoredRedirectEntry]

    var body: some View {
        if !redirectChain.isEmpty {
            HttpResponseInfoSection(String(localized: "Redirects")) {
                ForEach(redirectChain, id: \.self) { entry in
                    HttpResponseInfoRow("\(entry.statusCode)", entry.url)
                }
            }
        }
    }
}
