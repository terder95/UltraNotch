import AppKit
import EventKit
import SwiftUI

// Tu agenda en la isla: las juntas de hoy y mañana, con botón "Unirme" para Teams, Meet y Zoom.
//
// De dónde salen:
//  • Calendario de la Mac: incluye Google (Gmail) y Outlook / Teams si los agregaste en
//    Ajustes del Sistema › Cuentas de internet. Es lo más fácil y se actualiza solo.
//  • Links de calendario (.ics): el "link secreto" de Google Calendar o el de "Publicar calendario"
//    de Outlook. Sirve si tu empresa no deja agregar la cuenta a la Mac.
// Todo se lee en tu Mac; Isla no manda tu agenda a ningún lado.

struct Meeting: Identifiable, Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let allDay: Bool
    let location: String
    let joinURL: URL?
    /// "Teams", "Meet", "Zoom", "Webex"
    let service: String?
    let calendar: String
    let color: Color

    var isNow: Bool {
        let now = Date()
        return start <= now && end > now
    }
}

/// Un link de calendario (.ics) que agregaste.
struct CalendarLink: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var url: String
}

@MainActor
final class CalendarStore: ObservableObject {
    enum Access: Equatable {
        case unknown, granted, denied
    }

    @Published private(set) var meetings: [Meeting] = []
    @Published private(set) var access: Access = .unknown
    /// Leer el Calendario de la Mac.
    @Published var useMacCalendar = false {
        didSet {
            UserDefaults.standard.set(useMacCalendar, forKey: Keys.mac)
            if useMacCalendar { requestAccess() } else { refresh() }
        }
    }
    @Published private(set) var links: [CalendarLink] = []
    /// Avisarte X minutos antes de una junta (0 = no avisar).
    @Published var remindMinutes: Double = 5 {
        didSet { UserDefaults.standard.set(remindMinutes, forKey: Keys.remind) }
    }
    /// Qué pasó con los links (.ics), para Configuración.
    @Published private(set) var linkStatus: [UUID: String] = [:]

    /// Es hora de tu junta (para el aviso y el botón "Unirme").
    var onReminder: ((Meeting) -> Void)?

    var isConfigured: Bool {
        (useMacCalendar && access == .granted) || links.contains { !$0.url.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private enum Keys {
        static let mac = "calendarUseMac"
        static let links = "calendarLinks"
        static let remind = "calendarRemindMinutes"
    }

    private let store = EKEventStore()
    private var linkEvents: [UUID: [Meeting]] = [:]
    private var lastLinkFetch = Date.distantPast
    private var reminded = Set<String>()
    private var timer: Timer?
    private var changeObserver: NSObjectProtocol?
    private var pendingFetch: Task<Void, Never>?

    init() {
        // Modo capturas: sin tu calendario (las juntas de ejemplo llegan con cargarDemo).
        if ModoCapturas.activo {
            useMacCalendar = true
            access = .granted
            return
        }
        let defaults = UserDefaults.standard
        useMacCalendar = defaults.object(forKey: Keys.mac) as? Bool ?? false
        remindMinutes = defaults.object(forKey: Keys.remind) as? Double ?? 5
        if let data = defaults.data(forKey: Keys.links),
           let saved = try? JSONDecoder().decode([CalendarLink].self, from: data) {
            links = saved
        }
        access = CalendarStore.currentAccess()
    }

    func start() {
        changeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        refresh(forceLinks: true)
    }

    private func tick() {
        // Cada 30 s revisamos avisos; la agenda se relee cada 5 min y los links cada 15.
        let now = Date()
        if Int(now.timeIntervalSince1970) % 300 < 30 {
            refresh(forceLinks: now.timeIntervalSince(lastLinkFetch) > 15 * 60)
        } else {
            dropFinished()
        }
        checkReminders()
    }

    // MARK: Permiso del Calendario de la Mac

    private static func currentAccess() -> Access {
        let status = EKEventStore.authorizationStatus(for: .event)
        if #available(macOS 14.0, *) {
            if status == .fullAccess { return .granted }
        } else if status == .authorized {
            return .granted
        }
        return status == .notDetermined ? .unknown : .denied
    }

    func requestAccess() {
        access = CalendarStore.currentAccess()
        guard access != .granted else {
            refresh()
            return
        }
        let finish: @Sendable (Bool) -> Void = { [weak self] granted in
            Task { @MainActor in
                guard let strongSelf = self else { return }
                strongSelf.access = granted ? .granted : .denied
                IslaLog.shared.add(granted ? "Calendario de la Mac conectado ✓" : "Sin permiso para el Calendario de la Mac")
                strongSelf.refresh()
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        if #available(macOS 14.0, *) {
            store.requestFullAccessToEvents { granted, _ in finish(granted) }
        } else {
            store.requestAccess(to: .event) { granted, _ in finish(granted) }
        }
    }

    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }

    func openInternetAccounts() {
        let candidates = [
            "x-apple.systempreferences:com.apple.Internet-Accounts-Settings.extension",
            "x-apple.systempreferences:com.apple.preferences.internetaccounts"
        ]
        for link in candidates {
            if let url = URL(string: link), NSWorkspace.shared.open(url) { return }
        }
    }

    // MARK: Links (.ics)

    func addLink() {
        links.append(CalendarLink(name: "", url: ""))
        saveLinks()
    }

    func update(_ link: CalendarLink) {
        guard let index = links.firstIndex(where: { $0.id == link.id }) else { return }
        let changedURL = links[index].url != link.url
        links[index] = link
        saveLinks()
        if changedURL {
            linkEvents[link.id] = nil
            linkStatus[link.id] = nil
            rebuild()
            // Lo leemos en cuanto dejes de escribir (no en cada tecla).
            pendingFetch?.cancel()
            pendingFetch = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                guard !Task.isCancelled else { return }
                self?.refresh(forceLinks: true)
            }
        }
    }

