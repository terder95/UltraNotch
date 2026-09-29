import AppKit

/// Tecla para hablar: mantén presionada la tecla ⌥ (Option) de la derecha, di lo que quieras
/// ("terminal …", "ChatGPT …", "cowork …", o solo tu pregunta) y suéltala para mandarlo.
/// Sin esperar la frase para despertar.
///
/// Solo se activa si la mantienes sola un momento: si la usas para escribir (⌥ + otra tecla)
/// no hace nada.
@MainActor
final class HoldToTalkKey {
    nonisolated static let enabledKey = "holdToTalk"

    /// Empezar a escuchar. Regresa false si la voz no está lista.
    var onBegan: (() -> Bool)?
    /// Soltaste la tecla.
    var onEnded: (() -> Void)?
    /// Escribiste algo mientras la mantenías (era un atajo): se cancela sin mandar nada.
    var onCancelled: (() -> Void)?

    var enabled: Bool {
        UserDefaults.standard.object(forKey: HoldToTalkKey.enabledKey) as? Bool ?? true
    }

    private static let rightOptionKeyCode: UInt16 = 61
    /// Bit de "⌥ derecha" en las banderas del teclado (NX_DEVICERALTKEYMASK).
    private static let rightOptionMask: UInt = 0x40
    /// Cuánto hay que mantenerla para que cuente (así no estorba al escribir).
    private static let holdDelay: UInt64 = 280_000_000

    private var monitors: [Any] = []
    private var pressed = false
    private var started = false
    private var otherKeyPressed = false
    private var pending: Task<Void, Never>?

    /// Vuelve a escuchar el teclado (por ejemplo, después de dar el permiso de Accesibilidad).
    func restart() {
        stop()
        start()
    }

    func stop() {
        for monitor in monitors {
            NSEvent.removeMonitor(monitor)
        }
        monitors.removeAll()
        cancelPending()
        pressed = false
        if started {
            started = false
            onEnded?() // no dejar la voz "escuchando" para siempre
        }
    }

    func start() {
        guard monitors.isEmpty else { return }
        let globalFlags = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            let code = event.keyCode
            let raw = event.modifierFlags.rawValue
            Task { @MainActor in self?.flagsChanged(keyCode: code, raw: raw) }
        }
        let globalKeys = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] _ in
            Task { @MainActor in self?.otherKey() }
        }
        // También cuando Isla está al frente (por ejemplo, con Configuración abierta).
        let localFlags = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            let code = event.keyCode
            let raw = event.modifierFlags.rawValue
            Task { @MainActor in self?.flagsChanged(keyCode: code, raw: raw) }
            return event
        }
        let localKeys = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in self?.otherKey() }
            return event
        }
        monitors = [globalFlags, globalKeys, localFlags, localKeys].compactMap { $0 }
    }

    private func flagsChanged(keyCode: UInt16, raw: UInt) {
        guard keyCode == HoldToTalkKey.rightOptionKeyCode else {
            // Otra tecla modificadora mientras la mantienes: es un atajo, no para hablar.
            if pressed && !started { cancelPending() }
            return
        }
        let down = raw & HoldToTalkKey.rightOptionMask != 0
        if down {
            guard enabled, !pressed else { return }
            pressed = true
            otherKeyPressed = false
            pending = Task { [weak self] in
                try? await Task.sleep(nanoseconds: HoldToTalkKey.holdDelay)
                guard !Task.isCancelled, let strongSelf = self,
                      strongSelf.pressed, !strongSelf.otherKeyPressed else { return }
                strongSelf.started = strongSelf.onBegan?() ?? false
            }
        } else {
            cancelPending()
            pressed = false
            if started {
                started = false
                onEnded?()
            }
        }
    }

    private func otherKey() {
        guard pressed else { return }
        otherKeyPressed = true
        if started {
            started = false
            onCancelled?()
        } else {
            cancelPending()
        }
    }

    private func cancelPending() {
        pending?.cancel()
        pending = nil
    }
}
