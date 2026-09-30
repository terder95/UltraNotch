import SwiftUI
import Foundation
import Darwin

// Tus límites de uso del plan de Claude (la sesión de 5 horas y la semana), chiquitos en la isla.
//
// De dónde salen: Claude Code le pasa estos datos a su "línea de estado" (status line)
// cada vez que se actualiza (es una función oficial y documentada). UltraNotch se pone como esa
// línea de estado, le avisa a la isla y sigue mostrando la línea de estado que ya tenías.
// Los límites son de toda tu cuenta (chat, Cowork y Claude Code); se actualizan mientras
// usas Claude Code.

/// Cuánto llevas de tu plan.
struct PlanUsage: Codable, Equatable {
    struct Window: Codable, Equatable {
        /// 0…100
        var percent: Double
        var resetsAt: Date?
    }

    /// Sesión de 5 horas.
    var session: Window?
    /// Semana (7 días).
    var week: Window?
    var updated: Date

    /// Lee `rate_limits` tal como lo manda Claude Code.
    static func from(rateLimits: [String: Any], now: Date = Date()) -> PlanUsage? {
        func window(_ key: String) -> Window? {
            guard let raw = rateLimits[key] as? [String: Any],
                  let percent = (raw["used_percentage"] as? NSNumber)?.doubleValue else { return nil }
            return Window(percent: percent, resetsAt: date(raw["resets_at"]))
        }
        let usage = PlanUsage(session: window("five_hour"), week: window("seven_day"), updated: now)
        return usage.session == nil && usage.week == nil ? nil : usage
    }

    /// La hora de reinicio: Claude Code la manda en segundos (epoch); por si acaso, también ISO-8601.
    private static func date(_ value: Any?) -> Date? {
        if let seconds = value as? NSNumber {
            return Date(timeIntervalSince1970: seconds.doubleValue)
        }
        guard let text = value as? String else { return nil }
        if let seconds = Double(text) { return Date(timeIntervalSince1970: seconds) }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }

    /// Si ya pasó la hora de reinicio, ese número ya no aplica.
    func current(_ window: Window?, now: Date = Date()) -> Window? {
        guard let window = window else { return nil }
        if let reset = window.resetsAt, reset < now { return nil }
        return window
    }

    var tooltip: String {
        var lines: [String] = []
        if let session = current(session) {
            lines.append("Sesión (5 h): \(Int(session.percent.rounded())) %" + PlanUsage.resetText(session.resetsAt, long: false))
        } else {
            lines.append("Sesión (5 h): se reinició")
        }
        if let week = current(week) {
            lines.append("Semana: \(Int(week.percent.rounded())) %" + PlanUsage.resetText(week.resetsAt, long: true))
        }
        let minutes = Int(Date().timeIntervalSince(updated) / 60)
        lines.append(minutes < 1 ? "Actualizado hace un momento" : "Actualizado hace \(minutes) min")
        lines.append("Se actualiza mientras usas Claude Code (es el mismo límite para el chat y Cowork).")
        return lines.joined(separator: "\n")
    }

    static func resetText(_ date: Date?, long: Bool) -> String {
        guard let date = date else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_MX")
        formatter.dateFormat = long ? "EEE d, h:mm a" : "h:mm a"
        return " · se reinicia \(long ? "el" : "a las") \(formatter.string(from: date))"
    }
}

// MARK: - En la isla

/// Dos anillitos: sesión de 5 h y semana. Al pasar el mouse te dice cuándo se reinician.
struct UsageMeterView: View {
    let usage: PlanUsage

    var body: some View {
        let session = usage.current(usage.session)
        let week = usage.current(usage.week)
        let stale = Date().timeIntervalSince(usage.updated) > 45 * 60
        return HStack(spacing: 7) {
            gauge(label: "5h", window: session)
            if week != nil || usage.week != nil {
                gauge(label: "7d", window: week)
            }
        }
        .opacity(stale ? 0.55 : 1)
        .help(usage.tooltip)
    }

