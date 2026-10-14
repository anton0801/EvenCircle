import XCTest
@testable import EvenCircle

final class BackupTests: XCTestCase {
    private let codec = JSONBackupCodec()
    private let a = TestIDs.a, b = TestIDs.b, c = TestIDs.c

    /// Sample with every feature: Equal, Shares, Items with a zero-share recipient, a payment and a demo event.
    private func richData() throws -> [EventAggregate] {
        let people = Set([a, b, c])
        func build(_ draft: ExpenseDraft) throws -> Expense {
            try ExpenseBuilder.build(draft, eventPeopleIDs: people, today: Fixtures.today, now: Fixtures.now).get()
        }
        let equal = try build(ExpenseDraft(id: UUID(), eventID: TestIDs.event, title: "Dinner", amountMinor: 1000, payerID: a,
                                           date: Fixtures.today, note: "Window table", method: .equal, participants: [a: 1, b: 1, c: 1],
                                           items: [], createdAt: nil, revision: 0))
        let shares = try build(ExpenseDraft(id: UUID(), eventID: TestIDs.event, title: "Cabin", amountMinor: 999_999_999, payerID: b,
                                            date: Fixtures.today, note: nil, method: .shares, participants: [a: 1, b: 2, c: 3],
                                            items: [], createdAt: nil, revision: 0))
        let items = try build(ExpenseDraft(id: UUID(), eventID: TestIDs.event, title: "Snacks", amountMinor: nil, payerID: c,
                                           date: Fixtures.today, note: nil, method: .items, participants: [:],
                                           items: [.init(id: UUID(), title: "Gum", quantity: 1, unitPriceMinor: 1, recipientIDs: [c, b, a]),
                                                   .init(id: UUID(), title: "Chips", quantity: 3, unitPriceMinor: 250, recipientIDs: [b])],
                                           createdAt: nil, revision: 0))
        var event = Fixtures.event()
        event.currencyLocked = true
        event.isArchived = true
        let main = EventAggregate(event: event, people: Fixtures.threePeople(), expenses: [equal, shares, items],
                                  payments: [Fixtures.payment(from: c, to: a, amount: 123)])
        return [main, DemoEventFactory.make(today: Fixtures.today, now: Fixtures.now)]
    }

    private func normalized(_ aggregates: [EventAggregate]) -> [String] {
        // Compares everything except sub-millisecond timestamp precision.
        aggregates.sorted { $0.id.uuidString < $1.id.uuidString }.map { aggregate in
            var copy = aggregate
            copy.event.createdAt = Date(timeIntervalSince1970: 0)
            copy.event.updatedAt = Date(timeIntervalSince1970: 0)
            copy.people = copy.people.map { var p = $0; p.createdAt = .distantPast; p.updatedAt = .distantPast; return p }
                .sorted { $0.id.uuidString < $1.id.uuidString }
            copy.expenses = copy.expenses.map { var e = $0; e.createdAt = .distantPast; e.updatedAt = .distantPast; return e }
                .sorted { $0.id.uuidString < $1.id.uuidString }
            copy.payments = copy.payments.map { var p = $0; p.createdAt = .distantPast; return p }
            return String(describing: copy)
        }
    }

    func testRoundTripPreservesEverythingExactly() throws {
        let original = try richData()
        let data = try codec.encode(original, exportedAt: Fixtures.now)
        let restored = try codec.decodeAndValidate(data)

        XCTAssertEqual(normalized(restored.aggregates), normalized(original))
        XCTAssertEqual(restored.preview.schemaVersion, 1)
        XCTAssertEqual(restored.preview.counts, DataCounts(events: 2, people: 6, expenses: 6, payments: 2))
        XCTAssertTrue(restored.preview.containsDemo)

        let main = try XCTUnwrap(restored.aggregates.first { !$0.event.isDemo })
        XCTAssertTrue(main.event.isArchived)
        let cabin = try XCTUnwrap(main.expenses.first { $0.title == "Cabin" })
        XCTAssertEqual(cabin.amountMinor, 999_999_999)
        let gum = try XCTUnwrap(main.expenses.first { $0.title == "Snacks" }?.items.first { $0.title == "Gum" })
        XCTAssertEqual(gum.shares.count, 3, "Recipients with a zero share are preserved")
        XCTAssertEqual(gum.shares.filter { $0.allocatedMinor == 0 }.count, 2)
        for aggregate in restored.aggregates {
            XCTAssertEqual(try BalanceCalculator.calculate(aggregate).people.map(\.netMinor).reduce(0, +), 0)
        }
    }

