import XCTest
@testable import EvenCircle

/// Runs the real Core Data stack against an in-memory SQLite store (same constraints as on disk).
final class RepositoryTests: XCTestCase {
    private var stack: CoreDataStack!
    private var repository: CoreDataEventRepository!
    private var events: EventUseCases!
    private var people: PeopleUseCases!
    private var expenses: ExpenseUseCases!
    private var payments: PaymentUseCases!
    private var demo: DemoUseCases!

    override func setUpWithError() throws {
        stack = CoreDataStack(location: .inMemory)
        try stack.load()
        repository = CoreDataEventRepository(stack: stack, clock: Fixtures.clock)
        events = EventUseCases(repository: repository, clock: Fixtures.clock)
        people = PeopleUseCases(repository: repository, clock: Fixtures.clock)
        expenses = ExpenseUseCases(repository: repository, clock: Fixtures.clock)
        payments = PaymentUseCases(repository: repository, clock: Fixtures.clock)
        demo = DemoUseCases(repository: repository, clock: Fixtures.clock)
    }

    private func makeEvent(currency: CurrencyCode = .eur, names: [String] = ["Alex", "Bea", "Chris"]) async throws -> EventAggregate {
        let id = UUID()
        try await events.createEvent(
            id: id,
            form: EventForm(name: "Trip", date: Fixtures.today, currency: currency, note: nil),
            people: names.map { PersonTemplate(name: $0, avatarColor: .blue) }
        )
        return try await XCTUnwrapAsync(try await events.loadAggregate(id: id))
    }

    private func saveEqual(_ amount: Int64, payer: Int, in aggregate: EventAggregate, participants: [Int]? = nil) async throws -> Expense {
        let ids = aggregate.orderedPeople.map(\.id)
        let chosen = (participants ?? Array(ids.indices)).map { ids[$0] }
        let draft = ExpenseDraft(id: UUID(), eventID: aggregate.event.id, title: "Dinner", amountMinor: amount, payerID: ids[payer],
                                 date: Fixtures.today, note: nil, method: .equal,
                                 participants: Dictionary(uniqueKeysWithValues: chosen.map { ($0, 1) }), items: [], createdAt: nil, revision: 0)
        let expense = try expenses.build(draft, in: aggregate).get()
        _ = try await expenses.save(expense, operationID: UUID(), expectedRevision: aggregate.event.revision)
        return expense
    }

    func testCreateEventIsIdempotentAndStartsEmpty() async throws {
        let id = UUID()
        let form = EventForm(name: "Dinner", date: Fixtures.today, currency: .usd, note: nil)
        let first = try await events.createEvent(id: id, form: form, people: [])
        let second = try await events.createEvent(id: id, form: form, people: [])
        XCTAssertEqual(first, .applied)
        XCTAssertEqual(second, .alreadyApplied)
        let all = try await repository.loadAll()
        XCTAssertEqual(all.count, 1)
        XCTAssertTrue(all[0].expenses.isEmpty && all[0].payments.isEmpty)
    }

    func testDuplicateNamesAreRejectedIgnoringCaseAndSpaces() async throws {
        let aggregate = try await makeEvent(names: ["Alex"])
        do {
            try await people.addPerson(name: "  aLeX ", color: .mint, to: aggregate)
            XCTFail("Duplicate accepted")
        } catch {}
        try await people.addPerson(name: "Alex  Smith", color: .mint, to: aggregate)
        let fresh = try await XCTUnwrapAsync(try await events.loadAggregate(id: aggregate.id))
        XCTAssertEqual(fresh.people.map(\.name).sorted(), ["Alex", "Alex Smith"])
    }

