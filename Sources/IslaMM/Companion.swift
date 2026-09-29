import SwiftUI
import AppKit
import Combine

// El "compañero": un personajito original que vive junto al notch, se asoma,
// te sigue con la mirada y a veces te dice algo en un globito.

/// Hacia dónde mira (cambia seguido; va aparte para no redibujar toda la isla).
@MainActor
final class CompanionGaze: ObservableObject {
    /// -1 izquierda … 1 derecha
    @Published var x: CGFloat = 0
    /// 0 al frente … 1 hacia abajo
    @Published var down: CGFloat = 0
    /// El mouse anda cerca.
    @Published var tracking = false
    /// El mouse está muy cerca: se emociona.
    @Published var excited = false
}

enum CompanionMood: Equatable {
    case idle, sleepy, listening, working, waiting, happy
    /// Reacciones a tu Mac: mucho trabajo (calor), batería bajita, música sonando.
    case hot, lowBattery, grooving

    /// Usa el color que elegiste; solo "te espera" se pone naranja para llamar tu atención.
    func tint(base: Color) -> Color {
        self == .waiting ? Theme.warning : base
    }
}

enum CompanionSide {
    case left, right

    var other: CompanionSide { self == .left ? .right : .left }
}

/// Travesuras del compañero (cuando no hay nada pasando).
enum CompanionAction: CaseIterable {
    case rest, lookAround, peek, walkAcross, dangle, hop, spin, wave, yawn, dance, coffee, stretch, read, heart, sneeze
    // Vehículos y visitas
    case skateboard, car, rocket, ufo, plane, friend
    // Juegos en su lugar
    case fishing, juggle, soccer, umbrella, bubbles, magic, photo

    var randomDuration: Double {
        switch self {
        case .rest: return Double.random(in: 4...8)
        case .lookAround: return 3
        case .peek: return 5
        case .walkAcross: return 4.5
        case .dangle: return 6.5
        case .hop: return 2
        case .spin: return 1.4
        case .wave: return 2.5
        case .yawn: return 3
        case .dance: return 5
        case .coffee: return 6
        case .stretch: return 2.4
        case .read: return 7
        case .heart: return 2.2
        case .sneeze: return 2.2
        case .skateboard: return 4.5
        case .car: return 7
        case .rocket: return 6.5
        case .ufo: return 7.5
        case .plane: return 8.5
        case .friend: return 9.5
        case .fishing: return 9
        case .juggle: return 5
        case .soccer: return 5
        case .umbrella: return 7
        case .bubbles: return 6
        case .magic: return 4.5
        case .photo: return 4.2
        }
    }

    /// Al terminar queda del otro lado del notch.
    var swapsSide: Bool {
        switch self {
        case .walkAcross, .skateboard, .car, .ufo, .plane, .magic: return true
        default: return false
        }
    }

    /// Se aleja de su lugar: si algo pasa (Claude, tu voz, un globito) mejor regresa.
    var travels: Bool {
        switch self {
        case .walkAcross, .skateboard, .car, .rocket, .ufo, .plane, .friend, .magic, .fishing: return true
        default: return false
        }
    }

    /// Qué tan seguido sale cada una junto al notch.
    private var weight: Int {
        switch self {
        case .rest: return 0
        case .lookAround, .peek, .walkAcross, .hop, .wave: return 4
        case .skateboard, .friend: return 3
        case .dangle, .dance, .coffee, .read, .heart, .stretch, .yawn, .spin: return 2
        case .car, .rocket, .ufo, .plane, .fishing, .juggle, .soccer, .bubbles, .magic, .photo: return 2
        case .sneeze: return 1
        // Arriba del notch no se vería la nube: el paraguas solo sale cuando anda de paseo.
        case .umbrella: return 0
        }
    }

    static func randomFun(excluding previous: CompanionAction, allowTravel: Bool = true) -> CompanionAction {
        let options = allCases.filter { $0 != previous && $0.weight > 0 && (allowTravel || !$0.travels) }
        let total = options.reduce(0) { $0 + $1.weight }
        var roll = Int.random(in: 0..<max(total, 1))
        for option in options {
            roll -= option.weight
            if roll < 0 { return option }
        }
        return .lookAround
    }
}

/// Colores para el compañero (Configuración › Compañero).
enum MascotPalette {
    struct Preset {
        let name: String
        let hex: String   // "" = color de acento del sistema
    }

