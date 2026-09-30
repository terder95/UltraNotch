import AppKit
import SwiftUI

/// Ventana transparente que flota encima de la barra de menús, justo sobre el notch.
final class NotchPanel: NSPanel {
    // No roba el teclado a la app que estés usando.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    // Permite colocarla encima de la barra de menús.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

/// Permite hacer clic y arrastrar a la primera, sin "activar" la app antes.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}

/// Mide el notch de la pantalla (o inventa uno si la pantalla no tiene).
@MainActor
enum NotchGeometry {
    static func targetScreen() -> NSScreen? {
        NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main ?? NSScreen.screens.first
    }

    static func notchSize(for screen: NSScreen) -> CGSize {
        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            let width = right.minX - left.maxX
            return CGSize(width: max(width, 120), height: screen.safeAreaInsets.top)
        }
        // Pantallas sin notch (monitor externo, Macs anteriores): "isla" virtual.
        let menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
        return CGSize(width: 200, height: max(menuBarHeight, 24))
    }
}
