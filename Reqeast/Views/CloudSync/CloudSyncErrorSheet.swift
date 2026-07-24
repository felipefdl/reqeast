//
//  CloudSyncErrorSheet.swift
//  Reqeast
//

import SwiftUI

struct CloudSyncErrorSheet: View {
    private let state = CloudSyncService.shared.syncState

    var body: some View {
        VStack(spacing: 0) {
            CloudSyncErrorHeader(error: state.currentError)
            Divider()
            CloudSyncErrorContent(error: state.currentError)
            Divider()
            CloudSyncErrorFooter()
        }
        #if os(macOS)
        .frame(width: 480, height: 360)
        #endif
    }
}
