import SwiftUI
import TagwerkCore

/// Unteraufgaben einer Aufgabe: abhaken, Timer starten, Ticket zuordnen, neue anlegen.
/// Offene stehen oben, je eine Zeile; erledigte sind eingeklappt. Ziehen legt eine Unteraufgabe auf einen eigenen Tag.
struct SubtaskList: View {
    @Environment(AppModel.self) private var model
    let parent: TaskItem
    var showsAddField = true

    @State private var showsDone = false

    var body: some View {
        let all = model.subtasks(of: parent.id)
        let open = all.filter { !$0.isDone }
        let done = all.filter(\.isDone)
        VStack(alignment: .leading, spacing: 1) {
            ForEach(open) { subtask in
                SubtaskRow(task: subtask)
            }
            if !done.isEmpty {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { showsDone.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: showsDone ? "chevron.down" : "chevron.right")
                            .font(.system(size: 8, weight: .semibold))
                            .frame(width: 13)
                        Text(done.count == 1 ? "1 erledigt" : "\(done.count) erledigt")
                    }
                    .font(.caption)
                    .foregroundStyle(Theme.tertiary)
                    .padding(.vertical, 3)
                    .padding(.horizontal, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(showsDone ? "Erledigte Unteraufgaben ausblenden" : "Erledigte Unteraufgaben zeigen")
                if showsDone {
                    ForEach(done) { subtask in
                        SubtaskRow(task: subtask)
                    }
                }
            }
            if showsAddField, !parent.isDone {
                AddSubtaskField(parentID: parent.id)
            }
        }
        // Feine Linie links: gehört zur Aufgabe darüber
        .padding(.leading, 6)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Theme.border)
                .frame(width: 1)
                .padding(.vertical, 4)
        }
    }
}

/// Kurzer Tag für kleine Markierungen: Heute, Morgen, sonst „Mo 30.11.“.
enum DayText {
    static func short(_ day: LocalDate, today: LocalDate) -> String {
        if day == today { return "Heute" }
        if day == today.adding(days: 1) { return "Morgen" }
        if day == today.adding(days: -1) { return "Gestern" }
        let names = ["So", "Mo", "Di", "Mi", "Do", "Fr", "Sa"]
        let weekday = Calendar.current.component(.weekday, from: day.startDate())
        return "\(names[weekday - 1]) \(day.day).\(day.month)."
    }

    /// Für Menüs: „Heute“, „Morgen“, „Übermorgen“, sonst „Montag, 30.11.“.
    static func long(_ day: LocalDate, today: LocalDate) -> String {
        let label = QuickCommand.dayLabel(day, today: today, calendar: .current)
        return label.prefix(1).uppercased() + label.dropFirst()
    }

    /// Die nächsten Arbeitstage ab heute, für „Einplanen am“.
    static func upcomingWorkdays(from today: LocalDate, count: Int = 10) -> [LocalDate] {
        var days: [LocalDate] = []
        var offset = 0
        while days.count < count, offset < 30 {
            let day = today.adding(days: offset)
            if !Calendar.current.isDateInWeekend(day.startDate()) { days.append(day) }
            offset += 1
        }
        return days
    }
}

/// Fortschritt der Unteraufgaben („2/5“) mit Pfeil zum Auf- und Zuklappen.
struct SubtaskToggle: View {
    @Environment(AppModel.self) private var model
    let task: TaskItem

    var body: some View {
        let subtasks = model.subtasks(of: task.id)
        let expanded = model.expandedTaskIDs.contains(task.id)
        if !subtasks.isEmpty {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { model.toggleSubtasks(task.id) }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "checklist")
                    Text("\(subtasks.filter(\.isDone).count)/\(subtasks.count)")
                        .monospacedDigit()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .medium))
                }
                .font(.caption)
                .foregroundStyle(Theme.tertiary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(expanded ? "Unteraufgaben zuklappen" : "Unteraufgaben zeigen")
        }
    }
}

struct SubtaskRow: View {
    @Environment(AppModel.self) private var model
    let task: TaskItem

    @State private var hovering = false
    @State private var showsTicketPicker = false
    @State private var isEditing = false
    @State private var draft = ""
    @FocusState private var editorFocused: Bool

