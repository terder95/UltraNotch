import SwiftUI

/// Punto de entrada.
/// - Normal: abre Isla (sin ventana ni ícono en el Dock; vive en el notch y en la barra de menús).
/// - `--claude-hook`: modo "mensajero" que Claude Code ejecuta en cada aviso (sin interfaz).
/// - `--remove-claude-hooks`: quita los avisos de Claude Code (lo usa desinstalar.sh).
/// - `--capturas <carpeta>`: genera imágenes PNG con datos de ejemplo (para el README) y sale.
@main
enum Launcher {
    @MainActor
    static func main() {
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: ModoCapturas.marker) {
            let carpeta = index + 1 < arguments.count ? arguments[index + 1] : "capturas"
            ModoCapturas.correr(carpeta: carpeta)
        }
        if arguments.contains(ClaudeStatusLine.marker) {
            ClaudeStatusLine.run()
        }
        if arguments.contains(ClaudeHookInstaller.marker) {
            ClaudeHookRelay.run()
        }
        if arguments.contains("--remove-claude-hooks") {
            try? ClaudeHookInstaller.uninstall()
            exit(0)
        }
        CrashGuard.configureEarly()
        IslaMMApp.main()
    }
}

struct IslaMMApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
