import Foundation

@MainActor
final class AppRootViewModel: ObservableObject {
    enum Phase: Equatable {
        case loading
        case ready
        case failed(String)
    }

    @Published private(set) var phase: Phase = .loading
    @Published private(set) var onboardingCompleted: Bool
    @Published var pendingRecovery: ValidatedBackup?
    @Published var recoveryError: String?
    @Published private(set) var isRecovering = false

    let container: AppContainer
    var dependencies: AppDependencies { container.dependencies }

    init(container: AppContainer) {
        self.container = container
        onboardingCompleted = container.dependencies.settings.current.onboardingCompleted
    }

    /// Opens the store off the main thread. A failure never deletes data.
    func start() async {
        phase = .loading
        let stack = container.stack
        do {
            try await Task.detached(priority: .userInitiated) { try stack.load() }.value
            phase = .ready
        } catch {
            phase = .failed("Your saved events couldn't be opened. They have not been deleted. Try again, or import a backup.")
        }
    }

    func completeOnboarding() {
        dependencies.settings.update { $0.onboardingCompleted = true }
        onboardingCompleted = true
    }

    /// After Reset All Data: settings are cleared, so onboarding shows again.
    func didResetAllData() {
        onboardingCompleted = dependencies.settings.current.onboardingCompleted
    }

    // MARK: - Recovery when the store can't be opened

    func validateRecoveryFile(_ url: URL) async {
        recoveryError = nil
        do {
            let files = BackupFileStore()
            let codec = container.codec
            pendingRecovery = try await Task.detached(priority: .userInitiated) {
                try codec.decodeAndValidate(try files.readImportFile(at: url))
            }.value
        } catch {
            recoveryError = UserMessage.text(for: error)
        }
    }

    /// Moves the unreadable store aside (kept on disk), creates a fresh one and imports the backup.
    func importRecovery() async {
        guard let backup = pendingRecovery else { return }
        isRecovering = true
        defer { isRecovering = false }
        let stack = container.stack
        do {
            try await Task.detached(priority: .userInitiated) {
                _ = try stack.quarantineStoreFiles()
                try stack.load()
            }.value
            try await dependencies.repository.replaceAll(with: backup.aggregates)
            pendingRecovery = nil
            phase = .ready
        } catch {
            recoveryError = "The backup couldn't be imported. Your previous files were kept."
        }
    }
}