    static let presets: [Preset] = [
        Preset(name: "Color del sistema", hex: ""),
        Preset(name: "Azul", hex: "1EA2DD"),
        Preset(name: "Rosa", hex: "E12378"),
        Preset(name: "Morado", hex: "8B5CF6"),
        Preset(name: "Verde", hex: "22C55E"),
        Preset(name: "Naranja", hex: "F97316"),
        Preset(name: "Terracota", hex: "D97757"),
        Preset(name: "Amarillo", hex: "EAB308"),
        Preset(name: "Gris", hex: "9CA3AF")
    ]

    static func color(hex: String) -> Color {
        let clean = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# ")).uppercased()
        guard clean.count == 6, let value = UInt32(clean, radix: 16) else { return Theme.accent }
        return Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    static func hex(from color: Color) -> String {
        guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return "" }
        func channel(_ value: CGFloat) -> Int { Int((min(max(value, 0), 1) * 255).rounded()) }
        return String(format: "%02X%02X%02X", channel(rgb.redComponent), channel(rgb.greenComponent), channel(rgb.blueComponent))
    }
}

/// Globito de texto.
struct CompanionBubble: Identifiable {
    enum Kind { case info, claude, reply, warning }

    let id = UUID()
    var title: String
    var message: String? = nil
    var kind: Kind = .info
    var buttons: [BubbleButton] = []
    /// Qué pasa si tocas el globito.
    var onTap: (() -> Void)? = nil
    /// Segundos visible. nil = hasta que se quite solo (por ejemplo, al responder).
    var duration: Double? = 7
}

struct BubbleButton: Identifiable {
    let id = UUID()
    let title: String
    var symbol: String? = nil
    var prominent = false
    let action: () -> Void
}

// MARK: - Controlador

@MainActor
final class CompanionController: ObservableObject {
    @Published var enabled = true {
        didSet {
            UserDefaults.standard.set(enabled, forKey: Keys.enabled)
            if !enabled { dismissBubble() }
        }
    }
    @Published var bubblesEnabled = true {
        didSet {
            UserDefaults.standard.set(bubblesEnabled, forKey: Keys.bubbles)
            if !bubblesEnabled { dismissBubble() }
        }
    }
    /// Cada cuántos minutos dice algo por su cuenta (0 = nunca).
    @Published var chatterMinutes: Double = 15 {
        didSet { UserDefaults.standard.set(chatterMinutes, forKey: Keys.chatter) }
    }
    @Published var followMouse = true {
        didSet {
            UserDefaults.standard.set(followMouse, forKey: Keys.follow)
            if !followMouse { resetGaze() }
        }
    }
    /// Color del compañero en hexadecimal ("" = color de acento del sistema).
    @Published var colorHex = "" {
        didSet { UserDefaults.standard.set(colorHex, forKey: Keys.color) }
    }

    var color: Color {
        colorHex.isEmpty ? Theme.accent : MascotPalette.color(hex: colorHex)
    }

    /// Cada cuántos minutos sale a pasear por la pantalla (0 = nunca).
    @Published var roamMinutes: Double = 20 {
        didSet { UserDefaults.standard.set(roamMinutes, forKey: Keys.roam) }
    }
    /// Se duerme si no usas la Mac tantos minutos (0 = nunca, salvo en la noche).
    @Published var sleepMinutes: Double = 3 {
        didSet { UserDefaults.standard.set(sleepMinutes, forKey: Keys.sleep) }
    }
    /// Cuando abres algo por voz, vuela a presentarte la ventana.
    @Published var presentWindows = true {
        didSet { UserDefaults.standard.set(presentWindows, forKey: Keys.present) }
    }
    /// Reacciona a tu Mac: suda si va a tope, tiembla con poca batería, baila con tu música.
    @Published var reactionsEnabled = true {
        didSet { UserDefaults.standard.set(reactionsEnabled, forKey: Keys.reactions) }
    }

    // Animación actual (la vista calcula la pose con esto).
    @Published private(set) var action: CompanionAction = .rest
    @Published private(set) var actionStart = Date()
    @Published private(set) var actionDuration: Double = 5
    /// De qué lado del notch está.
    @Published private(set) var side: CompanionSide = .left
    /// Anda de paseo por la pantalla.
    @Published private(set) var roaming = false
    /// Está dormido (de noche o si no usas la Mac).
    @Published private(set) var sleepy = false
    /// Festeja (confeti) hasta esta hora.
    @Published private(set) var celebrateUntil = Date.distantPast

