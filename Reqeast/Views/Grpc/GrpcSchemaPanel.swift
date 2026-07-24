//
//  GrpcSchemaPanel.swift
//  Reqeast
//

import SwiftUI

struct GrpcSchemaPanel: View, RequestDataBindable {
    @Bindable var store: ProjectStore
    let request: Request
    var isDiscovering: Bool
    var canSaveDescriptors: Bool
    var onDiscover: () -> Void
    var onSaveDescriptors: (String) -> Void

    @State private var showingLibrarySheet = false
    @State private var shouldStartImport = false
    @State private var showingSaveSheet = false
    @State private var saveBundleName = ""

    private var grpcData: GrpcRequestData { readData() }

    private var projectBundles: [ProtoBundle] {
        store.protoBundles(for: request.projectId)
    }

    private var selectedBundle: ProtoBundle? {
        guard let id = grpcData.protoBundleId else { return nil }
        return store.protoBundle(id: id)
    }

    func readData() -> GrpcRequestData {
        request.grpcData ?? GrpcRequestData()
    }

    func writeData(_ data: GrpcRequestData, to request: inout Request) {
        request.grpcData = data
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Schema")
                .font(.headline)

            Picker("Schema source", selection: binding(\.schemaSource)) {
                Text("Proto bundle").tag(GrpcSchemaSource.protoBundle)
                Text("Server reflection").tag(GrpcSchemaSource.reflection)
            }
            .tint(.primary)
            .disabled(isDiscovering)

            if grpcData.schemaSource == .protoBundle {
                protoBundleSection
            } else {
                reflectionSection
            }
        }
        .sheet(isPresented: $showingLibrarySheet) {
            GrpcProtoLibrarySheet(
                store: store,
                projectId: request.projectId,
                selectedBundleId: grpcData.protoBundleId,
                shouldStartImport: $shouldStartImport,
                onSelectBundle: selectBundle
            )
        }
        .sheet(isPresented: $showingSaveSheet) {
            saveDescriptorsSheet
        }
    }

    @ViewBuilder
    private var protoBundleSection: some View {
        if projectBundles.isEmpty {
            Text("No proto bundles in this project.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Picker("Active bundle", selection: optionalBundleBinding) {
                Text("Select a bundle").tag(UUID?.none)
                ForEach(projectBundles) { bundle in
                    Text(bundle.name).tag(Optional(bundle.id))
                }
            }
            .tint(.primary)
            .disabled(isDiscovering)

            if let bundle = selectedBundle, bundle.isReadOnlyDueToMissingAsset {
                GrpcReadOnlyBanner()
            }
        }

        HStack(spacing: 8) {
            Button("Manage Proto Library") {
                shouldStartImport = false
                showingLibrarySheet = true
            }
            .buttonStyle(.glass)
            .accessibilityIdentifier("grpc-manage-proto-library")

            Button("Import…") {
                shouldStartImport = true
                showingLibrarySheet = true
            }
            .buttonStyle(.glass)
            .accessibilityIdentifier("grpc-import-proto")
        }
    }

    @ViewBuilder
    private var reflectionSection: some View {
        Button(action: onDiscover) {
            if isDiscovering {
                Label("Discovering…", systemImage: "arrow.triangle.2.circlepath")
            } else {
                Label("Discover from server", systemImage: "antenna.radiowaves.left.and.right")
            }
        }
        .buttonStyle(.glass)
        .disabled(isDiscovering || grpcData.authority.isEmpty)

        Button("Save descriptors") {
            saveBundleName = defaultReflectionBundleName()
            showingSaveSheet = true
        }
        .buttonStyle(.glass)
        .disabled(!canSaveDescriptors)
        .help(
            canSaveDescriptors
                ? "Save reflection descriptors as a project proto bundle"
                : "Discover services before saving descriptors."
        )
    }

    private var optionalBundleBinding: Binding<UUID?> {
        Binding(
            get: { readData().protoBundleId },
            set: { newValue in
                updateData { data in
                    data.protoBundleId = newValue
                    if newValue != nil {
                        data.schemaSource = .protoBundle
                    }
                }
            }
        )
    }

    private func selectBundle(_ bundleId: UUID) {
        updateData { data in
            data.protoBundleId = bundleId
            data.schemaSource = .protoBundle
        }
    }

    private func defaultReflectionBundleName() -> String {
        let authority = grpcData.authority.trimmingCharacters(in: .whitespaces)
        if authority.isEmpty {
            return "Reflection"
        }
        return "Reflection \(authority)"
    }

    #if os(macOS)
    private var saveDescriptorsSheet: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Save Descriptors").font(.headline)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                Text("Create a proto bundle from the current reflection descriptors.")
                    .foregroundStyle(.secondary)
                TextField("Bundle name", text: $saveBundleName)
                    .textFieldStyle(.roundedBorder)
                    .devTextInput()
            }
            .padding(16)
            Divider()
            HStack {
                Button("Cancel") { showingSaveSheet = false }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") {
                    onSaveDescriptors(saveBundleName.trimmingCharacters(in: .whitespaces))
                    showingSaveSheet = false
                }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(saveBundleName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(width: 400, height: 220)
    }
    #else
    private var saveDescriptorsSheet: some View {
        NavigationStack {
            Form {
                TextField("Bundle name", text: $saveBundleName)
                    .devTextInput()
            }
            .navigationTitle("Save Descriptors")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingSaveSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSaveDescriptors(saveBundleName.trimmingCharacters(in: .whitespaces))
                        showingSaveSheet = false
                    }
                    .disabled(saveBundleName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
    #endif
}