//
//  SpecImportSheet+SourceActions.swift
//  Reqeast
//

import SwiftUI

extension SpecImportSheet {

    var canContinueFromSource: Bool {
        switch sourceTab {
        case .file:
            return false
        case .url:
            return !urlText.trimmingCharacters(in: .whitespaces).isEmpty
        case .paste:
            let trimmed = pasteText.trimmingCharacters(in: .whitespacesAndNewlines)
            return !trimmed.isEmpty && pasteText.utf8.count <= SpecImportHelpers.maxBytes
        }
    }

    var primarySourceActionTitle: LocalizedStringKey {
        switch sourceTab {
        case .file: "Choose File"
        case .url: "Fetch"
        case .paste: "Continue"
        }
    }

    var primarySourceActionAccessibilityIdentifier: String {
        switch sourceTab {
        case .file: SpecImportAccessibility.chooseFileButton
        case .url: SpecImportAccessibility.fetchButton
        case .paste: SpecImportAccessibility.continueButton
        }
    }

    func chooseSpecFile() {
        #if os(macOS)
        SpecImportFilePicker.chooseFile { url in
            if let url { handleImportedFile(at: url) }
        }
        #else
        showingFileImporter = true
        #endif
    }

    func chooseSpecFolder() {
        #if os(macOS)
        SpecImportFilePicker.chooseFolder { url in
            if let url { handleImportedBundleFolder(at: url) }
        }
        #else
        showingFolderImporter = true
        #endif
    }

    func performPrimarySourceAction() {
        switch sourceTab {
        case .file:
            chooseSpecFile()
        case .url:
            startTask { await fetchFromURL() }
        case .paste:
            startTask { await previewFromPaste() }
        }
    }

    func handleImportedFile(at url: URL) {
        startTask { await previewFromFile(url: url) }
    }

    func handleImportedBundleFolder(at url: URL) {
        startTask { await previewFromBundleFolder(url: url) }
    }

    func retryAfterError() {
        phase = .sourcePick
    }

    func startTask(_ operation: @escaping @MainActor () async -> Void) {
        activeTask?.cancel()
        activeTask = Task { await operation() }
    }

    func previewFromFile(url: URL) async {
        phase = .parsing
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }

