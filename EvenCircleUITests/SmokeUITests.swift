import XCTest

/// End-to-end smoke paths on a clean in-memory install (launch argument -ec-uitest).
final class SmokeUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ec-uitest"]
        app.launch()
    }

    // MARK: - Helpers

    @discardableResult
    private func wait(_ element: XCUIElement, timeout: TimeInterval = 8, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "Missing \(element)", file: file, line: line)
        return element
    }

    private func tap(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        wait(element, file: file, line: line).tap()
    }

    private func type(_ text: String, into field: XCUIElement) {
        tap(field)
        field.typeText(text)
    }

    private func skipOnboarding() {
        tap(app.buttons["onboardingNext"])
        wait(app.staticTexts["Split it the way it happened"])
        tap(app.buttons["onboardingNext"])
        wait(app.staticTexts["Even Circle does not move money."])
        let getStarted = wait(app.buttons["onboardingGetStarted"])
        // The button replaces "Next" in place; retry once if the first tap hit the outgoing view.
        for _ in 0..<2 where getStarted.exists {
            getStarted.tap()
            _ = app.staticTexts["Even Circle"].waitForExistence(timeout: 3)
        }
        wait(app.staticTexts["Even Circle"])
    }

    /// Number pads have no return key; the app adds a "Done" button above the keyboard.
    private func dismissKeyboard() {
        guard app.keyboards.count > 0 else { return }
        let done = app.toolbars.buttons["Done"].firstMatch
        if done.waitForExistence(timeout: 2) { done.tap() }
    }

    private func createEvent(_ name: String) {
        if app.buttons["newEventButton"].waitForExistence(timeout: 2) {
            app.buttons["newEventButton"].tap()
        } else {
            tap(app.buttons["New Event"])
        }
        type(name, into: app.textFields["eventNameField"])
        tap(app.buttons["saveEventButton"])
        wait(app.staticTexts["eventTitle"])
    }

    private func addPerson(_ name: String) {
        if app.buttons["addPersonButton"].exists {
            app.buttons["addPersonButton"].tap()
        } else {
            tap(app.buttons["Add Person"])
        }
        type(name, into: app.textFields["personNameField"])
        tap(app.buttons["savePersonButton"])
        wait(app.staticTexts[name])
    }

    private func choosePayer(_ name: String) {
        tap(app.buttons["paidByPicker"])
        tap(app.buttons[name].firstMatch)
    }

    // MARK: - Tests

    func testCleanInstallShowsOnboardingAndEmptyEventsWithoutDemo() {
        wait(app.staticTexts["Good plans. Clear expenses."])
        skipOnboarding()
        wait(app.staticTexts["Start with a shared plan"])
        XCTAssertFalse(app.staticTexts["Sample Weekend"].exists)
    }

    /// Event → People → Equal Expense → Balances → Partial Payment → History → Share.
    func testEqualExpensePartialPaymentHistoryAndShare() {
        skipOnboarding()
        createEvent("Lisbon")
        addPerson("Alex")
        addPerson("Bea")
        tap(app.buttons["continueToExpensesButton"])

        tap(app.buttons["Add Expense"].firstMatch)
        type("Dinner", into: app.textFields["expenseTitleField"])
        type("90", into: app.textFields["expenseAmountField"])
        dismissKeyboard()
        choosePayer("Alex")
        tap(app.buttons["expenseNextButton"])
        tap(app.buttons["previewExpenseButton"])
        tap(app.buttons["saveExpenseButton"])

        wait(app.staticTexts["expenseDetailTitle"])
        tap(app.buttons["viewBalancesButton"])

        let bea = wait(app.buttons["balanceRow_Bea"])
        XCTAssertTrue(bea.label.contains("To pay"), bea.label)
        tap(app.buttons["recordSuggestion_Bea_Alex"])

        let amount = wait(app.textFields["paymentAmountField"])
        XCTAssertTrue((amount.value as? String)?.contains("45") == true)
        XCTAssertFalse(app.buttons["recordPaymentButton"].isEnabled, "Checkbox is required")
        amount.tap()
        amount.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 8))
        amount.typeText("20")
        dismissKeyboard()
        tap(app.switches["paymentConfirmCheckbox"])
        tap(app.buttons["recordPaymentButton"])

        let updated = wait(app.buttons["balanceRow_Bea"])
        let predicate = NSPredicate(format: "label CONTAINS '25'")
        expectation(for: predicate, evaluatedWith: updated)
        waitForExpectations(timeout: 5)

        tap(app.buttons["paymentHistoryButton"])
        wait(app.buttons["paymentRow_Bea_Alex"])
        app.navigationBars.buttons.element(boundBy: 0).tap()

        tap(app.buttons["shareSummaryButton"])
        let preview = wait(app.staticTexts["summaryPreviewText"])
        XCTAssertTrue(preview.label.contains("EUR"))
        XCTAssertTrue(preview.label.contains("Payment suggestions are not transfer confirmations."))
        tap(app.buttons["closeSummaryButton"])
    }

    func testItemsExpenseAndCancelWithConfirmation() {
        skipOnboarding()
        createEvent("Market")
        addPerson("Alex")
        addPerson("Bea")
        tap(app.buttons["continueToExpensesButton"])

        tap(app.buttons["Add Expense"].firstMatch)
        type("Groceries", into: app.textFields["expenseTitleField"])
        tap(app.buttons["Items"])
        choosePayer("Bea")
        tap(app.buttons["expenseNextButton"])

        tap(app.buttons["addItemButton"])
        type("Bread", into: app.textFields["itemNameField"])
        let quantity = app.textFields["itemQuantityField"]
        tap(quantity)
        quantity.typeText(XCUIKeyboardKey.delete.rawValue + "2")
        type("1.50", into: app.textFields["itemPriceField"])
        dismissKeyboard()
        tap(app.switches["itemRecipient_Alex"])
        tap(app.switches["itemRecipient_Bea"])
        tap(app.buttons["saveItemButton"])

        tap(app.buttons["previewExpenseButton"])
        tap(app.buttons["saveExpenseButton"])
        wait(app.staticTexts["expenseDetailTitle"])
        app.navigationBars.buttons.element(boundBy: 0).tap()

        // Cancel with changes asks before discarding.
        tap(app.buttons["addExpenseButton"])
        type("Coffee", into: app.textFields["expenseTitleField"])
        tap(app.buttons["cancelExpenseButton"])
        tap(app.buttons["Discard Changes"])
        wait(app.buttons["expenseRow_Groceries"])
        XCTAssertFalse(app.buttons["expenseRow_Coffee"].exists)
    }
}
