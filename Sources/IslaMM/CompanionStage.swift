import SwiftUI

// El escenario del compañero junto al notch: calcula dónde está y cómo se ve
// en cada instante (camina de un ala a la otra, se cuelga de un hilo, baila…).

/// Dónde dibujar al personaje y con qué pose.
struct StageFrame {
    var x: CGFloat
    var y: CGFloat
    var pose: BuddyPose
    /// Si está colgado de un hilo: desde qué altura baja el hilo.
    var threadTop: CGFloat? = nil
    var vehicle: StageVehicle? = nil
    var friend: StageFriend? = nil
    var puffs: [StagePuff] = []
    var label: StageLabel? = nil
}

enum CompanionAnimator {
    static func ease(_ value: Double) -> CGFloat {
        let clamped = min(max(value, 0), 1)
        return CGFloat(clamped * clamped * (3 - 2 * clamped))
    }

    static func clamp01(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    /// Qué tanto va (0…1) dentro del tramo de `from` a `to` segundos.
    static func segment(_ elapsed: Double, _ from: Double, _ to: Double) -> Double {
        clamp01((elapsed - from) / max(to - from, 0.001))
    }

    static func lerp(_ a: CGFloat, _ b: CGFloat, _ k: CGFloat) -> CGFloat {
        a + (b - a) * k
    }

    static func easeIn(_ value: Double) -> CGFloat {
        let c = clamp01(value)
        return CGFloat(c * c)
    }

    static func easeOut(_ value: Double) -> CGFloat {
        let c = clamp01(value)
        return CGFloat(1 - (1 - c) * (1 - c))
    }

    /// Sube y baja (0 → 1 → 0), para brincos.
    static func arc(_ value: Double) -> CGFloat {
        CGFloat(sin(clamp01(value) * Double.pi))
    }

    /// Pose de una travesura que no cambia de lugar (también la usa el paseo por la pantalla).
    /// `elapsed` en segundos desde que empezó, `progress` de 0 a 1.
    static func pose(for action: CompanionAction, elapsed: Double, progress p: Double, time t: Double,
                     facing: CGFloat, size: CGFloat) -> BuddyPose {
        var pose = BuddyPose()
        pose.propTime = t
        pose.facing = facing
        let blinking = t.truncatingRemainder(dividingBy: 3.7) < 0.12
        pose.eyes = blinking ? .closed : .open

        switch action {
        case .rest, .peek, .walkAcross, .dangle, .skateboard, .car, .rocket, .ufo, .plane, .friend:
            pose.scaleY = 1 + CGFloat(sin(t * 2)) * 0.03
            pose.lookX = CGFloat(sin(t * 0.5)) * 0.5
        case .lookAround:
            let look = CGFloat(sin(p * .pi * 3))
            pose.lookX = look
            pose.rotation = Double(look) * 8
        case .hop:
            let hop = (p * 2).truncatingRemainder(dividingBy: 1)
            pose.dy = -CGFloat(sin(hop * .pi)) * size * 0.28
            if p < 1 && (hop < 0.12 || hop > 0.88) {
                pose.scaleY = 0.85
                pose.scaleX = 1.1
            }
            pose.eyes = .happy
        case .spin:
            pose.rotation = Double(ease(p)) * 360
            pose.eyes = p > 0.85 ? .dizzy : .happy
        case .wave:
            pose.arm = -60 + 35 * sin(t * 10)
            pose.mouth = .smile
            if p > 0.2 { pose.eyes = .happy }
        case .yawn:
            if p < 0.65 {
                let k = sin(p / 0.65 * .pi)
                pose.eyes = .closed
                pose.mouth = .open
                pose.mouthOpen = CGFloat(k)
                pose.scaleY = 1 + CGFloat(k) * 0.1
                pose.arm = -90 * k
            }
        case .dance:
            let beat = sin(t * 6)
            pose.dx = CGFloat(beat) * size * 0.18
            pose.rotation = beat * 12
            pose.walk = t * 3
            pose.prop = .notes
            pose.eyes = .happy
            pose.mouth = .smile
        case .coffee:
            let sipping = elapsed.truncatingRemainder(dividingBy: 2.4) > 1.3 && elapsed.truncatingRemainder(dividingBy: 2.4) < 1.9
            pose.prop = .cup
            pose.arm = sipping ? -70 : -15
            if sipping { pose.eyes = .closed }
            pose.lookX = facing * 0.4
        case .stretch:
            let k = sin(p * .pi)
            pose.scaleY = 1 + CGFloat(k) * 0.25
            pose.scaleX = 1 - CGFloat(k) * 0.12
            pose.arm = -90 * k
            if k > 0.5 { pose.eyes = .closed }
            pose.mouth = .small
        case .read:
            pose.prop = .book
            pose.lookY = 0.9
            pose.lookX = CGFloat(sin(t * 1.5)) * 0.5
        case .heart:
            pose.prop = .heart
            pose.propTime = elapsed
            pose.eyes = .happy
            pose.mouth = .smile
            pose.dy = -CGFloat(abs(sin(t * 5))) * size * 0.08
        case .sneeze:
            if p < 0.45 {
                let k = p / 0.45
                pose.eyes = .closed
                pose.mouth = .open
                pose.mouthOpen = CGFloat(k) * 0.5
                pose.scaleY = 1 + CGFloat(k) * 0.1
                pose.rotation = -6 * Double(facing) * k
            } else if p < 0.6 {
                pose.eyes = .closed
                pose.mouth = .open
                pose.mouthOpen = 1
                pose.scaleY = 0.85
                pose.dx = facing * size * 0.2 * CGFloat(sin((p - 0.45) / 0.15 * .pi))
                pose.prop = .sweat
            }
        case .juggle:
            pose.prop = .juggle
            pose.arm = -45 + 30 * sin(t * 8)
            pose.lookX = facing * 0.6
            pose.lookY = -0.4
            pose.mouth = .small
            pose.dy = CGFloat(sin(t * 8)) * size * 0.02
        case .soccer:
            pose.prop = .soccer
            pose.propTime = elapsed * 1.5
            pose.propOffset = soccerBall(elapsed: elapsed, facing: facing, size: size)
            let kick = segment(elapsed, 0.55, 0.95)
            if kick > 0 && kick < 1 {
                pose.rotation = -Double(facing) * 12 * sin(kick * Double.pi)
                pose.eyes = .big
            }
            pose.lookX = facing * 0.8
            pose.lookY = 0.4
            if elapsed > 3.4 {
                pose.eyes = .happy
                pose.mouth = .smile
            }
        case .umbrella:
            pose.prop = .umbrella
            // Clima: 0 → 1 llega la nube; 1 → 2 sale el sol.
            let weather: Double
            if elapsed < 1.2 {
                weather = elapsed / 1.2
            } else if elapsed < 5.4 {
                weather = 1
            } else {
                weather = 1 + segment(elapsed, 5.4, 6.2)
            }
            pose.propValue2 = CGFloat(weather)
            let opening = segment(elapsed, 1.5, 2.0)
            let closing = segment(elapsed, 6.0, 6.5)
            pose.propValue = CGFloat(opening * (1 - closing))
            pose.lookY = -0.8
            if opening > 0 && closing < 1 {
                pose.arm = -60
            }
            if elapsed > 1.2 && elapsed < 1.6 {
                pose.eyes = .closed
            }
            if elapsed > 2.0 && elapsed < 5.4 {
                pose.mouth = .smile
            }
            if elapsed > 5.8 {
                pose.eyes = .happy
                pose.mouth = .smile
            }
        case .bubbles:
            pose.prop = .bubbles
            pose.propValue2 = 1
            pose.mouth = .small
            let blow = sin(t * 2.5)
            pose.scaleX = 1 + CGFloat(max(blow, 0)) * 0.06
            pose.arm = -20
            pose.lookX = facing * 0.7
            if blow > 0.6 {
                pose.eyes = .closed
            }
        case .photo:
            pose.prop = .camera
            pose.arm = -10
            pose.lookY = 0.4
            pose.propValue = CGFloat(segment(elapsed, 1.3, 1.65))
            pose.propValue2 = CGFloat(segment(elapsed, 1.9, 3.0))
            if elapsed > 1.25 && elapsed < 1.5 {
                pose.eyes = .closed
            }
            if elapsed > 2.0 {
                pose.eyes = .happy
                pose.mouth = .smile
            }
        case .magic:
            if elapsed < 1.7 {
                pose.prop = .wand
                pose.arm = -50 + 30 * sin(t * 9)
                pose.eyes = elapsed < 0.8 ? .big : .happy
            } else if elapsed > 3.0 {
                pose.prop = .sparkles
                pose.eyes = .happy
                pose.mouth = .smile
            }
            if elapsed >= 1.6 && elapsed < 2.75 {
                pose.opacity = 1 - segment(elapsed, 1.6, 1.75)
            } else if elapsed >= 2.75 {
                pose.opacity = segment(elapsed, 2.75, 2.95)
            }
        case .fishing:
            pose.prop = .fishing
            let cast = segment(elapsed, 0.7, 1.6)
            let reel = segment(elapsed, 6.0, 6.9)
            pose.propValue = CGFloat(cast * (1 - reel))
            if elapsed > 5.2 && elapsed < 6.0 {
                pose.propValue2 = -CGFloat(abs(sin((elapsed - 5.2) * 14)))
                pose.eyes = .big
            } else if elapsed >= 6.0 {
                pose.propValue2 = CGFloat(reel)
            }
            pose.arm = (elapsed >= 6.0 && elapsed < 6.9) ? -70 : -25
            pose.lookX = facing * 0.7
            pose.lookY = 0.7
            if elapsed >= 6.9 {
                pose.eyes = .happy
                pose.mouth = .smile
                pose.lookY = 0
                pose.dy = -CGFloat(abs(sin(t * 5))) * size * 0.1
            }
        }
        return pose
    }

    /// Dónde va la pelota: la patea, rebota lejos, regresa rodando y dominadas.
    private static func soccerBall(elapsed e: Double, facing: CGFloat, size: CGFloat) -> CGSize {
        let ground: CGFloat = size * 0.33
        if e < 0.8 {
            return CGSize(width: facing * size * 0.55, height: ground)
        } else if e < 2.2 {
            let k = segment(e, 0.8, 2.2)
            let x: CGFloat = facing * size * (0.55 + 2.8 * easeOut(k))
            let bounce: CGFloat = CGFloat(abs(sin(k * 3 * Double.pi))) * size * 0.6 * CGFloat(1 - k * 0.6)
            return CGSize(width: x, height: ground - bounce)
        } else if e < 3.4 {
            let k = segment(e, 2.2, 3.4)
            let x: CGFloat = facing * size * (3.35 - 2.8 * ease(k))
            return CGSize(width: x, height: ground)
        } else {
            let bounce: CGFloat = CGFloat(abs(sin((e - 3.4) * 6))) * size * 0.7
            return CGSize(width: facing * size * 0.5, height: size * 0.25 - bounce)
        }
    }
}

/// Hacia dónde mira el compañero, copiado en un instante.
struct GazeSnapshot {
    var x: CGFloat = 0
    var down: CGFloat = 0
    var tracking = false
    var excited = false
}

/// Todo lo que hace falta para dibujar al compañero junto al notch.
struct CompanionStageInput {
    let action: CompanionAction
    let actionStart: Date
    let actionDuration: Double
    let side: CompanionSide
    let mood: CompanionMood
    let celebrateUntil: Date
    let talkUntil: Date
    let panelWidth: CGFloat
    let notchWidth: CGFloat
    let notchHeight: CGFloat
    let wing: CGFloat
    let size: CGFloat

