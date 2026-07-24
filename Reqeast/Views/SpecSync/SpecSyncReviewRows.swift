//
//  SpecSyncReviewRows.swift
//  Reqeast
//

import SwiftUI

struct SpecSyncReviewRows: View {
    let segment: SpecSyncReviewSegment
    let diff: SpecSyncDiff
    let projectId: UUID
    @Bindable var store: ProjectStore
    @Binding var selections: SpecSyncSelections

    var body: some View {
        switch segment {
        case .added:
            if diff.added.isEmpty {
                emptyState(String(localized: "No added operations"))
            } else {
                ForEach(diff.added, id: \.primaryKey) { operation in
                    SpecSyncAddedRow(
                        operation: operation,
                        isSelected: selections.addedPrimaryKeys.contains(operation.primaryKey),
                        onToggle: { toggleAdded(operation.primaryKey) }
                    )
                }
            }
        case .modified:
            if diff.modified.isEmpty && diff.identityChanged.isEmpty {
                emptyState(String(localized: "No modified operations"))
            } else {
                ForEach(diff.modified, id: \.requestId) { operationDiff in
                    SpecSyncModifiedRow(
                        title: SpecSyncHelpers.requestName(
                            for: operationDiff.requestId,
                            projectId: projectId,
                            store: store
                        ),
                        subtitle: operationDiff.primaryKey,
                        fieldDeltas: operationDiff.fieldDeltas,
                        isSelected: selections.modifiedRequestIDs.contains(operationDiff.requestId),
                        rowID: operationDiff.requestId,
                        onToggle: { toggleModified(operationDiff.requestId) }
                    )
                }

                ForEach(diff.identityChanged, id: \.requestId) { identityDiff in
                    SpecSyncModifiedRow(
                        title: SpecSyncHelpers.requestName(
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
                        isSelected: selections.identityChangedRequestIDs.contains(identityDiff.requestId),
                        rowID: identityDiff.requestId,
                        onToggle: { toggleIdentityChanged(identityDiff.requestId) },
                        showsIdentityBadge: true
                    )
                }
            }
        case .removed:
            if diff.removed.isEmpty {
                emptyState(String(localized: "No removed operations"))
            } else {
                ForEach(diff.removed, id: \.requestId) { removed in
                    SpecSyncRemovedRow(
                        title: SpecSyncHelpers.requestName(
                            for: removed.requestId,
                            projectId: projectId,
                            store: store
                        ),
                        subtitle: removed.primaryKey,
                        isSelected: selections.removedRequestIDs.contains(removed.requestId),
                        rowID: removed.requestId,
                        onToggle: { toggleRemoved(removed.requestId) }
                    )
                }
            }
        case .unchanged:
            if diff.unchanged.isEmpty {
                emptyState(String(localized: "No unchanged operations"))
            } else {
                ForEach(diff.unchanged, id: \.requestId) { unchanged in
                    SpecSyncUnchangedRow(
                        title: SpecSyncHelpers.requestName(
                            for: unchanged.requestId,
                            projectId: projectId,
                            store: store
                        ),
                        subtitle: unchanged.primaryKey,
                        rowID: unchanged.requestId
                    )
                }
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

    private func toggleAdded(_ primaryKey: String) {
        if selections.addedPrimaryKeys.contains(primaryKey) {
            selections.addedPrimaryKeys.remove(primaryKey)
        } else {
            selections.addedPrimaryKeys.insert(primaryKey)
        }
    }

    private func toggleModified(_ requestId: String) {
        if selections.modifiedRequestIDs.contains(requestId) {
            selections.modifiedRequestIDs.remove(requestId)
        } else {
            selections.modifiedRequestIDs.insert(requestId)
        }
    }

    private func toggleRemoved(_ requestId: String) {
        if selections.removedRequestIDs.contains(requestId) {
            selections.removedRequestIDs.remove(requestId)
        } else {
            selections.removedRequestIDs.insert(requestId)
        }
    }

    private func toggleIdentityChanged(_ requestId: String) {
        if selections.identityChangedRequestIDs.contains(requestId) {
            selections.identityChangedRequestIDs.remove(requestId)
        } else {
            selections.identityChangedRequestIDs.insert(requestId)
        }
    }
}

private struct SpecSyncAddedRow: View {
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
        .accessibilityIdentifier(SpecSyncAccessibility.operationToggle(operation.primaryKey))
    }
}

private struct SpecSyncRemovedRow: View {
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
        .accessibilityIdentifier(SpecSyncAccessibility.operationToggle(rowID))
    }
}

private struct SpecSyncModifiedRow: View {
    let title: String
    let subtitle: String
    let fieldDeltas: [SpecFieldDelta]
    let isSelected: Bool
    let rowID: String
    let onToggle: () -> Void
    var showsIdentityBadge: Bool = false

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(fieldDeltas.enumerated()), id: \.offset) { _, delta in
                    SpecSyncFieldDeltaRow(delta: delta)
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
                    }
                    Text(subtitle)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityIdentifier(SpecSyncAccessibility.operationToggle(rowID))
    }
}

private struct SpecSyncUnchangedRow: View {
    let title: String
    let subtitle: String
    let rowID: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline.weight(.medium))
            Text(subtitle)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier(SpecSyncAccessibility.operationRow(rowID))
    }
}

private struct SpecSyncFieldDeltaRow: View {
    let delta: SpecFieldDelta

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(SpecSyncHelpers.fieldLabel(delta.field))
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
                .textSelection(.enabled)
                .lineLimit(3)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 8))
    }
}