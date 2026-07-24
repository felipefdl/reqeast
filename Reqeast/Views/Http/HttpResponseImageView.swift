//
//  HttpResponseImageView.swift
//  Reqeast
//

import SwiftUI

struct HttpResponseImageView: View {
    let responseBody: Data
    let subtype: String

    var body: some View {
        ScrollView {
            if let image = PlatformImage.fromData(responseBody) {
                Image(platformImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 600)
                    .padding(12)
            } else {
                Text("Failed to decode \(subtype) image")
                    .foregroundStyle(.secondary)
                    .padding(12)
            }
        }
    }
}
