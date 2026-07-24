//
//  SafeFetchService.swift
//  Reqeast
//
//  Transport: Ephemeral URLSession with cookies disabled. Redirects are not
//  auto-followed — URLSessionTaskDelegate returns nil so each hop is handled
//  manually: parse Location, re-resolve the host, re-validate all IPs, cap at
//  3 hops. After DNS validation, the request URL is rewritten to a pinned IP
//  literal (eliminating connect-time re-resolve / TOCTOU) while the original
//  hostname is sent as the HTTP Host header. HTTPS uses PinnedIPURLProtocol
//  (NWConnection + TLS with correct SNI); tests inject MockURLProtocol instead.
//  Response bodies stream via URLSessionDataDelegate chunks with a 5 MiB cap.
//

import Darwin
import Foundation
import Network

// MARK: - Errors

enum SafeFetchError: Error, LocalizedError, Equatable {
    case httpNotAllowed
    case invalidURL
    case hostNotTrusted(String)
    case blockedIPAddress(String)
    case dnsResolutionFailed(String)
    case tooManyRedirects
    case invalidRedirect
    case invalidResponse
    case responseTooLarge
    case httpError(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .httpNotAllowed:
            String(localized: "HTTP URLs are not allowed. Use HTTPS.")
        case .invalidURL:
            String(localized: "The URL is invalid.")
        case .hostNotTrusted(let host):
            String(
                localized: "Host \(host) is not trusted. Add it under Settings → Trusted Git Hosts to import from this server."
            )
        case .blockedIPAddress(let ip):
            String(localized: "Blocked IP address: \(ip)")
        case .dnsResolutionFailed(let host):
            String(localized: "Could not resolve host: \(host)")
        case .tooManyRedirects:
            String(localized: "Too many redirects.")
        case .invalidRedirect:
            String(localized: "Invalid redirect location.")
        case .invalidResponse:
            String(localized: "Invalid server response.")
        case .responseTooLarge:
            String(localized: "Response exceeds the 5 MiB size limit.")
        case .httpError(let statusCode):
            String(localized: "HTTP error \(statusCode).")
        }
    }
}

// MARK: - Host Resolution

protocol HostResolving: Sendable {
    func resolve(hostname: String) throws -> [String]
}

nonisolated struct SystemHostResolver: HostResolving {
    func resolve(hostname: String) throws -> [String] {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        hints.ai_flags = AI_ADDRCONFIG

        var head: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo(hostname, nil, &hints, &head)
        guard status == 0, let head else {
            throw SafeFetchError.dnsResolutionFailed(hostname)
        }
        defer { freeaddrinfo(head) }

        var addresses: [String] = []
        var node: UnsafeMutablePointer<addrinfo>? = head
        while let current = node {
            if let ip = numericHostString(
                from: current.pointee.ai_addr,
                length: current.pointee.ai_addrlen
            ) {
                addresses.append(ip)
            }
            node = current.pointee.ai_next
        }

        guard !addresses.isEmpty else {
            throw SafeFetchError.dnsResolutionFailed(hostname)
        }

        return addresses
    }

    private func numericHostString(from address: UnsafePointer<sockaddr>?, length: socklen_t) -> String? {
        guard let address else { return nil }
        var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let result = getnameinfo(
            address,
            length,
            &hostBuffer,
            socklen_t(hostBuffer.count),
            nil,
            0,
            NI_NUMERICHOST
        )
        guard result == 0 else { return nil }
        let raw = String(cString: hostBuffer)
        if let percent = raw.firstIndex(of: "%") {
            return String(raw[..<percent])
        }
        return raw
    }
}

// MARK: - IP Validation

enum IPAddressBlocklist {
    static func isBlocked(_ ipString: String) -> Bool {
        let normalized = ipString.lowercased()
        if let octets = parseIPv4(normalized) {
            return isBlockedIPv4(octets)
        }
        if let bytes = parseIPv6(normalized) {
            return isBlockedIPv6(bytes)
        }
        return true
    }

