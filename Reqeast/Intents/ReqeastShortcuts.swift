//
//  ReqeastShortcuts.swift
//  Reqeast
//

import AppIntents

struct ReqeastShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SendHttpRequestIntent(),
            phrases: [
                "Send HTTP request with \(.applicationName)",
                "Run HTTP request in \(.applicationName)"
            ],
            shortTitle: "Send HTTP Request",
            systemImageName: "globe"
        )
        AppShortcut(
            intent: SendTcpMessageIntent(),
            phrases: [
                "Send TCP message with \(.applicationName)",
                "Run TCP request in \(.applicationName)"
            ],
            shortTitle: "Send TCP Message",
            systemImageName: "point.3.connected.trianglepath.dotted"
        )
        AppShortcut(
            intent: SendUdpMessageIntent(),
            phrases: [
                "Send UDP message with \(.applicationName)",
                "Run UDP request in \(.applicationName)"
            ],
            shortTitle: "Send UDP Message",
            systemImageName: "bolt.horizontal"
        )
        AppShortcut(
            intent: SendWebSocketMessageIntent(),
            phrases: [
                "Send WebSocket message with \(.applicationName)",
                "Run WebSocket request in \(.applicationName)"
            ],
            shortTitle: "Send WebSocket Message",
            systemImageName: "arrow.left.arrow.right"
        )
        AppShortcut(
            intent: SendSseRequestIntent(),
            phrases: [
                "Listen to SSE stream with \(.applicationName)",
                "Run SSE request in \(.applicationName)"
            ],
            shortTitle: "Listen to SSE Stream",
            systemImageName: "antenna.radiowaves.left.and.right"
        )
        AppShortcut(
            intent: SendGrpcRequestIntent(),
            phrases: [
                "Send gRPC request with \(.applicationName)",
                "Run gRPC request in \(.applicationName)"
            ],
            shortTitle: "Send gRPC Request",
            systemImageName: "arrow.up.right.and.arrow.down.left"
        )
    }
}
