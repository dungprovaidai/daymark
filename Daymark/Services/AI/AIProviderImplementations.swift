import Foundation

private func redactedError(_ error: Error, apiKey: String?) -> AIError {
    let message = AISecretRedactor.redact(error.localizedDescription, apiKey: apiKey)
    switch error {
    case let ai as AIError: return ai
    default:
        if (error as NSError).domain == NSURLErrorDomain { return .networkError(message) }
        return .networkError(message)
    }
}

private func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
    let start = Date()
    do {
        let (data, response) = try await URLSession.shared.data(for: request)
        _ = start
        return (data, response)
    } catch {
        throw error
    }
}

struct OpenAICompatibleProvider: AIProviderProtocol {
    var protocolType: AIProtocolType { .openAICompatible }

    func testConnection(configuration: AIProviderConfiguration, apiKey: String?, modelID: String) async throws -> AIConnectionTestResult {
        try await AIConnectionTester.testChat(
            provider: self,
            configuration: configuration,
            apiKey: apiKey,
            modelID: modelID
        )
    }

    func fetchModels(configuration: AIProviderConfiguration, apiKey: String?) async throws -> [AIModelInfo] {
        let baseURL = try AIEndpointResolver.validateBaseURL(configuration.baseURLString)
        var url = AIEndpointResolver.openAIURL(
            baseURL: baseURL,
            mode: configuration.endpointMode,
            customPath: configuration.customChatPath,
            kind: .models
        )
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        AIAuthenticationHandler.apply(
            url: &url, request: &request, mode: configuration.authMode, apiKey: apiKey,
            customHeaders: configuration.customHeaders,
            organizationID: configuration.organizationID, projectID: configuration.projectID,
            protocolType: .openAICompatible
        )
        request.url = url
        request.timeoutInterval = TimeInterval(max(1, configuration.timeoutSeconds))
        do {
            let (data, response) = try await send(request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                let body = String(data: data, encoding: .utf8) ?? ""
                throw AIError.httpError(http.statusCode, AISecretRedactor.redact(body, apiKey: apiKey))
            }
            return try AIModelDiscoveryParser.openAI(from: data)
        } catch {
            throw redactedError(error, apiKey: apiKey)
        }
    }

    func chat(
        configuration: AIProviderConfiguration,
        apiKey: String?,
        modelID: String,
        messages: [AIMessage],
        options: AIChatRequestOptions
    ) async throws -> AIChatResponse {
        let builder = AIRequestBuilder(configuration: configuration, apiKey: apiKey, modelID: modelID, messages: messages, options: options)
        do {
            let request = try builder.build()
            let (data, response) = try await send(request)
            return try AIResponseNormalizer.normalize(
                data: data,
                response: response,
                protocolType: .openAICompatible,
                modelID: modelID,
                providerDisplayName: configuration.displayName
            )
        } catch {
            throw redactedError(error, apiKey: apiKey)
        }
    }
}

struct GeminiNativeProvider: AIProviderProtocol {
    var protocolType: AIProtocolType { .geminiNative }

    func testConnection(configuration: AIProviderConfiguration, apiKey: String?, modelID: String) async throws -> AIConnectionTestResult {
        try await AIConnectionTester.testChat(
            provider: self,
            configuration: configuration,
            apiKey: apiKey,
            modelID: modelID
        )
    }

    func fetchModels(configuration: AIProviderConfiguration, apiKey: String?) async throws -> [AIModelInfo] {
        let baseURL = try AIEndpointResolver.validateBaseURL(configuration.baseURLString)
        var url = AIEndpointResolver.geminiURL(baseURL: baseURL, modelID: "", streaming: false, kind: .listModels)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        AIAuthenticationHandler.apply(
            url: &url, request: &request, mode: configuration.authMode, apiKey: apiKey,
            customHeaders: configuration.customHeaders,
            protocolType: .geminiNative
        )
        request.url = url
        request.timeoutInterval = TimeInterval(max(1, configuration.timeoutSeconds))
        do {
            let (data, response) = try await send(request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                let body = String(data: data, encoding: .utf8) ?? ""
                throw AIError.httpError(http.statusCode, AISecretRedactor.redact(body, apiKey: apiKey))
            }
            return try AIModelDiscoveryParser.gemini(from: data)
        } catch {
            throw redactedError(error, apiKey: apiKey)
        }
    }

    func chat(
        configuration: AIProviderConfiguration,
        apiKey: String?,
        modelID: String,
        messages: [AIMessage],
        options: AIChatRequestOptions
    ) async throws -> AIChatResponse {
        let builder = AIRequestBuilder(configuration: configuration, apiKey: apiKey, modelID: modelID, messages: messages, options: options)
        do {
            let request = try builder.build()
            let (data, response) = try await send(request)
            return try AIResponseNormalizer.normalize(
                data: data,
                response: response,
                protocolType: .geminiNative,
                modelID: modelID,
                providerDisplayName: configuration.displayName
            )
        } catch {
            throw redactedError(error, apiKey: apiKey)
        }
    }
}

struct CustomProviderAdapter: AIProviderProtocol {
    var protocolType: AIProtocolType { .customAdapter }

    func testConnection(configuration: AIProviderConfiguration, apiKey: String?, modelID: String) async throws -> AIConnectionTestResult {
        try await AIConnectionTester.testChat(
            provider: self,
            configuration: configuration,
            apiKey: apiKey,
            modelID: modelID
        )
    }

    func fetchModels(configuration: AIProviderConfiguration, apiKey: String?) async throws -> [AIModelInfo] {
        throw AIError.unsupportedAdapter(configuration.customAdapterName.isEmpty ? "custom adapter" : configuration.customAdapterName)
    }

    func chat(
        configuration: AIProviderConfiguration,
        apiKey: String?,
        modelID: String,
        messages: [AIMessage],
        options: AIChatRequestOptions
    ) async throws -> AIChatResponse {
        let builder = AIRequestBuilder(configuration: configuration, apiKey: apiKey, modelID: modelID, messages: messages, options: options)
        do {
            let request = try builder.build()
            let (data, response) = try await send(request)
            return try AIResponseNormalizer.normalize(
                data: data,
                response: response,
                protocolType: .customAdapter,
                modelID: modelID,
                providerDisplayName: configuration.displayName
            )
        } catch {
            throw redactedError(error, apiKey: apiKey)
        }
    }
}

enum AIProviderFactory {
    static func provider(for protocolType: AIProtocolType) -> AIProviderProtocol {
        switch protocolType {
        case .openAICompatible: return OpenAICompatibleProvider()
        case .geminiNative: return GeminiNativeProvider()
        case .customAdapter: return CustomProviderAdapter()
        }
    }
}
