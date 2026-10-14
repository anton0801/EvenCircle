import Foundation

enum MoneyInputError: Error, Equatable {
    case empty
    /// A separator with no digits after it, e.g. "12." – the user is still typing.
    case incomplete
    case invalidCharacters
    case multipleSeparators
    case missingLeadingDigit
    case tooManyDecimals(maxDigits: Int)
    case wholeAmountsOnly(CurrencyCode)
    case tooLarge

    var message: String {
        switch self {
        case .empty:
            return "Enter an amount."
        case .incomplete:
            return "Add digits after the decimal separator."
        case .invalidCharacters:
            return "Use digits and one decimal separator only."
        case .multipleSeparators:
            return "Use only one decimal separator, without thousands separators."
        case .missingLeadingDigit:
            return "Add a digit before the decimal separator."
        case .tooManyDecimals(let digits):
            return digits == 1 ? "Use up to 1 decimal place." : "Use up to \(digits) decimal places."
        case .wholeAmountsOnly(let currency):
            return "\(currency.code) uses whole amounts."
        case .tooLarge:
            return "This amount is too large."
        }
    }
}

enum MoneyRangeError: Error, Equatable {
    case notPositive
    case aboveLimit(limit: Int64, currency: CurrencyCode)

    var message: String {
        switch self {
        case .notPositive:
            return "Enter an amount greater than 0."
        case .aboveLimit(let limit, let currency):
            return "The maximum is \(PlainMoneyText.string(limit, currency))."
        }
    }
}

/// Strict money input parser. Never rounds and never uses floating point.
///
/// Accepted: ASCII digits with at most one '.' or ',' separator, at least one digit before it
/// and 1…scale digits after it. Outer whitespace is trimmed; nothing else is tolerated.
enum MoneyParser {
    static func parse(_ raw: String, currency: CurrencyCode) -> Result<Int64, MoneyInputError> {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .failure(.empty) }

        var integerDigits: [UInt8] = []
        var fractionDigits: [UInt8] = []
        var separatorCount = 0

        for scalar in text.unicodeScalars {
            switch scalar {
            case "0"..."9":
                let digit = UInt8(scalar.value - 48)
                if separatorCount == 0 { integerDigits.append(digit) } else { fractionDigits.append(digit) }
            case ".", ",":
                separatorCount += 1
            default:
                return .failure(.invalidCharacters)
            }
        }

        if separatorCount > 1 { return .failure(.multipleSeparators) }
        if separatorCount == 1 {
            if currency.scale == 0 { return .failure(.wholeAmountsOnly(currency)) }
            if integerDigits.isEmpty { return .failure(.missingLeadingDigit) }
            if fractionDigits.isEmpty { return .failure(.incomplete) }
            if fractionDigits.count > currency.scale { return .failure(.tooManyDecimals(maxDigits: currency.scale)) }
        }
        guard !integerDigits.isEmpty else { return .failure(.invalidCharacters) }

        // Far above every limit, yet small enough that the remaining ×10 steps cannot overflow Int64.
        let ceiling: Int64 = 1_000_000_000_000
        var value: Int64 = 0
        for digit in integerDigits {
            value = value * 10 + Int64(digit)
            if value > ceiling { return .failure(.tooLarge) }
        }
        for index in 0..<currency.scale {
            let digit = index < fractionDigits.count ? Int64(fractionDigits[index]) : 0
            value = value * 10 + digit
        }
        return .success(value)
    }

    /// Parses and checks 1…limit in one step.
    static func parsePositive(_ raw: String, currency: CurrencyCode, limit: Int64) -> Result<Int64, FieldError> {
        switch parse(raw, currency: currency) {
        case .failure(let error):
            return .failure(FieldError(error.message))
        case .success(let minor):
            if let rangeError = checkRange(minor, currency: currency, limit: limit) {
                return .failure(FieldError(rangeError.message))
            }
            return .success(minor)
        }
    }

    static func checkRange(_ minor: Int64, currency: CurrencyCode, limit: Int64) -> MoneyRangeError? {
        if minor <= 0 { return .notPositive }
        if minor > limit { return .aboveLimit(limit: limit, currency: currency) }
        return nil
    }

    /// Editable text for a stored amount ("12.30", "1500"), always accepted back by `parse`.
    static func editableText(_ minor: Int64, currency: CurrencyCode, separator: Character = ".") -> String {
        let magnitude = minor.magnitude
        let divisor = UInt64(currency.minorUnitsPerMajor)
        let major = magnitude / divisor
        guard currency.scale > 0 else { return (minor < 0 ? "-" : "") + String(major) }
        let fraction = String(magnitude % divisor)
        let padded = String(repeating: "0", count: currency.scale - fraction.count) + fraction
        return (minor < 0 ? "-" : "") + String(major) + String(separator) + padded
    }
}
