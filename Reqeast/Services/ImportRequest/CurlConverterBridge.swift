//
//  CurlConverterBridge.swift
//  Reqeast
//

import Foundation
import JavaScriptCore

enum CurlConverterBridge {

    private static let bundleSource: String? = {
        for bundle in Bundle.allBundles + [Bundle.main] {
            if let url = bundle.url(forResource: "curlconverter.bundle", withExtension: "js"),
               let source = try? String(contentsOf: url, encoding: .utf8) {
                return source
            }
        }
        return nil
    }()

    private static let nodeGlobals = """
        var process = {
            env: {}, platform: "browser", versions: {}, argv: [],
            cwd: function() { return "/"; },
            stdout: { write: function() {} }, stderr: { write: function() {} }
        };
        var __dirname = "/";
        var __filename = "/bundle.js";
        var global = globalThis;
        if (typeof Buffer === "undefined") {
            var Buffer = { isBuffer: function() { return false; } };
        }
        """

    static func parse(_ curlCommand: String) throws -> CurlConverterJSON {
        guard let source = bundleSource else {
            throw ImportError.curlParseError("Failed to load curlconverter bundle")
        }

        guard let ctx = JSContext() else {
            throw ImportError.curlParseError("Failed to create JavaScript context")
        }

        ctx.evaluateScript(nodeGlobals)
        ctx.evaluateScript(source)

        if let exception = ctx.exception {
            throw ImportError.curlParseError(exception.toString() ?? "Bundle initialization failed")
        }

        let escaped = curlCommand
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")

        let script = "CurlConverter.toJsonString(`\(escaped)`)"
        let result = ctx.evaluateScript(script)

        if let exception = ctx.exception {
            let message = exception.toString() ?? "Unknown JavaScript error"
            throw ImportError.curlParseError(message)
        }

        guard let jsonString = result?.toString(), jsonString != "undefined" else {
            throw ImportError.curlParseError("curlconverter returned no output")
        }

        guard let jsonData = jsonString.data(using: .utf8) else {
            throw ImportError.curlParseError("Invalid JSON encoding")
        }

        return try JSONDecoder().decode(CurlConverterJSON.self, from: jsonData)
    }
}
