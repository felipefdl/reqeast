//
//  CloudSyncSendHandlingTests.swift
//  ReqeastTests
//

import CloudKit
import Foundation
import Testing
@testable import Reqeast

@Suite("CloudSync SendHandling")
struct CloudSyncSendHandlingTests {

    /// Builds a `CKError.partialFailure` whose `partialErrorsByItemID` is populated, matching
    /// the case where the delegate already saw the per-record failures.
    private func handledPartialFailure(_ inner: CKError.Code = .serverRecordChanged) -> Error {
        let recordID = CKRecord.ID(recordName: "r1")
        let nested = NSError(domain: CKErrorDomain, code: inner.rawValue)
        return NSError(
            domain: CKErrorDomain,
            code: CKError.partialFailure.rawValue,
            userInfo: [CKPartialErrorsByItemIDKey: [recordID: nested]]
        )
    }

    @Test func transientSaveErrorCodesAreRetryable() {
        let retryable = CloudSyncSendHandling.retryableSaveErrorCodes
        #expect(retryable.contains(.zoneBusy))
        #expect(retryable.contains(.serviceUnavailable))
        #expect(retryable.contains(.requestRateLimited))
        #expect(retryable.contains(.networkFailure))
        #expect(retryable.contains(.networkUnavailable))
    }

    @Test func nonRetryableSaveErrorCodesAreExplicit() {
        let nonRetryable = CloudSyncSendHandling.nonRetryableSaveErrorCodes
        #expect(nonRetryable.contains(.notAuthenticated))
        #expect(nonRetryable.contains(.quotaExceeded))
    }

    @Test func nonPartialCloudKitErrorsAreNotHandled() {
        let codes: [CKError.Code] = [.networkFailure, .quotaExceeded, .notAuthenticated, .serverRecordChanged]
        for code in codes {
            #expect(!CloudSyncSendHandling.isHandledPartialFailure(CKError(code)))
        }
    }

    @Test func nonCloudKitErrorIsNotHandled() {
        struct OtherError: Error {}
        #expect(!CloudSyncSendHandling.isHandledPartialFailure(OtherError()))
    }

    @Test func reportableErrorIsNilWhenBothNil() {
        #expect(CloudSyncSendHandling.reportableError(send: nil, fetch: nil) == nil)
    }

    @Test func reportableErrorIsNilWhenOnlyHandledPartialFailures() {
        let send = handledPartialFailure()
        let fetch = handledPartialFailure()
        #expect(CloudSyncSendHandling.reportableError(send: send, fetch: nil) == nil)
        #expect(CloudSyncSendHandling.reportableError(send: nil, fetch: fetch) == nil)
        #expect(CloudSyncSendHandling.reportableError(send: send, fetch: fetch) == nil)
    }

    @Test func reportableErrorPicksFetchWhenSendIsHandledPartialFailure() {
        let send = handledPartialFailure()
        let fetch: Error = CKError(.networkFailure)
        let picked = CloudSyncSendHandling.reportableError(send: send, fetch: fetch)
        #expect((picked as? CKError)?.code == .networkFailure)
    }

    @Test func reportableErrorPicksSendWhenFetchIsHandledPartialFailure() {
        let send: Error = CKError(.quotaExceeded)
        let fetch = handledPartialFailure()
        let picked = CloudSyncSendHandling.reportableError(send: send, fetch: fetch)
        #expect((picked as? CKError)?.code == .quotaExceeded)
    }

    @Test func reportableErrorPrefersSendWhenBothAreReal() {
        let send: Error = CKError(.notAuthenticated)
        let fetch: Error = CKError(.networkFailure)
        let picked = CloudSyncSendHandling.reportableError(send: send, fetch: fetch)
        #expect((picked as? CKError)?.code == .notAuthenticated)
    }

    @Test func partialFailureWithEmptyItemDictIsNotHandled() {
        let err = CKError(.partialFailure)
        #expect(!CloudSyncSendHandling.isHandledPartialFailure(err))
    }

    @Test func partialFailureWithPerRecordErrorsIsHandled() {
        #expect(CloudSyncSendHandling.isHandledPartialFailure(handledPartialFailure()))
    }

    @Test func quotaRecoveryCodesAreExplicit() {
        let codes = CloudSyncSendHandling.quotaRecoveryCodes
        #expect(codes.contains(.quotaExceeded))
    }

    @Test func quotaRecoveryAndRetryableAreDisjoint() {
        let retry = CloudSyncSendHandling.retryableSaveErrorCodes
        let quota = CloudSyncSendHandling.quotaRecoveryCodes
        #expect(retry.isDisjoint(with: quota))
    }

    @Test func quotaRecoveryCodesAreSubsetOfNonRetryable() {
        let nonRetryable = CloudSyncSendHandling.nonRetryableSaveErrorCodes
        let quota = CloudSyncSendHandling.quotaRecoveryCodes
        #expect(quota.isSubset(of: nonRetryable))
    }
}
