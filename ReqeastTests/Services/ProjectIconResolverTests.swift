//
//  ProjectIconResolverTests.swift
//  ReqeastTests
//

import Testing
@testable import Reqeast

@Suite("ProjectIconResolver")
struct ProjectIconResolverTests {

    @Test func buildCandidateURLsPrefersWebsiteFaviconsBeforeSpecLogo() {
        let candidates = ProjectIconResolver.buildCandidateURLs(
            specIconURL: "https://docs.example.com/logo.svg",
            discoveredFavicons: [
                "https://docs.example.com/img/favicon.ico",
                "https://docs.example.com/favicon.ico",
            ]
        )

        #expect(candidates == [
            "https://docs.example.com/img/favicon.ico",
            "https://docs.example.com/favicon.ico",
            "https://docs.example.com/logo.svg",
        ])
    }

    @Test func buildCandidateURLsSkipsInvalidValues() {
        let candidates = ProjectIconResolver.buildCandidateURLs(
            specIconURL: "#",
            discoveredFavicons: []
        )

        #expect(candidates.isEmpty)
    }

    @Test func faviconURLUsesOriginPath() {
        #expect(
            ProjectIconResolver.faviconURL(
                for: "https://api.example.com/v1/openapi.yaml"
            ) == "https://api.example.com/favicon.ico"
        )
    }

    @Test func faviconCandidatesFromHTMLParsesDocusaurusIcon() {
        let html = """
        <head>
        <link data-rh="true" rel="icon" href="/img/favicon.ico">
        <link rel="apple-touch-icon" href="/img/apple-touch-icon.png">
        </head>
        """

        let candidates = ProjectIconResolver.faviconCandidatesFromHTML(
            html,
            baseURL: "https://docs.connect-api.1global.com/"
        )

        #expect(candidates == ["https://docs.connect-api.1global.com/img/favicon.ico"])
    }

    @Test func faviconCandidatesFromHTMLPrefersSmallerDeclaredSizes() {
        let html = """
        <link rel="apple-touch-icon" sizes="180x180" href="/apple.png">
        <link rel="icon" type="image/png" sizes="32x32" href="/favicon-32.png">
        <link rel="icon" type="image/png" sizes="16x16" href="/favicon-16.png">
        """

        let candidates = ProjectIconResolver.faviconCandidatesFromHTML(
            html,
            baseURL: "https://docs.example.com/"
        )

        #expect(candidates == [
            "https://docs.example.com/favicon-16.png",
            "https://docs.example.com/favicon-32.png",
        ])
    }
}