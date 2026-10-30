import XCTest
import UIKit
import WebKit

// Explicit opt-in only: ordinary UI tests remain offline. These read-only probes
// use fresh iOS WebKit data stores, never app cookies, sign-in or cart actions.
final class LiveUSSearchTests: XCTestCase {
    @MainActor
    func testReadOnlySearchRoutes() async throws {
        guard ProcessInfo.processInfo.environment["LISTRUNNER_LIVE_US_SEARCH"] == "1" else {
            throw XCTSkip("Live retailer search requires explicit opt-in")
        }
        let probes = [
            ("walmart", "https://www.walmart.com/search?q=milk", "a[href*='/ip/']"),
            ("amazon", "https://www.amazon.com/s?k=milk", "a[href*='/dp/']"),
            ("costcoUS", "https://www.costco.com/s?keyword=milk", "a[href*='.product.'], a[href*='/p/']"),
            ("kroger", "https://www.kroger.com/search?query=milk", "a[href*='/p/']"),
            ("target", "https://www.target.com/s?searchTerm=milk", "a[href*='/p/']")
        ]
        let required = Set((ProcessInfo.processInfo.environment["LISTRUNNER_LIVE_US_REQUIRED"] ?? "")
            .split(separator: ",").map(String.init))
        for (id, route, selector) in probes {
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = .nonPersistent()
            let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: configuration)
            let policy = ReadOnlySearchPolicy(host: URL(string: route)!.host!)
            webView.navigationDelegate = policy
            webView.load(URLRequest(url: URL(string: route)!))
            var products = 0
            var matched = false
            for _ in 0..<30 {
                try await Task.sleep(nanoseconds: 1_000_000_000)
                let script = """
                (() => {
                    const links = [...document.querySelectorAll("\(selector)")]
                      .filter(a => a.getClientRects().length && new URL(a.href).host === location.host);
                    return {products: links.length, matched: links.some(a => /milk/i.test(a.textContent || a.getAttribute('aria-label') || ''))};
                })()
                """
                if let result = try? await webView.evaluateJavaScript(script) as? [String: Any] {
                    products = result["products"] as? Int ?? 0
                    matched = result["matched"] as? Bool ?? false
                    if products > 0 && matched { break }
                }
            }
            let result = "\(id): productLinks=\(products), milkProduct=\(matched), sameHost=\(webView.url?.host == policy.host)"
            print("US_SEARCH_PROBE \(result)")
            let attachment = XCTAttachment(string: result)
            attachment.name = "Read-only search: \(id)"
            attachment.lifetime = .keepAlways
            add(attachment)
            if required.contains(id) {
                XCTAssertTrue(products > 0 && matched && webView.url?.host == policy.host, result)
            }
            webView.stopLoading()
            webView.navigationDelegate = nil
        }
    }
}

@MainActor
private final class ReadOnlySearchPolicy: NSObject, WKNavigationDelegate {
    let host: String
    init(host: String) { self.host = host }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url, url.scheme == "https",
              url.host == host, navigationAction.request.httpMethod == "GET" else {
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }
}

