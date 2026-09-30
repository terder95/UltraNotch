import AppKit
import SwiftUI

// Modo capturas: `UltraNotch --capturas <carpeta>` dibuja la isla con datos de ejemplo
// (inventados: nada de tu Mac, tu música, tu agenda ni tu portapapeles) y guarda
// imágenes PNG para el README. No abre ventanas en pantalla, no pide permisos,
// no instala los avisos de Claude Code y no usa la red. Al terminar, sale sola.

enum ModoCapturas {
    static let marker = "--capturas"
    /// Estamos generando capturas (los stores no leen nada real).
    private(set) static var activo = false
    /// Con qué vista abre la pestaña Hoy (nil = la de siempre).
    static var hoyInicial: TodayMode?

    @MainActor
    static func correr(carpeta: String) -> Never {
        activo = true
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.appearance = NSAppearance(named: .darkAqua)

        let destino = URL(fileURLWithPath: (carpeta as NSString).expandingTildeInPath, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: destino, withIntermediateDirectories: true)
        } catch {
            print("No pude crear la carpeta \(destino.path): \(error.localizedDescription)")
            exit(1)
        }
        let taller = TallerCapturas(destino: destino)
        taller.generarTodo()
        taller.limpiar()
        print("Listo: \(taller.guardadas) imágenes en \(destino.path)")
        exit(0)
    }
}

// MARK: - Taller: arma cada escena y la guarda

@MainActor
final class TallerCapturas {
    private let destino: URL
    private let archivos: URL
    private(set) var guardadas = 0

    private let notch = NotchController()
    private let shelf = ShelfStore()
    private let clipboard = ClipboardStore()
    private let monitor = SystemMonitor()
    private let claude = ClaudeCodeMonitor()
    private let voice = VoiceWake()
    private let companion = CompanionController()
    private let keepAwake = KeepAwake()
    private let music = NowPlaying()
    private let lyrics = LyricsStore()
    private let agenda = CalendarStore()

