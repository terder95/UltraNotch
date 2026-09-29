import Foundation
import Darwin

// Conexión con Claude Code mediante "hooks" (avisos que Claude Code manda a un programa).
//
//  Claude Code ──(hook)──▶ IslaMM --claude-hook ──(socket local)──▶ Isla abierta
//
// No usa la API ni cuesta nada extra: solo "escucha" lo que Claude Code ya hace.
// Si Isla no está abierta, el aviso termina al instante y Claude Code sigue normal.

enum ClaudeHookPaths {
    static var socketPath: String {
        AppPaths.support.appendingPathComponent("claude.sock").path
    }
}

/// Mensaje que llega de Claude Code.
struct HookMessage: Sendable {
    /// Solo existe cuando Claude Code se queda esperando a Isla
    /// (un permiso, o tu respuesta cuando termina una tarea).
    let requestID: String?
    let data: Data
}

// MARK: - Qué sesiones ignorar

/// Sesiones que no son "tuyas": automáticas (Agent SDK, plugins como claude-mem)
/// o de carpetas que pediste ignorar. Isla ni las muestra ni las detiene.
enum ClaudeSessionFilter {
    static let ignoreAutomaticKey = "claudeIgnoreAutomatic"
    static let ignoredFoldersKey = "claudeIgnoredFolders"
    static let defaultIgnoredFolders = "observer-sessions"

    static func isIgnored(_ payload: [String: Any]) -> Bool {
        let defaults = UserDefaults.standard
        let ignoreAutomatic = defaults.object(forKey: ignoreAutomaticKey) as? Bool ?? true
        let entrypoint = (payload["isla_entrypoint"] as? String ?? "").lowercased()
        if ignoreAutomatic && entrypoint.hasPrefix("sdk") {
            return true
        }
        let cwd = (payload["cwd"] as? String ?? "").lowercased()
        guard !cwd.isEmpty else { return false }
        let folder = URL(fileURLWithPath: cwd).lastPathComponent
        let ignored = (defaults.string(forKey: ignoredFoldersKey) ?? defaultIgnoredFolders)
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
        return ignored.contains { name in
            folder == name || cwd.contains("/\(name)/")
        }
    }
}

// MARK: - Sockets locales (Unix)

enum ClaudeSocket {
    static func address(for path: String) -> sockaddr_un {
        var socketAddress = sockaddr_un()
        socketAddress.sun_family = sa_family_t(AF_UNIX)
        socketAddress.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let bytes = Array(path.utf8CString)
        withUnsafeMutableBytes(of: &socketAddress.sun_path) { raw in
            for (index, byte) in bytes.enumerated() where index < raw.count - 1 {
                raw[index] = UInt8(bitPattern: byte)
            }
        }
        return socketAddress
    }

    /// Evita que la app se cierre si el otro lado se desconecta.
    static func disableSigpipe(_ fd: Int32) {
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
    }

    static func setTimeout(_ fd: Int32, seconds: Int) {
        var interval = timeval(tv_sec: seconds, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &interval, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &interval, socklen_t(MemoryLayout<timeval>.size))
    }

    static func connect(to path: String, timeout: Int) -> Int32? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        disableSigpipe(fd)
        setTimeout(fd, seconds: timeout)
        var socketAddress = address(for: path)
        let result = withUnsafePointer(to: &socketAddress) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { rebound in
                Darwin.connect(fd, rebound, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else {
            Darwin.close(fd)
            return nil
        }
        return fd
    }

    /// Lee hasta el primer salto de línea (o hasta que se cierre la conexión).
    static func readLine(_ fd: Int32, limit: Int) -> Data {
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 8192)
        while result.count < limit {
            let count = Darwin.recv(fd, &buffer, buffer.count, 0)
            if count <= 0 { break }
            if let newline = buffer[0..<count].firstIndex(of: 10) {
                result.append(contentsOf: buffer[0..<newline])
                return result
            }
            result.append(contentsOf: buffer[0..<count])
        }
        return result
    }

