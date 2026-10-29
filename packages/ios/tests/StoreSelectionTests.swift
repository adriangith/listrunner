import XCTest

final class StoreSelectionTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["LISTRUNNER_UI_TEST_SESSION"] = UUID().uuidString
        if name.contains("Paprika") {
            app.launchEnvironment["LISTRUNNER_PAPRIKA_TEST_FIXTURE"] = "enabled"
        }
        if name.contains("Verification") {
            app.launchEnvironment["LISTRUNNER_VERIFICATION_TEST_FIXTURE"] = "enabled"
        }
        app.launch()
        XCTAssertTrue(app.buttons["store-picker"].waitForExistence(timeout: 10))
    }

    override func tearDownWithError() throws { app.terminate() }

    private func choose(_ name: String) {
        app.buttons["store-picker"].tap()
        let option = app.buttons[name].firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 3))
        option.tap()
    }

    private func row(_ name: String, status: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", name, status)).firstMatch
    }

    func testStorePickerKeepsListsAndStatusesSeparate() {
        XCTAssertTrue(row("Coles fixture item", status: "Pending").exists)
        app.buttons["Actions for Coles fixture item"].tap()
        app.buttons["Mark Skipped"].tap()
        XCTAssertTrue(row("Coles fixture item", status: "Skipped").exists)
        choose("Woolworths")
        XCTAssertTrue(row("Woolworths fixture item", status: "Pending").waitForExistence(timeout: 3))
        XCTAssertFalse(row("Coles fixture item", status: "Skipped").exists)
        choose("Coles")
        XCTAssertTrue(row("Coles fixture item", status: "Skipped").waitForExistence(timeout: 3))
    }

    func testExplicitMoveTransfersOnlySelectedRow() {
        app.buttons["Actions for Coles fixture item"].tap()
        app.buttons["Move to Another Store"].tap()
        app.buttons["Move to Woolworths"].tap()
        XCTAssertTrue(app.staticTexts["Your list is empty"].waitForExistence(timeout: 3))
        choose("Woolworths")
        XCTAssertTrue(row("Coles fixture item", status: "Pending").waitForExistence(timeout: 3))
        XCTAssertTrue(row("Woolworths fixture item", status: "Pending").exists)
    }

    func testSettingsExposeStoreSpecificResetConfirmation() {
        app.buttons["Settings"].tap()
        app.buttons["Woolworths"].tap()
        app.buttons["Reset Woolworths Session"].tap()
        XCTAssertTrue(app.alerts["Reset Woolworths Session?"].waitForExistence(timeout: 3))
        app.alerts.buttons["Cancel"].tap()
        XCTAssertFalse(app.alerts.firstMatch.exists)
        XCTAssertTrue(app.buttons["Clear Woolworths Diagnostics"].exists)
    }

    func testClearListHasWideTapTarget() {
        let clear = app.buttons["Clear List"]
        XCTAssertTrue(clear.waitForExistence(timeout: 3))
        XCTAssertGreaterThan(clear.frame.width, 250)
    }

    func testNewItemsAreAddedToFrontInEnteredOrder() {
        let input = app.descendants(matching: .any)["grocery-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 3))
        input.tap()
        input.typeText("new apples\nnew pears")
        app.buttons["Add Items"].tap()

        let apples = row("new apples", status: "Pending")
        let pears = row("new pears", status: "Pending")
        let existing = row("Coles fixture item", status: "Pending")
        XCTAssertTrue(apples.waitForExistence(timeout: 3))
        XCTAssertTrue(pears.exists)
        XCTAssertLessThan(apples.frame.minY, pears.frame.minY)
        XCTAssertLessThan(pears.frame.minY, existing.frame.minY)
    }

    func testGroceryInputReturnSubmitsItem() {
        let input = app.descendants(matching: .any)["grocery-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 3))
        input.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["dismiss-grocery-keyboard"].exists)
        input.typeText("milk\n")
        XCTAssertTrue(row("milk", status: "Pending").waitForExistence(timeout: 3))
    }

    func testTappingOutsideGroceryInputDismissesKeyboard() {
        let input = app.descendants(matching: .any)["grocery-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 3))
        input.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        app.staticTexts["Ready when you are"].tap()
        XCTAssertFalse(app.keyboards.firstMatch.waitForExistence(timeout: 2))
    }

    func testWoolworthsDetectionDoesNotEnableCartUndo() {
        choose("Woolworths")
        app.buttons["Show Store"].tap()
        XCTAssertFalse(app.staticTexts["Cart detection unavailable"].exists)
        app.buttons["Mark Added"].tap()
        XCTAssertTrue(app.buttons["Finish"].waitForExistence(timeout: 3))
        app.buttons["Undo"].tap()
        XCTAssertTrue(app.buttons["Mark Added"].waitForExistence(timeout: 3))
        app.buttons["Dismiss store"].tap()
        XCTAssertTrue(row("Woolworths fixture item", status: "Pending").waitForExistence(timeout: 3))
        choose("Coles")
        XCTAssertTrue(row("Coles fixture item", status: "Pending").waitForExistence(timeout: 3))
    }

    func testUpwardOverlayPullReturnsCardsToRestWithoutCollapsing() {
        app.buttons["Show Store"].tap()
        let card = app.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@",
                                                   "Coles fixture item", "selected")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        let original = card.frame
        let start = card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
        start.press(forDuration: 0.2, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -120)),
                    withVelocity: .slow, thenHoldForDuration: 0.3)
        XCTAssertTrue(card.exists)
        let returned = NSPredicate { _, _ in
            abs(card.frame.minY - original.minY) < 2 && abs(card.frame.height - original.height) < 2
        }
        expectation(for: returned, evaluatedWith: nil)
        waitForExpectations(timeout: 3)
        XCTAssertTrue(app.buttons["Mark Added"].isHittable)
    }

    func testSlowOverlayDragCollapsesAndCanExpandAgain() {
        app.buttons["Show Store"].tap()
        let card = app.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@",
                                                   "Coles fixture item", "selected")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        let start = card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
        let end = start.withOffset(CGVector(dx: 0, dy: 140))
        start.press(forDuration: 0.2, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
        let expand = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Expand overlay")).firstMatch
        XCTAssertTrue(expand.waitForExistence(timeout: 3))
        XCTAssertFalse(card.exists)
        expand.tap()
        XCTAssertTrue(card.waitForExistence(timeout: 3))
    }

    func testVerificationPagePausesRetriesAndCanReturnToList() {
        app.buttons["Show Store"].tap()
        let notice = app.buttons["store-verification-notice"]
        XCTAssertTrue(notice.waitForExistence(timeout: 8))
        XCTAssertTrue(notice.isHittable)
    }

    func testReloadControlRemainsVisibleAcrossNavigationActions() {
        app.buttons["Show Store"].tap()
        XCTAssertTrue(app.buttons["Skip"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Reload store page"].exists)

        app.buttons["Mark Added"].tap()
        XCTAssertTrue(app.buttons["Finish"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Reload store page"].exists)
    }

    func testSameDayRelaunchOpensRememberedStoreList() {
        choose("Woolworths")
        XCTAssertTrue(row("Woolworths fixture item", status: "Pending").waitForExistence(timeout: 3))
        app.terminate()
        app.launch()
        XCTAssertTrue(row("Woolworths fixture item", status: "Pending").waitForExistence(timeout: 3))
        XCTAssertFalse(row("Coles fixture item", status: "Pending").exists)
        XCTAssertFalse(app.buttons["Dismiss store"].exists)
    }

    func testPaprikaImportUsesSelectedStoreAndIsIdempotent() {
        let importButton = app.buttons["import-from-paprika"]
        XCTAssertTrue(importButton.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(importButton.frame.width, 180)
        importButton.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5)).tap()
        XCTAssertTrue(row("milk", status: "Pending").waitForExistence(timeout: 5))
        XCTAssertTrue(row("bread", status: "Pending").exists)

        app.buttons["Import from Paprika"].tap()
        XCTAssertTrue(app.staticTexts["No new Paprika items"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "milk, quantity 2 l")).count, 1)

        app.buttons["Actions for milk"].tap()
        app.buttons["Mark Added"].tap()
        XCTAssertTrue(row("milk", status: "Added").waitForExistence(timeout: 3))
        choose("Woolworths")
        XCTAssertTrue(row("Woolworths fixture item", status: "Pending").waitForExistence(timeout: 3))
        XCTAssertFalse(row("milk", status: "Added").exists)
        choose("Coles")
        XCTAssertTrue(row("milk", status: "Added").waitForExistence(timeout: 3))
    }

    func testPaprikaImportFailuresKeepTheCurrentList() {
        for (fixture, expectedNotice) in [("missing", "Paprika list not found"),
                                          ("multiple", "Multiple Paprika lists found"),
                                          ("accessDenied", "Could not access Paprika reminders")] {
            app.terminate()
            app.launchEnvironment["LISTRUNNER_UI_TEST_SESSION"] = UUID().uuidString
            app.launchEnvironment["LISTRUNNER_PAPRIKA_TEST_FIXTURE"] = fixture
            app.launch()
            app.buttons["Import from Paprika"].tap()
            XCTAssertTrue(app.staticTexts[expectedNotice].waitForExistence(timeout: 5))
            XCTAssertTrue(row("Coles fixture item", status: "Pending").exists)
        }
    }
}
