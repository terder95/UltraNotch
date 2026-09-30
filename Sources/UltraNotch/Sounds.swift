import AppKit
import SwiftUI

// Un sonido distinto para cada cosa que pasa (se eligen en Configuración › Sonidos).

enum SoundEvent: String, CaseIterable, Identifiable {
    case permission, question, finished, sessionStart, usage, failure, meeting

    var id: String { rawValue }

    var label: String {
        switch self {
        case .permission: return "Claude pide permiso"
        case .question: return "Claude te hace una pregunta"
        case .finished: return "Claude terminó una tarea"
        case .sessionStart: return "Empieza una sesión de Claude Code"
        case .usage: return "Aviso de límite de uso"
        case .failure: return "Algo no se pudo hacer"
        case .meeting: return "Tu junta está por empezar"
        }
    }

    var symbol: String {
        switch self {
        case .permission: return "hand.raised.fill"
        case .question: return "questionmark.bubble.fill"
        case .finished: return "checkmark.circle.fill"
        case .sessionStart: return "play.circle.fill"
        case .usage: return "gauge.with.dots.needle.67percent"
        case .failure: return "exclamationmark.triangle.fill"
        case .meeting: return "calendar"
        }
    }

    /// El de fábrica ("" = sin sonido).
    var defaultSound: String {
        switch self {
        case .permission: return "Ping"
        case .question: return "Purr"
        case .finished: return "Glass"
        case .sessionStart: return ""
        case .usage: return "Submarine"
        case .failure: return "Basso"
        case .meeting: return "Hero"
        }
    }

    var key: String { "sound.\(rawValue)" }
}

@MainActor
enum SoundBoard {
    /// Interruptor general (es el mismo "Sonidos" de siempre).
    nonisolated static let enabledKey = "claudeSounds"

    /// Los sonidos que trae macOS.
    static let choices = ["Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero", "Morse",
                          "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink"]

    static var enabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    static func sound(for event: SoundEvent) -> String {
        UserDefaults.standard.string(forKey: event.key) ?? event.defaultSound
    }

    static func set(_ name: String, for event: SoundEvent) {
        UserDefaults.standard.set(name, forKey: event.key)
    }

    static func play(_ event: SoundEvent) {
        guard enabled else { return }
        preview(sound(for: event))
    }

    /// Suena ya (también para probarlo en Configuración).
    static func preview(_ name: String) {
        guard !name.isEmpty, let sound = NSSound(named: NSSound.Name(name)) else { return }
        sound.stop()
        sound.play()
    }
}

/// Configuración › Sonidos: un renglón por evento.
struct SoundEventRow: View {
    let event: SoundEvent
    @State private var name: String

    init(event: SoundEvent) {
        self.event = event
        _name = State(initialValue: SoundBoard.sound(for: event))
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: event.symbol)
                .foregroundColor(.secondary)
                .frame(width: 18)
            Picker(event.label, selection: $name) {
                Text("Sin sonido").tag("")
                ForEach(SoundBoard.choices, id: \.self) { choice in
                    Text(choice).tag(choice)
                }
            }
            .onChange(of: name) { newName in
                SoundBoard.set(newName, for: event)
                SoundBoard.preview(newName)
            }
            Button {
                SoundBoard.preview(name)
            } label: {
                Image(systemName: "speaker.wave.2.fill")
            }
            .buttonStyle(.borderless)
            .disabled(name.isEmpty)
            .help("Escucharlo")
        }
    }
}
