//
//  JsonBeautifier.swift
//  Reqeast
//

import Foundation
import JavaScriptCore

@MainActor
enum JsonBeautifier {
    private static let jsContext: JSContext? = {
        let ctx = JSContext()
        ctx?.evaluateScript("""
            function prettyJSON(input, spaces) {
                return JSON.stringify(JSON.parse(input), null, spaces);
            }
            """)
        return ctx
    }()

    static func prettify(_ input: String, spaces: Int? = nil) -> String? {
        let indent = spaces ?? {
            let stored = UserDefaults.standard.integer(forKey: "jsonIndentSpaces")
            return stored > 0 ? stored : 2
        }()
        guard let ctx = jsContext,
              let fn = ctx.objectForKeyedSubscript("prettyJSON"),
              let result = fn.call(withArguments: [input, indent]),
              !result.isUndefined, !result.isNull else { return nil }
        return result.toString()
    }

    static func validate(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let data = trimmed.data(using: .utf8) else { return nil }
        do {
            _ = try JSONSerialization.jsonObject(with: data)
            return nil
        } catch let error as NSError {
            let debug = error.userInfo[NSDebugDescriptionErrorKey] as? String
            return debug ?? error.localizedDescription
        }
    }
}
