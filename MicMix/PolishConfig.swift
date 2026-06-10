//
//  PolishConfig.swift
//  MicMix
//
//  User-configurable settings for the cleanup step: the cleanup engine, the
//  optional remote model API, the output style and target language, and the
//  cleanup prompt. Persisted in UserDefaults.
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
        static let style = "polish.style"
        static let outputLanguage = "polish.outputLanguage"
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

    /// Output style applied to BOTH the cleaned Chinese and the English translation.
    enum Style: String, CaseIterable, Identifiable {
        case developer
        case casual
        case formal
        case concise

        var id: String { rawValue }

        var label: String {
            switch self {
            case .developer: return "Developer"
            case .casual:    return "Casual"
            case .formal:    return "Formal"
            case .concise:   return "Concise"
            }
        }

        /// Appended to the cleanup prompt at request time. Editable prompts in
        /// Settings don't need to include any placeholder — the style line is
        /// always added on top.
        var directive: String {
            switch self {
            case .developer:
                return "Style: developer. Use direct, technical, declarative phrasing. Keep all programming languages, libraries, frameworks, tools, file formats, and acronyms exactly as their original English names. No fluff, no marketing language."
            case .casual:
                return "Style: casual. Use natural, conversational phrasing as if chatting with a friend. Contractions are fine. Keep technical terms in English."
            case .formal:
                return "Style: formal. Use polite, professional phrasing suitable for business or formal writing. Complete sentences, no slang. Keep technical terms in English."
            case .concise:
                return "Style: concise. Tighten phrasing; drop redundancy while preserving every concrete piece of information. Keep technical terms in English."
            }
        }
    }

    /// Which language is actually typed at the cursor.
    enum OutputLanguage: String, CaseIterable, Identifiable {
        case chinese
        case english

        var id: String { rawValue }

        var label: String {
            switch self {
            case .chinese: return "中文 (Chinese)"
            case .english: return "English"
            }
        }
    }

    /// Default cleanup prompt — editable in Settings, restored from here on reset.
    /// The model MUST output two labeled lines so the UI can show both and the
    /// keystroke injector can pick either.
    static let defaultPrompt = """
    You clean up a raw Chinese dictation transcript AND produce a faithful English translation.

    Cleaning rules (the "CLEANED" line):
    - Preserve the speaker's meaning and primary language. Do NOT translate ordinary Chinese words on this line.
    - Add or fix punctuation and capitalization.
    - Remove filler words (um, uh, like, 那个, 就是, 然后那个).
    - Restore foreign terms that speech-to-text rendered as a phonetic transliteration (or mis-heard) to their correct original spelling. This applies to technical terms, programming languages, libraries and frameworks, product / brand / company names, file formats, and acronyms. Examples: 派森/拍森 → Python, 吉特哈勃 → GitHub, 多克 → Docker, 库伯内提斯 → Kubernetes, 瑞迪斯 → Redis, 杰森 → JSON, 诶屁艾 / A P I → API, 瑞爱克特 → React. Keep genuinely Chinese words in Chinese.
    - Fix other obvious speech-to-text mistakes only when the intended word is clear from context.
    - Do NOT summarize, rephrase, or add new content.

    Translation rules (the "ENGLISH" line):
    - Faithfully translate the CLEANED text into natural English. Preserve meaning, not literal word order.
    - Keep technical terms in English (Python, GitHub, Docker, JSON, API, …) — never localize them.
    - Apply the requested style (appended at the end of this prompt).

    Output EXACTLY this two-line format and NOTHING else (no preface, no quotes, no markdown, no extra lines):
    CLEANED: <cleaned Chinese text on a single line>
    ENGLISH: <natural English translation on a single line>
    """

    struct Snapshot {
        var engine: Engine
        var provider: Provider
        var baseURL: String
        var apiKey: String
        var model: String
        var prompt: String
        var style: Style
        var outputLanguage: OutputLanguage

        /// The system prompt actually sent to the model: the user-editable prompt
        /// with a style directive appended. Keeps the editable prompt clean.
        var fullSystemPrompt: String {
            prompt + "\n\n" + style.directive
        }

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

    /// The API key lives in the Keychain (platform convention for credentials).
    /// Reading migrates any legacy plaintext value out of UserDefaults once.
    static var storedAPIKey: String {
        if let value = KeychainStore.string(forKey: Keys.apiKey) {
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let defaults = UserDefaults.standard
        if let legacy = defaults.string(forKey: Keys.apiKey), !legacy.isEmpty {
            KeychainStore.set(legacy, forKey: Keys.apiKey)
            defaults.removeObject(forKey: Keys.apiKey)
            return legacy.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ""
    }

    static func setAPIKey(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            KeychainStore.delete(key: Keys.apiKey)
        } else {
            KeychainStore.set(trimmed, forKey: Keys.apiKey)
        }
    }

    /// Reads the current settings from UserDefaults (key from the Keychain),
    /// applying defaults.
    static var current: Snapshot {
        let defaults = UserDefaults.standard
        func trimmed(_ key: String) -> String {
            (defaults.string(forKey: key) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let storedPrompt = defaults.string(forKey: Keys.prompt)
        let engine = Engine(rawValue: defaults.string(forKey: Keys.engine) ?? "") ?? .onDevice
        let provider = Provider(rawValue: defaults.string(forKey: Keys.provider) ?? "") ?? .openai
        let style = Style(rawValue: defaults.string(forKey: Keys.style) ?? "") ?? .developer
        let outputLanguage = OutputLanguage(rawValue: defaults.string(forKey: Keys.outputLanguage) ?? "") ?? .chinese
        return Snapshot(
            engine: engine,
            provider: provider,
            baseURL: trimmed(Keys.baseURL),
            apiKey: storedAPIKey,
            model: trimmed(Keys.model),
            prompt: (storedPrompt?.isEmpty == false) ? storedPrompt! : defaultPrompt,
            style: style,
            outputLanguage: outputLanguage
        )
    }
}
