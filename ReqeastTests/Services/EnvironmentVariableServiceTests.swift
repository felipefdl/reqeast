//
//  EnvironmentVariableServiceTests.swift
//  ReqeastTests
//

import Foundation
import Testing
@testable import Reqeast

@Suite("EnvironmentVariableService")
struct EnvironmentVariableServiceTests {
    @Test func substitutesVariables() {
        let env = ApiEnvironment(
            projectId: UUID(),
            name: "Dev",
            variables: [
                EnvironmentVariable(key: "host", value: "localhost"),
                EnvironmentVariable(key: "port", value: "8080"),
            ],
            isActive: true
        )
        let result = EnvironmentVariableService.substitute(
            "https://{{host}}:{{port}}/api",
            environment: env
        )
        #expect(result == "https://localhost:8080/api")
    }

    @Test func returnsInputWhenNoEnvironment() {
        let result = EnvironmentVariableService.substitute("{{host}}/api", environment: nil)
        #expect(result == "{{host}}/api")
    }

    @Test func skipsDisabledVariables() {
        let env = ApiEnvironment(
            projectId: UUID(),
            name: "Dev",
            variables: [
                EnvironmentVariable(key: "host", value: "localhost", enabled: false),
            ],
            isActive: true
        )
        let result = EnvironmentVariableService.substitute("{{host}}", environment: env)
        #expect(result == "{{host}}")
    }

    @Test func handlesUnknownVariables() {
        let env = ApiEnvironment(
            projectId: UUID(),
            name: "Dev",
            variables: [
                EnvironmentVariable(key: "host", value: "localhost"),
            ],
            isActive: true
        )
        let result = EnvironmentVariableService.substitute("{{host}}:{{port}}", environment: env)
        #expect(result == "localhost:{{port}}")
    }

    @Test func handlesEmptyInput() {
        let env = ApiEnvironment(projectId: UUID(), name: "Dev")
        let result = EnvironmentVariableService.substitute("", environment: env)
        #expect(result == "")
    }

    @Test func handlesMultipleOccurrences() {
        let env = ApiEnvironment(
            projectId: UUID(),
            name: "Dev",
            variables: [
                EnvironmentVariable(key: "token", value: "abc123"),
            ],
            isActive: true
        )
        let result = EnvironmentVariableService.substitute("{{token}} and {{token}}", environment: env)
        #expect(result == "abc123 and abc123")
    }
}
