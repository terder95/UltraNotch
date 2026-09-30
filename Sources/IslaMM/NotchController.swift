import AppKit
import SwiftUI
import Combine

enum IslandTab {
    case today, shelf, clipboard, claude, mac
}

/// Aviso corto que aparece a los lados del notch (como la isla del iPhone).
struct Peek {
    let id = UUID()
    var symbol: String
    var title: String
    var tint: Color
    var fileURL: URL? = nil
}

/// Controla la ventana de la isla: abrir al pasar el mouse, cerrar al salir,
/// avisos ("peek") y la pestaña activa.
@MainActor
final class NotchController: ObservableObject {
    @Published private(set) var isExpanded = false
    @Published private(set) var isPeeking = false
    @Published private(set) var peek: Peek? = nil
    @Published private(set) var toast: String? = nil
    @Published var tab: IslandTab = .shelf
    @Published private(set) var notchSize = CGSize(width: 190, height: 32)
    @Published var isDropTargeted = false {
        didSet {
            if isDropTargeted { tab = .shelf }
        }
    }
    /// Mientras arrastras: si vas a soltar en el estante o en AirDrop.
    @Published var dropZone: DropZone = .shelf
    @Published var style: IslandStyle = .glass {
        didSet { UserDefaults.standard.set(style.rawValue, forKey: NotchController.styleKey) }
    }
    private static let styleKey = "islandStyle"

    /// Actividad en vivo de Claude Code junto al notch (isla cerrada).
    @Published var live: LiveActivity? = nil
    /// Hay un permiso de Claude Code esperando: la isla baja la tarjeta.
    @Published var alertActive = false {
        didSet {
            if !alertActive && !isExpanded { panel?.ignoresMouseEvents = true }
        }
    }

    let panelSize = CGSize(width: 740, height: 340)
    let expandedSize = CGSize(width: 660, height: 288)
    let peekWing: CGFloat = 112
    let liveWing: CGFloat = 92
    /// Alitas del compañero (isla cerrada, sin Claude trabajando).
    let companionWing: CGFloat = 40
    /// Suena música y no está el compañero: la isla cerrada enseña carátula y barritas.
    var musicWings = false
    /// Altura extra de la tarjeta (preguntas con opciones, vista previa de cambios).
    @Published var alertExtra: CGFloat = 0
    var alertSize: CGSize { CGSize(width: 480, height: notchSize.height + 104 + alertExtra) }

    /// Se llama cada vez que la isla se abre.
    var onOpen: (() -> Void)?
    /// El compañero que vive junto al notch.
    weak var companion: CompanionController?
    /// Dónde está el globito del compañero (coordenadas de la ventana; .zero = no hay).
    private(set) var bubbleFrame: CGRect = .zero
    private var bubbleOwner: UUID?

    func setBubbleFrame(_ frame: CGRect, id: UUID) {
        bubbleOwner = id
        bubbleFrame = frame
    }

    /// Solo lo borra el mismo globito (si ya llegó otro, no le quitamos su lugar).
    func clearBubbleFrame(id: UUID) {
        guard bubbleOwner == id else { return }
        bubbleOwner = nil
        bubbleFrame = .zero
    }

    private var panel: NotchPanel?
    private var screen: NSScreen?
    private var tracker: AnyCancellable?
    private var observers = Set<AnyCancellable>()
    private var clickMonitor: Any?
    private var hoverSince: Date?
    private var outsideSince: Date?
    private var menuOpen = false
    private var stayOpenUntilVisited = false
    private var peekTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?

    init() {
        // Modo capturas: negro clásico (el cristal no se ve fuera de pantalla) y sin leer tus ajustes.
        if ModoCapturas.activo {
            style = .black
            return
        }
        let saved = UserDefaults.standard.string(forKey: NotchController.styleKey) ?? ""
        style = IslandStyle(rawValue: saved) ?? .glass
    }

    /// Modo capturas: deja la isla quieta en un estado (sin ventana, sin tiempos).
    func fijarParaCaptura(abierta: Bool, pestaña: IslandTab = .shelf, peek: Peek? = nil) {
        isExpanded = abierta
        tab = pestaña
        self.peek = peek
        isPeeking = peek != nil
        toast = nil
    }

    // MARK: Instalación

    func install<Content: View>(root: Content) {
        let newPanel = NotchPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        newPanel.isFloatingPanel = true
        newPanel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        newPanel.backgroundColor = .clear
        newPanel.isOpaque = false
        newPanel.hasShadow = false
        newPanel.hidesOnDeactivate = false
        newPanel.isMovable = false
        newPanel.isReleasedWhenClosed = false
        newPanel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        newPanel.ignoresMouseEvents = true

        let host = FirstMouseHostingView(rootView: root)
        host.sizingOptions = []
        host.frame = NSRect(origin: .zero, size: panelSize)
        host.autoresizingMask = [.width, .height]
        newPanel.contentView = host

        panel = newPanel
        reposition()
        newPanel.orderFrontRegardless()
        startTracking()
    }

    func reposition() {
        guard let panel = panel, let target = NotchGeometry.targetScreen() else { return }
        screen = target
        notchSize = NotchGeometry.notchSize(for: target)
        let frame = target.frame
        let origin = NSPoint(x: frame.midX - panelSize.width / 2, y: frame.maxY - panelSize.height)
        panel.setFrame(NSRect(origin: origin, size: panelSize), display: true)
    }

