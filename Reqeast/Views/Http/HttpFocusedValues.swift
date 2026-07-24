//
//  HttpFocusedValues.swift
//  Reqeast
//

import SwiftUI

#if os(macOS)
struct HttpFocusedValuesModifier: ViewModifier {
    var execution: HttpExecutionState
    var httpData: HttpRequestData
    var request: Request
    var store: ProjectStore
    var sessionStore: HttpSessionStore
    @Binding var urlFieldFocusTrigger: Bool
    @Binding var showingHistory: Bool
    @Binding var selectedTab: HttpRequestTab
    @Binding var strictHttpMode: Bool

    func body(content: Content) -> some View {
        content
            .focusedSceneValue(\.sendOrConnect, {
                execution.send(
                    request: request,
                    environment: store.activeEnvironment(for: request.projectId),
                    sessionStore: sessionStore
                ) { name in
                    store.renameRequest(request, to: name)
                }
            })
            .focusedSceneValue(\.cancelOrDisconnect, execution.isLoading ? { execution.cancel() } : nil)
            .focusedSceneValue(\.canSendOrConnect, !httpData.url.isEmpty && !execution.isLoading)
            .focusedSceneValue(\.canCancelOrDisconnect, execution.isLoading)
            .focusedSceneValue(\.focusUrlField, { urlFieldFocusTrigger.toggle() })
            .focusedSceneValue(\.selectRequestTab, { index in
                let tabs = HttpRequestTab.availableTabs(method: httpData.method, strictMode: strictHttpMode)
                if index >= 0 && index < tabs.count {
                    selectedTab = tabs[index]
                }
            })
            .focusedSceneValue(\.requestHistory, { showingHistory.toggle() })
            .focusedSceneValue(\.hasResponse, execution.response != nil)
            .focusedSceneValue(\.copyResponseBody, {
                guard let body = execution.response?.body,
                      let text = String(data: body, encoding: .utf8) else { return }
                PlatformClipboard.copy(text)
            })
            .focusedSceneValue(\.shareResponse, {
                guard let response = execution.response else { return }
                let md = ResponseShareService.generateMarkdown(
                    response: response,
                    method: httpData.method.rawLabel,
                    url: httpData.url,
                    requestName: request.isRenamed ? request.name : nil
                )
                PlatformClipboard.copy(md)
            })
            .focusedSceneValue(\.shareResponseDetailed, {
                guard let response = execution.response else { return }
                let md = ResponseShareService.generateDetailedMarkdown(
                    response: response,
                    method: httpData.method.rawLabel,
                    url: httpData.url,
                    requestName: request.isRenamed ? request.name : nil
                )
                PlatformClipboard.copy(md)
            })
            .focusedSceneValue(\.hasMessages, false)
    }
}
#endif