    @Published private(set) var bubble: CompanionBubble?
    /// Mueve la boca hasta esta hora (cuando empieza a "hablar").
    @Published private(set) var talkUntil = Date.distantPast
    let gaze = CompanionGaze()

    weak var claude: ClaudeCodeMonitor?
    weak var monitor: SystemMonitor?
    weak var shelf: ShelfStore?
    /// Abre la isla en una pestaña.
    var openTab: ((IslandTab) -> Void)?
    /// true si la isla está abierta o mostrando un permiso (no interrumpimos).
    var isIslandBusy: (() -> Bool)?
    /// true si no hay nada pasando (Claude quieto, sin voz): puede hacer travesuras.
    var isMoodIdle: (() -> Bool)?
    /// Pide salir a pasear por la pantalla (lo maneja AppDelegate).
    var onRoamRequest: (() -> Void)?
    /// Modo programación activo: estás trabajando, no se duerme.
    var isKeepingAwake: (() -> Bool)?

    private enum Keys {
        static let enabled = "companionEnabled"
        static let bubbles = "companionBubbles"
        static let chatter = "companionChatterMinutes"
        static let follow = "companionFollowMouse"
        static let color = "companionColor"
        static let roam = "companionRoamMinutes"
        static let sleep = "companionSleepMinutes"
        static let present = "companionPresentWindows"
        static let reactions = "companionReactions"
    }

    private var hideTask: Task<Void, Never>?
    private var chatterTimer: AnyCancellable?
    private var lastBubbleAt = Date()
    private var tipIndex = 0
    private var lastShelfMention = Date.distantPast
    private var actionTimer: AnyCancellable?
    private var lastFun: CompanionAction = .rest
    private var lastRoam = Date()

    init() {
        let defaults = UserDefaults.standard
        enabled = defaults.object(forKey: Keys.enabled) as? Bool ?? true
        bubblesEnabled = defaults.object(forKey: Keys.bubbles) as? Bool ?? true
        chatterMinutes = defaults.object(forKey: Keys.chatter) as? Double ?? 15
        followMouse = defaults.object(forKey: Keys.follow) as? Bool ?? true
        colorHex = defaults.string(forKey: Keys.color) ?? ""
        roamMinutes = defaults.object(forKey: Keys.roam) as? Double ?? 20
        sleepMinutes = defaults.object(forKey: Keys.sleep) as? Double ?? 3
        presentWindows = defaults.object(forKey: Keys.present) as? Bool ?? true
        reactionsEnabled = defaults.object(forKey: Keys.reactions) as? Bool ?? true
        tipIndex = Int.random(in: 0..<20)
    }

