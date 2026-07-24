//
//  GrpcServiceTests.swift
//  ReqeastTests
//

import Foundation
import Testing
@testable import Reqeast

@Suite("GrpcService")
struct GrpcServiceTests {
    static let fixtureRoot: URL = {
        if let srcRoot = ProcessInfo.processInfo.environment["SRCROOT"] {
            return URL(fileURLWithPath: srcRoot, isDirectory: true)
                .appendingPathComponent("rust/tests/fixtures/grpc", isDirectory: true)
        }
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("rust/tests/fixtures/grpc", isDirectory: true)
    }()

    @Test func compileBundleProducesDescriptorBytes() async throws {
        let bundle = try await GrpcService.compileBundle(
            rootPath: Self.fixtureRoot.path,
            entryFiles: ["hello.proto"]
        )
        #expect(!bundle.descriptorBytes.isEmpty)
        #expect(!bundle.contentFingerprint.isEmpty)
        #expect(bundle.entryFile == "hello.proto")
        #expect(bundle.fileCount >= 1)
    }

    @Test func listServicesFindsGreeter() async throws {
        let bundle = try await GrpcService.compileBundle(
            rootPath: Self.fixtureRoot.path,
            entryFiles: ["hello.proto"]
        )
        let services = try await GrpcService.listServices(descriptorBytes: bundle.descriptorBytes)
        #expect(services.contains { $0.name == "helloworld.Greeter" })
        let greeter = try #require(services.first { $0.name == "helloworld.Greeter" })
        #expect(greeter.methods.contains { $0.name == "SayHello" && $0.rpcKind == .unary })
    }

    @Test func fetchReflectionFailsWhenServerUnreachable() async throws {
        let config = GrpcReflectionConfig(
            authority: "127.0.0.1:1",
            useTls: false,
            allowInsecureTls: false,
            timeoutSecs: 1
        )

        await #expect(throws: ReqeastError.self) {
            try await GrpcService.fetchReflection(config: config)
        }
    }

    @Test func invokeUnaryFailsWhenServerUnreachable() async throws {
        let bundle = try await GrpcService.compileBundle(
            rootPath: Self.fixtureRoot.path,
            entryFiles: ["hello.proto"]
        )
        let config = GrpcConfig(
            authority: "127.0.0.1:1",
            useTls: false,
            allowInsecureTls: false,
            metadata: [],
            service: "helloworld.Greeter",
            method: "SayHello",
            rpcKind: .unary,
            deadlineMs: 0,
            timeoutSecs: 1
        )

        await #expect(throws: ReqeastError.self) {
            try await GrpcService.invokeUnary(
                config: config,
                descriptorBytes: bundle.descriptorBytes,
                requestBody: #"{"name":"Reqeast"}"#,
                bodyIsHex: false
            )
        }
    }

    @Test func grpcErrorKindHasTitleAndIcon() {
        let error = RequestError.from(message: "stream failed", kind: .grpcError)
        #expect(error.localizedTitle == "gRPC Error")
        #expect(error.iconName == "arrow.up.right.and.arrow.down.left")
    }
}