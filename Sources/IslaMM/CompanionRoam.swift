import AppKit
import SwiftUI
import Combine
import ApplicationServices

// Paseo por la pantalla: el compañero se deja caer del notch (a veces en paracaídas),
// aterriza arriba del Dock (o abajo de la pantalla si el Dock está escondido), camina,
// anda en patineta o en coche, recibe a su amigo, hace sus cosas y regresa volando
// en globo, en ovni o en cohete. Es una ventanita transparente que no roba el teclado.

/// Tamaño de la ventanita del paseo (lo transparente deja pasar los clics).
enum RoamWindow {
    static let width: CGFloat = 280
    static let height: CGFloat = 200
}

@MainActor
final class RoamModel: ObservableObject {
    @Published var scene = StageFrame(x: RoamWindow.width / 2, y: RoamWindow.height / 2, pose: BuddyPose())
    @Published var tint: Color = Theme.accent
}

struct RoamingBuddyView: View {
    @ObservedObject var model: RoamModel
    let size: CGFloat
    var onTap: () -> Void

    var body: some View {
        StageSceneView(frame: model.scene, tint: model.tint, size: size, onTapBuddy: onTap)
            .frame(width: RoamWindow.width, height: RoamWindow.height, alignment: .topLeading)
    }
}

@MainActor
final class RoamController {
    let size: CGFloat = 26

    /// Se llama cuando regresa al notch.
    var onFinished: (() -> Void)?
    private(set) var isRoaming = false

    /// Cómo regresa al notch.
    enum ReturnStyle {
        case balloon, ufo, rocket
        /// Volando con su gorrito de hélice (rápido).
        case propeller
    }

    private enum Phase {
        case falling(vx: CGFloat, vy: CGFloat, parachute: Bool)
        case landing(until: Date)
        case walking(target: CGFloat)
        case skating(target: CGFloat)
        case driving(start: Date, from: CGFloat, target: CGFloat)
        /// Su amigo llega de un lado (-1 izquierda, 1 derecha).
        case visiting(start: Date, from: CGFloat)
        case activity(CompanionAction, start: Date, duration: Double)
        case magic(start: Date, target: CGFloat)
        case napping(until: Date)
        case jumping(vy: CGFloat)
        case returning(style: ReturnStyle, from: NSPoint, start: Date)
        /// Vuela a la ventana que abriste por voz…
        case flyingTo(from: NSPoint, to: NSPoint, start: Date, duration: Double)
        /// …y te la presenta ("¡Aquí está!").
        case presenting(start: Date)
    }

    /// Salió solo a presentarte una ventana (regresa en cuanto termina).
    private var presentingTrip = false

    private var panel: NotchPanel?
    private let model = RoamModel()
    private var timer: AnyCancellable?
    private var phase: Phase = .landing(until: Date())
    /// Centro del cuerpo en coordenadas de pantalla (= centro de la ventanita).
    private var position = NSPoint.zero
    private var floorY: CGFloat = 0
    private var range: ClosedRange<CGFloat> = 0...1
    private var facing: CGFloat = 1
    private var walkPhase: Double = 0
    private var started = Date()
    private var totalDuration: Double = 40
    private var lastTick = Date()
    private var lastTap = Date.distantPast
    private var home: (() -> NSPoint)?

    private static let gravity: CGFloat = 1500
    private static let parachuteSpeed: CGFloat = 150

    /// Centro de la ventanita (ahí está el compañero).
    private var cx: CGFloat { RoamWindow.width / 2 }
    private var cy: CGFloat { RoamWindow.height / 2 }

    // MARK: Empezar / terminar

    /// `point`: dónde está ahorita (junto al notch). `home`: a dónde regresar.
    func start(from point: NSPoint, screen: NSScreen, tint: Color, home: @escaping () -> NSPoint) {
        guard !isRoaming else { return }
        isRoaming = true
        self.home = home
        model.tint = tint
        position = point
        started = Date()
        lastTick = Date()
        totalDuration = Double.random(in: 40...60)
        computeSurface(on: screen)

        // Salta un poquito y cae hacia un punto del Dock (a veces en paracaídas).
        let initialVY: CGFloat = 160
        let height = max(position.y - size / 2 - floorY, 1)
        let parachute = height > 250 && Int.random(in: 0..<3) == 0
        let fallTime: CGFloat
        if parachute {
            fallTime = height / RoamController.parachuteSpeed + 0.3
        } else {
            let g = RoamController.gravity
            fallTime = (initialVY + (initialVY * initialVY + 2 * g * height).squareRoot()) / g
        }
        let landingX = min(max(point.x + CGFloat.random(in: -80...80), range.lowerBound), range.upperBound)
        phase = .falling(vx: (landingX - point.x) / max(fallTime, 0.2), vy: initialVY, parachute: parachute)

        showPanel()
        IslaLog.shared.add("El compañero salió a pasear por la pantalla")
        timer = Timer.publish(every: 1.0 / 30.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.step()
            }
        step()
    }

