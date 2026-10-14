import Foundation

/// Builds the plain-text event report from one consistent snapshot. No invented numbers:
/// every amount comes from saved records and carries its currency code.
enum ShareSummaryBuilder {
    struct Options: Equatable {
        var includeExpenses = true
        var includePayments = false
        var includeNotes = false
    }

    static func text(for snapshot: EventSnapshot, options: Options, generatedAt: Date) -> String {
        let aggregate = snapshot.aggregate
        let event = aggregate.event
        let currency = event.currency
        let money = { (minor: Int64) in MoneyFormatter.string(minor, currency) }
        var lines: [String] = []

        lines.append("Even Circle – event summary")
        lines.append(event.name)
        lines.append("Date: \(DateText.medium(event.eventDate))")
        lines.append("Currency: \(currency.code)")
        lines.append("Generated: \(DateText.timestamp(generatedAt))")
        if event.isArchived { lines.append("Status: Archived") }
        if event.isDemo { lines.append("Sample data") }
        if options.includeNotes, let note = event.note {
            lines.append("Note: \(note)")
        }
        lines.append("")

        lines.append("Total Expenses: \(money(snapshot.balances.totalExpensesMinor))")
        lines.append("Outstanding to Settle: \(money(snapshot.balances.outstandingMinor))")
        if aggregate.expenses.isEmpty {
            lines.append("No expenses recorded.")
        }
        lines.append("")

        lines.append("Balances")
        if snapshot.balances.people.isEmpty {
            lines.append("- No people added.")
        }
        for balance in snapshot.balances.people {
            let name = aggregate.personName(balance.personID)
            switch balance.direction {
            case .toReceive(let amount): lines.append("- \(name): to receive \(money(amount))")
            case .toPay(let amount): lines.append("- \(name): to pay \(money(amount))")
            case .settled: lines.append("- \(name): settled")
            }
        }
        lines.append("")

        lines.append("Suggested Payments")
        if snapshot.suggestions.isEmpty {
            lines.append("- None. Nothing is left to settle.")
        }
        for suggestion in snapshot.suggestions {
            lines.append("- \(aggregate.personName(suggestion.fromID)) → \(aggregate.personName(suggestion.toID)): \(money(suggestion.amountMinor))")
        }
        lines.append("Payment suggestions are not transfer confirmations.")

        if options.includeExpenses && !aggregate.expenses.isEmpty {
            lines.append("")
            lines.append("Expenses (\(aggregate.expenses.count))")
            for expense in aggregate.orderedExpenses {
                lines.append("- \(DateText.medium(expense.expenseDate)) · \(expense.title) · \(money(expense.amountMinor)) · paid by \(aggregate.personName(expense.payerID)) · \(expense.method.title)")
                if options.includeNotes, let note = expense.note {
                    lines.append("  Note: \(note)")
                }
            }
        }

        if options.includePayments {
            lines.append("")
            lines.append("Recorded Payments (\(aggregate.payments.count))")
            if aggregate.payments.isEmpty {
                lines.append("- No payments recorded.")
            }
            for payment in aggregate.orderedPayments {
                lines.append("- \(DateText.medium(payment.paymentDate)) · \(aggregate.personName(payment.fromID)) → \(aggregate.personName(payment.toID)): \(money(payment.amountMinor))")
                if options.includeNotes, let note = payment.note {
                    lines.append("  Note: \(note)")
                }
            }
            lines.append("Recorded payments are personal records, not bank confirmations.")
        }

        return lines.joined(separator: "\n")
    }
}
