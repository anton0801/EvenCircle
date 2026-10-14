import Foundation

/// JSON schema v1 of `evencircle-backup-v1.json`.
/// Money is always an integer count of minor units, never a localized string or a float.
struct BackupDocument: Codable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var app: String
    var exportedAt: String
    var events: [EventDTO]

    struct EventDTO: Codable {
        var id: UUID
        var name: String
        var eventDate: String
        var currencyCode: String
        var currencyScale: Int
        var currencyLocked: Bool
        var note: String?
        var isArchived: Bool
        var isDemo: Bool
        var revision: Int64
        var createdAt: String
        var updatedAt: String
        var people: [PersonDTO]
        var expenses: [ExpenseDTO]
        var payments: [PaymentDTO]
    }

    struct PersonDTO: Codable {
        var id: UUID
        var name: String
        var avatarColorKey: String
        var createdAt: String
        var updatedAt: String
    }

    struct ExpenseDTO: Codable {
        var id: UUID
        var title: String
        var amountMinor: Int64
        var payerID: UUID
        var expenseDate: String
        var method: String
        var note: String?
        var createdAt: String
        var updatedAt: String
        var revision: Int64
        var shares: [ShareDTO]
        var items: [ItemDTO]
    }

    struct ShareDTO: Codable {
        var personID: UUID
        var allocatedMinor: Int64
        var weight: Int?
    }

    struct ItemDTO: Codable {
        var id: UUID
        var title: String
        var quantity: Int
        var unitPriceMinor: Int64
        var sortOrder: Int
        var shares: [ItemShareDTO]
    }

    struct ItemShareDTO: Codable {
        var personID: UUID
        var allocatedMinor: Int64
    }

    struct PaymentDTO: Codable {
        var id: UUID
        var fromID: UUID
        var toID: UUID
        var amountMinor: Int64
        var paymentDate: String
        var note: String?
        var operationID: UUID
        var createdAt: String
    }
}

/// Only reads the version, so an unknown schema is reported as such rather than as a parse error.
struct BackupVersionProbe: Decodable {
    var schemaVersion: Int?
}