    private func homeX(_ side: CompanionSide) -> CGFloat {
        let offset = notchWidth / 2 + wing / 2
        return side == .left ? panelWidth / 2 - offset : panelWidth / 2 + offset
    }

    func frame(at date: Date, gaze: GazeSnapshot) -> StageFrame {
        let t = date.timeIntervalSinceReferenceDate
        let elapsed = date.timeIntervalSince(actionStart)
        let progress = min(max(elapsed / max(actionDuration, 0.1), 0), 1)
        let towardNotch: CGFloat = side == .left ? 1 : -1
        let outward = -towardNotch
        let baseY = notchHeight / 2
        var x = homeX(side)
        var y = baseY
        var threadTop: CGFloat?
        var pose = CompanionAnimator.pose(for: .rest, elapsed: elapsed, progress: progress, time: t,
                                          facing: outward, size: size)

        // 1) Lo que pasa con Claude o contigo tiene prioridad sobre las travesuras.
        if date < celebrateUntil {
            pose.eyes = .happy
            pose.mouth = .smile
            pose.prop = .confetti
            pose.arm = -80 + 25 * sin(t * 10)
            pose.dy = -CGFloat(abs(sin(t * 6))) * size * 0.2
            return StageFrame(x: x, y: y, pose: pose, threadTop: nil)
        }
        switch mood {
        case .listening:
            pose.eyes = .big
            pose.ring = true
            pose.lookY = -0.3
            pose.dy = CGFloat(sin(t * 3)) * size * 0.05
            return StageFrame(x: x, y: y, pose: pose, threadTop: nil)
        case .waiting:
            pose.eyes = .big
            pose.prop = .exclamation
            pose.arm = -70 + 30 * sin(t * 9)
            pose.dy = -CGFloat(abs(sin(t * 5))) * size * 0.18
            return StageFrame(x: x, y: y, pose: pose, threadTop: nil)
        case .working:
            pose = BuddyPose.status(.working, time: t)
            pose.facing = outward
            return StageFrame(x: x, y: y, pose: pose, threadTop: nil)
        case .happy:
            pose.eyes = .happy
            pose.mouth = .smile
            pose.prop = .sparkles
            pose.dy = -CGFloat(abs(sin(t * 3))) * size * 0.12
            return StageFrame(x: x, y: y, pose: pose, threadTop: nil)
        case .sleepy:
            pose.eyes = .sleepy
            pose.prop = .zzz
            pose.scaleY = 1 + CGFloat(sin(t * 1.6)) * 0.04
            pose.rotation = -8 * Double(towardNotch)
            pose.dy = size * 0.05
            return StageFrame(x: x, y: y, pose: pose, threadTop: nil)
        case .hot:
            // La Mac va a tope: suda, se abanica y jadea.
            pose.prop = .hot
            pose.eyes = .sleepy
            pose.mouth = .open
            pose.mouthOpen = 0.35 + 0.25 * CGFloat(abs(sin(t * 5)))
            pose.arm = -35 + 30 * sin(t * 14)
            pose.scaleY = 1 - CGFloat(abs(sin(t * 2.5))) * 0.05
            return StageFrame(x: x, y: y, pose: pose, threadTop: nil)
        case .lowBattery:
            // Poca batería: tiembla y se ve cansado.
            pose.prop = .lowBattery
            pose.eyes = .sleepy
            pose.mouth = .small
            pose.dx = CGFloat(sin(t * 45)) * size * 0.035
            pose.scaleY = 0.94
            pose.lookY = 0.4
            return StageFrame(x: x, y: y, pose: pose, threadTop: nil)
        case .grooving:
            // Suena tu música: entre travesura y travesura mueve la cabeza al ritmo.
            if action == .rest && !gaze.excited {
                let beat = sin(t * 4.4)
                pose.prop = .notes
                pose.rotation = beat * 10
                pose.dy = -CGFloat(abs(beat)) * size * 0.1
                pose.walk = t * 2.2
                pose.eyes = t.truncatingRemainder(dividingBy: 4) < 2.4 ? .happy : .open
                pose.mouth = .smile
                pose.lookX = CGFloat(beat) * 0.4
                return StageFrame(x: x, y: y, pose: pose, threadTop: nil)
            }
        case .idle:
            break
        }

        // 2) Si acercas el mouse, te ve y se emociona.
        let calm = action == .rest || action == .lookAround
        if calm && gaze.excited {
            pose.eyes = .big
            pose.lookX = gaze.x
            pose.lookY = gaze.down
            pose.mouth = .small
            pose.dy = -CGFloat(abs(sin(t * 6))) * size * 0.16
            return StageFrame(x: x, y: y, pose: pose, threadTop: nil)
        }

        // 3) Travesuras grandes (vehículos, su amigo, magia, pesca)
        if let special = travelFrame(elapsed: elapsed, progress: progress, time: t) {
            return talking(special, date: date, time: t)
        }

        // 4) Travesuras en su lugar
        switch action {
        case .rest:
            if gaze.tracking {
                pose.lookX = gaze.x
                pose.lookY = gaze.down
            }
        case .peek:
            // Se esconde detrás del notch, se asoma a medias y sale de un brinco.
            let distance = wing / 2 + size / 2 + 4
            let offset: CGFloat
            var curious = false
            switch elapsed {
            case ..<0.5: offset = distance * CompanionAnimator.ease(elapsed / 0.5)
            case ..<1.8: offset = distance
            case ..<2.2:
                offset = distance - distance * 0.5 * CompanionAnimator.ease((elapsed - 1.8) / 0.4)
                curious = true
            case ..<3.4:
                offset = distance * 0.5
                curious = true
            case ..<3.8:
                let k = (elapsed - 3.4) / 0.4
                offset = distance * 0.5 * (1 - CompanionAnimator.ease(k)) - CGFloat(sin(k * .pi)) * size * 0.12
            default: offset = 0
            }
            x += towardNotch * offset
            if curious {
                pose.lookX = CGFloat(sin(t * 7)) * 0.9
                pose.eyes = .big
            }
        case .walkAcross:
            // Camina al otro lado pasando por detrás del notch.
            let from = homeX(side)
            let to = homeX(side.other)
            x = from + (to - from) * CompanionAnimator.ease(progress)
            pose.facing = to > from ? 1 : -1
            if progress < 1 {
                pose.walk = elapsed * 2.2
                pose.lookX = pose.facing * 0.6
                pose.dy = -CGFloat(abs(sin(elapsed * .pi * 2.2))) * size * 0.06
            }
        case .dangle:
            // Baja colgado de un hilo, se columpia y vuelve a subir.
            let drop = notchHeight * 0.55 + size * 1.1
            if progress < 0.18 {
                y = baseY + drop * CompanionAnimator.ease(progress / 0.18)
                pose.eyes = .big
            } else if progress < 0.82 {
                let swing = sin(elapsed * 3) * 14
                y = baseY + drop
                pose.dx = CGFloat(sin(swing * .pi / 180)) * drop * 0.6
                pose.rotation = -swing * 0.6
                pose.eyes = .happy
                pose.mouth = .smile
                pose.arm = -100
            } else {
                y = baseY + drop * (1 - CompanionAnimator.ease((progress - 0.82) / 0.18))
                pose.walk = elapsed * 3
                pose.arm = -100
            }
            if y > baseY + 2 { threadTop = baseY }
        default:
            pose = CompanionAnimator.pose(for: action, elapsed: elapsed, progress: progress, time: t,
                                          facing: outward, size: size)
            // Junto al notch no hay espacio arriba: las burbujas se van de lado.
            if action == .bubbles { pose.propValue2 = 0.15 }
        }

        return talking(StageFrame(x: x, y: y, pose: pose, threadTop: threadTop), date: date, time: t)
    }

