//
//  CookieStore.swift
//  Reqeast
//

import Foundation

struct StoredCookie: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var value: String
    var domain: String
    var path: String
    var expires: String?
    var httpOnly: Bool
    var secure: Bool
    var sameSite: String?

    init(
        id: UUID = UUID(),
        name: String = "",
        value: String = "",
        domain: String = "",
        path: String = "/",
        expires: String? = nil,
        httpOnly: Bool = false,
        secure: Bool = false,
        sameSite: String? = nil
    ) {
        self.id = id
        self.name = name
        self.value = value
        self.domain = domain
        self.path = path
        self.expires = expires
        self.httpOnly = httpOnly
        self.secure = secure
        self.sameSite = sameSite
    }
}

@MainActor
@Observable
class CookieStore {
    static let shared = CookieStore()

    var cookies: [StoredCookie] = []

    private init() {
        load()
    }

    func addCookiesFromResponse(_ responseCookies: [StoredCookie]) {
        for rc in responseCookies {
            if let idx = cookies.firstIndex(where: { $0.name == rc.name && $0.domain == rc.domain }) {
                cookies[idx].value = rc.value
                cookies[idx].path = rc.path
                cookies[idx].expires = rc.expires
                cookies[idx].httpOnly = rc.httpOnly
                cookies[idx].secure = rc.secure
                cookies[idx].sameSite = rc.sameSite
            } else {
                cookies.append(rc)
            }
        }
        save()
    }

    func addCookiesFromImport(_ cookies: [String: String], url: String) {
        guard !cookies.isEmpty else { return }
        let domain = URL(string: url).flatMap { $0.host() } ?? ""
        let imported = cookies.map { name, value in
            StoredCookie(name: name, value: value, domain: domain)
        }
        addCookiesFromResponse(imported)
    }

    func cookiesForUrl(_ urlString: String) -> [KeyValuePair] {
        guard let url = URL(string: urlString),
              let host = url.host() else { return [] }
        return cookies
            .filter { host.hasSuffix($0.domain) }
            .map { KeyValuePair(key: $0.name, value: $0.value, enabled: true) }
    }

    func deleteCookie(_ cookie: StoredCookie) {
        cookies.removeAll { $0.id == cookie.id }
        save()
    }

    func clearAll() {
        cookies.removeAll()
        save()
    }

    private func save() {
        SessionPersistenceService.shared.saveCookies(cookies)
    }

    private func load() {
        cookies = SessionPersistenceService.shared.loadCookies()
    }
}