    static func write(_ fd: Int32, _ data: Data) {
        let bytes = [UInt8](data)
        var sent = 0
        while sent < bytes.count {
            let count = bytes.withUnsafeBytes { raw -> Int in
                guard let base = raw.baseAddress else { return -1 }
                return Darwin.send(fd, base.advanced(by: sent), raw.count - sent, 0)
            }
            if count <= 0 { break }
            sent += count
        }
    }

    static func writeLine(_ fd: Int32, _ text: String) {
        write(fd, Data((text + "\n").utf8))
    }
}

// MARK: - Servidor dentro de Isla

/// Escucha los avisos de Claude Code en un socket local (solo tu usuario puede usarlo).
final class ClaudeHookServer: @unchecked Sendable {
    static let approvalsKey = "claudeApprovals"
    /// Contestar las preguntas de Claude (AskUserQuestion) desde la isla.
    static let questionsKey = "claudeQuestions"
    /// Responder por voz cuando una sesión termina.
    static let replyKey = "claudeVoiceReply"

    /// Se llama en un hilo de fondo.
    var onMessage: (@Sendable (HookMessage) -> Void)?

    private let lock = NSLock()
    private var waiting: [String: Int32] = [:]
    private var serverFD: Int32 = -1

    /// Herramientas cuyo permiso necesita una respuesta que la isla no puede dar
    /// (aprobar un plan tiene varias opciones: eso se hace en la terminal).
    private static let terminalOnlyTools: Set<String> = ["ExitPlanMode"]

    func start() {
        guard serverFD < 0 else { return }
        let path = ClaudeHookPaths.socketPath
        unlink(path)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return }
        var socketAddress = ClaudeSocket.address(for: path)
        let bound = withUnsafePointer(to: &socketAddress) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { rebound in
                Darwin.bind(fd, rebound, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, Darwin.listen(fd, 32) == 0 else {
            Darwin.close(fd)
            return
        }
        chmod(path, 0o600)
        serverFD = fd

        Thread.detachNewThread { [weak self] in
            self?.acceptLoop(fd)
        }
    }

    private func acceptLoop(_ fd: Int32) {
        while true {
            let client = Darwin.accept(fd, nil, nil)
            if client < 0 {
                if errno == EBADF || errno == EINVAL { break }
                usleep(50_000) // error pasajero (muchas conexiones, etc.): seguimos escuchando
                continue
            }
            ClaudeSocket.disableSigpipe(client)
            Thread.detachNewThread { [weak self] in
                self?.handle(client)
            }
        }
    }

    private func handle(_ client: Int32) {
        ClaudeSocket.setTimeout(client, seconds: 3)
        let data = ClaudeSocket.readLine(client, limit: 4_000_000)
        guard !data.isEmpty else {
            Darwin.close(client)
            return
        }

        let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        if let payload = payload, ClaudeSessionFilter.isIgnored(payload) {
            Darwin.close(client) // sesión automática: Claude Code sigue normal y no la mostramos
            return
        }
        let event = payload?["hook_event_name"] as? String ?? ""
        let tool = payload?["tool_name"] as? String ?? ""
        let defaults = UserDefaults.standard
        let approvalsOn = defaults.object(forKey: ClaudeHookServer.approvalsKey) as? Bool ?? true
        let questionsOn = defaults.object(forKey: ClaudeHookServer.questionsKey) as? Bool ?? true
        let replyOn = defaults.object(forKey: ClaudeHookServer.replyKey) as? Bool ?? true
        let voiceOn = defaults.object(forKey: VoiceWake.enabledKey) as? Bool ?? true

        let holdsPermission: Bool
        if event != "PermissionRequest" {
            holdsPermission = false
        } else if tool == "AskUserQuestion" {
            holdsPermission = questionsOn // una pregunta: la contestas en la isla
        } else {
            holdsPermission = approvalsOn && !ClaudeHookServer.terminalOnlyTools.contains(tool)
        }
        // Al terminar una tarea, Claude Code espera unos segundos por si respondes por voz.
        let holdsStop = event == "Stop" && replyOn && voiceOn

        if holdsPermission || holdsStop {
            // Claude Code se queda esperando: respondemos cuando elijas en la isla.
            let requestID = UUID().uuidString
            lock.lock()
            waiting[requestID] = client
            lock.unlock()
            onMessage?(HookMessage(requestID: requestID, data: data))
            return
        }

        onMessage?(HookMessage(requestID: nil, data: data))
        Darwin.close(client) // sin respuesta = Claude Code sigue como siempre
    }

    /// ¿Claude Code sigue esperando esta respuesta? (false si la canceló o se le acabó su tiempo)
    func isWaiting(_ requestID: String) -> Bool {
        lock.lock()
        let client = waiting[requestID]
        lock.unlock()
        guard let fd = client else { return false }
        var byte: UInt8 = 0
        let result = Darwin.recv(fd, &byte, 1, MSG_PEEK | MSG_DONTWAIT)
        if result == 0 { return false } // el otro lado cerró
        if result < 0 { return errno == EAGAIN || errno == EWOULDBLOCK }
        return true
    }

    /// Envía la decisión. `json == nil` = que Claude Code pregunte en la terminal como siempre.
    func respond(_ requestID: String, with json: String?) {
        lock.lock()
        let client = waiting.removeValue(forKey: requestID)
        lock.unlock()
        guard let client = client else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            if let json = json {
                ClaudeSocket.writeLine(client, json)
            }
            Darwin.close(client)
        }
    }
}

