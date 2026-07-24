//
//  AiImportParser.swift
//  Reqeast
//

import Foundation
import FoundationModels

@Generable
struct AiParsedRequest {
    @Guide(description: "HTTP method (GET, POST, PUT, DELETE, PATCH, HEAD, OPTIONS)")
    var method: String

    @Guide(description: "The full URL including scheme, host, path, and query string")
    var url: String

    @Guide(description: "HTTP headers as key-value pairs")
    var headers: [AiHeader]

    @Guide(description: "Request body content, empty string if none")
    var body: String

    @Guide(description: "Query parameters as key-value pairs")
    var queryParams: [AiKeyValue]

    @Guide(description: "Basic auth username, empty string if none")
    var basicAuthUser: String

    @Guide(description: "Basic auth password, empty string if none")
    var basicAuthPassword: String
}

@Generable
struct AiHeader {
    @Guide(description: "Header name")
    var name: String
    @Guide(description: "Header value")
    var value: String
}

@Generable
struct AiKeyValue {
    @Guide(description: "Parameter name")
    var name: String
    @Guide(description: "Parameter value")
    var value: String
}

// MARK: - Parser

@MainActor
enum AiImportParser {

    static var isAvailable: Bool {
        SystemLanguageModel.default.availability == .available
    }

    static func parse(_ input: String) async throws -> ImportedRequestData {
        let session = LanguageModelSession(instructions: """
            You are an HTTP request parser. Extract the HTTP request details from the given text.
            The text may be a curl command, wget command, httpie command, raw HTTP request,
            or a natural language description of an API request.
            Extract: method, URL, headers, body, query parameters, and authentication.
            If a field is not present, use an empty string.
            """)

        let options = GenerationOptions(sampling: .greedy)

        let response = try await session.respond(
            to: input,
            generating: AiParsedRequest.self,
            options: options
        )

        return mapToImportedData(response.content)
    }

    private static func mapToImportedData(_ parsed: AiParsedRequest) -> ImportedRequestData {
        var data = ImportedRequestData()
        data.method = parsed.method.isEmpty ? nil : parsed.method.uppercased()
        data.url = parsed.url
        data.headers = parsed.headers.map { (name: $0.name, value: $0.value) }
        data.body = parsed.body.isEmpty ? nil : parsed.body
        data.queryParams = parsed.queryParams.map { (name: $0.name, value: $0.value) }
        data.basicAuthUser = parsed.basicAuthUser.isEmpty ? nil : parsed.basicAuthUser
        data.basicAuthPassword = parsed.basicAuthPassword.isEmpty ? nil : parsed.basicAuthPassword
        return data
    }
}