    func testMoneyIsStoredAsIntegers() throws {
        let data = try codec.encode(try richData(), exportedAt: Fixtures.now)
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(text.contains("\"amountMinor\" : 999999999"))
        XCTAssertFalse(text.contains("9999999.99"))
    }

    private func mutate(_ change: (inout [String: Any]) -> Void) throws -> Data {
        let data = try codec.encode(try richData(), exportedAt: Fixtures.now)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        change(&json)
        return try JSONSerialization.data(withJSONObject: json)
    }

    private func firstExpense(_ json: inout [String: Any], _ change: (inout [String: Any]) -> Void) {
        var events = json["events"] as! [[String: Any]]
        var expenses = events[0]["expenses"] as! [[String: Any]]
        change(&expenses[0])
        events[0]["expenses"] = expenses
        json["events"] = events
    }

    private func assertRejected(_ data: Data, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try codec.decodeAndValidate(data), file: file, line: line) { error in
            XCTAssertTrue(error is BackupValidationError, "\(error)", file: file, line: line)
        }
    }

    func testRejectsUnknownSchema() throws {
        let data = try mutate { $0["schemaVersion"] = 2 }
        XCTAssertThrowsError(try codec.decodeAndValidate(data)) { error in
            XCTAssertTrue((error as? BackupValidationError)?.message.contains("version 2") == true)
        }
    }

    func testRejectsGarbageAndOversizedFiles() {
        assertRejected(Data("not json".utf8))
        assertRejected(Data([0xFF, 0xFE, 0x00]))
        assertRejected(Data(count: DomainLimits.backupMaxBytes + 1))
    }

    func testRejectsBrokenReferences() throws {
        assertRejected(try mutate { json in firstExpense(&json) { $0["payerID"] = UUID().uuidString } })
        assertRejected(try mutate { json in
            var events = json["events"] as! [[String: Any]]
            var payments = events[0]["payments"] as! [[String: Any]]
            payments[0]["toID"] = payments[0]["fromID"]
            events[0]["payments"] = payments
            json["events"] = events
        })
    }

    func testRejectsAllocationMismatch() throws {
        assertRejected(try mutate { json in
            firstExpense(&json) { expense in
                var shares = expense["shares"] as! [[String: Any]]
                // Same total, but not what the largest remainder method produces.
                let first = shares[0]["allocatedMinor"] as! Int
                let second = shares[1]["allocatedMinor"] as! Int
                shares[0]["allocatedMinor"] = second
                shares[1]["allocatedMinor"] = first
                if first == second {
                    shares[0]["allocatedMinor"] = first + 1
                    shares[1]["allocatedMinor"] = second - 1
                }
                expense["shares"] = shares
            }
        })
        assertRejected(try mutate { json in firstExpense(&json) { $0["amountMinor"] = 1001 } })
    }

    func testRejectsDuplicateIDsAndBadCurrency() throws {
        assertRejected(try mutate { json in
            var events = json["events"] as! [[String: Any]]
            events[1]["id"] = events[0]["id"]
            json["events"] = events
        })
        assertRejected(try mutate { json in
            var events = json["events"] as! [[String: Any]]
            events[0]["currencyCode"] = "BTC"
            json["events"] = events
        })
    }

    /// A payment recorded before an expense correction stays valid even if the debt direction flipped.
    func testHistoricalPaymentSurvivesAfterExpenseCorrection() throws {
        let dinner = Fixtures.equalExpense(amount: 9000, payer: a, participants: [a, b, c])
        var aggregate = Fixtures.aggregate(expenses: [dinner], payments: [Fixtures.payment(from: b, to: a, amount: 3000)])
        aggregate.expenses = [Fixtures.equalExpense(id: dinner.id, amount: 300, payer: a, participants: [a, b, c])]
        XCTAssertEqual(try Fixtures.nets(aggregate), [-2800, 2900, -100])

        let restored = try codec.decodeAndValidate(try codec.encode([aggregate], exportedAt: Fixtures.now))
        XCTAssertEqual(try Fixtures.nets(restored.aggregates[0]), [-2800, 2900, -100])
    }

    func testReplaceAllIsAtomicAndKeepsSafetyCopy() async throws {
        let stack = CoreDataStack(location: .inMemory)
        try stack.load()
        let repository = CoreDataEventRepository(stack: stack, clock: Fixtures.clock)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let files = BackupFileStore(rootDirectory: folder)
        let settings = UserDefaultsSettingsRepository(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let backup = BackupUseCases(repository: repository, codec: codec, files: files, settings: settings, clock: Fixtures.clock)
        defer { try? FileManager.default.removeItem(at: folder) }

        let existing = DemoEventFactory.make(today: Fixtures.today, now: Fixtures.now)
        _ = try await repository.insertDemo(existing)
        let incoming = try codec.decodeAndValidate(try codec.encode([Fixtures.aggregate(expenses: [
            Fixtures.equalExpense(amount: 500, payer: a, participants: [b]),
        ])], exportedAt: Fixtures.now))

        try await backup.replaceAll(with: incoming)
        var all = try await repository.loadAll()
        XCTAssertEqual(all.map(\.event.id), [TestIDs.event])
        XCTAssertNotNil(files.safetyCopyInfo())

        try await backup.restoreSafetyCopy()
        all = try await repository.loadAll()
        XCTAssertEqual(all.map(\.event.id), [DemoEventFactory.eventID])

        try backup.deleteSafetyCopy()
        XCTAssertNil(files.safetyCopyInfo())
    }
}

