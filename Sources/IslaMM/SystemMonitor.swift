import AppKit
import SwiftUI
import Combine

/// Una app abierta y cuánta memoria usa (sumando sus procesos auxiliares).
struct AppMemory: Identifiable {
    let id: pid_t
    let name: String
    let bytes: UInt64
    let icon: NSImage?
}

/// Datos en vivo de la Mac para la pestaña "Mac" de la isla.
@MainActor
final class SystemMonitor: ObservableObject {
    struct Snapshot {
        var cpu: Double = 0
        var cores = ProcessInfo.processInfo.activeProcessorCount
        var memory = MemoryInfo(used: 0, free: 0, total: ProcessInfo.processInfo.physicalMemory)
        var pressure: MemoryPressure = .normal
        var swapUsed: UInt64 = 0
        var disk = DiskInfo(free: 0, total: 0)
        var chipTemperature: Double?
        var battery: BatteryInfo?
        var thermal: ProcessInfo.ThermalState = .nominal
        var uptime: TimeInterval = 0
    }

    @Published private(set) var snapshot = Snapshot()

    /// Lo que le importa al compañero (cambia poco: así casi no redibuja la isla).
    struct Vitals: Equatable {
        /// La Mac va a tope (CPU alto sostenido o se está calentando).
        var hot = false
        /// Batería en 10 % o menos, sin cargador.
        var lowBattery = false
        var onAC = true
    }
    @Published private(set) var vitals = Vitals()
    /// Conectaste (true) o desconectaste (false) el cargador.
    var onPowerChanged: ((Bool) -> Void)?
    private var hotSamples = 0
    private var knowsPower = false
    @Published private(set) var topApps: [AppMemory] = []
    @Published private(set) var cleanup: [CleanupKind: CleanupScan] = [:]
    @Published private(set) var scanning = false
    @Published private(set) var busy = Set<String>()

    /// La isla, para saber si está abierta y en qué pestaña.
    weak var notch: NotchController?
    /// Para mostrar avisos en la isla.
    var onEvent: ((Peek) -> Void)?

    private let cpuSampler = CPUSampler()
    private let temperatureReader = TemperatureReader()
    private var timer: AnyCancellable?
    private var ticks = 0
    private var loadingApps = false
    private var lastScan: Date?
    private var lastAlerts: [String: Date] = [:]

    init() {
        // Modo capturas: nada de leer tu Mac (las cifras de ejemplo llegan con cargarDemo).
        if ModoCapturas.activo { return }
        refreshStats()
        timer = Timer.publish(every: 2, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.tick()
            }
    }

    private func tick() {
        ticks += 1
        let expanded = notch?.isExpanded ?? false
        if expanded {
            refreshStats(includeDisk: ticks % 15 == 0)
            if notch?.tab == .mac, ticks % 2 == 0 {
                refreshTopApps()
            }
        } else if ticks % 5 == 0 {
            // Isla cerrada: solo una muestra de CPU de vez en cuando (casi sin consumo),
            // para que al abrir la isla el porcentaje salga al instante (y para el compañero).
            let cpu = cpuSampler.usage()
            updateVitals(cpu: cpu, battery: SystemStats.battery(), thermal: ProcessInfo.processInfo.thermalState)
        }
        if ticks % 30 == 0 {
            checkAlerts()
        }
    }

    /// Modo capturas: cifras inventadas.
    func cargarDemo(snapshot demo: Snapshot, apps: [AppMemory], limpieza: [CleanupKind: CleanupScan]) {
        snapshot = demo
        topApps = apps
        cleanup = limpieza
    }

    /// Se llama al entrar a la pestaña Mac.
    func tabAppeared() {
        if ModoCapturas.activo { return }
        refreshStats(includeDisk: true)
        refreshTopApps()
        scanCleanup(force: false)
    }

    func isBusy(_ key: String) -> Bool {
        busy.contains(key)
    }

    // MARK: Lecturas

    /// Lee todo lo rápido. El disco (más lento) solo cuando se pide o cada 30 s.
    func refreshStats(includeDisk: Bool = true) {
        var next = snapshot
        if let cpu = cpuSampler.usage() { next.cpu = cpu }
        if let memory = SystemStats.memory() { next.memory = memory }
        next.pressure = SystemStats.memoryPressure()
        next.swapUsed = SystemStats.swapUsed()
        if includeDisk || next.disk.total == 0, let disk = SystemStats.disk() { next.disk = disk }
        next.chipTemperature = temperatureReader.chipTemperature()
        next.battery = SystemStats.battery()
        next.thermal = ProcessInfo.processInfo.thermalState
        next.uptime = ProcessInfo.processInfo.systemUptime
        snapshot = next
        updateVitals(cpu: next.cpu, battery: next.battery, thermal: next.thermal)
    }

