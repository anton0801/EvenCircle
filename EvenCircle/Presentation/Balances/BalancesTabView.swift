import SwiftUI

/// Screen 12: personal totals first, then a suggested (never automatic) settlement plan.
struct BalancesTabView<ExpenseDestination: View, HistoryDestination: View>: View {
    let snapshot: EventSnapshot
    let onRecord: (SuggestedPayment) -> Void
    let onRecordDifferent: () -> Void
    let onHistory: () -> Void
    let onShare: () -> Void
    let expenseDestination: (UUID) -> ExpenseDestination
    let historyDestination: () -> HistoryDestination

    @State private var expanded: Set<UUID> = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var currency: CurrencyCode { snapshot.currency }
    private var aggregate: EventAggregate { snapshot.aggregate }
    private var hasHistory: Bool { !aggregate.expenses.isEmpty || !aggregate.payments.isEmpty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.m) {
                totalsCard
                if !hasHistory {
                    EmptyStateView(
                        systemImage: "scalemass",
                        title: "Add an expense to see balances",
                        message: "Balances appear once someone has paid for something shared."
                    )
                } else {
                    if snapshot.balances.allSettled {
                        HStack(spacing: Spacing.m) {
                            IllustrationView(.balancedShapes)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("All settled")
                                    .ecSectionFont()
                                    .foregroundColor(.ecMint)
                                Text("Every net balance is zero based on the saved expenses and recorded payments.")
                                    .ecCaptionFont()
                                    .foregroundColor(.ecTextSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .ecCard()
                        .accessibilityElement(children: .combine)
                    }

                    SectionHeader(title: "People", subtitle: "Net = paid for expenses − share + payments sent − payments received")
                    LazyVStack(spacing: Spacing.xs) {
                        ForEach(snapshot.balances.people) { balance in
                            if let person = aggregate.person(balance.personID) {
                                personCard(person, balance)
                            }
                        }
                    }

                    suggestionsSection
                }

                actions
            }
            .padding(Spacing.screen)
        }
    }

    // MARK: - Totals

