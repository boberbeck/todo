import SwiftUI
import TagwerkCore

/// Der Sonnenstand: ein kleiner Halbkreis auf der Linie, wie im Logo die Sonne am Horizont.
/// Das Erkennungszeichen von Tagwerk für „jetzt“. Er steht nur im Tagesband und an der Jetzt-Linie der Kalender.
struct SunMark: View {
    var size: CGFloat = 10

    var body: some View {
        SunShape()
            .fill(Theme.accent)
            .frame(width: size, height: size / 2)
    }
}

/// Halbkreis über einer waagrechten Grundlinie.
struct SunShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius = min(rect.width / 2, rect.height)
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.maxY),
            radius: radius,
            startAngle: .degrees(180),
            endAngle: .degrees(360),
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}

/// Das Tagesband auf Start: der Arbeitstag als Leiste von Arbeitsbeginn bis Feierabend.
/// Erfasste Zeit in den Farben der Kunden, geplante Zeitblöcke als Umriss, Termine als ruhige Fläche, Pausen schraffiert,
/// der Sonnenstand zeigt, wo der Tag gerade steht. Hier sitzt die Farbe der Startseite.
struct DayBand: View {
    @Environment(AppModel.self) private var model

    private let barHeight: CGFloat = 20
    /// Platz über der Leiste für den Sonnenstand
    private let sunSpace: CGFloat = 8

