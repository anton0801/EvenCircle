import Foundation

final class SettingsUseCases {
    private let settings: SettingsRepository

    init(settings: SettingsRepository) {
        self.settings = settings
    }

    var current: AppSettings { settings.load() }

    func update(_ change: (inout AppSettings) -> Void) {
        var value = settings.load()
        change(&value)
        settings.save(value)
    }
}

/// Backup export / import with a single internal safety copy.
final class BackupUseCases {
    private let repository: EventRepository
    private let codec: BackupCoding
    private let files: BackupFileStoring
    private let settings: SettingsRepository
    private let clock: AppClock

    init(repository: EventRepository, codec: BackupCoding, files: BackupFileStoring, settings: SettingsRepository, clock: AppClock) {
        self.repository = repository
        self.codec = codec
        self.files = files
        self.settings = settings
        self.clock = clock
    }

    func counts() async throws -> DataCounts {
        try await repository.counts()
    }

    func safetyCopyInfo() -> SafetyCopyInfo? {
        files.safetyCopyInfo()
    }

    /// Writes `evencircle-backup-v1.json` to a temporary location for the system export UI.
    func makeExportFile() async throws -> URL {
        let aggregates = try await repository.loadAll()
        let codec = self.codec
        let exportedAt = clock.now()
        let data = try await Task.detached(priority: .userInitiated) {
            try codec.encode(aggregates, exportedAt: exportedAt)
        }.value
        return try files.writeExportFile(data)
    }

    /// Last Export means the file was handed to the system UI, not that it reached anyone.
    func markExported() {
        var value = settings.load()
        value.lastExportAt = clock.now()
        settings.save(value)
    }

    func prepareImport(from url: URL) async throws -> ValidatedBackup {
        let files = self.files
        let codec = self.codec
        return try await Task.detached(priority: .userInitiated) {
            let data = try files.readImportFile(at: url)
            return try codec.decodeAndValidate(data)
        }.value
    }

    func validate(data: Data) async throws -> ValidatedBackup {
        let codec = self.codec
        return try await Task.detached(priority: .userInitiated) {
            try codec.decodeAndValidate(data)
        }.value
    }

    /// Replaces all data. If the current database is not empty, a safety copy is written first;
    /// if that fails, nothing is replaced.
    func replaceAll(with backup: ValidatedBackup) async throws {
        let current = try await repository.loadAll()
        if !current.isEmpty {
            let codec = self.codec
            let exportedAt = clock.now()
            let data = try await Task.detached(priority: .userInitiated) {
                try codec.encode(current, exportedAt: exportedAt)
            }.value
            try files.writeSafetyCopy(data)
        }
        try await repository.replaceAll(with: backup.aggregates)
    }

    func restoreSafetyCopy() async throws {
        let data = try files.readSafetyCopy()
        let backup = try await validate(data: data)
        try await repository.replaceAll(with: backup.aggregates)
    }

    func deleteSafetyCopy() throws {
        try files.deleteSafetyCopy()
    }
}

final class ResetUseCase {
    private let repository: EventRepository
    private let files: BackupFileStoring
    private let settings: SettingsRepository

    init(repository: EventRepository, files: BackupFileStoring, settings: SettingsRepository) {
        self.repository = repository
        self.files = files
        self.settings = settings
    }

    /// Clears the local database, the safety copy and settings. Files already shared with
    /// other apps are outside the app and are not affected.
    func resetAllData() async throws {
        try await repository.deleteAll()
        try? files.deleteSafetyCopy()
        files.deleteExportFiles()
        settings.reset()
    }
}