    var body: some View {
        let running = model.isRunning(task.id)
        let tracked = model.tracked(taskID: task.id, now: running ? model.now : Date())
        HStack(spacing: 8) {
            Button {
                model.toggleDone(task.id)
            } label: {
                Image(systemName: task.isDone ? "checkmark.square.fill" : "square")
                    .font(.system(size: 13))
                    .foregroundStyle(task.isDone ? Theme.done : Theme.tertiary)
            }
            .buttonStyle(.plain)
            .help(task.isDone ? "Wieder öffnen" : "Erledigt")

            if isEditing {
                TextField("Unteraufgabe", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.callout)
                    .focused($editorFocused)
                    .onSubmit { commitRename() }
                    .onExitCommand { isEditing = false }
                    .onChange(of: editorFocused) { if !editorFocused, isEditing { commitRename() } }
            } else {
                // Passt alles in eine Zeile, steht es in einer; in schmalen Spalten darf der Name zwei Zeilen haben
                // (in der Mitte gekürzt, damit Anfang und Ende lesbar bleiben), Tag und Ticket stehen dann darunter.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) {
                        titleText
                            .lineLimit(1)
                            .fixedSize()
                        badges
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        titleText
                            .lineLimit(2)
                            .truncationMode(.middle)
                        if hasBadges {
                            HStack(spacing: 6) { badges }
                        }
                    }
                }
                .layoutPriority(1)
            }

            Spacer(minLength: 4)

            if tracked > 0 || running {
                Text(TimeMath.format(tracked))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(running ? Theme.text : Theme.tertiary)
                    .lineLimit(1)
                    .fixedSize()
            }
            // Läuft der Timer, bleibt „Pause“ fest stehen; alles andere erscheint erst beim Darüberfahren
            if running {
                timerButton(running: true)
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
        .background(RoundedRectangle(cornerRadius: 6).fill(running ? Theme.accentSoft : (hovering ? Color.white.opacity(0.04) : .clear)))
        // Knöpfe beim Darüberfahren schweben über dem Ende der Zeile, statt den Namen zu verdrängen
        .overlay(alignment: .trailing) {
            if !task.isDone, hovering {
                HStack(spacing: 2) {
                    ticketButton
                    if !running {
                        timerButton(running: false)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Capsule().fill(Theme.surfaceFloating))
                .overlay(Capsule().strokeBorder(Theme.border))
                .padding(.trailing, running ? 30 : 2)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Umbenennen") { beginRename() }
            TaskContextMenu(task: task)
        }
        // Auf einen Tag, auf „Heute“ oder in den Kalender ziehen: eigener Tag bzw. Zeitblock
        .draggable(task.id.uuidString)
    }

    private var ticketButton: some View {
        Button {
            showsTicketPicker = true
        } label: {
            Image(systemName: "ticket")
                .font(.system(size: 11))
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
        .foregroundStyle(task.ticketNumber == nil ? Theme.tertiary : Theme.secondary)
        .help("Ticket zuordnen")
        .popover(isPresented: $showsTicketPicker, arrowEdge: .bottom) {
            TicketPicker(taskID: task.id) { showsTicketPicker = false }
        }
    }

    private func timerButton(running: Bool) -> some View {
        Button {
            model.toggleTimer(for: task.id)
        } label: {
            Image(systemName: running ? "pause.fill" : "play.fill")
                .font(.system(size: 9))
                .frame(width: 20, height: 20)
                .background(Circle().fill(running ? Theme.accent : Color.white.opacity(0.08)))
                .foregroundStyle(running ? Color.black.opacity(0.85) : Theme.text)
        }
        .buttonStyle(.plain)
        .help(running ? "Timer stoppen" : "Timer für diese Unteraufgabe starten")
    }

    private var titleText: some View {
        Text(task.title)
            .font(.callout)
            .foregroundStyle(task.isDone ? Theme.secondary : Theme.text)
            .strikethrough(task.isDone, color: Theme.tertiary)
            .onTapGesture(count: 2) { beginRename() }
            .help("\(task.title)\n\nDoppelklick zum Umbenennen, ziehen zum Einplanen an einem eigenen Tag")
    }

    private var ownDay: LocalDate? {
        guard !task.isDone, model.isPlannedOnItsOwn(task) else { return nil }
        return task.plannedDate
    }

    private var ownTicket: String? {
        guard let number = task.ticketNumber, number != model.parent(of: task)?.linkedTicketNumber else { return nil }
        return number
    }

    private var hasBadges: Bool { ownDay != nil || ownTicket != nil }

    /// Eigener Tag und eigenes Ticket
    @ViewBuilder
    private var badges: some View {
        if let day = ownDay {
            let isToday = day == model.today
            Text(DayText.short(day, today: model.today))
                .font(.caption2.weight(.medium))
                .foregroundStyle(isToday ? Theme.accent : Theme.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(Capsule().fill(isToday ? Theme.accentSoft : Color.white.opacity(0.06)))
                .fixedSize()
                .help("Eigens eingeplant: steht an diesem Tag als eigene Aufgabe. Rechtsklick › „Wieder mit der Aufgabe planen“")
        }
        if let number = ownTicket {
            Text("#\(number)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(Theme.tertiary)
                .fixedSize()
                .help("Zeit geht auch als Worklog an Ticket #\(number)")
        }
    }

    private func beginRename() {
        draft = task.title
        isEditing = true
        DispatchQueue.main.async { editorFocused = true }
    }

    private func commitRename() {
        model.setTitle(draft, for: task.id)
        isEditing = false
    }
}

/// Kleiner Knopf, der das Aufgabenfenster mit allen Angaben öffnet.
struct OpenDetailButton: View {
    @Environment(AppModel.self) private var model
    let task: TaskItem

    var body: some View {
        Button {
            model.openDetail(task.id)
        } label: {
            Image(systemName: "info")
                .font(.system(size: 11, weight: .medium))
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.white.opacity(0.08)))
                .foregroundStyle(Theme.text)
        }
        .buttonStyle(.plain)
        .help("Aufgabe öffnen: alle Angaben, Unteraufgaben und Zeiten")
    }
}

/// Eingabe für eine neue Unteraufgabe. Eine Zeitangabe am Ende wird zur Schätzung.
struct AddSubtaskField: View {
    @Environment(AppModel.self) private var model
    let parentID: UUID

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.tertiary)
                .frame(width: 13)
            TextField("Unteraufgabe hinzufügen", text: $text)
                .labelsHidden()
                .textFieldStyle(.plain)
                .multilineTextAlignment(.leading)
                .font(.callout)
                .focused($focused)
                .onSubmit {
                    if model.addSubtask(title: text, to: parentID) != nil {
                        text = ""
                        focused = true
                    }
                }
                .onExitCommand {
                    text = ""
                    focused = false
                }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
        .onAppear { takeFocusIfRequested() }
        .onChange(of: model.subtaskEntryTaskID) { takeFocusIfRequested() }
    }

    private func takeFocusIfRequested() {
        guard model.subtaskEntryTaskID == parentID else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            focused = true
            model.subtaskEntryTaskID = nil
        }
    }
}

