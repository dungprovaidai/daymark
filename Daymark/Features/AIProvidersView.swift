import SwiftUI

struct AIProvidersView: View {
    @Environment(DaymarkStore.self) private var store
    @State private var editingProvider: AIProviderConfiguration?
    @State private var showNewProvider = false
    @State private var showAssignments = false

    private var manager: AIProviderManager { store.ai }

    var body: some View {
        List {
            Section {
                Label("Daymark AI works offline. No provider is required; configure endpoints manually only when you want AI features.", systemImage: "info.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                NavigationLink {
                    AITaskAssignmentsView()
                } label: {
                    Label("Task routing & assignment", systemImage: "slider.horizontal.3")
                }
                .accessibilityLabel("Task routing and assignment")
            } header: {
                Text("AI tasks")
            } footer: {
                Text("Default, Chat, Mood Analysis, Insights, and other app actions can each use a different provider and model. If you enable fallback, Daymark will show which provider actually handled a request.")
            }

            Section("Providers") {
                if manager.configurations.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No AI providers configured").font(.headline)
                        Text("Add a custom provider with your own Base URL, API key, and Model ID. Nothing is required for the rest of Daymark to work.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                ForEach(manager.configurations) { provider in
                    Button {
                        editingProvider = provider
                    } label: {
                        providerRow(provider)
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    showNewProvider = true
                } label: {
                    Label("Add custom provider", systemImage: "plus")
                }
            }

            Section("Presets") {
                presetButton(title: "OpenAI-compatible", subtitle: "Fill only the Base URL. Enter your model manually.", protocol: .openAICompatible, baseURL: "https://api.openai.com/v1")
                presetButton(title: "Google Gemini", subtitle: "Native Gemini API format. Enter your model manually.", protocol: .geminiNative, baseURL: "https://generativelanguage.googleapis.com/v1beta")
                presetButton(title: "Local OpenAI-compatible", subtitle: "For local servers such as Ollama-style endpoints.", protocol: .openAICompatible, baseURL: "http://localhost:11434")
            }
        }
        .navigationTitle("Daymark AI")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showNewProvider = true } label: {
                    Image(systemName: "plus")
                }.accessibilityLabel("Add provider")
            }
        }
        .sheet(isPresented: $showNewProvider) {
            AIProviderEditorView()
        }
        .sheet(item: $editingProvider) { provider in
            AIProviderEditorView(provider: provider)
        }
        .sheet(isPresented: $showAssignments) {
            NavigationStack { AITaskAssignmentsView() }
        }
    }

    private func providerRow(_ provider: AIProviderConfiguration) -> some View {
        let isActiveDefault = store.ai.assignment(for: .default)?.providerID == provider.id
        let keySaved = AIKeychainService.hasAPIKey(for: provider.id)
        return HStack(spacing: 12) {
            SymbolTile(symbol: provider.protocolType == .geminiNative ? "sparkles" : "cpu", color: provider.enabled ? Palette.accent : .secondary)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(provider.displayName).font(.headline).foregroundStyle(.primary).lineLimit(1)
                    if isActiveDefault {
                        Text("Active default")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Palette.accent, in: Capsule())
                    }
                }
                Text(provider.protocolType.title).font(.caption).foregroundStyle(.secondary)
                Text(provider.baseURLString.isEmpty ? "No Base URL" : provider.baseURLString)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Text("Model: \(provider.modelID.isEmpty ? "not set" : provider.modelID) · Key: \(keySaved ? "saved" : "not saved")")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                if !provider.lastTestStatus.isEmpty {
                    Text(provider.lastTestStatus == "succeeded" ? "Last test succeeded" : "Last test failed")
                        .font(.caption2)
                        .foregroundStyle(provider.lastTestStatus == "succeeded" ? Palette.color("mint") : .red)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    private func presetButton(title: String, subtitle: String, protocol: AIProtocolType, baseURL: String) -> some View {
        Button {
            let provider = AIProviderConfiguration(displayName: title)
            provider.baseURLString = baseURL
            provider.protocolRaw = protocol.rawValue
            provider.endpointModeRaw = protocol == .openAICompatible ? AIEndpointMode.v1AlreadyIncluded.rawValue : provider.endpointModeRaw
            editingProvider = provider
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }
}

struct AITaskAssignmentsView: View {
    @Environment(DaymarkStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                Text("Choose which provider and model handles each AI task. Leave a model blank to use the provider’s default model.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(AITaskType.allCases) { task in
                TaskAssignmentRow(task: task)
            }
            Section {
                Text("Daymark never silently switches providers. Fallback is only used when you enable it on a task, and the response reports which provider actually handled the request.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Task assignments")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }
}

struct TaskAssignmentRow: View {
    @Environment(DaymarkStore.self) private var store
    let task: AITaskType
    @State private var providerID: UUID?
    @State private var modelID: String = ""
    @State private var fallbackEnabled = false
    @State private var fallbackProviderID: UUID?
    @State private var fallbackModelID: String = ""

    private var manager: AIProviderManager { store.ai }
    private var providers: [AIProviderConfiguration] { manager.enabledConfigurations }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(task.title, systemImage: icon)
                    .font(.headline)
                Spacer()
                if manager.resolvedConfiguration(for: task)?.provider.id == providerID, providerID != nil {
                    Text("Active")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Palette.accent, in: Capsule())
                }
            }
            if providers.isEmpty {
                Text("Add and enable a provider first.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Picker("Provider", selection: $providerID) {
                    Text("None").tag(nil as UUID?)
                    ForEach(providers) { provider in
                        Text(provider.displayName).tag(provider.id as UUID?)
                    }
                }
                TextField("Model ID (manual)", text: $modelID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Toggle("Enable fallback", isOn: $fallbackEnabled)
                if fallbackEnabled {
                    Picker("Fallback provider", selection: $fallbackProviderID) {
                        Text("None").tag(nil as UUID?)
                        ForEach(providers) { provider in
                            Text(provider.displayName).tag(provider.id as UUID?)
                        }
                    }
                    TextField("Fallback Model ID (manual)", text: $fallbackModelID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Button("Save assignment") {
                    manager.setAssignment(
                        task: task,
                        providerID: providerID,
                        modelID: modelID,
                        fallbackProviderID: fallbackProviderID,
                        fallbackModelID: fallbackModelID,
                        fallbackEnabled: fallbackEnabled
                    )
                }
                .buttonStyle(.bordered)
            }
        }
        .onAppear {
            load()
        }
        .onChange(of: store.revision) { _, _ in load() }
    }

    private var icon: String {
        switch task {
        case .default: return "star.circle"
        case .chat: return "message"
        case .moodAnalysis: return "heart"
        case .insights: return "chart.xyaxis.line"
        case .appActions: return "wand.and.stars"
        }
    }

    private func load() {
        guard let assignment = manager.assignment(for: task) else {
            providerID = nil
            modelID = ""
            fallbackEnabled = false
            fallbackProviderID = nil
            fallbackModelID = ""
            return
        }
        providerID = assignment.providerID
        modelID = assignment.modelID
        fallbackEnabled = assignment.fallbackEnabled
        fallbackProviderID = assignment.fallbackProviderID
        fallbackModelID = assignment.fallbackModelID
    }
}
