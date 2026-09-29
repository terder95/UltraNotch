import SwiftUI
import AppKit

/// Pestaña "Mac": CPU, memoria, disco, temperatura, batería y limpieza.
struct MacView: View {
    @ObservedObject var monitor: SystemMonitor

    private var stats: SystemMonitor.Snapshot { monitor.snapshot }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                cpuCard
                memoryCard
                diskCard
                temperatureCard
                batteryCard
            }

            HStack(alignment: .top, spacing: 10) {
                TopAppsPanel(monitor: monitor)
                CleanupPanel(monitor: monitor)
            }
        }
        .onAppear {
            monitor.tabAppeared()
        }
    }

    // MARK: Tarjetas

    private var cpuCard: some View {
        let value = stats.cpu
        return StatCard(
            title: "CPU",
            value: "\(Int((value * 100).rounded()))%",
            subtitle: "\(stats.cores) núcleos",
            fraction: value,
            tint: MacView.levelColor(value, warn: 0.6, danger: 0.85),
            symbol: "cpu"
        )
    }

    private var memoryCard: some View {
        let memory = stats.memory
        let fraction = memory.total > 0 ? Double(memory.used) / Double(memory.total) : 0
        let tint: Color
        switch stats.pressure {
        case .normal: tint = Theme.accent
        case .warning: tint = Theme.warning
        case .critical: tint = Theme.danger
        }
        var help = stats.pressure.label
        if stats.swapUsed > 0 { help += " · Swap \(Formatters.memory(stats.swapUsed))" }
        return StatCard(
            title: "Memoria",
            value: Formatters.memory(memory.used),
            subtitle: "de \(Formatters.memory(memory.total))",
            fraction: fraction,
            tint: tint,
            symbol: "memorychip"
        )
        .help(help)
    }

    private var diskCard: some View {
        let disk = stats.disk
        let used = disk.total > 0 ? Double(disk.total - disk.free) / Double(disk.total) : 0
        return StatCard(
            title: "Disco",
            value: "\(Formatters.bytes(disk.free)) libres",
            subtitle: "de \(Formatters.bytes(disk.total))",
            fraction: used,
            tint: MacView.levelColor(used, warn: 0.8, danger: 0.92),
            symbol: "internaldrive"
        )
    }

    private var temperatureCard: some View {
        let chip = stats.chipTemperature
        let battery = stats.battery?.temperature
        let celsius = chip ?? battery
        let source = chip != nil ? "Chip" : (battery != nil ? "Batería" : "Sin sensor")
        return StatCard(
            title: "Temperatura",
            value: celsius.map { "\(Int($0.rounded())) °C" } ?? "—",
            subtitle: "\(source) · \(MacView.thermalLabel(stats.thermal))",
            fraction: (celsius ?? 0) / 100,
            tint: MacView.levelColor((celsius ?? 0) / 100, warn: 0.75, danger: 0.9),
            symbol: "thermometer"
        )
    }

    @ViewBuilder
    private var batteryCard: some View {
        if let battery = stats.battery {
            let state = battery.charging ? "Cargando" : (battery.onAC ? "Conectada" : "Con batería")
            let cycles = battery.cycles.map { " · \($0) ciclos" } ?? ""
            StatCard(
                title: "Batería",
                value: "\(battery.percent)%",
                subtitle: state + cycles,
                fraction: Double(battery.percent) / 100,
                tint: battery.percent <= 20 && !battery.onAC ? Theme.danger : Theme.success,
                symbol: MacView.batterySymbol(battery)
            )
        } else {
            StatCard(title: "Batería", value: "—", subtitle: "Sin batería", fraction: 0,
                     tint: Theme.accent, symbol: "powerplug")
        }
    }

    // MARK: Ayudantes

    static func levelColor(_ fraction: Double, warn: Double, danger: Double) -> Color {
        if fraction >= danger { return Theme.danger }
        if fraction >= warn { return Theme.warning }
        return Theme.accent
    }

    static func thermalLabel(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "normal"
        case .fair: return "tibia"
        case .serious: return "caliente"
        case .critical: return "muy caliente"
        @unknown default: return "—"
        }
    }

    static func batterySymbol(_ battery: BatteryInfo) -> String {
        if battery.charging { return "battery.100.bolt" }
        switch battery.percent {
        case 88...: return "battery.100"
        case 63..<88: return "battery.75"
        case 38..<63: return "battery.50"
        case 13..<38: return "battery.25"
        default: return "battery.0"
        }
    }
}

/// Tarjeta con anillo de progreso.
struct StatCard: View {
    let title: String
    let value: String
    let subtitle: String
    let fraction: Double
    let tint: Color
    let symbol: String

