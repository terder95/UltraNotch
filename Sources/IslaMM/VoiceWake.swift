import AppKit
import AVFoundation
import Speech
import Combine

/// Para quién es lo que estás dictando.
enum DictationTarget: Equatable {
    /// Chat nuevo, Cowork, Claude Code o uno de tus proyectos.
    case claude(ClaudeDestination)
    /// Respuesta para la sesión de Claude Code que acaba de terminar.
    case reply
    /// Se escribe en la terminal que está al frente (y se da Enter).
    case terminal
    /// Chat nuevo en ChatGPT (la app de Mac o chatgpt.com).
    case chatGPT

    var label: String {
        switch self {
        case .claude(let destination): return destination.label
        case .reply: return "tu respuesta a Claude Code"
        case .terminal: return "la terminal"
        case .chatGPT: return "ChatGPT"
        }
    }
}

/// Lo que puedes decir después de la frase para despertar ("Oye Claudio").
enum VoiceCommand: Equatable {
    case open, allow, always, deny, terminal, shelf, clipboard, mac, close, ignore, keepAwake
    /// Pestaña Hoy y controles de la música.
    case today, musicPlayPause, musicNext, musicPrevious
    /// Terminaste de dictar. El texto es nil si no dijiste nada.
    case dictated(DictationTarget, String?)
    /// Dijiste "cancela" al final del dictado: no se manda nada.
    case cancelled
}

/// Escucha la frase para despertar con el reconocimiento de voz de la Mac,
/// 100 % local (el audio no sale de tu computadora). Mientras está activo,
/// macOS muestra el punto naranja del micrófono en la barra de menús.
@MainActor
final class VoiceWake: ObservableObject {
    enum State: Equatable {
        case off
        case needsPermission
        case unavailable(String)
        case listening
        /// Lista, pero con el micrófono apagado: solo escucha mientras mantienes ⌥ (o tocas "Responder").
        case standby
    }

    enum Phase: Equatable {
        case idle             // esperando la frase para despertar
        case awaitingCommand  // ya te oyó; esperando la orden
        case dictating        // dictando un mensaje
    }

    @Published private(set) var state: State = .off
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var lastHeard = ""
    @Published private(set) var dictation = ""
    @Published private(set) var dictationTarget: DictationTarget?
    /// true mientras una sesión de Claude Code espera tu respuesta ("responde…").
    @Published private(set) var replyWindowOpen = false

    // MARK: Ajustes (se guardan solos)

    @Published var enabled = true {
        didSet {
            UserDefaults.standard.set(enabled, forKey: Keys.enabled)
            if enabled { start() } else { stop() }
        }
    }
    /// Una o varias frases separadas por comas.
    @Published var wakePhrases = VoiceWake.defaultPhrases {
        didSet {
            UserDefaults.standard.set(wakePhrases, forKey: Keys.phrases)
            rebuildWakeRegex()
            scheduleSettingsRestart()
        }
    }
    @Published var localeID = "es-MX" {
        didSet {
            UserDefaults.standard.set(localeID, forKey: Keys.locale)
            scheduleSettingsRestart()
        }
    }
    /// Segundos para decir la orden después de la frase.
    @Published var commandWindow: Double = 10 {
        didSet { UserDefaults.standard.set(commandWindow, forKey: Keys.window) }
    }
    /// Segundos de silencio que terminan un dictado.
    @Published var silenceSeconds: Double = 2 {
        didSet { UserDefaults.standard.set(silenceSeconds, forKey: Keys.silence) }
    }
    /// Escuchar siempre la frase para despertar. Apagado: el micrófono solo se prende mientras
    /// mantienes ⌥ derecha (o tocas "Responder").
    @Published var alwaysListen = true {
        didSet {
            UserDefaults.standard.set(alwaysListen, forKey: Keys.always)
            guard enabled, state == .listening || state == .standby else { return }
            if alwaysListen {
                beginListening()
            } else if phase == .idle && !holdingKey {
                goStandby()
            }
        }
    }

    /// Se llama al oír la frase (con .open) y luego con la orden o el dictado.
    var onCommand: ((VoiceCommand) -> Void)?
    /// El micrófono no respondió (para avisarte en la isla).
    var onMicrophoneProblem: ((String) -> Void)?
    /// Empezaste a dictar (para abrir la isla y que veas el texto).
    var onDictationStarted: ((DictationTarget) -> Void)?

    static let defaultPhrases = "oye claudio, hey claudio"
    /// La misma llave que usa el aviso de Claude Code para saber si la voz está encendida.
    nonisolated static let enabledKey = "voiceWake"

    private enum Keys {
        static let enabled = VoiceWake.enabledKey
        static let phrases = "voicePhrases"
        static let locale = "voiceLocale"
        static let window = "voiceCommandWindow"
        static let silence = "voiceSilence"
        static let always = "voiceAlwaysListen"
    }

    // MARK: Estado interno

