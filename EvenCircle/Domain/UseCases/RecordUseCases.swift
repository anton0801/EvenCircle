import Foundation

final class PeopleUseCases {
    private let repository: EventRepository
    private let clock: AppClock

    init(repository: EventRepository, clock: AppClock) {
        self.repository = repository
        self.clock = clock
    }

    func addPerson(name: String, color: AvatarColorKey, to aggregate: EventAggregate) async throws {
        guard aggregate.people.count < DomainLimits.maxPeoplePerEvent else {
            throw RepositoryError.limitReached("An event can have up to \(DomainLimits.maxPeoplePerEvent) people.")
        }
        if let error = PersonRules.validateName(name, eventPeople: aggregate.people, editingID: nil) { throw error }
        let now = clock.now()
        let person = Person(id: UUID(), eventID: aggregate.event.id, name: TextRules.clean(name), avatarColor: color, createdAt: now, updatedAt: now)
        try await repository.savePerson(person, expectedRevision: aggregate.event.revision)
    }

    /// Renaming keeps the UUID, so every calculation stays attached to the same person.
    func updatePerson(_ person: Person, name: String, color: AvatarColorKey, in aggregate: EventAggregate) async throws {
        if let error = PersonRules.validateName(name, eventPeople: aggregate.people, editingID: person.id) { throw error }
        var updated = person
        updated.name = TextRules.clean(name)
        updated.avatarColor = color
        updated.updatedAt = clock.now()
        try await repository.savePerson(updated, expectedRevision: aggregate.event.revision)
    }

    func deletePerson(_ personID: UUID, in aggregate: EventAggregate) async throws {
        guard !aggregate.isPersonLinked(personID) else { throw RepositoryError.personLinked }
        try await repository.deletePerson(personID: personID, eventID: aggregate.event.id, expectedRevision: aggregate.event.revision)
    }
}

final class ExpenseUseCases {
    private let repository: EventRepository
    private let clock: AppClock

    init(repository: EventRepository, clock: AppClock) {
        self.repository = repository
        self.clock = clock
    }

    var today: CalendarDate { clock.today }

    func build(_ draft: ExpenseDraft, in aggregate: EventAggregate) -> Result<Expense, ExpenseDraftIssues> {
        ExpenseBuilder.build(draft, eventPeopleIDs: Set(aggregate.people.map(\.id)), today: clock.today, now: clock.now())
    }

    /// Before / After for saving `expense` into `aggregate`.
    func previewSave(_ expense: Expense, in aggregate: EventAggregate) throws -> BalanceChangePreview {
        try BalanceChangePreview.make(before: aggregate, after: aggregate.replacingExpense(expense))
    }

    func previewDelete(_ expenseID: UUID, in aggregate: EventAggregate) throws -> BalanceChangePreview {
        try BalanceChangePreview.make(before: aggregate, after: aggregate.removingExpense(expenseID))
    }

    /// Saves one expense, its shares and receipt lines in one transaction and locks the event currency.
    func save(_ expense: Expense, operationID: UUID, expectedRevision: Int64) async throws -> WriteOutcome {
        try await repository.saveExpense(expense, operationID: operationID, expectedRevision: expectedRevision)
    }

    /// Recorded payments are never removed or adjusted when an expense is deleted.
    func delete(_ expenseID: UUID, in aggregate: EventAggregate) async throws {
        try await repository.deleteExpense(expenseID: expenseID, eventID: aggregate.event.id, expectedRevision: aggregate.event.revision)
    }
}

final class PaymentUseCases {
    private let repository: EventRepository
    private let clock: AppClock

    init(repository: EventRepository, clock: AppClock) {
        self.repository = repository
        self.clock = clock
    }

    var today: CalendarDate { clock.today }

    func validate(_ draft: PaymentDraft, aggregate: EventAggregate, balances: EventBalances) -> [PaymentDraftField: String] {
        PaymentRules.validate(draft, aggregate: aggregate, balances: balances, today: clock.today)
    }

    /// Records a transfer the user already made outside the app. The same `operationID`
    /// never creates a second record.
    func record(_ draft: PaymentDraft, operationID: UUID, paymentID: UUID, aggregate: EventAggregate) async throws -> WriteOutcome {
        let balances = try BalanceCalculator.calculate(aggregate)
        let issues = validate(draft, aggregate: aggregate, balances: balances)
        if let first = issues.first { throw FieldError(first.value) }
        guard let from = draft.fromID, let to = draft.toID, let amount = draft.amountMinor else {
            throw FieldError("Check the payment details.")
        }
        let payment = Payment(
            id: paymentID,
            eventID: aggregate.event.id,
            fromID: from,
            toID: to,
            amountMinor: amount,
            paymentDate: draft.date,
            note: TextRules.cleanNote(draft.note),
            operationID: operationID,
            createdAt: clock.now()
        )
        return try await repository.recordPayment(payment, expectedRevision: aggregate.event.revision)
    }

    func previewDelete(_ paymentID: UUID, in aggregate: EventAggregate) throws -> BalanceChangePreview {
        try BalanceChangePreview.make(before: aggregate, after: aggregate.removingPayment(paymentID))
    }

    /// Removes a record only; it does not reverse a real payment and never touches expenses.
    func delete(_ paymentID: UUID, in aggregate: EventAggregate) async throws {
        try await repository.deletePayment(paymentID: paymentID, eventID: aggregate.event.id, expectedRevision: aggregate.event.revision)
    }
}
