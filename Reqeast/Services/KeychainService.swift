//
//  KeychainService.swift
//  Reqeast
//

import Foundation
import Security

struct RequestCredentials: Codable {
    var bearerToken: String?
    var username: String?
    var password: String?
    var apiKeyName: String?
    var apiKeyValue: String?
    var authData: HttpAuthData?
}

enum KeychainError: Error {
    case duplicateEntry
    case unknown(OSStatus)
    case notFound
    case encodingFailed
    case decodingFailed
}

final class KeychainService {
    static let shared = KeychainService()

    private let service = "\(StorageEnvironment.keyPrefix)com.reqeast.credentials"

    private init() {}

    func saveCredentials(_ credentials: RequestCredentials, for requestId: UUID) throws {
        guard let data = try? JSONEncoder().encode(credentials) else {
            throw KeychainError.encodingFailed
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: requestId.uuidString,
            kSecAttrSynchronizable as String: kCFBooleanTrue!,
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        // Try update first
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        if updateStatus == errSecItemNotFound {
            // Item doesn't exist, add it
            var addQuery = query
            addQuery.merge(attributes) { _, new in new }
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.unknown(addStatus)
            }
        } else if updateStatus != errSecSuccess {
            throw KeychainError.unknown(updateStatus)
        }
    }

    func loadCredentials(for requestId: UUID) throws -> RequestCredentials {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: requestId.uuidString,
            kSecAttrSynchronizable as String: kCFBooleanTrue!,
            kSecReturnData as String: true,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                throw KeychainError.notFound
            }
            throw KeychainError.unknown(status)
        }

        guard let data = item as? Data,
              let credentials = try? JSONDecoder().decode(RequestCredentials.self, from: data)
        else {
            throw KeychainError.decodingFailed
        }

        return credentials
    }

    func deleteCredentials(for requestId: UUID) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: requestId.uuidString,
            kSecAttrSynchronizable as String: kCFBooleanTrue!,
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unknown(status)
        }
    }

    func deleteAllCredentials() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrSynchronizable as String: kCFBooleanTrue!,
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unknown(status)
        }
    }
}
