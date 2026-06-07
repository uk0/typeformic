//
//  FloatingPanel.swift
//  MicMix
//
//  A small borderless NSPanel that floats above other apps without stealing
//  keyboard focus, so injected keystrokes still go to the previously frontmost app.
//

import AppKit
import SwiftUI

final class FloatingPanel: NSPanel {
    init<Content: View>(contentRect: NSRect, @ViewBuilder content: () -> Content) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        self.isFloatingPanel = true
        self.level = .floating
        self.hidesOnDeactivate = false
        self.becomesKeyOnlyIfNeeded = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        self.isMovableByWindowBackground = true
        self.isReleasedWhenClosed = false
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false

        self.contentView = NSHostingView(rootView: content())
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
