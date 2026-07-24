//
//  SendHttpRequestIntent.swift
//  Reqeast
//

import AppIntents
import Foundation

struct SendHttpRequestIntent: AppIntent {
    static var title: LocalizedStringResource = "Send HTTP Request"
    static var description = IntentDescription("Execute an HTTP request from Reqeast and return the response.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Project")
    var project: ProjectEntity

    @Parameter(title: "Request")
    var request: RequestEntity?

    @Parameter(title: "Environment")
    var environment: EnvironmentEntity?

    @Parameter(title: "Variable Overrides", description: "Template variable values (key=value, one per line)")
    var variableOverrides: String?

    @Parameter(title: "Timeout (seconds)", default: 30, inclusiveRange: (1, 300))
    var timeout: Int

    static var parameterSummary: some ParameterSummary {
        Summary("In \(\.$project) send \(\.$request)") {
            \.$environment
            \.$variableOverrides
            \.$timeout
        }
    }

    func perform() async throws -> some ReturnsValue<String> {
        do {
            let resolved = try await IntentResolutionHelper.resolveRequest(
                projectId: project.id,
                selectedEntity: request,
                typeFilter: .http,
                disambiguate: {
                    try await $request.requestDisambiguation(among: $0, dialog: IntentDialog("Choose an HTTP request"))
                }
            )
            let env = try await IntentResolutionHelper.resolveEnvironment(
                projectId: project.id,
                selectedEntity: environment,
                disambiguate: {
                    try await $environment.requestDisambiguation(among: $0, dialog: IntentDialog("Choose an environment"))
                }
            )
            let finalEnv = try await IntentResolutionHelper.resolveVariableOverrides(
                for: resolved,
                environment: env,
                overridesInput: variableOverrides,
                requestOverridesInput: { unresolved in
                    let varList = unresolved.map { "{{\($0)}}" }.joined(separator: ", ")
                    return try await $variableOverrides.requestValue(
                        IntentDialog("Enter values for: \(varList)\nFormat: key=value, one per line")
                    )
                }
            )

            let response = try await IntentExecutionService.executeHttp(
                request: resolved, environment: finalEnv, timeout: timeout
            )
            return .result(value: response)
        } catch let error as IntentExecutionError {
            throw error
        } catch let error as ReqeastError {
            throw IntentExecutionError.executionFailed(error.intentMessage)
        } catch {
            throw IntentExecutionError.executionFailed(error.localizedDescription)
        }
    }
}
