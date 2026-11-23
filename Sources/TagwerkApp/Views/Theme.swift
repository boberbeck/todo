import AppKit
import SwiftUI
import TagwerkCore

/// Das Erscheinungsbild von Tagwerk: dunkel, warm, ruhig.
///
/// Regeln:
/// - Orange heißt „läuft jetzt“ oder „Hauptaktion“. Sonst nirgends.
/// - Tiefe entsteht durch Ebenen (Grund › Fläche › gehoben), nicht durch Leuchten oder Verläufe.
///   Schatten nur für das, was wirklich schwebt (Fenster).
/// - Zahlen und Zeiten in gerundeter Schrift, Text in normaler.
/// - Überschriften in normaler Schreibweise, keine Großbuchstaben-Etiketten.
///
/// Feste Werte statt freier Zahlen: Abstände `Theme.Space`, Rundungen `Theme.Radius`, Schrift `Theme.font…`.
enum Theme {
    // MARK: Farben

    /// Grund des Fensters (warmes Fast-Schwarz)
    static let background = Color(red: 0.063, green: 0.051, blue: 0.043)
    /// Kopfleiste
    static let bar = Color(red: 0.075, green: 0.062, blue: 0.053)
    /// Karten und Felder
    static let surface = Color(red: 0.110, green: 0.094, blue: 0.082)
    /// Gehobene Flächen: Hover, Knöpfe, ausgewählte Reiter
    static let surfaceRaised = Color(red: 0.150, green: 0.129, blue: 0.113)
    /// Schwebende Flächen: Fenster, Menüs
    static let surfaceFloating = Color(red: 0.125, green: 0.107, blue: 0.094)
    /// Vertieft: Eingabefelder, Leisten in Karten
    static let surfaceSunken = Color(red: 0.078, green: 0.066, blue: 0.057)

    static let border = Color(red: 1, green: 0.92, blue: 0.84).opacity(0.075)
    static let borderStrong = Color(red: 1, green: 0.92, blue: 0.84).opacity(0.14)

    static let text = Color(red: 0.97, green: 0.94, blue: 0.91)
    static let secondary = Color(red: 0.97, green: 0.94, blue: 0.91).opacity(0.62)
    static let tertiary = Color(red: 0.97, green: 0.94, blue: 0.91).opacity(0.40)

    /// Sonnen-Orange
    static let accent = Color(red: 1.0, green: 0.63, blue: 0.29)
    /// Tieferes Orange für Verläufe
    static let accentDeep = Color(red: 0.96, green: 0.45, blue: 0.20)
    /// Hellerer Ton oben im Verlauf
    static let accentBright = Color(red: 1.0, green: 0.74, blue: 0.40)
    static let accentSoft = Color(red: 1.0, green: 0.63, blue: 0.29).opacity(0.15)
    static let todayTint = Color(red: 1.0, green: 0.63, blue: 0.29).opacity(0.07)
    /// Text auf Orange
    static let onAccent = Color(red: 0.16, green: 0.08, blue: 0.03)

    static let done = Color(red: 0.48, green: 0.85, blue: 0.58)
    static let warning = Color(red: 1.0, green: 0.78, blue: 0.36)
    static let danger = Color(red: 1.0, green: 0.44, blue: 0.38)
    /// Tickets (ManageEngine): kühler Gegenton zum warmen SAP
    static let info = Color(red: 0.58, green: 0.68, blue: 1.0)

    static var accentGradient: LinearGradient {
        LinearGradient(colors: [accentBright, accent, accentDeep], startPoint: .top, endPoint: .bottom)
    }

    /// Licht von oben: Rand oben heller als unten.
    static var highlight: LinearGradient {
        LinearGradient(
            colors: [Color.white.opacity(0.11), Color.white.opacity(0.035), Color.white.opacity(0.02)],
            startPoint: .top, endPoint: .bottom
        )
    }

    // MARK: Maße

    enum Space {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
        static let page: CGFloat = 40
    }

