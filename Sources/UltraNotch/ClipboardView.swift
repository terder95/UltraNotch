import SwiftUI
import AppKit

/// Pestaña "Portapapeles": 9 ranuras fijas + historial de lo último copiado.
struct ClipboardView: View {
    @ObservedObject var clipboard: ClipboardStore
    var onRequestPermission: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !clipboard.shortcutsActive {
                PermissionBanner(action: onRequestPermission)
            }

            HStack(spacing: 6) {
                ForEach(1...9, id: \.self) { number in
                    SlotCard(number: number, item: clipboard.slots[number], clipboard: clipboard)
                }
            }

            HStack {
                Text("HISTORIAL")
                    .font(.system(size: 9.5, weight: .bold))
                    .tracking(0.8)
                    .foregroundColor(Color.secondary)
                Spacer()
                Text("⌘C + 1…9 guarda  ·  ⌘V + 1…9 pega")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Color.secondary)
            }

            if clipboard.history.isEmpty {
                Text("Copia algo y aparecerá aquí.")
                    .font(.system(size: 11))
                    .foregroundColor(Color.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 3) {
                        ForEach(clipboard.history) { item in
                            HistoryRow(item: item, clipboard: clipboard)
                        }
                    }
                }
            }
        }
    }
}

/// Una de las 9 ranuras. Clic = copiar su contenido.
struct SlotCard: View {
    let number: Int
    let item: ClipItem?
    @ObservedObject var clipboard: ClipboardStore
    @State private var hovering = false

    private var accent: Color { Theme.accent }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 0) {
                Text("\(number)")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .foregroundColor(item == nil ? Color.secondary : accent)
                Spacer(minLength: 0)
                if let item = item {
                    Image(systemName: item.kind.symbol)
                        .font(.system(size: 8))
                        .foregroundColor(Color.secondary)
                }
            }
            slotPreview
            Spacer(minLength: 0)
        }
        .padding(6)
        .frame(maxWidth: .infinity, minHeight: 54, maxHeight: 54, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.card(hovering))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(item == nil ? Color.clear : accent.opacity(0.35), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture {
            if let item = item {
                clipboard.copyToPasteboard(item, message: "Ranura \(number) copiada")
            }
        }
        .contextMenu {
            if let item = item {
                Button("Copiar") {
                    clipboard.copyToPasteboard(item, message: "Ranura \(number) copiada")
                }
                Button("Pegar en la app activa") {
                    clipboard.pasteSlot(number)
                }
                Divider()
                Button("Vaciar ranura \(number)") {
                    clipboard.clearSlot(number)
                }
            } else {
                Text("Copia algo con ⌘C y, sin soltar ⌘, pulsa \(number)")
            }
        }
        .help(item?.preview ?? "Ranura \(number) vacía — copia con ⌘C y, sin soltar ⌘, pulsa \(number)")
    }

    @ViewBuilder
    private var slotPreview: some View {
        if let item = item {
            if item.kind == .image, let image = clipboard.thumbnail(for: item) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: 26)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            } else {
                Text(item.preview)
                    .font(.system(size: 9))
                    .foregroundColor(Color.primary.opacity(0.85))
                    .lineLimit(2)
            }
        } else {
            Text("vacía")
                .font(.system(size: 9))
                .foregroundColor(Color.secondary.opacity(0.7))
        }
    }
}

/// Una fila del historial. Clic = copiar; clic derecho = guardar en ranura.
struct HistoryRow: View {
    let item: ClipItem
    @ObservedObject var clipboard: ClipboardStore
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: item.kind.symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Theme.accent)
                .frame(width: 16)
            if item.kind == .image, let image = clipboard.thumbnail(for: item) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 28, height: 18)
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            }
            Text(item.preview)
                .font(.system(size: 11))
                .foregroundColor(Color.primary.opacity(0.9))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            Text(Formatters.relative(item.date))
                .font(.system(size: 9.5))
                .foregroundColor(Color.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(hovering ? 0.1 : 0.035))
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture {
            clipboard.copyToPasteboard(item)
        }
        .contextMenu {
            Button("Copiar") {
                clipboard.copyToPasteboard(item)
            }
            Menu("Guardar en ranura") {
                ForEach(1...9, id: \.self) { number in
                    Button("Ranura \(number)") {
                        clipboard.save(item, toSlot: number)
                    }
                }
            }
            Divider()
            Button("Quitar del historial") {
                clipboard.removeFromHistory(item)
            }
        }
    }
}

struct PermissionBanner: View {
    let action: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundColor(Theme.warning)
            Text("Activa el permiso de Accesibilidad para usar ⌘C / ⌘V + número")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            Button("Activar", action: action)
                .buttonStyle(PillButtonStyle(tint: Theme.warning))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Theme.warning.opacity(0.14))
        )
    }
}
