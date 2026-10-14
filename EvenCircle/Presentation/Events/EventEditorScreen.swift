import SwiftUI

/// Screen 05: New / Edit / Duplicate Event.
struct EventEditorScreen: View {
    enum Mode: Identifiable {
        case create
        case edit(EventAggregate)
        case duplicate(EventAggregate)

        var id: String {
            switch self {
            case .create: return "create"
            case .edit(let aggregate): return "edit-\(aggregate.id)"
            case .duplicate(let aggregate): return "duplicate-\(aggregate.id)"
            }
        }
    }

    @StateObject private var vm: EventEditorViewModel
    private let onFinished: (UUID?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDiscard = false
    @FocusState private var focus: EventFormField?

    init(deps: AppDependencies, mode: Mode, onFinished: @escaping (UUID?) -> Void) {
        _vm = StateObject(wrappedValue: EventEditorViewModel(deps: deps, mode: mode))
        self.onFinished = onFinished
    }

    var body: some View {
        NavigationView {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.l) {
                        FormField(label: "Event Name", required: true, error: vm.errors[.name], helper: "Up to 80 characters.") {
                            TextField("e.g. Lisbon Weekend", text: $vm.form.name)
                                .focused($focus, equals: .name)
                                .submitLabel(.done)
                                .ecInputField(hasError: vm.errors[.name] != nil)
                                .accessibilityIdentifier("eventNameField")
                                .onChange(of: vm.form.name) { _ in
                                    if vm.errors[.name] != nil { vm.validateField(.name) }
                                }
                        }
                        .id(EventFormField.name)

                        FormField(label: "Event Date", required: true, helper: "Can be in the future.") {
                            DatePicker("Event Date", selection: $vm.form.date, displayedComponents: .date)
                                .labelsHidden()
                                .datePickerStyle(.compact)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .ecInputField()
                        }

                        FormField(
                            label: "Currency",
                            required: true,
                            helper: vm.currencyLocked
                                ? "Currency is locked after the first expense."
                                : "Amounts are never converted. Choose the currency everyone paid in."
                        ) {
                            Picker("Currency", selection: $vm.form.currency) {
                                ForEach(CurrencyCode.allCases) { currency in
                                    Text(currency.code).tag(currency)
                                }
                            }
                            .pickerStyle(.segmented)
                            .disabled(vm.currencyLocked)
                            .accessibilityValue(vm.form.currency.displayName)
                        }

                        FormField(label: "Note", error: vm.errors[.note]) {
                            NoteEditor(text: $vm.form.note, maxLength: DomainLimits.eventNoteMaxLength, hasError: vm.errors[.note] != nil)
                                .focused($focus, equals: .note)
                        }
                        .id(EventFormField.note)

                        if !vm.peopleToCopy.isEmpty {
                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                SectionHeader(title: "People to copy", subtitle: "Names only. Expenses, payments and the note are not copied.")
                                ForEach(Array(vm.peopleToCopy.enumerated()), id: \.offset) { _, person in
                                    HStack(spacing: Spacing.s) {
                                        AvatarView(name: person.name, color: person.avatarColor, size: 32)
                                        Text(person.name)
                                            .foregroundColor(.ecTextPrimary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                            .ecCard()
                        }
                    }
                    .padding(Spacing.screen)
                }
                .onChange(of: vm.errors) { errors in
                    if let first = [EventFormField.name, .note].first(where: { errors[$0] != nil }) {
                        focus = first
                        withAnimation { proxy.scrollTo(first, anchor: .top) }
                    }
                }
            }
            .ecScreenBackground()
            .safeAreaInset(edge: .bottom) {
                Button(vm.isSaving ? "Saving…" : vm.primaryTitle) {
                    Task {
                        let result = await vm.submit()
                        if result.success {
                            dismiss()
                            onFinished(result.createdID)
                        }
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(vm.isSaving)
                .accessibilityIdentifier("saveEventButton")
                .ecBottomBar()
            }
            .navigationTitle(vm.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if vm.hasChanges { confirmDiscard = true } else { dismiss() }
                    }
                }
            }
            .confirmationDialog("Discard changes?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Discard Changes", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) {}
            }
            .messageAlert($vm.alert)
        }
        .navigationViewStyle(.stack)
        .interactiveDismissDisabled(vm.hasChanges || vm.isSaving)
    }
}