final class ShareSummaryTests: XCTestCase {
    private let a = TestIDs.a, b = TestIDs.b, c = TestIDs.c

    func testDefaultSummaryHasCodesBalancesAndNoNotesOrPayments() throws {
        var aggregate = Fixtures.aggregate(
            expenses: [Fixtures.equalExpense(amount: 9000, payer: a, participants: [a, b, c], title: "Dinner")],
            payments: [Fixtures.payment(from: b, to: a, amount: 1000)]
        )
        aggregate.event.note = "Secret note"
        aggregate.payments[0].note = "Paid by card"
        let snapshot = try EventSnapshot.make(aggregate)
        let text = ShareSummaryBuilder.text(for: snapshot, options: .init(), generatedAt: Fixtures.now)

        XCTAssertTrue(text.contains("Trip"))
        XCTAssertTrue(text.contains("EUR"))
        XCTAssertTrue(text.contains("Dinner"), "Expense list is on by default")
        XCTAssertTrue(text.contains("Payment suggestions are not transfer confirmations."))
        XCTAssertTrue(text.contains("Bea: to pay"))
        XCTAssertFalse(text.contains("Secret note"))
        XCTAssertFalse(text.contains("Paid by card"))
        XCTAssertFalse(text.contains("Recorded Payments ("))

        let withAll = ShareSummaryBuilder.text(for: snapshot, options: .init(includeExpenses: false, includePayments: true, includeNotes: true),
                                               generatedAt: Fixtures.now)
        XCTAssertTrue(withAll.contains("Secret note"))
        XCTAssertTrue(withAll.contains("Paid by card"))
        XCTAssertFalse(withAll.contains("Expenses ("))
        XCTAssertTrue(withAll.contains("Balances"), "Balances stay even without the expense list")
    }

    func testEmptyEventSummary() throws {
        let text = ShareSummaryBuilder.text(for: try EventSnapshot.make(Fixtures.aggregate()), options: .init(), generatedAt: Fixtures.now)
        XCTAssertTrue(text.contains("No expenses recorded."))
        XCTAssertTrue(text.contains("Trip"))
    }
}
