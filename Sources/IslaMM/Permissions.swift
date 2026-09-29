import AppKit
import ApplicationServices

/// Permiso de Accesibilidad: lo necesita la app para escuchar ⌘C/⌘V + número
/// y para "teclear" ⌘V cuando pegas desde una ranura.
@MainActor
enum Permissions {
    static var accessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    /// Muestra el aviso del sistema ("Isla quiere controlar esta computadora…").
    static func promptAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// Abre Ajustes del Sistema › Privacidad y seguridad › Accesibilidad.
    static func openAccessibilitySettings() {
        let link = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        if let url = URL(string: link) {
            NSWorkspace.shared.open(url)
        }
    }
}
