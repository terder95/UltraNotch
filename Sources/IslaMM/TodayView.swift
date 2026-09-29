import SwiftUI
import AppKit

// Pestaña "Hoy": lo que suena (con su letra en vivo) y tus próximas juntas.
//
// Mientras suena algo se ve la letra en vivo; con "Letra completa" la ves toda (toca una línea
// para ir a esa parte de la canción) y con "Agenda" regresas a tus juntas.

enum TodayMode {
    case live, full, agenda
}

struct TodayView: View {
    @ObservedObject var music: NowPlaying
    @ObservedObject var lyrics: LyricsStore
    @ObservedObject var agenda: CalendarStore
    var onOpenSettings: () -> Void

    /// Lo que elegiste ver (nil = automático: la letra si suena algo, si no la agenda).
    @State private var chosen: TodayMode?

    private var mode: TodayMode {
        guard music.enabled, music.track != nil else { return .agenda }
        return chosen ?? .live
    }

    var body: some View {
        Group {
            switch mode {
            case .live:
                LiveLyricsCard(music: music, lyrics: lyrics, agenda: agenda,
                               onFull: { chosen = .full }, onAgenda: { chosen = .agenda })
            case .full:
                FullLyricsView(music: music, lyrics: lyrics, onBack: { chosen = .live })
            case .agenda:
                HStack(alignment: .top, spacing: 12) {
                    MusicCard(music: music, onLyrics: music.track == nil ? nil : { chosen = .live })
                        .frame(width: 236)
                    AgendaCard(agenda: agenda, onOpenSettings: onOpenSettings)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .onAppear {
            music.refreshIfNeeded()
            agenda.refresh()
            music.beginWatchingPosition()
        }
        .onDisappear {
            music.endWatchingPosition()
        }
    }
}

// MARK: - Piezas de la música

/// La carátula (o un cuadrito con una nota mientras llega).
struct ArtworkView: View {
    let image: NSImage?
    var color: Color? = nil
    let size: CGFloat
    var radius: CGFloat = 8

    var body: some View {
        ZStack {
            if let image = image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill((color ?? Theme.accent).opacity(0.35))
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .foregroundColor(Color.white.opacity(0.85))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .shadow(color: Color.black.opacity(size > 50 ? 0.3 : 0), radius: 6, x: 0, y: 3)
    }
}

/// Anterior · pausa · siguiente.
struct PlayerControls: View {
    @ObservedObject var music: NowPlaying
    var compact = false

    var body: some View {
        HStack(spacing: compact ? 4 : 16) {
            button("backward.fill", size: compact ? 12 : 13, help: "Anterior") { music.previous() }
            button(music.track?.playing == true ? "pause.fill" : "play.fill", size: compact ? 17 : 19,
                   help: music.track?.playing == true ? "Pausa" : "Reproducir") { music.playPause() }
            button("forward.fill", size: compact ? 12 : 13, help: "Siguiente") { music.next() }
        }
        .disabled(!music.enabled)
    }

    private func button(_ symbol: String, size: CGFloat, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundColor(.primary)
                .frame(width: 34, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

/// La barrita de avance con el tiempo que va y el que falta.
struct SongProgress: View {
    @ObservedObject var music: NowPlaying
    var tint: Color = Theme.accent

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let position = music.position(at: context.date)
            let duration = music.track?.duration
            VStack(spacing: 3) {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.primary.opacity(0.14))
                        Capsule()
                            .fill(tint)
                            .frame(width: max(4, proxy.size.width * SongProgress.fraction(position, duration)))
                    }
                }
                .frame(height: 4)
                HStack {
                    Text(position.map { NowPlaying.clock($0) } ?? "–:––")
                    Spacer(minLength: 4)
                    Text(SongProgress.remaining(position, duration))
                }
                .font(.system(size: 9.5, weight: .medium))
                .monospacedDigit()
                .foregroundColor(.secondary)
            }
        }
    }

    static func fraction(_ position: Double?, _ duration: Double?) -> CGFloat {
        guard let position = position, let duration = duration, duration > 0 else { return 0 }
        return CGFloat(min(max(position / duration, 0), 1))
    }

    static func remaining(_ position: Double?, _ duration: Double?) -> String {
        guard let duration = duration, duration > 0 else { return "" }
        return "-" + NowPlaying.clock(max(0, duration - (position ?? 0)))
    }
}

// MARK: - Letra en vivo (tres renglones)

struct LiveLyricsCard: View {
    @ObservedObject var music: NowPlaying
    @ObservedObject var lyrics: LyricsStore
    @ObservedObject var agenda: CalendarStore
    var onFull: () -> Void
    var onAgenda: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        ArtworkView(image: music.artwork, color: music.artColor, size: 60, radius: 10)
                            .onTapGesture { music.openPlayer() }
                            .help("Abrir \(music.track?.player.name ?? "la música")")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(music.track?.title ?? "")
                                .font(.system(size: 13.5, weight: .bold))
                                .foregroundColor(.primary)
                                .lineLimit(2)
                            Text(music.track?.artist ?? "")
                                .font(.system(size: 11.5))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                    PlayerControls(music: music, compact: true)
                }
                .frame(width: 180)
                .frame(maxHeight: .infinity, alignment: .top)

                Rectangle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(width: 1)

                LyricsTicker(music: music, lyrics: lyrics, onShowAll: onFull)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .help("Letra sincronizada de LRCLIB")
            }
            .frame(maxHeight: .infinity)

