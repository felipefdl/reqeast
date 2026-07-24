//
//  GrpcRequestView+Send.swift
//  Reqeast
//

import SwiftUI

extension GrpcRequestFullView {
    func reloadDescriptorsForSchemaSource() async {
        cachedDescriptorBytes = nil
        reflectionServices = []
        descriptorLoadError = nil

        switch readData().schemaSource {
        case .protoBundle:
            await loadProtoBundleDescriptors()
        case .reflection:
            break
        }
    }

    func loadProtoBundleDescriptors() async {
        descriptorLoadError = nil
        let data = readData()

        guard let bundleId = data.protoBundleId else {
            descriptorLoadError = RequestError.from(
                message: "Select a proto bundle before sending.",
                kind: .invalidConfig
            )
            return
        }

        guard store.isGrpcProtoReady(protoBundleId: bundleId) else {
            descriptorLoadError = RequestError.from(
                message: "Proto descriptors are unavailable on this device.",
                kind: .invalidConfig
            )
            return
        }

        guard let descriptorBytes = ProtoBundle.loadDescriptorBytes(
            projectId: request.projectId,
            bundleId: bundleId
        ) else {
            descriptorLoadError = RequestError.from(
                message: "Failed to load descriptor bytes for the selected bundle.",
                kind: .invalidConfig
            )
            return
        }

        do {
            cachedDescriptorBytes = descriptorBytes
            reflectionServices = try await GrpcService.listServices(descriptorBytes: descriptorBytes)
        } catch {
            descriptorLoadError = RequestError.from(error)
        }
    }

    func discoverFromServer() {
        guard !isDiscovering else { return }
        isDiscovering = true
        descriptorLoadError = nil
        sendError = nil

        let env = store.activeEnvironment(for: request.projectId)
        let data = readData()
        let authority = EnvironmentVariableService.substitute(data.authority, environment: env)
        let config = GrpcReflectionConfig(
            authority: authority,
            useTls: data.useTls,
            allowInsecureTls: data.allowInsecureTls,
            timeoutSecs: UInt32(clamping: data.timeoutSeconds)
        )

        Task {
            do {
                let descriptorBytes = try await GrpcService.fetchReflection(config: config)
                cachedDescriptorBytes = descriptorBytes
                reflectionServices = try await GrpcService.listServices(descriptorBytes: descriptorBytes)
            } catch {
                descriptorLoadError = RequestError.from(error)
            }
            isDiscovering = false
        }
    }

    func saveDescriptorsAsBundle(name: String) {
        guard let descriptorBytes = cachedDescriptorBytes, !name.isEmpty else { return }
        sendError = nil

        Task {
            do {
                let fingerprint = try await GrpcService.fingerprintDescriptorBytes(descriptorBytes)
                let bundle = try store.saveBundleFromReflection(
                    projectId: request.projectId,
                    name: name,
                    descriptorBytes: descriptorBytes,
                    contentFingerprint: fingerprint
                )
                updateData { data in
                    data.schemaSource = .protoBundle
                    data.protoBundleId = bundle.id
                }
            } catch {
                sendError = RequestError.from(error)
            }
        }
    }

    func resolvedRpcKind(for data: GrpcRequestData) -> GrpcRpcKind {
        guard let service = reflectionServices.first(where: { $0.name == data.service }),
              let method = service.methods.first(where: { $0.name == data.method }) else {
            return data.rpcKind
        }
        return method.rpcKind
    }

    func substitutedRequestPayload() -> (body: String, isHex: Bool) {
        let env = store.activeEnvironment(for: request.projectId)
        let data = readData()
        switch data.bodyMode {
        case .json:
            return (
                EnvironmentVariableService.substitute(data.requestBodyJSON, environment: env),
                false
            )
        case .hex:
            return (
                EnvironmentVariableService.substitute(data.requestBodyHex, environment: env),
                true
            )
        }
    }

    func validateBodyBeforeSend() async -> RequestError? {
        let payload = substitutedRequestPayload()
        guard payload.isHex else { return nil }
        if payload.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return RequestError.from(message: "Hex body is empty.", kind: .invalidConfig)
        }
        do {
            _ = try await GrpcService.parseHexBody(payload.body)
            return nil
        } catch {
            return RequestError.from(error)
        }
    }

    func sendUnary() {
        guard canSend, let descriptorBytes = cachedDescriptorBytes else { return }
        isSending = true
        lastResponse = nil
        sendError = nil
        bodyValidationError = nil

        let data = readData()
        let config = buildGrpcConfig(data: data, rpcKind: resolvedRpcKind(for: data))
        let payload = substitutedRequestPayload()

        Task {
            if let validationError = await validateBodyBeforeSend() {
                bodyValidationError = validationError
                sendError = validationError
                isSending = false
                return
            }

            do {
                let response = try await GrpcService.invokeUnary(
                    config: config,
                    descriptorBytes: descriptorBytes,
                    requestBody: payload.body,
                    bodyIsHex: payload.isHex
                )
                lastResponse = response
                responseTimestamp = Date()
            } catch {
                sendError = RequestError.from(error)
            }
            isSending = false
        }
    }
}