// MARK: - "Relay": lo que Claude Code ejecuta en cada aviso

/// Se ejecuta como `IslaMM --claude-hook` (proceso aparte, sin interfaz).
enum ClaudeHookRelay {
    static func run() -> Never {
        let input = FileHandle.standardInput.readDataToEndOfFile()
        guard !input.isEmpty,
              var payload = (try? JSONSerialization.jsonObject(with: input)) as? [String: Any] else {
            exit(0)
        }

        // Para el botón "Abrir terminal": qué app lanzó Claude Code.
        let environment = ProcessInfo.processInfo.environment
        payload["isla_terminal_bundle"] = environment["__CFBundleIdentifier"] ?? ""
        payload["isla_term_program"] = environment["TERM_PROGRAM"] ?? ""
        // "cli" = la terminal; "sdk-…" = sesiones automáticas (Agent SDK, plugins).
        payload["isla_entrypoint"] = environment["CLAUDE_CODE_ENTRYPOINT"] ?? ""
        // La pestaña exacta de la terminal (su "tty"), para poder ir directo a ella.
        payload["isla_tty"] = controllingTTY() ?? ""

        let event = payload["hook_event_name"] as? String ?? ""
        guard var body = try? JSONSerialization.data(withJSONObject: payload) else { exit(0) }
        body.append(10)

        // Permisos: esperamos a que elijas en la isla. Stop: por si respondes por voz.
        // (Isla siempre contesta antes de estos límites; si no quiere esperar, cierra al instante.)
        let waitSeconds: Int
        switch event {
        case "PermissionRequest": waitSeconds = 290
        case "Stop": waitSeconds = 115
        default: waitSeconds = 1
        }
        let waitsForDecision = waitSeconds > 1
        guard let fd = ClaudeSocket.connect(to: ClaudeHookPaths.socketPath, timeout: waitSeconds) else {
            exit(0) // Isla cerrada: no estorbamos a Claude Code
        }
        ClaudeSocket.write(fd, body)

        if waitsForDecision {
            let reply = ClaudeSocket.readLine(fd, limit: 1_000_000)
            if !reply.isEmpty {
                FileHandle.standardOutput.write(reply)
            }
        }
        Darwin.close(fd)
        exit(0)
    }

