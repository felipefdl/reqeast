//
//  RequestEditorView.swift
//  Reqeast
//

import SwiftUI

struct RequestEditorView: View {
    @Bindable var store: ProjectStore
    let requestId: UUID

    @State private var showingCodeSnippet = false
    @State private var showingImportRequest = false
    @State private var showingHistory = false

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var request: Request? {
        store.requests.first { $0.id == requestId && $0.deletedAt == nil }
    }

    var body: some View {
        if let request {
            Group {
                switch request.type {
                case .http:
                    HttpRequestFullView(store: store, request: request)
                case .tcp:
                    TcpRequestFullView(store: store, request: request)
                case .udp:
                    UdpRequestFullView(store: store, request: request)
                case .webSocket:
                    WebSocketRequestFullView(store: store, request: request)
                case .sse:
                    SseRequestFullView(store: store, request: request)
                case .grpc:
                    GrpcRequestFullView(store: store, request: request)
                }
            }
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    EnvironmentToolbarPicker(
                        environments: environmentsBinding(for: request),
                        projectId: request.projectId
                    )
                }
                if request.type == .http {
                    if horizontalSizeClass == .compact {
                        ToolbarItem(placement: .automatic) {
                            Button { showingHistory.toggle() } label: {
                                Label("History", systemImage: "clock.arrow.circlepath")
                            }
                        }
                        ToolbarItem(placement: .automatic) {
                            Menu {
                                Button { showingImportRequest = true } label: {
                                    Label("Import Request", systemImage: "square.and.arrow.down")
                                }
                                Button { showingCodeSnippet = true } label: {
                                    Label("Code Snippet", systemImage: "square.and.arrow.up")
                                }
                            } label: {
                                Label("More", systemImage: "ellipsis.circle")
                            }
                        }
                    } else {
                        ToolbarItem(placement: .automatic) {
                            Button { showingImportRequest = true } label: {
                                Label("Import Request", systemImage: "square.and.arrow.down")
                            }
                            .help("Import from cURL, wget, or HTTPie")
                        }
                        ToolbarItem(placement: .automatic) {
                            Button { showingCodeSnippet = true } label: {
                                Label("Code Snippet", systemImage: "square.and.arrow.up")
                            }
                            .help("Generate Code Snippet")
                        }
                    }
                }
            }
            .sheet(isPresented: $showingImportRequest) {
                ImportRequestSheet(store: store, request: request)
            }
            .sheet(isPresented: $showingCodeSnippet) {
                CodeSnippetSheet(
                    request: request,
                    environment: store.activeEnvironment(for: request.projectId)
                )
            }
            .sheet(isPresented: $showingHistory) {
                HttpHistoryPopover(
                    history: httpSessionStore(for: request)?.history ?? [],
                    onRestore: { data in
                        restoreFromHistory(data, for: request)
                        showingHistory = false
                    },
                    onDismiss: { showingHistory = false }
                )
            }
            #if os(macOS)
            .focusedSceneValue(\.isHttpRequest, request.type == .http)
            .focusedSceneValue(\.importRequest, request.type == .http ? { showingImportRequest = true } : nil)
            .focusedSceneValue(\.codeSnippet, request.type == .http ? { showingCodeSnippet = true } : nil)
            .focusedSceneValue(\.copyUrl, {
                let url: String
                switch request.type {
                case .http: url = request.httpData?.url ?? ""
                case .tcp: url = request.tcpData?.host ?? ""
                case .udp: url = request.udpData?.host ?? ""
                case .webSocket: url = request.webSocketData?.url ?? ""
                case .sse: url = request.sseData?.url ?? ""
                case .grpc: url = request.grpcData?.authority ?? ""
                }
                if !url.isEmpty {
                    PlatformClipboard.copy(url)
                }
            })
            #endif
        }
    }

    // MARK: - Compact Toolbar Helpers

    private func httpSessionStore(for request: Request) -> HttpSessionStore? {
        guard request.type == .http else { return nil }
        return SessionRegistry.shared.httpSession(for: request.id)
    }

    private func environmentsBinding(for request: Request) -> Binding<[ApiEnvironment]> {
        Binding(
            get: { store.environments(for: request.projectId) },
            set: { store.updateEnvironments($0, for: request.projectId) }
        )
    }

    private func restoreFromHistory(_ data: HttpRequestData, for request: Request) {
        var updated = request
        updated.httpData = data
        updated.updatedAt = Date()
        store.updateRequest(updated)
    }
}