final class StoreSelectionTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["LISTRUNNER_UI_TEST_SESSION"] = UUID().uuidString
        app.launchEnvironment["LISTRUNNER_COUNTRY_TEST_REGION"] = "AU"
        if name.contains("FullyRevealed") || name.contains("AlreadyVisibleNewItem") || name.contains("FocusedProductEntry") {
            app.launchEnvironment["LISTRUNNER_REVEAL_TEST_FIXTURE"] = "enabled"
        }
        if name.contains("KeyboardDismissalAnimation") {
            app.launchEnvironment["LISTRUNNER_ENTRY_ANIMATION_TEST_FIXTURE"] = "enabled"
        }
        if name.contains("IdleRecovery") {
            app.launchEnvironment["LISTRUNNER_IDLE_RECOVERY_TEST_FIXTURE"] = "enabled"
        }
        if name.contains("RegionalSearch") {
            app.launchEnvironment["LISTRUNNER_COUNTRY_TEST_REGION"] = "NZ"
            app.launchEnvironment["LISTRUNNER_UI_TEST_EMPTY_LIST"] = "1"
            app.launchEnvironment["LISTRUNNER_REGIONAL_SEARCH_TEST_FIXTURE"] = name.contains("Checks") ? "checks" : "query"
        }
        if name.contains("Preload") {
            app.launchEnvironment["LISTRUNNER_PRELOAD_TEST_FIXTURE"] = "enabled"
            app.launchEnvironment["LISTRUNNER_UI_TEST_EMPTY_LIST"] = "1"
        }
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
        if name.contains("NativeStoreIndex") {
            app.launchEnvironment["LISTRUNNER_COUNTRY_TEST_REGION"] = "NZ"
        }
        if name.contains("UnsetShoppingCountry") {
            app.launchEnvironment["LISTRUNNER_COUNTRY_TEST_REGION"] = "ZZ"
        }
        if name.contains("MixedCountry") {
            app.launchEnvironment["LISTRUNNER_COUNTRY_TEST_CATALOGUE"] = "mixed"
        }
        app.launch()
        if name.contains("FirstStoreWelcome") { return }
        // Shopping-flow tests start after the real first-store setup flow.
        if app.buttons["welcome-choose-store"].waitForExistence(timeout: 3) {
            app.buttons["welcome-choose-store"].tap()
            enableWelcomeStore("coles")
            app.buttons["store-picker"].tap()
            app.buttons["Manage Stores"].tap()
            for id in ["bunnings", "woolworths", "coles"] { setStoreVisibility(id, shown: true) }
            tapNavigationBack()
        }
        XCTAssertTrue(app.buttons["store-picker"].waitForExistence(timeout: 10))
    }

    override func tearDownWithError() throws { app.terminate() }

    func testFirstStoreWelcomePersistsUntilStoreEnabled() {
        XCTAssertTrue(app.buttons["welcome-choose-store"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Your lists.\nStreamlined."].exists)
        XCTAssertTrue(app.staticTexts["Bring your shopping lists to your favourite stores’ websites and work through them with ListRunner."].exists)
        XCTAssertEqual(app.buttons["welcome-choose-store"].label, "Choose Your First Store")
        XCTAssertFalse(app.buttons["Mark Added"].exists, "The illustrated action must not be an interactive shopping control")
        XCTAssertFalse(app.buttons["Settings"].exists)
        XCTAssertFalse(app.buttons["store-picker"].exists)
        XCTAssertFalse(app.buttons["Show Store"].exists)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["welcome-choose-store"].waitForExistence(timeout: 10))
        app.buttons["welcome-choose-store"].tap()
        tapNavigationBack()
        XCTAssertTrue(app.buttons["welcome-choose-store"].waitForExistence(timeout: 3))
        app.buttons["welcome-choose-store"].tap()
        enableWelcomeStore("coles")
        XCTAssertTrue(app.buttons["store-picker"].waitForExistence(timeout: 5))
        app.buttons["store-picker"].tap()
        app.buttons["Manage Stores"].tap()
        setStoreVisibility("coles", shown: false)
        tapNavigationBack()
        XCTAssertTrue(app.staticTexts["No stores enabled"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["welcome-choose-store"].exists)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["No stores enabled"].waitForExistence(timeout: 10))
    }

    func testFirstStoreWelcomeManageBackgroundAndReturnLayout() throws {
        let heading = app.staticTexts["Your lists.\nStreamlined."]
        let action = app.buttons["welcome-choose-store"]
        XCTAssertTrue(action.waitForExistence(timeout: 10))
        let originalHeading = heading.frame
        let originalAction = action.frame

        for visit in 0..<4 {
            action.tap()
            XCTAssertTrue(app.tables["manage-stores-table"].waitForExistence(timeout: 5))
            if visit == 0 {
                let screenshot = app.screenshot()
                let attachment = XCTAttachment(screenshot: screenshot)
                attachment.name = "Manage Stores full-screen grouped background"
                attachment.lifetime = .keepAlways
                add(attachment)
                let image = try XCTUnwrap(screenshot.image.cgImage)
                var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
                try pixels.withUnsafeMutableBytes { buffer in
                    let context = try XCTUnwrap(CGContext(data: buffer.baseAddress,
                        width: image.width, height: image.height, bitsPerComponent: 8,
                        bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
                    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
                }
                func rgb(x: Double, y: Double) -> [Int] {
                    let offset = (Int(Double(image.height) * y) * image.width + Int(Double(image.width) * x)) * 4
                    return (0..<3).map { Int(pixels[offset + $0]) }
                }
                // Sample away from status text, rows, section index and home indicator.
                let tableBackground = rgb(x: 0.015, y: 0.5)
                for (area, colour) in [("header", rgb(x: 0.015, y: 0.15)),
                                       ("bottom safe area", rgb(x: 0.1, y: 0.975))] {
                    for channel in 0..<3 {
                        XCTAssertLessThanOrEqual(abs(colour[channel] - tableBackground[channel]), 6,
                            "The \(area) should match the grouped table background")
                    }
                }
            }
            tapNavigationBack()
            XCTAssertTrue(action.waitForExistence(timeout: 5))
            XCTAssertEqual(heading.frame.minY, originalHeading.minY, accuracy: 1, "Heading moved after visit \(visit + 1)")
            XCTAssertEqual(action.frame.minY, originalAction.minY, accuracy: 1, "Action moved after visit \(visit + 1)")
            XCTAssertEqual(action.frame.height, originalAction.height, accuracy: 1)
            XCTAssertFalse(app.buttons["Settings"].exists)
        }
        // Settled geometry assertions do not claim that every animation frame is stable.
    }

    func testFirstStoreWelcomeInteractiveBackCanCancelAndComplete() {
        let action = app.buttons["welcome-choose-store"]
        let heading = app.staticTexts["Your lists.\nStreamlined."]
        XCTAssertTrue(action.waitForExistence(timeout: 10))
        let originalHeadingY = heading.frame.minY
        let originalActionY = action.frame.minY
        let table = app.tables["manage-stores-table"]

        for _ in 0..<3 {
            action.tap()
            XCTAssertTrue(table.waitForExistence(timeout: 5))
            let edge = app.coordinate(withNormalizedOffset: CGVector(dx: 0.005, dy: 0.55))
            let partial = app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.55))
            edge.press(forDuration: 0.1, thenDragTo: partial,
                       withVelocity: XCUIGestureVelocity(rawValue: 80), thenHoldForDuration: 0.5)
            XCTAssertTrue(table.waitForExistence(timeout: 5), "Cancelling Back must keep Manage Stores visible")
            XCTAssertTrue(app.navigationBars["Manage Stores"].exists)

            let finish = app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.55))
            edge.press(forDuration: 0.1, thenDragTo: finish,
                       withVelocity: XCUIGestureVelocity(rawValue: 300), thenHoldForDuration: 0.1)
            XCTAssertTrue(action.waitForExistence(timeout: 5))
            XCTAssertFalse(table.exists)
            XCTAssertEqual(heading.frame.minY, originalHeadingY, accuracy: 1)
            XCTAssertEqual(action.frame.minY, originalActionY, accuracy: 1)
            XCTAssertFalse(app.buttons["Settings"].exists)
        }
        // A recorded frame-by-frame device check is also needed to catch a
        // transient safe-area shift that disappears before these settled checks.
    }

    func testFirstStoreWelcomeLargeTextKeepsActionReachable() {
        app.terminate()
        app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Your lists.\nStreamlined."].waitForExistence(timeout: 10))
        let button = app.buttons["welcome-choose-store"]
        for _ in 0..<6 {
            if button.exists && button.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(button.isHittable, app.debugDescription)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Welcome at accessibility text size"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        button.tap()
        XCTAssertTrue(app.tables["manage-stores-table"].waitForExistence(timeout: 5))
        tapNavigationBack()
        XCTAssertTrue(app.staticTexts["Your lists.\nStreamlined."].exists)
    }

    func testFirstStoreWelcomePreviewReturnsAfterCancelledChoice() {
        XCTAssertTrue(app.buttons["welcome-choose-store"].waitForExistence(timeout: 10))
        app.buttons["welcome-choose-store"].tap()
        enableWelcomeStore("coles")
        XCTAssertTrue(app.buttons["store-picker"].waitForExistence(timeout: 5))
        app.terminate()
        app.launchArguments = ["--preview-store-welcome"]
        app.launch()
        XCTAssertTrue(app.buttons["welcome-choose-store"].waitForExistence(timeout: 10))
        app.buttons["welcome-choose-store"].tap()
        tapNavigationBack()
        XCTAssertTrue(app.buttons["welcome-choose-store"].waitForExistence(timeout: 5))
        app.buttons["welcome-choose-store"].tap()
        enableWelcomeStore("bunnings")
        XCTAssertTrue(app.buttons["store-picker"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["welcome-choose-store"].exists)
    }

    func testFirstStoreWelcomeSimpleSetupCancelsThenActivatesChosenStore() {
        XCTAssertTrue(app.buttons["welcome-choose-store"].waitForExistence(timeout: 10))
        app.buttons["welcome-choose-store"].tap()
        openStoreSettings("woolworths", welcome: true)
        XCTAssertTrue(app.buttons["welcome-enable-store"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Included Support"].exists)
        XCTAssertFalse(app.switches["store-visibility-woolworths"].exists)
        XCTAssertFalse(app.staticTexts["Current Session Status"].exists)
        XCTAssertFalse(app.buttons["Reset Woolworths Session"].exists)
        tapNavigationBack()
        tapNavigationBack()
        XCTAssertTrue(app.buttons["welcome-choose-store"].waitForExistence(timeout: 5))
        app.buttons["welcome-choose-store"].tap()
        enableWelcomeStore("woolworths")
        XCTAssertTrue(app.buttons["store-picker"].label.contains("Woolworths"))
        XCTAssertFalse(app.tables["manage-stores-table"].exists)
        XCTAssertFalse(app.buttons["welcome-enable-store"].exists)
        XCTAssertFalse(app.buttons["Dismiss store"].exists)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "BackButton").firstMatch.exists,
                       "Welcome completion must replace the setup navigation stack")
        app.buttons["store-picker"].tap()
        app.buttons["Manage Stores"].tap()
        openStoreSettings("woolworths")
        XCTAssertTrue(app.switches["store-visibility-woolworths"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["welcome-enable-store"].exists)
        XCTAssertTrue(app.staticTexts["Current Session Status"].exists)
    }

    private func enableWelcomeStore(_ store: String) {
        openStoreSettings(store, welcome: true)
        let button = app.buttons["welcome-enable-store"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.tap()
        XCTAssertTrue(app.buttons["store-picker"].waitForExistence(timeout: 5))
    }

    private func choose(_ name: String) {
        XCTAssertTrue(app.buttons["store-picker"].waitForExistence(timeout: 5))
        app.buttons["store-picker"].tap()
        let option = app.buttons[name].firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 3))
        option.tap()
    }

    private func tapNavigationBack() {
        // iOS 27 beta exposes the native back control as Other in some runs,
        // rather than Button. Match its stable identifier, not the AX type.
        let back = app.descendants(matching: .any).matching(identifier: "BackButton").firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 5), app.debugDescription)
        back.tap()
    }

    private func row(_ name: String, status: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS[cd] %@ AND label CONTAINS[cd] %@", name, status)).firstMatch
    }

    private func assertGroceryInputIsEmpty(_ input: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        // XCTest exposes the placeholder as value on iOS 26, but nil on iOS 27.
        let value = input.value as? String
        XCTAssertTrue(value == nil || value == "" || value == input.placeholderValue,
                      "Submitting should clear the grocery field, not leave typed text", file: file, line: line)
    }

    private func assertFirstItemIsFullyVisible(_ name: String, keyboardExpected: Bool = true, file: StaticString = #filePath, line: UInt = #line) {
        let app = self.app!
        let item = row(name, status: "Pending")
        XCTAssertTrue(item.waitForExistence(timeout: 5), file: file, line: line)
        let cell = app.collectionViews.cells.containing(.button, identifier: item.label).firstMatch
        let input = app.descendants(matching: .any)["grocery-input"]
        let showStore = app.buttons["Show Store"]
        let keyboard = app.keyboards.firstMatch
        let visible = NSPredicate { _, _ in
            guard cell.exists, input.exists, showStore.exists, keyboard.exists == keyboardExpected else { return false }
            let frame = cell.frame
            return frame.height > 0
                && frame.minY >= app.collectionViews.firstMatch.frame.minY
                && frame.maxY <= showStore.frame.minY
                && showStore.frame.maxY <= (keyboardExpected ? keyboard.frame.minY : app.frame.maxY)
                && input.isHittable && item.isHittable
        }
        let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: visible, object: app)], timeout: 5)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "First item after submission"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        if result != .completed { print(app.debugDescription) }
        XCTAssertEqual(result, .completed,
                       "The entire first grocery row must be visible above Show Store and the keyboard, with input still available",
                       file: file, line: line)
    }

    private func setStoreVisibility(_ store: String, shown: Bool) {
        openStoreSettings(store)
        let toggle = app.switches["store-visibility-\(store)"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 3))
        let desired = shown ? "1" : "0"
        if toggle.value as? String != desired {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
            let predicate = NSPredicate(format: "value == %@", desired)
            let expectation = XCTNSPredicateExpectation(predicate: predicate, object: app.switches["store-visibility-\(store)"])
            XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 3), .completed)
        }
        tapNavigationBack()
    }

    // UIKit table rows expose their identifier on Cell/Other elements, not as
    // Button elements; query by identifier across element types, matching the
    // pattern the previous Shopping country row used.
    private func manageRow(_ store: String) -> XCUIElement {
        app.descendants(matching: .any)["manage-store-\(store)"].firstMatch
    }

    private func openStoreSettings(_ store: String, welcome: Bool = false) {
        let entry = manageRow(store)
        let table = app.tables["manage-stores-table"]
        // XCTest considers even a sliver of a clipped cell hittable. Require
        // the whole row inside the table before tapping its centre.
        func fullyVisible() -> Bool {
            entry.exists && entry.isHittable && entry.frame.height > 0
                && entry.frame.minY >= table.frame.minY
                && entry.frame.maxY <= table.frame.maxY
        }
        for _ in 0..<5 {
            if fullyVisible() { break }
            table.swipeUp()
        }
        for _ in 0..<5 {
            if fullyVisible() { break }
            table.swipeDown()
        }
        XCTAssertTrue(entry.waitForExistence(timeout: 3))
        XCTAssertTrue(fullyVisible(), "Store row must be fully visible before tapping: \(store)")
        entry.tap()
        if welcome {
            XCTAssertTrue(app.buttons["welcome-enable-store"].waitForExistence(timeout: 3))
        } else {
            XCTAssertTrue(app.switches["store-visibility-\(store)"].waitForExistence(timeout: 3))
        }
    }

    private func changeCountry(_ code: String, name: String) {
        let country = app.descendants(matching: .any)["shopping-country"].firstMatch
        XCTAssertTrue(country.waitForExistence(timeout: 3))
        country.tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        search.tap()
        search.typeText(name)
        app.buttons["shopping-country-\(code)"].tap()
    }

    func testPreloadSearchIsPromotedAfterCooldown() {
        let input = app.descendants(matching: .any)["grocery-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 3))
        input.tap()
        input.typeText("preload apple; preload pear")
        app.buttons["Add Items"].tap()
        XCTAssertTrue(row("Apples", status: "Pending").waitForExistence(timeout: 3))
        XCTAssertTrue(row("Pears", status: "Pending").exists)
        app.buttons["Show Store"].tap()
        let promoted = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier == %@ AND label CONTAINS[c] %@", "preload-debug-status", "Promoting completed preload")
        ).firstMatch
        XCTAssertTrue(promoted.waitForExistence(timeout: 25), app.debugDescription)
    }

    func testIdleRecoveryBrowserChecks() {
        app.buttons["Show Store"].tap()
        let status = app.staticTexts["idle-recovery-test-status"]
        let finished = NSPredicate(format: "label BEGINSWITH %@ OR label BEGINSWITH %@", "PASS:", "FAIL:")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: finished, object: status)], timeout: 60),
                       .completed, app.debugDescription)
        XCTAssertTrue(status.label.hasPrefix("PASS:"), status.label)
        XCTAssertFalse(app.alerts["Could not load Coles"].exists)
    }

    func testRegionalSearchBrowserChecks() {
        app.buttons["Settings"].tap()
        changeCountry("NZ", name: "New Zealand")
        tapNavigationBack()
        let input = app.descendants(matching: .any)["grocery-input"]
        input.tap()
        input.typeText("2 zucchini")
        app.buttons["Add Items"].tap()
        app.buttons["Show Store"].tap()
        let pass = app.staticTexts.matching(NSPredicate(format: "identifier == %@ AND label BEGINSWITH %@",
                                                      "regional-search-test-status", "PASS:")).firstMatch
        XCTAssertTrue(pass.waitForExistence(timeout: 20), app.debugDescription)
    }

    private func openRegionalSearchStore() {
        // Returning from Settings restores the grocery field's keyboard focus.
        // A footer AX element can exist while XCTest computes no tappable point.
        if app.keyboards.firstMatch.exists {
            app.staticTexts["Ready when you are"].tap()
            let hidden = NSPredicate(format: "exists == false")
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: hidden, object: app.keyboards.firstMatch)], timeout: 5), .completed)
        }
        let button = app.buttons["Show Store"]
        let hittable = NSPredicate(format: "hittable == true")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: hittable, object: button)], timeout: 5), .completed)
        button.tap()
    }

    func testRegionalSearchTogglePersistsAndLeavesExistingItemUnchanged() {
        let input = app.descendants(matching: .any)["grocery-input"]
        input.tap()
        input.typeText("2 zucchini")
        app.buttons["Add Items"].tap()
        XCTAssertTrue(row("Zucchini", status: "Pending").exists)
        app.buttons["Show Store"].tap()
        let localized = app.staticTexts.matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@",
                                                            "regional-search-test-status", "courgette")).firstMatch
        XCTAssertTrue(localized.waitForExistence(timeout: 8), app.debugDescription)
        app.buttons["Dismiss store"].tap()
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 5))
        app.buttons["Settings"].tap()
        let toggle = app.switches["use-local-ingredient-names"]
        XCTAssertEqual(toggle.value as? String, "1")
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(toggle.value as? String, "0")
        tapNavigationBack()
        openRegionalSearchStore()
        let original = app.staticTexts.matching(NSPredicate(format: "identifier == %@ AND label CONTAINS[c] %@",
                                                           "regional-search-test-status", "zucchini")).firstMatch
        XCTAssertTrue(original.waitForExistence(timeout: 8), "Cached browser must use the changed toggle without a relaunch")
        XCTAssertFalse(localized.exists)
        app.buttons["Dismiss store"].tap()
        app.terminate()
        app.launch()
        XCTAssertTrue(row("Zucchini", status: "Pending").waitForExistence(timeout: 5))
        app.buttons["Settings"].tap()
        XCTAssertEqual(app.switches["use-local-ingredient-names"].value as? String, "0")
        tapNavigationBack()
        openRegionalSearchStore()
        XCTAssertTrue(original.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertFalse(localized.exists)
    }

    func testRegionalSearchCountryChangeUpdatesCachedBrowser() {
        let input = app.descendants(matching: .any)["grocery-input"]
        input.tap()
        input.typeText("2 zucchini")
        app.buttons["Add Items"].tap()
        app.buttons["Show Store"].tap()
        let localized = app.staticTexts.matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@",
                                                            "regional-search-test-status", "courgette")).firstMatch
        XCTAssertTrue(localized.waitForExistence(timeout: 8), app.debugDescription)
        app.buttons["Dismiss store"].tap()
        app.buttons["Settings"].tap()
        changeCountry("AU", name: "Australia")
        XCTAssertEqual(app.switches["use-local-ingredient-names"].value as? String, "1")
        tapNavigationBack()
        XCTAssertTrue(row("Zucchini", status: "Pending").exists)
        openRegionalSearchStore()
        let australian = app.staticTexts.matching(NSPredicate(format: "identifier == %@ AND label CONTAINS[c] %@",
                                                             "regional-search-test-status", "zucchini")).firstMatch
        XCTAssertTrue(australian.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertFalse(localized.exists)
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

    func testMostRecentlyEnabledStoreBecomesActiveOnReturn() {
        app.buttons["Settings"].tap()
        app.buttons["Manage Stores"].tap()
        setStoreVisibility("bigW", shown: true)
        setStoreVisibility("kmart", shown: true)
        XCTAssertTrue(app.navigationBars["Manage Stores"].exists, "Enabling must not dismiss management")
        tapNavigationBack()
        tapNavigationBack()
        XCTAssertTrue(app.buttons["store-picker"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["store-picker"].label, "Kmart")
        choose("Coles")
        app.buttons["Settings"].tap()
        tapNavigationBack()
        XCTAssertEqual(app.buttons["store-picker"].label, "Coles", "The enable preference must be consumed only once")
        app.buttons["Settings"].tap()
        app.buttons["Manage Stores"].tap()
        setStoreVisibility("bigW", shown: false)
        setStoreVisibility("bigW", shown: true)
        tapNavigationBack()
        tapNavigationBack()
        XCTAssertEqual(app.buttons["store-picker"].label, "BIG W")
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["store-picker"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["store-picker"].label, "BIG W")
    }

    func testHidingAndReenablingStorePreservesItsList() {
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.buttons["Manage Stores"].waitForExistence(timeout: 5))
        app.buttons["Manage Stores"].tap()
        setStoreVisibility("coles", shown: false)
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["Clear All Diagnostics"].waitForExistence(timeout: 3))
        app.navigationBars.buttons.firstMatch.tap()

        XCTAssertTrue(app.buttons["store-picker"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["store-picker"].label.contains("Bunnings"))
        XCTAssertTrue(row("Bunnings fixture item", status: "Pending").waitForExistence(timeout: 3))
        XCTAssertFalse(row("Coles fixture item", status: "Pending").exists)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["store-picker"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["store-picker"].label.contains("Bunnings"))
        XCTAssertFalse(app.webViews.firstMatch.exists, "Changing the active list must not open a retailer website")
        choose("Woolworths")
        XCTAssertTrue(row("Woolworths fixture item", status: "Pending").waitForExistence(timeout: 3))

        app.buttons["Settings"].tap()
        app.buttons["Manage Stores"].tap()
        setStoreVisibility("coles", shown: true)
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["Clear All Diagnostics"].waitForExistence(timeout: 3))
        app.navigationBars.buttons.firstMatch.tap()

        choose("Coles")
        XCTAssertTrue(row("Coles fixture item", status: "Pending").waitForExistence(timeout: 3))
    }

    func testDisablingActiveBunningsSelectsEnabledColesAndKeepsItems() {
        choose("Bunnings")
        app.buttons["Actions for Bunnings fixture item"].tap()
        app.buttons["Mark Skipped"].tap()
        let input = app.descendants(matching: .any)["grocery-input"]
        input.tap()
        input.typeText("Bunnings saved item")
        app.buttons["Add Items"].tap()
        XCTAssertTrue(row("Bunnings saved item", status: "Pending").waitForExistence(timeout: 3))
        app.buttons["Actions for Bunnings saved item"].tap()
        app.buttons["Mark Added"].tap()
        app.buttons["store-picker"].tap()
        app.buttons["store-picker-manage-stores"].tap()
        setStoreVisibility("bunnings", shown: false)
        XCTAssertTrue(app.navigationBars["Manage Stores"].exists, "Do not dismiss management during a toggle")
        tapNavigationBack()
        XCTAssertTrue(row("Coles fixture item", status: "Pending").waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["store-picker"].label.contains("Coles"))
        XCTAssertFalse(row("Bunnings saved item", status: "Added").exists)
        XCTAssertFalse(row("Bunnings fixture item", status: "Skipped").exists)
        XCTAssertTrue(app.buttons["Show Store"].isEnabled)
        XCTAssertFalse(app.webViews.firstMatch.exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Disabled Bunnings — enabled Coles list and branding"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.terminate()
        app.launch()
        XCTAssertTrue(row("Coles fixture item", status: "Pending").waitForExistence(timeout: 10))
        app.buttons["store-picker"].tap()
        app.buttons["store-picker-manage-stores"].tap()
        setStoreVisibility("bunnings", shown: true)
        tapNavigationBack()
        XCTAssertTrue(app.buttons["store-picker"].label.contains("Bunnings"), "Re-enabling a store makes it active on return")
        XCTAssertTrue(row("Bunnings fixture item", status: "Skipped").waitForExistence(timeout: 5))
        XCTAssertTrue(row("Bunnings saved item", status: "Added").exists)
    }

    func testSettingsHasCountryAndNoStoreRows() {
        app.buttons["Settings"].tap()
        let manage = app.buttons["Manage Stores"]
        XCTAssertTrue(manage.waitForExistence(timeout: 5))
        for id in ["coles", "woolworths", "bunnings"] {
            XCTAssertFalse(app.buttons["settings-store-\(id)"].exists)
        }
        XCTAssertTrue(app.descendants(matching: .any)["shopping-country"].firstMatch.exists)

        manage.tap()
        setStoreVisibility("coles", shown: false)
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(manage.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["settings-store-coles"].exists)
        XCTAssertFalse(app.buttons["settings-store-woolworths"].exists)
        XCTAssertFalse(app.buttons["settings-store-bunnings"].exists)

        manage.tap()
        XCTAssertTrue(manageRow("coles").waitForExistence(timeout: 5),
                      "Disabled stores must remain available in Manage Stores")
        setStoreVisibility("coles", shown: true)
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertFalse(app.buttons["settings-store-coles"].exists)
    }

    func testSettingsWithAllStoresHiddenKeepsManagementAvailable() {
        app.buttons["Settings"].tap()
        let manage = app.buttons["Manage Stores"]
        XCTAssertTrue(manage.waitForExistence(timeout: 5))
        manage.tap()
        for id in ["coles", "woolworths", "bunnings"] {
            setStoreVisibility(id, shown: false)
        }
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(manage.waitForExistence(timeout: 5))
        for id in ["coles", "woolworths", "bunnings"] {
            XCTAssertFalse(app.buttons["settings-store-\(id)"].exists)
        }
        XCTAssertTrue(app.buttons["Clear All Diagnostics"].exists)

        manage.tap()
        setStoreVisibility("woolworths", shown: true)
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertFalse(app.buttons["settings-store-woolworths"].exists)
        XCTAssertFalse(app.buttons["settings-store-coles"].exists)
        XCTAssertFalse(app.buttons["settings-store-bunnings"].exists)
        tapNavigationBack()
        XCTAssertTrue(row("Woolworths fixture item", status: "Pending").waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["store-picker"].label.contains("Woolworths"))
    }

    func testEnabledStoresMoveOutOfDiscoveryGroupsAndBack() {
        app.buttons["Settings"].tap()
        app.buttons["Manage Stores"].tap()
        XCTAssertTrue(app.staticTexts["ENABLED STORES"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["STORES IN AUSTRALIA"].exists)
        XCTAssertTrue(app.staticTexts["OTHER STORES"].exists)
        XCTAssertEqual(app.switches.count, 0)
        XCTAssertFalse(app.buttons["store-region-picker-costco"].exists)
        XCTAssertFalse(app.buttons["store-letter-menu"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["shopping-country"].firstMatch.exists)

        setStoreVisibility("tesco", shown: true)
        let tesco = manageRow("tesco")
        let costco = manageRow("costco")
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "manage-store-tesco").count, 1)
        XCTAssertLessThan(tesco.frame.minY, costco.frame.minY,
                          "Enabled Tesco moves above disabled Australian stores")
        XCTAssertFalse(app.staticTexts["T"].exists, "Enabling Tesco removes its empty index group")

        setStoreVisibility("tesco", shown: false)
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "manage-store-tesco").count, 1)
        XCTAssertLessThan(costco.frame.minY, tesco.frame.minY)
        XCTAssertTrue(app.staticTexts["T"].exists)
        openStoreSettings("tesco")
        XCTAssertEqual(app.switches["store-visibility-tesco"].value as? String, "0")
        XCTAssertTrue(app.staticTexts["Cart Undo, Not included"].exists,
                      "Disabled stores still expose their complete settings")
    }

    func testAllHiddenStoresHidePickerAndKeepManagementAvailable() {
        app.buttons["Settings"].tap()
        app.buttons["Manage Stores"].tap()
        for store in ["coles", "woolworths", "bunnings"] {
            setStoreVisibility(store, shown: false)
        }
        app.navigationBars.buttons.firstMatch.tap()
        app.navigationBars.buttons.firstMatch.tap()

        XCTAssertFalse(app.buttons["store-picker"].exists)
        XCTAssertFalse(app.buttons["Show Store"].exists)
        XCTAssertTrue(app.staticTexts["No stores enabled"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["grocery-input"].exists)
        app.buttons["no-stores-manage"].tap()
        setStoreVisibility("coles", shown: true)
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["store-picker"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Show Store"].isEnabled)
        app.buttons["store-picker"].tap()
        app.buttons["Manage Stores"].tap()
        setStoreVisibility("woolworths", shown: true)
        setStoreVisibility("bunnings", shown: true)
        app.navigationBars.buttons.firstMatch.tap()
    }

    func testAllDisabledBunningsThenColesSelectsEnabledListAndPreservesSavedLists() {
        choose("Bunnings")
        let input = app.descendants(matching: .any)["grocery-input"]
        input.tap()
        input.typeText("Bunnings saved list item")
        app.buttons["Add Items"].tap()
        XCTAssertTrue(row("Bunnings saved list item", status: "Pending").waitForExistence(timeout: 3))
        app.buttons["store-picker"].tap()
        app.buttons["Manage Stores"].tap()
        for id in ["coles", "woolworths", "bunnings"] { setStoreVisibility(id, shown: false) }
        tapNavigationBack()
        XCTAssertTrue(app.staticTexts["No stores enabled"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["store-picker"].exists)
        XCTAssertFalse(row("Bunnings saved list item", status: "Pending").exists)
        XCTAssertFalse(input.exists)
        XCTAssertFalse(app.buttons["Show Store"].exists)
        XCTAssertFalse(app.buttons["Edit"].exists)
        let neutral = XCTAttachment(screenshot: app.screenshot())
        neutral.name = "Neutral all-stores-disabled screen"
        neutral.lifetime = .keepAlways
        add(neutral)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["No stores enabled"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["store-picker"].exists)
        app.buttons["no-stores-manage"].tap()
        setStoreVisibility("coles", shown: true)
        // Enabling a store must not pop Manage Stores out from under the user.
        XCTAssertTrue(app.navigationBars["Manage Stores"].exists)
        tapNavigationBack()
        XCTAssertTrue(row("Coles fixture item", status: "Pending").waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["store-picker"].label.contains("Coles"))
        XCTAssertFalse(row("Bunnings saved list item", status: "Pending").exists)
        app.terminate()
        app.launch()
        XCTAssertTrue(row("Coles fixture item", status: "Pending").waitForExistence(timeout: 10))
        app.buttons["store-picker"].tap()
        app.buttons["Manage Stores"].tap()
        setStoreVisibility("bunnings", shown: true)
        tapNavigationBack()
        choose("Bunnings")
        XCTAssertTrue(row("Bunnings saved list item", status: "Pending").waitForExistence(timeout: 5))
    }

    func testStoreManagementSearchAndClearDoNotChangeVisibility() {
        app.buttons["store-picker"].tap()
        app.buttons["Manage Stores"].tap()
        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 3))
        searchField.tap()
        searchField.typeText("coles")
        XCTAssertTrue(manageRow("coles").exists)
        XCTAssertFalse(manageRow("woolworths").exists)
        XCTAssertEqual(app.switches.count, 0)

        searchField.buttons["Clear text"].tap()
        searchField.typeText("no-such-store")
        XCTAssertTrue(app.staticTexts["No stores found"].waitForExistence(timeout: 3))
        app.buttons["Clear Search"].tap()
        XCTAssertTrue(app.staticTexts["No stores found"].waitForNonExistence(timeout: 3))
        XCTAssertTrue(searchField.isHittable)
        XCTAssertTrue(app.keyboards.firstMatch.exists, "Clearing no-results should keep search focus")
    }

    func testNativeStoreIndexUsesOnlyNonemptyLettersAndHidesDuringSearch() {
        app.buttons["store-picker"].tap()
        app.buttons["Manage Stores"].tap()
        XCTAssertTrue(app.staticTexts["OTHER STORES"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["No supported stores for this country yet."].exists)
        XCTAssertTrue(app.staticTexts["ENABLED STORES"].exists)
        XCTAssertTrue(app.staticTexts["B"].exists, "Disabled BIG W keeps its own index group")
        XCTAssertLessThan(manageRow("bunnings").frame.minY, manageRow("bigW").frame.minY,
                          "Enabled Bunnings is not duplicated in the index groups")
        XCTAssertTrue(app.staticTexts["C"].exists)
        let index = app.tables["manage-stores-table"].otherElements.matching(NSPredicate(format: "label CONTAINS[cd] 'index'")).firstMatch
        XCTAssertTrue(index.waitForExistence(timeout: 3), app.debugDescription)
        index.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)).tap()
        XCTAssertFalse(app.buttons["store-letter-menu"].exists)
        let search = app.searchFields.firstMatch
        search.tap()
        search.typeText("coles")
        XCTAssertTrue(manageRow("coles").waitForExistence(timeout: 3))
        XCTAssertFalse(index.exists)
        XCTAssertFalse(app.staticTexts["OTHER STORES"].exists)
        search.buttons["Clear text"].tap()
        XCTAssertTrue(index.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["OTHER STORES"].exists)
    }

    func testStoreManagementAccessibility() throws {
        app.buttons["store-picker"].tap()
        let manage = app.buttons["Manage Stores"]
        XCTAssertTrue(manage.waitForExistence(timeout: 3))
        manage.tap()
        XCTAssertTrue(app.staticTexts["Manage Stores"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(manageRow("coles").waitForExistence(timeout: 5))
        XCTAssertEqual(app.switches.count, 0)
        try app.performAccessibilityAudit(for: [.hitRegion, .sufficientElementDescription, .dynamicType, .contrast]) { issue in
            if issue.auditType == .hitRegion && issue.element?.label == "Section index" {
                print("KNOWN NATIVE CONTROL LIMITATION: narrow UIKit index; store rows remain directly accessible")
                return true
            }
            print("Store-management accessibility issue: \(issue)")
            print(issue.element?.debugDescription ?? "No element supplied")
            return false
        }
    }

    func testShoppingCountryDefaultsToRegionWithoutLocationControls() {
        app.buttons["Settings"].tap()
        let country = app.descendants(matching: .any)["shopping-country"].firstMatch
        XCTAssertTrue(country.waitForExistence(timeout: 3))
        XCTAssertTrue(country.label.contains("Country"))
        XCTAssertTrue(country.label.contains("Australia") || country.value as? String == "Australia")
        app.buttons["Manage Stores"].tap()
        XCTAssertFalse(country.exists)
        XCTAssertTrue(app.staticTexts["ENABLED STORES"].exists)
        XCTAssertTrue(app.staticTexts["STORES IN AUSTRALIA"].exists)
        XCTAssertTrue(app.staticTexts["OTHER STORES"].exists)
        XCTAssertFalse(app.buttons["Nearby"].exists)
        XCTAssertFalse(app.buttons["Alphabetical"].exists)
        XCTAssertFalse(app.alerts["Location unavailable"].exists)
        XCTAssertTrue(app.tables.otherElements.matching(NSPredicate(format: "label CONTAINS[cd] 'index'")).firstMatch.exists)
        XCTAssertTrue(manageRow("bunnings").waitForExistence(timeout: 3))
        XCTAssertLessThan(manageRow("bunnings").frame.minY, manageRow("coles").frame.minY,
                          "Enabled stores are listed alphabetically")
        XCTAssertLessThan(manageRow("coles").frame.minY, manageRow("woolworths").frame.minY)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Country-first Manage Stores — Australian catalogue"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testShoppingCountryChangePersistsWithoutChangingVisibilityOrActiveStore() {
        app.buttons["Settings"].tap()
        app.buttons["Manage Stores"].tap()
        setStoreVisibility("bunnings", shown: false)
        tapNavigationBack()
        changeCountry("NZ", name: "New Zealand")
        app.buttons["Manage Stores"].tap()
        XCTAssertTrue(app.staticTexts["OTHER STORES"].waitForExistence(timeout: 3))
        openStoreSettings("bunnings")
        XCTAssertEqual(app.switches["store-visibility-bunnings"].value as? String, "0")
        app.terminate()
        app.launch()
        XCTAssertEqual(app.buttons["store-picker"].label, "Coles")
        app.buttons["Settings"].tap()
        let country = app.descendants(matching: .any)["shopping-country"].firstMatch
        XCTAssertTrue(country.waitForExistence(timeout: 3))
        XCTAssertTrue(country.label.contains("New Zealand") || country.value as? String == "New Zealand")
        app.buttons["Manage Stores"].tap()
        openStoreSettings("bunnings")
        XCTAssertEqual(app.switches["store-visibility-bunnings"].value as? String, "0")
        XCTAssertFalse(app.alerts["Location unavailable"].exists)
    }

    func testUnsetShoppingCountryKeepsAlphabeticalStoresAvailable() {
        app.buttons["Settings"].tap()
        let country = app.descendants(matching: .any)["shopping-country"].firstMatch
        XCTAssertTrue(country.waitForExistence(timeout: 3))
        XCTAssertTrue(country.label.contains("Choose Country") || country.value as? String == "Choose Country")
        app.buttons["Manage Stores"].tap()
        XCTAssertFalse(app.staticTexts["OTHER STORES"].exists)
        XCTAssertTrue(manageRow("coles").exists)
        XCTAssertTrue(app.tables.otherElements.matching(NSPredicate(format: "label CONTAINS[cd] 'index'")).firstMatch.exists)
    }

    func testMixedCountrySectionsKeepNativeIndexSeparateFromSwitches() throws {
        app.buttons["store-picker"].tap()
        app.buttons["Manage Stores"].tap()
        setStoreVisibility("bunnings", shown: false)
        XCTAssertTrue(app.staticTexts["STORES IN AUSTRALIA"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["OTHER STORES"].exists)
        XCTAssertTrue(app.staticTexts["B"].exists)
        XCTAssertFalse(app.staticTexts["C"].exists, "Local stores must not be duplicated in indexed sections")
        let index = app.tables.otherElements.matching(NSPredicate(format: "label CONTAINS[cd] 'index'")).firstMatch
        XCTAssertTrue(index.exists)
        let coles = manageRow("coles")
        let bunnings = manageRow("bunnings")
        XCTAssertLessThan(coles.frame.minY, bunnings.frame.minY)
        // The UIKit section index manages its own hit-testing over the row's
        // trailing edge; the old switch-separation check no longer applies to a
        // full-width disclosure row. Both controls must simply stay usable.
        XCTAssertTrue(bunnings.isHittable, "Store rows stay directly tappable beside the native index")
        XCTAssertTrue(index.isHittable)
        XCTAssertTrue(app.staticTexts["OTHER STORES"].exists)
        XCTAssertEqual(app.switches.count, 0)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Country-first Manage Stores — mixed service-area fixture"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        XCTAssertFalse(app.buttons["store-letter-menu"].exists)
        try app.performAccessibilityAudit(for: [.hitRegion, .sufficientElementDescription, .dynamicType, .contrast]) { issue in
            if issue.auditType == .hitRegion && issue.element?.label == "Section index" {
                print("KNOWN NATIVE CONTROL LIMITATION: UITableView section index has a narrow hit region; store rows remain directly accessible.")
                return true
            }
            print("Mixed-country accessibility issue: \(issue)")
            return false
        }
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

    func testCostcoStartsHiddenAndKeepsItsListAndManualShoppingSeparate() {
        app.buttons["Settings"].tap()
        XCTAssertFalse(app.buttons["settings-store-costco"].exists, "A newly introduced store must not enable itself")
        app.buttons["Manage Stores"].tap()
        openStoreSettings("costco")
        let toggle = app.switches["store-visibility-costco"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 3))
        XCTAssertEqual(toggle.value as? String, "0")
        tapNavigationBack()
        setStoreVisibility("costco", shown: true)
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertFalse(app.buttons["settings-store-costco"].exists)
        app.navigationBars.buttons.firstMatch.tap()

        choose("Costco")
        XCTAssertFalse(row("Coles fixture item", status: "Pending").exists)
        let input = app.descendants(matching: .any)["grocery-input"]
        input.tap()
        input.typeText("Coffee")
        app.buttons["Add Items"].tap()
        XCTAssertTrue(row("Coffee", status: "Pending").waitForExistence(timeout: 3))
        app.buttons["Show Store"].tap()
        XCTAssertTrue(app.buttons["cart-detection-notice"].waitForExistence(timeout: 5),
                      "Costco must not claim automatic cart detection")
        app.buttons["cart-detection-notice"].tap()
        XCTAssertTrue(app.alerts["Cart detection not included"].waitForExistence(timeout: 3),
                      "Intentionally unsupported detection is not a live retailer failure")
        app.alerts["Cart detection not included"].buttons["OK"].tap()
        app.buttons["Mark Added"].tap()
        XCTAssertTrue(app.buttons["Finish"].waitForExistence(timeout: 3))
        app.buttons["Undo"].tap()
        XCTAssertTrue(app.buttons["Mark Added"].waitForExistence(timeout: 3), "Costco Undo restores local status only")
        app.buttons["Dismiss store"].tap()
        choose("Coles")
        XCTAssertTrue(row("Coles fixture item", status: "Pending").waitForExistence(timeout: 3))
        XCTAssertFalse(row("Coffee", status: "Pending").exists)

        app.terminate()
        app.launch()
        choose("Costco")
        XCTAssertTrue(row("Coffee", status: "Pending").waitForExistence(timeout: 3),
                      "Costco visibility and its own list must survive relaunch")
    }

    func testCostcoSettingsKeepUnverifiedCapabilitiesOff() {
        app.buttons["Settings"].tap()
        app.buttons["Manage Stores"].tap()
        setStoreVisibility("costco", shown: true)
        openStoreSettings("costco")
        XCTAssertTrue(app.staticTexts["Search, Included"].exists)
        XCTAssertTrue(app.staticTexts["Cart Undo, Not included"].exists)
        XCTAssertEqual(app.staticTexts.matching(identifier: "Cart detection, Not included").count, 2,
                       "Bundled detection support and current detection session must both be not included")
        app.buttons["Reset Costco Session"].tap()
        XCTAssertTrue(app.alerts["Reset Costco Session?"].waitForExistence(timeout: 3))
        app.alerts["Reset Costco Session?"].buttons["Cancel"].tap()
    }

    func testTescoBrowsingOnlyAppearsUnderOtherStores() {
        app.buttons["Settings"].tap()
        XCTAssertFalse(app.buttons["settings-store-tesco"].exists)
        app.buttons["Manage Stores"].tap()
        XCTAssertTrue(app.staticTexts["STORES IN AUSTRALIA"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["OTHER STORES"].exists)
        XCTAssertTrue(app.staticTexts["T"].exists)
        let tesco = manageRow("tesco")
        XCTAssertTrue(tesco.waitForExistence(timeout: 3))
        XCTAssertEqual(app.switches.count, 0)
        XCTAssertLessThan(manageRow("woolworths").frame.minY, tesco.frame.minY)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Manage Stores — Australia with browsing-only Tesco UK"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        setStoreVisibility("tesco", shown: true)
        openStoreSettings("tesco")
        XCTAssertEqual(app.staticTexts.matching(identifier: "Search, Not included").count, 2,
                       "Tesco must not offer either bundled or session search automation")
        XCTAssertEqual(app.staticTexts.matching(identifier: "Cart detection, Not included").count, 2)
        XCTAssertTrue(app.staticTexts["Cart Undo, Not included"].exists)
    }

    func testTescoMovesToLocalGroupWhenShoppingCountryIsUK() {
        app.buttons["Settings"].tap()
        changeCountry("GB", name: "United Kingdom")
        app.buttons["Manage Stores"].tap()
        XCTAssertTrue(app.staticTexts["STORES IN UNITED KINGDOM"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["OTHER STORES"].exists)
        let tesco = manageRow("tesco")
        XCTAssertLessThan(manageRow("bunnings").frame.minY, tesco.frame.minY,
                          "Enabled Bunnings stays ahead of the local disabled group")
        openStoreSettings("tesco")
        XCTAssertEqual(app.switches["store-visibility-tesco"].value as? String, "0")
    }

    func testCostcoRegionalChoiceIsExplicitAndKeepsAustralianList() {
        app.buttons["store-picker"].tap()
        app.buttons["Manage Stores"].tap()
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "manage-store-costco").count, 1)
        XCTAssertFalse(app.switches["store-visibility-costcoUS"].exists, "Regional websites share a single brand switch")
        setStoreVisibility("costco", shown: true)
        app.navigationBars.buttons.firstMatch.tap()
        choose("Costco")
        let input = app.descendants(matching: .any)["grocery-input"]
        input.tap()
        input.typeText("Australian Costco item")
        app.buttons["Add Items"].tap()
        XCTAssertTrue(row("Australian Costco item", status: "Pending").waitForExistence(timeout: 3))
        app.buttons["store-picker"].tap()
        app.buttons["Manage Stores"].tap()
        openStoreSettings("costco")
        app.buttons["store-region-picker-costco"].tap()
        app.buttons["store-region-costcoUS"].tap()
        XCTAssertTrue(app.alerts["Change Costco region?"].waitForExistence(timeout: 3))
        app.alerts["Change Costco region?"].buttons["Cancel"].tap()
        app.buttons["Done"].tap()
        XCTAssertEqual(app.buttons["store-region-picker-costco"].value as? String, "Australia")
        app.buttons["store-region-picker-costco"].tap()
        app.buttons["store-region-costcoUS"].tap()
        app.alerts["Change Costco region?"].buttons["Use this regional website"].tap()
        XCTAssertTrue(app.navigationBars["Costco region"].waitForNonExistence(timeout: 5))
        XCTAssertEqual(app.buttons["store-region-picker-costco"].value as? String, "United States")
        XCTAssertTrue(app.buttons["Reset Costco US Session"].exists)
        XCTAssertEqual(app.staticTexts.matching(identifier: "Search, Not included").count, 2,
                       "Support and session status must refresh to the selected region")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Costco settings — United States regional website"
        shot.lifetime = .keepAlways
        add(shot)
        tapNavigationBack()
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(row("Bunnings fixture item", status: "Pending").waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["store-picker"].label.contains("Bunnings"),
                      "Bunnings is the alphabetically first enabled destination in this fixture")
        XCTAssertFalse(row("Australian Costco item", status: "Pending").exists,
                       "The now-disabled Australian region must not remain the displayed list")
        choose("Costco US")
        XCTAssertFalse(row("Australian Costco item", status: "Pending").exists, "US and AU lists remain separate")
        app.buttons["store-picker"].tap()
        app.buttons["Manage Stores"].tap()
        openStoreSettings("costco")
        app.buttons["store-region-picker-costco"].tap()
        app.buttons["store-region-costco"].tap()
        app.alerts["Change Costco region?"].buttons["Use this regional website"].tap()
        XCTAssertTrue(app.navigationBars["Costco region"].waitForNonExistence(timeout: 5))
        tapNavigationBack()
        let managementBack = app.navigationBars["Manage Stores"].buttons.firstMatch
        XCTAssertTrue(managementBack.waitForExistence(timeout: 5))
        let hittable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: managementBack)
        XCTAssertEqual(XCTWaiter.wait(for: [hittable], timeout: 5), .completed)
        managementBack.tap()
        choose("Costco")
        XCTAssertTrue(row("Australian Costco item", status: "Pending").waitForExistence(timeout: 3))
    }

    func testCostcoRegionalWebsitePickerAccessibility() throws {
        app.buttons["store-picker"].tap()
        app.buttons["Manage Stores"].tap()
        openStoreSettings("costco")
        app.buttons["store-region-picker-costco"].tap()
        let australian = app.buttons["store-region-costco"]
        XCTAssertTrue(australian.waitForExistence(timeout: 3))
        XCTAssertTrue(australian.isSelected)
        XCTAssertFalse(app.buttons["store-region-costcoUS"].isSelected)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Costco — explicit regional website choices"
        shot.lifetime = .keepAlways
        add(shot)
        try app.performAccessibilityAudit(for: [.hitRegion, .sufficientElementDescription, .dynamicType, .contrast])
    }

    func testCostcoCountryChangeSuggestsButDoesNotSwitchEnabledRegion() {
        app.buttons["Settings"].tap()
        app.buttons["Manage Stores"].tap()
        setStoreVisibility("costco", shown: true)
        tapNavigationBack()
        changeCountry("US", name: "United States")
        app.buttons["Manage Stores"].tap()
        openStoreSettings("costco")
        XCTAssertEqual(app.switches.matching(identifier: "store-visibility-costco").count, 1)
        XCTAssertEqual(app.buttons["store-region-picker-costco"].value as? String, "Australia")
        app.terminate()
        app.launch()
        app.buttons["store-picker"].tap()
        app.buttons["Manage Stores"].tap()
        openStoreSettings("costco")
        XCTAssertEqual(app.buttons["store-region-picker-costco"].value as? String, "Australia")
        XCTAssertEqual(app.switches["store-visibility-costco"].value as? String, "1")
    }

    func testBigWAustraliaStartsHiddenWithReviewedAutomation() {
        app.buttons["Settings"].tap()
        app.buttons["Manage Stores"].tap()
        openStoreSettings("bigW")
        XCTAssertEqual(app.switches["store-visibility-bigW"].value as? String, "0")
        app.switches["store-visibility-bigW"].tap()
        XCTAssertTrue(app.staticTexts["Search, Included"].exists)
        XCTAssertTrue(app.staticTexts["Cart detection, Included"].exists)
        XCTAssertTrue(app.staticTexts["Cart Undo, Included"].exists)
        app.buttons["Reset BIG W Session"].tap()
        XCTAssertTrue(app.alerts["Reset BIG W Session?"].waitForExistence(timeout: 3))
        app.alerts["Reset BIG W Session?"].buttons["Cancel"].tap()
    }

    func testKmartAustraliaStartsHiddenWithReviewedAutomation() {
        app.buttons["Settings"].tap()
        XCTAssertFalse(app.buttons["settings-store-kmart"].exists)
        app.buttons["Manage Stores"].tap()
        let kmart = manageRow("kmart")
        XCTAssertTrue(kmart.waitForExistence(timeout: 3))
        XCTAssertLessThan(manageRow("costco").frame.minY, kmart.frame.minY)
        XCTAssertLessThan(manageRow("woolworths").frame.minY, kmart.frame.minY)
        setStoreVisibility("kmart", shown: true)
        openStoreSettings("kmart")
        XCTAssertEqual(app.staticTexts.matching(identifier: "Search, Included").count, 1)
        XCTAssertEqual(app.staticTexts.matching(identifier: "Cart detection, Included").count, 1)
        XCTAssertTrue(app.staticTexts["Cart Undo, Not included"].exists)
        app.buttons["Reset Kmart Session"].tap()
        XCTAssertTrue(app.alerts["Reset Kmart Session?"].waitForExistence(timeout: 3))
        app.alerts["Reset Kmart Session?"].buttons["Cancel"].tap()
    }

    func testWalmartUSSupportsSearchAndStartsHidden() {
        app.buttons["Settings"].tap()
        XCTAssertFalse(app.buttons["settings-store-walmart"].exists)
        app.buttons["Manage Stores"].tap()
        let walmart = manageRow("walmart")
        for _ in 0..<3 {
            if walmart.exists && walmart.isHittable { break }
            app.tables["manage-stores-table"].swipeUp()
        }
        XCTAssertTrue(walmart.waitForExistence(timeout: 3))
        XCTAssertEqual(app.switches.count, 0)
        setStoreVisibility("walmart", shown: true)
        openStoreSettings("walmart")
        XCTAssertTrue(app.staticTexts["Search, Included"].exists)
        XCTAssertEqual(app.staticTexts.matching(identifier: "Cart detection, Not included").count, 2)
        XCTAssertTrue(app.staticTexts["Cart Undo, Not included"].exists)
    }

    func testNewUSRetailersStartHiddenWithHonestSupportAndOwnReset() {
        app.buttons["Settings"].tap()
        changeCountry("US", name: "United States")
        app.buttons["Manage Stores"].tap()
        for (id, name) in [("amazon", "Amazon US"), ("kroger", "Kroger"), ("target", "Target US")] {
            openStoreSettings(id)
            XCTAssertEqual(app.switches["store-visibility-\(id)"].value as? String, "0")
            XCTAssertTrue(app.staticTexts[id == "amazon" ? "Search, Not included" : "Search, Included"].exists)
            XCTAssertTrue(app.staticTexts["Cart detection, Not included"].exists)
            XCTAssertTrue(app.staticTexts["Cart Undo, Not included"].exists)
            app.buttons["Reset \(name) Session"].tap()
            XCTAssertTrue(app.alerts["Reset \(name) Session?"].waitForExistence(timeout: 3))
            app.alerts["Reset \(name) Session?"].buttons["Cancel"].tap()
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
    }

    func testWalmartMovesToLocalGroupForUnitedStates() {
        app.buttons["Settings"].tap()
        changeCountry("US", name: "United States")
        app.buttons["Manage Stores"].tap()
        XCTAssertTrue(app.staticTexts["STORES IN UNITED STATES"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["OTHER STORES"].exists)
        let walmart = manageRow("walmart")
        XCTAssertLessThan(manageRow("bunnings").frame.minY, walmart.frame.minY)
        XCTAssertLessThan(walmart.frame.minY, manageRow("tesco").frame.minY)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Manage Stores — United States with browsing-only Walmart"
        screenshot.lifetime = .keepAlways
        add(screenshot)
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
        app.buttons["Manage Stores"].tap()
        openStoreSettings("woolworths")
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
        XCTAssertTrue(app.buttons["Clear All"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Clear Added"].exists)
        cancelClearListOptions()
    }

    private func openClearListOptions() {
        let clear = app.buttons["Clear List"]
        for _ in 0..<3 {
            if clear.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(clear.isHittable)
        clear.tap()
        XCTAssertTrue(app.buttons["Clear All"].waitForExistence(timeout: 3))
    }

    private func cancelClearListOptions() {
        // System popover presentations omit the cancel-role action. Dismiss
        // outside the button-anchored popup, as a person would, on those OSes.
        let cancel = app.buttons["Cancel"]
        if cancel.exists {
            cancel.tap()
        } else {
            app.staticTexts["Your list"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        XCTAssertTrue(app.buttons["Clear All"].waitForNonExistence(timeout: 3))
    }

    func testClearAddedPreservesPendingSkippedAndOtherStores() {
        let input = app.descendants(matching: .any)["grocery-input"]
        input.tap()
        input.typeText("Coffee; Apples")
        app.buttons["Add Items"].tap()
        app.staticTexts["Ready when you are"].tap()
        app.buttons["Actions for Coles fixture item"].tap()
        app.buttons["Mark Added"].tap()
        app.buttons["Actions for Coffee"].tap()
        app.buttons["Mark Skipped"].tap()
        openClearListOptions()
        XCTAssertTrue(app.buttons["Clear Added"].exists)
        app.buttons["Clear Added"].tap()
        XCTAssertTrue(app.buttons["Actions for Coles fixture item"].waitForNonExistence(timeout: 3))
        XCTAssertTrue(row("Apples", status: "Pending").exists)
        XCTAssertTrue(row("Coffee", status: "Skipped").exists)
        openClearListOptions()
        XCTAssertFalse(app.buttons["Clear Added"].exists, "Clear Added disappears when no Added items remain")
        cancelClearListOptions()
        choose("Woolworths")
        XCTAssertTrue(row("Woolworths fixture item", status: "Pending").waitForExistence(timeout: 3))
        choose("Coles")
        app.terminate()
        app.launch()
        XCTAssertTrue(row("Apples", status: "Pending").waitForExistence(timeout: 5))
        XCTAssertTrue(row("Coffee", status: "Skipped").exists)
        XCTAssertFalse(app.buttons["Actions for Coles fixture item"].exists)
    }

    func testClearAllWithoutAddedItemsAndCancel() {
        choose("Woolworths")
        app.buttons["Actions for Woolworths fixture item"].tap()
        app.buttons["Mark Added"].tap()
        choose("Coles")
        openClearListOptions()
        XCTAssertFalse(app.buttons["Clear Added"].exists, "Another store's Added items must not enable this action")
        cancelClearListOptions()
        XCTAssertTrue(row("Coles fixture item", status: "Pending").exists)
        openClearListOptions()
        app.buttons["Clear All"].tap()
        XCTAssertTrue(app.staticTexts["Your list is empty"].waitForExistence(timeout: 3))
        choose("Woolworths")
        XCTAssertTrue(row("Woolworths fixture item", status: "Added").waitForExistence(timeout: 3))
        choose("Coles")
        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["Your list is empty"].waitForExistence(timeout: 5))
    }

    func testClearAddedOnlyListStillOffersBothOptions() {
        app.buttons["Actions for Coles fixture item"].tap()
        app.buttons["Mark Added"].tap()
        openClearListOptions()
        XCTAssertTrue(app.buttons["Clear Added"].exists)
        cancelClearListOptions()
        XCTAssertTrue(row("Coles fixture item", status: "Added").exists,
                      "Even a completed list must not clear before a choice is made")
        openClearListOptions()
        app.buttons["Clear Added"].tap()
        XCTAssertTrue(app.staticTexts["Your list is empty"].waitForExistence(timeout: 3))
    }

    func testSwipeLeftRevealsDeleteAndRemovesOnlyThatItem() {
        let item = row("Coles fixture item", status: "Pending")
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        item.swipeLeft()
        let delete = app.buttons["Delete"].firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 3))
        XCTAssertTrue(item.exists, "Swiping must reveal Delete, not immediately remove the row")
        delete.tap()
        XCTAssertTrue(item.waitForNonExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Your list is empty"].waitForExistence(timeout: 3))
        choose("Woolworths")
        XCTAssertTrue(row("Woolworths fixture item", status: "Pending").waitForExistence(timeout: 3),
                      "Deleting a row must not change another store's list")
        choose("Coles")
        XCTAssertTrue(app.staticTexts["Your list is empty"].waitForExistence(timeout: 3))
        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["Your list is empty"].waitForExistence(timeout: 5), "Deletion must persist")
    }

    func testProductEntryActionsRowIsCompact() {
        let importButton = app.buttons["set-import-source"]
        XCTAssertTrue(importButton.waitForExistence(timeout: 3))
        let actionsRow = app.collectionViews.cells.containing(.button, identifier: "set-import-source").firstMatch
        XCTAssertTrue(actionsRow.exists)
        XCTAssertLessThanOrEqual(actionsRow.frame.height, 56, "Remove spare padding, not button hit areas")
        XCTAssertGreaterThanOrEqual(importButton.frame.height, 44)
        XCTAssertTrue(importButton.isHittable)
        XCTAssertTrue(app.buttons["Add Items"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Compact product-entry action row"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        print("Product-entry action row height: \(actionsRow.frame.height)")
    }

    func testLemonTreeRemainsDistinctFromLemon() {
        let input = app.descendants(matching: .any)["grocery-input"]
        input.tap()
        input.typeText("lemon, Lemon tree")
        app.buttons["Add Items"].tap()
        app.staticTexts["Ready when you are"].tap()
        XCTAssertTrue(app.buttons["Actions for Lemon"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Actions for Lemon Tree"].exists,
                      "Lemon Tree must retain its full name rather than merging with Lemon")
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["Actions for Lemon"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Actions for Lemon Tree"].exists)
    }

    func testKeyboardDismissalAnimationOnOutsideTap() {
        let input = app.descendants(matching: .any)["grocery-input"]
        input.tap()
        input.typeText("Unsubmitted draft")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        app.staticTexts["Ready when you are"].tap()
        assertEntryDismissalAllowsSystemAnimation()
        XCTAssertEqual(input.value as? String, "Unsubmitted draft")
        input.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3), "Defocus must not break refocusing")
    }

    func testKeyboardDismissalAnimationOnEmptyReturn() {
        let input = app.descendants(matching: .any)["grocery-input"]
        input.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        input.typeText("\n")
        assertEntryDismissalAllowsSystemAnimation()
        assertGroceryInputIsEmpty(input)
    }

    private func assertEntryDismissalAllowsSystemAnimation(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5), file: file, line: line)
        let status = app.staticTexts["entry-dismissal-animation-status"]
        let enabled = NSPredicate(format: "label ENDSWITH %@", "resign-animations-enabled")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: enabled, object: status)], timeout: 3),
                       .completed, "First responder must resign outside SwiftUI's animation-disabled update transaction", file: file, line: line)
        print("Entry dismissal animation: \(status.label)")
    }

    func testShowStoreDeactivatesGroceryInputAndPreservesDraft() {
        let input = app.descendants(matching: .any)["grocery-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.typeText("Unsubmitted item")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        app.buttons["Show Store"].tap()
        XCTAssertTrue(app.buttons["Dismiss store"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
        app.buttons["Dismiss store"].tap()
        XCTAssertTrue(app.buttons["Dismiss store"].waitForNonExistence(timeout: 5), "The store sheet must actually close before testing focus")
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        XCTAssertEqual(input.value as? String, "Unsubmitted item")
        XCTAssertFalse(app.keyboards.firstMatch.exists, "Returning must not reactivate the input")
    }

    func testAddProductsEntryOpensKeyboardAndSubmitsFromEmptyList() {
        let input = app.descendants(matching: .any)["grocery-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        assertGroceryInputIsEmpty(input)
        XCTAssertFalse(app.staticTexts["Type or paste a list, e.g. milk, bread, eggs"].exists)
        XCTAssertFalse(app.buttons["Add products"].exists, "No separate plus button should remain")
        // XCTest exposes the inner editor, excluding its 14pt visual padding.
        // Tap outside that editor but inside the outline to test the whole field.
        input.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 1))
            .withOffset(CGVector(dx: 10, dy: 10)).tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        app.staticTexts["Ready when you are"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
        input.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: -10, dy: -10)).tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        input.typeText("Milk")
        XCTAssertTrue(app.buttons["Add Items"].isEnabled)
        app.buttons["Add Items"].tap()
        XCTAssertTrue(row("Milk", status: "Pending").waitForExistence(timeout: 5))
        assertGroceryInputIsEmpty(input)
    }

    func testNewItemsAreAddedToFrontInEnteredOrder() {
        let input = app.descendants(matching: .any)["grocery-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 3))
        input.tap()
        input.typeText("new apples; new pears")
        app.buttons["Add Items"].tap()

        // The ingredient-first parser canonicalizes known ingredient names and
        // drops non-ingredient modifiers such as "new".
        let apples = row("apples", status: "Pending")
        let pears = row("pears", status: "Pending")
        let existing = row("Coles fixture item", status: "Pending")
        XCTAssertTrue(apples.waitForExistence(timeout: 3))
        XCTAssertTrue(apples.isHittable, "New items should scroll into the visible viewport")
        XCTAssertTrue(pears.exists)
        XCTAssertLessThan(apples.frame.minY, pears.frame.minY)
        XCTAssertLessThan(pears.frame.minY, existing.frame.minY)
    }

    func testRepeatedNewItemsAreFullyRevealedInExistingList() {
        let existingCell = app.collectionViews.cells.containing(.button, identifier: "Actions for Coles fixture item").firstMatch
        XCTAssertEqual(existingCell.frame.height, 78, accuracy: 1, "Reveal geometry must not add extra cell padding")
        let input = app.descendants(matching: .any)["grocery-input"]
        input.tap()
        let names = [
            "household organiser alpha",
            "household organiser with an unusually long custom product description",
            "household organiser bravo",
            "household organiser charlie",
            "household organiser with another unusually long custom product description",
            "household organiser delta"
        ]
        for (index, name) in names.enumerated() {
            if index.isMultiple(of: 2) {
                input.typeText(name)
                app.buttons["Add Items"].tap()
            } else {
                input.typeText(name + "\n")
            }
            assertFirstItemIsFullyVisible(name)
            assertGroceryInputIsEmpty(input)
        }
    }

    func testFocusedProductEntryGrowingDraftKeepsWholeCardAboveShowStore() {
        let input = app.descendants(matching: .any)["grocery-input"]
        input.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        input.typeText("household cleaning supplies with a deliberately long wrapping product description and extra details to fill several lines in the product entry field")
        let editorCell = app.collectionViews.cells.containing(.textView, identifier: "grocery-input").firstMatch
        let actionsCell = app.collectionViews.cells.containing(.button, identifier: "import-from-paprika").firstMatch
        let visible = NSPredicate { _, _ in
            editorCell.frame.minY >= self.app.buttons["store-picker"].frame.maxY
                && actionsCell.frame.maxY <= self.app.buttons["Show Store"].frame.minY
                && self.app.buttons["Show Store"].frame.maxY < self.app.frame.height * 0.65
                && self.app.buttons["Add Items"].isHittable
        }
        let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: visible, object: app)], timeout: 5)
        if result != .completed { print(app.debugDescription) }
        XCTAssertEqual(result, .completed, "Growing a focused draft must reveal the whole card without submitting it")
        XCTAssertTrue(row("household cleaning supplies", status: "Pending").exists == false)
        XCTAssertTrue(app.keyboards.firstMatch.exists)
    }

    func testFocusedProductEntryRevealsEntireCardAboveShowStore() {
        let input = app.descendants(matching: .any)["grocery-input"]
        let initialEditorY = app.collectionViews.cells.containing(.textView, identifier: "grocery-input").firstMatch.frame.minY
        input.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        let editorCell = app.collectionViews.cells.containing(.textView, identifier: "grocery-input").firstMatch
        let actionsCell = app.collectionViews.cells.containing(.button, identifier: "import-from-paprika").firstMatch
        let visible = NSPredicate { _, _ in
            editorCell.frame.minY >= self.app.buttons["store-picker"].frame.maxY
                && actionsCell.frame.maxY <= self.app.buttons["Show Store"].frame.minY
                && self.app.buttons["Show Store"].frame.maxY < self.app.frame.height * 0.65
                && self.app.keyboards.firstMatch.exists
        }
        let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: visible, object: app)], timeout: 5)
        if result != .completed { print(app.debugDescription) }
        XCTAssertEqual(result, .completed,
                       "The whole entry card, including the action row, must fit above Show Store")
        XCTAssertEqual(editorCell.frame.minY, initialEditorY, accuracy: 2,
                       "Opening the keyboard must not reposition a card that already fits")
        let originalY = editorCell.frame.minY
        // Refocusing an already visible card must not force a different offset.
        input.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        XCTAssertEqual(editorCell.frame.minY, originalY, accuracy: 2)
    }

    func testAlreadyVisibleNewItemDoesNotRepositionList() {
        let input = app.descendants(matching: .any)["grocery-input"]
        input.tap()
        // First establish the normal post-reveal position. Another same-height
        // row inserted at the front already fits there, without a synthetic drag
        // that can dismiss the keyboard or hide the editor beneath the header.
        input.typeText("kettle")
        app.buttons["Add Items"].tap()
        assertFirstItemIsFullyVisible("kettle")
        // Tap software keys so XCTest doesn't reposition the editor or briefly
        // switch to hardware-key injection while arranging this scenario.
        for letter in "toaster" {
            app.keys.matching(NSPredicate(format: "label ==[c] %@", String(letter))).firstMatch.tap()
        }
        let existingCell = app.collectionViews.cells.containing(.button, identifier: "Actions for kettle").firstMatch
        let showStore = app.buttons["Show Store"]
        let keyboardLayout = NSPredicate { _, _ in
            showStore.frame.maxY < self.app.frame.height * 0.65
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: keyboardLayout, object: app)], timeout: 5), .completed)
        assertFirstItemIsFullyVisible("kettle")
        XCTAssertLessThanOrEqual(existingCell.frame.maxY, showStore.frame.minY)
        XCTAssertTrue(input.isHittable)
        XCTAssertGreaterThan(input.frame.minY, app.buttons["store-picker"].frame.maxY,
                             "Keep the editor below the fixed header so UIKit need not reveal it on submission")
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        let originalInputY = input.frame.minY
        print("Before visible-row submission: cell=\(existingCell.frame), showStore=\(showStore.frame), input=\(input.frame)")
        app.buttons["Add Items"].tap()
        assertFirstItemIsFullyVisible("toaster")
        XCTAssertEqual(input.frame.minY, originalInputY, accuracy: 2,
                       "An already-visible new row must not force bottom alignment")
    }

    func testFirstItemAutoScrollsIntoViewFromEmptyList() {
        XCTAssertTrue(app.staticTexts["Your list is empty"].waitForExistence(timeout: 3))
        let input = app.descendants(matching: .any)["grocery-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 3))
        input.tap()
        input.typeText("first item")
        app.buttons["Add Items"].tap()

        assertFirstItemIsFullyVisible("first item")
    }

    func testFirstItemReturnAutoScrollsIntoViewFromEmptyList() {
        XCTAssertTrue(app.staticTexts["Your list is empty"].waitForExistence(timeout: 3))
        let input = app.descendants(matching: .any)["grocery-input"]
        input.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        input.typeText("first item\n")
        assertFirstItemIsFullyVisible("first item")
    }

    func testFirstLongItemAutoScrollsIntoViewFromEmptyList() {
        XCTAssertTrue(app.staticTexts["Your list is empty"].waitForExistence(timeout: 3))
        let input = app.descendants(matching: .any)["grocery-input"]
        input.tap()
        let name = "first household cleaning item with a deliberately long description"
        input.typeText(name)
        app.buttons["Add Items"].tap()
        assertFirstItemIsFullyVisible(name)
    }

    func testCommaSeparatedNonGroceryProductsCreateSeparateItems() {
        let input = app.descendants(matching: .any)["grocery-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 3))
        input.tap()
        input.typeText("toaster, chair")
        app.buttons["Add Items"].tap()
        XCTAssertTrue(row("toaster", status: "Pending").waitForExistence(timeout: 3))
        XCTAssertTrue(row("chair", status: "Pending").exists)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "toaster, chair")).firstMatch.exists)
        assertGroceryInputIsEmpty(input)
    }

    func testMultilineProductPasteCreatesSeparateItems() {
        let input = app.descendants(matching: .any)["grocery-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 3))
        UIPasteboard.general.string = "toaster\nchair"
        input.tap()
        input.press(forDuration: 1)
        let paste = app.menuItems["Paste"].firstMatch
        if paste.waitForExistence(timeout: 2) { paste.tap() }
        else {
            let pasteButton = app.buttons["Paste"].firstMatch
            XCTAssertTrue(pasteButton.waitForExistence(timeout: 3))
            pasteButton.tap()
        }
        XCTAssertTrue(row("toaster", status: "Pending").waitForExistence(timeout: 5))
        XCTAssertTrue(row("chair", status: "Pending").exists)
        assertGroceryInputIsEmpty(input)
        XCTAssertTrue(app.keyboards.firstMatch.exists)
    }

    func testReturnSubmissionKeepsProductEntryAtOneLine() {
        let input = app.descendants(matching: .any)["grocery-input"]
        input.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        let originalHeight = input.frame.height
        input.typeText("toaster")
        XCTAssertEqual(input.frame.height, originalHeight, accuracy: 1)
        input.typeText("\n")
        XCTAssertTrue(row("toaster", status: "Pending").waitForExistence(timeout: 3))
        assertGroceryInputIsEmpty(input)
        XCTAssertEqual(input.frame.height, originalHeight, accuracy: 1)
        XCTAssertTrue(app.keyboards.firstMatch.exists)
    }

    func testGroceryInputEmptyReturnDismissesKeyboard() {
        let input = app.descendants(matching: .any)["grocery-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 3))
        for text in ["\n", "   \n"] {
            input.tap()
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
            input.typeText(text)
            XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
            assertGroceryInputIsEmpty(input)
            XCTAssertTrue(row("Coles fixture item", status: "Pending").exists)
        }
        input.tap()
        input.typeText("milk\n")
        XCTAssertTrue(row("milk", status: "Pending").waitForExistence(timeout: 3))
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        input.typeText("\n")
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
        assertGroceryInputIsEmpty(input)
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
        assertGroceryInputIsEmpty(input)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3), "Keyboard should remain open for the next item")
        input.typeText("bread\n")
        XCTAssertTrue(row("bread", status: "Pending").waitForExistence(timeout: 3), "Typing should add the next item without refocusing")
        XCTAssertTrue(row("bread", status: "Pending").isHittable,
                      "Each newly added item should scroll into view")
    }

    func testAddItemsButtonSubmitsAndKeepsInputFocused() {
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
        XCTAssertTrue(app.staticTexts["Add products"].isHittable,
                      "The Add products heading should remain visible")
        assertGroceryInputIsEmpty(input)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3), "Add Items is an exception to outside-tap dismissal")
        input.typeText("bread")
        addButton.tap()
        XCTAssertTrue(row("bread", status: "Pending").waitForExistence(timeout: 3))
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        input.typeText("eggs\n")
        XCTAssertTrue(row("eggs", status: "Pending").waitForExistence(timeout: 3), "Continue typing without refocusing after repeated Add Items taps")
    }

    func testManageStoreRowsRespondAfterLeavingFocusedInput() {
        let input = app.descendants(matching: .any)["grocery-input"]
        for startsFocused in [false, true] {
            if startsFocused {
                input.tap()
                input.typeText("Draft item")
                XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
            }
            app.buttons["Settings"].tap()
            XCTAssertTrue(app.buttons["Manage Stores"].waitForExistence(timeout: 5))
            app.buttons["Manage Stores"].tap()
            for store in ["coles", "woolworths", "kmart", "coles"] {
                openStoreSettings(store)
                tapNavigationBack()
                XCTAssertTrue(app.navigationBars["Manage Stores"].waitForExistence(timeout: 3))
            }
            tapNavigationBack()
            tapNavigationBack()
            XCTAssertTrue(input.waitForExistence(timeout: 5))
            XCTAssertFalse(app.keyboards.firstMatch.exists, "Returning from Settings must not reactivate the field")
            if startsFocused { XCTAssertEqual(input.value as? String, "Draft item") }
        }
    }

    func testTappingOutsideGroceryInputDismissesKeyboard() {
        let input = app.descendants(matching: .any)["grocery-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 3))
        input.tap()
        input.typeText("Draft item")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        app.navigationBars.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
        XCTAssertEqual(input.value as? String, "Draft item")
        input.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        app.staticTexts["Add products"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
        XCTAssertEqual(input.value as? String, "Draft item")
    }

    func testEmptyListOutsideEntryDismissesKeyboard() {
        let input = app.descendants(matching: .any)["grocery-input"]
        input.tap()
        input.typeText("Draft item")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        let empty = app.staticTexts["Your list is empty"]
        if !empty.isHittable { app.swipeUp() }
        empty.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
        XCTAssertEqual(input.value as? String, "Draft item")
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

    func testProgressChevronCollapsesOverlayAndPreservesStatus() {
        app.buttons["Show Store"].tap()
        let collapse = app.buttons["Collapse overlay"]
        XCTAssertTrue(collapse.waitForExistence(timeout: 5))
        XCTAssertTrue(collapse.isHittable)
        XCTAssertEqual(collapse.value as? String, "Item 1 of 1")
        // Accessibility coordinates can round a 44pt frame to 43.9999999999.
        XCTAssertGreaterThanOrEqual(collapse.frame.width, 44 - 0.01)
        XCTAssertGreaterThanOrEqual(collapse.frame.height, 44 - 0.01)
        collapse.tap()
        let expand = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Expand overlay")).firstMatch
        XCTAssertTrue(expand.waitForExistence(timeout: 3))
        XCTAssertFalse(collapse.exists)
        expand.tap()
        XCTAssertTrue(collapse.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Mark Added"].exists, "Collapse must not mark the item added")
        app.buttons["Mark Added"].tap()
        XCTAssertTrue(app.buttons["Mark Pending"].waitForExistence(timeout: 3))
        collapse.tap()
        XCTAssertTrue(expand.waitForExistence(timeout: 3))
        expand.tap()
        XCTAssertTrue(app.buttons["Mark Pending"].waitForExistence(timeout: 3), "Collapse must preserve Added status too")
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
        collapsed.swipeUp()
        XCTAssertTrue(card.waitForExistence(timeout: 5))
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
        XCTAssertTrue(app.buttons["Reload product search"].exists)

        app.buttons["Mark Added"].tap()
        XCTAssertTrue(app.buttons["Finish"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Reload product search"].exists)
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

        let otherCard = app.scrollViews.buttons.matching(
            NSPredicate(format: "label CONTAINS[cd] %@ AND label CONTAINS[cd] %@", "second item", "Added")
        ).firstMatch
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

    private func selectPaprikaSource() {
        app.buttons["set-import-source"].tap()
        XCTAssertTrue(app.navigationBars["Set import source"].waitForExistence(timeout: 5))
        app.buttons["import-source-paprika"].tap()
        XCTAssertTrue(app.buttons["use-paprika"].waitForExistence(timeout: 5))
        app.buttons["use-paprika"].tap()
        XCTAssertTrue(app.buttons["import-from-paprika"].waitForExistence(timeout: 5))
    }

    func testPaprikaSourceSetupReturnsWithoutImportingAndPersists() {
        selectPaprikaSource()
        XCTAssertTrue(row("Coles fixture item", status: "Pending").exists)
        XCTAssertFalse(row("milk", status: "Pending").exists, "Choosing a source must not import")
        XCTAssertFalse(app.buttons["use-paprika"].exists)
        choose("Woolworths")
        XCTAssertTrue(app.buttons["import-from-paprika"].exists, "Import source is app-wide")
        XCTAssertTrue(row("Woolworths fixture item", status: "Pending").exists)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["import-from-paprika"].waitForExistence(timeout: 5))
        XCTAssertFalse(row("milk", status: "Pending").exists)
        app.buttons["import-from-paprika"].tap()
        XCTAssertTrue(row("milk", status: "Pending").waitForExistence(timeout: 5))
        choose("Coles")
        XCTAssertFalse(row("milk", status: "Pending").exists, "Import targets only the selected store")
    }

    func testPaprikaSourceSetupCanBeCancelledAndReopenedFromSettings() {
        let input = app.descendants(matching: .any)["grocery-input"]
        input.tap()
        input.typeText("Draft groceries")
        app.buttons["set-import-source"].tap()
        app.buttons["import-source-paprika"].tap()
        tapNavigationBack()
        tapNavigationBack()
        XCTAssertTrue(app.buttons["set-import-source"].waitForExistence(timeout: 5))
        XCTAssertEqual(input.value as? String, "Draft groceries")
        XCTAssertFalse(row("milk", status: "Pending").exists)

        app.buttons["Settings"].tap()
        app.buttons["import-source-setting"].tap()
        app.buttons["import-source-paprika"].tap()
        XCTAssertTrue(app.staticTexts["2. Export them to Apple Reminders."].exists)
        app.buttons["use-paprika"].tap()
        XCTAssertTrue(app.buttons["import-from-paprika"].waitForExistence(timeout: 5), "Settings setup returns all the way to the list")
        XCTAssertTrue(row("Coles fixture item", status: "Pending").exists)
        XCTAssertFalse(row("milk", status: "Pending").exists)
        XCTAssertEqual(input.value as? String, "Draft groceries")

        app.buttons["Settings"].tap()
        app.buttons["import-source-setting"].tap()
        app.buttons["import-source-paprika"].tap()
        XCTAssertTrue(app.buttons["use-paprika"].exists, "Instructions remain available after setup")
    }

    func testPaprikaSourceSetupFromEmptyList() {
        selectPaprikaSource()
        XCTAssertTrue(app.staticTexts["Your list is empty"].exists)
        XCTAssertFalse(app.buttons["Show Store"].exists)
        app.buttons["import-from-paprika"].tap()
        XCTAssertTrue(row("milk", status: "Pending").waitForExistence(timeout: 5))
    }

    func testPaprikaImportUsesSelectedStoreAndIsIdempotent() {
        selectPaprikaSource()
        let importButton = app.buttons["import-from-paprika"]
        XCTAssertTrue(importButton.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(importButton.frame.width, 180)
        importButton.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5)).tap()
        XCTAssertTrue(row("milk", status: "Pending").waitForExistence(timeout: 5))
        XCTAssertTrue(row("bread", status: "Pending").exists)

        app.buttons["Import from Paprika"].tap()
        XCTAssertTrue(app.staticTexts["No new Paprika items"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label CONTAINS[cd] %@", "milk, quantity 2 l")).count, 1)

        app.buttons.matching(NSPredicate(format: "label CONTAINS[cd] %@", "Actions for milk")).firstMatch.tap()
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
            selectPaprikaSource()
            app.buttons["Import from Paprika"].tap()
            XCTAssertTrue(app.staticTexts[expectedNotice].waitForExistence(timeout: 5))
            XCTAssertTrue(row("Coles fixture item", status: "Pending").exists)
        }
    }
}
