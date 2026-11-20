import AppKit
import SwiftUI
import TagwerkCore

/// Ruhiges, dunkles Erscheinungsbild mit warmer Akzentfarbe aus dem Logo.
enum Theme {
    static let background = Color(red: 0.047, green: 0.051, blue: 0.063)
    static let bar = Color(red: 0.035, green: 0.039, blue: 0.047)
    static let surface = Color(red: 0.082, green: 0.086, blue: 0.102)
    static let surfaceRaised = Color(red: 0.118, green: 0.122, blue: 0.141)
    static let border = Color.white.opacity(0.07)
    static let borderStrong = Color.white.opacity(0.13)
    static let text = Color.white.opacity(0.93)
    static let secondary = Color.white.opacity(0.56)
    static let tertiary = Color.white.opacity(0.34)
    static let accent = Color(red: 1.0, green: 0.62, blue: 0.25)
    static let accentSoft = Color(red: 1.0, green: 0.62, blue: 0.25).opacity(0.14)
    static let todayTint = Color(red: 1.0, green: 0.62, blue: 0.25).opacity(0.09)
    static let done = Color(red: 0.42, green: 0.80, blue: 0.55)

    static let pageTitle = Font.system(size: 30, weight: .medium)
    static let bigNumber = Font.system(size: 30, weight: .regular).monospacedDigit()
}

/// Kleine Überschrift in Großbuchstaben, wie „HEUTE“ oder „EINGANG“.
struct SectionLabel: View {
    let text: String
    var detail: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(text.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.6)
                .foregroundStyle(Theme.secondary)
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Theme.tertiary)
                    .monospacedDigit()
            }
        }
    }
}

/// Fläche mit leichtem Rand.
struct CardBackground: ViewModifier {
    var padding: CGFloat = 20
    var radius: CGFloat = 14
    var fill: Color = Theme.surface

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(RoundedRectangle(cornerRadius: radius).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(Theme.border))
    }
}

extension View {
    func card(padding: CGFloat = 20, radius: CGFloat = 14, fill: Color = Theme.surface) -> some View {
        modifier(CardBackground(padding: padding, radius: radius, fill: fill))
    }
}

/// Unauffälliger Knopf mit Rand, z. B. „Heute“ oder „Tag planen“.
struct GhostButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .lineLimit(1)
            .fixedSize()
            .font(.callout.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .foregroundStyle(prominent ? Color.black.opacity(0.85) : Theme.text)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(prominent ? Theme.accent : Color.white.opacity(configuration.isPressed ? 0.10 : 0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(prominent ? Color.clear : Theme.borderStrong)
            )
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

/// Kopf einer Seite: großer Titel, darunter ein Satz, rechts Platz für Knöpfe oder Zahlen.
struct PageHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(Theme.pageTitle)
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .foregroundStyle(Theme.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 16)
            trailing()
        }
    }
}

/// Wochenwahl „‹ 16.–22. Nov. ›“ mit Knopf zur aktuellen Woche.
struct WeekSwitcher: View {
    @Binding var weekStart: LocalDate
    let currentWeek: LocalDate

    var body: some View {
        HStack(spacing: 10) {
            Button {
                weekStart = weekStart.adding(days: -7)
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)
            .help("Vorige Woche")
            Text(Self.label(for: weekStart))
                .monospacedDigit()
                .foregroundStyle(Theme.text)
                .frame(minWidth: 120)
            Button {
                weekStart = weekStart.adding(days: 7)
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.borderless)
            .help("Nächste Woche")
            Button {
                weekStart = currentWeek
            } label: {
                Label("Diese Woche", systemImage: "calendar")
            }
            .buttonStyle(GhostButtonStyle())
            .disabled(weekStart == currentWeek)
        }
        .foregroundStyle(Theme.secondary)
    }

    /// „16.–22. Nov.“ oder über den Monatswechsel „30. Nov.–6. Dez.“
    static func label(for monday: LocalDate) -> String {
        let sunday = monday.adding(days: 6)
        let month = DateFormatter()
        month.locale = Locale(identifier: "de_DE")
        month.dateFormat = "MMM"
        let start = monday.startDate()
        let end = sunday.startDate()
        if monday.month == sunday.month {
            return "\(monday.day).–\(sunday.day). \(month.string(from: end))"
        }
        return "\(monday.day). \(month.string(from: start))–\(sunday.day). \(month.string(from: end))"
    }
}