    init(destino: URL) {
        self.destino = destino
        archivos = FileManager.default.temporaryDirectory
            .appendingPathComponent("UltraNotchCapturas-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: archivos, withIntermediateDirectories: true)
    }

    func limpiar() {
        try? FileManager.default.removeItem(at: archivos)
    }

    // MARK: Todas

    func generarTodo() {
        cargarDatos()

        // 1) Notch cerrado: la mascota junto al notch (con audífonos: suena la música).
        claude.cargarDemo(sesiones: [], pendientes: [], uso: DatosDemo.uso())
        companion.fijarParaCaptura()
        notch.fijarParaCaptura(abierta: false)
        guardar(escena(ancho: 760, alto: 96), "notch-cerrado")

        // 2) Notch cerrado con un aviso de junta en el globito.
        companion.fijarParaCaptura(globo: DatosDemo.globoJunta())
        guardar(escena(ancho: 760, alto: 176), "notch-cerrado-aviso-junta")

        companion.fijarParaCaptura()
        claude.cargarDemo(sesiones: DatosDemo.sesiones(), pendientes: [], uso: DatosDemo.uso())

        // 3) Hoy: música con la letra en vivo (a media línea de la letra).
        let (cancion, caratula, color) = DatosDemo.cancion()
        music.cargarDemo(cancion, carátula: caratula, color: color, segundo: DatosDemo.segundoDeLaLetra)
        ModoCapturas.hoyInicial = nil
        notch.fijarParaCaptura(abierta: true, pestaña: .today)
        guardar(escenaAbierta(), "hoy-musica-letra")

        // 4) Hoy: música y agenda.
        ModoCapturas.hoyInicial = .agenda
        guardar(escenaAbierta(), "hoy-agenda")
        ModoCapturas.hoyInicial = nil

        // 5) Estante.
        notch.fijarParaCaptura(abierta: true, pestaña: .shelf)
        guardar(escenaAbierta(), "estante", espera: 2.0)

        // 6) Portapapeles.
        notch.fijarParaCaptura(abierta: true, pestaña: .clipboard)
        guardar(escenaAbierta(), "portapapeles")

        // 7) Claude: sesiones.
        notch.fijarParaCaptura(abierta: true, pestaña: .claude)
        guardar(escenaAbierta(), "claude-sesiones")

        // 8) Mac.
        notch.fijarParaCaptura(abierta: true, pestaña: .mac)
        guardar(escenaAbierta(), "mac")

        // 9) Claude trabajando, junto al notch (un personajito por sesión).
        notch.fijarParaCaptura(abierta: false)
        notch.live = DatosDemo.actividadEnVivo()
        guardar(escena(ancho: 760, alto: 96), "claude-en-vivo")
        notch.live = nil

        // 10–12) Tarjetas que bajan del notch: permiso, pregunta y vista previa de cambios.
        for (pendiente, nombre) in [(DatosDemo.permisoBash(), "claude-permiso"),
                                     (DatosDemo.pregunta(), "claude-pregunta"),
                                     (DatosDemo.vistaPrevia(), "claude-vista-previa-cambios")] {
            claude.cargarDemo(sesiones: DatosDemo.sesiones(), pendientes: [pendiente], uso: DatosDemo.uso())
            notch.alertExtra = ApprovalLayout.extraHeight(for: pendiente)
            notch.alertActive = true
            guardar(escena(ancho: 760, alto: notch.alertSize.height + 44, centro: notch.alertSize.width + 28), nombre)
        }
        notch.alertActive = false
        notch.alertExtra = 0
        claude.cargarDemo(sesiones: DatosDemo.sesiones(), pendientes: [], uso: DatosDemo.uso())

        // 13) Aviso "peek": llegó una captura nueva al estante.
        let captura = archivos.appendingPathComponent("captura-diseño.png")
        notch.fijarParaCaptura(abierta: false, peek: Peek(symbol: "camera.viewfinder", title: "Captura en el estante",
                                                          tint: Theme.screenshot, fileURL: captura))
        guardar(escena(ancho: 760, alto: 96), "aviso-captura", espera: 1.5)
        notch.fijarParaCaptura(abierta: false)

        // 14) Hoja de Dottie (la mascota) con sus poses.
        guardar(HojaMascota(tint: companion.color), "dottie-poses")
    }

    // MARK: Datos de ejemplo

    private func cargarDatos() {
        let archivosDemo = DatosDemo.crearArchivos(en: archivos)
        shelf.cargarDemo(archivosDemo)
        // Miniaturas de Quick Look listas antes de dibujar el estante.
        for item in archivosDemo {
            Task { _ = await Thumbnailer.thumbnail(for: item.url) }
        }
        clipboard.cargarDemo(historial: DatosDemo.historial(), ranuras: DatosDemo.ranuras())
        clipboard.shortcutsActive = true
        monitor.cargarDemo(snapshot: DatosDemo.estadisticas(), apps: DatosDemo.apps(), limpieza: DatosDemo.limpieza())
        claude.cargarDemo(sesiones: DatosDemo.sesiones(), pendientes: [], uso: DatosDemo.uso())
        let (cancion, caratula, color) = DatosDemo.cancion()
        music.cargarDemo(cancion, carátula: caratula, color: color, segundo: DatosDemo.segundoDeLaLetra)
        lyrics.cargarDemo(DatosDemo.letra())
        agenda.cargarDemo(DatosDemo.juntas())
        esperar(1.0)
    }

    // MARK: Escenas

    private var panel: some View {
        IslandRootView(
            notch: notch,
            shelf: shelf,
            clipboard: clipboard,
            monitor: monitor,
            claude: claude,
            voice: voice,
            companion: companion,
            keepAwake: keepAwake,
            music: music,
            lyrics: lyrics,
            agenda: agenda,
            onRequestPermission: {},
            onOpenSettings: {}
        )
    }

    /// `centro`: lo que tapa la isla de la barra de menús (los menús se acomodan a los lados).
    private func escena(ancho: CGFloat, alto: CGFloat, centro: CGFloat = 440) -> some View {
        let vista = panel
        return EscenaEscritorio(ancho: ancho, alto: alto, alturaBarra: notch.notchSize.height, centro: centro) { vista }
    }

    private func escenaAbierta() -> some View {
        escena(ancho: 1000, alto: notch.expandedSize.height + 56, centro: notch.expandedSize.width + 28)
    }

    // MARK: Dibujar y guardar

    private func guardar<V: View>(_ vista: V, _ nombre: String, espera: Double = 0.8) {
        let raiz = vista
            .environment(\.locale, Locale(identifier: "es_MX"))
            .environment(\.colorScheme, .dark)
            .fixedSize()
        let host = NSHostingView(rootView: raiz)
        let tamaño = host.fittingSize
        host.frame = NSRect(origin: .zero, size: tamaño)

        // Ventana fuera de la pantalla: nunca se ve.
        let ventana = NSWindow(
            contentRect: NSRect(x: -30000, y: -30000, width: tamaño.width, height: tamaño.height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        ventana.isReleasedWhenClosed = false
        ventana.appearance = NSAppearance(named: .darkAqua)
        ventana.backgroundColor = .black
        ventana.contentView = host
        ventana.orderFrontRegardless()
        host.layoutSubtreeIfNeeded()
        esperar(espera)
        host.layoutSubtreeIfNeeded()
        host.display()

        let escala: CGFloat = 2 // Retina
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(tamaño.width * escala),
            pixelsHigh: Int(tamaño.height * escala),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return }
        rep.size = tamaño
        host.cacheDisplay(in: host.bounds, to: rep)
        ventana.orderOut(nil)
        ventana.contentView = nil

        let url = destino.appendingPathComponent("\(nombre).png")
        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        do {
            try png.write(to: url, options: .atomic)
            guardadas += 1
            print("✓ \(url.lastPathComponent)  (\(Int(tamaño.width * escala))×\(Int(tamaño.height * escala)))")
        } catch {
            print("✗ \(nombre): \(error.localizedDescription)")
        }
    }

    /// Deja correr el run loop (miniaturas, primeras vueltas de SwiftUI).
    private func esperar(_ segundos: Double) {
        RunLoop.main.run(until: Date().addingTimeInterval(segundos))
    }
}

// MARK: - Fondo tipo escritorio

/// Un escritorio de mentira: fondo de colores, barra de menús y la isla arriba al centro.
struct EscenaEscritorio<Panel: View>: View {
    let ancho: CGFloat
    let alto: CGFloat
    let alturaBarra: CGFloat
    var centro: CGFloat = 440
    @ViewBuilder var panel: () -> Panel

    var body: some View {
        ZStack(alignment: .top) {
            FondoEscritorio()
            BarraDeMenus(alto: alturaBarra, lado: max(0, (ancho - centro) / 2 - 20))
            panel()
        }
        .frame(width: ancho, height: alto, alignment: .top)
        .clipped()
    }
}

struct FondoEscritorio: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.13, green: 0.16, blue: 0.40),
                         Color(red: 0.38, green: 0.25, blue: 0.60),
                         Color(red: 0.90, green: 0.50, blue: 0.45)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(colors: [Color(red: 0.35, green: 0.75, blue: 0.95).opacity(0.55), .clear],
                           center: UnitPoint(x: 0.12, y: 0.95), startRadius: 0, endRadius: 420)
            RadialGradient(colors: [Color(red: 1.0, green: 0.72, blue: 0.45).opacity(0.5), .clear],
                           center: UnitPoint(x: 0.92, y: 0.15), startRadius: 0, endRadius: 380)
        }
    }
}

