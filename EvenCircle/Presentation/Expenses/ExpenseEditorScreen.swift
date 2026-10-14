import SwiftUI

/// Screens 08 → 09 / 10 in one sheet. The sheet owns the unsaved draft until Save.
struct ExpenseEditorScreen: View {
    @StateObject private var vm: ExpenseEditorViewModel
    private let onSaved: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDiscard = false

    init(deps: AppDependencies, aggregate: EventAggregate, editing: Expense?, onSaved: @escaping (UUID) -> Void) {
        _vm = StateObject(wrappedValue: ExpenseEditorViewModel(deps: deps, aggregate: aggregate, editing: editing))
        self.onSaved = onSaved
    }

    private var title: String {
        switch vm.step {
        case .details: return vm.isEditing ? "Edit Expense" : "Add Expense"
        case .split: return "Split Expense"
        case .items: return "Receipt Items"
        }
    }

    var body: some View {
        NavigationView {
            Group {
                if vm.isUnavailable {
                    VStack(spacing: Spacing.m) {
                        EmptyStateView(systemImage: "questionmark.folder", title: "Expense is no longer available",
                                       message: "It was removed while you were editing.")
                        Button("Back to Event") { dismiss() }.buttonStyle(PrimaryButtonStyle())
                    }
                    .padding(Spacing.screen)
                } else {
                    switch vm.step {
                    case .details: ExpenseDetailsStep(vm: vm)
                    case .split: SplitStep(vm: vm, onSave: save)
                    case .items: ItemsStep(vm: vm, onSave: save)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ecScreenBackground()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if vm.step == .details || vm.isUnavailable {
                        Button("Cancel") {
                            if vm.hasChanges && !vm.isUnavailable { confirmDiscard = true } else { dismiss() }
                        }
                        .accessibilityIdentifier("cancelExpenseButton")
                    } else {
                        Button {
                            vm.step = .details
                        } label: {
                            Label("Back", systemImage: "chevron.left").labelStyle(.titleAndIcon)
                        }
                        .accessibilityIdentifier("backToDetailsButton")
                    }
                }
            }
            .confirmationDialog("Discard this expense?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Discard Changes", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) {}
            } message: {
                Text("Unsaved changes are kept only while this editor is open.")
            }
            .confirmationDialog(
                "Change split method?",
                isPresented: Binding(get: { vm.pendingMethod != nil }, set: { if !$0 { vm.pendingMethod = nil } }),
                titleVisibility: .visible
            ) {
                Button("Confirm Change", role: .destructive) { vm.confirmPendingMethod() }
                Button("Keep Current Method", role: .cancel) { vm.pendingMethod = nil }
            } message: {
                Text(vm.methodChangeDescription)
            }
            .sheet(item: $vm.review) { request in
                ReviewBalanceChangesView(
                    title: "Review Balance Changes",
                    preview: request.preview,
                    explanation: "Recorded payments stay in the history. Balances may change direction.",
                    confirmTitle: "Save Expense",
                    destructive: false,
                    isWorking: vm.isSaving,
                    notice: request.notice,
                    onConfirm: {
                        Task {
                            if let id = await vm.confirmReview() { finish(id) }
                        }
                    },
                    onCancel: { vm.review = nil }
                )
            }
            .messageAlert($vm.alert)
        }
        .navigationViewStyle(.stack)
        .interactiveDismissDisabled(vm.hasChanges || vm.isSaving)
    }

    private func save() {
        Task {
            if let id = await vm.save() { finish(id) }
        }
    }

    private func finish(_ id: UUID) {
        dismiss()
        onSaved(id)
    }
}

// MARK: - 08 Details