    /// Vuela del notch a la ventana que acabas de abrir, se para arriba de ella,
    /// te la presenta y regresa volando. No mueve tus ventanas.
    func present(window: NSRect, from point: NSPoint, tint: Color, home: @escaping () -> NSPoint) {
        guard !isRoaming else { return }
        isRoaming = true
        presentingTrip = true
        self.home = home
        model.tint = tint
        position = point
        started = Date()
        lastTick = Date()
        totalDuration = 0 // al terminar de presentar, regresa
        // Se para sobre la orilla de arriba de la ventana, hacia el centro.
        let margin: CGFloat = min(60, window.width / 3)
        let landingX = min(max(window.midX, window.minX + margin), window.maxX - margin)
        let target = NSPoint(x: landingX, y: window.maxY + size / 2 - 1)
        floorY = window.maxY - 1
        range = (window.minX + margin)...max(window.minX + margin + 1, window.maxX - margin)
        facing = target.x >= point.x ? 1 : -1
        let distance = hypot(target.x - point.x, target.y - point.y)
        let duration = Double(min(max(distance / 700, 0.7), 1.6))
        phase = .flyingTo(from: point, to: target, start: Date(), duration: duration)

        showPanel()
        timer = Timer.publish(every: 1.0 / 30.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.step()
            }
        step()
    }

    /// Regresa al notch (volando) o de inmediato.
    func comeHome(fast: Bool) {
        guard isRoaming else { return }
        // Si solo fue a presentarte una ventana, deja que termine (tarda un par de segundos).
        if !fast, presentingTrip {
            return
        }
        if fast {
            finish()
        } else if case .returning = phase {
            return
        } else {
            startReturn()
        }
    }

    private func finish() {
        timer = nil
        panel?.orderOut(nil)
        isRoaming = false
        presentingTrip = false
        onFinished?()
    }