/// Ticket zuordnen: Knopf mit Suche. Bei Tickets selbst nicht nötig, sie sind ihr eigenes Ticket.
struct TicketMenu: View {
    @Environment(AppModel.self) private var model
    let task: TaskItem

    @State private var showsPicker = false

    var body: some View {
        if task.source != .ticket {
            Button {
                showsPicker = true
            } label: {
                Text(label)
                    .lineLimit(1)
            }
            .buttonStyle(GhostButtonStyle(small: true))
            .controlSize(.small)
            .fixedSize()
            .popover(isPresented: $showsPicker, arrowEdge: .bottom) {
                TicketPicker(taskID: task.id) { showsPicker = false }
            }
            .help("Ticket in ManageEngine, an das die Zeit zusätzlich als Worklog geht (freiwillig)")
        }
    }

    private var label: String {
        if let own = task.ticketNumber { return "Ticket #\(own)" }
        if let inherited = model.ticketNumber(for: task) { return "Ticket #\(inherited) (geerbt)" }
        return "Ticket zuordnen"
    }
}

/// Ticket suchen: erst unter den Tickets in Tagwerk, beim Tippen zugleich in ManageEngine (alle Techniker),
/// nach Nummer oder Betreff. Das Ticket erscheint mit Betreff und Status, bevor man es zuordnet.
struct TicketPicker: View {
    @Environment(AppModel.self) private var model
    let taskID: UUID
    let onDone: () -> Void

    @State private var query = ""
    @State private var remote: [ManageEngineTicket] = []
    @State private var remoteQuery = ""
    @State private var attempts: [String] = []
    @State private var isSearchingRemote = false
    @FocusState private var focused: Bool

