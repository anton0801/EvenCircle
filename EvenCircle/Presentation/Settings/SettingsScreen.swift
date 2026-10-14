import SwiftUI

/// Screen 16. No hidden server switches or remote configuration exist.
struct SettingsScreen: View {
    let deps: AppDependencies
    let onResetAllData: () -> Void
    @StateObject private var vm: SettingsViewModel

    @State private var showOnboarding = false
    @State private var showPrivacy = false
    @State private var showBackup = false
    @State private var showReset = false
    @State private var confirmRemoveDemo = false

    init(deps: AppDependencies, onResetAllData: @escaping () -> Void) {
        self.deps = deps
        self.onResetAllData = onResetAllData
        _vm = StateObject(wrappedValue: SettingsViewModel(deps: deps))
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    group("Preferences") {
                        HStack {
                            Label("Default Currency", systemImage: "banknote")
                                .foregroundColor(.ecTextPrimary)
                            Spacer()
                            Picker("Default Currency", selection: $vm.defaultCurrency) {
                                ForEach(CurrencyCode.allCases) { Text("\($0.code) – \($0.displayName)").tag($0) }
                            }
                            .pickerStyle(.menu)
                            .accessibilityIdentifier("defaultCurrencyPicker")
                        }
                        .frame(minHeight: Metrics.minTapTarget)
                        InfoNote(text: "Used for new events only. Existing events are never converted.")
                        divider
                        Toggle(isOn: $vm.hapticsEnabled) {
                            Label("Haptics", systemImage: "iphone.radiowaves.left.and.right")
                                .foregroundColor(.ecTextPrimary)
                        }
                        .toggleStyle(SwitchToggleStyle(tint: .ecBlue))
                        .frame(minHeight: Metrics.minTapTarget)
                    }

                    group("Help") {
                        row("View Onboarding", icon: "sparkles.rectangle.stack") { showOnboarding = true }
                    }

                    group("Data") {
                        row("Backup & Restore", icon: "externaldrive") { showBackup = true }
                        divider
                        row(vm.demoStatus.isLoaded ? "Sample Event Loaded" : "Load Demo Event", icon: "wand.and.stars") {
                            Task { await vm.loadDemo() }
                        }
                        .disabled(vm.isWorking || vm.demoStatus.isLoaded)
                        .accessibilityIdentifier("loadDemoButton")
                        divider
                        row("Remove Demo Event", icon: "minus.circle", tint: .ecCoral) { confirmRemoveDemo = true }
                            .disabled(vm.isWorking || !vm.demoStatus.isLoaded)
                    }

                    group("About") {
                        row("Privacy", icon: "hand.raised") { showPrivacy = true }
                        divider
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Even Circle")
                                .font(.body.weight(.semibold))
                                .foregroundColor(.ecTextPrimary)
                            Text(vm.versionText)
                                .ecCaptionFont()
                                .foregroundColor(.ecTextSecondary)
                            Text("An offline organiser for shared expenses. It never moves money.")
                                .ecCaptionFont()
                                .foregroundColor(.ecTextSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, minHeight: Metrics.minTapTarget, alignment: .leading)
                        .accessibilityElement(children: .combine)
                    }

                    group("Danger Zone") {
                        row("Reset All Data", icon: "trash", tint: .ecCoral) { showReset = true }
                            .accessibilityIdentifier("resetAllDataButton")
                    }
                }
                .padding(Spacing.screen)
            }
            .ecScreenBackground()
            .navigationTitle("Settings")
            .background(links)
            .fullScreenCover(isPresented: $showOnboarding) {
                OnboardingView(mode: .replay) { showOnboarding = false }
            }
            .task { await vm.refreshDemo() }
            .messageAlert($vm.alert)
            .toast($vm.toast)
            .alert("Remove the sample event?", isPresented: $confirmRemoveDemo) {
                Button("Remove", role: .destructive) { Task { await vm.removeDemo() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(vm.demoStatus.isModified
                     ? "The sample event was changed. Removing it deletes all of its people, expenses and payments, including ones you added. Your other events are not affected."
                     : "Removes Sample Weekend and everything in it. Your other events are not affected.")
            }
        }
        .navigationViewStyle(.stack)
        .sheet(isPresented: $showReset) {
            ResetAllDataSheet(deps: deps) {
                showReset = false
                onResetAllData()
            }
        }
    }

    private var links: some View {
        VStack {
            NavigationLink(isActive: $showBackup, destination: { LazyView(BackupScreen(deps: deps)) }, label: { EmptyView() })
            NavigationLink(isActive: $showPrivacy, destination: {
                LazyView(PrivacyScreen(deps: deps, onDeleteData: {
                    showPrivacy = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { showReset = true }
                }))
            }, label: { EmptyView() })
            NavigationLink(destination: EmptyView(), label: { EmptyView() })
        }
        .hidden()
    }

    private var divider: some View {
        Rectangle().fill(Color.ecDivider).frame(height: 1).accessibilityHidden(true)
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title.uppercased())
                .font(.footnote.weight(.semibold))
                .foregroundColor(.ecTextSecondary)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                content()
            }
            .ecCard(padding: 14)
        }
    }

    private func row(_ title: String, icon: String, tint: Color = .ecTextPrimary, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: icon)
                    .foregroundColor(tint)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(.ecTextSecondary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: Metrics.minTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Reset requires typing DELETE. Files already shared with other apps are not affected.
private struct ResetAllDataSheet: View {
    let deps: AppDependencies
    let onReset: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var confirmation = ""
    @State private var isWorking = false
    @State private var alert: AlertMessage?

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    Text("This deletes every event, person, expense and payment record on this device, the previous-data safety copy and all settings. Onboarding will open again.")
                        .foregroundColor(.ecTextPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    InfoNote(text: "Summaries or backup files you already shared or saved elsewhere are not affected. Export a backup first if you might need this data.")
                    FormField(label: "Type DELETE to confirm", required: true) {
                        TextField("DELETE", text: $confirmation)
                            .textInputAutocapitalization(.characters)
                            .disableAutocorrection(true)
                            .ecInputField()
                            .accessibilityIdentifier("resetConfirmField")
                    }
                    Button(isWorking ? "Resetting…" : "Reset All Data", role: .destructive) {
                        Task { await reset() }
                    }
                    .buttonStyle(SecondaryButtonStyle(tint: .ecCoral))
                    .disabled(confirmation != "DELETE" || isWorking)
                    .accessibilityIdentifier("confirmResetButton")
                }
                .padding(Spacing.screen)
            }
            .ecScreenBackground()
            .navigationTitle("Reset All Data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(isWorking) }
            }
            .messageAlert($alert)
        }
        .navigationViewStyle(.stack)
        .interactiveDismissDisabled(isWorking)
    }

    private func reset() async {
        guard confirmation == "DELETE", !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await deps.reset.resetAllData()
            onReset()
        } catch {
            alert = .error(error, title: "Couldn't reset")
        }
    }
}
