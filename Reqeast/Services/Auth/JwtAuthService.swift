//
//  JwtAuthService.swift
//  Reqeast
//

import CryptoKit
import Foundation

enum JwtAuthService {
    static func generateToken(
        algorithm: JwtAlgorithm,
        secret: String,
        payload: String,
        base64Encoded: Bool
    ) -> String? {
        let header = #"{"alg":"\#(algorithm.rawValue)","typ":"JWT"}"#

        guard let headerData = header.data(using: .utf8),
              let payloadData = payload.data(using: .utf8) else { return nil }

        let headerB64 = base64UrlEncode(headerData)
        let payloadB64 = base64UrlEncode(payloadData)
        let signingInput = "\(headerB64).\(payloadB64)"

        guard let signingInputData = signingInput.data(using: .utf8) else { return nil }

        let keyData: Data
        if base64Encoded {
            guard let decoded = Data(base64Encoded: secret) else { return nil }
            keyData = decoded
        } else {
            guard let data = secret.data(using: .utf8) else { return nil }
            keyData = data
        }

        let signatureData: Data
        switch algorithm {
        case .hs256:
            let key = SymmetricKey(data: keyData)
            signatureData = Data(HMAC<SHA256>.authenticationCode(for: signingInputData, using: key))
        case .hs384:
            let key = SymmetricKey(data: keyData)
            signatureData = Data(HMAC<SHA384>.authenticationCode(for: signingInputData, using: key))
        case .hs512:
            let key = SymmetricKey(data: keyData)
            signatureData = Data(HMAC<SHA512>.authenticationCode(for: signingInputData, using: key))
        }

        let signatureB64 = base64UrlEncode(signatureData)
        return "\(signingInput).\(signatureB64)"
    }

    private static func base64UrlEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
