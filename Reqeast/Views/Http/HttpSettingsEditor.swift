//
//  HttpSettingsEditor.swift
//  Reqeast
//

import SwiftUI

struct HttpSettingsEditor: View {
    @Binding var httpVersion: String
    @Binding var sslVerify: Bool
    @Binding var followRedirects: Bool
    @Binding var followOriginalMethod: Bool
    @Binding var followAuthHeader: Bool
    @Binding var removeRefererOnRedirect: Bool
    @Binding var encodeUrl: Bool
    @Binding var maxRedirects: Int
    @Binding var timeoutSeconds: Int
    @Binding var disableCookieJar: Bool

    var body: some View {
        Form {
            httpVersionSection
            timeoutSection
            sslSection
            cookieSection
            redirectSection
            encodingSection
        }
        .formStyle(.grouped)
    }

    private var httpVersionSection: some View {
        Section("HTTP Version") {
            Picker("HTTP Version", selection: $httpVersion) {
                Text("Auto").tag("auto")
                Text("HTTP/1.x").tag("http1")
                Text("HTTP/2").tag("http2")
            }
            .tint(.primary)
        }
    }

    private var sslSection: some View {
        Section("SSL") {
            Toggle(isOn: $sslVerify) {
                VStack(alignment: .leading) {
                    Text("Enable SSL certificate verification")
                    Text("Verify SSL certificates when sending requests")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var redirectSection: some View {
        Section("Redirects") {
            Toggle(isOn: $followRedirects) {
                VStack(alignment: .leading) {
                    Text("Automatically follow redirects")
                    Text("Follow HTTP 3xx redirect responses")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if followRedirects {
                Stepper(value: $maxRedirects, in: 1...50) {
                    HStack {
                        Text("Maximum redirects")
                        Spacer()
                        Text("\(maxRedirects)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }

                Toggle(isOn: $followOriginalMethod) {
                    VStack(alignment: .leading) {
                        Text("Follow original HTTP method")
                        Text("Use the original request method on 301/302/303 redirects instead of GET")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Toggle(isOn: $followAuthHeader) {
                    VStack(alignment: .leading) {
                        Text("Follow Authorization header")
                        Text("Keep Authorization header when redirecting to a different host")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Toggle(isOn: $removeRefererOnRedirect) {
                    VStack(alignment: .leading) {
                        Text("Remove Referer header on redirect")
                        Text("Strip the Referer header when following redirects")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var timeoutSection: some View {
        Section("Timeout") {
            Stepper(value: $timeoutSeconds, in: 1...300) {
                HStack {
                    Text("Request timeout")
                    Spacer()
                    Text("\(timeoutSeconds)s")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
    }

    private var cookieSection: some View {
        Section("Cookies") {
            Toggle(isOn: $disableCookieJar) {
                VStack(alignment: .leading) {
                    Text("Disable cookie jar")
                    Text("Do not store or send cookies for this request")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var encodingSection: some View {
        Section("Encoding") {
            Toggle(isOn: $encodeUrl) {
                VStack(alignment: .leading) {
                    Text("Encode URL automatically")
                    Text("Percent-encode special characters in the URL")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
