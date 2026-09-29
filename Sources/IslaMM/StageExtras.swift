import SwiftUI
import AppKit

// Lo que acompaña al compañero en sus aventuras: vehículos, su amigo,
// nubecitas de humo y letreros. Todo se dibuja con figuras (sin imágenes).

enum VehicleKind {
    case skateboard, car, rocket, ufo, plane, parachute
}

/// Un vehículo en el escenario (x, y = su centro).
struct StageVehicle {
    var kind: VehicleKind
    var x: CGFloat
    var y: CGFloat
    /// 1 = va a la derecha, -1 = a la izquierda.
    var facing: CGFloat = 1
    /// Inclinación en grados.
    var tilt: Double = 0
    /// Flama del cohete (0…1) o largo del rayo del ovni (en puntos).
    var value: CGFloat = 0
    /// Letrero que jala la avioneta.
    var label: String? = nil
    var opacity: Double = 1
    /// Reloj para animar ruedas, luces, hélice… (0 = quieto).
    var time: Double = 0
}

/// El amigo que viene de visita.
struct StageFriend {
    var x: CGFloat
    var y: CGFloat
    var pose: BuddyPose
    var opacity: Double = 1
}

/// Nubecita de humo (magia, despegue).
struct StagePuff {
    var x: CGFloat
    var y: CGFloat
    /// 0…1
    var progress: CGFloat
}

/// Texto corto flotando ("¡pip pip!", la cuenta regresiva…).
struct StageLabel {
    var x: CGFloat
    var y: CGFloat
    var text: String
}

/// Color del amigo: el "contrario" del color de tu compañero, para que se distingan.
enum FriendPalette {
    static func tint(for base: Color) -> Color {
        guard let rgb = NSColor(base).usingColorSpace(.sRGB) else { return Color.yellow }
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        rgb.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        let friendHue = (hue + 0.42).truncatingRemainder(dividingBy: 1)
        return Color(hue: Double(friendHue), saturation: 0.62, brightness: 0.97)
    }
}

// MARK: - Escena completa

/// Dibuja un cuadro del escenario: vehículo (atrás), amigo, compañero, vehículo (enfrente),
/// humo y letreros. La usan la isla y el paseo por la pantalla.
struct StageSceneView: View {
    let frame: StageFrame
    let tint: Color
    let size: CGFloat
    var onTapBuddy: (() -> Void)? = nil

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let top = frame.threadTop {
                Path { path in
                    path.move(to: CGPoint(x: frame.x, y: top))
                    path.addLine(to: CGPoint(x: frame.x + frame.pose.dx, y: frame.y + frame.pose.dy - size * 0.45))
                }
                .stroke(Color.white.opacity(0.6), lineWidth: 1)
            }
            if let vehicle = frame.vehicle {
                VehicleView(vehicle: vehicle, size: size, layer: .back)
                    .position(x: vehicle.x, y: vehicle.y)
            }
            if let friend = frame.friend {
                BuddyFigure(pose: friend.pose, tint: FriendPalette.tint(for: tint), size: size * 0.88,
                            bodyShape: .square)
                    .opacity(friend.opacity)
                    .position(x: friend.x, y: friend.y)
            }
            BuddyFigure(pose: frame.pose, tint: tint, size: size)
                .contentShape(Circle())
                .onTapGesture { onTapBuddy?() }
                .position(x: frame.x, y: frame.y)
            if let vehicle = frame.vehicle {
                VehicleView(vehicle: vehicle, size: size, layer: .front)
                    .position(x: vehicle.x, y: vehicle.y)
            }
            ForEach(Array(frame.puffs.enumerated()), id: \.offset) { _, puff in
                PuffView(progress: puff.progress, size: size)
                    .position(x: puff.x, y: puff.y)
            }
            if let label = frame.label {
                Text(label.text)
                    .font(.system(size: max(9, size * 0.55), weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .shadow(color: Color.black.opacity(0.6), radius: 1.5, x: 0, y: 1)
                    .fixedSize()
                    .position(x: label.x, y: label.y)
            }
        }
    }
}

