import AppKit
import ApplicationServices
import CoreGraphics

/// A dónde mandas lo que dictas.
enum ClaudeDestination: Equatable {
    case newChat
    case cowork
    case code
    case project(id: String, name: String)

    var label: String {
        switch self {
        case .newChat: return "un chat nuevo"
        case .cowork: return "Cowork"
        case .code: return "Claude Code"
        case .project(_, let name): return name.isEmpty ? "tu proyecto" : name
        }
    }

    /// El link de Claude acepta el texto ya escrito (?q=…) en estos destinos.
    var acceptsPrefill: Bool {
        if case .project = self { return false }
        return true
    }

    /// Cuánto esperar a que Claude termine de mostrar la pantalla antes de "teclear".
    var settleDelay: Double {
        switch self {
        case .newChat: return 1.2
        case .cowork, .code: return 1.6
        case .project: return 2.0
        }
    }
}

/// Dónde abrir Claude.
enum ClaudeChatTarget: String, CaseIterable, Identifiable {
    case desktop, web

    var id: String { rawValue }

    var label: String {
        switch self {
        case .desktop: return "Claude para Mac"
        case .web: return "Claude en el navegador"
        }
    }
}

/// Abre Claude con tu plan (sin API ni costo extra) usando los links oficiales
/// de Claude para Mac: claude://claude.ai/new?q=…, claude://claude.ai/project/…,
/// claude://cowork/new?q=… y claude://code/new?q=….
@MainActor
enum ClaudeChat {
    static let desktopBundleID = "com.anthropic.claudefordesktop"

    /// (mensaje corto para la isla, salió bien)
    typealias Report = (String, Bool) -> Void

    static var target: ClaudeChatTarget {
        ClaudeChatTarget(rawValue: UserDefaults.standard.string(forKey: SettingsKeys.chatTarget) ?? "") ?? .desktop
    }

    static var autoSend: Bool {
        UserDefaults.standard.object(forKey: SettingsKeys.chatAutoSend) as? Bool ?? true
    }

    private static var log: UltraNotchLog { UltraNotchLog.shared }

    /// Abre el destino y, si hay texto, lo deja escrito y (si quieres) lo envía.
    static func send(_ destination: ClaudeDestination, text rawText: String?, sendNow: Bool? = nil, report: Report? = nil) {
        var text = rawText?.trimmingCharacters(in: .whitespacesAndNewlines)
        if text?.isEmpty == true { text = nil }
        if let long = text, long.count > 12_000 {
            text = String(long.prefix(12_000))
        }
        let shouldSend = (sendNow ?? autoSend) && text != nil
        Task { @MainActor in
            if target == .desktop,
               let link = deepLink(destination, text: text),
               NSWorkspace.shared.urlForApplication(toOpen: link) != nil {
                await openInDesktop(link, destination: destination, text: text, shouldSend: shouldSend, report: report)
            } else {
                if target == .desktop {
                    log.add("No encontré Claude para Mac (o es una versión sin links claude://). Uso el navegador.")
                }
                await openInBrowser(destination, text: text, shouldSend: shouldSend, report: report)
            }
        }
    }

    /// Botón "Probar" de Configuración: abre un chat nuevo con texto, sin enviarlo.
    static func test(report: Report? = nil) {
        send(.newChat, text: "Hola Claude, esta es una prueba desde UltraNotch", sendNow: false, report: report)
    }

    // MARK: Links

    private static let unreserved = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")

    static func encode(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
    }

    static func deepLink(_ destination: ClaudeDestination, text: String?) -> URL? {
        var link: String
        switch destination {
        case .newChat: link = "claude://claude.ai/new"
        case .cowork: link = "claude://cowork/new"
        case .code: link = "claude://code/new"
        case .project(let id, _): link = "claude://claude.ai/project/\(id)"
        }
        if let text = text, destination.acceptsPrefill {
            link += "?q=" + encode(text)
        }
        return URL(string: link)
    }

