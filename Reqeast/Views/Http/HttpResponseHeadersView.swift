//
//  HttpResponseHeadersView.swift
//  Reqeast
//

import SwiftUI

struct HttpResponseHeadersView: View {
    let headers: [KeyValueEntry]

    var body: some View {
        ScrollView {
            Grid(alignment: .topLeading, horizontalSpacing: 16, verticalSpacing: 4) {
                ForEach(headers, id: \.id) { header in
                    GridRow {
                        Text(header.key)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.blue)
                            .gridColumnAlignment(.leading)

                        Text(header.value)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .gridColumnAlignment(.leading)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }
}
