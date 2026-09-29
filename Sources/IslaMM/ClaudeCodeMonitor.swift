import AppKit
import SwiftUI
import Combine

// MARK: - Modelos

enum ClaudeStatus {
    case idle, thinking, working, waiting, finished

    var label: String {
        switch self {
        case .idle: return "En pausa"
        case .thinking: return "Pensando"
        case .working: return "Trabajando"
        case .waiting: return "Te espera"
        case .finished: return "Terminó"
        }
    }

    var symbol: String {
        switch self {
        case .idle: return "moon.zzz"
        case .thinking: return "sparkle"
        case .working: return "gearshape.2"
        case .waiting: return "hand.raised.fill"
        case .finished: return "checkmark.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .idle: return Color.secondary
        case .thinking, .working: return Theme.accent
        case .waiting: return Theme.warning
        case .finished: return Theme.success
        }
    }

    var isActive: Bool { self == .thinking || self == .working }
}

struct ClaudeStep: Identifiable {
    let id = UUID()
    let symbol: String
    let verb: String
    let detail: String

    var text: String { detail.isEmpty ? verb : "\(verb) · \(detail)" }
}

struct ClaudeSession: Identifiable {
    let id: String
    var project: String
    var status: ClaudeStatus = .idle
    var steps: [ClaudeStep] = []
    var prompt: String?
    var summary: String?
    var terminalBundle: String?
    /// La pestaña exacta de la terminal ("/dev/ttys003").
    var tty: String?
    var updated = Date()
    /// Cuándo le pediste la tarea actual (para saber cuánto trabajó).
    var turnStarted: Date?
}

struct ClaudeApproval: Identifiable {
    let id: String          // id de la petición en espera
    let sessionID: String
    let project: String
    let step: ClaudeStep
    let suggestions: Data?  // opciones de "permitir siempre" que sugiere Claude Code
    /// Si Claude te hace una pregunta (AskUserQuestion): las preguntas con sus opciones.
    var questions: [ClaudeQuestion] = []
    /// Lo que mandó Claude Code tal cual (para regresarlo junto con tus respuestas).
    var toolInput: Data? = nil
    /// Vista previa del cambio (si la activaste).
    var diff: ClaudeDiff? = nil

    var isQuestion: Bool { !questions.isEmpty }
}

enum ApprovalDecision {
    case allow, always, deny, terminal
}

/// Una sesión terminó y Claude Code espera unos segundos por si le respondes por voz.
struct ReplyHold: Identifiable, Equatable {
    let id: String          // id de la petición en espera
    let sessionID: String
    let project: String
    let summary: String?
    let started: Date
    let deadline: Date
}

/// Actividad en vivo junto al notch (como las "Live Activities" del iPhone).
struct LiveActivity: Equatable {
    /// Un personajito por sesión (máximo 3).
    var statuses: [ClaudeStatus]
    var title: String
    var subtitle: String
    var tint: Color
}

// MARK: - Monitor

/// Lleva el estado de tus sesiones de Claude Code a partir de los hooks.
@MainActor
final class ClaudeCodeMonitor: ObservableObject {
    @Published private(set) var sessions: [ClaudeSession] = []
    @Published private(set) var approvals: [ClaudeApproval] = [] {
        didSet {
            onApprovalsChanged?(approvals.first)
            // Lo que llevabas contestado de tarjetas que ya se cerraron, se borra.
            let live = Set(approvals.map { $0.id })
            if questionDrafts.keys.contains(where: { !live.contains($0) }) {
                questionDrafts = questionDrafts.filter { live.contains($0.key) }
            }
        }
    }
    /// Lo que llevas contestado de cada pregunta pendiente (ver ClaudeQuestions.swift).
    @Published var questionDrafts: [String: QuestionDraft] = [:]
    /// Tarjetas con la ventanita de "Escribir…" abierta (no se les acaba el tiempo).
    var promptOpen = Set<String>()
    @Published private(set) var hooksInstalled = false

    @Published var approvalsEnabled = true {
        didSet { UserDefaults.standard.set(approvalsEnabled, forKey: ClaudeHookServer.approvalsKey) }
    }
    @Published var soundsEnabled = true {
        didSet { UserDefaults.standard.set(soundsEnabled, forKey: SoundBoard.enabledKey) }
    }
    /// Contestar desde la isla las preguntas que te hace Claude (AskUserQuestion).
    @Published var questionsEnabled = true {
        didSet { UserDefaults.standard.set(questionsEnabled, forKey: ClaudeHookServer.questionsKey) }
    }
    /// Ver qué cambia en el archivo antes de aprobar (apagado de fábrica).
    @Published var diffPreview = false {
        didSet { UserDefaults.standard.set(diffPreview, forKey: ClaudeDiff.enabledKey) }
    }
    @Published var liveEnabled = true {
        didSet {
            UserDefaults.standard.set(liveEnabled, forKey: ClaudeCodeMonitor.liveKey)
            updateLive()
        }
    }
    /// Responder por voz cuando una sesión termina ("responde…").
    @Published var replyEnabled = true {
        didSet {
            UserDefaults.standard.set(replyEnabled, forKey: ClaudeHookServer.replyKey)
            if !replyEnabled { releaseReplyHold(reason: "Respuesta por voz apagada") }
        }
    }
    /// Sesión que acaba de terminar y espera tu respuesta.
    @Published private(set) var replyHold: ReplyHold?
    /// Tus límites de uso del plan (sesión de 5 h y semana). nil = aún no llegan.
    @Published private(set) var usage: PlanUsage?
    /// Ver los límites en la isla (Isla se pone como la línea de estado de Claude Code).
    @Published var usageEnabled = true {
        didSet {
            UserDefaults.standard.set(usageEnabled, forKey: ClaudeHookInstaller.usageKey)
            if hooksInstalled && ClaudeHookInstaller.needsUpdate() {
                _ = try? ClaudeHookInstaller.install()
            }
            if !usageEnabled { usage = nil }
        }
    }
    private static let usageStoreKey = "claudePlanUsage"
    /// Avisos de límite ya dados (para no repetirlos en la misma ventana).
    private var usageAlerts: Set<String> = []