/// Barra de menús de mentira (el notch vive en medio; a cada lado va lo que quepa).
struct BarraDeMenus: View {
    let alto: CGFloat
    /// Espacio libre a cada lado de la isla.
    let lado: CGFloat

    fileprivate static let menus = ["Archivo", "Edición", "Visualización", "Ir", "Ventana", "Ayuda"]

    private var reloj: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_MX")
        formatter.dateFormat = "EEE d MMM  h:mm"
        return formatter.string(from: Date()).capitalizedFirst
    }

    var body: some View {
        HStack(spacing: 0) {
            ViewThatFits(in: .horizontal) {
                ForEach((0...BarraDeMenus.menus.count).reversed(), id: \.self) { cuantos in
                    izquierda(cuantos)
                }
            }
            .frame(width: lado, alignment: .leading)
            Spacer(minLength: 0)
            ViewThatFits(in: .horizontal) {
                derecha(completa: true)
                derecha(completa: false)
                Text(reloj).font(.system(size: 13, weight: .medium)).monospacedDigit().fixedSize()
            }
            .frame(width: lado, alignment: .trailing)
        }
        .foregroundColor(.white)
        .lineLimit(1)
        .padding(.horizontal, 16)
        .frame(height: alto)
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.22))
    }
}

extension BarraDeMenus {
    private func izquierda(_ cuantos: Int) -> some View {
        HStack(spacing: 18) {
            Image(systemName: "apple.logo")
                .font(.system(size: 14, weight: .medium))
            Text("Finder").font(.system(size: 13, weight: .bold))
            ForEach(BarraDeMenus.menus.prefix(cuantos), id: \.self) { menu in
                Text(menu).font(.system(size: 13))
            }
        }
        .fixedSize()
    }

    private func derecha(completa: Bool) -> some View {
        HStack(spacing: 18) {
            if completa {
                Image(systemName: "battery.75").font(.system(size: 14))
            }
            Image(systemName: "wifi").font(.system(size: 13, weight: .semibold))
            if completa {
                Image(systemName: "magnifyingglass").font(.system(size: 13, weight: .semibold))
            }
            Image(systemName: "switch.2").font(.system(size: 13, weight: .semibold))
            Text(reloj).font(.system(size: 13, weight: .medium)).monospacedDigit()
        }
        .fixedSize()
    }
}

// MARK: - Hoja de la mascota

/// Varias poses y travesuras de la mascota, cada una en su propio "notch".
struct HojaMascota: View {
    let tint: Color

    /// Un instante fijo (el letrero de la avioneta sale de este número).
    private static let base = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private struct Pose: Identifiable {
        let id = UUID()
        let titulo: String
        var accion: CompanionAction = .rest
        var segundo: Double = 0
        var animo: CompanionMood = .idle
        var festejo = false
        var lado: CompanionSide = .left
    }

    private let poses: [Pose] = [
        Pose(titulo: "Caminando", accion: .walkAcross, segundo: 1.6),
        Pose(titulo: "En patineta", accion: .skateboard, segundo: 3.1),
        Pose(titulo: "Despega en cohete", accion: .rocket, segundo: 2.08),
        Pose(titulo: "Avioneta con letrero", accion: .plane, segundo: 4.6),
        Pose(titulo: "Dormido", animo: .sleepy),
        Pose(titulo: "Festejando", festejo: true),
        Pose(titulo: "Con audífonos (suena tu música)", animo: .grooving),
        Pose(titulo: "Sudando: la Mac va a tope", animo: .hot),
        Pose(titulo: "Con su amigo", accion: .friend, segundo: 2.35),
        Pose(titulo: "Colgado de un hilo", accion: .dangle, segundo: 2.6),
        Pose(titulo: "Se lo lleva un ovni", accion: .ufo, segundo: 2.05),
        Pose(titulo: "Trabajando con Claude", animo: .working)
    ]