    func start() {
        chatterTimer = Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.chatterTick()
            }
        actionTimer = Timer.publish(every: 0.2, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.tickActions()
            }
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            self?.greet()
        }
    }

    // MARK: Globitos

    func say(_ newBubble: CompanionBubble) {
        guard enabled, bubblesEnabled else { return }
        hideTask?.cancel()
        // Si andaba lejos (en coche, en ovni…), regresa a su lugar para hablarte.
        if action.travels { play(.rest) }
        bubble = newBubble
        lastBubbleAt = Date()
        talkUntil = Date().addingTimeInterval(2.2)
        guard let duration = newBubble.duration else { return }
        let id = newBubble.id
        hideTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled, let strongSelf = self, strongSelf.bubble?.id == id else { return }
            strongSelf.bubble = nil
        }
    }

    func dismissBubble() {
        hideTask?.cancel()
        bubble = nil
    }

    func dismissBubble(kind: CompanionBubble.Kind) {
        if bubble?.kind == kind { dismissBubble() }
    }

    /// Tocaste el globito.
    func tapBubble() {
        let action = bubble?.onTap
        dismissBubble()
        action?()
    }

    func greet() {
        let name = NSFullUserName().split(separator: " ").first.map(String.init) ?? ""
        say(CompanionBubble(
            title: name.isEmpty ? "¡Hola! Aquí ando" : "¡Hola, \(name)! Aquí ando",
            message: "Pasa el mouse por el notch para abrirme, o di “Oye Claudio”.",
            duration: 7
        ))
    }

    /// Claude Code terminó. Con `hold`, la sesión espera tu respuesta por voz.
    func showFinished(session: ClaudeSession, hold: ReplyHold?, onReply: @escaping () -> Void, onIgnore: @escaping () -> Void) {
        var newBubble = CompanionBubble(
            title: "¡Listo! Terminé en \(session.project)",
            message: session.summary,
            kind: .claude,
            onTap: { [weak self] in self?.openTab?(.claude) },
            duration: 9
        )
        if hold != nil {
            newBubble.kind = .reply
            newBubble.message = [session.summary, "Di “responde…” y tu mensaje, o toca Responder."]
                .compactMap { $0 }
                .joined(separator: "\n")
            newBubble.buttons = [
                BubbleButton(title: "Responder", symbol: "mic.fill", prominent: true, action: onReply),
                BubbleButton(title: "Ignorar", action: onIgnore)
            ]
            newBubble.duration = nil
        }
        say(newBubble)
    }

    // MARK: Plática

    private func chatterTick() {
        guard enabled, bubblesEnabled, chatterMinutes > 0, bubble == nil, !roaming, !sleepy else { return }
        if isIslandBusy?() == true { return }
        guard Date().timeIntervalSince(lastBubbleAt) >= chatterMinutes * 60 else { return }
        // Si no estás usando la Mac, no habla solo.
        let idle = min(
            CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .mouseMoved),
            CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown)
        )
        if idle > 300 { return }
        say(nextChatter())
    }

    private func nextChatter() -> CompanionBubble {
        let openClaude: () -> Void = { [weak self] in self?.openTab?(.claude) }
        let openMac: () -> Void = { [weak self] in self?.openTab?(.mac) }

        if let claude = claude {
            if let active = claude.sessions.first(where: { $0.status.isActive }) {
                return CompanionBubble(title: "\(active.project) sigue trabajando",
                                       message: active.steps.last?.text ?? "Pensando…",
                                       kind: .claude, onTap: openClaude, duration: 6)
            }
            if let waiting = claude.sessions.first(where: { $0.status == .waiting }) {
                return CompanionBubble(title: "\(waiting.project) te está esperando",
                                       message: waiting.summary, kind: .claude, onTap: openClaude, duration: 9)
            }
        }

        if let monitor = monitor {
            monitor.refreshStats(includeDisk: false)
            let snapshot = monitor.snapshot
            let ratio = Double(snapshot.memory.used) / Double(max(snapshot.memory.total, 1))
            if ratio > 0.88 || snapshot.pressure == .critical {
                return CompanionBubble(title: "La RAM va al \(Int(ratio * 100)) %",
                                       message: "Toca para ver qué apps usan más y liberar memoria.",
                                       kind: .warning, onTap: openMac, duration: 9)
            }
            if let battery = snapshot.battery, battery.percent <= 20, !battery.onAC {
                return CompanionBubble(title: "Batería al \(battery.percent) %",
                                       message: "Buen momento para conectar el cargador.",
                                       kind: .warning, onTap: openMac, duration: 8)
            }
            if snapshot.disk.total > 0, Double(snapshot.disk.free) / Double(snapshot.disk.total) < 0.1 {
                return CompanionBubble(title: "Quedan \(Formatters.bytes(snapshot.disk.free)) libres",
                                       message: "Toca para ver qué se puede limpiar.",
                                       kind: .warning, onTap: openMac, duration: 9)
            }
        }

        if let shelf = shelf, !shelf.items.isEmpty, Date().timeIntervalSince(lastShelfMention) > 3 * 3600 {
            lastShelfMention = Date()
            let count = shelf.items.count
            return CompanionBubble(title: "Tienes \(count == 1 ? "1 archivo" : "\(count) archivos") en el estante",
                                   message: "Arrástralos a donde los necesites.",
                                   onTap: { [weak self] in self?.openTab?(.shelf) }, duration: 7)
        }

        let tips = currentTips()
        let tip = tips[tipIndex % tips.count]
        tipIndex += 1
        return CompanionBubble(title: tip.0, message: tip.1, duration: 8)
    }

    private func currentTips() -> [(String, String)] {
        let project = ProjectStore.shared.projects.first(where: { !$0.name.isEmpty && $0.projectID != nil })?.name
        return [
            ("Tip: ⌘C y luego un número", "Guarda lo que copiaste en esa ranura (1 a 9)."),
            ("Tip: ⌘V y luego un número", "Pega lo que guardaste en esa ranura."),
            ("Tip: “Oye Claudio, nuevo chat…”", "Dicta tu pregunta y te abro un chat nuevo con Claude."),
            project.map { ("Tip: “Oye Claudio, a \($0)…”", "Lo que dictes se va directo a ese proyecto de Claude.") }
                ?? ("Tip: agrega tus proyectos", "En Configuración › Proyectos de Claude, y mándales mensajes por voz."),
            ("Tip: “Oye Claudio, cowork…”", "Abre una tarea nueva de Cowork con lo que dictes."),
            ("Tip: arrastra archivos al notch", "Se quedan en el estante para usarlos después."),
            ("Tip: “responde…”", "Cuando Claude Code termina, contéstale por voz y sigue trabajando."),
            ("Tip: el engrane ⚙︎ de la isla", "Ahí cambias la frase, los tiempos y tus proyectos."),
            ("Tip: pestaña Hoy", "Tu música y tus próximas juntas, con botón para unirte a Teams, Meet o Zoom."),
            ("Tip: tu diccionario", "En Configuración › Voz enséñame palabras y correcciones (“cloud code” → “Claude Code”).")
        ]
    }

    // MARK: Mirada

    /// Se llama 20 veces por segundo con la isla cerrada.
    func track(mouse: NSPoint, buddyX: CGFloat, top: CGFloat) {
        guard enabled, followMouse else { return }
        let dx = mouse.x - buddyX
        let dy = top - mouse.y
        let near = dy < 320 && abs(dx) < 700
        let x = near ? max(-1, min(1, dx / 300)) : 0
        let down = near ? max(0, min(1, dy / 240)) : 0
        let roundedX = (x * 8).rounded() / 8
        let roundedDown = (down * 4).rounded() / 4
        if gaze.x != roundedX { gaze.x = roundedX }
        if gaze.down != roundedDown { gaze.down = roundedDown }
        if gaze.tracking != near { gaze.tracking = near }
        let excited = dy < 110 && abs(dx) < 260
        if gaze.excited != excited { gaze.excited = excited }
    }

    private func resetGaze() {
        gaze.x = 0
        gaze.down = 0
        gaze.tracking = false
        gaze.excited = false
    }

    // MARK: Animaciones

    /// Cambia de travesura cuando termina la actual; se duerme y despierta solo.
    private func tickActions() {
        guard enabled else { return }
        let userIdle = CompanionController.userIdleSeconds()
        let working = isKeepingAwake?() ?? false
        let nowSleepy = !working && (CompanionController.isNight || (sleepMinutes > 0 && userIdle > sleepMinutes * 60))
        if nowSleepy != sleepy {
            sleepy = nowSleepy
            if !nowSleepy { play(.yawn) } // despierta: bosteza
        }

        let now = Date()
        // Si algo lo interrumpe a medio viaje, regresa a su lado.
        if action.travels && (sleepy || isMoodIdle?() == false || now < celebrateUntil) {
            play(.rest)
        }
        if now.timeIntervalSince(actionStart) >= actionDuration {
            if action.swapsSide { side = side.other }
            nextAction()
        }

        // De vez en cuando sale a pasear por la pantalla.
        if roamMinutes > 0, !roaming, !sleepy, action == .rest, bubble == nil,
           now.timeIntervalSince(lastRoam) > roamMinutes * 60,
           userIdle < 90, isIslandBusy?() != true, isMoodIdle?() ?? true {
            lastRoam = now
            onRoamRequest?()
        }
    }

    /// Hace una animación ya.
    func play(_ newAction: CompanionAction) {
        action = newAction
        actionStart = Date()
        actionDuration = newAction.randomDuration
        if newAction != .rest { lastFun = newAction }
    }

    private func nextAction() {
        // Entre travesura y travesura, un ratito de descanso.
        guard action == .rest, !sleepy, !roaming, isMoodIdle?() ?? true else {
            play(.rest)
            return
        }
        // Con un globito abierto no se va lejos (la colita tiene que apuntarle).
        play(CompanionAction.randomFun(excluding: lastFun, allowTravel: bubble == nil))
    }

    /// Conectaste el cargador: se pone contento.
    func powerConnected() {
        guard enabled, reactionsEnabled, !roaming, !sleepy else { return }
        if isMoodIdle?() ?? true { play(.heart) }
        if bubble == nil, isIslandBusy?() != true {
            say(CompanionBubble(title: "¡Ñam! Energía", message: nil, duration: 3))
        }
    }

    /// Festeja cuando Claude termina una tarea.
    func celebrate() {
        celebrateUntil = Date().addingTimeInterval(3.5)
    }

    func beginRoam() {
        roaming = true
        lastRoam = Date()
    }

    func endRoam() {
        roaming = false
        lastRoam = Date()
        play(.hop)
    }

    /// Dónde está el personajito en la pantalla (para mirar el mouse y salir de paseo).
    func buddyPoint(on screen: NSScreen, notchSize: CGSize, wing: CGFloat) -> NSPoint {
        let frame = screen.frame
        let offset = notchSize.width / 2 + wing / 2
        return NSPoint(x: side == .left ? frame.midX - offset : frame.midX + offset,
                       y: frame.maxY - notchSize.height / 2)
    }

    /// Segundos sin tocar la Mac (mouse, teclado, scroll, trackpad…).
    static func userIdleSeconds() -> Double {
        if let anyInput = CGEventType(rawValue: ~UInt32(0)) {
            return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
        }
        return min(
            CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .mouseMoved),
            CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown),
            CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .scrollWheel)
        )
    }

    static var isNight: Bool {
        let hour = Calendar.current.component(.hour, from: Date())
        return hour >= 23 || hour < 6
    }
}

