import Foundation

/// Vigila una carpeta y avisa cuando aparece un archivo NUEVO y ya terminado
/// (ignora descargas a medias como .crdownload, .download, .part…).
@MainActor
final class FolderWatcher {
    let folder: URL
    var onNewFile: ((URL) -> Void)?

    private var source: DispatchSourceFileSystemObject?
    private var known = Set<String>()
    private var pending: [String: (size: Int, since: Date)] = [:]
    private var needsBaseline = true
    private var scanTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?

    private static let partialExtensions: Set<String> = [
        "crdownload", "download", "part", "partial", "tmp", "opdownload", "downloading", "aria2"
    ]

    init(folder: URL) {
        self.folder = folder
    }

    func start() {
        stop()
        let descriptor = open(folder.path, O_EVTONLY)
        guard descriptor >= 0 else {
            // La carpeta no existe o aún no hay permiso: reintenta en 5 s.
            retryTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard !Task.isCancelled else { return }
                self?.start()
            }
            return
        }

        let newSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete, .link],
            queue: .main
        )
        newSource.setEventHandler { [weak self] in
            Task { @MainActor in
                self?.scheduleScan(after: 0.25)
            }
        }
        newSource.setCancelHandler {
            _ = close(descriptor)
        }
        newSource.resume()
        source = newSource
        needsBaseline = true
        scan()
    }

    func stop() {
        source?.cancel()
        source = nil
        scanTask?.cancel()
        scanTask = nil
        retryTask?.cancel()
        retryTask = nil
    }

    private func scheduleScan(after delay: Double) {
        guard scanTask == nil else { return }
        scanTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, let strongSelf = self else { return }
            strongSelf.scanTask = nil
            strongSelf.scan()
        }
    }

    private func scan() {
        let keys: [URLResourceKey] = [.fileSizeKey, .isDirectoryKey]
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else {
            // macOS todavía no da permiso a la carpeta (te lo pregunta la 1ª vez).
            scheduleScan(after: 3)
            return
        }

        let names = Set(entries.map { $0.lastPathComponent })

        // La primera lectura solo "memoriza" lo que ya había: no lo sube a la isla.
        if needsBaseline {
            known = names
            needsBaseline = false
            return
        }

        known.formIntersection(names)
        pending = pending.filter { names.contains($0.key) }

        var waiting = false
        let now = Date()
        for entry in entries {
            let name = entry.lastPathComponent
            if known.contains(name) || FolderWatcher.isPartial(entry) { continue }

            let values = try? entry.resourceValues(forKeys: Set(keys))
            if values?.isDirectory == true {
                known.insert(name)
                onNewFile?(entry)
                continue
            }

            let size = values?.fileSize ?? 0
            if let previous = pending[name], previous.size == size {
                let age = now.timeIntervalSince(previous.since)
                if size > 0 && age >= 0.5 {
                    pending[name] = nil
                    known.insert(name)
                    onNewFile?(entry)
                } else if size == 0 && age > 120 {
                    pending[name] = nil
                    known.insert(name)
                } else {
                    waiting = true
                }
            } else {
                pending[name] = (size: size, since: now)
                waiting = true
            }
        }
        if waiting {
            scheduleScan(after: 0.5)
        }
    }

    private static func isPartial(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        if name.hasPrefix(".") || name.hasPrefix("~$") { return true }
        return partialExtensions.contains(url.pathExtension.lowercased())
    }
}