    /// Calor con "histéresis": se enciende con 2 lecturas altas seguidas y se apaga al bajar bien.
    private func updateVitals(cpu: Double?, battery: BatteryInfo?, thermal: ProcessInfo.ThermalState) {
        var next = vitals
        if let cpu = cpu {
            if cpu >= 0.85 {
                hotSamples += 1
            } else if cpu < 0.6 {
                hotSamples = 0
            }
        }
        let heating = thermal == .serious || thermal == .critical
        if heating || hotSamples >= 2 {
            next.hot = true
        } else if hotSamples == 0 {
            next.hot = false
        }
        if let battery = battery {
            if battery.onAC || battery.percent > 12 {
                next.lowBattery = false
            } else if battery.percent <= 10 {
                next.lowBattery = true
            }
            let wasOnAC = next.onAC
            next.onAC = battery.onAC
            if knowsPower && wasOnAC != battery.onAC {
                onPowerChanged?(battery.onAC)
            }
            knowsPower = true
        }
        if next != vitals { vitals = next }
    }

    func refreshTopApps() {
        guard !loadingApps else { return }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        var candidates: [AppCandidate] = []
        for app in NSWorkspace.shared.runningApplications {
            guard app.activationPolicy == .regular,
                  app.processIdentifier != ownPID,
                  app.bundleIdentifier != "com.apple.finder",
                  let path = app.bundleURL?.path else { continue }
            let name = app.localizedName ?? (path as NSString).lastPathComponent
            candidates.append(AppCandidate(pid: app.processIdentifier, name: name, bundlePath: path))
        }
        loadingApps = true
        let apps = candidates
        Task.detached(priority: .utility) { [weak self] in
            let totals = ProcessMemory.totals(for: apps)
            await self?.applyTopApps(totals)
        }
    }

    private func applyTopApps(_ totals: [AppMemoryTotal]) {
        loadingApps = false
        topApps = totals.prefix(5).map { total in
            AppMemory(
                id: total.pid,
                name: total.name,
                bytes: total.bytes,
                icon: NSRunningApplication(processIdentifier: total.pid)?.icon
            )
        }
    }

    // MARK: Liberar RAM

