//
//  TextPolisher.swift
//  MicMix
//
//  Cleans up a raw Chinese dictation transcript AND produces a faithful English
//  translation in a single model call, then parses the two-line output.
//
//  Uses the remote API (OpenAI-compatible or Anthropic) configured in Settings
//  when selected, and otherwise Apple's on-device Foundation Models.
//

import FoundationModels
import Foundation

/// Result of one polish round: the cleaned Chinese (line 1 in the panel) and
/// the English translation (line 2 in the panel).
struct PolishResult {
    let chinese: String
    let english: String

    static let empty = PolishResult(chinese: "", english: "")
}

@MainActor
final class TextPolisher {
    func polish(_ raw: String) async -> PolishResult {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }

        let config = PolishConfig.current
        if config.engine == .remote, config.usesRemote,
           let remote = await Self.polishRemote(trimmed, config: config) {
            return remote
        }
        if SystemLanguageModel.default.availability == .available {
            return await Self.polishOnDevice(trimmed, systemPrompt: config.fullSystemPrompt)
        }
        // No polishing engine available — pass the raw text through as the
        // cleaned line; English is left empty.
        return PolishResult(chinese: trimmed, english: "")
    }

    /// True when polishing can run at all — a remote API is configured, or the
    /// on-device model is available.
    static var isAvailable: Bool {
        let config = PolishConfig.current
        if config.engine == .remote, config.usesRemote { return true }
        return SystemLanguageModel.default.availability == .available
    }

    // MARK: - On-device (Foundation Models)

    private static func polishOnDevice(_ text: String, systemPrompt: String) async -> PolishResult {
        let session = LanguageModelSession { systemPrompt }
        do {
            let response = try await session.respond(to: text)
            return parseDual(response.content, fallback: text)
        } catch {
            return PolishResult(chinese: text, english: "")
        }
    }

    // MARK: - Remote (OpenAI-compatible or Anthropic)

    private static func polishRemote(_ text: String, config: PolishConfig.Snapshot) async -> PolishResult? {
        do {
            let content = try await remoteRequest(
                text: text,
                systemPrompt: config.fullSystemPrompt,
                config: config
            )
            return parseDual(content, fallback: text)
        } catch {
            return nil
        }
    }

    /// Sends a tiny round-trip and returns a human-readable success/failure line
    /// for the Settings "Test Connection" button. Uses a minimal system prompt
    /// — not the cleanup prompt — so it doesn't have to match the dual format.
    static func testConnection(config: PolishConfig.Snapshot) async -> String {
        guard config.usesRemote else {
            return "✗ Fill in Base URL, API Key, and Model first."
        }
        do {
            let reply = try await remoteRequest(
                text: "Reply with exactly: OK",
                systemPrompt: "You are a connection test.",
                config: config
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            return "✓ Connected — \(config.model) replied: \(reply.prefix(60))"
        } catch {
            return "✗ \(error.localizedDescription)"
        }
    }

    // MARK: - Output parsing

    /// Parses the model's "CLEANED: …\nENGLISH: …" output. Tolerates extra blank
    /// lines, multi-line values, leading bullets/quotes, and lower-case labels.
    /// Falls back to treating the whole output as the cleaned line when neither
    /// label is found.
    static func parseDual(_ text: String, fallback: String) -> PolishResult {
        var chineseLines: [String] = []
        var englishLines: [String] = []
        var section: Section = .none

        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if let value = strip(prefix: "CLEANED:", from: line) {
                section = .chinese
                if !value.isEmpty { chineseLines.append(value) }
            } else if let value = strip(prefix: "ENGLISH:", from: line) {
                section = .english
                if !value.isEmpty { englishLines.append(value) }
            } else {
                switch section {
                case .chinese: chineseLines.append(line)
                case .english: englishLines.append(line)
                case .none:    break
                }
            }
        }

        let zh = chineseLines.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        let en = englishLines.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)

        if zh.isEmpty && en.isEmpty {
            // Model ignored the format. Treat the whole reply as the cleaned text.
            let whole = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return PolishResult(chinese: whole.isEmpty ? fallback : whole, english: "")
        }
        return PolishResult(chinese: zh.isEmpty ? fallback : zh, english: en)
    }

    private enum Section { case none, chinese, english }

    /// If `line` begins with `prefix` (case-insensitive, optionally after a
    /// quote/bullet), returns the trimmed value after the colon. Otherwise nil.
    private static func strip(prefix: String, from line: String) -> String? {
        let stripped = line.drop(while: { "*-•>「" .contains($0) || $0.isWhitespace })
        let lower = stripped.lowercased()
        guard lower.hasPrefix(prefix.lowercased()) else { return nil }
        let after = stripped.dropFirst(prefix.count)
        return after.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Remote request plumbing

    private struct RemoteError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private static func remoteRequest(text: String,
                                      systemPrompt: String,
                                      config: PolishConfig.Snapshot) async throws -> String {
        guard let url = config.endpointURL else { throw RemoteError(message: "Invalid Base URL") }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        switch config.provider {
        case .openai:
            request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
            request.httpBody = try JSONEncoder().encode(OpenAIRequest(
                model: config.model,
                messages: [
                    OpenAIRequest.Message(role: "system", content: systemPrompt),
                    OpenAIRequest.Message(role: "user", content: text),
                ],
                temperature: 0.2,
                stream: false
            ))
        case .anthropic:
            request.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            request.httpBody = try JSONEncoder().encode(AnthropicRequest(
                model: config.model,
                max_tokens: 4096,
                system: systemPrompt,
                messages: [AnthropicRequest.Message(role: "user", content: text)]
            ))
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw RemoteError(message: "No HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let detail = (String(data: data, encoding: .utf8) ?? "").prefix(200)
            throw RemoteError(message: "HTTP \(http.statusCode): \(detail)")
        }

        switch config.provider {
        case .openai:
            let decoded = try JSONDecoder().decode(OpenAIResponse.self, from: data)
            guard let content = decoded.choices.first?.message.content else {
                throw RemoteError(message: "Empty response")
            }
            return content
        case .anthropic:
            let decoded = try JSONDecoder().decode(AnthropicResponse.self, from: data)
            guard let content = decoded.content.first(where: { $0.type == "text" })?.text else {
                throw RemoteError(message: "Empty response")
            }
            return content
        }
    }
}

private struct OpenAIRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }
    let model: String
    let messages: [Message]
    let temperature: Double
    let stream: Bool
}

private struct OpenAIResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable { let content: String }
        let message: Message
    }
    let choices: [Choice]
}

private struct AnthropicRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }
    let model: String
    let max_tokens: Int
    let system: String
    let messages: [Message]
}

private struct AnthropicResponse: Decodable {
    struct Block: Decodable {
        let type: String
        let text: String?
    }
    let content: [Block]
}
