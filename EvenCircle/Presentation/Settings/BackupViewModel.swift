import Foundation

@MainActor
final class BackupViewModel: ObservableObject {
    enum Activity: Equatable {
        case idle, exporting, validating, replacing, restoring
    }

    @Published private(set) var counts: DataCounts?
    @Published private(set) var lastExportAt: Date?
    @Published private(set) var safetyCopy: SafetyCopyInfo?
    @Published private(set) var pending: ValidatedBackup?
    @Published private(set) var activity: Activity = .idle
    @Published private(set) var importError: String?
    @Published var alert: AlertMessage?
    @Published var toast: String?

    private let deps: AppDependencies

    init(deps: AppDependencies) {
        self.deps = deps
    }

    var isBusy: Bool { activity != .idle }

    func refresh() async {
        counts = try? await deps.backup.counts()
        lastExportAt = deps.settings.current.lastExportAt
        safetyCopy = deps.backup.safetyCopyInfo()
    }

    func export() async {
        guard !isBusy else { return }
        activity = .exporting
        do {
            let url = try await deps.backup.makeExportFile()
            activity = .idle
            SystemShare.present(items: [url]) { [weak self] completed in
                guard let self, completed else { return }
                self.deps.backup.markExported()
                self.toast = "Backup handed to the system"
                Task { await self.refresh() }
            }
        } catch {
            activity = .idle
            alert = .error(error, title: "Couldn't create the backup")
        }
    }

    func validate(_ url: URL) async {
        guard !isBusy else { return }
        activity = .validating
        importError = nil
        pending = nil
        do {
            pending = try await deps.backup.prepareImport(from: url)
        } catch {
            importError = UserMessage.text(for: error)
        }
        activity = .idle
    }

    func cancelImport() {
        pending = nil
        importError = nil
    }

    func replaceAll() async {
        guard let pending, !isBusy else { return }
        activity = .replacing
        do {
            try await deps.backup.replaceAll(with: pending)
            self.pending = nil
            deps.haptics.success()
            toast = "Backup imported"
        } catch {
            alert = .error(error, title: "Import failed – your data is unchanged")
        }
        activity = .idle
        await refresh()
    }

    func restorePrevious() async {
        guard !isBusy else { return }
        activity = .restoring
        do {
            try await deps.backup.restoreSafetyCopy()
            deps.haptics.success()
            toast = "Previous data restored"
        } catch {
            alert = .error(error, title: "Couldn't restore – your data is unchanged")
        }
        activity = .idle
        await refresh()
    }

    func deletePrevious() async {
        do {
            try deps.backup.deleteSafetyCopy()
            toast = "Previous copy deleted"
        } catch {
            alert = .error(error, title: "Couldn't delete the copy")
        }
        await refresh()
    }
}
