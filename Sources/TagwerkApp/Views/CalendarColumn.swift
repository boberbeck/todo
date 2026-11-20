import AppKit
import SwiftUI
import TagwerkCore

/// Zeitleiste des Tages: Termine, Zeitblöcke der Aufgaben, erfasste Zeit und die aktuelle Uhrzeit.
struct CalendarColumn: View {
    @Environment(AppModel.self) private var model

    @AppStorage(Preferences.calendarHourHeightKey) private var zoom = Preferences.defaultHourHeight
    private let labelWidth: CGFloat = 40

    /// Höhe einer Stunde; über die Lupen im Kopf einstellbar.
    private var hourHeight: CGFloat {
        CGFloat(min(Preferences.hourHeightRange.upperBound, max(Preferences.hourHeightRange.lowerBound, zoom)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Kalender")
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                HStack(spacing: 6) {
                    Button {
                        zoom = max(Preferences.hourHeightRange.lowerBound, zoom - 16)
                    } label: {
                        Image(systemName: "minus.magnifyingglass")
                    }
                    .disabled(zoom <= Preferences.hourHeightRange.lowerBound)
                    .help("Stunden niedriger")
                    Button {
                        zoom = min(Preferences.hourHeightRange.upperBound, zoom + 16)
                    } label: {
                        Image(systemName: "plus.magnifyingglass")
                    }
                    .disabled(zoom >= Preferences.hourHeightRange.upperBound)
                    .help("Stunden höher")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.top, 16)
            .padding(.bottom, 8)

            accessHint

            if !model.allDayEvents.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(model.allDayEvents) { event in
                        Text(event.displayTitle)
                            .font(.caption)
                            .lineLimit(1)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.06)))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 6)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    timeline
                }
                .onAppear {
                    proxy.scrollTo(scrollAnchorHour, anchor: .top)
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var subtitle: String {
        switch model.calendarAccess {
        case .granted: return "Termine und Zeitblöcke"
        case .notDetermined: return "Noch nicht verbunden"
        case .denied: return "Kein Zugriff"
        case .unavailable: return "Nur in Tagwerk.app"
        }
    }

    @ViewBuilder
    private var accessHint: some View {
        switch model.calendarAccess {
        case .granted:
            EmptyView()
        case .notDetermined:
            Button("Kalender verbinden") {
                Task { await model.requestCalendarAccess() }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
        case .denied:
            VStack(alignment: .leading, spacing: 6) {
                Text("Erlaube den Zugriff in den Systemeinstellungen unter Datenschutz & Sicherheit › Kalender.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Systemeinstellungen öffnen") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .controlSize(.small)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
        case .unavailable:
            Text("Starte Tagwerk als App (scripts/make-app.sh), damit es nach dem Kalender fragen darf.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
        }
    }

    private var firstHour: Int { max(0, model.workday.startMinutes / 60 - 1) }

    private var lastHour: Int { max(firstHour + 1, min(24, (model.workday.endMinutes + 59) / 60 + 1)) }

    private var scrollAnchorHour: Int {
        let current = FreeTime.minutesSinceMidnight(Date()) / 60 - 2
        return max(firstHour, min(lastHour - 1, current))
    }

    private var timeline: some View {
        let dayStart = model.today.startDate()
        let first = firstHour
        let total = CGFloat(lastHour - firstHour) * hourHeight
        let height = hourHeight
        func y(_ date: Date) -> CGFloat {
            CGFloat((date.timeIntervalSince(dayStart) / 60 - Double(first * 60)) / 60) * height
        }
        let nowY = y(model.now)
        let work = model.workdayInterval

        return ZStack(alignment: .topLeading) {
            // Stundenraster; jede Stunde ist eine eigene Zeile, damit das Scrollen zur Uhrzeit klappt.
            VStack(spacing: 0) {
                ForEach(firstHour..<lastHour, id: \.self) { hour in
                    HStack(alignment: .top, spacing: 6) {
                        Text("\(hour):00")
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: labelWidth - 6, alignment: .trailing)
                            .offset(y: -6)
                        Rectangle()
                            .fill(Color.primary.opacity(0.08))
                            .frame(height: 1)
                    }
                    .frame(height: hourHeight, alignment: .top)
                    .id(hour)
                }
            }

            // Arbeitszeit leicht hinterlegt
            Rectangle()
                .fill(Theme.todayTint)
                .frame(height: max(0, y(work.end) - y(work.start)))
                .padding(.leading, labelWidth)
                .offset(y: y(work.start))
                .allowsHitTesting(false)

            ForEach(model.timedEvents) { event in
                let top = max(0, y(event.start))
                EventBlock(event: event, height: max(16, y(event.end) - top), logged: model.isLogged(event))
                    .padding(.leading, labelWidth + 2)
                    .padding(.trailing, 8)
                    .offset(y: top)
            }

            ForEach(model.entriesToday) { entry in
                let top = max(0, y(entry.start))
                RoundedRectangle(cornerRadius: 2)
                    .fill(Theme.accent.opacity(0.75))
                    .frame(width: 4, height: max(3, y(entry.end ?? model.now) - top))
                    .padding(.leading, labelWidth - 3)
                    .offset(y: top)
                    .help("Erfasst")
            }

            ForEach(model.scheduledToday) { task in
                if let interval = task.scheduledInterval {
                    TaskBlock(
                        task: task,
                        top: y(interval.start),
                        height: max(18, y(interval.end) - y(interval.start)),
                        hourHeight: hourHeight
                    )
                    .padding(.leading, labelWidth + 16)
                    .padding(.trailing, 4)
                }
            }

            if nowY >= 0 && nowY <= total {
                HStack(spacing: 0) {
                    Circle()
                        .fill(Theme.accent)
                        .frame(width: 7, height: 7)
                    Rectangle()
                        .fill(Theme.accent)
                        .frame(height: 1.5)
                }
                .padding(.leading, labelWidth - 4)
                .offset(y: nowY - 3.5)
                .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, minHeight: total, maxHeight: total, alignment: .topLeading)
        .contentShape(Rectangle())
        .dropDestination(for: String.self) { items, location in
            let minutes = Double(location.y / height) * 60 + Double(first * 60)
            let start = dayStart.addingTimeInterval(minutes * 60)
            let ids = items.compactMap { UUID(uuidString: $0) }
            for id in ids {
                model.schedule(id, at: start)
            }
            return !ids.isEmpty
        }
        .padding(.top, 8)
        .padding(.bottom, 16)
    }
}

struct EventBlock: View {
    @Environment(AppModel.self) private var model
    let event: CalendarEvent
    let height: CGFloat
    let logged: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Text(event.displayTitle)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                if logged {
                    Image(systemName: "checkmark")
                        .font(.caption2)
                        .foregroundStyle(.green)
                }
            }
            if height > 30 {
                Text(timeRange)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: height, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.primary.opacity(event.showsTitle ? 0.07 : 0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .stroke(Color.primary.opacity(0.15))
        )
        .contextMenu {
            Button(logged ? "Schon als Zeit erfasst" : "Als Zeit erfassen") {
                model.logEvent(event)
            }
            .disabled(logged)
        }
        .help("\(event.displayTitle) · \(timeRange)")
    }

    private var timeRange: String {
        "\(event.start.formatted(date: .omitted, time: .shortened))–\(event.end.formatted(date: .omitted, time: .shortened))"
    }
}

/// Zeitblock einer Aufgabe. Lässt sich mit der Maus verschieben.
struct TaskBlock: View {
    @Environment(AppModel.self) private var model
    let task: TaskItem
    let top: CGFloat
    let height: CGFloat
    let hourHeight: CGFloat

    @State private var dragOffset: CGFloat = 0

    var body: some View {
        let running = model.isRunning(task.id)
        VStack(alignment: .leading, spacing: 1) {
            Text(task.title)
                .font(.caption.weight(.semibold))
                .lineLimit(height > 34 ? 2 : 1)
            if height > 30, let start = task.scheduledStart {
                Text(start.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: height, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(Theme.accent.opacity(running ? 0.22 : 0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 1.2, dash: task.isDone ? [] : [4, 3]))
        )
        .opacity(task.isDone ? 0.55 : 1)
        .offset(y: top + dragOffset)
        .gesture(
            DragGesture(minimumDistance: 4)
                .onChanged { value in
                    dragOffset = value.translation.height
                }
                .onEnded { value in
                    let minutes = Double(value.translation.height / hourHeight) * 60
                    dragOffset = 0
                    model.moveBlock(task.id, byMinutes: minutes)
                }
        )
        .onTapGesture(count: 2) {
            model.openFocus(task.id)
        }
        .contextMenu {
            Button("Im Fokus öffnen") { model.openFocus(task.id) }
            Button("Zeitblock entfernen") { model.schedule(task.id, at: nil) }
        }
        .help("Ziehen verschiebt den Block, Doppelklick öffnet den Fokus")
    }
}