    func testCurrencyLocksAfterFirstExpenseEvenWhenAllAreDeleted() async throws {
        var aggregate = try await makeEvent()
        try await events.updateEvent(id: aggregate.id, form: EventForm(name: "Trip", date: Fixtures.today, currency: .gbp, note: nil),
                                     expectedRevision: aggregate.event.revision)
        aggregate = try await XCTUnwrapAsync(try await events.loadAggregate(id: aggregate.id))
        XCTAssertEqual(aggregate.event.currency, .gbp)

        let expense = try await saveEqual(1000, payer: 0, in: aggregate)
        aggregate = try await XCTUnwrapAsync(try await events.loadAggregate(id: aggregate.id))
        XCTAssertTrue(aggregate.event.currencyLocked)
        try await expenses.delete(expense.id, in: aggregate)
        aggregate = try await XCTUnwrapAsync(try await events.loadAggregate(id: aggregate.id))
        XCTAssertTrue(aggregate.expenses.isEmpty)
        XCTAssertTrue(aggregate.event.currencyLocked)

        do {
            try await events.updateEvent(id: aggregate.id, form: EventForm(name: "Trip", date: Fixtures.today, currency: .eur, note: nil),
                                         expectedRevision: aggregate.event.revision)
            XCTFail("Currency changed after lock")
        } catch {
            XCTAssertEqual(error as? RepositoryError, .currencyLocked)
        }
    }

    func testRecordPaymentTwiceWithSameOperationCreatesOneRecord() async throws {
        var aggregate = try await makeEvent()
        _ = try await saveEqual(9000, payer: 0, in: aggregate)
        aggregate = try await XCTUnwrapAsync(try await events.loadAggregate(id: aggregate.id))
        let ids = aggregate.orderedPeople.map(\.id)
        let draft = PaymentDraft(fromID: ids[1], toID: ids[0], amountMinor: 1000, date: Fixtures.today, note: nil, confirmedOutsideApp: true)
        let operation = UUID(), paymentID = UUID()
        let first = try await payments.record(draft, operationID: operation, paymentID: paymentID, aggregate: aggregate)
        // Retry with the stale snapshot, as after an uncertain result.
        let second = try await payments.record(draft, operationID: operation, paymentID: paymentID, aggregate: aggregate)
        XCTAssertEqual(first, .applied)
        XCTAssertEqual(second, .alreadyApplied)
        aggregate = try await XCTUnwrapAsync(try await events.loadAggregate(id: aggregate.id))
        XCTAssertEqual(aggregate.payments.count, 1)
        XCTAssertEqual(try Fixtures.netsInOrder(aggregate), [5000, -2000, -3000])
    }

    func testRevisionConflictIsDetected() async throws {
        let stale = try await makeEvent()
        _ = try await saveEqual(900, payer: 0, in: stale)
        // `stale` was loaded before the first save; its revision no longer matches the store.
        do {
            _ = try await saveEqual(300, payer: 1, in: stale)
            XCTFail("Stale revision accepted")
        } catch {
            XCTAssertEqual(error as? RepositoryError, .revisionConflict)
        }
        let fresh = try await XCTUnwrapAsync(try await events.loadAggregate(id: stale.id))
        XCTAssertEqual(fresh.expenses.count, 1, "The conflicting save wrote nothing")
    }

