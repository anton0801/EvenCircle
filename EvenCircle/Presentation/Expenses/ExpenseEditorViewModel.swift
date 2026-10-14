import Foundation

struct ReviewRequest: Identifiable {
    let id = UUID()
    var preview: BalanceChangePreview
    var notice: String?
}

/// State for screens 08 (details), 09 (Equal/Shares split) and 10 (receipt items).
/// Nothing is written until the final Save; Back/Next only move between steps in memory.
@MainActor
final class ExpenseEditorViewModel: ObservableObject {
    enum Step: Equatable {
        case details, split, items
    }

    struct ItemState: Identifiable, Equatable {
        let id: UUID
        var title: String
        var quantity: Int
        var unitPriceMinor: Int64
        var recipients: [UUID]
    }

    struct FormState: Equatable {
        var title: String
        var amountText: String
        var payerID: UUID?
        var date: Date
        var note: String
        var method: SplitMethod
        var included: Set<UUID>
        /// Kept while switching Shares → Equal so the user can switch back; Equal saves weight 1.
        var weightTexts: [UUID: String]
        var items: [ItemState]
    }

    @Published var form: FormState
    @Published var step: Step = .details
    @Published private(set) var aggregate: EventAggregate
    @Published private(set) var errors: [ExpenseDraftField: String] = [:]
    @Published private(set) var previewedForm: FormState?
    @Published private(set) var previewExpense: Expense?
    @Published private(set) var isSaving = false
    @Published var alert: AlertMessage?
    @Published var pendingMethod: SplitMethod?
    @Published var review: ReviewRequest?
    @Published private(set) var isUnavailable = false

    let editing: Expense?
    let deps: AppDependencies
    /// One save intent → one operation ID, reused for retries after an uncertain result.
    let operationID = UUID()
    private let expenseID: UUID
    private var expectedRevision: Int64
    private let initialForm: FormState
    private var splitTouched: Bool

    init(deps: AppDependencies, aggregate: EventAggregate, editing: Expense?) {
        self.deps = deps
        self.aggregate = aggregate
        self.editing = editing
        expenseID = editing?.id ?? UUID()
        expectedRevision = aggregate.event.revision
        let allPeople = Set(aggregate.people.map(\.id))
        let currency = aggregate.event.currency

        let start: FormState
        if let expense = editing {
            var included = allPeople
            var weights: [UUID: String] = [:]
            var items: [ItemState] = []
            switch expense.method {
            case .equal:
                included = Set(expense.shares.map(\.personID))
            case .shares:
                included = Set(expense.shares.map(\.personID))
                for share in expense.shares { weights[share.personID] = String(share.weight ?? 1) }
            case .items:
                items = expense.items.sorted { $0.sortOrder < $1.sortOrder }.map {
                    ItemState(id: $0.id, title: $0.title, quantity: $0.quantity, unitPriceMinor: $0.unitPriceMinor, recipients: $0.shares.map(\.personID))
                }
            }
            start = FormState(
                title: expense.title,
                amountText: expense.method == .items ? "" : MoneyFormatter.editable(expense.amountMinor, currency),
                payerID: expense.payerID,
                date: expense.expenseDate.date(),
                note: expense.note ?? "",
                method: expense.method,
                included: included,
                weightTexts: weights,
                items: items
            )
            splitTouched = expense.method != .items
        } else {
            // New expense: Equal, today, no payer yet, everyone included.
            start = FormState(
                title: "", amountText: "", payerID: nil, date: deps.clock.today.date(), note: "",
                method: .equal, included: allPeople, weightTexts: [:], items: []
            )
            splitTouched = false
        }
        form = start
        initialForm = start
    }

    // MARK: - Derived values

    var currency: CurrencyCode { aggregate.event.currency }
    var people: [Person] { aggregate.orderedPeople }
    var hasChanges: Bool { form != initialForm }
    var isEditing: Bool { editing != nil }
    var today: Date { deps.clock.today.date() }

    var parsedAmount: Result<Int64, FieldError> {
        MoneyParser.parsePositive(form.amountText, currency: currency, limit: DomainLimits.maxExpenseMinor)
    }

