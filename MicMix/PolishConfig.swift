//
//  PolishConfig.swift
//  MicMix
//
//  User-configurable settings for the cleanup step: an optional OpenAI-compatible
//  model API and the cleanup prompt. Persisted in UserDefaults.
//

import Foundation

enum PolishConfig {
    enum Keys {
        static let baseURL = "polish.baseURL"
        static let apiKey = "polish.apiKey"
        static let model = "polish.model"
        static let prompt = "polish.prompt"
        static let engine = "polish.engine"
        static let provider = "polish.provider"
        static let dictationLocale = "dictation.locale"
    }

    /// Remote API wire format.
    enum Provider: String, CaseIterable, Identifiable {
        case openai
        case anthropic

        var id: String { rawValue }
        var label: String { self == .anthropic ? "Anthropic" : "OpenAI-compatible" }
        var defaultBaseURL: String {
            self == .anthropic ? "https://api.anthropic.com" : "https://api.openai.com/v1"
        }
        var modelPlaceholder: String {
            self == .anthropic ? "claude-sonnet-4-6" : "gpt-4o-mini"
        }
    }

    /// Which model backs the cleanup step.
    enum Engine: String, CaseIterable, Identifiable {
        case onDevice
        case remote

        var id: String { rawValue }

        var label: String {
            switch self {
            case .onDevice: return "On-device (Apple)"
            case .remote: return "Remote API"
            }
        }
    }

    /// Default cleanup prompt — editable in Settings, restored from here on reset.
    static let defaultPrompt = """
    You clean up raw dictation transcripts. Rules:
    - Preserve meaning and the speaker's original language exactly.
    - Add or fix punctuation and capitalization.
    - Remove filler words (um, uh, like, you know, 那个, 就是, 然后那个).
    - Fix obvious speech-to-text mistakes only when the intended word is clear in context.
    - Do NOT translate, summarize, rephrase for style, or add new content.
    - Output ONLY the cleaned text, no preface, no quotes, no commentary.
    """

    struct Snapshot {
        var engine: Engine
        var provider: Provider
        var baseURL: String
        var apiKey: String
        var model: String
        var prompt: String

        /// Remote API is used only when all three connection fields are filled in.
        var usesRemote: Bool {
            !baseURL.isEmpty && !apiKey.isEmpty && !model.isEmpty
        }

        /// Resolves the request endpoint from the base URL, per provider.
        var endpointURL: URL? {
            var base = baseURL
            while base.hasSuffix("/") { base.removeLast() }
            guard !base.isEmpty else { return nil }
            switch provider {
            case .openai:
                if base.hasSuffix("/chat/completions") { return URL(string: base) }
                return URL(string: base + "/chat/completions")
            case .anthropic:
                if base.hasSuffix("/messages") { return URL(string: base) }
                if base.hasSuffix("/v1") { return URL(string: base + "/messages") }
                return URL(string: base + "/v1/messages")
            }
        }
    }

    /// Reads the current settings from UserDefaults, applying defaults.
    static var current: Snapshot {
        let defaults = UserDefaults.standard
        func trimmed(_ key: String) -> String {
            (defaults.string(forKey: key) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let storedPrompt = defaults.string(forKey: Keys.prompt)
        let engine = Engine(rawValue: defaults.string(forKey: Keys.engine) ?? "") ?? .onDevice
        let provider = Provider(rawValue: defaults.string(forKey: Keys.provider) ?? "") ?? .openai
        return Snapshot(
            engine: engine,
            provider: provider,
            baseURL: trimmed(Keys.baseURL),
            apiKey: trimmed(Keys.apiKey),
            model: trimmed(Keys.model),
            prompt: (storedPrompt?.isEmpty == false) ? storedPrompt! : defaultPrompt
        )
    }
}
