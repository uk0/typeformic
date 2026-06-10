//
//  DictationController.swift
//  MicMix
//
//  Orchestrates the full hot-key → record → transcribe → polish → type pipeline.
//

import AppKit
import Combine
import SwiftUI

@MainActor
final class DictationController: ObservableObject {
    enum Phase: Equatable {
        case idle
        case preparing
        case recording
        case polishing
        case typing
        case error(String)
    }

    @Published var phase: Phase = .idle
    /// Line 1 of the wake pill — raw Chinese during recording, cleaned Chinese after polishing.
    @Published var liveText: String = ""
    /// Line 2 of the wake pill — English translation, populated by the polish step.
    @Published var liveEnglish: String = ""
    /// The text actually injected at the cursor on the last completed dictation
    /// (may equal `liveText` or `liveEnglish` depending on the output language).
    @Published var lastOutput: String = ""

    let transcriber = MicTranscriber()
    private let polisher = TextPolisher()

    private var liveBinding: Task<Void, Never>?

    init() {
        // Mirror MicTranscriber.liveText into our own published prop so the panel can show it.
        liveBinding = Task { [weak self] in
            guard let self else { return }
            for await text in self.transcriber.$liveText.values {
                self.liveText = text
            }
        }
    }

    deinit { liveBinding?.cancel() }

    func toggle() async {
        switch phase {
        case .idle, .error:
            await beginRecording()
        case .recording:
            await finishRecording()
        case .preparing, .polishing, .typing:
            break
        }
    }

    private func beginRecording() async {
        guard await MicTranscriber.requestAuthorization() else {
            phase = .error("Grant Microphone & Speech access in System Settings")
            return
        }
        guard KeystrokeInjector.ensureAccessibilityTrusted(prompt: true) else {
            phase = .error("Grant Accessibility access in System Settings")
            return
        }
        liveText = ""
        liveEnglish = ""
        transcriber.onSilence = { [weak self] in
            Task { await self?.autoFinish() }
        }
        phase = .preparing
        do {
            try await transcriber.start()
            phase = .recording
        } catch {
            phase = .error(error.localizedDescription)
        }
    }

    /// Auto-finish triggered by trailing-silence detection; ignored unless we are
    /// still recording, so it can't race a manual ⌃⌥M stop.
    private func autoFinish() async {
        guard phase == .recording else { return }
        await finishRecording()
    }

    private func finishRecording() async {
        phase = .polishing
        let raw = await transcriber.stop()
        guard !raw.isEmpty else {
            phase = .idle
            return
        }

        let result: PolishResult = TextPolisher.isAvailable
            ? await polisher.polish(raw)
            : PolishResult(chinese: raw, english: "")

        // Update the panel: line 1 = cleaned Chinese, line 2 = English translation.
        liveText = result.chinese
        liveEnglish = result.english

        // Pick what to actually type based on the output-language setting.
        // Fall back to Chinese if English is empty (e.g. on-device model didn't
        // emit a second line, or the engine failed mid-way).
        let config = PolishConfig.current
        let target: String = {
            if config.outputLanguage == .english, !result.english.isEmpty {
                return result.english
            }
            return result.chinese
        }()
        lastOutput = target
        Stats.shared.record(rawText: raw, polishedText: result.chinese)

        phase = .typing
        // Tiny delay so the floating panel can resign anything it might briefly hold,
        // and the user's previously-frontmost app receives the keystrokes.
        try? await Task.sleep(nanoseconds: 80_000_000)
        KeystrokeInjector.type(target)

        phase = .idle
    }
}