    private func showPanel() {
        if panel == nil {
            let newPanel = NotchPanel(
                contentRect: NSRect(x: 0, y: 0, width: RoamWindow.width, height: RoamWindow.height),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            newPanel.isFloatingPanel = true
            newPanel.level = .statusBar // arriba del Dock
            newPanel.backgroundColor = .clear
            newPanel.isOpaque = false
            newPanel.hasShadow = false
            newPanel.hidesOnDeactivate = false
            newPanel.isMovable = false
            newPanel.isReleasedWhenClosed = false
            newPanel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
            // Sin tocar ignoresMouseEvents: los clics en lo transparente pasan a lo de abajo.
            let host = FirstMouseHostingView(rootView: RoamingBuddyView(model: model, size: size, onTap: { [weak self] in
                self?.poke()
            }))
            host.sizingOptions = []
            host.frame = NSRect(x: 0, y: 0, width: RoamWindow.width, height: RoamWindow.height)
            host.autoresizingMask = [.width, .height]
            newPanel.contentView = host
            panel = newPanel
        }
        moveWindow()
        panel?.orderFrontRegardless()
    }

    private func moveWindow() {
        panel?.setFrameOrigin(NSPoint(x: position.x - RoamWindow.width / 2, y: position.y - RoamWindow.height / 2))
    }

    // MARK: Dónde camina

    private func computeSurface(on screen: NSScreen) {
        let frame = screen.frame
        let dockShown = screen.visibleFrame.minY - frame.minY > 10 // si el Dock se esconde solo, caminamos abajo
        if dockShown, let dock = DockGeometry.frame(), dock.width > dock.height,
           frame.intersects(dock), dock.minY >= frame.minY - 2, dock.maxY < frame.midY {
            floorY = dock.maxY - 3 // los pies arriba de los íconos
            range = (dock.minX + 24)...max(dock.minX + 25, dock.maxX - 24)
        } else {
            floorY = screen.visibleFrame.minY + 1
            range = (frame.minX + 70)...max(frame.minX + 71, frame.maxX - 70)
        }
    }

    // MARK: Cada cuadro

    private func step() {
        let now = Date()
        let dt = CGFloat(min(now.timeIntervalSince(lastTick), 0.1))
        lastTick = now
        let t = now.timeIntervalSinceReferenceDate
        var pose = BuddyPose()
        pose.propTime = t
        pose.facing = facing
        pose.eyes = t.truncatingRemainder(dividingBy: 3.5) < 0.12 ? .closed : .open
        var scene = StageFrame(x: cx, y: cy, pose: pose)

        switch phase {
        case .falling(let vx, let vy, let parachute):
            scene = fall(vx: vx, vy: vy, parachute: parachute, dt: dt, t: t, now: now, base: pose)

        case .landing(let until):
            let k = CGFloat(max(until.timeIntervalSince(now), 0) / 0.35)
            scene.pose.scaleY = 1 - 0.3 * k
            scene.pose.scaleX = 1 + 0.2 * k
            if k > 0.5 { scene.pose.eyes = .closed }
            if now >= until { pickNext() }

        case .walking(let target):
            let direction: CGFloat = target > position.x ? 1 : -1
            facing = direction
            position.x += direction * 55 * dt
            walkPhase += Double(dt) * 2.4
            scene.pose.facing = direction
            scene.pose.walk = walkPhase
            scene.pose.dy = -CGFloat(abs(sin(walkPhase * .pi))) * size * 0.05
            scene.pose.lookX = direction * 0.5
            if (direction > 0 && position.x >= target) || (direction < 0 && position.x <= target) {
                position.x = target
                pickNext()
            }

        case .skating(let target):
            let direction: CGFloat = target > position.x ? 1 : -1
            facing = direction
            position.x += direction * 125 * dt
            scene.pose.facing = direction
            scene.pose.eyes = .happy
            scene.pose.mouth = .smile
            scene.pose.arm = -20 + 12 * sin(t * 7)
            scene.pose.lookX = direction * 0.6
            scene.y = cy - size * 0.3
            scene.vehicle = StageVehicle(kind: .skateboard, x: cx, y: cy + size * 0.3, facing: direction)
            if (direction > 0 && position.x >= target) || (direction < 0 && position.x <= target) {
                position.x = target
                pickNext()
            }

        case .driving(let start, let from, let target):
            scene = drive(start: start, from: from, target: target, t: t, now: now, base: pose)

        case .visiting(let start, let from):
            scene = visit(start: start, from: from, t: t, now: now, base: pose)

        case .activity(let action, let start, let duration):
            let elapsed = now.timeIntervalSince(start)
            scene.pose = CompanionAnimator.pose(for: action, elapsed: elapsed, progress: min(elapsed / duration, 1),
                                                time: t, facing: facing, size: size)
            if elapsed >= duration { pickNext() }

        case .magic(let start, let target):
            scene = magicStep(start: start, target: target, t: t, now: now)

        case .napping(let until):
            scene.pose.eyes = .sleepy
            scene.pose.prop = .zzz
            scene.pose.scaleY = 1 + CGFloat(sin(t * 1.6)) * 0.04
            if now >= until { pickNext() }

        case .jumping(let vy):
            let newVY = vy - RoamController.gravity * dt
            position.y += newVY * dt
            scene.pose.eyes = .happy
            scene.pose.mouth = .smile
            scene.pose.arm = -90
            scene.pose.prop = .heart
            scene.pose.propTime = Double(max(0, 1 - newVY / 500))
            if position.y - size / 2 <= floorY {
                position.y = floorY + size / 2
                phase = .landing(until: now.addingTimeInterval(0.3))
            } else {
                phase = .jumping(vy: newVY)
            }

        case .returning(let style, let from, let start):
            guard let flying = flyHome(style: style, from: from, start: start, t: t, now: now, base: pose) else {
                finish()
                return
            }
            scene = flying

        case .flyingTo(let from, let to, let start, let duration):
            scene = flyTo(from: from, to: to, start: start, duration: duration, t: t, now: now, base: pose)

        case .presenting(let start):
            scene = presentStep(start: start, t: t, now: now, base: pose)
        }

        model.scene = scene
        moveWindow()
    }

    // MARK: Caída

    private func fall(vx: CGFloat, vy: CGFloat, parachute: Bool, dt: CGFloat, t: Double, now: Date,
                      base: BuddyPose) -> StageFrame {
        var pose = base
        var newVY = vy - RoamController.gravity * dt
        if parachute { newVY = max(newVY, -RoamController.parachuteSpeed) }
        position.x += vx * dt
        position.y += newVY * dt
        var scene = StageFrame(x: cx, y: cy, pose: pose)
        if parachute && newVY < 0 {
            pose.eyes = .happy
            pose.mouth = .smile
            pose.arm = -100
            pose.rotation = sin(t * 2) * 8
            scene.vehicle = StageVehicle(kind: .parachute, x: cx, y: cy, tilt: pose.rotation)
        } else {
            pose.eyes = .big
            pose.mouth = .open
            pose.mouthOpen = 0.8
            pose.arm = -85
            pose.rotation = sin(t * 8) * 10
        }
        scene.pose = pose
        if position.y - size / 2 <= floorY {
            position.y = floorY + size / 2
            phase = .landing(until: now.addingTimeInterval(0.35))
        } else {
            phase = .falling(vx: vx, vy: newVY, parachute: parachute)
        }
        return scene
    }

    // MARK: Coche

    /// Llega el coche, se sube, pita, maneja a otro lado del Dock, se baja y el coche se va.
    private func drive(start: Date, from: CGFloat, target: CGFloat, t: Double, now: Date, base: BuddyPose) -> StageFrame {
        let e = now.timeIntervalSince(start)
        let dir: CGFloat = target >= from ? 1 : -1
        let driveTime = max(Double(abs(target - from) / 150), 0.8)
        let carY = cy + size * 0.18
        let seatY = carY - size * 0.42
        let driveStart = 1.4
        let driveEnd = driveStart + driveTime
        let outEnd = driveEnd + 0.5
        let leaveEnd = outEnd + 0.9
        var pose = base
        pose.facing = dir
        facing = dir
        var mascotX = cx
        var mascotY = cy
        var carRel: CGFloat = 0
        var carOpacity = 1.0
        var moving = false
        var label: StageLabel?

        if e < 0.9 {
            carRel = -dir * 125 * (1 - CompanionAnimator.easeOut(e / 0.9))
            carOpacity = CompanionAnimator.clamp01(e / 0.35)
            moving = true
            pose.facing = -dir
            pose.lookX = -dir * 0.8
            if e > 0.5 { pose.eyes = .big }
        } else if e < driveStart {
            let k = (e - 0.9) / 0.5
            mascotY = CompanionAnimator.lerp(cy, seatY, CompanionAnimator.ease(k)) - CompanionAnimator.arc(k) * size * 0.7
            pose.eyes = .happy
            pose.arm = -80
        } else if e < driveEnd {
            let k = (e - driveStart) / driveTime
            position.x = from + (target - from) * CompanionAnimator.ease(k)
            mascotY = seatY - CGFloat(abs(sin(e * 9))) * size * 0.04
            moving = true
            pose.eyes = .happy
            pose.mouth = .smile
            pose.arm = -60 + 20 * sin(t * 6)
            if e - driveStart < 0.8 {
                label = StageLabel(x: cx + dir * size * 0.6, y: cy - size * 1.4, text: "¡pip pip!")
            }
        } else if e < outEnd {
            let k = (e - driveEnd) / 0.5
            position.x = target
            mascotX = cx - dir * size * 1.4 * CompanionAnimator.ease(k)
            mascotY = CompanionAnimator.lerp(seatY, cy, CompanionAnimator.ease(k)) - CompanionAnimator.arc(k) * size * 0.7
            pose.facing = -dir
            pose.eyes = .happy
        } else if e < leaveEnd {
            let k = (e - outEnd) / 0.9
            mascotX = cx - dir * size * 1.4
            carRel = dir * 125 * CompanionAnimator.easeIn(k)
            carOpacity = 1 - CompanionAnimator.clamp01((k - 0.4) / 0.6)
            moving = true
            pose.arm = -60 + 35 * sin(t * 10)
            pose.eyes = .happy
            pose.mouth = .smile
        } else {
            // Se bajó a un ladito: la ventanita se vuelve a centrar en él.
            position.x = target - dir * size * 1.4
            pickNext()
            return StageFrame(x: cx, y: cy, pose: pose)
        }
        let car = StageVehicle(kind: .car, x: cx + carRel, y: carY, facing: dir,
                               opacity: carOpacity, time: moving ? t : 0)
        return StageFrame(x: mascotX, y: mascotY, pose: pose, vehicle: car, label: label)
    }

    // MARK: Visita del amigo

    private func visit(start: Date, from side: CGFloat, t: Double, now: Date, base: BuddyPose) -> StageFrame {
        let e = now.timeIntervalSince(start)
        let far = side * 125
        let near = side * size * 1.15
        var pose = base
        pose.facing = side
        facing = side
        var friend = BuddyPose()
        friend.propTime = t + 1.3
        friend.facing = -side
        friend.eyes = (t + 1.3).truncatingRemainder(dividingBy: 3.7) < 0.12 ? .closed : .open
        var fRel = near
        var y = cy
        let floorFriend = cy + size * 0.06
        var fy = floorFriend
        var fOpacity = 1.0

        switch e {
        case ..<1.4:
            let k = e / 1.4
            fRel = CompanionAnimator.lerp(far, near, CompanionAnimator.ease(k))
            fOpacity = CompanionAnimator.clamp01(e / 0.3)
            friend.walk = e * 2.4
            pose.eyes = k > 0.5 ? .happy : .big
        case ..<2.6:
            pose.arm = -60 + 35 * sin(t * 10)
            pose.eyes = .happy
            pose.mouth = .smile
            friend.arm = -60 + 35 * sin(t * 10 + 1)
            friend.eyes = .happy
            friend.mouth = .smile
        case ..<3.3:
            let k = (e - 2.6) / 0.7
            let jump = CompanionAnimator.arc(k) * size * 0.5
            y = cy - jump
            fy = floorFriend - jump
            pose.arm = -110
            friend.arm = -110
            pose.eyes = .happy
            friend.eyes = .happy
            if k > 0.4 && k < 0.9 { pose.prop = .sparkles }
        case ..<6.0:
            pose = CompanionAnimator.pose(for: .dance, elapsed: e, progress: 0.5, time: t, facing: side, size: size)
            friend = CompanionAnimator.pose(for: .dance, elapsed: e, progress: 0.5, time: t + 0.5, facing: -side, size: size)
            friend.prop = .none
        case ..<6.8:
            pose.prop = .heart
            pose.propTime = e - 6.0
            pose.eyes = .happy
            pose.mouth = .smile
            friend.eyes = .happy
            friend.mouth = .smile
            friend.dy = -CGFloat(abs(sin(t * 5))) * size * 0.08
        case ..<8.4:
            let k = (e - 6.8) / 1.6
            fRel = CompanionAnimator.lerp(near, far, CompanionAnimator.ease(k))
            fOpacity = 1 - CompanionAnimator.clamp01((e - 8.1) / 0.3)
            friend.facing = side
            friend.walk = e * 2.4
            pose.arm = -60 + 35 * sin(t * 10)
            pose.eyes = .happy
        case ..<9.0:
            fOpacity = 0
            pose.eyes = .happy
            pose.mouth = .smile
        default:
            pickNext()
            return StageFrame(x: cx, y: cy, pose: pose)
        }
        let buddy = StageFriend(x: cx + fRel, y: fy, pose: friend, opacity: fOpacity)
        return StageFrame(x: cx, y: y, pose: pose, friend: buddy)
    }

    // MARK: Magia

    /// Varita, ¡puf!, y aparece en otro lugar del Dock.
    private func magicStep(start: Date, target: CGFloat, t: Double, now: Date) -> StageFrame {
        let e = now.timeIntervalSince(start)
        let duration = CompanionAction.magic.randomDuration
        let pose = CompanionAnimator.pose(for: .magic, elapsed: e, progress: min(e / duration, 1), time: t,
                                          facing: facing, size: size)
        var puffs: [StagePuff] = []
        if e > 1.5 && e < 2.2 {
            puffs.append(StagePuff(x: cx, y: cy, progress: CGFloat((e - 1.5) / 0.7)))
        }
        if e >= 2.2 {
            position.x = target
        }
        if e > 2.6 && e < 3.3 {
            puffs.append(StagePuff(x: cx, y: cy, progress: CGFloat((e - 2.6) / 0.7)))
        }
        if e >= duration { pickNext() }
        return StageFrame(x: cx, y: cy, pose: pose, puffs: puffs)
    }

    // MARK: Regreso al notch

    private func flyHome(style: ReturnStyle, from: NSPoint, start: Date, t: Double, now: Date,
                         base: BuddyPose) -> StageFrame? {
        let e = now.timeIntervalSince(start)
        let target = home?() ?? from
        switch style {
        case .balloon:
            let k = CompanionAnimator.ease(e / 4)
            position.x = from.x + (target.x - from.x) * k + CGFloat(sin(t * 2)) * 10 * (1 - k)
            position.y = from.y + (target.y - from.y) * k
            if k >= 1 { return nil }
            var pose = base
            pose.prop = .balloon
            pose.arm = -95
            pose.eyes = .happy
            pose.lookY = -0.6
            return StageFrame(x: cx, y: cy, pose: pose)
        case .ufo:
            return ufoReturn(e: e, from: from, target: target, t: t, base: base)
        case .rocket:
            return rocketReturn(e: e, from: from, target: target, t: t, base: base)
        case .propeller:
            let k = CompanionAnimator.ease(e / 1.2)
            position.x = from.x + (target.x - from.x) * k
            position.y = from.y + (target.y - from.y) * k + CompanionAnimator.arc(e / 1.2) * 40
            if k >= 1 { return nil }
            var pose = base
            pose.prop = .propeller
            pose.facing = target.x >= from.x ? 1 : -1
            pose.rotation = Double(pose.facing) * 10
            pose.arm = -20
            pose.eyes = .happy
            pose.lookY = -0.4
            return StageFrame(x: cx, y: cy, pose: pose)
        }
    }

    // MARK: Presentar una ventana

    /// Vuela (con su gorrito de hélice) del notch a la orilla de la ventana.
    private func flyTo(from: NSPoint, to: NSPoint, start: Date, duration: Double, t: Double, now: Date,
                       base: BuddyPose) -> StageFrame {
        let e = now.timeIntervalSince(start)
        let k = CompanionAnimator.ease(e / duration)
        // Un arco hacia un lado para que se vea que vuela (no que cae).
        let sideways = CompanionAnimator.arc(e / duration) * 70 * facing
        position.x = from.x + (to.x - from.x) * k + sideways
        position.y = from.y + (to.y - from.y) * k
        var pose = base
        pose.prop = .propeller
        pose.facing = facing
        pose.rotation = Double(facing) * 12
        pose.arm = -15
        pose.eyes = .happy
        pose.mouth = .smile
        pose.lookX = facing * 0.6
        pose.lookY = 0.5
        if e >= duration {
            position = to
            phase = .presenting(start: now)
        }
        return StageFrame(x: cx, y: cy, pose: pose)
    }

    /// Aterriza, "¡tarán!", señala la ventana y saluda.
    private func presentStep(start: Date, t: Double, now: Date, base: BuddyPose) -> StageFrame {
        let e = now.timeIntervalSince(start)
        var pose = base
        pose.facing = facing
        var label: StageLabel?
        switch e {
        case ..<0.3:
            let k = CompanionAnimator.arc(e / 0.3)
            pose.scaleY = 1 - 0.25 * k
            pose.scaleX = 1 + 0.15 * k
            pose.eyes = .closed
        case ..<1.7:
            pose.eyes = .happy
            pose.mouth = .smile
            pose.prop = .confetti
            pose.arm = -110 + 20 * sin(t * 10)
            pose.dy = -CompanionAnimator.arc((e - 0.3) / 0.5) * size * 0.4
            label = StageLabel(x: cx, y: cy - size * 1.35, text: "¡Aquí está!")
        case ..<2.8:
            // Señala hacia abajo (la ventana) y la mira.
            pose.eyes = .happy
            pose.lookY = 1
            pose.arm = 45
            pose.rotation = Double(facing) * 8
            label = StageLabel(x: cx, y: cy - size * 1.35, text: "¡Aquí está!")
        case ..<3.6:
            pose.eyes = .happy
            pose.mouth = .smile
            pose.arm = -60 + 35 * sin(t * 10)
        default:
            phase = .returning(style: .propeller, from: position, start: now)
        }
        return StageFrame(x: cx, y: cy, pose: pose, label: label)
    }

    /// Un ovni baja, se lo lleva con su rayo y vuela hasta el notch.
    private func ufoReturn(e: Double, from: NSPoint, target: NSPoint, t: Double, base: BuddyPose) -> StageFrame? {
        let saucer = -size * 1.9
        let beamFull = -saucer + size * 0.2
        var pose = base
        var ufoY = cy + saucer
        var beam: CGFloat = 0
        var mascotY = cy

        if e < 1.0 {
            ufoY = cy + CompanionAnimator.lerp(-size * 4.2, saucer, CompanionAnimator.easeOut(e))
            pose.lookY = -1
            if e > 0.5 { pose.eyes = .big }
        } else if e < 1.4 {
            beam = beamFull * CGFloat((e - 1.0) / 0.4)
            pose.lookY = -1
            pose.eyes = .big
            pose.mouth = .open
        } else if e < 2.4 {
            let k = (e - 1.4) / 1.0
            beam = beamFull
            mascotY = CompanionAnimator.lerp(cy, cy + saucer + size * 0.1, CompanionAnimator.ease(k))
            pose.rotation = k * 360
            pose.scaleX = 1 - 0.55 * CGFloat(k)
            pose.scaleY = 1 - 0.55 * CGFloat(k)
            pose.opacity = 1 - CompanionAnimator.clamp01((k - 0.6) / 0.4)
            pose.eyes = .happy
        } else if e < 2.6 {
            beam = beamFull * CGFloat(1 - (e - 2.4) / 0.2)
            pose.opacity = 0
        } else {
            // El ovni va arriba de la ventanita: que sea él quien llegue justo al notch.
            let k = (e - 2.6) / 2.4
            let eased = CompanionAnimator.ease(k)
            position.x = from.x + (target.x - from.x) * eased
            position.y = from.y + (target.y + saucer - from.y) * eased
            pose.opacity = 0
            if k >= 1 { return nil }
        }
        let ufo = StageVehicle(kind: .ufo, x: cx, y: ufoY, value: beam, time: t)
        return StageFrame(x: cx, y: mascotY, pose: pose, vehicle: ufo)
    }

    /// Cuenta regresiva y ¡despega! directo al notch.
    private func rocketReturn(e: Double, from: NSPoint, target: NSPoint, t: Double, base: BuddyPose) -> StageFrame? {
        var pose = base
        pose.eyes = .big
        var rocket = StageVehicle(kind: .rocket, x: cx, y: cy)
        var label: StageLabel?
        var x = cx

        if e < 0.5 {
            rocket.opacity = e / 0.5
            pose.eyes = .happy
        } else if e < 1.8 {
            let k = (e - 0.5) / 1.3
            let count = 3 - min(Int(k * 3), 2)
            label = StageLabel(x: cx + size * 1.5, y: cy - size * 0.2, text: "\(count)")
            x = cx + CGFloat(sin(t * 45)) * size * 0.04 * CGFloat(k)
            rocket.x = x
            rocket.value = 0.2
            rocket.time = t
        } else {
            let k = (e - 1.8) / 1.8
            let kx = CompanionAnimator.ease(k)
            let ky = CompanionAnimator.easeIn(k)
            position.x = from.x + (target.x - from.x) * kx
            position.y = from.y + (target.y - from.y) * ky
            let lean = Double(max(-35, min(35, (target.x - from.x) / 20))) * Double(1 - kx)
            rocket.tilt = lean
            rocket.value = 1
            rocket.time = t
            pose.rotation = lean
            pose.eyes = .closed
            pose.mouth = .open
            if k >= 1 { return nil }
        }
        return StageFrame(x: x, y: cy, pose: pose, vehicle: rocket, label: label)
    }

    // MARK: Qué sigue

    /// Caminar, patineta, coche, visita del amigo, magia, dormir un ratito o hacer algo.
    private func pickNext() {
        if Date().timeIntervalSince(started) > totalDuration {
            startReturn()
            return
        }
        let roll = Int.random(in: 0..<100)
        switch roll {
        case ..<32:
            phase = .walking(target: walkTarget())
        case ..<42:
            phase = .skating(target: walkTarget(minDistance: 140))
        case ..<50:
            phase = .driving(start: Date(), from: position.x, target: walkTarget(minDistance: 180))
        case ..<58:
            phase = .visiting(start: Date(), from: friendSide())
        case ..<64:
            phase = .napping(until: Date().addingTimeInterval(4))
        case ..<69:
            phase = .magic(start: Date(), target: walkTarget(minDistance: 160))
        default:
            let options: [CompanionAction] = [
                .wave, .dance, .read, .coffee, .lookAround, .hop, .heart, .stretch, .yawn, .spin, .sneeze,
                .juggle, .soccer, .umbrella, .bubbles, .photo
            ]
            let action = options.randomElement() ?? .wave
            phase = .activity(action, start: Date(), duration: action.randomDuration)
        }
    }

    /// Un lugar del Dock no muy cerca de donde está.
    private func walkTarget(minDistance: CGFloat = 80) -> CGFloat {
        var target = CGFloat.random(in: range)
        if abs(target - position.x) < minDistance {
            let middle = (range.lowerBound + range.upperBound) / 2
            target = position.x < middle
                ? min(position.x + minDistance * 2, range.upperBound)
                : max(position.x - minDistance * 2, range.lowerBound)
        }
        return target
    }

    /// De qué lado llega el amigo (donde haya espacio).
    private func friendSide() -> CGFloat {
        if range.upperBound - position.x < 60 { return -1 }
        if position.x - range.lowerBound < 60 { return 1 }
        return Bool.random() ? 1 : -1
    }

    private func startReturn() {
        let styles: [ReturnStyle] = [.balloon, .balloon, .ufo, .rocket]
        phase = .returning(style: styles.randomElement() ?? .balloon, from: position, start: Date())
    }

    /// Lo tocaste: brinca con un corazón. Dos toques seguidos = regresa al notch.
    private func poke() {
        if presentingTrip { return }
        let now = Date()
        defer { lastTap = now }
        if now.timeIntervalSince(lastTap) < 0.45 {
            if case .returning = phase { return }
            startReturn()
            return
        }
        switch phase {
        case .walking, .landing, .napping, .activity, .skating:
            phase = .jumping(vy: 420)
        default:
            return
        }
    }

    // MARK: Pantalla completa

    /// true si hay una app en pantalla completa (no salimos a pasear encima de un video).
    static func fullScreenAppActive(on screen: NSScreen) -> Bool {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        let size = screen.frame.size
        // Core Graphics mide desde arriba de la pantalla principal.
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY
        let screenRect = CGRect(x: screen.frame.minX, y: primaryTop - screen.frame.maxY,
                                width: size.width, height: size.height)
        for window in windows {
            guard (window[kCGWindowLayer as String] as? Int) == 0,
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  rect.intersects(screenRect) else { continue }
            if rect.width >= size.width && rect.height >= size.height {
                return true
            }
        }
        return false
    }
}

/// Dónde está la ventana de enfrente de una app (con Accesibilidad). Corre fuera del hilo principal.
enum WindowLocator {
    /// `primaryTop`: la orilla de arriba de la pantalla principal (Accesibilidad mide desde ahí).
    static func frontWindowFrame(pid: pid_t, primaryTop: CGFloat) -> NSRect? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.5)
        var value: CFTypeRef?
        var window: AXUIElement?
        for attribute in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
            if AXUIElementCopyAttributeValue(app, attribute as CFString, &value) == .success,
               let found = value, CFGetTypeID(found) == AXUIElementGetTypeID() {
                window = (found as! AXUIElement)
                break
            }
        }
        guard let window = window,
              let origin = point(window), let size = size(window),
              size.width > 80, size.height > 60 else { return nil }
        // Accesibilidad mide desde arriba de la pantalla principal; macOS, desde abajo.
        return NSRect(x: origin.x, y: primaryTop - origin.y - size.height, width: size.width, height: size.height)
    }

    static func point(_ element: AXUIElement) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &value) == .success,
              let value = value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var result = CGPoint.zero
        guard AXValueGetValue(value as! AXValue, .cgPoint, &result) else { return nil }
        return result
    }

    static func size(_ element: AXUIElement) -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &value) == .success,
              let value = value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var result = CGSize.zero
        guard AXValueGetValue(value as! AXValue, .cgSize, &result) else { return nil }
        return result
    }
}

/// Dónde está el Dock (con Accesibilidad, el mismo permiso que ya usa Isla).
@MainActor
enum DockGeometry {
    static func frame() -> NSRect? {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
            return nil
        }
        let app = AXUIElementCreateApplication(dock.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.5)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXChildrenAttribute as CFString, &value) == .success,
              let children = value as? [AXUIElement] else { return nil }
        for child in children {
            var role: CFTypeRef?
            guard AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &role) == .success,
                  (role as? String) == kAXListRole,
                  let origin = WindowLocator.point(child), let size = WindowLocator.size(child) else { continue }
            // Accesibilidad mide desde arriba de la pantalla principal; macOS, desde abajo.
            let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
            return NSRect(x: origin.x, y: primaryTop - origin.y - size.height, width: size.width, height: size.height)
        }
        return nil
    }

}
