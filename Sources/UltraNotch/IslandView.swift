import SwiftUI
import UniformTypeIdentifiers

/// Forma de la isla: esquinas de abajo redondeadas y "orejitas" arriba
/// para que se funda con la barra de menús.
struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set {
            topRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let top = min(topRadius, rect.width / 4, rect.height / 2)
        let bottom = max(0, min(bottomRadius, (rect.width - 2 * top) / 2, rect.height - top))
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + top, y: rect.minY + top),
            control: CGPoint(x: rect.minX + top, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.minX + top, y: rect.maxY - bottom))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + top + bottom, y: rect.maxY),
            control: CGPoint(x: rect.minX + top, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - top - bottom, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - top, y: rect.maxY - bottom),
            control: CGPoint(x: rect.maxX - top, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - top, y: rect.minY + top))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - top, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}

/// Vista principal que vive dentro de la ventana del notch.
struct IslandRootView: View {
    @ObservedObject var notch: NotchController
    @ObservedObject var shelf: ShelfStore
    @ObservedObject var clipboard: ClipboardStore
    @ObservedObject var monitor: SystemMonitor
    @ObservedObject var claude: ClaudeCodeMonitor
    @ObservedObject var voice: VoiceWake
    @ObservedObject var companion: CompanionController
    @ObservedObject var keepAwake: KeepAwake
    @ObservedObject var music: NowPlaying
    @ObservedObject var lyrics: LyricsStore
    @ObservedObject var agenda: CalendarStore
    var onRequestPermission: () -> Void
    var onOpenSettings: () -> Void

    @Environment(\.colorScheme) private var systemScheme

    private static let bubbleTail: CGFloat = 26

    /// Qué muestra la isla, de mayor a menor prioridad.
    private enum Mode: Int {
        case collapsed, music, companion, live, peek, alert, expanded
    }

    private var mode: Mode {
        if notch.isExpanded { return .expanded }
        if notch.alertActive && !claude.approvals.isEmpty { return .alert }
        if notch.isPeeking { return .peek }
        if notch.live != nil { return .live }
        if companion.enabled { return .companion }
        if showsMusicWings { return .music }
        return .collapsed
    }

    private var isGlass: Bool { notch.style == .glass }

    private var bodySize: CGSize {
        let notchSize = notch.notchSize
        switch mode {
        case .expanded: return notch.expandedSize
        case .alert: return notch.alertSize
        case .peek: return CGSize(width: notchSize.width + notch.peekWing * 2, height: notchSize.height)
        case .live: return CGSize(width: notchSize.width + notch.liveWing * 2, height: notchSize.height)
        case .companion: return CGSize(width: notchSize.width + notch.companionWing * 2, height: notchSize.height)
        case .music: return CGSize(width: notchSize.width + notch.companionWing * 2, height: notchSize.height)
        case .collapsed: return notchSize
        }
    }

    private var topRadius: CGFloat {
        switch mode {
        case .expanded: return isGlass ? 10 : 14
        case .alert: return 10
        default: return 7
        }
    }

    private var bottomRadius: CGFloat {
        switch mode {
        case .expanded: return isGlass ? 30 : 26
        case .alert: return 24
        default: return 11
        }
    }

    private var stateKey: Int { mode.rawValue }

    private var shadowOpacity: Double {
        switch mode {
        case .expanded: return isGlass ? 0.22 : 0.45
        case .alert: return 0.4
        default: return 0
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            island
            Spacer(minLength: 0)
        }
        .frame(width: notch.panelSize.width, height: notch.panelSize.height, alignment: .top)
        .overlay(alignment: .topLeading) {
            // El compañero va encima de la isla (sin recortarse) para poder caminar y colgarse.
            CompanionStageView(
                gaze: companion.gaze,
                input: stageInput,
                tint: companionMood.tint(base: companion.color),
                visible: mode == .companion && !companion.roaming
            )
            .opacity(mode == .companion && !companion.roaming ? 1 : 0)
            .environment(\.colorScheme, .dark)
        }
        .overlay(alignment: .topLeading) {
            bubbleLayer
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: visibleBubbleID)
        // En "Negro clásico" todo va en modo oscuro; en cristal sigue al sistema.
        .environment(\.colorScheme, isGlass ? systemScheme : .dark)
    }

