import SwiftUI
import AppKit

// Preguntas de Claude Code (herramienta "AskUserQuestion") contestadas desde la isla,
// y la vista previa de los cambios de un archivo antes de aprobarlos.
//
// Cómo funciona: cuando Claude te pregunta algo, Claude Code pide "permiso" para mostrarte
// la pregunta. Isla detiene ese permiso, te enseña las opciones y le regresa tu respuesta
// (el mismo formato que usa la terminal). Si no contestas a tiempo, o tocas "Terminal",
// la pregunta aparece en la terminal como siempre.

// MARK: - Modelos

/// Una pregunta con sus opciones (1 a 4 por tarjeta, 2 a 4 opciones cada una).
struct ClaudeQuestion: Identifiable, Equatable {
    struct Option: Equatable {
        let label: String
        let detail: String
    }

    let id: Int
    /// El texto completo (también es la "llave" de la respuesta).
    let text: String
    /// Etiqueta cortita ("Formato", "Base de datos"…).
    let header: String
    let options: [Option]
    let multiSelect: Bool

    /// Lee el `tool_input` de AskUserQuestion.
    static func parse(_ input: [String: Any]) -> [ClaudeQuestion] {
        guard let raw = input["questions"] as? [[String: Any]] else { return [] }
        var result: [ClaudeQuestion] = []
        for (index, item) in raw.enumerated() {
            guard let text = item["question"] as? String,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let options = (item["options"] as? [[String: Any]] ?? []).compactMap { option -> Option? in
                guard let label = option["label"] as? String, !label.isEmpty else { return nil }
                return Option(label: label, detail: option["description"] as? String ?? "")
            }
            result.append(ClaudeQuestion(
                id: index,
                text: text,
                header: item["header"] as? String ?? "",
                options: options,
                multiSelect: item["multiSelect"] as? Bool ?? false
            ))
        }
        return result
    }
}

/// Lo que va a cambiar en un archivo (Edit, MultiEdit o Write), en renglones.
struct ClaudeDiff: Equatable {
    struct Line: Equatable {
        enum Kind { case removed, added, context, gap }
        let kind: Kind
        let text: String
    }

    let file: String
    let lines: [Line]
    /// Renglones que no cupieron.
    let hidden: Int
    let summary: String

    static let enabledKey = "claudeDiffPreview"
    private static let maxLines = 60

    static var enabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? false
    }

    static func make(tool: String, input: [String: Any]) -> ClaudeDiff? {
        let path = input["file_path"] as? String ?? ""
        let file = path.isEmpty ? "archivo" : URL(fileURLWithPath: path).lastPathComponent
        var lines: [Line] = []
        var removed = 0
        var added = 0

        func addPair(_ old: String, _ new: String) {
            let (pairLines, minus, plus) = compare(old, new)
            if !lines.isEmpty && !pairLines.isEmpty { lines.append(Line(kind: .gap, text: "···")) }
            lines += pairLines
            removed += minus
            added += plus
        }

        switch tool {
        case "Edit":
            guard let old = input["old_string"] as? String, let new = input["new_string"] as? String else { return nil }
            addPair(old, new)
        case "MultiEdit":
            guard let edits = input["edits"] as? [[String: Any]], !edits.isEmpty else { return nil }
            for edit in edits {
                guard let old = edit["old_string"] as? String, let new = edit["new_string"] as? String else { continue }
                addPair(old, new)
            }
        case "Write":
            guard let content = input["content"] as? String else { return nil }
            let newLines = split(content)
            lines = newLines.map { Line(kind: .added, text: $0) }
            added = newLines.count
            let exists = !path.isEmpty && FileManager.default.fileExists(atPath: path)
            let summary = exists ? "Reemplaza todo el archivo (\(added) renglones)" : "Archivo nuevo (\(added) renglones)"
            return ClaudeDiff(file: file, lines: Array(lines.prefix(maxLines)),
                              hidden: max(0, lines.count - maxLines), summary: summary)
        default:
            return nil
        }
        guard !lines.isEmpty else { return nil }
        let summary = "−\(removed)  +\(added)"
        return ClaudeDiff(file: file, lines: Array(lines.prefix(maxLines)),
                          hidden: max(0, lines.count - maxLines), summary: summary)
    }

    private static func split(_ text: String) -> [String] {
        var parts = text.components(separatedBy: "\n")
        if parts.last == "" { parts.removeLast() }
        return parts.map { $0.replacingOccurrences(of: "\t", with: "    ") }
    }

    /// Diferencia sencilla: quita lo que se repite al principio y al final y enseña lo de en medio.
    private static func compare(_ old: String, _ new: String) -> ([Line], Int, Int) {
        let a = split(old)
        let b = split(new)
        var start = 0
        while start < a.count && start < b.count && a[start] == b[start] { start += 1 }
        var endA = a.count
        var endB = b.count
        while endA > start && endB > start && a[endA - 1] == b[endB - 1] {
            endA -= 1
            endB -= 1
        }
        var lines: [Line] = []
        if start > 0 { lines.append(Line(kind: .context, text: a[start - 1])) }
        for index in start..<endA { lines.append(Line(kind: .removed, text: a[index])) }
        for index in start..<endB { lines.append(Line(kind: .added, text: b[index])) }
        if endA < a.count { lines.append(Line(kind: .context, text: a[endA])) }
        return (lines, endA - start, endB - start)
    }
}

