import Foundation

enum AllocationError: Error, Equatable {
    case negativeAmount
    case noParticipants
    case duplicateParticipant
    case invalidWeight
    case overflow
}

/// Splits an integer amount of minor units between weighted participants (largest remainder method).
///
/// base_i = (A × w_i) div W, remainder_i = (A × w_i) mod W, R = A − Σ base_i.
/// The R participants with the largest remainders get +1 minor unit; ties go to the
/// lexicographically smaller lowercase UUID. The result always sums to exactly A and
/// never depends on display order, names or colours.
enum LargestRemainderAllocator {
    struct Participant: Equatable {
        let personID: UUID
        let weight: Int

        init(_ personID: UUID, weight: Int = 1) {
            self.personID = personID
            self.weight = weight
        }
    }

    static func allocate(amount: Int64, participants: [Participant]) throws -> [UUID: Int64] {
        guard amount >= 0 else { throw AllocationError.negativeAmount }
        guard !participants.isEmpty else { throw AllocationError.noParticipants }
        guard Set(participants.map(\.personID)).count == participants.count else {
            throw AllocationError.duplicateParticipant
        }
        guard participants.allSatisfy({ $0.weight > 0 }) else { throw AllocationError.invalidWeight }

        do {
            let totalWeight = try CheckedMath.sum(participants.map { Int64($0.weight) })
            var allocations: [UUID: Int64] = [:]
            var remainders: [(id: UUID, key: String, remainder: Int64)] = []
            var baseSum: Int64 = 0

            for participant in participants {
                let product = try CheckedMath.multiply(amount, Int64(participant.weight))
                let base = product / totalWeight
                let remainder = product % totalWeight
                allocations[participant.personID] = base
                baseSum = try CheckedMath.add(baseSum, base)
                remainders.append((participant.personID, participant.personID.lowercasedString, remainder))
            }

            let leftover = try CheckedMath.subtract(amount, baseSum)
            remainders.sort { lhs, rhs in
                if lhs.remainder != rhs.remainder { return lhs.remainder > rhs.remainder }
                return lhs.key < rhs.key
            }
            for index in 0..<Int(leftover) {
                let id = remainders[index].id
                allocations[id, default: 0] += 1
            }
            return allocations
        } catch is ArithmeticError {
            throw AllocationError.overflow
        }
    }

    static func equal(amount: Int64, personIDs: [UUID]) throws -> [UUID: Int64] {
        try allocate(amount: amount, participants: personIDs.map { Participant($0) })
    }
}
