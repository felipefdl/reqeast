//
//  CodeSnippetSheet.swift
//  Reqeast
//

import SwiftUI

struct CodeSnippetSheet: View {
    let request: Request
    let environment: ApiEnvironment?
    @Environment(\.dismiss) private var dismiss

    @AppStorage("lastCodeSnippetTarget") private var lastTarget: CodeSnippetTarget = .curl
    @State private var generatedCode = ""
    @State private var copied = false

    private var resolved: ResolvedHttpRequest {
        guard let httpData = request.httpData else {
            return ResolvedHttpRequest(method: "GET", url: "", headers: [], body: .none, timeout: 30)
        }
        return HttpRequestResolver.resolve(httpData, environment: environment)
    }

    var body: some View {
        #if os(macOS)
        macOSBody
        #else
        iOSBody
        #endif
    }

    // MARK: - macOS

    #if os(macOS)
    private var macOSBody: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Code Snippet").font(.headline)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            sharedContent
                .padding(16)

            Divider()

            HStack {
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                copyButton
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(width: 600, height: 500)
        .onAppear { generate() }
    }
    #endif

    // MARK: - iOS

    #if !os(macOS)
    private var iOSBody: some View {
        NavigationStack {
            sharedContent
                .padding(16)
                .navigationTitle("Code Snippet")
                .toolbarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        copyButton
                    }
                }
        }
        .onAppear { generate() }
    }
    #endif

    // MARK: - Shared Content

    private var sharedContent: some View {
        VStack(spacing: 12) {
            targetPicker
            codeArea
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var targetPicker: some View {
        Picker("Target", selection: $lastTarget) {
            ForEach(CodeSnippetTarget.allCases) { target in
                Text(target.displayName).tag(target)
            }
        }
        .tint(.primary)
        .onChange(of: lastTarget) { generate() }
    }

    @ViewBuilder
    private var codeArea: some View {
        if generatedCode.isEmpty {
            ContentUnavailableView(
                "No Code",
                systemImage: "curlybraces",
                description: Text("Select a target to generate a snippet.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            CodeSnippetCodeView(
                code: generatedCode,
                language: lastTarget.highlightLanguage
            )
        }
    }

    private var copyButton: some View {
        Button {
            PlatformClipboard.copy(generatedCode)
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(2))
                copied = false
            }
        } label: {
            Label("Copy", systemImage: "doc.on.doc")
        }
        .buttonStyle(.glassProminent)
        .disabled(generatedCode.isEmpty)
        .overlay(alignment: .top) {
            if copied {
                Text("Copied!")
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: .capsule)
                    .offset(y: -30)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.smooth(duration: 0.2), value: copied)
    }

    // MARK: - Generation

    private func generate() {
        generatedCode = CodeSnippetService.generate(target: lastTarget, request: resolved)
    }
}