/// Qué tan alta baja la tarjeta del notch según lo que muestra.
enum ApprovalLayout {
    static func extraHeight(for approval: ClaudeApproval?) -> CGFloat {
        guard let approval = approval else { return 0 }
        if approval.isQuestion {
            let options = approval.questions.map { $0.options.count }.max() ?? 2
            let rows = CGFloat(max(1, (options + 1) / 2))
            return 16 + rows * 44
        }
        if approval.diff != nil { return 96 }
        return 0
    }
}

// MARK: - Tarjeta (permiso o pregunta)

/// Muestra la tarjeta que toque: una pregunta con opciones o un permiso con sus botones.
struct ApprovalCard: View {
    let approval: ClaudeApproval
    @ObservedObject var claude: ClaudeCodeMonitor
    var compact = false
    var onExpand: (() -> Void)?

    var body: some View {
        if approval.isQuestion {
            QuestionBody(approval: approval, claude: claude, compact: compact, onExpand: onExpand)
                .id(approval.id)
        } else {
            ApprovalBody(approval: approval, claude: claude, compact: compact, onExpand: onExpand)
        }
    }
}

// MARK: - Pregunta

/// Lo que llevas contestado de una tarjeta (vive en el monitor: si la isla se cierra o se abre
/// a media respuesta, no se pierde).
struct QuestionDraft: Equatable {
    /// Qué pregunta se ve.
    var index = 0
    /// Pregunta → opciones elegidas (en orden).
    var picked: [Int: [Int]] = [:]
    /// Pregunta → respuesta escrita por ti.
    var written: [Int: String] = [:]

    func answered(_ question: ClaudeQuestion) -> Bool {
        !(picked[question.id] ?? []).isEmpty || written[question.id] != nil
    }
}

extension ClaudeCodeMonitor {
    func draft(for approval: ClaudeApproval) -> QuestionDraft {
        questionDrafts[approval.id] ?? QuestionDraft()
    }

    func currentQuestion(_ approval: ClaudeApproval) -> ClaudeQuestion? {
        guard !approval.questions.isEmpty else { return nil }
        let index = min(max(draft(for: approval).index, 0), approval.questions.count - 1)
        return approval.questions[index]
    }

    private func isPending(_ approval: ClaudeApproval) -> Bool {
        approvals.contains { $0.id == approval.id }
    }

    private func editDraft(_ approval: ClaudeApproval, _ change: (inout QuestionDraft) -> Void) {
        var draft = self.draft(for: approval)
        change(&draft)
        questionDrafts[approval.id] = draft
    }