    func remove(_ link: CalendarLink) {
        links.removeAll { $0.id == link.id }
        linkEvents[link.id] = nil
        linkStatus[link.id] = nil
        saveLinks()
        rebuild()
    }

    private func saveLinks() {
        if let data = try? JSONEncoder().encode(links) {
            UserDefaults.standard.set(data, forKey: Keys.links)
        }
    }

    // MARK: Leer la agenda

    /// De hoy temprano a mañana en la noche.
    private var window: (start: Date, end: Date) {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let end = calendar.date(byAdding: .day, value: 2, to: start) ?? start.addingTimeInterval(2 * 86400)
        return (start, end)
    }

    /// Modo capturas: juntas inventadas.
    func cargarDemo(_ juntas: [Meeting]) {
        meetings = juntas
    }

    func refresh(forceLinks: Bool = false) {
        if ModoCapturas.activo { return }
        access = CalendarStore.currentAccess()
        if forceLinks || Date().timeIntervalSince(lastLinkFetch) > 15 * 60 {
            fetchLinks()
        }
        rebuild()
    }

    private func macMeetings() -> [Meeting] {
        guard useMacCalendar, access == .granted else { return [] }
        let range = window
        let predicate = store.predicateForEvents(withStart: range.start, end: range.end, calendars: nil)
        return store.events(matching: predicate).compactMap { event -> Meeting? in
            if event.status == .canceled { return nil }
            let texts = [event.url?.absoluteString, event.location, event.notes].compactMap { $0 }
            let join = MeetingLinks.find(in: texts)
            let color = event.calendar.map { Color(nsColor: $0.color) } ?? Theme.accent
            return Meeting(
                id: "mac-\(event.eventIdentifier ?? UUID().uuidString)-\(event.startDate.timeIntervalSince1970)",
                title: event.title?.isEmpty == false ? event.title! : "(Sin título)",
                start: event.startDate,
                end: event.endDate,
                allDay: event.isAllDay,
                location: event.location ?? "",
                joinURL: join?.url,
                service: join?.service,
                calendar: event.calendar?.title ?? "",
                color: color
            )
        }
    }

