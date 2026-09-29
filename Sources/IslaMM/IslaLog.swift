import AppKit
import SwiftUI

/// Registro corto de lo que hace Isla con tu voz y con Claude.
/// Sirve para saber en qué paso falló algo (Configuración › Registro).
@MainActor
final class IslaLog: ObservableObject {
    static let shared = IslaLog()

    struct Entry: Identifiable {
        let id = UUID()
        let date: Date
        let text: String
    }

    @Published private(set) var entries: [Entry] = []
    /// Lo que quedó guardado de la vez pasada (para saber qué pasaba si Isla se cerró de golpe).
    let previousSession: [String] = CrashGuard.previousLog()
    private var saveTask: Task<Void, Never>?

    private let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    func add(_ text: String) {
        entries.append(Entry(date: Date(), text: text))
        if entries.count > 80 {
            entries.removeFirst(entries.count - 80)
        }
        scheduleSave()
    }

    /// Lo guarda en disco (agrupando cambios) por si Isla se cierra de golpe.
    private func scheduleSave() {
        guard saveTask == nil else { return }
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard let strongSelf = self else { return }
            strongSelf.saveTask = nil
            let text = strongSelf.plainText
            let path = CrashGuard.logPath
            DispatchQueue.global(qos: .utility).async {
                try? text.write(toFile: path, atomically: true, encoding: .utf8)
            }
        }
    }

    func time(of entry: Entry) -> String {
        formatter.string(from: entry.date)
    }

    var plainText: String {
        entries.map { "\(time(of: $0))  \($0.text)" }.joined(separator: "\n")
    }

    func copyToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(plainText, forType: .string)
    }

    func clear() {
        entries.removeAll()
    }
}