    private let columnas = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                BuddyFigure(pose: BuddyPose(), tint: tint, size: 26)
                    .frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Dottie")
                        .font(.system(size: 22, weight: .bold))
                    Text("Vive junto al notch, te sigue con la mirada y hace travesuras cuando no pasa nada.")
                        .font(.system(size: 13))
                        .foregroundColor(Color.white.opacity(0.7))
                }
            }
            VStack(spacing: 16) {
                ForEach(0..<(poses.count + columnas - 1) / columnas, id: \.self) { fila in
                    HStack(spacing: 16) {
                        ForEach(fila * columnas..<min(poses.count, fila * columnas + columnas), id: \.self) { index in
                            celda(poses[index])
                        }
                    }
                }
            }
        }
        .foregroundColor(.white)
        .padding(28)
        .background(
            LinearGradient(colors: [Color(red: 0.10, green: 0.11, blue: 0.20), Color(red: 0.17, green: 0.13, blue: 0.27)],
                           startPoint: .top, endPoint: .bottom)
        )
    }

    // Medidas del escenario (en puntos, antes de agrandar).
    private static let panel: CGFloat = 260
    private static let notchAncho: CGFloat = 96
    private static let notchAlto: CGFloat = 32
    private static let ala: CGFloat = 40
    private static let alto: CGFloat = 80
    private static let zoom: CGFloat = 2.4

    private func celda(_ pose: Pose) -> some View {
        let fecha = HojaMascota.base.addingTimeInterval(pose.segundo)
        let input = CompanionStageInput(
            action: pose.accion,
            actionStart: HojaMascota.base,
            actionDuration: pose.accion.randomDuration,
            side: pose.lado,
            mood: pose.animo,
            celebrateUntil: pose.festejo ? fecha.addingTimeInterval(5) : .distantPast,
            talkUntil: .distantPast,
            panelWidth: HojaMascota.panel,
            notchWidth: HojaMascota.notchAncho,
            notchHeight: HojaMascota.notchAlto,
            wing: HojaMascota.ala,
            size: 18
        )
        var cuadro = input.frame(at: fecha, gaze: GazeSnapshot())
        if pose.animo == .grooving { cuadro.pose.headphones = true }
        let escenario = ZStack(alignment: .topLeading) {
            FondoEscritorio()
            Rectangle()
                .fill(Color.black.opacity(0.22))
                .frame(height: HojaMascota.notchAlto)
            NotchShape(topRadius: 7, bottomRadius: 11)
                .fill(Theme.island)
                .frame(width: HojaMascota.notchAncho + HojaMascota.ala * 2 + 14, height: HojaMascota.notchAlto)
                .position(x: HojaMascota.panel / 2, y: HojaMascota.notchAlto / 2)
            if pose.animo == .grooving {
                // Las barritas del otro lado, como en la isla.
                EqualizerBars(color: tint, height: 13, animated: false)
                    .position(x: HojaMascota.panel / 2 + HojaMascota.notchAncho / 2 + HojaMascota.ala / 2,
                              y: HojaMascota.notchAlto / 2)
            }
            StageSceneView(frame: cuadro, tint: pose.animo == .waiting ? Theme.warning : tint, size: 18)
                .frame(width: HojaMascota.panel, height: HojaMascota.alto, alignment: .topLeading)
        }
        .frame(width: HojaMascota.panel, height: HojaMascota.alto, alignment: .topLeading)
        .clipped()

        return VStack(alignment: .leading, spacing: 8) {
            escenario
                .scaleEffect(HojaMascota.zoom, anchor: .topLeading)
                .frame(width: HojaMascota.panel * HojaMascota.zoom, height: HojaMascota.alto * HojaMascota.zoom,
                       alignment: .topLeading)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            Text(pose.titulo)
                .font(.system(size: 14, weight: .semibold))
                .padding(.leading, 4)
        }
    }
}

// MARK: - Datos inventados

@MainActor
enum DatosDemo {
    // MARK: Música

    /// En qué segundo va la canción (a media línea de la letra).
    static let segundoDeLaLetra: Double = 64

    static func cancion() -> (NowPlaying.Track, NSImage?, Color) {
        let track = NowPlaying.Track(title: "Luces de la ciudad", artist: "Los Satélites", album: "Noches de verano",
                                     player: .spotify, playing: true, duration: 214)
        let color = Color(red: 1.0, green: 0.48, blue: 0.40)
        return (track, caratula(), color)
    }