    /// Cuando te habla en un globito, mueve la boca.
    private func talking(_ frame: StageFrame, date: Date, time t: Double) -> StageFrame {
        guard date < talkUntil else { return frame }
        var result = frame
        result.pose.mouth = .open
        result.pose.mouthOpen = CGFloat(abs(sin(t * 9)))
        return result
    }

    // MARK: Travesuras grandes

    private var towardNotch: CGFloat { side == .left ? 1 : -1 }
    private var baseY: CGFloat { notchHeight / 2 }

    private func travelFrame(elapsed e: Double, progress p: Double, time t: Double) -> StageFrame? {
        switch action {
        case .skateboard: return skateFrame(p, t)
        case .car: return carFrame(e, t)
        case .rocket: return rocketFrame(e, t)
        case .ufo: return ufoFrame(e, t)
        case .plane: return planeFrame(e, t)
        case .friend: return friendFrame(e, t)
        case .fishing: return fishingFrame(e, p, t)
        case .magic: return magicFrame(e, p, t)
        default: return nil
        }
    }

    private func basePose(_ t: Double, facing: CGFloat) -> BuddyPose {
        var pose = BuddyPose()
        pose.propTime = t
        pose.facing = facing
        pose.eyes = t.truncatingRemainder(dividingBy: 3.7) < 0.12 ? .closed : .open
        return pose
    }