    // MARK: Compañero

    private var companionMood: CompanionMood {
        if voice.phase != .idle { return .listening }
        if claude.replyHold != nil { return .happy }
        if claude.sessions.contains(where: { $0.status == .waiting }) { return .waiting }
        if claude.activeCount > 0 { return .working }
        // Reacciones a tu Mac (se apagan en Configuración › Compañero).
        if companion.reactionsEnabled {
            if monitor.vitals.hot { return .hot }
            if monitor.vitals.lowBattery { return .lowBattery }
        }
        // Suena tu música: se pone audífonos y mueve la cabeza (Configuración › Hoy).
        if music.isPlaying && music.showInIsland { return .grooving }
        if companion.sleepy { return .sleepy }
        return .idle
    }

    private var stageInput: CompanionStageInput {
        CompanionStageInput(
            action: companion.action,
            actionStart: companion.actionStart,
            actionDuration: companion.actionDuration,
            side: companion.side,
            mood: companionMood,
            celebrateUntil: companion.celebrateUntil,
            talkUntil: companion.talkUntil,
            panelWidth: notch.panelSize.width,
            notchWidth: notch.notchSize.width,
            notchHeight: notch.notchSize.height,
            wing: notch.companionWing,
            size: min(18, notch.notchSize.height * 0.55)
        )
    }

    /// Sin compañero: con la isla cerrada se ven la carátula y las barritas.
    private var showsMusicWings: Bool {
        music.isPlaying && music.showInIsland
    }

    /// Las barritas junto al compañero (del color de la carátula).
    private var musicBarsColor: Color? {
        guard music.isPlaying, music.showInIsland, claude.replyHold == nil else { return nil }
        return music.artColor ?? companion.color
    }

    private var companionIndicator: (symbol: String?, tint: Color) {
        if claude.replyHold != nil { return ("mic.fill", Theme.warning) }
        if keepAwake.isOn { return ("cup.and.saucer.fill", companion.color) }
        if voice.state == .listening { return ("waveform", Color.white.opacity(0.45)) }
        return (nil, Color.clear)
    }

    private var bubbleAllowed: Bool {
        companion.enabled && companion.bubblesEnabled && (mode == .companion || mode == .live || mode == .peek)
    }

    private var visibleBubbleID: UUID? {
        bubbleAllowed ? companion.bubble?.id : nil
    }

    /// Dónde está el personajito (para que la colita del globito le apunte).
    private var bubbleAnchorX: CGFloat {
        let center = notch.panelSize.width / 2
        let half = notch.notchSize.width / 2
        switch mode {
        case .live: return center - half - notch.liveWing + 21
        case .peek: return center - half - notch.peekWing + 26
        default:
            let offset = half + notch.companionWing / 2
            return companion.side == .left ? center - offset : center + offset
        }
    }

