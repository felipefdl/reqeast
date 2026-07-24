//
//  HawkAuthService.swift
//  Reqeast
//

import CryptoKit
import Foundation

enum HawkAuthService {
    static func generateHeader(
        url: String,
        method: String,
        authId: String,
        authKey: String,
        algorithm: HawkAlgorithm,
        timestamp: Int = Int(Date().timeIntervalSince1970),
        nonce: String = generateNonce()
    ) -> String? {
        guard let urlComponents = URLComponents(string: url),
              let host = urlComponents.host else { return nil }

        let port = urlComponents.port ?? (urlComponents.scheme == "https" ? 443 : 80)
        let path = urlComponents.path.isEmpty ? "/" : urlComponents.path
        let resource = urlComponents.query.map { "\(path)?\($0)" } ?? path

        let normalized = [
            "hawk.1.header",
            "\(timestamp)",
            nonce,
            method.uppercased(),
            resource,
            host.lowercased(),
            "\(port)",
            "", // ext
            "",
        ].joined(separator: "\n")

        guard let keyData = authKey.data(using: .utf8),
              let normalizedData = normalized.data(using: .utf8) else { return nil }

        let key = SymmetricKey(data: keyData)
        let mac: String
        switch algorithm {
        case .sha256:
            let code = HMAC<SHA256>.authenticationCode(for: normalizedData, using: key)
            mac = Data(code).base64EncodedString()
        case .sha512:
            let code = HMAC<SHA512>.authenticationCode(for: normalizedData, using: key)
            mac = Data(code).base64EncodedString()
        }

        return #"Hawk id="\#(authId)", ts="\#(timestamp)", nonce="\#(nonce)", mac="\#(mac)""#
    }

    static func generateNonce() -> String {
        let bytes = (0..<6).map { _ in UInt8.random(in: 0...255) }
        return Data(bytes).base64EncodedString()
    }
}
