import SwiftUI

/// Chat UI for the user-configured AI providers. Uses the Chat task route;
/// never silently falls back — the UI shows which provider/model answered.
struct AIChatView: View {
    @Environment(DaymarkStore.self) private var store
    @State private var draft = ""
    @State private var messages: [AIChatMessage] = []
    @State private var isSending = false
    @State private var errorMessage: String?

    private var manager: AIProviderManager { store.ai }
    private var resolved: AIResolvedConfiguration? { manager.resolvedConfiguration(for: .chat) }
    private var hasProvider: Bool { resolved != nil && manager.enabledConfigurations.contains { $0.id == resolved?.provider.id } }

    var body: some View {
        VStack(spacing: 0) {
            if let info = routingBanner {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                    Text(info)
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(.ultraThinMaterial)
            }
            if messages.isEmpty {
                emptyState
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(messages) { message in
                                AIChatBubble(message: message)
                                    .id(message.id)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                    }
                    .onChange(of: messages.count) { _, _ in
                        if let last = messages.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }
            }
            if let errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(errorMessage).font(.caption)
                    Spacer()
                    Button("Dismiss") { self.errorMessage = nil }
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(.red)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Color.red.opacity(0.08))
            }
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Message Daymark AI…", text: $draft, axis: .vertical)
                    .textInputAutocapitalization(.sentences)
                    .autocorrectionDisabled()
                    .padding(12)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
                    .disabled(isSending)
                Button {
                    send()
                } label: {
                    if isSending {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.up.circle.fill").font(.title2)
                    }
                }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
        }
        .navigationTitle("AI Chat")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var routingBanner: String? {
        guard let resolved else {
            return "No provider assigned to AI Chat. Add one in Settings → Daymark AI → Providers."
        }
        let fallback = manager.fallbackConfiguration(for: .chat)
        if let fallback {
            return "Chat → \(resolved.provider.displayName) · \(resolved.modelID) (fallback: \(fallback.provider.displayName) · \(fallback.modelID))"
        }
        return "Chat → \(resolved.provider.displayName) · \(resolved.modelID)"
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Spacer()
            Image(systemName: "message").font(.system(size: 36)).foregroundStyle(Palette.accent)
            Text("Daymark AI Chat").font(.title3.weight(.bold))
            Text(hasProvider
                ? "Ask anything. Responses come from your configured \(resolved?.provider.displayName ?? "provider") (model \(resolved?.modelID ?? "—")). Daymark only sends data when you send a message."
                : "Daymark works offline without AI. Add a provider to enable chat — your Base URL, API key and Model ID stay on this device (key in Keychain).")
                .font(.subheadline).foregroundStyle(.secondary)
            if !hasProvider {
                NavigationLink {
                    AIProvidersView()
                } label: {
                    Label("Open provider settings", systemImage: "cpu").font(.subheadline.weight(.medium))
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(24)
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        draft = ""
        errorMessage = nil
        messages.append(AIChatMessage(role: .user, text: text))
        isSending = true
        Task {
            let history = messages.map { AIChatMessage(role: $0.role, text: $0.text) }
            // Build AIMessage history from our local messages
            let apiMessages: [AIMessage] = history.map { msg in
                AIMessage(role: msg.role.rawValue, content: msg.text)
            }
            do {
                let response = try await manager.chat(task: .chat, messages: apiMessages, options: AIChatRequestOptions())
                messages.append(AIChatMessage(
                    role: .assistant,
                    text: response.text,
                    providerName: response.providerDisplayName,
                    modelID: response.modelID,
                    usedFallback: response.usedFallback
                ))
            } catch {
                errorMessage = (error as NSError).localizedDescription
                if let aiError = error as? AIError {
                    errorMessage = aiError.errorDescription ?? "\(aiError)"
                }
            }
            isSending = false
        }
    }
}

struct AIChatMessage: Identifiable {
    let id = UUID()
    var role: Role
    var text: String
    var providerName: String?
    var modelID: String?
    var usedFallback: Bool = false

    enum Role: String {
        case user, assistant
    }
}

private struct AIChatBubble: View {
    let message: AIChatMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(message.text)
                .font(.subheadline)
                .foregroundStyle(message.role == .user ? .white : .primary)
            if let providerName = message.providerName, let modelID = message.modelID {
                Text("\(providerName) · \(modelID)\(message.usedFallback ? " · fallback" : "")")
                    .font(.caption2)
                    .foregroundStyle(message.role == .user ? .white.opacity(0.8) : .secondary)
            }
        }
        .padding(12)
        .background(message.role == .user ? Palette.accent : Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }
}