    /// Patineta: se aleja, hace un "ollie", da la vuelta y cruza al otro lado.
    private func skateFrame(_ p: Double, _ t: Double) -> StageFrame {
        let home = homeX(side)
        let to = homeX(side.other)
        let outward = -towardNotch
        let far = home + outward * 60
        var x = home
        var facing = outward
        var hop: CGFloat = 0
        var tilt: Double = 0
        if p < 0.35 {
            x = CompanionAnimator.lerp(home, far, CompanionAnimator.ease(p / 0.35))
            if p > 0.22 {
                let k = (p - 0.22) / 0.13
                hop = CompanionAnimator.arc(k) * size * 0.7
                tilt = -Double(outward) * 22 * Double(CompanionAnimator.arc(k))
            }
        } else if p < 0.45 {
            x = far
            facing = towardNotch
        } else {
            x = CompanionAnimator.lerp(far, to, CompanionAnimator.ease((p - 0.45) / 0.55))
            facing = towardNotch
        }
        var pose = basePose(t, facing: facing)
        pose.eyes = .happy
        pose.mouth = .smile
        pose.lookX = facing * 0.6
        pose.arm = -20 + 12 * sin(t * 7)
        pose.rotation = tilt * 0.6
        let board = StageVehicle(kind: .skateboard, x: x, y: baseY + size * 0.44 - hop, facing: facing, tilt: tilt)
        return StageFrame(x: x, y: baseY - size * 0.16 - hop, pose: pose, vehicle: board)
    }

