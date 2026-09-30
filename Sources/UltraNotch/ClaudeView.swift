import SwiftUI
import AppKit

// MARK: - Actividad en vivo junto al notch (isla cerrada)

struct LiveActivityView: View {
    let activity: LiveActivity?
    var base: Color = Theme.accent
    let notchWidth: CGFloat
    let wing: CGFloat
    let height: CGFloat
    let visible: Bool

    var body: some View {
        HStack(spacing: 0) {
            HStack {
                BuddyGroup(statuses: activity?.statuses ?? [], size: min(18, height * 0.5), animated: visible, base: base)
                Spacer(minLength: 0)
            }
            .frame(width: wing - 12)
            .padding(.leading, 12)

            Spacer(minLength: notchWidth)

            VStack(alignment: .trailing, spacing: 0) {
                Text(activity?.title ?? "")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(activity?.tint ?? Theme.accent)
                    .lineLimit(1)
                Text(activity?.subtitle ?? "")
                    .font(.system(size: 9))
                    .foregroundColor(Color.white.opacity(0.6))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(width: wing - 12, alignment: .trailing)
            .padding(.trailing, 12)
        }
        .frame(width: notchWidth + wing * 2, height: height)
    }
}

// MARK: - Tarjeta de permiso que baja del notch (isla cerrada)

struct ApprovalAlertView: View {
    @ObservedObject var claude: ClaudeCodeMonitor
    let notchWidth: CGFloat
    let notchHeight: CGFloat
    let size: CGSize
    let visible: Bool
    var onExpand: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 0) {
                BuddyGroup(statuses: [.waiting], size: min(18, notchHeight * 0.5), animated: visible)
                    .frame(width: (size.width - notchWidth) / 2 - 16, alignment: .leading)
                Spacer(minLength: notchWidth)
                Text(claude.approvals.first?.isQuestion == true ? "Pregunta" : "Permiso")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(claude.approvals.first?.isQuestion == true ? Theme.accent : Theme.warning)
                    .frame(width: (size.width - notchWidth) / 2 - 16, alignment: .trailing)
            }
            .frame(height: notchHeight)

            if let approval = claude.approvals.first {
                ApprovalCard(approval: approval, claude: claude, compact: true, onExpand: onExpand)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .frame(width: size.width, height: size.height, alignment: .top)
    }
}

/// Contenido común de una petición de permiso: qué quiere hacer y los botones.
struct ApprovalBody: View {
    let approval: ClaudeApproval
    @ObservedObject var claude: ClaudeCodeMonitor
    var compact = false
    var onExpand: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("Claude Code · \(approval.project)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                if claude.approvals.count > 1 {
                    Text("+\(claude.approvals.count - 1)")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundColor(Theme.warning)
                }
                Spacer(minLength: 4)
                if let onExpand = onExpand {
                    Button(action: onExpand) {
                        Image(systemName: "chevron.down.circle.fill")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Abrir el panel")
                }
            }

            HStack(alignment: .top, spacing: 7) {
                Image(systemName: approval.step.symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Theme.warning)
                    .frame(width: 14)
                Text(approval.step.text)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.primary)
                    .lineLimit(compact ? 1 : 2)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.08)))

            if let diff = approval.diff {
                DiffPreview(diff: diff, height: compact ? 64 : 90)
            }

            HStack(spacing: 6) {
                Button("Permitir") { claude.decide(approval, .allow) }
                    .buttonStyle(ActionButtonStyle(tint: Theme.accent, filled: true))
                if approval.suggestions != nil {
                    Button("Siempre") { claude.decide(approval, .always) }
                        .buttonStyle(ActionButtonStyle(tint: Theme.accent, filled: false))
                        .help("Permitir y no volver a preguntar por esto")
                }
                Button("Negar") { claude.decide(approval, .deny) }
                    .buttonStyle(ActionButtonStyle(tint: Theme.danger, filled: false))
                Spacer(minLength: 4)
                Button {
                    claude.decide(approval, .terminal)
                    claude.openTerminal(forApproval: approval)
                } label: {
                    Label("Terminal", systemImage: "terminal")
                }
                .buttonStyle(ActionButtonStyle(tint: .secondary, filled: false))
                .help("Responder en la terminal como siempre")
            }
        }
    }
}

struct ActionButtonStyle: ButtonStyle {
    let tint: Color
    let filled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(filled ? .white : tint)
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(filled ? tint.opacity(configuration.isPressed ? 0.7 : 1) : tint.opacity(configuration.isPressed ? 0.25 : 0.14))
            )
            .contentShape(Capsule())
    }
}

// MARK: - Pestaña "Claude" (isla abierta)

struct ClaudeView: View {
    @ObservedObject var claude: ClaudeCodeMonitor
    @ObservedObject var voice: VoiceWake
    var mascot: Color = Theme.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !claude.hooksInstalled {
                ConnectClaudeCard(claude: claude)
            } else {
                if let approval = claude.approvals.first {
                    ApprovalCard(approval: approval, claude: claude)
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill((approval.isQuestion ? Theme.accent : Theme.warning).opacity(0.12))
                        )
                }
                if claude.sessions.isEmpty {
                    if claude.approvals.isEmpty {
                        EmptyClaudeCard()
                    }
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 6) {
                            ForEach(claude.sessions) { session in
                                SessionCard(session: session, claude: claude, voice: voice, mascot: mascot)
                            }
                        }
                    }
                }
            }
            Spacer(minLength: 0)
            VoiceStatusLine(voice: voice)
        }
    }
}

