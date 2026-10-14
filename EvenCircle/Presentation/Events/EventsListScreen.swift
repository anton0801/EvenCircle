import SwiftUI

struct EventsListScreen: View {
    let deps: AppDependencies
    @StateObject private var vm: EventsListViewModel

    @State private var sheet: EventEditorScreen.Mode?
    @State private var openedEventID: UUID?
    @State private var openedEventTab: EventTab = .people
    @State private var archiveCandidate: EventSummary?
    @State private var deleteCandidate: EventSummary?

    init(deps: AppDependencies) {
        self.deps = deps
        _vm = StateObject(wrappedValue: EventsListViewModel(deps: deps))
    }

    var body: some View {
        NavigationView {
            content
                .ecScreenBackground()
                .navigationBarHidden(true)
                .background(createdEventLink)
        }
        .navigationViewStyle(.stack)
        .task { await vm.load() }
        .sheet(item: $sheet) { mode in
            EventEditorScreen(deps: deps, mode: mode) { createdID in
                if let createdID {
                    openedEventTab = .people
                    // Push after the sheet has gone so the navigation stack is ready.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { openedEventID = createdID }
                }
            }
        }
        .messageAlert($vm.alert)
        .alert(
            "This event still has an open balance",
            isPresented: Binding(get: { archiveCandidate != nil }, set: { if !$0 { archiveCandidate = nil } }),
            presenting: archiveCandidate
        ) { summary in
            Button("Archive") { Task { await vm.setArchived(true, summary) } }
            Button("Cancel", role: .cancel) {}
        } message: { summary in
            Text("\(MoneyFormatter.string(summary.outstandingMinor, summary.event.currency)) is still outstanding. Archiving keeps every amount visible and doesn't write anything off.")
        }
        .alert(
            deleteCandidate.map { "Delete “\($0.event.name)”?" } ?? "",
            isPresented: Binding(get: { deleteCandidate != nil }, set: { if !$0 { deleteCandidate = nil } }),
            presenting: deleteCandidate
        ) { summary in
            Button("Delete Event", role: .destructive) { Task { await vm.delete(summary) } }
            Button("Cancel", role: .cancel) {}
        } message: { summary in
            Text("This permanently removes the event, \(summary.peopleCount.counted("person", "people")), \(summary.expenseCount.counted("expense")) and \(summary.paymentCount.counted("recorded payment")) from this device.")
        }
    }

    private var createdEventLink: some View {
        NavigationLink(
            isActive: Binding(get: { openedEventID != nil }, set: { if !$0 { openedEventID = nil } }),
            destination: {
                if let id = openedEventID {
                    LazyView(EventDetailScreen(deps: deps, eventID: id, initialTab: openedEventTab))
                }
            },
            label: { EmptyView() }
        )
        .hidden()
    }

    @ViewBuilder
    private var content: some View {
        switch vm.state {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ErrorStateView(title: "Couldn't load events", message: message) { vm.reload() }
                .frame(maxHeight: .infinity)
        case .loaded:
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.m) {
                    header
                    if vm.isDatabaseEmpty {
                        EmptyStateView(
                            illustration: .emptyEvent,
                            title: "Start with a shared plan",
                            message: "Create an event for a trip, a dinner or a shared purchase, then add the people who share it.",
                            actionTitle: "New Event",
                            action: { sheet = .create }
                        )
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("emptyEventsState")
                    } else {
                        controls
                        list
                    }
                }
                .padding(.horizontal, Spacing.screen)
                .padding(.bottom, Spacing.l)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: Spacing.s) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Even Circle")
                    .ecScreenTitleFont()
                    .foregroundColor(.ecTextPrimary)
                    .accessibilityAddTraits(.isHeader)
                if !vm.isDatabaseEmpty {
                    Button {
                        sheet = .create
                    } label: {
                        Label("New Event", systemImage: "plus")
                    }
                    .buttonStyle(InlineButtonStyle())
                    .accessibilityIdentifier("newEventButton")
                }
            }
            Spacer(minLength: 0)
            if vm.showsHero {
                IllustrationView(.eventsHero)
            }
        }
        .padding(.top, Spacing.m)
    }

    private var controls: some View {
        VStack(spacing: Spacing.s) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.ecTextSecondary)
                    .accessibilityHidden(true)
                TextField("Search Events", text: $vm.searchText)
                    .disableAutocorrection(true)
                    .submitLabel(.search)
                    .accessibilityIdentifier("searchEventsField")
                if vm.isSearching {
                    Button {
                        vm.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.ecTextSecondary)
                    }
                    .frame(width: Metrics.minTapTarget, height: Metrics.minTapTarget)
                    .accessibilityLabel("Clear search")
                }
            }
            .ecInputField()

            Picker("Show", selection: $vm.scope) {
                ForEach(EventsListViewModel.Scope.allCases) { scope in
                    Text(scope.rawValue).tag(scope)
                }
            }
            .pickerStyle(.segmented)
            .frame(minHeight: 36)
        }
    }

    @ViewBuilder
    private var list: some View {
        if vm.visible.isEmpty {
            if vm.isSearching {
                EmptyStateView(
                    systemImage: "magnifyingglass",
                    title: "No events found",
                    message: "No \(vm.scope == .archived ? "archived" : "active") event matches “\(vm.trimmedSearch)”.",
                    actionTitle: "Clear Search",
                    action: { vm.searchText = "" }
                )
            } else if vm.scope == .archived {
                EmptyStateView(systemImage: "archivebox", title: "No archived events", message: "Archived events stay readable here with their balances.")
            } else {
                EmptyStateView(
                    systemImage: "circle.grid.2x2",
                    title: "No active events",
                    message: "All your events are archived. Start a new one or restore an archived event.",
                    actionTitle: "New Event",
                    action: { sheet = .create }
                )
            }
        } else {
            LazyVStack(spacing: Spacing.s) {
                ForEach(vm.visible) { summary in
                    EventCard(
                        summary: summary,
                        destination: {
                            EventDetailScreen(
                                deps: deps,
                                eventID: summary.id,
                                initialTab: summary.peopleCount < 2 && summary.expenseCount == 0 ? .people : .expenses
                            )
                        },
                        onEdit: { sheet = .edit(summary.aggregate) },
                        onDuplicate: { sheet = .duplicate(summary.aggregate) },
                        onArchive: {
                            if summary.hasOpenBalance {
                                archiveCandidate = summary
                            } else {
                                Task { await vm.setArchived(true, summary) }
                            }
                        },
                        onRestore: { Task { await vm.setArchived(false, summary) } },
                        onDelete: { deleteCandidate = summary }
                    )
                }
            }
        }
    }
}

