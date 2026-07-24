//
//  HttpResponseMetadata.swift
//  Reqeast
//

import Foundation

struct StoredTimingBreakdown: Codable, Hashable {
    var dnsLookupMs: Double
    var connectionMs: Double
    var downloadMs: Double
    var totalMs: Double

    var phases: [(String, Double)] {
        [
            (String(localized: "DNS Lookup"), dnsLookupMs),
            (String(localized: "Connection"), connectionMs),
            (String(localized: "Download"), downloadMs),
        ].filter { $0.1 > 0.01 }
    }

    init(from rustTiming: HttpTimingBreakdown) {
        self.dnsLookupMs = rustTiming.dnsLookupMs
        self.connectionMs = rustTiming.connectionMs
        self.downloadMs = rustTiming.downloadMs
        self.totalMs = rustTiming.totalMs
    }

    init(dnsLookupMs: Double, connectionMs: Double, downloadMs: Double, totalMs: Double) {
        self.dnsLookupMs = dnsLookupMs
        self.connectionMs = connectionMs
        self.downloadMs = downloadMs
        self.totalMs = totalMs
    }
}

struct StoredCertificateInfo: Codable, Hashable {
    var subjectCn: String?
    var issuerCn: String?
    var validUntil: String?

    init(from rustCert: HttpCertificateInfo) {
        self.subjectCn = rustCert.subjectCn
        self.issuerCn = rustCert.issuerCn
        self.validUntil = rustCert.validUntil
    }

    init(subjectCn: String?, issuerCn: String?, validUntil: String?) {
        self.subjectCn = subjectCn
        self.issuerCn = issuerCn
        self.validUntil = validUntil
    }
}

struct StoredSizeInfo: Codable, Hashable {
    var requestHeadersSize: Int64
    var requestBodySize: Int64
    var responseHeadersSize: Int64
    var responseBodySize: Int64
    var responseCompressedSize: Int64

    var totalRequestSize: Int64 { requestHeadersSize + requestBodySize }
    var totalResponseSize: Int64 { responseHeadersSize + responseBodySize }
    var isCompressed: Bool { responseCompressedSize > 0 }

    init(from rustSize: HttpSizeInfo) {
        self.requestHeadersSize = Int64(rustSize.requestHeadersSize)
        self.requestBodySize = Int64(rustSize.requestBodySize)
        self.responseHeadersSize = Int64(rustSize.responseHeadersSize)
        self.responseBodySize = Int64(rustSize.responseBodySize)
        self.responseCompressedSize = Int64(rustSize.responseCompressedSize)
    }

    init(
        requestHeadersSize: Int64, requestBodySize: Int64,
        responseHeadersSize: Int64, responseBodySize: Int64,
        responseCompressedSize: Int64
    ) {
        self.requestHeadersSize = requestHeadersSize
        self.requestBodySize = requestBodySize
        self.responseHeadersSize = responseHeadersSize
        self.responseBodySize = responseBodySize
        self.responseCompressedSize = responseCompressedSize
    }
}

struct StoredRedirectEntry: Codable, Hashable {
    var url: String
    var statusCode: Int

    init(from rustEntry: HttpRedirectEntry) {
        self.url = rustEntry.url
        self.statusCode = Int(rustEntry.statusCode)
    }

    init(url: String, statusCode: Int) {
        self.url = url
        self.statusCode = statusCode
    }
}

func formatBytes(_ bytes: Int64) -> String {
    if bytes < 1024 {
        return "\(bytes) B"
    }
    let oneFraction: FloatingPointFormatStyle<Double> = .number.precision(.fractionLength(1))
    let kb = Double(bytes) / 1024
    if kb < 1024 {
        return kb.formatted(oneFraction) + " KB"
    }
    return (kb / 1024).formatted(oneFraction) + " MB"
}
