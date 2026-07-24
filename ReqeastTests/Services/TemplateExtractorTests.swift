//
//  TemplateExtractorTests.swift
//  ReqeastTests
//

import Foundation
@testable import Reqeast
import Testing

@Suite("TemplateExtractor")
struct TemplateExtractorTests {

    // MARK: - extractVariableNames

    @Test func extractSingleVariable() {
        let result = TemplateExtractor.extractVariableNames(from: "{{host}}/api")
        #expect(result == ["host"])
    }

    @Test func extractMultipleVariables() {
        let result = TemplateExtractor.extractVariableNames(from: "{{host}}:{{port}}")
        #expect(result == ["host", "port"])
    }

    @Test func extractNoVariables() {
        let result = TemplateExtractor.extractVariableNames(from: "https://example.com/api")
        #expect(result.isEmpty)
    }

    @Test func extractDeduplicatesVariables() {
        let result = TemplateExtractor.extractVariableNames(from: "{{host}}/{{host}}/{{port}}")
        #expect(result == ["host", "port"])
    }

    // MARK: - allVariableNames

    @Test func allVariableNamesHttp() {
        let projectId = UUID()
        var request = Request(projectId: projectId, name: "Test", type: .http)
        request.httpData?.url = "https://{{host}}/api"
        request.httpData?.headers = [
            KeyValueEntry(key: "Authorization", value: "Bearer {{token}}", enabled: true)
        ]
        let result = TemplateExtractor.allVariableNames(in: request)
        #expect(result == ["host", "token"])
    }

    @Test func allVariableNamesTcp() {
        let projectId = UUID()
        var request = Request(projectId: projectId, name: "Test", type: .tcp)
        request.tcpData?.host = "{{tcpHost}}"
        let result = TemplateExtractor.allVariableNames(in: request)
        #expect(result == ["tcpHost"])
    }

    @Test func allVariableNamesUdp() {
        let projectId = UUID()
        var request = Request(projectId: projectId, name: "Test", type: .udp)
        request.udpData?.host = "{{udpHost}}"
        let result = TemplateExtractor.allVariableNames(in: request)
        #expect(result == ["udpHost"])
    }

    @Test func allVariableNamesWebSocket() {
        let projectId = UUID()
        var request = Request(projectId: projectId, name: "Test", type: .webSocket)
        request.webSocketData?.url = "ws://{{wsHost}}/chat"
        request.webSocketData?.headers = [
            KeyValueEntry(key: "X-Key", value: "{{wsKey}}", enabled: true)
        ]
        let result = TemplateExtractor.allVariableNames(in: request)
        #expect(result == ["wsHost", "wsKey"])
    }

    @Test func allVariableNamesSse() {
        let projectId = UUID()
        var request = Request(projectId: projectId, name: "Test", type: .sse)
        request.sseData?.url = "https://{{sseHost}}/events"
        request.sseData?.headers = [
            KeyValueEntry(key: "Auth", value: "{{sseToken}}", enabled: true)
        ]
        let result = TemplateExtractor.allVariableNames(in: request)
        #expect(result == ["sseHost", "sseToken"])
    }

    // MARK: - unresolvedVariables

    @Test func unresolvedVariablesAllCovered() {
        let projectId = UUID()
        var request = Request(projectId: projectId, name: "Test", type: .http)
        request.httpData?.url = "https://{{host}}/api"
        let env = ApiEnvironment(
            projectId: projectId,
            name: "Dev",
            variables: [EnvironmentVariable(key: "host", value: "localhost")]
        )
        let result = TemplateExtractor.unresolvedVariables(in: request, environment: env)
        #expect(result.isEmpty)
    }

    @Test func unresolvedVariablesPartialCoverage() {
        let projectId = UUID()
        var request = Request(projectId: projectId, name: "Test", type: .http)
        request.httpData?.url = "https://{{host}}:{{port}}/{{path}}"
        let env = ApiEnvironment(
            projectId: projectId,
            name: "Dev",
            variables: [EnvironmentVariable(key: "host", value: "localhost")]
        )
        let result = TemplateExtractor.unresolvedVariables(in: request, environment: env)
        #expect(result == ["path", "port"])
    }
}
