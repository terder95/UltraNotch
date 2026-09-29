import SwiftUI
import AppKit
import Foundation

/// Colores del sistema (estilo Apple). Se adaptan solos a modo claro/oscuro
/// y al color de acento que elijas en Ajustes del Sistema.
enum Theme {
    static let accent = Color.accentColor
    static let screenshot = Color.pink
    static let download = Color.blue
    static let success = Color.green
    static let warning = Color.orange
    static let danger = Color.red
    /// Azul de AirDrop.
    static let airDrop = Color(red: 0.12, green: 0.6, blue: 0.96)
    /// El notch físico es negro: esta parte siempre va en negro para fundirse.
    static let island = Color.black

    static func card(_ highlighted: Bool) -> Color {
        Color.primary.opacity(highlighted ? 0.12 : 0.06)
    }
}

/// Estilo visual de la isla abierta.
enum IslandStyle: String {
    case glass   // Cristal líquido (Liquid Glass en macOS 26+, vidrio esmerilado antes)
    case black   // Negro clásico, como la Dynamic Island del iPhone
}

/// Fondo de cristal: Liquid Glass real en macOS 26 o superior;
/// en versiones anteriores, el desenfoque de vidrio del sistema.
struct IslandGlass<S: Shape>: View {
    let shape: S

    var body: some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            Color.clear
                .glassEffect(.regular, in: shape)
        } else {
            fallback
        }
        #else
        fallback
        #endif
    }

    private var fallback: some View {
        VisualEffectBlur()
            .clipShape(shape)
            .overlay(shape.stroke(Color.white.opacity(0.22), lineWidth: 0.8))
    }
}

/// Vidrio esmerilado de macOS (NSVisualEffectView) que desenfoca lo que hay detrás.
struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .popover

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
    }
}

/// Carpeta donde la app guarda sus datos:
/// ~/Library/Application Support/IslaMM
enum AppPaths {
    static let support: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let folder = base.appendingPathComponent("IslaMM", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }()
}

@MainActor
enum Formatters {
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "es_MX")
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    static func relative(_ date: Date) -> String {
        if Date().timeIntervalSince(date) < 10 { return "ahora" }
        return relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    /// Tamaños de archivos y disco (como Finder).
    static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: max(value, 0), countStyle: .file)
    }

    /// Memoria RAM (como el Monitor de Actividad).
    static func memory(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: value), countStyle: .memory)
    }

    private static let durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        var calendar = Calendar.current
        calendar.locale = Locale(identifier: "es_MX")
        formatter.calendar = calendar
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        return formatter
    }()

    static func duration(_ seconds: TimeInterval) -> String {
        durationFormatter.string(from: seconds) ?? ""
    }
}

/// Botón tipo píldora discreto.
struct PillButtonStyle: ButtonStyle {
    var tint: Color = .primary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundColor(tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.primary.opacity(configuration.isPressed ? 0.18 : 0.08)))
            .contentShape(Capsule())
    }
}
