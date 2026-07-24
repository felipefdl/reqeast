//
//  CurlConverterMapper.swift
//  Reqeast
//

import Foundation

enum CurlConverterMapper {

    static func map(_ json: CurlConverterJSON) -> ParsedImportResult {
        var data = ImportedRequestData()

        data.method = json.method.uppercased()
        data.url = json.url

        // Headers
        if let headers = json.headers {
            data.headers = headers.map { (name: $0.key, value: $0.value) }
        }

        // Query params from curlconverter's parsed queries
        if let queries = json.queries {
            for (key, value) in queries {
                switch value {
                case .single(let v):
                    data.queryParams.append((name: key, value: v))
                case .array(let values):
                    for v in values {
                        data.queryParams.append((name: key, value: v))
                    }
                }
            }
        }

        // Auth
        if let auth = json.auth {
            data.basicAuthUser = auth.user
            data.basicAuthPassword = auth.password
        }

        // Body
        if let bodyData = json.data {
            if bodyData.count == 1, let entry = bodyData.first, entry.value.isEmpty {
                // Single key with empty value = raw body string
                data.body = entry.key
            } else {
                // Multiple key-value pairs = form-encoded body
                let pairs = bodyData.map { "\($0.key)=\($0.value)" }
                data.body = pairs.joined(separator: "&")
            }
        }

        // Form file uploads
        if let files = json.files {
            data.bodyIsForm = true
            for (key, value) in files {
                data.formFields.append((name: key, value: "@\(value)"))
            }
            // Also include non-file form data
            if let bodyData = json.data {
                for (key, value) in bodyData {
                    data.formFields.append((name: key, value: value))
                }
            }
        }

        // Insecure
        if json.insecure != nil {
            data.insecure = true
        }

        // Cookies
        let cookies = json.cookies ?? [:]

        return ParsedImportResult(data: data, cookies: cookies)
    }
}
