import Foundation

enum AIEndpointResolver {
    static func validateBaseURL(_ string: String) throws -> URL {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AIError.invalidBaseURL("Base URL is empty. Enter the full API base URL, including https://.")
        }
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(), let host = url.host, !host.isEmpty else {
            throw AIError.invalidBaseURL("Base URL must be an absolute URL such as https://api.example.com/v1.")
        }
        guard scheme == "https" || scheme == "http" else {
            throw AIError.invalidBaseURL("Base URL must use http:// or https://.")
        }
        if url.user != nil || url.password != nil {
            throw AIError.invalidBaseURL("Do not put credentials in the Base URL. Use the API Key field instead.")
        }
        if url.fragment != nil {
            throw AIError.invalidBaseURL("Remove the fragment (#...) from the Base URL.")
        }
        return url
    }

    static func openAIURL(baseURL: URL, mode: AIEndpointMode, customPath: String, kind: OpenAIEndpointKind) -> URL {
        var components = normalizedOpenAIComponents(baseURL: baseURL, mode: mode, customPath: customPath)
        let suffix: [String]
        switch kind {
        case .chatCompletions: suffix = ["chat", "completions"]
        case .models: suffix = ["models"]
        case .responses: suffix = ["responses"]
        }
        components.path = appendPath(components.path, suffix)
        return components.url ?? baseURL
    }

    static func geminiURL(baseURL: URL, modelID: String, streaming: Bool, kind: GeminiEndpointKind) -> URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) ?? URLComponents()
        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let model = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        switch kind {
        case .listModels:
            components.path = "/" + (basePath.isEmpty ? "models" : basePath + "/models")
            components.queryItems = nil
        case .generateContent:
            let action = streaming ? "streamGenerateContent" : "generateContent"
            components.path = "/" + (basePath.isEmpty ? "models/\(model):\(action)" : basePath + "/models/\(model):\(action)")
            components.queryItems = streaming ? [URLQueryItem(name: "alt", value: "sse")] : nil
        }
        return components.url ?? baseURL
    }

    static func customURL(baseURL: URL, customPath: String) -> URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) ?? URLComponents()
        let path = customPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return baseURL }
        if path.hasPrefix("http://") || path.hasPrefix("https://") {
            return URL(string: path) ?? baseURL
        }
        components.path = appendPath(components.path, path.split(separator: "/").map(String.init))
        return components.url ?? baseURL
    }

    private static func normalizedOpenAIComponents(baseURL: URL, mode: AIEndpointMode, customPath: String) -> URLComponents {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) ?? URLComponents()
        let currentPath = components.path
        switch mode {
        case .openAIStandard:
            if !(currentPath.hasSuffix("/v1") || currentPath == "/v1") {
                components.path = appendPath(currentPath, ["v1"])
            }
        case .v1AlreadyIncluded:
            break
        case .customChatPath:
            components.path = currentPath
        }
        return components
    }

    private static func appendPath(_ existing: String, _ parts: [String]) -> String {
        var path = existing
        for part in parts where !part.isEmpty {
            if !path.hasSuffix("/") { path += "/" }
            path += part
        }
        return path.isEmpty ? "/" : path
    }

    enum OpenAIEndpointKind { case chatCompletions, models, responses }
    enum GeminiEndpointKind { case listModels, generateContent }
}

enum AIAuthenticationHandler {
    static func apply(
        url: inout URL,
        request: inout URLRequest,
        mode: AIAuthMode,
        apiKey: String?,
        customHeaders: [String: String],
        organizationID: String = "",
        projectID: String = "",
        protocolType: AIProtocolType
    ) {
        for (name, value) in customHeaders where !name.hasPrefix("Authorization") {
            request.setValue(value, forHTTPHeaderField: name)
        }
        if let authorization = customHeaders["Authorization"] {
            request.setValue(authorization, forHTTPHeaderField: "Authorization")
        }
        let key = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        switch mode {
        case .bearerAPIKey:
            if !key.isEmpty {
                request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            }
        case .headerAPIKey:
            if !key.isEmpty {
                request.setValue(key, forHTTPHeaderField: "X-API-Key")
                request.setValue(key, forHTTPHeaderField: "Api-Key")
            }
        case .queryAPIKey:
            guard !key.isEmpty else { break }
            if protocolType == .geminiNative {
                request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
            } else {
                var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                var items = components?.queryItems ?? []
                items.append(URLQueryItem(name: "key", value: key))
                components?.queryItems = items
                if let updated = components?.url { url = updated }
            }
        case .customHeadersOnly, .noAuth:
            break
        }
        let organization = organizationID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !organization.isEmpty {
            request.setValue(organization, forHTTPHeaderField: "OpenAI-Organization")
        }
        let project = projectID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !project.isEmpty {
            request.setValue(project, forHTTPHeaderField: "OpenAI-Project")
        }
    }
}