// MARK: - Globito

/// Globito con una colita que apunta al compañero.
struct BubbleShape: Shape {
    static let tail: CGFloat = 7
    static let radius: CGFloat = 14
    var tailX: CGFloat

    func path(in rect: CGRect) -> Path {
        let tail = BubbleShape.tail
        let r = BubbleShape.radius
        let body = CGRect(x: rect.minX, y: rect.minY + tail, width: rect.width, height: max(rect.height - tail, 2 * r))
        let x = min(max(rect.minX + tailX, body.minX + r + tail), body.maxX - r - tail)

        var path = Path()
        path.move(to: CGPoint(x: body.minX + r, y: body.minY))
        path.addLine(to: CGPoint(x: x - tail, y: body.minY))
        path.addLine(to: CGPoint(x: x, y: rect.minY))
        path.addLine(to: CGPoint(x: x + tail, y: body.minY))
        path.addLine(to: CGPoint(x: body.maxX - r, y: body.minY))
        path.addArc(tangent1End: CGPoint(x: body.maxX, y: body.minY), tangent2End: CGPoint(x: body.maxX, y: body.minY + r), radius: r)
        path.addLine(to: CGPoint(x: body.maxX, y: body.maxY - r))
        path.addArc(tangent1End: CGPoint(x: body.maxX, y: body.maxY), tangent2End: CGPoint(x: body.maxX - r, y: body.maxY), radius: r)
        path.addLine(to: CGPoint(x: body.minX + r, y: body.maxY))
        path.addArc(tangent1End: CGPoint(x: body.minX, y: body.maxY), tangent2End: CGPoint(x: body.minX, y: body.maxY - r), radius: r)
        path.addLine(to: CGPoint(x: body.minX, y: body.minY + r))
        path.addArc(tangent1End: CGPoint(x: body.minX, y: body.minY), tangent2End: CGPoint(x: body.minX + r, y: body.minY), radius: r)
        path.closeSubpath()
        return path
    }
}