    var body: some View {
        HStack(spacing: 7) {
            RingGauge(fraction: fraction, tint: tint, symbol: symbol)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.system(size: 12.5, weight: .semibold))
                    .monospacedDigit()
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(subtitle)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
        }
        .padding(7)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Theme.card(false))
        )
    }
}

struct RingGauge: View {
    let fraction: Double
    let tint: Color
    let symbol: String

    private var clamped: CGFloat {
        CGFloat(min(max(fraction, 0), 1))
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.1), lineWidth: 4)
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(tint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.5), value: clamped)
            Image(systemName: symbol)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundColor(tint)
        }
        .frame(width: 32, height: 32)
    }
}

struct SectionTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 9.5, weight: .bold))
            .tracking(0.8)
            .foregroundColor(.secondary)
    }
}

// MARK: - Apps que más RAM usan

struct TopAppsPanel: View {
    @ObservedObject var monitor: SystemMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                SectionTitle(text: "APPS QUE MÁS RAM USAN")
                Spacer(minLength: 4)
                Button {
                    monitor.purgeMemory()
                } label: {
                    Label(monitor.isBusy("purge") ? "Liberando…" : "Liberar RAM", systemImage: "wind")
                }
                .buttonStyle(PillButtonStyle())
                .disabled(monitor.isBusy("purge"))
                .help("Vacía la caché de memoria del sistema (te pide tu contraseña). El efecto es temporal: lo que más libera RAM es cerrar apps pesadas.")
            }
            .frame(height: 20)

            if monitor.topApps.isEmpty {
                Text("Calculando…")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            } else {
                ForEach(monitor.topApps) { app in
                    AppMemoryRow(app: app, monitor: monitor)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

struct AppMemoryRow: View {
    let app: AppMemory
    @ObservedObject var monitor: SystemMonitor
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 7) {
            if let icon = app.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 16, height: 16)
            } else {
                Image(systemName: "app")
                    .frame(width: 16, height: 16)
            }
            Text(app.name)
                .font(.system(size: 11))
                .foregroundColor(.primary)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(Formatters.memory(app.bytes))
                .font(.system(size: 10.5, weight: .medium))
                .monospacedDigit()
                .foregroundColor(.secondary)
            Button {
                monitor.quit(app)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(hovering ? Theme.danger : Color.secondary.opacity(0.6))
            }
            .buttonStyle(.plain)
            .help("Cerrar \(app.name)")
        }
        .padding(.horizontal, 7)
        .frame(height: 22)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(hovering ? 0.08 : 0.03))
        )
        .onHover { hovering = $0 }
    }
}

// MARK: - Liberar espacio

struct CleanupPanel: View {
    @ObservedObject var monitor: SystemMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                SectionTitle(text: "LIBERAR ESPACIO")
                Spacer(minLength: 4)
                if monitor.scanning {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                        .frame(width: 18, height: 18)
                } else {
                    Button {
                        monitor.scanCleanup(force: true)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(PillButtonStyle())
                    .help("Volver a medir")
                }
            }
            .frame(height: 20)

            ForEach(CleanupKind.allCases) { kind in
                CleanupRow(kind: kind, monitor: monitor)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

struct CleanupRow: View {
    let kind: CleanupKind
    @ObservedObject var monitor: SystemMonitor
    @State private var hovering = false

    private var scan: CleanupScan? { monitor.cleanup[kind] }
    private var busy: Bool { monitor.isBusy(kind.rawValue) }

    private var sizeText: String {
        guard let scan = scan else { return monitor.scanning ? "…" : "" }
        guard let bytes = scan.bytes else { return "" }
        return bytes > 0 ? Formatters.bytes(bytes) : "Limpio"
    }

    private var canClean: Bool {
        guard !busy, let scan = scan else { return false }
        if kind == .trash { return scan.bytes != 0 }
        return !scan.items.isEmpty && (scan.bytes ?? 0) > 0
    }

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: kind.symbol)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundColor(Theme.accent)
                .frame(width: 16)
            Text(kind.title)
                .font(.system(size: 11))
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 4)
            Text(sizeText)
                .font(.system(size: 10.5, weight: .medium))
                .monospacedDigit()
                .foregroundColor(.secondary)
            Button(busy ? "…" : kind.actionLabel) {
                monitor.clean(kind)
            }
            .buttonStyle(PillButtonStyle(tint: canClean ? Theme.accent : Color.secondary))
            .disabled(!canClean)
        }
        .padding(.horizontal, 7)
        .frame(height: 22)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(hovering ? 0.08 : 0.03))
        )
        .onHover { hovering = $0 }
        .help(kind.help)
    }
}
