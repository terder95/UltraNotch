import AppKit
import CoreGraphics

/// Escucha el teclado de todo el sistema (requiere permiso de Accesibilidad).
///
///   ⌘C y, SIN soltar ⌘, un número 1…9  →  guarda lo copiado en esa ranura.
///   ⌘V y, SIN soltar ⌘, un número 1…9  →  pega el contenido de esa ranura.
///
/// Cómo funciona el ⌘V: cuando presionas ⌘V la app "retiene" el pegado un instante.
/// Si enseguida presionas un número, pega esa ranura; si sueltas ⌘ o pasa ~0.9 s,
/// hace el pegado normal. En el uso diario no se nota.
final class KeyInterceptor {
    enum Action {
        case saveSlot(Int, baseline: Int)
        case pasteSlot(Int)
    }

    /// Se llama en el hilo principal.
    var onAction: ((Action) -> Void)?
    private(set) var isRunning = false

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private var copyArmedUntil: Date?
    private var copyBaseline = 0
    private var pendingPaste = false
    private var pasteGeneration = 0
    private var swallowedKeyUps = Set<Int64>()

    /// Marca para reconocer los eventos que genera la propia app.
    static let marker: Int64 = 0x4D4D_4953
    private static let keyC: Int64 = 8
    private static let keyV: Int64 = 9
    /// Cuánto espera después de ⌘V por si presionas un número (se cambia en Configuración).
    private static var pasteWindow: TimeInterval {
        let value = UserDefaults.standard.object(forKey: SettingsKeys.pasteWindow) as? Double ?? 0.9
        return min(max(value, 0.3), 3)
    }
    private static let copyWindow: TimeInterval = 1.5

    /// Códigos físicos de las teclas 1…9 (fila superior y teclado numérico).
    private static let digits: [Int64: Int] = [
        18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9,
        83: 1, 84: 2, 85: 3, 86: 4, 87: 5, 88: 6, 89: 7, 91: 8, 92: 9
    ]

    /// Intenta activar el "oído" del teclado. Devuelve false si falta el permiso.
    func start() -> Bool {
        if isRunning { return true }
        let types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged]
        let mask = types.reduce(CGEventMask(0)) { result, type in
            result | (CGEventMask(1) << CGEventMask(type.rawValue))
        }
        guard let newTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: islaKeyTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)
        tap = newTap
        runLoopSource = source
        isRunning = true
        return true
    }

    // MARK: - Lógica principal

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)

        // macOS apaga el "tap" si tarda mucho; lo volvemos a encender.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return pass
        }

        // Eventos generados por nosotros: dejarlos pasar.
        if event.getIntegerValueField(.eventSourceUserData) == KeyInterceptor.marker {
            return pass
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        let commandOnly = flags.contains(.maskCommand)
            && !flags.contains(.maskShift)
            && !flags.contains(.maskAlternate)
            && !flags.contains(.maskControl)

        switch type {
        case .flagsChanged:
            if !flags.contains(.maskCommand) {
                copyArmedUntil = nil
                if pendingPaste {
                    // Soltaste ⌘ sin número → pegado normal (respetando el orden).
                    flushPendingPaste()
                    repost(event)
                    return nil
                }
            }
            return pass

        case .keyUp:
            if swallowedKeyUps.remove(keyCode) != nil {
                return nil
            }
            return pass

        case .keyDown:
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0

            // ⌘ + número, justo después de ⌘V o ⌘C
            if commandOnly, let slot = KeyInterceptor.digits[keyCode] {
                if pendingPaste {
                    cancelPendingPaste()
                    swallowedKeyUps.insert(keyCode)
                    send(.pasteSlot(slot))
                    return nil
                }
                if let until = copyArmedUntil, Date() < until {
                    copyArmedUntil = nil
                    swallowedKeyUps.insert(keyCode)
                    send(.saveSlot(slot, baseline: copyBaseline))
                    return nil
                }
                return pass
            }

            // ⌘V → retener un instante para ver si viene un número
            if commandOnly && keyCode == KeyInterceptor.keyV {
                if isRepeat {
                    return pendingPaste ? nil : pass
                }
                if pendingPaste {
                    flushPendingPaste()
                }
                copyArmedUntil = nil
                startPendingPaste()
                swallowedKeyUps.insert(keyCode)
                return nil
            }

            // Cualquier otra tecla: primero resolvemos el pegado pendiente.
            var consumed = false
            if pendingPaste {
                flushPendingPaste()
                repost(event)
                consumed = true
            }

            // ⌘C → "armamos" la copia para que un número la guarde en ranura.
            if commandOnly && keyCode == KeyInterceptor.keyC && !isRepeat {
                copyBaseline = NSPasteboard.general.changeCount
                copyArmedUntil = Date().addingTimeInterval(KeyInterceptor.copyWindow)
            } else {
                copyArmedUntil = nil
            }
            return consumed ? nil : pass

        default:
            return pass
        }
    }

    // MARK: - Ayudantes

    private func send(_ action: Action) {
        let handler = onAction
        DispatchQueue.main.async {
            handler?(action)
        }
    }

    private func startPendingPaste() {
        pendingPaste = true
        pasteGeneration &+= 1
        let generation = pasteGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + KeyInterceptor.pasteWindow) { [weak self] in
            guard let self = self, self.pendingPaste, self.pasteGeneration == generation else { return }
            self.flushPendingPaste()
        }
    }

    private func cancelPendingPaste() {
        pendingPaste = false
        pasteGeneration &+= 1
    }

    private func flushPendingPaste() {
        cancelPendingPaste()
        KeyInterceptor.postCommandV()
    }

    /// Reenvía una copia del evento para que llegue DESPUÉS del pegado sintético.
    private func repost(_ event: CGEvent) {
        guard let copy = event.copy() else { return }
        copy.setIntegerValueField(.eventSourceUserData, value: KeyInterceptor.marker)
        copy.post(tap: .cghidEventTap)
    }

    /// "Teclea" ⌘V en la app que tengas al frente.
    static func postCommandV() {
        let source = CGEventSource(stateID: .hidSystemState)
        let key = CGKeyCode(keyV)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false) else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.setIntegerValueField(.eventSourceUserData, value: marker)
        up.setIntegerValueField(.eventSourceUserData, value: marker)
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}

/// Función C que macOS llama con cada tecla. Reenvía al KeyInterceptor.
private func islaKeyTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon = refcon else {
        return Unmanaged.passUnretained(event)
    }
    let interceptor = Unmanaged<KeyInterceptor>.fromOpaque(refcon).takeUnretainedValue()
    return interceptor.handle(type: type, event: event)
}
