import SwiftUI

/// Screen 07: purchases of the event and the exact total. Recorded payments never appear here.
struct ExpensesTabView<Destination: View>: View {
    @ObservedObject var vm: EventDetailViewModel
    let snapshot: EventSnapshot
    let onAddExpense: () -> Void
    let expenseDestination: (UUID) -> Destination

    @State private var search = ""
    @State private var noteExpanded = false

    private var query: String { search.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var allExpenses: [Expense] { snapshot.aggregate.orderedExpenses }
    private var filtered: [Expense] {
        guard !query.isEmpty else { return allExpenses }
        return allExpenses.filter { $0.title.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }

    private var filteredTotal: Int64 {
        (try? CheckedMath.sum(filtered.map(\.amountMinor))) ?? 0
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.m) {
                totalCard
                if let note = snapshot.event.note {
                    DisclosureGroup(isExpanded: $noteExpanded) {
                        Text(note)
                            .foregroundColor(.ecTextPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                            .padding(.top, Spacing.xs)
                    } label: {
                        Label("Event Note", systemImage: "note.text")
                            .foregroundColor(.ecTextPrimary)
                    }
                    .accentColor(.ecTextSecondary)
                    .ecCard()
                }

                if allExpenses.isEmpty {
                    EmptyStateView(
                        illustration: .emptyReceipt,
                        title: "No expenses yet",
                        message: snapshot.isArchived
                            ? "This archived event has no expenses."
                            : "Add what was bought, who paid and how to split it.",
                        actionTitle: snapshot.isArchived ? nil : "Add Expense",
                        action: snapshot.isArchived ? nil : onAddExpense
                    )
                } else {
                    searchField
                    if filtered.isEmpty {
                        EmptyStateView(
                            systemImage: "magnifyingglass",
                            title: "No expenses found",
                            message: "No expense title matches “\(query)”.",
                            actionTitle: "Clear Search",
                            action: { search = "" }
                        )
                    } else {
                        LazyVStack(spacing: Spacing.xs) {
                            ForEach(filtered) { expense in
                                NavigationLink(destination: LazyView(expenseDestination(expense.id))) {
                                    ExpenseRow(expense: expense, aggregate: snapshot.aggregate)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("expenseRow_\(expense.title)")
                            }
                        }
                    }
                }
            }
            .padding(Spacing.screen)
        }
        .safeAreaInset(edge: .bottom) {
            if !snapshot.isArchived && !allExpenses.isEmpty {
                Button(action: onAddExpense) {
                    Label("Add Expense", systemImage: "plus")
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("addExpenseButton")
                .ecBottomBar()
            }
        }
    }

    private var totalCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Total Expenses")
                .font(.callout.weight(.semibold))
                .foregroundColor(.ecTextSecondary)
            MoneyText(minor: snapshot.balances.totalExpensesMinor, currency: snapshot.currency, hero: true)
                .accessibilityIdentifier("totalExpensesValue")
            Text("\(allExpenses.count.counted("expense")) · \(snapshot.currency.code) · payments not included")
                .ecCaptionFont()
                .foregroundColor(.ecTextSecondary)
            if !query.isEmpty && !allExpenses.isEmpty {
                Divider().background(Color.ecDivider)
                LabeledValueRow(
                    label: "Filtered Total (\(filtered.count) of \(allExpenses.count))",
                    value: MoneyFormatter.string(filteredTotal, snapshot.currency),
                    spokenValue: MoneyFormatter.spoken(filteredTotal, snapshot.currency)
                )
            }
        }
        .ecCard()
        .accessibilityElement(children: .combine)
    }

    private var searchField: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "magnifyingglass").foregroundColor(.ecTextSecondary).accessibilityHidden(true)
            TextField("Search expenses", text: $search)
                .disableAutocorrection(true)
            if !query.isEmpty {
                Button { search = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.ecTextSecondary)
                }
                .frame(width: Metrics.minTapTarget, height: Metrics.minTapTarget)
                .accessibilityLabel("Clear search")
            }
        }
        .ecInputField()
    }
}

struct ExpenseRow: View {
    let expense: Expense
    let aggregate: EventAggregate

    var body: some View {
        AdaptiveRow {
            VStack(alignment: .leading, spacing: 4) {
                Text(expense.title)
                    .font(.headline)
                    .foregroundColor(.ecTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(DateText.medium(expense.expenseDate)) · Paid by \(aggregate.personName(expense.payerID))")
                    .ecCaptionFont()
                    .foregroundColor(.ecTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                StatusChip(text: expense.method.title, color: .ecTextSecondary, icon: expense.method.icon)
            }
        } trailing: {
            HStack(spacing: 6) {
                MoneyText(minor: expense.amountMinor, currency: aggregate.event.currency)
                    .multilineTextAlignment(.trailing)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(.ecTextSecondary)
                    .accessibilityHidden(true)
            }
        }
        .ecCard(padding: 14)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(expense.title), \(MoneyFormatter.spoken(expense.amountMinor, aggregate.event.currency)), paid by \(aggregate.personName(expense.payerID)), \(DateText.medium(expense.expenseDate)), split \(expense.method.title)")
        .accessibilityAddTraits(.isButton)
    }
}

extension SplitMethod {
    var icon: String {
        switch self {
        case .equal: return "equal.circle"
        case .shares: return "chart.pie"
        case .items: return "list.bullet.rectangle"
        }
    }
}
