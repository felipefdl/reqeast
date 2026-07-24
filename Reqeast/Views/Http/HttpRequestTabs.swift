//
//  HttpRequestTabs.swift
//  Reqeast
//

import SwiftUI

enum HttpRequestTab: String, CaseIterable, Codable {
    case params
    case headers
    case body
    case auth
    case settings

    static func availableTabs(method: HttpMethod, strictMode: Bool) -> [HttpRequestTab] {
        if strictMode && !method.conventionallyHasBody {
            return allCases.filter { $0 != .body }
        }
        return allCases
    }

    var localizedName: String {
        switch self {
        case .params:   return String(localized: "Params")
        case .headers:  return String(localized: "Headers")
        case .body:     return String(localized: "Body")
        case .auth:     return String(localized: "Auth")
        case .settings: return String(localized: "Settings")
        }
    }
}

struct HttpRequestTabs: View, RequestDataBindable {
    @Bindable var store: ProjectStore
    let request: Request
    var sessionStore: HttpSessionStore
    @Binding var selectedTab: HttpRequestTab
    let method: HttpMethod
    var isReadOnly: Bool = false

    @AppStorage("strictHttpMode") private var strictHttpMode: Bool = true
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var httpData: HttpRequestData { readData() }

    func readData() -> HttpRequestData {
        request.httpData ?? HttpRequestData()
    }

    func writeData(_ data: HttpRequestData, to request: inout Request) {
        request.httpData = data
    }

    var availableTabs: [HttpRequestTab] {
        HttpRequestTab.availableTabs(method: method, strictMode: strictHttpMode)
    }

    var body: some View {
        VStack(spacing: 0) {
            tabPicker
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            Divider()

            if tabNeedsFullExpansion {
                tabContent
                    .padding(selectedTab == .settings ? 0 : 12)
                    .disabled(isReadOnly)
            } else {
                ScrollView {
                    tabContent
                        .padding(12)
                }
                #if !os(macOS)
                .scrollDismissesKeyboard(.interactively)
                #endif
                .disabled(isReadOnly)
            }
        }
    }

    @ViewBuilder
    private var tabPicker: some View {
        if horizontalSizeClass == .compact {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(availableTabs, id: \.self) { tab in
                        tabButton(tab)
                    }
                }
            }
        } else {
            Picker("", selection: $selectedTab) {
                ForEach(availableTabs, id: \.self) { tab in
                    Text(tab.localizedName).tag(tab)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    @ViewBuilder
    private func tabButton(_ tab: HttpRequestTab) -> some View {
        let label = Text(tab.localizedName).font(.subheadline)
        if selectedTab == tab {
            Button { selectedTab = tab } label: { label }
                .buttonStyle(.glassProminent)
                .controlSize(.small)
        } else {
            Button { selectedTab = tab } label: { label }
                .buttonStyle(.glass)
                .controlSize(.small)
        }
    }

    private var tabNeedsFullExpansion: Bool {
        if selectedTab == .settings { return true }
        return selectedTab == .body && (httpData.bodyType == .json || httpData.bodyType == .raw)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .params:
            HttpParamsEditor(entries: binding(\.params))
        case .headers:
            HttpHeadersEditor(
                entries: binding(\.headers),
                autoHeaders: AutoHeaderService.generateHeaders(from: httpData),
                disabledAutoHeaders: binding(\.disabledAutoHeaders)
            )
        case .body:
            bodyEditor
        case .auth:
            HttpAuthEditor(
                authType: binding(\.authType),
                authToken: binding(\.authToken),
                authUsername: binding(\.authUsername),
                authPassword: binding(\.authPassword),
                authApiKeyName: binding(\.authApiKeyName),
                authApiKeyValue: binding(\.authApiKeyValue),
                authApiKeyLocation: binding(\.authApiKeyLocation),
                authOAuth2GrantType: binding(\.authOAuth2GrantType),
                authOAuth2AuthURL: binding(\.authOAuth2AuthURL),
                authOAuth2TokenURL: binding(\.authOAuth2TokenURL),
                authOAuth2Scopes: binding(\.authOAuth2Scopes),
                authData: binding(\.authData)
            )
        case .settings:
            HttpSettingsEditor(
                httpVersion: binding(\.httpVersion),
                sslVerify: binding(\.sslVerify),
                followRedirects: binding(\.followRedirects),
                followOriginalMethod: binding(\.followOriginalMethod),
                followAuthHeader: binding(\.followAuthHeader),
                removeRefererOnRedirect: binding(\.removeRefererOnRedirect),
                encodeUrl: binding(\.encodeUrl),
                maxRedirects: binding(\.maxRedirects),
                timeoutSeconds: binding(\.timeoutSeconds),
                disableCookieJar: binding(\.disableCookieJar)
            )
        }
    }

    private var bodyEditor: some View {
        HttpBodyEditor(
            bodyType: binding(\.bodyType),
            bodyContent: binding(\.bodyContent),
            bodyFormData: binding(\.bodyFormData),
            bodyFormDataEntries: binding(\.bodyFormDataEntries),
            rawContentType: binding(\.rawContentType),
            binaryFileName: binding(\.binaryFileName),
            onBinaryFileSelected: { data in
                sessionStore.binaryBodyData = data
            },
            onFormDataFileSelected: { entryId, data in
                sessionStore.formDataFiles[entryId] = data
            }
        )
    }

}
