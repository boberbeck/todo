import XCTest
@testable import TagwerkCore

final class MeetingTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }()

    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        LocalDate(year: 2026, month: 11, day: 26).startDate(calendar: calendar)
            .addingTimeInterval(TimeInterval(hour * 3600 + minute * 60))
    }

    func testFileAndFolderNames() {
        XCTAssertEqual(MeetingFiles.fileName(title: "Weekly Status Meeting - ceSA", start: at(14), calendar: calendar),
                       "2026-11-26 1400 Weekly Status Meeting - ceSA.md")
        XCTAssertEqual(MeetingFiles.fileName(title: "Review: Q4/2026 \"final\"", start: at(9, 30), calendar: calendar),
                       "2026-11-26 0930 Review Q4 2026 final.md")
        XCTAssertEqual(MeetingFiles.fileName(title: "  ", start: at(8), calendar: calendar), "2026-11-26 0800 Meeting.md")
        XCTAssertEqual(MeetingFiles.folderName(for: "Müller Logistik GmbH"), "Müller Logistik GmbH")
        XCTAssertEqual(MeetingFiles.folderName(for: "A/B: Test."), "A B Test")
        XCTAssertEqual(MeetingFiles.folderName(for: "///"), "Kunde")
    }

    func testTeamsVTTBecomesReadableText() {
        let vtt = """
        WEBVTT

        0f8b1c2d-1
        00:00:03.120 --> 00:00:05.680
        <v Max Muster>Guten Morgen zusammen.</v>

        0f8b1c2d-2
        00:00:05.680 --> 00:00:07.000
        <v Max Muster>Kurz zum Stand beim Ingress.</v>

        0f8b1c2d-3
        00:00:07.100 --> 00:00:09.000
        <v Erika Beispiel>Ich übernehme das Zertifikat &amp; die DNS-Einträge.</v>

        NOTE Ende
        """
        XCTAssertTrue(MeetingFiles.isVTT(vtt))
        XCTAssertFalse(MeetingFiles.isVTT("Max: Hallo"))
        XCTAssertEqual(MeetingFiles.plainTranscript(fromVTT: vtt), """
        Max Muster: Guten Morgen zusammen. Kurz zum Stand beim Ingress.

        Erika Beispiel: Ich übernehme das Zertifikat & die DNS-Einträge.
        """)
        // Ohne Sprecher und mit Windows-Zeilenenden
        let plain = "WEBVTT\r\n\r\n00:00:01.000 --> 00:00:02.000\r\nNur Text\r\n"
        XCTAssertEqual(MeetingFiles.plainTranscript(fromVTT: plain), "Nur Text")
    }

    func testDocumentAndInstructions() {
        let document = MeetingFiles.document(title: "Weekly", start: at(14), end: at(15), customerName: "ceSA",
                                             transcript: "\nMax: Hallo\n", calendar: calendar)
        XCTAssertEqual(document, "# Weekly\n\n26.11.2026, 14:00–15:00\nKunde: ceSA\n\n## Transkript\n\nMax: Hallo\n")
        let instructions = MeetingFiles.claudeInstructions(customerName: "ceSA")
        XCTAssertTrue(instructions.hasPrefix("# ceSA"))
        XCTAssertTrue(instructions.contains("`meeting_transkript`"))
        XCTAssertTrue(instructions.contains("kunde „ceSA“"))
    }

    func testStoredInSQLiteAndUnlinkedOnDelete() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("meeting-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try SQLiteStore(url: url)
        let customer = Customer(name: "ceSA", createdAt: Date(timeIntervalSince1970: 1_800_000_000), folderPath: "/Users/test/Kunden/ceSA")
        try store.save(customer)
        let meeting = Meeting(eventID: "abc@1800000000", title: "Weekly", start: at(14), end: at(15), customerID: customer.id,
                              transcriptPath: "/Users/test/Kunden/ceSA/Meetings/x.md", createdAt: Date(timeIntervalSince1970: 1_800_000_000))
        try store.save(meeting)
        let task = TaskItem(title: "Zertifikat erneuern", createdAt: Date(timeIntervalSince1970: 1_800_000_000), meetingID: meeting.id)
        try store.save(task)

        let loaded = try store.load()
        XCTAssertEqual(loaded.meetings, [meeting])
        XCTAssertEqual(loaded.customers.first?.folderPath, "/Users/test/Kunden/ceSA")
        XCTAssertEqual(loaded.tasks.first?.meetingID, meeting.id)

        var processed = meeting
        processed.processedAt = Date(timeIntervalSince1970: 1_800_003_600)
        try store.save(processed)
        XCTAssertEqual(try store.load().meetings.first?.isProcessed, true)

        try store.deleteMeeting(id: meeting.id)
        let afterDelete = try store.load()
        XCTAssertTrue(afterDelete.meetings.isEmpty)
        XCTAssertNil(afterDelete.tasks.first?.meetingID, "Aufgabe bleibt, verliert nur den Verweis")
    }

    func testClaudeDesktopLink() throws {
        let url = try XCTUnwrap(ClaudeDesktopLink.newCodeSession(
            prompt: "Mach Aufgaben aus „Weekly“ & Co: a=b+c?",
            folder: "/Users/test/Kunden/Müller Logistik"
        ))
        XCTAssertEqual(url.scheme, "claude")
        XCTAssertEqual(url.host, "code")
        XCTAssertEqual(url.path, "/new")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(items.first { $0.name == "q" }?.value, "Mach Aufgaben aus „Weekly“ & Co: a=b+c?")
        XCTAssertEqual(items.first { $0.name == "folder" }?.value, "/Users/test/Kunden/Müller Logistik")
        XCTAssertFalse(url.absoluteString.contains("&Co"), "& im Text ist kodiert")
        XCTAssertTrue(url.absoluteString.contains("%2FUsers%2Ftest"))
        XCTAssertEqual(ClaudeDesktopLink.newCodeSession(prompt: nil, folder: nil)?.absoluteString, "claude://code/new")
        let long = String(repeating: "x", count: 20_000)
        let truncated = ClaudeDesktopLink.newCodeSession(prompt: long, folder: nil)
        let value = URLComponents(url: try XCTUnwrap(truncated), resolvingAgainstBaseURL: false)?.queryItems?.first?.value
        XCTAssertEqual(value?.count, ClaudeDesktopLink.maximumPromptLength)
    }
}