            SongProgress(music: music, tint: music.artColor ?? Theme.accent)

            HStack(spacing: 8) {
                NextMeetingStrip(agenda: agenda)
                Spacer(minLength: 4)
                Button(action: onAgenda) {
                    Label("Agenda", systemImage: "calendar")
                }
                .buttonStyle(ActionButtonStyle(tint: .secondary, filled: false))
                .help("Ver tus juntas")
                Button(action: onFull) {
                    Label("Letra completa", systemImage: "text.quote")
                }
                .buttonStyle(ActionButtonStyle(tint: .secondary, filled: false))
                .disabled(lyrics.state != .synced && lyrics.state != .plain)
                .help("Ver toda la letra")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.card(false)))
    }
}

/// La línea que se canta, grande; la anterior y la siguiente, tenues.
struct LyricsTicker: View {
    @ObservedObject var music: NowPlaying
    @ObservedObject var lyrics: LyricsStore
    var onShowAll: () -> Void

    var body: some View {
        switch lyrics.state {
        case .synced:
            TimelineView(.periodic(from: .now, by: 0.25)) { context in
                lines(lyrics.lineIndex(at: music.position(at: context.date)))
            }
        case .loading:
            message("Buscando la letra…", symbol: "text.magnifyingglass")
        case .plain:
            VStack(alignment: .leading, spacing: 8) {
                message("Esta canción trae la letra, pero sin tiempos", symbol: "text.quote")
                Button("Ver la letra", action: onShowAll)
                    .buttonStyle(ActionButtonStyle(tint: Theme.accent, filled: false))
            }
        case .instrumental:
            message("Instrumental", symbol: "music.note")
        case .notFound:
            message("No encontré la letra de esta canción", symbol: "text.badge.xmark")
        case .off:
            message("La letra está apagada (Configuración › Hoy)", symbol: "text.quote")
        case .idle:
            message("", symbol: "music.note")
        }
    }