    // MARK: Seguimiento del mouse

    private func startTracking() {
        // Revisamos la posición del mouse 20 veces por segundo (consumo mínimo).
        tracker = Timer.publish(every: 0.05, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.tick()
            }

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.reposition() }
            .store(in: &observers)
        NotificationCenter.default.publisher(for: NSMenu.didBeginTrackingNotification)
            .sink { [weak self] _ in self?.menuOpen = true }
            .store(in: &observers)
        NotificationCenter.default.publisher(for: NSMenu.didEndTrackingNotification)
            .sink { [weak self] _ in self?.menuOpen = false }
            .store(in: &observers)

        // Clic en cualquier otra app → cerrar la isla.
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                self?.handleOutsideClick()
            }
        }
    }

    private func tick() {
        guard let screen = screen else { return }
        let mouse = NSEvent.mouseLocation
        let frame = screen.frame
        let buttonDown = (NSEvent.pressedMouseButtons & 1) != 0

        if isExpanded {
            let size = expandedSize
            let zone = NSRect(
                x: frame.midX - size.width / 2,
                y: frame.maxY - size.height,
                width: size.width,
                height: size.height
            ).insetBy(dx: -16, dy: -16)

            if zone.contains(mouse) {
                stayOpenUntilVisited = false
                outsideSince = nil
            } else if menuOpen || isDropTargeted || stayOpenUntilVisited {
                outsideSince = nil
            } else {
                if outsideSince == nil { outsideSince = Date() }
                if let since = outsideSince, Date().timeIntervalSince(since) > 0.22 {
                    close()
                }
            }
        } else if alertActive {
            // La tarjeta de permiso solo "atrapa" el mouse cuando estás encima de ella.
            let size = alertSize
            let card = NSRect(
                x: frame.midX - size.width / 2 - 12,
                y: frame.maxY - size.height - 4,
                width: size.width + 24,
                height: size.height + 8
            )
            panel?.ignoresMouseEvents = !card.contains(mouse)
            hoverSince = nil
        } else {
            let notch = notchSize
            let companionOn = companion?.enabled == true
            let wings: CGFloat
            if live != nil {
                wings = liveWing * 2
            } else if companionOn || musicWings {
                wings = companionWing * 2
            } else {
                wings = 0
            }

            // El globito del compañero solo "atrapa" el mouse cuando estás encima (para sus botones).
            let overBubble = bubbleScreenRect()?.contains(mouse) ?? false
            if let panel = panel, panel.ignoresMouseEvents == overBubble {
                panel.ignoresMouseEvents = !overBubble
            }
            if overBubble {
                hoverSince = nil
                return
            }

            if companionOn, let companion = companion {
                let buddyX = live != nil
                    ? frame.midX - notch.width / 2 - liveWing + 21
                    : companion.buddyPoint(on: screen, notchSize: notch, wing: companionWing).x
                companion.track(mouse: mouse, buddyX: buddyX, top: frame.maxY)
            }

            let zone = NSRect(
                x: frame.midX - (notch.width + wings) / 2 - 20,
                y: frame.maxY - notch.height - 4,
                width: notch.width + wings + 40,
                height: notch.height + 8
            )
            if zone.contains(mouse) {
                // Si vienes arrastrando un archivo, se abre al instante.
                if buttonDown {
                    open()
                    return
                }
                if hoverSince == nil { hoverSince = Date() }
                let delay = UserDefaults.standard.object(forKey: SettingsKeys.hoverDelay) as? Double ?? 0.1
                if let since = hoverSince, Date().timeIntervalSince(since) >= delay {
                    open()
                }
            } else {
                hoverSince = nil
            }
        }
    }

    /// El globito en coordenadas de pantalla.
    private func bubbleScreenRect() -> NSRect? {
        guard bubbleFrame != .zero, let panel = panel else { return nil }
        let origin = panel.frame.origin
        return NSRect(
            x: origin.x + bubbleFrame.minX,
            y: origin.y + panel.frame.height - bubbleFrame.maxY,
            width: bubbleFrame.width,
            height: bubbleFrame.height
        ).insetBy(dx: -2, dy: -2)
    }

    // MARK: Abrir / cerrar

    func open(pinned: Bool = false) {
        guard !isExpanded else { return }
        peekTask?.cancel()
        isPeeking = false
        stayOpenUntilVisited = pinned
        outsideSince = nil
        onOpen?()
        isExpanded = true
        panel?.ignoresMouseEvents = false
    }

    func close() {
        guard isExpanded else { return }
        isExpanded = false
        panel?.ignoresMouseEvents = true
        hoverSince = nil
        outsideSince = nil
        stayOpenUntilVisited = false
        toast = nil
    }

    private func handleOutsideClick() {
        guard isExpanded, !menuOpen else { return }
        close()
    }

    // MARK: Avisos

    /// Si la isla está cerrada: aviso a los lados del notch.
    /// Si está abierta: mensaje corto en la esquina.
    func flash(_ newPeek: Peek) {
        if isExpanded {
            toastTask?.cancel()
            toast = newPeek.title
            toastTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 1_600_000_000)
                guard !Task.isCancelled, let strongSelf = self else { return }
                strongSelf.toast = nil
            }
            return
        }

        peekTask?.cancel()
        peek = newPeek
        isPeeking = true
        peekTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            guard !Task.isCancelled, let strongSelf = self else { return }
            strongSelf.isPeeking = false
        }
    }
}