    enum Radius {
        /// kleine Markierungen, Balken
        static let xs: CGFloat = 4
        /// Knöpfe, Felder, Reiter
        static let control: CGFloat = 10
        /// Karten
        static let card: CGFloat = 16
        /// Fenster und große Flächen
        static let panel: CGFloat = 22
    }

    // MARK: Schrift
    // Überschriften und Zahlen gerundet (freundlicher, wie das Logo), Fließtext normal.

    static let pageTitle = Font.system(size: 28, weight: .semibold)
    static let title = Font.system(size: 19, weight: .semibold)
    static let cardTitle = Font.system(size: 14, weight: .medium)
    static let bigNumber = Font.system(size: 30, weight: .medium, design: .rounded).monospacedDigit()
    static let statNumber = Font.system(size: 34, weight: .medium, design: .rounded).monospacedDigit()
    static let timerNumber = Font.system(size: 80, weight: .light, design: .rounded).monospacedDigit()
    static let label = Font.system(size: 13, weight: .semibold)
}

/// Grund des Fensters: einfarbig warmes Dunkel.
struct AppBackground: View {
    var body: some View {
        Theme.background
            .ignoresSafeArea()
    }
}

/// Abschnittsüberschrift, z. B. „Heute“ oder „Eingang“, mit optionaler Zahl daneben.
struct SectionLabel: View {
    let text: String
    var detail: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(text)
                .font(Theme.label)
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

/// Wie hoch eine Fläche liegt: bestimmt Verlauf, Rand und Schatten.
enum Elevation {
    /// liegt flach im Grund (Listenzeilen)
    case flat
    /// Karte
    case raised
    /// schwebt über allem (Fenster, Popover)
    case floating
}

/// Fläche: einfarbig mit Haarlinie; Schatten nur, wenn sie schwebt. Mit `tint` bekommt sie links eine Kante
/// in der Farbe und einen Hauch davon in der Fläche (die laufende Aufgabe in Orange).
struct SurfaceStyle: ViewModifier {
    var radius: CGFloat = Theme.Radius.card
    var elevation: Elevation = .raised
    var tint: Color?
    var fill: Color = Theme.surface

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background {
                ZStack(alignment: .leading) {
                    shape.fill(fill)
                    if let tint {
                        shape.fill(tint.opacity(0.08))
                        Rectangle().fill(tint).frame(width: 3)
                    }
                }
                .clipShape(shape)
                .shadow(color: shadowColor, radius: shadowRadius, y: shadowY)
            }
            .overlay {
                shape.strokeBorder(tint.map { $0.opacity(0.35) } ?? Theme.border, lineWidth: 1)
            }
    }

    private var shadowColor: Color {
        switch elevation {
        case .flat, .raised: return .clear
        case .floating: return .black.opacity(0.5)
        }
    }

    private var shadowRadius: CGFloat {
        switch elevation {
        case .flat, .raised: return 0
        case .floating: return 30
        }
    }

    private var shadowY: CGFloat {
        switch elevation {
        case .flat, .raised: return 0
        case .floating: return 12
        }
    }
}

/// Fläche mit Innenabstand (Karten auf den Seiten).
struct CardBackground: ViewModifier {
    var padding: CGFloat = 20
    var radius: CGFloat = Theme.Radius.card
    var fill: Color = Theme.surface

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .modifier(SurfaceStyle(radius: radius, elevation: .raised, fill: fill))
    }
}

extension View {
    func card(padding: CGFloat = 20, radius: CGFloat = Theme.Radius.card, fill: Color = Theme.surface) -> some View {
        modifier(CardBackground(padding: padding, radius: radius, fill: fill))
    }

    /// Fläche mit Tiefe ohne Innenabstand.
    func surface(radius: CGFloat = Theme.Radius.card, elevation: Elevation = .raised, tint: Color? = nil, fill: Color = Theme.surface) -> some View {
        modifier(SurfaceStyle(radius: radius, elevation: elevation, tint: tint, fill: fill))
    }