    private func lines(_ index: Int?) -> some View {
        let all = lyrics.result.lines
        let previous = index.flatMap { $0 > 0 ? all[$0 - 1].text : nil }
        let current = index.map { all[$0].text } ?? ""
        let nextIndex = (index ?? -1) + 1
        let next = nextIndex < all.count ? all[nextIndex].text : ""
        return VStack(alignment: .leading, spacing: 8) {
            Text(LyricsTicker.show(previous ?? ""))
                .font(.system(size: 13))
                .foregroundColor(Color.primary.opacity(previous == nil ? 0 : 0.35))
                .lineLimit(1)
            Text(LyricsTicker.show(current))
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
                .fixedSize(horizontal: false, vertical: true)
                .id(index ?? -1)
                .transition(.opacity)
            Text(LyricsTicker.show(next))
                .font(.system(size: 13))
                .foregroundColor(Color.primary.opacity(next.isEmpty ? 0 : 0.55))
                .lineLimit(1)
        }
        .animation(.easeOut(duration: 0.25), value: index ?? -1)
    }

    /// Los renglones vacíos son partes sin letra (un solo de guitarra, por ejemplo).
    static func show(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespaces).isEmpty ? "♪" : text
    }

    private func message(_ text: String, symbol: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
            Text(text)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Tu siguiente junta, en un renglón (con "Unirme" si trae link).
struct NextMeetingStrip: View {
    @ObservedObject var agenda: CalendarStore

    var body: some View {
        if let meeting = agenda.meetings.first(where: { !$0.allDay }) {
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(meeting.isNow ? Theme.success : Theme.accent)
                Text(label(meeting))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if meeting.joinURL != nil {
                    Button {
                        agenda.join(meeting)
                    } label: {
                        Label(meeting.service.map { "Unirme · \($0)" } ?? "Unirme", systemImage: "video.fill")
                    }
                    .buttonStyle(ActionButtonStyle(tint: meeting.isNow || meeting.startsSoon ? Theme.success : Theme.accent,
                                                   filled: meeting.isNow || meeting.startsSoon))
                }
            }
        }
    }

    private func label(_ meeting: Meeting) -> String {
        if meeting.isNow { return "Ahora: \(meeting.title)" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_MX")
        formatter.dateFormat = "h:mm a"
        let day = Calendar.current.isDateInTomorrow(meeting.start) ? "Mañana " : ""
        return "\(day)\(formatter.string(from: meeting.start)) · \(meeting.title)"
    }
}

// MARK: - Letra completa

struct FullLyricsView: View {
    @ObservedObject var music: NowPlaying
    @ObservedObject var lyrics: LyricsStore
    var onBack: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 8) {
                ArtworkView(image: music.artwork, color: music.artColor, size: 88, radius: 12)
                    .onTapGesture { music.openPlayer() }
                VStack(spacing: 1) {
                    Text(music.track?.title ?? "")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Text(music.track?.artist ?? "")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                SongProgress(music: music, tint: music.artColor ?? Theme.accent)
                PlayerControls(music: music, compact: true)
            }
            .padding(12)
            .frame(width: 196)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.card(false)))

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "text.quote")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundColor(music.artColor ?? Theme.accent)
                    Text("Letra")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                    Spacer(minLength: 4)
                    Text(lyrics.state == .synced ? "Toca una línea para ir ahí · LRCLIB" : "LRCLIB")
                        .font(.system(size: 9.5))
                        .foregroundColor(.secondary)
                    Button(action: onBack) {
                        Image(systemName: "chevron.up.circle.fill")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Regresar a la letra en vivo")
                    .accessibilityLabel("Regresar")
                }
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.card(false)))
        }
    }

    @ViewBuilder
    private var content: some View {
        switch lyrics.state {
        case .synced:
            TimelineView(.periodic(from: .now, by: 0.25)) { context in
                LyricsScroller(lines: lyrics.result.lines,
                               index: lyrics.lineIndex(at: music.position(at: context.date)),
                               tint: music.artColor ?? Theme.accent,
                               onTap: { line in music.seek(to: line.time) })
            }
        case .plain:
            ScrollView(.vertical, showsIndicators: true) {
                Text(lyrics.result.plain)
                    .font(.system(size: 12.5))
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        case .loading:
            Text("Buscando la letra…").font(.system(size: 12.5)).foregroundColor(.secondary)
        case .instrumental:
            Text("Instrumental ♪").font(.system(size: 12.5)).foregroundColor(.secondary)
        case .notFound:
            Text("No encontré la letra de esta canción.").font(.system(size: 12.5)).foregroundColor(.secondary)
        case .off:
            Text("La letra está apagada (Configuración › Hoy).").font(.system(size: 12.5)).foregroundColor(.secondary)
        case .idle:
            EmptyView()
        }
    }
}