    private var recognizer: SFSpeechRecognizer?
    private var recognizerLocale = ""
    /// Se vuelve a crear si cambias de micrófono o audífonos (el viejo puede quedar inservible).
    /// El motor de audio (se crea en la fila del micrófono: crearlo también le pregunta cosas a macOS).
    private var engine: AVAudioEngine?
    private var engineNeedsReset = false
    /// Todo lo del micrófono corre en su propia fila, nunca en el hilo que dibuja la isla:
    /// si el servicio de audio de macOS (coreaudiod) se atora, la isla sigue funcionando.
    private var audioQueue = DispatchQueue(label: "isla.microfono", qos: .userInitiated)
    /// El micrófono está prendido y mandando audio.
    private var audioRunning = false
    /// Preparando el micrófono (en su fila).
    private var audioPending = false
    private var audioAttempt = 0
    /// Veces seguidas que macOS no contestó (para esperar cada vez más).
    private var stuckCount = 0
    /// Quién espera a que el micrófono quede listo (la tecla ⌥, "Responder"…).
    private var readyCallbacks: [(Bool) -> Void] = []
    /// El audio va al reconocimiento actual: así cambiamos de reconocimiento sin tocar el micrófono.
    private let feed = RecognitionFeed()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var tapInstalled = false
    private var generation = 0
    private var restartTask: Task<Void, Never>?
    private var renewalTask: Task<Void, Never>?
    private var settingsRestartTask: Task<Void, Never>?
    private var watchdogTask: Task<Void, Never>?
    private var wakeRegex: NSRegularExpression?
    private var lastWake = Date.distantPast
    private var phaseDeadline = Date.distantPast
    private var anchorOffset = 0
    /// La palabra clave que inició el dictado ("nuevo chat", "gorgias"…), para reubicarla.
    private var anchorPattern: NSRegularExpression?
    private var replyAnchor = 0
    /// Nunca reubicamos la palabra clave antes de este punto (la frase para despertar, etc.).
    private var anchorFloor = 0
    private var lastChange = Date()
    private var lastNormalized = ""
    /// Apple borra lo escuchado tras una pausa (sin avisar): aquí guardamos lo anterior
    /// para que la frase completa ("Oye Claudio … Gorgias … tu mensaje") no se pierda.
    private var baseRaw = ""
    private var segmentRaw = ""
    private var segmentNormalized = ""
    private let activity = VoiceActivity()
    private var startedAt = Date.distantPast
    private var quickFailures = 0
    private var speechDenied = false
    private var configObserver: NSObjectProtocol?
    private var projectCacheKey = "-"
    /// Cuándo oyó la frase (o apretaste la tecla), para medir cuánto tarda en entender la orden.
    private var heardAt: Date?
    /// Estás manteniendo la tecla para hablar.
    private(set) var holdingKey = false
    private var projectPatterns: [(DictationTarget, NSRegularExpression)] = []

    private var log: IslaLog { IslaLog.shared }

    init() {
        // Modo capturas: sin micrófono ni tus frases (se ve como si estuviera escuchando).
        if ModoCapturas.activo {
            state = .listening
            return
        }
        let defaults = UserDefaults.standard
        enabled = defaults.object(forKey: Keys.enabled) as? Bool ?? true
        wakePhrases = defaults.string(forKey: Keys.phrases) ?? VoiceWake.defaultPhrases
        localeID = defaults.string(forKey: Keys.locale) ?? "es-MX"
        commandWindow = defaults.object(forKey: Keys.window) as? Double ?? 10
        silenceSeconds = defaults.object(forKey: Keys.silence) as? Double ?? 2
        alwaysListen = defaults.object(forKey: Keys.always) as? Bool ?? true
        rebuildWakeRegex()
        observeEngine()
    }

