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
    @Published var liveText: String = ""
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
        guard await transcriber.requestAuthorization() else {
            phase = .error("Grant Microphone & Speech access in System Settings")
            return
        }
        guard KeystrokeInjector.ensureAccessibilityTrusted(prompt: true) else {
            phase = .error("Grant Accessibility access in System Settings")
            return
        }
        liveText = ""
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

        let polished = TextPolisher.isAvailable ? await polisher.polish(raw) : raw
        lastOutput = polished

        phase = .typing
        // Tiny delay so the floating panel can resign anything it might briefly hold,
        // and the user's previously-frontmost app receives the keystrokes.
        try? await Task.sleep(nanoseconds: 80_000_000)
        KeystrokeInjector.type(polished)

        phase = .idle
    }
}
