//
//  SpecImportSheetLayout.swift
//  Reqeast
//

import SwiftUI

extension SpecImportSheet {

    #if os(macOS)
    var macOSBody: some View {
        VStack(spacing: 0) {
            HStack {
                Text(sheetTitle).font(.headline)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            ScrollView {
                sheetContent
                    .padding(16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            footerButtons
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
        }
        .frame(
            width: 480,
            height: StorageEnvironment.isScreenshotMode || StorageEnvironment.isRunningTests ? 720 : 620
        )
        .modifier(SpecImportSheetModifiers(parent: self))
    }
    #endif

    #if !os(macOS)
    var iOSBody: some View {
        NavigationStack {
            ScrollView {
                sheetContent
                    .padding()
            }
            .navigationTitle(sheetTitle)
            .toolbarTitleDisplayMode(.inline)
            .toolbar { toolbarItems }
            .modifier(SpecImportSheetModifiers(parent: self))
        }
    }
    #endif
}

private struct SpecImportSheetModifiers: ViewModifier {
    let parent: SpecImportSheet

    func body(content: Content) -> some View {
        content
            #if !os(macOS)
            .fileImporter(
                isPresented: parent.$showingFileImporter,
                allowedContentTypes: SpecImportHelpers.specFileTypes,
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    parent.handleImportedFile(at: url)
                }
            }
            .fileImporter(
                isPresented: parent.$showingFolderImporter,
                allowedContentTypes: SpecImportHelpers.specFolderTypes,
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    parent.handleImportedBundleFolder(at: url)
                }
            }
            #endif
            .onChange(of: parent.importOptions) { oldValue, newValue in
                guard oldValue != newValue, !parent.isRefreshingPreview else { return }
                switch parent.phase {
                case .preview(let preview) where preview.options != newValue:
                    parent.repreview(with: newValue, from: preview)
                case .batchPreview(let batch):
                    parent.repreviewBatch(with: newValue, from: batch)
                default:
                    break
                }
            }
            .onDisappear { parent.activeTask?.cancel() }
            #if DEBUG
            .onAppear { parent.applyUITestFixturesIfNeeded() }
            #endif
    }
}