import Foundation

struct AIMessage: Codable, Equatable {
    var role: String
    var content: String
    init(role: String, content: String) {
        self.role = role
        self.content = content
    }
    static func user(_ content: String) -> AIMessage { AIMessage(role: "user", content: content) }
    static func system(_ content: String) -> AIMessage { AIMessage(role: "system", content: content) }
    static func assistant(_ content: String) -> AIMessage { AIMessage(role: "assistant", content: content) }
}

struct AIChatRequestOptions: Equatable {
    var temperature: Double
    var maxOutputTokens: Int
    var streaming: Bool
    var jsonMode: Bool
    var toolsEnabled: Bool
    var responseFormatInstructions: String?

    init(
        temperature: Double = 0.7,
        maxOutputTokens: Int = 1024,
        streaming: Bool = false,
        jsonMode: Bool = false,
        toolsEnabled: Bool = false,
        responseFormatInstructions: String? = nil
    ) {
        self.temperature = temperature
        self.maxOutputTokens = maxOutputTokens
        self.streaming = streaming
        self.jsonMode = jsonMode
        self.toolsEnabled = toolsEnabled
        self.responseFormatInstructions = responseFormatInstructions
    }

    static func connectionTest() -> AIChatRequestOptions {
        AIChatRequestOptions(temperature: 0, maxOutputTokens: 8, streaming: false)
    }
}

struct AIChatResponse: Equatable {
    var text: String
    var modelID: String
    var providerDisplayName: String
    var usedFallback: Bool
    var rawStatusCode: Int
}

struct AIModelInfo: Equatable, Identifiable {
    var id: String
    var displayName: String
    var ownedBy: String?
    var createdAt: Date?
    var source: String
    var capability: AIModelCapability
}

struct AIConnectionTestResult: Equatable {
    var succeeded: Bool
    var message: String
    var statusCode: Int?
    var latencyMilliseconds: Int
    var modelID: String
    var providerDisplayName: String
}

enum AIError: LocalizedError, Equatable {
    case invalidBaseURL(String)
    case missingAPIKey
    case missingModelID
    case providerDisabled
    case unsupportedAdapter(String)
    case missingAdapterPaths
    case networkError(String)
    case httpError(Int, String)
    case responseParsingFailed(String)
    case noProviderConfigured(AITaskType)
    case capabilityUnavailable(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL(let message): return message
        case .missingAPIKey: return "API key is missing. Add one in the provider settings."
        case .missingModelID: return "Model ID is missing. Enter one manually or fetch models."
        case .providerDisabled: return "This provider is disabled."
        case .unsupportedAdapter(let name): return "No adapter is registered for '\(name)'. Custom APIs need a compatible adapter implementation."
        case .missingAdapterPaths: return "Custom adapters need a chat path and a JSON text path."
        case .networkError(let message): return "Network error: \(message)"
        case .httpError(let code, let message): return "HTTP \(code): \(message)"
        case .responseParsingFailed(let message): return "Could not parse the AI response: \(message)"
        case .noProviderConfigured(let task): return "No provider is configured for \(task.title)."
        case .capabilityUnavailable(let message): return message
        case .cancelled: return "The request was cancelled."
        }
    }
}

struct AIResolvedConfiguration: Equatable {
    var provider: AIProviderConfiguration
    var modelID: String
    var capability: AIModelCapability
    var usedFallback: Bool
}

protocol AIProviderProtocol {
    var protocolType: AIProtocolType { get }
    func testConnection(configuration: AIProviderConfiguration, apiKey: String?, modelID: String) async throws -> AIConnectionTestResult
    func fetchModels(configuration: AIProviderConfiguration, apiKey: String?) async throws -> [AIModelInfo]
    func chat(configuration: AIProviderConfiguration, apiKey: String?, modelID: String, messages: [AIMessage], options: AIChatRequestOptions) async throws -> AIChatResponse
}
