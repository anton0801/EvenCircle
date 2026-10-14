import SwiftUI

enum LoadState<Value> {
    case loading
    case loaded(Value)
    case failed(String)

    var value: Value? {
        if case .loaded(let value) = self { return value }
        return nil
    }
}

struct AlertMessage: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String

    static func error(_ error: Error, title: String = "Something went wrong") -> AlertMessage {
        AlertMessage(title: title, message: UserMessage.text(for: error))
    }
}

enum UserMessage {
    /// Plain-language message for any error; technical details stay in debug logs.
    static func text(for error: Error) -> String {
        switch error {
        case let error as RepositoryError: return error.message
        case let error as FieldError: return error.message
        case let error as BackupValidationError: return error.message
        case let error as ExpenseDraftIssues: return error.first?.message ?? "Check the expense details."
        case is BalanceCalculationError: return "Balances for this event couldn't be calculated."
        default:
            #if DEBUG
            print("Even Circle unexpected error: \(error)")
            #endif
            return "Something went wrong. Try again."
        }
    }
}

extension View {
    func messageAlert(_ message: Binding<AlertMessage?>) -> some View {
        alert(
            message.wrappedValue?.title ?? "",
            isPresented: Binding(get: { message.wrappedValue != nil }, set: { if !$0 { message.wrappedValue = nil } }),
            actions: { Button("OK", role: .cancel) {} },
            message: { Text(message.wrappedValue?.message ?? "") }
        )
    }

    func ecCard(padding: CGFloat = Spacing.m) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Color.ecSurface))
    }

    func ecInputField(hasError: Bool = false) -> some View {
        self
            .foregroundColor(.ecTextPrimary)
            .padding(.horizontal, 14)
            .frame(minHeight: 48)
            .background(RoundedRectangle(cornerRadius: Radius.field, style: .continuous).fill(Color.ecInput))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.field, style: .continuous)
                    .stroke(hasError ? Color.ecCoral : Color.ecDivider, lineWidth: hasError ? 1.5 : 1)
            )
    }

    /// Bottom action area. The fill extends only behind the home indicator, and the controls
    /// inside keep their own frames, so they stay tappable above the keyboard.
    func ecBottomBar() -> some View {
        VStack(spacing: 0) { self }
            .padding(.horizontal, Spacing.screen)
            .padding(.vertical, Spacing.s)
            .frame(maxWidth: .infinity)
            .background(Color.ecBackground.ignoresSafeArea(.container, edges: .bottom))
    }

    func ecScreenBackground() -> some View {
        background(Color.ecBackground.ignoresSafeArea())
    }

    /// Hides `scrollContentBackground` on iOS 16+ so TextEditor uses our input surface.
    @ViewBuilder
    func hiddenScrollBackground() -> some View {
        if #available(iOS 16.0, *) {
            scrollContentBackground(.hidden)
        } else {
            self
        }
    }
}

/// Delays building a destination until it is actually shown.
struct LazyView<Content: View>: View {
    private let build: () -> Content

    init(_ build: @autoclosure @escaping () -> Content) {
        self.build = build
    }

    var body: Content { build() }
}

struct SectionHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .ecSectionFont()
                .foregroundColor(.ecTextPrimary)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle)
                    .ecCaptionFont()
                    .foregroundColor(.ecTextSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Name and amount side by side; stacked on separate lines at accessibility text sizes.
struct AdaptiveRow<Leading: View, Trailing: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let leading: Leading
    private let trailing: Trailing

    init(@ViewBuilder leading: () -> Leading, @ViewBuilder trailing: () -> Trailing) {
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 6) {
                leading
                trailing
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(alignment: .center, spacing: Spacing.s) {
                leading
                Spacer(minLength: Spacing.xs)
                trailing.layoutPriority(1)
            }
        }
    }
}

struct LabeledValueRow: View {
    let label: String
    let value: String
    var spokenValue: String?
    var emphasized = false
    var valueColor: Color = .ecTextPrimary

    var body: some View {
        AdaptiveRow {
            Text(label)
                .font(emphasized ? .body.weight(.semibold) : .body)
                .foregroundColor(emphasized ? .ecTextPrimary : .ecTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        } trailing: {
            Text(value)
                .ecAmountFont(weight: emphasized ? .bold : .semibold)
                .foregroundColor(valueColor)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(spokenValue ?? value)
    }
}

struct MoneyText: View {
    let minor: Int64
    let currency: CurrencyCode
    var hero = false
    var color: Color = .ecTextPrimary

    var body: some View {
        Group {
            if hero {
                Text(MoneyFormatter.string(minor, currency)).ecHeroAmountFont()
            } else {
                Text(MoneyFormatter.string(minor, currency)).ecAmountFont()
            }
        }
        .foregroundColor(color)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityLabel(MoneyFormatter.spoken(minor, currency))
    }
}

/// "To receive" / "To pay" / "Settled" always as text with a direction icon; colour is only a hint.
struct BalanceBadge: View {
    let direction: BalanceDirection
    let currency: CurrencyCode
    var showAmount = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var color: Color {
        switch direction {
        case .toReceive: return .ecMint
        case .toPay: return .ecCoral
        case .settled: return .ecTextSecondary
        }
    }

    private var icon: String {
        switch direction {
        case .toReceive: return "arrow.down.left.circle.fill"
        case .toPay: return "arrow.up.right.circle.fill"
        case .settled: return "checkmark.circle.fill"
        }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: icon)
                .foregroundColor(color)
                .accessibilityHidden(true)
            Text(showAmount ? direction.text(currency) : direction.shortText)
                .ecAmountFont()
                .foregroundColor(color)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .id(direction)
        .transition(.opacity)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: direction)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(direction.spoken(currency))
    }
}

