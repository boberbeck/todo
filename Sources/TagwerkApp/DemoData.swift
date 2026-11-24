import Foundation
import TagwerkCore

/// Beispieldaten für Screenshots und zum Ausprobieren (`TAGWERK_DEMO=1`). Werden nie gespeichert.
enum DemoData {
    static func snapshot(now: Date = Date(), calendar: Calendar = .current) -> Snapshot {
        let today = LocalDate(now, calendar: calendar)
        let minute: TimeInterval = 60
        let hour: TimeInterval = 3600

        let mueller = Customer(name: "Müller Logistik", colorIndex: 1, createdAt: now.addingTimeInterval(-90 * 86400),
                               manageEngineAccount: "Müller Logistik GmbH")
        let stadtwerke = Customer(name: "Stadtwerke Nord", colorIndex: 2, createdAt: now.addingTimeInterval(-80 * 86400))
        let becker = Customer(name: "Becker & Partner", colorIndex: 6, createdAt: now.addingTimeInterval(-70 * 86400))

        var tasks: [TaskItem] = []
        var entries: [TimeEntry] = []

        let week = today.startOfWeek(calendar: calendar)
        let goalOffer = WeeklyGoal(weekStart: week, customerID: becker.id, title: "Angebot Wartungsvertrag verschicken",
                                   createdAt: now.addingTimeInterval(-3 * 86400))
        let goalStoerungen = WeeklyGoal(weekStart: week, customerID: mueller.id, title: "Offene Störungen Müller abarbeiten",
                                        createdAt: now.addingTimeInterval(-3 * 86400))
        let goalMigration = WeeklyGoal(weekStart: week, customerID: becker.id, title: "Mailserver-Migration abschließen",
                                       isDone: true, createdAt: now.addingTimeInterval(-3 * 86400))
        let goalNext = WeeklyGoal(weekStart: week.adding(days: 7, calendar: calendar), customerID: stadtwerke.id,
                                  title: "Backup-Konzept vorstellen", createdAt: now)

        func at(_ hour: Int, _ minute: Int = 0) -> Date {
            FreeTime.date(on: today, minutes: hour * 60 + minute, calendar: calendar)
        }

        func entry(_ task: TaskItem, startsAgo: TimeInterval, minutes: Double) {
            let start = now.addingTimeInterval(-startsAgo)
            entries.append(TimeEntry(taskID: task.id, start: start, end: start.addingTimeInterval(minutes * minute)))
        }

        // Heute
        let serverUpdate = TaskItem(
            title: "Server-Update einspielen",
            customerID: mueller.id,
            source: .ticket,
            externalID: "1240",
            plannedDate: today,
            estimateMinutes: 30,
            workType: .wartung,
            pspElement: "CPSO8643-1",
            workDescription: "Updates eingespielt, Neustart geprüft",
            status: .done,
            completedAt: now.addingTimeInterval(-3 * hour),
            sortIndex: 1,
            createdAt: now.addingTimeInterval(-26 * hour),
            scheduledStart: at(8),
            externalKey: "100124"
        )
        let jourFixe = TaskItem(
            title: "Jour fixe",
            source: .calendar,
            externalID: "demo-jourfixe",
            plannedDate: today,
            estimateMinutes: 30,
            workType: .beratung,
            status: .done,
            completedAt: now.addingTimeInterval(-2 * hour),
            sortIndex: 2,
            createdAt: now.addingTimeInterval(-5 * hour)
        )
        let vpn = TaskItem(
            title: "VPN-Störung prüfen",
            customerID: mueller.id,
            source: .ticket,
            externalID: "1234",
            plannedDate: today,
            estimateMinutes: 60,
            workType: .stoerung,
            pspElement: "CPSO8643-2",
            workDescription: "VPN-Logs geprüft, Tunnel neu gestartet",
            sortIndex: 3,
            createdAt: now.addingTimeInterval(-4 * hour),
            scheduledStart: at(12),
            externalKey: "100123",
            goalID: goalStoerungen.id
        )
        let offer = TaskItem(
            title: "Angebot Wartungsvertrag",
            customerID: becker.id,
            plannedDate: today,
            estimateMinutes: 90,
            workType: .beratung,
            sortIndex: 4,
            createdAt: now.addingTimeInterval(-30 * hour),
            scheduledStart: at(15, 30),
            goalID: goalOffer.id
        )
        let invoice = TaskItem(
            title: "Rückfrage zur Rechnung",
            customerID: stadtwerke.id,
            source: .mail,
            plannedDate: today.adding(days: -1, calendar: calendar),
            estimateMinutes: 15,
            sortIndex: 5,
            createdAt: now.addingTimeInterval(-3 * hour)
        )
        tasks += [serverUpdate, jourFixe, vpn, offer, invoice]
        // Unteraufgaben: das Angebot in Schritten, einer davon mit eigenem Ticket
        tasks += [
            TaskItem(title: "Leistungsumfang klären", customerID: becker.id, status: .done, completedAt: now.addingTimeInterval(-hour),
                     sortIndex: 1, createdAt: now.addingTimeInterval(-29 * hour), parentID: offer.id),
            TaskItem(title: "Preise kalkulieren", customerID: becker.id, estimateMinutes: 45,
                     sortIndex: 2, createdAt: now.addingTimeInterval(-29 * hour), parentID: offer.id),
            TaskItem(title: "Lizenzen prüfen", customerID: becker.id, sortIndex: 3, createdAt: now.addingTimeInterval(-29 * hour),
                     parentID: offer.id, ticketNumber: "1243", ticketKey: "100143"),
            TaskItem(title: "Tunnel-Logs sichern", customerID: mueller.id, status: .done, completedAt: now.addingTimeInterval(-40 * minute),
                     sortIndex: 1, createdAt: now.addingTimeInterval(-3 * hour), parentID: vpn.id),
            TaskItem(title: "Provider anrufen", customerID: mueller.id, sortIndex: 2, createdAt: now.addingTimeInterval(-3 * hour), parentID: vpn.id),
        ]
        entry(serverUpdate, startsAgo: 4 * hour, minutes: 23)
        entries.append(TimeEntry(taskID: jourFixe.id, start: at(9), end: at(9, 30)))
        entry(vpn, startsAgo: 95 * minute, minutes: 10)
        // läuft gerade; zusammen mit dem Eintrag davor 0:42:15
        entries.append(TimeEntry(taskID: vpn.id, start: now.addingTimeInterval(-(32 * minute + 15))))

        // Standardaufgaben, eine davon heute schon genutzt; Mittagspause nach dem Server-Update
        let organisation = TaskItem(title: "Organisatorisches", sortIndex: 1, createdAt: now.addingTimeInterval(-60 * 86400), isStanding: true)
        tasks += [
            organisation,
            TaskItem(title: "Interne Besprechung", sortIndex: 2, createdAt: now.addingTimeInterval(-60 * 86400), isStanding: true),
            TaskItem(title: "Weiterbildung", sortIndex: 3, createdAt: now.addingTimeInterval(-60 * 86400), isStanding: true),
        ]
        entry(organisation, startsAgo: 140 * minute, minutes: 25)
        let lunchStart = now.addingTimeInterval(-215 * minute)
        let breaks = [WorkBreak(start: lunchStart, end: lunchStart.addingTimeInterval(30 * minute), note: "Mittag")]

        // Eingang
        tasks += [
            TaskItem(title: "Drucker im Lager", customerID: mueller.id, source: .ticket, externalID: "1241",
                     workType: .stoerung, createdAt: now.addingTimeInterval(-10 * minute)),
            TaskItem(title: "Zugang für neue Mitarbeiterin", customerID: stadtwerke.id, source: .ticket,
                     externalID: "1243", createdAt: now.addingTimeInterval(-50 * minute)),
            TaskItem(title: "Wartungsvertrag verlängern", customerID: becker.id,
                     createdAt: now.addingTimeInterval(-26 * hour)),
            TaskItem(title: "Backup-Konzept skizzieren", customerID: stadtwerke.id, estimateMinutes: 120,
                     workType: .projekt, createdAt: now.addingTimeInterval(-50 * hour)),
        ]

        // Geplantes für die nächsten Tage (Woche planen)
        tasks += [
            TaskItem(title: "Angebot Firewall-Erneuerung", customerID: mueller.id, plannedDate: today.adding(days: 1, calendar: calendar),
                     estimateMinutes: 90, workType: .beratung, sortIndex: 1, createdAt: now.addingTimeInterval(-5 * hour)),
            TaskItem(title: "Rollout Arbeitsplätze vorbereiten", customerID: stadtwerke.id, plannedDate: today.adding(days: 1, calendar: calendar),
                     estimateMinutes: 120, workType: .projekt, sortIndex: 2, createdAt: now.addingTimeInterval(-5 * hour)),
            TaskItem(title: "Monatsbericht Wartung", customerID: becker.id, plannedDate: today.adding(days: 2, calendar: calendar),
                     estimateMinutes: 45, workType: .wartung, sortIndex: 1, createdAt: now.addingTimeInterval(-4 * hour)),
            TaskItem(title: "Notfallplan aktualisieren", customerID: mueller.id, plannedDate: today.adding(days: 3, calendar: calendar),
                     estimateMinutes: 60, workType: .projekt, sortIndex: 1, createdAt: now.addingTimeInterval(-4 * hour)),
        ]

        // Langes Ziel: Zertifizierung mit Prüfungstermin und 40 Stunden Lernzeit
        let azure = LongGoal(title: "AZ-305 bestehen", dueDate: today.adding(days: 52, calendar: calendar), targetMinutes: 40 * 60,
                             notes: "Prüfung bei Pearson VUE", createdAt: now.addingTimeInterval(-24 * 86400))
        let learned = TaskItem(title: "Modul Identität & Governance", estimateMinutes: 240, status: .done,
                               completedAt: now.addingTimeInterval(-3 * 86400), sortIndex: 1,
                               createdAt: now.addingTimeInterval(-20 * 86400), longGoalID: azure.id)
        let storage = TaskItem(title: "Modul Datenspeicherung lernen", plannedDate: today, estimateMinutes: 90, sortIndex: 6,
                               createdAt: now.addingTimeInterval(-2 * 86400), longGoalID: azure.id)
        let practice = TaskItem(title: "Übungstest Microsoft Learn", estimateMinutes: 60,
                                createdAt: now.addingTimeInterval(-86400), longGoalID: azure.id)
        tasks += [learned, storage, practice]
        for (daysAgo, minutes) in [(18, 90.0), (15, 120), (11, 75), (6, 150), (4, 120), (1, 60)] {
            let start = today.adding(days: -daysAgo, calendar: calendar).startDate(calendar: calendar).addingTimeInterval(18 * hour)
            entries.append(TimeEntry(taskID: learned.id, start: start, end: start.addingTimeInterval(minutes * minute)))
        }

        // Frühere Wochen für den Verlauf im Rückblick
        let weekHours: [Double] = [26, 31, 22, 34, 29, 24]
        for (index, hours) in weekHours.enumerated() {
            let monday = week.adding(days: -7 * (index + 1), calendar: calendar)
            let customer = [mueller, stadtwerke, becker][index % 3]
            let task = TaskItem(title: "Projektarbeit \(customer.name)", customerID: customer.id, plannedDate: monday,
                                estimateMinutes: Int(hours * 60), workType: .projekt, status: .done,
                                completedAt: monday.startDate(calendar: calendar).addingTimeInterval(4 * 86400 + 17 * hour),
                                sortIndex: 1, createdAt: monday.startDate(calendar: calendar))
            tasks.append(task)
            for weekday in 0..<5 {
                let start = monday.adding(days: weekday, calendar: calendar).startDate(calendar: calendar).addingTimeInterval(8 * hour)
                entries.append(TimeEntry(taskID: task.id, start: start, end: start.addingTimeInterval(hours / 5 * hour)))
            }
        }

        // Erledigtes der letzten Tage für den Wochenrückblick
        let earlier: [(title: String, customer: Customer, work: WorkType, daysAgo: Int, minutes: Double)] = [
            ("Firewall-Regeln anpassen", mueller, .wartung, 1, 75),
            ("Workshop Netzplanung", stadtwerke, .beratung, 1, 120),
            ("Migration Mailserver", becker, .projekt, 2, 180),
            ("Störung Telefonanlage", stadtwerke, .stoerung, 2, 45),
            ("Patchday Clients", mueller, .wartung, 3, 90),
            ("Abstimmung Projektplan", becker, .projekt, 3, 60),
        ]
        var startHourByDay: [Int: Double] = [:]
        for item in earlier {
            let day = today.adding(days: -item.daysAgo, calendar: calendar)
            // Einträge eines Tages nacheinander, nicht übereinander
            let startHour = startHourByDay[item.daysAgo] ?? 13
            startHourByDay[item.daysAgo] = startHour + item.minutes / 60 + 0.5
            let start = day.startDate(calendar: calendar).addingTimeInterval(startHour * hour)
            let task = TaskItem(
                title: item.title,
                customerID: item.customer.id,
                source: .ticket,
                externalID: String(1200 + item.daysAgo * 7 + Int(item.minutes) % 7),
                plannedDate: day,
                estimateMinutes: Int(item.minutes),
                workType: item.work,
                status: .done,
                completedAt: start.addingTimeInterval(item.minutes * minute),
                sortIndex: 1,
                createdAt: start.addingTimeInterval(-hour)
            )
            var linked = task
            if item.title == "Migration Mailserver" { linked.goalID = goalMigration.id }
            if item.customer.id == mueller.id && item.work == .wartung { linked.goalID = goalStoerungen.id }
            tasks.append(linked)
            entries.append(TimeEntry(taskID: task.id, start: start, end: start.addingTimeInterval(item.minutes * minute)))
        }

        let psps = [
            PSPElement(customerID: mueller.id, code: "CPSO8643-1", title: "Wartungsvertrag 2026", lastUsedAt: now.addingTimeInterval(-3 * hour)),
            PSPElement(customerID: mueller.id, code: "CPSO8643-2", title: "Störungen", lastUsedAt: now.addingTimeInterval(-hour)),
            PSPElement(customerID: mueller.id, code: "CPSO8643-4", title: "Projekt Netzumbau", isActive: false),
            PSPElement(customerID: stadtwerke.id, code: "CPSO8710-1", title: "Support"),
            PSPElement(customerID: becker.id, code: "CPSO8802-1", title: "Beratung", activity: "Consulting"),
            PSPElement(customerID: becker.id, code: "CPSO8802-1", title: "Beratung", activity: "Remote Support"),
        ]

        // Das Server-Update ist schon gebucht: Worklog bestätigt, in SAP eingetragen.
        let bookings = [
            Booking(taskID: serverUpdate.id, day: today, target: .manageEngine, minutes: 30,
                    description: serverUpdate.workDescription, pspElement: "CPSO8643-1", workType: .wartung,
                    ticketKey: "100124", status: .confirmed, reference: "WL-8812", updatedAt: now.addingTimeInterval(-2 * hour)),
            Booking(taskID: serverUpdate.id, day: today, target: .sap, minutes: 30,
                    description: "#1240 \(serverUpdate.workDescription)", pspElement: "CPSO8643-1", workType: .wartung,
                    status: .entered, updatedAt: now.addingTimeInterval(-2 * hour)),
        ]

        return Snapshot(customers: [mueller, stadtwerke, becker], tasks: tasks, entries: entries,
                        pspElements: psps, bookings: bookings,
                        goals: [goalOffer, goalStoerungen, goalMigration, goalNext], longGoals: [azure],
                        breaks: breaks)
    }

