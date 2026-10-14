import Foundation

/// Encodes backups and validates imported ones completely before anything touches the database.
///
/// Import never executes code and never uses file paths from the JSON. Historical payments are
/// checked for structure only (positive, different people, existing references) – not against
/// current balances, because expenses may have been corrected after the payment was recorded.
final class JSONBackupCodec: BackupCoding {
    private static func timestampFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    private static func parseTimestamp(_ text: String) -> Date? {
        if let date = timestampFormatter().date(from: text) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: text)
    }

    // MARK: - Export

    func encode(_ aggregates: [EventAggregate], exportedAt: Date) throws -> Data {
        let formatter = JSONBackupCodec.timestampFormatter()
        let stamp = { (date: Date) in formatter.string(from: date) }
        let ordered = aggregates.sorted { lhs, rhs in
            if lhs.event.createdAt != rhs.event.createdAt { return lhs.event.createdAt < rhs.event.createdAt }
            return lhs.event.id.lowercasedString < rhs.event.id.lowercasedString
        }
        let document = BackupDocument(
            schemaVersion: BackupDocument.currentSchemaVersion,
            app: "Even Circle",
            exportedAt: stamp(exportedAt),
            events: ordered.map { aggregate in
                let event = aggregate.event
                return BackupDocument.EventDTO(
                    id: event.id,
                    name: event.name,
                    eventDate: event.eventDate.isoString,
                    currencyCode: event.currency.code,
                    currencyScale: event.currency.scale,
                    currencyLocked: event.currencyLocked,
                    note: event.note,
                    isArchived: event.isArchived,
                    isDemo: event.isDemo,
                    revision: event.revision,
                    createdAt: stamp(event.createdAt),
                    updatedAt: stamp(event.updatedAt),
                    people: aggregate.orderedPeople.map {
                        .init(id: $0.id, name: $0.name, avatarColorKey: $0.avatarColor.rawValue,
                              createdAt: stamp($0.createdAt), updatedAt: stamp($0.updatedAt))
                    },
                    expenses: aggregate.orderedExpenses.reversed().map { expense in
                        .init(
                            id: expense.id,
                            title: expense.title,
                            amountMinor: expense.amountMinor,
                            payerID: expense.payerID,
                            expenseDate: expense.expenseDate.isoString,
                            method: expense.method.rawValue,
                            note: expense.note,
                            createdAt: stamp(expense.createdAt),
                            updatedAt: stamp(expense.updatedAt),
                            revision: expense.revision,
                            shares: expense.shares.map { .init(personID: $0.personID, allocatedMinor: $0.allocatedMinor, weight: $0.weight) },
                            items: expense.items.sorted { $0.sortOrder < $1.sortOrder }.map { item in
                                .init(
                                    id: item.id,
                                    title: item.title,
                                    quantity: item.quantity,
                                    unitPriceMinor: item.unitPriceMinor,
                                    sortOrder: item.sortOrder,
                                    shares: item.shares.map { .init(personID: $0.personID, allocatedMinor: $0.allocatedMinor) }
                                )
                            }
                        )
                    },
                    payments: aggregate.orderedPayments.reversed().map {
                        .init(id: $0.id, fromID: $0.fromID, toID: $0.toID, amountMinor: $0.amountMinor,
                              paymentDate: $0.paymentDate.isoString, note: $0.note, operationID: $0.operationID,
                              createdAt: stamp($0.createdAt))
                    }
                )
            }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(document)
    }

    // MARK: - Import

    func decodeAndValidate(_ data: Data) throws -> ValidatedBackup {
        guard data.count <= DomainLimits.backupMaxBytes else {
            throw BackupValidationError(message: "The file is larger than 50 MB.")
        }
        guard String(data: data, encoding: .utf8) != nil else {
            throw BackupValidationError(message: "The file is not UTF-8 text.")
        }
        let decoder = JSONDecoder()
        guard let probe = try? decoder.decode(BackupVersionProbe.self, from: data) else {
            throw BackupValidationError(message: "This file is not an Even Circle backup (invalid JSON).")
        }
        guard let version = probe.schemaVersion else {
            throw BackupValidationError(message: "This file is not an Even Circle backup (no schema version).")
        }
        guard version == BackupDocument.currentSchemaVersion else {
            throw BackupValidationError(message: "Backup schema version \(version) is not supported. This app reads version 1.")
        }

        let document: BackupDocument
        do {
            document = try decoder.decode(BackupDocument.self, from: data)
        } catch let DecodingError.keyNotFound(key, context) {
            throw BackupValidationError(message: "The backup is missing “\(key.stringValue)” at \(Self.path(context.codingPath)).")
        } catch let DecodingError.typeMismatch(_, context) {
            throw BackupValidationError(message: "The backup has a value of the wrong type at \(Self.path(context.codingPath)).")
        } catch let DecodingError.valueNotFound(_, context) {
            throw BackupValidationError(message: "The backup has an empty value at \(Self.path(context.codingPath)).")
        } catch {
            throw BackupValidationError(message: "The backup structure is invalid.")
        }

        var validator = Validator()
        let aggregates = try document.events.map { try validator.validate($0) }
        let counts = DataCounts(
            events: aggregates.count,
            people: aggregates.reduce(0) { $0 + $1.people.count },
            expenses: aggregates.reduce(0) { $0 + $1.expenses.count },
            payments: aggregates.reduce(0) { $0 + $1.payments.count }
        )
        let preview = BackupPreview(
            schemaVersion: version,
            exportedAt: Self.parseTimestamp(document.exportedAt),
            counts: counts,
            events: aggregates.map { .init(id: $0.event.id, name: $0.event.name, currency: $0.event.currency, isDemo: $0.event.isDemo) }
        )
        return ValidatedBackup(preview: preview, aggregates: aggregates)
    }

    private static func path(_ codingPath: [CodingKey]) -> String {
        let text = codingPath.map { $0.intValue.map { "[\($0)]" } ?? ".\($0.stringValue)" }.joined()
        return text.isEmpty ? "the top level" : String(text.drop(while: { $0 == "." }))
    }

    // MARK: - Validator

    private struct Validator {
        var seenIDs: Set<UUID> = []
        var seenOperationIDs: Set<UUID> = []

        private func fail(_ message: String) -> BackupValidationError {
            BackupValidationError(message: message)
        }

        private mutating func claim(_ id: UUID, _ what: String) throws {
            guard seenIDs.insert(id).inserted else {
                throw fail("The backup contains a duplicate ID (\(what)).")
            }
        }

        private func timestamp(_ text: String, _ what: String) throws -> Date {
            guard let date = JSONBackupCodec.parseTimestamp(text) else { throw fail("Invalid timestamp for \(what).") }
            return date
        }

        private func day(_ text: String, _ what: String) throws -> CalendarDate {
            guard let date = CalendarDate(isoString: text) else { throw fail("Invalid date for \(what). Use YYYY-MM-DD.") }
            return date
        }

        mutating func validate(_ dto: BackupDocument.EventDTO) throws -> EventAggregate {
            try claim(dto.id, "event")
            let label = "event “\(dto.name.prefix(40))”"
            if let error = TextRules.validateRequired(dto.name, field: "Event name", range: DomainLimits.eventNameLength) {
                throw fail("Invalid \(label): \(error.message)")
            }
            guard let currency = CurrencyCode(rawValue: dto.currencyCode) else {
                throw fail("Unsupported currency “\(dto.currencyCode.prefix(8))” in \(label).")
            }
            guard dto.currencyScale == currency.scale else { throw fail("Wrong currency scale in \(label).") }
            if TextRules.validateNote(dto.note, maxLength: DomainLimits.eventNoteMaxLength) != nil {
                throw fail("The note in \(label) is too long.")
            }
            guard dto.revision >= 0 else { throw fail("Invalid revision in \(label).") }
            guard dto.people.count <= DomainLimits.maxPeoplePerEvent else { throw fail("Too many people in \(label).") }
            guard dto.expenses.count <= DomainLimits.maxExpensesPerEvent else { throw fail("Too many expenses in \(label).") }
            guard dto.payments.count <= DomainLimits.maxPaymentsPerEvent else { throw fail("Too many payments in \(label).") }

            let event = Event(
                id: dto.id,
                name: TextRules.clean(dto.name),
                eventDate: try day(dto.eventDate, label),
                currency: currency,
                currencyLocked: dto.currencyLocked,
                note: TextRules.cleanNote(dto.note),
                isArchived: dto.isArchived,
                isDemo: dto.isDemo,
                revision: dto.revision,
                createdAt: try timestamp(dto.createdAt, label),
                updatedAt: try timestamp(dto.updatedAt, label)
            )

            var people: [Person] = []
            var nameKeys: Set<String> = []
            for person in dto.people {
                try claim(person.id, "person")
                if let error = TextRules.validateRequired(person.name, field: "Name", range: DomainLimits.personNameLength) {
                    throw fail("Invalid person in \(label): \(error.message)")
                }
                guard nameKeys.insert(TextRules.nameKey(person.name)).inserted else {
                    throw fail("Two people in \(label) have the same name.")
                }
                guard let color = AvatarColorKey(rawValue: person.avatarColorKey) else {
                    throw fail("Unknown avatar colour in \(label).")
                }
                people.append(Person(
                    id: person.id, eventID: dto.id, name: TextRules.clean(person.name), avatarColor: color,
                    createdAt: try timestamp(person.createdAt, "a person in \(label)"),
                    updatedAt: try timestamp(person.updatedAt, "a person in \(label)")
                ))
            }
            let peopleIDs = Set(people.map(\.id))

            var expenses: [Expense] = []
            for expense in dto.expenses {
                expenses.append(try validate(expense, eventID: dto.id, peopleIDs: peopleIDs, label: label))
            }
            if !expenses.isEmpty && !dto.currencyLocked {
                throw fail("The currency lock in \(label) doesn't match its expenses.")
            }

            var payments: [Payment] = []
            for payment in dto.payments {
                try claim(payment.id, "payment")
                guard seenOperationIDs.insert(payment.operationID).inserted else {
                    throw fail("Two payments in the backup share an operation ID.")
                }
                guard payment.amountMinor > 0, payment.amountMinor <= DomainLimits.maxPaymentMinor else {
                    throw fail("A payment in \(label) has an invalid amount.")
                }
                guard payment.fromID != payment.toID else { throw fail("A payment in \(label) has the same sender and recipient.") }
                guard peopleIDs.contains(payment.fromID), peopleIDs.contains(payment.toID) else {
                    throw fail("A payment in \(label) refers to someone who is not in the event.")
                }
                if TextRules.validateNote(payment.note, maxLength: DomainLimits.paymentNoteMaxLength) != nil {
                    throw fail("A payment note in \(label) is too long.")
                }
                payments.append(Payment(
                    id: payment.id, eventID: dto.id, fromID: payment.fromID, toID: payment.toID,
                    amountMinor: payment.amountMinor, paymentDate: try day(payment.paymentDate, "a payment in \(label)"),
                    note: TextRules.cleanNote(payment.note), operationID: payment.operationID,
                    createdAt: try timestamp(payment.createdAt, "a payment in \(label)")
                ))
            }

            let aggregate = EventAggregate(event: event, people: people, expenses: expenses, payments: payments)
            // Current balances are recomputed, never imported; they must add up to zero.
            do {
                _ = try BalanceCalculator.calculate(aggregate)
            } catch {
                throw fail("Balances in \(label) don't add up.")
            }
            return aggregate
        }

        private mutating func validate(
            _ dto: BackupDocument.ExpenseDTO,
            eventID: UUID,
            peopleIDs: Set<UUID>,
            label: String
        ) throws -> Expense {
            try claim(dto.id, "expense")
            let what = "expense “\(dto.title.prefix(40))” in \(label)"
            if let error = TextRules.validateRequired(dto.title, field: "Title", range: DomainLimits.expenseTitleLength) {
                throw fail("Invalid \(what): \(error.message)")
            }
            guard dto.amountMinor > 0, dto.amountMinor <= DomainLimits.maxExpenseMinor else {
                throw fail("The amount of \(what) is outside the allowed range.")
            }
            guard peopleIDs.contains(dto.payerID) else { throw fail("The payer of \(what) is not in the event.") }
            guard let method = SplitMethod(rawValue: dto.method) else { throw fail("Unknown split method in \(what).") }
            if TextRules.validateNote(dto.note, maxLength: DomainLimits.expenseNoteMaxLength) != nil {
                throw fail("The note of \(what) is too long.")
            }
            guard dto.revision >= 0 else { throw fail("Invalid revision in \(what).") }
            guard !dto.shares.isEmpty else { throw fail("\(what.prefix(1).uppercased() + what.dropFirst()) has no shares.") }

            let shareIDs = dto.shares.map(\.personID)
            guard Set(shareIDs).count == shareIDs.count else { throw fail("Duplicate shares in \(what).") }
            guard shareIDs.allSatisfy(peopleIDs.contains) else { throw fail("A share in \(what) refers to someone not in the event.") }
            guard dto.shares.allSatisfy({ $0.allocatedMinor >= 0 }) else { throw fail("Negative share in \(what).") }

            guard let total = try? CheckedMath.sum(dto.shares.map(\.allocatedMinor)), total == dto.amountMinor else {
                throw fail("The shares of \(what) don't add up to its amount.")
            }

            var items: [ReceiptItem] = []
            let mismatch = fail("The allocations of \(what) don't match the \(method.title) split rules.")

            switch method {
            case .equal, .shares:
                guard dto.items.isEmpty else { throw fail("\(what.prefix(1).uppercased() + what.dropFirst()) has receipt items but isn't an Items split.") }
                var participants: [LargestRemainderAllocator.Participant] = []
                for share in dto.shares {
                    guard let weight = share.weight else { throw fail("A share in \(what) has no weight.") }
                    if method == .equal {
                        guard weight == 1 else { throw mismatch }
                    } else {
                        guard DomainLimits.weightRange.contains(weight) else { throw fail("A weight in \(what) is outside 1–1000.") }
                    }
                    participants.append(.init(share.personID, weight: weight))
                }
                guard let expected = try? LargestRemainderAllocator.allocate(amount: dto.amountMinor, participants: participants) else {
                    throw mismatch
                }
                guard dto.shares.allSatisfy({ expected[$0.personID] == $0.allocatedMinor }) else { throw mismatch }

            case .items:
                guard !dto.items.isEmpty, dto.items.count <= DomainLimits.maxItemsPerExpense else {
                    throw fail("\(what.prefix(1).uppercased() + what.dropFirst()) must have 1–\(DomainLimits.maxItemsPerExpense) receipt items.")
                }
                guard dto.shares.allSatisfy({ $0.weight == nil }) else { throw mismatch }
                var lines: [ReceiptCalculator.Line] = []
                for item in dto.items {
                    try claim(item.id, "receipt item")
                    if let error = TextRules.validateRequired(item.title, field: "Item name", range: DomainLimits.itemTitleLength) {
                        throw fail("Invalid item in \(what): \(error.message)")
                    }
                    let recipients = item.shares.map(\.personID)
                    guard !recipients.isEmpty else { throw fail("An item in \(what) has no recipients.") }
                    guard Set(recipients).count == recipients.count else { throw fail("Duplicate recipients in \(what).") }
                    guard recipients.allSatisfy(peopleIDs.contains) else { throw fail("An item in \(what) refers to someone not in the event.") }
                    lines.append(.init(id: item.id, quantity: item.quantity, unitPriceMinor: item.unitPriceMinor, recipientIDs: recipients))
                }
                let result: ReceiptCalculator.Result
                do {
                    result = try ReceiptCalculator.calculate(lines: lines)
                } catch {
                    throw fail("The receipt items of \(what) are invalid or exceed the limits.")
                }
                guard result.totalMinor == dto.amountMinor else { throw fail("The receipt items of \(what) don't add up to its amount.") }
                for (index, item) in dto.items.enumerated() {
                    let line = result.lines[index]
                    guard item.shares.allSatisfy({ line.allocations[$0.personID] == $0.allocatedMinor }) else { throw mismatch }
                }
                guard Set(shareIDs) == Set(result.totals.keys),
                      dto.shares.allSatisfy({ result.totals[$0.personID] == $0.allocatedMinor })
                else { throw mismatch }
                items = dto.items.map { item in
                    ReceiptItem(
                        id: item.id, title: TextRules.clean(item.title), quantity: item.quantity,
                        unitPriceMinor: item.unitPriceMinor, sortOrder: item.sortOrder,
                        shares: item.shares.map { ReceiptItemShare(personID: $0.personID, allocatedMinor: $0.allocatedMinor) }
                    )
                }
            }

            return Expense(
                id: dto.id,
                eventID: eventID,
                title: TextRules.clean(dto.title),
                amountMinor: dto.amountMinor,
                payerID: dto.payerID,
                expenseDate: try day(dto.expenseDate, what),
                method: method,
                note: TextRules.cleanNote(dto.note),
                createdAt: try timestamp(dto.createdAt, what),
                updatedAt: try timestamp(dto.updatedAt, what),
                revision: dto.revision,
                shares: dto.shares
                    .map { ExpenseShare(personID: $0.personID, allocatedMinor: $0.allocatedMinor, weight: $0.weight) }
                    .sorted { $0.personID.lowercasedString < $1.personID.lowercasedString },
                items: items
            )
        }
    }
}
