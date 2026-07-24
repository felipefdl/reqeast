//
//  HttpRequestBehavior.swift
//  Reqeast
//

import SwiftUI
#if canImport(UIKit)
import Combine
#endif

struct HttpRequestBehaviorModifier: ViewModifier {
    var httpData: HttpRequestData
    var store: ProjectStore
    var request: Request
    @Binding var selectedTab: HttpRequestTab
    @Binding var splitRatio: CGFloat
    @Binding var strictHttpMode: Bool

    #if !os(macOS)
    @Binding var isKeyboardVisible: Bool
    @Binding var savedSplitRatio: CGFloat?
    #endif

    func body(content: Content) -> some View {
        content
            #if !os(macOS)
            .keyboardDismissToolbar()
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                isKeyboardVisible = true
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                isKeyboardVisible = false
                UIStateStore.shared.isResponseFieldFocused = false
            }
            .onChange(of: UIStateStore.shared.isResponseFieldFocused) { _, focused in
                if focused {
                    savedSplitRatio = splitRatio
                    withAnimation(.easeInOut(duration: 0.25)) { splitRatio = 0.05 }
                } else if let saved = savedSplitRatio {
                    withAnimation(.easeInOut(duration: 0.25)) { splitRatio = saved }
                    savedSplitRatio = nil
                }
            }
            #endif
            .onChange(of: httpData.method) { _, newMethod in
                let bodyMethods: Set<HttpMethod> = [.post, .put, .patch]
                if bodyMethods.contains(newMethod) && httpData.bodyType == .none {
                    var updated = request
                    var data = updated.httpData ?? HttpRequestData()
                    data.bodyType = .json
                    updated.httpData = data
                    updated.updatedAt = Date()
                    store.updateRequest(updated)
                }
                if strictHttpMode && !newMethod.conventionallyHasBody && selectedTab == .body {
                    selectedTab = .params
                }
            }
            .onChange(of: strictHttpMode) { _, isStrict in
                if isStrict && !httpData.method.conventionallyHasBody && selectedTab == .body {
                    selectedTab = .params
                }
            }
    }
}
