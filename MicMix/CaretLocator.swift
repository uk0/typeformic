//
//  CaretLocator.swift
//  MicMix
//
//  Picks where to drop the translate overlay. Uses the current mouse position
//  (more reliable across apps than AX caret queries, which silently return wrong
//  rects in browsers, Electron, and some text editors).
//

import AppKit

enum CaretLocator {
    /// Suggested NSWindow origin (bottom-left, screen coords) for a panel of
    /// `panelSize`, placed just below-and-to-the-right of the mouse so the
    /// cursor remains visible above the bar.
    static func suggestedOverlayOrigin(panelSize: CGSize) -> CGPoint {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        let visible = screen?.visibleFrame ?? .zero

        let offsetX: CGFloat = 14
        let offsetY: CGFloat = 14

        var x = mouse.x + offsetX
        var y = mouse.y - panelSize.height - offsetY

        // Clamp horizontally.
        if x + panelSize.width > visible.maxX { x = visible.maxX - panelSize.width - 8 }
        if x < visible.minX { x = visible.minX + 8 }

        // If there isn't room below the cursor, flip above.
        if y < visible.minY { y = mouse.y + offsetY }
        if y + panelSize.height > visible.maxY { y = visible.maxY - panelSize.height - 8 }

        return CGPoint(x: x, y: y)
    }
}
