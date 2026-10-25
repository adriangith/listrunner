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
        if name.contains("CartDetection") {
            app.launchEnvironment["LISTRUNNER_CART_DETECTION_TEST_FIXTURE"] = "quantityUnavailable"
        }
        if name.contains("EmptyList") {
            app.launchEnvironment["LISTRUNNER_UI_TEST_EMPTY_LIST"] = "1"
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

    func testBunningsUsesAnIsolatedStoreSessionWithCartSignal() {
        choose("Bunnings")
        XCTAssertTrue(row("Bunnings fixture item", status: "Pending").waitForExistence(timeout: 3))
        XCTAssertFalse(row("Coles fixture item", status: "Pending").exists)

        app.buttons["Show Store"].tap()
        XCTAssertFalse(app.buttons["cart-detection-notice"].exists,
                       "Bunnings cart detection is enabled after its product-specific signal was verified")
        app.buttons["Dismiss store"].tap()

        XCTAssertTrue(row("Bunnings fixture item", status: "Pending").waitForExistence(timeout: 3))
        choose("Coles")
        XCTAssertTrue(row("Coles fixture item", status: "Pending").waitForExistence(timeout: 3))
        XCTAssertFalse(row("Bunnings fixture item", status: "Pending").exists)
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
        clear.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
    }

    func testNewItemsAreAddedToFrontInEnteredOrder() {
        let input = app.descendants(matching: .any)["grocery-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 3))
        input.tap()
        input.typeText("new apples; new pears")
        app.buttons["Add Items"].tap()

        let apples = row("new apples", status: "Pending")
        let pears = row("new pears", status: "Pending")
        let existing = row("Coles fixture item", status: "Pending")
        XCTAssertTrue(apples.waitForExistence(timeout: 3))
        XCTAssertTrue(apples.isHittable, "New items should scroll into the visible viewport")
        XCTAssertTrue(pears.exists)
        XCTAssertLessThan(apples.frame.minY, pears.frame.minY)
        XCTAssertLessThan(pears.frame.minY, existing.frame.minY)
    }

    func testFirstItemAutoScrollsIntoViewFromEmptyList() {
        XCTAssertTrue(app.staticTexts["Your list is empty"].waitForExistence(timeout: 3))
        let input = app.descendants(matching: .any)["grocery-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 3))
        input.tap()
        input.typeText("first item")
        app.buttons["Add Items"].tap()

        let firstItem = row("first item", status: "Pending")
        XCTAssertTrue(firstItem.waitForExistence(timeout: 3))
        XCTAssertTrue(firstItem.isHittable, "The first row should scroll into the visible viewport")
        XCTAssertTrue(input.isHittable, "The grocery input should remain available above the keyboard")
    }

    func testGroceryInputReturnSubmitsItem() {
        let input = app.descendants(matching: .any)["grocery-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 3))
        input.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["dismiss-grocery-keyboard"].exists)
        input.typeText("milk")
        XCTAssertEqual(input.value as? String, "milk", "Typed text should be visible before submitting")
        input.typeText("\n")
        XCTAssertTrue(row("milk", status: "Pending").waitForExistence(timeout: 3))
        XCTAssertTrue(row("milk", status: "Pending").isHittable,
                      "The new item should be visible above the keyboard")
        XCTAssertNil(input.value as? String, "Submitting with Return should clear the grocery field")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3), "Keyboard should remain open for the next item")
        input.typeText("bread\n")
        XCTAssertTrue(row("bread", status: "Pending").waitForExistence(timeout: 3), "Typing should add the next item without refocusing")
        XCTAssertTrue(row("bread", status: "Pending").isHittable,
                      "Each newly added item should scroll into view")
    }

    func testAddItemsButtonKeepsGroceryInputFocused() {
        let input = app.descendants(matching: .any)["grocery-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 3))
        input.tap()
        input.typeText("milk")
        XCTAssertEqual(input.value as? String, "milk", "Typed text should be visible before tapping Add Items")
        let showStoreButton = app.buttons["Show Store"]
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.exists)
        XCTAssertLessThanOrEqual(showStoreButton.frame.maxY, keyboard.frame.minY - 12,
                                 "Show Store should have breathing room above the keyboard while typing")

        let addButton = app.buttons["Add Items"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 3))
        addButton.tap()

        XCTAssertTrue(row("milk", status: "Pending").waitForExistence(timeout: 3))
        XCTAssertTrue(row("milk", status: "Pending").isHittable,
                      "The new item should be visible above the keyboard")
        XCTAssertTrue(input.isHittable, "The grocery input should remain visible after scrolling to the new item")
        XCTAssertTrue(app.staticTexts["Add grocery items"].isHittable,
                      "The Add grocery items heading should remain visible")
        XCTAssertNil(input.value as? String, "Tapping Add Items should clear the grocery field")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3), "Keyboard should remain open for the next item")
        input.typeText("bread\n")
        XCTAssertTrue(row("bread", status: "Pending").waitForExistence(timeout: 3), "Typing should add the next item without refocusing")
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
        let website = app.webViews.firstMatch
        XCTAssertTrue(website.exists)
        XCTAssertLessThanOrEqual(website.frame.maxY, expand.frame.minY + 1,
                                 "The collapsed bar must reserve space below the website instead of covering it")
        expand.tap()
        XCTAssertTrue(card.waitForExistence(timeout: 3))
    }

    func testCollapsedBarExpandsWithUpwardSwipe() {
        app.buttons["Show Store"].tap()
        let card = app.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@",
                                                   "Coles fixture item", "selected")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        let start = card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
        start.press(forDuration: 0.2, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 140)),
                    withVelocity: .slow, thenHoldForDuration: 0.3)

        let collapsed = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Expand overlay")).firstMatch
        XCTAssertTrue(collapsed.waitForExistence(timeout: 3))
        let dragStart = collapsed.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        dragStart.press(forDuration: 0.1, thenDragTo: dragStart.withOffset(CGVector(dx: 0, dy: -100)))
        XCTAssertTrue(card.waitForExistence(timeout: 3))
    }

    func testVerificationPagePausesRetriesAndCanReturnToList() {
        app.buttons["Show Store"].tap()
        let notice = app.buttons["store-verification-notice"]
        XCTAssertTrue(notice.waitForExistence(timeout: 8))
        XCTAssertTrue(notice.isHittable)
    }

    func testCartDetectionNoticeOpensFullExplanation() {
        app.buttons["Show Store"].tap()
        let notice = app.buttons["cart-detection-notice"]
        XCTAssertTrue(notice.waitForExistence(timeout: 5))
        notice.tap()

        let alert = app.alerts["Cart detection unavailable"]
        XCTAssertTrue(alert.waitForExistence(timeout: 3))
        XCTAssertTrue(alert.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "couldn't read this product's current cart quantity")).firstMatch.exists)
        XCTAssertTrue(alert.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Mark Added in ListRunner")).firstMatch.exists)
        alert.buttons["OK"].tap()
    }

    func testReloadControlRemainsVisibleAcrossNavigationActions() {
        app.buttons["Show Store"].tap()
        XCTAssertTrue(app.buttons["Skip"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Reload store page"].exists)

        app.buttons["Mark Added"].tap()
        XCTAssertTrue(app.buttons["Finish"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Reload store page"].exists)
    }

    func testFinalUndoFinishStateAllowsCardSwitchAndMarkPending() {
        let input = app.descendants(matching: .any)["grocery-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 3))
        input.tap()
        input.typeText("second item")
        app.buttons["Add Items"].tap()
        app.buttons["Show Store"].tap()

        app.buttons["Mark Added"].tap()
        XCTAssertTrue(app.buttons["Mark Added"].waitForExistence(timeout: 3))
        app.buttons["Mark Added"].tap()
        XCTAssertTrue(app.buttons["Finish"].waitForExistence(timeout: 3))

        let otherCard = app.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@",
                                                          "second item", "Added")).firstMatch
        XCTAssertTrue(otherCard.waitForExistence(timeout: 3))
        otherCard.tap()
        XCTAssertTrue(app.buttons["Undo"].exists)
        XCTAssertTrue(app.buttons["Finish"].exists)
        XCTAssertTrue(app.buttons["Mark Pending"].exists)
        app.buttons["Mark Pending"].tap()
        XCTAssertTrue(app.buttons["Mark Added"].waitForExistence(timeout: 3))
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