    var amountMinor: Int64? {
        if form.method == .items { return receiptTotal }
        if case .success(let value) = parsedAmount { return value }
        return nil
    }

    func weight(for id: UUID) -> Int? {
        let text = (form.weightTexts[id] ?? "1").trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, text.allSatisfy({ $0.isASCII && $0.isNumber }), let value = Int(text),
              DomainLimits.weightRange.contains(value) else { return nil }
        return value
    }

    /// Exact allocations for the Equal/Shares step, or nil while the input is incomplete.
    var splitAllocations: [UUID: Int64]? {
        guard form.method != .items, let amount = amountMinor, !form.included.isEmpty else { return nil }
        var participants: [LargestRemainderAllocator.Participant] = []
        for id in form.included {
            let weight = form.method == .equal ? 1 : self.weight(for: id)
            guard let weight else { return nil }
            participants.append(.init(id, weight: weight))
        }
        return try? LargestRemainderAllocator.allocate(amount: amount, participants: participants)
    }

    var allocatedMinor: Int64 {
        if form.method == .items { return receiptAssignedTotals.values.reduce(0, +) }
        return splitAllocations?.values.reduce(0, +) ?? 0
    }

    func lineAmount(_ item: ItemState) -> Int64? {
        try? ReceiptCalculator.lineAmount(quantity: item.quantity, unitPriceMinor: item.unitPriceMinor)
    }

    /// Σ line amounts, or nil on overflow.
    var receiptTotal: Int64? {
        var total: Int64 = 0
        for item in form.items {
            guard let line = lineAmount(item), let sum = try? CheckedMath.add(total, line) else { return nil }
            total = sum
        }
        return total
    }

    func lineAllocations(_ item: ItemState) -> [UUID: Int64] {
        guard let amount = lineAmount(item), !item.recipients.isEmpty else { return [:] }
        return (try? LargestRemainderAllocator.equal(amount: amount, personIDs: item.recipients)) ?? [:]
    }

    var receiptAssignedTotals: [UUID: Int64] {
        var totals: [UUID: Int64] = [:]
        for item in form.items {
            for (id, value) in lineAllocations(item) { totals[id, default: 0] += value }
        }
        return totals
    }

    var unassignedItemsCount: Int { form.items.filter { $0.recipients.isEmpty }.count }

    var receiptProblem: String? {
        guard form.method == .items else { return nil }
        if form.items.isEmpty { return "Add at least one receipt item." }
        guard let total = receiptTotal else { return "The receipt total is too large to calculate." }
        if total > DomainLimits.maxExpenseMinor {
            return "The receipt total is above the limit of \(MoneyFormatter.string(DomainLimits.maxExpenseMinor, currency)) for one expense."
        }
        if let item = form.items.first(where: { (lineAmount($0) ?? .max) > DomainLimits.maxExpenseMinor }) {
            return "“\(item.title)” is above the limit for one expense."
        }
        if unassignedItemsCount > 0 { return "Assign people to every item before saving." }
        return nil
    }

    var isPreviewCurrent: Bool { previewedForm == form && previewExpense != nil }

    func personName(_ id: UUID) -> String { aggregate.personName(id) }

    // MARK: - Step 08

    private func detailIssues() -> [ExpenseDraftField: String] {
        var issues: [ExpenseDraftField: String] = [:]
        if let error = TextRules.validateRequired(form.title, field: "Title", range: DomainLimits.expenseTitleLength) {
            issues[.title] = error.message
        }
        if form.method != .items, case .failure(let error) = parsedAmount {
            issues[.amount] = error.message
        }
        if form.payerID == nil {
            issues[.payer] = "Choose who paid."
        } else if let payer = form.payerID, aggregate.person(payer) == nil {
            issues[.payer] = "This person is no longer in the event."
        }
        if CalendarDate(date: form.date) > deps.clock.today {
            issues[.date] = "The expense date can't be in the future."
        }
        if let error = TextRules.validateNote(form.note, maxLength: DomainLimits.expenseNoteMaxLength) {
            issues[.note] = error.message
        }
        return issues
    }