    func testSaveExpenseRetryIsIdempotentAndEditUpdatesInPlace() async throws {
        var aggregate = try await makeEvent()
        let ids = aggregate.orderedPeople.map(\.id)
        let draft = ExpenseDraft(id: UUID(), eventID: aggregate.id, title: "Taxi", amountMinor: 2400, payerID: ids[1], date: Fixtures.today,
                                 note: nil, method: .equal, participants: [ids[1]: 1, ids[2]: 1], items: [], createdAt: nil, revision: 0)
        let expense = try expenses.build(draft, in: aggregate).get()
        let operation = UUID()
        let outcomes = [
            try await expenses.save(expense, operationID: operation, expectedRevision: aggregate.event.revision),
            try await expenses.save(expense, operationID: operation, expectedRevision: aggregate.event.revision),
        ]
        XCTAssertEqual(outcomes, [.applied, .alreadyApplied])
        aggregate = try await XCTUnwrapAsync(try await events.loadAggregate(id: aggregate.id))
        XCTAssertEqual(aggregate.expenses.count, 1)

        // Edit: switch to Items, then back to Equal – no receipt lines may remain.
        var itemsDraft = draft
        itemsDraft.method = .items
        itemsDraft.amountMinor = nil
        itemsDraft.createdAt = expense.createdAt
        itemsDraft.revision = expense.revision
        itemsDraft.items = [.init(id: UUID(), title: "Ride", quantity: 2, unitPriceMinor: 1200, recipientIDs: [ids[0]])]
        let itemsExpense = try expenses.build(itemsDraft, in: aggregate).get()
        _ = try await expenses.save(itemsExpense, operationID: UUID(), expectedRevision: aggregate.event.revision)
        aggregate = try await XCTUnwrapAsync(try await events.loadAggregate(id: aggregate.id))
        XCTAssertEqual(aggregate.expenses.count, 1)
        XCTAssertEqual(aggregate.expenses[0].items.count, 1)
        XCTAssertEqual(aggregate.expenses[0].id, expense.id)

        var equalDraft = draft
        equalDraft.createdAt = expense.createdAt
        equalDraft.revision = aggregate.expenses[0].revision
        let back = try expenses.build(equalDraft, in: aggregate).get()
        _ = try await expenses.save(back, operationID: UUID(), expectedRevision: aggregate.event.revision)
        aggregate = try await XCTUnwrapAsync(try await events.loadAggregate(id: aggregate.id))
        XCTAssertTrue(aggregate.expenses[0].items.isEmpty)
        XCTAssertEqual(aggregate.expenses[0].method, .equal)
    }

    func testDeletingExpenseKeepsPayments() async throws {
        var aggregate = try await makeEvent()
        let expense = try await saveEqual(9000, payer: 0, in: aggregate)
        aggregate = try await XCTUnwrapAsync(try await events.loadAggregate(id: aggregate.id))
        let ids = aggregate.orderedPeople.map(\.id)
        _ = try await payments.record(
            PaymentDraft(fromID: ids[1], toID: ids[0], amountMinor: 1000, date: Fixtures.today, note: nil, confirmedOutsideApp: true),
            operationID: UUID(), paymentID: UUID(), aggregate: aggregate)
        aggregate = try await XCTUnwrapAsync(try await events.loadAggregate(id: aggregate.id))
        try await expenses.delete(expense.id, in: aggregate)
        aggregate = try await XCTUnwrapAsync(try await events.loadAggregate(id: aggregate.id))
        XCTAssertEqual(aggregate.payments.count, 1)
        XCTAssertEqual(try Fixtures.netsInOrder(aggregate), [-1000, 1000, 0])
    }

    func testDeletingPaymentDoesNotTouchExpenses() async throws {
        var aggregate = try await makeEvent()
        _ = try await saveEqual(900, payer: 0, in: aggregate)
        aggregate = try await XCTUnwrapAsync(try await events.loadAggregate(id: aggregate.id))
        let ids = aggregate.orderedPeople.map(\.id)
        let paymentID = UUID()
        _ = try await payments.record(
            PaymentDraft(fromID: ids[1], toID: ids[0], amountMinor: 300, date: Fixtures.today, note: nil, confirmedOutsideApp: true),
            operationID: UUID(), paymentID: paymentID, aggregate: aggregate)
        aggregate = try await XCTUnwrapAsync(try await events.loadAggregate(id: aggregate.id))
        let preview = try payments.previewDelete(paymentID, in: aggregate)
        XCTAssertEqual(preview.rows.map(\.afterMinor), [600, -300, -300])
        try await payments.delete(paymentID, in: aggregate)
        aggregate = try await XCTUnwrapAsync(try await events.loadAggregate(id: aggregate.id))
        XCTAssertTrue(aggregate.payments.isEmpty)
        XCTAssertEqual(aggregate.expenses.count, 1)
    }

    func testLinkedPersonCannotBeDeletedButUnlinkedCan() async throws {
        var aggregate = try await makeEvent(names: ["Alex", "Bea", "Chris"])
        _ = try await saveEqual(900, payer: 0, in: aggregate, participants: [0, 1])
        aggregate = try await XCTUnwrapAsync(try await events.loadAggregate(id: aggregate.id))
        let ids = aggregate.orderedPeople.map(\.id)
        do {
            try await people.deletePerson(ids[1], in: aggregate)
            XCTFail("Linked person deleted")
        } catch {
            XCTAssertEqual(error as? RepositoryError, .personLinked)
        }
        try await people.deletePerson(ids[2], in: aggregate)
        aggregate = try await XCTUnwrapAsync(try await events.loadAggregate(id: aggregate.id))
        XCTAssertEqual(aggregate.people.count, 2)
    }

