//
//  AmbientListener.swift
//  MicMix
//
//  Optional always-on, on-device listener with two jobs:
//  1. Hear one of the user's configured names being called nearby (useful with
//     headphones on) and surface a notification with sound.
//  2. Hear a wake phrase and start hands-free dictation.
//
//  Audio is processed entirely on-device by SpeechTranscriber; nothing is
//  recorded or sent anywhere. Off by default — explicit opt-in in Settings.
//

@preconcurrency import AVFoundation
import Combine
import Foundation
import os
import Speech

@MainActor
final class AmbientListener: ObservableObject {
    enum Keys {
        static let enabled = "ambient.enabled"
        static let names = "ambient.names"
        static let wakePhrase = "ambient.wakePhrase"
    }

    @Published private(set) var isListening = false

    /// Someone nearby said one of the configured names.
    var onNameHeard: ((_ name: String, _ sentence: String) -> Void)?
    /// The wake phrase was heard.
    var onWakePhrase: (() -> Void)?

    private let audioEngine = AVAudioEngine()
    private var analyzer: SpeechAnalyzer?
    private var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var suspended = false
    private var lastNameTrigger = Date.distantPast
    private var lastWakeTrigger = Date.distantPast
    private static let cooldown: TimeInterval = 10

    private nonisolated static let log = Logger(subsystem: "me.firsh.MicMix", category: "ambient")

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: Keys.enabled) }

    // MARK: - Lifecycle

    /// Reconciles the engine with the Settings toggle. Idempotent.
    func syncWithConfig() {
        if Self.isEnabled, !suspended {
            startIfNeeded()
        } else if isListening {
            stopEngine()
        }
    }

    /// Temporarily releases the microphone (dictation is about to use it).
    func suspend() {
        suspended = true
        if isListening { stopEngine() }
    }

    /// Re-acquires the microphone after dictation finished, if enabled.
    func resume() {
        suspended = false
        syncWithConfig()
    }

    private func startIfNeeded() {
        guard !isListening else { return }
        isListening = true
        Task { [weak self] in
            await self?.begin()
        }
    }

    private func begin() async {
        guard await MicTranscriber.requestAuthorization() else {
            isListening = false
            return
        }
        do {
            let locale = await MicTranscriber.preferredSupportedLocale()
            let transcriber = SpeechTranscriber(
                locale: locale,
                transcriptionOptions: [],
                reportingOptions: [.volatileResults],
                attributeOptions: []
            )
            _ = try await MicTranscriber.ensureAssets(for: transcriber)

            let analyzer = SpeechAnalyzer(modules: [transcriber])
            self.analyzer = analyzer

            let (stream, builder) = AsyncStream<AnalyzerInput>.makeStream()
            self.inputBuilder = builder

            let input = audioEngine.inputNode
            let inputFormat = input.outputFormat(forBus: 0)
            let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
                ?? AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                 sampleRate: 16_000,
                                 channels: 1,
                                 interleaved: false)!
            let converter: AVAudioConverter? = (inputFormat == analyzerFormat)
                ? nil
                : AVAudioConverter(from: inputFormat, to: analyzerFormat)
            converter?.primeMethod = .none

            input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { buffer, _ in
                let payload: AVAudioPCMBuffer
                if let converter {
                    guard let converted = MicTranscriber.convert(buffer: buffer, using: converter, to: analyzerFormat) else { return }
                    payload = converted
                } else {
                    payload = buffer
                }
                builder.yield(AnalyzerInput(buffer: payload))
            }

            resultsTask = Task { [weak self] in
                guard let self else { return }
                do {
                    for try await result in transcriber.results {
                        self.inspect(text: String(result.text.characters))
                    }
                } catch {
                    Self.log.notice("ambient results error: \(error.localizedDescription, privacy: .public)")
                }
                self.handleStreamEnd()
            }

            audioEngine.prepare()
            try audioEngine.start()
            try await analyzer.start(inputSequence: stream)
            Self.log.notice("ambient listening started (\(locale.identifier, privacy: .public))")
        } catch {
            Self.log.notice("ambient start failed: \(error.localizedDescription, privacy: .public)")
            isListening = false
            scheduleRetry()
        }
    }

    private func stopEngine() {
        isListening = false
        retryTask?.cancel()
        retryTask = nil
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        inputBuilder?.finish()
        inputBuilder = nil
        resultsTask = nil
        let analyzer = self.analyzer
        self.analyzer = nil
        Task { try? await analyzer?.finalizeAndFinishThroughEndOfInput() }
        Self.log.notice("ambient listening stopped")
    }

    /// The results stream ended on its own (error, device change, system sleep).
    /// Tear down and retry while the feature is still wanted.
    private func handleStreamEnd() {
        guard isListening else { return }
        isListening = false
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        inputBuilder?.finish()
        inputBuilder = nil
        analyzer = nil
        scheduleRetry()
    }

    private func scheduleRetry() {
        guard Self.isEnabled, !suspended else { return }
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            guard !Task.isCancelled else { return }
            self?.syncWithConfig()
        }
    }

    // MARK: - Matching

    private func inspect(text: String) {
        let normalized = Self.normalize(text)
        guard !normalized.isEmpty else { return }
        let now = Date()

        if now.timeIntervalSince(lastNameTrigger) > Self.cooldown,
           let hit = Self.triggerNames.first(where: { normalized.contains($0.norm) }) {
            lastNameTrigger = now
            onNameHeard?(hit.display, text)
        }

        let wake = Self.wakePhrase
        if !wake.isEmpty,
           now.timeIntervalSince(lastWakeTrigger) > Self.cooldown,
           normalized.contains(wake) {
            lastWakeTrigger = now
            onWakePhrase?()
        }
    }

    private static var triggerNames: [(display: String, norm: String)] {
        (UserDefaults.standard.string(forKey: Keys.names) ?? "")
            .split(whereSeparator: { $0 == "," || $0 == "，" })
            .map { (String($0).trimmingCharacters(in: .whitespaces), normalize(String($0))) }
            .filter { !$0.1.isEmpty }
    }

    private static var wakePhrase: String {
        normalize(UserDefaults.standard.string(forKey: Keys.wakePhrase) ?? "")
    }

    /// Lowercases and strips whitespace/punctuation so transcription formatting
    /// ("Xiao Ming," vs "xiaoming") doesn't break matching.
    private static func normalize(_ text: String) -> String {
        String(String.UnicodeScalarView(text.lowercased().unicodeScalars.filter {
            !CharacterSet.whitespacesAndNewlines.contains($0) &&
            !CharacterSet.punctuationCharacters.contains($0)
        }))
    }
}
