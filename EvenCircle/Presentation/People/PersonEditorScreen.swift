import SwiftUI

/// Add / Edit Person sheet: a name (1–40) and one of six colours. No email, phone or Contacts access.
struct PersonEditorScreen: View {
    let deps: AppDependencies
    let person: Person?
    let onDelete: (() -> Void)?

    @State private var aggregate: EventAggregate
    @State private var name: String
    @State private var color: AvatarColorKey
    @State private var error: String?
    @State private var isSaving = false
    @State private var alert: AlertMessage?
    @State private var confirmDiscard = false
    @State private var confirmDelete = false
    @FocusState private var nameFocused: Bool
    @Environment(\.dismiss) private var dismiss

    private let initialName: String
    private let initialColor: AvatarColorKey

    init(deps: AppDependencies, aggregate: EventAggregate, person: Person?, onDelete: (() -> Void)?) {
        self.deps = deps
        self.person = person
        self.onDelete = onDelete
        _aggregate = State(initialValue: aggregate)
        let startName = person?.name ?? ""
        let startColor = person?.avatarColor ?? AvatarColorKey.suggested(forIndex: aggregate.people.count)
        _name = State(initialValue: startName)
        _color = State(initialValue: startColor)
        initialName = startName
        initialColor = startColor
    }

    private var hasChanges: Bool { name != initialName || color != initialColor }
    private var isLinked: Bool { person.map { aggregate.isPersonLinked($0.id) } ?? false }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    HStack {
                        Spacer()
                        AvatarView(name: name.isEmpty ? "?" : name, color: color, size: 72)
                        Spacer()
                    }
                    .accessibilityHidden(true)

                    FormField(label: "Name", required: true, error: error, helper: "1–40 characters. Must be unique in this event.") {
                        TextField("e.g. Alex", text: $name)
                            .focused($nameFocused)
                            .textContentType(.none)
                            .disableAutocorrection(true)
                            .submitLabel(.done)
                            .onSubmit { Task { await save() } }
                            .ecInputField(hasError: error != nil)
                            .accessibilityIdentifier("personNameField")
                            .onChange(of: name) { _ in if error != nil { error = nil } }
                    }

                    FormField(label: "Color", required: true, helper: "Colour is decoration only; the name identifies the person.") {
                        HStack(spacing: Spacing.s) {
                            ForEach(AvatarColorKey.allCases, id: \.self) { key in
                                Button { color = key } label: {
                                    Circle()
                                        .fill(key.fill)
                                        .frame(width: 36, height: 36)
                                        .overlay(
                                            Image(systemName: "checkmark")
                                                .font(.footnote.weight(.bold))
                                                .foregroundColor(key.initialsColor)
                                                .opacity(color == key ? 1 : 0)
                                        )
                                        .overlay(Circle().stroke(Color.ecTextPrimary, lineWidth: color == key ? 2 : 0).padding(-4))
                                        .frame(width: Metrics.minTapTarget, height: Metrics.minTapTarget)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(key.displayName)
                                .accessibilityAddTraits(color == key ? [.isButton, .isSelected] : .isButton)
                            }
                        }
                    }

                    if person != nil {
                        InfoNote(text: "Renaming updates this person everywhere in the event. Balances stay attached to the same person.")
                        if onDelete != nil {
                            Button(role: .destructive) {
                                confirmDelete = true
                            } label: {
                                Label("Delete Person", systemImage: "trash")
                            }
                            .buttonStyle(SecondaryButtonStyle(tint: .ecCoral))
                            if isLinked {
                                InfoNote(text: "This person is linked to saved records.", icon: "link", color: .ecCoral)
                            }
                        }
                    }
                }
                .padding(Spacing.screen)
            }
            .ecScreenBackground()
            .navigationTitle(person == nil ? "Add Person" : "Edit Person")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { if hasChanges { confirmDiscard = true } else { dismiss() } }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") { Task { await save() } }
                        .disabled(isSaving)
                        .accessibilityIdentifier("savePersonButton")
                }
            }
            .confirmationDialog("Discard changes?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Discard Changes", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) {}
            }
            .alert("Delete \(person?.name ?? "person")?", isPresented: $confirmDelete) {
                if isLinked {
                    Button("OK", role: .cancel) {}
                } else {
                    Button("Delete Person", role: .destructive) {
                        dismiss()
                        onDelete?()
                    }
                    Button("Cancel", role: .cancel) {}
                }
            } message: {
                Text(isLinked ? "This person is linked to saved records." : "This person isn't used in any saved record.")
            }
            .messageAlert($alert)
            .onAppear { if person == nil { nameFocused = true } }
        }
        .navigationViewStyle(.stack)
        .interactiveDismissDisabled(hasChanges || isSaving)
    }

    private func save() async {
        guard !isSaving else { return }
        if let validation = PersonRules.validateName(name, eventPeople: aggregate.people, editingID: person?.id) {
            error = validation.message
            nameFocused = true
            return
        }
        isSaving = true
        defer { isSaving = false }
        do {
            if let person {
                try await deps.people.updatePerson(person, name: name, color: color, in: aggregate)
            } else {
                try await deps.people.addPerson(name: name, color: color, to: aggregate)
            }
            deps.haptics.success()
            dismiss()
        } catch RepositoryError.revisionConflict {
            if let fresh = try? await deps.events.loadAggregate(id: aggregate.event.id) {
                aggregate = fresh
                if let validation = PersonRules.validateName(name, eventPeople: fresh.people, editingID: person?.id) {
                    error = validation.message
                }
            }
            alert = AlertMessage(title: "Event changed", message: "The event was updated. Check the name and save again.")
        } catch RepositoryError.duplicatePersonName {
            error = RepositoryError.duplicatePersonName.message
            nameFocused = true
        } catch {
            alert = .error(error, title: "Couldn't save")
        }
    }
}
