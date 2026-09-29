import AppKit
import SwiftUI

// Lo que suena en Spotify o en Música (Apple Music): canción, carátula, avance y controles.
//
// • La canción: las dos apps anuncian cada cambio (y si pausas) a todo el sistema; Isla solo
//   escucha esos avisos, así que no gasta batería.
// • La carátula: Spotify la da por su página pública de la canción; Música la entrega directo
//   (o la buscamos en el catálogo de Apple por artista y título).
// • El avance (para la letra): mientras ves la pestaña Hoy, Isla le pregunta a la app en qué
//   segundo va, cada 3 s, y entre preguntas lo calcula sola.
// • Los botones: AppleScript a esa app (la primera vez macOS te pide permiso) o, si no se puede,
//   las teclas multimedia de la Mac.

@MainActor
final class NowPlaying: ObservableObject {
    enum Player: String {
        case spotify, music

        var bundleID: String {
            switch self {
            case .spotify: return "com.spotify.client"
            case .music: return "com.apple.Music"
            }
        }

        var name: String {
            switch self {
            case .spotify: return "Spotify"
            case .music: return "Música"
            }
        }

        /// Nombre para AppleScript.
        var scriptName: String {
            switch self {
            case .spotify: return "Spotify"
            case .music: return "Music"
            }
        }

        @MainActor var isInstalled: Bool {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
        }

        @MainActor var isRunning: Bool {
            !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
        }

        @MainActor var icon: NSImage? {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
            return NSWorkspace.shared.icon(forFile: url.path)
        }
    }

    struct Track: Equatable {
        var title: String
        var artist: String
        var album: String
        var player: Player
        var playing: Bool
        /// Segundos que dura (si la app lo dijo).
        var duration: Double? = nil
        /// "spotify:track:…" en Spotify.
        var spotifyID: String? = nil

        /// Para saber si es la misma canción.
        var key: String { "\(player.rawValue)|\(artist.lowercased())|\(title.lowercased())" }
    }

    @Published private(set) var track: Track?
    /// La carátula de la canción que suena (nil = aún no llega o no hay).
    @Published private(set) var artwork: NSImage?
    /// El color principal de la carátula (para las barritas y los detalles).
    @Published private(set) var artColor: Color?

    /// Mostrar la música en la isla (pestaña Hoy).
    @Published var enabled = true {
        didSet {
            UserDefaults.standard.set(enabled, forKey: Keys.enabled)
            if !enabled { clear() }
        }
    }
    /// Aviso cortito junto al notch cuando cambia la canción.
    @Published var announce = true {
        didSet { UserDefaults.standard.set(announce, forKey: Keys.announce) }
    }
    /// Con la isla cerrada: el monito se pone audífonos y salen barritas del color de la carátula.
    @Published var showInIsland = true {
        didSet { UserDefaults.standard.set(showInIsland, forKey: Keys.inIsland) }
    }

    /// Cambió la canción (para el aviso junto al notch).
    var onNewSong: ((Track) -> Void)?
    /// Cambió la canción o dejó de sonar (para buscar la letra).
    var onTrackChanged: ((Track?) -> Void)?

    var isPlaying: Bool { enabled && track?.playing == true }

    private enum Keys {
        static let enabled = "musicEnabled"
        static let announce = "musicAnnounce"
        static let inIsland = "musicInIsland"
    }

    private var observers: [NSObjectProtocol] = []
    private var relays: [DistributedRelay] = []
    private var askedOnce = false
    /// Segundo en que iba la canción la última vez que lo supimos, y cuándo.
    private var positionBase: Double?
    private var positionAt = Date()
    private var watchers = 0
    private var pollTask: Task<Void, Never>?
    private var artworkTask: Task<Void, Never>?
    private var artworkCache: [String: NSImage] = [:]

    init() {
        let defaults = UserDefaults.standard
        enabled = defaults.object(forKey: Keys.enabled) as? Bool ?? true
        announce = defaults.object(forKey: Keys.announce) as? Bool ?? true
        showInIsland = defaults.object(forKey: Keys.inIsland) as? Bool ?? true
    }

