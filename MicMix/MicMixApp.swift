//
//  MicMixApp.swift
//  MicMix
//

import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI

@main
struct MicMixApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra("MicMix", systemImage: "mic.fill") {
            Button("Toggle Dictation  ⌃⌥M") {
                Task { await delegate.controller.toggle() }
            }
            Button("Translate Input  ⌃⌥T") {
                delegate.translateOverlay.toggle()
            }
            Button("Show / Hide Widget") {
                delegate.togglePanel()
            }
            Button("Statistics…") {
                delegate.showStats()
            }
            Button("Settings…") {
                delegate.showSettings()
            }
            .keyboardShortcut(",", modifiers: .command)
            Divider()
            Button("About MicMix") {
                delegate.showAbout()
            }
            Divider()
            Button("Quit MicMix") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = DictationController()
    let translateOverlay = TranslateOverlayController()
    private let dictationHotKey = HotKey()
    private let translateHotKey = HotKey()
    private var panel: FloatingPanel?
    private var settingsWindow: NSWindow?
    private var statsWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()
    private var hideWorkItem: DispatchWorkItem?
    private var wasActive = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Accessory behavior comes from LSUIElement in Info.plist, so the app
        // never flashes a Dock icon at launch.

        // One-time migration of a legacy plaintext API key into the Keychain.
        _ = PolishConfig.storedAPIKey

        // Hidden by default — only wakes on the hotkey / dictation activity.
        createPanelIfNeeded()

        dictationHotKey.register(id: 1) { [weak self] in
            guard let self else { return }
            self.wakePanel()
            Task { await self.controller.toggle() }
        }
        translateHotKey.register(keyCode: UInt32(kVK_ANSI_T),
                                 modifiers: UInt32(controlKey | optionKey),
                                 id: 2) { [weak self] in
            self?.translateOverlay.toggle()
        }

        controller.$phase
            .receive(on: RunLoop.main)
            .sink { [weak self] phase in self?.handlePhase(phase) }
            .store(in: &cancellables)
    }

    // MARK: - Phase-driven visibility

    private func handlePhase(_ phase: DictationController.Phase) {
        switch phase {
        case .preparing, .recording, .polishing, .typing:
            wasActive = true
            cancelHide()
            wakePanel()
        case .idle:
            if wasActive { wasActive = false; scheduleHide(after: 1.6) }
        case .error:
            if wasActive { wasActive = false; scheduleHide(after: 3.0) }
        }
    }

    // MARK: - Pill window

    func togglePanel() {
        if let panel, panel.isVisible {
            hidePanel()
        } else {
            wakePanel()
        }
    }

    private func createPanelIfNeeded() {
        guard panel == nil else { return }
        panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 460, height: 78)) {
            ContentView(controller: self.controller)
        }
        panel?.alphaValue = 0
    }

    private func wakePanel() {
        createPanelIfNeeded()
        cancelHide()
        positionPanel()
        guard let panel else { return }
        if !panel.isVisible { panel.alphaValue = 0 }
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            panel.animator().alphaValue = 1
        }
    }

    private func hidePanel() {
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak panel] in
            panel?.orderOut(nil)
        })
    }

    private func scheduleHide(after seconds: TimeInterval) {
        cancelHide()
        let item = DispatchWorkItem { [weak self] in self?.hidePanel() }
        hideWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: item)
    }

    private func cancelHide() {
        hideWorkItem?.cancel()
        hideWorkItem = nil
    }

    private func positionPanel() {
        guard let panel, let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        let origin = NSPoint(x: visible.midX - size.width / 2,
                             y: visible.minY + 40)
        panel.setFrameOrigin(origin)
    }

    // MARK: - Aux windows

    func showStats() {
        if statsWindow == nil {
            statsWindow = makeWindow(title: "MicMix Statistics",
                                     size: NSSize(width: 460, height: 230),
                                     content: StatsView())
        }
        NSApp.activate(ignoringOtherApps: true)
        statsWindow?.makeKeyAndOrderFront(nil)
    }

    func showSettings() {
        if settingsWindow == nil {
            settingsWindow = makeWindow(title: "MicMix Settings",
                                        size: NSSize(width: 520, height: 680),
                                        content: SettingsView())
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    private func makeWindow<Content: View>(title: String, size: NSSize, content: Content) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.contentView = NSHostingView(rootView: content)
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}
