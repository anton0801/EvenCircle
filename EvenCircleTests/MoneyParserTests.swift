import XCTest
@testable import EvenCircle

final class MoneyParserTests: XCTestCase {
    private func parse(_ text: String, _ currency: CurrencyCode = .eur) -> Result<Int64, MoneyInputError> {
        MoneyParser.parse(text, currency: currency)
    }

    func testValidEuroInputs() {
        XCTAssertEqual(try parse("12").get(), 1200)
        XCTAssertEqual(try parse("12.3").get(), 1230)
        XCTAssertEqual(try parse("12,30").get(), 1230)
        XCTAssertEqual(try parse("  12.30  ").get(), 1230)
        XCTAssertEqual(try parse("0.01").get(), 1)
        XCTAssertEqual(try parse("9999999.99").get(), 999_999_999)
    }

    func testThousandsLookalikeIsRejectedNotRounded() {
        XCTAssertEqual(parse("1,234"), .failure(.tooManyDecimals(maxDigits: 2)))
        XCTAssertEqual(parse("1.234"), .failure(.tooManyDecimals(maxDigits: 2)))
        XCTAssertEqual(MoneyInputError.tooManyDecimals(maxDigits: 2).message, "Use up to 2 decimal places.")
    }

    func testIncompleteAndMalformedInput() {
        XCTAssertEqual(parse("12."), .failure(.incomplete))
        XCTAssertEqual(parse(".5"), .failure(.missingLeadingDigit))
        XCTAssertEqual(parse(""), .failure(.empty))
        XCTAssertEqual(parse("   "), .failure(.empty))
        XCTAssertEqual(parse("1,234.56"), .failure(.multipleSeparators))
        XCTAssertEqual(parse("1.2.3"), .failure(.multipleSeparators))
    }

    func testRejectsSignsSymbolsExponentsAndInnerSpaces() {
        for text in ["-5", "+5", "1e3", "€5", "5 EUR", "1 000", "12a", "١٢"] {
            XCTAssertEqual(parse(text), .failure(.invalidCharacters), text)
        }
    }

    func testJPYUsesWholeAmounts() {
        XCTAssertEqual(try parse("1", .jpy).get(), 1)
        XCTAssertEqual(try parse("1500", .jpy).get(), 1500)
        XCTAssertEqual(parse("1.5", .jpy), .failure(.wholeAmountsOnly(.jpy)))
        XCTAssertEqual(parse("1,0", .jpy), .failure(.wholeAmountsOnly(.jpy)))
        XCTAssertEqual(MoneyInputError.wholeAmountsOnly(.jpy).message, "JPY uses whole amounts.")
    }

    func testHugeInputDoesNotOverflow() {
        XCTAssertEqual(parse("99999999999999999999999999"), .failure(.tooLarge))
    }

    func testRangeChecks() {
        XCTAssertEqual(MoneyParser.checkRange(0, currency: .eur, limit: 999_999_999), .notPositive)
        XCTAssertEqual(MoneyParser.checkRange(1_000_000_000, currency: .eur, limit: 999_999_999), .aboveLimit(limit: 999_999_999, currency: .eur))
        XCTAssertNil(MoneyParser.checkRange(1, currency: .eur, limit: 999_999_999))
        XCTAssertThrowsError(try MoneyParser.parsePositive("0", currency: .eur, limit: 100).get())
    }

    func testEditableTextRoundTrips() {
        for value: Int64 in [1, 10, 1230, 999_999_999] {
            let text = MoneyParser.editableText(value, currency: .eur)
            XCTAssertEqual(try parse(text).get(), value)
            let comma = MoneyParser.editableText(value, currency: .eur, separator: ",")
            XCTAssertEqual(try parse(comma).get(), value)
        }
        XCTAssertEqual(MoneyParser.editableText(1500, currency: .jpy), "1500")
    }

    func testPlainMoneyText() {
        XCTAssertEqual(PlainMoneyText.string(999_999_999, .eur), "9,999,999.99 EUR")
        XCTAssertEqual(PlainMoneyText.string(-805, .usd), "-8.05 USD")
        XCTAssertEqual(PlainMoneyText.string(1500, .jpy), "1,500 JPY")
    }
}

final class MoneyFormatterTests: XCTestCase {
    func testVisibleAmountsAlwaysCarryTheCode() {
        let en = Locale(identifier: "en_US")
        XCTAssertEqual(MoneyFormatter.string(123_456, .eur, locale: en), "1,234.56 EUR")
        XCTAssertEqual(MoneyFormatter.string(1500, .jpy, locale: en), "1,500 JPY")
        XCTAssertEqual(MoneyFormatter.string(-805, .gbp, locale: en), "-8.05 GBP")
    }

    func testSpokenAmountsUseTheEventCurrency() {
        XCTAssertEqual(MoneyFormatter.spoken(4400, .eur), "44.00 euros")
        XCTAssertEqual(MoneyFormatter.spoken(250, .gbp), "2.50 British pounds")
        XCTAssertEqual(MoneyFormatter.spoken(1500, .jpy), "1,500 Japanese yen")
        XCTAssertEqual(MoneyFormatter.spoken(999, .usd), "9.99 US dollars")
    }
}