    static func letra() -> [LyricLine] {
        let versos: [(Double, String)] = [
            (38, "Salgo tarde de la oficina"),
            (43, "con el cielo pintado de naranja"),
            (48.5, "el camión ya dobla la esquina"),
            (53.5, "y yo corro sin ninguna prisa"),
            (58, "Todo brilla cuando va cayendo el sol"),
            (62.5, "y las luces de la ciudad me siguen"),
            (67, "como estrellas que bajaron a bailar"),
            (72, "sobre el asfalto que nunca duerme"),
            (77, "♪"),
            (84, "Luces de la ciudad"),
            (88, "no me dejen de alumbrar")
        ]
        return versos.enumerated().map { LyricLine(id: $0.offset, time: $0.element.0, text: $0.element.1) }
    }

    /// Carátula inventada: atardecer con edificios.
    static func caratula() -> NSImage? {
        guard let png = dibujarPNG(ancho: 300, alto: 300, { rect in
            let cielo = NSGradient(colors: [NSColor(red: 0.42, green: 0.22, blue: 0.78, alpha: 1),
                                            NSColor(red: 1.0, green: 0.45, blue: 0.42, alpha: 1),
                                            NSColor(red: 1.0, green: 0.78, blue: 0.45, alpha: 1)])
            cielo?.draw(in: rect, angle: -90)
            // Sol con franjas.
            let sol = NSRect(x: 70, y: 70, width: 160, height: 160)
            NSColor(red: 1.0, green: 0.92, blue: 0.62, alpha: 1).setFill()
            NSBezierPath(ovalIn: sol).fill()
            NSColor(red: 1.0, green: 0.55, blue: 0.45, alpha: 1).setFill()
            for index in 0..<5 {
                let y = 80 + CGFloat(index) * 13
                NSBezierPath(rect: NSRect(x: 60, y: y, width: 180, height: CGFloat(5 - index) + 1)).fill()
            }
            // Edificios.
            NSColor(red: 0.12, green: 0.08, blue: 0.25, alpha: 1).setFill()
            let alturas: [CGFloat] = [70, 110, 85, 140, 60, 120, 95, 75]
            var x: CGFloat = 0
            for (index, altura) in alturas.enumerated() {
                let ancho: CGFloat = index % 2 == 0 ? 34 : 42
                NSBezierPath(rect: NSRect(x: x, y: 0, width: ancho, height: altura)).fill()
                x += ancho + 1
            }
            // Ventanitas encendidas.
            NSColor(red: 1.0, green: 0.85, blue: 0.45, alpha: 0.9).setFill()
            for index in 0..<26 {
                let wx = CGFloat((index * 37) % 290) + 4
                let wy = CGFloat((index * 23) % 50) + 8
                NSBezierPath(rect: NSRect(x: wx, y: wy, width: 4, height: 5)).fill()
            }
        }) else { return nil }
        return NSImage(data: png)
    }

    // MARK: Agenda

    static func juntas() -> [Meeting] {
        let now = Date()
        let calendar = Calendar.current
        let manana = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        func hora(_ h: Int, _ m: Int) -> Date {
            calendar.date(bySettingHour: h, minute: m, second: 0, of: manana) ?? manana
        }
        let proveedor = redondear(now.addingTimeInterval(6 * 60))
        let revision = redondear(now.addingTimeInterval(2 * 3600))
        return [
            Meeting(id: "demo-1", title: "Llamada con proveedor", start: proveedor, end: proveedor.addingTimeInterval(30 * 60),
                    allDay: false, location: "", joinURL: URL(string: "https://zoom.us/j/1234567890"), service: "Zoom",
                    calendar: "Trabajo", color: Color(red: 0.2, green: 0.6, blue: 1.0)),
            Meeting(id: "demo-2", title: "Revisión semanal", start: revision, end: revision.addingTimeInterval(45 * 60),
                    allDay: false, location: "", joinURL: URL(string: "https://meet.google.com/abc-defg-hij"), service: "Meet",
                    calendar: "Trabajo", color: Color(red: 0.2, green: 0.6, blue: 1.0)),
            Meeting(id: "demo-3", title: "Planeación del mes", start: hora(10, 0), end: hora(11, 0),
                    allDay: false, location: "", joinURL: URL(string: "https://teams.microsoft.com/l/meetup-join/demo"),
                    service: "Teams", calendar: "Trabajo", color: Color(red: 0.55, green: 0.4, blue: 0.95))
        ]
    }

    /// Minutos "redondos" (de 5 en 5), como una junta de verdad.
    private static func redondear(_ date: Date) -> Date {
        let paso: TimeInterval = 5 * 60
        return Date(timeIntervalSinceReferenceDate: (date.timeIntervalSinceReferenceDate / paso).rounded(.up) * paso)
    }

    static func globoJunta() -> CompanionBubble {
        var globo = CompanionBubble(title: "“Llamada con proveedor” empieza en 5 min", message: "Es en Zoom.",
                                    duration: nil)
        globo.buttons = [
            BubbleButton(title: "Unirme", symbol: "video.fill", prominent: true, action: {}),
            BubbleButton(title: "Luego", action: {})
        ]
        return globo
    }

    // MARK: Portapapeles

