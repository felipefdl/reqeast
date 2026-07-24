//
//  GrpcMethodPicker.swift
//  Reqeast
//

import SwiftUI

struct GrpcMethodPicker: View, RequestDataBindable {
    @Bindable var store: ProjectStore
    let request: Request
    let services: [GrpcServiceInfo]
    var isDisabled: Bool

    private var grpcData: GrpcRequestData { readData() }

    func readData() -> GrpcRequestData {
        request.grpcData ?? GrpcRequestData()
    }

    func writeData(_ data: GrpcRequestData, to request: inout Request) {
        request.grpcData = data
    }

    private var selectedService: GrpcServiceInfo? {
        services.first { $0.name == grpcData.service }
    }

    private var methods: [GrpcMethodInfo] {
        selectedService?.methods ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("RPC")
                .font(.headline)

            if services.isEmpty {
                manualFields
            } else {
                pickerFields
            }
        }
    }

    private var pickerFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Service", selection: serviceBinding) {
                Text("Select service").tag("")
                ForEach(services, id: \.name) { service in
                    Text(service.name).tag(service.name)
                }
            }
            .tint(.primary)
            .disabled(isDisabled)

            Picker("Method", selection: methodBinding) {
                Text("Select method").tag("")
                ForEach(methods, id: \.name) { method in
                    Text(method.name).tag(method.name)
                }
            }
            .tint(.primary)
            .disabled(isDisabled || grpcData.service.isEmpty)
        }
    }

    private var manualFields: some View {
        HStack(spacing: 8) {
            TextField("helloworld.Greeter", text: binding(\.service))
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .disabled(isDisabled)
                .devTextInput()

            TextField("SayHello", text: binding(\.method))
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .disabled(isDisabled)
                .devTextInput()
        }
    }

    private var serviceBinding: Binding<String> {
        Binding(
            get: { grpcData.service },
            set: { newService in
                updateData { data in
                    data.service = newService
                    if !data.method.isEmpty,
                       !(services.first { $0.name == newService }?
                        .methods.contains { $0.name == data.method } ?? false) {
                        data.method = ""
                    }
                }
            }
        )
    }

    private var methodBinding: Binding<String> {
        Binding(
            get: { grpcData.method },
            set: { newMethod in
                updateData { data in
                    data.method = newMethod
                    if let methodInfo = selectedService?.methods.first(where: { $0.name == newMethod }) {
                        data.rpcKind = methodInfo.rpcKind
                    }
                }
            }
        )
    }
}