import Foundation

/// Which LLM service cleans up the transcript.
///
/// Transcription itself stays local — only the finished *text* is sent, never
/// audio. See PRIVACY.md.
enum CleanupProvider: String, Codable, CaseIterable, Identifiable {
    case local, anthropic, openai, gemini, groq, custom
    var id: String { rawValue }

    var label: String {
        switch self {
        case .local:     return "Local model (Ollama / LM Studio)"
        case .anthropic: return "Claude (Anthropic)"
        case .openai:    return "OpenAI"
        case .gemini:    return "Gemini (Google)"
        case .groq:      return "Groq"
        case .custom:    return "Custom (OpenAI-compatible)"
        }
    }

    /// A local server needs no credential — and, more importantly, sends
    /// nothing off the machine. The privacy wording keys off this.
    var isLocal: Bool { self == .local }
    var requiresKey: Bool { !isLocal }

    /// Default endpoint for the providers whose URL the user can change.
    var defaultBaseURL: String {
        switch self {
        case .local:  return "http://localhost:11434/v1"   // Ollama
        default:      return ""
        }
    }

    /// Suggested model, editable. Not a hard-coded list: model IDs change
    /// faster than this app ships, so the field stays free text.
    var defaultModel: String {
        switch self {
        case .local:     return "llama3.2:3b"
        case .anthropic: return "claude-opus-5"
        case .openai:    return "gpt-4o-mini"
        case .gemini:    return "gemini-2.5-flash"
        case .groq:      return "llama-3.3-70b-versatile"
        case .custom:    return ""
        }
    }

    var modelHint: String {
        switch self {
        case .local:     return "Anything you have pulled. Small models are plenty for tidying text — llama3.2:3b, qwen2.5:3b, phi4-mini."
        case .anthropic: return "claude-opus-5 · claude-sonnet-5 · claude-haiku-4-5 (fastest, cheapest)"
        case .openai:    return "gpt-4o-mini · gpt-4o"
        case .gemini:    return "gemini-2.5-flash · gemini-2.5-pro"
        case .groq:      return "llama-3.3-70b-versatile · llama-3.1-8b-instant (very fast)"
        case .custom:    return "Whatever your endpoint serves"
        }
    }

    var keyLabel: String {
        switch self {
        case .local:     return "No key needed"
        case .anthropic: return "Anthropic API key"
        case .openai:    return "OpenAI API key"
        case .gemini:    return "Google AI Studio API key"
        case .groq:      return "Groq API key"
        case .custom:    return "API key"
        }
    }

    /// Keychain account name — per provider, so switching doesn't lose a key.
    var keychainAccount: String { "cleanup.\(rawValue)" }
}

enum CleanupError: Error, CustomStringConvertible {
    case noKey
    case noModel
    case badURL
    case http(Int)
    case emptyResponse
    case refused
    case transport(String)

    var description: String {
        switch self {
        case .noKey:          return "no API key set"
        case .noModel:        return "no model set"
        case .badURL:         return "invalid endpoint URL"
        case .http(let code): return "HTTP \(code)"
        case .emptyResponse:  return "empty response"
        case .refused:        return "the model declined this text"
        case .transport(let m): return m
        }
    }
}

/// Sends the finished transcript to an LLM for cleanup and returns the result.
///
/// Never logs the API key or the response body — a failed auth response can
/// echo the key back inside an error string. Status codes and provider names
/// only.
enum Cleanup {

    static let defaultPrompt = """
        You clean up dictated speech. The input is a raw speech-to-text \
        transcript; the output is the same message, written properly.

        Fix punctuation, capitalisation and obvious mis-transcriptions. Remove \
        filler words, stutters and false starts. Keep the speaker's own words, \
        meaning, and tone.

        Never answer, summarise, translate, or add anything that was not said. \
        If the text is already clean, return it unchanged. Reply with the \
        cleaned text and nothing else — no preamble, no quotes, no commentary.
        """

