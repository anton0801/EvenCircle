import Foundation

/// Fixed set of six avatar colours. A colour never identifies a person on its own:
/// avatars always show initials and expose the person's name to VoiceOver.
enum AvatarColorKey: String, CaseIterable, Codable, Sendable {
    case blue, lilac, mint, coral, amber, sky

    var displayName: String {
        switch self {
        case .blue: return "Blue"
        case .lilac: return "Lilac"
        case .mint: return "Mint"
        case .coral: return "Coral"
        case .amber: return "Amber"
        case .sky: return "Sky"
        }
    }

    /// Deterministic rotation used for newly added people.
    static func suggested(forIndex index: Int) -> AvatarColorKey {
        let all = AvatarColorKey.allCases
        return all[((index % all.count) + all.count) % all.count]
    }
}

enum SplitMethod: String, CaseIterable, Codable, Sendable {
    case equal = "Equal"
    case shares = "Shares"
    case items = "Items"

    var title: String { rawValue }
}

struct Event: Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    var eventDate: CalendarDate
    var currency: CurrencyCode
    var currencyLocked: Bool
    var note: String?
    var isArchived: Bool
    var isDemo: Bool
    var revision: Int64
    var createdAt: Date
    var updatedAt: Date

    var currencyScale: Int { currency.scale }
}

struct Person: Identifiable, Equatable, Sendable {
    let id: UUID
    let eventID: UUID
    var name: String
    var avatarColor: AvatarColorKey
    var createdAt: Date
    var updatedAt: Date
}

/// A person's part of one expense. `weight` is set for Equal (always 1) and Shares; nil for Items.
struct ExpenseShare: Equatable, Sendable {
    let personID: UUID
    var allocatedMinor: Int64
    var weight: Int?
}

/// One recipient of a receipt line. Recipients with a zero allocation (rounding) are still stored.
struct ReceiptItemShare: Equatable, Sendable {
    let personID: UUID
    var allocatedMinor: Int64
}

struct ReceiptItem: Identifiable, Equatable, Sendable {
    let id: UUID
    var title: String
    var quantity: Int
    var unitPriceMinor: Int64
    var sortOrder: Int
    var shares: [ReceiptItemShare]

    /// quantity × unit price; callers validate limits before relying on this.
    var lineAmountMinor: Int64 { Int64(quantity) * unitPriceMinor }
}

struct Expense: Identifiable, Equatable, Sendable {
    let id: UUID
    let eventID: UUID
    var title: String
    var amountMinor: Int64
    var payerID: UUID
    var expenseDate: CalendarDate
    var method: SplitMethod
    var note: String?
    var createdAt: Date
    var updatedAt: Date
    var revision: Int64
    var shares: [ExpenseShare]
    var items: [ReceiptItem]

    func share(for personID: UUID) -> ExpenseShare? {
        shares.first { $0.personID == personID }
    }

    var totalAllocatedMinor: Int64 {
        shares.reduce(0) { $0 + $1.allocatedMinor }
    }

    /// Every person referenced by this expense (payer, shares, receipt recipients).
    var referencedPersonIDs: Set<UUID> {
        var ids: Set<UUID> = [payerID]
        shares.forEach { ids.insert($0.personID) }
        items.forEach { item in item.shares.forEach { ids.insert($0.personID) } }
        return ids
    }
}

/// A personal record of a transfer the user made outside the app. Not a payment confirmation.
struct Payment: Identifiable, Equatable, Sendable {
    let id: UUID
    let eventID: UUID
    var fromID: UUID
    var toID: UUID
    var amountMinor: Int64
    var paymentDate: CalendarDate
    var note: String?
    var operationID: UUID
    var createdAt: Date
}

/// An event with everything that belongs to it, loaded as one consistent snapshot.
struct EventAggregate: Identifiable, Equatable, Sendable {
    var event: Event
    var people: [Person]
    var expenses: [Expense]
    var payments: [Payment]

    var id: UUID { event.id }

    func person(_ id: UUID) -> Person? {
        people.first { $0.id == id }
    }

    func personName(_ id: UUID) -> String {
        person(id)?.name ?? "Unknown person"
    }

    func expense(_ id: UUID) -> Expense? {
        expenses.first { $0.id == id }
    }

    func payment(_ id: UUID) -> Payment? {
        payments.first { $0.id == id }
    }

    /// True when the person appears in any saved expense or payment.
    func isPersonLinked(_ personID: UUID) -> Bool {
        expenses.contains { $0.referencedPersonIDs.contains(personID) }
            || payments.contains { $0.fromID == personID || $0.toID == personID }
    }

    /// People sorted by creation, then UUID – a stable order unaffected by renaming.
    var orderedPeople: [Person] {
        people.sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
            return lhs.id.lowercasedString < rhs.id.lowercasedString
        }
    }

    /// Expenses by date (newest first), then createdAt (newest first), then UUID.
    var orderedExpenses: [Expense] {
        expenses.sorted { lhs, rhs in
            if lhs.expenseDate != rhs.expenseDate { return lhs.expenseDate > rhs.expenseDate }
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
            return lhs.id.lowercasedString < rhs.id.lowercasedString
        }
    }

    /// Payments by date (newest first), then createdAt (newest first), then UUID.
    var orderedPayments: [Payment] {
        payments.sorted { lhs, rhs in
            if lhs.paymentDate != rhs.paymentDate { return lhs.paymentDate > rhs.paymentDate }
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
            return lhs.id.lowercasedString < rhs.id.lowercasedString
        }
    }

    func replacingExpense(_ expense: Expense) -> EventAggregate {
        var copy = self
        if let index = copy.expenses.firstIndex(where: { $0.id == expense.id }) {
            copy.expenses[index] = expense
        } else {
            copy.expenses.append(expense)
        }
        return copy
    }

    func removingExpense(_ id: UUID) -> EventAggregate {
        var copy = self
        copy.expenses.removeAll { $0.id == id }
        return copy
    }

    func addingPayment(_ payment: Payment) -> EventAggregate {
        var copy = self
        copy.payments.append(payment)
        return copy
    }

    func removingPayment(_ id: UUID) -> EventAggregate {
        var copy = self
        copy.payments.removeAll { $0.id == id }
        return copy
    }
}

extension UUID {
    /// Stable lexicographic key used for deterministic tie-breaking.
    var lowercasedString: String { uuidString.lowercased() }
}

struct AppSettings: Equatable, Sendable {
    var onboardingCompleted: Bool
    var defaultCurrency: CurrencyCode
    var hapticsEnabled: Bool
    var lastExportAt: Date?

    static let `default` = AppSettings(onboardingCompleted: false, defaultCurrency: .eur, hapticsEnabled: true, lastExportAt: nil)
}
