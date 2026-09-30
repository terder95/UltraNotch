import Foundation
import SwiftUI

// La letra de la canción que suena, sincronizada, desde LRCLIB (lrclib.net): un catálogo
// gratuito y abierto de letras, sin cuenta ni clave. UltraNotch solo le manda el título, el artista,
// el álbum y la duración de la canción. No todas las canciones tienen letra.

struct LyricLine: Identifiable, Equatable {
    let id: Int
    /// Segundo en que empieza.
    let time: Double
    let text: String
}

/// Lo que encontramos para una canción.
struct LyricsResult: Equatable {
    var lines: [LyricLine] = []
    var plain: String = ""
    var instrumental = false

    var isEmpty: Bool { lines.isEmpty && plain.isEmpty && !instrumental }
}

@MainActor
final class LyricsStore: ObservableObject {
    enum State: Equatable {
        case off, idle, loading, synced, plain, instrumental, notFound
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var result = LyricsResult()
    /// Buscar la letra de lo que suena.
    @Published var enabled = true {
        didSet {
            UserDefaults.standard.set(enabled, forKey: LyricsStore.enabledKey)
            update(for: lastTrack)
        }
    }

    static let enabledKey = "lyricsEnabled"

    private var lastTrack: NowPlaying.Track?
    private var currentKey: String?
    private var task: Task<Void, Never>?
    private var cache: [String: LyricsResult] = [:]

    init() {
        // Modo capturas: sin internet (la letra de ejemplo llega con cargarDemo).
        if ModoCapturas.activo { return }
        enabled = UserDefaults.standard.object(forKey: LyricsStore.enabledKey) as? Bool ?? true
    }

    /// Modo capturas: una letra inventada, ya sincronizada.
    func cargarDemo(_ lineas: [LyricLine]) {
        result = LyricsResult(lines: lineas)
        state = .synced
    }

    /// Cambió la canción: buscamos su letra (una sola vez por canción).
    func update(for track: NowPlaying.Track?) {
        lastTrack = track
        guard enabled else {
            task?.cancel()
            currentKey = nil
            result = LyricsResult()
            state = .off
            return
        }
        guard let track = track else {
            task?.cancel()
            currentKey = nil
            result = LyricsResult()
            state = .idle
            return
        }
        let key = track.key
        if key == currentKey && state != .idle { return }
        currentKey = key
        task?.cancel()
        if let cached = cache[key] {
            apply(cached)
            return
        }
        result = LyricsResult()
        state = .loading
        let title = track.title
        let artist = track.artist
        let album = track.album
        let duration = track.duration
        task = Task { @MainActor [weak self] in
            // Sin internet (o LRCLIB no contestó): lo intentamos otra vez un poco después.
            for attempt in 0..<3 {
                if attempt > 0 {
                    try? await Task.sleep(nanoseconds: 15_000_000_000)
                }
                let lookup = await LyricsFetcher.find(title: title, artist: artist, album: album, duration: duration)
                guard !Task.isCancelled, let strongSelf = self, strongSelf.currentKey == key else { return }
                if let found = lookup.result {
                    if strongSelf.cache.count > 40 { strongSelf.cache.removeAll() }
                    strongSelf.cache[key] = found
                    strongSelf.apply(found)
                    return
                }
                if !lookup.failed {
                    strongSelf.cache[key] = LyricsResult() // no la tienen: no volvemos a preguntar
                    strongSelf.result = LyricsResult()
                    strongSelf.state = .notFound
                    return
                }
                strongSelf.state = attempt < 2 ? .loading : .notFound
            }
        }
    }

    private func apply(_ found: LyricsResult) {
        result = found
        if !found.lines.isEmpty {
            state = .synced
        } else if found.instrumental {
            state = .instrumental
        } else if !found.plain.isEmpty {
            state = .plain
        } else {
            state = .notFound
        }
    }

    /// La línea que se canta en ese segundo (nil = todavía no empieza la letra).
    func lineIndex(at seconds: Double?) -> Int? {
        guard let seconds = seconds else { return nil }
        // Un poquito antes, para que la línea salga justo cuando se canta.
        return result.lines.lastIndex { $0.time <= seconds + 0.25 }
    }
}

// MARK: - LRCLIB

enum LyricsFetcher {
    private static let base = "https://lrclib.net/api"

    /// Lo que pasó al buscar: la letra, o si no la tienen (`failed` = no se pudo preguntar).
    struct Lookup {
        var result: LyricsResult?
        var failed = false
    }

    private enum Response {
        case ok(Any)
        case missing
        case failed
    }

