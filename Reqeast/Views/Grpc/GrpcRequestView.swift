//
//  GrpcRequestView.swift
//  Reqeast
//

import SwiftUI

struct GrpcRequestFullView: View, RequestDataBindable {
    @Bindable var store: ProjectStore
    let request: Request

    @State var cachedDescriptorBytes: Data?
    @State var reflectionServices: [GrpcServiceInfo] = []
    @State var descriptorLoadError: RequestError?
    @State var isDiscovering = false
    @State var isSending = false
    @State var lastResponse: GrpcUnaryResponse?
    @State var sendError: RequestError?
    @State var bodyValidationError: RequestError?
    @State var responseTimestamp = Date()
    @State private var authorityFocusTrigger = false

    var sessionStore: GrpcSessionStore {
        SessionRegistry.shared.grpcSession(for: request.id)
    }

    private var grpcData: GrpcRequestData { readData() }
    var effectiveRpcKind: GrpcRpcKind { resolvedRpcKind(for: grpcData) }
    var isUnary: Bool { effectiveRpcKind == .unary }

    func readData() -> GrpcRequestData {
        request.grpcData ?? GrpcRequestData()
    }

    func writeData(_ data: GrpcRequestData, to request: inout Request) {
        request.grpcData = data
    }

    private var needsReflectionDiscovery: Bool {
        grpcData.schemaSource == .reflection && cachedDescriptorBytes == nil
    }

    private var needsProtoBundleSelection: Bool {
        grpcData.schemaSource == .protoBundle && grpcData.protoBundleId == nil
    }

    private var isProtoBundleReadOnly: Bool {
        guard grpcData.schemaSource == .protoBundle,
              let bundleId = grpcData.protoBundleId,
              let bundle = store.protoBundle(id: bundleId) else {
            return false
        }
        return bundle.isReadOnlyDueToMissingAsset
    }

    var canSend: Bool {
        !isSending
            && !needsReflectionDiscovery
            && !needsProtoBundleSelection
            && !isProtoBundleReadOnly
            && cachedDescriptorBytes != nil
            && !grpcData.authority.isEmpty
            && !grpcData.service.isEmpty
            && !grpcData.method.isEmpty
    }

    var canConnectStream: Bool {
        canSend && !sessionStore.isConnected && !sessionStore.isConnecting
    }

    var canSendStream: Bool {
        guard canSend else { return false }
        switch effectiveRpcKind {
        case .unary:
            return false
        case .serverStreaming:
            return !sessionStore.isConnected && !sessionStore.isConnecting
        case .clientStreaming, .bidirectional:
            return sessionStore.isConnected
        }
    }

    var canHalfCloseStream: Bool {
        sessionStore.isConnected
            && (effectiveRpcKind == .clientStreaming || effectiveRpcKind == .bidirectional)
    }

    var canCancelStream: Bool {
        sessionStore.isConnected || sessionStore.isConnecting
    }

    var body: some View {
        VStack(spacing: 0) {
            GrpcConnectionBar(
                store: store,
                request: request,
                rpcKind: effectiveRpcKind,
                sessionStore: isUnary ? nil : sessionStore,
                isSending: isSending,
                canSend: connectionBarCanSend,
                canConnect: canConnectStream,
                onSend: connectionBarSend,
                onConnect: connectStream,
                focusTrigger: $authorityFocusTrigger
            )

            if needsReflectionDiscovery {
                reflectionDiscoveryBanner
            }

            if isProtoBundleReadOnly {
                GrpcReadOnlyBanner()
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    GrpcSchemaPanel(
                        store: store,
                        request: request,
                        isDiscovering: isDiscovering,
                        canSaveDescriptors: cachedDescriptorBytes != nil,
                        onDiscover: discoverFromServer,
                        onSaveDescriptors: saveDescriptorsAsBundle
                    )
                    GrpcMethodPicker(
                        store: store,
                        request: request,
                        services: reflectionServices,
                        isDisabled: isSending || isDiscovering || sessionStore.isConnected || sessionStore.isConnecting
                    )
                    GrpcBodyEditor(
                        bodyMode: binding(\.bodyMode),
                        requestBodyJSON: binding(\.requestBodyJSON),
                        requestBodyHex: binding(\.requestBodyHex),
                        bodyValidationError: bodyValidationError,
                        rpcKind: effectiveRpcKind,
                        canSend: canSendStream,
                        canHalfClose: canHalfCloseStream,
                        canCancel: canCancelStream,
                        onSend: sendStreamMessage,
                        onHalfClose: halfCloseStream,
                        onCancel: cancelStream
                    )
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            if isUnary {
                GrpcResponseLog(
                    isLoading: isSending,
                    response: lastResponse,
                    error: sendError ?? descriptorLoadError,
                    authority: grpcData.authority,
                    responseTimestamp: responseTimestamp
                )
            } else {
                ConversationLog(
                    messages: sessionStore.messages,
                    emptyTitle: "No gRPC Messages",
                    emptyIcon: "arrow.up.right.and.arrow.down.left",
                    emptyDescription: streamEmptyDescription
                )
            }
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        #if !os(macOS)
        .keyboardDismissToolbar()
        #endif
        .task(id: schemaTaskKey) {
            await reloadDescriptorsForSchemaSource()
        }
        #if os(macOS)
        .focusedSceneValue(\.sendOrConnect, macOSSendOrConnect)
        .focusedSceneValue(\.cancelOrDisconnect, macOSCancelOrDisconnect)
        .focusedSceneValue(\.canSendOrConnect, macOSCanSendOrConnect)
        .focusedSceneValue(\.canCancelOrDisconnect, macOSCanCancelOrDisconnect)
        .focusedSceneValue(\.focusUrlField, { authorityFocusTrigger.toggle() })
        .focusedSceneValue(\.clearMessages, macOSClearMessages)
        .focusedSceneValue(\.hasMessages, macOSHasMessages)
        .focusedSceneValue(\.hasResponse, isUnary && lastResponse != nil)
        #endif
    }

    /// Connection-bar Send is unary or start-server-stream; other kinds use Connect / body controls.
    private var connectionBarCanSend: Bool {
        switch effectiveRpcKind {
        case .unary:
            canSend
        case .serverStreaming:
            canSendStream
        case .clientStreaming, .bidirectional:
            false
        }
    }

    private func connectionBarSend() {
        switch effectiveRpcKind {
        case .unary:
            sendUnary()
        case .serverStreaming:
            sendStreamMessage()
        case .clientStreaming, .bidirectional:
            break
        }
    }

    private var streamEmptyDescription: LocalizedStringKey {
        switch effectiveRpcKind {
        case .serverStreaming:
            "Send a request to start receiving stream responses"
        case .clientStreaming, .bidirectional:
            "Connect to start sending stream messages"
        case .unary:
            ""
        }
    }

    private var schemaTaskKey: String {
        let bundleKey = grpcData.protoBundleId?.uuidString ?? "none"
        return "\(request.id.uuidString)-\(grpcData.schemaSource.rawValue)-\(bundleKey)"
    }

    private var reflectionDiscoveryBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .foregroundStyle(.secondary)
                .padding(.top, 1)
            Text("Discover services before sending.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(.orange.opacity(0.3)), in: .rect)
    }
}