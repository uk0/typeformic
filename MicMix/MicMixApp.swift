//
//  MicMixApp.swift
//  MicMix
//

import AppKit
import SwiftUI

@main
struct MicMixApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra("MicMix", systemImage: "mic.fill") {
            Button("Toggle Dictation  ⌃⌥M") {
                Task { await delegate.controller.toggle() }
            }
            Button("Show / Hide Widget") {
                delegate.togglePanel()
            }
            Button("Settings…") {
                delegate.showSettings()
            }
            .keyboardShortcut(",", modifiers: .command)
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
    private let hotKey = HotKey()
    private var panel: FloatingPanel?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        showPanel()

        hotKey.register { [weak self] in
            guard let self else { return }
            Task { await self.controller.toggle() }
            self.showPanel()
        }
    }

    func togglePanel() {
        if let panel, panel.isVisible {
            panel.orderOut(nil)
        } else {
            showPanel()
        }
    }

    func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 640),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "MicMix Settings"
            window.contentView = NSHostingView(rootView: SettingsView())
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func showPanel() {
        if panel == nil {
            let panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 180)) {
                ContentView(controller: self.controller)
            }
            if let screen = NSScreen.main {
                let frame = screen.visibleFrame
                let size = panel.frame.size
                panel.setFrameOrigin(NSPoint(x: frame.maxX - size.width - 20,
                                             y: frame.maxY - size.height - 20))
            }
            self.panel = panel
        }
        panel?.orderFrontRegardless()
    }
}
