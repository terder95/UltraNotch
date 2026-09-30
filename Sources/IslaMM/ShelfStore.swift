import AppKit
import SwiftUI
import Combine
import UniformTypeIdentifiers

/// Un archivo en el estante de la isla.
struct ShelfItem: Identifiable, Codable, Equatable {
    enum Source: String, Codable, CaseIterable {
        case screenshot, download, dropped

        var label: String {
            switch self {
            case .screenshot: return "Capturas"
            case .download: return "Descargas"
            case .dropped: return "Arrastrados"
            }
        }

        var symbol: String {
            switch self {
            case .screenshot: return "camera.fill"
            case .download: return "arrow.down"
            case .dropped: return "tray.and.arrow.down.fill"
            }
        }

        var tint: Color {
            switch self {
            case .screenshot: return Theme.screenshot
            case .download: return Theme.download
            case .dropped: return Color.primary
            }
        }

        var badgeColor: Color {
            switch self {
            case .screenshot: return Theme.screenshot
            case .download: return Theme.download
            case .dropped: return Color.gray
            }
        }
    }

    var id = UUID()
    var url: URL
    var source: Source
    var date = Date()
}

private struct WatchMode {
    var screenshots = false
    var downloads = false
}

/// El estante: capturas de pantalla, descargas nuevas y lo que arrastres a la isla.
@MainActor
final class ShelfStore: ObservableObject {
    @Published private(set) var items: [ShelfItem] = []
    @Published var filter: ShelfItem.Source? = nil
    @Published var watchScreenshots = true {
        didSet { settingsChanged() }
    }
    @Published var watchDownloads = true {
        didSet { settingsChanged() }
    }

    /// Se llama cuando llega algo automáticamente (captura o descarga).
    var onAutoAdded: ((ShelfItem) -> Void)?

    private var watchers: [FolderWatcher] = []
    private let maxItems = 40
    private let storeURL = AppPaths.support.appendingPathComponent("estante.json")
    private let dropsFolder = AppPaths.support.appendingPathComponent("Soltados", isDirectory: true)

    private static let screenshotsKey = "watchScreenshots"
    private static let downloadsKey = "watchDownloads"

    init() {
        // Modo capturas: sin leer tus carpetas (los archivos de ejemplo llegan con cargarDemo).
        if ModoCapturas.activo { return }
        let defaults = UserDefaults.standard
        watchScreenshots = defaults.object(forKey: ShelfStore.screenshotsKey) as? Bool ?? true
        watchDownloads = defaults.object(forKey: ShelfStore.downloadsKey) as? Bool ?? true
        try? FileManager.default.createDirectory(at: dropsFolder, withIntermediateDirectories: true)
        load()
        restartWatchers()
    }

    /// Modo capturas: archivos de ejemplo (no se guardan).
    func cargarDemo(_ demo: [ShelfItem]) {
        items = demo
    }

    // MARK: Lectura para la interfaz

    var visibleItems: [ShelfItem] {
        guard let current = filter else { return items }
        return items.filter { $0.source == current }
    }

    func count(_ source: ShelfItem.Source?) -> Int {
        guard let source = source else { return items.count }
        return items.filter { $0.source == source }.count
    }

    // MARK: Agregar / quitar

