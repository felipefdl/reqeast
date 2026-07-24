//
//  GrpcProtoLibrarySheet.swift
//  Reqeast
//

import SwiftUI
import UniformTypeIdentifiers

struct GrpcProtoLibrarySheet: View {
    @Bindable var store: ProjectStore
    let projectId: UUID
    var selectedBundleId: UUID?
    @Binding var shouldStartImport: Bool
    var onSelectBundle: (UUID) -> Void

    @Environment(\.dismiss) private var dismiss

    @State var showingFileImporter = false
    @State private var pendingImportURLs: [URL] = []
    @State private var importName = ""
    @State private var importEntryFile = ""
    @State private var importError: RequestError?
    @State private var isImporting = false
    @State var bundlePendingDeletion: ProtoBundle?
    @State private var didConsumeStartImport = false

    private var bundles: [ProtoBundle] {
        store.protoBundles(for: projectId)
    }

    var body: some View {
        #if os(macOS)
        macOSBody
        #else
        iOSBody
        #endif
    }

    #if os(macOS)
    private var macOSBody: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                sheetContent.padding(16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer
        }
        .frame(width: 480, height: 420)
        .modifier(ProtoLibrarySheetModifiers(parent: self))
        .onAppear { consumeStartImportIfNeeded() }
    }
    #endif

    #if !os(macOS)
    private var iOSBody: some View {
        NavigationStack {
            ScrollView {
                sheetContent.padding()
            }
            .navigationTitle("Proto Library")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Import") { beginImport() }
                        .disabled(isImporting)
                        .accessibilityIdentifier("grpc-proto-library-import")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("grpc-proto-library-done")
                }
            }
            .modifier(ProtoLibrarySheetModifiers(parent: self))
            .onAppear { consumeStartImportIfNeeded() }
        }
    }
    #endif

    private var header: some View {
        HStack {
            Text("Proto Library").font(.headline)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var footer: some View {
        HStack {
            Button("Done") { dismiss() }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("grpc-proto-library-done")
            Spacer()
            Button("Import…") { beginImport() }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(isImporting)
                .accessibilityIdentifier("grpc-proto-library-import")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var sheetContent: some View {
        if let importError {
            Text(importError.message)
                .foregroundStyle(.red)
                .textSelection(.enabled)
        }

        if bundles.isEmpty {
            ContentUnavailableView {
                Label("No Proto Bundles", systemImage: "doc.text")
            } description: {
                Text("Import .proto files to compile descriptors for gRPC requests.")
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(bundles) { bundle in
                    bundleRow(bundle)
                }
            }
        }

        if !pendingImportURLs.isEmpty {
            importConfirmationSection
        }
    }

    private func bundleRow(_ bundle: ProtoBundle) -> some View {
        let isSelected = selectedBundleId == bundle.id
        return HStack(spacing: 8) {
            Button {
                onSelectBundle(bundle.id)
            } label: {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(bundle.name)
                            .font(.headline)
                        Text("\(bundle.entryFile) · \(bundle.fileCount) file\(bundle.fileCount == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if bundle.isReadOnlyDueToMissingAsset {
                            Text("Waiting for iCloud download")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }

                    Spacer(minLength: 0)

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.tint)
                    }
                }
                .padding(10)
                .contentShape(.rect)
            }
            .buttonStyle(.glass)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityIdentifier("protoBundleRow-\(bundle.id.uuidString)")

            Button(role: .destructive) {
                bundlePendingDeletion = bundle
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.glass)
            .disabled(isImporting)
            .accessibilityLabel("Delete \(bundle.name)")
        }
    }

    @ViewBuilder
    private var importConfirmationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Import \(pendingImportURLs.count) file\(pendingImportURLs.count == 1 ? "" : "s")")
                .font(.headline)

            TextField("Bundle name", text: $importName)
                #if os(macOS)
                .textFieldStyle(.roundedBorder)
                #endif
                .devTextInput()

            Picker("Entry file", selection: $importEntryFile) {
                ForEach(pendingImportURLs.map(\.lastPathComponent), id: \.self) { file in
                    Text(file).tag(file)
                }
            }
            .tint(.primary)

            HStack {
                Button("Cancel") { resetPendingImport() }
                    .buttonStyle(.glass)
                Spacer()
                Button(isImporting ? "Importing…" : "Import") {
                    Task { await performImport() }
                }
                .buttonStyle(.glassProminent)
                .disabled(isImporting || importName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(.top, 8)
    }

    func beginImport() {
        importError = nil
        #if os(macOS)
        GrpcProtoFilePicker.chooseProtoFiles { urls in
            guard !urls.isEmpty else { return }
            handleImportedFiles(urls)
        }
        #else
        showingFileImporter = true
        #endif
    }

    func handleImportedFiles(_ urls: [URL]) {
        pendingImportURLs = urls
        importEntryFile = urls.first?.lastPathComponent ?? ""
        let stem = urls.first?.deletingPathExtension().lastPathComponent ?? "Proto Bundle"
        importName = stem
        importError = nil
    }

    func resetPendingImport() {
        pendingImportURLs = []
        importName = ""
        importEntryFile = ""
    }

    @MainActor
    func performImport() async {
        guard !pendingImportURLs.isEmpty else { return }
        isImporting = true
        importError = nil
        defer { isImporting = false }

        do {
            let bundle = try await store.importProtoBundleFromFiles(
                projectId: projectId,
                name: importName.trimmingCharacters(in: .whitespaces),
                entryFile: importEntryFile,
                protoFileURLs: pendingImportURLs
            )
            onSelectBundle(bundle.id)
            resetPendingImport()
        } catch {
            importError = RequestError.from(error)
        }
    }

    func confirmDeleteBundle() {
        guard let bundle = bundlePendingDeletion else { return }
        store.deleteProtoBundle(id: bundle.id)
        bundlePendingDeletion = nil
    }
}

private struct ProtoLibrarySheetModifiers: ViewModifier {
    let parent: GrpcProtoLibrarySheet

    func body(content: Content) -> some View {
        content
            #if !os(macOS)
            .fileImporter(
                isPresented: parent.$showingFileImporter,
                allowedContentTypes: GrpcProtoImportHelpers.protoTypes,
                allowsMultipleSelection: true
            ) { result in
                if case .success(let urls) = result, !urls.isEmpty {
                    parent.handleImportedFiles(urls)
                }
            }
            #endif
            .confirmationDialog(
                "Delete this proto bundle?",
                isPresented: Binding(
                    get: { parent.bundlePendingDeletion != nil },
                    set: { if !$0 { parent.bundlePendingDeletion = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    parent.confirmDeleteBundle()
                }
                Button("Cancel", role: .cancel) {
                    parent.bundlePendingDeletion = nil
                }
            }
    }
}

extension GrpcProtoLibrarySheet {
    /// Runs once when the sheet appears if the caller asked to jump straight into import.
    func consumeStartImportIfNeeded() {
        guard shouldStartImport, !didConsumeStartImport else { return }
        didConsumeStartImport = true
        shouldStartImport = false
        beginImport()
    }
}
