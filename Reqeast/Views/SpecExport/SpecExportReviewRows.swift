//
//  SpecExportReviewRows.swift
//  Reqeast
//

import SwiftUI

struct SpecExportReviewRows: View {
    let segment: SpecExportReviewSegment
    let diff: SpecSyncDiff
    let projectId: UUID
    @Bindable var store: ProjectStore
    @Binding var selections: SpecExportSelections

    var body: some View {
        switch segment {
        case .projectOnly:
            if diff.added.isEmpty {
                emptyState(String(localized: "No operations only in project"))
            } else {
                ForEach(diff.added, id: \.primaryKey) { operation in
                    SpecExportProjectOnlyRow(
                        operation: operation,
                        isSelected: selections.includeProjectOnlyPrimaryKeys.contains(operation.primaryKey),
                        onToggle: { toggleProjectOnly(operation.primaryKey) }
                    )
                }
            }
        case .specOnly:
            if diff.removed.isEmpty {
                emptyState(String(localized: "No operations only in spec"))
            } else {
                ForEach(diff.removed, id: \.requestId) { removed in
                    SpecExportSpecOnlyRow(
                        title: SpecExportReviewHelpers.requestName(
                            for: removed.requestId,
                            projectId: projectId,
                            store: store
                        ),
                        subtitle: removed.primaryKey,
                        isSelected: selections.includeSpecOnlyPrimaryKeys.contains(removed.primaryKey),
                        rowID: removed.requestId,
                        onToggle: { toggleSpecOnly(removed.primaryKey) }
                    )
                }
            }
        case .changed:
            changedRows
        case .conflicts:
            conflictRows
        }
    }

    @ViewBuilder
    private var changedRows: some View {
        let (modified, identity) = SpecExportReviewHelpers.changedOperations(from: diff)
        if modified.isEmpty && identity.isEmpty {
            emptyState(String(localized: "No changed operations"))
        } else {
            ForEach(modified, id: \.requestId) { operationDiff in
                SpecExportChangedRow(
                    title: SpecExportReviewHelpers.requestName(
                        for: operationDiff.requestId,
                        projectId: projectId,
                        store: store
                    ),
                    subtitle: operationDiff.primaryKey,
                    fieldDeltas: operationDiff.fieldDeltas,
                    isSelected: selections.useLocalVersionRequestIDs.contains(operationDiff.requestId),
                    rowID: operationDiff.requestId,
                    onToggle: { toggleUseLocal(operationDiff.requestId) }
                )
            }

            ForEach(identity, id: \.requestId) { identityDiff in
                SpecExportChangedRow(
                    title: SpecExportReviewHelpers.requestName(
                        for: identityDiff.requestId,
                        projectId: projectId,
                        store: store
                    ),
                    subtitle: String(
                        format: String(localized: "Identity changed from %@ to %@"),
                        locale: .current,
                        identityDiff.oldPrimaryKey,
                        identityDiff.newPrimaryKey
                    ),
                    fieldDeltas: identityDiff.fieldDeltas,
                    isSelected: selections.useLocalVersionRequestIDs.contains(identityDiff.requestId),
                    rowID: identityDiff.requestId,
                    onToggle: { toggleUseLocal(identityDiff.requestId) },
                    showsIdentityBadge: true
                )
            }
        }
    }

    @ViewBuilder
    private var conflictRows: some View {
        let (modified, identity) = SpecExportReviewHelpers.conflictOperations(from: diff)
        if modified.isEmpty && identity.isEmpty {
            emptyState(String(localized: "No conflicting operations"))
        } else {
            ForEach(modified, id: \.requestId) { operationDiff in
                SpecExportChangedRow(
                    title: SpecExportReviewHelpers.requestName(
                        for: operationDiff.requestId,
                        projectId: projectId,
                        store: store
                    ),
                    subtitle: operationDiff.primaryKey,
                    fieldDeltas: operationDiff.fieldDeltas,
                    isSelected: selections.useLocalVersionRequestIDs.contains(operationDiff.requestId),
                    rowID: operationDiff.requestId,
                    onToggle: { toggleUseLocal(operationDiff.requestId) },
                    showsConflictBadge: true
                )
            }

            ForEach(identity, id: \.requestId) { identityDiff in
                SpecExportChangedRow(
                    title: SpecExportReviewHelpers.requestName(
                        for: identityDiff.requestId,
                        projectId: projectId,
                        store: store
                    ),
                    subtitle: String(
                        format: String(localized: "Identity changed from %@ to %@"),
                        locale: .current,
                        identityDiff.oldPrimaryKey,
                        identityDiff.newPrimaryKey
                    ),
                    fieldDeltas: identityDiff.fieldDeltas,
                    isSelected: selections.useLocalVersionRequestIDs.contains(identityDiff.requestId),
                    rowID: identityDiff.requestId,
                    onToggle: { toggleUseLocal(identityDiff.requestId) },
                    showsIdentityBadge: true,
                    showsConflictBadge: true
                )
            }
        }
    }

