import Foundation

/// Cosas que la isla puede limpiar para liberar disco.
enum CleanupKind: String, CaseIterable, Identifiable {
    case trash, caches, downloads, screenshots, developer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .trash: return "Papelera"
        case .caches: return "Cachés de apps"
        case .downloads: return "Descargas de +\(CleanupKind.downloadsDays) días"
        case .screenshots: return "Capturas de +\(CleanupKind.screenshotsDays) días"
        case .developer: return "Cachés de desarrollo"
        }
    }

    static var downloadsDays: Int {
        let value = UserDefaults.standard.object(forKey: SettingsKeys.downloadsDays) as? Int ?? 30
        return max(value, 1)
    }

    static var screenshotsDays: Int {
        let value = UserDefaults.standard.object(forKey: SettingsKeys.screenshotsDays) as? Int ?? 14
        return max(value, 1)
    }

    var symbol: String {
        switch self {
        case .trash: return "trash"
        case .caches: return "square.stack.3d.up"
        case .downloads: return "arrow.down.circle"
        case .screenshots: return "camera.viewfinder"
        case .developer: return "hammer"
        }
    }

    var actionLabel: String {
        switch self {
        case .trash: return "Vaciar"
        case .caches, .developer: return "Borrar"
        case .downloads, .screenshots: return "A Papelera"
        }
    }

    var help: String {
        switch self {
        case .trash:
            return "Vacía la Papelera con Finder. No se puede deshacer."
        case .caches:
            return "Borra ~/Library/Caches. Las apps los vuelven a crear solas; conviene cerrar las apps abiertas antes."
        case .downloads:
            return "Mueve a la Papelera lo que lleva más de \(CleanupKind.downloadsDays) días en Descargas."
        case .screenshots:
            return "Mueve a la Papelera las capturas de pantalla de hace más de \(CleanupKind.screenshotsDays) días."
        case .developer:
            return "Borra DerivedData de Xcode y la caché de npm. Se regeneran al compilar o instalar."
        }
    }

    /// true = se borra directo (se regenera); false = va a la Papelera (se puede recuperar).
    var deletesPermanently: Bool {
        switch self {
        case .caches, .developer: return true
        default: return false
        }
    }
}

struct CleanupScan {
    /// nil = macOS no deja medirlo (por ejemplo, la Papelera sin permiso de disco completo).
    var bytes: Int64?
    var items: [URL]
}

/// Mide y limpia carpetas. Todo corre en segundo plano.
enum SystemCleaner {
    static func scan(_ kind: CleanupKind, screenshotFolder: URL) -> CleanupScan {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser

        switch kind {
        case .trash:
            let trash = home.appendingPathComponent(".Trash", isDirectory: true)
            guard let items = try? fileManager.contentsOfDirectory(at: trash, includingPropertiesForKeys: nil, options: []) else {
                return CleanupScan(bytes: nil, items: [])
            }
            return CleanupScan(bytes: totalSize(items), items: items)

        case .caches:
            let items = children(of: home.appendingPathComponent("Library/Caches", isDirectory: true))
            return CleanupScan(bytes: totalSize(items), items: items)

        case .downloads:
            let cutoff = Date().addingTimeInterval(-Double(CleanupKind.downloadsDays) * 24 * 3600)
            let items = children(of: home.appendingPathComponent("Downloads", isDirectory: true))
                .filter { addedDate($0) < cutoff }
            return CleanupScan(bytes: totalSize(items), items: items)

        case .screenshots:
            let cutoff = Date().addingTimeInterval(-Double(CleanupKind.screenshotsDays) * 24 * 3600)
            let items = children(of: screenshotFolder)
                .filter { ShelfStore.isScreenshot($0) && addedDate($0) < cutoff }
            return CleanupScan(bytes: totalSize(items), items: items)

        case .developer:
            var items = children(of: home.appendingPathComponent("Library/Developer/Xcode/DerivedData", isDirectory: true))
            let npmCache = home.appendingPathComponent(".npm/_cacache", isDirectory: true)
            if fileManager.fileExists(atPath: npmCache.path) {
                items.append(npmCache)
            }
            return CleanupScan(bytes: totalSize(items), items: items)
        }
    }

    /// Borra o manda a la Papelera. Devuelve cuánto espacio se movió o liberó.
    static func remove(_ items: [URL], permanently: Bool) -> Int64 {
        let fileManager = FileManager.default
        var freed: Int64 = 0
        for url in items {
            let size = allocatedSize(of: url)
            do {
                if permanently {
                    try fileManager.removeItem(at: url)
                } else {
                    try fileManager.trashItem(at: url, resultingItemURL: nil)
                }
                freed += size
            } catch {
                continue // archivos en uso o protegidos: se saltan
            }
        }
        return freed
    }

    /// Igual que runAppleScript, pero esperando en un hilo aparte
    /// (la ventana de contraseña puede quedarse abierta el tiempo que sea).
    static func runAppleScriptInBackground(_ source: String) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: SystemCleaner.runAppleScript(source))
            }
        }
    }

    /// Ejecuta AppleScript en un proceso aparte (no congela la isla).
    static func runAppleScript(_ source: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    // MARK: Ayudantes

    private static func children(of folder: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.addedToDirectoryDateKey, .creationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
    }

    private static func addedDate(_ url: URL) -> Date {
        let values = try? url.resourceValues(forKeys: [.addedToDirectoryDateKey, .creationDateKey])
        return values?.addedToDirectoryDate ?? values?.creationDate ?? Date()
    }

    private static func totalSize(_ items: [URL]) -> Int64 {
        var total: Int64 = 0
        for item in items { total += allocatedSize(of: item) }
        return total
    }

    static func allocatedSize(of url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return 0 }
        if values.isDirectory != true {
            return Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        var total: Int64 = 0
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: [],
            errorHandler: { _, _ in true }
        ) else { return 0 }
        while let file = enumerator.nextObject() as? URL {
            if let fileValues = try? file.resourceValues(forKeys: keys), fileValues.isDirectory != true {
                total += Int64(fileValues.totalFileAllocatedSize ?? fileValues.fileAllocatedSize ?? 0)
            }
        }
        return total
    }
}
