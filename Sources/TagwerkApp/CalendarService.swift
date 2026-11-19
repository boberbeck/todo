import EventKit
import Foundation
import TagwerkCore

enum CalendarAccess: Equatable {
    case notDetermined
    case granted
    case denied
    /// Ohne Berechtigungstext im App-Bundle darf die App nicht fragen.
    case unavailable
}

/// Wie ein Kalender in Tagwerk erscheint.
enum CalendarDisplayMode: String, CaseIterable, Identifiable {
    case hidden
    case busy
    case titled

    var id: String { rawValue }

    var label: String {
        switch self {
        case .hidden: return "Ausblenden"
        case .busy: return "Als „belegt“"
        case .titled: return "Mit Titel"
        }
    }
}

struct CalendarInfo: Identifiable, Hashable {
    var id: String
    var title: String
    var sourceTitle: String
    var mode: CalendarDisplayMode
}

/// Zugang zu den Kalendern. In der App EventKit, für Screenshots feste Beispieltermine.
@MainActor
protocol CalendarProviding: AnyObject {
    var access: CalendarAccess { get }
    var onChange: (() -> Void)? { get set }
    func requestAccess() async -> CalendarAccess
    func calendars(modes: [String: CalendarDisplayMode]) -> [CalendarInfo]
    func events(on day: LocalDate, modes: [String: CalendarDisplayMode]) -> [CalendarEvent]
    /// Legt einen Zeitblock im Kalender „Tagwerk“ an oder verschiebt ihn. Gibt die Termin-ID zurück.
    func saveBlock(title: String, start: Date, end: Date, existingID: String?) throws -> String?
    func removeBlock(id: String) throws
}

enum CalendarServiceError: Error, CustomStringConvertible {
    case noSource

    var description: String {
        "Es gibt kein Kalenderkonto, in dem Tagwerk einen Kalender anlegen kann."
    }
}

@MainActor
final class EventKitCalendar: CalendarProviding {
    static let blockCalendarTitle = "Tagwerk"

    private let store = EKEventStore()
    var onChange: (() -> Void)?
    private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: store,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.onChange?()
            }
        }
    }

    var access: CalendarAccess {
        guard Bundle.main.object(forInfoDictionaryKey: "NSCalendarsFullAccessUsageDescription") != nil else {
            return .unavailable
        }
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            return .granted
        case .notDetermined:
            return .notDetermined
        default:
            return .denied
        }
    }

    func requestAccess() async -> CalendarAccess {
        guard access == .notDetermined else { return access }
        _ = try? await store.requestFullAccessToEvents()
        return access
    }

    func calendars(modes: [String: CalendarDisplayMode]) -> [CalendarInfo] {
        guard access == .granted else { return [] }
        return store.calendars(for: .event)
            .filter { $0.title != Self.blockCalendarTitle }
            .map { calendar in
                CalendarInfo(
                    id: calendar.calendarIdentifier,
                    title: calendar.title,
                    sourceTitle: calendar.source?.title ?? "",
                    mode: modes[calendar.calendarIdentifier] ?? Self.defaultMode(for: calendar)
                )
            }
            .sorted { ($0.sourceTitle, $0.title) < ($1.sourceTitle, $1.title) }
    }

    func events(on day: LocalDate, modes: [String: CalendarDisplayMode]) -> [CalendarEvent] {
        guard access == .granted else { return [] }
        let visible = store.calendars(for: .event).filter { calendar in
            calendar.title != Self.blockCalendarTitle
                && (modes[calendar.calendarIdentifier] ?? Self.defaultMode(for: calendar)) != .hidden
        }
        guard !visible.isEmpty else { return [] }
        let interval = day.interval()
        let predicate = store.predicateForEvents(withStart: interval.start, end: interval.end, calendars: visible)
        return store.events(matching: predicate).map { event in
            let calendar = event.calendar
            let mode = calendar.map { modes[$0.calendarIdentifier] ?? Self.defaultMode(for: $0) } ?? .busy
            let baseID = event.eventIdentifier ?? event.calendarItemIdentifier
            return CalendarEvent(
                id: "\(baseID)@\(Int(event.startDate.timeIntervalSince1970))",
                title: event.title ?? "",
                start: event.startDate,
                end: event.endDate,
                isAllDay: event.isAllDay,
                calendarID: calendar?.calendarIdentifier ?? "",
                calendarTitle: calendar?.title ?? "",
                showsTitle: mode == .titled
            )
        }
        .sorted { $0.start < $1.start }
    }

    func saveBlock(title: String, start: Date, end: Date, existingID: String?) throws -> String? {
        guard access == .granted else { return existingID }
        let event = existingID.flatMap { store.event(withIdentifier: $0) } ?? EKEvent(eventStore: store)
        event.title = title
        event.startDate = start
        event.endDate = end
        event.calendar = try blockCalendar()
        try store.save(event, span: .thisEvent, commit: true)
        return event.eventIdentifier
    }

    func removeBlock(id: String) throws {
        guard access == .granted, let event = store.event(withIdentifier: id) else { return }
        try store.remove(event, span: .thisEvent, commit: true)
    }

    private func blockCalendar() throws -> EKCalendar {
        if let existing = store.calendars(for: .event).first(where: {
            $0.title == Self.blockCalendarTitle && $0.allowsContentModifications
        }) {
            return existing
        }
        let calendar = EKCalendar(for: .event, eventStore: store)
        calendar.title = Self.blockCalendarTitle
        guard let source = store.defaultCalendarForNewEvents?.source
            ?? store.sources.first(where: { $0.sourceType == .local }) else {
            throw CalendarServiceError.noSource
        }
        calendar.source = source
        try store.saveCalendar(calendar, commit: true)
        return calendar
    }

    /// Geburtstage und Feiertage blenden wir aus, Exchange (Outlook) zeigt Titel, alles andere „belegt“.
    static func defaultMode(for calendar: EKCalendar) -> CalendarDisplayMode {
        switch calendar.type {
        case .birthday:
            return .hidden
        case .subscription:
            let title = calendar.title.lowercased()
            let isHoliday = ["feiertag", "holiday", "ferien"].contains { title.contains($0) }
            return isHoliday ? .hidden : .busy
        case .exchange:
            return .titled
        default:
            return .busy
        }
    }
}

