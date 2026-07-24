//
//  SpecImportError.swift
//  Reqeast
//

import Foundation

enum SpecImportErrorKind: String, Codable, Equatable {
    case invalidSpec
    case unsupportedFormat
    case parseError
    case unknown
}

extension SpecImportError {
    var kind: SpecImportErrorKind {
        switch self {
        case .InvalidSpec: .invalidSpec
        case .UnsupportedFormat: .unsupportedFormat
        case .ParseError: .parseError
        }
    }

    var message: String {
        switch self {
        case .InvalidSpec(let msg),
             .UnsupportedFormat(let msg),
             .ParseError(let msg):
            msg
        }
    }

    var localizedTitle: String {
        switch kind {
        case .invalidSpec: String(localized: "Invalid Spec")
        case .unsupportedFormat: String(localized: "Unsupported Format")
        case .parseError: String(localized: "Parse Error")
        case .unknown: String(localized: "Import Failed")
        }
    }

    var iconName: String {
        switch kind {
        case .invalidSpec: "doc.badge.exclamationmark"
        case .unsupportedFormat: "doc.questionmark"
        case .parseError: "text.badge.xmark"
        case .unknown: "exclamationmark.circle"
        }
    }

    /// Full copyable error text for error sheets (title + detail).
    var fullMessage: String {
        "\(localizedTitle): \(message)"
    }

    static func from(_ error: Error) -> SpecImportError {
        if let specImportError = error as? SpecImportError {
            return specImportError
        }
        if let reqeastError = error as? ReqeastError {
            return from(reqeastError)
        }
        if let gitError = error as? GitSpecSourceError {
            return .InvalidSpec(gitError.localizedDescription)
        }
        let typeName = String(describing: type(of: error))
        let desc = error.localizedDescription
        return .ParseError("\(typeName): \(desc)")
    }

    static func from(_ error: ReqeastError) -> SpecImportError {
        switch error {
        case .InvalidConfig(let msg):
            .InvalidSpec(msg)
        case .InternalError(let msg):
            .ParseError(msg)
        case .HttpError(let msg),
             .ConnectionFailed(let msg),
             .Timeout(let msg),
             .TlsError(let msg),
             .WebSocketError(let msg),
             .SseError(let msg):
            .ParseError(msg)
        case .NotConnected:
            .ParseError(String(localized: "Not connected"))
        }
    }

    static func from(message: String, kind: SpecImportErrorKind = .unknown) -> SpecImportError {
        switch kind {
        case .invalidSpec:
            .InvalidSpec(message)
        case .unsupportedFormat:
            .UnsupportedFormat(message)
        case .parseError, .unknown:
            .ParseError(message)
        }
    }
}