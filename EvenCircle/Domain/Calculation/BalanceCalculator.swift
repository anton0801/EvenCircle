import Foundation

enum BalanceDirection: Hashable {
    case toReceive(Int64)
    case toPay(Int64)
    case settled

    init(net: Int64) {
        if net > 0 {
            self = .toReceive(net)
        } else if net < 0 {
            self = .toPay(-net)
        } else {
            self = .settled
        }
    }
}

struct PersonBalance: Identifiable, Equatable {
    let personID: UUID
    var paidMinor: Int64
    var owedMinor: Int64
    var sentMinor: Int64
    var receivedMinor: Int64
    var netMinor: Int64

    var id: UUID { personID }
    var direction: BalanceDirection { BalanceDirection(net: netMinor) }
}

enum EventStatus: Equatable {
    case noExpenses
    case openBalance
    case settled

    var title: String {
        switch self {
        case .noExpenses: return "No expenses"
        case .openBalance: return "Open balance"
        case .settled: return "Settled"
        }
    }
}

struct EventBalances: Equatable {
    /// One entry per person, in the event's stable people order.
    let people: [PersonBalance]
    let totalExpensesMinor: Int64
    let recordedPaymentsMinor: Int64
    let outstandingMinor: Int64
    let status: EventStatus

    func balance(for personID: UUID) -> PersonBalance? {
        people.first { $0.personID == personID }
    }

    func net(for personID: UUID) -> Int64 {
        balance(for: personID)?.netMinor ?? 0
    }

    var allSettled: Bool { people.allSatisfy { $0.netMinor == 0 } }
}

enum BalanceCalculationError: Error, Equatable {
    case overflow
    /// Σ Net ≠ 0 – only possible with corrupted data.
    case unbalanced
}

/// Net_i = Paid_i − Owed_i + Sent_i − Received_i, computed from saved records only.
enum BalanceCalculator {
    static func calculate(_ aggregate: EventAggregate) throws -> EventBalances {
        do {
            var paid: [UUID: Int64] = [:]
            var owed: [UUID: Int64] = [:]
            var sent: [UUID: Int64] = [:]
            var received: [UUID: Int64] = [:]
            var totalExpenses: Int64 = 0
            var recordedPayments: Int64 = 0

            for expense in aggregate.expenses {
                totalExpenses = try CheckedMath.add(totalExpenses, expense.amountMinor)
                paid[expense.payerID] = try CheckedMath.add(paid[expense.payerID] ?? 0, expense.amountMinor)
                for share in expense.shares {
                    owed[share.personID] = try CheckedMath.add(owed[share.personID] ?? 0, share.allocatedMinor)
                }
            }
            for payment in aggregate.payments {
                recordedPayments = try CheckedMath.add(recordedPayments, payment.amountMinor)
                sent[payment.fromID] = try CheckedMath.add(sent[payment.fromID] ?? 0, payment.amountMinor)
                received[payment.toID] = try CheckedMath.add(received[payment.toID] ?? 0, payment.amountMinor)
            }

            var balances: [PersonBalance] = []
            var netSum: Int64 = 0
            var outstanding: Int64 = 0
            for person in aggregate.orderedPeople {
                let id = person.id
                let p = paid[id] ?? 0
                let o = owed[id] ?? 0
                let s = sent[id] ?? 0
                let r = received[id] ?? 0
                let net = try CheckedMath.subtract(try CheckedMath.add(try CheckedMath.subtract(p, o), s), r)
                netSum = try CheckedMath.add(netSum, net)
                if net > 0 { outstanding = try CheckedMath.add(outstanding, net) }
                balances.append(PersonBalance(personID: id, paidMinor: p, owedMinor: o, sentMinor: s, receivedMinor: r, netMinor: net))
            }
            guard netSum == 0 else { throw BalanceCalculationError.unbalanced }

            let status: EventStatus
            if aggregate.expenses.isEmpty && aggregate.payments.isEmpty {
                status = .noExpenses
            } else if balances.allSatisfy({ $0.netMinor == 0 }) {
                status = .settled
            } else {
                status = .openBalance
            }
            return EventBalances(
                people: balances,
                totalExpensesMinor: totalExpenses,
                recordedPaymentsMinor: recordedPayments,
                outstandingMinor: outstanding,
                status: status
            )
        } catch is ArithmeticError {
            throw BalanceCalculationError.overflow
        }
    }
}