/// Toda la letra; la línea que suena se ve grande y se queda al centro.
struct LyricsScroller: View {
    let lines: [LyricLine]
    let index: Int?
    let tint: Color
    var onTap: (LyricLine) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(lines) { line in
                        row(line)
                    }
                }
                .padding(.vertical, 50)
            }
            .onAppear {
                if let index = index { proxy.scrollTo(index, anchor: .center) }
            }
            .onChange(of: index) { newIndex in
                guard let newIndex = newIndex else { return }
                withAnimation(.easeInOut(duration: 0.35)) {
                    proxy.scrollTo(newIndex, anchor: .center)
                }
            }
        }
    }

    private func row(_ line: LyricLine) -> some View {
        let isCurrent = line.id == index
        let isPast = index.map { line.id < $0 } ?? false
        return Text(LyricsTicker.show(line.text))
            .font(.system(size: isCurrent ? 16 : 13, weight: isCurrent ? .bold : .regular))
            .foregroundColor(isCurrent ? Color.primary : Color.primary.opacity(isPast ? 0.32 : 0.62))
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { onTap(line) }
            .id(line.id)
    }
}

// MARK: - Música (junto a la agenda)

struct MusicCard: View {
    @ObservedObject var music: NowPlaying
    /// Regresar a la letra en vivo (nil = no hay nada sonando).
    var onLyrics: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "music.note")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(music.artColor ?? Theme.accent)
                Text(music.track?.player.name ?? "Música")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                Spacer(minLength: 0)
                if let onLyrics = onLyrics {
                    Button(action: onLyrics) {
                        Image(systemName: "text.quote")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Ver la letra en vivo")
                    .accessibilityLabel("Ver la letra")
                }
            }

            if !music.enabled {
                Text("La música está apagada en Configuración › Hoy.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let track = music.track {
                HStack(alignment: .top, spacing: 10) {
                    ArtworkView(image: music.artwork, color: music.artColor, size: 48, radius: 9)
                        .onTapGesture { music.openPlayer() }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.title)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundColor(.primary)
                            .lineLimit(2)
                        Text(track.artist)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                SongProgress(music: music, tint: music.artColor ?? Theme.accent)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Nada sonando")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(.primary)
                    Text("Pon algo en Spotify o en Música y aquí verás la carátula y la letra.")
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
            HStack {
                Spacer(minLength: 0)
                PlayerControls(music: music)
                Spacer(minLength: 0)
            }
        }
        .padding(12)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.card(false)))
    }
}

// MARK: - Isla cerrada sin compañero: carátula y barritas

struct MusicWingsView: View {
    let notchWidth: CGFloat
    let wing: CGFloat
    let height: CGFloat
    let artwork: NSImage?
    let color: Color
    let animated: Bool

    var body: some View {
        HStack(spacing: 0) {
            ArtworkView(image: artwork, color: color, size: min(20, height * 0.62), radius: 5)
                .frame(width: wing)
            Spacer(minLength: notchWidth)
            EqualizerBars(color: color, height: min(14, height * 0.42), animated: animated)
                .frame(width: wing)
        }
        .frame(width: notchWidth + wing * 2, height: height)
    }
}

// MARK: - Agenda

struct AgendaCard: View {
    @ObservedObject var agenda: CalendarStore
    var onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(Theme.accent)
                Text("Agenda")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                Spacer(minLength: 0)
                if agenda.isConfigured {
                    Button {
                        agenda.refresh(forceLinks: true)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Actualizar")
                }
            }

