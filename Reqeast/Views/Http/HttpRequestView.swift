//
//  HttpRequestView.swift
//  Reqeast
//

import SwiftUI

struct HttpRequestFullView: View {
    @Bindable var store: ProjectStore
    let request: Request

    @State private var selectedTab: HttpRequestTab
    @State private var showingHistory = false
    @State private var splitRatio: CGFloat
    @State private var totalHeight: CGFloat = 0
    @State private var urlFieldFocusTrigger = false

    @AppStorage("strictHttpMode") private var strictHttpMode: Bool = true

    #if !os(macOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var isKeyboardVisible = false
    @State private var savedSplitRatio: CGFloat?
    #endif

    init(store: ProjectStore, request: Request) {
        self.store = store
        self.request = request
        self._selectedTab = State(initialValue: UIStateStore.shared.state(for: request.id).requestTab)
        self._splitRatio = State(initialValue: UIStateStore.shared.splitRatio(for: request.id))
    }

    private var execution: HttpExecutionState {
        SessionRegistry.shared.httpExecution(for: request.id)
    }

    private var sessionStore: HttpSessionStore {
        SessionRegistry.shared.httpSession(for: request.id)
    }

    private var httpData: HttpRequestData {
        request.httpData ?? HttpRequestData()
    }

    private var isSpecReadOnly: Bool {
        store.isSpecProjectReadOnly(projectId: request.projectId)
    }

    var body: some View {
        VStack(spacing: 0) {
            if isSpecReadOnly {
                SpecReadOnlyBanner()
                Divider()
            }

            #if os(macOS)
            HttpUrlBar(
                store: store,
                request: request,
                sessionStore: sessionStore,
                execution: execution,
                showingHistory: $showingHistory,
                focusTrigger: $urlFieldFocusTrigger,
                isReadOnly: isSpecReadOnly
            )
            Divider()
            #else
            HttpUrlBar(
                store: store,
                request: request,
                sessionStore: sessionStore,
                execution: execution,
                showingHistory: $showingHistory,
                focusTrigger: $urlFieldFocusTrigger,
                isReadOnly: isSpecReadOnly
            )
                .frame(height: isKeyboardVisible && horizontalSizeClass == .compact && UIStateStore.shared.isResponseFieldFocused ? 0 : nil)
                .clipped()
            Divider()
                .frame(height: isKeyboardVisible && horizontalSizeClass == .compact && UIStateStore.shared.isResponseFieldFocused ? 0 : nil)
                .clipped()
            #endif

            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { newHeight in
                    totalHeight = newHeight
                }
                .overlay {
                    if totalHeight > 0 {
                        #if os(macOS)
                        let hideResponse = false
                        let hideRequest = false
                        #else
                        let hideResponse = isKeyboardVisible && horizontalSizeClass == .compact
                            && !UIStateStore.shared.isResponseFieldFocused
                        let hideRequest = isKeyboardVisible && horizontalSizeClass == .compact
                            && UIStateStore.shared.isResponseFieldFocused
                        #endif

                        let dividerH: CGFloat = {
                            #if os(macOS)
                            return 6
                            #else
                            return 12
                            #endif
                        }()
                        let showDivider = !hideResponse && !hideRequest
                        let contentH = max(0, totalHeight - (showDivider ? dividerH : 0))
                        let requestHeight: CGFloat = {
                            if hideRequest { return 0 }
                            let raw = hideResponse ? contentH : contentH * splitRatio
                            return (raw.isFinite && raw > 0) ? raw : 0
                        }()
                        let responseHeight: CGFloat = {
                            if hideResponse { return 0 }
                            if hideRequest { return contentH }
                            let r = contentH - requestHeight
                            return (r.isFinite && r > 0) ? r : 0
                        }()

                        VStack(spacing: 0) {
                            HttpRequestTabs(
                                store: store,
                                request: request,
                                sessionStore: sessionStore,
                                selectedTab: $selectedTab,
                                method: httpData.method,
                                isReadOnly: isSpecReadOnly
                            )
                                .frame(height: requestHeight)
                                .clipped()

                            if showDivider {
                                ResizableDivider(splitRatio: $splitRatio, totalHeight: totalHeight, tint: execution.response?.statusColor, isLoading: execution.isLoading)
                            }

                            if !hideResponse {
                                HttpResponsePanel(execution: execution, request: request, httpData: httpData)
                                    .frame(height: responseHeight)
                                    #if !os(macOS)
                                    .overlay(alignment: .top) {
                                        Divider()
                                    }
                                    #endif
                                    .clipped()
                            }
                        }
                    }
                }
        }
        .scrollEdgeEffectStyle(.soft, for: .all)
        #if !os(macOS)
        .ignoresSafeArea(.container, edges: .bottom)
        .ignoresSafeArea(.keyboard)
        #endif
        .onAppear {
            sessionStore.loadHistoryIfNeeded(for: request.id)
        }
        .onChange(of: selectedTab) { _, newTab in
            UIStateStore.shared.update(for: request.id) { $0.requestTab = newTab }
        }
        .onChange(of: splitRatio) { _, newRatio in
            UIStateStore.shared.setSplitRatio(newRatio, for: request.id)
        }
        #if os(macOS)
        .modifier(HttpRequestBehaviorModifier(
            httpData: httpData,
            store: store,
            request: request,
            selectedTab: $selectedTab,
            splitRatio: $splitRatio,
            strictHttpMode: $strictHttpMode
        ))
        .modifier(HttpFocusedValuesModifier(
            execution: execution,
            httpData: httpData,
            request: request,
            store: store,
            sessionStore: sessionStore,
            urlFieldFocusTrigger: $urlFieldFocusTrigger,
            showingHistory: $showingHistory,
            selectedTab: $selectedTab,
            strictHttpMode: $strictHttpMode
        ))
        #else
        .modifier(HttpRequestBehaviorModifier(
            httpData: httpData,
            store: store,
            request: request,
            selectedTab: $selectedTab,
            splitRatio: $splitRatio,
            strictHttpMode: $strictHttpMode,
            isKeyboardVisible: $isKeyboardVisible,
            savedSplitRatio: $savedSplitRatio
        ))
        #endif
    }

}
