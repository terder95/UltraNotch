import Foundation
import SwiftUI
#if canImport(FoundationModels)
import FoundationModels
#endif

// Tu diccionario personal y la limpieza del dictado.
//
// • Palabras: se las pasamos al reconocimiento de voz de la Mac para que las entienda mejor
//   (nombres de clientes, marcas, términos técnicos). Gratis y en tu Mac.
// • Correcciones: "cloud code → Claude Code". Si aún así oye mal, Isla lo arregla antes de mandarlo.
// • Limpieza: quita muletillas ("eh", "mmm", "este…") y palabras repetidas, y pone mayúsculas,
//   signos y punto final. Con Apple Intelligence (si tu Mac lo tiene) queda todavía mejor:
//   también corre en tu Mac, gratis y sin internet.

/// "Si oyes esto → escribe esto otro".
struct DictionaryRule: Codable, Identifiable, Equatable {
    var id = UUID()
    /// Lo que entiende mal. Puedes poner varias formas separadas por comas.
    var heard: String
    /// Cómo debe quedar.
    var write: String
}

@MainActor
final class PersonalDictionary: ObservableObject {
    static let shared = PersonalDictionary()

    /// Palabras que debe conocer, separadas por comas.
    @Published var words: String {
        didSet { UserDefaults.standard.set(words, forKey: Keys.words) }
    }
    @Published private(set) var rules: [DictionaryRule] = []
    /// Limpieza automática (muletillas, repeticiones, mayúsculas y puntuación).
    @Published var cleanupEnabled: Bool {
        didSet { UserDefaults.standard.set(cleanupEnabled, forKey: Keys.cleanup) }
    }
    /// Pulir con Apple Intelligence (si tu Mac lo tiene activado).
    @Published var smartEnabled: Bool {
        didSet { UserDefaults.standard.set(smartEnabled, forKey: Keys.smart) }
    }

    private enum Keys {
        static let words = "dictionaryWords"
        static let rules = "dictionaryRules"
        static let cleanup = "dictationCleanup"
        static let smart = "dictationSmartCleanup"
    }

    private init() {
        let defaults = UserDefaults.standard
        words = defaults.string(forKey: Keys.words) ?? "México Makers"
        cleanupEnabled = defaults.object(forKey: Keys.cleanup) as? Bool ?? true
        smartEnabled = defaults.object(forKey: Keys.smart) as? Bool ?? true
        if let data = defaults.data(forKey: Keys.rules),
           let saved = try? JSONDecoder().decode([DictionaryRule].self, from: data) {
            rules = saved
        } else {
            rules = [
                DictionaryRule(heard: "cloud code, clod code, claud code", write: "Claude Code"),
                DictionaryRule(heard: "chat gpt, chat jipiti", write: "ChatGPT")
            ]
        }
    }