struct PuffView: View {
    let progress: CGFloat
    let size: CGFloat

    var body: some View {
        ZStack {
            ForEach(0..<6, id: \.self) { index in
                let angle: Double = Double(index) / 6 * 2 * Double.pi
                let radius: CGFloat = size * (0.2 + 0.8 * progress)
                let diameter: CGFloat = size * (0.35 + 0.3 * progress)
                Circle()
                    .fill(Color(white: 0.92))
                    .frame(width: diameter, height: diameter)
                    .offset(x: CGFloat(cos(angle)) * radius, y: CGFloat(sin(angle)) * radius * 0.7)
            }
        }
        .opacity(Double(1 - progress))
    }
}

// MARK: - Vehículos

enum VehicleLayer {
    case back, front
}

/// Cada vehículo tiene una parte que va detrás del compañero y otra enfrente
/// (así se ve "adentro" del coche, del cohete o del ovni).
struct VehicleView: View {
    let vehicle: StageVehicle
    let size: CGFloat
    let layer: VehicleLayer

    var body: some View {
        ZStack {
            flipped
                .scaleEffect(x: vehicle.facing >= 0 ? 1 : -1, y: 1)
                .rotationEffect(.degrees(vehicle.tilt))
            if layer == .back, vehicle.kind == .plane, let label = vehicle.label {
                banner(label)
            }
        }
        .frame(width: size, height: size)
        .opacity(vehicle.opacity)
    }

    /// Lo que se voltea según hacia dónde va.
    @ViewBuilder
    private var flipped: some View {
        switch (vehicle.kind, layer) {
        case (.skateboard, .back): skateboard
        case (.car, .back): carCabin
        case (.car, .front): carBody
        case (.rocket, .back): rocketBody
        case (.rocket, .front): porthole
        case (.ufo, .back): ufoBeam
        case (.ufo, .front): ufoSaucer
        case (.plane, .back): planeTail
        case (.plane, .front): planeBody
        case (.parachute, .back): parachute
        default: EmptyView()
        }
    }

    // Patineta