    /// Cierra una app de forma normal (si hay algo sin guardar, la app te pregunta).
    func quit(_ app: AppMemory) {
        guard let running = NSRunningApplication(processIdentifier: app.id) else { return }
        running.terminate()
        onEvent?(Peek(symbol: "xmark.circle.fill", title: "Cerrando \(app.name)", tint: Theme.accent))
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            self?.refreshTopApps()
            self?.refreshStats(includeDisk: false)
        }
    }

    /// Vacía la caché de memoria del sistema con `purge` (pide tu contraseña).
    func purgeMemory() {
        guard !busy.contains("purge") else { return }
        busy.insert("purge")
        let freeBefore = snapshot.memory.free
        Task { [weak self] in
            let success = await SystemCleaner.runAppleScriptInBackground("do shell script \"/usr/sbin/purge\" with administrator privileges")
            self?.finishPurge(success: success, freeBefore: freeBefore)
        }
    }

    private func finishPurge(success: Bool, freeBefore: UInt64) {
        busy.remove("purge")
        refreshStats(includeDisk: false)
        guard success else { return }
        let freeAfter = snapshot.memory.free
        let gained = freeAfter > freeBefore ? freeAfter - freeBefore : 0
        let title = gained > 50_000_000 ? "RAM libre +\(Formatters.memory(gained))" : "Memoria optimizada"
        onEvent?(Peek(symbol: "wind", title: title, tint: Theme.success))
    }

    // MARK: Liberar disco

    func scanCleanup(force: Bool) {
        guard !scanning else { return }
        if !force, let last = lastScan, Date().timeIntervalSince(last) < 300 { return }
        scanning = true
        let screenshotFolder = ShelfStore.screenshotFolder()
        Task.detached(priority: .utility) { [weak self] in
            var results: [CleanupKind: CleanupScan] = [:]
            for kind in CleanupKind.allCases {
                results[kind] = SystemCleaner.scan(kind, screenshotFolder: screenshotFolder)
            }
            await self?.applyScan(results)
        }
    }

    private func applyScan(_ results: [CleanupKind: CleanupScan]) {
        cleanup = results
        scanning = false
        lastScan = Date()
    }

    func clean(_ kind: CleanupKind) {
        guard !busy.contains(kind.rawValue) else { return }
        let scan = cleanup[kind] ?? CleanupScan(bytes: nil, items: [])
        guard confirm(kind, scan: scan) else { return }

        busy.insert(kind.rawValue)
        if kind == .trash {
            let knownSize = scan.bytes ?? 0
            Task { [weak self] in
                let success = await SystemCleaner.runAppleScriptInBackground("tell application \"Finder\" to empty trash")
                self?.finishCleaning(kind, freed: success ? knownSize : -1)
            }
            return
        }

        let items = scan.items
        let permanently = kind.deletesPermanently
        Task.detached(priority: .userInitiated) { [weak self] in
            let freed = SystemCleaner.remove(items, permanently: permanently)
            await self?.finishCleaning(kind, freed: freed)
        }
    }

    private func finishCleaning(_ kind: CleanupKind, freed: Int64) {
        busy.remove(kind.rawValue)
        if freed >= 0, kind != .trash {
            cleanup[kind] = CleanupScan(bytes: 0, items: [])
        }
        refreshStats(includeDisk: true)
        scanCleanup(force: true)

        if freed < 0 {
            onEvent?(Peek(symbol: "exclamationmark.triangle.fill", title: "No se pudo vaciar", tint: Theme.warning))
            return
        }
        let amount = Formatters.bytes(freed)
        let title: String
        switch kind {
        case .trash:
            title = freed > 0 ? "Liberaste \(amount)" : "Papelera vaciada"
        case .caches, .developer:
            title = "Liberaste \(amount)"
        case .downloads, .screenshots:
            title = "\(amount) a la Papelera"
        }
        onEvent?(Peek(symbol: "sparkles", title: title, tint: Theme.success))
    }

    private func confirm(_ kind: CleanupKind, scan: CleanupScan) -> Bool {
        let size = scan.bytes.map { Formatters.bytes($0) }
        let alert = NSAlert()
        alert.alertStyle = .warning

        switch kind {
        case .trash:
            alert.messageText = "¿Vaciar la Papelera?"
            alert.informativeText = (size.map { "Se liberarán \($0). " } ?? "") + "Esto no se puede deshacer."
            alert.addButton(withTitle: "Vaciar")
        case .caches, .developer:
            alert.messageText = "¿Borrar \(size ?? "los archivos") de \(kind.title.lowercased())?"
            alert.informativeText = kind.help
            alert.addButton(withTitle: "Borrar")
        case .downloads, .screenshots:
            let names = scan.items.prefix(6).map { "• " + $0.lastPathComponent }.joined(separator: "\n")
            let more = scan.items.count > 6 ? "\n… y \(scan.items.count - 6) más" : ""
            alert.messageText = "¿Mover \(scan.items.count) elemento\(scan.items.count == 1 ? "" : "s") a la Papelera?"
            alert.informativeText = "\(size ?? "") · Puedes recuperarlos desde la Papelera.\n\n\(names)\(more)"
            alert.addButton(withTitle: "Mover a la Papelera")
        }
        alert.addButton(withTitle: "Cancelar")

        NSApp.activate(ignoringOtherApps: true)
        let accepted = alert.runModal() == .alertFirstButtonReturn
        NSApp.deactivate()
        return accepted
    }

    // MARK: Avisos automáticos (cada minuto, aunque la isla esté cerrada)

    private func checkAlerts() {
        let now = Date()
        func allowed(_ key: String) -> Bool {
            if let last = lastAlerts[key], now.timeIntervalSince(last) < 3600 { return false }
            lastAlerts[key] = now
            return true
        }

        if let disk = SystemStats.disk(), disk.total > 0, disk.free < 10_000_000_000, allowed("disk") {
            onEvent?(Peek(symbol: "internaldrive", title: "Disco casi lleno", tint: Theme.warning))
        }
        if SystemStats.memoryPressure() == .critical, allowed("ram") {
            onEvent?(Peek(symbol: "memorychip", title: "RAM al límite", tint: Theme.danger))
        }
        let thermal = ProcessInfo.processInfo.thermalState
        if thermal == .serious || thermal == .critical, allowed("heat") {
            onEvent?(Peek(symbol: "thermometer", title: "Mac muy caliente", tint: Theme.danger))
        }
    }
}
