import Foundation
#if canImport(SQLite3)
import SQLite3
#else
import CSQLite
#endif

public enum SQLiteError: Error, CustomStringConvertible {
    case open(String)
    case prepare(String)
    case step(String)
    case exec(String)

    public var description: String {
        switch self {
        case .open(let message): return "Datenbank lässt sich nicht öffnen: \(message)"
        case .prepare(let message): return "SQL-Fehler: \(message)"
        case .step(let message): return "Speichern fehlgeschlagen: \(message)"
        case .exec(let message): return "SQL-Fehler: \(message)"
        }
    }
}

/// Speichert alle Daten lokal in einer SQLite-Datei. Nutzt die SQLite-Bibliothek des Systems.
public final class SQLiteStore: Store {
    private var db: OpaquePointer?

    /// Aktuelle Version des Datenbankschemas.
    public static let schemaVersion = 2

    public init(url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        if sqlite3_open_v2(url.path, &db, flags, nil) != SQLITE_OK {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unbekannt"
            sqlite3_close(db)
            db = nil
            throw SQLiteError.open(message)
        }
        try exec("PRAGMA journal_mode = WAL;")
        try migrate()
    }

    deinit {
        sqlite3_close(db)
    }

    // MARK: Schema

    private func migrate() throws {
        let version = try userVersion()
        if version < 1 {
            try exec("""
            BEGIN;
            CREATE TABLE IF NOT EXISTS customer (
                id TEXT PRIMARY KEY NOT NULL,
                name TEXT NOT NULL,
                color_index INTEGER NOT NULL DEFAULT 0,
                is_archived INTEGER NOT NULL DEFAULT 0,
                created_at REAL NOT NULL
            );
            CREATE TABLE IF NOT EXISTS task (
                id TEXT PRIMARY KEY NOT NULL,
                title TEXT NOT NULL,
                notes TEXT NOT NULL DEFAULT '',
                customer_id TEXT,
                source TEXT NOT NULL,
                external_id TEXT,
                external_url TEXT,
                planned_date TEXT,
                estimate_minutes INTEGER,
                work_type TEXT,
                psp_element TEXT,
                work_description TEXT NOT NULL DEFAULT '',
                status TEXT NOT NULL,
                completed_at REAL,
                sort_index REAL NOT NULL DEFAULT 0,
                created_at REAL NOT NULL
            );
            CREATE INDEX IF NOT EXISTS task_planned_date ON task (planned_date);
            CREATE INDEX IF NOT EXISTS task_customer ON task (customer_id);
            CREATE TABLE IF NOT EXISTS time_entry (
                id TEXT PRIMARY KEY NOT NULL,
                task_id TEXT,
                start_at REAL NOT NULL,
                end_at REAL,
                note TEXT NOT NULL DEFAULT ''
            );
            CREATE INDEX IF NOT EXISTS time_entry_task ON time_entry (task_id);
            CREATE INDEX IF NOT EXISTS time_entry_start ON time_entry (start_at);
            PRAGMA user_version = 1;
            COMMIT;
            """)
        }
        if version < 2 {
            try exec("""
            BEGIN;
            ALTER TABLE task ADD COLUMN scheduled_start REAL;
            ALTER TABLE task ADD COLUMN calendar_event_id TEXT;
            PRAGMA user_version = 2;
            COMMIT;
            """)
        }
    }

    private func userVersion() throws -> Int {
        let statement = try prepare("PRAGMA user_version;")
        guard try statement.step() else { return 0 }
        return statement.int(0) ?? 0
    }

    // MARK: Laden