    private var skateboard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.07, style: .continuous)
                .fill(Color(red: 0.86, green: 0.52, blue: 0.26))
                .frame(width: size * 1.3, height: size * 0.13)
            HStack(spacing: size * 0.6) {
                Circle().fill(Color(white: 0.92)).frame(width: size * 0.2, height: size * 0.2)
                Circle().fill(Color(white: 0.92)).frame(width: size * 0.2, height: size * 0.2)
            }
            .offset(y: size * 0.15)
        }
    }

    // Coche

    private static let carColor = Color(red: 0.93, green: 0.27, blue: 0.3)

    private var carCabin: some View {
        RoundedRectangle(cornerRadius: size * 0.35, style: .continuous)
            .fill(Color(red: 0.75, green: 0.9, blue: 1).opacity(0.35))
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.35, style: .continuous)
                    .stroke(VehicleView.carColor, lineWidth: max(1, size * 0.08))
            )
            .frame(width: size * 1.3, height: size * 0.95)
            .offset(x: -size * 0.1, y: -size * 0.38)
    }

    private var carBody: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(VehicleView.carColor)
                .frame(width: size * 2.0, height: size * 0.55)
            Circle()
                .fill(Color.yellow)
                .frame(width: size * 0.14, height: size * 0.14)
                .offset(x: size * 0.88, y: -size * 0.06)
            wheel.offset(x: -size * 0.58, y: size * 0.28)
            wheel.offset(x: size * 0.58, y: size * 0.28)
        }
    }

    private var wheel: some View {
        ZStack {
            Circle().fill(Color(white: 0.15))
            Rectangle()
                .fill(Color(white: 0.75))
                .frame(width: size * 0.06, height: size * 0.24)
                .rotationEffect(.degrees(vehicle.time * 540))
        }
        .frame(width: size * 0.34, height: size * 0.34)
    }

    // Cohete

    private var rocketBody: some View {
        let flame = vehicle.value
        let flicker = CGFloat(abs(sin(vehicle.time * 30)))
        return ZStack {
            if flame > 0 {
                Ellipse()
                    .fill(Color.orange)
                    .frame(width: size * 0.6, height: size * (0.4 + 1.1 * flame + 0.25 * flicker))
                    .offset(y: size * (1.15 + 0.5 * flame))
                Ellipse()
                    .fill(Color.yellow)
                    .frame(width: size * 0.32, height: size * (0.25 + 0.6 * flame))
                    .offset(y: size * (1.05 + 0.3 * flame))
            }
            Wedge()
                .fill(Color(red: 0.93, green: 0.3, blue: 0.3))
                .frame(width: size * 0.5, height: size * 0.6)
                .offset(x: -size * 0.72, y: size * 0.95)
            Wedge()
                .fill(Color(red: 0.93, green: 0.3, blue: 0.3))
                .frame(width: size * 0.5, height: size * 0.6)
                .scaleEffect(x: -1, y: 1)
                .offset(x: size * 0.72, y: size * 0.95)
            RoundedRectangle(cornerRadius: size * 0.6, style: .continuous)
                .fill(Color(white: 0.93))
                .frame(width: size * 1.4, height: size * 2.1)
                .offset(y: size * 0.15)
            Nose()
                .fill(Color(red: 0.93, green: 0.3, blue: 0.3))
                .frame(width: size * 1.05, height: size * 0.6)
                .offset(y: -size * 1.05)
        }
    }

    private var porthole: some View {
        Circle()
            .stroke(Color(white: 0.62), lineWidth: max(1.5, size * 0.12))
            .frame(width: size * 1.14, height: size * 1.14)
    }

    // Ovni

    private var ufoBeam: some View {
        let beam = vehicle.value
        return ZStack {
            if beam > 1 {
                Beam()
                    .fill(LinearGradient(
                        colors: [Color(red: 0.6, green: 1, blue: 0.7).opacity(0.6), Color(red: 0.6, green: 1, blue: 0.7).opacity(0.08)],
                        startPoint: .top, endPoint: .bottom))
                    .frame(width: size * 1.6, height: beam)
                    .offset(y: size * 0.2 + beam / 2)
            }
        }
    }

    private var ufoSaucer: some View {
        let t = vehicle.time
        return ZStack {
            Circle()
                .fill(Color(red: 0.6, green: 0.9, blue: 1).opacity(0.6))
                .frame(width: size * 0.9, height: size * 0.9)
                .offset(y: -size * 0.2)
            Ellipse()
                .fill(Color(white: 0.78))
                .frame(width: size * 2.3, height: size * 0.55)
            Ellipse()
                .fill(Color(white: 0.55))
                .frame(width: size * 1.6, height: size * 0.26)
                .offset(y: size * 0.13)
            HStack(spacing: size * 0.28) {
                ForEach(0..<4, id: \.self) { index in
                    Circle()
                        .fill(ufoLight(index, time: t))
                        .frame(width: size * 0.14, height: size * 0.14)
                }
            }
        }
    }

    private func ufoLight(_ index: Int, time t: Double) -> Color {
        let on = Int(t * 6) % 4 == index
        return on ? Color.yellow : Color(red: 0.5, green: 1, blue: 0.6)
    }

    // Avioneta

    private static let planeColor = Color(red: 1, green: 0.8, blue: 0.2)

    private var planeTail: some View {
        Wedge()
            .fill(VehicleView.planeColor)
            .brightness(-0.1)
            .frame(width: size * 0.5, height: size * 0.6)
            .scaleEffect(x: -1, y: 1)
            .offset(x: -size * 0.85, y: -size * 0.35)
    }

    private var planeBody: some View {
        let spin = CGFloat(abs(sin(vehicle.time * 40)))
        return ZStack {
            Capsule()
                .fill(VehicleView.planeColor)
                .frame(width: size * 2.1, height: size * 0.55)
            Capsule()
                .fill(VehicleView.planeColor)
                .brightness(-0.15)
                .frame(width: size * 0.95, height: size * 0.16)
                .offset(x: -size * 0.05, y: size * 0.05)
            Ellipse()
                .fill(Color(white: 0.9).opacity(0.85))
                .frame(width: size * 0.1, height: size * (0.2 + 0.55 * spin))
                .offset(x: size * 1.1)
            Circle()
                .fill(Color(white: 0.3))
                .frame(width: size * 0.14, height: size * 0.14)
                .offset(x: size * 1.06)
        }
    }

    /// El letrero va detrás de la avioneta y nunca se voltea (para que se lea).
    private func banner(_ text: String) -> some View {
        let width: CGFloat = CGFloat(text.count) * size * 0.3 + size * 0.9
        let back: CGFloat = vehicle.facing >= 0 ? -1 : 1
        let wave: Double = sin(vehicle.time * 4) * 3
        return ZStack {
            Rectangle()
                .fill(Color.white.opacity(0.7))
                .frame(width: size * 0.5, height: 0.8)
                .offset(x: back * (size * 1.1 + size * 0.25))
            Text(text)
                .font(.system(size: max(8, size * 0.5), weight: .bold, design: .rounded))
                .foregroundColor(Color(red: 0.12, green: 0.12, blue: 0.16))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(width: width - size * 0.3, height: size * 0.62)
                .background(
                    RoundedRectangle(cornerRadius: size * 0.1, style: .continuous)
                        .fill(Color.white)
                )
                .rotationEffect(.degrees(wave))
                .offset(x: back * (size * 1.35 + width / 2))
        }
    }

    // Paracaídas

    private var parachute: some View {
        let c = size / 2
        return ZStack {
            Path { path in
                path.move(to: CGPoint(x: c - size * 1.0, y: c - size * 1.45))
                path.addLine(to: CGPoint(x: c - size * 0.3, y: c - size * 0.2))
                path.move(to: CGPoint(x: c + size * 1.0, y: c - size * 1.45))
                path.addLine(to: CGPoint(x: c + size * 0.3, y: c - size * 0.2))
                path.move(to: CGPoint(x: c, y: c - size * 1.5))
                path.addLine(to: CGPoint(x: c, y: c - size * 0.45))
            }
            .stroke(Color.white.opacity(0.75), lineWidth: 0.7)
            Canopy()
                .fill(Color(red: 1, green: 0.55, blue: 0.2))
                .frame(width: size * 2.1, height: size * 0.85)
                .offset(y: -size * 1.85)
            Canopy()
                .fill(Color.white.opacity(0.9))
                .frame(width: size * 0.7, height: size * 0.85)
                .offset(y: -size * 1.85)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Figuritas

/// Triángulo rectángulo (aletas, cola).
struct Wedge: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// Punta del cohete.
struct Nose: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.midY))
        path.closeSubpath()
        return path
    }
}

/// Rayo del ovni (angosto arriba, ancho abajo).
struct Beam: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let inset = rect.width * 0.3
        path.move(to: CGPoint(x: rect.minX + inset, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// Tela del paracaídas (cúpula con la base plana).
struct Canopy: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addCurve(to: CGPoint(x: rect.maxX, y: rect.maxY),
                      control1: CGPoint(x: rect.minX, y: rect.minY - rect.height * 0.3),
                      control2: CGPoint(x: rect.maxX, y: rect.minY - rect.height * 0.3))
        path.closeSubpath()
        return path
    }
}