    private static func parseIPv4(_ string: String) -> (UInt8, UInt8, UInt8, UInt8)? {
        var addr = in_addr()
        guard string.withCString({ inet_pton(AF_INET, $0, &addr) }) == 1 else { return nil }
        let value = UInt32(bigEndian: addr.s_addr)
        return (
            UInt8((value >> 24) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF)
        )
    }

    private static func parseIPv6(_ string: String) -> [UInt8]? {
        var addr = in6_addr()
        guard string.withCString({ inet_pton(AF_INET6, $0, &addr) }) == 1 else { return nil }
        return withUnsafeBytes(of: addr) { Array($0) }
    }

    private static func isBlockedIPv4(_ octets: (UInt8, UInt8, UInt8, UInt8)) -> Bool {
        let (a, b, _, _) = octets

        if a == 0 { return true }
        if a == 10 { return true }
        if a == 127 { return true }
        if a == 169 && b == 254 { return true }
        if a == 172 && (16...31).contains(Int(b)) { return true }
        if a == 192 && b == 168 { return true }
        if (224...239).contains(Int(a)) { return true }

        return false
    }

    private static func isBlockedIPv6(_ bytes: [UInt8]) -> Bool {
        guard bytes.count == 16 else { return true }

        if bytes.allSatisfy({ $0 == 0 }) { return true }

        // IPv4-mapped IPv6 (::ffff:a.b.c.d) — apply IPv4 blocklist to embedded address.
        if bytes[0] == 0, bytes[1] == 0, bytes[2] == 0, bytes[3] == 0,
           bytes[4] == 0, bytes[5] == 0, bytes[6] == 0, bytes[7] == 0,
           bytes[8] == 0, bytes[9] == 0, bytes[10] == 0xFF, bytes[11] == 0xFF {
            return isBlockedIPv4((bytes[12], bytes[13], bytes[14], bytes[15]))
        }

        if bytes[0] == 0, bytes[1] == 0, bytes[2] == 0, bytes[3] == 0,
           bytes[4] == 0, bytes[5] == 0, bytes[6] == 0, bytes[7] == 0,
           bytes[8] == 0, bytes[9] == 0, bytes[10] == 0, bytes[11] == 0,
           bytes[12] == 0, bytes[13] == 0, bytes[14] == 0, bytes[15] == 1 {
            return true
        }

        if bytes[0] == 0xFE && (bytes[1] & 0xC0) == 0x80 { return true }
        if (bytes[0] & 0xFE) == 0xFC { return true }
        if bytes[0] == 0xFF { return true }

        if bytes[0] == 0xFE && bytes[1] == 0x80 && bytes[2] == 0x00 && bytes[3] == 0x00,
           bytes[4] == 0x00 && bytes[5] == 0x00 && bytes[6] == 0x00 && bytes[7] == 0x00,
           bytes[8] == 0x00 && bytes[9] == 0x00 && bytes[10] == 0xA9 && bytes[11] == 0xFE,
           bytes[12] == 0xA9 && bytes[13] == 0xFE {
            return true
        }

        return false
    }
}

// MARK: - Pinned Transport (NWConnection + TLS SNI)

private enum PinnedRequestKeys {
    static let pinnedIP = "SafeFetchPinnedIP"
    static let originalHost = "SafeFetchOriginalHost"
}

