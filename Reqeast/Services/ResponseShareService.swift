//
//  ResponseShareService.swift
//  Reqeast
//

import Foundation

enum ResponseShareService {
    private static let bodyTruncateLimit = 10_000

    static func generateMarkdown(
        response: HttpResponseData,
        method: String,
        url: String,
        requestName: String?
    ) -> String {
        var lines: [String] = []

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        lines.append("# Reqeast/v\(version) - \(formatTimestamp(response.timestamp))")
        lines.append("")

        if let name = requestName {
            lines.append("> \(name)")
            lines.append("")
        }

        lines.append("## Request")
        lines.append("")
        lines.append("- \(method) \(url)")
        lines.append("")

        if response.finalUrl != url {
            lines.append("- Final URL: \(response.finalUrl)")
            lines.append("")
        }

        lines.append("## Response")
        lines.append("")
        lines.append("- Status: \(response.statusCode) \(response.statusText)")
        lines.append("- Time: \(response.formattedElapsed)")
        lines.append("- Size: \(response.formattedBodySize)")
        lines.append("- Protocol: \(response.httpVersion)")
        if let addr = response.remoteAddr {
            lines.append("- Remote: \(addr)")
        }
        lines.append("- Timestamp: \(formatTimestamp(response.timestamp))")
        lines.append("")

        lines.append("## Headers")
        lines.append("")
        for header in response.headers {
            lines.append("- \(header.key): \(header.value)")
        }
        lines.append("")

        lines.append("## Body")
        lines.append("")
        lines.append(formatBody(response: response))

        return lines.joined(separator: "\n")
    }

    static func generateDetailedMarkdown(
        response: HttpResponseData,
        method: String,
        url: String,
        requestName: String?
    ) -> String {
        var md = generateMarkdown(response: response, method: method, url: url, requestName: requestName)

        if let timing = response.timing {
            md += "\n\n## Timing\n\n"
            for phase in timing.phases {
                md += "- \(phase.0): \(formatMs(phase.1))\n"
            }
            md += "- Total: \(formatMs(timing.totalMs))\n"
        }

        if let si = response.sizeInfo {
            md += "\n## Size\n\n"
            md += "- Request Headers: \(formatBytes(si.requestHeadersSize))\n"
            md += "- Request Body: \(formatBytes(si.requestBodySize))\n"
            md += "- Response Headers: \(formatBytes(si.responseHeadersSize))\n"
            md += "- Response Body: \(formatBytes(si.responseBodySize))\n"
            if si.isCompressed {
                md += "- Compressed: \(formatBytes(si.responseCompressedSize))\n"
            }
            md += "\n> Sizes are approximate\n"
        }

        if let cert = response.certificate {
            md += "\n## Certificate\n\n"
            if let subject = cert.subjectCn {
                md += "- Subject: \(subject)\n"
            }
            if let issuer = cert.issuerCn {
                md += "- Issuer: \(issuer)\n"
            }
            if let until = cert.validUntil {
                md += "- Valid Until: \(until)\n"
            }
        }

        if !response.redirectChain.isEmpty {
            md += "\n## Redirects\n\n"
            for (index, entry) in response.redirectChain.enumerated() {
                md += "\(index + 1). \(entry.statusCode) \(entry.url)\n"
            }
        }

        return md
    }

    private static func formatMs(_ ms: Double) -> String {
        DurationFormat.abbreviated(fromMilliseconds: ms)
    }

    private static func formatBody(response: HttpResponseData) -> String {
        if response.body.isEmpty {
            return "Empty body"
        }

        guard let text = String(data: response.body, encoding: .utf8) else {
            return "Binary data (\(response.formattedBodySize))"
        }

        let lang = codeFenceLanguage(headers: response.headers, body: response.body)
        let truncated = text.count > bodyTruncateLimit
        let content = truncated ? String(text.prefix(bodyTruncateLimit)) : text

        var result = "```\(lang)\n\(content)\n```"
        if truncated {
            result += "\n\nTruncated at \(bodyTruncateLimit) characters (\(text.count) total)"
        }
        return result
    }

    private static func codeFenceLanguage(headers: [KeyValueEntry], body: Data) -> String {
        let type = ResponseContentDetector.detect(headers: headers, body: body)
        switch type {
        case .json:       return "json"
        case .html:       return "html"
        case .xml:        return "xml"
        case .text:       return ""
        case .image:      return ""
        case .binary:     return ""
        }
    }

    private static func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date) + " UTC"
    }
}
