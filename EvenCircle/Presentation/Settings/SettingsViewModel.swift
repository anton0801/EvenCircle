import Combine
import Foundation

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var defaultCurrency: CurrencyCode {
        didSet { deps.settings.update { $0.defaultCurrency = defaultCurrency } }
    }
    @Published var hapticsEnabled: Bool {
        didSet { deps.settings.update { $0.hapticsEnabled = hapticsEnabled } }
    }
    @Published private(set) var demoStatus = DemoStatus(isLoaded: false, isModified: false)
    @Published private(set) var isWorking = false
    @Published var alert: AlertMessage?
    @Published var toast: String?

    let deps: AppDependencies
    private var cancellables: Set<AnyCancellable> = []

    init(deps: AppDependencies) {
        self.deps = deps
        let settings = deps.settings.current
        defaultCurrency = settings.defaultCurrency
        hapticsEnabled = settings.hapticsEnabled
        deps.repository.changes
            .sink { [weak self] _ in Task { await self?.refreshDemo() } }
            .store(in: &cancellables)
    }

    var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "Version \(version) (\(build))"
    }

    func refreshDemo() async {
        if let status = try? await deps.demo.status() { demoStatus = status }
    }

    func loadDemo() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            switch try await deps.demo.load() {
            case .applied:
                deps.haptics.success()
                toast = "Sample Weekend added to Events"
            case .alreadyApplied:
                alert = AlertMessage(title: "Already loaded", message: "The Sample Weekend event is already in Events.")
            }
            await refreshDemo()
        } catch {
            alert = .error(error, title: "Couldn't load the sample")
        }
    }

    func removeDemo() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await deps.demo.remove()
            deps.haptics.success()
            toast = "Sample event removed"
            await refreshDemo()
        } catch {
            alert = .error(error, title: "Couldn't remove the sample")
        }
    }
}
