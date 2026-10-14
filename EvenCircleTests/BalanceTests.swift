import XCTest
@testable import EvenCircle

final class BalanceTests: XCTestCase {
    private let a = TestIDs.a, b = TestIDs.b, c = TestIDs.c

    func testPayerCoversSomeoneElseEntirely() throws {
        let expense = Fixtures.equalExpense(amount: 2000, payer: a, participants: [b])
        let nets = try Fixtures.nets(Fixtures.aggregate(expenses: [expense]))
        XCTAssertEqual(nets, [2000, -2000, 0])
    }

    func testSection76ExampleSequence() throws {
        let dinnerID = UUID()
        let dinner = Fixtures.equalExpense(id: dinnerID, amount: 9000, payer: a, participants: [a, b, c])
        var aggregate = Fixtures.aggregate(expenses: [dinner])
        XCTAssertEqual(try Fixtures.nets(aggregate), [6000, -3000, -3000])

        aggregate = aggregate.addingPayment(Fixtures.payment(from: b, to: a, amount: 1000))
        XCTAssertEqual(try Fixtures.nets(aggregate), [5000, -2000, -3000])

        // Correcting the expense keeps the recorded payment.
        let corrected = Fixtures.equalExpense(id: dinnerID, amount: 6000, payer: a, participants: [a, b, c])
        let afterEdit = aggregate.replacingExpense(corrected)
        XCTAssertEqual(try Fixtures.nets(afterEdit), [3000, -1000, -2000])
        XCTAssertEqual(afterEdit.payments.count, 1)

        // Deleting the expense entirely: the payment remains a real fact.
        let afterDelete = aggregate.removingExpense(dinnerID)
        XCTAssertEqual(try Fixtures.nets(afterDelete), [-1000, 1000, 0])
        let balances = try BalanceCalculator.calculate(afterDelete)
        XCTAssertEqual(balances.status, .openBalance)
        XCTAssertEqual(balances.totalExpensesMinor, 0)
        XCTAssertEqual(balances.recordedPaymentsMinor, 1000)
    }

    func testDemoEventBalances() throws {
        var demo = DemoEventFactory.make(today: Fixtures.today, now: Fixtures.now)
        let alex = DemoEventFactory.alexID, bea = DemoEventFactory.beaID, chris = DemoEventFactory.chrisID
        var balances = try BalanceCalculator.calculate(demo)
        XCTAssertEqual([balances.net(for: alex), balances.net(for: bea), balances.net(for: chris)], [4400, -800, -3600])
        XCTAssertEqual(balances.totalExpensesMinor, 12_600)

        demo.payments = []
        balances = try BalanceCalculator.calculate(demo)
        XCTAssertEqual([balances.net(for: alex), balances.net(for: bea), balances.net(for: chris)], [5400, -1800, -3600])
        XCTAssertTrue(demo.event.isDemo)
        XCTAssertFalse(demo.expenses.contains { $0.expenseDate > Fixtures.today }, "Demo dates are never in the future")
    }

    func testStatusesAndTotals() throws {
        XCTAssertEqual(try BalanceCalculator.calculate(Fixtures.aggregate()).status, .noExpenses)

        let expense = Fixtures.equalExpense(amount: 900, payer: a, participants: [a, b, c])
        let open = Fixtures.aggregate(expenses: [expense])
        let openBalances = try BalanceCalculator.calculate(open)
        XCTAssertEqual(openBalances.status, .openBalance)
        XCTAssertEqual(openBalances.outstandingMinor, 600)

        let settled = open
            .addingPayment(Fixtures.payment(from: b, to: a, amount: 300))
            .addingPayment(Fixtures.payment(from: c, to: a, amount: 300))
        let settledBalances = try BalanceCalculator.calculate(settled)
        XCTAssertEqual(settledBalances.status, .settled)
        XCTAssertEqual(settledBalances.outstandingMinor, 0)
        XCTAssertEqual(settledBalances.totalExpensesMinor, 900, "Payments are never part of Total Expenses")
        XCTAssertEqual(settledBalances.recordedPaymentsMinor, 600)
    }