private struct ExpenseDetailsStep: View {
    @ObservedObject var vm: ExpenseEditorViewModel
    @FocusState private var focus: ExpenseDraftField?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    FormField(label: "Title", required: true, error: vm.errors[.title], helper: "Up to 100 characters.") {
                        TextField("e.g. Dinner", text: $vm.form.title)
                            .focused($focus, equals: .title)
                            .submitLabel(.next)
                            .onSubmit { focus = vm.form.method == .items ? nil : .amount }
                            .ecInputField(hasError: vm.errors[.title] != nil)
                            .accessibilityIdentifier("expenseTitleField")
                            .onChange(of: vm.form.title) { _ in vm.revalidate(.title) }
                    }
                    .id(ExpenseDraftField.title)

                    FormField(label: "Split Method", required: true) {
                        Picker("Split Method", selection: Binding(get: { vm.form.method }, set: { vm.requestMethod($0) })) {
                            ForEach(SplitMethod.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("splitMethodPicker")
                    }

                    if vm.form.method == .items {
                        FormField(label: "Amount", helper: "Calculated from receipt items") {
                            HStack {
                                Text(vm.receiptTotal.map { MoneyFormatter.string($0, vm.currency) } ?? "—")
                                    .ecAmountFont()
                                    .foregroundColor(.ecTextSecondary)
                                Spacer()
                                Image(systemName: "lock.fill").foregroundColor(.ecTextSecondary).accessibilityHidden(true)
                            }
                            .ecInputField()
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("Amount, calculated from receipt items")
                        }
                    } else {
                        FormField(
                            label: "Amount (\(vm.currency.code))",
                            required: true,
                            error: vm.errors[.amount] ?? vm.amountHint,
                            helper: vm.currency.scale == 0 ? "Whole amounts only." : "Use up to \(vm.currency.scale) decimal places, without thousands separators."
                        ) {
                            HStack {
                                TextField(vm.currency.scale == 0 ? "0" : "0.00", text: $vm.form.amountText)
                                    .keyboardType(vm.currency.scale == 0 ? .numberPad : .decimalPad)
                                    .font(.title3.monospacedDigit())
                                    .focused($focus, equals: .amount)
                                    .accessibilityIdentifier("expenseAmountField")
                                    .onChange(of: vm.form.amountText) { _ in vm.revalidate(.amount) }
                                Text(vm.currency.code)
                                    .font(.callout.weight(.semibold))
                                    .foregroundColor(.ecTextSecondary)
                            }
                            .ecInputField(hasError: vm.errors[.amount] != nil || vm.amountHint != nil)
                        }
                        .id(ExpenseDraftField.amount)
                    }

                    FormField(label: "Paid By", required: true, error: vm.errors[.payer], helper: "The payer doesn't have to share the cost.") {
                        PersonPickerField(title: "Paid By", people: vm.people, selection: Binding(
                            get: { vm.form.payerID },
                            set: { vm.form.payerID = $0; vm.revalidate(.payer) }
                        ), hasError: vm.errors[.payer] != nil)
                        .accessibilityIdentifier("paidByPicker")
                    }
                    .id(ExpenseDraftField.payer)

                    FormField(label: "Date", required: true, error: vm.errors[.date], helper: "Can be before the event date; can't be in the future.") {
                        DatePicker("Date", selection: $vm.form.date, in: ...vm.today, displayedComponents: .date)
                            .labelsHidden()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .ecInputField(hasError: vm.errors[.date] != nil)
                    }
                    .id(ExpenseDraftField.date)

                    FormField(label: "Note", error: vm.errors[.note]) {
                        NoteEditor(text: $vm.form.note, maxLength: DomainLimits.expenseNoteMaxLength, hasError: vm.errors[.note] != nil)
                            .focused($focus, equals: .note)
                    }
                    .id(ExpenseDraftField.note)
                }
                .padding(Spacing.screen)
            }
            .safeAreaInset(edge: .bottom) {
                Button("Next") {
                    if let field = vm.next() {
                        focus = field == .payer || field == .date ? nil : field
                        withAnimation { proxy.scrollTo(field, anchor: .top) }
                        UIAccessibility.post(notification: .announcement, argument: vm.errors[field] ?? "Check the highlighted field")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("expenseNextButton")
                .ecBottomBar()
            }
            .keyboardDoneButton { focus = nil }
        }
    }
}

