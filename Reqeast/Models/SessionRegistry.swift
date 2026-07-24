//
//  SessionRegistry.swift
//  Reqeast
//

import Foundation

@MainActor
@Observable
class SessionRegistry {
    static let shared = SessionRegistry()

    private var httpSessions: [UUID: HttpSessionStore] = [:]
    private var tcpSessions: [UUID: TcpSessionStore] = [:]
    private var udpSessions: [UUID: UdpSessionStore] = [:]
    private var wsSessions: [UUID: WebSocketSessionStore] = [:]
    private var sseSessions: [UUID: SseSessionStore] = [:]
    private var grpcSessions: [UUID: GrpcSessionStore] = [:]
    private var httpExecutions: [UUID: HttpExecutionState] = [:]

    private init() {}

    func httpExecution(for requestId: UUID) -> HttpExecutionState {
        if let existing = httpExecutions[requestId] {
            return existing
        }
        let execution = HttpExecutionState()
        httpExecutions[requestId] = execution
        return execution
    }

    func httpSession(for requestId: UUID) -> HttpSessionStore {
        if let existing = httpSessions[requestId] {
            return existing
        }
        let store = HttpSessionStore()
        httpSessions[requestId] = store
        return store
    }

    func tcpSession(for requestId: UUID) -> TcpSessionStore {
        if let existing = tcpSessions[requestId] {
            return existing
        }
        let store = TcpSessionStore()
        tcpSessions[requestId] = store
        return store
    }

    func udpSession(for requestId: UUID) -> UdpSessionStore {
        if let existing = udpSessions[requestId] {
            return existing
        }
        let store = UdpSessionStore()
        udpSessions[requestId] = store
        return store
    }

    func wsSession(for requestId: UUID) -> WebSocketSessionStore {
        if let existing = wsSessions[requestId] {
            return existing
        }
        let store = WebSocketSessionStore()
        wsSessions[requestId] = store
        return store
    }

    func sseSession(for requestId: UUID) -> SseSessionStore {
        if let existing = sseSessions[requestId] {
            return existing
        }
        let store = SseSessionStore()
        sseSessions[requestId] = store
        return store
    }

    func grpcSession(for requestId: UUID) -> GrpcSessionStore {
        if let existing = grpcSessions[requestId] {
            return existing
        }
        let store = GrpcSessionStore()
        grpcSessions[requestId] = store
        return store
    }

    func unreadCount(for requestId: UUID) -> Int {
        let tcp = tcpSessions[requestId]?.unreadCount ?? 0
        let udp = udpSessions[requestId]?.unreadCount ?? 0
        let ws = wsSessions[requestId]?.unreadCount ?? 0
        let sse = sseSessions[requestId]?.unreadCount ?? 0
        let grpc = grpcSessions[requestId]?.unreadCount ?? 0
        return tcp + udp + ws + sse + grpc
    }

    func hasActivity(for requestId: UUID) -> Bool {
        if let tcp = tcpSessions[requestId], (tcp.isConnected || tcp.isConnecting) {
            return true
        }
        if let udp = udpSessions[requestId], udp.isListening {
            return true
        }
        if let ws = wsSessions[requestId], (ws.isConnected || ws.isConnecting) {
            return true
        }
        if let sse = sseSessions[requestId], (sse.isConnected || sse.isConnecting) {
            return true
        }
        if let grpc = grpcSessions[requestId], (grpc.isConnected || grpc.isConnecting) {
            return true
        }
        return false
    }

    func markRead(for requestId: UUID) {
        tcpSessions[requestId]?.markRead()
        udpSessions[requestId]?.markRead()
        wsSessions[requestId]?.markRead()
        sseSessions[requestId]?.markRead()
        grpcSessions[requestId]?.markRead()
    }

    func removeAllSessions() {
        for (_, tcp) in tcpSessions where tcp.isConnected {
            tcp.disconnect()
        }
        for (_, udp) in udpSessions where udp.isListening {
            udp.stop()
        }
        for (_, ws) in wsSessions where ws.isConnected {
            ws.disconnect()
        }
        for (_, sse) in sseSessions where sse.isConnected {
            sse.disconnect()
        }
        for (_, grpc) in grpcSessions where grpc.isConnected || grpc.isConnecting {
            grpc.disconnect()
        }
        for (_, execution) in httpExecutions where execution.isLoading {
            execution.cancel()
        }
        httpExecutions.removeAll()
        httpSessions.removeAll()
        tcpSessions.removeAll()
        udpSessions.removeAll()
        wsSessions.removeAll()
        sseSessions.removeAll()
        grpcSessions.removeAll()
    }

    func removeSession(for requestId: UUID) {
        if let execution = httpExecutions.removeValue(forKey: requestId), execution.isLoading {
            execution.cancel()
        }
        httpSessions.removeValue(forKey: requestId)
        if let tcp = tcpSessions.removeValue(forKey: requestId), tcp.isConnected {
            tcp.disconnect()
        }
        if let udp = udpSessions.removeValue(forKey: requestId), udp.isListening {
            udp.stop()
        }
        if let ws = wsSessions.removeValue(forKey: requestId), ws.isConnected {
            ws.disconnect()
        }
        if let sse = sseSessions.removeValue(forKey: requestId), sse.isConnected {
            sse.disconnect()
        }
        if let grpc = grpcSessions.removeValue(forKey: requestId),
           grpc.isConnected || grpc.isConnecting {
            grpc.disconnect()
        }
    }
}