    /// Avisos cortos en el notch.
    var onPeek: ((Peek) -> Void)?
    /// Llegó una petición de permiso (para abrir la isla en la pestaña Claude).
    var onAttention: (() -> Void)?
    /// Cambió la actividad en vivo junto al notch.
    var onLive: ((LiveActivity?) -> Void)?
    /// Cambió la tarjeta pendiente (nil = ya no hay permisos ni preguntas esperando).
    var onApprovalsChanged: ((ClaudeApproval?) -> Void)?
    /// Una sesión terminó (con la espera para responder, si la hay).
    var onFinished: ((ClaudeSession, ReplyHold?) -> Void)?
    /// Empezó o terminó la espera para responder por voz.
    var onReplyHoldChanged: ((ReplyHold?) -> Void)?
    /// ¿"Oye Claudio" está escuchando? (si no, no tiene caso esperar tu respuesta)
    var canReplyByVoice: (() -> Bool)?
    /// ¿Estás dictando la respuesta ahorita? (para no cortarte a media frase)
    var isDictatingReply: (() -> Bool)?
    /// Llegó un permiso nuevo.
    var onNewApproval: ((ClaudeApproval) -> Void)?

    private static let liveKey = "claudeLive"

    private let server = ClaudeHookServer()
    private var cleanupTimer: AnyCancellable?

