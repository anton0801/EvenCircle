import Foundation

/// Files used by Backup & Restore: the temporary export file and the single internal safety copy.
/// Both live in the app's private container with file protection.
final class BackupFileStore: BackupFileStoring {
    static let exportFileName = "evencircle-backup-v1.json"

    private let fileManager = FileManager.default
    private let safetyDirectory: URL
    private let exportDirectory: URL

    init(rootDirectory: URL? = nil) {
        let support = rootDirectory
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("EvenCircle", isDirectory: true)
        safetyDirectory = support.appendingPathComponent("SafetyCopy", isDirectory: true)
        exportDirectory = fileManager.temporaryDirectory.appendingPathComponent("EvenCircleExport", isDirectory: true)
    }

    private var safetyCopyURL: URL { safetyDirectory.appendingPathComponent("previous-data.json") }

    private func ensureDirectory(_ url: URL) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true, attributes: [
            .protectionKey: FileProtectionType.completeUnlessOpen,
        ])
    }

    func writeExportFile(_ data: Data) throws -> URL {
        try ensureDirectory(exportDirectory)
        let url = exportDirectory.appendingPathComponent(BackupFileStore.exportFileName)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
        return url
    }

    func deleteExportFiles() {
        try? fileManager.removeItem(at: exportDirectory)
    }

    func readImportFile(at url: URL) throws -> Data {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        if values?.isRegularFile == false {
            throw BackupValidationError(message: "Choose a JSON backup file.")
        }
        if let size = values?.fileSize, size > DomainLimits.backupMaxBytes {
            throw BackupValidationError(message: "The file is larger than 50 MB.")
        }
        do {
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            guard data.count <= DomainLimits.backupMaxBytes else {
                throw BackupValidationError(message: "The file is larger than 50 MB.")
            }
            return data
        } catch let error as BackupValidationError {
            throw error
        } catch {
            throw BackupValidationError(message: "The file couldn't be read.")
        }
    }

    func safetyCopyInfo() -> SafetyCopyInfo? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: safetyCopyURL.path) else { return nil }
        let date = attributes[.modificationDate] as? Date ?? Date()
        let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
        return SafetyCopyInfo(createdAt: date, byteCount: size)
    }

    func writeSafetyCopy(_ data: Data) throws {
        try ensureDirectory(safetyDirectory)
        try data.write(to: safetyCopyURL, options: [.atomic, .completeFileProtectionUnlessOpen])
    }

    func readSafetyCopy() throws -> Data {
        guard fileManager.fileExists(atPath: safetyCopyURL.path) else {
            throw BackupValidationError(message: "There is no previous data copy.")
        }
        return try Data(contentsOf: safetyCopyURL)
    }

    func deleteSafetyCopy() throws {
        if fileManager.fileExists(atPath: safetyCopyURL.path) {
            try fileManager.removeItem(at: safetyCopyURL)
        }
    }
}
