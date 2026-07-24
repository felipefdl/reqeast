//
//  SseRequestView.swift
//  Reqeast
//

import SwiftUI

struct SseRequestFullView: View {
    @Bindable var store: ProjectStore
    let request: Request

    @State private var urlFocusTrigger = false

    private var sessionStore: SseSessionStore {
        SessionRegistry.shared.sseSession(for: request.id)
    }

    private var sseData: SseRequestData {
        request.sseData ?? SseRequestData()
    }

    var body: some View {
        VStack(spacing: 0) {
            SseConnectionBar(
                store: store,
                request: request,
                sessionStore: sessionStore,
                focusTrigger: $urlFocusTrigger
            )

            Divider()

            SseEventLog(events: sessionStore.events)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        #if !os(macOS)
        .keyboardDismissToolbar()
        #endif
        #if os(macOS)
        .focusedSceneValue(\.sendOrConnect, {
            let env = store.activeEnvironment(for: request.projectId)
            let url = EnvironmentVariableService.substitute(sseData.url, environment: env)
            let headers = sseData.headers
                .filter { $0.enabled && !$0.key.isEmpty }
                .map {
                    KeyValuePair(
                        key: $0.key,
                        value: EnvironmentVariableService.substitute($0.value, environment: env),
                        enabled: true
                    )
                }
            sessionStore.connect(
                url: url, headers: headers,
                sslVerify: sseData.sslVerify,
                timeoutSecs: UInt32(sseData.timeoutSeconds),
                lastEventId: sessionStore.lastEventId
            )
        })
        .focusedSceneValue(\.cancelOrDisconnect, (sessionStore.isConnected || sessionStore.isConnecting) ? { sessionStore.disconnect() } : nil)
        .focusedSceneValue(\.canSendOrConnect, !sessionStore.isConnected && !sessionStore.isConnecting && !sseData.url.isEmpty)
        .focusedSceneValue(\.canCancelOrDisconnect, sessionStore.isConnected || sessionStore.isConnecting)
        .focusedSceneValue(\.focusUrlField, { urlFocusTrigger.toggle() })
        .focusedSceneValue(\.clearMessages, sessionStore.events.isEmpty ? nil : { sessionStore.events.removeAll() })
        .focusedSceneValue(\.hasMessages, !sessionStore.events.isEmpty)
        .focusedSceneValue(\.hasResponse, false)
        #endif
    }
}