    /// Tocaste una opción. Si es de una sola respuesta, queda elegida y seguimos (como Enter en la terminal).
    func chooseOption(_ approval: ClaudeApproval, option: Int) {
        guard isPending(approval), let question = currentQuestion(approval) else { return }
        if question.multiSelect {
            editDraft(approval) { draft in
                var chosen = draft.picked[question.id] ?? []
                if let position = chosen.firstIndex(of: option) {
                    chosen.remove(at: position)
                } else {
                    chosen.append(option)
                    chosen.sort()
                }
                draft.picked[question.id] = chosen
            }
        } else {
            editDraft(approval) { draft in
                draft.picked[question.id] = [option]
                draft.written[question.id] = nil
            }
            advanceQuestion(approval)
        }
    }

    /// "Escribir…": contestas con tus palabras (mientras escribes, no se acaba el tiempo).
    func writeAnswer(_ approval: ClaudeApproval) {
        guard isPending(approval), let question = currentQuestion(approval) else { return }
        promptOpen.insert(approval.id)
        let text = TextPrompt.ask(
            title: question.text,
            message: "Escribe tu respuesta para Claude.",
            placeholder: question.options.first.map { "Por ejemplo: \($0.label)" } ?? "Tu respuesta",
            initial: draft(for: approval).written[question.id] ?? "",
            button: "Usar esta respuesta"
        )
        promptOpen.remove(approval.id)
        guard let text = text else { return }
        guard isPending(approval) else {
            onPeek?(Peek(symbol: "clock.badge.exclamationmark", title: "Esa pregunta ya se había cerrado",
                         tint: Theme.warning))
            return
        }
        editDraft(approval) { draft in
            draft.written[question.id] = text
            draft.picked[question.id] = nil
        }
        if !question.multiSelect { advanceQuestion(approval) }
    }

    func previousQuestion(_ approval: ClaudeApproval) {
        editDraft(approval) { $0.index = max(0, $0.index - 1) }
    }

    /// Siguiente pregunta sin contestar; si ya están todas, se manda.
    func advanceQuestion(_ approval: ClaudeApproval) {
        guard isPending(approval), let question = currentQuestion(approval) else { return }
        let draft = self.draft(for: approval)
        guard draft.answered(question) else { return }
        let questions = approval.questions
        let index = min(max(draft.index, 0), questions.count - 1)
        if let next = questions.indices.first(where: { $0 > index && !draft.answered(questions[$0]) })
            ?? questions.indices.first(where: { !draft.answered(questions[$0]) }) {
            editDraft(approval) { $0.index = next }
            return
        }
        var answers: [String: String] = [:]
        for question in questions {
            if let text = draft.written[question.id] {
                answers[question.text] = text
            } else if let chosen = draft.picked[question.id], !chosen.isEmpty {
                answers[question.text] = chosen
                    .filter { question.options.indices.contains($0) }
                    .map { question.options[$0].label }
                    .joined(separator: ", ")
            }
        }
        answer(approval, answers: answers)
    }
}

struct QuestionBody: View {
    let approval: ClaudeApproval
    @ObservedObject var claude: ClaudeCodeMonitor
    var compact = false
    var onExpand: (() -> Void)?

    private var questions: [ClaudeQuestion] { approval.questions }
    private var draft: QuestionDraft { claude.draft(for: approval) }

    var body: some View {
        if let current = claude.currentQuestion(approval) {
            content(current, draft: draft)
        }
    }

