import AppKit
import SwiftUI
import TagwerkCore

/// Tagesabschluss: Zeiten prüfen, Worklogs an ManageEngine senden, SAP-Zeilen übertragen und abhaken.
struct DayCloseView: View {
    @Environment(AppModel.self) private var model
    @State private var day = LocalDate.today()
    @State private var overrides: [UUID: Int] = [:]
    @State private var reflection = ""
    @State private var message: String?
    @State private var exportedFile: URL?

    var body: some View {
        let lines = model.closeLines(for: day)
        let total = lines.reduce(0) { $0 + (overrides[$1.id] ?? $1.minutes) }
        let openSAP = lines.filter { !($0.status(for: .sap)?.isDone ?? false) }.count

        VStack(spacing: 0) {
            header(total: total, lineCount: lines.count)
                .padding(.horizontal, 24)
                .padding(.top, 18)
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

            footer(hasLines: !lines.isEmpty, openSAP: openSAP)
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
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
                    .font(.title2.weight(.semibold))
                Text("\(lineCount) Aufgaben · \(TimeMath.format(minutes: total)) h zu buchen · gerundet auf \(model.bookingRules.roundingStep) Minuten")
                    .font(.callout)
                    .foregroundStyle(.secondary)
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
                .font(.headline)
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

    private func footer(hasLines: Bool, openSAP: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Rückschau: Was lief gut, was bleibt für morgen?", text: $reflection, axis: .vertical)
                .lineLimit(1...3)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 10) {
                if let message {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                Button {
                    let list = model.sapTransferList(for: day, minutes: overrides)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(list.text, forType: .string)
                    exportedFile = list.file
                    message = "SAP-Liste kopiert (zum Einfügen in Excel)."
                } label: {
                    Label("SAP-Liste kopieren", systemImage: "doc.on.clipboard")
                }
                .disabled(!hasLines)
                if let exportedFile {
                    Button("Datei zeigen") {
                        NSWorkspace.shared.activateFileViewerSelecting([exportedFile])
                    }
                }
                Button {
                    Task {
                        message = await model.bookDay(day, minutes: overrides)
                    }
                } label: {
                    Label(model.isSendingBookings ? "Wird gebucht …" : "Buchen", systemImage: "paperplane")
                        .frame(minWidth: 90)
                }
                .buttonStyle(GhostButtonStyle(prominent: true))
                .disabled(!hasLines || model.isSendingBookings)
                .help("Worklogs an ManageEngine senden und SAP-Zeilen vorbereiten")
            }
            if openSAP > 0 && hasLines {
                Text("SAP hat keine Schnittstelle: Trag die Zeilen in ByDesign ein und hak sie hier mit „In SAP eingetragen“ ab. Die Kopier-Knöpfe helfen beim Übertragen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

/// Eine Aufgabe im Tagesabschluss mit Zeit, Angaben für SAP und Status je Ziel.
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
                        .font(.headline)
                    TaskMetaLine(task: line.task, showsBooking: false)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("\(TimeMath.format(minutes: minutes)) h")
                            .font(.title3.weight(.semibold))
                            .monospacedDigit()
                        Stepper("Zeit", value: $minutes, in: 0...720, step: model.bookingRules.roundingStep)
                            .labelsHidden()
                            .disabled(line.isDone)
                    }
                    Text("erfasst \(TimeMath.format(line.trackedSeconds))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            FlowLayout(spacing: 8) {
                PSPMenu(task: line.task)
                WorkTypeMenu(task: line.task)
                TicketMenu(task: line.task)
                if line.targets.contains(.manageEngine) {
                    WorklogTypeMenu(task: line.task)
                }
                if let activity = line.task.sapActivity, !activity.isEmpty {
                    Text("Tätigkeit \(activity)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    let service = model.serviceProduct(for: line.task.workType)
                    if !service.isEmpty {
                        Text("Leistung \(service)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            DescriptionField(task: line.task)

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

/// Status eines Ziels. Bei SAP mit Kopier-Knöpfen und Abhaken.
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
            if target == .sap {
                sapTools(status: status)
            } else {
                if status == .failed, let error = line.bookings[target]?.lastError {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.danger)
                        .help(error)
                    Button("Erneut senden") {
                        Task { _ = await model.retryManageEngine() }
                    }
                    .controlSize(.small)
                }
                // Der Worklog im Ticket ist freiwillig, SAP nicht.
                if status == .skipped {
                    Button("Doch senden") { model.unskipManageEngine(line) }
                        .controlSize(.small)
                } else if status != .confirmed {
                    Button("Ohne Worklog") { model.skipManageEngine(line, minutes: minutes) }
                        .controlSize(.small)
                        .help("Nur in SAP buchen, keinen Worklog im Ticket anlegen")
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.white.opacity(0.04)))
    }

    @ViewBuilder
    private func sapTools(status: BookingStatus?) -> some View {
        if status == .entered {
            Button("Rückgängig") { model.undoEnteredInSAP(line) }
                .controlSize(.small)
        } else {
            copyButton("PSP", value: line.task.pspElement ?? "")
            if let activity = line.task.sapActivity, !activity.isEmpty {
                copyButton("Tätigkeit", value: activity)
            }
            copyButton("Std.", value: SAPTransfer.hours(minutes))
            copyButton("Text", value: line.sapComment)
            Button {
                model.markEnteredInSAP(line, minutes: minutes)
            } label: {
                Label("In SAP eingetragen", systemImage: "checkmark")
            }
            .controlSize(.small)
            .disabled(!line.issues(for: .sap).isEmpty)
        }
    }

    private func copyButton(_ title: String, value: String) -> some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
        } label: {
            Label(title, systemImage: "doc.on.doc")
        }
        .controlSize(.small)
        .disabled(value.isEmpty)
        .help("„\(value)“ kopieren")
    }

    private func color(for status: BookingStatus?) -> Color {
        switch status {
        case .confirmed, .entered: return Theme.done
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
        TextField("Was wurde gemacht? (Text für Worklog und SAP)", text: $text)
            .textFieldStyle(.roundedBorder)
            .onAppear { text = task.workDescription }
            .onSubmit { model.setDescription(text, for: task.id) }
            .onChange(of: text) { model.setDescription(text, for: task.id) }
    }
}