    static func ranuras() -> [Int: ClipItem] {
        var result: [Int: ClipItem] = [
            1: ClipItem.demo(texto: "hola@ejemplo.com"),
            2: ClipItem.demo(texto: "Av. de los Árboles 123, Col. Centro"),
            4: ClipItem.demo(texto: "npm run dev"),
            5: ClipItem.demo(texto: "https://ejemplo.com/tienda"),
            6: ClipItem.demo(texto: "¡Gracias por tu compra! Hoy mismo sale tu pedido."),
            7: ClipItem.demo(texto: "#FF7A66")
        ]
        if let png = paleta(ancho: 160, alto: 100) {
            result[3] = ClipItem.demo(png: png)
        }
        return result
    }

    static func historial() -> [ClipItem] {
        var items = [
            ClipItem.demo(texto: "git commit -m \"Agrega cupones al carrito\"", hace: 20),
            ClipItem.demo(texto: "Nos vemos a las 5 en la cafetería de la esquina", hace: 240),
            ClipItem.demo(texto: "SELECT * FROM pedidos WHERE estado = 'pendiente';", hace: 900)
        ]
        if let png = capturaDiseño() {
            items.append(ClipItem.demo(png: png, hace: 1_800))
        }
        items += [
            ClipItem.demo(texto: "Lista del súper: leche, pan, café y fruta", hace: 3_600)
        ]
        return items
    }

    // MARK: Mac

    static func estadisticas() -> SystemMonitor.Snapshot {
        var snapshot = SystemMonitor.Snapshot()
        let gb: UInt64 = 1_073_741_824
        snapshot.cpu = 0.23
        snapshot.cores = 10
        snapshot.memory = MemoryInfo(used: 11 * gb + gb / 5, free: 2 * gb, total: 16 * gb)
        snapshot.pressure = .normal
        snapshot.swapUsed = 0
        snapshot.disk = DiskInfo(free: 98_000_000_000, total: 494_000_000_000)
        snapshot.chipTemperature = 48
        snapshot.battery = BatteryInfo(percent: 82, charging: false, onAC: false, cycles: nil, temperature: 31)
        snapshot.thermal = .nominal
        snapshot.uptime = 3 * 86_400 + 4 * 3_600 + 20 * 60
        return snapshot
    }

    static func apps() -> [AppMemory] {
        let mb: UInt64 = 1_048_576
        let lista: [(String, String, UInt64)] = [
            ("Safari", "/Applications/Safari.app", 2_150 * mb),
            ("Terminal", "/System/Applications/Utilities/Terminal.app", 1_240 * mb),
            ("Música", "/System/Applications/Music.app", 610 * mb),
            ("Notas", "/System/Applications/Notes.app", 380 * mb),
            ("Vista Previa", "/System/Applications/Preview.app", 210 * mb)
        ]
        return lista.enumerated().map { index, app in
            let icono = FileManager.default.fileExists(atPath: app.1) ? NSWorkspace.shared.icon(forFile: app.1) : nil
            return AppMemory(id: pid_t(1000 + index), name: app.0, bytes: app.2, icon: icono)
        }
    }

    static func limpieza() -> [CleanupKind: CleanupScan] {
        [
            .trash: CleanupScan(bytes: 1_200_000_000, items: []),
            .caches: CleanupScan(bytes: 3_400_000_000, items: []),
            .downloads: CleanupScan(bytes: 860_000_000, items: []),
            .screenshots: CleanupScan(bytes: 240_000_000, items: []),
            .developer: CleanupScan(bytes: 5_100_000_000, items: [])
        ]
    }

    // MARK: Claude Code

    static func sesiones() -> [ClaudeSession] {
        let now = Date()
        func paso(_ tool: String, _ input: [String: Any]) -> ClaudeStep {
            ClaudeCodeMonitor.describe(tool: tool, input: input)
        }
        return [
            ClaudeSession(id: "demo-tienda", project: "mi-tienda", status: .working,
                          steps: [paso("Read", ["file_path": "/proyectos/mi-tienda/src/carrito.ts"]),
                                  paso("Edit", ["file_path": "/proyectos/mi-tienda/src/carrito.ts"]),
                                  paso("Bash", ["command": "npm test"])],
                          prompt: "Agrega cupones de descuento al carrito",
                          terminalBundle: "com.apple.Terminal", updated: now),
            ClaudeSession(id: "demo-blog", project: "blog-personal", status: .thinking,
                          steps: [paso("Grep", ["pattern": "href=\"/menu"]),
                                  paso("Read", ["file_path": "/proyectos/blog-personal/menu.html"])],
                          prompt: "Revisa los enlaces rotos del menú",
                          terminalBundle: "com.apple.Terminal", updated: now.addingTimeInterval(-40))
        ]
    }

    static func uso() -> PlanUsage {
        let now = Date()
        return PlanUsage(session: PlanUsage.Window(percent: 42, resetsAt: now.addingTimeInterval(2 * 3600 + 15 * 60)),
                         week: PlanUsage.Window(percent: 67, resetsAt: now.addingTimeInterval(3 * 86_400)),
                         updated: now)
    }

