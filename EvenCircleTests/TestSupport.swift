import Foundation
@testable import EvenCircle

/// IDs whose lowercase strings sort A < B < C < D, as in the spec examples.
enum TestIDs {
    static let a = UUID(uuidString: "00000000-0000-4000-8000-00000000000A")!
    static let b = UUID(uuidString: "00000000-0000-4000-8000-00000000000B")!
    static let c = UUID(uuidString: "00000000-0000-4000-8000-00000000000C")!
    static let d = UUID(uuidString: "00000000-0000-4000-8000-00000000000D")!
    static let event = UUID(uuidString: "00000000-0000-4000-8000-0000000000EE")!
}

enum Fixtures {
    // 2026-10-13 12:00 UTC; `today` is derived from it so the clock and fixtures agree.
    static let now = Date(timeIntervalSince1970: 1_791_892_800)
    static let today = CalendarDate(date: now, timeZone: TimeZone(identifier: "UTC")!)
    static let clock = AppClock(now: { Fixtures.now }, timeZone: { TimeZone(identifier: "UTC")! })

    static func event(_ currency: CurrencyCode = .eur, id: UUID = TestIDs.event, revision: Int64 = 1) -> Event {
        Event(id: id, name: "Trip", eventDate: today, currency: currency, currencyLocked: false, note: nil,
              isArchived: false, isDemo: false, revision: revision, createdAt: now, updatedAt: now)
    }

    static func person(_ id: UUID, _ name: String, eventID: UUID = TestIDs.event, offset: Double = 0) -> Person {
        Person(id: id, eventID: eventID, name: name, avatarColor: .blue,
               createdAt: now.addingTimeInterval(offset), updatedAt: now)
    }

    /// Alex (A), Bea (B), Chris (C).
    static func threePeople(eventID: UUID = TestIDs.event) -> [Person] {
        [person(TestIDs.a, "Alex", eventID: eventID, offset: 0),
         person(TestIDs.b, "Bea", eventID: eventID, offset: 1),
         person(TestIDs.c, "Chris", eventID: eventID, offset: 2)]
    }

    static func equalExpense(
        id: UUID = UUID(), amount: Int64, payer: UUID, participants: [UUID], eventID: UUID = TestIDs.event, title: String = "Expense"
    ) -> Expense {
        let allocations = try! LargestRemainderAllocator.equal(amount: amount, personIDs: participants)
        return Expense(id: id, eventID: eventID, title: title, amountMinor: amount, payerID: payer, expenseDate: today,
                       method: .equal, note: nil, createdAt: now, updatedAt: now, revision: 1,
                       shares: participants.map { ExpenseShare(personID: $0, allocatedMinor: allocations[$0]!, weight: 1) },
                       items: [])
    }

    static func payment(from: UUID, to: UUID, amount: Int64, eventID: UUID = TestIDs.event) -> Payment {
        Payment(id: UUID(), eventID: eventID, fromID: from, toID: to, amountMinor: amount, paymentDate: today,
                note: nil, operationID: UUID(), createdAt: now)
    }

    static func aggregate(expenses: [Expense] = [], payments: [Payment] = [], currency: CurrencyCode = .eur) -> EventAggregate {
        var event = event(currency)
        event.currencyLocked = !expenses.isEmpty
        return EventAggregate(event: event, people: threePeople(), expenses: expenses, payments: payments)
    }

    static func nets(_ aggregate: EventAggregate) throws -> [Int64] {
        let balances = try BalanceCalculator.calculate(aggregate)
        return [TestIDs.a, TestIDs.b, TestIDs.c].map { balances.net(for: $0) }
    }
}
