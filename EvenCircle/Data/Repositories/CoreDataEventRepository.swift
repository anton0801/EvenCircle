import Combine
import CoreData
import Foundation

/// Core Data implementation of `EventRepository`.
///
/// All work runs on one private-queue context, so operations are serialized: each write
/// validates the expected revision and commits in a single `save()` (all or nothing).
final class CoreDataEventRepository: EventRepository {
    private let stack: CoreDataStack
    private let clock: AppClock
    private let subject = PassthroughSubject<RepositoryChange, Never>()

    init(stack: CoreDataStack, clock: AppClock) {
        self.stack = stack
        self.clock = clock
    }

    var changes: AnyPublisher<RepositoryChange, Never> {
        subject.receive(on: DispatchQueue.main).eraseToAnyPublisher()
    }

    // MARK: - Infrastructure

    private func perform<T>(_ block: @escaping (NSManagedObjectContext) throws -> T) async throws -> T {
        let context = stack.context
        return try await context.perform {
            do {
                return try block(context)
            } catch {
                context.rollback()
                if let repositoryError = error as? RepositoryError { throw repositoryError }
                if error is FieldError { throw error }
                #if DEBUG
                print("Even Circle repository error: \(error)")
                #endif
                throw RepositoryError.storageFailure
            }
        }
    }

    private func notify(_ change: RepositoryChange) {
        subject.send(change)
    }