struct StatusChip: View {
    let text: String
    let color: Color
    var icon: String?

    var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon).font(.caption.weight(.bold)).accessibilityHidden(true)
            }
            Text(text).font(.footnote.weight(.semibold))
        }
        .foregroundColor(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(color.opacity(0.14)))
        .overlay(Capsule().stroke(color.opacity(0.35), lineWidth: 1))
        .fixedSize()
    }
}

extension EventStatus {
    var chip: StatusChip {
        switch self {
        case .noExpenses: return StatusChip(text: title, color: .ecTextSecondary, icon: "circle.dashed")
        case .openBalance: return StatusChip(text: title, color: .ecLilac, icon: "arrow.left.arrow.right")
        case .settled: return StatusChip(text: title, color: .ecMint, icon: "checkmark")
        }
    }
}

struct CurrencyChip: View {
    let currency: CurrencyCode

    var body: some View {
        Text(currency.code)
            .font(.footnote.weight(.bold).monospaced())
            .foregroundColor(.ecOnAccent)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.ecLilac))
            .fixedSize()
            .accessibilityLabel("Currency \(currency.displayName)")
    }
}

struct EmptyStateView: View {
    var illustration: Illustration?
    var illustrationSize: CGSize?
    var systemImage: String?
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: Spacing.m) {
            if let illustration {
                IllustrationView(illustration, size: illustrationSize)
            } else if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 44, weight: .regular))
                    .foregroundColor(.ecLilac)
                    .accessibilityHidden(true)
            }
            Text(title)
                .ecSectionFont()
                .foregroundColor(.ecTextPrimary)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text(message)
                .font(.body)
                .foregroundColor(.ecTextSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.top, Spacing.xs)
            }
        }
        .padding(.vertical, Spacing.l)
        .frame(maxWidth: .infinity)
    }
}

struct ErrorStateView: View {
    let title: String
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: Spacing.m) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundColor(.ecCoral)
                .accessibilityHidden(true)
            Text(title)
                .ecSectionFont()
                .foregroundColor(.ecTextPrimary)
                .multilineTextAlignment(.center)
            Text(message)
                .foregroundColor(.ecTextSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Retry", action: retry)
                .buttonStyle(PrimaryButtonStyle())
        }
        .padding(Spacing.screen)
        .frame(maxWidth: .infinity)
    }
}

struct InfoNote: View {
    let text: String
    var icon = "info.circle"
    var color: Color = .ecTextSecondary

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.xs) {
            Image(systemName: icon)
                .foregroundColor(color)
                .accessibilityHidden(true)
            Text(text)
                .ecCaptionFont()
                .foregroundColor(.ecTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Visible on every archived screen: data is read-only until Restore.
struct ArchivedBanner: View {
    var onRestore: (() -> Void)?

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.s) {
            Image(systemName: "archivebox.fill")
                .foregroundColor(.ecLilac)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Archived · Read only")
                    .font(.callout.weight(.semibold))
                    .foregroundColor(.ecTextPrimary)
                Text("Open balances stay visible. Restore to make changes.")
                    .ecCaptionFont()
                    .foregroundColor(.ecTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if let onRestore {
                Button("Restore", action: onRestore)
                    .buttonStyle(InlineButtonStyle())
                    .accessibilityIdentifier("restoreEventButton")
            }
        }
        .padding(Spacing.s)
        .background(RoundedRectangle(cornerRadius: Radius.field).fill(Color.ecLilac.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: Radius.field).stroke(Color.ecLilac.opacity(0.4), lineWidth: 1))
    }
}

struct ToastModifier: ViewModifier {
    @Binding var message: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let message {
                Text(message)
                    .font(.callout.weight(.semibold))
                    .foregroundColor(.ecOnAccent)
                    .padding(.horizontal, Spacing.m)
                    .padding(.vertical, Spacing.s)
                    .background(Capsule().fill(Color.ecMint))
                    .padding(.bottom, 90)
                    .transition(.opacity)
                    .onAppear {
                        UIAccessibility.post(notification: .announcement, argument: message)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { self.message = nil }
                        }
                    }
            }
        }
    }
}

extension View {
    func toast(_ message: Binding<String?>) -> some View {
        modifier(ToastModifier(message: message))
    }
}
