//
//  RequestNamingService.swift
//  Reqeast
//

import Foundation
import FoundationModels

@MainActor
struct RequestNamingService {

    static var isAvailable: Bool {
        SystemLanguageModel.default.availability == .available
    }

    static func generateName(method: String, url: String, statusCode: Int, protocolType: String = "HTTP") async -> String? {
        guard isAvailable else { return nil }

        let session = LanguageModelSession()
        let prompt: String
        if protocolType == "WebSocket" || protocolType == "SSE" {
            prompt = """
                Generate a very short name (2-5 words) for this \(protocolType) connection.
                URL: \(url).
                Return only the name, no quotes, no explanation.
                Examples: "Chat Stream", "Live Updates", "Price Feed", "Event Stream"
                """
        } else {
            prompt = """
                Generate a very short name (2-5 words) for this API request.
                Method: \(method), URL: \(url), Status: \(statusCode).
                Return only the name, no quotes, no explanation.
                Examples: "Get Users List", "Create Order", "Delete Session", "Health Check"
                """
        }

        do {
            let response = try await session.respond(to: prompt)
            let name = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? nil : name
        } catch {
            return nil
        }
    }

    static func generateNameForSocket(protocol proto: String, host: String, port: Int) async -> String? {
        guard isAvailable else { return nil }

        let session = LanguageModelSession()
        let prompt = """
            Generate a very short name (2-5 words) for this \(proto) connection.
            Host: \(host), Port: \(port).
            Return only the name, no quotes, no explanation.
            Examples: "Redis Local", "Echo Server", "DNS Query", "MQTT Broker", "Game Server"
            """

        do {
            let response = try await session.respond(to: prompt)
            let name = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? nil : name
        } catch {
            return nil
        }
    }
}