            if !agenda.isConfigured {
                connectView
            } else if agenda.meetings.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Nada más por hoy ni mañana")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(.primary)
                    Text("Tu agenda está libre. Si esperabas algo aquí, revisa Configuración › Hoy.")
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(groups) { group in
                            Text(group.title)
                                .font(.system(size: 9.5, weight: .bold))
                                .foregroundColor(.secondary)
                                .textCase(.uppercase)
                                .padding(.top, group.id == groups.first?.id ? 0 : 4)
                            ForEach(group.meetings) { meeting in
                                MeetingRow(meeting: meeting, onJoin: { agenda.join(meeting) })
                            }
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.card(false)))
    }

    private struct AgendaGroup: Identifiable {
        let title: String
        let meetings: [Meeting]
        var id: String { title }
    }

    private var groups: [AgendaGroup] {
        let calendar = Calendar.current
        let today = agenda.meetings.filter { calendar.isDateInToday($0.start) || ($0.start < Date() && $0.end > Date()) }
        let tomorrow = agenda.meetings.filter { !today.contains($0) && calendar.isDateInTomorrow($0.start) }
        var result: [AgendaGroup] = []
        if !today.isEmpty { result.append(AgendaGroup(title: "Hoy", meetings: today)) }
        if !tomorrow.isEmpty { result.append(AgendaGroup(title: "Mañana", meetings: tomorrow)) }
        return result
    }

    private var connectView: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Conecta tu calendario")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundColor(.primary)
            Text("Usa el Calendario de tu Mac (ahí puedes agregar Gmail y Outlook/Teams) o pega el link de tu calendario.")
                .font(.system(size: 10.5))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Button("Usar Calendario de la Mac") {
                    agenda.useMacCalendar = true
                }
                .buttonStyle(ActionButtonStyle(tint: Theme.accent, filled: true))
                Button("Más opciones…", action: onOpenSettings)
                    .buttonStyle(ActionButtonStyle(tint: Theme.accent, filled: false))
            }
            if agenda.useMacCalendar && agenda.access == .denied {
                Button("Dar permiso en Ajustes") { agenda.openPrivacySettings() }
                    .buttonStyle(PillButtonStyle(tint: Theme.warning))
            }
        }
    }
}

struct MeetingRow: View {
    let meeting: Meeting
    var onJoin: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(meeting.color)
                .frame(width: 3, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(timeText)
                        .font(.system(size: 10, weight: .semibold))
                        .monospacedDigit()
                        .foregroundColor(meeting.isNow ? Theme.success : .secondary)
                    if meeting.isNow {
                        Text("AHORA")
                            .font(.system(size: 8.5, weight: .heavy))
                            .foregroundColor(Theme.success)
                    }
                }
                Text(meeting.title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if meeting.joinURL != nil {
                Button(action: onJoin) {
                    Label(meeting.service.map { "Unirme · \($0)" } ?? "Unirme", systemImage: "video.fill")
                }
                .buttonStyle(ActionButtonStyle(tint: meeting.isNow || meeting.startsSoon ? Theme.success : Theme.accent,
                                               filled: meeting.isNow || meeting.startsSoon))
                .help(meeting.joinURL?.host ?? "")
            }
        }
        .padding(.vertical, 3)
        .help([meeting.title, meeting.location, meeting.calendar].filter { !$0.isEmpty }.joined(separator: "\n"))
    }

    private var timeText: String {
        if meeting.allDay { return "Todo el día" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_MX")
        formatter.dateFormat = "h:mm a"
        return "\(formatter.string(from: meeting.start)) – \(formatter.string(from: meeting.end))"
    }
}

extension Meeting {
    /// Empieza en menos de 10 minutos.
    var startsSoon: Bool {
        let until = start.timeIntervalSinceNow
        return until > 0 && until < 10 * 60
    }
}

extension String {
    /// "martes 29 de septiembre" → "Martes 29 de septiembre"
    var capitalizedFirst: String {
        prefix(1).uppercased() + dropFirst()
    }
}
