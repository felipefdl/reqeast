//
//  CloudSyncErrorContent.swift
//  Reqeast
//

import SwiftUI

struct CloudSyncErrorContent: View {
    let error: RequestError?

    var body: some View {
        if let error {
            ScrollView {
                Text(error.message)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
        } else {
            VStack {
                Spacer()
                Text("No sync errors.")
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
    }
}
