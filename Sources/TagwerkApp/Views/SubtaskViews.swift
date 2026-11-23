import SwiftUI
import TagwerkCore

/// Unteraufgaben einer Aufgabe: abhaken, Timer starten, Ticket zuordnen, neue anlegen.
struct SubtaskList: View {
    @Environment(AppModel.self) private var model
    let parent: TaskItem
    var showsAddField = true

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(model.subtasks(of: parent.id)) { subtask in
                SubtaskRow(task: subtask)
            }
            if showsAddField, !parent.isDone {
                AddSubtaskField(parentID: parent.id)
            }
        }
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
                Text(task.title)
                    .font(.callout)
                    .foregroundStyle(task.isDone ? Theme.secondary : Theme.text)
                    .strikethrough(task.isDone, color: Theme.tertiary)
                    .lineLimit(2)
                    .onTapGesture(count: 2) { beginRename() }
                    .help("Doppelklick zum Umbenennen")
            }

            if let number = task.ticketNumber, number != model.parent(of: task)?.linkedTicketNumber {
                Text("#\(number)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.tertiary)
                    .help("Zeit geht auch als Worklog an Ticket #\(number)")
            }

            Spacer(minLength: 4)

            if tracked > 0 || running {
                Text(TimeMath.format(tracked))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(running ? Theme.text : Theme.tertiary)
            }
            if !task.isDone, hovering || running {
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
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
        .background(RoundedRectangle(cornerRadius: 6).fill(running ? Theme.accentSoft : (hovering ? Color.white.opacity(0.04) : .clear)))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Umbenennen") { beginRename() }
            TaskContextMenu(task: task)
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
                .textFieldStyle(.roundedBorder)
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
                        .help("Die Nummer steht dann im SAP-Kommentar; einen Worklog kann Tagwerk ohne Verbindung zum Ticket nicht anlegen.")
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
                Text("Die Zeit geht dann auch als Worklog an das Ticket. SAP bleibt Pflicht.")
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

/// Wohin die Zeit einer Aufgabe geht: SAP-Aufgabe mit Tätigkeit und Ticket mit Titel. Ein Klick ändert es.
struct BookingSummary: View {
    @Environment(AppModel.self) private var model
    let task: TaskItem

    @State private var showsSAP = false
    @State private var showsTicket = false

    var body: some View {
        let effective = model.resolved(task)
        HStack(spacing: 6) {
            Button {
                showsSAP = true
            } label: {
                chip(
                    icon: "building.columns",
                    label: "SAP",
                    text: model.pspLabel(for: task) ?? "Aufgabe fehlt",
                    state: effective.pspElement == nil ? .missing : .ok
                )
            }
            .buttonStyle(.plain)
            .help(effective.pspElement == nil ? "SAP-Aufgabe wählen; ohne sie lässt sich die Zeit nicht buchen" : "SAP-Aufgabe ändern")
            .popover(isPresented: $showsSAP, arrowEdge: .bottom) {
                SAPTaskPicker(selectedCode: task.pspElement, selectedActivity: task.sapActivity) { psp, customCode in
                    if let psp {
                        model.setSAPTask(psp, for: task.id)
                    } else {
                        model.setPSPElement(customCode ?? "", for: task.id)
                    }
                    showsSAP = false
                }
            }

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
                      : "Die Zeit geht auch als Worklog an dieses Ticket")
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
