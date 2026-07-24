//
//  CloudSyncStateTests.swift
//  ReqeastTests
//

import Foundation
import Testing
@testable import Reqeast

@MainActor
@Suite("CloudSyncState", .serialized)
struct CloudSyncStateTests {

    @Test func idleByDefault() {
        let state = CloudSyncState()
        #expect(state.phase == .idle)
        #expect(state.lastSuccessfulSync == nil)
        #expect(!state.isSyncing)
        #expect(state.currentError == nil)
    }

    @Test func beginSyncMovesToSyncing() {
        let state = CloudSyncState()
        state.beginSync()
        #expect(state.isSyncing)
    }

    @Test func finishSyncStampsTimestampAndReturnsIdle() {
        let state = CloudSyncState()
        state.beginSync()
        state.finishSync()
        #expect(state.phase == .idle)
        #expect(state.lastSuccessfulSync != nil)
    }

    @Test func reportErrorOverridesPhase() {
        let state = CloudSyncState()
        state.beginSync()
        let err = RequestError(kind: .cloudQuotaExceeded, message: "iCloud full")
        state.report(err)
        #expect(state.currentError == err)
        #expect(!state.isSyncing)
    }

    @Test func beginSyncDoesNotClearPendingError() {
        let state = CloudSyncState()
        let err = RequestError(kind: .cloudSync, message: "network")
        state.report(err)
        state.beginSync()
        #expect(state.currentError == err)
    }

    @Test func finishSyncDoesNotClearErrorReportedThisCycle() {
        let state = CloudSyncState()
        let err = RequestError(kind: .cloudSync, message: "network")
        state.report(err)
        state.finishSync()
        #expect(state.currentError == err)
        #expect(state.lastSuccessfulSync != nil)
    }

    @Test func staleTransientErrorClearsAfterCleanCycle() {
        let state = CloudSyncState()
        state.report(RequestError(kind: .cloudSync, message: "network blip"))
        // Next cycle runs clean: the old error is stale and must auto-clear.
        state.beginSync()
        state.finishSync()
        #expect(state.phase == .idle)
    }

    @Test func staleQuotaErrorClearsAfterCleanCycle() {
        let state = CloudSyncState()
        state.report(RequestError(kind: .cloudQuotaExceeded, message: "full"))
        state.beginSync()
        state.finishSync()
        #expect(state.phase == .idle)
    }

    @Test func stickyRecordTooLargeSurvivesCleanCycle() {
        let state = CloudSyncState()
        let err = RequestError(kind: .cloudRecordTooLarge, message: "big")
        state.report(err)
        // The oversized record is blocked from retry, so a clean cycle does not disprove it.
        state.beginSync()
        state.finishSync()
        #expect(state.currentError == err)
    }

    @Test func stickyPermanentFailureSurvivesCleanCycle() {
        let state = CloudSyncState()
        let err = RequestError(kind: .cloudPermanentFailure, message: "rejected")
        state.report(err)
        state.beginSync()
        state.finishSync()
        #expect(state.currentError == err)
    }

    @Test func cleanSendBatchClearsStaleError() {
        let state = CloudSyncState()
        state.report(RequestError(kind: .cloudNotAuthenticated, message: "signed out"))
        // Engine-automatic cycle: will-send event resets tracking, then a fully clean batch.
        state.noteCycleWillStart()
        state.recordCleanSendBatch()
        #expect(state.phase == .idle)
        #expect(state.lastSuccessfulSync != nil)
    }

    @Test func cleanSendBatchKeepsErrorReportedThisCycle() {
        let state = CloudSyncState()
        state.noteCycleWillStart()
        let err = RequestError(kind: .cloudDecodeError, message: "corrupt")
        state.report(err)
        state.recordCleanSendBatch()
        #expect(state.currentError == err)
    }

    @Test func resetClearsErrorAndTimestamp() {
        let state = CloudSyncState()
        state.report(RequestError(kind: .cloudRecordTooLarge, message: "big"))
        state.finishSync()
        state.reset()
        #expect(state.phase == .idle)
        #expect(state.lastSuccessfulSync == nil)
    }

    @Test func clearErrorReturnsToIdle() {
        let state = CloudSyncState()
        state.report(RequestError(kind: .cloudSync, message: "x"))
        state.clearError()
        #expect(state.phase == .idle)
    }

    @Test func endSyncAttemptDoesNotStampLastSuccessfulSync() {
        let state = CloudSyncState()
        state.beginSync()
        state.endSyncAttempt()
        #expect(state.phase == .idle)
        #expect(state.lastSuccessfulSync == nil)
    }

    @Test func endSyncAttemptPreservesPendingError() {
        let state = CloudSyncState()
        let err = RequestError(kind: .cloudQuotaExceeded, message: "full")
        state.report(err)
        state.endSyncAttempt()
        #expect(state.currentError == err)
        #expect(state.lastSuccessfulSync == nil)
    }

    @Test func reportDoesNotOverwriteQuotaWithDecode() {
        let state = CloudSyncState()
        let quota = RequestError(kind: .cloudQuotaExceeded, message: "full")
        state.report(quota)
        state.report(RequestError(kind: .cloudDecodeError, message: "corrupt"))
        #expect(state.currentError == quota)
    }

    @Test func reportDoesNotOverwriteNotAuthenticatedWithSync() {
        let state = CloudSyncState()
        let auth = RequestError(kind: .cloudNotAuthenticated, message: "signed out")
        state.report(auth)
        state.report(RequestError(kind: .cloudSync, message: "network"))
        #expect(state.currentError == auth)
    }

    @Test func reportUpgradesFromSyncToQuota() {
        let state = CloudSyncState()
        state.report(RequestError(kind: .cloudSync, message: "network"))
        let quota = RequestError(kind: .cloudQuotaExceeded, message: "full")
        state.report(quota)
        #expect(state.currentError == quota)
    }

    @Test func reportDoesNotOverwriteRecordTooLargeWithSync() {
        let state = CloudSyncState()
        let tooLarge = RequestError(kind: .cloudRecordTooLarge, message: "big")
        state.report(tooLarge)
        state.report(RequestError(kind: .cloudSync, message: "network"))
        #expect(state.currentError == tooLarge)
    }

    @Test func reportOverwritesSameKindWithLaterMessage() {
        let state = CloudSyncState()
        state.report(RequestError(kind: .cloudSync, message: "first"))
        let later = RequestError(kind: .cloudSync, message: "second")
        state.report(later)
        #expect(state.currentError == later)
    }
}