    /// Live hint for the amount field while typing.
    var amountHint: String? {
        guard form.method != .items, !form.amountText.isEmpty else { return nil }
        switch MoneyParser.parse(form.amountText, currency: currency) {
        case .failure(let error): return error.message
        case .success(let value):
            return MoneyParser.checkRange(value, currency: currency, limit: DomainLimits.maxExpenseMinor)?.message
        }
    }

    func revalidate(_ field: ExpenseDraftField) {
        guard errors[field] != nil else { return }
        errors[field] = detailIssues()[field]
    }

    /// Returns the first invalid field, or moves on to the split step.
    @discardableResult
    func next() -> ExpenseDraftField? {
        errors = detailIssues()
        if let first = Self.fieldOrder.first(where: { errors[$0] != nil }) { return first }
        if form.method == .shares { ensureDefaultWeights() }
        step = form.method == .items ? .items : .split
        return nil
    }

    static let fieldOrder: [ExpenseDraftField] = [.title, .amount, .payer, .date, .note]

    // MARK: - Method switching

    var methodChangeDescription: String {
        guard let pendingMethod else { return "" }
        if form.method == .items {
            return "Switching to \(pendingMethod.title) removes \(form.items.count.counted("receipt item")) from this expense."
        }
        return "Switching to Items resets the people and shares chosen for the \(form.method.title) split."
    }

    func requestMethod(_ method: SplitMethod) {
        guard method != form.method else { return }
        let crossesItems = (form.method == .items) != (method == .items)
        let hasData = form.method == .items ? !form.items.isEmpty : splitTouched
        if crossesItems && hasData {
            pendingMethod = method
        } else {
            applyMethod(method)
        }
    }

    func confirmPendingMethod() {
        if let method = pendingMethod { applyMethod(method) }
        pendingMethod = nil
    }

    private func applyMethod(_ method: SplitMethod) {
        let old = form.method
        let everyone = Set(people.map(\.id))
        if old == .items && method != .items {
            if form.amountText.trimmingCharacters(in: .whitespaces).isEmpty, let total = receiptTotal, total > 0,
               total <= DomainLimits.maxExpenseMinor {
                form.amountText = MoneyFormatter.editable(total, currency)
            }
            form.items = []
            form.included = everyone
            form.weightTexts = [:]
            splitTouched = false
        } else if old != .items && method == .items {
            form.included = everyone
            form.weightTexts = [:]
            splitTouched = false
        }
        form.method = method
        if method == .shares { ensureDefaultWeights() }
        errors[.amount] = nil
        if step != .details { step = method == .items ? .items : .split }
    }

    private func ensureDefaultWeights() {
        for id in form.included where form.weightTexts[id] == nil {
            form.weightTexts[id] = "1"
        }
    }

    // MARK: - Step 09

    func setIncluded(_ id: UUID, _ included: Bool) {
        splitTouched = true
        if included {
            form.included.insert(id)
            if form.weightTexts[id] == nil { form.weightTexts[id] = "1" }
        } else {
            form.included.remove(id)
        }
    }

    func includeEveryone() {
        splitTouched = true
        for person in people { setIncluded(person.id, true) }
    }

    func clearSelection() {
        splitTouched = true
        form.included = []
    }

    func setWeightText(_ id: UUID, _ text: String) {
        splitTouched = true
        form.weightTexts[id] = text
    }

    func stepWeight(_ id: UUID, by delta: Int) {
        let current = weight(for: id) ?? 1
        let next = min(max(current + delta, DomainLimits.weightRange.lowerBound), DomainLimits.weightRange.upperBound)
        setWeightText(id, String(next))
    }

    // MARK: - Step 10

    var canAddItem: Bool { form.items.count < DomainLimits.maxItemsPerExpense }

    func upsertItem(_ item: ItemState) {
        if let index = form.items.firstIndex(where: { $0.id == item.id }) {
            form.items[index] = item
        } else if canAddItem {
            form.items.append(item)
        }
    }

