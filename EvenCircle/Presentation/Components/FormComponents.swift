import SwiftUI

/// Label + control + error/helper text. Required fields carry a visible "*" and a VoiceOver hint.
struct FormField<Content: View>: View {
    let label: String
    var required = false
    var error: String?
    var helper: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 2) {
                Text(label)
                    .font(.callout.weight(.semibold))
                    .foregroundColor(.ecTextPrimary)
                if required {
                    Text("*")
                        .font(.callout.weight(.semibold))
                        .foregroundColor(.ecCoral)
                        .accessibilityLabel("required")
                }
            }
            .accessibilityElement(children: .combine)
            content()
            if let error {
                HStack(alignment: .top, spacing: 4) {
                    Image(systemName: "exclamationmark.circle.fill").accessibilityHidden(true)
                    Text(error).fixedSize(horizontal: false, vertical: true)
                }
                .ecCaptionFont()
                .foregroundColor(.ecCoral)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Error: \(error)")
            } else if let helper {
                Text(helper)
                    .ecCaptionFont()
                    .foregroundColor(.ecTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Multi-line note with a character counter (TextEditor works on iOS 15).
struct NoteEditor: View {
    @Binding var text: String
    let maxLength: Int
    var placeholder = "Optional"
    var hasError = false

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder)
                        .foregroundColor(.ecTextSecondary.opacity(0.7))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 8)
                        .accessibilityHidden(true)
                }
                TextEditor(text: $text)
                    .hiddenScrollBackground()
                    .foregroundColor(.ecTextPrimary)
                    .frame(minHeight: 88)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: Radius.field, style: .continuous).fill(Color.ecInput))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.field, style: .continuous)
                    .stroke(hasError ? Color.ecCoral : Color.ecDivider, lineWidth: hasError ? 1.5 : 1)
            )
            Text("\(text.trimmingCharacters(in: .whitespacesAndNewlines).count)/\(maxLength)")
                .ecCaptionFont()
                .foregroundColor(text.trimmingCharacters(in: .whitespacesAndNewlines).count > maxLength ? .ecCoral : .ecTextSecondary)
                .accessibilityLabel("\(text.count) of \(maxLength) characters")
        }
    }
}

/// Initials in a coloured circle. The colour is decoration; the name is what VoiceOver reads.
struct AvatarView: View {
    let name: String
    let color: AvatarColorKey
    var size: CGFloat = 40

    var body: some View {
        Text(TextRules.initials(name))
            .font(.system(size: size * 0.38, weight: .bold, design: .rounded))
            .foregroundColor(color.initialsColor)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(width: size, height: size)
            .background(Circle().fill(color.fill))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(name)
    }
}

extension AvatarView {
    init(person: Person, size: CGFloat = 40) {
        self.init(name: person.name, color: person.avatarColor, size: size)
    }
}

/// A menu-backed picker for people with a 48 pt field look.
struct PersonPickerField: View {
    let title: String
    let people: [Person]
    @Binding var selection: UUID?
    var detail: (Person) -> String? = { _ in nil }
    var hasError = false
    var placeholder = "Select a person"

    var body: some View {
        Menu {
            ForEach(people) { person in
                Button {
                    selection = person.id
                } label: {
                    if let detail = detail(person) {
                        Text("\(person.name) — \(detail)")
                    } else {
                        Text(person.name)
                    }
                }
            }
        } label: {
            HStack(spacing: Spacing.s) {
                if let person = people.first(where: { $0.id == selection }) {
                    AvatarView(person: person, size: 28)
                    Text(person.name)
                        .foregroundColor(.ecTextPrimary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(placeholder)
                        .foregroundColor(.ecTextSecondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(.ecTextSecondary)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 8)
            .ecInputField(hasError: hasError)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(title)
        .accessibilityValue(people.first(where: { $0.id == selection })?.name ?? "Not selected")
    }
}

/// Toolbar "Done" for number pads, which have no return key.
struct KeyboardDoneToolbar: ViewModifier {
    let onDone: () -> Void

    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done", action: onDone)
            }
        }
    }
}

extension View {
    func keyboardDoneButton(_ onDone: @escaping () -> Void) -> some View {
        modifier(KeyboardDoneToolbar(onDone: onDone))
    }
}