/// Feste Beispieltermine für Screenshots und den Demo-Modus.
@MainActor
final class DemoCalendar: CalendarProviding {
    var onChange: (() -> Void)?
    var access: CalendarAccess { .granted }

    func requestAccess() async -> CalendarAccess { .granted }

    func calendars(modes: [String: CalendarDisplayMode]) -> [CalendarInfo] {
        [
            CalendarInfo(id: "demo-work", title: "Kalender", sourceTitle: "Exchange", mode: modes["demo-work"] ?? .titled),
            CalendarInfo(id: "demo-private", title: "Privat", sourceTitle: "iCloud", mode: modes["demo-private"] ?? .busy),
        ]
    }

    func events(on day: LocalDate, modes: [String: CalendarDisplayMode]) -> [CalendarEvent] {
        func at(_ hour: Int, _ minute: Int = 0) -> Date {
            FreeTime.date(on: day, minutes: hour * 60 + minute)
        }
        let all = [
            CalendarEvent(id: "demo-jourfixe", title: "Jour fixe", start: at(9), end: at(9, 30),
                          calendarID: "demo-work", calendarTitle: "Kalender"),
            CalendarEvent(id: "demo-privat", title: "Zahnarzt", start: at(10, 30), end: at(11, 30),
                          calendarID: "demo-private", calendarTitle: "Privat"),
            CalendarEvent(id: "demo-kunde", title: "Kundentermin Stadtwerke", start: at(14), end: at(15),
                          calendarID: "demo-work", calendarTitle: "Kalender"),
        ]
        let modeByCalendar = Dictionary(uniqueKeysWithValues: calendars(modes: modes).map { ($0.id, $0.mode) })
        return all.compactMap { event in
            let mode = modeByCalendar[event.calendarID] ?? .busy
            guard mode != .hidden else { return nil }
            var shown = event
            shown.showsTitle = mode == .titled
            return shown
        }
    }

    func saveBlock(title: String, start: Date, end: Date, existingID: String?) throws -> String? { existingID }

    func removeBlock(id: String) throws {}
}
