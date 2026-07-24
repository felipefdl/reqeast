//
//  ApiEnvironmentTests.swift
//  ReqeastTests
//

import Foundation
import Testing
@testable import Reqeast

@Suite("ApiEnvironment Model")
struct ApiEnvironmentTests {
    @Test func defaultInit() {
        let projectId = UUID()
        let env = ApiEnvironment(projectId: projectId, name: "Dev")
        #expect(env.name == "Dev")
        #expect(env.projectId == projectId)
        #expect(env.variables.isEmpty)
        #expect(env.isActive == false)
    }

    @Test func codableRoundtrip() throws {
        let projectId = UUID()
        var env = ApiEnvironment(projectId: projectId, name: "Production", isActive: true)
        env.variables = [
            EnvironmentVariable(key: "API_URL", value: "https://api.example.com", isSecret: false),
            EnvironmentVariable(key: "TOKEN", value: "secret123", isSecret: true),
        ]

        let encoded = try JSONEncoder().encode(env)
        let decoded = try JSONDecoder().decode(ApiEnvironment.self, from: encoded)

        #expect(decoded.id == env.id)
        #expect(decoded.projectId == projectId)
        #expect(decoded.name == "Production")
        #expect(decoded.isActive == true)
        #expect(decoded.variables.count == 2)
        #expect(decoded.variables[0].key == "API_URL")
        #expect(decoded.variables[1].isSecret == true)
    }
}

@Suite("EnvironmentVariable Model")
struct EnvironmentVariableTests {
    @Test func defaultInit() {
        let variable = EnvironmentVariable()
        #expect(variable.key == "")
        #expect(variable.value == "")
        #expect(variable.isSecret == false)
        #expect(variable.enabled == true)
    }

    @Test func isEmptyWhenBothKeyAndValueAreEmpty() {
        let empty = EnvironmentVariable()
        #expect(empty.isEmpty == true)

        let withKey = EnvironmentVariable(key: "HOST")
        #expect(withKey.isEmpty == false)

        let withValue = EnvironmentVariable(value: "localhost")
        #expect(withValue.isEmpty == false)

        let withBoth = EnvironmentVariable(key: "HOST", value: "localhost")
        #expect(withBoth.isEmpty == false)
    }

    @Test func codableRoundtrip() throws {
        let variable = EnvironmentVariable(
            key: "DB_HOST",
            value: "localhost",
            isSecret: true,
            enabled: false
        )

        let encoded = try JSONEncoder().encode(variable)
        let decoded = try JSONDecoder().decode(EnvironmentVariable.self, from: encoded)

        #expect(decoded.id == variable.id)
        #expect(decoded.key == "DB_HOST")
        #expect(decoded.value == "localhost")
        #expect(decoded.isSecret == true)
        #expect(decoded.enabled == false)
    }
}