/// Schmaler Fortschrittsbalken in der Akzentfarbe.
struct ProgressLine: View {
    let value: Double
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                Capsule()
                    .fill(Theme.accent)
                    .frame(width: max(0, min(1, value)) * geometry.size.width)
            }
        }
        .frame(height: height)
    }
}

/// Das Zeichen aus dem App-Symbol: Sonne am Horizont mit Haken.
struct LogoMark: View {
    var body: some View {
        Canvas { context, size in
            let scale = min(size.width, size.height) / 100
            let horizon = 66 * scale
            let center = CGPoint(x: 50 * scale, y: horizon)
            var sun = Path()
            sun.addArc(center: center, radius: 30 * scale, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
            sun.closeSubpath()
            context.fill(sun, with: .linearGradient(
                Gradient(colors: [Color(red: 1, green: 0.82, blue: 0.35), Color(red: 1, green: 0.45, blue: 0.22)]),
                startPoint: CGPoint(x: 0, y: horizon - 30 * scale),
                endPoint: CGPoint(x: 0, y: horizon)
            ))
            var line = Path()
            line.addRoundedRect(in: CGRect(x: 14 * scale, y: horizon + 5 * scale, width: 72 * scale, height: 4 * scale), cornerSize: CGSize(width: 2 * scale, height: 2 * scale))
            context.fill(line, with: .color(Color(red: 1, green: 0.55, blue: 0.25).opacity(0.7)))
            var check = Path()
            check.move(to: CGPoint(x: 34 * scale, y: 52 * scale))
            check.addLine(to: CGPoint(x: 46 * scale, y: 63 * scale))
            check.addLine(to: CGPoint(x: 72 * scale, y: 28 * scale))
            context.stroke(check, with: .color(.white), style: StrokeStyle(lineWidth: 9 * scale, lineCap: .round, lineJoin: .round))
        }
    }
}

// MARK: Aufgaben

/// Eingabe für neue Aufgaben mit „Oben“ und „Unten“. Enter legt unten an.
struct AddTaskField: View {
    @Environment(AppModel.self) private var model
    let day: LocalDate?
    var customerID: UUID?
    var compact = false
    /// Reagiert auf ⌘N.
    var takesNewTaskShortcut = false

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            TextField("", text: $text, prompt: Text(compact ? "Aufgabe hinzufügen …" : "Aufgabe hinzufügen … (z. B. „Angebot prüfen 30m“)").foregroundColor(Theme.tertiary))
                .textFieldStyle(.plain)
                .foregroundStyle(Theme.text)
                .focused($focused)
                .onSubmit { add(atTop: false) }
            HStack(spacing: 2) {
                insertButton(atTop: true)
                insertButton(atTop: false)
            }
            .padding(2)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.05)))
            .opacity(text.trimmingCharacters(in: .whitespaces).isEmpty ? 0.6 : 1)
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(focused ? 0.04 : 0.015)))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(focused ? Theme.accent.opacity(0.6) : Theme.borderStrong, style: StrokeStyle(lineWidth: 1, dash: focused ? [] : [4, 3]))
        )
        .onChange(of: model.newTaskRequest) {
            if takesNewTaskShortcut { focused = true }
        }
    }

    private func insertButton(atTop: Bool) -> some View {
        Button {
            add(atTop: atTop)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: atTop ? "arrow.up.to.line" : "arrow.down.to.line")
                if !compact {
                    Text(atTop ? "Oben" : "Unten")
                }
            }
            .font(.caption.weight(.medium))
            .padding(.horizontal, compact ? 6 : 8)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.secondary)
        .help(atTop ? "Oben einfügen" : "Unten einfügen (↩)")
    }

    private func add(atTop: Bool) {
        guard model.addTask(title: text, customerID: customerID, plannedDate: day, atTop: atTop) != nil else { return }
        text = ""
    }
}