    func testNetAlwaysSumsToZeroForRandomHistories() throws {
        for _ in 0..<200 {
            var expenses: [Expense] = []
            for _ in 0..<Int.random(in: 1...20) {
                let participants = [a, b, c].filter { _ in Bool.random() }
                expenses.append(Fixtures.equalExpense(amount: .random(in: 1...999_999), payer: [a, b, c].randomElement()!,
                                                      participants: participants.isEmpty ? [a] : participants))
            }
            let payments = (0..<Int.random(in: 0...5)).map { _ in Fixtures.payment(from: b, to: c, amount: .random(in: 1...5000)) }
            let balances = try BalanceCalculator.calculate(Fixtures.aggregate(expenses: expenses, payments: payments))
            XCTAssertEqual(balances.people.map(\.netMinor).reduce(0, +), 0)
            XCTAssertEqual(balances.outstandingMinor, balances.people.map { max(-$0.netMinor, 0) }.reduce(0, +))
        }
    }

    func testRenamingAndRecolouringDoesNotChangeBalances() throws {
        let expense = Fixtures.equalExpense(amount: 1000, payer: a, participants: [a, b, c])
        let original = Fixtures.aggregate(expenses: [expense])
        var renamed = original
        renamed.people[0].name = "Zed"
        renamed.people[1].avatarColor = .coral
        renamed.people.reverse()
        XCTAssertEqual(try Fixtures.nets(original), try Fixtures.nets(renamed))
    }

    func testBalanceChangePreview() throws {
        let expenseID = UUID()
        let aggregate = Fixtures.aggregate(
            expenses: [Fixtures.equalExpense(id: expenseID, amount: 9000, payer: a, participants: [a, b, c])],
            payments: [Fixtures.payment(from: b, to: a, amount: 1000)]
        )
        let preview = try BalanceChangePreview.make(before: aggregate, after: aggregate.removingExpense(expenseID))
        XCTAssertEqual(preview.rows.map(\.beforeMinor), [5000, -2000, -3000])
        XCTAssertEqual(preview.rows.map(\.afterMinor), [-1000, 1000, 0])
        XCTAssertTrue(preview.rows[0].directionChanged)
        XCTAssertEqual(preview.basedOnRevision, aggregate.event.revision)
    }
}

final class SuggestionTests: XCTestCase {
    private let a = TestIDs.a, b = TestIDs.b, c = TestIDs.c, d = TestIDs.d

    private func balance(_ id: UUID, _ net: Int64) -> PersonBalance {
        PersonBalance(personID: id, paidMinor: 0, owedMinor: 0, sentMinor: 0, receivedMinor: 0, netMinor: net)
    }

    func testDemoSuggestions() {
        let plan = PaymentSuggestionBuilder.build(from: [balance(a, 4400), balance(b, -800), balance(c, -3600)])
        XCTAssertEqual(plan, [
            SuggestedPayment(fromID: c, toID: a, amountMinor: 3600),
            SuggestedPayment(fromID: b, toID: a, amountMinor: 800),
        ])
    }

    func testTieBreakByUUID() {
        let plan = PaymentSuggestionBuilder.build(from: [balance(c, -500), balance(b, -500), balance(d, 500), balance(a, 500)])
        XCTAssertEqual(plan.first, SuggestedPayment(fromID: b, toID: a, amountMinor: 500))
        XCTAssertEqual(plan.last, SuggestedPayment(fromID: c, toID: d, amountMinor: 500))
    }

    func testNoSuggestionsWhenSettled() {
        XCTAssertTrue(PaymentSuggestionBuilder.build(from: [balance(a, 0), balance(b, 0)]).isEmpty)
    }

