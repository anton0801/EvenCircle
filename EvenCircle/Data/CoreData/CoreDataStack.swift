import CoreData
import Foundation

enum StoreLocation: Equatable {
    /// SQLite in the app's private Application Support directory, with file protection.
    case persistent
    /// SQLite at /dev/null: same constraints as production, nothing on disk. Used by tests.
    case inMemory
}

enum StoreLoadError: Error {
    case failed(String)
}

final class CoreDataStack {
    let container: NSPersistentContainer
    private let location: StoreLocation
    private(set) lazy var context: NSManagedObjectContext = {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSErrorMergePolicy
        context.undoManager = nil
        context.name = "EvenCircle.writer"
        return context
    }()

    init(location: StoreLocation) {
        self.location = location
        container = NSPersistentContainer(name: "EvenCircle", managedObjectModel: CoreDataModel.shared)
        container.persistentStoreDescriptions = [CoreDataStack.makeDescription(for: location)]
    }

    static var storeDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("EvenCircle", isDirectory: true)
    }

    static var storeURL: URL { storeDirectory.appendingPathComponent("EvenCircle.sqlite") }

    private static func makeDescription(for location: StoreLocation) -> NSPersistentStoreDescription {
        let description: NSPersistentStoreDescription
        switch location {
        case .persistent:
            try? FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true, attributes: [
                .protectionKey: FileProtectionType.completeUnlessOpen,
            ])
            description = NSPersistentStoreDescription(url: storeURL)
            description.setOption(FileProtectionType.completeUnlessOpen as NSObject, forKey: NSPersistentStoreFileProtectionKey)
        case .inMemory:
            description = NSPersistentStoreDescription(url: URL(fileURLWithPath: "/dev/null"))
        }
        description.type = NSSQLiteStoreType
        description.shouldAddStoreAsynchronously = false
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        return description
    }

    /// Loads the store synchronously. Call off the main thread.
    func load() throws {
        guard container.persistentStoreCoordinator.persistentStores.isEmpty else { return }
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError {
            #if DEBUG
            print("Even Circle store load failed: \(loadError)")
            #endif
            throw StoreLoadError.failed((loadError as NSError).localizedDescription)
        }
    }

    /// Moves an unreadable store aside (never deletes it) so a backup can be imported into a fresh one.
    func quarantineStoreFiles() throws -> URL {
        let fm = FileManager.default
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let folder = CoreDataStack.storeDirectory.appendingPathComponent("Unreadable-\(stamp)", isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        for suffix in ["", "-wal", "-shm"] {
            let source = URL(fileURLWithPath: CoreDataStack.storeURL.path + suffix)
            if fm.fileExists(atPath: source.path) {
                try fm.moveItem(at: source, to: folder.appendingPathComponent(source.lastPathComponent))
            }
        }
        return folder
    }
}