    private func fetchLinks() {
        lastLinkFetch = Date()
        let range = window
        for link in links {
            let raw = link.url.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else { continue }
            let fixed = raw.hasPrefix("webcal://") ? "https://" + raw.dropFirst("webcal://".count) : raw
            guard let url = URL(string: fixed), url.scheme?.hasPrefix("http") == true else {
                linkStatus[link.id] = "El link debe empezar con https:// o webcal://"
                continue
            }
            let id = link.id
            let name = link.name.isEmpty ? (url.host ?? "Calendario") : link.name
            linkStatus[id] = "Leyendo…"
            Task.detached(priority: .utility) { [weak self] in
                var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
                request.setValue("Isla (calendario)", forHTTPHeaderField: "User-Agent")
                let status: String
                var events: [ICSEvent] = []
                do {
                    let (data, response) = try await URLSession.shared.data(for: request)
                    let code = (response as? HTTPURLResponse)?.statusCode ?? 200
                    if code >= 400 {
                        status = "No se pudo leer (error \(code)); revisa el link"
                    } else if let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1),
                              text.contains("BEGIN:VCALENDAR") {
                        events = ICSParser.events(in: text, from: range.start, to: range.end)
                        status = "Conectado ✓"
                    } else {
                        status = "Ese link no es un calendario (.ics)"
                    }
                } catch {
                    status = "Sin conexión; lo intento más tarde"
                }
                let found = events
                await self?.applyLink(id, name: name, events: found, status: status)
            }
        }
    }

    private func applyLink(_ id: UUID, name: String, events: [ICSEvent], status: String) {
        linkStatus[id] = status
        guard links.contains(where: { $0.id == id }) else { return }
        if status.hasPrefix("Conectado") {
            linkEvents[id] = events.map { event in
                let join = MeetingLinks.find(in: [event.url, event.location, event.notes].compactMap { $0 })
                return Meeting(
                    id: "ics-\(event.uid)-\(event.start.timeIntervalSince1970)",
                    title: event.title.isEmpty ? "(Sin título)" : event.title,
                    start: event.start,
                    end: event.end,
                    allDay: event.allDay,
                    location: event.location ?? "",
                    joinURL: join?.url,
                    service: join?.service,
                    calendar: name,
                    color: Theme.accent
                )
            }
        }
        rebuild()
    }

    private func rebuild() {
        let now = Date()
        var all = macMeetings() + linkEvents.values.flatMap { $0 }
        all = all.filter { $0.end > now }
        // La misma junta en dos calendarios (por ejemplo, la Mac y un link): solo una vez.
        var seen = Set<String>()
        all = all.sorted { ($0.allDay ? 0 : 1, $0.start) < ($1.allDay ? 0 : 1, $1.start) }
            .filter { seen.insert("\($0.title.lowercased())|\(Int($0.start.timeIntervalSince1970))").inserted }
        all.sort { $0.start < $1.start }
        if all != meetings { meetings = all }
    }

    private func dropFinished() {
        let now = Date()
        let current = meetings.filter { $0.end > now }
        if current.count != meetings.count { meetings = current }
    }

    // MARK: Avisos

    private func checkReminders() {
        guard remindMinutes > 0 else { return }
        let now = Date()
        for meeting in meetings where !meeting.allDay && !reminded.contains(meeting.id) {
            let until = meeting.start.timeIntervalSince(now)
            if until <= remindMinutes * 60 && until > -60 {
                reminded.insert(meeting.id)
                onReminder?(meeting)
            }
        }
        if reminded.count > 300 { reminded.removeAll() }
    }

    /// Abre la junta (Teams en su app si la tienes).
    func join(_ meeting: Meeting) {
        guard let url = meeting.joinURL else { return }
        NSWorkspace.shared.open(MeetingLinks.appURL(for: url))
        IslaLog.shared.add("Abriendo la junta “\(meeting.title)”\(meeting.service.map { " en \($0)" } ?? "")")
    }
}

// MARK: - Links de juntas

