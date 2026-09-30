import SwiftUI

// El personaje (original): una bolita con ojos, bracito, piecitos y cosas que carga.
// Cada animación solo calcula una "pose" y esta vista la dibuja.

/// Cómo se ve el personaje en un instante.
struct BuddyPose {
    enum Eyes { case open, big, closed, sleepy, happy, dizzy }
    enum Mouth { case none, small, open, smile }
    enum Prop {
        case none, toolbox, dots, exclamation, zzz, notes, heart, sparkles, cup, book, balloon, confetti, question, sweat
        case juggle, fishing, soccer, umbrella, bubbles, camera, wand
        /// Gorrito con hélice (para volar).
        case propeller
        /// Tiene calor (la Mac va a tope): gotitas y termómetro.
        case hot
        /// Batería bajita: pila parpadeando.
        case lowBattery
    }

    /// Desplazamiento en puntos (y positivo = hacia abajo).
    var dx: CGFloat = 0
    var dy: CGFloat = 0
    /// Giro del cuerpo en grados.
    var rotation: Double = 0
    var scaleX: CGFloat = 1
    var scaleY: CGFloat = 1
    var eyes: Eyes = .open
    /// Hacia dónde mira: -1…1 (y: -1 arriba, 1 abajo).
    var lookX: CGFloat = 0
    var lookY: CGFloat = 0
    var mouth: Mouth = .none
    /// Abertura de la boca (0…1) cuando está abierta.
    var mouthOpen: CGFloat = 0.6
    /// Bracito: ángulo en grados (0 = hacia afuera, -90 = arriba). nil = sin bracito.
    var arm: Double?
    /// 1 = voltea a la derecha, -1 = a la izquierda.
    var facing: CGFloat = 1
    /// Fase de los piecitos al caminar (nil = quieto).
    var walk: Double?
    var prop: Prop = .none
    /// Reloj del objeto (para animarlo).
    var propTime: Double = 0
    /// Aro que late (te está escuchando).
    var ring = false
    /// Transparencia del cuerpo (0 = desaparece; lo que carga se sigue viendo).
    var opacity: Double = 1
    /// Valores extra para animar lo que carga (caña, paraguas, flash, burbujas…).
    var propValue: CGFloat = 0
    var propValue2: CGFloat = 0
    /// Dónde va la pelota (desde el centro del cuerpo).
    var propOffset: CGSize = .zero
    /// Trae audífonos (está sonando tu música).
    var headphones = false
}

/// Forma del cuerpo: redondo (el compañero) o cuadradito con antena (su amigo).
enum BuddyBodyShape {
    case round, square
}

struct BuddyFigure: View {
    let pose: BuddyPose
    let tint: Color
    let size: CGFloat
    var showProps = true
    var bodyShape: BuddyBodyShape = .round

    var body: some View {
        ZStack {
            if showProps && pose.prop == .balloon {
                balloon
            }
            if showProps && pose.prop == .umbrella {
                weather
            }
            character
                .scaleEffect(x: pose.scaleX, y: pose.scaleY, anchor: .bottom)
                .rotationEffect(.degrees(pose.rotation))
                .opacity(pose.opacity)
            if showProps {
                prop
            }
        }
        .frame(width: size, height: size)
        .offset(x: pose.dx, y: pose.dy)
    }

    // MARK: Cuerpo

    private var character: some View {
        ZStack {
            if pose.ring {
                Circle()
                    .stroke(tint.opacity(0.6), lineWidth: max(1, size * 0.08))
                    .scaleEffect(1 + CGFloat(pose.propTime.truncatingRemainder(dividingBy: 1.2) / 1.2) * 0.8)
                    .opacity(Double(0.9 - pose.propTime.truncatingRemainder(dividingBy: 1.2) / 1.2 * 0.9))
            }
            if bodyShape == .square {
                antenna
            }
            if let phase = pose.walk {
                feet(phase)
            }
            if let angle = pose.arm {
                arm(angle)
            }
            bodyFill
            face
            if pose.headphones {
                headphones
            }
        }
        .frame(width: size, height: size)
    }