    /// "/dev/ttys003": la terminal donde corre Claude Code (la nuestra o la de quien nos lanzó).
    static func controllingTTY() -> String? {
        for pid in [getpid(), getppid()] {
            var info = kinfo_proc()
            var size = MemoryLayout<kinfo_proc>.stride
            var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
            guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0, size > 0 else { continue }
            let device = info.kp_eproc.e_tdev
            guard device != -1, let name = devname(device, S_IFCHR) else { continue }
            let text = String(cString: name)
            if !text.isEmpty && text != "??" { return "/dev/" + text }
        }
        return nil
    }
}

// MARK: - Instalar / quitar los avisos en ~/.claude/settings.json

enum ClaudeHookInstaller {
    static let marker = "--claude-hook"
    /// Ver tus límites de uso en la isla (Isla se pone como la línea de estado de Claude Code).
    static let usageKey = "claudeUsageStatusLine"

    static var usageEnabled: Bool {
        UserDefaults.standard.object(forKey: usageKey) as? Bool ?? true
    }

    /// Evento → segundos máximos que Claude Code espera al aviso.
    private static let events: [String: Int] = [
        "SessionStart": 5,
        "SessionEnd": 5,
        "UserPromptSubmit": 5,
        "PreToolUse": 5,
        "PermissionRequest": 300,
        "Notification": 5,
        "Stop": 120
    ]

    enum InstallError: LocalizedError {
        case unreadable

        var errorDescription: String? {
            "No pude leer ~/.claude/settings.json (parece tener un error de formato), así que no lo modifiqué."
        }
    }

