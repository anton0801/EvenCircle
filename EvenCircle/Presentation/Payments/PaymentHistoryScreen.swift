import SwiftUI

/// Screen 14: recorded settlements, kept apart from purchases. Old records stay valid facts even
/// if later expense corrections changed who owes whom.
struct PaymentHistoryScreen: View {
    @ObservedObject var vm: EventDetailViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var expanded: Set<UUID> = []
    @State private var review: ReviewRequest?
    @State private var pendingPaymentID: UUID?
    @State private var isDeleting = false
    @State private var alert: AlertMessage?

    var body: some View {
        Group {
            if let snapshot = vm.snapshot {
                content(snapshot)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ecScreenBackground()
        .navigationTitle("Payment History")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $review) { request in
            ReviewBalanceChangesView(
                title: "Delete Record",
                preview: request.preview,
                explanation: "This removes a record only. It does not reverse a real payment.",
                confirmTitle: "Confirm Delete",
                destructive: true,
                isWorking: isDeleting,
                notice: request.notice,
                onConfirm: { Task { await confirmDelete(basedOn: request.preview.basedOnRevision) } },
                onCancel: { review = nil; pendingPaymentID = nil }
            )
        }
        .messageAlert($alert)
    }

    private func content(_ snapshot: EventSnapshot) -> some View {
        let payments = snapshot.aggregate.orderedPayments
        return ScrollView {
            VStack(alignment: .leading, spacing: Spacing.m) {
                if snapshot.isArchived { ArchivedBanner() }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Recorded Payments")
                        .font(.callout.weight(.semibold))
                        .foregroundColor(.ecTextSecondary)
                    MoneyText(minor: snapshot.balances.recordedPaymentsMinor, currency: snapshot.currency, hero: true)
                    Text("\(payments.count.counted("record")) · not part of Total Expenses")
                        .ecCaptionFont()
                        .foregroundColor(.ecTextSecondary)
                }
                .ecCard()
                .accessibilityElement(children: .combine)

                if payments.isEmpty {
                    EmptyStateView(
                        illustration: .paymentNote,
                        illustrationSize: CGSize(width: 112, height: 112),
                        title: "No payments recorded",
                        message: "When someone settles up outside the app, record it from Balances."
                    )
                } else {
                    VStack(spacing: Spacing.xs) {
                        ForEach(payments) { payment in
                            row(payment, snapshot: snapshot)
                        }
                    }
                }

                Button("Back to Balances") { dismiss() }
                    .buttonStyle(SecondaryButtonStyle())
            }
            .padding(Spacing.screen)
        }
    }

    private func row(_ payment: Payment, snapshot: EventSnapshot) -> some View {
        let isExpanded = expanded.contains(payment.id)
        let aggregate = snapshot.aggregate
        let from = aggregate.personName(payment.fromID)
        let to = aggregate.personName(payment.toID)
        return VStack(alignment: .leading, spacing: Spacing.xs) {
            Button {
                if isExpanded { expanded.remove(payment.id) } else { expanded.insert(payment.id) }
            } label: {
                AdaptiveRow {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(from) → \(to)")
                            .font(.body.weight(.semibold))
                            .foregroundColor(.ecTextPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(DateText.medium(payment.paymentDate))
                            .ecCaptionFont()
                            .foregroundColor(.ecTextSecondary)
                        if let note = payment.note {
                            Text(note)
                                .ecCaptionFont()
                                .foregroundColor(.ecTextSecondary)
                                .lineLimit(isExpanded ? nil : 2)
                        }
                    }
                } trailing: {
                    MoneyText(minor: payment.amountMinor, currency: snapshot.currency)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(from) paid \(to) \(MoneyFormatter.spoken(payment.amountMinor, snapshot.currency)) on \(DateText.medium(payment.paymentDate))")
            .accessibilityHint(isExpanded ? "Hide details" : "Show details")
            .accessibilityIdentifier("paymentRow_\(from)_\(to)")

            if isExpanded {
                Divider().background(Color.ecDivider)
                LabeledValueRow(label: "Record created", value: DateText.timestamp(payment.createdAt))
                Text("Recorded by you")
                    .ecCaptionFont()
                    .foregroundColor(.ecTextSecondary)
                if !snapshot.isArchived {
                    Button(role: .destructive) {
                        startDelete(payment.id, snapshot: snapshot)
                    } label: {
                        Label("Delete Record", systemImage: "trash")
                    }
                    .buttonStyle(SecondaryButtonStyle(tint: .ecCoral))
                    .accessibilityIdentifier("deletePaymentRecordButton")
                }
            }
        }
        .ecCard(padding: 14)
    }

    private func startDelete(_ paymentID: UUID, snapshot: EventSnapshot) {
        do {
            pendingPaymentID = paymentID
            review = ReviewRequest(preview: try vm.deps.payments.previewDelete(paymentID, in: snapshot.aggregate), notice: nil)
        } catch {
            alert = .error(error)
        }
    }

    private func confirmDelete(basedOn revision: Int64) async {
        guard let paymentID = pendingPaymentID, !isDeleting else { return }
        isDeleting = true
        defer { isDeleting = false }
        do {
            guard let fresh = try await vm.freshSnapshot(), fresh.aggregate.payment(paymentID) != nil else {
                review = nil
                return
            }
            guard fresh.aggregate.event.revision == revision else {
                review = ReviewRequest(
                    preview: try vm.deps.payments.previewDelete(paymentID, in: fresh.aggregate),
                    notice: "The event changed. Review the updated balances before deleting."
                )
                return
            }
            try await vm.deps.payments.delete(paymentID, in: fresh.aggregate)
            vm.deps.haptics.success()
            review = nil
            pendingPaymentID = nil
        } catch {
            review = nil
            alert = .error(error, title: "Couldn't delete the record")
        }
    }
}
