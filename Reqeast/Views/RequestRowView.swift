//
//  RequestRowView.swift
//  Reqeast
//

import SwiftUI

struct RequestRowView: View {
    let request: Request

    private var registry: SessionRegistry { SessionRegistry.shared }

    private var unread: Int {
        registry.unreadCount(for: request.id)
    }

    private var isActive: Bool {
        registry.hasActivity(for: request.id)
    }

    var body: some View {
        HStack(spacing: 10) {
            RequestMethodBadge(request: request)

            VStack(alignment: .leading, spacing: 2) {
                Text(request.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .accessibilityIdentifier("request-\(request.name)")

                Text(urlPreview)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if unread > 0 {
                Text("\(unread)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .glassEffect(.regular.tint(.blue), in: .capsule)
            } else if request.isSpecStale {
                Circle()
                    .fill(.orange)
                    .frame(width: 8, height: 8)
                    .accessibilityLabel(String(localized: "Removed from spec"))
            } else if isActive {
                Circle()
                    .fill(.green)
                    .frame(width: 8, height: 8)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
    }

    private var urlPreview: String {
        switch request.type {
        case .http:
            let url = request.httpData?.url ?? ""
            return url.isEmpty ? String(localized: "No URL") : url
        case .tcp:
            let host = request.tcpData?.host ?? ""
            let port = request.tcpData?.port ?? 80
            return host.isEmpty ? String(localized: "No host") : "\(host):\(port)"
        case .udp:
            let host = request.udpData?.host ?? ""
            let port = request.udpData?.port ?? 8080
            return host.isEmpty ? String(localized: "No host") : "\(host):\(port)"
        case .webSocket:
            let url = request.webSocketData?.url ?? ""
            return url.isEmpty ? String(localized: "No URL") : url
        case .sse:
            let url = request.sseData?.url ?? ""
            return url.isEmpty ? String(localized: "No URL") : url
        case .grpc:
            let authority = request.grpcData?.authority ?? ""
            return authority.isEmpty ? String(localized: "No authority") : authority
        }
    }
}
