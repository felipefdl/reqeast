//
//  AwsSignatureService.swift
//  Reqeast
//

import CryptoKit
import Foundation

enum AwsSignatureService {
    static func generateHeaders(
        url: String,
        method: String,
        headers: [(String, String)],
        body: Data?,
        accessKey: String,
        secretKey: String,
        region: String,
        service: String,
        sessionToken: String,
        date: Date = Date()
    ) -> [(String, String)]? {
        guard let urlComponents = URLComponents(string: url),
              let host = urlComponents.host else { return nil }

        let now = date
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone(identifier: "UTC")

        dateFormatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        let amzDate = dateFormatter.string(from: now)

        dateFormatter.dateFormat = "yyyyMMdd"
        let dateStamp = dateFormatter.string(from: now)

        let payloadHash = sha256Hex(body ?? Data())
        let path = urlComponents.path.isEmpty ? "/" : urlComponents.path
        let query = canonicalQueryString(urlComponents)

        var signedHeaders = headers.map { ($0.0.lowercased(), $0.1) }
        signedHeaders.append(("host", host))
        signedHeaders.append(("x-amz-date", amzDate))
        signedHeaders.append(("x-amz-content-sha256", payloadHash))
        if !sessionToken.isEmpty {
            signedHeaders.append(("x-amz-security-token", sessionToken))
        }
        signedHeaders.sort { $0.0 < $1.0 }

        let signedHeaderNames = signedHeaders.map(\.0).joined(separator: ";")
        let canonicalHeaders = signedHeaders.map { "\($0.0):\($0.1)\n" }.joined()

        let canonicalRequest = [
            method.uppercased(),
            path,
            query,
            canonicalHeaders,
            signedHeaderNames,
            payloadHash,
        ].joined(separator: "\n")

        let credentialScope = "\(dateStamp)/\(region)/\(service)/aws4_request"
        let stringToSign = [
            "AWS4-HMAC-SHA256",
            amzDate,
            credentialScope,
            sha256Hex(canonicalRequest.data(using: .utf8)!),
        ].joined(separator: "\n")

        guard let signingKey = deriveSigningKey(
            secretKey: secretKey,
            dateStamp: dateStamp,
            region: region,
            service: service
        ) else { return nil }

        let signature = hmacSHA256Hex(key: signingKey, data: stringToSign.data(using: .utf8)!)
        let authorization = "AWS4-HMAC-SHA256 Credential=\(accessKey)/\(credentialScope), SignedHeaders=\(signedHeaderNames), Signature=\(signature)"

        var result: [(String, String)] = [
            ("Authorization", authorization),
            ("x-amz-date", amzDate),
            ("x-amz-content-sha256", payloadHash),
        ]
        if !sessionToken.isEmpty {
            result.append(("x-amz-security-token", sessionToken))
        }
        return result
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func hmacSHA256(_ key: Data, _ data: Data) -> Data {
        let key = SymmetricKey(data: key)
        return Data(HMAC<SHA256>.authenticationCode(for: data, using: key))
    }

    private static func hmacSHA256Hex(key: Data, data: Data) -> String {
        hmacSHA256(key, data).map { String(format: "%02x", $0) }.joined()
    }

    private static func deriveSigningKey(
        secretKey: String,
        dateStamp: String,
        region: String,
        service: String
    ) -> Data? {
        guard let kSecret = "AWS4\(secretKey)".data(using: .utf8) else { return nil }
        let kDate = hmacSHA256(kSecret, dateStamp.data(using: .utf8)!)
        let kRegion = hmacSHA256(kDate, region.data(using: .utf8)!)
        let kService = hmacSHA256(kRegion, service.data(using: .utf8)!)
        return hmacSHA256(kService, "aws4_request".data(using: .utf8)!)
    }

    private static func canonicalQueryString(_ components: URLComponents) -> String {
        guard let items = components.queryItems, !items.isEmpty else { return "" }
        return items
            .sorted { $0.name < $1.name }
            .map { "\(uriEncode($0.name))=\(uriEncode($0.value ?? ""))" }
            .joined(separator: "&")
    }

    private static func uriEncode(_ string: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return string.addingPercentEncoding(withAllowedCharacters: allowed) ?? string
    }
}
