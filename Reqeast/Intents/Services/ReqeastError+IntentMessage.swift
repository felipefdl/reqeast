//
//  ReqeastError+IntentMessage.swift
//  Reqeast
//

extension ReqeastError {
    var intentMessage: String {
        switch self {
        case .HttpError(let msg):        "HTTP error: \(msg)"
        case .ConnectionFailed(let msg): "Connection failed: \(msg)"
        case .NotConnected:              "Not connected"
        case .TlsError(let msg):         "TLS error: \(msg)"
        case .InvalidConfig(let msg):    "Invalid configuration: \(msg)"
        case .Timeout(let msg):          "Request timed out: \(msg)"
        case .InternalError(let msg):    "Internal error: \(msg)"
        case .WebSocketError(let msg):   "WebSocket error: \(msg)"
        case .SseError(let msg):         "SSE error: \(msg)"
        }
    }
}
