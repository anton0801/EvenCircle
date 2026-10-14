import XCTest
@testable import EvenCircle

final class ExpenseBuilderTests: XCTestCase {
    private let a = TestIDs.a, b = TestIDs.b, c = TestIDs.c
    private var people: Set<UUID> { [a, b, c] }

    private func draft(
        method: SplitMethod = .equal,
        amount: Int64? = 1000,
        payer: UUID? = TestIDs.a,
        participants: [UUID: Int] = [:],
        items: [ExpenseDraft.Item] = [],
        date: CalendarDate = Fixtures.today,
        title: String = "Dinner"
    ) -> ExpenseDraft {
        ExpenseDraft(id: UUID(), eventID: TestIDs.event, title: title, amountMinor: amount, payerID: payer, date: date,
                     note: nil, method: method, participants: participants, items: items, createdAt: nil, revision: 0)
    }

    private func build(_ draft: ExpenseDraft) -> Result<Expense, ExpenseDraftIssues> {
        ExpenseBuilder.build(draft, eventPeopleIDs: people, today: Fixtures.today, now: Fixtures.now)
    }

    func testEqualSplit() throws {
        let expense = try build(draft(participants: [a: 1, b: 1, c: 1])).get()
        XCTAssertEqual(expense.share(for: a)?.allocatedMinor, 334)
        XCTAssertEqual(expense.share(for: b)?.allocatedMinor, 333)
        XCTAssertEqual(expense.totalAllocatedMinor, 1000)
        XCTAssertTrue(expense.shares.allSatisfy { $0.weight == 1 })
    }

    func testEqualIgnoresWeightsKeptInTheForm() throws {
        let expense = try build(draft(method: .equal, participants: [a: 1, b: 2, c: 3])).get()
        XCTAssertTrue(expense.shares.allSatisfy { $0.weight == 1 })
        XCTAssertEqual(expense.share(for: a)?.allocatedMinor, 334)
    }

    func testSharesSplitAndInvalidWeights() throws {
        let expense = try build(draft(method: .shares, participants: [a: 1, b: 2, c: 3])).get()
        XCTAssertEqual(expense.shares.map(\.allocatedMinor).sorted(), [167, 333, 500])
        XCTAssertEqual(expense.share(for: c)?.weight, 3)

        for bad in [0, -1, 1001] {
            guard case .failure(let failure) = build(draft(method: .shares, participants: [a: bad, b: 1])) else {
                return XCTFail("Weight \(bad) must be rejected")
            }
            XCTAssertNotNil(failure.message(for: .weight(a)))
        }
    }

    func testValidationErrors() {
        guard case .failure(let failure) = build(draft(amount: 0, payer: nil, participants: [:], date: Fixtures.today.adding(days: 1), title: "  ")) else {
            return XCTFail("Expected failure")
        }
        XCTAssertNotNil(failure.message(for: .title))
        XCTAssertNotNil(failure.message(for: .amount))
        XCTAssertNotNil(failure.message(for: .payer))
        XCTAssertNotNil(failure.message(for: .date))
        XCTAssertNotNil(failure.message(for: .participants))
    }

    func testPayerNeedNotBeARecipientAndSingleRecipientIsAllowed() throws {
        let expense = try build(draft(amount: 2000, payer: a, participants: [b: 1])).get()
        XCTAssertEqual(expense.shares, [ExpenseShare(personID: b, allocatedMinor: 2000, weight: 1)])
    }

    func testItemsSplit() throws {
        let first = UUID(), second = UUID()
        let expense = try build(draft(method: .items, amount: nil, items: [
            .init(id: first, title: "Pizza", quantity: 1, unitPriceMinor: 1000, recipientIDs: [a, b, c]),
            .init(id: second, title: "Wine", quantity: 1, unitPriceMinor: 500, recipientIDs: [b, c]),
        ])).get()
        XCTAssertEqual(expense.amountMinor, 1500)
        XCTAssertEqual(expense.share(for: a)?.allocatedMinor, 334)
        XCTAssertEqual(expense.share(for: b)?.allocatedMinor, 583)
        XCTAssertEqual(expense.share(for: c)?.allocatedMinor, 583)
        XCTAssertEqual(expense.items.count, 2)
        XCTAssertTrue(expense.shares.allSatisfy { $0.weight == nil })
    }

    func testItemWithoutRecipientsBlocksSave() {
        let item = UUID()
        guard case .failure(let failure) = build(draft(method: .items, amount: nil, items: [
            .init(id: item, title: "Tip", quantity: 1, unitPriceMinor: 300, recipientIDs: []),
        ])) else { return XCTFail("Expected failure") }
        XCTAssertNotNil(failure.message(for: .item(item)))
    }

    func testZeroShareRecipientIsKept() throws {
        let expense = try ExpenseBuilder.build(
            ExpenseDraft(id: UUID(), eventID: TestIDs.event, title: "Candy", amountMinor: 1, payerID: a, date: Fixtures.today,
                         note: nil, method: .equal, participants: [a: 1, b: 1, c: 1], items: [], createdAt: nil, revision: 0),
            eventPeopleIDs: people, today: Fixtures.today, now: Fixtures.now
        ).get()
        XCTAssertEqual(expense.shares.count, 3)
        XCTAssertEqual(expense.share(for: c)?.allocatedMinor, 0)
    }

    func testRebuildingIsDeterministic() throws {
        let d = draft(method: .shares, amount: 99_997, participants: [a: 7, b: 3, c: 11])
        XCTAssertEqual(try build(d).get().shares, try build(d).get().shares)
    }
}