    /// Einheitlicher Rahmen für Fenster (Sheets): warmer Grund, Orange statt System-Blau, Tagwerk-Knöpfe.
    func tagwerkSheet() -> some View {
        self
            .tint(Theme.accent)
            .buttonStyle(GhostButtonStyle())
            .foregroundStyle(Theme.text)
            .presentationBackground(Theme.surfaceFloating)
    }

    /// Formulare in Tagwerk-Fenstern: ohne grauen System-Hintergrund.
    func tagwerkForm() -> some View {
        self
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .tint(Theme.accent)
    }
}

/// Knopf von Tagwerk. Normal: gehobene Fläche mit Haarlinie. `prominent`: Orange, für die eine Hauptaktion
/// eines Bereichs (z. B. „Sichern“ oder „Buchen“).
struct GhostButtonStyle: ButtonStyle {
    var prominent = false
    var destructive = false
    /// klein, für Knöpfe in Zeilen (Kopieren, Zuordnen, Rückgängig)
    var small = false

    func makeBody(configuration: Configuration) -> some View {
        GhostButtonBody(configuration: configuration, prominent: prominent, destructive: destructive, small: small)
    }
}

private struct GhostButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let prominent: Bool
    let destructive: Bool
    let small: Bool
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: small ? 7 : Theme.Radius.control, style: .continuous)
        let pressed = configuration.isPressed
        configuration.label
            .lineLimit(1)
            .fixedSize()
            .font(.system(size: small ? 12 : 13, weight: prominent ? .semibold : .medium))
            .padding(.horizontal, small ? 9 : 14)
            .padding(.vertical, small ? 4 : 7)
            .foregroundStyle(prominent ? Theme.onAccent : (destructive ? Theme.danger : Theme.text))
            .background {
                if prominent {
                    shape.fill(Theme.accent)
                        .brightness(pressed ? -0.08 : (hovering ? 0.05 : 0))
                } else {
                    shape.fill(Color.white.opacity(pressed ? 0.10 : (hovering ? 0.08 : 0.05)))
                }
            }
            .overlay {
                if !prominent {
                    shape.strokeBorder(Theme.border, lineWidth: 1)
                }
            }
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(pressed ? 0.98 : 1)
            .contentShape(shape)
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

/// Rundes Symbol-Knöpfchen (Play, Info, Einstellungen).
struct IconButtonStyle: ButtonStyle {
    var size: CGFloat = 28
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        IconButtonBody(configuration: configuration, size: size, prominent: prominent)
    }
}

