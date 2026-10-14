import CoreData
import Foundation

/// The Core Data model, defined in code so it is reviewable as text and shared by app and tests.
enum CoreDataModel {
    /// Built once: several models claiming the same classes confuse Core Data.
    static let shared: NSManagedObjectModel = makeModel()

    private static func attribute(
        _ name: String,
        _ type: NSAttributeType,
        optional: Bool = false,
        defaultValue: Any? = nil
    ) -> NSAttributeDescription {
        let attribute = NSAttributeDescription()
        attribute.name = name
        attribute.attributeType = type
        attribute.isOptional = optional
        attribute.defaultValue = defaultValue
        return attribute
    }

    private static func entity(_ name: String, _ cls: AnyClass, _ attributes: [NSAttributeDescription]) -> NSEntityDescription {
        let entity = NSEntityDescription()
        entity.name = name
        entity.managedObjectClassName = NSStringFromClass(cls)
        entity.properties = attributes
        return entity
    }

    private static func link(
        _ parent: NSEntityDescription, _ toMany: String,
        _ child: NSEntityDescription, _ toOne: String
    ) {
        let many = NSRelationshipDescription()
        many.name = toMany
        many.destinationEntity = child
        many.minCount = 0
        many.maxCount = 0
        many.deleteRule = .cascadeDeleteRule
        many.isOptional = true

        let one = NSRelationshipDescription()
        one.name = toOne
        one.destinationEntity = parent
        one.minCount = 0
        one.maxCount = 1
        one.deleteRule = .nullifyDeleteRule
        one.isOptional = true

        many.inverseRelationship = one
        one.inverseRelationship = many
        parent.properties.append(many)
        child.properties.append(one)
    }

    private static func makeModel() -> NSManagedObjectModel {
        let event = entity("CDEvent", CDEvent.self, [
            attribute("id", .UUIDAttributeType),
            attribute("name", .stringAttributeType),
            attribute("eventDate", .stringAttributeType),
            attribute("currencyCode", .stringAttributeType),
            attribute("currencyScale", .integer16AttributeType, defaultValue: 2),
            attribute("currencyLocked", .booleanAttributeType, defaultValue: false),
            attribute("note", .stringAttributeType, optional: true),
            attribute("isArchived", .booleanAttributeType, defaultValue: false),
            attribute("isDemo", .booleanAttributeType, defaultValue: false),
            attribute("revision", .integer64AttributeType, defaultValue: 0),
            attribute("createdAt", .dateAttributeType),
            attribute("updatedAt", .dateAttributeType),
        ])
        let person = entity("CDPerson", CDPerson.self, [
            attribute("id", .UUIDAttributeType),
            attribute("name", .stringAttributeType),
            attribute("avatarColorKey", .stringAttributeType),
            attribute("createdAt", .dateAttributeType),
            attribute("updatedAt", .dateAttributeType),
        ])
        let expense = entity("CDExpense", CDExpense.self, [
            attribute("id", .UUIDAttributeType),
            attribute("title", .stringAttributeType),
            attribute("amountMinor", .integer64AttributeType, defaultValue: 0),
            attribute("payerID", .UUIDAttributeType),
            attribute("expenseDate", .stringAttributeType),
            attribute("method", .stringAttributeType),
            attribute("note", .stringAttributeType, optional: true),
            attribute("createdAt", .dateAttributeType),
            attribute("updatedAt", .dateAttributeType),
            attribute("revision", .integer64AttributeType, defaultValue: 0),
            attribute("operationID", .UUIDAttributeType, optional: true),
        ])
        let share = entity("CDExpenseShare", CDExpenseShare.self, [
            attribute("personID", .UUIDAttributeType),
            attribute("allocatedMinor", .integer64AttributeType, defaultValue: 0),
            attribute("weight", .integer64AttributeType, optional: true),
        ])
        let item = entity("CDReceiptItem", CDReceiptItem.self, [
            attribute("id", .UUIDAttributeType),
            attribute("title", .stringAttributeType),
            attribute("quantity", .integer64AttributeType, defaultValue: 1),
            attribute("unitPriceMinor", .integer64AttributeType, defaultValue: 0),
            attribute("sortOrder", .integer64AttributeType, defaultValue: 0),
        ])
        let itemShare = entity("CDReceiptItemShare", CDReceiptItemShare.self, [
            attribute("personID", .UUIDAttributeType),
            attribute("allocatedMinor", .integer64AttributeType, defaultValue: 0),
        ])
        let payment = entity("CDPayment", CDPayment.self, [
            attribute("id", .UUIDAttributeType),
            attribute("fromID", .UUIDAttributeType),
            attribute("toID", .UUIDAttributeType),
            attribute("amountMinor", .integer64AttributeType, defaultValue: 0),
            attribute("paymentDate", .stringAttributeType),
            attribute("note", .stringAttributeType, optional: true),
            attribute("operationID", .UUIDAttributeType),
            attribute("createdAt", .dateAttributeType),
        ])

        link(event, "people", person, "event")
        link(event, "expenses", expense, "event")
        link(event, "payments", payment, "event")
        link(expense, "shares", share, "expense")
        link(expense, "items", item, "expense")
        link(item, "shares", itemShare, "item")

        event.uniquenessConstraints = [["id"]]
        person.uniquenessConstraints = [["id"]]
        expense.uniquenessConstraints = [["id"]]
        item.uniquenessConstraints = [["id"]]
        payment.uniquenessConstraints = [["id"], ["operationID"]]

        let model = NSManagedObjectModel()
        model.entities = [event, person, expense, share, item, itemShare, payment]
        return model
    }
}
