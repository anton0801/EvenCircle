import Foundation

/// The complete, unsaved state of an expense editor.
struct ExpenseDraft: Equatable {
    struct Item: Equatable, Identifiable {
        let id: UUID
        var title: String
        var quantity: Int
        var unitPriceMinor: Int64
        /// Recipients in the order they were chosen; order does not affect allocation.
        var recipientIDs: [UUID]
    }

    let id: UUID
    let eventID: UUID
    var title: String
    var amountMinor: Int64?
    var payerID: UUID?
    var date: CalendarDate
    var note: String?
    var method: SplitMethod
    /// Included people → weight. Equal ignores the weights and uses 1.
    var participants: [UUID: Int]
    var items: [Item]
    /// Preserved from the saved expense when editing.
    var createdAt: Date?
    var revision: Int64
}

enum ExpenseDraftField: Hashable {
    case title, amount, payer, date, note, participants, items
    case weight(UUID)
    case item(UUID)
}

struct ExpenseDraftIssue: Equatable {
    let field: ExpenseDraftField
    let message: String
}

struct ExpenseDraftIssues: Error, Equatable {
    let issues: [ExpenseDraftIssue]

    var first: ExpenseDraftIssue? { issues.first }
    func message(for field: ExpenseDraftField) -> String? { issues.first { $0.field == field }?.message }
}