    /// Audífonos: la diadema por arriba de la cabeza y una bocina de cada lado.
    private var headphones: some View {
        let color = Color(white: 0.94)
        return ZStack {
            Circle()
                .trim(from: 0.53, to: 0.97)
                .stroke(color, style: StrokeStyle(lineWidth: max(1, size * 0.09), lineCap: .round))
                .frame(width: size * 1.1, height: size * 1.1)
            HStack(spacing: size * 0.96) {
                RoundedRectangle(cornerRadius: size * 0.08, style: .continuous)
                    .fill(color)
                    .frame(width: size * 0.2, height: size * 0.36)
                RoundedRectangle(cornerRadius: size * 0.08, style: .continuous)
                    .fill(color)
                    .frame(width: size * 0.2, height: size * 0.36)
            }
            .offset(y: size * 0.03)
        }
    }

    @ViewBuilder
    private var bodyFill: some View {
        switch bodyShape {
        case .round:
            Circle()
                .fill(tint)
            Circle()
                .fill(Color.white.opacity(0.22))
                .frame(width: size * 0.42, height: size * 0.42)
                .offset(x: -size * 0.18, y: -size * 0.2)
        case .square:
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(tint)
            RoundedRectangle(cornerRadius: size * 0.1, style: .continuous)
                .fill(Color.white.opacity(0.22))
                .frame(width: size * 0.36, height: size * 0.18)
                .offset(x: -size * 0.16, y: -size * 0.28)
        }
    }

    /// Antenita del amigo (la bolita brilla).
    private var antenna: some View {
        let glow: Double = 0.55 + 0.45 * abs(sin(pose.propTime * 3))
        return ZStack {
            Capsule()
                .fill(tint)
                .brightness(-0.12)
                .frame(width: size * 0.08, height: size * 0.3)
                .offset(y: -size * 0.6)
            Circle()
                .fill(Color.yellow)
                .frame(width: size * 0.2, height: size * 0.2)
                .opacity(glow)
                .offset(y: -size * 0.76)
        }
    }

    private func feet(_ phase: Double) -> some View {
        HStack(spacing: size * 0.16) {
            ForEach(0..<2, id: \.self) { index in
                Capsule()
                    .fill(tint)
                    .brightness(-0.15)
                    .frame(width: size * 0.24, height: size * 0.14)
                    .offset(y: -CGFloat(abs(sin((phase + Double(index) * 0.5) * .pi))) * size * 0.1)
            }
        }
        .offset(y: size * 0.5)
    }

    private func arm(_ angle: Double) -> some View {
        let length = size * 0.36
        let side = pose.facing >= 0 ? 1.0 : -1.0
        return Capsule()
            .fill(tint)
            .brightness(-0.08)
            .frame(width: length, height: size * 0.13)
            .rotationEffect(.degrees(angle * side), anchor: side > 0 ? .leading : .trailing)
            .offset(x: CGFloat(side) * (size * 0.38 + length / 2 - size * 0.04), y: size * 0.05)
    }

    private var face: some View {
        VStack(spacing: size * 0.06) {
            HStack(spacing: size * 0.2) {
                eye
                eye
            }
            mouth
        }
        .offset(x: pose.lookX * size * 0.13, y: -size * 0.04 + pose.lookY * size * 0.08)
    }

