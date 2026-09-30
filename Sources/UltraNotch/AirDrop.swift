import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Manda archivos por AirDrop: abre el panel de AirDrop de macOS para que elijas
/// a qué aparato (tu iPhone, tu iPad, otra Mac…).
@MainActor
final class AirDropSender: NSObject, NSSharingServiceDelegate {
    static let shared = AirDropSender()

    /// Cómo le fue (para avisar en la isla): enviado o no y cuántos archivos.
    /// Si cancelas el panel no se llama.
    var onResult: ((_ sent: Bool, _ count: Int) -> Void)?

    /// Mientras el panel está abierto guardamos el servicio (si no, macOS lo suelta).
    private var service: NSSharingService?
    private var pendingCount = 0

    @discardableResult
    func send(_ urls: [URL]) -> Bool {
        let files = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !files.isEmpty else {
            UltraNotchLog.shared.add("AirDrop: no encontré los archivos para mandar")
            onResult?(false, 0)
            return false
        }
        guard let airDrop = NSSharingService(named: .sendViaAirDrop), airDrop.canPerform(withItems: files) else {
            UltraNotchLog.shared.add("AirDrop no está disponible: revisa que el Wi-Fi y el Bluetooth estén prendidos")
            onResult?(false, files.count)
            return false
        }
        airDrop.delegate = self
        service = airDrop
        pendingCount = files.count
        // UltraNotch vive en la barra de menús: la traemos al frente para que el panel no quede escondido.
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        airDrop.perform(withItems: files)
        let what = files.count == 1 ? files[0].lastPathComponent : "\(files.count) archivos"
        UltraNotchLog.shared.add("AirDrop: elige a quién mandarle \(what)")
        return true
    }

    nonisolated func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
        Task { @MainActor in
            AirDropSender.shared.finish(sent: true, cancelled: false)
        }
    }

    nonisolated func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: Error) {
        let cancelled = (error as NSError).code == NSUserCancelledError
        Task { @MainActor in
            AirDropSender.shared.finish(sent: false, cancelled: cancelled)
        }
    }

    private func finish(sent: Bool, cancelled: Bool) {
        let count = pendingCount
        service = nil
        pendingCount = 0
        if cancelled {
            UltraNotchLog.shared.add("AirDrop cancelado")
            return
        }
        UltraNotchLog.shared.add(sent ? "AirDrop enviado" : "AirDrop no se pudo enviar")
        onResult?(sent, count)
    }
}

// MARK: - Soltar archivos sobre la isla: estante o AirDrop

enum DropZone {
    case shelf, airDrop
}

/// Recibe lo que sueltas sobre la isla. Del lado izquierdo se guarda en el estante;
/// del lado derecho se manda por AirDrop.
@MainActor
struct IslandDropDelegate: DropDelegate {
    /// Qué parte del ancho es del estante (el resto es AirDrop).
    static let split: CGFloat = 0.56
    static let types: [UTType] = [.fileURL, .image]

    let notch: NotchController
    let shelf: ShelfStore
    /// Dónde empieza y qué tan ancho es el contenido de la isla abierta (coordenadas de la isla).
    let contentMinX: CGFloat
    let contentWidth: CGFloat

    private func zone(at location: CGPoint) -> DropZone {
        guard notch.isExpanded else { return .shelf }
        return location.x >= contentMinX + contentWidth * IslandDropDelegate.split ? .airDrop : .shelf
    }

    private func update(_ info: DropInfo) {
        let current = zone(at: info.location)
        if notch.dropZone != current { notch.dropZone = current }
    }

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: IslandDropDelegate.types)
    }

    func dropEntered(info: DropInfo) {
        if !notch.isDropTargeted { notch.isDropTargeted = true }
        update(info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        update(info)
        return DropProposal(operation: .copy)
    }

    func dropExited(info: DropInfo) {
        notch.isDropTargeted = false
        notch.dropZone = .shelf
    }

    func performDrop(info: DropInfo) -> Bool {
        let target = zone(at: info.location)
        let providers = info.itemProviders(for: IslandDropDelegate.types)
        notch.isDropTargeted = false
        notch.dropZone = .shelf
        switch target {
        case .shelf: return shelf.handleDrop(providers)
        case .airDrop: return shelf.airDrop(providers)
        }
    }
}

/// Las dos zonas que aparecen cuando arrastras algo a la isla.
struct DropZonesView: View {
    let zone: DropZone

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 10) {
                DropZoneCard(
                    title: "Guardar en el estante",
                    subtitle: "Se queda aquí para usarlo después",
                    symbol: "tray.and.arrow.down.fill",
                    tint: Theme.accent,
                    active: zone == .shelf
                )
                .frame(width: max(proxy.size.width * IslandDropDelegate.split - 5, 0))
                DropZoneCard(
                    title: "AirDrop",
                    subtitle: "Suéltalo aquí y elige tu iPhone, iPad u otra Mac",
                    symbol: "dot.radiowaves.left.and.right",
                    tint: Theme.airDrop,
                    active: zone == .airDrop
                )
            }
        }
    }
}

private struct DropZoneCard: View {
    let title: String
    let subtitle: String
    let symbol: String
    let tint: Color
    let active: Bool

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: active ? 28 : 22, weight: .semibold))
                .foregroundColor(active ? tint : Color.secondary)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color.primary.opacity(active ? 1 : 0.7))
            Text(subtitle)
                .font(.system(size: 10.5))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(tint.opacity(active ? 0.16 : 0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(active ? tint : Color.primary.opacity(0.18),
                              style: StrokeStyle(lineWidth: active ? 2 : 1.2, dash: active ? [] : [5, 4]))
        )
        .animation(.easeOut(duration: 0.15), value: active)
    }
}
