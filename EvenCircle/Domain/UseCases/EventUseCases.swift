import Foundation

/// Card data for the Events list. Totals are per event; there is no cross-currency total.
struct EventSummary: Identifiable, Equatable {
    let aggregate: EventAggregate
    let balances: EventBalances?

    var id: UUID { event.id }
    var event: Event { aggregate.event }
    var peopleCount: Int { aggregate.people.count }
    var expenseCount: Int { aggregate.expenses.count }
    var paymentCount: Int { aggregate.payments.count }
    var totalExpensesMinor: Int64 { balances?.totalExpensesMinor ?? 0 }
    var outstandingMinor: Int64 { balances?.outstandingMinor ?? 0 }
    var status: EventStatus { balances?.status ?? .openBalance }
    var hasOpenBalance: Bool { (balances?.outstandingMinor ?? 0) > 0 }
}

/// A person to create together with a new event (used by Duplicate).
struct PersonTemplate: Equatable {
    var name: String
    var avatarColor: AvatarColorKey
}

struct EventForm: Equatable {
    var name: String
    var date: CalendarDate
    var currency: CurrencyCode
    var note: String?
}

enum EventFormField: Hashable {
    case name, note
}

enum EventRules {
    static func validate(_ form: EventForm) -> [EventFormField: String] {
        var issues: [EventFormField: String] = [:]
        if let error = TextRules.validateRequired(form.name, field: "Event name", range: DomainLimits.eventNameLength) {
            issues[.name] = error.message
        }
        if let error = TextRules.validateNote(form.note, maxLength: DomainLimits.eventNoteMaxLength) {
            issues[.note] = error.message
        }
        return issues
    }

    /// Events by date (newest first), then createdAt (newest first), then UUID.
    static func sort(_ summaries: [EventSummary]) -> [EventSummary] {
        summaries.sorted { lhs, rhs in
            if lhs.event.eventDate != rhs.event.eventDate { return lhs.event.eventDate > rhs.event.eventDate }
            if lhs.event.createdAt != rhs.event.createdAt { return lhs.event.createdAt > rhs.event.createdAt }
            return lhs.event.id.lowercasedString < rhs.event.id.lowercasedString
        }
    }
}

final class EventUseCases {
    private let repository: EventRepository
    private let clock: AppClock

    init(repository: EventRepository, clock: AppClock) {
        self.repository = repository
        self.clock = clock
    }

    var today: CalendarDate { clock.today }

    func loadSummaries() async throws -> [EventSummary] {
        let aggregates = try await repository.loadAll()
        return await Task.detached(priority: .userInitiated) {
            EventRules.sort(aggregates.map { EventSummary(aggregate: $0, balances: try? BalanceCalculator.calculate($0)) })
        }.value
    }

    func loadAggregate(id: UUID) async throws -> EventAggregate? {
        try await repository.load(eventID: id)
    }

    /// Creates the event and its people atomically. `id` is generated once per form, so
    /// a double tap or a retry can never create two events.
    @discardableResult
    func createEvent(id: UUID, form: EventForm, people: [PersonTemplate]) async throws -> WriteOutcome {
        let issues = EventRules.validate(form)
        guard issues.isEmpty else { throw FieldError(issues.values.first ?? "Check the event details.") }
        guard people.count <= DomainLimits.maxPeoplePerEvent else {
            throw RepositoryError.limitReached("An event can have up to \(DomainLimits.maxPeoplePerEvent) people.")
        }
        let now = clock.now()
        let event = Event(
            id: id,
            name: TextRules.clean(form.name),
            eventDate: form.date,
            currency: form.currency,
            currencyLocked: false,
            note: TextRules.cleanNote(form.note),
            isArchived: false,
            isDemo: false,
            revision: 1,
            createdAt: now,
            updatedAt: now
        )
        let persons = people.enumerated().map { index, template in
            Person(
                id: UUID(),
                eventID: id,
                name: TextRules.clean(template.name),
                avatarColor: template.avatarColor,
                // Keeps the copied order stable.
                createdAt: now.addingTimeInterval(Double(index) * 0.001),
                updatedAt: now
            )
        }
        return try await repository.createEvent(event, people: persons)
    }

    func updateEvent(id: UUID, form: EventForm, expectedRevision: Int64) async throws {
        let issues = EventRules.validate(form)
        guard issues.isEmpty else { throw FieldError(issues.values.first ?? "Check the event details.") }
        try await repository.updateEvent(
            id: id,
            name: TextRules.clean(form.name),
            date: form.date,
            currency: form.currency,
            note: TextRules.cleanNote(form.note),
            expectedRevision: expectedRevision
        )
    }

    func setArchived(_ archived: Bool, eventID: UUID) async throws {
        try await repository.setArchived(eventID: eventID, archived: archived)
    }

    func deleteEvent(id: UUID) async throws {
        try await repository.deleteEvent(eventID: id)
    }

    /// Form values for Duplicate: "<name> copy", today, same currency, people names only.
    func duplicateTemplate(from aggregate: EventAggregate) -> (form: EventForm, people: [PersonTemplate]) {
        let suffix = " copy"
        var name = aggregate.event.name
        if name.count + suffix.count > DomainLimits.eventNameLength.upperBound {
            name = String(name.prefix(DomainLimits.eventNameLength.upperBound - suffix.count))
        }
        let form = EventForm(name: name + suffix, date: clock.today, currency: aggregate.event.currency, note: nil)
        let people = aggregate.orderedPeople.map { PersonTemplate(name: $0.name, avatarColor: $0.avatarColor) }
        return (form, people)
    }
}
