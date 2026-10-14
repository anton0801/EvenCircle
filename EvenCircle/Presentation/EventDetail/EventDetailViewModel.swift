import Combine
import Foundation

enum EventTab: String, CaseIterable, Identifiable {
    case expenses = "Expenses"
    case people = "People"
    case balances = "Balances"

    var id: String { rawValue }
}

/// One consistent snapshot of an event plus everything derived from it.
/// Balances and suggestions are recomputed from saved records on every load; nothing derived is stored.
struct EventSnapshot: Equatable {
    let aggregate: EventAggregate
    let balances: EventBalances
    let suggestions: [SuggestedPayment]

    var event: Event { aggregate.event }
    var currency: CurrencyCode { aggregate.event.currency }
    var isArchived: Bool { aggregate.event.isArchived }
    var people: [Person] { aggregate.orderedPeople }
    var canAddExpense: Bool { aggregate.people.count >= 2 }

    static func make(_ aggregate: EventAggregate) throws -> EventSnapshot {
        let balances = try BalanceCalculator.calculate(aggregate)
        return EventSnapshot(aggregate: aggregate, balances: balances, suggestions: PaymentSuggestionBuilder.build(from: balances.people))
    }
}

/// Shared by the Expenses, People and Balances tabs and the screens pushed from them.
@MainActor
final class EventDetailViewModel: ObservableObject {
    @Published private(set) var state: LoadState<EventSnapshot> = .loading
    @Published private(set) var isMissing = false
    @Published var alert: AlertMessage?
    @Published private(set) var isWorking = false

    let eventID: UUID
    let deps: AppDependencies
    private var cancellables: Set<AnyCancellable> = []
    private var loadTask: Task<Void, Never>?

    init(deps: AppDependencies, eventID: UUID) {
        self.deps = deps
        self.eventID = eventID
        deps.repository.changes
            .filter { change in
                if case .event(let id) = change { return id == eventID }
                return true
            }
            .sink { [weak self] _ in self?.reload() }
            .store(in: &cancellables)
    }

    var snapshot: EventSnapshot? { state.value }

    func reload() {
        loadTask?.cancel()
        loadTask = Task { await load() }
    }

    func load() async {
        do {
            guard let aggregate = try await deps.events.loadAggregate(id: eventID) else {
                isMissing = true
                return
            }
            let snapshot = try await Task.detached(priority: .userInitiated) { try EventSnapshot.make(aggregate) }.value
            guard !Task.isCancelled else { return }
            isMissing = false
            state = .loaded(snapshot)
        } catch {
            if state.value == nil {
                state = .failed(UserMessage.text(for: error))
            } else {
                alert = .error(error, title: "Couldn't refresh this event")
            }
        }
    }

    /// Reads the latest saved state directly (used right before confirming a change).
    func freshSnapshot() async throws -> EventSnapshot? {
        guard let aggregate = try await deps.events.loadAggregate(id: eventID) else { return nil }
        return try EventSnapshot.make(aggregate)
    }

    func setArchived(_ archived: Bool) async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await deps.events.setArchived(archived, eventID: eventID)
            deps.haptics.success()
        } catch {
            alert = .error(error, title: archived ? "Couldn't archive" : "Couldn't restore")
        }
    }

    func deletePerson(_ person: Person) async {
        guard let snapshot else { return }
        do {
            try await deps.people.deletePerson(person.id, in: snapshot.aggregate)
            deps.haptics.success()
        } catch RepositoryError.personLinked {
            alert = AlertMessage(title: "Can't delete \(person.name)", message: "This person is linked to saved records.")
        } catch RepositoryError.revisionConflict {
            reload()
            alert = AlertMessage(title: "Event changed", message: "The event was updated. Review the people list and try again.")
        } catch {
            alert = .error(error, title: "Couldn't delete \(person.name)")
        }
    }
}
