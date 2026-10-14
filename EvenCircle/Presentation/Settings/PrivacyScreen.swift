import SwiftUI

/// Screen 18: offline privacy text. No developer contact, legal policy or URL is invented here;
/// the owner adds their own details and Privacy URL before publishing.
struct PrivacyScreen: View {
    let deps: AppDependencies
    let onDeleteData: () -> Void
    @State private var showBackup = false

    private let sections: [(title: String, icon: String, body: String)] = [
        ("Local Records", "iphone",
         "Events, names, notes, expenses and payment records you enter are stored only in Even Circle's private storage on this device. They are not sent to the developer. Even Circle has no account, sign-in, analytics, advertising or network requests, and it never asks for access to your contacts."),
        ("No Money Transfers", "hand.raised",
         "Even Circle never moves money and does not connect to banks or payment services. “Record Payment” is your own note about a transfer you already made elsewhere; the app can't confirm that money arrived. Suggested payments are calculations, not instructions or confirmations."),
        ("Sharing and Backups", "square.and.arrow.up",
         "A summary or a backup file leaves the app only when you choose a destination in the system share or export sheet. Backups include names, notes and amounts and are not encrypted by Even Circle, so store them carefully. Opening and cancelling the share sheet sends nothing."),
        ("Device Backups", "externaldrive",
         "Your data may be included in your device's regular system backups, depending on your own device settings. Even Circle has no cloud sync of its own."),
        ("Deleting Data", "trash",
         "You can delete single records, whole events, the sample event, or everything with Reset All Data in Settings. Deleting in the app doesn't remove summaries or backup files you already shared or saved elsewhere."),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.m) {
                ForEach(sections, id: \.title) { section in
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Label(section.title, systemImage: section.icon)
                            .font(.headline)
                            .foregroundColor(.ecTextPrimary)
                            .accessibilityAddTraits(.isHeader)
                        Text(section.body)
                            .font(.body)
                            .foregroundColor(.ecTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .ecCard()
                }

                VStack(spacing: Spacing.xs) {
                    Button { showBackup = true } label: { Label("Manage Data", systemImage: "externaldrive") }
                        .buttonStyle(SecondaryButtonStyle())
                    Button(role: .destructive, action: onDeleteData) { Label("Delete Data", systemImage: "trash") }
                        .buttonStyle(SecondaryButtonStyle(tint: .ecCoral))
                }
            }
            .padding(Spacing.screen)
        }
        .ecScreenBackground()
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
        .background(
            NavigationLink(isActive: $showBackup, destination: { LazyView(BackupScreen(deps: deps)) }, label: { EmptyView() })
                .hidden()
        )
    }
}
