//
//  TextPolisher.swift
//  MicMix
//
//  Cleans up dictated speech — adds punctuation, drops filler words, fixes obvious
//  recognition slips — while preserving meaning and the speaker's language.
//
//  Uses the remote API (OpenAI-compatible or Anthropic) configured in Settings when
//  selected, and otherwise Apple's on-device Foundation Models.
//

import FoundationModels
import Foundation

@MainActor
final class TextPolisher {
    func polish(_ raw: String) async -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let config = PolishConfig.current
        if config.engine == .remote, config.usesRemote,
           let remote = await Self.polishRemote(trimmed, config: config) {
            return remote
        }
        if SystemLanguageModel.default.availability == .available {
            return await Self.polishOnDevice(trimmed, prompt: config.prompt)
        }
        return trimmed
    }

    /// True when polishing can run at all — a remote API is configured, or the
    /// on-device model is available.
    static var isAvailable: Bool {
        let config = PolishConfig.current
        if config.engine == .remote, config.usesRemote { return true }
        return SystemLanguageModel.default.availability == .available
    }

    // MARK: - On-device (Foundation Models)

    private static func polishOnDevice(_ text: String, prompt: String) async -> String {
        let session = LanguageModelSession { prompt }
        do {
            let response = try await session.respond(to: text)
            return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return text
        }
    }

    // MARK: - Remote (OpenAI-compatible or Anthropic)

    private static func polishRemote(_ text: String, config: PolishConfig.Snapshot) async -> String? {
        do {
            let content = try await remoteRequest(text: text, systemPrompt: config.prompt, config: config)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return content.isEmpty ? nil : content
        } catch {
            return nil
        }
    }

    /// Sends a tiny round-trip and returns a human-readable success/failure line
    /// for the Settings "Test Connection" button.
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
