import Foundation
import SwiftData

enum AIProtocolType: String, Codable, CaseIterable, Identifiable {
    case openAICompatible
    case geminiNative
    case customAdapter
    var id: String { rawValue }
    var title: String {
        switch self {
        case .openAICompatible: return "OpenAI-compatible"
        case .geminiNative: return "Google Gemini native"
        case .customAdapter: return "Custom API adapter"
        }
    }
}

enum AIAuthMode: String, Codable, CaseIterable, Identifiable {
    case bearerAPIKey
    case headerAPIKey
    case queryAPIKey
    case customHeadersOnly
    case noAuth
    var id: String { rawValue }
    var title: String {
        switch self {
        case .bearerAPIKey: return "Bearer API key"
        case .headerAPIKey: return "API key header"
        case .queryAPIKey: return "API key in query"
        case .customHeadersOnly: return "Custom headers only"
        case .noAuth: return "No authentication"
        }
    }
}

enum AIEndpointMode: String, Codable, CaseIterable, Identifiable {
    case openAIStandard
    case v1AlreadyIncluded
    case customChatPath
    var id: String { rawValue }
    var title: String {
        switch self {
        case .openAIStandard: return "Append /v1"
        case .v1AlreadyIncluded: return "Base URL ends with /v1"
        case .customChatPath: return "Custom chat path"
        }
    }
}

enum AITaskType: String, Codable, CaseIterable, Identifiable {
    case `default`
    case chat
    case moodAnalysis
    case insights
    case appActions
    var id: String { rawValue }
    var title: String {
        switch self {
        case .default: return "Default"
        case .chat: return "AI Chat"
        case .moodAnalysis: return "Automatic Mood Analysis"
        case .insights: return "AI-generated Insights"
        case .appActions: return "Other AI features"
        }
    }
}

struct AIModelCapability: Codable, Equatable {
    var supportsStreaming = false
    var supportsJSONMode = false
    var supportsTools = false
    var supportsVision = false
    var supportsTemperature = true
    var contextLength = 0
    var maxOutputTokens = 0
    var manuallyOverridden = false
}

@Model final class AIProviderConfiguration {
    @Attribute(.unique) var id: UUID
    var displayName: String
    var baseURLString: String
    var modelID: String
    var protocolRaw: String
    var authModeRaw: String
    var endpointModeRaw: String
    var enabled: Bool
    var customHeaderLines: [String]
    var organizationID: String
    var projectID: String
    var timeoutSeconds: Int
    var streamingEnabled: Bool
    var temperature: Double
    var maxOutputTokens: Int
    var customChatPath: String
    var customTextPath: String
    var customAdapterName: String
    var lastTestedAt: Date?
    var lastTestStatus: String
    var lastTestError: String
    var createdAt: Date
    var updatedAt: Date

    var protocolType: AIProtocolType { AIProtocolType(rawValue: protocolRaw) ?? .openAICompatible }
    var authMode: AIAuthMode { AIAuthMode(rawValue: authModeRaw) ?? .bearerAPIKey }
    var endpointMode: AIEndpointMode { AIEndpointMode(rawValue: endpointModeRaw) ?? .openAIStandard }

    var customHeaders: [String: String] {
        var result: [String: String] = [:]
        for line in customHeaderLines {
            let line = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            if let range = line.range(of: ":") {
                let name = line[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
                let value = line[range.upperBound...].trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { result[name] = value }
            } else if let range = line.range(of: "=") {
                let name = line[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
                let value = line[range.upperBound...].trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { result[name] = value }
            }
        }
        return result
    }

    var isReadyForTest: Bool {
        !baseURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init(displayName: String = "Custom provider") {
        id = UUID()
        self.displayName = displayName
        baseURLString = ""
        modelID = ""
        protocolRaw = AIProtocolType.openAICompatible.rawValue
        authModeRaw = AIAuthMode.bearerAPIKey.rawValue
        endpointModeRaw = AIEndpointMode.openAIStandard.rawValue
        enabled = true
        customHeaderLines = []
        organizationID = ""
        projectID = ""
        timeoutSeconds = 30
        streamingEnabled = false
        temperature = 0.7
        maxOutputTokens = 1024
        customChatPath = ""
        customTextPath = ""
        customAdapterName = ""
        lastTestedAt = nil
        lastTestStatus = ""
        lastTestError = ""
        createdAt = .now
        updatedAt = .now
    }
}

@Model final class AIModelConfiguration {
    @Attribute(.unique) var id: UUID
    var providerID: UUID
    var modelID: String
    var displayName: String
    var source: String
    var supportsStreaming: Bool
    var supportsJSONMode: Bool
    var supportsTools: Bool
    var supportsVision: Bool
    var supportsTemperature: Bool
    var contextLength: Int
    var maxOutputTokens: Int
    var manuallyOverridden: Bool
    var detectedAt: Date?
    var createdAt: Date
    var updatedAt: Date

    var capability: AIModelCapability {
        AIModelCapability(
            supportsStreaming: supportsStreaming,
            supportsJSONMode: supportsJSONMode,
            supportsTools: supportsTools,
            supportsVision: supportsVision,
            supportsTemperature: supportsTemperature,
            contextLength: contextLength,
            maxOutputTokens: maxOutputTokens,
            manuallyOverridden: manuallyOverridden
        )
    }

    init(providerID: UUID, modelID: String, displayName: String = "", source: String = "manual") {
        id = UUID()
        self.providerID = providerID
        self.modelID = modelID
        self.displayName = displayName.isEmpty ? modelID : displayName
        self.source = source
        supportsStreaming = false
        supportsJSONMode = false
        supportsTools = false
        supportsVision = false
        supportsTemperature = true
        contextLength = 0
        maxOutputTokens = 0
        manuallyOverridden = false
        detectedAt = nil
        createdAt = .now
        updatedAt = .now
    }

    func apply(_ capability: AIModelCapability) {
        supportsStreaming = capability.supportsStreaming
        supportsJSONMode = capability.supportsJSONMode
        supportsTools = capability.supportsTools
        supportsVision = capability.supportsVision
        supportsTemperature = capability.supportsTemperature
        contextLength = capability.contextLength
        maxOutputTokens = capability.maxOutputTokens
        manuallyOverridden = capability.manuallyOverridden
        updatedAt = .now
    }
}

@Model final class AITaskAssignment {
    @Attribute(.unique) var taskRaw: String
    var providerID: UUID?
    var modelID: String
    var fallbackProviderID: UUID?
    var fallbackModelID: String
    var fallbackEnabled: Bool
    var updatedAt: Date

    var task: AITaskType { AITaskType(rawValue: taskRaw) ?? .default }

    init(task: AITaskType) {
        taskRaw = task.rawValue
        providerID = nil
        modelID = ""
        fallbackProviderID = nil
        fallbackModelID = ""
        fallbackEnabled = false
        updatedAt = .now
    }
}
