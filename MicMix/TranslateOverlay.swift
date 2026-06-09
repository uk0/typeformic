//
//  TranslateOverlay.swift
//  MicMix
//
//  A translucent compose bar that pops up at the user's caret. The user types
//  Chinese, presses Return — we translate (per current style), refocus the
//  previously-frontmost app, and inject the English at the cursor. Esc cancels.
//

import AppKit
import Combine
import SwiftUI

@MainActor
final class TranslateOverlayController: ObservableObject {
    @Published var input: String = ""
    @Published var translation: String = ""
    @Published var isTranslating: Bool = false
    @Published var errorMessage: String?

    private var panel: TranslateOverlayPanel?
    private var previousAppPID: pid_t?

    // MARK: - Public toggle

    func toggle() {
        if let panel, panel.isVisible {
            close()
        } else {
            open()
        }
    }

    func open() {
        // Capture the previously-focused app BEFORE we activate ourselves,
        // so we can refocus it on commit and inject keystrokes there.
        previousAppPID = NSWorkspace.shared.frontmostApplication?.processIdentifier

        input = ""
        translation = ""
        isTranslating = false
        errorMessage = nil

        let panel = ensurePanel()
        let origin = CaretLocator.suggestedOverlayOrigin(panelSize: panel.frame.size)
        panel.setFrameOrigin(origin)

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        panel?.orderOut(nil)
    }

    /// Called when the user presses Return in the input field.
    func commit() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { close(); return }

        Task { @MainActor in
            errorMessage = nil
            isTranslating = true
            let english = await TextPolisher.translate(text)
            isTranslating = false

            guard !english.isEmpty else {
                errorMessage = "Translation unavailable — check your engine in Settings."
                return
            }
            translation = english

            // Close, refocus original app, then inject.
            let targetPID = previousAppPID
            close()
            if let pid = targetPID, let app = NSRunningApplication(processIdentifier: pid) {
                app.activate()
            }
            // Brief wait for focus to land, otherwise the first keystrokes go nowhere.
            try? await Task.sleep(nanoseconds: 120_000_000)
            KeystrokeInjector.type(english)
        }
    }

    // MARK: - Panel lifecycle

    private func ensurePanel() -> TranslateOverlayPanel {
        if let panel { return panel }
        let p = TranslateOverlayPanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 76),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.isMovableByWindowBackground = false
        p.hidesOnDeactivate = true

        let hosting = NSHostingView(rootView: TranslateOverlayView(controller: self))
        // Without this, the hosting view's backing layer renders an opaque
        // white margin around the rounded material — visible past the capsule.
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        p.contentView = hosting
        panel = p
        return p
    }
}

/// Borderless NSPanel that still accepts keyboard focus so the embedded
/// TextField can receive typed input.
final class TranslateOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private struct TranslateOverlayView: View {
    @ObservedObject var controller: TranslateOverlayController
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "character.bubble.fill")
                    .foregroundStyle(.tint)
                    .font(.system(size: 14, weight: .semibold))

                TextField("说中文,按 ⏎ 翻译并插入", text: $controller.input)
                    .textFieldStyle(.plain)
                    .font(.system(.callout))
                    .focused($fieldFocused)
                    .onSubmit { controller.commit() }
                    .onExitCommand { controller.close() }
                    .disabled(controller.isTranslating)

                if controller.isTranslating {
                    ProgressView().controlSize(.small)
                }
            }

            HStack(spacing: 0) {
                if let err = controller.errorMessage {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                        .truncationMode(.tail)
                } else if controller.isTranslating {
                    Text("Translating…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if !controller.translation.isEmpty {
                    Text(controller.translation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                } else {
                    Text("⏎ Insert English  ·  ⎋ Cancel")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        // Fills the panel content area exactly — so the rounded material is the
        // whole visible window and the window's shadow handles the soft edge.
        .frame(width: 460, height: 76)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(.white.opacity(0.15), lineWidth: 1)
        )
        .onAppear { fieldFocused = true }
    }
}