    static func actividadEnVivo() -> LiveActivity {
        LiveActivity(statuses: [.working, .thinking], title: "2 sesiones", subtitle: "mi-tienda",
                     tint: Theme.accent)
    }

    static func permisoBash() -> ClaudeApproval {
        ClaudeApproval(id: "demo-permiso", sessionID: "demo-tienda", project: "mi-tienda",
                       step: ClaudeCodeMonitor.describe(tool: "Bash", input: ["command": "npm test"]),
                       suggestions: Data("[]".utf8))
    }

    static func pregunta() -> ClaudeApproval {
        let input: [String: Any] = [
            "questions": [[
                "question": "¿Qué base de datos uso?",
                "header": "Base de datos",
                "multiSelect": false,
                "options": [
                    ["label": "PostgreSQL", "description": "Robusta, ideal para producción"],
                    ["label": "SQLite", "description": "Un solo archivo, sin servidor"],
                    ["label": "MySQL", "description": "Muy común en hostings"]
                ]
            ]]
        ]
        return ClaudeApproval(id: "demo-pregunta", sessionID: "demo-tienda", project: "mi-tienda",
                              step: ClaudeCodeMonitor.describe(tool: "AskUserQuestion", input: input),
                              suggestions: nil, questions: ClaudeQuestion.parse(input))
    }

    static func vistaPrevia() -> ClaudeApproval {
        let input: [String: Any] = [
            "file_path": "/proyectos/mi-tienda/src/carrito.ts",
            "old_string": "  const subtotal = sumar(carrito.productos)\n  return subtotal\n}",
            "new_string": "  const subtotal = sumar(carrito.productos)\n  const descuento = cupon ? subtotal * cupon.porcentaje : 0\n  return subtotal - descuento\n}"
        ]
        return ClaudeApproval(id: "demo-cambios", sessionID: "demo-tienda", project: "mi-tienda",
                              step: ClaudeCodeMonitor.describe(tool: "Edit", input: input),
                              suggestions: Data("[]".utf8),
                              diff: ClaudeDiff.make(tool: "Edit", input: input))
    }

    // MARK: Archivos del estante

    static func crearArchivos(en carpeta: URL) -> [ShelfItem] {
        let ahora = Date()
        var items: [ShelfItem] = []
        func agregar(_ nombre: String, _ datos: Data?, _ origen: ShelfItem.Source, hace minutos: Double) {
            guard let datos = datos else { return }
            let url = carpeta.appendingPathComponent(nombre)
            guard (try? datos.write(to: url)) != nil else { return }
            items.append(ShelfItem(url: url, source: origen, date: ahora.addingTimeInterval(-minutos * 60)))
        }
        agregar("captura-diseño.png", capturaDiseño(), .screenshot, hace: 1)
        agregar("cotizacion.pdf", cotizacionPDF(), .download, hace: 12)
        agregar("fotos-producto.zip", zipVacio(), .download, hace: 30)
        agregar("paleta-colores.png", paleta(ancho: 480, alto: 300), .dropped, hace: 55)
        agregar("notas-reunion.txt", Data(notas.utf8), .dropped, hace: 90)
        return items
    }

    private static let notas = """
    Notas de la reunión

    • Lanzar la nueva página el lunes
    • Revisar precios de envío
    • Mandar fotos del producto al diseñador
    • Siguiente revisión: jueves 10:00
    """

    /// Una "captura de pantalla" de una app inventada.
    private static func capturaDiseño() -> Data? {
        dibujarPNG(ancho: 640, alto: 400) { rect in
            NSColor(red: 0.96, green: 0.96, blue: 0.98, alpha: 1).setFill()
            rect.fill()
            // Barra de arriba.
            NSColor(red: 0.36, green: 0.30, blue: 0.85, alpha: 1).setFill()
            NSRect(x: 0, y: 352, width: 640, height: 48).fill()
            NSColor.white.withAlphaComponent(0.9).setFill()
            NSBezierPath(roundedRect: NSRect(x: 20, y: 366, width: 120, height: 20), xRadius: 6, yRadius: 6).fill()
            // Menú lateral.
            NSColor(red: 0.90, green: 0.90, blue: 0.95, alpha: 1).setFill()
            NSRect(x: 0, y: 0, width: 150, height: 352).fill()
            NSColor(red: 0.75, green: 0.75, blue: 0.85, alpha: 1).setFill()
            for index in 0..<6 {
                NSBezierPath(roundedRect: NSRect(x: 18, y: 310 - CGFloat(index) * 36, width: 110, height: 14),
                             xRadius: 5, yRadius: 5).fill()
            }
            // Tarjetas.
            let colores = [NSColor(red: 1.0, green: 0.48, blue: 0.40, alpha: 1),
                           NSColor(red: 0.25, green: 0.70, blue: 0.95, alpha: 1),
                           NSColor(red: 0.30, green: 0.80, blue: 0.55, alpha: 1)]
            for (index, color) in colores.enumerated() {
                let x = 172 + CGFloat(index) * 152
                NSColor.white.setFill()
                NSBezierPath(roundedRect: NSRect(x: x, y: 190, width: 138, height: 140), xRadius: 12, yRadius: 12).fill()
                color.setFill()
                NSBezierPath(roundedRect: NSRect(x: x + 12, y: 250, width: 114, height: 66), xRadius: 8, yRadius: 8).fill()
                NSColor(red: 0.8, green: 0.8, blue: 0.86, alpha: 1).setFill()
                NSBezierPath(roundedRect: NSRect(x: x + 12, y: 226, width: 90, height: 10), xRadius: 4, yRadius: 4).fill()
                NSBezierPath(roundedRect: NSRect(x: x + 12, y: 206, width: 60, height: 10), xRadius: 4, yRadius: 4).fill()
            }
            // Gráfica.
            NSColor.white.setFill()
            NSBezierPath(roundedRect: NSRect(x: 172, y: 24, width: 442, height: 148), xRadius: 12, yRadius: 12).fill()
            NSColor(red: 0.36, green: 0.30, blue: 0.85, alpha: 1).setFill()
            let barras: [CGFloat] = [40, 70, 55, 95, 80, 110, 90, 120]
            for (index, altura) in barras.enumerated() {
                NSBezierPath(roundedRect: NSRect(x: 196 + CGFloat(index) * 50, y: 40, width: 28, height: altura),
                             xRadius: 5, yRadius: 5).fill()
            }
        }
    }