    /// Llega un cochecito, se sube, pita, cruza al otro lado y se baja.
    private func carFrame(_ e: Double, _ t: Double) -> StageFrame {
        let home = homeX(side)
        let to = homeX(side.other)
        let outward = -towardNotch
        let gap = size * 1.3
        let start = home + outward * 150
        let stop1 = home + outward * gap
        let stop2 = to + towardNotch * gap
        let exit = to + towardNotch * 160
        let carY = baseY + size * 0.28
        let seatY = carY - size * 0.42
        var carX = start
        var carOpacity = 1.0
        var moving = false
        var x = home
        var y = baseY
        var pose = basePose(t, facing: towardNotch)
        var label: StageLabel?

        switch e {
        case ..<1.4:
            carX = CompanionAnimator.lerp(start, stop1, CompanionAnimator.easeOut(e / 1.4))
            carOpacity = CompanionAnimator.clamp01(e / 0.3)
            moving = true
            pose.facing = outward
            pose.lookX = outward * 0.8
            if e > 0.8 { pose.eyes = .big }
        case ..<2.0:
            let k = (e - 1.4) / 0.6
            carX = stop1
            x = CompanionAnimator.lerp(home, stop1, CompanionAnimator.ease(k))
            y = CompanionAnimator.lerp(baseY, seatY, CompanionAnimator.ease(k)) - CompanionAnimator.arc(k) * size * 0.7
            pose.eyes = .happy
            pose.arm = -80
        case ..<2.7:
            carX = stop1 + CGFloat(sin(e * 30)) * 0.6
            x = carX
            y = seatY
            pose.eyes = .happy
            pose.mouth = .open
            pose.mouthOpen = 0.8
            label = StageLabel(x: stop1 + towardNotch * size * 0.4, y: carY + size * 1.0, text: "¡pip pip!")
        case ..<5.6:
            let k = (e - 2.7) / 2.9
            carX = CompanionAnimator.lerp(stop1, stop2, CompanionAnimator.ease(k))
            moving = true
            x = carX
            y = seatY - CGFloat(abs(sin(e * 9))) * size * 0.04
            pose.eyes = .happy
            pose.mouth = .smile
            pose.arm = -60 + 20 * sin(t * 6)
        case ..<6.2:
            let k = (e - 5.6) / 0.6
            carX = stop2
            x = CompanionAnimator.lerp(stop2, to, CompanionAnimator.ease(k))
            y = CompanionAnimator.lerp(seatY, baseY, CompanionAnimator.ease(k)) - CompanionAnimator.arc(k) * size * 0.7
            pose.facing = outward
            pose.eyes = .happy
        default:
            let k = (e - 6.2) / 0.8
            carX = CompanionAnimator.lerp(stop2, exit, CompanionAnimator.easeIn(k))
            carOpacity = 1 - CompanionAnimator.clamp01((k - 0.4) / 0.6)
            moving = true
            x = to
            pose.arm = -60 + 35 * sin(t * 10)
            pose.eyes = .happy
            pose.mouth = .smile
        }
        let car = StageVehicle(kind: .car, x: carX, y: carY, facing: towardNotch,
                               opacity: carOpacity, time: moving ? t : 0)
        return StageFrame(x: x, y: y, pose: pose, vehicle: car, label: label)
    }