    public func load() throws -> Snapshot {
        var snapshot = Snapshot()

        let customers = try prepare("SELECT id, name, color_index, is_archived, created_at FROM customer;")
        while try customers.step() {
            guard let id = customers.uuid(0) else { continue }
            snapshot.customers.append(Customer(
                id: id,
                name: customers.text(1) ?? "",
                colorIndex: customers.int(2) ?? 0,
                isArchived: (customers.int(3) ?? 0) != 0,
                createdAt: customers.date(4) ?? Date()
            ))
        }

        let tasks = try prepare("""
        SELECT id, title, notes, customer_id, source, external_id, external_url, planned_date,
               estimate_minutes, work_type, psp_element, work_description, status, completed_at,
               sort_index, created_at, scheduled_start, calendar_event_id
        FROM task;
        """)
        while try tasks.step() {
            guard let id = tasks.uuid(0) else { continue }
            snapshot.tasks.append(TaskItem(
                id: id,
                title: tasks.text(1) ?? "",
                notes: tasks.text(2) ?? "",
                customerID: tasks.uuid(3),
                source: TaskSource(rawValue: tasks.text(4) ?? "") ?? .local,
                externalID: tasks.text(5),
                externalURL: tasks.text(6),
                plannedDate: tasks.text(7).flatMap { LocalDate(string: $0) },
                estimateMinutes: tasks.int(8),
                workType: tasks.text(9).flatMap { WorkType(rawValue: $0) },
                pspElement: tasks.text(10),
                workDescription: tasks.text(11) ?? "",
                status: TaskStatus(rawValue: tasks.text(12) ?? "") ?? .open,
                completedAt: tasks.date(13),
                sortIndex: tasks.double(14) ?? 0,
                createdAt: tasks.date(15) ?? Date(),
                scheduledStart: tasks.date(16),
                calendarEventID: tasks.text(17)
            ))
        }

        let entries = try prepare("SELECT id, task_id, start_at, end_at, note FROM time_entry;")
        while try entries.step() {
            guard let id = entries.uuid(0), let start = entries.date(2) else { continue }
            snapshot.entries.append(TimeEntry(
                id: id,
                taskID: entries.uuid(1),
                start: start,
                end: entries.date(3),
                note: entries.text(4) ?? ""
            ))
        }

        return snapshot
    }

    // MARK: Speichern

    public func save(_ customer: Customer) throws {
        try run("""
        INSERT INTO customer (id, name, color_index, is_archived, created_at)
        VALUES (?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            name = excluded.name,
            color_index = excluded.color_index,
            is_archived = excluded.is_archived;
        """, [
            .text(customer.id.uuidString),
            .text(customer.name),
            .int(customer.colorIndex),
            .int(customer.isArchived ? 1 : 0),
            .double(customer.createdAt.timeIntervalSince1970),
        ])
    }

    public func save(_ task: TaskItem) throws {
        try run("""
        INSERT INTO task (id, title, notes, customer_id, source, external_id, external_url, planned_date,
                          estimate_minutes, work_type, psp_element, work_description, status, completed_at,
                          sort_index, created_at, scheduled_start, calendar_event_id)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            title = excluded.title,
            notes = excluded.notes,
            customer_id = excluded.customer_id,
            source = excluded.source,
            external_id = excluded.external_id,
            external_url = excluded.external_url,
            planned_date = excluded.planned_date,
            estimate_minutes = excluded.estimate_minutes,
            work_type = excluded.work_type,
            psp_element = excluded.psp_element,
            work_description = excluded.work_description,
            status = excluded.status,
            completed_at = excluded.completed_at,
            sort_index = excluded.sort_index,
            scheduled_start = excluded.scheduled_start,
            calendar_event_id = excluded.calendar_event_id;
        """, [
            .text(task.id.uuidString),
            .text(task.title),
            .text(task.notes),
            .optionalText(task.customerID?.uuidString),
            .text(task.source.rawValue),
            .optionalText(task.externalID),
            .optionalText(task.externalURL),
            .optionalText(task.plannedDate?.string),
            .optionalInt(task.estimateMinutes),
            .optionalText(task.workType?.rawValue),
            .optionalText(task.pspElement),
            .text(task.workDescription),
            .text(task.status.rawValue),
            .optionalDouble(task.completedAt?.timeIntervalSince1970),
            .double(task.sortIndex),
            .double(task.createdAt.timeIntervalSince1970),
            .optionalDouble(task.scheduledStart?.timeIntervalSince1970),
            .optionalText(task.calendarEventID),
        ])
    }

    public func save(_ entry: TimeEntry) throws {
        try run("""
        INSERT INTO time_entry (id, task_id, start_at, end_at, note)
        VALUES (?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            task_id = excluded.task_id,
            start_at = excluded.start_at,
            end_at = excluded.end_at,
            note = excluded.note;
        """, [
            .text(entry.id.uuidString),
            .optionalText(entry.taskID?.uuidString),
            .double(entry.start.timeIntervalSince1970),
            .optionalDouble(entry.end?.timeIntervalSince1970),
            .text(entry.note),
        ])
    }

