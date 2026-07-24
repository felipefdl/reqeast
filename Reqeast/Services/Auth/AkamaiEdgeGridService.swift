//
//  AkamaiEdgeGridService.swift
//  Reqeast
//

import CryptoKit
import Foundation

enum AkamaiEdgeGridService {
    static func generateHeader(
        url: String,
        method: String,
        body: Data?,
        clientToken: String,
        clientSecret: String,
        accessToken: String,
        timestamp: String? = nil,
        nonce: String? = nil
    ) -> String? {
        guard let urlComponents = URLComponents(string: url),
              let host = urlComponents.host else { return nil }

        let timestamp = timestamp ?? edgeGridTimestamp()
        let nonce = nonce ?? generateNonce()
        let path = urlComponents.path.isEmpty ? "/" : urlComponents.path

        let bodyHash = computeBodyHash(body: body, method: method, clientSecret: clientSecret)

        let authHeader = "EG1-HMAC-SHA256 client_token=\(clientToken);access_token=\(accessToken);timestamp=\(timestamp);nonce=\(nonce);"

        let dataToSign = [
            method.uppercased(),
            "https",
            host,
            path,
            "", // canonical headers (empty for basic)
            bodyHash,
            authHeader,
        ].joined(separator: "\t")

        guard let signingKey = deriveSigningKey(clientSecret: clientSecret, timestamp: timestamp),
              let dataBytes = dataToSign.data(using: .utf8) else { return nil }

        let key = SymmetricKey(data: signingKey)
        let signature = Data(HMAC<SHA256>.authenticationCode(for: dataBytes, using: key))
            .base64EncodedString()

        return "\(authHeader)signature=\(signature)"
    }

    private static func edgeGridTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd'T'HH:mm:ss+0000"
        return formatter.string(from: Date())
    }

    private static func generateNonce() -> String {
        UUID().uuidString.lowercased()
    }

    private static func computeBodyHash(body: Data?, method: String, clientSecret: String) -> String {
        let upperMethod = method.uppercased()
        guard upperMethod == "POST" || upperMethod == "PUT",
              let body, !body.isEmpty else { return "" }

        let maxBody = 131072 // 128KB
        let truncated = body.prefix(maxBody)
        let hash = SHA256.hash(data: truncated)
        return Data(hash).base64EncodedString()
    }

    private static func deriveSigningKey(clientSecret: String, timestamp: String) -> Data? {
        guard let secretData = Data(base64Encoded: clientSecret) else {
            guard let rawData = clientSecret.data(using: .utf8) else { return nil }
            guard let tsData = timestamp.data(using: .utf8) else { return nil }
            let key = SymmetricKey(data: rawData)
            return Data(HMAC<SHA256>.authenticationCode(for: tsData, using: key))
        }
        guard let tsData = timestamp.data(using: .utf8) else { return nil }
        let key = SymmetricKey(data: secretData)
        return Data(HMAC<SHA256>.authenticationCode(for: tsData, using: key))
    }
}
