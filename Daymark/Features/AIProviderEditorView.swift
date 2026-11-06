import SwiftUI

struct AIProviderEditorView: View {
    @Environment(DaymarkStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private let provider: AIProviderConfiguration?
    @State private var displayName: String
    @State private var baseURLString: String
    @State private var modelID: String
    @State private var protocolType: AIProtocolType
    @State private var authMode: AIAuthMode
    @State private var endpointMode: AIEndpointMode
    @State private var enabled: Bool
    @State private var apiKey: String = ""
    @State private var showAPIKey = false
    @State private var customHeaderLines: [String]
    @State private var organizationID: String
    @State private var projectID: String
    @State private var timeoutSeconds: Int
    @State private var streamingEnabled: Bool
    @State private var temperature: Double
    @State private var maxOutputTokens: Int
    @State private var customChatPath: String
    @State private var customTextPath: String
    @State private var customAdapterName: String
    @State private var supportsStreaming: Bool
    @State private var supportsJSONMode: Bool
    @State private var supportsTools: Bool
    @State private var supportsVision: Bool
    @State private var supportsTemperature: Bool
    @State private var contextLength: Int
    @State private var discoveredModels: [AIModelInfo] = []
    @State private var isDiscovering = false
    @State private var isTesting = false
    @State private var testMessage: String?
    @State private var testSucceeded = false
    @State private var confirmDelete = false
    @State private var savedMessage: String?

    init(provider: AIProviderConfiguration? = nil) {
        self.provider = provider
        _displayName = State(initialValue: provider?.displayName ?? "Custom provider")
        _baseURLString = State(initialValue: provider?.baseURLString ?? "")
        _modelID = State(initialValue: provider?.modelID ?? "")
        _protocolType = State(initialValue: provider?.protocolType ?? .openAICompatible)
        _authMode = State(initialValue: provider?.authMode ?? .bearerAPIKey)
        _endpointMode = State(initialValue: provider?.endpointMode ?? .openAIStandard)
        _enabled = State(initialValue: provider?.enabled ?? true)
        _customHeaderLines = State(initialValue: provider?.customHeaderLines ?? [])
        _organizationID = State(initialValue: provider?.organizationID ?? "")
        _projectID = State(initialValue: provider?.projectID ?? "")
        _timeoutSeconds = State(initialValue: provider?.timeoutSeconds ?? 30)
        _streamingEnabled = State(initialValue: provider?.streamingEnabled ?? false)
        _temperature = State(initialValue: provider?.temperature ?? 0.7)
        _maxOutputTokens = State(initialValue: provider?.maxOutputTokens ?? 1024)
        _customChatPath = State(initialValue: provider?.customChatPath ?? "")
        _customTextPath = State(initialValue: provider?.customTextPath ?? "")
        _customAdapterName = State(initialValue: provider?.customAdapterName ?? "")
        let capability = AIModelCapability()
        _supportsStreaming = State(initialValue: capability.supportsStreaming)
        _supportsJSONMode = State(initialValue: capability.supportsJSONMode)
        _supportsTools = State(initialValue: capability.supportsTools)
        _supportsVision = State(initialValue: capability.supportsVision)
        _supportsTemperature = State(initialValue: capability.supportsTemperature)
        _contextLength = State(initialValue: capability.contextLength)
    }

    // Capabilities are loaded in onAppear from DaymarkStore because SwiftUI
    // state initialization runs before environment values are available.

    private var isNew: Bool { provider == nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Connection") {
                    TextField("Display name", text: $displayName)
                    Picker("API protocol", selection: $protocolType) {
                        ForEach(AIProtocolType.allCases) { Text($0.title).tag($0) }
                    }
                    TextField("Base URL", text: $baseURLString)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    if protocolType == .openAICompatible {
                        Picker("Endpoint mode", selection: $endpointMode) {
                            ForEach(AIEndpointMode.allCases) { Text($0.title).tag($0) }
                        }
                        if endpointMode == .customChatPath {
                            TextField("Custom chat path", text: $customChatPath)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                    }
                    if protocolType == .customAdapter {
                        TextField("Adapter name", text: $customAdapterName)
                        TextField("Chat path", text: $customChatPath)
                        TextField("Text JSON path (e.g. choices.0.message.content)", text: $customTextPath)
                        Text("Custom adapters are not arbitrary URLs. The adapter name, chat path, and JSON text path must describe a compatible implementation.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Toggle("Enabled", isOn: $enabled)
                }

                Section("Authentication") {
                    Picker("Auth mode", selection: $authMode) {
                        ForEach(AIAuthMode.allCases) { Text($0.title).tag($0) }
                    }
                    HStack {
                        if showAPIKey {
                            TextField("API key", text: $apiKey)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        } else {
                            SecureField("API key", text: $apiKey)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                        Button(showAPIKey ? "Hide" : "Show") { showAPIKey.toggle() }
                            .font(.subheadline)
                    }
                    Text("API keys are stored in the iOS Keychain and are never written to UserDefaults, logs, or exported backups.")
                        .font(.caption).foregroundStyle(.secondary)
                    TextField("Organization ID (optional)", text: $organizationID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Project ID (optional)", text: $projectID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("Custom headers") {
                    ForEach(Array(customHeaderLines.enumerated()), id: \.offset) { index, _ in
                        HStack {
                            TextField("Name: value", text: Binding(
                                get: { customHeaderLines.indices.contains(index) ? customHeaderLines[index] : "" },
                                set: { value in
                                    if customHeaderLines.indices.contains(index) { customHeaderLines[index] = value }
                                }
                            ))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            Button(role: .destructive) {
                                customHeaderLines.remove(at: index)
                            } label: {
                                Image(systemName: "trash")
                            }.accessibilityLabel("Remove header")
                        }
                    }
                    Button { customHeaderLines.append("") } label: {
                        Label("Add header", systemImage: "plus")
                    }
                }

                Section("Model") {
                    TextField("Model ID (manual)", text: $modelID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button {
                        discoverModels()
                    } label: {
                        Label(isDiscovering ? "Fetching models…" : "Fetch models", systemImage: "arrow.down.doc")
                    }
                    .disabled(isDiscovering || protocolType == .customAdapter)
                    if !discoveredModels.isEmpty {
                        ForEach(discoveredModels) { model in
                            Button {
                                modelID = model.id
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(model.displayName).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                                        Text(model.id).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if modelID == model.id { Image(systemName: "checkmark") }
                                }
                            }
                        }
                        Text("Tapping a discovered model fills the Model ID. You can also type any model ID manually.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section("Request options") {
                    Stepper("Timeout: \(timeoutSeconds)s", value: $timeoutSeconds, in: 5...120, step: 5)
                    Toggle("Streaming", isOn: $streamingEnabled)
                    Slider(value: $temperature, in: 0...2, step: 0.1) {
                        Text("Temperature: \(temperature, specifier: "%.1f")")
                    }
                    Stepper("Max output tokens: \(maxOutputTokens)", value: $maxOutputTokens, in: 1...32768, step: 128)
                }

                Section("Model capabilities") {
                    Toggle("Streaming", isOn: $supportsStreaming)
                    Toggle("JSON mode", isOn: $supportsJSONMode)
                    Toggle("Tool / function calling", isOn: $supportsTools)
                    Toggle("Vision", isOn: $supportsVision)
                    Toggle("Temperature", isOn: $supportsTemperature)
                    Stepper("Context length: \(contextLength == 0 ? "unknown" : "\(contextLength)")", value: $contextLength, in: 0...1_000_000, step: 1024)
                    Text("Capabilities are checked before invoking a feature. Automatic detection is optional; manual values are kept.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("Test") {
                    Button {
                        testConnection()
                    } label: {
                        Label(isTesting ? "Testing…" : "Test connection & model", systemImage: "network")
                    }
                    .disabled(isTesting)
                    if let testMessage {
                        Label(testMessage, systemImage: testSucceeded ? "checkmark.circle" : "exclamationmark.triangle")
                            .foregroundStyle(testSucceeded ? Palette.color("mint") : .red)
                            .font(.subheadline)
                    }
                }

                if let savedMessage {
                    Section { Text(savedMessage).font(.subheadline) }
                }

                if !isNew {
                    Section {
                        Button("Duplicate provider", systemImage: "rectangle.on.rectangle") {
                            if let source = provider {
                                _ = store.ai.duplicateProvider(source)
                                dismiss()
                            }
                        }
                        Button("Delete provider", role: .destructive) {
                            confirmDelete = true
                        }
                    }
                }
            }
            .navigationTitle(isNew ? "Add provider" : "Edit provider")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.bold() }
            }
            .confirmationDialog("Delete this provider and its saved API key?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete provider", role: .destructive) {
                    if let provider { store.ai.deleteProvider(provider) }
                    dismiss()
                }
                Button("Cancel", role: .cancel) { }
            }
            .onAppear {
                loadCapabilityForCurrentModel()
            }
        }
    }

    private func loadCapabilityForCurrentModel() {
        guard let provider,
              !modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let capability = store.ai.modelConfiguration(providerID: provider.id, modelID: modelID)?.capability else { return }
        supportsStreaming = capability.supportsStreaming
        supportsJSONMode = capability.supportsJSONMode
        supportsTools = capability.supportsTools
        supportsVision = capability.supportsVision
        supportsTemperature = capability.supportsTemperature
        contextLength = capability.contextLength
    }

    private func currentProviderForTesting() -> AIProviderConfiguration {
        let target = provider ?? AIProviderConfiguration(displayName: displayName)
        target.displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        target.baseURLString = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        target.modelID = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        target.protocolRaw = protocolType.rawValue
        target.authModeRaw = authMode.rawValue
        target.endpointModeRaw = endpointMode.rawValue
        target.enabled = enabled
        target.customHeaderLines = customHeaderLines
        target.organizationID = organizationID
        target.projectID = projectID
        target.timeoutSeconds = timeoutSeconds
        target.streamingEnabled = streamingEnabled
        target.temperature = temperature
        target.maxOutputTokens = maxOutputTokens
        target.customChatPath = customChatPath
        target.customTextPath = customTextPath
        target.customAdapterName = customAdapterName
        target.updatedAt = .now
        return target
    }

    private func save() {
        let target = currentProviderForTesting()
        target.displayName = target.displayName.isEmpty ? "Custom provider" : target.displayName
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        store.ai.saveProvider(target, apiKey: key.isEmpty ? nil : key)
        let capability = AIModelCapability(
            supportsStreaming: supportsStreaming,
            supportsJSONMode: supportsJSONMode,
            supportsTools: supportsTools,
            supportsVision: supportsVision,
            supportsTemperature: supportsTemperature,
            contextLength: contextLength,
            maxOutputTokens: maxOutputTokens,
            manuallyOverridden: true
        )
        store.ai.updateModelCapability(providerID: target.id, modelID: target.modelID, capability: capability)
        savedMessage = "Saved. Your API key, if provided, is stored in the Keychain."
        dismiss()
    }

    private func testConnection() {
        let target = currentProviderForTesting()
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveKey = key.isEmpty ? (provider.flatMap { AIKeychainService.loadAPIKey(for: $0.id) }) : key
        isTesting = true
        testMessage = nil
        Task {
            do {
                let result = try await AIProviderFactory.provider(for: target.protocolType).testConnection(
                    configuration: target,
                    apiKey: effectiveKey,
                    modelID: target.modelID
                )
                testSucceeded = result.succeeded
                testMessage = result.message
            } catch {
                testSucceeded = false
                testMessage = AISecretRedactor.redact(error.localizedDescription, apiKey: effectiveKey)
            }
            isTesting = false
        }
    }

    private func discoverModels() {
        let target = currentProviderForTesting()
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveKey = key.isEmpty ? (provider.flatMap { AIKeychainService.loadAPIKey(for: $0.id) }) : key
        isDiscovering = true
        Task {
            do {
                let models = try await AIModelDiscoveryService.fetchModels(configuration: target, apiKey: effectiveKey)
                discoveredModels = models
                if let targetProvider = provider {
                    for model in models {
                        store.ai.ensureModelConfiguration(providerID: targetProvider.id, modelID: model.id, capability: model.capability, source: model.source)
                    }
                }
            } catch {
                testSucceeded = false
                testMessage = AISecretRedactor.redact(error.localizedDescription, apiKey: effectiveKey)
            }
            isDiscovering = false
        }
    }
}
