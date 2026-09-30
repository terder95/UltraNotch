import AppKit

/// "Oye Claudio, ChatGPT, …": abre un chat nuevo en ChatGPT, deja tu mensaje y lo envía.
/// Usa la app de ChatGPT para Mac si la tienes (trae ChatGPT y Codex juntos);
/// si no, chatgpt.com en tu navegador. Con tu cuenta de siempre: sin API ni costo extra.
@MainActor
enum ChatGPTChat {
    /// Identificadores con los que ha salido la app de ChatGPT para Mac.
    static let bundleIDs = ["com.openai.chat", "com.openai.chatgpt", "com.openai.codex"]
    static let label = "ChatGPT"

    private static var log: UltraNotchLog { UltraNotchLog.shared }

    /// La app de ChatGPT para Mac, si está instalada.
    static func appURL() -> URL? {
        for id in bundleIDs {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) { return url }
        }
        let paths = ["/Applications/ChatGPT.app", NSHomeDirectory() + "/Applications/ChatGPT.app"]
        for path in paths where FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    static func send(_ rawText: String?, report: ClaudeChat.Report? = nil) {
        var text = rawText?.trimmingCharacters(in: .whitespacesAndNewlines)
        if text?.isEmpty == true { text = nil }
        if let long = text, long.count > 12_000 {
            text = String(long.prefix(12_000))
        }
        let shouldSend = ClaudeChat.autoSend && text != nil
        Task { @MainActor in
            if let app = appURL() {
                await openInApp(app, text: text, shouldSend: shouldSend, report: report)
            } else {
                log.add("No encontré la app de ChatGPT para Mac: uso chatgpt.com")
                await openInBrowser(text: text, shouldSend: shouldSend, report: report)
            }
        }
    }

    // MARK: App de Mac

    private static func openInApp(_ url: URL, text: String?, shouldSend: Bool, report: ClaudeChat.Report?) async {
        let bundleID = Bundle(url: url)?.bundleIdentifier ?? "com.openai.chat"
        let wasRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
        log.add("Abriendo ChatGPT para Mac")
        log.add(text.map { "Mensaje: “\(String($0.prefix(80)))”" } ?? "Sin mensaje (solo abro)")

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration, completionHandler: nil)

        guard await ClaudeChat.waitUntilFront(bundleID: bundleID, timeout: wasRunning ? 6 : 18, nudge: true) else {
            log.add("ChatGPT no pasó al frente; no tecleo nada por seguridad.")
            if let text = text { ClaudeChat.copyTransient(text) }
            report?(text == nil ? "ChatGPT no pasó al frente" : "ChatGPT no pasó al frente · tu texto quedó copiado", false)
            return
        }
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            if let text = text { ClaudeChat.copyTransient(text) }
            report?("No encontré ChatGPT abierto", false)
            return
        }
        let pid = app.processIdentifier
        // La app nueva de ChatGPT está hecha con Electron: hay que pedirle su árbol de accesibilidad.
        ClaudeComposer.enableAccessibility(pid: pid)
        try? await Task.sleep(nanoseconds: UInt64((wasRunning ? 0.5 : 3.0) * 1_000_000_000))

        // Chat nuevo (⌘N), solo si ChatGPT sigue al frente.
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID else {
            if let text = text { ClaudeChat.copyTransient(text) }
            report?("ChatGPT dejó de estar al frente", false)
            return
        }
        KeyboardSynth.press(45, flags: .maskCommand) // ⌘N
        log.add("Chat nuevo en ChatGPT (⌘N)")

        guard let text = text else {
            report?("Listo: ChatGPT", true)
            return
        }
        try? await Task.sleep(nanoseconds: 1_000_000_000) // que termine de mostrar el chat nuevo
        await ClaudeChat.writeAndSend(pid: pid, bundleID: bundleID, label: label, prefilled: false, text: text,
                                      shouldSend: shouldSend, textAreaOnly: false, report: report)
    }

    // MARK: Navegador

    /// chatgpt.com/?prompt=… deja el texto escrito; luego lo confirmamos y damos Enter.
    private static func openInBrowser(text: String?, shouldSend: Bool, report: ClaudeChat.Report?) async {
        let address = "https://chatgpt.com/" + (text.map { "?prompt=" + ClaudeChat.encode($0) } ?? "")
        guard let url = URL(string: address) else { return }
        let browserID = NSWorkspace.shared.urlForApplication(toOpen: url).flatMap { Bundle(url: $0)?.bundleIdentifier }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open(url, configuration: configuration, completionHandler: nil)

        guard let text = text else {
            report?("Listo: ChatGPT", true)
            return
        }
        guard let browserID = browserID,
              await ClaudeChat.waitUntilFront(bundleID: browserID, timeout: 8, nudge: false) else {
            ClaudeChat.copyTransient(text)
            report?("Abrí ChatGPT · tu texto quedó copiado", false)
            return
        }
        try? await Task.sleep(nanoseconds: 3_000_000_000) // que cargue la página
        guard let browser = NSRunningApplication.runningApplications(withBundleIdentifier: browserID).first else {
            ClaudeChat.copyTransient(text)
            report?("Abrí ChatGPT · tu texto quedó copiado", false)
            return
        }
        await ClaudeChat.writeAndSend(pid: browser.processIdentifier, bundleID: browserID, label: label,
                                      prefilled: true, text: text, shouldSend: shouldSend,
                                      textAreaOnly: true, report: report)
    }
}