// MARK: - Shared header & preview

private struct DraftHeader: View {
    @ObservedObject var vm: ExpenseEditorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(TextRules.clean(vm.form.title))
                .font(.headline)
                .foregroundColor(.ecTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if let amount = vm.amountMinor {
                MoneyText(minor: amount, currency: vm.currency, hero: true)
            }
            if let payer = vm.form.payerID {
                Text("Paid by \(vm.personName(payer)) · \(DateText.medium(CalendarDate(date: vm.form.date)))")
                    .ecCaptionFont()
                    .foregroundColor(.ecTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .ecCard()
        .accessibilityElement(children: .combine)
    }
}

private struct PreviewBlock: View {
    @ObservedObject var vm: ExpenseEditorViewModel
    let onSave: () -> Void

    var body: some View {
        if let expense = vm.previewExpense, vm.isPreviewCurrent {
            VStack(alignment: .leading, spacing: Spacing.s) {
                SectionHeader(title: "Preview", subtitle: "This is exactly what will be saved.")
                LabeledValueRow(label: "Title", value: expense.title)
                LabeledValueRow(label: "Paid By", value: vm.personName(expense.payerID))
                LabeledValueRow(label: "Date", value: DateText.medium(expense.expenseDate))
                LabeledValueRow(label: "Method", value: expense.method.title)
                Divider().background(Color.ecDivider)
                ForEach(expense.shares, id: \.personID) { share in
                    LabeledValueRow(
                        label: vm.personName(share.personID) + (expense.method == .shares ? " · \(share.weight ?? 1) \((share.weight ?? 1) == 1 ? "share" : "shares")" : ""),
                        value: MoneyFormatter.string(share.allocatedMinor, vm.currency),
                        spokenValue: MoneyFormatter.spoken(share.allocatedMinor, vm.currency)
                    )
                }
                Divider().background(Color.ecDivider)
                LabeledValueRow(
                    label: "Total",
                    value: MoneyFormatter.string(expense.amountMinor, vm.currency),
                    spokenValue: MoneyFormatter.spoken(expense.amountMinor, vm.currency),
                    emphasized: true
                )
                Button(vm.isSaving ? "Saving…" : "Save Expense", action: onSave)
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(vm.isSaving || expense.totalAllocatedMinor != expense.amountMinor)
                    .accessibilityIdentifier("saveExpenseButton")
            }
            .ecCard()
            .id("preview")
        } else if vm.previewedForm != nil {
            InfoNote(text: "The split changed after the preview. Tap Preview again before saving.", icon: "arrow.clockwise")
        }
    }
}

// MARK: - 09 Split (Equal / Shares)

private struct SplitStep: View {
    @ObservedObject var vm: ExpenseEditorViewModel
    let onSave: () -> Void
    @FocusState private var weightFocus: UUID?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.m) {
                    DraftHeader(vm: vm)

                    Picker("Split", selection: Binding(get: { vm.form.method }, set: { vm.requestMethod($0) })) {
                        Text("Equal").tag(SplitMethod.equal)
                        Text("Shares").tag(SplitMethod.shares)
                    }
                    .pickerStyle(.segmented)

                    HStack(spacing: Spacing.xs) {
                        Button("Include Everyone") { vm.includeEveryone() }
                            .buttonStyle(InlineButtonStyle())
                        Button("Clear Selection") { vm.clearSelection() }
                            .buttonStyle(InlineButtonStyle())
                        Spacer(minLength: 0)
                    }

                    if let error = vm.errors[.participants] {
                        InfoNote(text: error, icon: "exclamationmark.circle.fill", color: .ecCoral)
                    } else if vm.form.included.isEmpty {
                        InfoNote(text: "Select at least one person.", icon: "exclamationmark.circle.fill", color: .ecCoral)
                    }

                    VStack(spacing: Spacing.xs) {
                        ForEach(vm.people) { person in
                            participantRow(person)
                        }
                    }

                    totals
                    Button("Preview") {
                        vm.preview()
                        withAnimation { proxy.scrollTo("preview", anchor: .top) }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(vm.splitAllocations == nil)
                    .accessibilityIdentifier("previewExpenseButton")

                    PreviewBlock(vm: vm, onSave: onSave)
                }
                .padding(Spacing.screen)
            }
            .keyboardDoneButton { weightFocus = nil }
        }
    }

    private func participantRow(_ person: Person) -> some View {
        let included = vm.form.included.contains(person.id)
        let allocation = vm.splitAllocations?[person.id]
        let weightError = included && vm.form.method == .shares && vm.weight(for: person.id) == nil
        return VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.s) {
                Toggle(isOn: Binding(get: { included }, set: { vm.setIncluded(person.id, $0) })) {
                    HStack(spacing: Spacing.s) {
                        AvatarView(person: person, size: 36)
                        Text(person.name)
                            .foregroundColor(.ecTextPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .toggleStyle(SwitchToggleStyle(tint: .ecBlue))
                .accessibilityLabel("Include \(person.name)")
                .accessibilityIdentifier("include_\(person.name)")
            }
            if included {
                AdaptiveRow {
                    if vm.form.method == .shares {
                        HStack(spacing: 6) {
                            IconButton(systemName: "minus", label: "Fewer shares for \(person.name)") { vm.stepWeight(person.id, by: -1) }
                            TextField("1", text: Binding(get: { vm.form.weightTexts[person.id] ?? "1" }, set: { vm.setWeightText(person.id, $0) }))
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.center)
                                .font(.body.monospacedDigit())
                                .frame(width: 64)
                                .focused($weightFocus, equals: person.id)
                                .ecInputField(hasError: weightError)
                                .accessibilityLabel("Shares for \(person.name)")
                            IconButton(systemName: "plus", label: "More shares for \(person.name)") { vm.stepWeight(person.id, by: 1) }
                            Text((vm.weight(for: person.id) ?? 0) == 1 ? "share" : "shares")
                                .ecCaptionFont()
                                .foregroundColor(.ecTextSecondary)
                        }
                    } else {
                        Text("Equal share")
                            .ecCaptionFont()
                            .foregroundColor(.ecTextSecondary)
                    }
                } trailing: {
                    Text(allocation.map { MoneyFormatter.string($0, vm.currency) } ?? "—")
                        .ecAmountFont()
                        .foregroundColor(.ecTextPrimary)
                        .accessibilityLabel(allocation.map { MoneyFormatter.spoken($0, vm.currency) } ?? "Not calculated yet")
                }
                if weightError {
                    Text(vm.errors[.weight(person.id)] ?? "Use a whole number from 1 to 1000.")
                        .ecCaptionFont()
                        .foregroundColor(.ecCoral)
                }
                if allocation == 0 {
                    Text("Gets 0 at this amount because of rounding. The total is unchanged.")
                        .ecCaptionFont()
                        .foregroundColor(.ecTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .ecCard(padding: 14)
    }

    private var totals: some View {
        let amount = vm.amountMinor ?? 0
        let allocated = vm.allocatedMinor
        return VStack(alignment: .leading, spacing: 4) {
            LabeledValueRow(label: "Amount", value: MoneyFormatter.string(amount, vm.currency), spokenValue: MoneyFormatter.spoken(amount, vm.currency))
            LabeledValueRow(label: "Allocated", value: MoneyFormatter.string(allocated, vm.currency), spokenValue: MoneyFormatter.spoken(allocated, vm.currency))
            LabeledValueRow(
                label: "Remaining",
                value: MoneyFormatter.string(amount - allocated, vm.currency),
                spokenValue: MoneyFormatter.spoken(amount - allocated, vm.currency),
                valueColor: amount == allocated ? .ecTextPrimary : .ecCoral
            )
            InfoNote(text: "Small rounding differences are included in the shown amounts.")
        }
        .ecCard()
    }
}

// MARK: - 10 Receipt Items

private struct ItemsStep: View {
    @ObservedObject var vm: ExpenseEditorViewModel
    let onSave: () -> Void
    @State private var editingItem: ExpenseEditorViewModel.ItemState?
    @State private var deleteCandidate: ExpenseEditorViewModel.ItemState?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.m) {
                    DraftHeader(vm: vm)
                    InfoNote(text: "Enter each line as paid, after any discount. Add a separate line for a tip or service fee and choose who shares it.")

                    if vm.form.items.isEmpty {
                        EmptyStateView(
                            systemImage: "list.bullet.rectangle",
                            title: "Add Your First Item",
                            message: "Each line is split equally between the people you assign to it."
                        )
                    } else {
                        VStack(spacing: Spacing.xs) {
                            ForEach(vm.form.items) { item in
                                itemCard(item)
                            }
                        }
                    }

                    Button {
                        editingItem = ExpenseEditorViewModel.ItemState(id: UUID(), title: "", quantity: 1, unitPriceMinor: 0, recipients: [])
                    } label: {
                        Label("Add Item", systemImage: "plus")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(!vm.canAddItem)
                    .accessibilityIdentifier("addItemButton")
                    if !vm.canAddItem {
                        InfoNote(text: "An expense can have up to \(DomainLimits.maxItemsPerExpense) items.")
                    }

                    summary

                    if let problem = vm.receiptProblem, !vm.form.items.isEmpty {
                        InfoNote(text: problem, icon: "exclamationmark.circle.fill", color: .ecCoral)
                    }
                    if let error = vm.errors[.items] {
                        InfoNote(text: error, icon: "exclamationmark.circle.fill", color: .ecCoral)
                    }

                    Button("Preview") {
                        vm.preview()
                        withAnimation { proxy.scrollTo("preview", anchor: .top) }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(vm.receiptProblem != nil)
                    .accessibilityIdentifier("previewExpenseButton")

                    PreviewBlock(vm: vm, onSave: onSave)
                }
                .padding(Spacing.screen)
            }
        }
        .sheet(item: $editingItem) { item in
            ReceiptItemEditor(
                item: item,
                isNew: !vm.form.items.contains { $0.id == item.id },
                people: vm.people,
                currency: vm.currency,
                onSave: { vm.upsertItem($0) }
            )
        }
        .alert(
            deleteCandidate.map { "Delete “\($0.title)”?" } ?? "",
            isPresented: Binding(get: { deleteCandidate != nil }, set: { if !$0 { deleteCandidate = nil } }),
            presenting: deleteCandidate
        ) { item in
            Button("Delete Item", role: .destructive) { vm.deleteItem(item.id) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("The line is removed from this unsaved receipt.")
        }
    }

    private func itemCard(_ item: ExpenseEditorViewModel.ItemState) -> some View {
        let line = vm.lineAmount(item)
        let allocations = vm.lineAllocations(item)
        let hasError = vm.errors[.item(item.id)] != nil || item.recipients.isEmpty
        return VStack(alignment: .leading, spacing: Spacing.xs) {
            Button { editingItem = item } label: {
                AdaptiveRow {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.headline)
                            .foregroundColor(.ecTextPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("\(item.quantity) × \(MoneyFormatter.string(item.unitPriceMinor, vm.currency))")
                            .ecCaptionFont()
                            .foregroundColor(.ecTextSecondary)
                    }
                } trailing: {
                    Text(line.map { MoneyFormatter.string($0, vm.currency) } ?? "Too large")
                        .ecAmountFont()
                        .foregroundColor(.ecTextPrimary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Edit item")

            if item.recipients.isEmpty {
                Text("Unassigned – choose who shares this item.")
                    .ecCaptionFont()
                    .foregroundColor(.ecCoral)
            } else {
                ForEach(item.recipients, id: \.self) { id in
                    HStack {
                        Text(vm.personName(id))
                            .ecCaptionFont()
                            .foregroundColor(.ecTextSecondary)
                        Spacer()
                        Text(MoneyFormatter.string(allocations[id] ?? 0, vm.currency))
                            .ecCaptionFont()
                            .monospacedDigit()
                            .foregroundColor(.ecTextSecondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            if let error = vm.errors[.item(item.id)] {
                Text(error).ecCaptionFont().foregroundColor(.ecCoral)
            }
            HStack(spacing: Spacing.xs) {
                Button("Assign All People") { vm.assignAllPeople(to: item.id) }
                    .buttonStyle(InlineButtonStyle())
                Spacer(minLength: 0)
                Button {
                    deleteCandidate = item
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .buttonStyle(InlineButtonStyle(tint: .ecCoral))
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: Radius.card).fill(Color.ecSurface))
        .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(hasError ? Color.ecCoral.opacity(0.7) : Color.clear, lineWidth: 1))
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledValueRow(
                label: "Receipt Total",
                value: vm.receiptTotal.map { MoneyFormatter.string($0, vm.currency) } ?? "Too large",
                emphasized: true
            )
            LabeledValueRow(label: "Unassigned Items", value: "\(vm.unassignedItemsCount)",
                            valueColor: vm.unassignedItemsCount > 0 ? .ecCoral : .ecTextPrimary)
            if !vm.receiptAssignedTotals.isEmpty {
                Divider().background(Color.ecDivider)
                ForEach(vm.people.filter { vm.receiptAssignedTotals[$0.id] != nil }) { person in
                    LabeledValueRow(
                        label: person.name,
                        value: MoneyFormatter.string(vm.receiptAssignedTotals[person.id] ?? 0, vm.currency),
                        spokenValue: MoneyFormatter.spoken(vm.receiptAssignedTotals[person.id] ?? 0, vm.currency)
                    )
                }
            }
            InfoNote(text: "Small rounding differences are included in the shown amounts.")
        }
        .ecCard()
    }
}

/// Add / Edit Item sheet. Cancel never creates an empty line.
private struct ReceiptItemEditor: View {
    let item: ExpenseEditorViewModel.ItemState
    let isNew: Bool
    let people: [Person]
    let currency: CurrencyCode
    let onSave: (ExpenseEditorViewModel.ItemState) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var quantityText: String
    @State private var priceText: String
    @State private var recipients: [UUID]
    @State private var errors: [String: String] = [:]
    @State private var confirmDiscard = false
    @FocusState private var focus: String?

    init(item: ExpenseEditorViewModel.ItemState, isNew: Bool, people: [Person], currency: CurrencyCode,
         onSave: @escaping (ExpenseEditorViewModel.ItemState) -> Void) {
        self.item = item
        self.isNew = isNew
        self.people = people
        self.currency = currency
        self.onSave = onSave
        _name = State(initialValue: item.title)
        _quantityText = State(initialValue: String(item.quantity))
        _priceText = State(initialValue: item.unitPriceMinor > 0 ? MoneyFormatter.editable(item.unitPriceMinor, currency) : "")
        _recipients = State(initialValue: item.recipients)
    }

    private var quantity: Int? {
        let text = quantityText.trimmingCharacters(in: .whitespaces)
        guard text.allSatisfy({ $0.isASCII && $0.isNumber }), let value = Int(text), DomainLimits.quantityRange.contains(value) else { return nil }
        return value
    }

    private var price: Int64? {
        if case .success(let value) = MoneyParser.parsePositive(priceText, currency: currency, limit: DomainLimits.maxUnitPriceMinor) { return value }
        return nil
    }

    private var lineTotal: Int64? {
        guard let quantity, let price else { return nil }
        return try? ReceiptCalculator.lineAmount(quantity: quantity, unitPriceMinor: price)
    }

    private var hasChanges: Bool {
        name != item.title || quantityText != String(item.quantity) || recipients != item.recipients
            || priceText != (item.unitPriceMinor > 0 ? MoneyFormatter.editable(item.unitPriceMinor, currency) : "")
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    FormField(label: "Item Name", required: true, error: errors["name"]) {
                        TextField("e.g. Pizza or Service fee", text: $name)
                            .focused($focus, equals: "name")
                            .ecInputField(hasError: errors["name"] != nil)
                            .accessibilityIdentifier("itemNameField")
                    }
                    HStack(alignment: .top, spacing: Spacing.s) {
                        FormField(label: "Quantity", required: true, error: errors["quantity"]) {
                            TextField("1", text: $quantityText)
                                .keyboardType(.numberPad)
                                .focused($focus, equals: "quantity")
                                .ecInputField(hasError: errors["quantity"] != nil)
                                .accessibilityIdentifier("itemQuantityField")
                        }
                        .frame(maxWidth: 120)
                        FormField(label: "Unit Price (\(currency.code))", required: true, error: errors["price"]) {
                            TextField(currency.scale == 0 ? "0" : "0.00", text: $priceText)
                                .keyboardType(currency.scale == 0 ? .numberPad : .decimalPad)
                                .focused($focus, equals: "price")
                                .ecInputField(hasError: errors["price"] != nil)
                                .accessibilityIdentifier("itemPriceField")
                        }
                    }
                    LabeledValueRow(
                        label: "Line Total",
                        value: lineTotal.map { MoneyFormatter.string($0, currency) } ?? "—",
                        emphasized: true
                    )
                    .ecCard()

                    FormField(label: "Shared By", required: true, error: errors["recipients"],
                              helper: "Split equally between the selected people. Leave empty to assign later.") {
                        VStack(spacing: Spacing.xs) {
                            Button("Select All") { recipients = people.map(\.id) }
                                .buttonStyle(InlineButtonStyle())
                                .frame(maxWidth: .infinity, alignment: .leading)
                            ForEach(people) { person in
                                Toggle(isOn: Binding(
                                    get: { recipients.contains(person.id) },
                                    set: { on in
                                        if on { if !recipients.contains(person.id) { recipients.append(person.id) } }
                                        else { recipients.removeAll { $0 == person.id } }
                                    }
                                )) {
                                    HStack(spacing: Spacing.s) {
                                        AvatarView(person: person, size: 32)
                                        Text(person.name).foregroundColor(.ecTextPrimary)
                                    }
                                }
                                .toggleStyle(SwitchToggleStyle(tint: .ecBlue))
                                .frame(minHeight: Metrics.minTapTarget)
                                .accessibilityIdentifier("itemRecipient_\(person.name)")
                            }
                        }
                        .ecCard(padding: Spacing.s)
                    }
                }
                .padding(Spacing.screen)
            }
            .ecScreenBackground()
            .navigationTitle(isNew ? "Add Item" : "Edit Item")
            .navigationBarTitleDisplayMode(.inline)
            .keyboardDoneButton { focus = nil }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { if hasChanges { confirmDiscard = true } else { dismiss() } }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save Item", action: save)
                        .accessibilityIdentifier("saveItemButton")
                }
            }
            .confirmationDialog("Discard this item?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Discard Changes", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) {}
            }
        }
        .navigationViewStyle(.stack)
        .interactiveDismissDisabled(hasChanges)
    }

    private func save() {
        var issues: [String: String] = [:]
        if let error = TextRules.validateRequired(name, field: "Item name", range: DomainLimits.itemTitleLength) {
            issues["name"] = error.message
        }
        if quantity == nil { issues["quantity"] = "Use a whole number from 1 to 999." }
        if case .failure(let error) = MoneyParser.parsePositive(priceText, currency: currency, limit: DomainLimits.maxUnitPriceMinor) {
            issues["price"] = error.message
        }
        if issues.isEmpty, let total = lineTotal, total > DomainLimits.maxExpenseMinor {
            issues["price"] = "Quantity × unit price is above the limit for one expense."
        }
        errors = issues
        guard issues.isEmpty, let quantity, let price else {
            focus = ["name", "quantity", "price"].first { issues[$0] != nil }
            return
        }
        onSave(.init(id: item.id, title: TextRules.clean(name), quantity: quantity, unitPriceMinor: price, recipients: recipients))
        dismiss()
    }
}