    /// Checks properties, not a promised transfer count: positive amounts, debtor → creditor,
    /// determinism, and that applying the plan closes every balance.
    func testPlanPropertiesOnRandomBalances() {
        for _ in 0..<300 {
            let ids = (0..<Int.random(in: 2...12)).map { _ in UUID() }
            var nets = ids.dropLast().map { _ in Int64.random(in: -100_000...100_000) }
            nets.append(-nets.reduce(0, +))
            let balances = zip(ids, nets).map { balance($0, $1) }
            let plan = PaymentSuggestionBuilder.build(from: balances)

            XCTAssertEqual(plan, PaymentSuggestionBuilder.build(from: balances), "Deterministic")
            XCTAssertEqual(plan, PaymentSuggestionBuilder.build(from: balances.reversed()), "Independent of input order")
            var remaining = Dictionary(uniqueKeysWithValues: zip(ids, nets))
            for step in plan {
                XCTAssertGreaterThan(step.amountMinor, 0)
                XCTAssertNotEqual(step.fromID, step.toID)
                XCTAssertLessThan(remaining[step.fromID]!, 0, "Sender must currently owe")
                XCTAssertGreaterThan(remaining[step.toID]!, 0, "Recipient must currently be owed")
                remaining[step.fromID]! += step.amountMinor
                remaining[step.toID]! -= step.amountMinor
            }
            XCTAssertTrue(remaining.values.allSatisfy { $0 == 0 }, "Plan closes all balances")
        }
    }
}

final class PaymentRulesTests: XCTestCase {
    private let a = TestIDs.a, b = TestIDs.b, c = TestIDs.c

    private var aggregate: EventAggregate {
        Fixtures.aggregate(expenses: [Fixtures.equalExpense(amount: 9000, payer: a, participants: [a, b, c])])
    }

    private func draft(from: UUID?, to: UUID?, amount: Int64?, date: CalendarDate = Fixtures.today, confirmed: Bool = true) -> PaymentDraft {
        PaymentDraft(fromID: from, toID: to, amountMinor: amount, date: date, note: nil, confirmedOutsideApp: confirmed)
    }

    private func issues(_ draft: PaymentDraft) throws -> [PaymentDraftField: String] {
        PaymentRules.validate(draft, aggregate: aggregate, balances: try BalanceCalculator.calculate(aggregate), today: Fixtures.today)
    }

    func testMaximumIsMinOfDebtAndCredit() throws {
        let balances = try BalanceCalculator.calculate(aggregate)
        XCTAssertEqual(PaymentRules.maximum(fromID: b, toID: a, balances: balances), 3000)
        XCTAssertNil(PaymentRules.maximum(fromID: a, toID: b, balances: balances))
        XCTAssertNil(PaymentRules.maximum(fromID: b, toID: c, balances: balances))
    }

    func testPartialPaymentIsValidAndReducesDebt() throws {
        XCTAssertTrue(try issues(draft(from: b, to: a, amount: 1000)).isEmpty)
        let after = aggregate.addingPayment(Fixtures.payment(from: b, to: a, amount: 1000))
        XCTAssertEqual(try Fixtures.nets(after), [5000, -2000, -3000])
    }

    func testRejectsOverpaymentSameSidesFutureDateAndMissingConfirmation() throws {
        XCTAssertNotNil(try issues(draft(from: b, to: a, amount: 3001))[.amount])
        XCTAssertNotNil(try issues(draft(from: b, to: b, amount: 100))[.to])
        XCTAssertNotNil(try issues(draft(from: b, to: a, amount: 100, date: Fixtures.today.adding(days: 1)))[.date])
        XCTAssertNotNil(try issues(draft(from: b, to: a, amount: 100, confirmed: false))[.confirmation])
        XCTAssertNotNil(try issues(draft(from: b, to: a, amount: 0))[.amount])
        XCTAssertNotNil(try issues(draft(from: nil, to: a, amount: 10))[.from])
    }
}
