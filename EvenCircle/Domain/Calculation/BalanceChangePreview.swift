import Foundation

/// Before / After net balances for a pending change, computed in memory before anything is saved.
struct BalanceChangePreview: Equatable {
    struct Row: Identifiable, Equatable {
        let personID: UUID
        let name: String
        let beforeMinor: Int64
        let afterMinor: Int64

        var id: UUID { personID }
        var changed: Bool { beforeMinor != afterMinor }
        var directionChanged: Bool {
            beforeMinor.signum() != afterMinor.signum() && beforeMinor != 0 && afterMinor != 0
        }
    }

    let currency: CurrencyCode
    let rows: [Row]
    let basedOnRevision: Int64

    var changedRows: [Row] { rows.filter(\.changed) }
    var hasChanges: Bool { rows.contains(where: \.changed) }

    static func make(before: EventAggregate, after: EventAggregate) throws -> BalanceChangePreview {
        let beforeBalances = try BalanceCalculator.calculate(before)
        let afterBalances = try BalanceCalculator.calculate(after)
        let rows = before.orderedPeople.map { person in
            Row(
                personID: person.id,
                name: person.name,
                beforeMinor: beforeBalances.net(for: person.id),
                afterMinor: afterBalances.net(for: person.id)
            )
        }
        return BalanceChangePreview(currency: before.event.currency, rows: rows, basedOnRevision: before.event.revision)
    }
}
