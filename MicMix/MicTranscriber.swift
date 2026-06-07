//
//  MicTranscriber.swift
//  MicMix
//
//  Streams microphone audio through SpeechAnalyzer + SpeechTranscriber.
//  Publishes a live transcript while recording; returns the final concatenated
//  text when stopped.
//

import AVFoundation
import Combine
import Foundation
import Speech
@preconcurrency import CoreMedia

@MainActor
final class MicTranscriber: ObservableObject {
    @Published private(set) var liveText: String = ""
    @Published private(set) var isRecording: Bool = false
    @Published private(set) var statusMessage: String = ""

    private let audioEngine = AVAudioEngine()
    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?

    /// Per-phrase storage keyed by audio-range start. Volatile results overwrite
    /// the entry at the same start; final results "lock in" via isFinal.
    private struct Phrase {
        var text: String
        var isFinal: Bool
    }
    private var phrases: [CMTime: Phrase] = [:]

    /// Fires on the main actor when trailing silence is detected after speech,
    /// so the controller can auto-finish the utterance.
    var onSilence: (() -> Void)?

    /// Auto-stop tuning: RMS at or above this counts as speech; that many seconds
    /// of trailing silence after speech has begun ends the utterance.
    private static let voiceThreshold: Float = 0.012
    private static let silenceTimeout: TimeInterval = 1.5
    private var voiceDetected = false
    private var silenceAccumulated: TimeInterval = 0

    func requestAuthorization() async -> Bool {
        let speechAuthorized = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
        guard speechAuthorized else { return false }
        // macOS does not reliably raise the microphone prompt from AVAudioEngine
        // alone — without this the input node just yields silence. Request capture
        // access explicitly and wait for the grant.
        return await AVCaptureDevice.requestAccess(for: .audio)
    }

    func start() async throws {
        guard !isRecording else { return }
        resetState()

        let locale = await Self.preferredSupportedLocale()
        let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        self.transcriber = transcriber

        try await Self.ensureAssetsInstalled(for: transcriber)

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer

        let (stream, builder) = AsyncStream<AnalyzerInput>.makeStream()
        self.inputBuilder = builder

        try await startMicrophone(transcriber: transcriber, builder: builder)

        resultsTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await result in transcriber.results {
                    await self.append(result: result)
                }
            } catch {
                await self.report(error: error)
            }
        }

        try await analyzer.start(inputSequence: stream)
        isRecording = true
        statusMessage = "Listening…"
    }

    func stop() async -> String {
        guard isRecording else { return finalText() }
        isRecording = false
        statusMessage = "Finalizing…"

        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()

        inputBuilder?.finish()
        inputBuilder = nil

        do {
            try await analyzer?.finalizeAndFinishThroughEndOfInput()
        } catch {
            report(error: error)
        }
        await resultsTask?.value
        resultsTask = nil
        analyzer = nil
        transcriber = nil
        statusMessage = ""
        return finalText()
    }

    // MARK: - Private

    private func resetState() {
        liveText = ""
        statusMessage = ""
        phrases.removeAll()
        voiceDetected = false
        silenceAccumulated = 0
    }

    private func append(result: SpeechTranscriber.Result) {
        let text = String(result.text.characters)
        phrases[result.range.start] = Phrase(text: text, isFinal: result.isFinal)
        liveText = finalText()
    }

    private func finalText() -> String {
        phrases
            .sorted { $0.key < $1.key }
            .map { $0.value.text }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func report(error: Error) {
        statusMessage = "Error: \(error.localizedDescription)"
    }

    /// Tracks speech vs. silence from per-buffer RMS and fires `onSilence` once
    /// enough trailing silence accrues after speech began.
    private func updateVAD(level: Float, bufferDuration: TimeInterval) {
        guard isRecording else { return }
        if level >= Self.voiceThreshold {
            voiceDetected = true
            silenceAccumulated = 0
        } else if voiceDetected {
            silenceAccumulated += bufferDuration
            if silenceAccumulated >= Self.silenceTimeout {
                voiceDetected = false
                silenceAccumulated = 0
                onSilence?()
            }
        }
    }

    private nonisolated static func rmsLevel(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channels = buffer.floatChannelData else { return 0 }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return 0 }
        let channelCount = Int(buffer.format.channelCount)
        var sumSquares: Float = 0
        for ch in 0..<channelCount {
            let samples = channels[ch]
            for i in 0..<frameLength {
                let sample = samples[i]
                sumSquares += sample * sample
            }
        }
        let totalSamples = Float(frameLength * channelCount)
        return totalSamples > 0 ? (sumSquares / totalSamples).squareRoot() : 0
    }

    private func startMicrophone(transcriber: SpeechTranscriber,
                                 builder: AsyncStream<AnalyzerInput>.Continuation) async throws {
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

        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            let payload: AVAudioPCMBuffer
            if let converter {
                guard let converted = Self.convert(buffer: buffer, using: converter, to: analyzerFormat) else { return }
                payload = converted
            } else {
                payload = buffer
            }
            builder.yield(AnalyzerInput(buffer: payload))

            let level = Self.rmsLevel(of: buffer)
            let sampleRate = buffer.format.sampleRate
            let bufferDuration = sampleRate > 0 ? Double(buffer.frameLength) / sampleRate : 0
            Task { @MainActor in
                self?.updateVAD(level: level, bufferDuration: bufferDuration)
            }
        }

        audioEngine.prepare()
        try audioEngine.start()
    }

    private nonisolated static func convert(buffer: AVAudioPCMBuffer,
                                            using converter: AVAudioConverter,
                                            to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 32)
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }

        var consumed = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if consumed {
                inputStatus.pointee = .endOfStream
                return nil
            }
            consumed = true
            inputStatus.pointee = .haveData
            return buffer
        }
        if status == .error || error != nil { return nil }
        return output
    }

    private static func preferredSupportedLocale() async -> Locale {
        let supported = await SpeechTranscriber.supportedLocales
        let preferred = Locale.preferredLanguages
            .compactMap { Locale(identifier: $0) }
        for locale in preferred {
            if let match = await SpeechTranscriber.supportedLocale(equivalentTo: locale) {
                return match
            }
        }
        return supported.first ?? Locale(identifier: "en-US")
    }

    private static func ensureAssetsInstalled(for transcriber: SpeechTranscriber) async throws {
        guard let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) else {
            return
        }
        try await request.downloadAndInstall()
    }
}