struct CompanionBubbleView: View {
    let bubble: CompanionBubble
    let tailX: CGFloat
    var onTap: () -> Void
    var onClose: () -> Void

    static let width: CGFloat = 280

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(bubble.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if let message = bubble.message, !message.isEmpty {
                        Text(message)
                            .font(.system(size: 11))
                            .foregroundColor(Color.white.opacity(0.72))
                            .lineLimit(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(Color.white.opacity(0.45))
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Cerrar")
            }
            if !bubble.buttons.isEmpty {
                HStack(spacing: 6) {
                    ForEach(bubble.buttons) { button in
                        Button(action: button.action) {
                            if let symbol = button.symbol {
                                Label(button.title, systemImage: symbol)
                            } else {
                                Text(button.title)
                            }
                        }
                        .buttonStyle(ActionButtonStyle(tint: button.prominent ? Theme.accent : Color.white.opacity(0.85),
                                                       filled: button.prominent))
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 9 + BubbleShape.tail)
        .padding(.bottom, 10)
        .frame(width: CompanionBubbleView.width, alignment: .leading)
        .background(BubbleShape(tailX: tailX).fill(Theme.island))
        .overlay(BubbleShape(tailX: tailX).stroke(Color.white.opacity(0.16), lineWidth: 0.8))
        .contentShape(BubbleShape(tailX: tailX))
        .onTapGesture(perform: onTap)
        .shadow(color: Color.black.opacity(0.35), radius: 10, x: 0, y: 5)
        .environment(\.colorScheme, .dark)
    }
}