    /// Si cambias de micrófono o audífonos, macOS avisa: rehacemos el audio desde cero.
    private func observeEngine() {
        if let old = configObserver {
            NotificationCenter.default.removeObserver(old)
        }
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let changed = (note.object as? AVAudioEngine).map { ObjectIdentifier($0) }
            Task { @MainActor in
                // Solo nos importa el motor que estamos usando.
                guard let strongSelf = self, strongSelf.enabled,
                      let current = strongSelf.engine, changed == ObjectIdentifier(current) else { return }
                strongSelf.engineNeedsReset = true
                // Algunos audífonos Bluetooth avisan cambios al reiniciar: esperamos más para no ciclarnos.
                strongSelf.restart(after: Date().timeIntervalSince(strongSelf.startedAt) < 3 ? 5 : 1)
            }
        }
    }

    private func playTink() {
        let sound = NSSound(named: NSSound.Name("Tink"))
        sound?.volume = 0.35 // bajito, para que el micrófono casi no lo oiga
        sound?.play()
    }

    /// Texto de la primera frase, para mostrarla en la isla ("Oye Claudio").
    var displayPhrase: String {
        let first = wakePhrases.split(separator: ",").first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
        return first.isEmpty ? "Oye Claudio" : first.capitalized
    }

    var isReady: Bool {
        enabled && (state == .listening || state == .standby)
    }

    var isDictatingReply: Bool {
        phase == .dictating && dictationTarget == .reply
    }

    // MARK: Encender / apagar

    func start() {
        guard enabled else { return }
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor in
                guard let strongSelf = self else { return }
                guard status == .authorized else {
                    strongSelf.speechDenied = true
                    strongSelf.state = .needsPermission
                    return
                }
                strongSelf.speechDenied = false
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    Task { @MainActor in
                        guard let strongSelf = self else { return }
                        if granted {
                            if strongSelf.alwaysListen {
                                strongSelf.beginListening()
                            } else {
                                strongSelf.goStandby()
                            }
                        } else {
                            strongSelf.state = .needsPermission
                        }
                    }
                }
            }
        }
    }

    func stop() {
        restartTask?.cancel()
        renewalTask?.cancel()
        watchdogTask?.cancel()
        stopAudio()
        phase = .idle
        dictation = ""
        dictationTarget = nil
        state = .off
    }

    /// Abre Ajustes en el permiso que falta (reconocimiento de voz o micrófono).
    func openPrivacySettings() {
        let pane = speechDenied ? "Privacy_SpeechRecognition" : "Privacy_Microphone"
        let link = "x-apple.systempreferences:com.apple.preference.security?\(pane)"
        if let url = URL(string: link) {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Respuestas a Claude Code

    /// Una sesión terminó y espera: basta con decir "responde…" (sin la frase para despertar).
    func openReplyWindow() {
        replyWindowOpen = true
        replyAnchor = lastNormalized.count
    }

    func closeReplyWindow() {
        replyWindowOpen = false
    }

    /// Entiende un texto (por ejemplo, lo que dijiste con la tecla ⌥) igual que lo que dices después de
    /// "Oye Claudio": "a Gorgias …", "terminal …", "responde …", "permitir"… nil si no hay orden.
    func interpret(_ raw: String, remote: Bool = true) -> VoiceCommand? {
        let normalized = VoiceWake.normalize(raw)
        // Si empieza con la frase para despertar, la saltamos.
        var start = 0
        if let wakeEnd = wakePhraseEnd(in: normalized, from: 0),
           VoiceWake.prefix(of: normalized, count: wakeEnd).split(separator: " ").count <= 3 {
            start = wakeEnd
        }
        let tail = VoiceWake.suffix(of: normalized, from: start)
        if tail.trimmingCharacters(in: .whitespaces).isEmpty { return .open }
        if let hit = firstKeyword(in: tail, strict: remote) {
            let message = VoiceWake.suffix(of: raw, from: start + hit.end)
                .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
            return .dictated(hit.target, message.isEmpty ? nil : message)
        }
        // Órdenes cortas ("permitir", "negar", "modo programación"); un texto largo es un mensaje.
        if tail.split(separator: " ").count <= 3, let command = VoiceWake.command(in: tail) {
            return command
        }
        return nil
    }

    /// Deja de dictar sin mandar nada (por ejemplo, si había un permiso pendiente).
    func cancelDictation() {
        guard phase == .dictating else { return }
        finishPhase()
        restart(after: 0.4)
    }

    /// Empieza a dictar sin palabra clave (por ejemplo, desde el botón "Responder").
    @discardableResult
    func startDictation(for target: DictationTarget) -> Bool {
        guard isReady else { return false }
        watchdogTask?.cancel()
        var failed = false
        // Escucha limpia: solo cuenta lo que digas a partir de ahora.
        beginListening { [weak self] ready in
            guard let strongSelf = self else { return }
            guard ready else {
                failed = true
                strongSelf.onMicrophoneProblem?("El micrófono no respondió")
                return
            }
            strongSelf.playTink()
            strongSelf.beginDictation(target, anchor: 0, floor: 0, pattern: nil)
        }
        return !failed
    }

    // MARK: Tecla para hablar (⌥ derecha)

    /// Empezaste a mantener la tecla: escucha sin esperar la frase para despertar.
    @discardableResult
    func holdToTalkBegan() -> Bool {
        guard isReady else { return false }
        guard !holdingKey else { return true }
        holdingKey = true
        watchdogTask?.cancel()
        if phase != .idle { finishPhase() }
        // Escucha limpia: solo cuenta lo que digas mientras la mantienes. Si el micrófono estaba
        // apagado, se prende (el "tink" te avisa cuando ya te escucha).
        beginListening { [weak self] ready in
            guard let strongSelf = self else { return }
            guard ready else {
                strongSelf.holdingKey = false
                strongSelf.log.add("Tecla para hablar: el micrófono no respondió")
                strongSelf.onMicrophoneProblem?("El micrófono no respondió")
                return
            }
            guard strongSelf.holdingKey else {
                // Soltaste la tecla antes de que el micrófono estuviera listo.
                strongSelf.restart(after: 0.2)
                return
            }
            strongSelf.playTink()
            strongSelf.heardAt = Date()
            strongSelf.log.add("Tecla para hablar: te escucho…")
            strongSelf.enter(.awaitingCommand, seconds: 120)
            strongSelf.onCommand?(.open)
        }
        return holdingKey
    }

    /// Soltaste la tecla: entendemos lo que dijiste (después de un instante, por lo último que llegue).
    func holdToTalkEnded() {
        guard holdingKey else { return }
        holdingKey = false
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 450_000_000)
            self?.finishHold()
        }
    }

    /// Escribiste algo mientras mantenías la tecla: era un atajo, no para hablar.
    func cancelHold() {
        guard holdingKey || phase != .idle else { return }
        holdingKey = false
        finishPhase()
        log.add("Tecla para hablar: cancelado (escribiste con la tecla)")
        restart(after: 0.4)
    }

    private func finishHold() {
        guard !holdingKey else { return } // la volviste a apretar
        switch phase {
        case .idle:
            return
        case .dictating:
            finishDictation()
        case .awaitingCommand:
            let text = (baseRaw + segmentRaw).trimmingCharacters(in: .whitespacesAndNewlines)
            finishPhase()
            if text.isEmpty {
                log.add("Tecla para hablar: no oí nada")
                onCommand?(.cancelled)
            } else if let command = interpret(text, remote: true), command != .open {
                log.add("Tecla para hablar: \(VoiceWake.describe(command))")
                onCommand?(command)
            } else {
                // Sin palabra clave: va a un chat nuevo de Claude.
                log.add("Tecla para hablar: “\(String(text.prefix(80)))” → chat nuevo")
                onCommand?(.dictated(.claude(.newChat), text))
            }
            restart(after: 0.4)
        }
    }

    // MARK: Escuchar

    /// Empieza (o renueva) la escucha. `then` se llama cuando el micrófono quedó listo (true) o si falló.
    private func beginListening(then completion: ((Bool) -> Void)? = nil) {
        guard enabled else {
            completion?(false)
            return
        }
        restartTask?.cancel() // que un reinicio pendiente no nos corte a media frase
        if recognizer == nil || recognizerLocale != localeID {
            recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeID))
            recognizerLocale = localeID
        }
        guard let recognizer = recognizer else {
            state = .unavailable("Tu Mac no tiene reconocimiento de voz para este idioma")
            completion?(false)
            return
        }
        guard recognizer.supportsOnDeviceRecognition else {
            state = .unavailable("Activa Dictado en este idioma (Ajustes › Teclado › Dictado)")
            completion?(false)
            return
        }

        // Un reconocimiento nuevo (Apple limita cada uno a ~1 minuto).
        task?.cancel()
        task = nil
        generation += 1
        let newRequest = makeRequest()
        request = newRequest
        feed.swap(to: newRequest)?.endAudio()

        // El micrófono ya está prendido: solo cambiamos de reconocimiento, sin tocar a macOS.
        if audioRunning && !engineNeedsReset && !audioPending {
            startRecognition(recognizer, newRequest, generation)
            completion?(true)
            return
        }
        if let completion = completion {
            readyCallbacks.append(completion)
        }
        // Si ya se está preparando, al terminar usa este reconocimiento nuevo.
        if !audioPending {
            prepareMicrophone()
        }
    }

    private func makeRequest() -> SFSpeechAudioBufferRecognitionRequest {
        let newRequest = SFSpeechAudioBufferRecognitionRequest()
        newRequest.shouldReportPartialResults = true
        newRequest.requiresOnDeviceRecognition = true
        newRequest.taskHint = .dictation
        let phrases = wakePhrases.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
        let projectNames = ProjectStore.shared.projects.map { $0.name }.filter { !$0.isEmpty }
        var hints: [String] = phrases + projectNames
        hints += ["nuevo chat", "Cowork", "Claude Code", "ChatGPT", "responde", "permitir", "siempre", "negar",
                  "terminal", "enviar"]
        // Tus palabras del diccionario personal también (nombres, marcas, términos).
        hints += PersonalDictionary.shared.recognitionHints
        newRequest.contextualStrings = hints
        return newRequest
    }

    private func startRecognition(_ recognizer: SFSpeechRecognizer,
                                  _ newRequest: SFSpeechAudioBufferRecognitionRequest, _ current: Int) {
        task = recognizer.recognitionTask(with: newRequest) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString ?? ""
            let isFinal = result?.isFinal ?? false
            let failed = error != nil
            Task { @MainActor in
                self?.process(text, isFinal: isFinal, failed: failed, generation: current)
            }
        }
        state = .listening
        anchorOffset = 0
        anchorFloor = 0
        replyAnchor = 0
        lastNormalized = ""
        baseRaw = ""
        segmentRaw = ""
        segmentNormalized = ""
        startedAt = Date()
        scheduleRenewal()
    }

    /// Prende el micrófono en su propia fila. Si macOS no contesta en 4 s, lo damos por atorado
    /// y lo reintentamos cada vez más espaciado (la isla nunca se congela esperándolo).
    private func prepareMicrophone() {
        if engineNeedsReset, let old = engine {
            // Cambiaste de micrófono o algo falló: empezamos con un motor de audio nuevo.
            let oldHadTap = tapInstalled
            audioQueue.async {
                _ = ObjC.attempt {
                    if old.isRunning { old.stop() }
                    if oldHadTap { old.inputNode.removeTap(onBus: 0) }
                }
            }
            engine = nil
        }
        if engine == nil {
            tapInstalled = false
            audioRunning = false
        }
        engineNeedsReset = false
        audioPending = true
        audioAttempt += 1
        let attempt = audioAttempt
        let existing = engine
        let hadTap = tapInstalled
        let queue = audioQueue
        let feed = self.feed
        let meter = activity
        // El micrófono de Apple lanza "excepciones" si cambiaste de audífonos a media escucha:
        // las atrapamos (si se escapan, Isla se cerraba sola minutos después).
        queue.async { [weak self] in
            let audioEngine = existing ?? AVAudioEngine()
            var outcome = MicrophoneSetup()
            let problem = ObjC.attempt {
                if audioEngine.isRunning { audioEngine.stop() }
                let input = audioEngine.inputNode
                if hadTap { input.removeTap(onBus: 0) }
                let format = input.outputFormat(forBus: 0)
                guard format.sampleRate > 0, format.channelCount > 0 else { return }
                outcome.hasMicrophone = true
                // format nil = el formato real del micrófono (evita el error si cambió).
                input.installTap(onBus: 0, bufferSize: 1024, format: nil) { buffer, _ in
                    feed.append(buffer)
                    meter.feed(buffer)
                }
                outcome.installed = true
                audioEngine.prepare()
                do {
                    try audioEngine.start()
                } catch {
                    outcome.startFailed = true
                }
            }
            outcome.problem = problem?.localizedDescription
            let result = outcome
            Task { @MainActor in
                self?.microphoneReady(result, attempt: attempt, engine: audioEngine, queue: queue)
            }
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            self?.microphoneTimedOut(attempt)
        }
    }

    private func microphoneReady(_ outcome: MicrophoneSetup, attempt: Int, engine used: AVAudioEngine,
                                 queue: DispatchQueue) {
        guard attempt == audioAttempt, audioPending else {
            // Llegó tarde (lo dimos por atorado, o apagaste la voz mientras tanto): lo apagamos.
            guard outcome.installed else { return }
            if used !== engine {
                DispatchQueue.global(qos: .utility).async {
                    _ = ObjC.attempt {
                        if used.isRunning { used.stop() }
                        used.inputNode.removeTap(onBus: 0)
                    }
                }
            } else if !audioPending && !audioRunning {
                queue.async {
                    _ = ObjC.attempt {
                        if used.isRunning { used.stop() }
                        used.inputNode.removeTap(onBus: 0)
                    }
                }
            }
            return
        }
        audioPending = false
        engine = used
        tapInstalled = outcome.installed
        if let problem = outcome.problem {
            log.add("El micrófono falló (\(problem)). Lo reinicio en unos segundos.")
            microphoneFailed("Reiniciando el micrófono…", retryAfter: 3, reset: true)
            return
        }
        guard outcome.hasMicrophone else {
            microphoneFailed("No encontré un micrófono", retryAfter: 10, reset: false)
            return
        }
        if outcome.startFailed {
            microphoneFailed("No pude usar el micrófono", retryAfter: 10, reset: true)
            return
        }
        audioRunning = true
        stuckCount = 0
        if let recognizer = recognizer, let current = request {
            startRecognition(recognizer, current, generation)
        }
        let callbacks = readyCallbacks
        readyCallbacks = []
        callbacks.forEach { $0(true) }
    }

    private func microphoneFailed(_ message: String, retryAfter seconds: Double?, reset: Bool) {
        if reset { engineNeedsReset = true }
        audioRunning = false
        task?.cancel()
        task = nil
        request = nil
        feed.swap(to: nil)?.endAudio()
        state = .unavailable(message)
        let callbacks = readyCallbacks
        readyCallbacks = []
        callbacks.forEach { $0(false) }
        if let seconds = seconds {
            restart(after: seconds)
        }
    }

    /// macOS no contestó a tiempo (se atoró su servicio de audio).
    private func microphoneTimedOut(_ attempt: Int) {
        guard attempt == audioAttempt, audioPending else { return }
        audioPending = false
        stuckCount += 1
        // Esa fila y ese motor se quedaron esperando a macOS: los dejamos y usamos unos nuevos.
        audioQueue = DispatchQueue(label: "isla.microfono.\(attempt)", qos: .userInitiated)
        engine = nil
        engineNeedsReset = false
        tapInstalled = false
        let waits: [Double] = [3, 10, 30, 60, 120]
        guard stuckCount <= waits.count else {
            log.add("El audio de la Mac sigue sin responder. Apaga y prende la voz en Configuración, o reinicia la Mac.")
            microphoneFailed("El audio de la Mac no responde", retryAfter: nil, reset: false)
            onMicrophoneProblem?("El audio de la Mac no responde")
            return
        }
        let wait = waits[stuckCount - 1]
        log.add("El micrófono de macOS no responde (se atoró su servicio de audio). La isla sigue funcionando; lo intento otra vez en \(Int(wait)) s.")
        microphoneFailed("Reiniciando el micrófono…", retryAfter: wait, reset: false)
    }

    /// Apaga el micrófono (en su fila, sin trabar la isla).
    private func stopAudio() {
        task?.cancel()
        task = nil
        request = nil
        feed.swap(to: nil)?.endAudio()
        if audioPending {
            // Se estaba prendiendo: cuando termine, se apaga solo (ver microphoneReady).
            audioPending = false
            audioAttempt += 1
            let callbacks = readyCallbacks
            readyCallbacks = []
            callbacks.forEach { $0(false) }
        }
        guard audioRunning || tapInstalled, let audioEngine = engine else { return }
        let hadTap = tapInstalled
        audioRunning = false
        tapInstalled = false
        audioQueue.async { [weak self] in
            let problem = ObjC.attempt {
                if audioEngine.isRunning { audioEngine.stop() }
                if hadTap { audioEngine.inputNode.removeTap(onBus: 0) }
            }
            if problem != nil {
                Task { @MainActor in self?.engineNeedsReset = true }
            }
        }
    }

    /// Sin "siempre escuchando": el micrófono se apaga hasta que mantengas ⌥ (o toques "Responder").
    private func goStandby() {
        restartTask?.cancel()
        renewalTask?.cancel()
        stopAudio()
        state = .standby
    }

    private func restart(after seconds: Double) {
        restartTask?.cancel()
        restartTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled, let strongSelf = self, strongSelf.enabled else { return }
            if !strongSelf.alwaysListen && strongSelf.phase == .idle && !strongSelf.holdingKey {
                strongSelf.goStandby()
            } else {
                strongSelf.beginListening()
            }
        }
    }

    /// Apple limita cada reconocimiento a ~1 minuto: lo renovamos solo (sin cortar un dictado).
    private func scheduleRenewal() {
        renewalTask?.cancel()
        renewalTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 50_000_000_000)
            guard !Task.isCancelled, let strongSelf = self, strongSelf.enabled else { return }
            if strongSelf.phase == .idle && !strongSelf.holdingKey {
                if strongSelf.alwaysListen {
                    strongSelf.beginListening()
                } else {
                    strongSelf.goStandby()
                }
            } else {
                strongSelf.scheduleRenewal()
            }
        }
    }

    /// Al cambiar frase o idioma, reiniciamos la escucha (con una pausa por si sigues escribiendo).
    private func scheduleSettingsRestart() {
        settingsRestartTask?.cancel()
        settingsRestartTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled, let strongSelf = self, strongSelf.enabled,
                  strongSelf.state != .off, strongSelf.state != .needsPermission,
                  strongSelf.alwaysListen else { return }
            strongSelf.finishPhase()
            strongSelf.beginListening()
        }
    }

    // MARK: Entender lo que dijiste

    private func process(_ segment: String, isFinal: Bool, failed: Bool, generation current: Int) {
        guard current == generation else { return } // resultado de una escucha anterior

        // Si Apple empezó de cero tras una pausa, juntamos lo anterior con lo nuevo.
        let segmentNorm = VoiceWake.normalize(segment)
        if !segment.isEmpty, isSegmentReset(from: segmentNormalized, to: segmentNorm) {
            baseRaw += segmentRaw + " "
            if phase != .idle {
                log.add("(Hiciste una pausa: junto lo que llevabas con lo nuevo)")
            }
        }
        if !segment.isEmpty {
            segmentRaw = segment
            segmentNormalized = segmentNorm
        }
        // Si Apple volvió a mandar todo junto (resultado final), no lo duplicamos.
        let baseNormalized = VoiceWake.normalize(baseRaw).trimmingCharacters(in: .whitespaces)
        if !baseNormalized.isEmpty && segmentNorm.hasPrefix(baseNormalized) {
            baseRaw = ""
        }
        let text = baseRaw + segmentRaw
        let normalized = VoiceWake.normalize(text)
        if normalized != lastNormalized {
            lastNormalized = normalized
            lastChange = Date()
            if !text.isEmpty { lastHeard = String(text.suffix(90)) }
        }

        switch phase {
        case .idle:
            if let wakeEnd = wakePhraseEnd(in: normalized, from: anchorOffset),
               Date().timeIntervalSince(lastWake) > 2 {
                lastWake = Date()
                heardAt = Date()
                anchorOffset = wakeEnd
                playTink()
                log.add("Oí “\(displayPhrase)”")
                onCommand?(.open)
                enter(.awaitingCommand, seconds: commandWindow)
                _ = handleAwaiting(normalized, raw: text)
            } else if replyWindowOpen {
                // Una sesión espera tu respuesta: "responde…" basta, sin "Oye Claudio".
                let from = max(anchorOffset, replyAnchor)
                let tail = VoiceWake.suffix(of: normalized, from: from)
                if let hit = VoiceWake.firstMatch(of: VoiceWake.replyPattern, in: tail) {
                    playTink()
                    beginDictation(.reply, anchor: from + hit.end, floor: from, pattern: VoiceWake.replyPattern)
                    updateDictation(from: text)
                }
            }
        case .awaitingCommand:
            _ = handleAwaiting(normalized, raw: text)
        case .dictating:
            updateDictation(from: text)
        }

        if failed || isFinal {
            if phase == .dictating {
                finishDictation()
                return
            }
            // Si falla apenas empezar varias veces seguidas, esperamos más (no gastar CPU).
            if Date().timeIntervalSince(startedAt) < 2 {
                quickFailures += 1
            } else {
                quickFailures = 0
            }
            restart(after: quickFailures >= 5 ? 30 : (phase == .idle ? 0.3 : 0.1))
        }
    }

    /// ¿El texto nuevo de Apple empezó de cero (en vez de seguir lo que ya iba)?
    private func isSegmentReset(from previous: String, to new: String) -> Bool {
        let old = previous.split(separator: " ")
        let fresh = new.split(separator: " ")
        guard !old.isEmpty, !fresh.isEmpty else { return false }
        // Si empieza igual que antes, Apple solo corrigió palabras (por ejemplo "hoy" → "oye").
        let head = Set(old.prefix(2))
        if fresh.prefix(3).contains(where: { head.contains($0) }) { return false }
        // 1) Lo nuevo ya no alcanza a donde íbamos (después de "Oye Claudio" o del proyecto).
        if baseRaw.count + new.count < anchorOffset {
            return true
        }
        // 2) Estuvo quieto un rato, volviste a hablar y el texto empezó con otra cosa (o mucho más corto).
        //    Si no volviste a hablar es solo Apple acomodando el texto (por ejemplo "dos más dos" → "2 + 2").
        let quiet = Date().timeIntervalSince(lastChange)
        let spokeAgain = activity.lastSpeech.timeIntervalSince(lastChange) > 0.25
        if quiet > 0.5 && spokeAgain && (fresh.first != old.first || fresh.count * 2 < old.count) {
            return true
        }
        return false
    }

    /// Busca a dónde mandar el dictado o una orden después de la frase. true = ya la atendió.
    private func handleAwaiting(_ normalized: String, raw: String) -> Bool {
        let tail = VoiceWake.suffix(of: normalized, from: anchorOffset)

        // Con la tecla, la palabra clave va casi al principio ("terminal …", "ChatGPT …"):
        // así "¿cuál es la respuesta…?" no se va por error a otro lado.
        if let hit = firstKeyword(in: tail, hold: holdingKey) {
            beginDictation(hit.target, anchor: anchorOffset + hit.end, floor: anchorOffset, pattern: hit.pattern)
            updateDictation(from: raw) // por si ya dijiste el mensaje en la misma frase
            return true
        }
        // Con la tecla para hablar, las órdenes cortas se entienden al soltarla.
        if !holdingKey, let command = VoiceWake.command(in: tail) {
            finishPhase()
            log.add("Orden: \(VoiceWake.describe(command))\(elapsedSinceHeard)")
            onCommand?(command)
            restart(after: 0.4) // limpiamos lo escuchado
            return true
        }
        return false
    }

    private func beginDictation(_ target: DictationTarget, anchor: Int, floor: Int, pattern: NSRegularExpression?) {
        anchorOffset = anchor
        anchorFloor = floor
        anchorPattern = pattern
        dictation = ""
        dictationTarget = target
        enter(.dictating, seconds: 90)
        log.add("Dictando para \(target.label)…\(elapsedSinceHeard)")
        onDictationStarted?(target)
    }

    private static let stopWords: Set<String> = ["enviar", "envialo", "envia", "listo", "send"]
    private static let cancelWords: Set<String> = ["cancela", "cancelar", "cancelalo", "olvidalo"]

    private var lastDictatedWord: String? {
        guard let last = dictation.split(separator: " ").last else { return nil }
        return VoiceWake.normalize(String(last)).trimmingCharacters(in: .whitespaces)
    }

    /// true si lo último que dictaste fue "enviar"/"listo" (o "cancela").
    private var endsWithStopWord: Bool {
        guard let last = lastDictatedWord else { return false }
        return VoiceWake.stopWords.contains(last) || VoiceWake.cancelWords.contains(last)
    }

    private func updateDictation(from text: String) {
        // Si el reconocimiento reescribió palabras anteriores, volvemos a ubicar la palabra clave.
        let normalized = VoiceWake.normalize(text)
        if let pattern = anchorPattern {
            let searchFrom = max(anchorFloor, anchorOffset - 24)
            if let hit = VoiceWake.firstMatch(of: pattern, in: VoiceWake.suffix(of: normalized, from: searchFrom)) {
                anchorOffset = searchFrom + hit.end
            }
        }
        dictation = VoiceWake.suffix(of: text, from: anchorOffset)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
    }

    private func finishDictation() {
        var cancelled = false
        if let last = lastDictatedWord {
            if VoiceWake.cancelWords.contains(last) {
                cancelled = true
            } else if VoiceWake.stopWords.contains(last) {
                dictation = dictation.split(separator: " ").dropLast().joined(separator: " ")
            }
        }
        let text = dictation.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
        let target = dictationTarget ?? .claude(.newChat)
        finishPhase()
        if cancelled {
            log.add("Dictado cancelado")
            onCommand?(.cancelled)
        } else {
            log.add(text.isEmpty ? "No oí mensaje para \(target.label)" : "Dictado para \(target.label): “\(text)”")
            onCommand?(.dictated(target, text.isEmpty ? nil : text))
        }
        restart(after: 0.4)
    }

    /// " (entendí la orden 0.8 s después)" para el Registro.
    private var elapsedSinceHeard: String {
        guard let heard = heardAt else { return "" }
        heardAt = nil
        return String(format: " (entendí la orden %.1f s después)", Date().timeIntervalSince(heard))
    }

    private func enter(_ newPhase: Phase, seconds: Double) {
        phase = newPhase
        phaseDeadline = Date().addingTimeInterval(seconds)
        lastChange = Date()
        startWatchdog()
    }

    private func finishPhase() {
        phase = .idle
        dictation = ""
        dictationTarget = nil
        anchorPattern = nil
        watchdogTask?.cancel()
        watchdogTask = nil
    }

    /// Vigila los tiempos: fin de la ventana para la orden y silencio al dictar.
    private func startWatchdog() {
        watchdogTask?.cancel()
        watchdogTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard let strongSelf = self else { return }
                let now = Date()
                switch strongSelf.phase {
                case .idle:
                    return
                case .awaitingCommand:
                    if strongSelf.holdingKey { continue }
                    if now > strongSelf.phaseDeadline {
                        let heard = strongSelf.lastHeard
                        strongSelf.log.add("No entendí ninguna orden. Lo último que oí: “\(heard)”")
                        strongSelf.finishPhase()
                        strongSelf.restart(after: 0.1)
                        return
                    }
                case .dictating:
                    if strongSelf.holdingKey { continue } // mientras mantienes la tecla, sigue escuchando
                    let quiet = now.timeIntervalSince(strongSelf.lastChange)
                    // "…enviar" + una pausa cortita = enviar ya (sin cortar frases como "listo para mañana").
                    if quiet > 0.8 && strongSelf.endsWithStopWord {
                        strongSelf.finishDictation()
                        return
                    }
                    let empty = strongSelf.dictation.isEmpty
                    // Si aún no empiezas a hablar te damos más tiempo.
                    let limit = empty ? max(strongSelf.silenceSeconds, 5) : strongSelf.silenceSeconds
                    if quiet > limit || now > strongSelf.phaseDeadline {
                        strongSelf.finishDictation()
                        return
                    }
                }
            }
        }
    }

    // MARK: Palabras clave

    private struct KeywordHit {
        let target: DictationTarget
        let start: Int
        let end: Int
        let pattern: NSRegularExpression
    }

    private static func regex(_ pattern: String) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: pattern)
    }

    // swiftlint:disable:next force_try
    private static let replyPattern = try! NSRegularExpression(pattern: "\\b(respondele|responde|contestale|contesta|respuesta)\\b")

    /// Destinos fijos. Se reconocen con o sin acentos.
    private static let builtinPatterns: [(DictationTarget, NSRegularExpression)] = {
        let list: [(DictationTarget, String)] = [
            // "nuevo chat" pero no "nuevo chat GPT" (ese va a ChatGPT).
            (.claude(.newChat), "\\b(nuevo\\s+(chat|chad|shat|chats)(?!\\s*(g\\s*p\\s*t|gpt|jipiti|yipiti))|chat\\s+nuevo|nueva\\s+conversacion|nueva\\s+pregunta|nueva\\s+charla|preguntale|escribele|abre\\s+un\\s+chat(?!\\s*(g\\s*p\\s*t|gpt|jipiti|yipiti))|abre\\s+chat(?!\\s*(g\\s*p\\s*t|gpt|jipiti|yipiti))|new\\s+chat)\\b"),
            (.claude(.cowork), "\\b(co\\s*work|coworking|co\\s+working|cowor|kowork|ko\\s+work|cou\\s*work|co\\s*guork|co\\s*bork|nueva\\s+tarea|tarea\\s+nueva)\\b"),
            (.claude(.code), "\\b((claude|cloud|clod|clau)\\s+code|sesion\\s+de\\s+codigo|codigo\\s+nuevo)\\b")
        ]
        var result: [(DictationTarget, NSRegularExpression)] = list.compactMap { target, pattern in
            VoiceWake.regex(pattern).map { (target, $0) }
        }
        result.append((.reply, VoiceWake.replyPattern))
        // "ChatGPT" se reconoce de muchas formas: "chat GPT", "chat g p t", "chat yipiti"…
        if let chatGPT = VoiceWake.regex("\\b(chat\\s*gpt|chat\\s*g\\s*p\\s*t|chat\\s*(ji|yi|ge|je|y)\\s*(pi|pe|p)\\s*(ti|te|t)|chat\\s*jipiti|chat\\s*yipiti|chatgpt|open\\s*ai)\\b") {
            result.append((.chatGPT, chatGPT))
        }
        if let terminal = VoiceWake.regex("\\b(terminal)\\b") {
            result.append((.terminal, terminal))
        }
        return result
    }()

    /// Patrones de tus proyectos (se rehacen solo si cambias la lista).
    private func currentProjectPatterns() -> [(DictationTarget, NSRegularExpression)] {
        let projects = ProjectStore.shared.projects
        let key = projects.map { "\($0.name)|\($0.spoken)|\($0.link)" }.joined(separator: "¦")
        guard key != projectCacheKey else { return projectPatterns }
        projectCacheKey = key
        projectPatterns = projects.compactMap { project in
            guard let id = project.projectID else { return nil }
            let alternatives = project.spokenForms.map { form in
                form.split(separator: " ")
                    .map { NSRegularExpression.escapedPattern(for: String($0)) }
                    .joined(separator: "\\s+")
            }
            guard !alternatives.isEmpty,
                  let pattern = VoiceWake.regex("\\b(" + alternatives.joined(separator: "|") + ")\\b") else { return nil }
            return (.claude(.project(id: id, name: project.name)), pattern)
        }
        return projectPatterns
    }

    /// La primera palabra clave que dijiste (la más temprana gana).
    /// `strict`: la palabra clave debe ir casi al principio (para la tecla ⌥ y textos escritos).
    private func firstKeyword(in text: String, strict: Bool = false, hold: Bool = false) -> KeywordHit? {
        var best: KeywordHit?
        let candidates = VoiceWake.builtinPatterns.map { ($0.0, $0.1, false) }
            + currentProjectPatterns().map { ($0.0, $0.1, true) }
        for (target, pattern, isProject) in candidates {
            guard let hit = VoiceWake.firstMatch(of: pattern, in: text) else { continue }
            // El nombre de un proyecto debe ir al principio ("a Gorgias…", "en el proyecto Gorgias…").
            let wordsBefore = VoiceWake.prefix(of: text, count: hit.start).split(separator: " ").count
            // Tecla ⌥ o escrito: "terminal …", "responde …" tienen que ir primero; un proyecto, casi al principio.
            // Con la tecla para hablar: hasta 2 palabras antes ("abre cowork…"), 4 para un proyecto.
            let limit = strict ? (isProject ? 3 : 0) : (hold ? (isProject ? 4 : 2) : (isProject ? 5 : Int.max))
            if wordsBefore > limit {
                continue
            }
            if best.map({ hit.start < $0.start }) ?? true {
                best = KeywordHit(target: target, start: hit.start, end: hit.end, pattern: pattern)
            }
        }
        return best
    }

    // MARK: Texto

    nonisolated static func normalize(_ text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_MX"))
        let cleaned = folded.lowercased().map { character -> Character in
            character.isLetter || character.isNumber ? character : " "
        }
        return String(cleaned)
    }

    nonisolated private static func suffix(of text: String, from offset: Int) -> String {
        guard offset > 0 else { return text }
        guard offset < text.count else { return "" }
        return String(text.dropFirst(offset))
    }

    nonisolated private static func prefix(of text: String, count: Int) -> String {
        String(text.prefix(max(0, count)))
    }

    /// Dónde empieza y termina la primera coincidencia (en caracteres).
    nonisolated private static func firstMatch(of pattern: NSRegularExpression, in text: String) -> (start: Int, end: Int)? {
        let range = NSRange(text.startIndex..., in: text)
        guard let match = pattern.firstMatch(in: text, range: range),
              let matchRange = Range(match.range, in: text) else { return nil }
        return (text.distance(from: text.startIndex, to: matchRange.lowerBound),
                text.distance(from: text.startIndex, to: matchRange.upperBound))
    }

    private func rebuildWakeRegex() {
        let phrases = wakePhrases
            .split(separator: ",")
            .map { VoiceWake.normalize(String($0)).split(separator: " ").map(String.init) }
            .filter { !$0.isEmpty }
        guard !phrases.isEmpty else {
            wakeRegex = nil
            return
        }
        let alternatives = phrases.map { words in
            words.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "\\s+")
        }
        wakeRegex = try? NSRegularExpression(pattern: "\\b(" + alternatives.joined(separator: "|") + ")\\b")
    }

    /// Posición donde termina la frase para despertar.
    private func wakePhraseEnd(in text: String, from offset: Int) -> Int? {
        guard let regex = wakeRegex else { return nil }
        let searchText = VoiceWake.suffix(of: text, from: offset)
        let range = NSRange(searchText.startIndex..., in: searchText)
        guard let match = regex.matches(in: searchText, range: range).last,
              let matchRange = Range(match.range, in: searchText) else { return nil }
        return offset + searchText.distance(from: searchText.startIndex, to: matchRange.upperBound)
    }

    nonisolated static func command(in text: String) -> VoiceCommand? {
        let words = Set(text.split(separator: " ").map(String.init))
        guard !words.isEmpty else { return nil }
        // Música: solo frases cortas ("siguiente canción", "pausa", "canción anterior").
        // Van antes que "permitir" para que "play" nunca cuente como aprobar.
        if words.count <= 4 {
            let song = !words.isDisjoint(with: ["cancion", "rola", "musica", "song"])
            if song && !words.isDisjoint(with: ["siguiente", "salta", "saltala", "next"]) { return .musicNext }
            if song && !words.isDisjoint(with: ["anterior", "previous"]) { return .musicPrevious }
            if !words.isDisjoint(with: ["pausa", "pausar", "pausala", "play", "pause"])
                || (song && !words.isDisjoint(with: ["reproduce", "reanuda"])) {
                return .musicPlayPause
            }
            if !words.isDisjoint(with: ["agenda", "juntas", "calendario", "reuniones"]) {
                return .today
            }
        }
        if words.contains("siempre") || words.contains("always") { return .always }
        // Solo verbos claros (no "sí"/"no"), para no aprobar nada por accidente.
        if !words.isDisjoint(with: ["permite", "permitir", "permitelo", "acepta", "aceptar", "aceptalo",
                                    "aprueba", "aprobar", "apruebalo", "dale", "allow", "approve"]) { return .allow }
        if !words.isDisjoint(with: ["niega", "negar", "niegalo", "rechaza", "rechazar", "rechazalo",
                                    "cancela", "cancelar", "deny", "reject"]) { return .deny }
        if !words.isDisjoint(with: ["ignora", "ignorar", "ignoralo", "dejalo", "nada"]) { return .ignore }
        if words.contains("programacion") || words.contains("cafe") { return .keepAwake }
        if words.contains("terminal") { return .terminal }
        if words.contains("estante") || words.contains("archivos") { return .shelf }
        if words.contains("portapapeles") || words.contains("copias") { return .clipboard }
        if words.contains("mac") || words.contains("sistema") { return .mac }
        if !words.isDisjoint(with: ["cierra", "cerrar", "cierrate", "adios", "close"]) { return .close }
        return nil
    }

    nonisolated static func describe(_ command: VoiceCommand) -> String {
        switch command {
        case .open: return "abrir"
        case .allow: return "permitir"
        case .always: return "permitir siempre"
        case .deny: return "negar"
        case .terminal: return "terminal"
        case .shelf: return "estante"
        case .clipboard: return "portapapeles"
        case .mac: return "Mac"
        case .close: return "cerrar"
        case .ignore: return "ignorar"
        case .keepAwake: return "modo programación"
        case .today: return "hoy (música y agenda)"
        case .musicPlayPause: return "pausar / reproducir la música"
        case .musicNext: return "siguiente canción"
        case .musicPrevious: return "canción anterior"
        case .dictated(let target, _): return "dictado para \(target.label)"
        case .cancelled: return "cancelar"
        }
    }
}

