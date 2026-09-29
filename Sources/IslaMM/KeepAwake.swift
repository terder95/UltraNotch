import Foundation
import IOKit.pwr_mgt
import Combine

/// "Modo programación": mientras está activo, la Mac no se duerme, no se apaga la
/// pantalla y no se bloquea por inactividad (conectada o con batería).
/// Si cierras la tapa sí se duerme (macOS no deja evitarlo sin cambiar ajustes del sistema).
@MainActor
final class KeepAwake: ObservableObject {
    @Published private(set) var isOn = false
    @Published private(set) var since: Date?

    private var displayAssertion: IOPMAssertionID = 0
    private var systemAssertion: IOPMAssertionID = 0

    func toggle() {
        if isOn { stop() } else { start() }
    }

    func start() {
        guard !isOn else { return }
        let reason = "Isla: modo programación (mantener la Mac despierta)" as CFString
        let level = IOPMAssertionLevel(kIOPMAssertionLevelOn)

        var display = IOPMAssertionID(0)
        let displayResult = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString, level, reason, &display)
        var system = IOPMAssertionID(0)
        let systemResult = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString, level, reason, &system)

        guard displayResult == kIOReturnSuccess || systemResult == kIOReturnSuccess else {
            IslaLog.shared.add("No pude activar el modo programación (macOS lo rechazó)")
            return
        }
        displayAssertion = displayResult == kIOReturnSuccess ? display : 0
        systemAssertion = systemResult == kIOReturnSuccess ? system : 0
        isOn = true
        since = Date()
        // Con la pantalla sin dormirse tampoco sale el protector ni se bloquea por inactividad.
        IslaLog.shared.add("Modo programación activado: la Mac no se dormirá ni se bloqueará")
    }

    func stop() {
        guard isOn else { return }
        for assertion in [displayAssertion, systemAssertion] where assertion != 0 {
            IOPMAssertionRelease(assertion)
        }
        displayAssertion = 0
        systemAssertion = 0
        isOn = false
        since = nil
        IslaLog.shared.add("Modo programación apagado")
    }
}
