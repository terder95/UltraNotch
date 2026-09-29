import SwiftUI
import AppKit
import QuickLookThumbnailing
import UniformTypeIdentifiers

/// Pestaña "Estante": tus capturas, descargas y archivos arrastrados.
struct ShelfView: View {
    @ObservedObject var shelf: ShelfStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                FilterChip(title: "Todo", count: shelf.count(nil), selected: shelf.filter == nil) {
                    shelf.filter = nil
                }
                ForEach(ShelfItem.Source.allCases, id: \.self) { source in
                    FilterChip(title: source.label, count: shelf.count(source),
                               selected: shelf.filter == source, tint: source.tint) {
                        shelf.filter = (shelf.filter == source) ? nil : source
                    }
                }
                Spacer(minLength: 0)
                if !shelf.items.isEmpty {
                    Button {
                        shelf.clear()
                    } label: {
                        Label("Vaciar", systemImage: "trash")
                    }
                    .buttonStyle(PillButtonStyle())
                }
            }

            if shelf.visibleItems.isEmpty {
                EmptyShelf(filtered: shelf.filter != nil)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 10) {
                        ForEach(shelf.visibleItems) { item in
                            ShelfTile(item: item, shelf: shelf)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }
}

/// Un archivo del estante. Arrástralo a donde quieras; doble clic lo abre.
struct ShelfTile: View {
    let item: ShelfItem
    @ObservedObject var shelf: ShelfStore
    @State private var hovering = false

    private var isImage: Bool {
        guard let type = UTType(filenameExtension: item.url.pathExtension) else { return false }
        return type.conforms(to: .image)
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.card(hovering))

                FileThumb(url: item.url, fill: isImage)
                    .frame(width: 92, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .frame(width: 104, height: 84)

                SourceBadge(source: item.source)
                    .padding(6)

                if hovering {
                    Button {
                        shelf.remove(item)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(Color.white, Color.black.opacity(0.65))
                    }
                    .buttonStyle(.plain)
                    .help("Quitar de la isla")
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(4)

                    Button {
                        shelf.airDrop([item])
                    } label: {
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(Theme.airDrop))
                            .shadow(color: Color.black.opacity(0.3), radius: 2, x: 0, y: 1)
                    }
                    .buttonStyle(.plain)
                    .help("Mandar por AirDrop")
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(5)
                }
            }
            .frame(width: 104, height: 84)

            Text(item.url.lastPathComponent)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Color.primary.opacity(0.85))
                .lineLimit(2)
                .truncationMode(.middle)
                .multilineTextAlignment(.center)
                .frame(width: 104, height: 28, alignment: .top)
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) {
            NSWorkspace.shared.open(item.url)
        }
        .onDrag {
            NSItemProvider(object: item.url as NSURL)
        }
        .contextMenu {
            Button("Abrir") {
                NSWorkspace.shared.open(item.url)
            }
            Button("Mostrar en Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            }
            Button("Copiar archivo") {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.writeObjects([item.url as NSURL])
            }
            Button("Mandar por AirDrop") {
                shelf.airDrop([item])
            }
            if shelf.visibleItems.count > 1 {
                Button("Mandar todos (\(shelf.visibleItems.count)) por AirDrop") {
                    shelf.airDrop(shelf.visibleItems)
                }
            }
            Divider()
            Button("Quitar de la isla") {
                shelf.remove(item)
            }
        }
        .help(item.url.path)
    }
}

/// Iconito de origen (cámara = captura, flecha = descarga…).
struct SourceBadge: View {
    let source: ShelfItem.Source

    var body: some View {
        Image(systemName: source.symbol)
            .font(.system(size: 8, weight: .bold))
            .foregroundColor(.white)
            .frame(width: 16, height: 16)
            .background(Circle().fill(source.badgeColor))
    }
}

/// Filtro tipo píldora (Todo / Capturas / Descargas / Arrastrados).
struct FilterChip: View {
    let title: String
    let count: Int
    let selected: Bool
    var tint: Color = .primary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(selected ? .primary : .secondary)
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .foregroundColor(selected ? tint : .secondary)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.primary.opacity(selected ? 0.12 : 0.05)))
            .overlay(Capsule().stroke(selected ? tint.opacity(0.55) : Color.clear, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct EmptyShelf: View {
    let filtered: Bool

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 22, weight: .light))
                .foregroundColor(Color.secondary)
            Text(filtered ? "Nada en esta categoría" : "Suelta archivos aquí")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color.primary.opacity(0.85))
            Text("Tus capturas y descargas nuevas aparecen solas. Suelta del lado derecho para mandar por AirDrop.")
                .font(.system(size: 10.5))
                .foregroundColor(Color.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity, minHeight: 118)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.18), style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
        )
    }
}

/// Miniatura real del archivo (Quick Look) o su ícono mientras carga.
struct FileThumb: View {
    let url: URL
    var fill: Bool = false
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image = image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: fill ? .fill : .fit)
            } else {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(4)
            }
        }
        .task(id: url) {
            image = await Thumbnailer.thumbnail(for: url)
        }
    }
}

enum Thumbnailer {
    private static let cache = NSCache<NSURL, NSImage>()

    static func thumbnail(for url: URL, size: CGFloat = 180) async -> NSImage? {
        if let cached = cache.object(forKey: url as NSURL) { return cached }
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: size, height: size),
            scale: 2,
            representationTypes: .all
        )
        guard let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) else {
            return nil
        }
        let image = representation.nsImage
        cache.setObject(image, forKey: url as NSURL)
        return image
    }
}
