import AppKit
import UltraNotchObjC

/// Corre código de Apple que puede lanzar una "excepción de Objective-C" (NSException).
/// Swift no puede atraparlas; si se escapan, AppKit se las traga pero deja a Swift en mal
/// estado y la app se cierra minutos después. Aquí las atrapamos justo donde pasan.
enum ObjC {
    /// Regresa el error si hubo una excepción (y nil si todo salió bien).
    @discardableResult
    static func attempt(_ block: () -> Void) -> NSError? {
        var error: NSError?
        let ok = UltraNotchTryObjC(block, &error)
        return ok ? nil : (error ?? NSError(domain: "UltraNotchObjCException", code: 1))
    }
}

/// Cuida que UltraNotch no desaparezca:
///  • Un "vigilante" chiquito (un proceso aparte que casi no gasta) lo vuelve a abrir
///    si se cierra de golpe. Si lo cierras tú (Salir, o el instalador) no hace nada.
///  • Si macOS se traga un error, UltraNotch se cierra de inmediato (y el vigilante lo reabre)
///    en vez de quedar dañado y cerrarse solo más tarde. Así el reporte de macOS
///    muestra el error real.
///  • Guarda el registro en disco para saber qué pasaba antes del cierre.
@MainActor
final class CrashGuard {
    static let shared = CrashGuard()

    /// Si existe cuando UltraNotch se cierra, fue a propósito (el vigilante no la reabre). Uno por proceso.
    nonisolated static let cleanFlagPath = AppPaths.support
        .appendingPathComponent("cierre-limpio-\(ProcessInfo.processInfo.processIdentifier)").path
    /// Marca de cuándo arrancó (para saber si macOS dejó un reporte de error después).
    nonisolated static let startMarkPath = AppPaths.support
        .appendingPathComponent("inicio-\(ProcessInfo.processInfo.processIdentifier)").path
    nonisolated static let logPath = AppPaths.support.appendingPathComponent("registro.txt").path
    nonisolated static let reopenArgument = "--reabierta"

    private var watchdog: Process?
    private var termSource: DispatchSourceSignal?

    /// true si esta vez la abrió el vigilante porque se había cerrado de golpe.
    var reopenedAfterCrash: Bool {
        CommandLine.arguments.contains(CrashGuard.reopenArgument)
    }

    /// Antes de arrancar la app: que un error tragado cierre de inmediato (y se registre bien).
    nonisolated static func configureEarly() {
        UserDefaults.standard.register(defaults: ["NSApplicationCrashOnExceptions": true])
    }

    /// ¿Ya hay otro UltraNotch abierto desde antes? (si se abren dos al mismo tiempo, se queda la primera)
    static var anotherInstanceRunning: Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }
        let me = NSRunningApplication.current
        let myLaunch = me.launchDate ?? .distantFuture
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).contains {
            $0.processIdentifier != me.processIdentifier && !$0.isTerminated
                && ($0.launchDate ?? .distantPast) < myLaunch
        }
    }

    func start() {
        removeOldMarks()
        spawnWatchdog()
        handleTerminateSignal()
    }

    /// Borra marcas de sesiones viejas (de otros procesos que ya no existen).
    private func removeOldMarks() {
        let folder = AppPaths.support
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return }
        for name in names where name.hasPrefix("cierre-limpio") || name.hasPrefix("inicio-") {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
        }
    }

    /// Te vas a salir (o te sacó el instalador): el vigilante no debe reabrirla.
    nonisolated static func markCleanExit() {
        FileManager.default.createFile(atPath: cleanFlagPath, contents: Data())
    }

    /// El registro de la vez pasada (para mostrar qué pasaba antes de cerrarse).
    nonisolated static func previousLog() -> [String] {
        guard let text = try? String(contentsOfFile: logPath, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").map(String.init)
    }

    // MARK: Vigilante

    private func spawnWatchdog() {
        let appPath = Bundle.main.bundleURL.path
        guard appPath.hasSuffix(".app") else { return } // solo cuando corre como app instalada
        let pid = ProcessInfo.processInfo.processIdentifier
        // Espera a que UltraNotch se cierre. La vuelve a abrir solo si fue un cierre de golpe: no fue a
        // propósito, llevaba más de 25 s abierta (para no ciclarse si falla al arrancar) y macOS
        // dejó un reporte de error (si la forzaste a salir no hay reporte y no la reabre).
        let script = """
        PID="$1"; FLAG="$2"; APP="$3"; MARK="$4"; START=$(date +%s)
        touch "$MARK"
        while kill -0 "$PID" 2>/dev/null; do sleep 2; done
        if [ -f "$FLAG" ]; then rm -f "$FLAG" "$MARK"; exit 0; fi
        NOW=$(date +%s)
        if [ $((NOW - START)) -lt 25 ]; then rm -f "$MARK"; exit 0; fi
        FOUND=""; i=0
        while [ $i -lt 15 ]; do
          FOUND=$(find "$HOME/Library/Logs/DiagnosticReports" -maxdepth 1 -name 'UltraNotch*' -newer "$MARK" 2>/dev/null | head -1)
          [ -n "$FOUND" ] && break
          sleep 1; i=$((i + 1))
        done
        rm -f "$MARK"
        [ -z "$FOUND" ] && exit 0
        /usr/bin/open "$APP" --args \(CrashGuard.reopenArgument)
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script, "ultranotch-guardian", "\(pid)", CrashGuard.cleanFlagPath, appPath,
                             CrashGuard.startMarkPath]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            watchdog = process
        } catch {
            UltraNotchLog.shared.add("No pude iniciar el vigilante que reabre UltraNotch (\(error.localizedDescription))")
        }
    }

    /// El instalador cierra UltraNotch con una señal (SIGTERM): lo tomamos como salida normal.
    private func handleTerminateSignal() {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler {
            CrashGuard.markCleanExit()
            exit(0)
        }
        source.resume()
        termSource = source
    }
}
