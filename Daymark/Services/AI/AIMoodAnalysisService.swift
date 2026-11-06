import Foundation

struct MoodAnalysisResult: Codable, Equatable {
    var mood: String
    var confidence: Double
    var tags: [String]
    var summary: String
}

enum AIMoodAnalysisService {
    static let allowedMoods = ["calm", "good", "great", "neutral", "low", "anxious", "tired", "overwhelmed", "grateful", "inspired"]

    static func analyze(text: String, using manager: AIProviderManager) async throws -> (result: MoodAnalysisResult, response: AIChatResponse) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AIError.responseParsingFailed("Mood analysis needs some text to analyze.")
        }
        guard let resolved = manager.resolvedConfiguration(for: .moodAnalysis) ?? manager.resolvedConfiguration(for: .chat) ?? manager.resolvedConfiguration(for: .default) else {
            throw AIError.noProviderConfigured(.moodAnalysis)
        }
        let instructions = """
        Return only a JSON object with these keys:
        - mood: one of \(allowedMoods.joined(separator: ", "))
        - confidence: a number from 0 to 1
        - tags: an array of short strings
        - summary: a short human-readable summary
        Do not include markdown fences or extra commentary.
        """
        let options = AIChatRequestOptions(
            temperature: 0.2,
            maxOutputTokens: 256,
            streaming: false,
            jsonMode: resolved.capability.supportsJSONMode,
            toolsEnabled: false,
            responseFormatInstructions: instructions
        )
        let response = try await manager.chat(task: resolved.usedFallback ? .moodAnalysis : .moodAnalysis, messages: [.user(trimmed)], options: options)
        let result = try validateMoodResponse(response.text)
        return (result, response)
    }

    static func validateMoodResponse(_ text: String) throws -> MoodAnalysisResult {
        let cleaned = stripJSONFences(text)
        guard let data = cleaned.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIError.responseParsingFailed("The model did not return valid JSON for mood analysis.")
        }
        let rawMood = (object["mood"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard allowedMoods.contains(rawMood) else {
            throw AIError.responseParsingFailed("Mood analysis returned an unsupported mood value: \(rawMood.isEmpty ? "empty" : rawMood).")
        }
        let confidence: Double
        if let number = object["confidence"] as? Double {
            confidence = number
        } else if let string = object["confidence"] as? String, let number = Double(string) {
            confidence = number
        } else {
            throw AIError.responseParsingFailed("Mood analysis confidence must be a number.")
        }
        guard confidence >= 0, confidence <= 1 else {
            throw AIError.responseParsingFailed("Mood analysis confidence must be between 0 and 1.")
        }
        let tags: [String]
        if let array = object["tags"] as? [String] {
            tags = array
        } else if let array = object["tags"] as? [Any] {
            tags = array.compactMap { $0 as? String }
        } else {
            tags = []
        }
        let summary = (object["summary"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return MoodAnalysisResult(mood: rawMood, confidence: confidence, tags: tags, summary: summary)
    }

    private static func stripJSONFences(_ text: String) -> String {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            cleaned = cleaned.replacingOccurrences(of: "```json", with: "")
            cleaned = cleaned.replacingOccurrences(of: "```", with: "")
            cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let start = cleaned.firstIndex(of: "{"), let end = cleaned.lastIndex(of: "}") {
            cleaned = String(cleaned[start...end])
        }
        return cleaned
    }
}
