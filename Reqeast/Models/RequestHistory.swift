//
//  RequestHistory.swift
//  Reqeast
//

import Foundation

struct RequestHistoryEntry: Codable, Identifiable {
    var id: UUID
    var requestId: UUID
    var method: String
    var url: String
    var statusCode: Int
    var elapsedMs: Double
    var bodySize: Int64
    var timestamp: Date
    var responseBodyPath: String?
    var httpData: HttpRequestData?

    init(
        id: UUID = UUID(),
        requestId: UUID,
        method: String,
        url: String,
        statusCode: Int,
        elapsedMs: Double,
        bodySize: Int64,
        timestamp: Date = Date(),
        responseBodyPath: String? = nil,
        httpData: HttpRequestData? = nil
    ) {
        self.id = id
        self.requestId = requestId
        self.method = method
        self.url = url
        self.statusCode = statusCode
        self.elapsedMs = elapsedMs
        self.bodySize = bodySize
        self.timestamp = timestamp
        self.responseBodyPath = responseBodyPath
        self.httpData = httpData
    }
}
