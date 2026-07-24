//
//  CodeSnippetService.swift
//  Reqeast
//

import Foundation

enum CodeSnippetTarget: String, CaseIterable, Codable, Identifiable {
    case curl
    case httpRaw
    case pythonRequests
    case javaScriptFetch
    case nodeAxios
    case swiftUrlSession
    case goNative
    case rustReqwest
    case javaOkHttp
    case cSharpHttpClient

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .curl:             return "cURL"
        case .httpRaw:          return "HTTP"
        case .pythonRequests:   return "Python - Requests"
        case .javaScriptFetch:  return "JavaScript - Fetch"
        case .nodeAxios:        return "Node.js - Axios"
        case .swiftUrlSession:  return "Swift - URLSession"
        case .goNative:         return "Go - net/http"
        case .rustReqwest:      return "Rust - reqwest"
        case .javaOkHttp:       return "Java - OkHttp"
        case .cSharpHttpClient: return "C# - HttpClient"
        }
    }

    var highlightLanguage: String {
        switch self {
        case .curl:             return "bash"
        case .httpRaw:          return "http"
        case .pythonRequests:   return "python"
        case .javaScriptFetch:  return "javascript"
        case .nodeAxios:        return "javascript"
        case .swiftUrlSession:  return "swift"
        case .goNative:         return "go"
        case .rustReqwest:      return "rust"
        case .javaOkHttp:       return "java"
        case .cSharpHttpClient: return "csharp"
        }
    }
}

enum CodeSnippetService {

    static func canGenerate(for request: Request) -> Bool {
        request.type == .http && request.httpData != nil
    }

    static func generate(target: CodeSnippetTarget, request: ResolvedHttpRequest) -> String {
        switch target {
        case .curl:             return CurlGenerator.generate(request)
        case .httpRaw:          return HttpRawGenerator.generate(request)
        case .pythonRequests:   return PythonRequestsGenerator.generate(request)
        case .javaScriptFetch:  return JavaScriptFetchGenerator.generate(request)
        case .nodeAxios:        return NodeAxiosGenerator.generate(request)
        case .swiftUrlSession:  return SwiftUrlSessionGenerator.generate(request)
        case .goNative:         return GoNativeGenerator.generate(request)
        case .rustReqwest:      return RustReqwestGenerator.generate(request)
        case .javaOkHttp:       return JavaOkHttpGenerator.generate(request)
        case .cSharpHttpClient: return CSharpHttpClientGenerator.generate(request)
        }
    }
}