enum MeetingLinks {
    private static let patterns: [(String, String)] = [
        ("Teams", "https://teams\\.microsoft\\.com/l/meetup-join/[^\\s\"<>)]+"),
        ("Teams", "https://teams\\.live\\.com/meet/[^\\s\"<>)]+"),
        ("Teams", "https://teams\\.microsoft\\.com/meet/[^\\s\"<>)]+"),
        ("Meet", "https://meet\\.google\\.com/[a-z]{3}-[a-z]{4}-[a-z]{3}"),
        ("Zoom", "https://[\\w.-]*zoom\\.us/(?:j|my|w|s)/[^\\s\"<>)]+"),
        ("Webex", "https://[\\w.-]*webex\\.com/[^\\s\"<>)]+")
    ]

    static func find(in texts: [String]) -> (url: URL, service: String)? {
        let joined = texts.joined(separator: "\n")
        guard !joined.isEmpty else { return nil }
        for (service, pattern) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let match = regex.firstMatch(in: joined, range: NSRange(joined.startIndex..., in: joined)),
                  let range = Range(match.range, in: joined) else { continue }
            var link = String(joined[range])
            while let last = link.last, ".,;>".contains(last) { link.removeLast() }
            if let url = URL(string: link) { return (url, service) }
        }
        return nil
    }

    /// Teams se abre directo en su app (si está instalada) en lugar del navegador.
    @MainActor static func appURL(for url: URL) -> URL {
        let text = url.absoluteString
        let teamsApps = ["com.microsoft.teams2", "com.microsoft.teams"]
        let hasTeams = teamsApps.contains { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil }
        if hasTeams, text.hasPrefix("https://teams.microsoft.com/"),
           let app = URL(string: "msteams:" + text.dropFirst("https://teams.microsoft.com".count)) {
            return app
        }
        return url
    }
}

// MARK: - Lector de calendarios .ics

struct ICSEvent: Sendable {
    let uid: String
    let title: String
    let start: Date
    let end: Date
    let allDay: Bool
    let location: String?
    let notes: String?
    let url: String?
}

/// Lee lo básico de un .ics (juntas, repeticiones diarias/semanales/mensuales, excepciones).
enum ICSParser {
    private struct Property {
        let name: String
        let params: [String: String]
        let value: String
    }

    private struct RawEvent {
        var props: [Property] = []

        func first(_ name: String) -> Property? { props.first { $0.name == name } }
        func all(_ name: String) -> [Property] { props.filter { $0.name == name } }
    }

    static func events(in text: String, from windowStart: Date, to windowEnd: Date) -> [ICSEvent] {
        let raws = parse(text)
        // Juntas movidas o canceladas de una serie (RECURRENCE-ID): reemplazan a la original.
        var overrides: [String: Set<Int>] = [:]
        for raw in raws {
            guard let uid = raw.first("UID")?.value, let recurrence = raw.first("RECURRENCE-ID"),
                  let date = date(recurrence) else { continue }
            overrides[uid, default: []].insert(Int(date.date.timeIntervalSince1970))
        }

        var result: [ICSEvent] = []
        for raw in raws {
            if raw.first("STATUS")?.value.uppercased() == "CANCELLED" { continue }
            guard let startProp = raw.first("DTSTART"), let start = date(startProp) else { continue }
            let uid = raw.first("UID")?.value ?? UUID().uuidString
            let duration: TimeInterval
            if let endProp = raw.first("DTEND"), let end = date(endProp) {
                duration = max(0, end.date.timeIntervalSince(start.date))
            } else if let text = raw.first("DURATION")?.value {
                duration = parseDuration(text)
            } else {
                duration = start.allDay ? 86400 : 0
            }
            let make: (Date) -> ICSEvent = { begin in
                ICSEvent(
                    uid: uid,
                    title: unescape(raw.first("SUMMARY")?.value ?? ""),
                    start: begin,
                    end: begin.addingTimeInterval(duration),
                    allDay: start.allDay,
                    location: raw.first("LOCATION").map { unescape($0.value) },
                    notes: raw.first("DESCRIPTION").map { unescape($0.value) },
                    url: raw.first("URL")?.value
                )
            }

            if raw.first("RECURRENCE-ID") != nil || raw.first("RRULE") == nil {
                // Junta de una sola vez (o una excepción de una serie).
                if start.date < windowEnd && start.date.addingTimeInterval(max(duration, 1)) > windowStart {
                    result.append(make(start.date))
                }
                continue
            }

            guard let rule = raw.first("RRULE")?.value else { continue }
            var skip = overrides[uid] ?? []
            for exdate in raw.all("EXDATE") {
                for piece in exdate.value.split(separator: ",") {
                    let single = Property(name: "EXDATE", params: exdate.params, value: String(piece))
                    if let excluded = date(single) { skip.insert(Int(excluded.date.timeIntervalSince1970)) }
                }
            }
            for occurrence in expand(rule: rule, start: start.date, timeZone: start.timeZone, duration: duration,
                                     windowStart: windowStart, windowEnd: windowEnd)
            where !skip.contains(Int(occurrence.timeIntervalSince1970)) {
                result.append(make(occurrence))
            }
        }
        return result
    }

