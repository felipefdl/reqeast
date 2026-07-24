//
//  EnvironmentVariableService.swift
//  Reqeast
//

import Foundation

enum EnvironmentVariableService {
    private static let pattern = try! NSRegularExpression(pattern: #"\{\{([^}]+)\}\}"#)

    static func substitute(
        _ input: String,
        environment: ApiEnvironment?,
        secretLoader: ((String) -> String?)? = nil
    ) -> String {
        guard let environment else { return input }

        let nsInput = input as NSString
        let range = NSRange(location: 0, length: nsInput.length)
        var result = input

        let matches = pattern.matches(in: input, range: range)

        // Process in reverse order to preserve indices
        for match in matches.reversed() {
            guard let keyRange = Range(match.range(at: 1), in: input) else { continue }
            let key = String(input[keyRange])

            if let variable = environment.variables.first(where: { $0.key == key && $0.enabled }) {
                let value: String
                if variable.isSecret {
                    value = secretLoader?(key) ?? variable.value
                } else {
                    value = variable.value
                }

                if let fullRange = Range(match.range, in: result) {
                    result.replaceSubrange(fullRange, with: value)
                }
            }
        }

        return result
    }
}