    private var totalsCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Outstanding to Settle")
                .font(.callout.weight(.semibold))
                .foregroundColor(.ecTextSecondary)
            MoneyText(minor: snapshot.balances.outstandingMinor, currency: currency, hero: true)
                .accessibilityIdentifier("outstandingValue")
            Divider().background(Color.ecDivider)
            LabeledValueRow(
                label: "Total Expenses",
                value: MoneyFormatter.string(snapshot.balances.totalExpensesMinor, currency),
                spokenValue: MoneyFormatter.spoken(snapshot.balances.totalExpensesMinor, currency)
            )
            LabeledValueRow(
                label: "Recorded Payments",
                value: MoneyFormatter.string(snapshot.balances.recordedPaymentsMinor, currency),
                spokenValue: MoneyFormatter.spoken(snapshot.balances.recordedPaymentsMinor, currency)
            )
        }
        .ecCard()
    }

    // MARK: - People

    private func personCard(_ person: Person, _ balance: PersonBalance) -> some View {
        let isExpanded = expanded.contains(person.id)
        return VStack(alignment: .leading, spacing: Spacing.s) {
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                    if isExpanded { expanded.remove(person.id) } else { expanded.insert(person.id) }
                }
            } label: {
                HStack(alignment: .center, spacing: Spacing.s) {
                    AvatarView(person: person, size: 40)
                    // Name and status on separate lines: a long name wraps, the amount never squeezes it.
                    VStack(alignment: .leading, spacing: 4) {
                        Text(person.name)
                            .font(.body.weight(.semibold))
                            .foregroundColor(.ecTextPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        BalanceBadge(direction: balance.direction, currency: currency)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(.ecTextSecondary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .accessibilityHidden(true)
                }
                .frame(minHeight: Metrics.minTapTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // A Button is already one element; an explicit label replaces its children's text.
            .accessibilityLabel("\(person.name), \(balance.direction.spoken(currency))")
            .accessibilityHint(isExpanded ? "Hide details" : "Show expenses and payments behind this balance")
            .accessibilityIdentifier("balanceRow_\(person.name)")

            if isExpanded {
                breakdown(person, balance)
            }
        }
        .ecCard(padding: 14)
    }

    private func breakdown(_ person: Person, _ balance: PersonBalance) -> some View {
        let relatedExpenses = aggregate.orderedExpenses.filter { $0.payerID == person.id || $0.share(for: person.id) != nil }
        let relatedPayments = aggregate.orderedPayments.filter { $0.fromID == person.id || $0.toID == person.id }
        return VStack(alignment: .leading, spacing: Spacing.xs) {
            Divider().background(Color.ecDivider)
            amountRow("Paid for Expenses", balance.paidMinor)
            amountRow("Share of Expenses", balance.owedMinor)
            amountRow("Payments Sent", balance.sentMinor)
            amountRow("Payments Received", balance.receivedMinor)
            LabeledValueRow(
                label: "Net Balance",
                value: MoneyFormatter.signed(balance.netMinor, currency),
                spokenValue: balance.direction.spoken(currency),
                emphasized: true
            )

            if !relatedExpenses.isEmpty {
                Text("Expenses")
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(.ecTextSecondary)
                    .padding(.top, Spacing.xs)
                ForEach(relatedExpenses) { expense in
                    NavigationLink(destination: LazyView(expenseDestination(expense.id))) {
                        sourceRow(
                            title: expense.title,
                            detail: expenseDetail(expense, person: person)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            if !relatedPayments.isEmpty {
                Text("Recorded payments")
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(.ecTextSecondary)
                    .padding(.top, Spacing.xs)
                ForEach(relatedPayments) { payment in
                    NavigationLink(destination: LazyView(historyDestination())) {
                        sourceRow(
                            title: payment.fromID == person.id
                                ? "Sent to \(aggregate.personName(payment.toID))"
                                : "Received from \(aggregate.personName(payment.fromID))",
                            detail: "\(MoneyFormatter.string(payment.amountMinor, currency)) · \(DateText.medium(payment.paymentDate))"
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func expenseDetail(_ expense: Expense, person: Person) -> String {
        var parts: [String] = []
        if expense.payerID == person.id {
            parts.append("paid \(MoneyFormatter.string(expense.amountMinor, currency))")
        }
        if let share = expense.share(for: person.id) {
            parts.append("share \(MoneyFormatter.string(share.allocatedMinor, currency))")
        }
        return parts.joined(separator: " · ")
    }

    private func amountRow(_ label: String, _ minor: Int64) -> some View {
        LabeledValueRow(
            label: label,
            value: MoneyFormatter.string(minor, currency),
            spokenValue: MoneyFormatter.spoken(minor, currency)
        )
    }

    private func sourceRow(title: String, detail: String) -> some View {
        HStack(spacing: Spacing.xs) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.semibold))
                    .foregroundColor(.ecTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .ecCaptionFont()
                    .foregroundColor(.ecTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote)
                .foregroundColor(.ecTextSecondary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .frame(minHeight: Metrics.minTapTarget)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.ecInput))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    // MARK: - Suggestions

    @ViewBuilder
    private var suggestionsSection: some View {
        if !snapshot.suggestions.isEmpty {
            SectionHeader(title: "Suggested Payments", subtitle: "Suggestions only. No money is moved.")
            VStack(spacing: Spacing.xs) {
                ForEach(snapshot.suggestions) { suggestion in
                    suggestionRow(suggestion)
                }
            }
            InfoNote(text: "A plan that closes every current balance. It isn't guaranteed to be the fewest possible transfers.")
        }
    }

    private func suggestionRow(_ suggestion: SuggestedPayment) -> some View {
        let fromName = aggregate.personName(suggestion.fromID)
        let toName = aggregate.personName(suggestion.toID)
        return VStack(alignment: .leading, spacing: Spacing.s) {
            AdaptiveRow {
                HStack(spacing: 6) {
                    Text(fromName)
                        .font(.body.weight(.semibold))
                        .foregroundColor(.ecTextPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Image(systemName: "arrow.right")
                        .foregroundColor(.ecTextSecondary)
                        .accessibilityHidden(true)
                    Text(toName)
                        .font(.body.weight(.semibold))
                        .foregroundColor(.ecTextPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } trailing: {
                MoneyText(minor: suggestion.amountMinor, currency: currency)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Suggested: \(fromName) pays \(toName) \(MoneyFormatter.spoken(suggestion.amountMinor, currency))")

            if suggestion.amountMinor > DomainLimits.maxPaymentMinor {
                InfoNote(text: "Above the limit for one record. Record it in several parts of up to \(MoneyFormatter.string(DomainLimits.maxPaymentMinor, currency)).")
            }
            Button {
                onRecord(suggestion)
            } label: {
                Label("Record Payment", systemImage: "square.and.pencil")
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(snapshot.isArchived)
            .accessibilityHint("Opens a form to record a transfer \(fromName) already made to \(toName) outside the app")
            .accessibilityIdentifier("recordSuggestion_\(fromName)_\(toName)")
        }
        .ecCard(padding: 14)
    }

    // MARK: - Actions

    private var actions: some View {
        VStack(spacing: Spacing.xs) {
            if snapshot.isArchived && !snapshot.suggestions.isEmpty {
                InfoNote(text: "Restore the event to record payments.", icon: "archivebox")
            }
            if !snapshot.isArchived && !snapshot.suggestions.isEmpty {
                Button("Record a Different Payment", action: onRecordDifferent)
                    .buttonStyle(SecondaryButtonStyle())
            }
            HStack(spacing: Spacing.xs) {
                Button(action: onHistory) { Label("History", systemImage: "clock.arrow.circlepath") }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityIdentifier("paymentHistoryButton")
                Button(action: onShare) { Label("Share Summary", systemImage: "square.and.arrow.up") }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityIdentifier("shareSummaryButton")
            }
        }
        .padding(.top, Spacing.xs)
    }
}