    // MARK: Leer el texto

    private static func parse(_ text: String) -> [RawEvent] {
        // Renglones "doblados": los que empiezan con espacio siguen al anterior.
        var lines: [String] = []
        for rawLine in text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n") {
            if let first = rawLine.first, first == " " || first == "\t", !lines.isEmpty {
                lines[lines.count - 1] += String(rawLine.dropFirst())
            } else {
                lines.append(rawLine)
            }
        }
        var events: [RawEvent] = []
        var current: RawEvent?
        var nested = 0
        for line in lines {
            let upper = line.uppercased()
            if upper == "BEGIN:VEVENT" {
                current = RawEvent()
                nested = 0
                continue
            }
            if upper == "END:VEVENT" {
                if let event = current { events.append(event) }
                current = nil
                continue
            }
            guard current != nil else { continue }
            if upper.hasPrefix("BEGIN:") { nested += 1; continue } // VALARM, etc.
            if upper.hasPrefix("END:") { nested = max(0, nested - 1); continue }
            if nested > 0 { continue }
            if let property = property(line) { current?.props.append(property) }
        }
        return events
    }

    private static func property(_ line: String) -> Property? {
        // NOMBRE;PARAM=valor;PARAM="va:lor":VALOR  (el ":" dentro de comillas no cuenta)
        var inQuotes = false
        var splitIndex: String.Index?
        for index in line.indices {
            let character = line[index]
            if character == "\"" { inQuotes.toggle() }
            if character == ":" && !inQuotes {
                splitIndex = index
                break
            }
        }
        guard let colon = splitIndex else { return nil }
        let head = line[line.startIndex..<colon]
        let value = String(line[line.index(after: colon)...])
        let parts = head.split(separator: ";")
        guard let name = parts.first else { return nil }
        var params: [String: String] = [:]
        for part in parts.dropFirst() {
            let pieces = part.split(separator: "=", maxSplits: 1)
            if pieces.count == 2 {
                params[pieces[0].uppercased()] = pieces[1].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            }
        }
        return Property(name: name.uppercased(), params: params, value: value)
    }

    private static func unescape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\N", with: "\n")
            .replacingOccurrences(of: "\\,", with: ",")
            .replacingOccurrences(of: "\\;", with: ";")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }

    // MARK: Fechas

    private struct ParsedDate {
        let date: Date
        let allDay: Bool
        let timeZone: TimeZone
    }

    private static func date(_ property: Property) -> ParsedDate? {
        let value = property.value.trimmingCharacters(in: .whitespaces)
        let isDateOnly = property.params["VALUE"]?.uppercased() == "DATE" || (value.count == 8 && !value.contains("T"))
        let utc = value.hasSuffix("Z")
        let zone: TimeZone
        if utc {
            zone = TimeZone(identifier: "UTC") ?? .current
        } else if let tzid = property.params["TZID"] {
            zone = timeZone(named: tzid)
        } else {
            zone = .current
        }
        let digits = value.replacingOccurrences(of: "Z", with: "")
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = isDateOnly ? .current : zone
        formatter.dateFormat = isDateOnly ? "yyyyMMdd" : (digits.count >= 15 ? "yyyyMMdd'T'HHmmss" : "yyyyMMdd'T'HHmm")
        guard let parsed = formatter.date(from: isDateOnly ? String(digits.prefix(8)) : digits) else { return nil }
        return ParsedDate(date: parsed, allDay: isDateOnly, timeZone: isDateOnly ? .current : zone)
    }

    /// Zonas con nombre de Windows (así las manda Outlook) → zonas normales.
    private static let windowsZones: [String: String] = [
        "Central Standard Time (Mexico)": "America/Mexico_City",
        "Mountain Standard Time (Mexico)": "America/Mazatlan",
        "Pacific Standard Time (Mexico)": "America/Tijuana",
        "Eastern Standard Time (Mexico)": "America/Cancun",
        "Central Standard Time": "America/Chicago",
        "Eastern Standard Time": "America/New_York",
        "Mountain Standard Time": "America/Denver",
        "US Mountain Standard Time": "America/Phoenix",
        "Pacific Standard Time": "America/Los_Angeles",
        "Central America Standard Time": "America/Guatemala",
        "SA Pacific Standard Time": "America/Bogota",
        "Argentina Standard Time": "America/Argentina/Buenos_Aires",
        "E. South America Standard Time": "America/Sao_Paulo",
        "Pacific SA Standard Time": "America/Santiago",
        "GMT Standard Time": "Europe/London",
        "Romance Standard Time": "Europe/Paris",
        "W. Europe Standard Time": "Europe/Berlin",
        "Central European Standard Time": "Europe/Warsaw",
        "UTC": "UTC",
        "Coordinated Universal Time": "UTC"
    ]

    private static func timeZone(named name: String) -> TimeZone {
        if let zone = TimeZone(identifier: name) { return zone }
        if let mapped = windowsZones[name], let zone = TimeZone(identifier: mapped) { return zone }
        // A veces viene como "/mozilla.org/.../America/Mexico_City".
        if let slash = name.range(of: "/", options: .backwards) {
            let tail = name[name.index(after: slash.lowerBound)...]
            for candidate in [String(name.split(separator: "/").suffix(2).joined(separator: "/")), String(tail)] {
                if let zone = TimeZone(identifier: candidate) { return zone }
            }
        }
        return .current
    }

    private static func parseDuration(_ text: String) -> TimeInterval {
        // P1D, PT1H30M, PT45M, P1W
        var total: TimeInterval = 0
        var number = ""
        var inTime = false
        for character in text.uppercased() {
            if character.isNumber {
                number.append(character)
                continue
            }
            let value = Double(number) ?? 0
            number = ""
            switch character {
            case "T": inTime = true
            case "W": total += value * 7 * 86400
            case "D": total += value * 86400
            case "H": total += value * 3600
            case "M": total += inTime ? value * 60 : value * 30 * 86400
            case "S": total += value
            default: break
            }
        }
        return total
    }

    // MARK: Repeticiones (RRULE)

    private static let weekdays = ["SU": 1, "MO": 2, "TU": 3, "WE": 4, "TH": 5, "FR": 6, "SA": 7]

    private static func expand(rule: String, start: Date, timeZone: TimeZone, duration: TimeInterval,
                               windowStart: Date, windowEnd: Date) -> [Date] {
        var parts: [String: String] = [:]
        for piece in rule.split(separator: ";") {
            let pair = piece.split(separator: "=", maxSplits: 1)
            if pair.count == 2 { parts[pair[0].uppercased()] = String(pair[1]) }
        }
        guard let frequency = parts["FREQ"]?.uppercased() else { return [] }
        let interval = max(1, Int(parts["INTERVAL"] ?? "1") ?? 1)
        let count = parts["COUNT"].flatMap { Int($0) }
        var until: Date?
        if let untilText = parts["UNTIL"] {
            until = date(Property(name: "UNTIL", params: [:], value: untilText))?.date
            if let day = until, !untilText.contains("T") {
                until = day.addingTimeInterval(86399) // hasta el final de ese día
            }
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let byDay: [(ordinal: Int?, weekday: Int)] = (parts["BYDAY"] ?? "").split(separator: ",").compactMap { token in
            let text = String(token).uppercased()
            let code = String(text.suffix(2))
            guard let weekday = weekdays[code] else { return nil }
            let prefix = text.dropLast(2)
            return (prefix.isEmpty ? nil : Int(prefix), weekday)
        }
        let byMonthDay = (parts["BYMONTHDAY"] ?? "").split(separator: ",").compactMap { Int($0) }

        var results: [Date] = []
        var produced = 0
        let limit = 4000
        func consider(_ candidate: Date) -> Bool {
            // false = ya no seguir
            if let until = until, candidate > until { return false }
            if candidate < start { return true }
            produced += 1
            if let count = count, produced > count { return false }
            if candidate < windowEnd && candidate.addingTimeInterval(max(duration, 1)) > windowStart {
                results.append(candidate)
            }
            return candidate < windowEnd
        }

        // Series viejas sin COUNT: brincamos cerca de la ventana (no hace falta contar desde el inicio).
        func firstStep(unit: Double) -> Int {
            guard count == nil else { return 0 }
            let elapsed = windowStart.timeIntervalSince(start) / (unit * Double(interval))
            return max(0, Int(elapsed) - 2)
        }

        switch frequency {
        case "DAILY":
            for step in firstStep(unit: 86400)..<(firstStep(unit: 86400) + limit) {
                guard let candidate = calendar.date(byAdding: .day, value: step * interval, to: start) else { break }
                if !byDay.isEmpty && !byDay.contains(where: { $0.weekday == calendar.component(.weekday, from: candidate) }) {
                    if candidate >= windowEnd { break }
                    continue
                }
                if !consider(candidate) { break }
            }
        case "WEEKLY":
            let days = byDay.isEmpty ? [calendar.component(.weekday, from: start)] : byDay.map { $0.weekday }.sorted()
            let weekStart = calendar.date(byAdding: .day, value: -(calendar.component(.weekday, from: start) - 1), to: start) ?? start
            var stop = false
            let firstWeek = firstStep(unit: 7 * 86400)
            for week in firstWeek..<(firstWeek + limit) where !stop {
                guard let base = calendar.date(byAdding: .weekOfYear, value: week * interval, to: weekStart) else { break }
                for weekday in days {
                    guard let candidate = calendar.date(byAdding: .day, value: weekday - 1, to: base) else { continue }
                    if !consider(candidate) {
                        stop = true
                        break
                    }
                }
            }
        case "MONTHLY":
            for step in 0..<limit {
                guard let month = calendar.date(byAdding: .month, value: step * interval, to: start) else { break }
                var candidates: [Date] = []
                if let first = byDay.first, let ordinal = first.ordinal {
                    if let day = nthWeekday(ordinal, first.weekday, in: month, calendar: calendar, time: start) {
                        candidates.append(day)
                    }
                } else if !byMonthDay.isEmpty {
                    for monthDay in byMonthDay {
                        var components = calendar.dateComponents([.year, .month, .hour, .minute, .second], from: month)
                        components.day = monthDay
                        if let day = calendar.date(from: components),
                           calendar.component(.month, from: day) == calendar.component(.month, from: month) {
                            candidates.append(day)
                        }
                    }
                } else {
                    candidates.append(month)
                }
                var stop = false
                for candidate in candidates.sorted() where !consider(candidate) {
                    stop = true
                    break
                }
                if stop { break }
            }
        case "YEARLY":
            for step in 0..<200 {
                guard let candidate = calendar.date(byAdding: .year, value: step * interval, to: start) else { break }
                if !consider(candidate) { break }
            }
        default:
            break
        }
        return results
    }

    /// "El segundo martes" (2TU) o "el último viernes" (-1FR) del mes.
    private static func nthWeekday(_ ordinal: Int, _ weekday: Int, in month: Date, calendar: Calendar, time: Date) -> Date? {
        var components = calendar.dateComponents([.year, .month], from: month)
        let clock = calendar.dateComponents([.hour, .minute, .second], from: time)
        components.hour = clock.hour
        components.minute = clock.minute
        components.second = clock.second
        components.weekday = weekday
        components.weekdayOrdinal = ordinal
        guard let day = calendar.date(from: components),
              calendar.component(.month, from: day) == components.month else { return nil }
        return day
    }
}