    /// Cuenta regresiva, despega en cohete, se pierde arriba y cae de regreso algo mareado.
    private func rocketFrame(_ e: Double, _ t: Double) -> StageFrame {
        let home = homeX(side)
        let outward = -towardNotch
        var pose = basePose(t, facing: outward)
        pose.eyes = .big
        var x = home
        var y = baseY
        var rocket: StageVehicle? = StageVehicle(kind: .rocket, x: home, y: baseY)
        var label: StageLabel?
        var puffs: [StagePuff] = []

        switch e {
        case ..<0.6:
            rocket?.opacity = e / 0.6
            pose.eyes = .happy
        case ..<1.9:
            let k = (e - 0.6) / 1.3
            let count = 3 - min(Int(k * 3), 2)
            label = StageLabel(x: home + towardNotch * size * 1.35, y: baseY, text: "\(count)")
            x = home + CGFloat(sin(t * 45)) * size * 0.04 * CGFloat(k)
            rocket?.x = x
            rocket?.value = 0.2
            rocket?.time = t
        case ..<2.9:
            let k = (e - 1.9) / 1.0
            y = baseY - CGFloat(k * k) * (baseY + size * 4)
            rocket?.y = y
            rocket?.value = 1
            rocket?.time = t
            pose.eyes = .closed
            pose.mouth = .open
            puffs = [StagePuff(x: home, y: baseY + size * 1.2, progress: CGFloat(k))]
        case ..<3.5:
            // Anda allá arriba (no se ve).
            pose.opacity = 0
            rocket = nil
        case ..<4.1:
            let k = (e - 3.5) / 0.6
            rocket = nil
            y = CompanionAnimator.lerp(-size * 2, baseY, CompanionAnimator.easeIn(k))
            pose.arm = -95
            pose.mouth = .open
        case ..<4.4:
            let k = (e - 4.1) / 0.3
            rocket = nil
            pose.scaleY = 1 - 0.3 * CompanionAnimator.arc(k)
            pose.scaleX = 1 + 0.2 * CompanionAnimator.arc(k)
            pose.eyes = .closed
        case ..<5.6:
            rocket = nil
            pose.eyes = .dizzy
            pose.prop = .sparkles
            pose.rotation = sin(e * 8) * 12
        default:
            rocket = nil
            pose.eyes = .happy
            pose.mouth = .smile
            pose.rotation = sin(e * 20) * 6 * (1 - CompanionAnimator.segment(e, 5.6, 6.2))
        }
        return StageFrame(x: x, y: y, pose: pose, vehicle: rocket, puffs: puffs, label: label)
    }

    /// Un ovni se lo lleva con su rayo y lo deja del otro lado.
    private func ufoFrame(_ e: Double, _ t: Double) -> StageFrame {
        let home = homeX(side)
        let to = homeX(side.other)
        let hover = baseY - size * 0.75
        let beamFull = baseY - hover + size * 0.3
        var ufoX = home
        var ufoY = hover
        var beam: CGFloat = 0
        var ufoOpacity = 1.0
        var x = home
        var y = baseY
        var pose = basePose(t, facing: -towardNotch)

        switch e {
        case ..<1.3:
            ufoY = CompanionAnimator.lerp(-size * 1.6, hover, CompanionAnimator.easeOut(e / 1.3))
            pose.lookY = -1
            pose.eyes = e > 0.7 ? .big : .open
        case ..<1.8:
            beam = beamFull * CGFloat((e - 1.3) / 0.5)
            pose.lookY = -1
            pose.eyes = .big
            pose.mouth = .open
        case ..<3.0:
            let k = (e - 1.8) / 1.2
            beam = beamFull
            y = CompanionAnimator.lerp(baseY, hover + size * 0.1, CompanionAnimator.ease(k))
            pose.rotation = k * 360
            pose.scaleX = 1 - 0.55 * CGFloat(k)
            pose.scaleY = 1 - 0.55 * CGFloat(k)
            pose.opacity = 1 - CompanionAnimator.clamp01((k - 0.6) / 0.4)
            pose.eyes = .happy
        case ..<5.3:
            let k = (e - 3.0) / 2.3
            beam = e < 3.3 ? beamFull * CGFloat(1 - (e - 3.0) / 0.3) : 0
            ufoX = CompanionAnimator.lerp(home, to, CompanionAnimator.ease(k))
            ufoY = hover + CGFloat(sin(e * 5)) * size * 0.08
            pose.opacity = 0
            x = ufoX
            y = hover
        case ..<5.7:
            ufoX = to
            beam = beamFull * CGFloat((e - 5.3) / 0.4)
            pose.opacity = 0
            x = to
            y = hover
        case ..<6.7:
            let k = (e - 5.7) / 1.0
            ufoX = to
            beam = beamFull
            x = to
            y = CompanionAnimator.lerp(hover + size * 0.1, baseY, CompanionAnimator.ease(k))
            pose.scaleX = 0.45 + 0.55 * CGFloat(k)
            pose.scaleY = 0.45 + 0.55 * CGFloat(k)
            pose.opacity = CompanionAnimator.clamp01(k / 0.3)
            pose.rotation = -(1 - k) * 360
            pose.eyes = .dizzy
        default:
            let k = (e - 6.7) / 0.8
            ufoX = to
            ufoY = CompanionAnimator.lerp(hover, -size * 1.8, CompanionAnimator.easeIn(k))
            ufoOpacity = 1 - CompanionAnimator.clamp01(k)
            x = to
            pose.eyes = e < 7.1 ? .dizzy : .happy
            pose.mouth = .smile
            pose.lookY = -0.8
        }
        let ufo = StageVehicle(kind: .ufo, x: ufoX, y: ufoY, value: beam, opacity: ufoOpacity, time: t)
        return StageFrame(x: x, y: y, pose: pose, vehicle: ufo)
    }

    /// Letreros de la avioneta.
    private var bannerText: String {
        let texts = ["¡Tú puedes!", "Toma agua", "¡Vas muy bien!", "Estírate tantito", "México Makers",
                     "Hora de un cafecito", "¡Hola!", "Respira hondo"]
        let index = abs(Int(actionStart.timeIntervalSinceReferenceDate)) % texts.count
        return texts[index]
    }

