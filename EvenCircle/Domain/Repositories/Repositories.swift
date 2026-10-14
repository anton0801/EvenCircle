import Combine
import Foundation

enum RepositoryError: Error, Equatable {
    case notFound
    /// The event changed after the editor loaded it (Event.revision mismatch).
    case revisionConflict
    case eventArchived
    case currencyLocked
    case personLinked
    case duplicatePersonName
    case limitReached(String)
    case invalidReference
    case storageFailure

    var message: String {
        switch self {
        case .notFound: return "This record is no longer available."
        case .revisionConflict: return "This event changed while you were editing. Review the updated data."
        case .eventArchived: return "This event is archived. Restore it to make changes."
        case .currencyLocked: return "Currency is locked after the first expense."
        case .personLinked: return "This person is linked to saved records."
        case .duplicatePersonName: return "Someone in this event already has this name."
        case .limitReached(let detail): return detail
        case .invalidReference: return "This change refers to people who are not in the event."
        case .storageFailure: return "Your changes couldn't be saved. Try again."
        }
    }
}

enum WriteOutcome: Equatable {
    case applied
    /// The same operation was already stored earlier (idempotent retry); nothing new was written.
    case alreadyApplied
}

struct DataCounts: Equatable {
    var events: Int
    var people: Int
    var expenses: Int
    var payments: Int

    static let zero = DataCounts(events: 0, people: 0, expenses: 0, payments: 0)
    var isEmpty: Bool { events == 0 }
}

enum RepositoryChange: Equatable {
    case event(UUID)
    case all
}

/// Local event storage. Every mutation of an event increments `Event.revision` in the same transaction.
protocol EventRepository: AnyObject {
    /// Emits after every committed change, on the main queue.
    var changes: AnyPublisher<RepositoryChange, Never> { get }

    func loadAll() async throws -> [EventAggregate]
    func load(eventID: UUID) async throws -> EventAggregate?
    func counts() async throws -> DataCounts

    func createEvent(_ event: Event, people: [Person]) async throws -> WriteOutcome
    func updateEvent(id: UUID, name: String, date: CalendarDate, currency: CurrencyCode, note: String?, expectedRevision: Int64) async throws
    func setArchived(eventID: UUID, archived: Bool) async throws
    func deleteEvent(eventID: UUID) async throws

    func savePerson(_ person: Person, expectedRevision: Int64) async throws
    func deletePerson(personID: UUID, eventID: UUID, expectedRevision: Int64) async throws

    func saveExpense(_ expense: Expense, operationID: UUID, expectedRevision: Int64) async throws -> WriteOutcome
    func deleteExpense(expenseID: UUID, eventID: UUID, expectedRevision: Int64) async throws

    func recordPayment(_ payment: Payment, expectedRevision: Int64) async throws -> WriteOutcome
    func deletePayment(paymentID: UUID, eventID: UUID, expectedRevision: Int64) async throws

    func insertDemo(_ aggregate: EventAggregate) async throws -> WriteOutcome
    func deleteDemoEvents() async throws -> Int

    /// Atomically replaces the whole database. On failure nothing changes.
    func replaceAll(with aggregates: [EventAggregate]) async throws
    func deleteAll() async throws
}

protocol SettingsRepository: AnyObject {
    func load() -> AppSettings
    func save(_ settings: AppSettings)
    func reset()
}

struct BackupPreview: Equatable {
    struct EventLine: Equatable, Identifiable {
        let id: UUID
        let name: String
        let currency: CurrencyCode
        let isDemo: Bool
    }

    let schemaVersion: Int
    let exportedAt: Date?
    let counts: DataCounts
    let events: [EventLine]

    var containsDemo: Bool { events.contains(where: \.isDemo) }
}

struct ValidatedBackup: Equatable {
    let preview: BackupPreview
    let aggregates: [EventAggregate]
}

struct BackupValidationError: Error, Equatable {
    let message: String
}

protocol BackupCoding {
    func encode(_ aggregates: [EventAggregate], exportedAt: Date) throws -> Data
    /// Decodes and fully validates a backup without touching the database.
    func decodeAndValidate(_ data: Data) throws -> ValidatedBackup
}

struct SafetyCopyInfo: Equatable {
    let createdAt: Date
    let byteCount: Int
}

protocol BackupFileStoring: AnyObject {
    func writeExportFile(_ data: Data) throws -> URL
    func deleteExportFiles()
    /// Reads a user-selected file, enforcing the size limit before loading it.
    func readImportFile(at url: URL) throws -> Data

    func safetyCopyInfo() -> SafetyCopyInfo?
    func writeSafetyCopy(_ data: Data) throws
    func readSafetyCopy() throws -> Data
    func deleteSafetyCopy() throws
}

/// Injectable time source so dates are testable.
struct AppClock {
    var now: () -> Date
    var timeZone: () -> TimeZone

    static let system = AppClock(now: { Date() }, timeZone: { .current })

    var today: CalendarDate { CalendarDate.today(now: now(), timeZone: timeZone()) }
}
