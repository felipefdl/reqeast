//
//  HttpExecutionState.swift
//  Reqeast
//

import Foundation

@MainActor
@Observable
class HttpExecutionState {
    var isLoading = false
    var response: HttpResponseData?
    var error: RequestError?

    private let httpService = HttpService.shared
    private var currentTask: Task<Void, Never>?

    func send(
        request: Request,
        environment: ApiEnvironment?,
        sessionStore: HttpSessionStore,
        onAutoRename: (@Sendable (String) -> Void)? = nil
    ) {
        guard let httpData = request.httpData else { return }
        cancel()
        isLoading = true
        error = nil

        currentTask = Task {
            await performSend(
                request: request,
                httpData: httpData,
                environment: environment,
                sessionStore: sessionStore,
                onAutoRename: onAutoRename
            )
        }
    }

    func cancel() {
        currentTask?.cancel()
        currentTask = nil
        isLoading = false
    }

    func clear() {
        response = nil
        error = nil
    }

    // MARK: - Private

    private func performSend(
        request: Request,
        httpData: HttpRequestData,
        environment: ApiEnvironment?,
        sessionStore: HttpSessionStore,
        onAutoRename: (@Sendable (String) -> Void)?
    ) async {
        let strictMode = UserDefaults.standard.object(forKey: "strictHttpMode") == nil
            ? true
            : UserDefaults.standard.bool(forKey: "strictHttpMode")
        let stripBody = strictMode && !httpData.method.conventionallyHasBody

        let sub = { (input: String) -> String in
            EnvironmentVariableService.substitute(input, environment: environment)
        }

        let result = await httpService.send(
            url: UrlNormalizer.normalize(sub(httpData.url)),
            method: httpData.method,
            headers: httpData.headers.map {
                KeyValueEntry(id: $0.id, key: sub($0.key), value: sub($0.value), enabled: $0.enabled)
            },
            params: httpData.params.map {
                KeyValueEntry(id: $0.id, key: sub($0.key), value: sub($0.value), enabled: $0.enabled)
            },
            bodyType: stripBody ? .none : httpData.bodyType,
            bodyContent: sub(httpData.bodyContent),
            bodyFormData: httpData.bodyFormData.map {
                KeyValueEntry(id: $0.id, key: sub($0.key), value: sub($0.value), enabled: $0.enabled)
            },
            bodyFormDataEntries: httpData.bodyFormDataEntries.map {
                var entry = $0
                entry.key = sub(entry.key)
                if entry.fieldType == .text { entry.value = sub(entry.value) }
                return entry
            },
            formDataFiles: sessionStore.formDataFiles,
            binaryData: sessionStore.binaryBodyData,
            authType: httpData.authType,
            authToken: sub(httpData.authToken),
            authUsername: sub(httpData.authUsername),
            authPassword: sub(httpData.authPassword),
            authApiKeyName: sub(httpData.authApiKeyName),
            authApiKeyValue: sub(httpData.authApiKeyValue),
            authApiKeyLocation: httpData.authApiKeyLocation,
            authData: httpData.authData,
            followRedirects: httpData.followRedirects,
            timeoutSeconds: httpData.timeoutSeconds,
            sslVerify: httpData.sslVerify,
            httpVersion: httpData.httpVersion,
            maxRedirects: httpData.maxRedirects,
            encodeUrl: httpData.encodeUrl,
            followOriginalMethod: httpData.followOriginalMethod,
            followAuthHeader: httpData.followAuthHeader,
            removeRefererOnRedirect: httpData.removeRefererOnRedirect,
            rawContentType: httpData.rawContentType?.mimeType ?? "text/plain"
        )

        guard !Task.isCancelled else { return }

        isLoading = false
        if let index = ProjectStore.shared.requests.firstIndex(where: { $0.id == request.id }) {
            ProjectStore.shared.requests[index].touch()
            ProjectStore.shared.saveAll()
            CloudSyncService.shared.queueSave(ProjectStore.shared.requests[index])
        } else {
            ProjectStore.shared.saveAll()
        }

        switch result {
        case .success(let httpResponse):
            response = httpResponse
            if !httpResponse.cookies.isEmpty {
                CookieStore.shared.addCookiesFromResponse(httpResponse.cookies)
            }
            let entry = RequestHistoryEntry(
                requestId: request.id,
                method: httpData.method.rawLabel,
                url: httpData.url,
                statusCode: httpResponse.statusCode,
                elapsedMs: httpResponse.elapsedMs,
                bodySize: httpResponse.bodySize,
                httpData: httpData
            )
            sessionStore.history.append(entry)
            SessionPersistenceService.shared.saveResponseBody(httpResponse.body, for: request.id)
            SessionPersistenceService.shared.saveHistory(sessionStore.history, for: request.id)

            #if os(macOS)
            let projectName = ProjectStore.shared.projects.first { $0.id == request.projectId }?.name ?? ""
            MCPExportService.shared.recordExecution(
                requestId: request.id,
                requestName: request.name,
                projectName: projectName,
                method: httpData.method.rawLabel,
                url: httpData.url,
                statusCode: httpResponse.statusCode,
                elapsedMs: httpResponse.elapsedMs
            )
            MCPExportService.shared.exportResponseMeta(requestId: request.id, response: httpResponse)
            #endif

            if !request.isRenamed, let onAutoRename {
                let method = httpData.method.rawLabel
                let url = httpData.url
                let statusCode = httpResponse.statusCode
                Task {
                    if let name = await RequestNamingService.generateName(
                        method: method, url: url, statusCode: statusCode
                    ) {
                        onAutoRename(name)
                    }
                }
            }
        case .failure(let err):
            response = nil
            error = RequestError.from(err)

            #if os(macOS)
            let projectName = ProjectStore.shared.projects.first { $0.id == request.projectId }?.name ?? ""
            MCPExportService.shared.recordExecution(
                requestId: request.id,
                requestName: request.name,
                projectName: projectName,
                method: httpData.method.rawLabel,
                url: httpData.url,
                statusCode: 0,
                elapsedMs: 0
            )
            #endif
        }
    }
}
