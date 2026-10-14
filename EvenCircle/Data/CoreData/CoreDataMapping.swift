import CoreData
import Foundation

/// Converts between managed objects and domain values. Unknown enum values map to safe
/// defaults only for display; backup validation rejects them before they reach the store.
enum CoreDataMapping {
    static func aggregate(_ object: CDEvent) -> EventAggregate {
        let event = Event(
            id: object.id,
            name: object.name,
            eventDate: CalendarDate(isoString: object.eventDate) ?? CalendarDate(date: object.createdAt),
            currency: CurrencyCode(rawValue: object.currencyCode) ?? .eur,
            currencyLocked: object.currencyLocked,
            note: object.note,
            isArchived: object.isArchived,
            isDemo: object.isDemo,
            revision: object.revision,
            createdAt: object.createdAt,
            updatedAt: object.updatedAt
        )
        let people = object.people.map { person(eventID: object.id, $0) }
        let expenses = object.expenses.map { expense(eventID: object.id, $0) }
        let payments = object.payments.map { payment(eventID: object.id, $0) }
        return EventAggregate(event: event, people: people, expenses: expenses, payments: payments)
    }

    static func person(eventID: UUID, _ object: CDPerson) -> Person {
        Person(
            id: object.id,
            eventID: eventID,
            name: object.name,
            avatarColor: AvatarColorKey(rawValue: object.avatarColorKey) ?? .blue,
            createdAt: object.createdAt,
            updatedAt: object.updatedAt
        )
    }

    static func expense(eventID: UUID, _ object: CDExpense) -> Expense {
        let shares = object.shares
            .map { ExpenseShare(personID: $0.personID, allocatedMinor: $0.allocatedMinor, weight: $0.weight?.intValue) }
            .sorted { $0.personID.lowercasedString < $1.personID.lowercasedString }
        let items = object.items
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { item in
                ReceiptItem(
                    id: item.id,
                    title: item.title,
                    quantity: Int(item.quantity),
                    unitPriceMinor: item.unitPriceMinor,
                    sortOrder: Int(item.sortOrder),
                    shares: item.shares
                        .map { ReceiptItemShare(personID: $0.personID, allocatedMinor: $0.allocatedMinor) }
                        .sorted { $0.personID.lowercasedString < $1.personID.lowercasedString }
                )
            }
        return Expense(
            id: object.id,
            eventID: eventID,
            title: object.title,
            amountMinor: object.amountMinor,
            payerID: object.payerID,
            expenseDate: CalendarDate(isoString: object.expenseDate) ?? CalendarDate(date: object.createdAt),
            method: SplitMethod(rawValue: object.method) ?? .equal,
            note: object.note,
            createdAt: object.createdAt,
            updatedAt: object.updatedAt,
            revision: object.revision,
            shares: shares,
            items: items
        )
    }

    static func payment(eventID: UUID, _ object: CDPayment) -> Payment {
        Payment(
            id: object.id,
            eventID: eventID,
            fromID: object.fromID,
            toID: object.toID,
            amountMinor: object.amountMinor,
            paymentDate: CalendarDate(isoString: object.paymentDate) ?? CalendarDate(date: object.createdAt),
            note: object.note,
            operationID: object.operationID,
            createdAt: object.createdAt
        )
    }

    // MARK: - Writing

    @discardableResult
    static func insert(_ aggregate: EventAggregate, into context: NSManagedObjectContext) -> CDEvent {
        let event = CDEvent(context: context)
        event.id = aggregate.event.id
        event.name = aggregate.event.name
        event.eventDate = aggregate.event.eventDate.isoString
        event.currencyCode = aggregate.event.currency.code
        event.currencyScale = Int16(aggregate.event.currency.scale)
        event.currencyLocked = aggregate.event.currencyLocked
        event.note = aggregate.event.note
        event.isArchived = aggregate.event.isArchived
        event.isDemo = aggregate.event.isDemo
        event.revision = aggregate.event.revision
        event.createdAt = aggregate.event.createdAt
        event.updatedAt = aggregate.event.updatedAt
        for person in aggregate.people {
            insert(person, into: event, context: context)
        }
        for expense in aggregate.expenses {
            let object = CDExpense(context: context)
            object.id = expense.id
            object.createdAt = expense.createdAt
            object.event = event
            apply(expense, to: object, context: context)
        }
        for payment in aggregate.payments {
            insert(payment, into: event, context: context)
        }
        return event
    }

    static func insert(_ person: Person, into event: CDEvent, context: NSManagedObjectContext) {
        let object = CDPerson(context: context)
        object.id = person.id
        object.name = person.name
        object.avatarColorKey = person.avatarColor.rawValue
        object.createdAt = person.createdAt
        object.updatedAt = person.updatedAt
        object.event = event
    }

    static func insert(_ payment: Payment, into event: CDEvent, context: NSManagedObjectContext) {
        let object = CDPayment(context: context)
        object.id = payment.id
        object.fromID = payment.fromID
        object.toID = payment.toID
        object.amountMinor = payment.amountMinor
        object.paymentDate = payment.paymentDate.isoString
        object.note = payment.note
        object.operationID = payment.operationID
        object.createdAt = payment.createdAt
        object.event = event
    }

    /// Overwrites an expense's fields, shares and receipt lines. Old lines are deleted, so a
    /// switch from Items to Equal leaves no orphaned receipt rows behind.
    static func apply(_ expense: Expense, to object: CDExpense, context: NSManagedObjectContext) {
        object.title = expense.title
        object.amountMinor = expense.amountMinor
        object.payerID = expense.payerID
        object.expenseDate = expense.expenseDate.isoString
        object.method = expense.method.rawValue
        object.note = expense.note
        object.updatedAt = expense.updatedAt
        object.revision = expense.revision

        object.shares.forEach(context.delete)
        object.items.forEach(context.delete)

        for share in expense.shares {
            let shareObject = CDExpenseShare(context: context)
            shareObject.personID = share.personID
            shareObject.allocatedMinor = share.allocatedMinor
            shareObject.weight = share.weight.map { NSNumber(value: $0) }
            shareObject.expense = object
        }
        for item in expense.items {
            let itemObject = CDReceiptItem(context: context)
            itemObject.id = item.id
            itemObject.title = item.title
            itemObject.quantity = Int64(item.quantity)
            itemObject.unitPriceMinor = item.unitPriceMinor
            itemObject.sortOrder = Int64(item.sortOrder)
            itemObject.expense = object
            for share in item.shares {
                let shareObject = CDReceiptItemShare(context: context)
                shareObject.personID = share.personID
                shareObject.allocatedMinor = share.allocatedMinor
                shareObject.item = itemObject
            }
        }
    }
}
