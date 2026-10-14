import Foundation

/// Everything the presentation layer may use, passed explicitly through initializers.
struct AppDependencies {
    let repository: EventRepository
    let events: EventUseCases
    let people: PeopleUseCases
    let expenses: ExpenseUseCases
    let payments: PaymentUseCases
    let demo: DemoUseCases
    let backup: BackupUseCases
    let reset: ResetUseCase
    let settings: SettingsUseCases
    let haptics: HapticFeedback
    let clock: AppClock
}

/// Composition root: the only place that knows concrete Data-layer types.
final class AppContainer {
    static let uiTestArgument = "-ec-uitest"

    let stack: CoreDataStack
    let dependencies: AppDependencies
    let codec: BackupCoding
    let isUITesting: Bool

    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        isUITesting = arguments.contains(AppContainer.uiTestArgument)
        // Unit tests run inside the app as host; keep them away from real data too.
        let isHostingUnitTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        let clock = AppClock.system

        let defaults: UserDefaults
        let files: BackupFileStore
        if isUITesting || isHostingUnitTests {
            // UI tests start from a clean install every launch and never touch real data.
            let suite = "EvenCircle.UITests"
            UserDefaults.standard.removePersistentDomain(forName: suite)
            defaults = UserDefaults(suiteName: suite) ?? .standard
            stack = CoreDataStack(location: .inMemory)
            files = BackupFileStore(rootDirectory: FileManager.default.temporaryDirectory.appendingPathComponent("EvenCircleUITests"))
        } else {
            defaults = .standard
            stack = CoreDataStack(location: .persistent)
            files = BackupFileStore()
        }

        let settingsRepository = UserDefaultsSettingsRepository(defaults: defaults)
        let repository = CoreDataEventRepository(stack: stack, clock: clock)
        let codec = JSONBackupCodec()
        self.codec = codec
        let settings = SettingsUseCases(settings: settingsRepository)

        dependencies = AppDependencies(
            repository: repository,
            events: EventUseCases(repository: repository, clock: clock),
            people: PeopleUseCases(repository: repository, clock: clock),
            expenses: ExpenseUseCases(repository: repository, clock: clock),
            payments: PaymentUseCases(repository: repository, clock: clock),
            demo: DemoUseCases(repository: repository, clock: clock),
            backup: BackupUseCases(repository: repository, codec: codec, files: files, settings: settingsRepository, clock: clock),
            reset: ResetUseCase(repository: repository, files: files, settings: settingsRepository),
            settings: settings,
            haptics: HapticFeedback(isEnabled: { settings.current.hapticsEnabled }),
            clock: clock
        )
    }
}
