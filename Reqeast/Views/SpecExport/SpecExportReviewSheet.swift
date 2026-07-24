//
//  SpecExportReviewSheet.swift
//  Reqeast
//

import SwiftUI

struct SpecExportReviewSheet: View {
    @Environment(\.dismiss) private var dismiss

    @Bindable var store: ProjectStore
    let project: Project
    let review: SpecExportReviewContext
    var onExportReady: (Data) -> Void

    @State private var segment: SpecExportReviewSegment
    @State private var selections: SpecExportSelections
    @State private var isExporting = false
    @State private var exportError: String?

    init(
        store: ProjectStore,
        project: Project,
        review: SpecExportReviewContext,
        onExportReady: @escaping (Data) -> Void
    ) {
        self.store = store
        self.project = project
        self.review = review
        self.onExportReady = onExportReady
        _selections = State(initialValue: SpecExportReviewHelpers.defaultSelections(from: review.diff))
        _segment = State(initialValue: SpecExportReviewHelpers.preferredInitialSegment(for: review.diff))
    }

    var body: some View {
        #if os(macOS)
        macOSBody
        #else
        iOSBody
        #endif
    }

    private var canExport: Bool {
        SpecExportService.canExport(
            project: project,
            store: store,
            diff: review.diff,
            selections: selections,
            specProject: review.specProject,
            options: review.options
        ) && !isExporting
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
                .navigationTitle(String(localized: "Export Review"))
                .toolbarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                            .disabled(isExporting)
                            .accessibilityIdentifier(SpecExportAccessibility.cancelButton)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Export...") { confirmExport() }
                            .disabled(!canExport)
                            .accessibilityIdentifier(SpecExportAccessibility.exportButton)
                    }
                }
        }
    }
    #endif

    private var header: some View {
        HStack {
            Text(String(localized: "Export Review"))
                .font(.headline)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var reviewContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(SpecExportReviewHelpers.reviewSummaryLabel(diff: review.diff))
                .font(.subheadline.weight(.medium))
                .accessibilityElement(children: .combine)
                .accessibilityLabel(SpecExportReviewHelpers.reviewSummaryLabel(diff: review.diff))
                .accessibilityIdentifier(SpecExportAccessibility.summaryCounts)

            Picker(String(localized: "Changes"), selection: $segment) {
                ForEach(SpecExportReviewSegment.allCases) { item in
                    Text(SpecExportReviewHelpers.segmentLabel(item, diff: review.diff))
                        .tag(item)
                }
            }
            .pickerStyle(.segmented)
            .tint(.primary)
            .accessibilityIdentifier(SpecExportAccessibility.segmentPicker)

            SpecExportReviewRows(
                segment: segment,
                diff: review.diff,
                projectId: project.id,
                store: store,
                selections: $selections
            )

            if let exportError {
                Text(exportError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            if isExporting {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(String(localized: "Exporting…"))
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
                .disabled(isExporting)
                .accessibilityIdentifier(SpecExportAccessibility.cancelButton)

            Spacer()

            Button("Export...") { confirmExport() }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canExport)
                .accessibilityIdentifier(SpecExportAccessibility.exportButton)
        }
    }
    #endif

    private func confirmExport() {
        exportError = nil
        isExporting = true

        Task {
            do {
                let data = try await SpecExportService.exportData(
                    project: project,
                    store: store,
                    review: review,
                    selections: selections
                )
                await MainActor.run {
                    isExporting = false
                    onExportReady(data)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    exportError = error.localizedDescription
                    isExporting = false
                }
            }
        }
    }
}