import CoreData
import Foundation

@objc(CDEvent)
final class CDEvent: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var name: String
    @NSManaged var eventDate: String
    @NSManaged var currencyCode: String
    @NSManaged var currencyScale: Int16
    @NSManaged var currencyLocked: Bool
    @NSManaged var note: String?
    @NSManaged var isArchived: Bool
    @NSManaged var isDemo: Bool
    @NSManaged var revision: Int64
    @NSManaged var createdAt: Date
    @NSManaged var updatedAt: Date
    @NSManaged var people: Set<CDPerson>
    @NSManaged var expenses: Set<CDExpense>
    @NSManaged var payments: Set<CDPayment>
}

@objc(CDPerson)
final class CDPerson: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var name: String
    @NSManaged var avatarColorKey: String
    @NSManaged var createdAt: Date
    @NSManaged var updatedAt: Date
    @NSManaged var event: CDEvent?
}

@objc(CDExpense)
final class CDExpense: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var title: String
    @NSManaged var amountMinor: Int64
    @NSManaged var payerID: UUID
    @NSManaged var expenseDate: String
    @NSManaged var method: String
    @NSManaged var note: String?
    @NSManaged var createdAt: Date
    @NSManaged var updatedAt: Date
    @NSManaged var revision: Int64
    /// Last save intent applied to this record; makes retries idempotent.
    @NSManaged var operationID: UUID?
    @NSManaged var event: CDEvent?
    @NSManaged var shares: Set<CDExpenseShare>
    @NSManaged var items: Set<CDReceiptItem>
}

@objc(CDExpenseShare)
final class CDExpenseShare: NSManagedObject {
    @NSManaged var personID: UUID
    @NSManaged var allocatedMinor: Int64
    @NSManaged var weight: NSNumber?
    @NSManaged var expense: CDExpense?
}

@objc(CDReceiptItem)
final class CDReceiptItem: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var title: String
    @NSManaged var quantity: Int64
    @NSManaged var unitPriceMinor: Int64
    @NSManaged var sortOrder: Int64
    @NSManaged var expense: CDExpense?
    @NSManaged var shares: Set<CDReceiptItemShare>
}

@objc(CDReceiptItemShare)
final class CDReceiptItemShare: NSManagedObject {
    @NSManaged var personID: UUID
    @NSManaged var allocatedMinor: Int64
    @NSManaged var item: CDReceiptItem?
}

@objc(CDPayment)
final class CDPayment: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var fromID: UUID
    @NSManaged var toID: UUID
    @NSManaged var amountMinor: Int64
    @NSManaged var paymentDate: String
    @NSManaged var note: String?
    @NSManaged var operationID: UUID
    @NSManaged var createdAt: Date
    @NSManaged var event: CDEvent?
}
