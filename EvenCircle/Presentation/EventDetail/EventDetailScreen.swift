import SwiftUI

enum EventDetailSheet: Identifiable {
    case editEvent(EventAggregate)
    case newExpense(EventAggregate)
    case recordPayment(EventAggregate, SuggestedPayment?)
    case shareSummary
    case addPerson(EventAggregate)
    case editPerson(EventAggregate, Person)

    var id: String {
        switch self {
        case .editEvent: return "editEvent"
        case .newExpense: return "newExpense"
        case .recordPayment(_, let suggestion): return "recordPayment-\(suggestion?.id ?? "custom")"
        case .shareSummary: return "shareSummary"
        case .addPerson: return "addPerson"
        case .editPerson(_, let person): return "editPerson-\(person.id)"
        }
    }
}

/// Event container: name and currency always visible, pinned Expenses / People / Balances switch.
struct EventDetailScreen: View {
    let deps: AppDependencies
    @StateObject private var vm: EventDetailViewModel
    @State private var tab: EventTab
    @State private var sheet: EventDetailSheet?
    @State private var pushedExpenseID: UUID?
    @State private var showHistory = false
    @State private var confirmArchive = false
    @State private var peopleNotice: String?
    @Environment(\.dismiss) private var dismiss

    init(deps: AppDependencies, eventID: UUID, initialTab: EventTab) {
        self.deps = deps
        _vm = StateObject(wrappedValue: EventDetailViewModel(deps: deps, eventID: eventID))
        _tab = State(initialValue: initialTab)
    }

