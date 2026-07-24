//
//  CloudSyncState.swift
//  Reqeast
//

import Foundation

@MainActor
@Observable
final class CloudSyncState {
    enum Phase: Equatable {
        case idle
        case syncing
        case error(RequestError)
    }

    var phase: Phase = .idle
    var lastSuccessfulSync: Date?

    /// Whether `report` fired since the current cycle started. Completion paths use it to
    /// distinguish "this cycle produced this error" (keep it visible) from "error left over
    /// from an earlier cycle" (clear it once the pipe demonstrably works again).
    private var errorReportedThisCycle = false

    /// Error kinds describing a standing per-item condition that automatic retries will not
    /// re-attempt (the record is blocked from requeue until the user edits it). These survive
    /// clean cycles so the user keeps seeing that one item is not syncing; everything else
    /// auto-clears once a later cycle or send batch completes without errors.
    private static let stickyKinds: Set<RequestErrorKind> = [.cloudRecordTooLarge, .cloudPermanentFailure]

    /// Resets per-cycle error tracking. Manual cycles call it via `beginSync`; engine-automatic
    /// cycles via the `.willSendChanges` / `.willFetchChanges` delegate events.
    func noteCycleWillStart() {
        errorReportedThisCycle = false
    }

    func beginSync() {
        noteCycleWillStart()
        if case .error = phase { return }
        phase = .syncing
    }

    func finishSync() {
        lastSuccessfulSync = .now
        guard !errorReportedThisCycle else { return }
        clearRecoveredError()
    }

    /// Transitions out of `.syncing` without stamping `lastSuccessfulSync`. Use when a cycle
    /// completed but had a suppressed partial failure: the per-record errors were already
    /// classified by the delegate, so we should not pretend the cycle was a clean success.
    func endSyncAttempt() {
        if case .error = phase { return }
        phase = .idle
    }

    /// Positive evidence from an engine-automatic cycle: a send batch where every record
    /// succeeded. Clears a stale error from an earlier cycle (the transport is healthy again)
    /// without touching errors reported during the current cycle.
    func recordCleanSendBatch() {
        lastSuccessfulSync = .now
        guard !errorReportedThisCycle else { return }
        clearRecoveredError()
    }

    /// Full reset for account-lifecycle boundaries (sign-out, account switch, zone purge,
    /// encrypted-data reset, reset-all-data). The previous error and success timestamp belong
    /// to a sync world that no longer exists.
    func reset() {
        phase = .idle
        lastSuccessfulSync = nil
        errorReportedThisCycle = false
    }

    private func clearRecoveredError() {
        if case .error(let err) = phase, Self.stickyKinds.contains(err.kind) { return }
        phase = .idle
    }

    /// Priority by error kind so a lower-severity error (e.g. a generic .cloudSync network hiccup,
    /// or a single decode failure) cannot overwrite a user-action-required one (quota full, not
    /// signed in, record too big) that fired earlier in the same sync cycle. Same-kind errors
    /// overwrite so a newer message replaces a stale one.
    private static func priority(_ kind: RequestErrorKind) -> Int {
        switch kind {
        case .cloudQuotaExceeded, .cloudNotAuthenticated: 100
        case .cloudRecordTooLarge: 90
        case .cloudPermanentFailure: 80
        case .cloudConflictUnresolvable: 70
        case .cloudDecodeError: 60
        case .cloudSync: 10
        default: 0
        }
    }

    func report(_ error: RequestError) {
        errorReportedThisCycle = true
        if case .error(let existing) = phase,
           existing.kind != error.kind,
           Self.priority(error.kind) < Self.priority(existing.kind) {
            return
        }
        phase = .error(error)
    }

    func clearError() {
        if case .error = phase {
            phase = .idle
        }
    }

    var currentError: RequestError? {
        if case .error(let err) = phase { return err }
        return nil
    }

    var isSyncing: Bool {
        if case .syncing = phase { return true }
        return false
    }
}