    private static func describe(_ url: URL) -> String {
        let full = url.absoluteString
        guard let queryStart = full.firstIndex(of: "?") else { return full }
        return String(full[..<queryStart]) + "?q=…"
    }

    // MARK: Claude para Mac

    private static var runningClaude: NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: desktopBundleID).first
    }

    private static func openInDesktop(_ link: URL, destination: ClaudeDestination, text: String?,
                                      shouldSend: Bool, report: Report?) async {
        let wasRunning = runningClaude != nil
        log.add("Abriendo \(describe(link)) en Claude para Mac")
        log.add(text.map { "Mensaje: “\(String($0.prefix(80)))”" } ?? "Sin mensaje (solo abro)")
        if let pid = runningClaude?.processIdentifier {
            ClaudeComposer.enableAccessibility(pid: pid) // que Claude arme su árbol de accesibilidad desde ya
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        let opened: Bool = await withCheckedContinuation { continuation in
            NSWorkspace.shared.open(link, configuration: configuration) { _, error in
                continuation.resume(returning: error == nil)
            }
        }
        guard opened else {
            log.add("macOS no pudo abrir el link. Uso el navegador.")
            await openInBrowser(destination, text: text, shouldSend: shouldSend, report: report)
            return
        }

        guard await waitUntilFront(bundleID: desktopBundleID, timeout: wasRunning ? 6 : 18, nudge: true) else {
            log.add("Claude no pasó al frente; no tecleo nada por seguridad.")
            if let text = text { copyTransient(text) }
            report?(text == nil ? "Claude no pasó al frente" : "Claude no pasó al frente · tu texto quedó copiado", false)
            return
        }
        log.add("Claude al frente ✓")

        guard let text = text else {
            report?("Listo: \(destination.label)", true)
            return
        }
        guard let pid = runningClaude?.processIdentifier else { return }
        ClaudeComposer.enableAccessibility(pid: pid)

        // Esperamos a que Claude termine de mostrar la pantalla nueva.
        let settle = destination.settleDelay + (wasRunning ? 0 : 2.5)
        try? await Task.sleep(nanoseconds: UInt64(settle * 1_000_000_000))

        await writeAndSend(pid: pid, bundleID: desktopBundleID, label: destination.label,
                           prefilled: destination.acceptsPrefill, text: text,
                           shouldSend: shouldSend, textAreaOnly: false, report: report)
    }

    /// Deja tu texto en la caja de escribir (buscándola con Accesibilidad), confirma que
    /// sí quedó escrito y, si quieres, lo envía. Nunca da Enter en otra app.
    /// `prefilled`: el link ya debería traer el texto escrito. También lo usa ChatGPT.
    static func writeAndSend(pid: pid_t, bundleID: String, label: String, prefilled: Bool, text: String,
                             shouldSend: Bool, textAreaOnly: Bool, report: Report?) async {
        let inFront: () -> Bool = { NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID }

        // 1) Buscamos la caja de texto y le damos el foco (reintenta mientras carga la página).
        var existing: String?
        for attempt in 0..<5 {
            existing = await Task.detached { ClaudeComposer.focusComposer(pid: pid, textAreaOnly: textAreaOnly) }.value
            if existing != nil { break }
            if attempt < 4 { try? await Task.sleep(nanoseconds: 600_000_000) }
        }
        let composerFound = existing != nil
        log.add(composerFound ? "Encontré la caja de texto de \(label) ✓" : "No encontré la caja de texto por Accesibilidad")

        // 2) Si el link no dejó el texto escrito (proyectos), lo pegamos.
        //    Sin Accesibilidad confiamos en que el link (?q=…) ya lo escribió, como antes.
        var written = existing.map { ClaudeComposer.contains($0, text) } ?? prefilled
        if written {
            log.add(composerFound ? "El texto ya estaba escrito ✓" : "El link trae tu texto (sin poder confirmarlo)")
        } else {
            guard inFront() else {
                copyTransient(text)
                log.add("\(label) dejó de estar al frente; tu texto quedó copiado.")
                report?("Tu texto quedó copiado (pégalo con ⌘V)", false)
                return
            }
            copyTransient(text)
            KeyInterceptor.postCommandV()
            try? await Task.sleep(nanoseconds: 600_000_000)
            let now = await Task.detached { ClaudeComposer.focusedText(pid: pid) }.value
            written = now.map { ClaudeComposer.contains($0, text) } ?? false
            if written {
                log.add("Pegué el texto en \(label) ✓")
            } else if composerFound {
                // Encontramos la caja pero el texto no aparece: no enviamos nada a ciegas.
                log.add("El texto no apareció en la caja de \(label). Quedó copiado.")
                report?("Abrí \(label) · pega tu texto con ⌘V", false)
                return
            } else {
                log.add("Pegué sin poder confirmarlo (quedó copiado por si acaso)")
            }
        }

        guard shouldSend else {
            log.add("Listo para que lo revises y envíes")
            report?("Escrito en \(label) · revisa y envía", true)
            return
        }
        guard inFront() else {
            log.add("\(label) dejó de estar al frente; no envié nada.")
            report?("No envié: \(label) ya no estaba al frente", false)
            return
        }
        KeyboardSynth.press(36, flags: []) // Enter
        log.add("Envié con Enter ✓")
        report?("Enviado a \(label)", true)
    }

    // MARK: Navegador

    private static func openInBrowser(_ destination: ClaudeDestination, text: String?,
                                      shouldSend: Bool, report: Report?) async {
        let address: String
        switch destination {
        case .newChat:
            address = "https://claude.ai/new" + (text.map { "?q=" + encode($0) } ?? "")
        case .project(let id, _):
            address = "https://claude.ai/project/\(id)"
        case .cowork, .code:
            log.add("\(destination.label) solo se abre en Claude para Mac.")
            if let text = text { copyTransient(text) }
            report?("\(destination.label) necesita Claude para Mac", false)
            return
        }
        guard let url = URL(string: address) else { return }
        let browserID = NSWorkspace.shared.urlForApplication(toOpen: url).flatMap { Bundle(url: $0)?.bundleIdentifier }
        log.add("Abriendo \(describe(url)) en el navegador")

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open(url, configuration: configuration, completionHandler: nil)

        guard let text = text else {
            report?("Listo: \(destination.label)", true)
            return
        }
        guard let browserID = browserID,
              await waitUntilFront(bundleID: browserID, timeout: 8, nudge: false) else {
            copyTransient(text)
            report?("Abrí Claude · tu texto quedó copiado", false)
            return
        }
        try? await Task.sleep(nanoseconds: 2_800_000_000) // que cargue la página
        guard let browser = NSRunningApplication.runningApplications(withBundleIdentifier: browserID).first else {
            copyTransient(text)
            report?("Abrí Claude · tu texto quedó copiado", false)
            return
        }
        // En el navegador solo buscamos áreas de texto (para no escribir en la barra de direcciones).
        await writeAndSend(pid: browser.processIdentifier, bundleID: browserID, label: destination.label,
                           prefilled: destination.acceptsPrefill, text: text,
                           shouldSend: shouldSend, textAreaOnly: true, report: report)
    }

    // MARK: Ayudantes

    /// Espera a que la app quede al frente. `nudge` la vuelve a abrir si tarda.
    static func waitUntilFront(bundleID: String, timeout: Double, nudge: Bool) async -> Bool {
        let start = Date()
        var nudged = false
        while Date().timeIntervalSince(start) < timeout {
            if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID { return true }
            if nudge, !nudged, Date().timeIntervalSince(start) > 1.5,
               let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first,
               let url = app.bundleURL {
                // Algunas versiones de Claude cambian de pantalla sin pasar al frente: la traemos.
                nudged = true
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = true
                NSWorkspace.shared.openApplication(at: url, configuration: configuration, completionHandler: nil)
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID
    }

    /// Copia el texto marcado como temporal (no entra al historial de UltraNotch).
    static func copyTransient(_ text: String) {
        writeTransient(text, to: NSPasteboard.general)
    }

    static func writeTransient(_ text: String, to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        item.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
        pasteboard.writeObjects([item])
    }
}

/// "Teclea" en la Mac (usa el permiso de Accesibilidad que UltraNotch ya tiene).
enum KeyboardSynth {
    static func press(_ key: CGKeyCode, flags: CGEventFlags) {
        post(key, down: true, flags: flags)
        post(key, down: false, flags: flags)
    }

    private static func post(_ key: CGKeyCode, down: Bool, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down) else { return }
        event.flags = flags
        event.setIntegerValueField(.eventSourceUserData, value: KeyInterceptor.marker)
        event.post(tap: .cghidEventTap)
    }
}

// MARK: - Caja de texto de Claude (Accesibilidad)

/// Encuentra la caja donde escribes en Claude para Mac y le da el foco, usando
/// Accesibilidad (el mismo permiso que UltraNotch ya tiene para los atajos).
/// Todo esto corre fuera del hilo principal.
enum ClaudeComposer {
    /// Claude para Mac (Electron) solo arma su árbol de accesibilidad si se lo pedimos.
    static func enableAccessibility(pid: pid_t) {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }

    /// Le da el foco a la caja de texto. Devuelve lo que ya tenía escrito, o nil si no la encontró.
    static func focusComposer(pid: pid_t, textAreaOnly: Bool) -> String? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 1.0)
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        guard let window = element(app, kAXFocusedWindowAttribute) ?? element(app, kAXMainWindowAttribute),
              let box = findComposer(in: window, textAreaOnly: textAreaOnly) else { return nil }
        AXUIElementSetAttributeValue(box, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        return string(box, kAXValueAttribute) ?? ""
    }

    /// El texto de lo que tiene el foco en Claude (para confirmar que sí se pegó).
    static func focusedText(pid: pid_t) -> String? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 1.0)
        guard let focused = element(app, kAXFocusedUIElementAttribute) else { return nil }
        return string(focused, kAXValueAttribute)
    }

    /// ¿`haystack` ya trae el principio de `text`? (sin fijarse en acentos, mayúsculas ni signos)
    static func contains(_ haystack: String, _ text: String) -> Bool {
        let needle = String(VoiceWake.normalize(text).split(separator: " ").joined(separator: " ").prefix(24))
        guard !needle.isEmpty else { return false }
        let hay = VoiceWake.normalize(haystack).split(separator: " ").joined(separator: " ")
        return hay.contains(needle)
    }

    /// La caja de escribir mensajes: el área de texto más ancha de la ventana
    /// (si no hay áreas de texto, el campo de texto más ancho).
    private static func findComposer(in root: AXUIElement, textAreaOnly: Bool) -> AXUIElement? {
        var queue: [AXUIElement] = [root]
        var index = 0
        var bestArea: (element: AXUIElement, width: CGFloat)?
        var bestField: (element: AXUIElement, width: CGFloat)?
        while index < queue.count && index < 8000 {
            let current = queue[index]
            index += 1
            let role = string(current, kAXRoleAttribute) ?? ""
            if role == kAXTextAreaRole {
                let width = size(current)?.width ?? 0
                if width > (bestArea?.width ?? -1) { bestArea = (current, width) }
            } else if role == kAXTextFieldRole && !textAreaOnly {
                let width = size(current)?.width ?? 0
                if width > (bestField?.width ?? -1) { bestField = (current, width) }
            }
            if let kids = children(current) {
                queue.append(contentsOf: kids)
            }
        }
        return bestArea?.element ?? bestField?.element
    }

    private static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value = value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func children(_ element: AXUIElement) -> [AXUIElement]? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success else { return nil }
        return value as? [AXUIElement]
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func size(_ element: AXUIElement) -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &value) == .success,
              let value = value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var result = CGSize.zero
        guard AXValueGetValue(value as! AXValue, .cgSize, &result) else { return nil }
        return result
    }
}