    /// So sieht die englische Aufgabenliste aus ByDesign aus (für Bildschirmfotos): mehrere Activities je Aufgabe.
    static let sapRows: [SAPTaskRow] = SAPImport.rows(fromCells: [
        ["Category", "Task ID", "Work Package Task", "Activity", "Project ID", "Customer"],
        ["Project Task", "CPSO8643-1", "Wartungsvertrag 2026", "Maintenance", "CPSO8643", "Müller Logistik GmbH"],
        ["Project Task", "CPSO8643-1", "Wartungsvertrag 2026", "Remote Support", "CPSO8643", "Müller Logistik GmbH"],
        ["Project Task", "CPSO8643-2", "Störungen und Notfälle", "Remote Support", "CPSO8643", "Müller Logistik GmbH"],
        ["Project Task", "CPSO8643-5", "Migration Exchange Online", "Consulting", "CPSO8643", "Müller Logistik GmbH"],
        ["Project Task", "CPSO8643-6", "Firewall-Erneuerung", "Consulting", "CPSO8643", "Müller Logistik GmbH"],
        ["Project Task", "CPSO8710-1", "Support", "Remote Support", "CPSO8710", "Stadtwerke Nord"],
        ["Project Task", "CPSO8710-2", "Rollout Arbeitsplätze", "Installation", "CPSO8710", "Stadtwerke Nord"],
        ["Project Task", "CPSO8955-1", "Team Sitzung", "Internal Meeting", "CPSO8955", "Intern"],
        ["Project Task", "CPSO8955-1", "Team Sitzung", "Training", "CPSO8955", "Intern"],
    ])
}