/// Validates a draft and computes exact allocations. Preview and Save use the same function,
/// so the saved record is always identical to what was previewed.
enum ExpenseBuilder {
    static func build(
        _ draft: ExpenseDraft,
        eventPeopleIDs: Set<UUID>,
        today: CalendarDate,
        now: Date
    ) -> Result<Expense, ExpenseDraftIssues> {
        var issues: [ExpenseDraftIssue] = []

        if let error = TextRules.validateRequired(draft.title, field: "Title", range: DomainLimits.expenseTitleLength) {
            issues.append(.init(field: .title, message: error.message))
        }
        if let payer = draft.payerID {
            if !eventPeopleIDs.contains(payer) {
                issues.append(.init(field: .payer, message: "Choose who paid from this event's people."))
            }
        } else {
            issues.append(.init(field: .payer, message: "Choose who paid."))
        }
        if draft.date > today {
            issues.append(.init(field: .date, message: "The expense date can't be in the future."))
        }
        if let error = TextRules.validateNote(draft.note, maxLength: DomainLimits.expenseNoteMaxLength) {
            issues.append(.init(field: .note, message: error.message))
        }

        var amount: Int64 = 0
        var shares: [ExpenseShare] = []
        var items: [ReceiptItem] = []

        switch draft.method {
        case .equal, .shares:
            if let value = draft.amountMinor {
                if value <= 0 {
                    issues.append(.init(field: .amount, message: MoneyRangeError.notPositive.message))
                } else if value > DomainLimits.maxExpenseMinor {
                    issues.append(.init(field: .amount, message: "This amount is above the limit for one expense."))
                } else {
                    amount = value
                }
            } else {
                issues.append(.init(field: .amount, message: "Enter an amount."))
            }

            let included = draft.participants.keys.sorted { $0.lowercasedString < $1.lowercasedString }
            if included.isEmpty {
                issues.append(.init(field: .participants, message: "Select at least one person."))
            }
            for id in included where !eventPeopleIDs.contains(id) {
                issues.append(.init(field: .participants, message: "Someone selected is no longer in this event."))
                break
            }
            var participants: [LargestRemainderAllocator.Participant] = []
            for id in included {
                let weight = draft.method == .equal ? 1 : (draft.participants[id] ?? 0)
                if !DomainLimits.weightRange.contains(weight) {
                    issues.append(.init(field: .weight(id), message: "Use a whole number from 1 to 1000."))
                }
                participants.append(.init(id, weight: weight))
            }

            if issues.isEmpty {
                do {
                    let allocations = try LargestRemainderAllocator.allocate(amount: amount, participants: participants)
                    shares = participants.map { participant in
                        ExpenseShare(
                            personID: participant.personID,
                            allocatedMinor: allocations[participant.personID] ?? 0,
                            weight: participant.weight
                        )
                    }
                } catch {
                    issues.append(.init(field: .amount, message: "This split can't be calculated. Check the amount and shares."))
                }
            }

        case .items:
            if draft.items.isEmpty {
                issues.append(.init(field: .items, message: "Add at least one receipt item."))
            } else if draft.items.count > DomainLimits.maxItemsPerExpense {
                issues.append(.init(field: .items, message: "An expense can have up to \(DomainLimits.maxItemsPerExpense) items."))
            }
            for item in draft.items {
                if let error = TextRules.validateRequired(item.title, field: "Item name", range: DomainLimits.itemTitleLength) {
                    issues.append(.init(field: .item(item.id), message: error.message))
                } else if !DomainLimits.quantityRange.contains(item.quantity) {
                    issues.append(.init(field: .item(item.id), message: "Quantity must be a whole number from 1 to 999."))
                } else if item.unitPriceMinor <= 0 || item.unitPriceMinor > DomainLimits.maxUnitPriceMinor {
                    issues.append(.init(field: .item(item.id), message: "Unit price must be greater than 0 and within the limit."))
                } else if item.recipientIDs.isEmpty {
                    issues.append(.init(field: .item(item.id), message: "Assign at least one person to this item."))
                } else if item.recipientIDs.contains(where: { !eventPeopleIDs.contains($0) }) {
                    issues.append(.init(field: .item(item.id), message: "Someone assigned is no longer in this event."))
                }
            }

            if issues.isEmpty {
                let lines = draft.items.map {
                    ReceiptCalculator.Line(id: $0.id, quantity: $0.quantity, unitPriceMinor: $0.unitPriceMinor, recipientIDs: $0.recipientIDs)
                }
                do {
                    let result = try ReceiptCalculator.calculate(lines: lines)
                    amount = result.totalMinor
                    items = draft.items.enumerated().map { index, item in
                        let line = result.lines[index]
                        return ReceiptItem(
                            id: item.id,
                            title: TextRules.clean(item.title),
                            quantity: item.quantity,
                            unitPriceMinor: item.unitPriceMinor,
                            sortOrder: index,
                            shares: item.recipientIDs.map { ReceiptItemShare(personID: $0, allocatedMinor: line.allocations[$0] ?? 0) }
                        )
                    }
                    let recipients = Set(draft.items.flatMap(\.recipientIDs)).sorted { $0.lowercasedString < $1.lowercasedString }
                    shares = recipients.map { ExpenseShare(personID: $0, allocatedMinor: result.totals[$0] ?? 0, weight: nil) }
                } catch ReceiptCalculator.Failure.lineAboveLimit(let id) {
                    issues.append(.init(field: .item(id), message: "This line is above the limit for one expense."))
                } catch ReceiptCalculator.Failure.totalAboveLimit {
                    issues.append(.init(field: .items, message: "The receipt total is above the limit for one expense."))
                } catch {
                    issues.append(.init(field: .items, message: "The receipt total is too large to calculate."))
                }
            }
        }

        guard issues.isEmpty else { return .failure(ExpenseDraftIssues(issues: issues)) }

        let allocated = shares.reduce(Int64(0)) { $0 + $1.allocatedMinor }
        guard allocated == amount else {
            return .failure(ExpenseDraftIssues(issues: [.init(field: .amount, message: "Internal check failed: allocated amount differs from the total.")]))
        }

        let expense = Expense(
            id: draft.id,
            eventID: draft.eventID,
            title: TextRules.clean(draft.title),
            amountMinor: amount,
            payerID: draft.payerID!,
            expenseDate: draft.date,
            method: draft.method,
            note: TextRules.cleanNote(draft.note),
            createdAt: draft.createdAt ?? now,
            updatedAt: now,
            revision: draft.revision + 1,
            shares: shares,
            items: items
        )
        return .success(expense)
    }
}