    func start() {
        guard observers.isEmpty, relays.isEmpty else { return }
        let center = DistributedNotificationCenter.default()
        let sources: [(String, Player)] = [
            ("com.spotify.client.PlaybackStateChanged", .spotify),
            ("com.apple.Music.playerInfo", .music),
            ("com.apple.iTunes.playerInfo", .music)
        ]
        for (name, player) in sources {
            // "Entregar de inmediato": Isla casi nunca es la app activa y macOS guardaría los avisos.
            let relay = DistributedRelay { [weak self] note in
                let info = NowPlaying.strings(note.userInfo)
                Task { @MainActor in
                    self?.handle(info, player: player)
                }
            }
            center.addObserver(relay, selector: #selector(DistributedRelay.fire(_:)), name: Notification.Name(name),
                               object: nil, suspensionBehavior: .deliverImmediately)
            relays.append(relay)
        }
        // Si cierras la app de música, ya no hay nada sonando.
        let quit = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let bundle = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            Task { @MainActor in
                guard let strongSelf = self, let bundle = bundle, strongSelf.track?.player.bundleID == bundle else { return }
                strongSelf.clear()
            }
        }
        observers.append(quit)
    }

    /// Copia lo que necesitamos del aviso como textos (así cruza de hilo sin problema).
    nonisolated private static func strings(_ info: [AnyHashable: Any]?) -> [String: String] {
        var result: [String: String] = [:]
        for (key, value) in info ?? [:] {
            guard let key = key as? String else { continue }
            if let text = value as? String {
                result[key] = text
            } else if let number = value as? NSNumber {
                result[key] = number.stringValue
            }
        }
        return result
    }

    private func clear() {
        let hadTrack = track != nil
        track = nil
        artwork = nil
        artColor = nil
        positionBase = nil
        artworkTask?.cancel()
        if hadTrack { onTrackChanged?(nil) }
    }

    private func handle(_ info: [String: String], player: Player) {
        guard enabled else { return }
        let state = info["Player State"] ?? ""
        if state == "Stopped" {
            if track == nil || track?.player == player { clear() }
            return
        }
        let title = info["Name"] ?? track?.title ?? ""
        guard !title.isEmpty else { return }
        // Spotify manda "Duration" y Música "Total Time", los dos en milisegundos.
        let milliseconds = Double(info["Duration"] ?? info["Total Time"] ?? "")
        let next = Track(
            title: title,
            artist: info["Artist"] ?? "",
            album: info["Album"] ?? "",
            player: player,
            playing: state == "Playing",
            duration: milliseconds.map { $0 / 1000 },
            spotifyID: info["Track ID"]
        )
        let isNewSong = track?.key != next.key
        // El avance: lo que diga la app; si no, lo que llevábamos (o 0 si es otra canción).
        let now = Date()
        if let position = Double(info["Playback Position"] ?? "") {
            positionBase = position
        } else if isNewSong {
            positionBase = 0
        } else {
            positionBase = position(at: now)
        }
        positionAt = now
        track = next
        if isNewSong {
            loadArtwork(for: next)
            onTrackChanged?(next)
            if next.playing && announce { onNewSong?(next) }
        }
    }

    /// La primera vez que abres la pestaña Hoy: si ya sonaba algo antes de abrir Isla, lo preguntamos.
    func refreshIfNeeded() {
        guard enabled, track == nil, !askedOnce else { return }
        guard let player = [Player.spotify, .music].first(where: { $0.isRunning }) else { return }
        askedOnce = true
        let app = player.scriptName
        // Spotify da la duración en milisegundos; Música, en segundos.
        let duration = player == .spotify ? "((duration of t) / 1000)" : "(duration of t)"
        let identifier = player == .spotify ? "(id of t)" : "\"\""
        let script = """
        if application "\(app)" is running then
            tell application "\(app)"
                if player state is stopped then return ""
                set t to current track
                return (name of t) & linefeed & (artist of t) & linefeed & (album of t) & linefeed & (player state as string) & linefeed & (\(duration) as string) & linefeed & (player position as string) & linefeed & \(identifier)
            end tell
        end if
        return ""
        """
        Task { @MainActor [weak self] in
            guard let output = await ScriptRunner.run(script, timeout: 4), !output.isEmpty else { return }
            let parts = output.components(separatedBy: "\n")
            guard parts.count >= 4, let strongSelf = self, strongSelf.track == nil else { return }
            let found = Track(
                title: parts[0], artist: parts[1], album: parts[2], player: player,
                playing: parts[3].lowercased().contains("playing"),
                duration: parts.count > 4 ? NowPlaying.number(parts[4]) : nil,
                spotifyID: parts.count > 6 && !parts[6].isEmpty ? parts[6] : nil
            )
            strongSelf.positionBase = parts.count > 5 ? NowPlaying.number(parts[5]) : nil
            strongSelf.positionAt = Date()
            strongSelf.track = found
            strongSelf.loadArtwork(for: found)
            strongSelf.onTrackChanged?(found)
        }
    }

    /// "12,5" o "12.5" → 12.5 (AppleScript usa el separador de tu región).
    nonisolated static func number(_ text: String) -> Double? {
        Double(text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: "."))
    }

    // MARK: Avance de la canción

    /// En qué segundo va la canción (nil si no lo sabemos).
    func position(at date: Date = Date()) -> Double? {
        guard let base = positionBase, let track = track else { return nil }
        var value = base
        if track.playing { value += date.timeIntervalSince(positionAt) }
        if let duration = track.duration, duration > 0 { value = min(value, duration) }
        return max(0, value)
    }

    /// La pestaña Hoy está a la vista: preguntamos el avance cada 3 s (solo mientras se ve).
    func beginWatchingPosition() {
        watchers += 1
        guard pollTask == nil else { return }
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let strongSelf = self else { return }
                await strongSelf.pollPosition()
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }

    func endWatchingPosition() {
        watchers = max(0, watchers - 1)
        if watchers == 0 {
            pollTask?.cancel()
            pollTask = nil
        }
    }

    private func pollPosition() async {
        guard let current = track, current.player.isRunning else { return }
        let app = current.player.scriptName
        let duration = current.player == .spotify ? "((duration of current track) / 1000)" : "(duration of current track)"
        let script = """
        if application "\(app)" is running then
            tell application "\(app)"
                if player state is stopped then return ""
                return (player position as string) & "|" & (\(duration) as string) & "|" & (player state as string)
            end tell
        end if
        return ""
        """
        let asked = Date()
        guard let output = await ScriptRunner.run(script, timeout: 2.5), !output.isEmpty else { return }
        let parts = output.components(separatedBy: "|")
        guard parts.count >= 3, let position = NowPlaying.number(parts[0]),
              var updated = track, updated.key == current.key else { return }
        // La respuesta tardó un poquito: la medimos a la mitad del camino.
        positionBase = position
        positionAt = asked.addingTimeInterval(Date().timeIntervalSince(asked) / 2)
        if updated.duration == nil { updated.duration = NowPlaying.number(parts[1]) }
        updated.playing = parts[2].lowercased().contains("playing")
        if updated != track { track = updated }
    }

    // MARK: Carátula

    private func loadArtwork(for current: Track) {
        artworkTask?.cancel()
        let key = current.key
        if let cached = artworkCache[key] {
            setArtwork(cached)
            return
        }
        artwork = nil
        artColor = nil
        artworkTask = Task { @MainActor [weak self] in
            let image = await ArtworkLoader.load(for: current)
            guard !Task.isCancelled, let strongSelf = self, strongSelf.track?.key == key else { return }
            if let image = image {
                if strongSelf.artworkCache.count > 30 { strongSelf.artworkCache.removeAll() }
                strongSelf.artworkCache[key] = image
            }
            strongSelf.setArtwork(image)
        }
    }

    private func setArtwork(_ image: NSImage?) {
        artwork = image
        artColor = image.flatMap { ArtworkLoader.mainColor(of: $0) }.map { Color(nsColor: $0) }
    }

    // MARK: Controles

    func playPause() {
        // Guardamos en qué iba antes de cambiar (para que el avance no brinque).
        positionBase = position()
        positionAt = Date()
        control("playpause", mediaKey: NowPlaying.keyPlay)
        if var current = track {
            current.playing.toggle() // se ve al instante; el aviso de la app lo confirma
            track = current
        }
    }

    func next() {
        control("next track", mediaKey: NowPlaying.keyNext)
    }

    func previous() {
        control("previous track", mediaKey: NowPlaying.keyPrevious)
    }

    /// Brinca a ese segundo (tocando una línea de la letra).
    func seek(to seconds: Double) {
        guard let player = track?.player, player.isRunning else { return }
        let target = max(0, seconds)
        positionBase = target
        positionAt = Date()
        let value = String(format: "%.2f", target)
        let script = "tell application \"\(player.scriptName)\" to set player position to \(value)"
        Task { _ = await ScriptRunner.run(script, timeout: 3) }
    }

    func openPlayer() {
        let player = track?.player ?? ([Player.spotify, .music].first(where: { $0.isRunning || $0.isInstalled }) ?? .music)
        AppActivator.bringToFront(player.bundleID)
    }

    /// Con la app conocida usamos AppleScript (va directo a esa app); si no se puede, la tecla multimedia.
    private func control(_ command: String, mediaKey: Int32) {
        guard let player = track?.player, player.isRunning else {
            NowPlaying.postMediaKey(mediaKey)
            return
        }
        let script = "tell application \"\(player.scriptName)\" to \(command)"
        Task { @MainActor in
            if await ScriptRunner.run(script, timeout: 3) == nil {
                NowPlaying.postMediaKey(mediaKey)
            }
        }
    }

    // Teclas multimedia (NX_KEYTYPE_PLAY / NEXT / PREVIOUS).
    private static let keyPlay: Int32 = 16
    private static let keyNext: Int32 = 17
    private static let keyPrevious: Int32 = 18

    static func postMediaKey(_ key: Int32) {
        for down in [true, false] {
            let flags = NSEvent.ModifierFlags(rawValue: down ? 0xa00 : 0xb00)
            let data1 = Int((key << 16) | ((down ? 0xa : 0xb) << 8))
            let event = NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: flags,
                                           timestamp: 0, windowNumber: 0, context: nil,
                                           subtype: 8, data1: data1, data2: -1)
            event?.cgEvent?.post(tap: .cghidEventTap)
        }
    }

    /// "3:07"
    static func clock(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - Carátulas

enum ArtworkLoader {
    /// Busca la carátula: Spotify (su página pública), Música (directo de la app) y, si no,
    /// el catálogo de Apple por artista y título.
    static func load(for track: NowPlaying.Track) async -> NSImage? {
        if track.player == .spotify, let id = track.spotifyID, id.hasPrefix("spotify:track:"),
           let image = await spotifyArtwork(id) {
            return image
        }
        if track.player == .music, let image = await musicAppArtwork() {
            return image
        }
        return await appleCatalogArtwork(artist: track.artist, title: track.title)
    }

    /// La "tarjeta" pública de la canción en Spotify trae su carátula (oEmbed).
    private static func spotifyArtwork(_ id: String) async -> NSImage? {
        let trackID = id.replacingOccurrences(of: "spotify:track:", with: "")
        var components = URLComponents(string: "https://open.spotify.com/oembed")
        components?.queryItems = [URLQueryItem(name: "url", value: "https://open.spotify.com/track/\(trackID)")]
        guard let url = components?.url,
              let json = await fetchJSON(url) as? [String: Any],
              let thumbnail = json["thumbnail_url"] as? String,
              let imageURL = URL(string: thumbnail) else { return nil }
        return await fetchImage(imageURL)
    }

    /// Música guarda la carátula en la canción: la pedimos por AppleScript a un archivo temporal.
    private static func musicAppArtwork() async -> NSImage? {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("isla-caratula-\(UUID().uuidString).dat")
        let script = """
        tell application "Music"
            if player state is stopped then return ""
            set t to current track
            if (count of artworks of t) is 0 then return ""
            set d to raw data of artwork 1 of t
        end tell
        set f to open for access (POSIX file "\(file.path)") with write permission
        set eof f to 0
        write d to f
        close access f
        return "ok"
        """
        defer { try? FileManager.default.removeItem(at: file) }
        guard await ScriptRunner.run(script, timeout: 5) == "ok" else { return nil }
        guard let data = try? Data(contentsOf: file) else { return nil }
        return NSImage(data: data)
    }

    /// Catálogo de Apple (iTunes Search): gratis y sin cuenta.
    private static func appleCatalogArtwork(artist: String, title: String) async -> NSImage? {
        let term = "\(artist) \(title)".trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty else { return nil }
        var components = URLComponents(string: "https://itunes.apple.com/search")
        components?.queryItems = [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "1")
        ]
        // Un "+" sin codificar se leería como espacio ("1+1" → "1 1").
        let encodedQuery = components?.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        components?.percentEncodedQuery = encodedQuery
        guard let url = components?.url,
              let json = await fetchJSON(url) as? [String: Any],
              let results = json["results"] as? [[String: Any]],
              let small = results.first?["artworkUrl100"] as? String,
              let imageURL = URL(string: small.replacingOccurrences(of: "100x100bb", with: "600x600bb")) else { return nil }
        return await fetchImage(imageURL)
    }

    private static func fetchJSON(_ url: URL) async -> Any? {
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.setValue("Isla (app del notch)", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode ?? 200 < 400 else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    private static func fetchImage(_ url: URL) async -> NSImage? {
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode ?? 200 < 400 else { return nil }
        return NSImage(data: data)
    }

    /// El color principal de la carátula, un poco más vivo (para que se vea sobre el negro).
    static func mainColor(of image: NSImage) -> NSColor? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        let drawn: Bool = pixel.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                                          bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard drawn else { return nil }
        let average = NSColor(srgbRed: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255,
                              blue: CGFloat(pixel[2]) / 255, alpha: 1)
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        average.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        if saturation < 0.08 {
            return NSColor(white: 0.86, alpha: 1) // carátula en blanco y negro: gris clarito
        }
        return NSColor(hue: hue, saturation: max(saturation, 0.5), brightness: max(brightness, 0.8), alpha: 1)
    }
}

/// Recibe un aviso del sistema y se lo pasa a quien lo necesite.
final class DistributedRelay: NSObject {
    private let handler: (Notification) -> Void

    init(_ handler: @escaping (Notification) -> Void) {
        self.handler = handler
    }

    @objc func fire(_ notification: Notification) {
        handler(notification)
    }
}

/// Corre AppleScript en otro proceso (así la isla nunca se traba). nil si falló, tardó o no hubo permiso.
enum ScriptRunner {
    static func run(_ script: String, timeout: Double) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                process.arguments = ["-e", script]
                let output = Pipe()
                process.standardOutput = output
                process.standardError = Pipe()
                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: nil)
                    return
                }
                let deadline = Date().addingTimeInterval(timeout)
                while process.isRunning && Date() < deadline {
                    usleep(40_000)
                }
                if process.isRunning {
                    process.terminate()
                    continuation.resume(returning: nil)
                    return
                }
                let data = output.fileHandleForReading.readDataToEndOfFile()
                let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                continuation.resume(returning: process.terminationStatus == 0 ? (text ?? "") : nil)
            }
        }
    }
}
