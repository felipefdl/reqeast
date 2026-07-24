//
//  HttpEnumsTests.swift
//  ReqeastTests
//

import Foundation
import Testing
@testable import Reqeast

@Suite("HttpEnums")
struct HttpEnumsTests {

    // MARK: - HttpMethod.rawLabel

    @Test func rawLabelGet() {
        #expect(HttpMethod.get.rawLabel == "GET")
    }

    @Test func rawLabelPost() {
        #expect(HttpMethod.post.rawLabel == "POST")
    }

    @Test func rawLabelPut() {
        #expect(HttpMethod.put.rawLabel == "PUT")
    }

    @Test func rawLabelPatch() {
        #expect(HttpMethod.patch.rawLabel == "PATCH")
    }

    @Test func rawLabelDelete() {
        #expect(HttpMethod.delete.rawLabel == "DELETE")
    }

    @Test func rawLabelHead() {
        #expect(HttpMethod.head.rawLabel == "HEAD")
    }

    @Test func rawLabelOptions() {
        #expect(HttpMethod.options.rawLabel == "OPTIONS")
    }

    // MARK: - HttpMethod.shortLabel

    @Test func shortLabelDeleteIsDel() {
        #expect(HttpMethod.delete.shortLabel == "DEL")
    }

    @Test func shortLabelOptionsIsOpts() {
        #expect(HttpMethod.options.shortLabel == "OPTS")
    }

    // MARK: - HttpMethod.conventionallyHasBody

    @Test func conventionallyHasBodyFalseForGetHeadOptions() {
        #expect(HttpMethod.get.conventionallyHasBody == false)
        #expect(HttpMethod.head.conventionallyHasBody == false)
        #expect(HttpMethod.options.conventionallyHasBody == false)
    }

    @Test func conventionallyHasBodyTrueForOthers() {
        #expect(HttpMethod.post.conventionallyHasBody == true)
        #expect(HttpMethod.put.conventionallyHasBody == true)
        #expect(HttpMethod.patch.conventionallyHasBody == true)
        #expect(HttpMethod.delete.conventionallyHasBody == true)
    }

    // MARK: - HttpMethod.color

    @Test func colorMapping() {
        #expect(HttpMethod.get.color == .green)
        #expect(HttpMethod.post.color == .orange)
        #expect(HttpMethod.put.color == .blue)
        #expect(HttpMethod.patch.color == .purple)
        #expect(HttpMethod.delete.color == .red)
        #expect(HttpMethod.head.color == .gray)
        #expect(HttpMethod.options.color == .gray)
    }

    // MARK: - HttpMethod Codable

    @Test func httpMethodCodableRoundTrip() throws {
        for method in HttpMethod.allCases {
            let data = try JSONEncoder().encode(method)
            let decoded = try JSONDecoder().decode(HttpMethod.self, from: data)
            #expect(decoded == method)
        }
    }

    // MARK: - HttpBodyType

    @Test func bodyTypeLocalizedNamesAreNonEmpty() {
        for bodyType in HttpBodyType.allCases {
            #expect(!bodyType.localizedName.isEmpty)
        }
    }

    @Test func bodyTypeAllCasesCount() {
        #expect(HttpBodyType.allCases.count == 6)
    }

    // MARK: - HttpRawContentType

    @Test func rawContentTypeLocalizedNamesAreNonEmpty() {
        for ct in HttpRawContentType.allCases {
            #expect(!ct.localizedName.isEmpty)
        }
    }

    @Test func rawContentTypeMimeTypes() {
        #expect(HttpRawContentType.text.mimeType == "text/plain")
        #expect(HttpRawContentType.javascript.mimeType == "application/javascript")
        #expect(HttpRawContentType.json.mimeType == "application/json")
        #expect(HttpRawContentType.html.mimeType == "text/html")
        #expect(HttpRawContentType.xml.mimeType == "application/xml")
    }

    // MARK: - HttpAuthType

    @Test func authTypeLocalizedNamesAreNonEmpty() {
        for authType in HttpAuthType.allCases {
            #expect(!authType.localizedName.isEmpty)
        }
        #expect(HttpAuthType.allCases.count == 12)
    }

    @Test func oauth2GrantTypeRawValues() {
        #expect(OAuth2GrantType.clientCredentials.rawValue == "clientCredentials")
        #expect(OAuth2GrantType.authorizationCode.rawValue == "authorizationCode")
        #expect(OAuth2GrantType.implicit.rawValue == "implicit")
        #expect(OAuth2GrantType.password.rawValue == "password")
    }

    @Test func authTypeIsComingSoon() {
        #expect(HttpAuthType.digestAuth.isComingSoon == true)
        #expect(HttpAuthType.oauth1.isComingSoon == true)
        #expect(HttpAuthType.oauth2.isComingSoon == false)
        #expect(HttpAuthType.ntlm.isComingSoon == true)
        #expect(HttpAuthType.bearer.isComingSoon == false)
        #expect(HttpAuthType.basic.isComingSoon == false)
        #expect(HttpAuthType.none.isComingSoon == false)
    }
}