    func testArchivedEventIsReadOnlyUntilRestore() async throws {
        var aggregate = try await makeEvent()
        _ = try await saveEqual(900, payer: 0, in: aggregate)
        try await events.setArchived(true, eventID: aggregate.id)
        aggregate = try await XCTUnwrapAsync(try await events.loadAggregate(id: aggregate.id))
        XCTAssertTrue(aggregate.event.isArchived)
        XCTAssertEqual(try BalanceCalculator.calculate(aggregate).outstandingMinor, 600, "Debts stay visible in the archive")
        do {
            _ = try await saveEqual(100, payer: 1, in: aggregate)
            XCTFail("Archived event accepted a change")
        } catch {
            XCTAssertEqual(error as? RepositoryError, .eventArchived)
        }
        try await events.setArchived(false, eventID: aggregate.id)
        aggregate = try await XCTUnwrapAsync(try await events.loadAggregate(id: aggregate.id))
        _ = try await saveEqual(100, payer: 1, in: aggregate)
    }

    func testDuplicateCopiesNamesOnlyWithNewIDs() async throws {
        var source = try await makeEvent()
        _ = try await saveEqual(900, payer: 0, in: source)
        source = try await XCTUnwrapAsync(try await events.loadAggregate(id: source.id))
        let template = events.duplicateTemplate(from: source)
        XCTAssertEqual(template.form.name, "Trip copy")
        XCTAssertEqual(template.form.date, Fixtures.today)
        let copyID = UUID()
        try await events.createEvent(id: copyID, form: template.form, people: template.people)
        let copy = try await XCTUnwrapAsync(try await events.loadAggregate(id: copyID))
        XCTAssertEqual(copy.orderedPeople.map(\.name), ["Alex", "Bea", "Chris"])
        XCTAssertTrue(Set(copy.people.map(\.id)).isDisjoint(with: Set(source.people.map(\.id))))
        XCTAssertTrue(copy.expenses.isEmpty && copy.payments.isEmpty)
        XCTAssertNil(copy.event.note)
        XCTAssertFalse(copy.event.currencyLocked)
    }

    func testDemoLoadsOnceAndRemovesOnlyDemo() async throws {
        _ = try await makeEvent()
        let firstLoad = try await demo.load()
        let secondLoad = try await demo.load()
        XCTAssertEqual(firstLoad, .applied)
        XCTAssertEqual(secondLoad, .alreadyApplied)
        var all = try await repository.loadAll()
        XCTAssertEqual(all.filter(\.event.isDemo).count, 1)
        let initialStatus = try await demo.status()
        XCTAssertFalse(initialStatus.isModified)

        let sample = try XCTUnwrap(all.first(where: \.event.isDemo))
        try await people.addPerson(name: "Dana", color: .amber, to: sample)
        let changedStatus = try await demo.status()
        XCTAssertTrue(changedStatus.isModified)

        let removed = try await demo.remove()
        XCTAssertEqual(removed, 1)
        all = try await repository.loadAll()
        XCTAssertEqual(all.count, 1)
        XCTAssertFalse(all[0].event.isDemo)
    }
}

extension Fixtures {
    /// Nets in the stable people order (Alex, Bea, Chris for events created in tests).
    static func netsInOrder(_ aggregate: EventAggregate) throws -> [Int64] {
        let balances = try BalanceCalculator.calculate(aggregate)
        return aggregate.orderedPeople.map { balances.net(for: $0.id) }
    }
}

func XCTUnwrapAsync<T>(_ expression: @autoclosure () async throws -> T?, file: StaticString = #filePath, line: UInt = #line) async throws -> T {
    let value = try await expression()
    return try XCTUnwrap(value, file: file, line: line)
}