    private func emptyState(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
    }

    private func toggleProjectOnly(_ primaryKey: String) {
        if selections.includeProjectOnlyPrimaryKeys.contains(primaryKey) {
            selections.includeProjectOnlyPrimaryKeys.remove(primaryKey)
        } else {
            selections.includeProjectOnlyPrimaryKeys.insert(primaryKey)
        }
    }

    private func toggleSpecOnly(_ primaryKey: String) {
        if selections.includeSpecOnlyPrimaryKeys.contains(primaryKey) {
            selections.includeSpecOnlyPrimaryKeys.remove(primaryKey)
        } else {
            selections.includeSpecOnlyPrimaryKeys.insert(primaryKey)
        }
    }

    private func toggleUseLocal(_ requestId: String) {
        if selections.useLocalVersionRequestIDs.contains(requestId) {
            selections.useLocalVersionRequestIDs.remove(requestId)
        } else {
            selections.useLocalVersionRequestIDs.insert(requestId)
        }
    }
}

private struct SpecExportProjectOnlyRow: View {
    let operation: NormalizedOperation
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Toggle(isOn: Binding(get: { isSelected }, set: { _ in onToggle() })) {
            VStack(alignment: .leading, spacing: 2) {
                Text(operation.name)
                    .font(.subheadline.weight(.medium))
                Text(operation.primaryKey)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier(SpecExportAccessibility.operationToggle(operation.primaryKey))
    }
}

private struct SpecExportSpecOnlyRow: View {
    let title: String
    let subtitle: String
    let isSelected: Bool
    let rowID: String
    let onToggle: () -> Void

    var body: some View {
        Toggle(isOn: Binding(get: { isSelected }, set: { _ in onToggle() })) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(subtitle)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier(SpecExportAccessibility.operationToggle(rowID))
    }
}

private struct SpecExportChangedRow: View {
    let title: String
    let subtitle: String
    let fieldDeltas: [SpecFieldDelta]
    let isSelected: Bool
    let rowID: String
    let onToggle: () -> Void
    var showsIdentityBadge: Bool = false
    var showsConflictBadge: Bool = false

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(fieldDeltas.enumerated()), id: \.offset) { _, delta in
                    SpecExportFieldDeltaRow(delta: delta)
                }
            }
            .padding(.top, 4)
        } label: {
            Toggle(isOn: Binding(get: { isSelected }, set: { _ in onToggle() })) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.subheadline.weight(.medium))
                        if showsIdentityBadge {
                            Text("Identity changed")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .glassEffect(.regular.tint(.orange.opacity(0.8)), in: .capsule)
                        }
                        if showsConflictBadge {
                            Text("Conflict")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .glassEffect(.regular.tint(.red.opacity(0.8)), in: .capsule)
                        }
                    }
                    Text(isSelected
                        ? String(localized: "Use local version")
                        : String(localized: "Align export to spec"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(subtitle)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityIdentifier(SpecExportAccessibility.operationToggle(rowID))
    }
}

private struct SpecExportFieldDeltaRow: View {
    let delta: SpecFieldDelta

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(SpecExportReviewHelpers.fieldLabel(delta.field))
                    .font(.caption.weight(.semibold))
                if delta.isConflict {
                    Text("Conflict")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .glassEffect(.regular.tint(.red.opacity(0.8)), in: .capsule)
                }
            }

            Text(delta.oldValue)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(3)

            Image(systemName: "arrow.down")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Text(delta.newValue)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(3)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 8))
    }
}