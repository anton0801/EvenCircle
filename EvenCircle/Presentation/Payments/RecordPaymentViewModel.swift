import Foundation

@MainActor
final class RecordPaymentViewModel: ObservableObject {
    @Published var fromID: UUID? { didSet { clearError(.from); clearError(.amount) } }
    @Published var toID: UUID? { didSet { clearError(.to); clearError(.amount) } }
    @Published var amountText: String { didSet { clearError(.amount) } }
    @Published var date: Date { didSet { clearError(.date) } }
    @Published var note = "" { didSet { clearError(.note) } }
    @Published var confirmed = false { didSet { clearError(.confirmation) } }
    @Published private(set) var snapshot: EventSnapshot?
    @Published private(set) var errors: [PaymentDraftField: String] = [:]
    @Published private(set) var notice: String?
    @Published private(set) var isSaving = false
    @Published var alert: AlertMessage?

    let deps: AppDependencies
    private let eventID: UUID
    /// One intent to record → one operation ID; a retry can never create a duplicate.
    private let operationID = UUID()
    private let paymentID = UUID()

    init(deps: AppDependencies, aggregate: EventAggregate, suggestion: SuggestedPayment?) {
        self.deps = deps
        eventID = aggregate.event.id
        snapshot = try? EventSnapshot.make(aggregate)
        date = deps.clock.today.date()
        if let suggestion {
            fromID = suggestion.fromID
            toID = suggestion.toID
            amountText = MoneyFormatter.editable(min(suggestion.amountMinor, DomainLimits.maxPaymentMinor), aggregate.event.currency)
        } else {
            amountText = ""
        }
    }

    var currency: CurrencyCode { snapshot?.currency ?? .eur }
    var today: Date { deps.clock.today.date() }

    var debtors: [Person] {
        guard let snapshot else { return [] }
        return snapshot.people.filter { snapshot.balances.net(for: $0.id) < 0 }
    }

    var creditors: [Person] {
        guard let snapshot else { return [] }
        return snapshot.people.filter { snapshot.balances.net(for: $0.id) > 0 }
    }

    /// Maximum for This Payment = min(−Net_from, Net_to), capped by the one-record limit.
    var maximum: Int64? {
        guard let snapshot, let fromID, let toID else { return nil }
        return PaymentRules.maximum(fromID: fromID, toID: toID, balances: snapshot.balances)
    }

    var amountMinor: Int64? {
        if case .success(let value) = MoneyParser.parse(amountText, currency: currency) { return value }
        return nil
    }

    var amountHint: String? {
        guard !amountText.isEmpty else { return nil }
        if case .failure(let error) = MoneyParser.parse(amountText, currency: currency) { return error.message }
        return nil
    }

    func balanceText(_ person: Person) -> String {
        guard let snapshot else { return "" }
        return BalanceDirection(net: snapshot.balances.net(for: person.id)).text(currency)
    }

    private var draft: PaymentDraft {
        PaymentDraft(
            fromID: fromID,
            toID: toID,
            amountMinor: amountMinor,
            date: CalendarDate(date: date),
            note: note,
            confirmedOutsideApp: confirmed
        )
    }

    var canSubmit: Bool {
        guard let snapshot, !snapshot.isArchived, !isSaving else { return false }
        return deps.payments.validate(draft, aggregate: snapshot.aggregate, balances: snapshot.balances).isEmpty
    }

    private func clearError(_ field: PaymentDraftField) {
        if errors[field] != nil { errors[field] = nil }
    }

    /// Returns true once the record is stored (or was already stored by an earlier attempt).
    func submit() async -> Bool {
        guard let snapshot, !isSaving else { return false }
        if case .failure(let error) = MoneyParser.parse(amountText, currency: currency), !amountText.isEmpty {
            errors = [.amount: error.message]
            return false
        }
        errors = deps.payments.validate(draft, aggregate: snapshot.aggregate, balances: snapshot.balances)
        guard errors.isEmpty else { return false }

        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await deps.payments.record(draft, operationID: operationID, paymentID: paymentID, aggregate: snapshot.aggregate)
            deps.haptics.success()
            return true
        } catch RepositoryError.revisionConflict {
            await refreshAfterConflict()
            return false
        } catch let error as FieldError {
            alert = AlertMessage(title: "Check this payment", message: error.message)
            return false
        } catch {
            // The form stays filled and nothing is shown as recorded.
            alert = .error(error, title: "Couldn't record the payment")
            return false
        }
    }

    /// Recalculate balances, update the limit and ask for confirmation again.
    /// The entered amount is never reduced silently.
    private func refreshAfterConflict() async {
        guard let fresh = try? await deps.events.loadAggregate(id: eventID), let freshSnapshot = try? EventSnapshot.make(fresh) else {
            alert = AlertMessage(title: "Event unavailable", message: "This event is no longer available.")
            return
        }
        snapshot = freshSnapshot
        confirmed = false
        notice = "Balances changed. Review this payment."
        errors = deps.payments.validate(draft, aggregate: freshSnapshot.aggregate, balances: freshSnapshot.balances)
        errors[.confirmation] = nil
    }
}