    var wordList: [String] {
        words.split(whereSeparator: { $0 == "," || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Para el reconocimiento de voz: tus palabras y cómo deben quedar tus correcciones.
    var recognitionHints: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for word in wordList + rules.map({ $0.write.trimmingCharacters(in: .whitespaces) }) where !word.isEmpty {
            if seen.insert(word.lowercased()).inserted { result.append(word) }
        }
        return Array(result.prefix(60))
    }

    // MARK: Correcciones

    func addRule() {
        rules.append(DictionaryRule(heard: "", write: ""))
        saveRules()
    }

    func update(_ rule: DictionaryRule) {
        guard let index = rules.firstIndex(where: { $0.id == rule.id }) else { return }
        rules[index] = rule
        saveRules()
    }

    func remove(_ rule: DictionaryRule) {
        rules.removeAll { $0.id == rule.id }
        saveRules()
    }

    private func saveRules() {
        if let data = try? JSONEncoder().encode(rules) {
            UserDefaults.standard.set(data, forKey: Keys.rules)
        }
    }

    /// Aplica tus correcciones (sin importar mayúsculas; solo palabras completas).
    func applyRules(_ text: String) -> String {
        var result = text
        for rule in rules {
            let target = rule.write.trimmingCharacters(in: .whitespaces)
            guard !target.isEmpty else { continue }
            let variants = rule.heard.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            for variant in variants {
                let words = variant.split(separator: " ").map { NSRegularExpression.escapedPattern(for: String($0)) }
                let pattern = "(?<![\\p{L}\\p{N}])" + words.joined(separator: "\\s+") + "(?![\\p{L}\\p{N}])"
                guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
                let range = NSRange(result.startIndex..., in: result)
                result = regex.stringByReplacingMatches(in: result, range: range,
                                                        withTemplate: NSRegularExpression.escapedTemplate(for: target))
            }
        }
        return result
    }
}

// MARK: - Limpieza con reglas (gratis, instantánea)

enum DictationCleaner {
    /// Muletillas que nunca significan nada.
    private static let fillers = "(?:e+h+|e+m+|e+h+m+|m{2,}|h+m+|m+h+m+|u+h+|u+m+)"
    /// Palabras que no pueden venir después de "este" como adjetivo ("este quiero…" = muletilla).
    private static let afterFillerEste = "(?:quiero|quisiera|queremos|necesito|necesitamos|oye|por favor|puedes|podrías|podrias|me puedes|me podrías|me podrias|me ayudas|haz|hazme|dame|ayúdame|ayudame|pues|o sea|bueno|entonces|mira|fíjate|fijate|creo que|yo|tú)"
    private static let questionStart = "(?:qué|cómo|cuándo|dónde|por qué|cuál|cuáles|cuánto|cuánta|cuántos|cuántas|quién|quiénes|puedes|podrías|podrias|sabes|me puedes|me podrías|me podrias|me ayudas|es posible|hay forma|hay manera|tienes|crees que|what|how|why|when|where|who|which|can you|could you|do you|is there|are there)"

    static func clean(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { return result }

        // 1) Muletillas sueltas ("eh", "mmm", "ehm").
        result = replace(result, "(?<![\\p{L}])" + fillers + "(?![\\p{L}])[,.…]*", with: "")
        // 2) Al principio: "este…", "o sea…", "pues…", "bueno…", "a ver…" (varias seguidas).
        result = replace(result, "^\\s*(?:(?:este|o sea|pues|bueno|a ver|ok|okay)\\s*[,.…]+\\s*)+", with: "")
        result = replace(result, "^\\s*este\\s+(?=" + afterFillerEste + "(?![\\p{L}]))", with: "")
        // ", este, …" en medio de la frase.
        result = replace(result, ",\\s*este\\s*(?:,|…|\\.\\.\\.)\\s*", with: ", ")
        // 3) Palabras repetidas por error ("el el", "que que que").
        result = replace(result, "(?<![\\p{L}])([\\p{L}]+)(?:[\\s,]+\\1)+(?![\\p{L}])", with: "$1", caseInsensitive: true)
        // 4) Espacios.
        result = replace(result, "\\s{2,}", with: " ")
        result = replace(result, "\\s+([,.;:?!…])", with: "$1")
        result = result.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",;")))
        guard !result.isEmpty else { return text.trimmingCharacters(in: .whitespacesAndNewlines) }

        // 5) Mayúscula al inicio y después de punto.
        result = capitalizeSentences(result)

        // 6) Signos: ¿…? si es pregunta, punto final si es una frase completa.
        let wordCount = result.split(separator: " ").count
        let last = result.last.map(String.init) ?? ""
        let hasEnding = [".", "?", "!", "…", ":", ")", "\"", "”"].contains(last)
        if !hasEnding {
            let lower = result.lowercased()
            let isQuestion = lower.range(of: "^" + questionStart + "(?![\\p{L}])", options: .regularExpression) != nil
            if isQuestion {
                result = (result.hasPrefix("¿") || !isSpanish(lower) ? "" : "¿") + result + "?"
            } else if wordCount >= 4 {
                result += "."
            }
        }
        return result
    }

    private static func isSpanish(_ lower: String) -> Bool {
        lower.range(of: "^(what|how|why|when|where|who|which|can|could|do|is|are)(?![\\p{L}])", options: .regularExpression) == nil
    }

    /// Mayúscula al principio y después de ". ", "? " o "! " (no en "claude.ai" ni en "v1.8").
    private static func capitalizeSentences(_ text: String) -> String {
        var output = ""
        var capitalizeNext = true
        var sentenceEnded = false
        for character in text {
            if capitalizeNext, character.isLetter {
                output += String(character).uppercased()
                capitalizeNext = false
                continue
            }
            output.append(character)
            if ".?!".contains(character) {
                sentenceEnded = true
            } else if character.isWhitespace {
                if sentenceEnded { capitalizeNext = true }
                sentenceEnded = false
            } else {
                sentenceEnded = false
                if character.isLetter || character.isNumber { capitalizeNext = false }
            }
        }
        return output
    }

    private static func replace(_ text: String, _ pattern: String, with template: String,
                                caseInsensitive: Bool = true) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: caseInsensitive ? [.caseInsensitive] : []) else {
            return text
        }
        return regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }
}

// MARK: - Apple Intelligence (en tu Mac, gratis)

