//
//  SpecImportErrorTests.swift
//  ReqeastTests
//

import Foundation
import Testing
@testable import Reqeast

@Suite("SpecImportError")
struct SpecImportErrorTests {

    @Test func invalidSpecKindAndPresentation() {
        let error = SpecImportError.InvalidSpec("missing openapi field")
        #expect(error.kind == .invalidSpec)
        #expect(error.message == "missing openapi field")
        #expect(error.iconName == "doc.badge.exclamationmark")
        #expect(error.fullMessage.contains("missing openapi field"))
    }

    @Test func unsupportedFormatKindAndPresentation() {
        let error = SpecImportError.UnsupportedFormat("application/xml")
        #expect(error.kind == .unsupportedFormat)
        #expect(error.message == "application/xml")
        #expect(error.iconName == "doc.questionmark")
    }

    @Test func parseErrorKindAndPresentation() {
        let error = SpecImportError.ParseError("unexpected token at line 4")
        #expect(error.kind == .parseError)
        #expect(error.message == "unexpected token at line 4")
        #expect(error.iconName == "text.badge.xmark")
    }

    @Test func bridgesFromRustSpecImportError() {
        let ffiError: SpecImportError = .ParseError("invalid JSON")
        let bridged = SpecImportError.from(ffiError)
        #expect(bridged == ffiError)
        #expect(bridged.kind == .parseError)
        #expect(bridged.message == "invalid JSON")
    }

    @Test func bridgesFromReqeastInvalidConfig() {
        let error = SpecImportError.from(ReqeastError.InvalidConfig("file too large"))
        #expect(error.kind == .invalidSpec)
        #expect(error.message == "file too large")
    }

    @Test func bridgesFromReqeastInternalError() {
        let error = SpecImportError.from(ReqeastError.InternalError("normalize failed"))
        #expect(error.kind == .parseError)
        #expect(error.message == "normalize failed")
    }

    @Test func bridgesSafeFetchBlockedIPToParseError() {
        let error = SpecImportError.from(SafeFetchError.blockedIPAddress("10.0.0.55"))
        #expect(error.kind == .parseError)
        #expect(error.message.contains("SafeFetchError"))
        #expect(error.message.contains("10.0.0.55"))
    }

    @Test func bridgesGitSpecSourceTokenRequiredToInvalidSpec() {
        let error = SpecImportError.from(GitSpecSourceError.tokenRequired)
        #expect(error.kind == .invalidSpec)
        #expect(error.message.contains("personal access token"))
    }

    @Test func bridgesFromGenericError() {
        struct SampleError: Error, LocalizedError {
            var errorDescription: String? { "sample failure" }
        }
        let error = SpecImportError.from(SampleError())
        #expect(error.kind == .parseError)
        #expect(error.message.contains("SampleError"))
        #expect(error.message.contains("sample failure"))
    }

    @Test func fromMessageUsesRequestedKind() {
        let invalid = SpecImportError.from(message: "bad spec", kind: .invalidSpec)
        #expect(invalid.kind == .invalidSpec)
        #expect(invalid.message == "bad spec")

        let unsupported = SpecImportError.from(message: "xml", kind: .unsupportedFormat)
        #expect(unsupported.kind == .unsupportedFormat)

        let unknown = SpecImportError.from(message: "oops", kind: .unknown)
        #expect(unknown.kind == .parseError)
        #expect(unknown.message == "oops")
    }

    @Test func parseSpecInvalidJsonProducesParseError() {
        do {
            _ = try parseSpec(
                bytes: Data("{not json".utf8),
                sourceHint: .json,
                bundleEntryPath: nil,
                options: SpecParseOptions(enableSchemaSynthesis: false)
            )
            Issue.record("expected parseSpec to throw")
        } catch {
            let mapped = SpecImportError.from(error)
            #expect(mapped.kind == .parseError)
            #expect(!mapped.message.isEmpty)
        }
    }
}