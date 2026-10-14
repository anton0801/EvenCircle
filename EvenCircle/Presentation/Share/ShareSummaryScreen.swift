import Combine
import SwiftUI
import UIKit

@MainActor
final class ShareSummaryViewModel: ObservableObject {
    @Published var options = ShareSummaryBuilder.Options()
    @Published private(set) var snapshot: EventSnapshot?
    @Published private(set) var generatedAt = Date()
    @Published private(set) var isOutOfDate = false
    @Published private(set) var loadError: String?
    @Published var toast: String?

    private let deps: AppDependencies
    private let eventID: UUID
    private var cancellables: Set<AnyCancellable> = []

    init(deps: AppDependencies, eventID: UUID) {
        self.deps = deps
        self.eventID = eventID
        deps.repository.changes
            .filter { change in
                if case .event(let id) = change { return id == eventID }
                return true
            }
            .sink { [weak self] _ in
                // Any committed change bumps the revision, so the preview no longer matches the data.
                guard let self, self.snapshot != nil else { return }
                self.isOutOfDate = true
            }
            .store(in: &cancellables)
    }

    var text: String {
        guard let snapshot else { return "" }
        return ShareSummaryBuilder.text(for: snapshot, options: options, generatedAt: generatedAt)
    }

    func refresh() async {
        do {
            guard let aggregate = try await deps.events.loadAggregate(id: eventID) else {
                loadError = "This event is no longer available."
                return
            }
            snapshot = try EventSnapshot.make(aggregate)
            generatedAt = deps.clock.now()
            isOutOfDate = false
            loadError = nil
        } catch {
            loadError = UserMessage.text(for: error)
        }
    }

    func share() {
        guard !isOutOfDate, snapshot != nil else { return }
        SystemShare.present(items: [text])
    }

    func copy() {
        guard !isOutOfDate, snapshot != nil else { return }
        UIPasteboard.general.string = text
        toast = "Summary copied"
    }
}

/// Screen 15: a readable report for manual sharing. Nothing is sent unless the user picks
/// a destination in the system share sheet; the app never confirms delivery.
struct ShareSummaryScreen: View {
    @StateObject private var vm: ShareSummaryViewModel
    @Environment(\.dismiss) private var dismiss

    init(deps: AppDependencies, eventID: UUID) {
        _vm = StateObject(wrappedValue: ShareSummaryViewModel(deps: deps, eventID: eventID))
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.m) {
                    HStack(spacing: Spacing.s) {
                        IllustrationView(.summaryFolder)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Event report")
                                .ecSectionFont()
                                .foregroundColor(.ecTextPrimary)
                            Text("Names and amounts will be included.")
                                .ecCaptionFont()
                                .foregroundColor(.ecTextSecondary)
                        }
                    }

                    VStack(spacing: 0) {
                        toggle("Include Expense List", $vm.options.includeExpenses)
                        Divider().background(Color.ecDivider)
                        toggle("Include Recorded Payments", $vm.options.includePayments)
                        Divider().background(Color.ecDivider)
                        toggle("Include Notes", $vm.options.includeNotes)
                    }
                    .ecCard(padding: Spacing.s)

                    if let error = vm.loadError {
                        InfoNote(text: error, icon: "exclamationmark.circle.fill", color: .ecCoral)
                    }

                    if vm.snapshot != nil {
                        HStack {
                            Text("Generated \(DateText.timestamp(vm.generatedAt))")
                                .ecCaptionFont()
                                .foregroundColor(.ecTextSecondary)
                            Spacer()
                            if vm.isOutOfDate {
                                StatusChip(text: "Out of date", color: .ecCoral, icon: "exclamationmark.triangle.fill")
                                    .accessibilityIdentifier("summaryOutOfDate")
                            }
                        }
                        if vm.isOutOfDate {
                            InfoNote(text: "The event changed after this preview. Refresh before sharing or copying.", icon: "arrow.clockwise", color: .ecCoral)
                        }
                        Text(vm.text)
                            .font(.callout)
                            .foregroundColor(vm.isOutOfDate ? .ecTextSecondary : .ecTextPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                            .ecCard()
                            .accessibilityIdentifier("summaryPreviewText")
                    } else if vm.loadError == nil {
                        ProgressView().frame(maxWidth: .infinity)
                    }
                }
                .padding(Spacing.screen)
            }
            .ecScreenBackground()
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: Spacing.xs) {
                    Button { vm.share() } label: { Label("Share Text", systemImage: "square.and.arrow.up") }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(vm.isOutOfDate || vm.snapshot == nil)
                        .accessibilityIdentifier("shareTextButton")
                    HStack(spacing: Spacing.xs) {
                        Button { vm.copy() } label: { Label("Copy Summary", systemImage: "doc.on.doc") }
                            .buttonStyle(SecondaryButtonStyle())
                            .disabled(vm.isOutOfDate || vm.snapshot == nil)
                            .accessibilityIdentifier("copySummaryButton")
                        Button { Task { await vm.refresh() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                            .buttonStyle(SecondaryButtonStyle())
                            .accessibilityIdentifier("refreshSummaryButton")
                    }
                }
                .ecBottomBar()
            }
            .navigationTitle("Share Summary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .accessibilityIdentifier("closeSummaryButton")
                }
            }
            .toast($vm.toast)
            .task { await vm.refresh() }
        }
        .navigationViewStyle(.stack)
    }

    private func toggle(_ title: String, _ binding: Binding<Bool>) -> some View {
        Toggle(title, isOn: binding)
            .toggleStyle(SwitchToggleStyle(tint: .ecBlue))
            .foregroundColor(.ecTextPrimary)
            .frame(minHeight: Metrics.minTapTarget)
    }
}
