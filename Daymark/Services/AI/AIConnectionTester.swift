import Foundation

enum AIConnectionTester {
    static func testChat(
        provider: AIProviderProtocol,
        configuration: AIProviderConfiguration,
        apiKey: String?,
        modelID: String
    ) async throws -> AIConnectionTestResult {
        try AIEndpointResolver.validateBaseURL(configuration.baseURLString)
        let model = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else { throw AIError.missingModelID }
        if configuration.protocolType == .customAdapter {
            let chatPath = configuration.customChatPath.trimmingCharacters(in: .whitespacesAndNewlines)
            let textPath = configuration.customTextPath.trimmingCharacters(in: .whitespacesAndNewlines)
            let adapterName = configuration.customAdapterName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !chatPath.isEmpty, !textPath.isEmpty else { throw AIError.missingAdapterPaths }
            guard !adapterName.isEmpty else { throw AIError.unsupportedAdapter("custom adapter") }
        }
        let start = Date()
        let response = try await provider.chat(
            configuration: configuration,
            apiKey: apiKey,
            modelID: model,
            messages: [.user("Reply with OK.")],
            options: .connectionTest()
        )
        let latency = Int(Date().timeIntervalSince(start) * 1000)
        let preview = response.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return AIConnectionTestResult(
            succeeded: true,
            message: preview.isEmpty ? "Connection succeeded. The model answered in \(latency) ms." : "Connected to \(configuration.displayName) · \(model) in \(latency) ms. Model said: \(preview.prefix(120))",
            statusCode: response.rawStatusCode == 0 ? 200 : response.rawStatusCode,
            latencyMilliseconds: latency,
            modelID: model,
            providerDisplayName: configuration.displayName
        )
    }
}

enum AIModelDiscoveryService {
    static func fetchModels(configuration: AIProviderConfiguration, apiKey: String?) async throws -> [AIModelInfo] {
        let provider = AIProviderFactory.provider(for: configuration.protocolType)
        return try await provider.fetchModels(configuration: configuration, apiKey: apiKey)
    }
}