/// Eine Aufgabe als Karte. Ziehen verschiebt sie (in einen anderen Tag oder an eine andere Stelle),
/// Doppelklick öffnet den Fokus.
struct TaskCard: View {
    @Environment(AppModel.self) private var model
    let task: TaskItem
    var compact = false
    /// Ziel, wenn eine andere Aufgabe auf diese Karte gezogen wird.
    var dropDay: LocalDate?
    var allowsDrop = true

    @State private var hovering = false
    @State private var isDropTarget = false

    var body: some View {
        let running = model.isRunning(task.id)
        HStack(alignment: .top, spacing: 10) {
            Button {
                model.toggleDone(task.id)
            } label: {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(task.isDone ? Theme.done : Theme.tertiary)
            }
            .buttonStyle(.plain)
            .help(task.isDone ? "Wieder öffnen" : "Erledigt")

            VStack(alignment: .leading, spacing: 5) {
                Text(task.title)
                    .foregroundStyle(task.isDone ? Theme.secondary : Theme.text)
                    .strikethrough(task.isDone, color: Theme.tertiary)
                    .lineLimit(compact ? 3 : 2)
                    .fixedSize(horizontal: false, vertical: true)
                CardMeta(task: task, compact: compact)
            }

            Spacer(minLength: 4)

            if !compact || running || hovering {
                VStack(alignment: .trailing, spacing: 6) {
                    if !compact {
                        Text(model.timeLabel(for: task, now: running ? model.now : Date()))
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(running ? Theme.text : Theme.secondary)
                    }
                    if !task.isDone, running || hovering {
                        Button {
                            model.toggleTimer(for: task.id)
                        } label: {
                            Image(systemName: running ? "pause.fill" : "play.fill")
                                .font(.system(size: 11))
                                .frame(width: 24, height: 24)
                                .background(Circle().fill(running ? Theme.accent : Color.white.opacity(0.08)))
                                .foregroundStyle(running ? Color.black.opacity(0.85) : Theme.text)
                        }
                        .buttonStyle(.plain)
                        .help(running ? "Timer stoppen" : "Timer starten")
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, compact ? 9 : 11)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(running ? Theme.accentSoft : (hovering ? Theme.surfaceRaised : Theme.surface))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(running ? Theme.accent.opacity(0.7) : Theme.border)
        )
        .overlay(alignment: .top) {
            if isDropTarget {
                Capsule()
                    .fill(Theme.accent)
                    .frame(height: 2)
                    .offset(y: -5)
            }
        }
        .opacity(task.isDone ? 0.75 : 1)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { model.openFocus(task.id) }
        .contextMenu { TaskContextMenu(task: task) }
        .draggable(task.id.uuidString)
        .dropDestination(for: String.self) { items, _ in
            guard allowsDrop else { return false }
            let ids = items.compactMap { UUID(uuidString: $0) }
            for id in ids {
                model.move(id, to: dropDay ?? task.plannedDate, before: task.id)
            }
            return !ids.isEmpty
        } isTargeted: { isDropTarget = $0 && allowsDrop }
    }
}

/// Kunde, Ticket, Schätzung und Zeitblock einer Aufgabe in einer Zeile.
struct CardMeta: View {
    @Environment(AppModel.self) private var model
    let task: TaskItem
    var compact = false

    var body: some View {
        let parts = metaParts
        if model.customer(task.customerID) != nil || !parts.isEmpty {
            HStack(spacing: 6) {
                if let customer = model.customer(task.customerID) {
                    HStack(spacing: 4) {
                        CustomerDot(colorIndex: customer.colorIndex, size: 6)
                        Text(customer.name)
                            .lineLimit(1)
                    }
                }
                ForEach(parts, id: \.self) { part in
                    Text(part)
                        .lineLimit(1)
                }
            }
            .font(.caption)
            .foregroundStyle(Theme.tertiary)
        }
    }

    private var metaParts: [String] {
        var parts: [String] = []
        if task.source == .ticket, let number = task.externalID { parts.append("#\(number)") }
        if task.source == .mail { parts.append("Mail") }
        if !compact, let start = task.scheduledStart, !task.isDone { parts.append(start.formatted(date: .omitted, time: .shortened)) }
        if let estimate = task.estimateMinutes, compact || task.isDone { parts.append("\(TimeMath.format(minutes: estimate)) h") }
        if !compact, let workType = task.workType { parts.append(workType.label) }
        return parts
    }
}