/// Mide si estás hablando (lo alimenta el hilo de audio; lo lee la app).
/// Sirve para distinguir cuando Apple reinicia el texto porque volviste a hablar.
final class VoiceActivity: @unchecked Sendable {
    private let lock = NSLock()
    private var speechAt = Date.distantPast
    private var noiseFloor: Float = 0.01

    func feed(_ buffer: AVAudioPCMBuffer) {
        guard let samples = buffer.floatChannelData?[0] else { return }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return }
        var sum: Float = 0
        var used = 0
        var index = 0
        while index < count {
            let value = samples[index]
            sum += value * value
            used += 1
            index += 4
        }
        let rms = (sum / Float(max(used, 1))).squareRoot()
        lock.lock()
        // El ruido de fondo se ajusta solo: baja rápido y sube despacio.
        if rms < noiseFloor {
            noiseFloor = noiseFloor * 0.9 + rms * 0.1
        } else {
            noiseFloor = noiseFloor * 0.998 + rms * 0.002
        }
        if rms > max(noiseFloor * 2.5, 0.004) {
            speechAt = Date()
        }
        lock.unlock()
    }

    /// Última vez que se oyó voz.
    var lastSpeech: Date {
        lock.lock()
        defer { lock.unlock() }
        return speechAt
    }
}

/// Lo que pasó al prender el micrófono (lo llena la fila del audio).
struct MicrophoneSetup {
    var hasMicrophone = false
    var installed = false
    var startFailed = false
    var problem: String?
}

/// El audio del micrófono va al reconocimiento actual. Cambiar de reconocimiento es solo
/// cambiar a quién se lo mandamos: no hay que tocar el micrófono (lo que a veces atora a macOS).
final class RecognitionFeed: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?

    /// Cambia el reconocimiento y regresa el anterior (ya no le llega audio).
    @discardableResult
    func swap(to newRequest: SFSpeechAudioBufferRecognitionRequest?) -> SFSpeechAudioBufferRecognitionRequest? {
        lock.lock()
        defer { lock.unlock() }
        let old = request
        request = newRequest
        return old
    }

    /// Se llama desde el hilo del audio.
    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }
        request?.append(buffer)
    }
}
