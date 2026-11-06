import Foundation

@MainActor
struct AIProviderManager {
    let store: DaymarkStore
    init(store: DaymarkStore) { self.store = store }

    var configurations: [AIProviderConfiguration] { store.aiProviders }
    var enabledConfigurations: [AIProviderConfiguration] { store.aiProviders.filter { $0.enabled } }

    func configuration(_ id: UUID?) -> AIProviderConfiguration? {
        guard let id else { return nil }
        return store.aiProviders.first { $0.id == id }
    }

    func modelConfiguration(providerID: UUID, modelID: String) -> AIModelConfiguration? {
        let model = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.aiModels.first { $0.providerID == providerID && $0.modelID == model }
    }

    func assignment(for task: AITaskType) -> AITaskAssignment? {
        store.aiAssignments.first { $0.taskRaw == task.rawValue }
    }

    func resolvedConfiguration(for task: AITaskType) -> AIResolvedConfiguration? {
        if let assignment = assignment(for: task),
           let provider = configuration(assignment.providerID),
           !assignment.modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return AIResolvedConfiguration(
                provider: provider,
                modelID: assignment.modelID,
                capability: modelConfiguration(providerID: provider.id, modelID: assignment.modelID)?.capability ?? AIModelCapability(),
                usedFallback: false
            )
        }
        if let assignment = assignment(for: .default),
           let provider = configuration(assignment.providerID),
           !assignment.modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return AIResolvedConfiguration(
                provider: provider,
                modelID: assignment.modelID,
                capability: modelConfiguration(providerID: provider.id, modelID: assignment.modelID)?.capability ?? AIModelCapability(),
                usedFallback: false
            )
        }
        if let provider = enabledConfigurations.first {
            let model = provider.modelID
            guard !model.isEmpty else { return nil }
            return AIResolvedConfiguration(
                provider: provider,
                modelID: model,
                capability: modelConfiguration(providerID: provider.id, modelID: model)?.capability ?? AIModelCapability(),
                usedFallback: false
            )
        }
        return nil
    }

    func fallbackConfiguration(for task: AITaskType) -> AIResolvedConfiguration? {
        guard let assignment = assignment(for: task), assignment.fallbackEnabled,
              let provider = configuration(assignment.fallbackProviderID),
              !assignment.fallbackModelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return AIResolvedConfiguration(
            provider: provider,
            modelID: assignment.fallbackModelID,
            capability: modelConfiguration(providerID: provider.id, modelID: assignment.fallbackModelID)?.capability ?? AIModelCapability(),
            usedFallback: true
        )
    }

    func saveProvider(_ configuration: AIProviderConfiguration, apiKey: String? = nil) {
        let isNew = !store.aiProviders.contains { $0.id == configuration.id }
        let id = configuration.id
        store.perform {
            if isNew { store.context.insert(configuration) }
            configuration.updatedAt = .now
        }
        if let apiKey, !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            _ = AIKeychainService.saveAPIKey(apiKey, for: id)
        }
        if isNew {
            setDefaultIfNeeded(providerID: id, modelID: configuration.modelID)
        }
    }

    func duplicateProvider(_ configuration: AIProviderConfiguration) -> AIProviderConfiguration? {
        let copy = AIProviderConfiguration(displayName: configuration.displayName + " copy")
        copy.baseURLString = configuration.baseURLString
        copy.modelID = configuration.modelID
        copy.protocolRaw = configuration.protocolRaw
        copy.authModeRaw = configuration.authModeRaw
        copy.endpointModeRaw = configuration.endpointModeRaw
        copy.enabled = configuration.enabled
        copy.customHeaderLines = configuration.customHeaderLines
        copy.organizationID = configuration.organizationID
        copy.projectID = configuration.projectID
        copy.timeoutSeconds = configuration.timeoutSeconds
        copy.streamingEnabled = configuration.streamingEnabled
        copy.temperature = configuration.temperature
        copy.maxOutputTokens = configuration.maxOutputTokens
        copy.customChatPath = configuration.customChatPath
        copy.customTextPath = configuration.customTextPath
        copy.customAdapterName = configuration.customAdapterName
        store.perform { store.context.insert(copy) }
        if let key = AIKeychainService.loadAPIKey(for: configuration.id) {
            _ = AIKeychainService.saveAPIKey(key, for: copy.id)
        }
        for model in store.aiModels.filter({ $0.providerID == configuration.id }) {
            let modelCopy = AIModelConfiguration(providerID: copy.id, modelID: model.modelID, displayName: model.displayName, source: model.source)
            modelCopy.apply(model.capability)
            store.perform { store.context.insert(modelCopy) }
        }
        return copy
    }

    func deleteProvider(_ configuration: AIProviderConfiguration) {
        let id = configuration.id
        store.perform {
            store.aiModels.filter { $0.providerID == id }.forEach { store.context.delete($0) }
            for assignment in store.aiAssignments {
                if assignment.providerID == id { assignment.providerID = nil; assignment.modelID = "" }
                if assignment.fallbackProviderID == id { assignment.fallbackProviderID = nil; assignment.fallbackModelID = ""; assignment.fallbackEnabled = false }
                assignment.updatedAt = .now
            }
            store.context.delete(configuration)
        }
        _ = AIKeychainService.deleteAPIKey(for: id)
    }

    func setEnabled(_ enabled: Bool, provider: AIProviderConfiguration) {
        store.perform {
            provider.enabled = enabled
            provider.updatedAt = .now
        }
    }

    func setAssignment(
        task: AITaskType,
        providerID: UUID?,
        modelID: String,
        fallbackProviderID: UUID? = nil,
        fallbackModelID: String = "",
        fallbackEnabled: Bool = false
    ) {
        let existing = assignment(for: task)
        store.perform {
            let target = existing ?? AITaskAssignment(task: task)
            if existing == nil { store.context.insert(target) }
            target.providerID = providerID
            target.modelID = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
            target.fallbackProviderID = fallbackProviderID
            target.fallbackModelID = fallbackModelID.trimmingCharacters(in: .whitespacesAndNewlines)
            target.fallbackEnabled = fallbackEnabled
            target.updatedAt = .now
        }
    }

    func setDefault(providerID: UUID?, modelID: String) {
        setAssignment(task: .default, providerID: providerID, modelID: modelID)
    }

    func ensureModelConfiguration(providerID: UUID, modelID: String, capability: AIModelCapability? = nil, source: String = "manual") {
        let model = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else { return }
        if modelConfiguration(providerID: providerID, modelID: model) == nil {
            let record = AIModelConfiguration(providerID: providerID, modelID: model, displayName: model, source: source)
            if let capability { record.apply(capability) }
            store.perform { store.context.insert(record) }
        } else if let capability, let record = modelConfiguration(providerID: providerID, modelID: model) {
            store.perform { record.apply(capability) }
        }
    }

    func updateModelCapability(providerID: UUID, modelID: String, capability: AIModelCapability) {
        ensureModelConfiguration(providerID: providerID, modelID: modelID, capability: capability, source: "manual")
    }

    func validateCapabilities(task: AITaskType, resolved: AIResolvedConfiguration, requiresJSON: Bool = false, requiresTools: Bool = false) throws {
        if requiresJSON, !resolved.capability.supportsJSONMode {
            throw AIError.capabilityUnavailable("This model does not report native JSON mode. Daymark will request JSON text and validate it locally if you continue.")
        }
        if requiresTools, !resolved.capability.supportsTools {
            throw AIError.capabilityUnavailable("\(resolved.modelID) does not report tool/function calling support, so it cannot be used for app actions that require tools.")
        }
    }

    func chat(
        task: AITaskType = .chat,
        messages: [AIMessage],
        options: AIChatRequestOptions = AIChatRequestOptions()
    ) async throws -> AIChatResponse {
        guard let primary = resolvedConfiguration(for: task) else {
            throw AIError.noProviderConfigured(task)
        }
        guard primary.provider.enabled else { throw AIError.providerDisabled }
        do {
            return try await performChat(resolved: primary, messages: messages, options: options)
        } catch {
            if let fallback = fallbackConfiguration(for: task) {
                return try await performChat(resolved: fallback, messages: messages, options: options)
            }
            throw error
        }
    }

    private func performChat(resolved: AIResolvedConfiguration, messages: [AIMessage], options: AIChatRequestOptions) async throws -> AIChatResponse {
        let provider = AIProviderFactory.provider(for: resolved.provider.protocolType)
        let apiKey = AIKeychainService.loadAPIKey(for: resolved.provider.id)
        return try await provider.chat(
            configuration: resolved.provider,
            apiKey: apiKey,
            modelID: resolved.modelID,
            messages: messages,
            options: options
        )
    }

    func testConnection(providerID: UUID, modelID: String) async throws -> AIConnectionTestResult {
        guard let configuration = configuration(providerID) else {
            throw AIError.networkError("Provider not found.")
        }
        let model = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        let apiKey = AIKeychainService.loadAPIKey(for: providerID)
        let result = try await AIProviderFactory.provider(for: configuration.protocolType).testConnection(
            configuration: configuration,
            apiKey: apiKey,
            modelID: model
        )
        store.perform {
            configuration.lastTestedAt = .now
            configuration.lastTestStatus = result.succeeded ? "succeeded" : "failed"
            configuration.lastTestError = result.succeeded ? "" : result.message
            configuration.updatedAt = .now
        }
        return result
    }

    func fetchModels(providerID: UUID) async throws -> [AIModelInfo] {
        guard let configuration = configuration(providerID) else {
            throw AIError.networkError("Provider not found.")
        }
        let apiKey = AIKeychainService.loadAPIKey(for: providerID)
        let models = try await AIModelDiscoveryService.fetchModels(configuration: configuration, apiKey: apiKey)
        for model in models {
            ensureModelConfiguration(providerID: providerID, modelID: model.id, capability: model.capability, source: model.source)
        }
        return models
    }

    private func setDefaultIfNeeded(providerID: UUID, modelID: String) {
        if assignment(for: .default) == nil && !modelID.isEmpty {
            setDefault(providerID: providerID, modelID: modelID)
        }
    }
}

// Provider routing updates are stored in SwiftData with API keys in Keychain.