    /// Avioneta con letrero: baja, da la vuelta y cruza por debajo del notch.
    private func planeFrame(_ e: Double, _ t: Double) -> StageFrame {
        let home = homeX(side)
        let to = homeX(side.other)
        let outward = -towardNotch
        let low = notchHeight + size * 1.4
        let turnX = home + outward * 70
        let arriveX = to + towardNotch * 70
        var px = home
        var py = baseY
        var facing = outward
        var tilt: Double = 0
        var opacity = 1.0
        var lift: CGFloat = 0.32
        var banner: String?

        switch e {
        case ..<0.8:
            opacity = e / 0.8
        case ..<2.0:
            let k = (e - 0.8) / 1.2
            px = CompanionAnimator.lerp(home, turnX, CompanionAnimator.ease(k))
            py = CompanionAnimator.lerp(baseY, low, CompanionAnimator.ease(k))
            tilt = Double(facing) * 18 * Double(CompanionAnimator.arc(k))
        case ..<2.6:
            let k = (e - 2.0) / 0.6
            px = turnX + outward * CompanionAnimator.arc(k) * size * 0.8
            py = low - CompanionAnimator.arc(k) * size * 0.5
            facing = k < 0.5 ? outward : towardNotch
        case ..<6.6:
            let k = (e - 2.6) / 4.0
            px = CompanionAnimator.lerp(turnX, arriveX, CompanionAnimator.ease(k))
            py = low + CGFloat(sin(e * 2.2)) * size * 0.25
            facing = towardNotch
            banner = bannerText
        case ..<7.8:
            let k = (e - 6.6) / 1.2
            px = CompanionAnimator.lerp(arriveX, to, CompanionAnimator.ease(k))
            py = CompanionAnimator.lerp(low, baseY, CompanionAnimator.ease(k))
            facing = outward
            tilt = -Double(facing) * 15 * Double(CompanionAnimator.arc(k))
        default:
            let k = (e - 7.8) / 0.7
            px = to
            opacity = 1 - CompanionAnimator.clamp01(k)
            lift = 0.32 * (1 - CompanionAnimator.ease(k))
        }
        var pose = basePose(t, facing: facing)
        pose.eyes = .happy
        pose.mouth = .smile
        pose.rotation = tilt
        let plane = StageVehicle(kind: .plane, x: px, y: py, facing: facing, tilt: tilt, label: banner,
                                 opacity: opacity, time: t)
        return StageFrame(x: px, y: py - size * lift, pose: pose, vehicle: plane)
    }

    /// Su amigo sale de detrás del notch: se saludan, chocan las manos, bailan y se despiden.
    private func friendFrame(_ e: Double, _ t: Double) -> StageFrame {
        let home = homeX(side)
        let outward = -towardNotch
        let edge = home + towardNotch * wing / 2
        let mySpot = home + outward * size * 0.6
        let hidden = edge + towardNotch * size * 1.2
        let friendSpot = edge + outward * size * 0.5

        var x = mySpot
        var y = baseY
        var pose = basePose(t, facing: towardNotch)
        var fx = friendSpot
        var fy = baseY
        var friend = basePose(t + 1.3, facing: outward)

        switch e {
        case ..<0.6:
            x = CompanionAnimator.lerp(home, mySpot, CompanionAnimator.ease(e / 0.6))
            fx = hidden
            pose.walk = e * 2.4
            pose.facing = outward
        case ..<1.8:
            let k = (e - 0.6) / 1.2
            fx = CompanionAnimator.lerp(hidden, friendSpot, CompanionAnimator.ease(k))
            friend.walk = e * 2.4
            pose.eyes = k > 0.5 ? .happy : .big
        case ..<3.0:
            pose.arm = -60 + 35 * sin(t * 10)
            pose.eyes = .happy
            pose.mouth = .smile
            friend.arm = -60 + 35 * sin(t * 10 + 1)
            friend.eyes = .happy
            friend.mouth = .smile
        case ..<3.7:
            let k = (e - 3.0) / 0.7
            let jump = CompanionAnimator.arc(k) * size * 0.45
            y = baseY - jump
            fy = baseY - jump
            pose.arm = -110
            friend.arm = -110
            pose.eyes = .happy
            friend.eyes = .happy
            if k > 0.4 && k < 0.9 { pose.prop = .sparkles }
        case ..<6.4:
            pose = CompanionAnimator.pose(for: .dance, elapsed: e, progress: 0.5, time: t,
                                          facing: towardNotch, size: size)
            friend = CompanionAnimator.pose(for: .dance, elapsed: e, progress: 0.5, time: t + 0.5,
                                            facing: outward, size: size)
            friend.prop = .none
        case ..<7.2:
            pose.prop = .heart
            pose.propTime = e - 6.4
            pose.eyes = .happy
            pose.mouth = .smile
            friend.eyes = .happy
            friend.mouth = .smile
            friend.dy = -CGFloat(abs(sin(t * 5))) * size * 0.08
        case ..<8.6:
            let k = (e - 7.2) / 1.4
            fx = CompanionAnimator.lerp(friendSpot, hidden, CompanionAnimator.ease(k))
            friend.facing = towardNotch
            friend.walk = e * 2.4
            pose.arm = -60 + 35 * sin(t * 10)
            pose.eyes = .happy
        default:
            let k = (e - 8.6) / 0.9
            x = CompanionAnimator.lerp(mySpot, home, CompanionAnimator.ease(k))
            fx = hidden
            pose.walk = e * 2.4
        }
        let buddy = StageFriend(x: fx, y: fy, pose: friend)
        return StageFrame(x: x, y: y, pose: pose, friend: buddy)
    }

