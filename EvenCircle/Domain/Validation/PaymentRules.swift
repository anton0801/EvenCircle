import Foundation

struct PaymentDraft: Equatable {
    var fromID: UUID?
    var toID: UUID?
    var amountMinor: Int64?
    var date: CalendarDate
    var note: String?
    var confirmedOutsideApp: Bool
}

enum PaymentDraftField: Hashable {
    case from, to, amount, date, note, confirmation
}

enum PaymentRules {
    /// min(−Net_from, Net_to), capped by the single-payment limit. Nil if the pair isn't a current debtor → creditor.
    static func maximum(fromID: UUID, toID: UUID, balances: EventBalances) -> Int64? {
        guard fromID != toID,
              let from = balances.balance(for: fromID), from.netMinor < 0,
              let to = balances.balance(for: toID), to.netMinor > 0
        else { return nil }
        return min(-from.netMinor, to.netMinor, DomainLimits.maxPaymentMinor)
    }

    static func validate(
        _ draft: PaymentDraft,
        aggregate: EventAggregate,
        balances: EventBalances,
        today: CalendarDate
    ) -> [PaymentDraftField: String] {
        var issues: [PaymentDraftField: String] = [:]
        let peopleIDs = Set(aggregate.people.map(\.id))

        if let from = draft.fromID {
            if !peopleIDs.contains(from) {
                issues[.from] = "This person is no longer in the event."
            } else if balances.net(for: from) >= 0 {
                issues[.from] = "\(aggregate.personName(from)) has nothing left to pay."
            }
        } else {
            issues[.from] = "Choose who paid."
        }

        if let to = draft.toID {
            if !peopleIDs.contains(to) {
                issues[.to] = "This person is no longer in the event."
            } else if balances.net(for: to) <= 0 {
                issues[.to] = "\(aggregate.personName(to)) has nothing left to receive."
            } else if to == draft.fromID {
                issues[.to] = "Choose two different people."
            }
        } else {
            issues[.to] = "Choose who received the payment."
        }

        if let amount = draft.amountMinor {
            if amount <= 0 {
                issues[.amount] = MoneyRangeError.notPositive.message
            } else if let from = draft.fromID, let to = draft.toID,
                      let maximum = maximum(fromID: from, toID: to, balances: balances),
                      amount > maximum {
                issues[.amount] = "The maximum for this payment is \(PlainMoneyText.string(maximum, aggregate.event.currency)). Overpayments aren't supported."
            } else if amount > DomainLimits.maxPaymentMinor {
                issues[.amount] = "The maximum for one payment record is \(PlainMoneyText.string(DomainLimits.maxPaymentMinor, aggregate.event.currency))."
            }
        } else {
            issues[.amount] = "Enter an amount."
        }

        if draft.date > today {
            issues[.date] = "The payment date can't be in the future."
        }
        if let error = TextRules.validateNote(draft.note, maxLength: DomainLimits.paymentNoteMaxLength) {
            issues[.note] = error.message
        }
        if !draft.confirmedOutsideApp {
            issues[.confirmation] = "Confirm that this payment was already made outside Even Circle."
        }
        if aggregate.payments.count >= DomainLimits.maxPaymentsPerEvent {
            issues[.amount] = "This event has reached the limit of \(DomainLimits.maxPaymentsPerEvent) payment records."
        }
        return issues
    }
}
