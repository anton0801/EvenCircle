import SwiftUI

/// Screen 06: people of this event. Names are local labels, not accounts or contacts.
struct PeopleTabView: View {
    let snapshot: EventSnapshot
    @Binding var notice: String?
    let onAdd: () -> Void
    let onEdit: (Person) -> Void
    let onDelete: (Person) -> Void
    let onContinue: () -> Void

    @State private var deleteCandidate: Person?
    @State private var linkedPerson: Person?

    private var people: [Person] { snapshot.people }
    private var atLimit: Bool { people.count >= DomainLimits.maxPeoplePerEvent }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.m) {
                if let notice {
                    HStack(alignment: .top) {
                        InfoNote(text: notice, icon: "person.2.fill", color: .ecLilac)
                        Button { self.notice = nil } label: { Image(systemName: "xmark") }
                            .frame(width: Metrics.minTapTarget, height: Metrics.minTapTarget)
                            .foregroundColor(.ecTextSecondary)
                            .accessibilityLabel("Dismiss")
                    }
                    .ecCard(padding: Spacing.s)
                }

                if people.isEmpty {
                    EmptyStateView(
                        illustration: .peopleGroup,
                        title: "Who is sharing?",
                        message: snapshot.isArchived
                            ? "This archived event has no people."
                            : "Add everyone who pays or shares costs. Only names are stored – no contacts, phone numbers or accounts.",
                        actionTitle: snapshot.isArchived ? nil : "Add Person",
                        action: snapshot.isArchived ? nil : onAdd
                    )
                } else {
                    SectionHeader(
                        title: people.count.counted("person", "people"),
                        subtitle: people.count < 2 ? "Add at least two people to start adding expenses." : nil
                    )
                    LazyVStack(spacing: Spacing.xs) {
                        ForEach(people) { person in
                            row(person)
                        }
                    }
                    if atLimit {
                        InfoNote(text: "An event can have up to \(DomainLimits.maxPeoplePerEvent) people.")
                    }
                }
            }
            .padding(Spacing.screen)
        }
        .safeAreaInset(edge: .bottom) {
            if !snapshot.isArchived && !people.isEmpty {
                VStack(spacing: Spacing.xs) {
                    if people.count >= 2 {
                        Button("Continue to Expenses", action: onContinue)
                            .buttonStyle(PrimaryButtonStyle())
                            .accessibilityIdentifier("continueToExpensesButton")
                    }
                    Button(action: onAdd) { Label("Add Person", systemImage: "person.badge.plus") }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(atLimit)
                        .accessibilityIdentifier("addPersonButton")
                }
                .ecBottomBar()
            }
        }
        .alert(
            deleteCandidate.map { "Delete \($0.name)?" } ?? "",
            isPresented: Binding(get: { deleteCandidate != nil }, set: { if !$0 { deleteCandidate = nil } }),
            presenting: deleteCandidate
        ) { person in
            Button("Delete Person", role: .destructive) { onDelete(person) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text(people.count <= 2 ? "With fewer than two people, new expenses can't be added until you add someone again." : "This person isn't used in any saved record.")
        }
        .alert(
            linkedPerson.map { "Can't delete \($0.name)" } ?? "",
            isPresented: Binding(get: { linkedPerson != nil }, set: { if !$0 { linkedPerson = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This person is linked to saved records.")
        }
    }

    private func row(_ person: Person) -> some View {
        HStack(spacing: Spacing.s) {
            Button {
                if !snapshot.isArchived { onEdit(person) }
            } label: {
                HStack(spacing: Spacing.s) {
                    AvatarView(person: person, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(person.name)
                            .font(.body.weight(.semibold))
                            .foregroundColor(.ecTextPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        if snapshot.aggregate.isPersonLinked(person.id) {
                            Text("In saved records")
                                .ecCaptionFont()
                                .foregroundColor(.ecTextSecondary)
                        }
                    }
                    Spacer(minLength: 0)
                    if !snapshot.isArchived {
                        Image(systemName: "pencil")
                            .foregroundColor(.ecTextSecondary)
                            .accessibilityHidden(true)
                    }
                }
                .frame(minHeight: Metrics.minTapTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(snapshot.isArchived)
            .accessibilityLabel(person.name + (snapshot.aggregate.isPersonLinked(person.id) ? ", in saved records" : ""))
            .accessibilityHint(snapshot.isArchived ? "" : "Edit person")

            if !snapshot.isArchived {
                Menu {
                    Button { onEdit(person) } label: { Label("Edit Person", systemImage: "pencil") }
                    Button(role: .destructive) {
                        if snapshot.aggregate.isPersonLinked(person.id) {
                            linkedPerson = person
                        } else {
                            deleteCandidate = person
                        }
                    } label: { Label("Delete Person", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundColor(.ecTextSecondary)
                        .frame(width: Metrics.minTapTarget, height: Metrics.minTapTarget)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Actions for \(person.name)")
            }
        }
        .ecCard(padding: Spacing.s)
    }
}