    init() {
        let defaults = UserDefaults.standard
        approvalsEnabled = defaults.object(forKey: ClaudeHookServer.approvalsKey) as? Bool ?? true
        soundsEnabled = defaults.object(forKey: SoundBoard.enabledKey) as? Bool ?? true
        questionsEnabled = defaults.object(forKey: ClaudeHookServer.questionsKey) as? Bool ?? true
        diffPreview = ClaudeDiff.enabled
        liveEnabled = defaults.object(forKey: ClaudeCodeMonitor.liveKey) as? Bool ?? true
        replyEnabled = defaults.object(forKey: ClaudeHookServer.replyKey) as? Bool ?? true
        hooksInstalled = ClaudeHookInstaller.isInstalled()
        usageEnabled = ClaudeHookInstaller.usageEnabled
        if usageEnabled, let data = defaults.data(forKey: ClaudeCodeMonitor.usageStoreKey) {
            usage = try? JSONDecoder().decode(PlanUsage.self, from: data)
        }

        // Si moviste la app de carpeta, actualizamos la ruta de los avisos.
        if hooksInstalled && ClaudeHookInstaller.needsUpdate() {
            _ = try? ClaudeHookInstaller.install()
        }

        server.onMessage = { [weak self] message in
            Task { @MainActor in
                self?.handle(message)
            }
        }
        server.start()

        cleanupTimer = Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.prune()
            }
    }

    var activeCount: Int {
        sessions.filter { $0.status.isActive }.count
    }

    /// Solo los permisos (sin las preguntas): lo que se contesta con "permitir" / "negar".
    var pendingPermissions: [ClaudeApproval] {
        approvals.filter { !$0.isQuestion }
    }

    // MARK: Límites de uso

    private func updateUsage(_ limits: [String: Any]) {
        guard usageEnabled, let fresh = PlanUsage.from(rateLimits: limits) else { return }
        usage = fresh
        if let data = try? JSONEncoder().encode(fresh) {
            UserDefaults.standard.set(data, forKey: ClaudeCodeMonitor.usageStoreKey)
        }
        // Te avisamos una vez al pasar 80 % y 95 % de la sesión, y 90 % de la semana.
        if let session = fresh.session {
            for level in [80.0, 95.0] where session.percent >= level {
                alertUsage("session-\(Int(level))-\(session.resetsAt?.timeIntervalSince1970 ?? 0)",
                           title: "Llevas \(Int(session.percent.rounded())) % de tu sesión de 5 h")
            }
        }
        if let week = fresh.week, week.percent >= 90 {
            alertUsage("week-90-\(week.resetsAt?.timeIntervalSince1970 ?? 0)",
                       title: "Llevas \(Int(week.percent.rounded())) % de tu límite semanal")
        }
    }

    private func alertUsage(_ key: String, title: String) {
        guard !usageAlerts.contains(key) else { return }
        usageAlerts.insert(key)
        onPeek?(Peek(symbol: "gauge.with.dots.needle.67percent", title: title, tint: Theme.warning))
        SoundBoard.play(.usage)
        IslaLog.shared.add(title)
    }

    // MARK: Conectar / desconectar

    func connect() {
        let alert = NSAlert()
        alert.messageText = "¿Conectar Isla con Claude Code?"
        alert.informativeText = """
        Isla agregará unos avisos (hooks) a ~/.claude/settings.json para ver tus sesiones \
        y aprobar permisos desde la isla. Antes guarda un respaldo del archivo y no toca tus otros ajustes.

        No usa la API ni tiene costo extra. Aplica a las sesiones nuevas de Claude Code.
        """
        alert.addButton(withTitle: "Conectar")
        alert.addButton(withTitle: "Cancelar")
        NSApp.activate(ignoringOtherApps: true)
        let accepted = alert.runModal() == .alertFirstButtonReturn
        NSApp.deactivate()
        guard accepted else { return }

        do {
            try ClaudeHookInstaller.install()
            hooksInstalled = true
            onPeek?(Peek(symbol: "checkmark.circle.fill", title: "Claude Code conectado", tint: Theme.success))
        } catch {
            showError(error)
        }
    }

    func disconnect() {
        do {
            try ClaudeHookInstaller.uninstall()
            hooksInstalled = false
            releaseReplyHold(reason: nil)
            for approval in approvals {
                server.respond(approval.id, with: nil)
            }
            approvals.removeAll()
            sessions.removeAll()
            updateLive()
        } catch {
            showError(error)
        }
    }

    private func showError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "No se pudo cambiar la conexión con Claude Code"
        alert.informativeText = error.localizedDescription
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
        NSApp.deactivate()
    }

    // MARK: Eventos de Claude Code

    private func handle(_ message: HookMessage) {
        guard let payload = (try? JSONSerialization.jsonObject(with: message.data)) as? [String: Any],
              let event = payload["hook_event_name"] as? String else {
            if let requestID = message.requestID { server.respond(requestID, with: nil) }
            return
        }
        // Límites de uso (vienen de la línea de estado, no de una sesión).
        if event == "IslaUsage" {
            if let limits = payload["rate_limits"] as? [String: Any] {
                updateUsage(limits)
            }
            return
        }
        hooksInstalled = true

        let sessionID = payload["session_id"] as? String ?? "sesion"
        let cwd = payload["cwd"] as? String ?? ""
        var session = sessions.first(where: { $0.id == sessionID })
            ?? ClaudeSession(id: sessionID, project: ClaudeCodeMonitor.projectName(from: cwd))
        if let bundle = payload["isla_terminal_bundle"] as? String, !bundle.isEmpty {
            session.terminalBundle = bundle
            if bundle != ClaudeChat.desktopBundleID {
                UserDefaults.standard.set(bundle, forKey: ClaudeCodeMonitor.lastTerminalKey)
            }
        }
        if let tty = payload["isla_tty"] as? String, !tty.isEmpty {
            session.tty = tty
        }
        session.updated = Date()
        var finishedHold: ReplyHold?
        var finished = false

        switch event {
        case "SessionStart":
            session.status = .idle
            session.steps = []
            // Solo las sesiones nuevas (no al reanudar ni al compactar).
            if (payload["source"] as? String ?? "startup") == "startup" {
                SoundBoard.play(.sessionStart)
            }

        case "UserPromptSubmit":
            clearApprovals(for: sessionID) // si respondiste en la terminal, quitamos la tarjeta
            session.turnStarted = Date()
            session.status = .thinking
            session.summary = nil
            if let prompt = payload["prompt"] as? String {
                session.prompt = ClaudeCodeMonitor.oneLine(prompt, max: 110)
            }

        case "PreToolUse":
            session.status = .working
            let step = ClaudeCodeMonitor.describe(
                tool: payload["tool_name"] as? String ?? "Herramienta",
                input: payload["tool_input"] as? [String: Any] ?? [:]
            )
            session.steps.append(step)
            if session.steps.count > 12 {
                session.steps.removeFirst(session.steps.count - 12)
            }

        case "PermissionRequest":
            session.status = .waiting
            let tool = payload["tool_name"] as? String ?? "Herramienta"
            let input = payload["tool_input"] as? [String: Any] ?? [:]
            let step = ClaudeCodeMonitor.describe(tool: tool, input: input)
            let isQuestion = tool == "AskUserQuestion"
            if let requestID = message.requestID {
                var suggestions: Data?
                if let raw = payload["permission_suggestions"] as? [Any], !raw.isEmpty {
                    suggestions = try? JSONSerialization.data(withJSONObject: raw)
                }
                var approval = ClaudeApproval(
                    id: requestID,
                    sessionID: sessionID,
                    project: session.project,
                    step: step,
                    suggestions: suggestions
                )
                if isQuestion {
                    approval.questions = ClaudeQuestion.parse(input)
                    approval.toolInput = try? JSONSerialization.data(withJSONObject: input)
                } else if diffPreview {
                    approval.diff = ClaudeDiff.make(tool: tool, input: input)
                }
                if isQuestion && (approval.questions.isEmpty || approval.toolInput == nil) {
                    // No la entendimos: que la terminal la muestre como siempre.
                    server.respond(requestID, with: nil)
                    onPeek?(Peek(symbol: "questionmark.bubble.fill", title: "Claude te pregunta algo en la terminal",
                                 tint: Theme.accent))
                } else {
                    approvals.append(approval)
                    scheduleTimeout(for: requestID, question: approval.isQuestion)
                    onNewApproval?(approval)
                    onAttention?()
                    if approval.isQuestion {
                        IslaLog.shared.add("\(session.project) te pregunta: “\(ClaudeCodeMonitor.oneLine(approval.questions[0].text, max: 90))”")
                    }
                }
            } else {
                onPeek?(Peek(symbol: isQuestion ? "questionmark.bubble.fill" : "hand.raised.fill",
                             title: isQuestion ? "Claude te pregunta algo" : "Claude pide permiso",
                             tint: isQuestion ? Theme.accent : Theme.warning))
            }
            SoundBoard.play(isQuestion ? .question : .permission)

        case "Notification":
            let type = payload["notification_type"] as? String ?? ""
            let needsYou: Set<String> = ["permission_prompt", "idle_prompt", "elicitation_dialog", "agent_needs_input"]
            if type.isEmpty || needsYou.contains(type) {
                if session.status != .finished || type == "permission_prompt" {
                    session.status = .waiting
                }
                if let text = payload["message"] as? String {
                    session.summary = ClaudeCodeMonitor.oneLine(text, max: 140)
                }
            }

        case "Stop":
            clearApprovals(for: sessionID)
            session.status = .finished
            if let text = payload["last_assistant_message"] as? String, !text.isEmpty {
                session.summary = ClaudeCodeMonitor.oneLine(text, max: 180)
            }
            // Solo avisamos de tareas de verdad: las que tardaron un rato (se cambia en Configuración).
            let minimum = UserDefaults.standard.object(forKey: SettingsKeys.minTaskSeconds) as? Double ?? 10
            let worked = session.turnStarted.map { Date().timeIntervalSince($0) }
            let isTask = worked.map { $0 >= minimum } ?? true
            if let requestID = message.requestID {
                if isTask {
                    finishedHold = startReplyHold(requestID, session: session)
                } else {
                    server.respond(requestID, with: nil)
                }
            }
            finished = isTask
            if isTask { SoundBoard.play(.finished) }

        case "SessionEnd":
            if replyHold?.sessionID == sessionID {
                releaseReplyHold(reason: nil)
            }
            sessions.removeAll { $0.id == sessionID }
            clearApprovals(for: sessionID)
            updateLive()
            return

        default:
            break
        }

        upsert(session)
        if finished {
            onFinished?(session, finishedHold)
        }
    }

    // MARK: Responder por voz cuando termina

    private func startReplyHold(_ requestID: String, session: ClaudeSession) -> ReplyHold? {
        let defaults = UserDefaults.standard
        let onlyAway = defaults.object(forKey: SettingsKeys.replyOnlyAway) as? Bool ?? true
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let lookingAtTerminal = session.terminalBundle != nil && front == session.terminalBundle
        let voiceReady = canReplyByVoice?() ?? false

        // Sin app de terminal (por ejemplo `claude -p` en un script) no hay a quién esperar.
        let hasTerminal = session.terminalBundle?.isEmpty == false
        guard replyEnabled, voiceReady, hasTerminal, !(onlyAway && lookingAtTerminal) else {
            server.respond(requestID, with: nil) // Claude Code termina al instante, como siempre
            return nil
        }
        if let previous = replyHold {
            server.respond(previous.id, with: nil)
        }
        let configured = defaults.object(forKey: SettingsKeys.replyWait) as? Double ?? 20
        let wait = min(max(configured, 5), 90)
        let hold = ReplyHold(
            id: requestID,
            sessionID: session.id,
            project: session.project,
            summary: session.summary,
            started: Date(),
            deadline: Date().addingTimeInterval(wait)
        )
        replyHold = hold
        onReplyHoldChanged?(hold)
        IslaLog.shared.add("\(session.project) terminó: te espero \(Int(wait)) s por si le respondes (di “responde…”)")
        watchReplyHold(requestID)
        return hold
    }

    private func watchReplyHold(_ requestID: String) {
        Task { [weak self] in
            while true {
                try? await Task.sleep(nanoseconds: 400_000_000)
                guard let strongSelf = self, let hold = strongSelf.replyHold, hold.id == requestID else { return }
                if !strongSelf.server.isWaiting(requestID) {
                    // Claude Code dejó de esperar (lo cancelaste, o la sesión se abrió antes de actualizar Isla).
                    strongSelf.releaseReplyHold(reason: "Claude Code ya no estaba esperando respuesta")
                    return
                }
                let now = Date()
                if now < hold.deadline { continue }
                // Si estás dictando la respuesta te esperamos (hasta el límite que da Claude Code).
                if strongSelf.isDictatingReply?() == true && now.timeIntervalSince(hold.started) < 105 { continue }
                strongSelf.releaseReplyHold(reason: "Nadie respondió: Claude Code sigue normal")
                return
            }
        }
    }

    /// Deja que Claude Code termine como siempre (sin respuesta).
    func releaseReplyHold(reason: String?) {
        guard let hold = replyHold else { return }
        server.respond(hold.id, with: nil)
        replyHold = nil
        onReplyHoldChanged?(nil)
        if let reason = reason {
            IslaLog.shared.add(reason)
        }
    }

    /// Manda lo que dictaste a la sesión que acaba de terminar: Claude sigue trabajando con eso.
    /// Devuelve false si ya no había ninguna sesión esperando.
    @discardableResult
    func sendReply(_ text: String) -> Bool {
        guard let hold = replyHold else { return false }
        guard server.isWaiting(hold.id) else {
            releaseReplyHold(reason: "Claude Code ya no estaba esperando respuesta")
            return false
        }
        let object: [String: Any] = [
            "decision": "block",
            "reason": "El usuario te respondió por voz desde Isla: \(text)"
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let json = String(data: data, encoding: .utf8) else { return false }
        server.respond(hold.id, with: json)
        replyHold = nil
        onReplyHoldChanged?(nil)

        if let index = sessions.firstIndex(where: { $0.id == hold.sessionID }) {
            sessions[index].status = .thinking
            sessions[index].turnStarted = Date()
            sessions[index].prompt = ClaudeCodeMonitor.oneLine(text, max: 110)
            sessions[index].summary = nil
            sessions[index].updated = Date()
        }
        updateLive()
        IslaLog.shared.add("Respuesta enviada a \(hold.project) ✓")
        return true
    }

    /// Si abres la terminal de esa sesión, le regresamos el control a Claude Code de inmediato.
    func appActivated(_ bundleID: String?) {
        guard let hold = replyHold, let bundleID = bundleID,
              let session = sessions.first(where: { $0.id == hold.sessionID }),
              session.terminalBundle == bundleID else { return }
        releaseReplyHold(reason: "Abriste la terminal: Claude Code sigue normal")
    }

    private func upsert(_ session: ClaudeSession) {
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        } else {
            sessions.append(session)
        }
        sessions.sort { $0.updated > $1.updated }
        if sessions.count > 6 {
            sessions.removeLast(sessions.count - 6)
        }
        updateLive()
    }

    // MARK: Permisos

    private func clearApprovals(for sessionID: String) {
        let stale = approvals.filter { $0.sessionID == sessionID }
        guard !stale.isEmpty else { return }
        for approval in stale {
            server.respond(approval.id, with: nil)
        }
        approvals.removeAll { $0.sessionID == sessionID }
    }

    func decide(_ approval: ClaudeApproval, _ decision: ApprovalDecision) {
        // Si ya se había resuelto (se acabó el tiempo, lo contestaste en otro lado), no hacemos nada.
        guard approvals.contains(where: { $0.id == approval.id }) else { return }
        let response: String?
        switch decision {
        case .allow:
            response = ClaudeCodeMonitor.decisionJSON(["behavior": "allow"])
        case .always:
            var body: [String: Any] = ["behavior": "allow"]
            if let data = approval.suggestions,
               let suggestions = try? JSONSerialization.jsonObject(with: data) {
                body["updatedPermissions"] = suggestions
            }
            response = ClaudeCodeMonitor.decisionJSON(body)
        case .deny:
            response = ClaudeCodeMonitor.decisionJSON(["behavior": "deny", "message": "El usuario lo negó desde Isla."])
        case .terminal:
            response = nil
        }
        server.respond(approval.id, with: response)
        approvals.removeAll { $0.id == approval.id }

        if let index = sessions.firstIndex(where: { $0.id == approval.sessionID }) {
            sessions[index].status = decision == .terminal ? .waiting : .working
            sessions[index].updated = Date()
        }
        updateLive()
    }

    /// Contestaste la pregunta de Claude en la isla: se la regresamos a Claude Code.
    /// `answers`: texto de cada pregunta → la opción elegida (varias, separadas por comas) o lo que escribiste.
    func answer(_ approval: ClaudeApproval, answers: [String: String]) {
        guard approvals.contains(where: { $0.id == approval.id }) else { return }
        guard approval.isQuestion, !answers.isEmpty, let data = approval.toolInput,
              var input = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            decide(approval, .terminal)
            return
        }
        input["answers"] = answers
        let response = ClaudeCodeMonitor.decisionJSON(["behavior": "allow", "updatedInput": input])
        server.respond(approval.id, with: response)
        approvals.removeAll { $0.id == approval.id }
        if let index = sessions.firstIndex(where: { $0.id == approval.sessionID }) {
            sessions[index].status = .thinking
            sessions[index].updated = Date()
        }
        updateLive()
        let summary = approval.questions.compactMap { answers[$0.text] }.joined(separator: " · ")
        IslaLog.shared.add("Le contesté a \(approval.project): \(ClaudeCodeMonitor.oneLine(summary, max: 120))")
    }

    /// Si no eliges a tiempo (30 s por defecto; se cambia en Configuración),
    /// Claude Code te pregunta en la terminal como siempre. Las preguntas esperan al menos 2 minutos.
    private func scheduleTimeout(for requestID: String, question: Bool = false) {
        Task { [weak self] in
            let configured = UserDefaults.standard.object(forKey: SettingsKeys.approvalTimeout) as? Double ?? 30
            let minimum: Double = question ? 120 : 10
            let seconds = min(max(configured, minimum), 240)
            var deadline = Date().addingTimeInterval(seconds)
            while Date() < deadline {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let strongSelf = self,
                      strongSelf.approvals.contains(where: { $0.id == requestID }) else { return }
                // Estás escribiendo tu respuesta: te esperamos.
                if strongSelf.promptOpen.contains(requestID) {
                    deadline = max(deadline, Date().addingTimeInterval(15))
                }
                // Si lo cancelaste en la terminal (Esc), quitamos la tarjeta.
                if !strongSelf.server.isWaiting(requestID) {
                    strongSelf.server.respond(requestID, with: nil)
                    strongSelf.approvals.removeAll { $0.id == requestID }
                    strongSelf.updateLive()
                    return
                }
            }
            guard let strongSelf = self,
                  let approval = strongSelf.approvals.first(where: { $0.id == requestID }) else { return }
            strongSelf.decide(approval, .terminal)
        }
    }

    private static func decisionJSON(_ decision: [String: Any]) -> String? {
        let object: [String: Any] = [
            "hookSpecificOutput": [
                "hookEventName": "PermissionRequest",
                "decision": decision
            ]
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: Abrir la terminal de una sesión

    static let lastTerminalKey = "claudeLastTerminal"

    /// Terminales donde Isla puede escribir sin riesgo (en editores el texto caería en un archivo).
    static let typableTerminals: Set<String> = [
        "com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable", "com.mitchellh.ghostty",
        "net.kovidgoyal.kitty", "io.alacritty", "org.alacritty", "com.github.wez.wezterm"
    ]

    /// ¿Hay una sesión de Claude Code (vista en las últimas horas) corriendo en esa app?
    func hasSession(inTerminal bundle: String) -> Bool {
        sessions.contains { $0.terminalBundle == bundle && Date().timeIntervalSince($0.updated) < 6 * 3600 }
    }

    /// Tu sesión más reciente de Claude Code en una terminal donde Isla puede escribir.
    var latestTerminalSession: ClaudeSession? {
        sessions.first { session in
            guard let bundle = session.terminalBundle, ClaudeCodeMonitor.typableTerminals.contains(bundle) else { return false }
            return Date().timeIntervalSince(session.updated) < 6 * 3600
                && !NSRunningApplication.runningApplications(withBundleIdentifier: bundle).isEmpty
        }
    }

    /// La última sesión que terminó una tarea (para escribirle tu respuesta).
    var lastFinishedSession: ClaudeSession? {
        sessions.first { $0.status == .finished || $0.status == .waiting }
    }

    /// Terminales conocidas, por si no sabemos cuál usas.
    private static let knownTerminals = [
        "com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable", "com.mitchellh.ghostty",
        "net.kovidgoyal.kitty", "io.alacritty", "com.github.wez.wezterm", "com.microsoft.VSCode",
        "com.todesktop.230313mzl4w4u92"
    ]

    @discardableResult
    func openTerminal(for session: ClaudeSession) -> String? {
        if let bundle = session.terminalBundle, !bundle.isEmpty, bundle != ClaudeChat.desktopBundleID,
           !NSRunningApplication.runningApplications(withBundleIdentifier: bundle).isEmpty,
           AppActivator.bringToFront(bundle) {
            // Directo a la pestaña de esa sesión (Terminal e iTerm2), si lo activaste.
            if TerminalJump.enabled, let tty = session.tty, TerminalJump.supports(bundle) {
                let project = session.project
                Task { @MainActor in
                    if await TerminalJump.focus(tty: tty, bundle: bundle) {
                        IslaLog.shared.add("Fui a la pestaña de \(project) ✓")
                    }
                }
            }
            return bundle
        }
        return openTerminal()
    }

    /// "Oye Claudio, terminal": la terminal de tu sesión más reciente; si no hay sesiones,
    /// la última terminal donde usaste Claude Code, cualquier terminal abierta o Terminal.
    /// Devuelve cuál abrió.
    @discardableResult
    func openTerminal() -> String? {
        let isRunning: (String) -> Bool = { !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty }
        let fromSessions = sessions.compactMap { $0.terminalBundle }
            .filter { !$0.isEmpty && $0 != ClaudeChat.desktopBundleID && isRunning($0) }
        let last = UserDefaults.standard.string(forKey: ClaudeCodeMonitor.lastTerminalKey).map { [$0] } ?? []
        let open = ClaudeCodeMonitor.knownTerminals.filter(isRunning)
        for bundle in fromSessions + last + open + ["com.apple.Terminal"] where AppActivator.bringToFront(bundle) {
            return bundle
        }
        onPeek?(Peek(symbol: "questionmark.circle", title: "No encontré la terminal", tint: Theme.warning))
        return nil
    }

    func openTerminal(forApproval approval: ClaudeApproval) {
        if let session = sessions.first(where: { $0.id == approval.sessionID }) {
            openTerminal(for: session)
        } else {
            openTerminal()
        }
    }

    // MARK: Actividad en vivo junto al notch

    private func updateLive() {
        let activity: LiveActivity?
        if let approval = approvals.first {
            activity = LiveActivity(statuses: [.waiting], title: approval.isQuestion ? "Pregunta" : "Permiso",
                                    subtitle: approval.project, tint: approval.isQuestion ? Theme.accent : Theme.warning)
        } else if !liveEnabled {
            activity = nil
        } else if let active = sessions.first(where: { $0.status.isActive }) {
            let visible = sessions.filter { $0.status.isActive || $0.status == .waiting }
            let title: String
            let subtitle: String
            if activeCount > 1 {
                title = "\(activeCount) sesiones"
                subtitle = active.project
            } else if active.status == .thinking {
                title = "Pensando…"
                subtitle = active.project
            } else {
                title = active.steps.last?.verb ?? "Trabajando"
                if let last = active.steps.last, !last.detail.isEmpty {
                    subtitle = last.detail
                } else {
                    subtitle = active.project
                }
            }
            activity = LiveActivity(statuses: visible.prefix(3).map { $0.status }, title: title,
                                    subtitle: subtitle, tint: Theme.accent)
        } else if let waiting = sessions.first(where: { $0.status == .waiting }) {
            activity = LiveActivity(statuses: [.waiting], title: "Te espera",
                                    subtitle: waiting.project, tint: Theme.warning)
        } else {
            activity = nil
        }
        onLive?(activity)
    }

    /// Limpia sesiones viejas.
    private func prune() {
        let now = Date()
        var changed = false
        sessions.removeAll { session in
            let stale = now.timeIntervalSince(session.updated) > 3 * 3600
            if stale { changed = true }
            return stale
        }
        for index in sessions.indices {
            let age = now.timeIntervalSince(sessions[index].updated)
            if sessions[index].status == .finished && age > 30 * 60 {
                sessions[index].status = .idle
                changed = true
            } else if sessions[index].status.isActive && age > 20 * 60 {
                sessions[index].status = .idle   // se perdió un aviso: no lo dejamos "trabajando" para siempre
                changed = true
            }
        }
        if changed { updateLive() }
    }

    // MARK: Textos

    static func projectName(from cwd: String) -> String {
        let name = URL(fileURLWithPath: cwd).lastPathComponent
        return name.isEmpty || name == "/" ? "Claude Code" : name
    }

    static func oneLine(_ text: String, max: Int) -> String {
        let collapsed = text
            .prefix(2000)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return collapsed.count > max ? String(collapsed.prefix(max)) + "…" : collapsed
    }

    static func describe(tool: String, input: [String: Any]) -> ClaudeStep {
        let verb: String
        let symbol: String
        switch tool {
        case "Read": verb = "Lee"; symbol = "doc.text"
        case "Write": verb = "Crea"; symbol = "doc.badge.plus"
        case "Edit", "MultiEdit": verb = "Edita"; symbol = "pencil"
        case "NotebookEdit": verb = "Edita notebook"; symbol = "pencil"
        case "Bash": verb = "Ejecuta"; symbol = "terminal"
        case "Glob": verb = "Busca archivos"; symbol = "magnifyingglass"
        case "Grep": verb = "Busca"; symbol = "magnifyingglass"
        case "LS": verb = "Revisa carpeta"; symbol = "folder"
        case "WebSearch": verb = "Busca en la web"; symbol = "globe"
        case "WebFetch": verb = "Abre página"; symbol = "globe"
        case "Task", "Agent": verb = "Agente"; symbol = "person.2"
        case "TodoWrite": verb = "Planea"; symbol = "checklist"
        case "AskUserQuestion": verb = "Te pregunta"; symbol = "questionmark.bubble"
        case "ExitPlanMode": verb = "Plan listo"; symbol = "list.bullet.clipboard"
        default:
            if tool.hasPrefix("mcp__") {
                let parts = tool.components(separatedBy: "__")
                verb = parts.count >= 3 ? "\(parts[1]) · \(parts[2])" : tool
                symbol = "puzzlepiece.extension"
            } else {
                verb = tool
                symbol = "wrench.and.screwdriver"
            }
        }

        var detail = ""
        if let command = input["command"] as? String {
            detail = oneLine(command, max: 70)
        } else if let path = (input["file_path"] as? String) ?? (input["notebook_path"] as? String) ?? (input["path"] as? String) {
            detail = URL(fileURLWithPath: path).lastPathComponent
        } else if let pattern = (input["pattern"] as? String) ?? (input["query"] as? String) {
            detail = oneLine(pattern, max: 60)
        } else if let url = input["url"] as? String {
            detail = URL(string: url)?.host ?? oneLine(url, max: 60)
        } else if let description = input["description"] as? String {
            detail = oneLine(description, max: 60)
        } else if let questions = input["questions"] as? [[String: Any]],
                  let first = questions.first?["question"] as? String {
            detail = oneLine(first, max: 70)
        }
        return ClaudeStep(symbol: symbol, verb: verb, detail: detail)
    }
}

/// Trae una app al frente (o la abre), aunque Isla esté en segundo plano.
@MainActor
enum AppActivator {
    /// false si la app no está instalada.
    @discardableResult
    static func bringToFront(_ bundleID: String) -> Bool {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
        guard let url = running?.bundleURL ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return false
        }
        let name = running?.localizedName ?? url.deletingPathExtension().lastPathComponent
        IslaLog.shared.add("Abriendo \(name)")
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration, completionHandler: nil)

        // Si macOS no la trajo al frente, insistimos (y como último recurso, con AppleScript).
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier != bundleID,
                  let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { return }
            app.unhide()
            app.activate(options: [.activateAllWindows])
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier != bundleID else { return }
            // Último recurso: AppleScript en otro proceso (así nunca se traba la isla).
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", "with timeout of 5 seconds", "-e", "tell application id \"\(bundleID)\" to activate",
                                 "-e", "end timeout"]
            process.terminationHandler = { finished in
                let ok = finished.terminationStatus == 0
                Task { @MainActor in
                    IslaLog.shared.add(ok ? "Traje \(name) al frente" : "macOS no dejó traer \(name) al frente")
                }
            }
            try? process.run()
        }
        return true
    }
}

