import AppKit
import SwiftUI
import TagwerkCore

/// Tagesabschluss: Zeiten prüfen, Worklogs an ManageEngine senden, Rückschau schreiben.
/// „Liste kopieren“ gibt die Zeiten des Tages als Tabelle mit, z. B. zum Abtippen in ein anderes System.
struct DayCloseView: View {
    @Environment(AppModel.self) private var model
    @State private var day = LocalDate.today()
    @State private var overrides: [UUID: Int] = [:]
    @State private var reflection = ""
    @State private var message: String?

    var body: some View {
        let lines = model.closeLines(for: day)
        let total = lines.reduce(0) { $0 + (overrides[$1.id] ?? $1.minutes) }
        let worklogs = lines.filter { !$0.targets.isEmpty }.count

        VStack(spacing: 0) {
            header(total: total, lineCount: lines.count)
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 10)

            if lines.isEmpty {
                ContentUnavailableView(
                    "Keine erfasste Zeit",
                    systemImage: "moon",
                    description: Text("An diesem Tag wurde keine Zeit erfasst.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(lines) { line in
                        CloseLineRow(line: line, minutes: binding(for: line))
                    }
                }
                .listStyle(.inset)
            }

            Divider()

            footer(hasLines: !lines.isEmpty, worklogs: worklogs)
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
        }
        .navigationTitle("Tag abschließen")
        .onAppear {
            day = model.today
            reflection = model.reflection(for: day)
        }
        .onChange(of: day) {
            overrides = [:]
            message = nil
            reflection = model.reflection(for: day)
        }
        .onChange(of: reflection) {
            model.setReflection(reflection, for: day)
        }
        // Tickets, die nur als Nummer zugeordnet sind, mit ManageEngine verbinden
        .task(id: day) {
            await model.connectMissingTickets(for: day)
        }
    }

    private func header(total: Int, lineCount: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Tag abschließen")
                    .font(.title2.weight(.medium))
                Text("\(lineCount) Aufgaben · \(TimeMath.format(minutes: total)) h · gerundet auf \(model.bookingRules.roundingStep) Minuten")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if let absence = model.absence(on: day) {
                    Label("\(absence.label) eingetragen", systemImage: absence.kind.symbol)
                        .font(.callout)
                        .foregroundStyle(Theme.secondary)
                }
                let pause = model.breakTotal(on: day)
                let missing = model.missingBreakMinutes(on: day)
                if pause >= 60 || missing > 0 {
                    HStack(spacing: 6) {
                        Label(pause >= 60 ? "\(TimeMath.format(pause)) h Mittagspause, nicht gebucht" : "Keine Mittagspause eingetragen", systemImage: "fork.knife")
                            .foregroundStyle(Theme.secondary)
                        if missing > 0 {
                            Text("· laut Arbeitszeitgesetz fehlen \(missing) Minuten (Pausen zählen ab 15 Minuten am Stück)")
                                .foregroundStyle(Theme.warning)
                            Button("Mittagspause nachtragen …") { model.beginBreakEntry(start: FreeTime.date(on: day, minutes: 12 * 60)) }
                                .buttonStyle(GhostButtonStyle(small: true))
                        }
                    }
                    .font(.callout)
                }
            }
            Spacer()
            Button {
                day = day.adding(days: -1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(IconButtonStyle(size: 28))
            .help("Vortag")
            Text(day.startDate().formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                .font(.system(size: 14, weight: .medium))
                .frame(minWidth: 110)
            Button {
                day = day.adding(days: 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(IconButtonStyle(size: 28))
            .disabled(day >= model.today)
            .help("Nächster Tag")
        }
    }

    private func footer(hasLines: Bool, worklogs: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Rückschau: Was lief gut, was bleibt für morgen?", text: $reflection, axis: .vertical)
                .lineLimit(1...3)
                .textFieldStyle(TagwerkFieldStyle())

            HStack(spacing: 10) {
                if let message {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.dayListText(for: day, minutes: overrides), forType: .string)
                    message = "Liste kopiert: Aufgabe, Kunde, Ticket, Stunden und Beschreibung, passt so in Excel oder Numbers."
                } label: {
                    Label("Liste kopieren", systemImage: "doc.on.clipboard")
                }
                .disabled(!hasLines)
                .help("Die Zeiten des Tages als Tabelle kopieren, z. B. zum Abtippen in ein anderes System")
                if worklogs > 0 {
                    Button {
                        Task {
                            message = await model.bookDay(day, minutes: overrides)
                        }
                    } label: {
                        Label(model.isSendingBookings ? "Wird gesendet …" : "Worklogs senden", systemImage: "paperplane")
                            .frame(minWidth: 120)
                    }
                    .buttonStyle(GhostButtonStyle(prominent: true))
                    .disabled(model.isSendingBookings)
                    .help("Die Zeit der Aufgaben mit Ticket als Worklog an ManageEngine senden")
                }
            }
        }
    }

    private func binding(for line: BookingLine) -> Binding<Int> {
        Binding(
            get: { overrides[line.id] ?? line.minutes },
            set: { overrides[line.id] = $0 }
        )
    }
}