    private func content(_ current: ClaudeQuestion, draft: QuestionDraft) -> some View {
        let othersPending = questions.contains { $0.id != current.id && !draft.answered($0) }
        let index = min(max(draft.index, 0), questions.count - 1)
        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: "questionmark.bubble.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Theme.accent)
                Text("\(approval.project) te pregunta")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                if questions.count > 1 {
                    Text("\(index + 1) de \(questions.count)")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
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
                    .help("Abrir la isla")
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if !current.header.isEmpty {
                    Text(current.header)
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundColor(Theme.accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Theme.accent.opacity(0.16)))
                        .lineLimit(1)
                        .fixedSize()
                }
                Text(current.text)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .help(current.text)
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)],
                      alignment: .leading, spacing: 6) {
                ForEach(Array(current.options.enumerated()), id: \.offset) { item in
                    optionButton(item.offset, item.element, question: current,
                                 selected: draft.picked[current.id]?.contains(item.offset) == true)
                }
            }

            HStack(spacing: 6) {
                if index > 0 {
                    Button {
                        claude.previousQuestion(approval)
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(ActionButtonStyle(tint: .secondary, filled: false))
                    .help("Pregunta anterior")
                }
                Button {
                    claude.writeAnswer(approval)
                } label: {
                    Label(draft.written[current.id] == nil ? "Escribir…" : "Editar", systemImage: "pencil")
                }
                .buttonStyle(ActionButtonStyle(tint: Theme.accent, filled: false))
                .help("Contestar con tus palabras")
                if let text = draft.written[current.id] {
                    Text("“\(text)”")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 4)
                if current.multiSelect || draft.written[current.id] != nil {
                    Button(othersPending ? "Siguiente" : "Enviar") {
                        claude.advanceQuestion(approval)
                    }
                    .buttonStyle(ActionButtonStyle(tint: Theme.accent, filled: true))
                    .disabled(!draft.answered(current))
                }
                Button {
                    claude.decide(approval, .terminal)
                    claude.openTerminal(forApproval: approval)
                } label: {
                    Image(systemName: "terminal")
                }
                .buttonStyle(ActionButtonStyle(tint: .secondary, filled: false))
                .help("Contestar en la terminal como siempre")
            }
        }
    }

    private func optionButton(_ number: Int, _ option: ClaudeQuestion.Option, question: ClaudeQuestion,
                              selected: Bool) -> some View {
        Button {
            claude.chooseOption(approval, option: number)
        } label: {
            HStack(alignment: .top, spacing: 5) {
                if question.multiSelect {
                    Image(systemName: selected ? "checkmark.square.fill" : "square")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(selected ? Theme.accent : .secondary)
                        .padding(.top, 1)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(option.label)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    if !option.detail.isEmpty {
                        Text(option.detail)
                            .font(.system(size: 9.5))
                            .foregroundColor(.secondary)
                            .lineLimit(compact ? 1 : 2)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? Theme.accent.opacity(0.28) : Color.primary.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Theme.accent.opacity(selected ? 0.8 : 0), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(option.detail.isEmpty ? option.label : "\(option.label): \(option.detail)")
    }
}

/// Ventanita para escribir (la isla no puede recibir el teclado sin estorbarle a tu app).
@MainActor
enum TextPrompt {
    static func ask(title: String, message: String, placeholder: String, initial: String = "",
                    button: String, deactivateAfter: Bool = true) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: button)
        alert.addButton(withTitle: "Cancelar")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 340, height: 24))
        field.placeholderString = placeholder
        field.stringValue = initial
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        NSApp.activate(ignoringOtherApps: true)
        let result = alert.runModal()
        if deactivateAfter { NSApp.deactivate() }
        guard result == .alertFirstButtonReturn else { return nil }
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}

// MARK: - Vista previa del cambio

struct DiffPreview: View {
    let diff: ClaudeDiff
    var height: CGFloat = 84

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(diff.file)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                Text(diff.summary)
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(diff.lines.enumerated()), id: \.offset) { item in
                        row(item.element)
                    }
                    if diff.hidden > 0 {
                        Text("… y \(diff.hidden) renglones más")
                            .font(.system(size: 9.5))
                            .foregroundColor(.secondary)
                            .padding(.top, 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: height)
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.black.opacity(0.25)))
    }

    private func row(_ line: ClaudeDiff.Line) -> some View {
        let sign: String
        let color: Color
        let fill: Color
        switch line.kind {
        case .removed:
            sign = "−"
            color = Color(red: 1, green: 0.55, blue: 0.55)
            fill = Theme.danger.opacity(0.16)
        case .added:
            sign = "+"
            color = Color(red: 0.55, green: 0.95, blue: 0.6)
            fill = Theme.success.opacity(0.14)
        case .context:
            sign = " "
            color = Color.primary.opacity(0.55)
            fill = Color.clear
        case .gap:
            sign = " "
            color = Color.secondary
            fill = Color.clear
        }
        return HStack(spacing: 4) {
            Text(sign)
                .frame(width: 8, alignment: .center)
            Text(line.text.isEmpty ? " " : line.text)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .font(.system(size: 9.5, design: .monospaced))
        .foregroundColor(color)
        .padding(.horizontal, 3)
        .background(fill)
    }
}
