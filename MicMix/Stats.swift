//
//  Stats.swift
//  MicMix
//
//  Persistent usage counters: dictation sessions, characters produced, and the
//  number of times the cleanup model changed the raw transcript.
//

import Combine
import Foundation

@MainActor
final class Stats: ObservableObject {
    static let shared = Stats()

    @Published private(set) var sessions: Int
    @Published private(set) var characters: Int
    @Published private(set) var corrections: Int

    private enum Keys {
        static let sessions = "stats.sessions"
        static let characters = "stats.characters"
        static let corrections = "stats.corrections"
    }

    private init() {
        let defaults = UserDefaults.standard
        sessions = defaults.integer(forKey: Keys.sessions)
        characters = defaults.integer(forKey: Keys.characters)
        corrections = defaults.integer(forKey: Keys.corrections)
    }

    /// Records one completed dictation. A "correction" is counted when the cleaned
    /// text differs from the raw transcript.
    func record(rawText: String, polishedText: String) {
        sessions += 1
        characters += polishedText.count
        let rawTrim = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        let polishedTrim = polishedText.trimmingCharacters(in: .whitespacesAndNewlines)
        if rawTrim != polishedTrim {
            corrections += 1
        }
        persist()
    }

    func reset() {
        sessions = 0
        characters = 0
        corrections = 0
        persist()
    }

    private func persist() {
        let defaults = UserDefaults.standard
        defaults.set(sessions, forKey: Keys.sessions)
        defaults.set(characters, forKey: Keys.characters)
        defaults.set(corrections, forKey: Keys.corrections)
    }
}
