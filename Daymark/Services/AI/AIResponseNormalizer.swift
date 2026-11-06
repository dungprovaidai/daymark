import Foundation

enum AIResponseNormalizer {
    static func normalize(
        data: Data,
        response: URLResponse?,
        protocolType: AIProtocolType,
        modelID: String,
        providerDisplayName: String,
        usedFallback: Bool = false
    ) throws -> AIChatResponse {
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw AIError.httpError(http.statusCode, sanitized(body))
        }
        let text: String
        switch protocolType {
        case .openAICompatible:
            text = try openAIText(from: data)
        case .geminiNative:
            text = try geminiText(from: data)
        case .customAdapter:
            text = try customText(from: data)
        }
        return AIChatResponse(
            text: text,
            modelID: modelID,
            providerDisplayName: providerDisplayName,
            usedFallback: usedFallback,
            rawStatusCode: (response as? HTTPURLResponse)?.statusCode ?? 0
        )
    }

    static func openAIText(from data: Data) throws -> String {
        let string = String(data: data, encoding: .utf8) ?? ""
        if string.contains("data: ") || string.contains("\ndata:") {
            let streamed = openAIStreamText(from: string)
            if !streamed.isEmpty { return streamed }
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIError.responseParsingFailed(sanitized(string))
        }
        if let choices = object["choices"] as? [[String: Any]],
           let first = choices.first {
            if let message = first["message"] as? [String: Any], let content = message["content"] as? String {
                return content
            }
            if let delta = first["delta"] as? [String: Any], let content = delta["content"] as? String {
                return content
            }
            if let text = first["text"] as? String { return text }
        }
        if let text = object["text"] as? String { return text }
        throw AIError.responseParsingFailed("No message content was found in the OpenAI-compatible response.")
    }

    static func geminiText(from data: Data) throws -> String {
        let string = String(data: data, encoding: .utf8) ?? ""
        if string.contains("data: ") || string.contains("\ndata:") {
            let streamed = geminiStreamText(from: string)
            if !streamed.isEmpty { return streamed }
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = object["candidates"] as? [[String: Any]],
              let first = candidates.first,
              let content = first["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]] else {
            throw AIError.responseParsingFailed("No candidate text was found in the Gemini response.")
        }
        return parts.compactMap { $0["text"] as? String }.joined(separator: "\n")
    }

    static func customText(from data: Data, path: String? = nil) throws -> String {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIError.responseParsingFailed("The custom adapter expected JSON.")
        }
        if let path, !path.isEmpty, let value = value(at: path, in: object) as? String {
            return value
        }
        if let value = value(at: "choices.0.message.content", in: object) as? String { return value }
        if let value = value(at: "candidates.0.content.parts.0.text", in: object) as? String { return value }
        if let value = value(at: "text", in: object) as? String { return value }
        if let value = value(at: "message", in: object) as? String { return value }
        if let value = value(at: "content", in: object) as? String { return value }
        throw AIError.responseParsingFailed("No text was found at the configured custom response path.")
    }

    static func value(at path: String, in object: [String: Any]) -> Any? {
        var current: Any = object
        for component in path.split(separator: ".", omittingEmptySubsequences: true) {
            if let dictionary = current as? [String: Any] {
                current = dictionary[String(component)] as Any
            } else if let array = current as? [Any], let index = Int(component), array.indices.contains(index) {
                current = array[index]
            } else {
                return nil
            }
            if current is NSNull { return nil }
        }
        return current
    }

    private static func openAIStreamText(from string: String) -> String {
        var result = ""
        for line in string.components(separatedBy: .newlines) where line.hasPrefix("data:") {
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            guard payload != "[DONE]", let data = payload.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = object["choices"] as? [[String: Any]],
                  let first = choices.first,
                  let delta = first["delta"] as? [String: Any],
                  let content = delta["content"] as? String else { continue }
            result += content
        }
        return result
    }

    private static func geminiStreamText(from string: String) -> String {
        var result = ""
        for line in string.components(separatedBy: .newlines) where line.hasPrefix("data:") {
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            guard let data = payload.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let candidates = object["candidates"] as? [[String: Any]],
                  let first = candidates.first,
                  let content = first["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]] else { continue }
            result += parts.compactMap { $0["text"] as? String }.joined()
        }
        return result
    }

    private static func sanitized(_ text: String) -> String {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty { return "Empty response body." }
        return String(clean.prefix(500))
    }
}

enum AIModelDiscoveryParser {
    static func openAI(from data: Data) throws -> [AIModelInfo] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = object["data"] as? [[String: Any]] else {
            throw AIError.responseParsingFailed("Model discovery did not return an OpenAI-compatible model list.")
        }
        return items.compactMap { item in
            guard let id = item["id"] as? String, !id.isEmpty else { return nil }
            return AIModelInfo(
                id: id,
                displayName: id,
                ownedBy: item["owned_by"] as? String,
                createdAt: (item["created"] as? Double).map { Date(timeIntervalSince1970: $0) },
                source: "discovered",
                capability: AIModelCapability()
            )
        }
    }

    static func gemini(from data: Data) throws -> [AIModelInfo] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = object["models"] as? [[String: Any]] else {
            throw AIError.responseParsingFailed("Model discovery did not return a Gemini model list.")
        }
        return items.compactMap { item in
            guard let name = item["name"] as? String, !name.isEmpty else { return nil }
            let id = name.hasPrefix("models/") ? String(name.dropFirst("models/".count)) : name
            return AIModelInfo(
                id: id,
                displayName: item["displayName"] as? String ?? id,
                ownedBy: "Google",
                createdAt: nil,
                source: "discovered",
                capability: AIModelCapability()
            )
        }
    }
}
