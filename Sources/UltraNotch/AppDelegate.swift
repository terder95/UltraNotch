import AppKit
import SwiftUI
import Combine
import ServiceManagement

/// Arranca todo: la isla, el estante, el portapapeles, los atajos y el ícono
/// de la barra de menús.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var notch: NotchController!
    private var shelf: ShelfStore!
    private var clipboard: ClipboardStore!
    private var monitor: SystemMonitor!
    private var claude: ClaudeCodeMonitor!
    private var voice: VoiceWake!
    private var companion: CompanionController!
    private let keys = KeyInterceptor()
    private let roamer = RoamController()
    private let keepAwake = KeepAwake()
    private let holdToTalk = HoldToTalkKey()
    private let music = NowPlaying()
    private let lyrics = LyricsStore()
    private let agenda = CalendarStore()
    private var musicObserver: AnyCancellable?
    private var companionObserver: AnyCancellable?
    /// La terminal que trajimos al frente para dictarle.
    private var terminalTarget: String?
    private let settingsWindow = SettingsWindowController()
    private var statusItem: NSStatusItem?
    private var permissionRetry: AnyCancellable?
    private var activationObserver: NSObjectProtocol?
    private var voiceObserver: AnyCancellable?
    /// Estamos puliendo lo que dictaste para responderle a Claude Code.
    private var polishingReply = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Si ya hay un UltraNotch abierto, este se cierra sin hacer nada (nunca dos al mismo tiempo).
        if CrashGuard.anotherInstanceRunning {
            exit(0)
        }
        NSApp.setActivationPolicy(.accessory)
        CrashGuard.shared.start()

        let notch = NotchController()
        let shelf = ShelfStore()
        let clipboard = ClipboardStore()
        let monitor = SystemMonitor()
        let claude = ClaudeCodeMonitor()
        let voice = VoiceWake()
        let companion = CompanionController()
        self.notch = notch
        self.companion = companion
        self.shelf = shelf
        self.clipboard = clipboard
        self.monitor = monitor
        self.claude = claude
        self.voice = voice

        // Claude Code en vivo
        claude.onPeek = { [weak self] peek in
            self?.notch.flash(peek)
        }
        claude.onLive = { [weak self] activity in
            self?.notch.live = activity
            if activity != nil { self?.roamer.comeHome(fast: false) } // a trabajar: regresa del paseo
        }
        claude.onApprovalsChanged = { [weak self] first in
            guard let strongSelf = self else { return }
            // Las preguntas (y la vista previa de cambios) necesitan una tarjeta más alta.
            strongSelf.notch.alertExtra = ApprovalLayout.extraHeight(for: first)
            strongSelf.notch.alertActive = first != nil
            if first != nil { strongSelf.roamer.comeHome(fast: true) }
        }
        claude.onAttention = { [weak self] in
            guard let strongSelf = self, !strongSelf.notch.isExpanded else { return }
            strongSelf.notch.tab = .claude
        }
        claude.onFinished = { [weak self] session, hold in
            self?.claudeFinished(session, hold: hold)
        }
        claude.onReplyHoldChanged = { [weak self] hold in
            guard let strongSelf = self else { return }
            if hold != nil {
                strongSelf.voice.openReplyWindow()
            } else {
                strongSelf.voice.closeReplyWindow()
                strongSelf.companion.dismissBubble(kind: .reply)
            }
        }
        claude.canReplyByVoice = { [weak self] in
            guard let strongSelf = self else { return false }
            // Con el micrófono apagado ("escuchar siempre" desactivado) solo se puede con la tecla ⌥.
            switch strongSelf.voice.state {
            case .listening: return true
            case .standby: return strongSelf.holdToTalk.enabled
            default: return false
            }
        }
        claude.isDictatingReply = { [weak self] in
            guard let strongSelf = self else { return false }
            // También mientras pulimos tu respuesta (Apple Intelligence tarda un segundito).
            return strongSelf.voice.isDictatingReply || strongSelf.polishingReply
        }

        // Voz: "Oye Claudio"
        voice.onCommand = { [weak self] command in
            self?.handleVoice(command)
        }
        voice.onMicrophoneProblem = { [weak self] message in
            self?.notch.flash(Peek(symbol: "mic.slash", title: message, tint: Theme.warning))
        }
        // Si apagas la voz (o falta el permiso), no tiene caso que Claude Code siga esperando.
        voiceObserver = voice.$state
            .removeDuplicates()
            .sink { [weak self] state in
                guard state != .listening && state != .standby else { return }
                self?.claude.releaseReplyHold(reason: "La voz no está escuchando: Claude Code sigue normal")
            }
        voice.onDictationStarted = { [weak self] target in
            guard let strongSelf = self else { return }
            if target == .terminal {
                // Con un permiso pendiente, "terminal" es para contestarlo allá (no para escribir).
                if let approval = strongSelf.claude.approvals.first {
                    strongSelf.voice.cancelDictation()
                    strongSelf.notch.close()
                    strongSelf.claude.decide(approval, .terminal)
                    strongSelf.claude.openTerminal(forApproval: approval)
                    return
                }
                // Traemos la terminal al frente ya; lo que dictes se escribe ahí.
                strongSelf.terminalTarget = strongSelf.claude.openTerminal()
            }
            // Abrimos la isla para que veas lo que vas dictando.
            strongSelf.notch.tab = .claude
            strongSelf.notch.open(pinned: true)
        }

        // Tecla para hablar: mantén ⌥ derecha, habla y suéltala.
        holdToTalk.onBegan = { [weak self] in
            guard let strongSelf = self else { return false }
            if strongSelf.voice.holdToTalkBegan() { return true }
            strongSelf.notch.flash(Peek(symbol: "mic.slash",
                                        title: strongSelf.voice.enabled ? "La voz aún no está lista" : "Activa la voz en Configuración",
                                        tint: Theme.warning))
            return false
        }
        holdToTalk.onEnded = { [weak voice] in
            voice?.holdToTalkEnded()
        }
        holdToTalk.onCancelled = { [weak self] in
            self?.voice.cancelHold()
            self?.notch.close()
        }
        holdToTalk.start()

        // Compañero junto al notch
        notch.companion = companion
        companion.claude = claude
        companion.monitor = monitor
        companion.shelf = shelf
        companion.openTab = { [weak self] tab in
            guard let strongSelf = self else { return }
            strongSelf.notch.tab = tab
            strongSelf.notch.open(pinned: true)
        }
        companion.isMoodIdle = { [weak self] in
            guard let strongSelf = self else { return false }
            return strongSelf.voice.phase == .idle
                && strongSelf.claude.activeCount == 0
                && strongSelf.claude.approvals.isEmpty
                && strongSelf.claude.replyHold == nil
                && !strongSelf.claude.sessions.contains(where: { $0.status == .waiting })
        }
        companion.isKeepingAwake = { [weak self] in
            self?.keepAwake.isOn ?? false
        }
        // Si apagas al compañero mientras anda de paseo, regresa de inmediato.
        companionObserver = companion.$enabled
            .removeDuplicates()
            .sink { [weak self] enabled in
                if !enabled { self?.roamer.comeHome(fast: true) }
            }
        companion.onRoamRequest = { [weak self] in
            self?.startRoam(force: false)
        }
        roamer.onFinished = { [weak self] in
            self?.companion.endRoam()
        }
        companion.isIslandBusy = { [weak self] in
            guard let strongSelf = self else { return true }
            return strongSelf.notch.isExpanded || strongSelf.notch.alertActive
        }

        // Si abres la terminal de una sesión que espera tu respuesta, le regresamos el control.
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let bundleID = app?.bundleIdentifier
            Task { @MainActor in
                self?.claude.appActivated(bundleID)
            }
        }

        monitor.notch = notch
        monitor.onEvent = { [weak self] peek in
            self?.notch.flash(peek)
        }
        // Conectaste el cargador: el compañero se pone contento.
        monitor.onPowerChanged = { [weak self] connected in
            if connected { self?.companion.powerConnected() }
        }

        // Música: la letra de cada canción y, sin compañero, la carátula junto al notch.
        music.onTrackChanged = { [weak self] track in
            self?.lyrics.update(for: track)
        }
        musicObserver = Publishers.CombineLatest3(music.$track, music.$showInIsland, companion.$enabled)
            .sink { [weak self] track, inIsland, companionOn in
                self?.notch.musicWings = track?.playing == true && inIsland && !companionOn
            }
        // Música: aviso cortito cuando cambia la canción (si no hay nada más importante).
        music.onNewSong = { [weak self] track in
            guard let strongSelf = self, !strongSelf.notch.isExpanded, !strongSelf.notch.alertActive,
                  strongSelf.notch.live == nil, !strongSelf.notch.isPeeking else { return }
            strongSelf.notch.flash(Peek(symbol: "music.note", title: track.title, tint: Theme.accent))
        }
        // Agenda: te avisa antes de tus juntas (con botón para unirte).
        agenda.onReminder = { [weak self] meeting in
            self?.meetingReminder(meeting)
        }

        shelf.onAutoAdded = { [weak self] item in
            self?.announce(item)
        }
        AirDropSender.shared.onResult = { [weak self] sent, count in
            guard let strongSelf = self else { return }
            let what = count == 1 ? "Archivo" : "\(count) archivos"
            strongSelf.notch.flash(Peek(
                symbol: sent ? "dot.radiowaves.left.and.right" : "exclamationmark.triangle.fill",
                title: sent ? "\(what) por AirDrop ✓" : "AirDrop no se pudo mandar",
                tint: sent ? Theme.airDrop : Theme.warning
            ))
            if sent { strongSelf.companion.celebrate() }
        }
        clipboard.onEvent = { [weak self] peek in
            self?.notch.flash(peek)
        }
        notch.onOpen = { [weak self] in
            self?.roamer.comeHome(fast: true)
            self?.shelf.prune()
            if self?.notch.tab == .mac {
                self?.monitor.tabAppeared()
            } else {
                self?.monitor.refreshStats(includeDisk: true)
            }
        }
        keys.onAction = { [weak self] action in
            Task { @MainActor in
                self?.handle(action)
            }
        }

        let root = IslandRootView(
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
            onRequestPermission: { [weak self] in
                self?.requestAccessibility()
            },
            onOpenSettings: { [weak self] in
                self?.openSettings()
            }
        )
        .environment(\.locale, Locale(identifier: "es_MX"))
        notch.install(root: root)

        setupStatusItem()
        startShortcuts()
        if voice.enabled {
            voice.start()
        }
        companion.start()
        music.start()
        agenda.start()

        // Si el vigilante la volvió a abrir, te decimos qué pasó (y queda en el Registro).
        if CrashGuard.shared.reopenedAfterCrash {
            let before = UltraNotchLog.shared.previousSession.suffix(12)
            UltraNotchLog.shared.add("⚠︎ UltraNotch se cerró de golpe y el vigilante lo volvió a abrir. Lo último antes del cierre:")
            for line in before { UltraNotchLog.shared.add("   " + line) }
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                self?.companion.say(CompanionBubble(title: "Me cerré de golpe, pero ya volví",
                                                   message: "Guardé lo que pasó en Configuración › Registro.",
                                                   kind: .warning, duration: 8))
            }
        }
    }

    // MARK: Claude Code terminó

    private func claudeFinished(_ session: ClaudeSession, hold: ReplyHold?) {
        companion.celebrate()
        if companion.enabled && companion.bubblesEnabled && !notch.isExpanded {
            companion.showFinished(
                session: session,
                hold: hold,
                onReply: { [weak self] in self?.startReplyDictation() },
                onIgnore: { [weak self] in self?.claude.releaseReplyHold(reason: "Lo ignoraste") }
            )
        } else {
            let title = hold != nil ? "\(session.project) terminó · di “responde…”" : "\(session.project) terminó"
            notch.flash(Peek(symbol: "checkmark.circle.fill", title: title, tint: Theme.success))
        }
    }

    // MARK: Juntas

    private func meetingReminder(_ meeting: Meeting) {
        SoundBoard.play(.meeting)
        let minutes = Int((meeting.start.timeIntervalSinceNow / 60).rounded(.up))
        let when = minutes <= 0 ? "ya empezó" : (minutes == 1 ? "empieza en 1 min" : "empieza en \(minutes) min")
        UltraNotchLog.shared.add("Junta: “\(meeting.title)” \(when)")
        if companion.enabled && companion.bubblesEnabled && !notch.isExpanded && !roamer.isRoaming {
            var bubble = CompanionBubble(
                title: "“\(meeting.title)” \(when)",
                message: meeting.service.map { "Es en \($0)." } ?? (meeting.location.isEmpty ? nil : meeting.location),
                onTap: { [weak self] in self?.companion.openTab?(.today) },
                duration: 45
            )
            if meeting.joinURL != nil {
                bubble.buttons = [
                    BubbleButton(title: "Unirme", symbol: "video.fill", prominent: true, action: { [weak self] in
                        self?.companion.dismissBubble()
                        self?.agenda.join(meeting)
                    }),
                    BubbleButton(title: "Luego", action: { [weak self] in
                        self?.companion.dismissBubble()
                    })
                ]
            }
            companion.say(bubble)
        } else {
            notch.flash(Peek(symbol: "calendar", title: "\(meeting.title) · \(when)", tint: Theme.accent))
        }
    }

    // MARK: Paseo del compañero

    /// Sale a pasear por la pantalla. `force` = lo pediste tú (menú o Configuración).
    private func startRoam(force: Bool) {
        guard companion.enabled, !roamer.isRoaming, !companion.roaming,
              let screen = NotchGeometry.targetScreen() else { return }
        if !force && (notch.isExpanded || notch.alertActive || RoamController.fullScreenAppActive(on: screen)) {
            return
        }
        if notch.isExpanded { notch.close() }
        companion.beginRoam()
        let start = companion.buddyPoint(on: screen, notchSize: notch.notchSize, wing: notch.companionWing)
        roamer.start(from: start, screen: screen, tint: companion.color, home: { [weak self] in
            guard let strongSelf = self, let current = NotchGeometry.targetScreen() else { return start }
            return strongSelf.companion.buddyPoint(on: current, notchSize: strongSelf.notch.notchSize,
                                                   wing: strongSelf.notch.companionWing)
        })
    }

    @objc private func toggleKeepAwake() {
        keepAwake.toggle()
        notch.flash(Peek(symbol: "cup.and.saucer.fill",
                         title: keepAwake.isOn ? "Modo programación: no se dormirá" : "Modo programación apagado",
                         tint: Theme.accent))
    }

    func applicationWillTerminate(_ notification: Notification) {
        CrashGuard.markCleanExit() // la cerraste tú: el vigilante no la reabre
        keepAwake.stop()
    }

    @objc private func roamNow() {
        startRoam(force: true)
    }

    private func startReplyDictation() {
        companion.dismissBubble(kind: .reply)
        if !voice.startDictation(for: .reply) {
            notch.flash(Peek(symbol: "mic.slash", title: "Activa “\(voice.displayPhrase)” para responder", tint: Theme.warning))
        }
    }

    // MARK: Voz ("Oye Claudio")

    private func handleVoice(_ command: VoiceCommand) {
        switch command {
        case .open:
            roamer.comeHome(fast: true)
            notch.tab = .claude
            notch.open(pinned: true)
            notch.flash(Peek(symbol: "waveform", title: "Te escucho…", tint: Theme.accent))
        case .allow, .always, .deny:
            // Solo la tarjeta que estás viendo (nunca un permiso escondido detrás de una pregunta).
            guard let approval = claude.approvals.first, !approval.isQuestion else {
                if claude.approvals.first?.isQuestion == true {
                    // Una pregunta no se contesta con "permitir": se elige una opción.
                    notch.tab = .claude
                    notch.open(pinned: true)
                    notch.flash(Peek(symbol: "questionmark.bubble.fill", title: "Elige una opción de la pregunta",
                                     tint: Theme.accent))
                } else {
                    notch.flash(Peek(symbol: "hand.raised", title: "No hay permisos pendientes", tint: Theme.warning))
                }
                return
            }
            let decision: ApprovalDecision = command == .allow ? .allow : (command == .always ? .always : .deny)
            claude.decide(approval, decision)
            let title = command == .deny ? "Negado" : "Permitido"
            notch.flash(Peek(symbol: command == .deny ? "xmark.circle.fill" : "checkmark.circle.fill",
                             title: title, tint: command == .deny ? Theme.danger : Theme.success))
        case .terminal:
            notch.close()
            if let approval = claude.approvals.first {
                claude.decide(approval, .terminal)
                claude.openTerminal(forApproval: approval)
            } else {
                claude.openTerminal()
                presentFrontWindow(after: 0.9)
            }
        case .shelf:
            notch.tab = .shelf
            notch.open(pinned: true)
        case .clipboard:
            notch.tab = .clipboard
            notch.open(pinned: true)
        case .mac:
            notch.tab = .mac
            notch.open(pinned: true)
        case .close:
            notch.close()
        case .ignore:
            if claude.replyHold != nil {
                claude.releaseReplyHold(reason: "Lo ignoraste")
                notch.flash(Peek(symbol: "hand.thumbsup.fill", title: "Va, lo dejo así", tint: Theme.accent))
            } else {
                notch.flash(Peek(symbol: "checkmark.circle", title: "Nada pendiente", tint: Theme.accent))
            }
        case .keepAwake:
            toggleKeepAwake()
        case .today:
            notch.tab = .today
            notch.open(pinned: true)
        case .musicPlayPause:
            notch.close()
            music.playPause()
            let playing = music.track?.playing
            notch.flash(Peek(symbol: playing == false ? "pause.fill" : "play.fill",
                             title: playing == nil ? "Play / pausa" : (playing == true ? "Reproduciendo" : "En pausa"),
                             tint: Theme.accent))
        case .musicNext:
            notch.close()
            music.next()
            notch.flash(Peek(symbol: "forward.fill", title: "Siguiente canción", tint: Theme.accent))
        case .musicPrevious:
            notch.close()
            music.previous()
            notch.flash(Peek(symbol: "backward.fill", title: "Canción anterior", tint: Theme.accent))
        case .cancelled:
            terminalTarget = nil
            notch.close()
            notch.flash(Peek(symbol: "xmark.circle", title: "Cancelado, no mandé nada", tint: Theme.warning))
        case .dictated(let target, let text):
            notch.close()
            guard let raw = text else {
                route(target, nil)
                return
            }
            // Tu diccionario y la limpieza (con Apple Intelligence si está activado).
            // En una terminal "pelona" (sin Claude Code) solo tus correcciones: sin mayúsculas ni puntos.
            let terminalHasClaude = terminalTarget.map { claude.hasSession(inTerminal: $0) } ?? false
            let rulesOnly = target == .terminal && !terminalHasClaude
            if DictationPolisher.usesSmart && !rulesOnly {
                notch.flash(Peek(symbol: "wand.and.stars", title: "Puliendo tu texto…", tint: Theme.accent))
            }
            if target == .reply { polishingReply = true }
            Task { @MainActor [weak self] in
                let polished = rulesOnly ? PersonalDictionary.shared.applyRules(raw) : await DictationPolisher.polish(raw)
                guard let strongSelf = self else { return }
                strongSelf.polishingReply = false
                if polished != raw {
                    UltraNotchLog.shared.add("Texto pulido: “\(String(polished.prefix(120)))”")
                }
                strongSelf.route(target, polished)
            }
        }
    }

    /// Manda lo que dictaste a donde dijiste.
    private func route(_ target: DictationTarget, _ text: String?) {
        switch target {
        case .reply:
            sendReply(text)
        case .terminal:
            if text == nil { presentFrontWindow(after: 0.6) } // solo querías la terminal
            typeInTerminal(text, done: { [weak self] _, ok in
                if ok { self?.presentFrontWindow() }
            })
        case .claude(let destination):
            openInClaude(destination, text: text, done: { [weak self] _, ok in
                if ok { self?.presentFrontWindow() }
            })
        case .chatGPT:
            openInChatGPT(text, done: { [weak self] _, ok in
                if ok { self?.presentFrontWindow() }
            })
        }
    }

    /// "Oye Claudio, ChatGPT, …"
    private func openInChatGPT(_ text: String?, done: Done? = nil) {
        notch.flash(Peek(symbol: "bubble.left.and.bubble.right.fill", title: "Abriendo ChatGPT…", tint: Theme.accent))
        ChatGPTChat.send(text) { [weak self] message, ok in
            if !ok { SoundBoard.play(.failure) }
            self?.notch.flash(Peek(symbol: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                                   title: message, tint: ok ? Theme.success : Theme.warning))
            done?(message, ok)
        }
    }

    /// El compañero vuela a presentarte la ventana que acabas de abrir (sin moverla).
    private func presentFrontWindow(after delay: Double = 0.5) {
        guard companion.enabled, companion.presentWindows else { return }
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let strongSelf = self,
                  !strongSelf.roamer.isRoaming, !strongSelf.companion.roaming,
                  !strongSelf.notch.isExpanded, !strongSelf.notch.alertActive,
                  let screen = NotchGeometry.targetScreen(),
                  let front = NSWorkspace.shared.frontmostApplication,
                  front.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
            // Preguntamos por la ventana fuera del hilo principal (la app puede tardar en contestar).
            let pid = front.processIdentifier
            let primaryTop = NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY
            let found = await Task.detached { WindowLocator.frontWindowFrame(pid: pid, primaryTop: primaryTop) }.value
            guard let window = found, screen.frame.intersects(window),
                  !strongSelf.roamer.isRoaming, !strongSelf.companion.roaming, !strongSelf.notch.isExpanded else { return }
            // En pantalla completa no hay dónde pararse.
            if window.width >= screen.frame.width - 2 && window.height >= screen.frame.height - 2 { return }
            strongSelf.companion.beginRoam()
            let start = strongSelf.companion.buddyPoint(on: screen, notchSize: strongSelf.notch.notchSize,
                                                        wing: strongSelf.notch.companionWing)
            strongSelf.roamer.present(window: window, from: start, tint: strongSelf.companion.color, home: { [weak self] in
                guard let strongSelf = self, let current = NotchGeometry.targetScreen() else { return start }
                return strongSelf.companion.buddyPoint(on: current, notchSize: strongSelf.notch.notchSize,
                                                       wing: strongSelf.notch.companionWing)
            })
        }
    }

    /// "Oye Claudio, nuevo chat / cowork / a <proyecto>…"
    private func openInClaude(_ destination: ClaudeDestination, text: String?, done: Done? = nil) {
        notch.flash(Peek(symbol: "bubble.left.and.bubble.right.fill",
                         title: "Abriendo \(destination.label)…", tint: Theme.accent))
        ClaudeChat.send(destination, text: text) { [weak self] message, ok in
            if !ok { SoundBoard.play(.failure) }
            self?.notch.flash(Peek(symbol: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                                   title: message, tint: ok ? Theme.success : Theme.warning))
            done?(message, ok)
        }
    }

    typealias Done = (String, Bool) -> Void

    /// "Oye Claudio, terminal, …": escribe lo que dictaste en la terminal y da Enter.
    /// `requireSession`: solo escribe si ahí corre una sesión de Claude Code (para las respuestas;
    /// así nunca mandamos texto a una terminal "pelona" donde se ejecutaría como comando).
    /// `fallbackToChat`: si no hay ninguna sesión de Claude Code abierta, lo manda a un chat nuevo.
    private func typeInTerminal(_ text: String?, requireSession: Bool = false,
                                fallbackToChat: Bool = false, session: ClaudeSession? = nil, done: Done? = nil) {
        let target = terminalTarget
        terminalTarget = nil
        guard let text = text else { return } // solo querías la terminal: ya está al frente

        let fail: (String, Bool) -> Void = { [weak self] reason, noSession in
            if noSession && fallbackToChat {
                UltraNotchLog.shared.add("\(reason) Lo mando a un chat nuevo.")
                self?.openInClaude(.newChat, text: text, done: done)
                return
            }
            ClaudeChat.copyTransient(text)
            SoundBoard.play(.failure)
            UltraNotchLog.shared.add("\(reason) Tu texto quedó copiado.")
            self?.notch.flash(Peek(symbol: "doc.on.clipboard", title: "Quedó copiado: pégalo con ⌘V", tint: Theme.warning))
            done?("\(reason) Tu texto quedó copiado en la Mac.", false)
        }

        Task { @MainActor [weak self] in
            guard let strongSelf = self else { return }

            // 1) Buscamos la pestaña donde corre Claude Code y la ponemos al frente.
            var bundle = target
            var claudeTabFound = false
            // a) La pestaña exacta de la sesión (Terminal e iTerm2), si lo activaste en Configuración.
            if TerminalJump.enabled,
               let exact = session ?? strongSelf.claude.latestTerminalSession,
               let tty = exact.tty, let exactBundle = exact.terminalBundle, TerminalJump.supports(exactBundle),
               !NSRunningApplication.runningApplications(withBundleIdentifier: exactBundle).isEmpty,
               await TerminalJump.focus(tty: tty, bundle: exactBundle) {
                bundle = exactBundle
                claudeTabFound = true
                UltraNotchLog.shared.add("Fui a la pestaña exacta de \(exact.project) ✓")
            } else if !NSRunningApplication.runningApplications(withBundleIdentifier: TerminalFinder.terminalID).isEmpty {
                // b) En Terminal (la de macOS), la primera pestaña donde corre Claude Code.
                let result = await TerminalFinder.focusClaudeTab()
                if result == .found {
                    bundle = TerminalFinder.terminalID
                    claudeTabFound = true
                    UltraNotchLog.shared.add("Encontré la pestaña de Terminal donde corre Claude Code ✓")
                } else if result == .noPermission {
                    UltraNotchLog.shared.add("macOS no dejó a UltraNotch revisar las pestañas de Terminal (Ajustes › Privacidad › Automatización)")
                }
            }
            if bundle == nil {
                bundle = strongSelf.claude.openTerminal()
            }
            guard let bundle = bundle else {
                fail("No encontré la terminal.", true)
                return
            }
            // Solo terminales de verdad (no editores como VS Code, donde el texto caería en un archivo).
            guard ClaudeCodeMonitor.typableTerminals.contains(bundle) else {
                fail("Esa app no es una terminal donde pueda escribir sin riesgo.", false)
                return
            }
            if requireSession && !claudeTabFound && !strongSelf.claude.hasSession(inTerminal: bundle) {
                fail("No encontré una sesión de Claude Code abierta en la terminal.", true)
                return
            }

            // 2) Esperamos a que la terminal esté al frente; nunca escribimos en otra app.
            if NSWorkspace.shared.frontmostApplication?.bundleIdentifier != bundle {
                AppActivator.bringToFront(bundle)
            }
            let deadline = Date().addingTimeInterval(3)
            while NSWorkspace.shared.frontmostApplication?.bundleIdentifier != bundle && Date() < deadline {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundle else {
                fail("La terminal no pasó al frente.", false)
                return
            }
            // Si Claude te está pidiendo un permiso, un Enter lo aprobaría: no escribimos.
            guard strongSelf.claude.approvals.isEmpty else {
                fail("Claude está pidiendo un permiso; contéstalo primero.", false)
                return
            }
            try? await Task.sleep(nanoseconds: 250_000_000) // que la pestaña termine de acomodarse

            // 3) Pegamos y damos Enter.
            let pasteboard = NSPasteboard.general
            let backup = ClipItem.capture(from: pasteboard, respectPrivacy: false)
            ClaudeChat.copyTransient(text)
            KeyInterceptor.postCommandV()
            UltraNotchLog.shared.add("Escribí en la terminal: “\(String(text.prefix(80)))”")
            try? await Task.sleep(nanoseconds: 400_000_000)
            var sent = false
            if ClaudeChat.autoSend && NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundle
                && strongSelf.claude.approvals.isEmpty {
                KeyboardSynth.press(36, flags: []) // Enter
                UltraNotchLog.shared.add("Envié con Enter ✓")
                sent = true
            }
            done?(sent ? "Lo escribí en Claude Code (terminal) y le di Enter ✓" : "Lo escribí en la terminal (sin enviar)", true)
            // Te regresamos lo que tenías copiado.
            try? await Task.sleep(nanoseconds: 800_000_000)
            backup?.write(to: pasteboard)
        }
    }

    /// "responde…": se lo mandamos a la sesión de Claude Code que acaba de terminar.
    private func sendReply(_ text: String?, done: Done? = nil) {
        guard let text = text else {
            // No dijiste nada (o dijiste "cancela"): la sesión sigue esperando hasta su límite.
            notch.flash(Peek(symbol: "mic.slash", title: "No mandé nada", tint: Theme.warning))
            done?("No mandé nada: no oí tu respuesta.", false)
            return
        }
        if let hold = claude.replyHold, claude.sendReply(text) {
            companion.say(CompanionBubble(title: "Se lo dije a \(hold.project)", message: "“\(text)”",
                                          kind: .claude, duration: 4))
            if !(companion.enabled && companion.bubblesEnabled) {
                notch.flash(Peek(symbol: "paperplane.fill", title: "Respuesta enviada", tint: Theme.success))
            }
            done?("Se lo dije a \(hold.project) ✓", true)
            return
        }
        // Ya nadie esperaba: lo escribimos en la terminal de la sesión que terminó.
        guard let session = claude.lastFinishedSession ?? claude.sessions.first else {
            ClaudeChat.copyTransient(text)
            notch.flash(Peek(symbol: "doc.on.clipboard", title: "No hay sesión esperando · quedó copiado", tint: Theme.warning))
            done?("No hay ninguna sesión de Claude Code esperando. Tu texto quedó copiado en la Mac.", false)
            return
        }
        UltraNotchLog.shared.add("\(session.project) ya no esperaba: lo escribo en su terminal")
        terminalTarget = claude.openTerminal(for: session)
        typeInTerminal(text, requireSession: true, session: session, done: done)
    }

    // MARK: Configuración

    @objc private func openSettings() {
        notch.close()
        settingsWindow.show {
            SettingsView(notch: notch, shelf: shelf, claude: claude, voice: voice, companion: companion,
                         keepAwake: keepAwake, music: music, lyrics: lyrics, agenda: agenda,
                         onRoamNow: { [weak self] in self?.startRoam(force: true) })
                .environment(\.locale, Locale(identifier: "es_MX"))
        }
    }

    // MARK: Avisos

    private func announce(_ item: ShelfItem) {
        switch item.source {
        case .screenshot:
            notch.flash(Peek(symbol: "camera.viewfinder", title: "Captura en el estante", tint: Theme.screenshot, fileURL: item.url))
        case .download:
            notch.flash(Peek(symbol: "arrow.down.circle.fill", title: "Descarga lista", tint: Theme.download, fileURL: item.url))
        case .dropped:
            break
        }
    }

    private func handle(_ action: KeyInterceptor.Action) {
        switch action {
        case .saveSlot(let slot, let baseline):
            clipboard.saveAfterCopy(slot: slot, baseline: baseline)
        case .pasteSlot(let slot):
            clipboard.pasteSlot(slot)
        }
    }

    // MARK: Atajos de teclado (permiso de Accesibilidad)

    private func startShortcuts() {
        if keys.start() {
            clipboard.shortcutsActive = true
            return
        }
        Permissions.promptAccessibility()
        // Reintenta hasta que actives el permiso en Ajustes.
        permissionRetry = Timer.publish(every: 1.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let strongSelf = self else { return }
                if strongSelf.keys.start() {
                    strongSelf.clipboard.shortcutsActive = true
                    strongSelf.permissionRetry = nil
                    strongSelf.holdToTalk.restart() // ya con permiso, que escuche la tecla ⌥
                    strongSelf.notch.flash(Peek(symbol: "keyboard", title: "Atajos activos", tint: Theme.success))
                }
            }
    }

    @objc private func requestAccessibility() {
        Permissions.promptAccessibility()
        Permissions.openAccessibilitySettings()
    }

    // MARK: Ícono en la barra de menús

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            if let image = NSImage(systemSymbolName: "rectangle.topthird.inset.filled", accessibilityDescription: "UltraNotch") {
                image.isTemplate = true
                button.image = image
            } else {
                button.title = "◉"
            }
        }
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    /// Se reconstruye cada vez que abres el menú (así las palomitas están al día).
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        menu.addItem(makeItem("Configuración…", #selector(openSettings)))
        let awake = makeItem("Modo programación (la Mac no se duerme)", #selector(toggleKeepAwake))
        awake.state = keepAwake.isOn ? .on : .off
        menu.addItem(awake)
        menu.addItem(.separator())
        menu.addItem(makeItem("Abrir el panel", #selector(openIsland)))
        menu.addItem(makeItem("Ver hoy (música y agenda)", #selector(openTodayTab)))
        menu.addItem(makeItem("Ver datos de la Mac", #selector(openMacTab)))
        menu.addItem(.separator())

        let glass = makeItem("Estilo: Cristal líquido", #selector(useGlassStyle))
        glass.state = notch.style == .glass ? .on : .off
        menu.addItem(glass)
        let black = makeItem("Estilo: Negro clásico", #selector(useBlackStyle))
        black.state = notch.style == .black ? .on : .off
        menu.addItem(black)
        menu.addItem(.separator())

        if claude.hooksInstalled {
            let connected = NSMenuItem(title: "Claude Code: conectado", action: nil, keyEquivalent: "")
            connected.isEnabled = false
            menu.addItem(connected)
            let approvals = makeItem("Aprobar permisos desde el notch", #selector(toggleClaudeApprovals))
            approvals.state = claude.approvalsEnabled ? .on : .off
            menu.addItem(approvals)
            let live = makeItem("Actividad en vivo junto al notch", #selector(toggleClaudeLive))
            live.state = claude.liveEnabled ? .on : .off
            menu.addItem(live)
            let sounds = makeItem("Sonidos de Claude", #selector(toggleClaudeSounds))
            sounds.state = claude.soundsEnabled ? .on : .off
            menu.addItem(sounds)
            menu.addItem(makeItem("Desconectar Claude Code", #selector(disconnectClaude)))
        } else {
            menu.addItem(makeItem("Conectar con Claude Code…", #selector(connectClaude)))
        }
        let wake = makeItem("Escuchar “\(voice.displayPhrase)”", #selector(toggleVoiceWake))
        wake.state = voice.enabled ? .on : .off
        menu.addItem(wake)
        let buddy = makeItem("Dottie junto al notch", #selector(toggleCompanion))
        buddy.state = companion.enabled ? .on : .off
        menu.addItem(buddy)
        if companion.enabled {
            menu.addItem(makeItem("Mandar a Dottie de paseo", #selector(roamNow)))
        }
        menu.addItem(.separator())

        let screenshots = makeItem("Capturas de pantalla → estante", #selector(toggleScreenshots))
        screenshots.state = shelf.watchScreenshots ? .on : .off
        menu.addItem(screenshots)

        let downloads = makeItem("Descargas → estante", #selector(toggleDownloads))
        downloads.state = shelf.watchDownloads ? .on : .off
        menu.addItem(downloads)

        let folder = ShelfStore.screenshotFolder().lastPathComponent
        let folderInfo = NSMenuItem(title: "Carpeta de capturas: \(folder)", action: nil, keyEquivalent: "")
        folderInfo.isEnabled = false
        menu.addItem(folderInfo)
        menu.addItem(.separator())

        if clipboard.shortcutsActive {
            let active = NSMenuItem(title: "Atajos ⌘C / ⌘V + número: activos", action: nil, keyEquivalent: "")
            active.isEnabled = false
            menu.addItem(active)
        } else {
            menu.addItem(makeItem("Activar atajos (permiso de Accesibilidad)…", #selector(requestAccessibility)))
        }

        let login = makeItem("Abrir al iniciar sesión", #selector(toggleLaunchAtLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())

        menu.addItem(makeItem("Vaciar estante", #selector(clearShelf)))
        menu.addItem(makeItem("Borrar historial del portapapeles", #selector(clearHistory)))
        menu.addItem(makeItem("Vaciar las 9 ranuras", #selector(clearSlots)))
        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: "Salir de UltraNotch", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func makeItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func openIsland() {
        notch.open(pinned: true)
    }

    @objc private func connectClaude() {
        claude.connect()
    }

    @objc private func disconnectClaude() {
        claude.disconnect()
    }

    @objc private func toggleClaudeApprovals() {
        claude.approvalsEnabled.toggle()
    }

    @objc private func toggleClaudeLive() {
        claude.liveEnabled.toggle()
    }

    @objc private func toggleClaudeSounds() {
        claude.soundsEnabled.toggle()
    }

    @objc private func toggleVoiceWake() {
        voice.enabled.toggle()
    }

    @objc private func toggleCompanion() {
        if companion.enabled { roamer.comeHome(fast: true) }
        companion.enabled.toggle()
    }

    @objc private func openTodayTab() {
        notch.tab = .today
        notch.open(pinned: true)
    }

    @objc private func openMacTab() {
        notch.tab = .mac
        notch.open(pinned: true)
    }

    @objc private func useGlassStyle() {
        notch.style = .glass
        notch.open(pinned: true)
    }

    @objc private func useBlackStyle() {
        notch.style = .black
        notch.open(pinned: true)
    }

    @objc private func toggleScreenshots() {
        shelf.watchScreenshots.toggle()
    }

    @objc private func toggleDownloads() {
        shelf.watchDownloads.toggle()
    }

    @objc private func clearShelf() {
        shelf.clear()
    }

    @objc private func clearHistory() {
        clipboard.clearHistory()
    }

    @objc private func clearSlots() {
        clipboard.clearAllSlots()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "No se pudo cambiar el inicio automático"
            alert.informativeText = "\(error.localizedDescription)\n\nAsegúrate de que UltraNotch esté en la carpeta Aplicaciones."
            alert.runModal()
        }
    }
}
