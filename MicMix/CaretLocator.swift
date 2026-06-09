//
//  CaretLocator.swift
//  MicMix
//
//  Finds the on-screen rect of the current text caret using the Accessibility
//  API, so the translate overlay can position itself near where the user is
//  about to type. Falls back to the mouse cursor when AX text APIs aren't
//  available (some browsers, terminals, Electron apps).
//

import AppKit
import ApplicationServices

enum CaretLocator {
    /// AX returns coordinates in Carbon's top-left origin global screen space.
    /// NSWindow expects bottom-left origin anchored at the primary screen.
    /// Returns the suggested top-left origin for an overlay panel of the given
    /// size, placed just below the caret/focused element with a small gap.
    static func suggestedOverlayOrigin(panelSize: CGSize) -> CGPoint {
        if let rect = caretRectInAXSpace(), rect.width > 0, rect.height > 0 {
            return convertedOrigin(below: rect, panelSize: panelSize)
        }
        if let rect = focusedElementRectInAXSpace() {
            return convertedOrigin(below: rect, panelSize: panelSize)
        }
        return mouseFallback(panelSize: panelSize)
    }

    // MARK: - AX queries

    private static func caretRectInAXSpace() -> CGRect? {
        guard let focused = focusedElement() else { return nil }
        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focused, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
              let rangeValue = rangeRef, CFGetTypeID(rangeValue) == AXValueGetTypeID() else {
            return nil
        }
        var boundsRef: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(focused,
                                                         kAXBoundsForRangeParameterizedAttribute as CFString,
                                                         rangeValue,
                                                         &boundsRef) == .success,
              let boundsValue = boundsRef, CFGetTypeID(boundsValue) == AXValueGetTypeID() else {
            return nil
        }
        var rect = CGRect.zero
        guard AXValueGetType(boundsValue as! AXValue) == .cgRect,
              AXValueGetValue(boundsValue as! AXValue, .cgRect, &rect) else {
            return nil
        }
        return rect
    }

    private static func focusedElementRectInAXSpace() -> CGRect? {
        guard let focused = focusedElement() else { return nil }
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focused, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(focused, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let posValue = posRef, CFGetTypeID(posValue) == AXValueGetTypeID(),
              let sizeValue = sizeRef, CFGetTypeID(sizeValue) == AXValueGetTypeID() else {
            return nil
        }
        var pos = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(posValue as! AXValue, .cgPoint, &pos),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else {
            return nil
        }
        // Use only the bottom edge — we'll place the overlay below it.
        return CGRect(x: pos.x, y: pos.y + size.height - 1, width: max(size.width, 1), height: 1)
    }

    private static func focusedElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &ref) == .success,
              let element = ref else {
            return nil
        }
        return (element as! AXUIElement)
    }

    // MARK: - Coordinate conversion

    /// Picks the NSScreen the AX rect falls inside (AX top-left → NSScreen
    /// bottom-left), and returns the panel origin so the overlay sits just below
    /// the caret/element with a small gap, clamped onto the visible frame.
    private static func convertedOrigin(below axRect: CGRect, panelSize: CGSize) -> CGPoint {
        let gap: CGFloat = 8
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        // Convert top-left AX origin to bottom-left NSScreen origin.
        let nsTopY = mainHeight - axRect.minY
        let nsBottomY = nsTopY - axRect.height
        let nsRect = CGRect(x: axRect.minX, y: nsBottomY, width: axRect.width, height: axRect.height)

        let screen = NSScreen.screens.first(where: { $0.frame.contains(CGPoint(x: nsRect.midX, y: nsRect.midY)) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        let visible = screen?.visibleFrame ?? .zero

        var x = nsRect.minX
        var y = nsRect.minY - panelSize.height - gap
        if x + panelSize.width > visible.maxX { x = visible.maxX - panelSize.width - 16 }
        if x < visible.minX { x = visible.minX + 16 }
        if y < visible.minY { y = nsRect.maxY + gap }   // not enough room below — go above
        if y + panelSize.height > visible.maxY { y = visible.maxY - panelSize.height - 16 }
        return CGPoint(x: x, y: y)
    }

    private static func mouseFallback(panelSize: CGSize) -> CGPoint {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        let visible = screen?.visibleFrame ?? .zero
        var x = mouse.x - panelSize.width / 2
        var y = mouse.y - panelSize.height - 24
        if x + panelSize.width > visible.maxX { x = visible.maxX - panelSize.width - 16 }
        if x < visible.minX { x = visible.minX + 16 }
        if y < visible.minY { y = visible.minY + 16 }
        return CGPoint(x: x, y: y)
    }
}
