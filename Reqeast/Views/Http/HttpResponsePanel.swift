//
//  HttpResponsePanel.swift
//  Reqeast
//

import SwiftUI

struct HttpResponsePanel: View {
    var execution: HttpExecutionState
    var request: Request
    var httpData: HttpRequestData

    @State private var pulse = false

    var body: some View {
        VStack(spacing: 0) {
            if let response = execution.response {
                HttpResponseView(
                    response: response,
                    requestId: request.id,
                    requestMethod: httpData.method.rawLabel,
                    requestUrl: httpData.url,
                    requestName: request.isRenamed ? request.name : nil
                )
            } else if let error = execution.error {
                ContentUnavailableView {
                    Label(error.localizedTitle, systemImage: error.iconName)
                } description: {
                    Text(error.message)
                        .textSelection(.enabled)
                }
            } else if execution.isLoading {
                VStack(spacing: 16) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                        .opacity(pulse ? 0.3 : 0.8)
                        .scaleEffect(pulse ? 1.08 : 1.0)
                        .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: pulse)
                    Text("Sending request…")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onAppear { pulse = true }
                .onDisappear { pulse = false }
            } else {
                ContentUnavailableView {
                    Label("No Response", systemImage: "paperplane")
                        .foregroundStyle(.secondary)
                } description: {
                    if httpData.url.isEmpty {
                        Text("Enter a URL above to get started")
                    } else {
                        #if os(macOS)
                        Text("Press \u{2318}Return to send the request")
                        #else
                        Text("Tap Send to make the request")
                        #endif
                    }
                }
            }
        }
    }
}
