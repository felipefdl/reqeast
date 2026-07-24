//
//  CloudSyncErrorHeader.swift
//  Reqeast
//

import SwiftUI

struct CloudSyncErrorHeader: View {
    let error: RequestError?

    var body: some View {
        HStack {
            if let error {
                Label {
                    Text(error.localizedTitle).font(.headline)
                } icon: {
                    Image(systemName: error.iconName).foregroundStyle(.red)
                }
            } else {
                Label {
                    Text("iCloud Sync").font(.headline)
                } icon: {
                    Image(systemName: "icloud")
                }
            }
            Spacer()
        }
        .padding()
    }
}