    @ViewBuilder
    private var eye: some View {
        switch pose.eyes {
        case .open:
            Capsule().fill(Color.white).frame(width: size * 0.16, height: size * 0.26)
        case .big:
            Capsule().fill(Color.white).frame(width: size * 0.19, height: size * 0.32)
        case .closed:
            Capsule().fill(Color.white).frame(width: size * 0.18, height: size * 0.05)
        case .sleepy:
            Capsule().fill(Color.white.opacity(0.9)).frame(width: size * 0.18, height: size * 0.07)
                .offset(y: size * 0.04)
        case .happy:
            HappyEye()
                .stroke(Color.white, style: StrokeStyle(lineWidth: max(1, size * 0.07), lineCap: .round))
                .frame(width: size * 0.2, height: size * 0.12)
        case .dizzy:
            Text("×")
                .font(.system(size: size * 0.32, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .frame(width: size * 0.2, height: size * 0.26)
        }
    }

    @ViewBuilder
    private var mouth: some View {
        switch pose.mouth {
        case .none:
            EmptyView()
        case .small:
            Capsule().fill(Color.white.opacity(0.9)).frame(width: size * 0.16, height: size * 0.06)
        case .open:
            Ellipse().fill(Color.white.opacity(0.92))
                .frame(width: size * 0.18, height: size * (0.06 + 0.14 * pose.mouthOpen))
        case .smile:
            HappyEye()
                .stroke(Color.white, style: StrokeStyle(lineWidth: max(1, size * 0.06), lineCap: .round))
                .rotationEffect(.degrees(180))
                .frame(width: size * 0.24, height: size * 0.1)
        }
    }

    // MARK: Cosas que carga

    @ViewBuilder
    private var prop: some View {
        let t = pose.propTime
        let side = pose.facing >= 0 ? CGFloat(1) : CGFloat(-1)
        switch pose.prop {
        case .none, .balloon:
            EmptyView()
        case .toolbox:
            ZStack {
                // Caja de herramientas (del lado contrario al bracito)
                ZStack {
                    RoundedRectangle(cornerRadius: size * 0.08, style: .continuous)
                        .stroke(Color(red: 0.55, green: 0.55, blue: 0.6), lineWidth: max(1, size * 0.07))
                        .frame(width: size * 0.3, height: size * 0.22)
                        .offset(y: -size * 0.2)
                    RoundedRectangle(cornerRadius: size * 0.07, style: .continuous)
                        .fill(Color(red: 0.9, green: 0.27, blue: 0.22))
                        .frame(width: size * 0.62, height: size * 0.38)
                    Rectangle()
                        .fill(Color.black.opacity(0.25))
                        .frame(width: size * 0.62, height: size * 0.05)
                        .offset(y: -size * 0.06)
                }
                .offset(x: -side * size * 0.82, y: size * 0.3)
                // Martillo en el bracito, golpeando
                Image(systemName: "hammer.fill")
                    .font(.system(size: size * 0.48, weight: .bold))
                    .foregroundColor(Color(red: 0.85, green: 0.85, blue: 0.9))
                    .scaleEffect(x: side, y: 1)
                    .rotationEffect(.degrees(Double(side) * (-35 + 45 * abs(sin(t * 6)))), anchor: .bottom)
                    .offset(x: side * size * 0.82, y: -size * 0.12)
                if abs(sin(t * 6)) > 0.93 {
                    Image(systemName: "sparkle")
                        .font(.system(size: size * 0.3, weight: .bold))
                        .foregroundColor(.yellow)
                        .offset(x: side * size * 1.05, y: size * 0.25)
                }
            }
        case .dots:
            HStack(spacing: size * 0.08) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(Color.white)
                        .frame(width: size * 0.14, height: size * 0.14)
                        .opacity(t.truncatingRemainder(dividingBy: 1.6) > Double(index) * 0.4 ? 1 : 0.2)
                }
            }
            .offset(x: side * size * 0.75, y: -size * 0.55)
        case .exclamation:
            Text("!")
                .font(.system(size: size * 0.6, weight: .black, design: .rounded))
                .foregroundColor(Theme.warning)
                .offset(x: side * size * 0.62, y: -size * 0.55 - CGFloat(abs(sin(t * 5))) * size * 0.12)
        case .question:
            Text("?")
                .font(.system(size: size * 0.55, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .offset(x: side * size * 0.62, y: -size * 0.55)
        case .zzz:
            ZStack {
                ForEach(0..<3, id: \.self) { index in
                    let phase = (t * 0.45 + Double(index) / 3).truncatingRemainder(dividingBy: 1)
                    Text("z")
                        .font(.system(size: size * (0.3 + 0.18 * CGFloat(phase)), weight: .heavy, design: .rounded))
                        .foregroundColor(Color.white.opacity(0.85))
                        .opacity(1 - phase)
                        .offset(x: size * (0.5 + 0.35 * CGFloat(phase)), y: -size * (0.3 + 0.55 * CGFloat(phase)))
                }
            }
        case .notes:
            ZStack {
                ForEach(0..<2, id: \.self) { index in
                    let phase = (t * 0.6 + Double(index) * 0.5).truncatingRemainder(dividingBy: 1)
                    Image(systemName: index == 0 ? "music.note" : "music.quarternote.3")
                        .font(.system(size: size * 0.38, weight: .bold))
                        .foregroundColor(.white)
                        .opacity(1 - phase)
                        .offset(x: (index == 0 ? -1 : 1) * size * (0.55 + 0.2 * CGFloat(phase)), y: -size * (0.25 + 0.5 * CGFloat(phase)))
                }
            }
        case .heart:
            let phase = min(t / 1.6, 1)
            Image(systemName: "heart.fill")
                .font(.system(size: size * (0.35 + 0.15 * CGFloat(phase)), weight: .bold))
                .foregroundColor(Color(red: 1, green: 0.3, blue: 0.5))
                .opacity(1 - phase * 0.8)
                .offset(x: side * size * 0.5, y: -size * (0.45 + 0.6 * CGFloat(phase)))
        case .sparkles:
            ZStack {
                Image(systemName: "sparkle")
                    .font(.system(size: size * 0.32, weight: .bold))
                    .foregroundColor(.yellow)
                    .scaleEffect(0.6 + 0.4 * CGFloat(abs(sin(t * 4))))
                    .offset(x: -size * 0.7, y: -size * 0.45)
                Image(systemName: "sparkle")
                    .font(.system(size: size * 0.26, weight: .bold))
                    .foregroundColor(.white)
                    .scaleEffect(0.6 + 0.4 * CGFloat(abs(cos(t * 4))))
                    .offset(x: size * 0.72, y: -size * 0.3)
            }
        case .cup:
            ZStack {
                Image(systemName: "cup.and.saucer.fill")
                    .font(.system(size: size * 0.42, weight: .bold))
                    .foregroundColor(Color(red: 0.95, green: 0.95, blue: 0.97))
                ForEach(0..<2, id: \.self) { index in
                    let phase = (t * 0.7 + Double(index) * 0.5).truncatingRemainder(dividingBy: 1)
                    Circle()
                        .fill(Color.white.opacity(0.5 * (1 - phase)))
                        .frame(width: size * 0.08, height: size * 0.08)
                        .offset(x: CGFloat(sin(phase * 6 + Double(index))) * size * 0.06, y: -size * (0.25 + 0.35 * CGFloat(phase)))
                }
            }
            .offset(x: side * size * 0.78, y: size * 0.05)
        case .book:
            Image(systemName: "book.fill")
                .font(.system(size: size * 0.5, weight: .bold))
                .foregroundColor(Color(red: 0.35, green: 0.6, blue: 1))
                .offset(y: size * 0.32)
        case .confetti:
            ZStack {
                ForEach(0..<8, id: \.self) { index in
                    confettiPiece(index, time: t)
                }
            }
        case .hot:
            ZStack {
                ForEach(0..<2, id: \.self) { index in
                    let phase = (t * 0.8 + Double(index) * 0.5).truncatingRemainder(dividingBy: 1)
                    Image(systemName: "drop.fill")
                        .font(.system(size: size * 0.22, weight: .bold))
                        .foregroundColor(Color(red: 0.5, green: 0.8, blue: 1))
                        .opacity(1 - phase * 0.7)
                        .offset(x: (index == 0 ? -side : side) * size * 0.5,
                                y: -size * 0.3 + CGFloat(phase) * size * 0.35)
                }
                Image(systemName: "thermometer.sun.fill")
                    .font(.system(size: size * 0.34, weight: .bold))
                    .foregroundColor(Color(red: 1, green: 0.55, blue: 0.25))
                    .offset(x: -side * size * 0.72, y: -size * 0.55)
            }
        case .lowBattery:
            Image(systemName: "battery.25")
                .font(.system(size: size * 0.36, weight: .bold))
                .foregroundColor(Theme.danger)
                .opacity(t.truncatingRemainder(dividingBy: 1.2) < 0.7 ? 1 : 0.25)
                .offset(x: side * size * 0.7, y: -size * 0.58)
        case .sweat:
            Image(systemName: "drop.fill")
                .font(.system(size: size * 0.26, weight: .bold))
                .foregroundColor(Color(red: 0.5, green: 0.8, blue: 1))
                .offset(x: -side * size * 0.5, y: -size * 0.35 + CGFloat(t.truncatingRemainder(dividingBy: 1.5)) * size * 0.2)
        case .juggle:
            juggleBalls(side: side)
        case .fishing:
            fishingRod(side: side)
        case .soccer:
            soccerBall
        case .umbrella:
            umbrella
        case .bubbles:
            soapBubbles(side: side)
        case .camera:
            camera(side: side)
        case .wand:
            wand(side: side)
        case .propeller:
            propellerCap
        }
    }

    /// Gorrito de colores con una hélice que gira.
    private var propellerCap: some View {
        let spin = CGFloat(abs(sin(pose.propTime * 28)))
        return ZStack {
            Capsule()
                .fill(Color(red: 0.3, green: 0.62, blue: 1))
                .frame(width: size * 0.56, height: size * 0.2)
                .offset(y: -size * 0.47)
            Rectangle()
                .fill(Color(white: 0.35))
                .frame(width: size * 0.05, height: size * 0.16)
                .offset(y: -size * 0.62)
            Capsule()
                .fill(Color(red: 1, green: 0.38, blue: 0.38))
                .frame(width: size * (0.12 + 0.78 * spin), height: size * 0.07)
                .offset(y: -size * 0.7)
        }
        .rotationEffect(.degrees(pose.rotation))
    }

    // MARK: Cosas nuevas

    private static let juggleColors: [Color] = [
        Color(red: 1, green: 0.35, blue: 0.35), Color.yellow, Color(red: 0.3, green: 0.85, blue: 1)
    ]

    /// Tres pelotitas dando vueltas enfrente.
    private func juggleBalls(side: CGFloat) -> some View {
        let t = pose.propTime
        return ZStack {
            ForEach(0..<3, id: \.self) { index in
                let phase: Double = (t * 1.3 + Double(index) / 3).truncatingRemainder(dividingBy: 1)
                let angle: Double = phase * 2 * Double.pi
                let x: CGFloat = side * size * 0.8 + CGFloat(sin(angle)) * size * 0.42
                let y: CGFloat = -size * 0.2 - CGFloat(cos(angle)) * size * 0.42
                Circle()
                    .fill(BuddyFigure.juggleColors[index])
                    .frame(width: size * 0.2, height: size * 0.2)
                    .offset(x: x, y: y)
            }
        }
    }

    /// Caña de pescar. propValue = qué tanto hilo soltó (0…1);
    /// propValue2 < 0 = jalón en el corcho, 0…1 = el pez va saliendo del agua.
    private func fishingRod(side: CGFloat) -> some View {
        let t = pose.propTime
        let c = size / 2
        let hand = CGPoint(x: c + side * size * 0.55, y: c + size * 0.05)
        let tip = CGPoint(x: c + side * size * 1.25, y: c - size * 0.5)
        let lineLength: CGFloat = size * 2.4 * pose.propValue
        let tug: CGFloat = pose.propValue2 < 0 ? -pose.propValue2 : 0
        let fishK: CGFloat = max(pose.propValue2, 0)
        let bob: CGFloat = CGFloat(sin(t * 3)) * size * 0.05 + tug * size * 0.3
        let bobber = CGPoint(x: tip.x, y: tip.y + lineLength + bob)
        let fishStart = CGPoint(x: tip.x, y: tip.y + size * 2.4)
        let fishEnd = CGPoint(x: tip.x, y: tip.y + size * 0.45)
        let fishLift: CGFloat = CGFloat(sin(Double(fishK) * Double.pi)) * size * 0.6
        let fish = CGPoint(x: fishStart.x + (fishEnd.x - fishStart.x) * fishK - side * fishLift * 0.4,
                           y: fishStart.y + (fishEnd.y - fishStart.y) * fishK - fishLift)
        let lineEnd = fishK > 0 ? fish : bobber
        let flipping: Double = Double(fishK) * 360
        let wiggle: Double = 70 * Double(side) + 20 * sin(t * 6)
        let fishAngle: Double = fishK < 1 ? flipping : wiggle
        return ZStack {
            Path { path in
                path.move(to: hand)
                path.addLine(to: tip)
            }
            .stroke(Color(red: 0.7, green: 0.48, blue: 0.28),
                    style: StrokeStyle(lineWidth: max(1, size * 0.08), lineCap: .round))
            if lineLength > 1 || fishK > 0 {
                Path { path in
                    path.move(to: tip)
                    path.addLine(to: lineEnd)
                }
                .stroke(Color.white.opacity(0.75), lineWidth: 0.7)
            }
            if lineLength > 1 && fishK == 0 {
                Circle()
                    .fill(Color(red: 1, green: 0.3, blue: 0.3))
                    .frame(width: size * 0.18, height: size * 0.18)
                    .position(bobber)
            }
            if fishK > 0 {
                Image(systemName: "fish.fill")
                    .font(.system(size: size * 0.5, weight: .bold))
                    .foregroundColor(Color(red: 1, green: 0.62, blue: 0.2))
                    .scaleEffect(x: -side, y: 1)
                    .rotationEffect(.degrees(fishAngle))
                    .position(fish)
            }
        }
        .frame(width: size, height: size)
    }

    /// Pelota de fútbol (propOffset = dónde va).
    private var soccerBall: some View {
        let d = size * 0.34
        return ZStack {
            Circle().fill(Color.white)
            Circle().stroke(Color.black.opacity(0.6), lineWidth: max(0.6, size * 0.03))
            Circle()
                .fill(Color.black.opacity(0.85))
                .frame(width: d * 0.32, height: d * 0.32)
            ForEach(0..<5, id: \.self) { index in
                Circle()
                    .fill(Color.black.opacity(0.75))
                    .frame(width: d * 0.16, height: d * 0.16)
                    .offset(y: -d * 0.36)
                    .rotationEffect(.degrees(Double(index) * 72))
            }
        }
        .frame(width: d, height: d)
        .rotationEffect(.degrees(pose.propTime * 360))
        .offset(pose.propOffset)
    }

    /// Paraguas (propValue = qué tan abierto).
    private var umbrella: some View {
        let open: CGFloat = max(pose.propValue, 0.001)
        return Image(systemName: "umbrella.fill")
            .font(.system(size: size * 1.05, weight: .bold))
            .foregroundColor(Color(red: 0.95, green: 0.35, blue: 0.55))
            .scaleEffect(x: open, y: 0.55 + 0.45 * open, anchor: .bottom)
            .offset(y: -size * 0.62)
            .opacity(pose.propValue > 0.02 ? 1 : 0)
    }

    /// Nube con lluvia que luego se vuelve sol (propValue2: 0…1 llega la nube, 1…2 sale el sol).
    private var weather: some View {
        let t = pose.propTime
        let w = Double(pose.propValue2)
        let cloudOpacity: Double = min(w, 1) * max(0, min(1, 2 - w))
        let sunOpacity: Double = max(0, min(1, w - 1))
        let raining = w > 0.6 && w < 1.5
        return ZStack {
            ZStack {
                Circle()
                    .frame(width: size * 0.55, height: size * 0.55)
                    .offset(x: -size * 0.3, y: size * 0.06)
                Circle()
                    .frame(width: size * 0.75, height: size * 0.75)
                    .offset(y: -size * 0.08)
                Circle()
                    .frame(width: size * 0.5, height: size * 0.5)
                    .offset(x: size * 0.33, y: size * 0.08)
            }
            .foregroundColor(Color(white: 0.75))
            .offset(y: -size * 1.75)
            .opacity(cloudOpacity)
            if raining {
                ForEach(0..<5, id: \.self) { index in
                    let phase: Double = (t * 1.8 + Double(index) * 0.23).truncatingRemainder(dividingBy: 1)
                    let x: CGFloat = size * (CGFloat(index) - 2) * 0.2
                    let y: CGFloat = -size * 1.45 + CGFloat(phase) * size * 0.8
                    Capsule()
                        .fill(Color(red: 0.55, green: 0.8, blue: 1))
                        .frame(width: size * 0.05, height: size * 0.16)
                        .offset(x: x, y: y)
                }
            }
            Image(systemName: "sun.max.fill")
                .font(.system(size: size * 0.7, weight: .bold))
                .foregroundColor(.yellow)
                .rotationEffect(.degrees(t * 40))
                .offset(y: -size * 1.75)
                .opacity(sunOpacity)
        }
    }

    /// Burbujas de jabón (propValue2 = qué tanto suben).
    private func soapBubbles(side: CGFloat) -> some View {
        let t = pose.propTime
        let rise = pose.propValue2
        return ZStack {
            Circle()
                .stroke(Color(red: 1, green: 0.8, blue: 0.3), lineWidth: max(0.8, size * 0.05))
                .frame(width: size * 0.26, height: size * 0.26)
                .offset(x: side * size * 0.62, y: -size * 0.02)
            ForEach(0..<5, id: \.self) { index in
                let phase: Double = (t * 0.45 + Double(index) / 5).truncatingRemainder(dividingBy: 1)
                let k = CGFloat(phase)
                let d: CGFloat = size * (0.16 + 0.2 * k)
                let x: CGFloat = side * size * (0.8 + 1.6 * k) + CGFloat(sin(phase * 9 + Double(index))) * size * 0.12
                let y: CGFloat = -size * (0.1 + 1.4 * k * rise) + CGFloat(cos(phase * 7 + Double(index))) * size * 0.1
                Circle()
                    .fill(Color(red: 0.7, green: 0.9, blue: 1).opacity(0.2))
                    .overlay(Circle().stroke(Color.white.opacity(0.8), lineWidth: 0.7))
                    .frame(width: d, height: d)
                    .offset(x: x, y: y)
                    .opacity(1 - phase)
            }
        }
    }

    /// Cámara con flash (propValue) y la foto que va saliendo (propValue2).
    private func camera(side: CGFloat) -> some View {
        let flash = pose.propValue
        let photo = pose.propValue2
        return ZStack {
            if photo > 0 {
                ZStack {
                    RoundedRectangle(cornerRadius: size * 0.03, style: .continuous)
                        .fill(Color.white)
                    RoundedRectangle(cornerRadius: size * 0.02, style: .continuous)
                        .fill(tint.opacity(0.85))
                        .padding(size * 0.04)
                        .padding(.bottom, size * 0.06)
                }
                .frame(width: size * 0.42, height: size * 0.5)
                .rotationEffect(.degrees(Double(side) * 10 * Double(photo)))
                .offset(x: side * size * 0.75, y: size * (0.05 + 0.5 * photo))
            }
            Image(systemName: "camera.fill")
                .font(.system(size: size * 0.45, weight: .bold))
                .foregroundColor(Color(white: 0.88))
                .offset(x: side * size * 0.72, y: -size * 0.05)
            if flash > 0 && flash < 1 {
                Circle()
                    .fill(Color.white)
                    .frame(width: size * (0.3 + 1.6 * flash), height: size * (0.3 + 1.6 * flash))
                    .opacity(Double(1 - flash))
                    .offset(x: side * size * 0.72, y: -size * 0.05)
            }
        }
    }

    /// Varita mágica.
    private func wand(side: CGFloat) -> some View {
        let t = pose.propTime
        return Image(systemName: "wand.and.stars")
            .font(.system(size: size * 0.55, weight: .bold))
            .foregroundColor(.yellow)
            .scaleEffect(x: side, y: 1)
            .rotationEffect(.degrees(Double(side) * (-20 + 25 * sin(t * 9))))
            .offset(x: side * size * 0.8, y: -size * 0.3)
    }

    private static let confettiColors: [Color] = [.yellow, .pink, .green, .orange, .cyan, .purple, .red, .mint]

    private func confettiPiece(_ index: Int, time t: Double) -> some View {
        let phase = (t * 0.8 + Double(index) / 8).truncatingRemainder(dividingBy: 1)
        let spread: CGFloat = size * (0.5 + 0.5 * CGFloat(phase))
        let x: CGFloat = CGFloat(cos(Double(index) * 0.8)) * spread
        let y: CGFloat = -size * 0.7 + size * 1.2 * CGFloat(phase)
        let angle: Double = phase * 360 + Double(index) * 40
        return Rectangle()
            .fill(BuddyFigure.confettiColors[index % BuddyFigure.confettiColors.count])
            .frame(width: size * 0.1, height: size * 0.16)
            .rotationEffect(.degrees(angle))
            .offset(x: x, y: y)
            .opacity(1 - phase * 0.7)
    }

    /// Globo para volver volando al notch.
    private var balloon: some View {
        let sway = CGFloat(sin(pose.propTime * 2)) * size * 0.12
        return ZStack {
            Path { path in
                path.move(to: CGPoint(x: size / 2, y: 0))
                path.addQuadCurve(to: CGPoint(x: size / 2 + sway, y: -size * 0.95),
                                  control: CGPoint(x: size / 2 - sway, y: -size * 0.5))
            }
            .stroke(Color.white.opacity(0.7), lineWidth: 1)
            Ellipse()
                .fill(Color(red: 1, green: 0.3, blue: 0.35))
                .overlay(
                    Ellipse()
                        .fill(Color.white.opacity(0.35))
                        .frame(width: size * 0.2, height: size * 0.28)
                        .offset(x: -size * 0.14, y: -size * 0.14)
                )
                .frame(width: size * 0.85, height: size)
                .offset(x: sway, y: -size * 1.45)
        }
        .frame(width: size, height: size)
    }
}

/// Ojito feliz (^) y sonrisa (al revés).
private struct HappyEye: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY), control: CGPoint(x: rect.midX, y: rect.minY - rect.height))
        return path
    }
}

