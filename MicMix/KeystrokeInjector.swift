//
//  KeystrokeInjector.swift
//  MicMix
//
//  Posts Unicode strings as synthesized key events at the current cursor location
//  in whatever app is frontmost. Does NOT touch the pasteboard.
//
//  Requires the user to grant Accessibility permission
//  (System Settings → Privacy & Security → Accessibility).
//

import AppKit
import CoreGraphics

enum KeystrokeInjector {
    /// Returns true when the process is trusted for Accessibility / event posting.
    static func ensureAccessibilityTrusted(prompt: Bool = true) -> Bool {
        let opts: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt]
        return AXIsProcessTrustedWithOptions(opts)
    }

    /// Types `string` into the frontmost app via CGEvent Unicode injection.
    /// Chunks the string so each event stays within the OS limit (~20 UTF-16 units per event).
    static func type(_ string: String) {
        guard !string.isEmpty else { return }
        let source = CGEventSource(stateID: .combinedSessionState)
        let utf16 = Array(string.utf16)

        let chunkSize = 20
        var index = 0
        while index < utf16.count {
            let end = min(index + chunkSize, utf16.count)
            let slice = Array(utf16[index..<end])

            guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
                return
            }

            slice.withUnsafeBufferPointer { buf in
                down.keyboardSetUnicodeString(stringLength: buf.count, unicodeString: buf.baseAddress)
                up.keyboardSetUnicodeString(stringLength: buf.count, unicodeString: buf.baseAddress)
            }

            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)

            index = end
        }
    }
}