private nonisolated enum PinnedHTTPClient {
    static let queue = DispatchQueue(label: "com.reqeast.safefetch.pinned")

    static func fetch(
        request: URLRequest,
        pinnedIP: String,
        originalHost: String,
        maxBodyBytes: Int
    ) async throws -> (HTTPURLResponse, Data) {
        guard let url = request.url else { throw SafeFetchError.invalidURL }

        let scheme = url.scheme?.lowercased() ?? "https"
        let port = url.port ?? (scheme == "https" ? 443 : 80)
        let useTLS = scheme == "https"

        let host = NWEndpoint.Host(pinnedIP)
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            throw SafeFetchError.invalidURL
        }

        let parameters: NWParameters
        if useTLS {
            let tls = NWProtocolTLS.Options()
            sec_protocol_options_set_tls_server_name(
                tls.securityProtocolOptions,
                originalHost
            )
            parameters = NWParameters(tls: tls)
        } else {
            parameters = NWParameters.tcp
        }

        let connection = NWConnection(host: host, port: nwPort, using: parameters)

        return try await withCheckedThrowingContinuation { continuation in
            let state = FetchState(
                connection: connection,
                maxBodyBytes: maxBodyBytes,
                continuation: continuation
            )

            connection.stateUpdateHandler = { connectionState in
                switch connectionState {
                case .ready:
                    let payload = buildHTTPRequest(request: request, originalHost: originalHost)
                    connection.send(content: payload, completion: .contentProcessed { error in
                        if let error {
                            state.finish(with: .failure(error))
                        } else {
                            state.receiveNextChunk()
                        }
                    })
                case .failed(let error):
                    state.finish(with: .failure(error))
                case .cancelled:
                    state.finish(with: .failure(URLError(.cancelled)))
                default:
                    break
                }
            }

            connection.start(queue: queue)
        }
    }

    private static func buildHTTPRequest(request: URLRequest, originalHost: String) -> Data {
        guard let url = request.url else { return Data() }

        let method = request.httpMethod ?? "GET"
        var path = url.path
        if path.isEmpty { path = "/" }
        if let query = url.query { path += "?\(query)" }

        var hostHeader = originalHost
        if let port = url.port {
            hostHeader += ":\(port)"
        }

        var lines = ["\(method) \(path) HTTP/1.1", "Host: \(hostHeader)", "Connection: close", "Accept: */*"]
        if let body = request.httpBody, !body.isEmpty {
            lines.append("Content-Length: \(body.count)")
        }
        let headerBlock = lines.joined(separator: "\r\n") + "\r\n\r\n"
        var data = Data(headerBlock.utf8)
        if let body = request.httpBody {
            data.append(body)
        }
        return data
    }

    private nonisolated final class FetchState: @unchecked Sendable {
        private let connection: NWConnection
        private let maxBodyBytes: Int
        private let continuation: CheckedContinuation<(HTTPURLResponse, Data), Error>
        private var buffer = Data()
        private var finished = false

        init(
            connection: NWConnection,
            maxBodyBytes: Int,
            continuation: CheckedContinuation<(HTTPURLResponse, Data), Error>
        ) {
            self.connection = connection
            self.maxBodyBytes = maxBodyBytes
            self.continuation = continuation
        }

        func receiveNextChunk() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [self] content, _, isComplete, error in
                if let error {
                    finish(with: .failure(error))
                    return
                }

                if let content, !content.isEmpty {
                    buffer.append(content)
                    if buffer.count > maxBodyBytes + 65_536 {
                        finish(with: .failure(SafeFetchError.responseTooLarge))
                        return
                    }
                }

                if isComplete {
                    do {
                        let result = try parseResponse()
                        finish(with: .success(result))
                    } catch {
                        finish(with: .failure(error))
                    }
                } else {
                    receiveNextChunk()
                }
            }
        }

        func finish(with result: Result<(HTTPURLResponse, Data), Error>) {
            guard !finished else { return }
            finished = true
            connection.cancel()
            continuation.resume(with: result)
        }

        private func parseResponse() throws -> (HTTPURLResponse, Data) {
            guard let headerRange = buffer.range(of: Data([0x0D, 0x0A, 0x0D, 0x0A])) else {
                throw SafeFetchError.invalidResponse
            }

            let headerData = buffer[..<headerRange.lowerBound]
            guard let headerText = String(data: headerData, encoding: .utf8) else {
                throw SafeFetchError.invalidResponse
            }

            let lines = headerText.split(separator: "\r\n", omittingEmptySubsequences: false)
            guard let statusLine = lines.first else { throw SafeFetchError.invalidResponse }

            let statusParts = statusLine.split(separator: " ", maxSplits: 2)
            guard statusParts.count >= 2, let statusCode = Int(statusParts[1]) else {
                throw SafeFetchError.invalidResponse
            }

            var headerFields: [String: String] = [:]
            for line in lines.dropFirst() where !line.isEmpty {
                guard let colon = line.firstIndex(of: ":") else { continue }
                let name = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
                let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                headerFields[name] = value
            }

            let bodyStart = headerRange.upperBound
            var body = Data(buffer[bodyStart...])

            if let contentLengthValue = headerFields["Content-Length"],
               let contentLength = Int(contentLengthValue) {
                if contentLength > maxBodyBytes {
                    throw SafeFetchError.responseTooLarge
                }
                if body.count > contentLength {
                    body = body.prefix(contentLength)
                }
            }

            if body.count > maxBodyBytes {
                throw SafeFetchError.responseTooLarge
            }

            guard let responseURL = URL(string: "https://placeholder.local/") else {
                throw SafeFetchError.invalidResponse
            }

            guard let httpResponse = HTTPURLResponse(
                url: responseURL,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: headerFields
            ) else {
                throw SafeFetchError.invalidResponse
            }

            return (httpResponse, body)
        }
    }
}