/// Va a la pestaña exacta de una sesión (por su "tty"): Terminal e iTerm2.
/// Ghostty y Warp no dejan elegir pestañas desde fuera: con ellas solo traemos la app al frente.
enum TerminalJump {
    /// Apagado de fábrica (Configuración › Claude Code).
    static let enabledKey = "claudeExactTab"

    static var enabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? false
    }

    static func supports(_ bundle: String) -> Bool {
        bundle == "com.apple.Terminal" || bundle == "com.googlecode.iterm2"
    }

    /// true si encontró la pestaña y la puso al frente.
    static func focus(tty: String, bundle: String) async -> Bool {
        let safe = tty.replacingOccurrences(of: "\"", with: "")
        let script: String
        switch bundle {
        case "com.apple.Terminal":
            script = """
            tell application id "com.apple.Terminal"
                repeat with w in windows
                    repeat with t in tabs of w
                        try
                            if (tty of t) is "\(safe)" then
                                set selected of t to true
                                set index of w to 1
                                activate
                                return "found"
                            end if
                        end try
                    end repeat
                end repeat
                return "none"
            end tell
            """
        case "com.googlecode.iterm2":
            script = """
            tell application id "com.googlecode.iterm2"
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            try
                                if (tty of s) is "\(safe)" then
                                    tell w to select
                                    tell t to select
                                    tell s to select
                                    activate
                                    return "found"
                                end if
                            end try
                        end repeat
                    end repeat
                end repeat
                return "none"
            end tell
            """
        default:
            return false
        }
        return await ScriptRunner.run(script, timeout: 5) == "found"
    }
}

