import Foundation

/// Deterministic "Sample Weekend" event. Stable IDs make a second Load a no-op.
///
/// Alex paid Dinner 90.00 for Alex/Bea/Chris; Bea paid Taxi 24.00 for Bea/Chris;
/// Chris paid Snacks 12.00 for Alex/Chris → Alex +54.00, Bea −18.00, Chris −36.00.
/// The sample payment Bea → Alex 10.00 then gives Alex +44.00, Bea −8.00, Chris −36.00.
enum DemoEventFactory {
    static let eventID = UUID(uuidString: "EC0DE000-0000-4000-8000-000000000001")!
    static let alexID = UUID(uuidString: "EC0DE000-0000-4000-8000-0000000000A1")!
    static let beaID = UUID(uuidString: "EC0DE000-0000-4000-8000-0000000000A2")!
    static let chrisID = UUID(uuidString: "EC0DE000-0000-4000-8000-0000000000A3")!
    static let dinnerID = UUID(uuidString: "EC0DE000-0000-4000-8000-0000000000E1")!
    static let taxiID = UUID(uuidString: "EC0DE000-0000-4000-8000-0000000000E2")!
    static let snacksID = UUID(uuidString: "EC0DE000-0000-4000-8000-0000000000E3")!
    static let paymentID = UUID(uuidString: "EC0DE000-0000-4000-8000-0000000000F1")!
    static let paymentOperationID = UUID(uuidString: "EC0DE000-0000-4000-8000-0000000000F2")!

    /// Revision of a freshly loaded sample; anything higher means the user changed it.
    static let initialRevision: Int64 = 1

    static func make(today: CalendarDate, now: Date) -> EventAggregate {
        let start = today.adding(days: -2)
        let event = Event(
            id: eventID,
            name: "Sample Weekend",
            eventDate: start,
            currency: .eur,
            currencyLocked: true,
            note: "Sample data to explore Even Circle. Remove it any time in Settings.",
            isArchived: false,
            isDemo: true,
            revision: initialRevision,
            createdAt: now,
            updatedAt: now
        )
        let people = [(alexID, "Alex", AvatarColorKey.blue), (beaID, "Bea", .lilac), (chrisID, "Chris", .mint)]
            .enumerated()
            .map { index, entry in
                Person(id: entry.0, eventID: eventID, name: entry.1, avatarColor: entry.2,
                       createdAt: now.addingTimeInterval(Double(index) * 0.001), updatedAt: now)
            }

        func expense(_ id: UUID, _ title: String, _ amount: Int64, payer: UUID, date: CalendarDate,
                     participants: [UUID], offset: Double) -> Expense {
            // Equal split; the allocator is exact for these amounts.
            let allocations = (try? LargestRemainderAllocator.equal(amount: amount, personIDs: participants)) ?? [:]
            return Expense(
                id: id, eventID: eventID, title: title, amountMinor: amount, payerID: payer,
                expenseDate: date, method: .equal, note: nil,
                createdAt: now.addingTimeInterval(offset), updatedAt: now.addingTimeInterval(offset), revision: 1,
                shares: participants.map { ExpenseShare(personID: $0, allocatedMinor: allocations[$0] ?? 0, weight: 1) },
                items: []
            )
        }

        let expenses = [
            expense(dinnerID, "Dinner", 9_000, payer: alexID, date: start, participants: [alexID, beaID, chrisID], offset: 0.01),
            expense(taxiID, "Taxi", 2_400, payer: beaID, date: start, participants: [beaID, chrisID], offset: 0.02),
            expense(snacksID, "Snacks", 1_200, payer: chrisID, date: start.adding(days: 1), participants: [alexID, chrisID], offset: 0.03),
        ]
        let payment = Payment(
            id: paymentID, eventID: eventID, fromID: beaID, toID: alexID, amountMinor: 1_000,
            paymentDate: today, note: "Sample record", operationID: paymentOperationID,
            createdAt: now.addingTimeInterval(0.04)
        )
        return EventAggregate(event: event, people: people, expenses: expenses, payments: [payment])
    }
}

struct DemoStatus: Equatable {
    var isLoaded: Bool
    var isModified: Bool
}

final class DemoUseCases {
    private let repository: EventRepository
    private let clock: AppClock

    init(repository: EventRepository, clock: AppClock) {
        self.repository = repository
        self.clock = clock
    }

    func status() async throws -> DemoStatus {
        let demos = try await repository.loadAll().filter(\.event.isDemo)
        guard !demos.isEmpty else { return DemoStatus(isLoaded: false, isModified: false) }
        let modified = demos.contains { $0.event.id != DemoEventFactory.eventID || $0.event.revision != DemoEventFactory.initialRevision }
        return DemoStatus(isLoaded: true, isModified: modified)
    }

    /// Returns `.alreadyApplied` when the sample already exists.
    func load() async throws -> WriteOutcome {
        try await repository.insertDemo(DemoEventFactory.make(today: clock.today, now: clock.now()))
    }

    /// Deletes every event marked as demo, including people and records the user added to it.
    @discardableResult
    func remove() async throws -> Int {
        try await repository.deleteDemoEvents()
    }
}