    /// Cinco franjas de color.
    private static func paleta(ancho: CGFloat, alto: CGFloat) -> Data? {
        dibujarPNG(ancho: ancho, alto: alto) { rect in
            let colores = [NSColor(red: 0.13, green: 0.16, blue: 0.40, alpha: 1),
                           NSColor(red: 0.38, green: 0.25, blue: 0.60, alpha: 1),
                           NSColor(red: 0.90, green: 0.50, blue: 0.45, alpha: 1),
                           NSColor(red: 1.0, green: 0.78, blue: 0.45, alpha: 1),
                           NSColor(red: 0.35, green: 0.75, blue: 0.95, alpha: 1)]
            let franja = rect.width / CGFloat(colores.count)
            for (index, color) in colores.enumerated() {
                color.setFill()
                NSRect(x: CGFloat(index) * franja, y: 0, width: franja + 1, height: rect.height).fill()
            }
        }
    }

    /// Una cotización de una hoja (PDF).
    private static func cotizacionPDF() -> Data? {
        let datos = NSMutableData()
        var caja = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let consumer = CGDataConsumer(data: datos as CFMutableData),
              let contexto = CGContext(consumer: consumer, mediaBox: &caja, nil) else { return nil }
        contexto.beginPDFPage(nil)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: contexto, flipped: false)
        NSColor(red: 0.36, green: 0.30, blue: 0.85, alpha: 1).setFill()
        NSRect(x: 0, y: 700, width: 612, height: 92).fill()
        func texto(_ valor: String, _ x: CGFloat, _ y: CGFloat, _ tamaño: CGFloat, _ color: NSColor = .black,
                   negritas: Bool = false) {
            let fuente = negritas ? NSFont.boldSystemFont(ofSize: tamaño) : NSFont.systemFont(ofSize: tamaño)
            (valor as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: [.font: fuente, .foregroundColor: color])
        }
        texto("Cotización", 48, 732, 34, .white, negritas: true)
        texto("Estudio Ejemplo · Folio 0231", 48, 660, 14, .darkGray)
        let renglones = [("Diseño de página de inicio", "$8,500"), ("Sesión de fotos de producto", "$4,200"),
                         ("Tienda en línea (configuración)", "$6,800"), ("Soporte por 3 meses", "$2,500")]
        for (index, renglon) in renglones.enumerated() {
            let y = 600 - CGFloat(index) * 44
            NSColor(white: 0.93, alpha: 1).setFill()
            NSRect(x: 48, y: y - 12, width: 516, height: 36).fill()
            texto(renglon.0, 60, y, 16)
            texto(renglon.1, 470, y, 16, negritas: true)
        }
        texto("Total", 60, 400, 22, negritas: true)
        texto("$22,000", 440, 400, 22, NSColor(red: 0.36, green: 0.30, blue: 0.85, alpha: 1), negritas: true)
        NSGraphicsContext.restoreGraphicsState()
        contexto.endPDFPage()
        contexto.closePDF()
        return datos as Data
    }

    /// Un .zip válido y vacío (solo para que Quick Look le ponga su ícono).
    private static func zipVacio() -> Data {
        Data([0x50, 0x4B, 0x05, 0x06] + [UInt8](repeating: 0, count: 18))
    }

    /// Dibuja con AppKit y regresa un PNG (a 1x: son "archivos", no interfaz).
    static func dibujarPNG(ancho: CGFloat, alto: CGFloat, _ dibujo: (NSRect) -> Void) -> Data? {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(ancho), pixelsHigh: Int(alto),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let contexto = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = contexto
        dibujo(NSRect(x: 0, y: 0, width: ancho, height: alto))
        contexto.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }
}
