import Foundation
import Combine

/// Un proyecto de Claude al que le puedes mandar mensajes por voz:
/// "Oye Claudio, a Gorgias: …".
struct ClaudeProject: Codable, Identifiable, Equatable {
    var id = UUID()
    /// Nombre que ves (y que también reconoce la voz).
    var name: String
    /// Otras formas de decirlo, separadas por comas (opcional). Ej: "gorgias, soporte".
    var spoken: String
    /// Link del proyecto (https://claude.ai/project/…) o solo su código.
    var link: String

    /// El código del proyecto dentro del link.
    var projectID: String? {
        let pattern = "[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"
        guard let range = link.range(of: pattern, options: .regularExpression) else { return nil }
        return String(link[range]).lowercased()
    }

    /// Lo que UltraNotch busca cuando hablas (nombre + formas extra, sin acentos).
    var spokenForms: [String] {
        let extras = spoken.split(separator: ",").map(String.init)
        var seen = Set<String>()
        return ([name] + extras)
            .map { VoiceWake.normalize($0).split(separator: " ").joined(separator: " ") }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}

/// Tus proyectos guardados (Configuración › Proyectos de Claude).
@MainActor
final class ProjectStore: ObservableObject {
    static let shared = ProjectStore()
    private static let key = "claudeProjects"

    @Published var projects: [ClaudeProject] = [] {
        didSet { save() }
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: ProjectStore.key),
           let saved = try? JSONDecoder().decode([ClaudeProject].self, from: data) {
            projects = saved
        }
    }

    func add() {
        projects.append(ClaudeProject(name: "", spoken: "", link: ""))
    }

    func update(_ project: ClaudeProject) {
        guard let index = projects.firstIndex(where: { $0.id == project.id }),
              projects[index] != project else { return }
        projects[index] = project
    }

    func remove(_ project: ClaudeProject) {
        projects.removeAll { $0.id == project.id }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(projects) {
            UserDefaults.standard.set(data, forKey: ProjectStore.key)
        }
    }
}
