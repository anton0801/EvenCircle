import Foundation

/// Per-line receipt allocation. Each line is split equally between its own recipients;
/// a person's expense share is the sum of their line allocations.
/// The receipt is never re-split as one total, which would change who pays for what.
enum ReceiptCalculator {
    struct Line: Equatable {
        let id: UUID
        let quantity: Int
        let unitPriceMinor: Int64
        let recipientIDs: [UUID]
    }

    struct LineResult: Equatable {
        let id: UUID
        let lineAmountMinor: Int64
        let allocations: [UUID: Int64]
    }

    struct Result: Equatable {
        let lines: [LineResult]
        let totals: [UUID: Int64]
        let totalMinor: Int64
    }

    enum Failure: Error, Equatable {
        case noLines
        case lineWithoutRecipients(UUID)
        case invalidQuantity(UUID)
        case invalidUnitPrice(UUID)
        case lineAboveLimit(UUID)
        case totalAboveLimit
        case overflow
    }

    static func lineAmount(quantity: Int, unitPriceMinor: Int64) throws -> Int64 {
        do {
            return try CheckedMath.multiply(Int64(quantity), unitPriceMinor)
        } catch {
            throw Failure.overflow
        }
    }

    static func calculate(lines: [Line], limit: Int64 = DomainLimits.maxExpenseMinor) throws -> Result {
        guard !lines.isEmpty else { throw Failure.noLines }
        var results: [LineResult] = []
        var totals: [UUID: Int64] = [:]
        var total: Int64 = 0

        for line in lines {
            guard DomainLimits.quantityRange.contains(line.quantity) else { throw Failure.invalidQuantity(line.id) }
            guard line.unitPriceMinor > 0, line.unitPriceMinor <= DomainLimits.maxUnitPriceMinor else {
                throw Failure.invalidUnitPrice(line.id)
            }
            guard !line.recipientIDs.isEmpty else { throw Failure.lineWithoutRecipients(line.id) }
            let amount = try lineAmount(quantity: line.quantity, unitPriceMinor: line.unitPriceMinor)
            guard amount <= limit else { throw Failure.lineAboveLimit(line.id) }

            let allocations: [UUID: Int64]
            do {
                allocations = try LargestRemainderAllocator.equal(amount: amount, personIDs: line.recipientIDs)
            } catch {
                throw Failure.overflow
            }
            do {
                total = try CheckedMath.add(total, amount)
                for (personID, value) in allocations {
                    totals[personID] = try CheckedMath.add(totals[personID] ?? 0, value)
                }
            } catch {
                throw Failure.overflow
            }
            guard total <= limit else { throw Failure.totalAboveLimit }
            results.append(LineResult(id: line.id, lineAmountMinor: amount, allocations: allocations))
        }
        return Result(lines: results, totals: totals, totalMinor: total)
    }
}