        do {
            let data = try Data(contentsOf: url)
            try validateByteCount(data.count)
            let preview = try await SpecImportService.preview(
                bytes: data,
                sourceHint: SpecImportHelpers.sourceHint(for: url, data: data),
                source: .file,
                options: importOptions
            )
            applyPreview(preview)
        } catch {
            phase = .error(SpecImportError.from(error))
        }
    }

    func previewFromBundleFolder(url: URL) async {
        phase = .parsing
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }

        do {
            guard let resolution = SpecImportHelpers.resolveBundleFolder(in: url) else {
                throw SpecImportError.from(
                    message: String(localized: "No OpenAPI entry file found in the selected folder. Expected openapi.yaml, openapi.json, swagger.yaml, or one or more *.openapi.json files."),
                    kind: .invalidSpec
                )
            }

            switch resolution {
            case .bundle(let entryURL):
                try await previewBundleEntry(entryURL: entryURL, in: url)
            case .multiSpec(let entryURLs):
                try await previewMultiSpecEntries(entryURLs, in: url)
            }
        } catch {
            phase = .error(SpecImportError.from(error))
        }
    }

    func fetchFromURL() async {
        let trimmed = urlText.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" else {
            phase = .error(
                SpecImportError.from(
                    message: String(localized: "Enter a valid HTTPS URL."),
                    kind: .invalidSpec
                )
            )
            return
        }

        phase = .parsing
        do {
            let data: Data
            let source: SpecSource
            let gitRef: GitSourceRef?

            if let gitSource = GitImportURLParser.parse(trimmed) {
                #if DEBUG
                if let fixture = SpecSyncUITestSupport.fetchData(for: url) {
                    data = fixture
                } else {
                    data = try await GitSpecSourceService.fetchImportSource(gitSource)
                }
                #else
                data = try await GitSpecSourceService.fetchImportSource(gitSource)
                #endif
                let metadata = GitSpecSourceService.importMetadata(for: gitSource, sourceURL: trimmed)
                source = metadata.0
                gitRef = metadata.1
            } else {
                #if DEBUG
                if let fixture = SpecSyncUITestSupport.fetchData(for: url) {
                    data = fixture
                } else {
                    data = try await SafeFetchService.shared.fetch(url: url)
                }
                #else
                data = try await SafeFetchService.shared.fetch(url: url)
                #endif
                source = .url
                gitRef = nil
            }

            try validateByteCount(data.count)
            urlSnapshotDate = Date()
            let preview = try await SpecImportService.preview(
                SpecImportRequest(
                    bytes: data,
                    sourceHint: SpecImportHelpers.sourceHint(for: data),
                    source: source,
                    sourceURL: trimmed,
                    gitRef: gitRef
                ),
                options: importOptions
            )
            applyPreview(preview)
        } catch {
            phase = .error(SpecImportError.from(error))
        }
    }

    func previewFromPaste() async {
        let trimmed = pasteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            phase = .error(
                SpecImportError.from(
                    message: String(localized: "Paste a spec to continue."),
                    kind: .invalidSpec
                )
            )
            return
        }

        phase = .parsing
        do {
            guard let data = trimmed.data(using: .utf8) else {
                throw SpecImportError.from(
                    message: String(localized: "Could not read pasted content."),
                    kind: .parseError
                )
            }
            try validateByteCount(data.count)
            let preview = try await SpecImportService.preview(
                bytes: data,
                sourceHint: SpecImportHelpers.sourceHint(for: data),
                source: .paste,
                options: importOptions
            )
            applyPreview(preview)
        } catch {
            phase = .error(SpecImportError.from(error))
        }
    }

    func previewBundleEntry(entryURL: URL, in folderURL: URL) async throws {
        let data = try Data(contentsOf: entryURL)
        try validateByteCount(data.count)
        let linkToFolder = importOptions.linkToSpec == .linked
        #if os(macOS)
        let source: SpecSource = linkToFolder ? .localBookmark : .file
        let bookmarkFolder: URL? = linkToFolder ? folderURL : nil
        #else
        let source: SpecSource = .file
        let bookmarkFolder: URL? = nil
        #endif

        let preview = try await SpecImportService.preview(
            SpecImportRequest(
                bytes: data,
                sourceHint: SpecImportHelpers.sourceHint(for: entryURL, data: data),
                source: source,
                sourceURL: linkToFolder ? folderURL.path : nil,
                bundleEntryPath: entryURL.path,
                bundleSourceDirectory: folderURL,
                bookmarkSourceFolder: bookmarkFolder
            ),
            options: importOptions
        )
        applyPreview(preview)
    }

    func previewMultiSpecEntries(_ entryURLs: [URL], in folderURL: URL) async throws {
        var items: [SpecImportPreview] = []
        items.reserveCapacity(entryURLs.count)

        for entryURL in entryURLs {
            let data = try Data(contentsOf: entryURL)
            try validateByteCount(data.count)
            let preview = try await SpecImportService.preview(
                bytes: data,
                sourceHint: SpecImportHelpers.sourceHint(for: entryURL, data: data),
                source: .file,
                options: importOptions,
                sourceURL: entryURL.path
            )
            items.append(preview)
        }

        applyBatchPreview(
            SpecImportBatchPreview(
                items: items,
                sourceFolderName: folderURL.lastPathComponent
            )
        )
    }

    #if DEBUG
    func applyUITestFixturesIfNeeded() {
        if let paste = SpecImportUITestSupport.prefilledPasteText(), pasteText.isEmpty {
            pasteText = paste
        }
        if let url = SpecImportUITestSupport.prefilledURLText(), urlText.isEmpty {
            urlText = url
        }
        if SpecImportUITestSupport.shouldDefaultLinkToSpec {
            importOptions.linkToSpec = .linked
        }
    }
    #endif
}