    /// Primero la búsqueda exacta (título, artista, álbum y duración); si no, una búsqueda
    /// con el título limpio ("- Remastered", "(feat. …)" fuera).
    static func find(title: String, artist: String, album: String, duration: Double?) async -> Lookup {
        var failed = false
        if let duration = duration, !album.isEmpty {
            switch await get(title: title, artist: artist, album: album, duration: duration) {
            case .ok(let json):
                if let item = json as? [String: Any], let parsed = result(from: item), !parsed.isEmpty {
                    return Lookup(result: parsed)
                }
            case .missing:
                break
            case .failed:
                failed = true
            }
        }
        let clean = cleanTitle(title)
        let list: [[String: Any]]
        switch await search(title: clean, artist: artist) {
        case .ok(let json):
            list = json as? [[String: Any]] ?? []
        case .missing:
            list = []
        case .failed:
            return Lookup(result: nil, failed: true)
        }
        // La que mejor le queda: con tiempos y de la misma duración (±4 s).
        let scored = list.compactMap { item -> (LyricsResult, Int)? in
            guard let parsed = result(from: item), !parsed.isEmpty else { return nil }
            var score = 0
            if !parsed.lines.isEmpty { score += 2 }
            if let duration = duration, let theirs = (item["duration"] as? NSNumber)?.doubleValue,
               abs(theirs - duration) <= 4 {
                score += 3
            }
            return (parsed, score)
        }
        return Lookup(result: scored.max { $0.1 < $1.1 }?.0, failed: failed && scored.isEmpty)
    }

    private static func get(title: String, artist: String, album: String, duration: Double) async -> Response {
        var components = URLComponents(string: base + "/get")
        components?.queryItems = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist),
            URLQueryItem(name: "album_name", value: album),
            URLQueryItem(name: "duration", value: String(Int(duration.rounded())))
        ]
        return await fetch(components)
    }

    private static func search(title: String, artist: String) async -> Response {
        var components = URLComponents(string: base + "/search")
        components?.queryItems = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist)
        ]
        return await fetch(components)
    }

    private static func fetch(_ components: URLComponents?) async -> Response {
        var components = components
        // Un "+" sin codificar se leería como espacio ("1+1" → "1 1").
        let encodedQuery = components?.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        components?.percentEncodedQuery = encodedQuery
        guard let url = components?.url else { return .failed }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("UltraNotch (app del notch de Mac)", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request) else { return .failed }
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 404 { return .missing }
        guard code == 200, let json = try? JSONSerialization.jsonObject(with: data) else { return .failed }
        return .ok(json)
    }

    private static func result(from item: [String: Any]) -> LyricsResult? {
        var found = LyricsResult()
        found.instrumental = item["instrumental"] as? Bool ?? false
        if let synced = item["syncedLyrics"] as? String {
            found.lines = parseLRC(synced)
        }
        found.plain = (item["plainLyrics"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return found
    }

    /// "Canción - Remastered 2011 (feat. Alguien)" → "Canción"
    static func cleanTitle(_ title: String) -> String {
        var text = title
        if let dash = text.range(of: " - ") { text = String(text[..<dash.lowerBound]) }
        if let regex = try? NSRegularExpression(pattern: "\\s*[\\(\\[](feat|ft|with|con)\\.?[^\\)\\]]*[\\)\\]]",
                                                options: [.caseInsensitive]) {
            text = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
        }
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? title : trimmed
    }

    /// Lee el formato LRC: "[01:23.45] texto" (una línea puede traer varios tiempos).
    static func parseLRC(_ text: String) -> [LyricLine] {
        guard let stamp = try? NSRegularExpression(pattern: "\\[(\\d{1,3}):(\\d{1,2}(?:[.:]\\d{1,3})?)\\]") else { return [] }
        var offset = 0.0
        var pairs: [(Double, String)] = []
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.lowercased().hasPrefix("[offset:") {
                let digits = line.dropFirst(8).dropLast().trimmingCharacters(in: .whitespaces)
                offset = (Double(digits) ?? 0) / 1000
                continue
            }
            let range = NSRange(line.startIndex..., in: line)
            let matches = stamp.matches(in: line, range: range)
            guard let last = matches.last, let tail = Range(NSRange(location: last.range.upperBound,
                                                                       length: range.length - last.range.upperBound),
                                                             in: line) else { continue }
            let words = String(line[tail]).trimmingCharacters(in: .whitespaces)
            for match in matches {
                guard let minutesRange = Range(match.range(at: 1), in: line),
                      let secondsRange = Range(match.range(at: 2), in: line),
                      let minutes = Double(line[minutesRange]),
                      let seconds = Double(line[secondsRange].replacingOccurrences(of: ":", with: ".")) else { continue }
                // Un offset positivo adelanta la letra.
                pairs.append((max(0, minutes * 60 + seconds - offset), words))
            }
        }
        return pairs.sorted { $0.0 < $1.0 }.enumerated().map { index, pair in
            LyricLine(id: index, time: pair.0, text: pair.1)
        }
    }
}
