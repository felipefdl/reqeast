//
//  SpecSyncHelpersTests.swift
//  ReqeastTests
//

import Testing
@testable import Reqeast

@Suite("SpecSyncHelpers")
struct SpecSyncHelpersTests {

    @Test func truncatedFingerprintShowsPrefixAndSuffix() {
        let full = "abcdef0123456789deadbeef0123456789cafebabe0123456789abcd"
        #expect(SpecSyncHelpers.truncatedFingerprint(full) == "abcdef01…6789abcd")
    }

    @Test func truncatedFingerprintReturnsShortValuesUnchanged() {
        #expect(SpecSyncHelpers.truncatedFingerprint("abc") == "abc")
    }

    @Test func fingerprintMatchLabelReflectsComparison() {
        #expect(SpecSyncHelpers.fingerprintsMatch("same", "same"))
        #expect(!SpecSyncHelpers.fingerprintsMatch("one", "two"))
    }
}