    func add(_ url: URL, source: ShelfItem.Source, announce: Bool = false) {
        let clean = ((url as NSURL).filePathURL ?? url).standardizedFileURL
        guard FileManager.default.fileExists(atPath: clean.path) else { return }
        var list = items
        list.removeAll { $0.url == clean }
        let item = ShelfItem(url: clean, source: source)
        list.insert(item, at: 0)
        if list.count > maxItems {
            list.removeLast(list.count - maxItems)
        }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            items = list
        }
        save()
        if announce {
            onAutoAdded?(item)
        }
    }

    func remove(_ item: ShelfItem) {
        withAnimation(.easeOut(duration: 0.2)) {
            items.removeAll { $0.id == item.id }
        }
        save()
    }

    func clear() {
        withAnimation(.easeOut(duration: 0.2)) {
            items.removeAll()
        }
        save()
    }

    /// Quita del estante los archivos que ya no existen.
    func prune() {
        let alive = items.filter { FileManager.default.fileExists(atPath: $0.url.path) }
        if alive.count != items.count {
            items = alive
            save()
        }
    }

    // MARK: Soltar archivos sobre la isla

    func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var accepted = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                accepted = true
                _ = provider.loadObject(ofClass: URL.self) { [weak self] url, _ in
                    guard let url = url else { return }
                    Task { @MainActor in
                        self?.add(url, source: .dropped)
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                // Imágenes arrastradas desde el navegador: se guardan en una copia.
                accepted = true
                let folder = dropsFolder
                let suggested = provider.suggestedName
                _ = provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { [weak self] tempURL, _ in
                    guard let tempURL = tempURL,
                          let saved = ShelfStore.persistDroppedFile(tempURL, into: folder, suggestedName: suggested) else { return }
                    Task { @MainActor in
                        self?.add(saved, source: .dropped)
                    }
                }
            }
        }
        return accepted
    }

    // MARK: AirDrop

    /// Manda archivos del estante por AirDrop.
    func airDrop(_ items: [ShelfItem]) {
        AirDropSender.shared.send(items.map { $0.url })
    }

    /// Lo que soltaste del lado de AirDrop: se manda sin guardarlo en el estante.
    func airDrop(_ providers: [NSItemProvider]) -> Bool {
        let usable = providers.filter {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
                || $0.hasItemConformingToTypeIdentifier(UTType.image.identifier)
        }
        guard !usable.isEmpty else { return false }
        let folder = dropsFolder
        Task { @MainActor in
            var urls: [URL] = []
            for provider in usable {
                if let url = await ShelfStore.fileURL(from: provider, dropsFolder: folder) {
                    urls.append(url)
                }
            }
            AirDropSender.shared.send(urls)
        }
        return true
    }

    /// El archivo que viene en lo que soltaste (las imágenes del navegador se guardan en una copia).
    nonisolated static func fileURL(from provider: NSItemProvider, dropsFolder: URL) async -> URL? {
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            return await withCheckedContinuation { (continuation: CheckedContinuation<URL?, Never>) in
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    // Finder a veces manda "file:///.file/id=…": lo convertimos a la ruta real.
                    continuation.resume(returning: url.map { (($0 as NSURL).filePathURL ?? $0).standardizedFileURL })
                }
            }
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            let suggested = provider.suggestedName
            return await withCheckedContinuation { (continuation: CheckedContinuation<URL?, Never>) in
                _ = provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { tempURL, _ in
                    guard let tempURL = tempURL else {
                        continuation.resume(returning: nil)
                        return
                    }
                    let saved = ShelfStore.persistDroppedFile(tempURL, into: dropsFolder, suggestedName: suggested)
                    continuation.resume(returning: saved)
                }
            }
        }
        return nil
    }

    nonisolated static func persistDroppedFile(_ temp: URL, into folder: URL, suggestedName: String?) -> URL? {
        let ext = temp.pathExtension.isEmpty ? "png" : temp.pathExtension
        var base = "Imagen"
        if let suggestedName = suggestedName, !suggestedName.isEmpty {
            base = (suggestedName as NSString).deletingPathExtension
        }
        let stamp = Int(Date().timeIntervalSince1970)
        let unique = UUID().uuidString.prefix(6)
        let destination = folder.appendingPathComponent("\(base)-\(stamp)-\(unique).\(ext)")
        do {
            try FileManager.default.copyItem(at: temp, to: destination)
            return destination
        } catch {
            return nil
        }
    }

    // MARK: Vigilar carpetas

    private func settingsChanged() {
        let defaults = UserDefaults.standard
        defaults.set(watchScreenshots, forKey: ShelfStore.screenshotsKey)
        defaults.set(watchDownloads, forKey: ShelfStore.downloadsKey)
        restartWatchers()
    }

    func restartWatchers() {
        for watcher in watchers { watcher.stop() }
        watchers.removeAll()

        var modes: [String: WatchMode] = [:]
        if watchScreenshots {
            let path = ShelfStore.screenshotFolder().standardizedFileURL.path
            modes[path, default: WatchMode()].screenshots = true
        }
        if watchDownloads, let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            let path = downloads.standardizedFileURL.path
            modes[path, default: WatchMode()].downloads = true
        }

        for (path, mode) in modes {
            let watcher = FolderWatcher(folder: URL(fileURLWithPath: path, isDirectory: true))
            watcher.onNewFile = { [weak self] url in
                self?.autoDetected(url, mode: mode)
            }
            watcher.start()
            watchers.append(watcher)
        }
    }

    private func autoDetected(_ url: URL, mode: WatchMode) {
        let isShot = ShelfStore.isScreenshot(url)
        if isShot && mode.screenshots {
            add(url, source: .screenshot, announce: true)
        } else if mode.downloads {
            add(url, source: isShot ? .screenshot : .download, announce: true)
        }
    }

    /// Dónde guarda macOS las capturas (⌘⇧5 › Opciones). Por defecto: Escritorio.
    nonisolated static func screenshotFolder() -> URL {
        if let location = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location"),
           !location.isEmpty {
            let path = (location as NSString).expandingTildeInPath
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue {
                return URL(fileURLWithPath: path, isDirectory: true)
            }
        }
        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
    }

    /// macOS marca las capturas con un atributo oculto; también revisamos el nombre.
    nonisolated static func isScreenshot(_ url: URL) -> Bool {
        let flagged = url.withUnsafeFileSystemRepresentation { path -> Bool in
            guard let path = path else { return false }
            return getxattr(path, "com.apple.metadata:kMDItemIsScreenCapture", nil, 0, 0, 0) >= 0
        }
        if flagged { return true }
        let name = url.lastPathComponent.lowercased()
        let prefixes = [
            "captura de pantalla", "grabación de pantalla", "grabacion de pantalla",
            "screenshot", "screen shot", "screen recording"
        ]
        return prefixes.contains { name.hasPrefix($0) }
    }

    // MARK: Guardar en disco

    private func load() {
        guard let data = try? Data(contentsOf: storeURL),
              let saved = try? JSONDecoder().decode([ShelfItem].self, from: data) else { return }
        items = saved.filter { FileManager.default.fileExists(atPath: $0.url.path) }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }
}