    func deleteItem(_ id: UUID) {
        form.items.removeAll { $0.id == id }
    }

    func assignAllPeople(to id: UUID) {
        guard let index = form.items.firstIndex(where: { $0.id == id }) else { return }
        form.items[index].recipients = people.map(\.id)
    }

    // MARK: - Preview & Save

    private func makeDraft() -> ExpenseDraft {
        var participants: [UUID: Int] = [:]
        if form.method != .items {
            for id in form.included {
                participants[id] = form.method == .equal ? 1 : (weight(for: id) ?? 0)
            }
        }
        return ExpenseDraft(
            id: expenseID,
            eventID: aggregate.event.id,
            title: form.title,
            amountMinor: form.method == .items ? nil : amountMinor,
            payerID: form.payerID,
            date: CalendarDate(date: form.date),
            note: form.note,
            method: form.method,
            participants: participants,
            items: form.items.map {
                ExpenseDraft.Item(id: $0.id, title: $0.title, quantity: $0.quantity, unitPriceMinor: $0.unitPriceMinor, recipientIDs: $0.recipients)
            },
            createdAt: editing?.createdAt,
            revision: editing?.revision ?? 0
        )
    }

    /// Builds the exact expense that Save would store and shows it inline.
    func preview() {
        switch deps.expenses.build(makeDraft(), in: aggregate) {
        case .success(let expense):
            errors = [:]
            previewExpense = expense
            previewedForm = form
        case .failure(let failure):
            var mapped: [ExpenseDraftField: String] = [:]
            for issue in failure.issues where mapped[issue.field] == nil { mapped[issue.field] = issue.message }
            errors = mapped
            previewExpense = nil
            previewedForm = nil
            if Self.fieldOrder.contains(where: { mapped[$0] != nil }) {
                step = .details
            }
        }
    }

    /// Returns the saved expense ID, or nil if a review step or an error intervened.
    func save() async -> UUID? {
        guard isPreviewCurrent, !isSaving else { return nil }
        guard case .success(let expense) = deps.expenses.build(makeDraft(), in: aggregate) else {
            preview()
            return nil
        }
        if isEditing && !aggregate.payments.isEmpty {
            // Editing after recorded payments: show Before / After first.
            do {
                review = ReviewRequest(preview: try deps.expenses.previewSave(expense, in: aggregate), notice: nil)
            } catch {
                alert = .error(error)
            }
            return nil
        }
        return await commit(expense)
    }

    func confirmReview() async -> UUID? {
        guard case .success(let expense) = deps.expenses.build(makeDraft(), in: aggregate) else {
            review = nil
            preview()
            return nil
        }
        return await commit(expense)
    }

    private func commit(_ expense: Expense) async -> UUID? {
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await deps.expenses.save(expense, operationID: operationID, expectedRevision: expectedRevision)
            deps.haptics.success()
            review = nil
            return expense.id
        } catch RepositoryError.revisionConflict {
            await refreshAfterConflict()
            return nil
        } catch {
            // The editor keeps every field; nothing is reported as saved.
            review = nil
            alert = .error(error, title: "Couldn't save the expense")
            return nil
        }
    }

    /// "Review Updated Event": reload, keep the user's input, require a new Preview.
    private func refreshAfterConflict() async {
        review = nil
        guard let fresh = try? await deps.events.loadAggregate(id: aggregate.event.id) else {
            isUnavailable = true
            return
        }
        if let editing, fresh.expense(editing.id) == nil {
            isUnavailable = true
            return
        }
        aggregate = fresh
        expectedRevision = fresh.event.revision
        let ids = Set(fresh.people.map(\.id))
        form.included = form.included.intersection(ids)
        if let payer = form.payerID, !ids.contains(payer) { form.payerID = nil }
        for index in form.items.indices {
            form.items[index].recipients.removeAll { !ids.contains($0) }
        }
        previewedForm = nil
        previewExpense = nil
        alert = AlertMessage(
            title: "Review Updated Event",
            message: "This event changed while you were editing. The latest people and balances are loaded – check the split and tap Preview again."
        )
    }
}