// MARK: - Personajito de cada sesión de Claude Code

extension BuddyPose {
    /// Pose según lo que hace una sesión: trabaja con su caja de herramientas, piensa, te espera o festeja.
    static func status(_ status: ClaudeStatus, time t: Double) -> BuddyPose {
        var pose = BuddyPose()
        pose.propTime = t
        let blinking = t.truncatingRemainder(dividingBy: 3.4) < 0.12
        switch status {
        case .idle:
            pose.eyes = .sleepy
            pose.scaleY = 1 + CGFloat(sin(t * 2)) * 0.03
        case .thinking:
            pose.eyes = blinking ? .closed : .open
            pose.lookY = -0.9
            pose.lookX = 0.4
            pose.dy = CGFloat(sin(t * 2)) * 1.2
            pose.prop = .dots
        case .working:
            pose.eyes = blinking ? .closed : .open
            pose.lookX = -0.5
            pose.lookY = 0.6
            pose.arm = -30 + 40 * abs(sin(t * 6))
            pose.dy = CGFloat(sin(t * 6)) * 0.6
            pose.prop = .toolbox
        case .waiting:
            pose.eyes = .big
            pose.arm = -70 + 30 * sin(t * 9)
            pose.dy = -CGFloat(abs(sin(t * 5))) * 2.5
            pose.prop = .exclamation
        case .finished:
            pose.eyes = .happy
            pose.mouth = .smile
            pose.dy = -CGFloat(abs(sin(t * 3))) * 1.5
            pose.prop = .sparkles
        }
        return pose
    }
}

/// Personajito de una sesión (en la actividad en vivo y en la pestaña Claude).
struct SessionBuddy: View {
    let status: ClaudeStatus
    let time: Double
    var size: CGFloat = 16
    var seed: Double = 0
    /// Color del compañero (trabajando/pensando); los demás estados usan su color.
    var base: Color = Theme.accent
    var showProps = true

    var body: some View {
        BuddyFigure(
            pose: .status(status, time: time + seed),
            tint: status.isActive ? base : status.tint,
            size: size,
            showProps: showProps
        )
    }
}

/// Grupo de personajitos (uno por sesión), animados solo mientras se ven.
struct BuddyGroup: View {
    let statuses: [ClaudeStatus]
    var size: CGFloat = 16
    var animated = true
    var base: Color = Theme.accent

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !animated)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: -size * 0.25) {
                ForEach(Array(statuses.enumerated()), id: \.offset) { index, status in
                    // Solo el último carga sus cosas, para que no se encimen.
                    SessionBuddy(status: status, time: time, size: size, seed: Double(index) * 1.7,
                                 base: base, showProps: index == statuses.count - 1)
                }
            }
        }
    }
}
