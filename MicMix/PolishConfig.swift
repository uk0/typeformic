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
        var baseURL: String
        var apiKey: String
        var model: String
        var prompt: String

        /// Remote API is used only when all three connection fields are filled in.
        var usesRemote: Bool {
            !baseURL.isEmpty && !apiKey.isEmpty && !model.isEmpty
        }

        /// Resolves the chat-completions endpoint from the configured base URL.
        var chatCompletionsURL: URL? {
            var base = baseURL
            while base.hasSuffix("/") { base.removeLast() }
            guard !base.isEmpty else { return nil }
            if base.hasSuffix("/chat/completions") { return URL(string: base) }
            return URL(string: base + "/chat/completions")
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
        return Snapshot(
            engine: engine,
            baseURL: trimmed(Keys.baseURL),
            apiKey: trimmed(Keys.apiKey),
            model: trimmed(Keys.model),
            prompt: (storedPrompt?.isEmpty == false) ? storedPrompt! : defaultPrompt
        )
    }
}