private struct IconButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let size: CGFloat
    let prominent: Bool
    @State private var hovering = false

    var body: some View {
        configuration.label
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(prominent ? Theme.onAccent : (hovering ? Theme.text : Theme.secondary))
            .frame(width: size, height: size)
            .background {
                if prominent {
                    Circle().fill(Theme.accent)
                        .brightness(hovering ? 0.05 : 0)
                } else {
                    Circle().fill(Color.white.opacity(hovering ? 0.09 : 0.05))
                }
            }
            .overlay(Circle().strokeBorder(prominent ? Color.clear : Theme.border, lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .contentShape(Circle())
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

/// Markierung in Kapselform: SAP-Aufgabe, Ticket, Hinweise. Der Ton sagt, was es ist.
struct Chip: View {
    enum Tone {
        case neutral, accent, info, success, warning, danger

        var color: Color {
            switch self {
            case .neutral: return Theme.secondary
            case .accent: return Theme.accent
            case .info: return Theme.info
            case .success: return Theme.done
            case .warning: return Theme.warning
            case .danger: return Theme.danger
            }
        }
    }

    var icon: String?
    var label: String?
    var text: String?
    var tone: Tone = .neutral

    var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .bold))
            }
            if let label {
                Text(label)
                    .fontWeight(.semibold)
            }
            if let text {
                Text(text)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(tone == .neutral ? Theme.secondary : tone.color.opacity(0.85))
            }
        }
        .font(.caption)
        .foregroundStyle(tone == .neutral ? Theme.text.opacity(0.8) : tone.color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(tone == .neutral ? Color.white.opacity(0.06) : tone.color.opacity(0.12)))
        .contentShape(Capsule())
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
                    .fixedSize()
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
    var color: Color = Theme.accent

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.07))
                Capsule()
                    .fill(color)
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
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(task.isDone ? Theme.done : (running ? Theme.accent : Theme.tertiary))
            }
            .buttonStyle(.plain)
            .help(task.isDone ? "Wieder öffnen" : "Erledigt")

            VStack(alignment: .leading, spacing: 5) {
                Text(task.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(task.isDone ? Theme.secondary : Theme.text)
                    .strikethrough(task.isDone, color: Theme.tertiary)
                    .lineLimit(compact ? 3 : 2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    CardMeta(task: task, compact: compact)
                    SubtaskToggle(task: task)
                }
                if !compact, !task.isDone {
                    BookingSummary(task: task)
                }
                if model.expandedTaskIDs.contains(task.id) {
                    SubtaskList(parent: task)
                        .padding(.top, 2)
                }
            }

            Spacer(minLength: 4)

            if !compact || running || hovering {
                VStack(alignment: .trailing, spacing: 6) {
                    if !compact {
                        Text(model.timeLabel(for: task, now: running ? model.now : Date()))
                            .font(.system(.callout, design: .rounded).weight(running ? .semibold : .regular).monospacedDigit())
                            .foregroundStyle(running ? Theme.accent : Theme.secondary)
                    }
                    if !task.isDone, running || hovering {
                        HStack(spacing: 6) {
                            if hovering {
                                OpenDetailButton(task: task)
                                AddSubtaskButton(task: task)
                            }
                            Button {
                                model.toggleTimer(for: task.id)
                            } label: {
                                Image(systemName: running ? "pause.fill" : "play.fill")
                            }
                            .buttonStyle(IconButtonStyle(size: 28, prominent: running))
                            .help(running ? "Timer stoppen" : "Timer starten")
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, compact ? 10 : 13)
        .surface(
            radius: compact ? 12 : 14,
            elevation: task.isDone ? .flat : .raised,
            tint: running ? Theme.accent : nil,
            fill: hovering ? Theme.surfaceRaised : Theme.surface
        )
        .animation(.easeOut(duration: 0.12), value: hovering)
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
        if compact || task.isDone, let number = task.linkedTicketNumber { parts.append("#\(number)") }
        if let goal = model.longGoal(task.longGoalID) { parts.append("◎ \(goal.title)") }
        if task.source == .mail { parts.append("Mail") }
        if !compact, let start = task.scheduledStart, !task.isDone { parts.append(start.formatted(date: .omitted, time: .shortened)) }
        if let estimate = task.estimateMinutes, compact || task.isDone { parts.append("\(TimeMath.format(minutes: estimate)) h") }
        if !compact, let workType = task.workType { parts.append(workType.label) }
        return parts
    }
}

/// Reiht Elemente nebeneinander und bricht in die nächste Zeile um, wenn der Platz nicht reicht
/// (z. B. Arbeitsart, SAP-Aufgabe, Ticket mit langen Namen).
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var width: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            let itemWidth = min(size.width, maxWidth)
            if x > 0, x + itemWidth > maxWidth {
                y += lineHeight + lineSpacing
                x = 0
                lineHeight = 0
            }
            x += itemWidth + spacing
            lineHeight = max(lineHeight, size.height)
            width = max(width, x - spacing)
        }
        return CGSize(width: width, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            let itemWidth = min(size.width, bounds.width)
            if x > bounds.minX, x + itemWidth > bounds.maxX {
                y += lineHeight + lineSpacing
                x = bounds.minX
                lineHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: itemWidth, height: size.height))
            x += itemWidth + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