    /// Si tu settings.json es un enlace (por ejemplo, a un repo de dotfiles), usamos el archivo real.
    static var settingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")
            .resolvingSymlinksInPath()
    }

    private static var executable: String {
        Bundle.main.executablePath ?? "/Applications/Isla.app/Contents/MacOS/IslaMM"
    }

    static var command: String {
        "\"\(executable)\" \(marker)"
    }

    static var statusCommand: String {
        "\"\(executable)\" \(ClaudeStatusLine.marker)"
    }

    static func isInstalled() -> Bool {
        !installedCommands().isEmpty
    }

    /// true si hay que actualizar los avisos (moviste la app o cambió una versión de Isla).
    static func needsUpdate() -> Bool {
        guard let settings = readSettings(), let hooks = settings["hooks"] as? [String: Any] else { return false }
        // La línea de estado (límites de uso): puesta si está activado, con la ruta de ahora.
        let statusNow = (settings["statusLine"] as? [String: Any])?["command"] as? String ?? ""
        if usageEnabled != statusNow.contains(ClaudeStatusLine.marker) { return true }
        if usageEnabled && statusNow != statusCommand { return true }
        for (event, timeout) in events {
            guard let groups = hooks[event] as? [[String: Any]] else { return true }
            let ours = groups
                .compactMap { $0["hooks"] as? [[String: Any]] }
                .flatMap { $0 }
                .filter { ($0["command"] as? String)?.contains(marker) == true }
            guard let entry = ours.first,
                  entry["command"] as? String == command,
                  entry["timeout"] as? Int == timeout else { return true }
        }
        return false
    }

    private static func installedCommands() -> [String] {
        guard let settings = readSettings(), let hooks = settings["hooks"] as? [String: Any] else { return [] }
        var result: [String] = []
        for value in hooks.values {
            guard let groups = value as? [[String: Any]] else { continue }
            for group in groups {
                guard let entries = group["hooks"] as? [[String: Any]] else { continue }
                for entry in entries {
                    if let command = entry["command"] as? String, command.contains(marker) {
                        result.append(command)
                    }
                }
            }
        }
        return result
    }

    private static func containsOurHook(_ group: [String: Any]) -> Bool {
        guard let entries = group["hooks"] as? [[String: Any]] else { return false }
        return entries.contains { ($0["command"] as? String)?.contains(marker) == true }
    }

    static func readSettings() -> [String: Any]? {
        guard let data = try? Data(contentsOf: settingsURL) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// Agrega los avisos (o los actualiza). Devuelve la ruta del respaldo, si había archivo.
    @discardableResult
    static func install() throws -> URL? {
        let fileManager = FileManager.default
        var settings: [String: Any] = [:]
        var backup: URL?

        if fileManager.fileExists(atPath: settingsURL.path) {
            guard let parsed = readSettings() else { throw InstallError.unreadable }
            settings = parsed
            backup = try makeBackup()
        } else {
            try fileManager.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        }

        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        for (event, timeout) in events {
            var groups = hooks[event] as? [[String: Any]] ?? []
            groups.removeAll(where: containsOurHook)
            let entry: [String: Any] = ["type": "command", "command": command, "timeout": timeout]
            groups.append(["hooks": [entry]])
            hooks[event] = groups
        }
        settings["hooks"] = hooks
        applyStatusLine(to: &settings)
        try write(settings)
        return backup
    }

    /// Pone (o quita) a Isla como la línea de estado de Claude Code, guardando la tuya para
    /// seguir mostrándola y regresártela si lo apagas.
    private static func applyStatusLine(to settings: inout [String: Any]) {
        let current = settings["statusLine"] as? [String: Any]
        let currentCommand = current?["command"] as? String ?? ""
        let isOurs = currentCommand.contains(ClaudeStatusLine.marker)
        if usageEnabled {
            if let current = current, !isOurs, !currentCommand.isEmpty,
               let data = try? JSONSerialization.data(withJSONObject: current) {
                try? data.write(to: ClaudeStatusLine.originalURL, options: .atomic)
            }
            var ours: [String: Any] = ["type": "command", "command": statusCommand]
            if let padding = current?["padding"] { ours["padding"] = padding }
            settings["statusLine"] = ours
        } else if isOurs {
            restoreStatusLine(into: &settings)
        }
    }

    private static func restoreStatusLine(into settings: inout [String: Any]) {
        if let data = try? Data(contentsOf: ClaudeStatusLine.originalURL),
           let original = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            settings["statusLine"] = original
        } else {
            settings.removeValue(forKey: "statusLine")
        }
        try? FileManager.default.removeItem(at: ClaudeStatusLine.originalURL)
    }

    /// Quita solo los avisos de Isla (deja intactos los tuyos).
    static func uninstall() throws {
        guard var settings = readSettings() else { return }
        _ = try? makeBackup()
        if var hooks = settings["hooks"] as? [String: Any] {
            for (event, value) in hooks {
                guard var groups = value as? [[String: Any]] else { continue }
                groups.removeAll(where: containsOurHook)
                if groups.isEmpty {
                    hooks.removeValue(forKey: event)
                } else {
                    hooks[event] = groups
                }
            }
            if hooks.isEmpty {
                settings.removeValue(forKey: "hooks")
            } else {
                settings["hooks"] = hooks
            }
        }
        // Te regresamos tu línea de estado de antes.
        let statusNow = (settings["statusLine"] as? [String: Any])?["command"] as? String ?? ""
        if statusNow.contains(ClaudeStatusLine.marker) {
            restoreStatusLine(into: &settings)
        }
        try write(settings)
    }

    private static func makeBackup() throws -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let name = "settings.json.isla-respaldo-\(formatter.string(from: Date()))"
        let backup = settingsURL.deletingLastPathComponent().appendingPathComponent(name)
        try FileManager.default.copyItem(at: settingsURL, to: backup)
        return backup
    }

    private static func write(_ settings: [String: Any]) throws {
        let data = try JSONSerialization.data(
            withJSONObject: settings,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        try data.write(to: settingsURL, options: .atomic)
    }
}