    @ViewBuilder
    private var bubbleLayer: some View {
        if bubbleAllowed, let bubble = companion.bubble {
            // Que no se salga de la ventana; la colita siempre apunta al compañero.
            let maxLeading = notch.panelSize.width - CompanionBubbleView.width - 8
            let leading = min(max(8, bubbleAnchorX - IslandRootView.bubbleTail), maxLeading)
            let top = notch.notchSize.height + 3
            CompanionBubbleView(
                bubble: bubble,
                tailX: bubbleAnchorX - leading,
                onTap: { companion.tapBubble() },
                onClose: { companion.dismissBubble() }
            )
            .background(
                GeometryReader { proxy in
                    // Posición conocida + tamaño real (sin la animación de entrada).
                    let frame = CGRect(x: leading, y: top, width: proxy.size.width, height: proxy.size.height)
                    Color.clear
                        .onAppear {
                            notch.setBubbleFrame(frame, id: bubble.id)
                        }
                        .onChange(of: frame) { newFrame in
                            notch.setBubbleFrame(newFrame, id: bubble.id)
                        }
                        .onDisappear {
                            notch.clearBubbleFrame(id: bubble.id)
                        }
                }
            )
            .padding(.leading, leading)
            .padding(.top, top)
            .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .topLeading)))
            .id(bubble.id)
        }
    }

    private var island: some View {
        let shape = NotchShape(topRadius: topRadius, bottomRadius: bottomRadius)
        return ZStack(alignment: .top) {
            expandedContent
                .frame(width: notch.expandedSize.width, height: notch.expandedSize.height, alignment: .top)
                .opacity(notch.isExpanded ? 1 : 0)
                .allowsHitTesting(notch.isExpanded)

            peekContent
                .opacity(mode == .peek ? 1 : 0)
                .allowsHitTesting(false)
                .environment(\.colorScheme, .dark)

            CompanionWingsView(
                notchWidth: notch.notchSize.width,
                wing: notch.companionWing,
                height: notch.notchSize.height,
                buddySide: companion.side,
                indicator: companionIndicator.symbol,
                indicatorTint: companionIndicator.tint,
                musicColor: musicBarsColor,
                animated: mode == .companion
            )
            .opacity(mode == .companion ? 1 : 0)
            .allowsHitTesting(false)
            .environment(\.colorScheme, .dark)

            // Sin compañero: carátula y barritas a los lados del notch.
            if mode == .music {
                MusicWingsView(
                    notchWidth: notch.notchSize.width,
                    wing: notch.companionWing,
                    height: notch.notchSize.height,
                    artwork: music.artwork,
                    color: music.artColor ?? Theme.accent,
                    animated: true
                )
                .allowsHitTesting(false)
                .environment(\.colorScheme, .dark)
                .transition(.opacity)
            }

            LiveActivityView(
                activity: notch.live,
                base: companion.color,
                notchWidth: notch.notchSize.width,
                wing: notch.liveWing,
                height: notch.notchSize.height,
                visible: mode == .live
            )
            .opacity(mode == .live ? 1 : 0)
            .allowsHitTesting(false)
            .environment(\.colorScheme, .dark)

            ApprovalAlertView(
                claude: claude,
                notchWidth: notch.notchSize.width,
                notchHeight: notch.notchSize.height,
                size: notch.alertSize,
                visible: mode == .alert,
                onExpand: {
                    notch.tab = .claude
                    notch.open(pinned: true)
                }
            )
            .opacity(mode == .alert ? 1 : 0)
            .allowsHitTesting(mode == .alert)
            .environment(\.colorScheme, .dark)
        }
        .frame(width: bodySize.width + topRadius * 2, height: bodySize.height, alignment: .top)
        .background(islandBackground(shape))
        .clipShape(shape)
        .overlay(
            shape
                .stroke(Theme.accent, lineWidth: 1.5)
                .opacity(notch.isDropTargeted ? 1 : 0)
        )
        .contentShape(shape)
        .onDrop(of: IslandDropDelegate.types, delegate: dropDelegate)
        .shadow(color: Color.black.opacity(shadowOpacity), radius: 18, x: 0, y: 10)
        .animation(.spring(response: 0.38, dampingFraction: 0.8), value: stateKey)
    }

    /// Recibe lo que sueltas: a la izquierda el estante, a la derecha AirDrop.
    private var dropDelegate: IslandDropDelegate {
        let islandWidth = bodySize.width + topRadius * 2
        return IslandDropDelegate(
            notch: notch,
            shelf: shelf,
            contentMinX: (islandWidth - notch.expandedSize.width) / 2 + 20,
            contentWidth: notch.expandedSize.width - 40
        )
    }

    /// Cristal cuando está abierta (estilo cristal); negro en todo lo demás.
    @ViewBuilder
    private func islandBackground(_ shape: NotchShape) -> some View {
        if isGlass && mode == .expanded {
            IslandGlass(shape: shape)
                .overlay(alignment: .top) {
                    // "Tapa" negra del notch para que la cámara se funda con el cristal.
                    NotchShape(topRadius: 6, bottomRadius: 12)
                        .fill(Theme.island)
                        .frame(width: notch.notchSize.width + 12, height: notch.notchSize.height)
                }
        } else {
            shape.fill(Theme.island)
        }
    }

    // MARK: Panel abierto

    private var expandedContent: some View {
        VStack(spacing: 10) {
            header
            Group {
                if notch.isDropTargeted {
                    DropZonesView(zone: notch.dropZone)
                } else {
                    tabContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch notch.tab {
        case .today:
            if notch.isExpanded {
                TodayView(music: music, lyrics: lyrics, agenda: agenda, onOpenSettings: onOpenSettings)
            }
        case .shelf:
            ShelfView(shelf: shelf)
        case .clipboard:
            ClipboardView(clipboard: clipboard, onRequestPermission: onRequestPermission)
        case .claude:
            // Solo se dibuja con la isla abierta (sus personajitos se animan).
            if notch.isExpanded {
                ClaudeView(claude: claude, voice: voice, mascot: companion.color)
            }
        case .mac:
            MacView(monitor: monitor)
        }
    }

    private var header: some View {
        HStack(spacing: 0) {
            // Si no cabe el nombre de la pestaña, solo se ven los íconos.
            ViewThatFits(in: .horizontal) {
                tabPills(showTitle: true)
                tabPills(showTitle: false)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Espacio que ocupa la cámara / el notch físico.
            Color.clear.frame(width: notch.notchSize.width + 12)

            HStack(spacing: 6) {
                if voice.phase != .idle {
                    Label(voiceHeaderText, systemImage: "waveform")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Theme.accent)
                        .lineLimit(1)
                } else if let toast = notch.toast {
                    Label(toast, systemImage: "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Theme.accent)
                        .lineLimit(1)
                } else if claude.usageEnabled, let usage = claude.usage {
                    // Tus límites del plan: sesión de 5 h y semana (pasa el mouse para ver cuándo se reinician).
                    UsageMeterView(usage: usage)
                } else {
                    statusView
                }
                Button {
                    keepAwake.toggle()
                    notch.flash(Peek(symbol: "cup.and.saucer.fill",
                                     title: keepAwake.isOn ? "Modo programación: no se dormirá" : "Modo programación apagado",
                                     tint: Theme.accent))
                } label: {
                    Image(systemName: keepAwake.isOn ? "cup.and.saucer.fill" : "cup.and.saucer")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(keepAwake.isOn ? Theme.accent : .secondary)
                }
                .buttonStyle(.plain)
                .help(keepAwake.isOn
                      ? "Modo programación activo: la Mac no se duerme ni se bloquea (clic para apagarlo)"
                      : "Modo programación: que la Mac no se duerma ni se bloquee mientras trabajas")
                Button(action: onOpenSettings) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Configuración")
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(height: notch.notchSize.height)
    }

    private func tabPills(showTitle: Bool) -> some View {
        HStack(spacing: 3) {
            TabPill(title: "Hoy", symbol: "calendar", selected: notch.tab == .today, showTitle: showTitle,
                    badge: agenda.meetings.contains { $0.isNow || $0.startsSoon }) {
                notch.tab = .today
            }
            TabPill(title: "Estante", symbol: "tray.full.fill", selected: notch.tab == .shelf, showTitle: showTitle) {
                notch.tab = .shelf
            }
            TabPill(title: "Portapapeles", symbol: "doc.on.clipboard.fill", selected: notch.tab == .clipboard,
                    showTitle: showTitle) {
                notch.tab = .clipboard
            }
            TabPill(title: "Claude", symbol: "sparkle", selected: notch.tab == .claude, showTitle: showTitle,
                    badge: !claude.approvals.isEmpty) {
                notch.tab = .claude
            }
            TabPill(title: "Mac", symbol: "laptopcomputer", selected: notch.tab == .mac, showTitle: showTitle) {
                notch.tab = .mac
            }
        }
        .fixedSize()
    }

    private var voiceHeaderText: String {
        guard voice.phase == .dictating else {
            // Lo que va entendiendo, para que veas que sí te está oyendo.
            let words = voice.lastHeard.split(separator: " ").suffix(3).joined(separator: " ")
            return words.isEmpty ? "Te escucho…" : "Te escucho… “\(words)”"
        }
        switch voice.dictationTarget {
        case .reply: return "Tu respuesta…"
        case .terminal: return "Para la terminal…"
        case .chatGPT: return "Para ChatGPT…"
        case .claude(let destination): return "Para \(destination.label)…"
        case nil: return "Dictando…"
        }
    }

    private var todayStatusText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_MX")
        formatter.dateFormat = "EEEE d 'de' MMMM"
        return formatter.string(from: Date()).capitalizedFirst
    }

    private var fileCountText: String {
        let count = shelf.items.count
        if count == 0 { return "Estante vacío" }
        return count == 1 ? "1 archivo" : "\(count) archivos"
    }

    private var claudeStatusText: String {
        if !claude.hooksInstalled { return "Sin conectar" }
        if let first = claude.approvals.first { return first.isQuestion ? "Claude te pregunta algo" : "Permiso pendiente" }
        if let hold = claude.replyHold { return "\(hold.project) espera tu respuesta" }
        let active = claude.activeCount
        if active > 0 { return active == 1 ? "1 sesión trabajando" : "\(active) sesiones trabajando" }
        return "Conectado"
    }

    private var claudeStatusColor: Color {
        if !claude.hooksInstalled { return .secondary }
        if !claude.approvals.isEmpty { return Theme.warning }
        return Theme.success
    }

    @ViewBuilder
    private var statusView: some View {
        switch notch.tab {
        case .today:
            Text(verbatim: todayStatusText)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .lineLimit(1)
        case .shelf:
            Text(verbatim: fileCountText)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
        case .clipboard:
            HStack(spacing: 5) {
                Circle()
                    .fill(clipboard.shortcutsActive ? Theme.success : Theme.warning)
                    .frame(width: 6, height: 6)
                Text(clipboard.shortcutsActive ? "Atajos activos" : "Atajos inactivos")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }
        case .claude:
            HStack(spacing: 5) {
                Circle()
                    .fill(claudeStatusColor)
                    .frame(width: 6, height: 6)
                Text(verbatim: claudeStatusText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        case .mac:
            Text(verbatim: "Encendida hace \(Formatters.duration(monitor.snapshot.uptime))")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
    }

    // MARK: Aviso a los lados del notch (siempre negro, como la Dynamic Island)

    private var peekContent: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                if let url = notch.peek?.fileURL {
                    FileThumb(url: url, fill: true)
                        .frame(width: 24, height: 24)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                } else {
                    Image(systemName: notch.peek?.symbol ?? "sparkles")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(notch.peek?.tint ?? Theme.accent)
                }
                Spacer(minLength: 0)
            }
            .frame(width: notch.peekWing - 14)
            .padding(.leading, 14)

            Spacer(minLength: notch.notchSize.width)

            HStack(spacing: 5) {
                Spacer(minLength: 0)
                if notch.peek?.fileURL != nil {
                    Image(systemName: notch.peek?.symbol ?? "sparkles")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(notch.peek?.tint ?? Theme.accent)
                }
                Text(notch.peek?.title ?? "")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(width: notch.peekWing - 14)
            .padding(.trailing, 14)
        }
        .frame(width: notch.notchSize.width + notch.peekWing * 2, height: notch.notchSize.height)
    }
}

/// Pestaña del encabezado (Estante / Portapapeles / Mac). Solo la activa muestra su nombre.
struct TabPill: View {
    let title: String
    let symbol: String
    let selected: Bool
    var showTitle = true
    var badge = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(selected ? Theme.accent : .secondary)
                    .overlay(alignment: .topTrailing) {
                        if badge {
                            Circle()
                                .fill(Theme.warning)
                                .frame(width: 6, height: 6)
                                .offset(x: 4, y: -3)
                        }
                    }
                if selected && showTitle {
                    Text(title)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .padding(.horizontal, selected && showTitle ? 9 : 6)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.primary.opacity(selected ? 0.1 : 0)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(title)
    }
}
