//
//  GrpcRequestView+MacOS.swift
//  Reqeast
//

import SwiftUI

#if os(macOS)
extension GrpcRequestFullView {
    var macOSSendOrConnect: (() -> Void)? {
        if isUnary {
            return canSend ? { sendUnary() } : nil
        }
        switch effectiveRpcKind {
        case .serverStreaming:
            return canSendStream ? { sendStreamMessage() } : nil
        case .clientStreaming, .bidirectional:
            return canConnectStream ? { connectStream() } : (canSendStream ? { sendStreamMessage() } : nil)
        case .unary:
            return nil
        }
    }

    var macOSCancelOrDisconnect: (() -> Void)? {
        guard !isUnary, canCancelStream else { return nil }
        return { cancelStream() }
    }

    var macOSCanSendOrConnect: Bool {
        if isUnary { return canSend }
        return canConnectStream || canSendStream
    }

    var macOSCanCancelOrDisconnect: Bool {
        !isUnary && canCancelStream
    }

    var macOSClearMessages: (() -> Void)? {
        guard !isUnary, !sessionStore.messages.isEmpty else { return nil }
        return { sessionStore.clear() }
    }

    var macOSHasMessages: Bool {
        !isUnary && !sessionStore.messages.isEmpty
    }
}
#endif