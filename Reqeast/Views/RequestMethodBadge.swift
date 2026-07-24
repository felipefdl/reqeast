//
//  RequestMethodBadge.swift
//  Reqeast
//

import SwiftUI

struct RequestMethodBadge: View {
    let request: Request

    var body: some View {
        let config = badgeConfig
        Text(config.label)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .glassEffect(.regular.tint(config.color.opacity(0.8)), in: .capsule)
    }

    private var badgeConfig: (label: String, color: Color) {
        switch request.type {
        case .http:
            let method = request.httpData?.method ?? .get
            return (method.shortLabel, method.color)
        case .tcp:
            let useTls = request.tcpData?.useTls ?? false
            return (useTls ? "TLS" : "TCP", useTls ? .cyan : .blue)
        case .udp:
            return ("UDP", .purple)
        case .webSocket:
            return ("WS", .teal)
        case .sse:
            return ("SSE", .orange)
        case .grpc:
            return ("gRPC", .indigo)
        }
    }
}