    private func gauge(label: String, window: PlanUsage.Window?) -> some View {
        let percent = window?.percent ?? 0
        let fraction = CGFloat(min(max(percent / 100, 0), 1))
        return HStack(spacing: 3) {
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.15), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(UsageMeterView.color(percent), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 11, height: 11)
            Text(window == nil ? "\(label) —" : "\(label) \(Int(percent.rounded()))%")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(.secondary)
                .lineLimit(1)
                .fixedSize()
        }
    }

    static func color(_ percent: Double) -> Color {
        if percent >= 90 { return Theme.danger }
        if percent >= 70 { return Theme.warning }
        return Theme.success
    }
}

// MARK: - La "línea de estado" que Claude Code ejecuta

/// Se ejecuta como `UltraNotch --claude-statusline` (proceso aparte y rapidito, sin interfaz).
/// 1) Le pasa a UltraNotch tus límites de uso. 2) Muestra tu línea de estado de antes (si tenías)
/// o una cortita de UltraNotch con los límites.
enum ClaudeStatusLine {
    static let marker = "--claude-statusline"

    /// Aquí guardamos la línea de estado que ya tenías (para seguir mostrándola y regresarla).
    static var originalURL: URL {
        AppPaths.support.appendingPathComponent("linea-de-estado-original.json")
    }

    static func run() -> Never {
        signal(SIGPIPE, SIG_IGN) // si tu línea de estado no lee lo que le mandamos, que no nos tumbe
        // Pase lo que pase, en 5 s terminamos (Claude Code no debe quedarse esperando).
        DispatchQueue.global().asyncAfter(deadline: .now() + 5) { exit(0) }
        let input = FileHandle.standardInput.readDataToEndOfFile()
        let payload = (try? JSONSerialization.jsonObject(with: input)) as? [String: Any] ?? [:]

        if let limits = payload["rate_limits"] as? [String: Any] {
            let message: [String: Any] = ["hook_event_name": "UltraNotchUsage", "rate_limits": limits]
            if var body = try? JSONSerialization.data(withJSONObject: message),
               let fd = ClaudeSocket.connect(to: ClaudeHookPaths.socketPath, timeout: 1) {
                body.append(10)
                ClaudeSocket.write(fd, body)
                Darwin.close(fd) // sin esperar respuesta: UltraNotch cerrado = no pasa nada
            }
        }

        if let command = originalCommand() {
            runOriginal(command, input: input)
        } else {
            let text = summary(payload)
            if !text.isEmpty {
                FileHandle.standardOutput.write(Data((text + "\n").utf8))
            }
        }
        exit(0)
    }

    static func originalCommand() -> String? {
        guard let data = try? Data(contentsOf: originalURL),
              let saved = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let command = saved["command"] as? String,
              !command.isEmpty, !command.contains(marker) else { return nil }
        return command
    }

    /// Corre tu línea de estado de antes con los mismos datos y muestra lo que imprima.
    private static func runOriginal(_ command: String, input: Data) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return
        }
        try? stdinPipe.fileHandleForWriting.write(contentsOf: input)
        try? stdinPipe.fileHandleForWriting.close()
        // Si tarda demasiado, la cortamos (Claude Code no espera para siempre).
        let deadline = DispatchTime.now() + 4
        DispatchQueue.global().asyncAfter(deadline: deadline) {
            if process.isRunning { process.terminate() }
        }
        let output = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        FileHandle.standardOutput.write(output)
    }

    /// Línea cortita: "UltraNotch · 5 h: 23 % · semana: 41 %".
    static func summary(_ payload: [String: Any]) -> String {
        guard let limits = payload["rate_limits"] as? [String: Any],
              let usage = PlanUsage.from(rateLimits: limits) else { return "" }
        var parts: [String] = []
        if let session = usage.session {
            parts.append("5 h: \(Int(session.percent.rounded())) %")
        }
        if let week = usage.week {
            parts.append("semana: \(Int(week.percent.rounded())) %")
        }
        return parts.isEmpty ? "" : "UltraNotch · " + parts.joined(separator: " · ")
    }
}
