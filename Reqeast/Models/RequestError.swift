//
//  RequestError.swift
//  Reqeast
//

import CloudKit
import Foundation

enum RequestErrorKind: String, Codable {
    case timeout
    case connectionFailed
    case tlsError
    case notConnected
    case invalidConfig
    case httpError
    case webSocketError
    case sseError
    case grpcError
    case unknown
    case cloudSync
    case cloudQuotaExceeded
    case cloudNotAuthenticated
    case cloudPermanentFailure
    case cloudDecodeError
    case cloudConflictUnresolvable
    case cloudRecordTooLarge
}

struct RequestError: Codable, Equatable {
    let kind: RequestErrorKind
    let message: String

    var localizedTitle: String {
        switch kind {
        case .timeout: String(localized: "Request Timed Out")
        case .connectionFailed: String(localized: "Connection Failed")
        case .tlsError: String(localized: "TLS Error")
        case .notConnected: String(localized: "Not Connected")
        case .invalidConfig: String(localized: "Invalid Configuration")
        case .httpError: String(localized: "Request Failed")
        case .webSocketError: String(localized: "WebSocket Error")
        case .sseError: String(localized: "SSE Error")
        case .grpcError: String(localized: "gRPC Error")
        case .unknown: String(localized: "Request Failed")
        case .cloudSync: String(localized: "iCloud Sync Error")
        case .cloudQuotaExceeded: String(localized: "iCloud Storage Full")
        case .cloudNotAuthenticated: String(localized: "iCloud Not Signed In")
        case .cloudPermanentFailure: String(localized: "iCloud Sync Failed")
        case .cloudDecodeError: String(localized: "iCloud Data Could Not Be Read")
        case .cloudConflictUnresolvable: String(localized: "iCloud Conflict")
        case .cloudRecordTooLarge: String(localized: "Record Too Large for iCloud")
        }
    }

    var iconName: String {
        switch kind {
        case .timeout: "clock.badge.exclamationmark"
        case .connectionFailed: "wifi.slash"
        case .tlsError: "lock.trianglebadge.exclamationmark"
        case .notConnected: "cable.connector.slash"
        case .invalidConfig: "gear.badge.xmark"
        case .httpError: "exclamationmark.triangle"
        case .webSocketError: "arrow.up.arrow.down.circle"
        case .sseError: "antenna.radiowaves.left.and.right.slash"
        case .grpcError: "arrow.up.right.and.arrow.down.left"
        case .unknown: "exclamationmark.circle"
        case .cloudSync: "exclamationmark.icloud"
        case .cloudQuotaExceeded: "icloud.slash"
        case .cloudNotAuthenticated: "person.icloud"
        case .cloudPermanentFailure: "exclamationmark.icloud.fill"
        case .cloudDecodeError: "doc.badge.ellipsis"
        case .cloudConflictUnresolvable: "arrow.triangle.2.circlepath.icloud"
        case .cloudRecordTooLarge: "doc.badge.plus"
        }
    }

    static func from(_ error: Error) -> RequestError {
        if let reqeastError = error as? ReqeastError {
            return from(reqeastError)
        }
        let typeName = String(describing: type(of: error))
        let desc = error.localizedDescription
        return RequestError(kind: .unknown, message: "\(typeName): \(desc)")
    }

    static func from(_ error: ReqeastError) -> RequestError {
        switch error {
        case .HttpError(let msg):
            RequestError(kind: .httpError, message: cleanReqwestMessage(msg))
        case .ConnectionFailed(let msg):
            RequestError(kind: .connectionFailed, message: cleanReqwestMessage(msg))
        case .Timeout(let msg):
            RequestError(kind: .timeout, message: cleanReqwestMessage(msg))
        case .NotConnected:
            RequestError(kind: .notConnected, message: String(localized: "Not connected"))
        case .TlsError(let msg):
            RequestError(kind: .tlsError, message: msg)
        case .InvalidConfig(let msg):
            RequestError(kind: .invalidConfig, message: msg)
        case .InternalError(let msg):
            RequestError(kind: .unknown, message: msg)
        case .WebSocketError(let msg):
            RequestError(kind: .webSocketError, message: msg)
        case .SseError(let msg):
            RequestError(kind: .sseError, message: msg)
        }
    }

    /// Strips the outer reqwest wrapper from error messages.
    /// reqwest errors follow the pattern:
    ///   "error sending request for url (https://...): error trying to connect: dns error: ..."
    /// We strip only the "error sending request for url (URL): " prefix and keep
    /// the full remaining chain, which shows the actual cause.
    private static func cleanReqwestMessage(_ raw: String) -> String {
        let reqwestPrefix = "error sending request for url ("
        guard raw.hasPrefix(reqwestPrefix) else { return raw }
        // Find the closing paren + colon separator after the URL
        guard let closingParen = raw.range(of: "): ", range: raw.index(raw.startIndex, offsetBy: reqwestPrefix.count)..<raw.endIndex) else {
            return raw
        }
        let remainder = String(raw[closingParen.upperBound...])
        return remainder.isEmpty ? raw : remainder
    }

    static func from(message: String, kind: RequestErrorKind = .unknown) -> RequestError {
        RequestError(kind: kind, message: message)
    }

    /// Classifies a CloudKit error into a typed `RequestError`. The full chain is preserved
    /// in `message` so it remains copyable from the error sheet.
    static func fromCloudKit(_ error: Error) -> RequestError {
        if let ckError = error as? CKError {
            return fromCloudKitCode(ckError)
        }
        let typeName = String(describing: type(of: error))
        let desc = error.localizedDescription
        return RequestError(kind: .cloudSync, message: "\(typeName): \(desc)")
    }

    private static func fromCloudKitCode(_ error: CKError) -> RequestError {
        let detail = error.localizedDescription
        switch error.code {
        case .quotaExceeded:
            return RequestError(kind: .cloudQuotaExceeded, message: detail)
        case .notAuthenticated, .managedAccountRestricted, .accountTemporarilyUnavailable:
            return RequestError(kind: .cloudNotAuthenticated, message: detail)
        case .permissionFailure, .invalidArguments, .limitExceeded, .badContainer, .badDatabase,
             .missingEntitlement, .incompatibleVersion, .internalError, .serverRejectedRequest,
             .assetFileNotFound, .assetFileModified, .constraintViolation, .referenceViolation,
             .batchRequestFailed:
            return RequestError(kind: .cloudPermanentFailure, message: "\(error.code): \(detail)")
        default:
            return RequestError(kind: .cloudSync, message: "\(error.code): \(detail)")
        }
    }
}
