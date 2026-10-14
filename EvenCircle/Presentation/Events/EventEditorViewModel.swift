import Foundation

@MainActor
final class EventEditorViewModel: ObservableObject {
    struct FormState: Equatable {
        var name: String
        var date: Date
        var currency: CurrencyCode
        var note: String
    }

    @Published var form: FormState
    @Published private(set) var errors: [EventFormField: String] = [:]
    @Published private(set) var isSaving = false
    @Published var alert: AlertMessage?
    @Published private(set) var currencyLocked: Bool
    @Published private(set) var peopleToCopy: [PersonTemplate]

    let mode: EventEditorScreen.Mode
    private let deps: AppDependencies
    private let initial: FormState
    private var expectedRevision: Int64
    /// Generated once per form so a double tap or retry can create at most one event.
    private let newEventID = UUID()

    init(deps: AppDependencies, mode: EventEditorScreen.Mode) {
        self.deps = deps
        self.mode = mode
        let today = deps.clock.today.date()
        let start: FormState
        switch mode {
        case .create:
            start = FormState(name: "", date: today, currency: deps.settings.current.defaultCurrency, note: "")
            currencyLocked = false
            peopleToCopy = []
            expectedRevision = 0
        case .edit(let aggregate):
            let event = aggregate.event
            start = FormState(name: event.name, date: event.eventDate.date(), currency: event.currency, note: event.note ?? "")
            currencyLocked = event.currencyLocked || !aggregate.expenses.isEmpty
            peopleToCopy = []
            expectedRevision = event.revision
        case .duplicate(let aggregate):
            let template = deps.events.duplicateTemplate(from: aggregate)
            start = FormState(name: template.form.name, date: template.form.date.date(), currency: template.form.currency, note: "")
            currencyLocked = false
            peopleToCopy = template.people
            expectedRevision = 0
        }
        form = start
        initial = start
    }

    var title: String {
        switch mode {
        case .create: return "New Event"
        case .edit: return "Edit Event"
        case .duplicate: return "Duplicate Event"
        }
    }

    var primaryTitle: String {
        if case .edit = mode { return "Save Changes" }
        return "Create Event"
    }

    var hasChanges: Bool { form != initial }

    private var domainForm: EventForm {
        EventForm(name: form.name, date: CalendarDate(date: form.date), currency: form.currency, note: form.note)
    }

    func validateField(_ field: EventFormField) {
        let issues = EventRules.validate(domainForm)
        errors[field] = issues[field]
    }

    /// Returns the created event's ID (nil for edits) on success.
    func submit() async -> (success: Bool, createdID: UUID?) {
        guard !isSaving else { return (false, nil) }
        errors = EventRules.validate(domainForm)
        guard errors.isEmpty else { return (false, nil) }
        isSaving = true
        defer { isSaving = false }
        do {
            switch mode {
            case .create:
                try await deps.events.createEvent(id: newEventID, form: domainForm, people: [])
                deps.haptics.success()
                return (true, newEventID)
            case .duplicate:
                try await deps.events.createEvent(id: newEventID, form: domainForm, people: peopleToCopy)
                deps.haptics.success()
                return (true, newEventID)
            case .edit(let aggregate):
                try await deps.events.updateEvent(id: aggregate.event.id, form: domainForm, expectedRevision: expectedRevision)
                deps.haptics.success()
                return (true, nil)
            }
        } catch RepositoryError.revisionConflict {
            await refreshAfterConflict()
            return (false, nil)
        } catch {
            // The form stays filled; nothing is reported as saved.
            alert = .error(error, title: "Couldn't save the event")
            return (false, nil)
        }
    }

    private func refreshAfterConflict() async {
        guard case .edit(let aggregate) = mode,
              let fresh = try? await deps.events.loadAggregate(id: aggregate.event.id)
        else {
            alert = AlertMessage(title: "Event unavailable", message: "This event is no longer available.")
            return
        }
        expectedRevision = fresh.event.revision
        currencyLocked = fresh.event.currencyLocked || !fresh.expenses.isEmpty
        if currencyLocked { form.currency = fresh.event.currency }
        alert = AlertMessage(title: "Event changed", message: "This event was updated elsewhere. Your edits are kept – review them and save again.")
    }
}