    private func fetchEvent(_ id: UUID, in context: NSManagedObjectContext) throws -> CDEvent? {
        let request = NSFetchRequest<CDEvent>(entityName: "CDEvent")
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    private func fetchAllEvents(in context: NSManagedObjectContext) throws -> [CDEvent] {
        let request = NSFetchRequest<CDEvent>(entityName: "CDEvent")
        request.relationshipKeyPathsForPrefetching = [
            "people", "expenses", "expenses.shares", "expenses.items", "expenses.items.shares", "payments",
        ]
        return try context.fetch(request)
    }

    /// Loads an event for writing and checks the edit preconditions.
    private func writableEvent(
        _ id: UUID,
        expectedRevision: Int64?,
        in context: NSManagedObjectContext
    ) throws -> CDEvent {
        guard let event = try fetchEvent(id, in: context) else { throw RepositoryError.notFound }
        guard !event.isArchived else { throw RepositoryError.eventArchived }
        if let expectedRevision, event.revision != expectedRevision { throw RepositoryError.revisionConflict }
        return event
    }

    private func bump(_ event: CDEvent) {
        event.revision += 1
        event.updatedAt = clock.now()
    }

    private func saveIfNeeded(_ context: NSManagedObjectContext) throws {
        if context.hasChanges { try context.save() }
    }

    // MARK: - Reading

    func loadAll() async throws -> [EventAggregate] {
        try await perform { context in
            let result = try self.fetchAllEvents(in: context).map(CoreDataMapping.aggregate)
            context.reset()
            return result
        }
    }

    func load(eventID: UUID) async throws -> EventAggregate? {
        try await perform { context in
            let result = try self.fetchEvent(eventID, in: context).map(CoreDataMapping.aggregate)
            context.reset()
            return result
        }
    }

    func counts() async throws -> DataCounts {
        try await perform { context in
            func count(_ entity: String) throws -> Int {
                try context.count(for: NSFetchRequest<NSFetchRequestResult>(entityName: entity))
            }
            return DataCounts(
                events: try count("CDEvent"),
                people: try count("CDPerson"),
                expenses: try count("CDExpense"),
                payments: try count("CDPayment")
            )
        }
    }

    // MARK: - Events

    func createEvent(_ event: Event, people: [Person]) async throws -> WriteOutcome {
        let outcome: WriteOutcome = try await perform { context in
            if try self.fetchEvent(event.id, in: context) != nil { return .alreadyApplied }
            CoreDataMapping.insert(EventAggregate(event: event, people: people, expenses: [], payments: []), into: context)
            try self.saveIfNeeded(context)
            return .applied
        }
        notify(.event(event.id))
        return outcome
    }

    func updateEvent(id: UUID, name: String, date: CalendarDate, currency: CurrencyCode, note: String?, expectedRevision: Int64) async throws {
        try await perform { context in
            let event = try self.writableEvent(id, expectedRevision: expectedRevision, in: context)
            if event.currencyCode != currency.code {
                // Currency stays locked forever once an expense was saved, even if all were deleted.
                guard !event.currencyLocked && event.expenses.isEmpty else { throw RepositoryError.currencyLocked }
                event.currencyCode = currency.code
                event.currencyScale = Int16(currency.scale)
            }
            event.name = name
            event.eventDate = date.isoString
            event.note = note
            self.bump(event)
            try self.saveIfNeeded(context)
        }
        notify(.event(id))
    }

    func setArchived(eventID: UUID, archived: Bool) async throws {
        try await perform { context in
            guard let event = try self.fetchEvent(eventID, in: context) else { throw RepositoryError.notFound }
            guard event.isArchived != archived else { return }
            event.isArchived = archived
            self.bump(event)
            try self.saveIfNeeded(context)
        }
        notify(.event(eventID))
    }

    func deleteEvent(eventID: UUID) async throws {
        try await perform { context in
            guard let event = try self.fetchEvent(eventID, in: context) else { return }
            context.delete(event)
            try self.saveIfNeeded(context)
        }
        notify(.event(eventID))
    }

    // MARK: - People

    func savePerson(_ person: Person, expectedRevision: Int64) async throws {
        try await perform { context in
            let event = try self.writableEvent(person.eventID, expectedRevision: expectedRevision, in: context)
            let key = TextRules.nameKey(person.name)
            if event.people.contains(where: { $0.id != person.id && TextRules.nameKey($0.name) == key }) {
                throw RepositoryError.duplicatePersonName
            }
            if let existing = event.people.first(where: { $0.id == person.id }) {
                existing.name = person.name
                existing.avatarColorKey = person.avatarColor.rawValue
                existing.updatedAt = person.updatedAt
            } else {
                guard event.people.count < DomainLimits.maxPeoplePerEvent else {
                    throw RepositoryError.limitReached("An event can have up to \(DomainLimits.maxPeoplePerEvent) people.")
                }
                CoreDataMapping.insert(person, into: event, context: context)
            }
            self.bump(event)
            try self.saveIfNeeded(context)
        }
        notify(.event(person.eventID))
    }

    func deletePerson(personID: UUID, eventID: UUID, expectedRevision: Int64) async throws {
        try await perform { context in
            let event = try self.writableEvent(eventID, expectedRevision: expectedRevision, in: context)
            guard let person = event.people.first(where: { $0.id == personID }) else { throw RepositoryError.notFound }
            let linkedToExpense = event.expenses.contains { expense in
                expense.payerID == personID
                    || expense.shares.contains { $0.personID == personID }
                    || expense.items.contains { item in item.shares.contains { $0.personID == personID } }
            }
            let linkedToPayment = event.payments.contains { $0.fromID == personID || $0.toID == personID }
            guard !linkedToExpense && !linkedToPayment else { throw RepositoryError.personLinked }
            context.delete(person)
            self.bump(event)
            try self.saveIfNeeded(context)
        }
        notify(.event(eventID))
    }

    // MARK: - Expenses

    func saveExpense(_ expense: Expense, operationID: UUID, expectedRevision: Int64) async throws -> WriteOutcome {
        let outcome: WriteOutcome = try await perform { context in
            guard let event = try self.fetchEvent(expense.eventID, in: context) else { throw RepositoryError.notFound }
            let existing = event.expenses.first { $0.id == expense.id }
            if let existing, existing.operationID == operationID { return .alreadyApplied }
            guard !event.isArchived else { throw RepositoryError.eventArchived }
            guard event.revision == expectedRevision else { throw RepositoryError.revisionConflict }

            let peopleIDs = Set(event.people.map(\.id))
            guard expense.referencedPersonIDs.isSubset(of: peopleIDs) else { throw RepositoryError.invalidReference }
            guard expense.totalAllocatedMinor == expense.amountMinor,
                  expense.amountMinor > 0, expense.amountMinor <= DomainLimits.maxExpenseMinor
            else { throw RepositoryError.storageFailure }

            let object: CDExpense
            if let existing {
                object = existing
            } else {
                guard event.expenses.count < DomainLimits.maxExpensesPerEvent else {
                    throw RepositoryError.limitReached("This event has reached the limit of \(DomainLimits.maxExpensesPerEvent) expenses.")
                }
                object = CDExpense(context: context)
                object.id = expense.id
                object.createdAt = expense.createdAt
                object.event = event
            }
            CoreDataMapping.apply(expense, to: object, context: context)
            object.operationID = operationID
            event.currencyLocked = true
            self.bump(event)
            try self.saveIfNeeded(context)
            return .applied
        }
        notify(.event(expense.eventID))
        return outcome
    }

    func deleteExpense(expenseID: UUID, eventID: UUID, expectedRevision: Int64) async throws {
        try await perform { context in
            guard let event = try self.fetchEvent(eventID, in: context) else { throw RepositoryError.notFound }
            // Already gone (e.g. a retry after an uncertain result): nothing to do.
            guard let expense = event.expenses.first(where: { $0.id == expenseID }) else { return }
            guard !event.isArchived else { throw RepositoryError.eventArchived }
            guard event.revision == expectedRevision else { throw RepositoryError.revisionConflict }
            context.delete(expense)
            self.bump(event)
            try self.saveIfNeeded(context)
        }
        notify(.event(eventID))
    }

    // MARK: - Payments

    func recordPayment(_ payment: Payment, expectedRevision: Int64) async throws -> WriteOutcome {
        let outcome: WriteOutcome = try await perform { context in
            let duplicate = NSFetchRequest<CDPayment>(entityName: "CDPayment")
            duplicate.predicate = NSPredicate(format: "operationID == %@ OR id == %@", payment.operationID as CVarArg, payment.id as CVarArg)
            duplicate.fetchLimit = 1
            if try context.count(for: duplicate) > 0 { return .alreadyApplied }

            let event = try self.writableEvent(payment.eventID, expectedRevision: expectedRevision, in: context)
            let peopleIDs = Set(event.people.map(\.id))
            guard peopleIDs.contains(payment.fromID), peopleIDs.contains(payment.toID), payment.fromID != payment.toID else {
                throw RepositoryError.invalidReference
            }
            guard payment.amountMinor > 0, payment.amountMinor <= DomainLimits.maxPaymentMinor else {
                throw RepositoryError.storageFailure
            }
            guard event.payments.count < DomainLimits.maxPaymentsPerEvent else {
                throw RepositoryError.limitReached("This event has reached the limit of \(DomainLimits.maxPaymentsPerEvent) payment records.")
            }
            CoreDataMapping.insert(payment, into: event, context: context)
            self.bump(event)
            try self.saveIfNeeded(context)
            return .applied
        }
        notify(.event(payment.eventID))
        return outcome
    }

    func deletePayment(paymentID: UUID, eventID: UUID, expectedRevision: Int64) async throws {
        try await perform { context in
            guard let event = try self.fetchEvent(eventID, in: context) else { throw RepositoryError.notFound }
            guard let payment = event.payments.first(where: { $0.id == paymentID }) else { return }
            guard !event.isArchived else { throw RepositoryError.eventArchived }
            guard event.revision == expectedRevision else { throw RepositoryError.revisionConflict }
            context.delete(payment)
            self.bump(event)
            try self.saveIfNeeded(context)
        }
        notify(.event(eventID))
    }

    // MARK: - Demo, import, reset

    func insertDemo(_ aggregate: EventAggregate) async throws -> WriteOutcome {
        let outcome: WriteOutcome = try await perform { context in
            if try self.fetchEvent(aggregate.event.id, in: context) != nil { return .alreadyApplied }
            CoreDataMapping.insert(aggregate, into: context)
            try self.saveIfNeeded(context)
            return .applied
        }
        notify(.all)
        return outcome
    }

    func deleteDemoEvents() async throws -> Int {
        let removed: Int = try await perform { context in
            let request = NSFetchRequest<CDEvent>(entityName: "CDEvent")
            request.predicate = NSPredicate(format: "isDemo == YES")
            let demos = try context.fetch(request)
            demos.forEach(context.delete)
            try self.saveIfNeeded(context)
            return demos.count
        }
        notify(.all)
        return removed
    }

    func replaceAll(with aggregates: [EventAggregate]) async throws {
        try await perform { context in
            try self.fetchAllEvents(in: context).forEach(context.delete)
            for aggregate in aggregates {
                CoreDataMapping.insert(aggregate, into: context)
            }
            // One save: either the whole backup is in place or the old data stays untouched.
            try self.saveIfNeeded(context)
            context.reset()
        }
        notify(.all)
    }

    func deleteAll() async throws {
        try await perform { context in
            try self.fetchAllEvents(in: context).forEach(context.delete)
            try self.saveIfNeeded(context)
            context.reset()
        }
        notify(.all)
    }
}
