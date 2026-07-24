//
//  HttpResponseView.swift
//  Reqeast
//

import SwiftUI

struct HttpResponseView: View {
    let response: HttpResponseData
    let requestId: UUID
    let requestMethod: String
    let requestUrl: String
    let requestName: String?

    var body: some View {
        @Bindable var uiState = UIStateStore.shared
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                HttpStatusBadge(response: response)
                Spacer()
                HttpTimingBadge(response: response)
                HttpSizeBadge(response: response)
                HttpNetworkBadge(response: response)

                if !response.cookies.isEmpty {
                    Text("\(response.cookies.count) cookies")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .glassEffect(.regular.tint(response.statusColor.opacity(0.3)), in: .rect(cornerRadius: 0))

            Picker("", selection: $uiState.globalResponseTab) {
                ForEach(HttpResponseTab.allCases, id: \.self) { tab in
                    Text(tab.localizedName).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            switch uiState.globalResponseTab {
            case .body:
                HttpResponseBodyView(
                    responseBody: response.body,
                    headers: response.headers,
                    requestId: requestId,
                    response: response,
                    requestMethod: requestMethod,
                    requestUrl: requestUrl,
                    requestName: requestName
                )
            case .headers:
                HttpResponseHeadersView(headers: response.headers)
            case .cookies:
                HttpResponseCookiesView(cookies: response.cookies)
            case .info:
                HttpResponseInfoView(response: response)
            }
        }
    }
}
