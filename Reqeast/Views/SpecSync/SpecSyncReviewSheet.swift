//
//  SpecSyncReviewSheet.swift
//  Reqeast
//

import SwiftUI

struct SpecSyncReviewContext: Identifiable {
    let id = UUID()
    let diff: SpecSyncDiff
    let newFingerprint: String
    let newBytes: Data
}

struct SpecSyncReviewSheet: View {
    @Environment(\.dismiss) private var dismiss

    @Bindable var store: ProjectStore
    let project: Project
    let diff: SpecSyncDiff
    let newFingerprint: String
    let newBytes: Data

    @State private var segment: SpecSyncReviewSegment = .added
    @State private var selections: SpecSyncSelections
    @State private var isApplying = false
    @State private var applyError: SpecImportError?

    init(
        store: ProjectStore,
        project: Project,
        diff: SpecSyncDiff,
        newFingerprint: String,
        newBytes: Data
    ) {
        self.store = store
        self.project = project
        self.diff = diff
        self.newFingerprint = newFingerprint
        self.newBytes = newBytes
        _selections = State(initialValue: SpecSyncHelpers.defaultSelections(from: diff))
        _segment = State(initialValue: SpecSyncReviewSheet.preferredInitialSegment(for: diff))
    }

    var body: some View {
        #if os(macOS)
        macOSBody
        #else
        iOSBody
        #endif
    }

    private var canApply: Bool {
        selections.hasSelection && !isApplying
    }

    #if os(macOS)
    private var macOSBody: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView { reviewContent.padding(16) }
            Divider()
            footer
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
        }
        .frame(width: 520, height: 560)
    }
    #endif

    #if !os(macOS)
    private var iOSBody: some View {
        NavigationStack {
            ScrollView { reviewContent.padding() }
                .navigationTitle("Spec Sync Review")
                .toolbarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                            .disabled(isApplying)
                            .accessibilityIdentifier(SpecSyncAccessibility.cancelButton)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Apply") { applyChanges() }
                            .disabled(!canApply)
                            .accessibilityIdentifier(SpecSyncAccessibility.applyButton)
                    }
                }
        }
    }
    #endif

    private var header: some View {
        HStack {
            Text("Spec Sync Review")
                .font(.headline)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var reviewContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(SpecSyncHelpers.reviewSummaryLabel(diff: diff))
                .font(.subheadline.weight(.medium))
                .accessibilityElement(children: .combine)
                .accessibilityLabel(SpecSyncHelpers.reviewSummaryLabel(diff: diff))
                .accessibilityIdentifier(SpecSyncAccessibility.summaryCounts)

            Picker("Changes", selection: $segment) {
                ForEach(SpecSyncReviewSegment.allCases) { item in
                    Text(SpecSyncHelpers.segmentLabel(item, diff: diff))
                        .tag(item)
                }
            }
            .pickerStyle(.segmented)
            .tint(.primary)
            .accessibilityIdentifier(SpecSyncAccessibility.segmentPicker)

            SpecSyncReviewRows(
                segment: segment,
                diff: diff,
                projectId: project.id,
                store: store,
                selections: $selections
            )

            if let applyError {
                SpecSyncInlineErrorView(error: applyError)
            }

            if isApplying {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Applying changes…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    #if os(macOS)
    private var footer: some View {
        HStack {
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
                .disabled(isApplying)
                .accessibilityIdentifier(SpecSyncAccessibility.cancelButton)

            Spacer()

            Button("Apply") { applyChanges() }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canApply)
                .accessibilityIdentifier(SpecSyncAccessibility.applyButton)
        }
    }
    #endif

    @MainActor
    private func applyChanges() {
        isApplying = true
        applyError = nil
        defer { isApplying = false }

        do {
            try SpecSyncService.apply(
                diff: diff,
                selections: selections,
                projectId: project.id,
                newContentFingerprint: newFingerprint,
                specBytes: newBytes,
                store: store
            )
            dismiss()
        } catch let error as SpecSyncApplyError {
            applyError = SpecImportError.from(message: error.localizedDescription, kind: .parseError)
        } catch {
            applyError = SpecImportError.from(error)
        }
    }

    private static func preferredInitialSegment(for diff: SpecSyncDiff) -> SpecSyncReviewSegment {
        if !diff.added.isEmpty { return .added }
        if !diff.modified.isEmpty || !diff.identityChanged.isEmpty { return .modified }
        if !diff.removed.isEmpty { return .removed }
        return .unchanged
    }
}