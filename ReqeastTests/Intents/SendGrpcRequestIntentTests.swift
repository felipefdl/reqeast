//
//  SendGrpcRequestIntentTests.swift
//  ReqeastTests
//

import Foundation
import Testing
@testable import Reqeast

@Suite("SendGrpcRequestIntent", .serialized)
struct SendGrpcRequestIntentTests {

    @Test func executeGrpcRejectsMissingConfiguration() async {
        let projectId = UUID()
        var request = Request(projectId: projectId, name: "gRPC", type: .grpc)
        request.grpcData = nil

        await #expect(throws: IntentExecutionError.self) {
            try await IntentExecutionService.executeGrpc(request: request, environment: nil, timeout: 5)
        }
    }

    @Test(arguments: [GrpcRpcKind.serverStreaming, .clientStreaming, .bidirectional])
    func executeGrpcRejectsStreamingRpcKind(rpcKind: GrpcRpcKind) async {
        let projectId = UUID()
        var request = Request(projectId: projectId, name: "gRPC", type: .grpc)
        request.grpcData = GrpcRequestData(rpcKind: rpcKind)

        await #expect(throws: IntentExecutionError.self) {
            try await IntentExecutionService.executeGrpc(request: request, environment: nil, timeout: 5)
        }
    }

    @Test func executeGrpcRejectsMissingProtoBundleId() async {
        let projectId = UUID()
        var request = Request(projectId: projectId, name: "gRPC", type: .grpc)
        request.grpcData = GrpcRequestData(protoBundleId: nil, rpcKind: .unary)

        await #expect(throws: IntentExecutionError.self) {
            try await IntentExecutionService.executeGrpc(request: request, environment: nil, timeout: 5)
        }
    }

    @Test @MainActor func executeGrpcRejectsUnhydratedProtoBundle() async throws {
        let projectId = UUID()
        let bundleId = UUID()
        let bundle = ProtoBundle(
            id: bundleId,
            projectId: projectId,
            name: "Greeter",
            contentFingerprint: "fp",
            entryFile: "hello.proto",
            fileCount: 1,
            assetHydrated: false
        )

        let originalBundles = ProjectStore.shared.protoBundles
        defer { ProjectStore.shared.protoBundles = originalBundles }
        ProjectStore.shared.protoBundles = [bundle]

        var request = Request(projectId: projectId, name: "gRPC", type: .grpc)
        request.grpcData = GrpcRequestData(
            protoBundleId: bundleId,
            service: "helloworld.Greeter",
            method: "SayHello",
            rpcKind: .unary,
            requestBodyJSON: #"{"name":"Reqeast"}"#
        )

        await #expect(throws: IntentExecutionError.self) {
            try await IntentExecutionService.executeGrpc(request: request, environment: nil, timeout: 5)
        }
    }

    @Test @MainActor func executeGrpcLoadsDescriptorBytesFromDisk() async throws {
        guard let fixtureRoot = Self.fixtureRootPath() else {
            Issue.record("hello.proto fixture not found")
            return
        }

        try await withTempProtosRoot { _ in
            let compiled = try await GrpcService.compileBundle(rootPath: fixtureRoot, entryFiles: ["hello.proto"])
            let projectId = UUID()
            let store = ProjectStore.mock()
            let bundle = try store.importProtoBundle(
                projectId: projectId,
                name: "Greeter",
                protoSourceDirectory: URL(fileURLWithPath: fixtureRoot, isDirectory: true),
                entryFile: "hello.proto",
                compiled: compiled
            )

            let originalBundles = ProjectStore.shared.protoBundles
            defer { ProjectStore.shared.protoBundles = originalBundles }
            ProjectStore.shared.protoBundles = store.protoBundles

            var request = Request(projectId: projectId, name: "gRPC", type: .grpc)
            request.grpcData = GrpcRequestData(
                authority: "127.0.0.1:1",
                protoBundleId: bundle.id,
                service: "helloworld.Greeter",
                method: "SayHello",
                rpcKind: .unary,
                requestBodyJSON: #"{"name":"Reqeast"}"#
            )

            #expect(ProjectStore.shared.isGrpcProtoReady(protoBundleId: bundle.id))

            await #expect(throws: ReqeastError.self) {
                try await IntentExecutionService.executeGrpc(request: request, environment: nil, timeout: 1)
            }
        }
    }

    @Test @MainActor func executeGrpcSubstitutesEnvironmentVariables() async throws {
        guard let fixtureRoot = Self.fixtureRootPath() else {
            Issue.record("hello.proto fixture not found")
            return
        }

        try await withTempProtosRoot { _ in
            let compiled = try await GrpcService.compileBundle(rootPath: fixtureRoot, entryFiles: ["hello.proto"])
            let projectId = UUID()
            let store = ProjectStore.mock()
            let bundle = try store.importProtoBundle(
                projectId: projectId,
                name: "Greeter",
                protoSourceDirectory: URL(fileURLWithPath: fixtureRoot, isDirectory: true),
                entryFile: "hello.proto",
                compiled: compiled
            )

            let originalBundles = ProjectStore.shared.protoBundles
            defer { ProjectStore.shared.protoBundles = originalBundles }
            ProjectStore.shared.protoBundles = store.protoBundles

            var request = Request(projectId: projectId, name: "gRPC", type: .grpc)
            request.grpcData = GrpcRequestData(
                authority: "{{grpc_host}}",
                protoBundleId: bundle.id,
                service: "helloworld.Greeter",
                method: "SayHello",
                rpcKind: .unary,
                requestBodyJSON: #"{"name":"{{name}}"}"#
            )

            let environment = ApiEnvironment(
                projectId: projectId,
                name: "Test",
                variables: [
                    EnvironmentVariable(key: "grpc_host", value: "127.0.0.1:1", enabled: true),
                    EnvironmentVariable(key: "name", value: "Reqeast", enabled: true)
                ]
            )

            #expect(ProjectStore.shared.isGrpcProtoReady(protoBundleId: bundle.id))

            await #expect(throws: ReqeastError.self) {
                try await IntentExecutionService.executeGrpc(request: request, environment: environment, timeout: 1)
            }
        }
    }

    private func withTempProtosRoot(
        _ body: @escaping @MainActor (URL) async throws -> Void
    ) async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("grpc-intent-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        try await ProtoBundleService.$protosRootDirectoryOverride.withValue(tempRoot) {
            try await body(tempRoot)
        }
    }

    private static func fixtureRootPath() -> String? {
        if let srcRoot = ProcessInfo.processInfo.environment["SRCROOT"] {
            let path = (srcRoot as NSString).appendingPathComponent("rust/tests/fixtures/grpc")
            if FileManager.default.fileExists(atPath: path) { return path }
        }
        let candidate = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("rust/tests/fixtures/grpc", isDirectory: true)
        return FileManager.default.fileExists(atPath: candidate.path) ? candidate.path : nil
    }
}