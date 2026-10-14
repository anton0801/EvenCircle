import SwiftUI

/// Screen 13: a personal record of a transfer already made outside the app. Nothing is sent or paid here.
struct RecordPaymentScreen: View {
    @StateObject private var vm: RecordPaymentViewModel
    private let onRecorded: () -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focus: PaymentDraftField?

    init(deps: AppDependencies, aggregate: EventAggregate, suggestion: SuggestedPayment?, onRecorded: @escaping () -> Void) {
        _vm = StateObject(wrappedValue: RecordPaymentViewModel(deps: deps, aggregate: aggregate, suggestion: suggestion))
        self.onRecorded = onRecorded
    }

    var body: some View {
        NavigationView {
            ScrollView {
                if let snapshot = vm.snapshot {
                    form(snapshot)
                        .padding(Spacing.screen)
                } else {
                    ErrorStateView(title: "Balances unavailable", message: "Balances for this event couldn't be calculated.") {
                        dismiss()
                    }
                }
            }
            .ecScreenBackground()
            .safeAreaInset(edge: .bottom) {
                Button(vm.isSaving ? "Recording…" : "Record Payment") {
                    Task {
                        if await vm.submit() {
                            dismiss()
                            onRecorded()
                        } else if let first = [PaymentDraftField.amount, .note].first(where: { vm.errors[$0] != nil }) {
                            focus = first
                        }
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!vm.canSubmit)
                .accessibilityIdentifier("recordPaymentButton")
                .ecBottomBar()
            }
            .navigationTitle("Record Payment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(vm.isSaving)
                }
            }
            .keyboardDoneButton { focus = nil }
            .messageAlert($vm.alert)
        }
        .navigationViewStyle(.stack)
        .interactiveDismissDisabled(vm.isSaving)
    }

    private func form(_ snapshot: EventSnapshot) -> some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            HStack(alignment: .top, spacing: Spacing.s) {
                IllustrationView(.paymentNote)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Even Circle does not move money.")
                        .font(.callout.weight(.semibold))
                        .foregroundColor(.ecTextPrimary)
                    Text("Record a transfer that already happened outside the app. Partial amounts reduce the open balance.")
                        .ecCaptionFont()
                        .foregroundColor(.ecTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .ecCard()

            if let notice = vm.notice {
                InfoNote(text: notice, icon: "arrow.triangle.2.circlepath", color: .ecLilac)
                    .ecCard(padding: Spacing.s)
                    .accessibilityIdentifier("balancesChangedNotice")
            }
            if snapshot.isArchived {
                ArchivedBanner()
            }

            FormField(label: "From", required: true, error: vm.errors[.from], helper: "Someone who currently has an amount to pay.") {
                PersonPickerField(
                    title: "From",
                    people: vm.debtors,
                    selection: $vm.fromID,
                    detail: { vm.balanceText($0) },
                    hasError: vm.errors[.from] != nil,
                    placeholder: vm.debtors.isEmpty ? "Nobody has anything to pay" : "Select who paid"
                )
                .accessibilityIdentifier("paymentFromPicker")
            }

            FormField(label: "To", required: true, error: vm.errors[.to], helper: "Someone who currently has an amount to receive.") {
                PersonPickerField(
                    title: "To",
                    people: vm.creditors.filter { $0.id != vm.fromID },
                    selection: $vm.toID,
                    detail: { vm.balanceText($0) },
                    hasError: vm.errors[.to] != nil,
                    placeholder: "Select who received it"
                )
                .accessibilityIdentifier("paymentToPicker")
            }

            FormField(
                label: "Amount (\(vm.currency.code))",
                required: true,
                error: vm.errors[.amount] ?? vm.amountHint,
                helper: nil
            ) {
                HStack {
                    TextField(vm.currency.scale == 0 ? "0" : "0.00", text: $vm.amountText)
                        .keyboardType(vm.currency.scale == 0 ? .numberPad : .decimalPad)
                        .font(.title3.monospacedDigit())
                        .focused($focus, equals: .amount)
                        .accessibilityIdentifier("paymentAmountField")
                    Text(vm.currency.code)
                        .font(.callout.weight(.semibold))
                        .foregroundColor(.ecTextSecondary)
                }
                .ecInputField(hasError: vm.errors[.amount] != nil || vm.amountHint != nil)
            }
            if let maximum = vm.maximum {
                LabeledValueRow(
                    label: "Maximum for This Payment",
                    value: MoneyFormatter.string(maximum, vm.currency),
                    spokenValue: MoneyFormatter.spoken(maximum, vm.currency)
                )
                .accessibilityIdentifier("paymentMaximum")
            }

            FormField(label: "Date", required: true, error: vm.errors[.date], helper: "When the transfer happened. It can't be in the future.") {
                DatePicker("Date", selection: $vm.date, in: ...vm.today, displayedComponents: .date)
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .ecInputField(hasError: vm.errors[.date] != nil)
            }

            FormField(label: "Note", error: vm.errors[.note]) {
                NoteEditor(text: $vm.note, maxLength: DomainLimits.paymentNoteMaxLength, hasError: vm.errors[.note] != nil)
                    .focused($focus, equals: .note)
            }

            VStack(alignment: .leading, spacing: 4) {
                Toggle(isOn: $vm.confirmed) {
                    Text("I have already made this payment outside Even Circle.")
                        .font(.body)
                }
                .toggleStyle(CheckboxToggleStyle())
                .accessibilityIdentifier("paymentConfirmCheckbox")
                if let error = vm.errors[.confirmation] {
                    Text(error).ecCaptionFont().foregroundColor(.ecCoral)
                }
            }
        }
    }
}