    var body: some View {
        let now = model.now
        let window = Self.window(work: model.workdayInterval, entries: model.entriesToday, day: model.today, now: now)
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geometry in
                let scale = BandScale(window: window, width: geometry.size.width)
                ZStack(alignment: .topLeading) {
                    // Spur, die Arbeitszeit eine Stufe heller
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Theme.surfaceSunken)
                        .frame(height: barHeight)
                        .offset(y: sunSpace)
                    let work = model.workdayInterval
                    Rectangle()
                        .fill(Theme.surface)
                        .frame(width: scale.width(from: work.start, to: work.end), height: barHeight)
                        .offset(x: scale.x(work.start), y: sunSpace)

                    ForEach(model.timedEvents) { event in
                        BandSegment(kind: .event, x: scale.x(event.start), width: scale.width(from: event.start, to: event.end), height: barHeight)
                            .offset(y: sunSpace)
                            .help("\(event.displayTitle) · \(Self.clock(event.start))–\(Self.clock(event.end))")
                    }

                    ForEach(model.scheduledToday.filter { !$0.isDone }) { task in
                        if let interval = task.scheduledInterval {
                            BandSegment(kind: .planned, x: scale.x(interval.start), width: scale.width(from: interval.start, to: interval.end), height: barHeight)
                                .offset(y: sunSpace)
                                .help("Geplant: \(task.title) · \(Self.clock(interval.start))")
                        }
                    }

                    ForEach(model.breaks(on: model.today)) { item in
                        let start = max(item.start, window.start)
                        let end = min(item.end ?? now, window.end)
                        if end > start {
                            BandSegment(kind: .pause, x: scale.x(start), width: scale.width(from: start, to: end), height: barHeight)
                                .offset(y: sunSpace)
                                .help("Pause · \(Self.clock(item.start))–\(item.end.map(Self.clock) ?? "läuft")")
                        }
                    }

                    ForEach(model.entriesToday) { entry in
                        let start = max(entry.start, window.start)
                        let end = min(entry.end ?? now, window.end)
                        if end > start {
                            BandSegment(kind: .tracked(color(for: entry)), x: scale.x(start), width: scale.width(from: start, to: end), height: barHeight)
                                .offset(y: sunSpace)
                                .help("\(title(for: entry)) · \(Self.clock(entry.start))–\(entry.end.map(Self.clock) ?? "läuft")")
                        }
                    }

                    if window.contains(now) {
                        let nowX = scale.x(now)
                        Rectangle()
                            .fill(Theme.accent)
                            .frame(width: 1.5, height: barHeight + 2)
                            .offset(x: nowX - 0.75, y: sunSpace - 1)
                            .allowsHitTesting(false)
                        SunMark(size: 12)
                            .offset(x: nowX - 6, y: sunSpace - 6)
                            .allowsHitTesting(false)
                            .help("Jetzt, \(Self.clock(now))")
                    }
                }
            }
            .frame(height: sunSpace + barHeight)

            // Stunden darunter, leise
            GeometryReader { geometry in
                let scale = BandScale(window: window, width: geometry.size.width)
                let hours = Self.hourMarks(in: window, width: geometry.size.width)
                ZStack(alignment: .topLeading) {
                    ForEach(hours, id: \.self) { hour in
                        Text(Self.hourLabel(hour))
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(Theme.tertiary)
                            .fixedSize()
                            .position(x: scale.x(hour), y: 6)
                    }
                }
            }
            .frame(height: 12)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tagesband: \(TimeMath.format(model.trackedToday(now: now))) Stunden erfasst")
    }

    private func color(for entry: TimeEntry) -> Color {
        let customerID = model.task(entry.taskID).map { model.resolved($0) }?.customerID
        guard let customer = model.customer(customerID) else { return Theme.secondary.opacity(0.7) }
        return CustomerPalette.color(customer.colorIndex)
    }

    private func title(for entry: TimeEntry) -> String {
        model.task(entry.taskID)?.title ?? "Ohne Aufgabe"
    }

    // MARK: Hilfen

    /// Ausschnitt des Tages: die Arbeitszeit, erweitert um erfasste Zeit davor oder danach, auf volle Stunden.
    static func window(work: DateInterval, entries: [TimeEntry], day: LocalDate, now: Date) -> DateInterval {
        let dayInterval = day.interval()
        var start = work.start
        var end = work.end
        for entry in entries {
            start = min(start, max(entry.start, dayInterval.start))
            end = max(end, min(entry.end ?? now, dayInterval.end))
        }
        if dayInterval.contains(now) {
            end = max(end, now)
        }
        let calendar = Calendar.current
        let roundedStart = calendar.dateInterval(of: .hour, for: start)?.start ?? start
        let minuteParts = calendar.dateComponents([.minute, .second], from: end)
        let onTheHour = (minuteParts.minute ?? 0) == 0 && (minuteParts.second ?? 0) == 0
        let roundedEnd = onTheHour ? end : (calendar.dateInterval(of: .hour, for: end)?.end ?? end)
        return DateInterval(start: roundedStart, end: max(roundedEnd, roundedStart.addingTimeInterval(3600)))
    }

    /// Volle Stunden für die Beschriftung; bei wenig Platz jede zweite.
    static func hourMarks(in window: DateInterval, width: CGFloat) -> [Date] {
        let hours = Int((window.duration / 3600).rounded())
        guard hours > 0 else { return [] }
        let step = width / CGFloat(hours) < 36 ? 2 : 1
        return stride(from: 0, through: hours, by: step).map { window.start.addingTimeInterval(TimeInterval($0) * 3600) }
    }

    static func hourLabel(_ date: Date) -> String {
        String(Calendar.current.component(.hour, from: date))
    }

    static func clock(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}

/// Umrechnung von Uhrzeit in eine Position auf dem Tagesband.
private struct BandScale {
    let window: DateInterval
    let width: CGFloat

    func x(_ date: Date) -> CGFloat {
        guard window.duration > 0 else { return 0 }
        let fraction = date.timeIntervalSince(window.start) / window.duration
        return CGFloat(min(1, max(0, fraction))) * width
    }

    func width(from start: Date, to end: Date) -> CGFloat {
        max(0, x(end) - x(start))
    }
}

/// Ein Abschnitt auf dem Tagesband.
private struct BandSegment: View {
    enum Kind {
        case event
        case planned
        case tracked(Color)
        case pause
    }

    let kind: Kind
    let x: CGFloat
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 3, style: .continuous)
        Group {
            switch kind {
            case .event:
                shape.fill(Color.white.opacity(0.07))
            case .planned:
                shape.strokeBorder(Theme.borderStrong, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
            case .tracked(let color):
                shape.fill(color)
            case .pause:
                ZStack {
                    shape.fill(Theme.surfaceSunken)
                    Hatch(color: Theme.secondary.opacity(0.4), spacing: 5)
                }
                .clipShape(shape)
            }
        }
        .frame(width: max(2, width), height: height)
        .offset(x: x)
    }
}
