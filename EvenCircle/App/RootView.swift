import SwiftUI

struct RootView: View {
    @ObservedObject var root: AppRootViewModel

    var body: some View {
        ZStack {
            Color.ecBackground.ignoresSafeArea()
            switch root.phase {
            case .loading:
                ProgressView("Opening your events…")
                    .foregroundColor(.ecTextSecondary)
                    .tint(.ecTextSecondary)
            case .failed(let message):
                StoreErrorView(root: root, message: message)
            case .ready:
                if root.onboardingCompleted {
                    MainTabView(deps: root.dependencies, onResetAllData: root.didResetAllData)
                } else {
                    OnboardingView(mode: .firstRun) {
                        root.completeOnboarding()
                    }
                }
            }
        }
        .task { await root.start() }
    }
}

struct MainTabView: View {
    let deps: AppDependencies
    let onResetAllData: () -> Void
    @State private var tab = Tab.events

    enum Tab: Hashable {
        case events, settings
    }

    var body: some View {
        TabView(selection: $tab) {
            EventsListScreen(deps: deps)
                .tabItem { Label("Events", systemImage: "circle.grid.2x2.fill") }
                .tag(Tab.events)
            SettingsScreen(deps: deps, onResetAllData: onResetAllData)
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(Tab.settings)
        }
    }
}

/// Shown when the local database can't be opened: Retry or Import Backup, never auto-delete.
private struct StoreErrorView: View {
    @ObservedObject var root: AppRootViewModel
    let message: String
    @State private var showImporter = false

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.l) {
                ErrorStateView(title: "Couldn't open your data", message: message) {
                    Task { await root.start() }
                }
                Button("Import Backup") { showImporter = true }
                    .buttonStyle(SecondaryButtonStyle())
                if let error = root.recoveryError {
                    InfoNote(text: error, icon: "exclamationmark.circle.fill", color: .ecCoral)
                }
                if let backup = root.pendingRecovery {
                    VStack(alignment: .leading, spacing: Spacing.s) {
                        SectionHeader(title: "Backup ready")
                        Text("\(backup.preview.counts.events.counted("event")), \(backup.preview.counts.expenses.counted("expense")), \(backup.preview.counts.payments.counted("payment")).")
                            .foregroundColor(.ecTextSecondary)
                        InfoNote(text: "The unreadable database will be kept as a separate file on this device. A new database will be created from this backup.")
                        Button(root.isRecovering ? "Importing…" : "Import into a New Database") {
                            Task { await root.importRecovery() }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(root.isRecovering)
                    }
                    .ecCard()
                }
            }
            .padding(Spacing.screen)
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            if case .success(let url) = result {
                Task { await root.validateRecoveryFile(url) }
            }
        }
    }
}
