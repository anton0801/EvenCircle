import Foundation

/// Hard limits from the specification. All money is in Int64 minor units.
enum DomainLimits {
    static let maxExpenseMinor: Int64 = 999_999_999
    static let maxPaymentMinor: Int64 = 999_999_999
    static let maxUnitPriceMinor: Int64 = 999_999_999

    static let maxExpensesPerEvent = 10_000
    static let maxPaymentsPerEvent = 10_000
    static let maxItemsPerExpense = 200
    static let maxPeoplePerEvent = 50

    static let weightRange = 1...1000
    static let quantityRange = 1...999

    static let eventNameLength = 1...80
    static let personNameLength = 1...40
    static let expenseTitleLength = 1...100
    static let itemTitleLength = 1...100
    static let eventNoteMaxLength = 1000
    static let expenseNoteMaxLength = 1000
    static let paymentNoteMaxLength = 500

    static let backupMaxBytes = 50 * 1024 * 1024
}

enum ArithmeticError: Error, Equatable {
    case overflow
}

/// Overflow-checked Int64 arithmetic. Every money sum and product goes through here.
enum CheckedMath {
    static func add(_ a: Int64, _ b: Int64) throws -> Int64 {
        let (result, overflow) = a.addingReportingOverflow(b)
        if overflow { throw ArithmeticError.overflow }
        return result
    }

    static func subtract(_ a: Int64, _ b: Int64) throws -> Int64 {
        let (result, overflow) = a.subtractingReportingOverflow(b)
        if overflow { throw ArithmeticError.overflow }
        return result
    }

    static func multiply(_ a: Int64, _ b: Int64) throws -> Int64 {
        let (result, overflow) = a.multipliedReportingOverflow(by: b)
        if overflow { throw ArithmeticError.overflow }
        return result
    }

    static func sum<S: Sequence>(_ values: S) throws -> Int64 where S.Element == Int64 {
        try values.reduce(0) { try add($0, $1) }
    }
}

/// Plain, locale-independent money text for domain-level messages ("9,999,999.99 EUR").
/// Screen formatting lives in the presentation layer.
enum PlainMoneyText {
    static func string(_ minor: Int64, _ currency: CurrencyCode) -> String {
        let negative = minor < 0
        let magnitude = minor.magnitude
        let divisor = UInt64(currency.minorUnitsPerMajor)
        let major = magnitude / divisor
        let fraction = magnitude % divisor
        var majorText = String(major)
        var grouped = ""
        while majorText.count > 3 {
            grouped = "," + majorText.suffix(3) + grouped
            majorText = String(majorText.dropLast(3))
        }
        grouped = majorText + grouped
        var text = (negative ? "-" : "") + grouped
        if currency.scale > 0 {
            let fractionText = String(fraction)
            text += "." + String(repeating: "0", count: currency.scale - fractionText.count) + fractionText
        }
        return text + " " + currency.code
    }
}
