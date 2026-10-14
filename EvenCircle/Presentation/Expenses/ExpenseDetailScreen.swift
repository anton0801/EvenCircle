import SwiftUI

/// Screen 11: who paid and exactly how the purchase was split. A purchase, never a transfer.
struct ExpenseDetailScreen: View {
    @ObservedObject var vm: EventDetailViewModel
    let expenseID: UUID
    let onViewBalances: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var editing: EditRequest?
    @State private var review: ReviewRequest?
    @State private var isDeleting = false
    @State private var alert: AlertMessage?
    @State private var expandedItems: Set<UUID> = []

    struct EditRequest: Identifiable {
        let id = UUID()
        let aggregate: EventAggregate
        let expense: Expense
    }

    var body: some View {
        Group {
            if let snapshot = vm.snapshot, let expense = snapshot.aggregate.expense(expenseID) {
                content(snapshot, expense)
            } else if vm.snapshot == nil && !vm.isMissing {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: Spacing.m) {
                    EmptyStateView(systemImage: "questionmark.folder", title: "Expense is no longer available",
                                   message: "It may have been deleted or replaced by an imported backup.")
                    Button("Back to Event") { dismiss() }
                        .buttonStyle(PrimaryButtonStyle())
                }
                .padding(Spacing.screen)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ecScreenBackground()
        .navigationTitle("Expense")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { request in
            ExpenseEditorScreen(deps: vm.deps, aggregate: request.aggregate, editing: request.expense) { _ in }
        }
        .sheet(item: $review) { request in
            ReviewBalanceChangesView(
                title: "Delete Expense",
                preview: request.preview,
                explanation: "Recorded payments stay in the history. Balances may change direction.",
                confirmTitle: "Delete Expense",
                destructive: true,
                isWorking: isDeleting,
                notice: request.notice,
                onConfirm: { Task { await confirmDelete(basedOn: request.preview.basedOnRevision) } },
                onCancel: { review = nil }
            )
        }
        .messageAlert($alert)
    }

    private func content(_ snapshot: EventSnapshot, _ expense: Expense) -> some View {
        let currency = snapshot.currency
        let aggregate = snapshot.aggregate
        return ScrollView {
            VStack(alignment: .leading, spacing: Spacing.m) {
                if snapshot.isArchived { ArchivedBanner() }

                VStack(alignment: .leading, spacing: Spacing.s) {
                    Text(expense.title)
                        .font(.title2.weight(.bold))
                        .foregroundColor(.ecTextPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("expenseDetailTitle")
                    MoneyText(minor: expense.amountMinor, currency: currency, hero: true)
                    LabeledValueRow(label: "Date", value: DateText.medium(expense.expenseDate))
                    LabeledValueRow(label: "Paid By", value: aggregate.personName(expense.payerID))
                    LabeledValueRow(label: "Method", value: expense.method.title)
                    if let note = expense.note {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Note").font(.callout.weight(.semibold)).foregroundColor(.ecTextSecondary)
                            Text(note)
                                .foregroundColor(.ecTextPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                        }
                        .padding(.top, 4)
                    }
                }
                .ecCard()

                SectionHeader(title: "Split", subtitle: "\(expense.shares.count.counted("person", "people")) share this purchase")
                VStack(spacing: Spacing.xs) {
                    ForEach(sortedShares(expense, aggregate), id: \.personID) { share in
                        shareRow(share, expense: expense, aggregate: aggregate, currency: currency)
                    }
                }

                if expense.method == .items {
                    SectionHeader(title: "Receipt Items")
                    VStack(spacing: Spacing.xs) {
                        ForEach(expense.items.sorted { $0.sortOrder < $1.sortOrder }) { item in
                            itemRow(item, aggregate: aggregate, currency: currency)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    LabeledValueRow(
                        label: "Total Allocated",
                        value: MoneyFormatter.string(expense.totalAllocatedMinor, currency),
                        spokenValue: MoneyFormatter.spoken(expense.totalAllocatedMinor, currency),
                        emphasized: true
                    )
                    InfoNote(text: "Small rounding differences are included in the shown amounts.")
                }
                .ecCard()

                actions(snapshot, expense)
            }
            .padding(Spacing.screen)
        }
    }

    private func sortedShares(_ expense: Expense, _ aggregate: EventAggregate) -> [ExpenseShare] {
        let order = Dictionary(uniqueKeysWithValues: aggregate.orderedPeople.enumerated().map { ($1.id, $0) })
        return expense.shares.sorted { (order[$0.personID] ?? .max) < (order[$1.personID] ?? .max) }
    }

    private func shareRow(_ share: ExpenseShare, expense: Expense, aggregate: EventAggregate, currency: CurrencyCode) -> some View {
        let person = aggregate.person(share.personID)
        return HStack(spacing: Spacing.s) {
            if let person { AvatarView(person: person, size: 36) }
            AdaptiveRow {
                VStack(alignment: .leading, spacing: 2) {
                    Text(aggregate.personName(share.personID))
                        .foregroundColor(.ecTextPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    if expense.method == .shares, let weight = share.weight {
                        Text(weight == 1 ? "1 share" : "\(weight) shares")
                            .ecCaptionFont()
                            .foregroundColor(.ecTextSecondary)
                    }
                }
            } trailing: {
                MoneyText(minor: share.allocatedMinor, currency: currency)
            }
        }
        .ecCard(padding: 12)
        .accessibilityElement(children: .combine)
    }

    private func itemRow(_ item: ReceiptItem, aggregate: EventAggregate, currency: CurrencyCode) -> some View {
        DisclosureGroup(isExpanded: Binding(
            get: { expandedItems.contains(item.id) },
            set: { if $0 { expandedItems.insert(item.id) } else { expandedItems.remove(item.id) } }
        )) {
            VStack(alignment: .leading, spacing: 4) {
                LabeledValueRow(label: "Quantity", value: "\(item.quantity)")
                LabeledValueRow(label: "Unit Price", value: MoneyFormatter.string(item.unitPriceMinor, currency))
                ForEach(item.shares, id: \.personID) { share in
                    LabeledValueRow(
                        label: aggregate.personName(share.personID),
                        value: MoneyFormatter.string(share.allocatedMinor, currency),
                        spokenValue: MoneyFormatter.spoken(share.allocatedMinor, currency)
                    )
                }
            }
            .padding(.top, Spacing.xs)
        } label: {
            AdaptiveRow {
                Text(item.title)
                    .foregroundColor(.ecTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            } trailing: {
                MoneyText(minor: item.lineAmountMinor, currency: currency)
            }
        }
        .accentColor(.ecTextSecondary)
        .ecCard(padding: 12)
    }

    private func actions(_ snapshot: EventSnapshot, _ expense: Expense) -> some View {
        VStack(spacing: Spacing.xs) {
            if !snapshot.isArchived {
                HStack(spacing: Spacing.xs) {
                    Button {
                        editing = EditRequest(aggregate: snapshot.aggregate, expense: expense)
                    } label: { Label("Edit", systemImage: "pencil") }
                        .buttonStyle(SecondaryButtonStyle())
                        .accessibilityIdentifier("editExpenseButton")
                    Button(role: .destructive) {
                        startDelete(snapshot)
                    } label: { Label("Delete Expense", systemImage: "trash") }
                        .buttonStyle(SecondaryButtonStyle(tint: .ecCoral))
                        .accessibilityIdentifier("deleteExpenseButton")
                }
            }
            Button("View Balances") {
                onViewBalances()
                dismiss()
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("viewBalancesButton")
            Button("Back to Expenses") { dismiss() }
                .buttonStyle(SecondaryButtonStyle())
        }
    }

    private func startDelete(_ snapshot: EventSnapshot) {
        do {
            review = ReviewRequest(preview: try vm.deps.expenses.previewDelete(expenseID, in: snapshot.aggregate), notice: nil)
        } catch {
            alert = .error(error)
        }
    }

    /// Deletes only if the event is still at the revision the preview was based on.
    private func confirmDelete(basedOn revision: Int64) async {
        guard !isDeleting else { return }
        isDeleting = true
        defer { isDeleting = false }
        do {
            guard let fresh = try await vm.freshSnapshot() else {
                review = nil
                return
            }
            guard fresh.aggregate.event.revision == revision else {
                if fresh.aggregate.expense(expenseID) == nil {
                    review = nil
                    return
                }
                review = ReviewRequest(
                    preview: try vm.deps.expenses.previewDelete(expenseID, in: fresh.aggregate),
                    notice: "The event changed. Review the updated balances before deleting."
                )
                return
            }
            try await vm.deps.expenses.delete(expenseID, in: fresh.aggregate)
            vm.deps.haptics.success()
            review = nil
            dismiss()
        } catch RepositoryError.revisionConflict {
            review?.notice = "The event changed. Review the updated balances before deleting."
            if let fresh = try? await vm.freshSnapshot(), let preview = try? vm.deps.expenses.previewDelete(expenseID, in: fresh.aggregate) {
                review?.preview = preview
            }
        } catch {
            review = nil
            alert = .error(error, title: "Couldn't delete the expense")
        }
    }
}