private struct EventCard<Destination: View>: View {
    let summary: EventSummary
    @ViewBuilder let destination: () -> Destination
    let onEdit: () -> Void
    let onDuplicate: () -> Void
    let onArchive: () -> Void
    let onRestore: () -> Void
    let onDelete: () -> Void

    private var event: Event { summary.event }

    private var accent: Color {
        switch summary.status {
        case .noExpenses: return .ecDivider
        case .openBalance: return .ecLilac
        case .settled: return .ecMint
        }
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            NavigationLink(destination: LazyView(destination())) {
                cardBody
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("eventCard_\(event.name)")

            Menu {
                if event.isArchived {
                    Button(action: onRestore) { Label("Restore", systemImage: "arrow.uturn.backward") }
                    Button(role: .destructive, action: onDelete) { Label("Delete", systemImage: "trash") }
                } else {
                    Button(action: onEdit) { Label("Edit", systemImage: "pencil") }
                    Button(action: onDuplicate) { Label("Duplicate", systemImage: "plus.square.on.square") }
                    Button(action: onArchive) { Label("Archive", systemImage: "archivebox") }
                    Button(role: .destructive, action: onDelete) { Label("Delete", systemImage: "trash") }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.bold))
                    .foregroundColor(.ecTextSecondary)
                    .frame(width: Metrics.minTapTarget, height: Metrics.minTapTarget)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Actions for \(event.name)")
            .padding(6)
        }
    }

    private var cardBody: some View {
        HStack(alignment: .top, spacing: Spacing.s) {
            RoundedRectangle(cornerRadius: 2)
                .fill(accent)
                .frame(width: 4)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(alignment: .top, spacing: Spacing.xs) {
                    Image(systemName: event.isArchived ? "archivebox.fill" : "person.3.fill")
                        .foregroundColor(.ecLilac)
                        .accessibilityHidden(true)
                    Text(event.name)
                        .font(.headline)
                        .foregroundColor(.ecTextPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.trailing, 40)
                }
                Text("\(DateText.medium(event.eventDate)) · \(event.currency.code) · \(summary.peopleCount.counted("person", "people"))")
                    .ecCaptionFont()
                    .foregroundColor(.ecTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                LabeledValueRow(
                    label: "Total Expenses",
                    value: MoneyFormatter.string(summary.totalExpensesMinor, event.currency),
                    spokenValue: MoneyFormatter.spoken(summary.totalExpensesMinor, event.currency)
                )
                LabeledValueRow(
                    label: "Outstanding to Settle",
                    value: MoneyFormatter.string(summary.outstandingMinor, event.currency),
                    spokenValue: MoneyFormatter.spoken(summary.outstandingMinor, event.currency)
                )
                HStack(spacing: Spacing.xs) {
                    summary.status.chip
                    if event.isDemo { StatusChip(text: "Sample", color: .ecLilac, icon: "sparkles") }
                    if event.isArchived { StatusChip(text: "Archived", color: .ecTextSecondary, icon: "archivebox") }
                }
            }
        }
        .ecCard()
        .contentShape(Rectangle())
    }
}