    var body: some View {
        let found = results
        let trimmed = cleanedQuery
        let typedNumber = cleanedNumber
        let current = model.task(taskID)
        let searchedRemote = remoteQuery == trimmed && !trimmed.isEmpty
        VStack(alignment: .leading, spacing: 8) {
            Text(current.map { "Ticket für „\($0.title)“" } ?? "Ticket zuordnen")
                .font(.system(size: 14, weight: .medium))
                .lineLimit(1)
            TextField("Ticketnummer oder Betreff, auch von Kollegen", text: $query)
                .textFieldStyle(TagwerkFieldStyle())
                .focused($focused)
                .onSubmit {
                    if let first = found.first {
                        choose(first)
                    } else if let first = remote.first, searchedRemote {
                        model.linkTicket(first, to: taskID)
                        onDone()
                    }
                }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if !found.isEmpty {
                        sectionTitle("IN TAGWERK")
                    }
                    ForEach(found) { ticket in
                        Button {
                            choose(ticket)
                        } label: {
                            row(number: ticket.linkedTicketNumber ?? "?",
                                title: ticket.title,
                                detail: [model.customer(ticket.customerID)?.name, ticket.isDone ? "erledigt" : nil].compactMap { $0 }.joined(separator: " · "),
                                selected: current?.ticketNumber == ticket.linkedTicketNumber,
                                closed: false)
                        }
                        .buttonStyle(.plain)
                    }

                    if isSearchingRemote {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Sucht in ManageEngine …")
                                .foregroundStyle(.secondary)
                        }
                        .padding(8)
                    }
                    if searchedRemote, !remote.isEmpty {
                        sectionTitle("AUS MANAGEENGINE")
                        ForEach(remote, id: \.key) { ticket in
                            Button {
                                model.linkTicket(ticket, to: taskID)
                                onDone()
                            } label: {
                                row(number: ticket.number,
                                    title: ticket.subject,
                                    detail: [ticket.accountName, ticket.statusName.isEmpty ? nil : ticket.statusName].compactMap { $0 }.joined(separator: " · "),
                                    selected: current?.ticketNumber == ticket.number,
                                    closed: !ticket.isOpen)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if searchedRemote, remote.isEmpty, !isSearchingRemote, found.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(typedNumber != nil ? "Ticket #\(trimmed) in ManageEngine nicht gefunden." : "In ManageEngine nichts mit „\(trimmed)“ gefunden.")
                                .foregroundStyle(Theme.warning)
                            if !attempts.isEmpty {
                                Text("Versucht: " + attempts.joined(separator: " · "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(8)
                    }
                    if let typedNumber, !found.contains(where: { $0.linkedTicketNumber == typedNumber }),
                       !remote.contains(where: { $0.number == typedNumber }),
                       !model.canUseManageEngine || (searchedRemote && !isSearchingRemote) {
                        Button {
                            model.linkTicketNumberOnly(typedNumber, to: taskID)
                            onDone()
                        } label: {
                            Label("Trotzdem #\(typedNumber) zuordnen (ohne Worklog)", systemImage: "number")
                        }
                        .padding(8)
                        .help("Die Nummer steht dann an der Aufgabe und in der Tagesliste; einen Worklog kann Tagwerk ohne Verbindung zum Ticket nicht anlegen.")
                    }
                    if found.isEmpty, remote.isEmpty, trimmed.count < 3, !isSearchingRemote {
                        Text(model.canUseManageEngine
                             ? "Ticketnummer oder Wörter aus dem Betreff eintippen; Tagwerk sucht dann auch in ManageEngine über alle Techniker."
                             : "Ticketnummer eintippen. Für die Suche in ManageEngine erst Einstellungen › ManageEngine einrichten.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(8)
                    }
                }
            }
            .frame(height: 260)
            Divider()
            HStack {
                Text("Die Zeit geht dann als Worklog an das Ticket.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if current?.ticketNumber != nil || current?.ticketKey != nil {
                    Button("Kein Ticket") {
                        model.unlinkTicket(from: taskID)
                        onDone()
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .padding(12)
        .frame(width: 460)
        .onAppear { focused = true }
        .task(id: trimmed) {
            await searchRemote(trimmed)
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.top, 6)
    }

    private func row(number: String, title: String, detail: String, selected: Bool, closed: Bool) -> some View {
        HStack(spacing: 8) {
            Text("#\(number)")
                .monospacedDigit()
                .foregroundStyle(Theme.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .lineLimit(1)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if closed {
                Text("geschlossen")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if selected {
                Image(systemName: "checkmark")
                    .foregroundStyle(Theme.accent)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private var cleanedQuery: String {
        query.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "#"))
    }

    private var cleanedNumber: String? {
        let value = cleanedQuery
        return !value.isEmpty && value.allSatisfy(\.isNumber) ? value : nil
    }

    private var results: [TaskItem] {
        let words = query.lowercased()
            .folding(options: .diacriticInsensitive, locale: nil)
            .replacingOccurrences(of: "#", with: "")
            .split(separator: " ")
            .map(String.init)
        return model.ticketTasks
            .filter { $0.id != taskID }
            .filter { ticket in
                guard !words.isEmpty else { return !ticket.isDone }
                let haystack = ["\(ticket.linkedTicketNumber ?? "")", ticket.title, model.customer(ticket.customerID)?.name ?? ""]
                    .joined(separator: " ")
                    .lowercased()
                    .folding(options: .diacriticInsensitive, locale: nil)
                return words.allSatisfy { haystack.contains($0) }
            }
            .prefix(50)
            .map { $0 }
    }

    private func choose(_ ticket: TaskItem) {
        model.linkTicket(ticket, to: taskID)
        onDone()
    }

    /// Kurz nach dem Tippen in ManageEngine suchen; neues Tippen bricht die alte Suche ab.
    private func searchRemote(_ text: String) async {
        guard model.canUseManageEngine, text.count >= 3 else {
            remote = []
            attempts = []
            remoteQuery = ""
            isSearchingRemote = false
            return
        }
        try? await Task.sleep(for: .milliseconds(450))
        guard !Task.isCancelled else { return }
        isSearchingRemote = true
        let search = await model.searchManageEngineTickets(text)
        guard !Task.isCancelled else { return }
        remote = search.tickets
        attempts = search.attempts
        remoteQuery = text
        isSearchingRemote = false
    }
}

/// „Vergessen zu starten?“: Timer rückwirkend starten oder Zeit nachtragen.
struct BackdatedStartMenu: View {
    @Environment(AppModel.self) private var model
    let task: TaskItem
    /// Als eigener Menü-Knopf (Fokus) statt als Untermenü im Rechtsklick.
    var asButton = false

    var body: some View {
        if asButton {
            Menu {
                items
            } label: {
                Label(model.isRunning(task.id) ? "Früher angefangen?" : "Vergessen zu starten?", systemImage: "clock.arrow.circlepath")
                    .font(.callout)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .foregroundStyle(Theme.tertiary)
            .tint(Theme.secondary)
            .help("Timer rückwirkend starten oder Zeit nachtragen")
        } else {
            Menu(model.isRunning(task.id) ? "Läuft eigentlich schon seit" : "Timer starten, läuft schon seit") {
                items
            }
        }
    }

    @ViewBuilder
    private var items: some View {
        if let last = model.lastEntryEndToday, Date().timeIntervalSince(last) >= 60, Date().timeIntervalSince(last) <= 10 * 3600 {
            Button("dem letzten Eintrag (\(last.formatted(date: .omitted, time: .shortened)))") {
                model.startTimer(task.id, since: last)
            }
        }
        ForEach([5, 10, 15, 30, 45, 60, 90], id: \.self) { minutes in
            Button(minutes < 60 ? "\(minutes) Minuten" : "\(TimeMath.format(minutes: minutes)) Stunden") {
                model.startTimer(task.id, since: Date().addingTimeInterval(TimeInterval(-minutes * 60)))
            }
        }
        if asButton {
            Divider()
            Button("Zeit nachtragen …") { model.beginTimeEntry(for: task.id) }
        }
    }
}

/// „Falsche Aufgabe?“ im Fokus: andere Aufgabe wählen. Läuft der Timer, wandert die bisherige Zeit mit,
/// Timer und Pomodoro-Runde laufen weiter.
struct SwitchTaskMenu: View {
    @Environment(AppModel.self) private var model
    let task: TaskItem

    var body: some View {
        let running = model.isRunning(task.id)
        Menu {
            SwitchTaskItems(current: task.id, offersSearch: true)
        } label: {
            Label(running ? "Falsche Aufgabe?" : "Andere Aufgabe", systemImage: "arrow.left.arrow.right")
                .font(.callout)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(Theme.tertiary)
        .tint(Theme.secondary)
        .help(running ? "Aufgabe wechseln: die Zeit seit dem Start zählt dann für die neue Aufgabe, der Timer läuft weiter" : "Andere Aufgabe in den Fokus holen")
    }
}

/// Aufgaben zum Wechseln: heute, Standardaufgaben, Eingang. Für Fokus, Titelleiste und Menüleiste.
struct SwitchTaskItems: View {
    @Environment(AppModel.self) private var model
    let current: UUID?
    /// „Andere suchen …“ öffnet die Befehlszeile (nur im Hauptfenster sinnvoll).
    var offersSearch = false

    var body: some View {
        let today = model.todayTasks.filter { !$0.isDone && $0.id != current }
        let standing = model.standingTasks.filter { $0.id != current }
        let inbox = Array(model.inboxTasks.filter { $0.id != current }.prefix(10))
        if today.isEmpty, standing.isEmpty, inbox.isEmpty {
            Text("Keine anderen offenen Aufgaben")
        }
        if !today.isEmpty {
            Section("Heute") {
                ForEach(today) { task in
                    Button(task.title) { model.switchTask(to: task.id) }
                }
            }
        }
        if !standing.isEmpty {
            Section("Standardaufgaben") {
                ForEach(standing) { task in
                    Button(task.title) { model.switchTask(to: task.id) }
                }
            }
        }
        if !inbox.isEmpty {
            Section("Eingang") {
                ForEach(inbox) { task in
                    Button(task.title) { model.switchTask(to: task.id) }
                }
            }
        }
        if offersSearch {
            Divider()
            Button("Andere suchen … (⌘K)") { model.openCommandBar(with: "wechseln zu ") }
        }
    }
}

/// Unteraufgaben unter einer Zeile, wenn sie aufgeklappt sind (Eingang, Kunden).
struct ExpandedSubtasks: View {
    @Environment(AppModel.self) private var model
    let task: TaskItem

    var body: some View {
        if model.expandedTaskIDs.contains(task.id) {
            SubtaskList(parent: task)
                .padding(.leading, 24)
                .padding(.top, 2)
        }
    }
}

/// Kleiner Knopf „Unteraufgabe“ zum Aufklappen und Anlegen, erscheint beim Darüberfahren.
struct AddSubtaskButton: View {
    @Environment(AppModel.self) private var model
    let task: TaskItem

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { model.beginSubtaskEntry(for: task.id) }
        } label: {
            Image(systemName: "checklist")
                .font(.system(size: 11))
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.white.opacity(0.08)))
                .foregroundStyle(Theme.text)
        }
        .buttonStyle(.plain)
        .help("Unteraufgabe hinzufügen")
    }
}

/// Ticket einer Aufgabe mit Titel; dorthin geht die Zeit als Worklog. Ein Klick ändert es.
struct BookingSummary: View {
    @Environment(AppModel.self) private var model
    let task: TaskItem

    @State private var showsTicket = false

    var body: some View {
        let effective = model.resolved(task)
        HStack(spacing: 6) {
            if let number = effective.linkedTicketNumber {
                Button {
                    if task.source != .ticket { showsTicket = true }
                } label: {
                    chip(
                        icon: "ticket",
                        label: "#\(number)",
                        text: ticketText(effective),
                        state: effective.linkedTicketKey == nil ? .missing : .ok
                    )
                }
                .buttonStyle(.plain)
                .help(effective.linkedTicketKey == nil
                      ? "Ticket ohne Verbindung zu ManageEngine: kein Worklog möglich"
                      : "Die Zeit geht als Worklog an dieses Ticket")
                .popover(isPresented: $showsTicket, arrowEdge: .bottom) {
                    TicketPicker(taskID: task.id) { showsTicket = false }
                }
            }
        }
    }

    private func ticketText(_ effective: TaskItem) -> String {
        let title = model.ticketTitle(for: task) ?? ""
        if effective.linkedTicketKey == nil { return title.isEmpty ? "ohne Worklog" : "\(title) · ohne Worklog" }
        return title.isEmpty ? "ManageEngine" : title
    }

    private enum ChipState { case ok, missing }

    private func chip(icon: String, label: String, text: String, state: ChipState) -> some View {
        Chip(
            icon: icon,
            label: label,
            text: text,
            tone: state == .missing ? .warning : (icon == "ticket" ? .info : .neutral)
        )
    }
}
