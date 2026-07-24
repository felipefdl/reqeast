//
//  GrpcRequestData.swift
//  Reqeast
//

import Foundation

enum GrpcSchemaSource: String, Codable, CaseIterable, Hashable {
    case protoBundle
    case reflection
}

enum GrpcBodyMode: String, Codable, CaseIterable, Hashable {
    case json
    case hex
}

struct GrpcRequestData: Codable, Hashable {
    var authority: String
    var useTls: Bool
    var allowInsecureTls: Bool
    var metadata: [KeyValueEntry]
    var schemaSource: GrpcSchemaSource
    var protoBundleId: UUID?
    var service: String
    var method: String
    var rpcKind: GrpcRpcKind
    var requestBodyJSON: String
    var requestBodyHex: String
    var bodyMode: GrpcBodyMode
    var timeoutSeconds: Int
    var deadlineMs: Int
    var messageHistory: [MessageHistoryEntry]

    init(
        authority: String = "",
        useTls: Bool = false,
        allowInsecureTls: Bool = false,
        metadata: [KeyValueEntry] = [KeyValueEntry()],
        schemaSource: GrpcSchemaSource = .protoBundle,
        protoBundleId: UUID? = nil,
        service: String = "",
        method: String = "",
        rpcKind: GrpcRpcKind = .unary,
        requestBodyJSON: String = "",
        requestBodyHex: String = "",
        bodyMode: GrpcBodyMode = .json,
        timeoutSeconds: Int = 30,
        deadlineMs: Int = 0,
        messageHistory: [MessageHistoryEntry] = []
    ) {
        self.authority = authority
        self.useTls = useTls
        self.allowInsecureTls = allowInsecureTls
        self.metadata = metadata
        self.schemaSource = schemaSource
        self.protoBundleId = protoBundleId
        self.service = service
        self.method = method
        self.rpcKind = rpcKind
        self.requestBodyJSON = requestBodyJSON
        self.requestBodyHex = requestBodyHex
        self.bodyMode = bodyMode
        self.timeoutSeconds = Self.clampedUInt32Field(timeoutSeconds)
        self.deadlineMs = Self.clampedUInt32Field(deadlineMs)
        self.messageHistory = messageHistory
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        authority = try container.decode(String.self, forKey: .authority)
        useTls = try container.decodeIfPresent(Bool.self, forKey: .useTls) ?? false
        allowInsecureTls = try container.decodeIfPresent(Bool.self, forKey: .allowInsecureTls) ?? false
        metadata = try container.decodeIfPresent([KeyValueEntry].self, forKey: .metadata) ?? [KeyValueEntry()]
        schemaSource = try container.decodeIfPresent(GrpcSchemaSource.self, forKey: .schemaSource) ?? .protoBundle
        protoBundleId = try container.decodeIfPresent(UUID.self, forKey: .protoBundleId)
        service = try container.decodeIfPresent(String.self, forKey: .service) ?? ""
        method = try container.decodeIfPresent(String.self, forKey: .method) ?? ""
        rpcKind = try container.decodeIfPresent(GrpcRpcKind.self, forKey: .rpcKind) ?? .unary
        requestBodyJSON = try container.decodeIfPresent(String.self, forKey: .requestBodyJSON) ?? ""
        requestBodyHex = try container.decodeIfPresent(String.self, forKey: .requestBodyHex) ?? ""
        bodyMode = try container.decodeIfPresent(GrpcBodyMode.self, forKey: .bodyMode) ?? .json
        // Clamp before UInt32 casts in send/stream/intent paths (CloudKit/import can supply extremes).
        timeoutSeconds = Self.clampedUInt32Field(
            try container.decodeIfPresent(Int.self, forKey: .timeoutSeconds) ?? 30
        )
        deadlineMs = Self.clampedUInt32Field(
            try container.decodeIfPresent(Int.self, forKey: .deadlineMs) ?? 0
        )
        messageHistory = try container.decodeIfPresent([MessageHistoryEntry].self, forKey: .messageHistory) ?? []
    }

    /// Values that feed `UInt32(...)` must stay in `0...UInt32.max` so casts never trap.
    static func clampedUInt32Field(_ value: Int) -> Int {
        if value < 0 { return 0 }
        if value > Int(UInt32.max) { return Int(UInt32.max) }
        return value
    }
}

// MARK: - GrpcRpcKind Codable

extension GrpcRpcKind: Codable {
    private enum Storage: String, Codable {
        case unary
        case serverStreaming
        case clientStreaming
        case bidirectional
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let storage = Storage(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown GrpcRpcKind: \(raw)"
            )
        }
        switch storage {
        case .unary: self = .unary
        case .serverStreaming: self = .serverStreaming
        case .clientStreaming: self = .clientStreaming
        case .bidirectional: self = .bidirectional
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        let raw: String
        switch self {
        case .unary: raw = Storage.unary.rawValue
        case .serverStreaming: raw = Storage.serverStreaming.rawValue
        case .clientStreaming: raw = Storage.clientStreaming.rawValue
        case .bidirectional: raw = Storage.bidirectional.rawValue
        }
        try container.encode(raw)
    }
}