struct AIRequestBuilder {
    let configuration: AIProviderConfiguration
    let apiKey: String?
    let modelID: String
    let messages: [AIMessage]
    let options: AIChatRequestOptions

    func build() throws -> URLRequest {
        let baseURL = try AIEndpointResolver.validateBaseURL(configuration.baseURLString)
        let model = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else { throw AIError.missingModelID }
        switch configuration.protocolType {
        case .openAICompatible:
            return try openAIRequest(baseURL: baseURL, model: model)
        case .geminiNative:
            return try geminiRequest(baseURL: baseURL, model: model)
        case .customAdapter:
            return try customRequest(baseURL: baseURL, model: model)
        }
    }

    private func openAIRequest(baseURL: URL, model: String) throws -> URLRequest {
        var url = AIEndpointResolver.openAIURL(
            baseURL: baseURL,
            mode: configuration.endpointMode,
            customPath: configuration.customChatPath,
            kind: .chatCompletions
        )
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if options.streaming {
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        }
        AIAuthenticationHandler.apply(
            url: &url, request: &request, mode: configuration.authMode, apiKey: apiKey,
            customHeaders: configuration.customHeaders,
            organizationID: configuration.organizationID, projectID: configuration.projectID,
            protocolType: .openAICompatible
        )
        request.url = url
        request.timeoutInterval = TimeInterval(max(1, configuration.timeoutSeconds))
        var body: [String: Any] = [
            "model": model,
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
        ]
        if options.jsonMode {
            body["response_format"] = ["type": "json_object"]
        }
        body["temperature"] = min(max(0, options.temperature), 2)
        body["max_tokens"] = max(1, options.maxOutputTokens)
        body["stream"] = options.streaming
        if let instructions = options.responseFormatInstructions, !instructions.isEmpty {
            body["messages"] = ([AIMessage(role: "system", content: instructions)] + messages).map { ["role": $0.role, "content": $0.content] }
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func geminiRequest(baseURL: URL, model: String) throws -> URLRequest {
        var url = AIEndpointResolver.geminiURL(baseURL: baseURL, modelID: model, streaming: options.streaming, kind: .generateContent)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        AIAuthenticationHandler.apply(
            url: &url, request: &request, mode: configuration.authMode, apiKey: apiKey,
            customHeaders: configuration.customHeaders,
            protocolType: .geminiNative
        )
        request.url = url
        request.timeoutInterval = TimeInterval(max(1, configuration.timeoutSeconds))
        let contents = messages.map { message in
            ["role": message.role == "assistant" ? "model" : "user", "parts": [["text": message.content]]]
        }
        var generationConfig: [String: Any] = [
            "temperature": min(max(0, options.temperature), 2),
            "maxOutputTokens": max(1, options.maxOutputTokens)
        ]
        if options.jsonMode {
            generationConfig["responseMimeType"] = "application/json"
        }
        var body: [String: Any] = ["contents": contents, "generationConfig": generationConfig]
        if let instructions = options.responseFormatInstructions, !instructions.isEmpty {
            body["systemInstruction"] = ["parts": [["text": instructions]]]
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func customRequest(baseURL: URL, model: String) throws -> URLRequest {
        let chatPath = configuration.customChatPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let textPath = configuration.customTextPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !chatPath.isEmpty, !textPath.isEmpty else { throw AIError.missingAdapterPaths }
        guard !configuration.customAdapterName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIError.unsupportedAdapter("empty")
        }
        var url = AIEndpointResolver.customURL(baseURL: baseURL, customPath: chatPath)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        AIAuthenticationHandler.apply(
            url: &url, request: &request, mode: configuration.authMode, apiKey: apiKey,
            customHeaders: configuration.customHeaders,
            organizationID: configuration.organizationID, projectID: configuration.projectID,
            protocolType: .customAdapter
        )
        request.url = url
        request.timeoutInterval = TimeInterval(max(1, configuration.timeoutSeconds))
        var body: [String: Any] = [
            "model": model,
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
            "temperature": min(max(0, options.temperature), 2),
            "max_tokens": max(1, options.maxOutputTokens),
            "stream": options.streaming
        ]
        if options.jsonMode { body["response_format"] = ["type": "json_object"] }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }
}
