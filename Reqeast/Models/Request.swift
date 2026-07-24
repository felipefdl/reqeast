//
//  Request.swift
//  Reqeast
//

import Foundation

enum RequestType: String, Codable, CaseIterable, Hashable {
    case http
    case tcp
    case udp
    case webSocket
    case sse
    case grpc

    var localizedName: String {
        switch self {
        case .http:      return "HTTP"
        case .tcp:       return "TCP"
        case .udp:       return "UDP"
        case .webSocket: return "WebSocket"
        case .sse:       return "SSE"
        case .grpc:      return "gRPC"
        }
    }

    var iconName: String {
        switch self {
        case .http:      return "arrow.up.arrow.down"
        case .tcp:       return "cable.connector"
        case .udp:       return "dot.radiowaves.up.forward"
        case .webSocket: return "arrow.left.arrow.right"
        case .sse:       return "antenna.radiowaves.left.and.right"
        case .grpc:      return "arrow.up.right.and.arrow.down.left"
        }
    }
}

struct Request: Codable, Identifiable, Hashable {
    var id: UUID
    var projectId: UUID
    var name: String
    var type: RequestType
    var folderId: UUID?
    var sortOrder: Int
    var isRenamed: Bool
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var specIdentity: SpecOperationIdentity?
    var specLastSyncedAt: Date?
    var isSpecStale: Bool = false
    /// SHA-256 hex of canonical JSON `SpecOperationSnapshot`; synced for Rule A.
    var specFieldFingerprint: String?
    /// Gzip JSON snapshot for multi-device hydrate when disk file is missing; size-capped.
    var specSnapshotPayload: Data?
    var schemaVersion: Int = CloudSyncableSchema.currentVersion

    // Protocol-specific configs (only one populated based on type)
    var httpData: HttpRequestData?
    var tcpData: TcpRequestData?
    var udpData: UdpRequestData?
    var webSocketData: WebSocketRequestData?
    var sseData: SseRequestData?
    var grpcData: GrpcRequestData?

    init(
        id: UUID = UUID(),
        projectId: UUID,
        name: String,
        type: RequestType = .http,
        folderId: UUID? = nil,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.projectId = projectId
        self.name = name
        self.type = type
        self.folderId = folderId
        self.sortOrder = sortOrder
        self.isRenamed = false
        self.createdAt = Date()
        self.updatedAt = Date()
        self.deletedAt = nil

        switch type {
        case .http:
            self.httpData = HttpRequestData()
        case .tcp:
            self.tcpData = TcpRequestData()
        case .udp:
            self.udpData = UdpRequestData()
        case .webSocket:
            self.webSocketData = WebSocketRequestData()
        case .sse:
            self.sseData = SseRequestData()
        case .grpc:
            self.grpcData = GrpcRequestData()
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        projectId = try container.decode(UUID.self, forKey: .projectId)
        name = try container.decode(String.self, forKey: .name)
        type = try container.decode(RequestType.self, forKey: .type)
        folderId = try container.decodeIfPresent(UUID.self, forKey: .folderId)
        sortOrder = try container.decode(Int.self, forKey: .sortOrder)
        isRenamed = try container.decodeIfPresent(Bool.self, forKey: .isRenamed) ?? false
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? .distantPast
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .distantPast
        httpData = try container.decodeIfPresent(HttpRequestData.self, forKey: .httpData)
        tcpData = try container.decodeIfPresent(TcpRequestData.self, forKey: .tcpData)
        udpData = try container.decodeIfPresent(UdpRequestData.self, forKey: .udpData)
        webSocketData = try container.decodeIfPresent(WebSocketRequestData.self, forKey: .webSocketData)
        sseData = try container.decodeIfPresent(SseRequestData.self, forKey: .sseData)
        grpcData = try container.decodeIfPresent(GrpcRequestData.self, forKey: .grpcData)
        deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
        specIdentity = try container.decodeIfPresent(SpecOperationIdentity.self, forKey: .specIdentity)
        specLastSyncedAt = try container.decodeIfPresent(Date.self, forKey: .specLastSyncedAt)
        isSpecStale = try container.decodeIfPresent(Bool.self, forKey: .isSpecStale) ?? false
        specFieldFingerprint = try container.decodeIfPresent(String.self, forKey: .specFieldFingerprint)
        specSnapshotPayload = try container.decodeIfPresent(Data.self, forKey: .specSnapshotPayload)
        schemaVersion = try CloudSyncableSchema.decodeVersion(from: container, forKey: .schemaVersion)
    }
}
