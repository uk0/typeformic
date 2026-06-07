//
//  TextPolisher.swift
//  MicMix
//
//  Cleans up dictated speech — adds punctuation, drops filler words, fixes obvious
//  recognition slips — while preserving meaning and the speaker's language.
//
//  Uses the OpenAI-compatible API configured in Settings when available, and falls
//  back to Apple's on-device Foundation Models otherwise.
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

    // MARK: - Remote (OpenAI-compatible chat completions)

    private static func polishRemote(_ text: String, config: PolishConfig.Snapshot) async -> String? {
        guard let url = config.chatCompletionsURL else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")

        let payload = ChatRequest(
            model: config.model,
            messages: [
                ChatRequest.Message(role: "system", content: config.prompt),
                ChatRequest.Message(role: "user", content: text),
            ],
            temperature: 0.2,
            stream: false
        )
        guard let body = try? JSONEncoder().encode(payload) else { return nil }
        request.httpBody = body

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
            let content = (decoded.choices.first?.message.content ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return content.isEmpty ? nil : content
        } catch {
            return nil
        }
    }
}

private struct ChatRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }
    let model: String
    let messages: [Message]
    let temperature: Double
    let stream: Bool
}

private struct ChatResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable { let content: String }
        let message: Message
    }
    let choices: [Choice]
}