    /// Pesca desde la barra de menús.
    private func fishingFrame(_ e: Double, _ p: Double, _ t: Double) -> StageFrame {
        let home = homeX(side)
        let outward = -towardNotch
        let pose = CompanionAnimator.pose(for: .fishing, elapsed: e, progress: p, time: t,
                                          facing: outward, size: size)
        var label: StageLabel?
        if e > 5.2 && e < 6.0 {
            label = StageLabel(x: home + towardNotch * size * 0.8, y: baseY - size * 0.1, text: "!")
        }
        return StageFrame(x: home, y: baseY, pose: pose, label: label)
    }

    /// Magia: ¡puf! desaparece y aparece del otro lado del notch.
    private func magicFrame(_ e: Double, _ p: Double, _ t: Double) -> StageFrame {
        let home = homeX(side)
        let to = homeX(side.other)
        let outward = -towardNotch
        var pose = CompanionAnimator.pose(for: .magic, elapsed: e, progress: p, time: t,
                                          facing: outward, size: size)
        let there = e >= 2.2
        if there { pose.facing = towardNotch }
        var puffs: [StagePuff] = []
        if e > 1.5 && e < 2.2 {
            puffs.append(StagePuff(x: home, y: baseY, progress: CGFloat((e - 1.5) / 0.7)))
        }
        if e > 2.6 && e < 3.3 {
            puffs.append(StagePuff(x: to, y: baseY, progress: CGFloat((e - 2.6) / 0.7)))
        }
        return StageFrame(x: there ? to : home, y: baseY, pose: pose, puffs: puffs)
    }
}

/// El compañero junto al notch (va encima de la isla, sin recortarse, para poder colgarse y caminar).
struct CompanionStageView: View {
    @ObservedObject var gaze: CompanionGaze
    let input: CompanionStageInput
    let tint: Color
    let visible: Bool

    var body: some View {
        // Quieto va a 15 cuadros por segundo (casi no gasta); en movimiento, a 30.
        let calm = input.action == .rest && !gaze.tracking && input.mood != .listening
        return TimelineView(.animation(minimumInterval: calm ? 1.0 / 15.0 : 1.0 / 30.0, paused: !visible)) { context in
            stage(context.date)
        }
        .frame(width: input.panelWidth, height: input.notchHeight + 90, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    private func stage(_ date: Date) -> some View {
        let snapshot = GazeSnapshot(x: gaze.x, down: gaze.down, tracking: gaze.tracking, excited: gaze.excited)
        var frame = input.frame(at: date, gaze: snapshot)
        // Suena tu música: trae sus audífonos puestos (haga lo que haga).
        if input.mood == .grooving { frame.pose.headphones = true }
        return StageSceneView(frame: frame, tint: tint, size: input.size)
            .frame(width: input.panelWidth, height: input.notchHeight + 90, alignment: .topLeading)
    }
}

/// Las "alitas" del notch cuando está el compañero: solo un indicador del lado contrario.
struct CompanionWingsView: View {
    let notchWidth: CGFloat
    let wing: CGFloat
    let height: CGFloat
    let buddySide: CompanionSide
    let indicator: String?
    let indicatorTint: Color
    /// Suena música: barritas del color de la carátula (en lugar del indicador).
    var musicColor: Color? = nil
    var animated = true

    var body: some View {
        HStack(spacing: 0) {
            slot(buddySide == .right)
            Spacer(minLength: notchWidth)
            slot(buddySide == .left)
        }
        .frame(width: notchWidth + wing * 2, height: height)
    }

    private func slot(_ showsIndicator: Bool) -> some View {
        ZStack {
            if showsIndicator, let color = musicColor {
                EqualizerBars(color: color, height: min(14, height * 0.42), animated: animated)
            } else if showsIndicator, let indicator = indicator {
                Image(systemName: indicator)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(indicatorTint)
            }
        }
        .frame(width: wing, height: height)
    }
}

/// Barritas que bailan (suena tu música). Se mueven solas, sin saber el ritmo real.
struct EqualizerBars: View {
    let color: Color
    var height: CGFloat = 14
    var barWidth: CGFloat = 3
    var animated = true

    private static let speeds: [Double] = [5.3, 7.1, 4.4, 6.2]
    private static let phases: [Double] = [0, 1.7, 3.1, 0.8]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 14.0, paused: !animated)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: barWidth * 0.7) {
                ForEach(0..<4, id: \.self) { index in
                    let wave = abs(sin(t * EqualizerBars.speeds[index] / 2 + EqualizerBars.phases[index]))
                    Capsule()
                        .fill(color)
                        .frame(width: barWidth, height: max(barWidth, height * CGFloat(0.28 + 0.72 * wave)))
                }
            }
            .frame(height: height, alignment: .bottom)
        }
        .accessibilityHidden(true)
    }
}
