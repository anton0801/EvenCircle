import Foundation

/// Supported event currencies. One event uses exactly one currency; there is no conversion.
enum CurrencyCode: String, CaseIterable, Codable, Identifiable, Sendable {
    case usd = "USD"
    case eur = "EUR"
    case gbp = "GBP"
    case jpy = "JPY"

    var id: String { rawValue }
    var code: String { rawValue }

    /// Number of decimal digits in the minor unit.
    var scale: Int {
        switch self {
        case .jpy: return 0
        case .usd, .eur, .gbp: return 2
        }
    }

    /// Minor units in one major unit (100 for cents, 1 for yen).
    var minorUnitsPerMajor: Int64 {
        switch self {
        case .jpy: return 1
        case .usd, .eur, .gbp: return 100
        }
    }

    var displayName: String {
        switch self {
        case .usd: return "US Dollar"
        case .eur: return "Euro"
        case .gbp: return "British Pound"
        case .jpy: return "Japanese Yen"
        }
    }
}