    var body: some View {
        Group {
            if vm.isMissing {
                VStack(spacing: Spacing.m) {
                    EmptyStateView(systemImage: "questionmark.folder", title: "Event is no longer available",
                                   message: "It may have been deleted or replaced by an imported backup.")
                    Button("Back to Events") { dismiss() }
                        .buttonStyle(PrimaryButtonStyle())
                }
                .padding(Spacing.screen)
            } else {
                switch vm.state {
                case .loading:
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                case .failed(let message):
                    ErrorStateView(title: "Couldn't load this event", message: message) { vm.reload() }
                case .loaded(let snapshot):
                    content(snapshot)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ecScreenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if let snapshot = vm.snapshot { eventMenu(snapshot) }
            }
        }
        .background(links)
        .task { await vm.load() }
        .sheet(item: $sheet) { sheet in sheetView(sheet) }
        .messageAlert($vm.alert)
        .alert("This event still has an open balance", isPresented: $confirmArchive) {
            Button("Archive") { Task { await vm.setArchived(true) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let snapshot = vm.snapshot {
                Text("\(MoneyFormatter.string(snapshot.balances.outstandingMinor, snapshot.currency)) is still outstanding. The archive keeps every amount visible and nothing is written off.")
            }
        }
    }

    // MARK: - Layout

    private func content(_ snapshot: EventSnapshot) -> some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: Spacing.s) {
                HStack(alignment: .top, spacing: Spacing.xs) {
                    Text(snapshot.event.name)
                        .font(.title2.weight(.bold))
                        .foregroundColor(.ecTextPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("eventTitle")
                    Spacer(minLength: Spacing.xs)
                    CurrencyChip(currency: snapshot.currency)
                }
                HStack(spacing: Spacing.xs) {
                    Text(DateText.medium(snapshot.event.eventDate))
                        .ecCaptionFont()
                        .foregroundColor(.ecTextSecondary)
                    if snapshot.event.isDemo { StatusChip(text: "Sample", color: .ecLilac, icon: "sparkles") }
                }
                if snapshot.isArchived {
                    ArchivedBanner { Task { await vm.setArchived(false) } }
                }
                Picker("Section", selection: $tab) {
                    ForEach(EventTab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("eventTabs")
            }
            .padding(.horizontal, Spacing.screen)
            .padding(.bottom, Spacing.s)
            .background(Color.ecBackground)

            Rectangle().fill(Color.ecDivider).frame(height: 1).accessibilityHidden(true)

            switch tab {
            case .expenses:
                ExpensesTabView(
                    vm: vm,
                    snapshot: snapshot,
                    onAddExpense: { addExpense(snapshot) },
                    expenseDestination: { expenseDetail($0) }
                )
            case .people:
                PeopleTabView(
                    snapshot: snapshot,
                    notice: $peopleNotice,
                    onAdd: { sheet = .addPerson(snapshot.aggregate) },
                    onEdit: { sheet = .editPerson(snapshot.aggregate, $0) },
                    onDelete: { person in Task { await vm.deletePerson(person) } },
                    onContinue: { tab = .expenses }
                )
            case .balances:
                BalancesTabView(
                    snapshot: snapshot,
                    onRecord: { sheet = .recordPayment(snapshot.aggregate, $0) },
                    onRecordDifferent: { sheet = .recordPayment(snapshot.aggregate, nil) },
                    onHistory: { showHistory = true },
                    onShare: { sheet = .shareSummary },
                    expenseDestination: { expenseDetail($0) },
                    historyDestination: { PaymentHistoryScreen(vm: vm) }
                )
            }
        }
    }

    private func eventMenu(_ snapshot: EventSnapshot) -> some View {
        Menu {
            Button { sheet = .editEvent(snapshot.aggregate) } label: { Label("Event Details", systemImage: "info.circle") }
                .disabled(snapshot.isArchived)
            if snapshot.isArchived {
                Button { Task { await vm.setArchived(false) } } label: { Label("Restore", systemImage: "arrow.uturn.backward") }
            } else {
                Button {
                    if snapshot.balances.outstandingMinor > 0 {
                        confirmArchive = true
                    } else {
                        Task { await vm.setArchived(true) }
                    }
                } label: { Label("Archive", systemImage: "archivebox") }
            }
            Button { sheet = .shareSummary } label: { Label("Share Summary", systemImage: "square.and.arrow.up") }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3)
                .frame(width: Metrics.minTapTarget, height: Metrics.minTapTarget)
        }
        .accessibilityLabel("Event actions")
        .accessibilityIdentifier("eventMenu")
    }

    private var links: some View {
        VStack {
            NavigationLink(
                isActive: Binding(get: { pushedExpenseID != nil }, set: { if !$0 { pushedExpenseID = nil } }),
                destination: {
                    if let id = pushedExpenseID { LazyView(expenseDetail(id)) }
                },
                label: { EmptyView() }
            )
            NavigationLink(isActive: $showHistory, destination: { LazyView(PaymentHistoryScreen(vm: vm)) }, label: { EmptyView() })
            // A third link avoids the iOS 14/15 bug where exactly two hidden links pop immediately.
            NavigationLink(destination: EmptyView(), label: { EmptyView() })
        }
        .hidden()
    }

    private func expenseDetail(_ id: UUID) -> ExpenseDetailScreen {
        ExpenseDetailScreen(vm: vm, expenseID: id, onViewBalances: { tab = .balances })
    }

    private func addExpense(_ snapshot: EventSnapshot) {
        if snapshot.canAddExpense {
            sheet = .newExpense(snapshot.aggregate)
        } else {
            peopleNotice = "Add at least two people before adding an expense. One expense can still be assigned to a single person."
            tab = .people
        }
    }

    @ViewBuilder
    private func sheetView(_ sheet: EventDetailSheet) -> some View {
        switch sheet {
        case .editEvent(let aggregate):
            EventEditorScreen(deps: deps, mode: .edit(aggregate)) { _ in }
        case .newExpense(let aggregate):
            ExpenseEditorScreen(deps: deps, aggregate: aggregate, editing: nil) { savedID in
                tab = .expenses
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { pushedExpenseID = savedID }
            }
        case .recordPayment(let aggregate, let suggestion):
            RecordPaymentScreen(deps: deps, aggregate: aggregate, suggestion: suggestion) {
                tab = .balances
            }
        case .shareSummary:
            ShareSummaryScreen(deps: deps, eventID: vm.eventID)
        case .addPerson(let aggregate):
            PersonEditorScreen(deps: deps, aggregate: aggregate, person: nil, onDelete: nil)
        case .editPerson(let aggregate, let person):
            PersonEditorScreen(deps: deps, aggregate: aggregate, person: person) {
                Task { await vm.deletePerson(person) }
            }
        }
    }
}
