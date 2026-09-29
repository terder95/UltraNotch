import SwiftUI
import AppKit
import ServiceManagement

/// Nombres de los ajustes guardados (UserDefaults).
enum SettingsKeys {
    static let hoverDelay = "hoverDelay"
    static let approvalTimeout = "claudeApprovalTimeout"
    static let pasteWindow = "pasteWindow"
    static let downloadsDays = "cleanupDownloadsDays"
    static let screenshotsDays = "cleanupScreenshotsDays"
    static let chatTarget = "claudeChatTarget"
    static let chatAutoSend = "claudeChatAutoSend"
    static let replyWait = "claudeReplyWait"
    static let replyOnlyAway = "claudeReplyOnlyAway"
    static let minTaskSeconds = "claudeMinTaskSeconds"
}

/// Ventana de Configuración (se abre desde el menú o el engrane de la isla).
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?

    func show<Content: View>(_ makeContent: () -> Content) {
        if window == nil {
            let controller = NSHostingController(rootView: makeContent())
            let newWindow = NSWindow(contentViewController: controller)
            newWindow.title = "Configuración de Isla"
            newWindow.styleMask = [.titled, .closable, .miniaturizable]
            newWindow.isReleasedWhenClosed = false
            newWindow.setContentSize(NSSize(width: 620, height: 740))
            newWindow.center()
            window = newWindow
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @ObservedObject var notch: NotchController
    @ObservedObject var shelf: ShelfStore
    @ObservedObject var claude: ClaudeCodeMonitor
    @ObservedObject var voice: VoiceWake
    @ObservedObject var companion: CompanionController
    @ObservedObject var keepAwake: KeepAwake
    @ObservedObject var music: NowPlaying
    @ObservedObject var lyrics: LyricsStore
    @ObservedObject var agenda: CalendarStore
    @ObservedObject var dictionary = PersonalDictionary.shared
    @ObservedObject var projects = ProjectStore.shared
    @ObservedObject var log = IslaLog.shared
    /// "Que salga a pasear ahora".
    var onRoamNow: () -> Void = {}

    @AppStorage(SettingsKeys.hoverDelay) private var hoverDelay = 0.1
    @AppStorage(SettingsKeys.approvalTimeout) private var approvalTimeout = 30.0
    @AppStorage(SettingsKeys.pasteWindow) private var pasteWindow = 0.9
    @AppStorage(SettingsKeys.downloadsDays) private var downloadsDays = 30
    @AppStorage(SettingsKeys.screenshotsDays) private var screenshotsDays = 14
    @AppStorage(SettingsKeys.chatTarget) private var chatTarget = ClaudeChatTarget.desktop.rawValue
    @AppStorage(SettingsKeys.chatAutoSend) private var chatAutoSend = true
    @AppStorage(SettingsKeys.replyWait) private var replyWait = 20.0
    @AppStorage(SettingsKeys.replyOnlyAway) private var replyOnlyAway = true
    @AppStorage(SettingsKeys.minTaskSeconds) private var minTaskSeconds = 10.0
    @AppStorage(ClaudeSessionFilter.ignoreAutomaticKey) private var ignoreAutomatic = true
    @AppStorage(ClaudeSessionFilter.ignoredFoldersKey) private var ignoredFolders = ClaudeSessionFilter.defaultIgnoredFolders
    @AppStorage(HoldToTalkKey.enabledKey) private var holdToTalk = true
    @AppStorage(TerminalJump.enabledKey) private var exactTab = false

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var testResult: String?
    @State private var terminalTest: String?
    @State private var cleanupTest: String?

    var body: some View {
        TabView {
            Form {
                voiceSection
                dictionarySection
                claudeVoiceSection
                projectsSection
            }
            .formStyle(.grouped)
            .tabItem { Label("Voz", systemImage: "waveform") }

            Form {
                claudeSection
                soundsSection
                replySection
            }
            .formStyle(.grouped)
            .tabItem { Label("Claude", systemImage: "sparkle") }

            Form {
                musicSection
                agendaSection
            }
            .formStyle(.grouped)
            .tabItem { Label("Hoy", systemImage: "calendar") }

            Form {
                companionSection
            }
            .formStyle(.grouped)
            .tabItem { Label("Compañero", systemImage: "face.smiling") }

            Form {
                islandSection
                shelfSection
                clipboardSection
            }
            .formStyle(.grouped)
            .tabItem { Label("Isla", systemImage: "rectangle.topthird.inset.filled") }

            Form {
                logSection
            }
            .formStyle(.grouped)
            .tabItem { Label("Registro", systemImage: "list.bullet.rectangle") }
        }
        .padding(.top, 6)
        .frame(width: 620, height: 740)
    }

    // MARK: Diccionario y limpieza

    private var dictionarySection: some View {
        Section {
            TextField("Palabras que debe conocer", text: $dictionary.words, prompt: Text("México Makers, Gorgias, Shopify"))
            ForEach(dictionary.rules) { rule in
                DictionaryRuleRow(rule: rule, onChange: { dictionary.update($0) }, onDelete: { dictionary.remove(rule) })
            }
            Button {
                dictionary.addRule()
            } label: {
                Label("Agregar corrección", systemImage: "plus")
            }
            Toggle("Limpiar el dictado (muletillas, repeticiones, mayúsculas y puntos)", isOn: $dictionary.cleanupEnabled)
            Toggle("Pulir con Apple Intelligence (en tu Mac, gratis)", isOn: $dictionary.smartEnabled)
                .disabled(!dictionary.cleanupEnabled)
            LabeledContent("Apple Intelligence") {
                Text(AppleIntelligence.statusText)
                    .foregroundColor(AppleIntelligence.isAvailable ? Theme.success : .secondary)
            }
            LabeledContent("Probar") {
                HStack(spacing: 8) {
                    if let cleanupTest = cleanupTest {
                        Text(cleanupTest)
                            .foregroundColor(.secondary)
                            .lineLimit(3)
                            .multilineTextAlignment(.trailing)
                            .textSelection(.enabled)
                    }
                    Button("Probar la limpieza…") {
                        guard let text = TextPrompt.ask(
                            title: "Probar la limpieza",
                            message: "Escribe algo como lo dirías, por ejemplo: “este, eh, quiero que revises el el archivo de cloud code”.",
                            placeholder: "Tu texto",
                            button: "Limpiar",
                            deactivateAfter: false
                        ) else { return }
                        cleanupTest = "Limpiando…"
                        Task { @MainActor in
                            cleanupTest = await DictationPolisher.polish(text)
                        }
                    }
                }
            }
        } header: {
            Text("Diccionario y limpieza del dictado")
        } footer: {
            Text("Palabras: separadas por comas (nombres de clientes, marcas, términos); el reconocimiento de voz las entiende mejor. Correcciones: si oye “cloud code”, escribe “Claude Code” (pon varias formas separadas por comas). La limpieza quita “eh”, “mmm”, “este…” y palabras repetidas, y pone mayúsculas, ¿? y punto final. Con Apple Intelligence queda mejor; si tarda más de 4 segundos o no está activado, se usa la limpieza normal. Todo pasa en tu Mac y no cuesta nada.")
        }
    }

    // MARK: Sonidos

    private var soundsSection: some View {
        Section {
            Toggle("Sonidos", isOn: $claude.soundsEnabled)
            ForEach(SoundEvent.allCases) { event in
                SoundEventRow(event: event)
            }
            .disabled(!claude.soundsEnabled)
        } header: {
            Text("Sonidos")
        } footer: {
            Text("Un sonido distinto para cada cosa, así sabes qué pasó sin voltear a ver.")
        }
    }

    // MARK: Hoy (música y agenda)

    private var musicSection: some View {
        Section {
            Toggle("Mostrar lo que suena (Spotify y Música)", isOn: $music.enabled)
            Toggle("Avisarme junto al notch cuando cambia la canción", isOn: $music.announce)
                .disabled(!music.enabled)
            Toggle("Con la isla cerrada: el monito se pone audífonos y salen barritas", isOn: $music.showInIsland)
                .disabled(!music.enabled)
            Toggle("Mostrar la letra de la canción (LRCLIB)", isOn: $lyrics.enabled)
                .disabled(!music.enabled)
            LabeledContent("Sonando") {
                Text(music.track.map { "\($0.title) · \($0.artist)" } ?? "Nada")
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        } header: {
            Text("Música")
        } footer: {
            Text("Isla escucha los avisos que Spotify y Música mandan al cambiar de canción, así que no gasta batería. La carátula sale de Spotify o de Música (si no, del catálogo de Apple). La letra viene de LRCLIB, un catálogo gratis y abierto: Isla solo le manda el título, el artista, el álbum y la duración; no todas las canciones tienen letra. Mientras ves la pestaña Hoy, Isla le pregunta a la app en qué segundo va la canción; la primera vez macOS te pide permiso para que Isla controle Spotify o Música. Sin compañero, la isla cerrada enseña la carátula y las barritas.")
        }
    }

    private var agendaSection: some View {
        Section {
            Toggle("Calendario de la Mac", isOn: $agenda.useMacCalendar)
            if agenda.useMacCalendar {
                LabeledContent("Permiso") {
                    HStack(spacing: 8) {
                        Text(agendaAccessText)
                            .foregroundColor(agenda.access == .granted ? Theme.success : .secondary)
                        if agenda.access == .denied {
                            Button("Abrir Ajustes") { agenda.openPrivacySettings() }
                        } else if agenda.access == .unknown {
                            Button("Dar permiso") { agenda.requestAccess() }
                        }
                    }
                }
            }
            LabeledContent("Gmail, Outlook o Teams") {
                Button("Agregar cuenta a la Mac…") { agenda.openInternetAccounts() }
            }
            ForEach(agenda.links) { link in
                CalendarLinkRow(link: link, status: agenda.linkStatus[link.id],
                                onChange: { agenda.update($0) }, onDelete: { agenda.remove(link) })
            }
            Button {
                agenda.addLink()
            } label: {
                Label("Agregar link de calendario (.ics)", systemImage: "link.badge.plus")
            }
            Picker("Avisarme antes de una junta", selection: $agenda.remindMinutes) {
                Text("No avisar").tag(0.0)
                Text("1 min antes").tag(1.0)
                Text("5 min antes").tag(5.0)
                Text("10 min antes").tag(10.0)
                Text("15 min antes").tag(15.0)
            }
            Button("Actualizar ahora") { agenda.refresh(forceLinks: true) }
        } header: {
            Text("Agenda")
        } footer: {
            Text("Lo más fácil: toca “Agregar cuenta a la Mac…”, agrega tu cuenta de Google (Gmail) o de Microsoft (Outlook / Teams) con Calendarios activado y enciende “Calendario de la Mac”. Si tu empresa no lo permite, usa un link: en Google Calendar › Configuración › tu calendario › “Dirección secreta en formato iCal”; en Outlook › Configuración › Calendario › Calendarios compartidos › Publicar un calendario › link ICS. Los links son privados: no los compartas. Si la junta trae link de Teams, Meet o Zoom, aparece el botón “Unirme”.")
        }
    }

    private var agendaAccessText: String {
        switch agenda.access {
        case .granted: return "Concedido ✓"
        case .denied: return "Sin permiso"
        case .unknown: return "Falta dar permiso"
        }
    }

    // MARK: Voz

    private var voiceSection: some View {
        Section {
            Toggle("Usar la voz (“\(voice.displayPhrase)” y la tecla ⌥)", isOn: $voice.enabled)
            Toggle("Escuchar siempre “\(voice.displayPhrase)” (micrófono prendido)", isOn: $voice.alwaysListen)
                .disabled(!voice.enabled)
            Toggle("Mantener ⌥ derecha para hablar (sin decir la frase)", isOn: $holdToTalk)
                .disabled(!voice.enabled)

            TextField("Frase para despertar", text: $voice.wakePhrases, prompt: Text(VoiceWake.defaultPhrases))
            Text("Puedes poner varias separadas por comas, por ejemplo: oye claudio, hey claudio")
                .font(.caption)
                .foregroundColor(.secondary)

            Picker("Idioma del reconocimiento", selection: $voice.localeID) {
                Text("Español (México)").tag("es-MX")
                Text("Español (Estados Unidos)").tag("es-US")
                Text("Español (España)").tag("es-ES")
                Text("English (US)").tag("en-US")
            }

            LabeledContent("Tiempo para decir la orden") {
                HStack {
                    Slider(value: $voice.commandWindow, in: 3...30, step: 1)
                    Text("\(Int(voice.commandWindow)) s")
                        .monospacedDigit()
                        .frame(width: 40, alignment: .trailing)
                }
            }

            LabeledContent("Silencio que termina un dictado") {
                HStack {
                    Slider(value: $voice.silenceSeconds, in: 1...6, step: 0.5)
                    Text(String(format: "%.1f s", voice.silenceSeconds))
                        .monospacedDigit()
                        .frame(width: 40, alignment: .trailing)
                }
            }

            LabeledContent("Estado") {
                HStack(spacing: 8) {
                    Text(voiceStateText)
                        .foregroundColor(.secondary)
                    if voice.state == .needsPermission {
                        Button("Dar permiso") { voice.openPrivacySettings() }
                    }
                }
            }

            LabeledContent("Última frase escuchada") {
                Text(voice.lastHeard.isEmpty ? "—" : voice.lastHeard)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
            }
        } header: {
            Text("Voz")
        } footer: {
            Text("Después de la frase puedes decir: “nuevo chat …”, el nombre de un proyecto, “cowork …”, “Claude Code …”, “ChatGPT …”, “terminal …” (lo que dictes se escribe en la terminal), “responde …”, “permitir”, “siempre”, “negar”, “estante”, “portapapeles”, “Mac”, “agenda”, “pausa”, “siguiente canción” o “cierra”. Con la tecla ⌥ derecha: mantenla, di lo mismo (sin la frase) y suéltala para mandarlo; si no dices a dónde, va a un chat nuevo de Claude. Si apagas “Escuchar siempre”, el micrófono se queda apagado y solo escucha mientras mantienes ⌥ (o tocas Responder). Todo se reconoce en tu Mac.")
        }
    }

    private var usageSummary: String {
        guard let usage = claude.usage else {
            return "Aparecen cuando uses Claude Code (en una sesión nueva)"
        }
        return usage.tooltip
    }

    private var voiceStateText: String {
        switch voice.state {
        case .off: return "Apagado"
        case .listening: return "Escuchando"
        case .standby: return "Micrófono apagado (solo con ⌥)"
        case .needsPermission: return "Falta permiso"
        case .unavailable(let reason): return reason
        }
    }

    // MARK: Claude por voz

    private var claudeVoiceSection: some View {
        Section {
            Picker("Abrir en", selection: $chatTarget) {
                ForEach(ClaudeChatTarget.allCases) { target in
                    Text(target.label).tag(target.rawValue)
                }
            }
            Toggle("Enviar solo al terminar de dictar", isOn: $chatAutoSend)
            LabeledContent("Probar") {
                HStack(spacing: 8) {
                    if let testResult = testResult {
                        Text(testResult)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    Button("Abrir chat de prueba") {
                        testResult = "Abriendo…"
                        ClaudeChat.test { message, _ in
                            testResult = message
                        }
                    }
                }
            }
        } header: {
            Text("Claude por voz")
        } footer: {
            Text("Di “\(voice.displayPhrase), nuevo chat” (o “cowork”, “Claude Code” o el nombre de un proyecto) y luego tu mensaje. Al quedarte callado, o al decir “enviar”, Isla lo abre en Claude con tu plan, sin costo extra. Di “cancela” al final para no mandarlo. “Abrir chat de prueba” escribe un mensaje sin enviarlo.")
        }
    }

    // MARK: Proyectos

    private var projectsSection: some View {
        Section {
            if projects.projects.isEmpty {
                Text("Aún no tienes proyectos. Agrega uno para mandarle mensajes por voz.")
                    .foregroundColor(.secondary)
            }
            ForEach(projects.projects) { project in
                ProjectRow(
                    project: project,
                    onChange: { updated in
                        projects.update(updated)
                    },
                    onTest: { current in
                        guard let id = current.projectID else { return }
                        testResult = "Abriendo \(current.name)…"
                        ClaudeChat.send(.project(id: id, name: current.name), text: nil, sendNow: false) { message, _ in
                            testResult = message
                        }
                    },
                    onDelete: {
                        projects.remove(project)
                    }
                )
            }
            Button {
                projects.add()
            } label: {
                Label("Agregar proyecto", systemImage: "plus")
            }
        } header: {
            Text("Proyectos de Claude")
        } footer: {
            Text("Abre el proyecto en claude.ai (en el navegador) y copia el link de arriba; se ve así: https://claude.ai/project/… Luego di “\(voice.displayPhrase), a Gorgias: …” (con el nombre que le pongas). Isla abre el proyecto, pega lo que dictaste y lo envía.")
        }
    }

    // MARK: Responder a Claude Code

    private var replySection: some View {
        Section {
            Toggle("Responder por voz cuando Claude Code termina", isOn: $claude.replyEnabled)
            LabeledContent("Tiempo para responder") {
                HStack {
                    Slider(value: $replyWait, in: 5...90, step: 5)
                    Text("\(Int(replyWait)) s")
                        .monospacedDigit()
                        .frame(width: 40, alignment: .trailing)
                }
            }
            .disabled(!claude.replyEnabled)
            Toggle("Solo si no estás viendo la terminal", isOn: $replyOnlyAway)
                .disabled(!claude.replyEnabled)
        } header: {
            Text("Responder a Claude Code por voz")
        } footer: {
            Text("Cuando una sesión termina, el compañero te avisa y Claude Code espera unos segundos. Di “responde…” (no hace falta “\(voice.displayPhrase)”) y tu mensaje: le llega a esa misma sesión y Claude sigue trabajando. Mientras espera, la terminal tarda esos segundos en regresarte el control; si abres la terminal, se lo regresa al instante. Aplica a sesiones nuevas de Claude Code.")
        }
    }

    static func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    static func confirm(_ title: String, _ message: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "Cambiar")
        alert.addButton(withTitle: "Cancelar")
        return alert.runModal() == .alertFirstButtonReturn
    }

    // MARK: Claude Code

    private var claudeSection: some View {
        Section {
            LabeledContent("Conexión") {
                HStack(spacing: 8) {
                    Text(claude.hooksInstalled ? "Conectado" : "Sin conectar")
                        .foregroundColor(claude.hooksInstalled ? Theme.success : .secondary)
                    if claude.hooksInstalled {
                        Button("Desconectar") { claude.disconnect() }
                    } else {
                        Button("Conectar…") { claude.connect() }
                    }
                }
            }
            Toggle("Aprobar permisos desde la isla", isOn: $claude.approvalsEnabled)
            Toggle("Contestar las preguntas de Claude desde la isla", isOn: $claude.questionsEnabled)
            Toggle("Ver qué cambia en el archivo antes de aprobar", isOn: $claude.diffPreview)
                .disabled(!claude.approvalsEnabled)
            Toggle("Ir a la pestaña exacta de cada sesión (Terminal e iTerm2)", isOn: $exactTab)
            LabeledContent("Probar la terminal") {
                HStack(spacing: 8) {
                    if let terminalTest = terminalTest {
                        Text(terminalTest)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                    Button("Buscar mi Claude Code") {
                        terminalTest = "Buscando…"
                        Task { @MainActor in
                            switch await TerminalFinder.focusClaudeTab() {
                            case .found: terminalTest = "Lo encontré ✓"
                            case .notFound: terminalTest = "No hay Claude Code abierto en Terminal"
                            case .noPermission: terminalTest = "Falta permiso: Ajustes › Privacidad › Automatización › Isla › Terminal"
                            }
                        }
                    }
                }
            }
            LabeledContent("Tiempo para responder un permiso") {
                HStack {
                    Slider(value: $approvalTimeout, in: 10...240, step: 5)
                    Text("\(Int(approvalTimeout)) s")
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                }
            }
            .disabled(!claude.approvalsEnabled)
            Toggle("Actividad en vivo junto al notch", isOn: $claude.liveEnabled)
            Toggle("Ver mis límites de uso en la isla (5 h y semana)", isOn: $claude.usageEnabled)
            if claude.usageEnabled {
                LabeledContent("Límites") {
                    Text(usageSummary)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }
            LabeledContent("Avisar si la tarea tardó al menos") {
                HStack {
                    Slider(value: $minTaskSeconds, in: 0...120, step: 5)
                    Text(minTaskSeconds < 1 ? "siempre" : "\(Int(minTaskSeconds)) s")
                        .monospacedDigit()
                        .frame(width: 52, alignment: .trailing)
                }
            }
            Toggle("Ignorar sesiones automáticas (Agent SDK y plugins)", isOn: $ignoreAutomatic)
            TextField("Carpetas a ignorar", text: $ignoredFolders, prompt: Text("observer-sessions, otra-carpeta"))
        } header: {
            Text("Claude Code")
        } footer: {
            Text("Cuando Claude te pregunta algo (con opciones), eliges en la isla; “Escribir…” te deja contestar con tus palabras y el botón de terminal la manda a la terminal. La vista previa enseña los renglones que se quitan (rojo) y se agregan (verde). “Pestaña exacta” lleva a la pestaña de cada sesión en Terminal e iTerm2 (en Ghostty y Warp trae la app al frente); aplica a sesiones nuevas. Isla ve las sesiones de Claude Code que corren en tu Mac (terminal, VS Code). Las sesiones automáticas (por ejemplo, las “observer-sessions” de plugins de memoria) y las carpetas que pongas arriba, separadas por comas, no aparecen ni te avisan. Solo te avisa cuando termina una tarea que tardó al menos ese tiempo. Si no respondes un permiso a tiempo, Claude Code te pregunta en la terminal como siempre. Los límites de uso los manda Claude Code a su “línea de estado”: Isla se pone ahí, te sigue mostrando la línea que ya tenías (o una cortita con tus límites) y te la regresa si apagas esta opción.")
        }
    }

    // MARK: Compañero

    private var companionSection: some View {
        Section {
            Toggle("Mostrar al compañero junto al notch", isOn: $companion.enabled)
            Toggle("Globitos de texto", isOn: $companion.bubblesEnabled)
                .disabled(!companion.enabled)
            Picker("Platica por su cuenta", selection: $companion.chatterMinutes) {
                Text("Nunca").tag(0.0)
                Text("Cada 5 min").tag(5.0)
                Text("Cada 10 min").tag(10.0)
                Text("Cada 15 min").tag(15.0)
                Text("Cada 30 min").tag(30.0)
                Text("Cada hora").tag(60.0)
            }
            .disabled(!companion.enabled || !companion.bubblesEnabled)
            LabeledContent("Color") {
                MascotColorPicker(companion: companion, initial: companion.color)
            }
            .disabled(!companion.enabled)
            Toggle("Me sigue con la mirada", isOn: $companion.followMouse)
                .disabled(!companion.enabled)
            Toggle("Me presenta las ventanas que abro por voz", isOn: $companion.presentWindows)
                .disabled(!companion.enabled)
            Toggle("Reacciona a mi Mac (calor, batería baja, música, cargador)", isOn: $companion.reactionsEnabled)
                .disabled(!companion.enabled)
            Picker("Sale a pasear por la pantalla", selection: $companion.roamMinutes) {
                Text("Nunca").tag(0.0)
                Text("Cada 10 min").tag(10.0)
                Text("Cada 20 min").tag(20.0)
                Text("Cada 45 min").tag(45.0)
                Text("Cada hora").tag(60.0)
            }
            .disabled(!companion.enabled)
            Picker("Se duerme si no usas la Mac", selection: $companion.sleepMinutes) {
                Text("Nunca (solo de noche)").tag(0.0)
                Text("Después de 1 min").tag(1.0)
                Text("Después de 3 min").tag(3.0)
                Text("Después de 5 min").tag(5.0)
                Text("Después de 10 min").tag(10.0)
            }
            .disabled(!companion.enabled)
            Button("Que salga a pasear ahora") {
                onRoamNow()
            }
            .disabled(!companion.enabled)
            Button("Que me salude") {
                companion.greet()
            }
            .disabled(!companion.enabled || !companion.bubblesEnabled)
        } header: {
            Text("Compañero")
        } footer: {
            Text("Un personajito que vive junto al notch: se asoma, camina de un lado al otro, se cuelga de un hilo, baila, toma café, lee, trabaja con su caja de herramientas cuando Claude trabaja y se duerme si no usas la Mac. Si activas las reacciones: suda y se abanica cuando la Mac va a tope, tiembla con la batería baja, mueve la cabeza con tu música y se pone feliz al conectar el cargador. De paseo cae arriba del Dock y regresa con un globo; tócalo para que brinque, o dos veces para que regrese. También te avisa cosas en globitos.")
        }
    }

    // MARK: Isla

    private var islandSection: some View {
        Section("Isla") {
            LabeledContent("Modo programación") {
                HStack(spacing: 8) {
                    Text(keepAwake.isOn ? "Activo: la Mac no se duerme" : "Apagado")
                        .foregroundColor(keepAwake.isOn ? Theme.accent : .secondary)
                    Button(keepAwake.isOn ? "Apagar" : "Activar") {
                        keepAwake.toggle()
                    }
                }
            }
            Picker("Estilo", selection: $notch.style) {
                Text("Cristal líquido").tag(IslandStyle.glass)
                Text("Negro clásico").tag(IslandStyle.black)
            }
            LabeledContent("Espera al pasar el mouse") {
                HStack {
                    Slider(value: $hoverDelay, in: 0...0.8, step: 0.05)
                    Text("\(Int(hoverDelay * 1000)) ms")
                        .monospacedDigit()
                        .frame(width: 56, alignment: .trailing)
                }
            }
            Toggle("Abrir al iniciar sesión", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { enabled in
                    updateLaunchAtLogin(enabled)
                }
        }
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    // MARK: Estante y limpieza

    private var shelfSection: some View {
        Section("Estante y limpieza") {
            Toggle("Capturas de pantalla → isla", isOn: $shelf.watchScreenshots)
            Toggle("Descargas → isla", isOn: $shelf.watchDownloads)
            Stepper("Descargas viejas: más de \(downloadsDays) días", value: $downloadsDays, in: 7...365)
            Stepper("Capturas viejas: más de \(screenshotsDays) días", value: $screenshotsDays, in: 3...180)
        }
    }

    // MARK: Portapapeles

    private var clipboardSection: some View {
        Section {
            LabeledContent("Espera de ⌘V + número") {
                HStack {
                    Slider(value: $pasteWindow, in: 0.4...2.0, step: 0.1)
                    Text(String(format: "%.1f s", pasteWindow))
                        .monospacedDigit()
                        .frame(width: 40, alignment: .trailing)
                }
            }
        } header: {
            Text("Portapapeles")
        } footer: {
            Text("Cuánto espera Isla después de ⌘V por si presionas un número. Más tiempo = más fácil de usar; menos tiempo = el pegado normal se siente más rápido.")
        }
    }

    // MARK: Registro

    private var logSection: some View {
        Section {
            if log.entries.isEmpty {
                Text("Aún no hay nada. Aquí verás, paso a paso, lo que hace Isla con tu voz y con Claude.")
                    .foregroundColor(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(log.entries.reversed()) { entry in
                            HStack(alignment: .top, spacing: 8) {
                                Text(log.time(of: entry))
                                    .font(.system(size: 10.5, design: .monospaced))
                                    .foregroundColor(.secondary)
                                Text(entry.text)
                                    .font(.system(size: 11))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                }
                .frame(height: 170)
            }
            HStack {
                Button("Copiar registro") { log.copyToClipboard() }
                    .disabled(log.entries.isEmpty)
                Button("Borrar") { log.clear() }
                    .disabled(log.entries.isEmpty)
            }
        } header: {
            Text("Registro")
        } footer: {
            Text("Si algo no funciona, copia el registro y pégaselo a Claude en el chat.")
        }
    }
}

/// Un renglón de la lista de proyectos (edita una copia y la guarda al escribir).
struct ProjectRow: View {
    let project: ClaudeProject
    let onChange: (ClaudeProject) -> Void
    let onTest: (ClaudeProject) -> Void
    let onDelete: () -> Void

    @State private var name: String
    @State private var spoken: String
    @State private var link: String

    init(project: ClaudeProject,
         onChange: @escaping (ClaudeProject) -> Void,
         onTest: @escaping (ClaudeProject) -> Void,
         onDelete: @escaping () -> Void) {
        self.project = project
        self.onChange = onChange
        self.onTest = onTest
        self.onDelete = onDelete
        _name = State(initialValue: project.name)
        _spoken = State(initialValue: project.spoken)
        _link = State(initialValue: project.link)
    }

    private var current: ClaudeProject {
        var updated = project
        updated.name = name
        updated.spoken = spoken
        updated.link = link
        return updated
    }

    private var valid: Bool {
        current.projectID != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TextField("Nombre", text: $name, prompt: Text("Gorgias"))
                Button {
                    onTest(current)
                } label: {
                    Image(systemName: "arrow.up.forward.app")
                }
                .buttonStyle(.borderless)
                .disabled(!valid)
                .help("Abrir este proyecto (sin enviar nada)")
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundColor(Theme.danger)
                }
                .buttonStyle(.borderless)
                .help("Quitar este proyecto")
            }
            TextField("Link", text: $link, prompt: Text("https://claude.ai/project/…"))
            TextField("Otras formas de decirlo", text: $spoken, prompt: Text("Opcional, separadas por comas"))
            Text(hint)
                .font(.caption)
                .foregroundColor(valid ? .secondary : Theme.warning)
        }
        .padding(.vertical, 4)
        .onChange(of: name) { _ in onChange(current) }
        .onChange(of: spoken) { _ in onChange(current) }
        .onChange(of: link) { _ in onChange(current) }
    }

    private var hint: String {
        guard valid else { return "Pega el link del proyecto (debe traer su código, como claude.ai/project/abcd…)" }
        let spokenName = name.trimmingCharacters(in: .whitespaces)
        return spokenName.isEmpty ? "Ponle un nombre para poder decirlo" : "Di: “Oye Claudio, a \(spokenName): …”"
    }
}

/// Colores para el compañero: los de la lista o uno a tu gusto.
struct MascotColorPicker: View {
    @ObservedObject var companion: CompanionController
    @State private var custom: Color

    init(companion: CompanionController, initial: Color) {
        _companion = ObservedObject(wrappedValue: companion)
        _custom = State(initialValue: initial)
    }

    var body: some View {
        HStack(spacing: 7) {
            ForEach(MascotPalette.presets, id: \.hex) { preset in
                let color = preset.hex.isEmpty ? Theme.accent : MascotPalette.color(hex: preset.hex)
                let selected = companion.colorHex == preset.hex
                Button {
                    companion.colorHex = preset.hex
                } label: {
                    Circle()
                        .fill(color)
                        .frame(width: 16, height: 16)
                        .overlay(
                            Circle()
                                .stroke(Color.primary.opacity(selected ? 0.85 : 0), lineWidth: 2)
                                .padding(-3)
                        )
                }
                .buttonStyle(.plain)
                .help(preset.name)
            }
            ColorPicker("Otro color", selection: $custom, supportsOpacity: false)
                .labelsHidden()
                .help("Otro color")
                .onChange(of: custom) { newColor in
                    companion.colorHex = MascotPalette.hex(from: newColor)
                }
        }
    }
}

/// Un renglón del diccionario: "si oye… → escribe…".
struct DictionaryRuleRow: View {
    let rule: DictionaryRule
    let onChange: (DictionaryRule) -> Void
    let onDelete: () -> Void

    @State private var heard: String
    @State private var write: String

    init(rule: DictionaryRule, onChange: @escaping (DictionaryRule) -> Void, onDelete: @escaping () -> Void) {
        self.rule = rule
        self.onChange = onChange
        self.onDelete = onDelete
        _heard = State(initialValue: rule.heard)
        _write = State(initialValue: rule.write)
    }

    private var current: DictionaryRule {
        var updated = rule
        updated.heard = heard
        updated.write = write
        return updated
    }

    var body: some View {
        HStack(spacing: 8) {
            TextField("Si oye", text: $heard, prompt: Text("cloud code, clod code"))
            Image(systemName: "arrow.right")
                .foregroundColor(.secondary)
            TextField("Escribe", text: $write, prompt: Text("Claude Code"))
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundColor(Theme.danger)
            }
            .buttonStyle(.borderless)
            .help("Quitar esta corrección")
        }
        .onChange(of: heard) { _ in onChange(current) }
        .onChange(of: write) { _ in onChange(current) }
    }
}

/// Un link de calendario (.ics) con su estado.
struct CalendarLinkRow: View {
    let link: CalendarLink
    let status: String?
    let onChange: (CalendarLink) -> Void
    let onDelete: () -> Void

    @State private var name: String
    @State private var url: String

    init(link: CalendarLink, status: String?, onChange: @escaping (CalendarLink) -> Void, onDelete: @escaping () -> Void) {
        self.link = link
        self.status = status
        self.onChange = onChange
        self.onDelete = onDelete
        _name = State(initialValue: link.name)
        _url = State(initialValue: link.url)
    }

    private var current: CalendarLink {
        var updated = link
        updated.name = name
        updated.url = url
        return updated
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TextField("Nombre", text: $name, prompt: Text("Trabajo (Teams)"))
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundColor(Theme.danger)
                }
                .buttonStyle(.borderless)
                .help("Quitar este calendario")
            }
            SecureField("Link", text: $url, prompt: Text("https://… .ics  o  webcal://…"))
            if let status = status {
                Text(status)
                    .font(.caption)
                    .foregroundColor(status.hasPrefix("Conectado") ? Theme.success : .secondary)
            }
        }
        .padding(.vertical, 4)
        .onChange(of: name) { _ in onChange(current) }
        .onChange(of: url) { _ in onChange(current) }
    }
}
