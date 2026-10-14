import Foundation

/// A computed proposal, never stored. It has no payment status of its own.
struct SuggestedPayment: Identifiable, Equatable {
    let fromID: UUID
    let toID: UUID
    let amountMinor: Int64

    var id: String { fromID.uuidString + ">" + toID.uuidString }
}

/// Deterministic settlement plan from current integer balances.
///
/// Each step pairs the largest remaining debt with the largest remaining credit
/// (ties by ascending lowercase UUID) and proposes min(debt, credit). The plan closes
/// every balance; it does not promise the minimal number of transfers.
enum PaymentSuggestionBuilder {
    static func build(from balances: [PersonBalance]) -> [SuggestedPayment] {
        var debtors = balances.filter { $0.netMinor < 0 }.map { (id: $0.personID, remaining: -$0.netMinor) }
        var creditors = balances.filter { $0.netMinor > 0 }.map { (id: $0.personID, remaining: $0.netMinor) }
        var result: [SuggestedPayment] = []

        func pickIndex(_ list: [(id: UUID, remaining: Int64)]) -> Int? {
            var best: Int?
            for (index, entry) in list.enumerated() where entry.remaining > 0 {
                guard let current = best else { best = index; continue }
                let candidate = list[current]
                if entry.remaining > candidate.remaining
                    || (entry.remaining == candidate.remaining && entry.id.lowercasedString < candidate.id.lowercasedString) {
                    best = index
                }
            }
            return best
        }

        // Each step zeroes at least one side, so this terminates in at most debtors + creditors steps.
        while let d = pickIndex(debtors), let c = pickIndex(creditors) {
            let amount = min(debtors[d].remaining, creditors[c].remaining)
            result.append(SuggestedPayment(fromID: debtors[d].id, toID: creditors[c].id, amountMinor: amount))
            debtors[d].remaining -= amount
            creditors[c].remaining -= amount
        }
        return result
    }
}