enum AppleIntelligence {
    /// ¿Tu Mac tiene Apple Intelligence activado y listo?
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        #endif
        return false
    }

    /// Por qué no está disponible (para Configuración).
    static var statusText: String {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            let availability = SystemLanguageModel.default.availability
            if case .available = availability { return "Lista ✓" }
            let text = String(describing: availability)
            if text.contains("NotEnabled") || text.contains("notEnabled") {
                return "Actívala en Ajustes › Apple Intelligence y Siri"
            }
            if text.contains("NotReady") || text.contains("notReady") {
                return "Se está descargando; intenta más tarde"
            }
            return "Tu Mac no es compatible"
        }
        #endif
        return "Necesita macOS 26 o más nuevo"
    }

    /// Pule el texto dictado. nil si no está disponible, tardó mucho o la respuesta no sirve.
    static func polish(_ text: String, keep: [String], timeout: Double = 4) async -> String? {
        guard isAvailable else { return nil }
        let keepList = (["Claude", "Claude Code", "Cowork", "ChatGPT"] + keep).joined(separator: ", ")
        let prompt = """
        Eres un corrector de textos dictados por voz. Corrige el texto que está entre <texto> y </texto>:
        - Quita muletillas (eh, este, o sea, mmm, bueno…) y palabras repetidas por error.
        - Corrige ortografía, acentos, mayúsculas y puntuación (usa ¿? y ¡! cuando toque).
        - No cambies el significado, no resumas, no agregues nada y no contestes lo que dice: es un mensaje para otra persona.
        - Deja el texto en el mismo idioma.
        - Escribe exactamente así estas palabras: \(keepList).
        Responde solo con el texto corregido, sin comillas ni explicaciones.

        <texto>
        \(text)
        </texto>
        """
        guard let output = await withTimeout(timeout, { await rewrite(prompt) }) else { return nil }
        return validated(output, original: text)
    }

    private static func rewrite(_ prompt: String) async -> String? {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            do {
                let session = LanguageModelSession()
                let response = try await session.respond(to: prompt)
                return response.content
            } catch {
                return nil
            }
        }
        #endif
        return nil
    }

    /// Descarta respuestas raras (explicaciones, textos mucho más largos, vacías).
    private static func validated(_ output: String, original: String) -> String? {
        var text = output.trimmingCharacters(in: .whitespacesAndNewlines)
        text = text.replacingOccurrences(of: "<texto>", with: "").replacingOccurrences(of: "</texto>", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        for (open, close) in [("«", "»"), ("\"", "\""), ("“", "”")] where text.hasPrefix(open) && text.hasSuffix(close) && text.count > 2 {
            text = String(text.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !text.isEmpty else { return nil }
        let lower = text.lowercased()
        let preambles = ["aquí", "aqui", "claro", "texto corregido", "el texto corregido", "here", "sure", "lo siento", "no puedo"]
        let originalLower = original.lowercased()
        if preambles.contains(where: { lower.hasPrefix($0) && !originalLower.hasPrefix($0) }) { return nil }
        if text.count > Int(Double(original.count) * 1.5) + 30 { return nil }
        if text.count < original.count / 3 { return nil }
        return text
    }

    /// Corre `work` pero no espera más de `seconds`.
    private static func withTimeout(_ seconds: Double, _ work: @escaping @Sendable () async -> String?) async -> String? {
        await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            let once = OnceFlag()
            Task {
                let result = await work()
                if once.claim() { continuation.resume(returning: result) }
            }
            Task {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                if once.claim() { continuation.resume(returning: nil) }
            }
        }
    }
}

/// Se puede "ganar" una sola vez (para el que termine primero).
final class OnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}

// MARK: - Todo junto

@MainActor
enum DictationPolisher {
    /// ¿Vamos a usar Apple Intelligence? (para avisarte que tarda un segundito)
    static var usesSmart: Bool {
        let dictionary = PersonalDictionary.shared
        return dictionary.cleanupEnabled && dictionary.smartEnabled && AppleIntelligence.isAvailable
    }

    /// Rápido (sin Apple Intelligence): correcciones + limpieza con reglas.
    static func quick(_ text: String) -> String {
        let dictionary = PersonalDictionary.shared
        var result = dictionary.applyRules(text)
        if dictionary.cleanupEnabled {
            result = DictationCleaner.clean(result)
        }
        return result
    }

    /// Completo: correcciones, limpieza y, si está activado, Apple Intelligence.
    static func polish(_ text: String) async -> String {
        let dictionary = PersonalDictionary.shared
        let ruled = dictionary.applyRules(text)
        guard dictionary.cleanupEnabled else { return ruled }
        let basic = DictationCleaner.clean(ruled)
        guard dictionary.smartEnabled, AppleIntelligence.isAvailable else { return basic }
        let started = Date()
        if let smart = await AppleIntelligence.polish(ruled, keep: dictionary.recognitionHints) {
            let result = dictionary.applyRules(smart)
            IslaLog.shared.add(String(format: "Apple Intelligence pulió tu texto (%.1f s)", Date().timeIntervalSince(started)))
            return result
        }
        IslaLog.shared.add("Apple Intelligence no respondió a tiempo: usé la limpieza normal")
        return basic
    }
}