struct SessionCard: View {
    let session: ClaudeSession
    @ObservedObject var claude: ClaudeCodeMonitor
    @ObservedObject var voice: VoiceWake
    var mascot: Color = Theme.accent

    private var waitingForReply: Bool {
        claude.replyHold?.sessionID == session.id
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            BuddyGroup(statuses: [session.status], size: 22,
                       animated: session.status.isActive || session.status == .waiting, base: mascot)
                .frame(width: 26, height: 26)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(session.project)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Text(session.status.label)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(session.status.tint)
                    Spacer(minLength: 4)
                    Text(Formatters.relative(session.updated))
                        .font(.system(size: 9.5))
                        .foregroundColor(.secondary)
                    if session.terminalBundle != nil {
                        Button {
                            claude.openTerminal(for: session)
                        } label: {
                            Image(systemName: "arrow.up.forward.app")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Abrir la terminal de esta sesión")
                    }
                }

                if let prompt = session.prompt {
                    Text("“\(prompt)”")
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                if session.status == .finished || session.status == .waiting, let summary = session.summary {
                    Text(summary)
                        .font(.system(size: 10.5))
                        .foregroundColor(Color.primary.opacity(0.85))
                        .lineLimit(2)
                } else {
                    ForEach(Array(session.steps.suffix(3).reversed())) { step in
                        HStack(spacing: 5) {
                            Image(systemName: step.symbol)
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                                .frame(width: 12)
                            Text(step.text)
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundColor(Color.primary.opacity(0.85))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }

                if waitingForReply {
                    replyRow
                }
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.card(waitingForReply)))
    }

    /// La sesión terminó y espera unos segundos por si le respondes por voz.
    private var replyRow: some View {
        HStack(spacing: 6) {
            if voice.isDictatingReply {
                Image(systemName: "waveform")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Theme.accent)
                Text(voice.dictation.isEmpty ? "Te escucho…" : voice.dictation)
                    .font(.system(size: 10.5))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.head)
            } else {
                Text("Di “responde…” para contestarle")
                    .font(.system(size: 10.5))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Button {
                    voice.startDictation(for: .reply)
                } label: {
                    Label("Responder", systemImage: "mic.fill")
                }
                .buttonStyle(ActionButtonStyle(tint: Theme.accent, filled: true))
                .disabled(!voice.isReady)
                .help(voice.isReady ? "Dicta tu respuesta" : "Activa “Oye Claudio” en Configuración")
                Button("Ignorar") {
                    claude.releaseReplyHold(reason: "Lo ignoraste")
                }
                .buttonStyle(ActionButtonStyle(tint: .secondary, filled: false))
            }
        }
        .padding(.top, 2)
    }
}

struct ConnectClaudeCard: View {
    @ObservedObject var claude: ClaudeCodeMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                BuddyGroup(statuses: [.working, .thinking, .finished], size: 18)
                Text("Ve a Claude Code desde el notch")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
            }
            Text("Verás qué hace cada sesión (lee, edita, ejecuta), te avisará cuando termine y podrás aprobar permisos sin cambiar de ventana. No usa la API ni cuesta nada extra.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Conectar con Claude Code") {
                claude.connect()
            }
            .buttonStyle(ActionButtonStyle(tint: Theme.accent, filled: true))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.card(false)))
    }
}

struct EmptyClaudeCard: View {
    var body: some View {
        VStack(spacing: 6) {
            BuddyGroup(statuses: [.idle], size: 22, animated: false)
            Text("Sin sesiones activas")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.primary)
            Text("Abre una sesión nueva de Claude Code y aquí verás lo que hace.")
                .font(.system(size: 10.5))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 110)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.15), style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
        )
    }
}

struct VoiceStatusLine: View {
    @ObservedObject var voice: VoiceWake

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(color)
            Text(text)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .lineLimit(1)
            Spacer(minLength: 4)
            if voice.state == .needsPermission {
                Button("Dar permiso") { voice.openPrivacySettings() }
                    .buttonStyle(PillButtonStyle(tint: Theme.warning))
            }
        }
    }

    private var icon: String {
        switch voice.state {
        case .listening: return "waveform"
        case .standby: return "keyboard"
        case .off: return "mic.slash"
        default: return "exclamationmark.triangle.fill"
        }
    }

    private var color: Color {
        switch voice.state {
        case .listening: return Theme.accent
        case .off, .standby: return .secondary
        default: return Theme.warning
        }
    }

    private var text: String {
        switch voice.phase {
        case .awaitingCommand:
            return "Te escucho… di “nuevo chat”, el nombre de un proyecto, “terminal”, “responde” o “permitir”"
        case .dictating:
            let target = voice.dictationTarget?.label ?? "Claude"
            return voice.dictation.isEmpty
                ? "Dictando para \(target)… habla y quédate callado para enviar (o di “cancela”)"
                : "Para \(target): \(voice.dictation)"
        case .idle:
            break
        }
        switch voice.state {
        case .listening:
            if voice.replyWindowOpen { return "Di “responde…” y tu mensaje para contestarle a Claude Code" }
            return "Di “\(voice.displayPhrase)” · luego “nuevo chat…”, “a <proyecto>…”, “cowork…” o “permitir”"
        case .standby: return "Micrófono apagado · mantén ⌥ derecha para hablar"
        case .off: return "“\(voice.displayPhrase)” apagado (actívalo en Configuración)"
        case .needsPermission: return "Falta permiso de micrófono / reconocimiento de voz"
        case .unavailable(let reason): return reason
        }
    }
}
