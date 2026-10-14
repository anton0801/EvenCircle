import XCTest
@testable import EvenCircle

final class AllocationTests: XCTestCase {
    private let a = TestIDs.a, b = TestIDs.b, c = TestIDs.c

    func testEqualTenEurosOnThree() throws {
        let result = try LargestRemainderAllocator.equal(amount: 1000, personIDs: [a, b, c])
        XCTAssertEqual(result[a], 334)
        XCTAssertEqual(result[b], 333)
        XCTAssertEqual(result[c], 333)
        XCTAssertEqual(result.values.reduce(0, +), 1000)
    }

    func testOrderOfParticipantsDoesNotMatter() throws {
        let permutations = [[a, b, c], [c, b, a], [b, a, c], [c, a, b]]
        let results = try permutations.map { try LargestRemainderAllocator.equal(amount: 1000, personIDs: $0) }
        XCTAssertTrue(results.allSatisfy { $0 == results[0] })
    }

    func testWeightsOneTwoThree() throws {
        let result = try LargestRemainderAllocator.allocate(amount: 1000, participants: [.init(a, weight: 1), .init(b, weight: 2), .init(c, weight: 3)])
        XCTAssertEqual(result[a], 167)
        XCTAssertEqual(result[b], 333)
        XCTAssertEqual(result[c], 500)
    }

    func testOneYenOnThree() throws {
        let result = try LargestRemainderAllocator.equal(amount: 1, personIDs: [c, b, a])
        XCTAssertEqual(result[a], 1)
        XCTAssertEqual(result[b], 0)
        XCTAssertEqual(result[c], 0)
        XCTAssertEqual(result.count, 3, "People with a zero share stay in the result")
    }

    func testInvalidWeightsAndInputs() {
        XCTAssertThrowsError(try LargestRemainderAllocator.allocate(amount: 100, participants: [.init(a, weight: 0)]))
        XCTAssertThrowsError(try LargestRemainderAllocator.allocate(amount: 100, participants: [.init(a, weight: -1)]))
        XCTAssertThrowsError(try LargestRemainderAllocator.allocate(amount: 100, participants: []))
        XCTAssertThrowsError(try LargestRemainderAllocator.allocate(amount: -1, participants: [.init(a)]))
        XCTAssertThrowsError(try LargestRemainderAllocator.allocate(amount: 100, participants: [.init(a), .init(a)]))
    }

    func testOverflowIsReportedNotTrapped() {
        XCTAssertThrowsError(try LargestRemainderAllocator.allocate(amount: .max, participants: [.init(a, weight: 2), .init(b)])) { error in
            XCTAssertEqual(error as? AllocationError, .overflow)
        }
    }

    func testRandomizedSumsAreExact() throws {
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<500 {
            let count = Int.random(in: 1...50, using: &generator)
            let participants = (0..<count).map { _ in
                LargestRemainderAllocator.Participant(UUID(), weight: Int.random(in: 1...1000, using: &generator))
            }
            let amount = Int64.random(in: 0...DomainLimits.maxExpenseMinor, using: &generator)
            let result = try LargestRemainderAllocator.allocate(amount: amount, participants: participants)
            XCTAssertEqual(result.values.reduce(0, +), amount)
            XCTAssertTrue(result.values.allSatisfy { $0 >= 0 })
            XCTAssertEqual(try LargestRemainderAllocator.allocate(amount: amount, participants: participants.reversed()), result)
        }
    }

    // MARK: - Receipt items

    func testItemsExampleFromSpec() throws {
        let result = try ReceiptCalculator.calculate(lines: [
            .init(id: UUID(), quantity: 1, unitPriceMinor: 1000, recipientIDs: [a, b, c]),
            .init(id: UUID(), quantity: 1, unitPriceMinor: 500, recipientIDs: [b, c]),
        ])
        XCTAssertEqual(result.totals[a], 334)
        XCTAssertEqual(result.totals[b], 583)
        XCTAssertEqual(result.totals[c], 583)
        XCTAssertEqual(result.totalMinor, 1500)
    }

    func testLineWithoutRecipientsBlocks() {
        let line = UUID()
        XCTAssertThrowsError(try ReceiptCalculator.calculate(lines: [.init(id: line, quantity: 1, unitPriceMinor: 100, recipientIDs: [])])) {
            XCTAssertEqual($0 as? ReceiptCalculator.Failure, .lineWithoutRecipients(line))
        }
    }

    func testQuantityTimesPriceAndLimits() throws {
        let result = try ReceiptCalculator.calculate(lines: [.init(id: UUID(), quantity: 3, unitPriceMinor: 450, recipientIDs: [a])])
        XCTAssertEqual(result.totalMinor, 1350)
        XCTAssertThrowsError(try ReceiptCalculator.calculate(lines: [.init(id: UUID(), quantity: 999, unitPriceMinor: 999_999_999, recipientIDs: [a])]))
        XCTAssertThrowsError(try ReceiptCalculator.calculate(lines: [.init(id: UUID(), quantity: 0, unitPriceMinor: 1, recipientIDs: [a])]))
        let half = DomainLimits.maxExpenseMinor / 2 + 1
        XCTAssertThrowsError(try ReceiptCalculator.calculate(lines: [
            .init(id: UUID(), quantity: 1, unitPriceMinor: half, recipientIDs: [a]),
            .init(id: UUID(), quantity: 1, unitPriceMinor: half, recipientIDs: [a]),
        ])) { XCTAssertEqual($0 as? ReceiptCalculator.Failure, .totalAboveLimit) }
    }
}
