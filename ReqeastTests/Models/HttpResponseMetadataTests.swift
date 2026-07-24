//
//  HttpResponseMetadataTests.swift
//  ReqeastTests
//

import Foundation
import Testing
@testable import Reqeast

@Suite("HttpResponseMetadata")
struct HttpResponseMetadataTests {

    // MARK: - StoredSizeInfo

    @Test func totalRequestSize() {
        let size = StoredSizeInfo(
            requestHeadersSize: 200, requestBodySize: 300,
            responseHeadersSize: 0, responseBodySize: 0,
            responseCompressedSize: 0
        )
        #expect(size.totalRequestSize == 500)
    }

    @Test func totalResponseSize() {
        let size = StoredSizeInfo(
            requestHeadersSize: 0, requestBodySize: 0,
            responseHeadersSize: 150, responseBodySize: 850,
            responseCompressedSize: 0
        )
        #expect(size.totalResponseSize == 1000)
    }

    @Test func isCompressedTrueWhenPositive() {
        let size = StoredSizeInfo(
            requestHeadersSize: 0, requestBodySize: 0,
            responseHeadersSize: 0, responseBodySize: 0,
            responseCompressedSize: 512
        )
        #expect(size.isCompressed == true)
    }

    @Test func isCompressedFalseWhenZero() {
        let size = StoredSizeInfo(
            requestHeadersSize: 0, requestBodySize: 0,
            responseHeadersSize: 0, responseBodySize: 0,
            responseCompressedSize: 0
        )
        #expect(size.isCompressed == false)
    }

    @Test func sizeInfoCodableRoundTrip() throws {
        let size = StoredSizeInfo(
            requestHeadersSize: 100, requestBodySize: 200,
            responseHeadersSize: 300, responseBodySize: 400,
            responseCompressedSize: 150
        )
        let data = try JSONEncoder().encode(size)
        let decoded = try JSONDecoder().decode(StoredSizeInfo.self, from: data)
        #expect(decoded == size)
    }

    // MARK: - StoredTimingBreakdown

    @Test func phasesFiltersSmallValues() {
        let timing = StoredTimingBreakdown(
            dnsLookupMs: 0.005, connectionMs: 50.0,
            downloadMs: 0.001, totalMs: 50.006
        )
        let phases = timing.phases
        #expect(phases.count == 1)
        #expect(phases[0].0 == "Connection")
    }

    @Test func phasesIncludesLargeValues() {
        let timing = StoredTimingBreakdown(
            dnsLookupMs: 10.0, connectionMs: 25.0,
            downloadMs: 15.0, totalMs: 50.0
        )
        #expect(timing.phases.count == 3)
    }

    @Test func timingCodableRoundTrip() throws {
        let timing = StoredTimingBreakdown(
            dnsLookupMs: 5.0, connectionMs: 10.0,
            downloadMs: 20.0, totalMs: 35.0
        )
        let data = try JSONEncoder().encode(timing)
        let decoded = try JSONDecoder().decode(StoredTimingBreakdown.self, from: data)
        #expect(decoded == timing)
    }

    // MARK: - StoredCertificateInfo

    @Test func certificateInfoCodableRoundTrip() throws {
        let cert = StoredCertificateInfo(
            subjectCn: "example.com",
            issuerCn: "Let's Encrypt",
            validUntil: "2026-12-31"
        )
        let data = try JSONEncoder().encode(cert)
        let decoded = try JSONDecoder().decode(StoredCertificateInfo.self, from: data)
        #expect(decoded == cert)
    }

    @Test func certificateInfoCodableWithNils() throws {
        let cert = StoredCertificateInfo(
            subjectCn: nil, issuerCn: nil, validUntil: nil
        )
        let data = try JSONEncoder().encode(cert)
        let decoded = try JSONDecoder().decode(StoredCertificateInfo.self, from: data)
        #expect(decoded.subjectCn == nil)
        #expect(decoded.issuerCn == nil)
        #expect(decoded.validUntil == nil)
    }

    // MARK: - StoredRedirectEntry

    @Test func redirectEntryCodableRoundTrip() throws {
        let entry = StoredRedirectEntry(url: "https://example.com/new", statusCode: 301)
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(StoredRedirectEntry.self, from: data)
        #expect(decoded == entry)
    }

    // MARK: - formatBytes

    @Test func formatBytesUnderKilobyte() {
        #expect(formatBytes(512) == "512 B")
        #expect(formatBytes(0) == "0 B")
    }

    @Test func formatBytesKilobytes() {
        #expect(formatBytes(2048) == "2.0 KB")
    }

    @Test func formatBytesMegabytes() {
        #expect(formatBytes(1_500_000) == "1.4 MB")
    }
}
