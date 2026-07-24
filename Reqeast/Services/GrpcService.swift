//
//  GrpcService.swift
//  Reqeast
//

import Foundation

private func rustFingerprintDescriptorBytes(descriptorBytes: Data) throws -> String {
    try fingerprintDescriptorBytes(descriptorBytes: descriptorBytes)
}

private func rustInvokeUnary(
    config: GrpcConfig,
    descriptorBytes: Data,
    requestBody: String,
    bodyIsHex: Bool
) throws -> GrpcUnaryResponse {
    try invokeUnary(
        config: config,
        descriptorBytes: descriptorBytes,
        requestBody: requestBody,
        bodyIsHex: bodyIsHex
    )
}

enum GrpcService {
    /// Compiles `.proto` entry files into a `FileDescriptorSet`. `@concurrent` because protox compile is synchronous UniFFI.
    @concurrent
    static func compileBundle(rootPath: String, entryFiles: [String]) async throws -> CompiledProtoBundle {
        try compileProtoBundle(rootPath: rootPath, entryFiles: entryFiles)
    }

    /// Lists gRPC services and methods from encoded descriptor bytes.
    @concurrent
    static func listServices(descriptorBytes: Data) async throws -> [GrpcServiceInfo] {
        try listGrpcServices(descriptorBytes: descriptorBytes)
    }

    /// Fetches `FileDescriptorSet` bytes from a reflection-enabled gRPC server.
    /// `@concurrent` because `fetch_reflection_descriptors` blocks via `block_on`.
    @concurrent
    static func fetchReflection(config: GrpcReflectionConfig) async throws -> Data {
        try fetchReflectionDescriptors(config: config)
    }

    /// SHA-256 fingerprint of canonical descriptor bytes (for reflection save).
    @concurrent
    static func fingerprintDescriptorBytes(_ descriptorBytes: Data) async throws -> String {
        try rustFingerprintDescriptorBytes(descriptorBytes: descriptorBytes)
    }

    /// Parses hex wire bytes; use before send to surface validation errors early.
    @concurrent
    static func parseHexBody(_ hex: String) async throws -> Data {
        try hexToWire(hex: hex)
    }

    /// Invokes a unary gRPC RPC. `@concurrent` because `invoke_unary` blocks the caller thread via `block_on`.
    /// Environment variable substitution belongs at the call site (view/intent), not here.
    @concurrent
    static func invokeUnary(
        config: GrpcConfig,
        descriptorBytes: Data,
        requestBody: String,
        bodyIsHex: Bool
    ) async throws -> GrpcUnaryResponse {
        try rustInvokeUnary(
            config: config,
            descriptorBytes: descriptorBytes,
            requestBody: requestBody,
            bodyIsHex: bodyIsHex
        )
    }
}