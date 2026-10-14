import Combine
import Foundation

@MainActor
final class EventsListViewModel: ObservableObject {
    enum Scope: String, CaseIterable, Identifiable {
        case active = "Active"
        case archived = "Archived"

        var id: String { rawValue }
    }

    @Published private(set) var state: LoadState<[EventSummary]> = .loading
    @Published var searchText = ""
    @Published var scope: Scope = .active
    @Published var alert: AlertMessage?

    let deps: AppDependencies
    private var cancellables: Set<AnyCancellable> = []
    private var loadTask: Task<Void, Never>?

    init(deps: AppDependencies) {
        self.deps = deps
        deps.repository.changes
            .sink { [weak self] _ in self?.reload() }
            .store(in: &cancellables)
    }

    func reload() {
        loadTask?.cancel()
        loadTask = Task { await load() }
    }

    func load() async {
        do {
            let summaries = try await deps.events.loadSummaries()
            guard !Task.isCancelled else { return }
            state = .loaded(summaries)
        } catch {
            // A read error is never shown as an empty list.
            if state.value == nil {
                state = .failed(UserMessage.text(for: error))
            } else {
                alert = .error(error, title: "Couldn't refresh events")
            }
        }
    }

    var summaries: [EventSummary] { state.value ?? [] }
    var isDatabaseEmpty: Bool { state.value?.isEmpty == true }
    var trimmedSearch: String { searchText.trimmingCharacters(in: .whitespacesAndNewlines) }
    var isSearching: Bool { !trimmedSearch.isEmpty }

    var scoped: [EventSummary] {
        summaries.filter { scope == .archived ? $0.event.isArchived : !$0.event.isArchived }
    }

    var visible: [EventSummary] {
        guard isSearching else { return scoped }
        return scoped.filter {
            $0.event.name.range(of: trimmedSearch, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    /// EC04 appears only for a non-empty active list that is not filtered to nothing.
    var showsHero: Bool { scope == .active && !scoped.isEmpty && !visible.isEmpty }

    func setArchived(_ archived: Bool, _ summary: EventSummary) async {
        do {
            try await deps.events.setArchived(archived, eventID: summary.id)
            deps.haptics.success()
        } catch {
            alert = .error(error, title: archived ? "Couldn't archive" : "Couldn't restore")
        }
    }

    func delete(_ summary: EventSummary) async {
        do {
            try await deps.events.deleteEvent(id: summary.id)
            deps.haptics.success()
        } catch {
            alert = .error(error, title: "Couldn't delete the event")
        }
    }
}