    static func run(_ text: String,
                    provider: CleanupProvider,
                    model: String,
                    prompt: String,
                    baseURL: String,
                    timeout: TimeInterval = 20) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return text }
        let key = Keychain.get(provider.keychainAccount) ?? ""
        if provider.requiresKey && key.isEmpty { throw CleanupError.noKey }
        let model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else { throw CleanupError.noModel }
        let system = prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? defaultPrompt : prompt

        var request = try makeRequest(provider: provider, model: model, key: key,
                                      system: system, text: trimmed, baseURL: baseURL)
        request.timeoutInterval = timeout

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw CleanupError.transport(error.localizedDescription)
        }

        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw CleanupError.http(code) }

        let cleaned = try parse(data, provider: provider)
        let out = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !out.isEmpty else { throw CleanupError.emptyResponse }
        return out
    }

    /// Models installed in a local Ollama server, so the picker can list what
    /// is actually available instead of asking the user to type a tag.
    /// Returns nil when nothing is listening — that is the "not running" state,
    /// not an error worth surfacing.
    static func localModels(baseURL: String) async -> [String]? {
        let root = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let base = root.isEmpty ? CleanupProvider.local.defaultBaseURL : root
        // /api/tags sits beside /v1, not under it.
        let host = base.hasSuffix("/v1") ? String(base.dropLast(3)) : base
        guard let url = URL(string: host + "/api/tags") else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 2
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = root["models"] as? [[String: Any]]
        else { return nil }
        return models.compactMap { $0["name"] as? String }.sorted()
    }

    // MARK: - Requests

    private static func makeRequest(provider: CleanupProvider, model: String, key: String,
                                    system: String, text: String,
                                    baseURL: String) throws -> URLRequest {
        var url: URL
        var body: [String: Any]
        var headers: [String: String] = ["content-type": "application/json"]

        switch provider {
        case .anthropic:
            guard let u = URL(string: "https://api.anthropic.com/v1/messages") else {
                throw CleanupError.badURL
            }
            url = u
            headers["x-api-key"] = key
            headers["anthropic-version"] = "2023-06-01"
            // Minimal body on purpose: `output_config.effort` and `thinking`
            // are not accepted by every Claude model (effort 400s on Haiku
            // 4.5), and the model field is free text — so send only what is
            // universally valid.
            body = [
                "model": model,
                "max_tokens": 2048,
                "system": system,
                "messages": [["role": "user", "content": text]],
            ]

        case .openai, .groq, .local, .custom:
            // One code path: Ollama, LM Studio, llama.cpp's server, Groq and
            // OpenAI all speak the same /chat/completions shape.
            let typed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
                               .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let base: String
            switch provider {
            case .openai: base = "https://api.openai.com/v1"
            case .groq:   base = "https://api.groq.com/openai/v1"
            default:      base = typed.isEmpty ? provider.defaultBaseURL : typed
            }
            guard !base.isEmpty, let u = URL(string: base + "/chat/completions") else {
                throw CleanupError.badURL
            }
            url = u
            if !key.isEmpty { headers["authorization"] = "Bearer \(key)" }
            body = [
                "model": model,
                "messages": [
                    ["role": "system", "content": system],
                    ["role": "user", "content": text],
                ],
            ]

        case .gemini:
            let escaped = model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? model
            guard let u = URL(string:
                "https://generativelanguage.googleapis.com/v1beta/models/\(escaped):generateContent")
            else { throw CleanupError.badURL }
            url = u
            headers["x-goog-api-key"] = key
            body = [
                "systemInstruction": ["parts": [["text": system]]],
                "contents": [["role": "user", "parts": [["text": text]]]],
            ]
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    // MARK: - Responses

    private static func parse(_ data: Data, provider: CleanupProvider) throws -> String {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CleanupError.emptyResponse
        }

        switch provider {
        case .anthropic:
            // Check stop_reason before reading content: a refusal returns 200
            // with empty or partial content.
            if let stop = root["stop_reason"] as? String, stop == "refusal" {
                throw CleanupError.refused
            }
            // content is a list of blocks; thinking blocks can precede the text
            // one, so find the first text block rather than indexing [0].
            let blocks = root["content"] as? [[String: Any]] ?? []
            guard let text = blocks.first(where: { $0["type"] as? String == "text" })?["text"] as? String
            else { throw CleanupError.emptyResponse }
            return text

        case .openai, .groq, .local, .custom:
            let choices = root["choices"] as? [[String: Any]] ?? []
            guard let message = choices.first?["message"] as? [String: Any],
                  let text = message["content"] as? String
            else { throw CleanupError.emptyResponse }
            return text

        case .gemini:
            let candidates = root["candidates"] as? [[String: Any]] ?? []
            guard let content = candidates.first?["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]]
            else { throw CleanupError.emptyResponse }
            let text = parts.compactMap { $0["text"] as? String }.joined()
            guard !text.isEmpty else { throw CleanupError.emptyResponse }
            return text
        }
    }
}