/// Eine Aufgabe im Tagesabschluss mit Zeit, Ticket, Beschreibung und Status des Worklogs.
struct CloseLineRow: View {
    @Environment(AppModel.self) private var model
    let line: BookingLine
    @Binding var minutes: Int

    var body: some View {
        rowContent
            // Knöpfe in der Zeile (Kopieren, Rückgängig …) neutral; Orange bleibt „Buchen“ vorbehalten
            .buttonStyle(GhostButtonStyle(small: true))
    }

    private var rowContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(line.displayTitle)
                        .font(.system(size: 14, weight: .medium))
                    TaskMetaLine(task: line.task, showsBooking: false)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("\(TimeMath.format(minutes: minutes)) h")
                            .font(.title3.weight(.medium))
                            .monospacedDigit()
                        Stepper("Zeit", value: $minutes, in: 0...720, step: model.bookingRules.roundingStep)
                            .labelsHidden()
                            .disabled(!line.targets.isEmpty && line.isDone)
                    }
                    Text("erfasst \(TimeMath.format(line.trackedSeconds))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            FlowLayout(spacing: 8) {
                TicketMenu(task: line.task)
                if line.targets.contains(.manageEngine) {
                    WorklogTypeMenu(task: line.task)
                }
            }

            if line.isCombined {
                CombinedPartsView(line: line)
            } else {
                DescriptionField(task: line.task)
            }

            HStack(spacing: 8) {
                ForEach(line.targets) { target in
                    TargetStatusView(line: line, target: target, minutes: minutes)
                }
                if line.changedAfterBooking {
                    Label("Zeit nach dem Buchen geändert", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(Theme.warning)
                }
            }

            if line.status(for: .manageEngine) == .failed, let error = line.bookings[.manageEngine]?.lastError {
                Label("Worklog abgelehnt: \(error)", systemImage: "xmark.octagon.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.danger)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(line.openIssues, id: \.self) { issue in
                Label(issue.message, systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(Theme.warning)
            }
        }
        .padding(.vertical, 6)
    }
}

/// Zusammengefasste Zeile: jede Unteraufgabe (und die Aufgabe selbst) mit ihrer Zeit und ihrem Bearbeitungstext.
/// Im Ticket landet ein Worklog mit allen Texten untereinander.
struct CombinedPartsView: View {
    let line: BookingLine

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("\(line.parts.count) Teile, ein Worklog im Ticket", systemImage: "square.stack")
                .font(.caption)
                .foregroundStyle(Theme.tertiary)
                .help("Unteraufgaben am selben Ticket gehen zusammen als ein Worklog ins Ticket: Zeit zusammengezählt, die Texte untereinander.\n\n\(line.worklogDescription)")
            ForEach(line.parts, id: \.task.id) { part in
                HStack(spacing: 10) {
                    Text(part.task.isSubtask ? part.task.title : "Aufgabe selbst")
                        .font(.callout)
                        .foregroundStyle(part.task.isSubtask ? Theme.text : Theme.secondary)
                        .lineLimit(1)
                        .frame(width: 170, alignment: .leading)
                    Text(TimeMath.format(part.trackedSeconds))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 40, alignment: .trailing)
                    DescriptionField(task: part.task)
                }
            }
        }
    }
}

/// Status des Worklogs im Ticket.
struct TargetStatusView: View {
    @Environment(AppModel.self) private var model
    let line: BookingLine
    let target: BookingTarget
    let minutes: Int

    var body: some View {
        let status = line.status(for: target)
        HStack(spacing: 6) {
            Circle()
                .fill(color(for: status))
                .frame(width: 7, height: 7)
            Text("\(target.label): \(status?.label ?? "offen")")
                .font(.caption.weight(.medium))
            if status == .failed, let error = line.bookings[target]?.lastError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.danger)
                    .help(error)
                Button("Erneut senden") {
                    Task { _ = await model.retryManageEngine() }
                }
                .controlSize(.small)
            }
            // Der Worklog im Ticket ist freiwillig.
            if status == .skipped {
                Button("Doch senden") { model.unskipManageEngine(line) }
                    .controlSize(.small)
            } else if status != .confirmed {
                Button("Ohne Worklog") { model.skipManageEngine(line, minutes: minutes) }
                    .controlSize(.small)
                    .help("Keinen Worklog im Ticket anlegen")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.white.opacity(0.04)))
    }

    private func color(for status: BookingStatus?) -> Color {
        switch status {
        case .confirmed: return Theme.done
        case .skipped: return Theme.tertiary
        case .failed: return Theme.danger
        default: return Theme.tertiary
        }
    }
}

/// Beschreibung der Bearbeitung direkt bearbeiten.
struct DescriptionField: View {
    @Environment(AppModel.self) private var model
    let task: TaskItem
    @State private var text = ""

    var body: some View {
        TextField("Was wurde gemacht", text: $text)
            .help("Text für den Worklog im Ticket und für die Liste")
            .textFieldStyle(TagwerkFieldStyle())
            .onAppear { text = task.workDescription }
            .onSubmit { model.setDescription(text, for: task.id) }
            .onChange(of: text) { model.setDescription(text, for: task.id) }
    }
}