private nonisolated final class PinnedIPURLProtocol: URLProtocol, @unchecked Sendable {
    private var activeTask: Task<Void, Never>?

    override class func canInit(with request: URLRequest) -> Bool {
        property(forKey: PinnedRequestKeys.pinnedIP, in: request) != nil
    }

    override class func canInit(with task: URLSessionTask) -> Bool {
        guard let request = task.currentRequest else { return false }
        return canInit(with: request)
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard
            let pinnedIP = Self.property(forKey: PinnedRequestKeys.pinnedIP, in: request) as? String,
            let originalHost = Self.property(forKey: PinnedRequestKeys.originalHost, in: request) as? String
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        activeTask = Task {
            do {
                let (response, body) = try await PinnedHTTPClient.fetch(
                    request: request,
                    pinnedIP: pinnedIP,
                    originalHost: originalHost,
                    maxBodyBytes: SafeFetchLimits.maxBodyBytes
                )
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                if !body.isEmpty {
                    client?.urlProtocol(self, didLoad: body)
                }
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
        }
    }

    override func stopLoading() {
        activeTask?.cancel()
        activeTask = nil
    }
}

// MARK: - Streaming Session Delegate

private nonisolated final class SafeFetchSessionDelegate: NSObject, URLSessionDataDelegate, URLSessionTaskDelegate,
    @unchecked Sendable
{
    private struct TaskState {
        let continuation: CheckedContinuation<(Data, HTTPURLResponse), Error>
        var data = Data()
        var response: HTTPURLResponse?
        var finished = false
    }

    private let lock = NSLock()
    private var taskStates: [Int: TaskState] = [:]
    private let maxBodyBytes: Int

    init(maxBodyBytes: Int) {
        self.maxBodyBytes = maxBodyBytes
    }

    func register(
        task: URLSessionTask,
        continuation: CheckedContinuation<(Data, HTTPURLResponse), Error>
    ) {
        lock.lock()
        taskStates[task.taskIdentifier] = TaskState(continuation: continuation)
        lock.unlock()
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let httpResponse = response as? HTTPURLResponse else {
            finish(taskID: dataTask.taskIdentifier, result: .failure(SafeFetchError.invalidResponse))
            completionHandler(.cancel)
            return
        }

        if let contentLength = httpResponse.value(forHTTPHeaderField: "Content-Length"),
           let length = Int(contentLength),
           length > maxBodyBytes {
            finish(taskID: dataTask.taskIdentifier, result: .failure(SafeFetchError.responseTooLarge))
            completionHandler(.cancel)
            return
        }

        lock.lock()
        taskStates[dataTask.taskIdentifier]?.response = httpResponse
        lock.unlock()
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        guard var state = taskStates[dataTask.taskIdentifier], !state.finished else {
            lock.unlock()
            return
        }
        state.data.append(data)
        let overLimit = state.data.count > maxBodyBytes
        taskStates[dataTask.taskIdentifier] = state
        lock.unlock()

        if overLimit {
            dataTask.cancel()
            finish(taskID: dataTask.taskIdentifier, result: .failure(SafeFetchError.responseTooLarge))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            if (error as? URLError)?.code != .cancelled {
                finish(taskID: task.taskIdentifier, result: .failure(error))
            }
            return
        }

        lock.lock()
        guard let state = taskStates[task.taskIdentifier], !state.finished else {
            lock.unlock()
            return
        }
        guard let httpResponse = state.response else {
            lock.unlock()
            finish(taskID: task.taskIdentifier, result: .failure(SafeFetchError.invalidResponse))
            return
        }
        let data = state.data
        lock.unlock()

        if data.count > maxBodyBytes {
            finish(taskID: task.taskIdentifier, result: .failure(SafeFetchError.responseTooLarge))
        } else {
            finish(taskID: task.taskIdentifier, result: .success((data, httpResponse)))
        }
    }

    private func finish(taskID: Int, result: Result<(Data, HTTPURLResponse), Error>) {
        lock.lock()
        guard var state = taskStates.removeValue(forKey: taskID), !state.finished else {
            lock.unlock()
            return
        }
        state.finished = true
        lock.unlock()
        state.continuation.resume(with: result)
    }
}

// MARK: - Limits

enum SafeFetchLimits {
    static let maxBodyBytes = 5 * 1024 * 1024
    static let maxRedirects = 3
}

// MARK: - Service

@MainActor
final class SafeFetchService {
    #if DEBUG
    static var shared: SafeFetchService {
        get { _sharedOverride ?? _defaultShared }
        set { _sharedOverride = newValue }
    }

    private static let _defaultShared = SafeFetchService()
    private static var _sharedOverride: SafeFetchService?
    #else
    static let shared = SafeFetchService()
    #endif

    private let resolver: any HostResolving
    private let trustedHostPolicy: any TrustedHostPolicy
    private let session: URLSession
    private let sessionDelegate: SafeFetchSessionDelegate

    init(
        resolver: any HostResolving = SystemHostResolver(),
        protocolClasses: [AnyClass]? = nil,
        trustedHostPolicy: any TrustedHostPolicy = DefaultTrustedHostPolicy()
    ) {
        self.resolver = resolver
        self.trustedHostPolicy = trustedHostPolicy

        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        if let protocolClasses {
            config.protocolClasses = protocolClasses
        } else {
            config.protocolClasses = [PinnedIPURLProtocol.self]
        }

        let delegate = SafeFetchSessionDelegate(maxBodyBytes: SafeFetchLimits.maxBodyBytes)
        self.sessionDelegate = delegate
        self.session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }

    func fetch(
        url: URL,
        requireTrustedHost: Bool = false,
        headers: [String: String] = [:]
    ) async throws -> Data {
        var currentURL = try normalize(url: url)
        var redirectCount = 0

        while true {
            try validateHostPolicy(for: currentURL, requireTrustedHost: requireTrustedHost)
            try validateScheme(for: currentURL)

            let (data, httpResponse) = try await performPinnedRequest(url: currentURL, headers: headers)

            if isRedirect(statusCode: httpResponse.statusCode) {
                guard redirectCount < SafeFetchLimits.maxRedirects else {
                    throw SafeFetchError.tooManyRedirects
                }
                guard let nextURL = try redirectURL(from: httpResponse, relativeTo: currentURL) else {
                    throw SafeFetchError.invalidRedirect
                }
                currentURL = try normalize(url: nextURL)
                redirectCount += 1
                continue
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                throw SafeFetchError.httpError(statusCode: httpResponse.statusCode)
            }

            return data
        }
    }

    // MARK: - Pinned Request

    private func performPinnedRequest(
        url: URL,
        headers: [String: String] = [:]
    ) async throws -> (Data, HTTPURLResponse) {
        let endpoint = try resolvePinnedEndpoint(for: url)

        let mutableRequest = NSMutableURLRequest(url: try pinnedURL(from: url, pinnedIP: endpoint.pinnedIP))
        mutableRequest.httpShouldHandleCookies = false
        mutableRequest.setValue(endpoint.originalHost, forHTTPHeaderField: "Host")
        for (name, value) in headers {
            mutableRequest.setValue(value, forHTTPHeaderField: name)
        }

        URLProtocol.setProperty(endpoint.pinnedIP, forKey: PinnedRequestKeys.pinnedIP, in: mutableRequest)
        URLProtocol.setProperty(endpoint.originalHost, forKey: PinnedRequestKeys.originalHost, in: mutableRequest)

        let request = mutableRequest as URLRequest

        return try await withCheckedThrowingContinuation { continuation in
            let task = session.dataTask(with: request)
            sessionDelegate.register(task: task, continuation: continuation)
            task.resume()
        }
    }

    private func resolvePinnedEndpoint(for url: URL) throws -> (pinnedIP: String, originalHost: String) {
        guard let host = url.host, !host.isEmpty else {
            throw SafeFetchError.invalidURL
        }

        let allowsPrivateIPs = trustedHostPolicy.allowsPrivateIPs(for: host)

        if let literalIP = literalIPAddress(from: host) {
            if IPAddressBlocklist.isBlocked(literalIP), !allowsPrivateIPs {
                throw SafeFetchError.blockedIPAddress(literalIP)
            }
            return (literalIP, host)
        }

        let resolved = try resolver.resolve(hostname: host)
        guard let pinnedIP = resolved.first else {
            throw SafeFetchError.dnsResolutionFailed(host)
        }

        for ip in resolved {
            if IPAddressBlocklist.isBlocked(ip), !allowsPrivateIPs {
                throw SafeFetchError.blockedIPAddress(ip)
            }
        }

        return (pinnedIP, host)
    }

    private func pinnedURL(from url: URL, pinnedIP: String) throws -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw SafeFetchError.invalidURL
        }
        components.host = pinnedIP
        guard let pinned = components.url else {
            throw SafeFetchError.invalidURL
        }
        return pinned
    }

    // MARK: - Validation

    private func validateHostPolicy(for url: URL, requireTrustedHost: Bool) throws {
        guard requireTrustedHost else { return }
        guard let host = url.host, !host.isEmpty else {
            throw SafeFetchError.invalidURL
        }
        guard trustedHostPolicy.isAllowedForGitFetch(host) else {
            throw SafeFetchError.hostNotTrusted(host)
        }
    }

    private func validateScheme(for url: URL) throws {
        guard let scheme = url.scheme?.lowercased() else {
            throw SafeFetchError.invalidURL
        }
        if scheme == "https" { return }
        if scheme == "http" {
            guard let host = url.host, trustedHostPolicy.allowsHTTP(for: host) else {
                throw SafeFetchError.httpNotAllowed
            }
            return
        }
        throw SafeFetchError.httpNotAllowed
    }

    private func literalIPAddress(from host: String) -> String? {
        var v4 = in_addr()
        if host.withCString({ inet_pton(AF_INET, $0, &v4) }) == 1 {
            return host
        }
        var v6 = in6_addr()
        if host.withCString({ inet_pton(AF_INET6, $0, &v6) }) == 1 {
            return host
        }
        return nil
    }

    // MARK: - Redirect Helpers

    private func isRedirect(statusCode: Int) -> Bool {
        switch statusCode {
        case 300...399 where statusCode != 304:
            true
        default:
            false
        }
    }

    private func redirectURL(from response: HTTPURLResponse, relativeTo baseURL: URL) throws -> URL? {
        guard let location = response.value(forHTTPHeaderField: "Location")?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !location.isEmpty
        else {
            return nil
        }

        if let absolute = URL(string: location), absolute.scheme != nil {
            return absolute
        }
        return URL(string: location, relativeTo: baseURL)?.absoluteURL
    }

    private func normalize(url: URL) throws -> URL {
        guard url.host != nil || url.path.isEmpty == false else {
            throw SafeFetchError.invalidURL
        }
        return url
    }
}