    public func deleteTask(id: UUID) throws {
        try exec("BEGIN;")
        do {
            try run("DELETE FROM time_entry WHERE task_id = ?;", [.text(id.uuidString)])
            try run("DELETE FROM task WHERE id = ?;", [.text(id.uuidString)])
            try exec("COMMIT;")
        } catch {
            try? exec("ROLLBACK;")
            throw error
        }
    }

    public func deleteEntry(id: UUID) throws {
        try run("DELETE FROM time_entry WHERE id = ?;", [.text(id.uuidString)])
    }

    // MARK: Hilfen

    private func exec(_ sql: String) throws {
        var errorPointer: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &errorPointer) != SQLITE_OK {
            let message = errorPointer.map { String(cString: $0) } ?? lastErrorMessage()
            sqlite3_free(errorPointer)
            throw SQLiteError.exec(message)
        }
    }

    private func run(_ sql: String, _ values: [SQLValue]) throws {
        let statement = try prepare(sql)
        try statement.bind(values)
        _ = try statement.step()
    }

    private func prepare(_ sql: String) throws -> Statement {
        guard let db else { throw SQLiteError.open("keine Verbindung") }
        return try Statement(db: db, sql: sql)
    }

    private func lastErrorMessage() -> String {
        guard let db else { return "keine Verbindung" }
        return String(cString: sqlite3_errmsg(db))
    }
}

enum SQLValue {
    case text(String)
    case int(Int)
    case double(Double)
    case null

    static func optionalText(_ value: String?) -> SQLValue { value.map { .text($0) } ?? .null }
    static func optionalInt(_ value: Int?) -> SQLValue { value.map { .int($0) } ?? .null }
    static func optionalDouble(_ value: Double?) -> SQLValue { value.map { .double($0) } ?? .null }
}

/// SQLite kopiert gebundene Texte sofort (entspricht SQLITE_TRANSIENT in C).
private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class Statement {
    private let db: OpaquePointer
    private let handle: OpaquePointer

    init(db: OpaquePointer, sql: String) throws {
        var pointer: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &pointer, nil) == SQLITE_OK, let pointer else {
            throw SQLiteError.prepare(String(cString: sqlite3_errmsg(db)))
        }
        self.db = db
        self.handle = pointer
    }

    deinit {
        sqlite3_finalize(handle)
    }

    func bind(_ values: [SQLValue]) throws {
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            let result: Int32
            switch value {
            case .text(let text):
                result = sqlite3_bind_text(handle, index, text, -1, sqliteTransient)
            case .int(let number):
                result = sqlite3_bind_int64(handle, index, Int64(number))
            case .double(let number):
                result = sqlite3_bind_double(handle, index, number)
            case .null:
                result = sqlite3_bind_null(handle, index)
            }
            if result != SQLITE_OK {
                throw SQLiteError.prepare(String(cString: sqlite3_errmsg(db)))
            }
        }
    }

    /// `true`, solange eine Zeile vorliegt.
    func step() throws -> Bool {
        let result = sqlite3_step(handle)
        switch result {
        case SQLITE_ROW: return true
        case SQLITE_DONE: return false
        default: throw SQLiteError.step(String(cString: sqlite3_errmsg(db)))
        }
    }

    private func isNull(_ column: Int32) -> Bool {
        sqlite3_column_type(handle, column) == SQLITE_NULL
    }

    func text(_ column: Int32) -> String? {
        guard !isNull(column), let pointer = sqlite3_column_text(handle, column) else { return nil }
        return String(cString: pointer)
    }

    func int(_ column: Int32) -> Int? {
        isNull(column) ? nil : Int(sqlite3_column_int64(handle, column))
    }

    func double(_ column: Int32) -> Double? {
        isNull(column) ? nil : sqlite3_column_double(handle, column)
    }

    func date(_ column: Int32) -> Date? {
        double(column).map { Date(timeIntervalSince1970: $0) }
    }

    func uuid(_ column: Int32) -> UUID? {
        text(column).flatMap { UUID(uuidString: $0) }
    }
}