/// Encuentra la pestaña de Terminal (la de macOS) donde corre Claude Code, aunque Isla
/// no haya visto todavía ningún aviso de esa sesión, y la pone al frente.
enum TerminalFinder {
    static let terminalID = "com.apple.Terminal"

    enum Result {
        case found, notFound, noPermission
    }

    static func focusClaudeTab() async -> Result {
        let script = """
        tell application id "com.apple.Terminal"
            repeat with w in windows
                repeat with t in tabs of w
                    try
                        repeat with p in (processes of t)
                            if (p as string) contains "claude" then
                                set selected of t to true
                                set index of w to 1
                                activate
                                return "found"
                            end if
                        end repeat
                    end try
                end repeat
            end repeat
            return "none"
        end tell
        """
        guard let output = await runAppleScript(script, timeout: 5) else { return .noPermission }
        return output == "found" ? .found : .notFound
    }

    /// Corre AppleScript en otro proceso (así la isla nunca se traba). nil si falló o no hubo permiso.
    private static func runAppleScript(_ script: String, timeout: Double) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                process.arguments = ["-e", script]
                let output = Pipe()
                process.standardOutput = output
                process.standardError = Pipe()
                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: nil)
                    return
                }
                let deadline = Date().addingTimeInterval(timeout)
                while process.isRunning && Date() < deadline {
                    usleep(50_000)
                }
                if process.isRunning {
                    process.terminate()
                    continuation.resume(returning: nil)
                    return
                }
                let data = output.fileHandleForReading.readDataToEndOfFile()
                let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                continuation.resume(returning: process.terminationStatus == 0 ? text : nil)
            }
        }
    }
}
