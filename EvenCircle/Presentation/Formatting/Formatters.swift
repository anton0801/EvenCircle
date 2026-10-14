import Foundation

/// Display formatting only. Arithmetic never happens here; values are exact Int64 minor units
/// converted to `Decimal` (base 10, exact) just for the number formatter.
enum MoneyFormatter {
    private static func decimal(_ minor: Int64, _ currency: CurrencyCode) -> Decimal {
        Decimal(sign: minor < 0 ? .minus : .plus, exponent: -currency.scale, significand: Decimal(minor.magnitude))
    }

    private static func numberFormatter(_ currency: CurrencyCode, locale: Locale) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = currency.scale
        formatter.maximumFractionDigits = currency.scale
        return formatter
    }

    /// "1,234.56 EUR" – the currency code is always visible.
    static func string(_ minor: Int64, _ currency: CurrencyCode, locale: Locale = .current) -> String {
        number(minor, currency, locale: locale) + " " + currency.code
    }

    /// "1,234.56" without the code; use only next to a visible code.
    static func number(_ minor: Int64, _ currency: CurrencyCode, locale: Locale = .current) -> String {
        let value = decimal(minor, currency) as NSDecimalNumber
        return numberFormatter(currency, locale: locale).string(from: value) ?? PlainMoneyText.string(minor, currency)
    }

    /// "+44.00 EUR" / "−8.00 EUR" for before/after tables.
    static func signed(_ minor: Int64, _ currency: CurrencyCode) -> String {
        if minor > 0 { return "+" + string(minor, currency) }
        if minor < 0 { return "−" + string(-minor, currency) }
        return string(0, currency)
    }

    /// Spoken form, e.g. "44.00 euros".
    static func spoken(_ minor: Int64, _ currency: CurrencyCode) -> String {
        let formatter = NumberFormatter()
        // `.currencyPlural` takes the currency from the locale, not from `currencyCode`.
        formatter.locale = Locale(identifier: "en_US@currency=\(currency.code)")
        formatter.numberStyle = .currencyPlural
        formatter.minimumFractionDigits = currency.scale
        formatter.maximumFractionDigits = currency.scale
        return formatter.string(from: decimal(minor, currency) as NSDecimalNumber) ?? string(minor, currency)
    }

    /// Decimal separator offered for prefilled editable amounts; the parser accepts '.' and ','.
    static var inputSeparator: Character {
        Locale.current.decimalSeparator == "," ? "," : "."
    }

    static func editable(_ minor: Int64, _ currency: CurrencyCode) -> String {
        MoneyParser.editableText(minor, currency: currency, separator: inputSeparator)
    }
}

enum DateText {
    private static let mediumFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    /// A calendar day shown in the local style, without any time-zone shift.
    static func medium(_ date: CalendarDate) -> String {
        mediumFormatter.string(from: date.date())
    }

    static func timestamp(_ date: Date) -> String {
        timestampFormatter.string(from: date)
    }
}

extension BalanceDirection {
    var shortText: String {
        switch self {
        case .toReceive: return "To receive"
        case .toPay: return "To pay"
        case .settled: return "Settled"
        }
    }

    func text(_ currency: CurrencyCode) -> String {
        switch self {
        case .toReceive(let amount): return "To receive \(MoneyFormatter.string(amount, currency))"
        case .toPay(let amount): return "To pay \(MoneyFormatter.string(amount, currency))"
        case .settled: return "Settled"
        }
    }

    func spoken(_ currency: CurrencyCode) -> String {
        switch self {
        case .toReceive(let amount): return "To receive \(MoneyFormatter.spoken(amount, currency))"
        case .toPay(let amount): return "To pay \(MoneyFormatter.spoken(amount, currency))"
        case .settled: return "Settled"
        }
    }
}

extension Int {
    func counted(_ singular: String, _ plural: String? = nil) -> String {
        "\(self) " + (self == 1 ? singular : (plural ?? singular + "s"))
    }
}
