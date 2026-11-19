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
            pspElement: "4702",
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
            pspElement: "4711",
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
        entry(serverUpdate, startsAgo: 4 * hour, minutes: 23)
        entries.append(TimeEntry(taskID: jourFixe.id, start: at(9), end: at(9, 30)))
        entry(vpn, startsAgo: 95 * minute, minutes: 10)
        // läuft gerade; zusammen mit dem Eintrag davor 0:42:15
        entries.append(TimeEntry(taskID: vpn.id, start: now.addingTimeInterval(-(32 * minute + 15))))

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

        // Erledigtes der letzten Tage für den Wochenrückblick
        let earlier: [(title: String, customer: Customer, work: WorkType, daysAgo: Int, minutes: Double)] = [
            ("Firewall-Regeln anpassen", mueller, .wartung, 1, 75),
            ("Workshop Netzplanung", stadtwerke, .beratung, 1, 120),
            ("Migration Mailserver", becker, .projekt, 2, 180),
            ("Störung Telefonanlage", stadtwerke, .stoerung, 2, 45),
            ("Patchday Clients", mueller, .wartung, 3, 90),
            ("Abstimmung Projektplan", becker, .projekt, 3, 60),
        ]
        for item in earlier {
            let day = today.adding(days: -item.daysAgo, calendar: calendar)
            let start = day.startDate(calendar: calendar).addingTimeInterval(9 * hour)
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
            PSPElement(customerID: mueller.id, code: "4702", title: "Wartungsvertrag 2026", lastUsedAt: now.addingTimeInterval(-3 * hour)),
            PSPElement(customerID: mueller.id, code: "4711", title: "Störungen", lastUsedAt: now.addingTimeInterval(-hour)),
            PSPElement(customerID: mueller.id, code: "4690", title: "Projekt Netzumbau", isActive: false),
            PSPElement(customerID: stadtwerke.id, code: "5120", title: "Support"),
            PSPElement(customerID: becker.id, code: "6001", title: "Beratung"),
        ]

        // Das Server-Update ist schon gebucht: Worklog bestätigt, in SAP eingetragen.
        let bookings = [
            Booking(taskID: serverUpdate.id, day: today, target: .manageEngine, minutes: 30,
                    description: serverUpdate.workDescription, pspElement: "4702", workType: .wartung,
                    ticketKey: "100124", status: .confirmed, reference: "WL-8812", updatedAt: now.addingTimeInterval(-2 * hour)),
            Booking(taskID: serverUpdate.id, day: today, target: .sap, minutes: 30,
                    description: "#1240 \(serverUpdate.workDescription)", pspElement: "4702", workType: .wartung,
                    status: .entered, updatedAt: now.addingTimeInterval(-2 * hour)),
        ]

        return Snapshot(customers: [mueller, stadtwerke, becker], tasks: tasks, entries: entries,
                        pspElements: psps, bookings: bookings,
                        goals: [goalOffer, goalStoerungen, goalMigration, goalNext])
    }
}
