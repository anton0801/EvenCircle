import SwiftUI

/// Before / After net balances for a pending change. Nothing is written until Confirm;
/// Cancel leaves expenses, payments and balances exactly as they were.
struct ReviewBalanceChangesView: View {
    let title: String
    let preview: BalanceChangePreview
    let explanation: String
    let confirmTitle: String
    let destructive: Bool
    let isWorking: Bool
    let notice: String?
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.m) {
                    if let notice {
                        InfoNote(text: notice, icon: "arrow.triangle.2.circlepath", color: .ecLilac)
                            .ecCard(padding: Spacing.s)
                    }
                    InfoNote(text: explanation, icon: "info.circle.fill", color: .ecLilac)

                    if !preview.hasChanges {
                        Text("No net balance changes for anyone.")
                            .foregroundColor(.ecTextSecondary)
                    }

                    if !dynamicTypeSize.isAccessibilitySize {
                        HStack {
                            Text("Person").frame(maxWidth: .infinity, alignment: .leading)
                            Text("Before").frame(maxWidth: .infinity, alignment: .trailing)
                            Text("After").frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(.ecTextSecondary)
                        .accessibilityHidden(true)
                    }

                    VStack(spacing: Spacing.xs) {
                        ForEach(preview.rows) { row in
                            rowView(row)
                        }
                    }
                }
                .padding(Spacing.screen)
            }
            .ecScreenBackground()
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: Spacing.xs) {
                    Group {
                        if destructive {
                            Button(isWorking ? "Deleting…" : confirmTitle, role: .destructive, action: onConfirm)
                                .buttonStyle(DestructiveButtonStyle())
                        } else {
                            Button(isWorking ? "Saving…" : confirmTitle, action: onConfirm)
                                .buttonStyle(PrimaryButtonStyle())
                        }
                    }
                    .disabled(isWorking)
                    .accessibilityIdentifier("confirmReviewButton")
                    Button("Cancel", action: onCancel)
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(isWorking)
                }
                .ecBottomBar()
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
        }
        .navigationViewStyle(.stack)
        .interactiveDismissDisabled(isWorking)
    }

    @ViewBuilder
    private func rowView(_ row: BalanceChangePreview.Row) -> some View {
        let before = BalanceDirection(net: row.beforeMinor)
        let after = BalanceDirection(net: row.afterMinor)
        let content = Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    Text(row.name).font(.body.weight(.semibold)).foregroundColor(.ecTextPrimary)
                    Text("Before: \(before.text(preview.currency))").foregroundColor(.ecTextSecondary)
                    Text("After: \(after.text(preview.currency))").foregroundColor(row.changed ? .ecTextPrimary : .ecTextSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .firstTextBaseline) {
                    Text(row.name)
                        .font(.callout.weight(.semibold))
                        .foregroundColor(.ecTextPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    cell(before)
                    cell(after).opacity(row.changed ? 1 : 0.7)
                }
            }
        }
        content
            .padding(12)
            .background(RoundedRectangle(cornerRadius: Radius.field).fill(row.changed ? Color.ecInput : Color.ecSurface))
            .overlay(alignment: .topTrailing) {
                if row.directionChanged {
                    StatusChip(text: "Direction changes", color: .ecLilac)
                        .offset(y: -10)
                        .padding(.trailing, 8)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(row.name). Before: \(before.spoken(preview.currency)). After: \(after.spoken(preview.currency))\(row.changed ? "" : ". No change")")
    }

    private func cell(_ direction: BalanceDirection) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(direction.shortText)
                .font(.caption.weight(.semibold))
                .foregroundColor(color(direction))
            if case .settled = direction {
                EmptyView()
            } else {
                Text(MoneyFormatter.string(amount(direction), preview.currency))
                    .font(.footnote.monospacedDigit())
                    .foregroundColor(.ecTextPrimary)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func amount(_ direction: BalanceDirection) -> Int64 {
        switch direction {
        case .toReceive(let value), .toPay(let value): return value
        case .settled: return 0
        }
    }

    private func color(_ direction: BalanceDirection) -> Color {
        switch direction {
        case .toReceive: return .ecMint
        case .toPay: return .ecCoral
        case .settled: return .ecTextSecondary
        }
    }
}
