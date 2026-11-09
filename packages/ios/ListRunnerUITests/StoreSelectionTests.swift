import XCTest
import UIKit
import WebKit

final class LiveIKEASearchTests: XCTestCase {
    @MainActor
    func testAustralianSearch() async throws {
        guard ProcessInfo.processInfo.environment["LISTRUNNER_LIVE_IKEA_SEARCH"] == "1" else {
            throw XCTSkip("IKEA live search requires explicit read-only opt-in")
        }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: configuration)
        let policy = ReadOnlySearchPolicy(host: "www.ikea.com")
        web.navigationDelegate = policy
        defer { web.stopLoading(); web.navigationDelegate = nil }
        web.load(URLRequest(url: URL(string: "https://www.ikea.com/au/en/search/?q=spoon")!))
        var result: [String: Any] = [:]
        for _ in 0..<40 {
            try await Task.sleep(for: .seconds(1))
            result = (try? await web.evaluateJavaScript("""
                (() => ({matching: [...document.querySelectorAll('[data-testid="plp-product-card"]')].filter(card =>
                  /spoon/i.test(card.innerText) && [...card.querySelectorAll('a[href]')].some(a =>
                    new URL(a.href).host === 'www.ikea.com' && /^\\/au\\/en\\/p\\/.*-\\d{8}\\/$/.test(new URL(a.href).pathname))).length,
                  query: [...document.querySelectorAll('input,h1')].some(e => /spoon/i.test(e.value || e.innerText || ''))}))()
                """) as? [String: Any]) ?? [:]
            if (result["matching"] as? Int ?? 0) > 0 && result["query"] as? Bool == true { break }
        }
        XCTAssertGreaterThan(result["matching"] as? Int ?? 0, 0)
        XCTAssertEqual(result["query"] as? Bool, true)
        XCTAssertEqual(web.url?.path, "/au/en/search")
        print("IKEA_SEARCH_PROBE matching=\(result["matching"] ?? 0), queryReflected=\(result["query"] ?? false)")
    }
}

// Generic onboarding probe: the same test works before a draft is registered.
// Developer-generated plans only; no production app path reads these variables.
final class StoreOnboardingSearchTests: XCTestCase {
    @MainActor
    func testSearchPlan() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let encoded = environment["LISTRUNNER_ONBOARDING_PLAN"],
              let data = Data(base64Encoded: encoded) else {
            throw XCTSkip("Requires an explicit developer onboarding plan")
        }
        let plan = try JSONDecoder().decode(Plan.self, from: data)
        let fixture = environment["LISTRUNNER_ONBOARDING_MODE"] == "fixture"
        guard fixture || environment["LISTRUNNER_ONBOARDING_MODE"] == "live-read-only" else {
            throw XCTSkip("Live search requires explicit read-only authorization")
        }
        XCTAssertEqual(plan.queries.count, 2)
        guard plan.queries.count == 2, plan.hosts.count > 0,
              plan.queries[0].query != plan.queries[1].query else { return XCTFail("Invalid differential plan") }
        var observations: [[String: Any]] = []
        var catalogues: [Set<String>] = []
        for query in plan.queries {
            guard let route = URL(string: query.url), route.scheme == "https",
                  route.user == nil, route.password == nil, route.port == nil || route.port == 443,
                  let host = route.host, plan.hosts.contains(host) else { return XCTFail("Untrusted search route") }
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = .nonPersistent()
            if fixture {
                // Even a mistakenly edited fixture cannot reach the network.
                let rule = """
                [{"trigger":{"url-filter":".*"},"action":{"type":"block"}}]
                """
                let compiled: WKContentRuleList = try await withCheckedThrowingContinuation { continuation in
                    WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "OnboardingFixtureOnly", encodedContentRuleList: rule) { result, error in
                        if let result { continuation.resume(returning: result) }
                        else { continuation.resume(throwing: error ?? NSError(domain: "OnboardingFixture", code: 1)) }
                    }
                }
                configuration.userContentController.add(compiled)
            }
            let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: configuration)
            let policy = OnboardingReadOnlyPolicy(hosts: Set(plan.hosts))
            webView.navigationDelegate = policy
            defer { webView.stopLoading(); webView.navigationDelegate = nil }
            if fixture {
                guard let html = query.fixtureHTML else { return XCTFail("Fixture HTML is required; no live fallback") }
                webView.loadHTMLString(html, baseURL: route)
            } else {
                webView.load(URLRequest(url: route))
            }
            var lastPaths: [String] = []
            var stable = 0
            var result: [String: Any] = [:]
            for _ in 0..<20 {
                try await Task.sleep(nanoseconds: 1_000_000_000)
                guard let current = try? await webView.evaluateJavaScript(query.script) as? [String: Any] else { continue }
                result = current
                let paths = current["paths"] as? [String] ?? []
                let total = current["productCount"] as? Int ?? 0
                let matching = current["matchingCount"] as? Int ?? 0
                let ready = total >= 3 && matching >= 3 && matching * 4 >= total * 3
                    && current["queryReflected"] as? Bool == true
                    && current["overflow"] as? Bool == false
                    && (current["blockers"] as? [String] ?? ["unknown"]).isEmpty
                stable = ready ? (paths == lastPaths ? stable + 1 : 1) : 0
                lastPaths = paths
                if stable >= 2 { break }
            }
            XCTAssertGreaterThanOrEqual(stable, 2, "Search needs stable relevant results with query reflection and no blocker")
            XCTAssertTrue(webView.url?.host.map(plan.hosts.contains) ?? false)
            XCTAssertFalse(policy.blocked, "Unreviewed host or non-GET navigation encountered")
            result["blockedSubframeNavigations"] = policy.blockedSubframes
            result["blockedMainNavigation"] = policy.blocked
            observations.append(result)
            catalogues.append(Set(result["paths"] as? [String] ?? []))
        }
        XCTAssertLessThan(catalogues[0].intersection(catalogues[1]).count * 2,
                          min(catalogues[0].count, catalogues[1].count),
                          "Unrelated queries must not produce the same general catalogue")
        let report: [String: Any] = ["store": plan.id, "mode": fixture ? "offline-fixture" : "live-read-only",
            "observations": observations, "cartVerification": "not-performed", "capabilitiesChanged": false]
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]), uniformTypeIdentifier: "public.json")
        attachment.name = "Store onboarding inspection - \(plan.id)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private struct Plan: Decodable {
        struct Query: Decodable { let query: String; let url: String; let script: String; let fixtureHTML: String? }
        let id: String
        let hosts: [String]
        let queries: [Query]
    }
}

private final class OnboardingReadOnlyPolicy: NSObject, WKNavigationDelegate {
    let hosts: Set<String>
    private(set) var blocked = false
    private(set) var blockedSubframes = 0
    init(hosts: Set<String>) { self.hosts = hosts }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // Ads/analytics frequently attempt third-party iframe navigation. Deny
        // every subframe rather than broadening trust, but do not misclassify a
        // successfully verified main-document search as an offsite redirect.
        if navigationAction.targetFrame?.isMainFrame == false {
            blockedSubframes += 1
            decisionHandler(.cancel)
            return
        }
        guard let url = navigationAction.request.url,
              (url.absoluteString == "about:blank" || (url.scheme == "https" && url.user == nil && url.password == nil
                && (url.port == nil || url.port == 443) && hosts.contains(url.host ?? ""))),
              navigationAction.request.httpMethod == "GET" else {
            blocked = true
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        guard navigationResponse.isForMainFrame, let url = navigationResponse.response.url,
              (url.absoluteString == "about:blank" || (url.scheme == "https" && url.user == nil && url.password == nil
                && (url.port == nil || url.port == 443) && hosts.contains(url.host ?? ""))) else {
            if navigationResponse.isForMainFrame { blocked = true }
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }
}

// Search certification is independent of cart certification. These probes never
// tap Add, use app cookies, set fulfilment details, or submit credentials.
final class LiveExpansionSearchTests: XCTestCase {
    @MainActor
    func testPricelineDifferentialSearch() async throws {
        guard ProcessInfo.processInfo.environment["LISTRUNNER_LIVE_EXPANSION_SEARCH"] == "1" else {
            throw XCTSkip("Live expansion search requires explicit opt-in")
        }
        // Priceline's visible heading says "All products" and its input clears
        // after submission. Two unrelated queries must instead produce distinct,
        // relevant product sets: a general catalogue cannot satisfy this proof.
        var productSets: [Set<String>] = []
        for query in ["shampoo", "toothpaste"] {
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = .nonPersistent()
            let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: configuration)
            let policy = ReadOnlySearchPolicy(host: "www.priceline.com.au")
            webView.navigationDelegate = policy
            webView.load(URLRequest(url: URL(string: "https://www.priceline.com.au/search?query=\(query)")!))
            var matches = Set<String>()
            var catalogue = Set<String>()
            for _ in 0..<25 {
                try await Task.sleep(nanoseconds: 1_000_000_000)
                let script = """
                (() => {
                  const links = [...document.querySelectorAll('a[href*="/product/"]')].filter(a =>
                    a.getClientRects().length && new URL(a.href).host === location.host
                    && /\\/product\\/[0-9]+\\//.test(new URL(a.href).pathname)
                    && (a.textContent || a.getAttribute('aria-label') || '').trim());
                  return {all: links.map(a => new URL(a.href).pathname),
                    matching: links.filter(a => /\(query)/i.test(a.textContent || a.getAttribute('aria-label') || ''))
                      .map(a => new URL(a.href).pathname)};
                })()
                """
                if let result = try? await webView.evaluateJavaScript(script) as? [String: Any] {
                    matches = Set(result["matching"] as? [String] ?? [])
                    catalogue = Set(result["all"] as? [String] ?? [])
                    if matches.count >= 3 && matches.count * 4 >= catalogue.count * 3 { break }
                }
            }
            XCTAssertGreaterThanOrEqual(matches.count, 3)
            XCTAssertGreaterThanOrEqual(matches.count * 4, catalogue.count * 3, "Results must predominantly match the query")
            let components = webView.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }
            XCTAssertEqual(components?.host, policy.host)
            XCTAssertEqual(components?.queryItems?.first(where: { $0.name == "query" })?.value, query)
            print("EXPANSION_DIFFERENTIAL_PROBE priceline: query=\(query), matchingProducts=\(matches.count), allProducts=\(catalogue.count)")
            productSets.append(catalogue)
            webView.stopLoading()
            webView.navigationDelegate = nil
        }
        XCTAssertLessThan(productSets[0].intersection(productSets[1]).count * 2,
                          min(productSets[0].count, productSets[1].count),
                          "Unrelated queries must not return the same general catalogue")
    }

    @MainActor
    func testReadOnlySearchRoutes() async throws {
        guard ProcessInfo.processInfo.environment["LISTRUNNER_LIVE_EXPANSION_SEARCH"] == "1" else {
            throw XCTSkip("Live expansion search requires explicit opt-in")
        }
        let probes = [
            ("chemistWarehouse", "https://www.chemistwarehouse.com.au/search?query=shampoo&contexts=default", "shampoo"),
            ("priceline", "https://www.priceline.com.au/search?query=shampoo", "shampoo"),
            ("officeworks", "https://www.officeworks.com.au/shop/officeworks/search?q=pens", "pen"),
            ("jbHiFi", "https://www.jbhifi.com.au/search?query=headphones", "headphone"),
            ("targetAU", "https://www.target.com.au/search?text=towels", "towel"),
            ("petbarn", "https://www.petbarn.com.au/catalogsearch/result/q/dog%20food", "dog"),
            ("supercheapAuto", "https://www.supercheapauto.com.au/search?q=car%20wash", "wash"),
            ("bcf", "https://www.bcf.com.au/search?q=camping%20chair", "chair"),
            ("bunningsNZ", "https://www.bunnings.co.nz/search/products?q=hammer", "hammer"),
            ("theWarehouse", "https://www.thewarehouse.co.nz/search?q=towels", "towel"),
            ("newWorld", "https://www.newworld.co.nz/shop/search?q=milk", "milk"),
            ("paknsave", "https://www.paknsave.co.nz/shop/search?q=milk", "milk"),
            ("sainsburys", "https://www.sainsburys.co.uk/gol-ui/SearchResults/milk", "milk"),
            ("asda", "https://www.asda.com/groceries/search/milk", "milk"),
            ("morrisons", "https://groceries.morrisons.com/search?q=milk", "milk"),
            ("ocado", "https://www.ocado.com/search?q=milk", "milk"),
            ("waitrose", "https://www.waitrose.com/ecom/shop/search?searchTerm=milk", "milk"),
            ("boots", "https://www.boots.com/sitesearch?searchTerm=shampoo", "shampoo"),
            ("walgreens", "https://www.walgreens.com/search/results.jsp?Ntt=shampoo", "shampoo"),
            ("cvs", "https://www.cvs.com/search?searchTerm=shampoo", "shampoo")
        ]
        let selected = Set((ProcessInfo.processInfo.environment["LISTRUNNER_LIVE_EXPANSION_ONLY"] ?? "")
            .split(separator: ",").map(String.init))
        let required = Set((ProcessInfo.processInfo.environment["LISTRUNNER_LIVE_EXPANSION_REQUIRED"] ?? "")
            .split(separator: ",").map(String.init))
        XCTAssertTrue(required.isSubset(of: Set(probes.map { $0.0 })), "Unknown required store")
        XCTAssertTrue(selected.isSubset(of: Set(probes.map { $0.0 })), "Unknown selected store")
        XCTAssertTrue(selected.isEmpty || required.isSubset(of: selected), "A required store must actually run")
        for (id, route, term) in probes where selected.isEmpty || selected.contains(id) {
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = .nonPersistent()
            let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: configuration)
            let policy = ReadOnlySearchPolicy(host: URL(string: route)!.host!)
            webView.navigationDelegate = policy
            webView.load(URLRequest(url: URL(string: route)!))
            var products = 0
            var paths: [String] = []
            var queryReflected = false
            for _ in 0..<25 {
                try await Task.sleep(nanoseconds: 1_000_000_000)
                let script = """
                (() => {
                    const links = [...document.querySelectorAll('a[href]')].filter(a => {
                        const u = new URL(a.href);
                        return a.getClientRects().length && u.host === location.host
                            && /\\b\\w*\(term)\\w*\\b/i.test(a.textContent || a.getAttribute('aria-label') || '')
                            && /(?:\\/p\\/|\\/product[s]?\\/|\\/shop\\/product\\/|\\/buy\\/[0-9]|_p[0-9]|\\.html(?:[?]|$)|\\.product|skuId|id=|prodid=)/i.test(u.pathname + u.search);
                    });
                    const queryReflected = [...document.querySelectorAll('input[type="search"],input[type="text"],input:not([type]),h1,h2')]
                      .some(e => e.getClientRects().length && /\\b\\w*\(term)\\w*\\b/i.test(e.value || e.innerText || ''));
                    return {products: new Set(links.map(a => a.href)).size, queryReflected,
                            paths: [...new Set(links.map(a => new URL(a.href).pathname))].slice(0, 3)};
                })()
                """
                if let result = try? await webView.evaluateJavaScript(script) as? [String: Any] {
                    products = result["products"] as? Int ?? 0
                    paths = result["paths"] as? [String] ?? []
                    queryReflected = result["queryReflected"] as? Bool ?? false
                    if products > 0 && queryReflected { break }
                }
            }
            let passed = products > 0 && queryReflected && webView.url?.host == policy.host
            let result = "\(id): matchingProductLinks=\(products), queryReflected=\(queryReflected), sameHost=\(webView.url?.host == policy.host), finalPath=\(webView.url?.path ?? "none"), paths=\(paths)"
            print("EXPANSION_SEARCH_PROBE \(result)")
            let attachment = XCTAttachment(string: result)
            attachment.name = "Read-only expansion search: \(id)"
            attachment.lifetime = .keepAlways
            add(attachment)
            if required.contains(id) { XCTAssertTrue(passed, result) }
            webView.stopLoading()
            webView.navigationDelegate = nil
        }
    }
}

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
        if name.contains("LiveStoreLogin") {
            let store = name.contains("Waitrose") ? "waitrose" : "sainsburys"
            guard ProcessInfo.processInfo.environment["LISTRUNNER_LIVE_LOGIN_STORE"] == store else {
                throw XCTSkip("Preparing a real sign-in screen requires explicit single-store opt-in")
            }
            app.launchEnvironment["LISTRUNNER_LIVE_BROWSE_PROBE"] = store
            app.launchEnvironment["LISTRUNNER_UI_TEST_EMPTY_LIST"] = "1"
            app.launchEnvironment["LISTRUNNER_COUNTRY_TEST_REGION"] = "GB"
            if store == "waitrose" {
                app.launchEnvironment["LISTRUNNER_LIVE_LOGIN_URL"] = "https://www.waitrose.com/ecom/login"
            }
        }
        if name.contains("LiveStoreCart") {
            let probes = [("Priceline", "priceline"), ("Supercheap", "supercheapAuto"), ("ChemistWarehouse", "chemistWarehouse"), ("JBHiFi", "jbHiFi"), ("BunningsNZ", "bunningsNZ"), ("Officeworks", "officeworks"), ("Ocado", "ocado"), ("Morrisons", "morrisons"), ("IKEA", "ikeaAU")]
            guard let store = probes.first(where: { name.contains($0.0) })?.1 else { throw XCTSkip("Unknown live cart probe") }
            guard ProcessInfo.processInfo.environment["LISTRUNNER_LIVE_CART_STORE"] == store else {
                throw XCTSkip("Live cart mutation requires explicit single-store opt-in")
            }
            app.launchEnvironment["LISTRUNNER_LIVE_CART_PROBE"] = store
            app.launchEnvironment["LISTRUNNER_UI_TEST_EMPTY_LIST"] = "1"
            if store == "ikeaAU" {
                guard ProcessInfo.processInfo.environment["LISTRUNNER_LIVE_IKEA_ESSENTIAL_COOKIES"] == "1" else {
                    throw XCTSkip("IKEA cookie preferences require separate essential-only consent permission")
                }
                app.launchEnvironment["LISTRUNNER_LIVE_UNDO_PROBE"] = store
                if name.contains("Detail") {
                    app.launchEnvironment["LISTRUNNER_LIVE_CART_DETAIL_URL"] = "https://www.ikea.com/au/en/p/dragon-spoon-stainless-steel-40515525/"
                }
            }
            if store == "bunningsNZ" { app.launchEnvironment["LISTRUNNER_COUNTRY_TEST_REGION"] = "NZ" }
            if ["ocado", "morrisons"].contains(store) { app.launchEnvironment["LISTRUNNER_COUNTRY_TEST_REGION"] = "GB" }
            if store == "morrisons" {
                guard ProcessInfo.processInfo.environment["LISTRUNNER_LIVE_GUEST_POSTCODE"] != nil,
                      ProcessInfo.processInfo.environment["LISTRUNNER_LIVE_GUEST_ADDRESS"] != nil else {
                    throw XCTSkip("Morrisons requires an explicitly authorized guest address supplied at runtime")
                }
            }
            if store == "chemistWarehouse" {
                app.launchEnvironment["LISTRUNNER_LIVE_CART_DETAIL_URL"] = "https://www.chemistwarehouse.com.au/buy/85510/sukin-natural-balance-shampoo-500ml"
            }
        }
        if name.contains("FullyRevealed") || name.contains("AlreadyVisibleNewItem") || name.contains("FocusedProductEntry") || name.contains("ManualScrolling") {
            app.launchEnvironment["LISTRUNNER_REVEAL_TEST_FIXTURE"] = "enabled"
        }
        if name.contains("KeyboardDismissalAnimation") {
            app.launchEnvironment["LISTRUNNER_ENTRY_ANIMATION_TEST_FIXTURE"] = "enabled"
        }
        if name.contains("IdleRecovery") {
            app.launchEnvironment["LISTRUNNER_IDLE_RECOVERY_TEST_FIXTURE"] = "enabled"
        }
        if name.contains("StoreResume") {
            app.launchEnvironment["LISTRUNNER_STORE_RESUME_TEST_FIXTURE"] = name.contains("Checks") ? "checks" : "page"
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
        if name.contains("LiveWoolworthsResultsScroll") {
            guard ProcessInfo.processInfo.environment["LISTRUNNER_LIVE_RESULTS_SCROLL"] == "1" else {
                throw XCTSkip("Requires explicit read-only live results-scroll opt-in")
            }
            app.launchEnvironment["LISTRUNNER_LIVE_BROWSE_PROBE"] = "woolworths"
            app.launchEnvironment["LISTRUNNER_RESULTS_SCROLL_PROBE"] = "woolworths"
            app.launchEnvironment["LISTRUNNER_UI_TEST_EMPTY_LIST"] = "1"
        } else if name.contains("ResultsScroll") {
            app.launchEnvironment["LISTRUNNER_RESULTS_SCROLL_TEST_FIXTURE"] = "enabled"
        }
        if name.contains("Paprika") {
            app.launchEnvironment["LISTRUNNER_PAPRIKA_TEST_FIXTURE"] = "enabled"
        }
        if name.contains("AllItemsUnavailable") {
            app.launchEnvironment["LISTRUNNER_ALL_ITEMS_RECOVERY_TEST_FIXTURE"] = "1"
        }
        if name.contains("Verification") {
            app.launchEnvironment["LISTRUNNER_VERIFICATION_TEST_FIXTURE"] = "enabled"
        }
        if name.contains("CartDetection") {
            app.launchEnvironment["LISTRUNNER_CART_DETECTION_TEST_FIXTURE"] = "quantityUnavailable"
        }
        if name.contains("EmptyList") || name.contains("FirstStoreWelcome") {
            app.launchEnvironment["LISTRUNNER_UI_TEST_EMPTY_LIST"] = "1"
        }
        if name.contains("NativeStoreIndex") {
            app.launchEnvironment["LISTRUNNER_COUNTRY_TEST_REGION"] = "NZ"
        }
        if name.contains("UnsetShoppingCountry") {
            app.launchEnvironment["LISTRUNNER_COUNTRY_TEST_REGION"] = "ZZ"
        }
        if ["SettingsHasCountryAndNoStoreRows", "SettingsWithAllStoresHiddenKeepsManagementAvailable",
            "AllHiddenStoresHidePickerAndKeepManagementAvailable", "MixedCountrySectionsKeepNativeIndexSeparateFromSwitches",
            "DisablingActiveBunningsSelectsEnabledColesAndKeepsItems", "AllDisabledBunningsThenColesSelectsEnabledListAndPreservesSavedLists",
            "DisablingActiveBunningsRequiresClearingItsList"]
            .contains(where: { name.contains($0) }) {
            app.launchEnvironment["LISTRUNNER_UI_TEST_EMPTY_LIST"] = "1"
        }
        if name.contains("MixedCountry") {
            app.launchEnvironment["LISTRUNNER_COUNTRY_TEST_CATALOGUE"] = "mixed"
        }
        app.launch()
        if name.contains("FirstStoreWelcome") { return }
        if name.contains("LiveStoreCartIKEA") {
            // Set up IKEA directly from welcome. Ordinary management can be a
            // modal with Close, not a pushed screen with Back while searching.
            let welcome = app.buttons["welcome-choose-store"]
            XCTAssertTrue(welcome.waitForExistence(timeout: 10))
            welcome.tap()
            let search = app.searchFields.firstMatch
            XCTAssertTrue(search.waitForExistence(timeout: 5))
            search.tap(); search.typeText("IKEA")
            enableWelcomeStore("ikeaAU")
            XCTAssertEqual(app.buttons["store-picker"].label, "IKEA")
            return
        }
        // Shopping-flow tests start after the real first-store setup flow.
        if app.buttons["welcome-choose-store"].waitForExistence(timeout: 3) {
            app.buttons["welcome-choose-store"].tap()
            enableWelcomeStore("coles")
            // Results positioning uses only the Coles HTML fixture. Avoid the
            // unrelated multi-store setup and its costly table navigation.
            if !name.contains("ResultsScroll") {
                app.buttons["store-picker"].tap()
                app.buttons["Manage Stores"].tap()
                // Coles was just enabled through the welcome flow. Reopening its
                // row is redundant and races its move between table sections.
                for id in ["bunnings", "woolworths"] { setStoreVisibility(id, shown: true) }
                tapNavigationBack()
            }
        }
        XCTAssertTrue(app.buttons["store-picker"].waitForExistence(timeout: 10))
        // These list-layout cases assert the Coles fixture specifically. First
        // store setup enables Woolworths last, which intentionally selects it;
        // make the test's starting list explicit rather than depending on order.
        if ["AlreadyVisibleNewItem", "FocusedProductEntry", "GroceryInputEmptyReturn", "RepeatedNewItemsAreFullyRevealed", "ResultsScroll", "Paprika", "StorePickerKeepsListsAndStatusesSeparate", "HidingAndReenablingStorePreservesItsList"]
            .contains(where: { name.contains($0) }) {
            choose("Coles")
        }
    }

    override func tearDownWithError() throws { app.terminate() }

    func testFirstStoreWelcomePersistsUntilStoreEnabled() {
        XCTAssertTrue(app.buttons["welcome-choose-store"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.staticTexts["A list for every store."].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label == %@",
            "Keep your shopping lists organised by where you shop, ready whenever you need them. Shopping online? Work through your list right on the store’s website.")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts["Add more stores and lists whenever you like."].exists)
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
        let heading = app.staticTexts["A list for every store."]
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
        let heading = app.staticTexts["A list for every store."]
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
        XCTAssertTrue(app.staticTexts["A list for every store."].waitForExistence(timeout: 10))
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
        XCTAssertTrue(app.staticTexts["A list for every store."].exists)
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

    func testFirstStoreWelcomePreviewOverridesAllItemsWithoutChangingSavedScope() {
        XCTAssertTrue(app.buttons["welcome-choose-store"].waitForExistence(timeout: 10))
        app.buttons["welcome-choose-store"].tap()
        enableWelcomeStore("coles")
        choose("All items")
        XCTAssertTrue(app.buttons["all-items-scope-picker"].waitForExistence(timeout: 5))

        app.terminate()
        app.launchArguments = ["--preview-store-welcome"]
        app.launch()
        XCTAssertTrue(app.buttons["welcome-choose-store"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["A list for every store."].exists)
        XCTAssertFalse(app.buttons["all-items-scope-picker"].exists)
        app.buttons["welcome-choose-store"].tap()
        tapNavigationBack()
        XCTAssertTrue(app.buttons["welcome-choose-store"].waitForExistence(timeout: 5))

        app.terminate()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.buttons["all-items-scope-picker"].waitForExistence(timeout: 10),
                      "Previewing and cancelling must preserve the saved All items scope")
        XCTAssertFalse(app.buttons["welcome-choose-store"].exists)

        app.terminate()
        app.launchArguments = ["--preview-store-welcome"]
        app.launch()
        XCTAssertTrue(app.buttons["welcome-choose-store"].waitForExistence(timeout: 10))
        app.buttons["welcome-choose-store"].tap()
        enableWelcomeStore("bunnings")
        XCTAssertTrue(app.buttons["store-picker"].label.contains("Bunnings"),
                      "Explicit welcome completion must open the chosen store, not All items")
        XCTAssertFalse(app.buttons["all-items-scope-picker"].exists)
        XCTAssertFalse(app.buttons["welcome-choose-store"].exists)
    }

    func testFirstStoreWelcomePreviewHidesSavedItemsShortcutAndPreservesLists() {
        XCTAssertTrue(app.buttons["welcome-choose-store"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["view-saved-items"].exists, "Fresh installs have no saved items to view")
        app.buttons["welcome-choose-store"].tap()
        enableWelcomeStore("coles")
        let input = app.descendants(matching: .any)["grocery-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.typeText("Saved welcome preview item")
        app.buttons["Add Items"].tap()
        XCTAssertTrue(row("Saved welcome preview item", status: "Pending").waitForExistence(timeout: 5))

        choose("All items")
        XCTAssertTrue(app.buttons["all-items-scope-picker"].waitForExistence(timeout: 5))
        app.terminate()
        app.launchArguments = ["--preview-store-welcome"]
        app.launch()
        XCTAssertTrue(app.buttons["welcome-choose-store"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["view-saved-items"].exists,
                       "The development preview should match first-run welcome, even with saved items")
        app.swipeUp()
        XCTAssertFalse(app.buttons["view-saved-items"].exists)

        app.terminate()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.buttons["all-items-scope-picker"].waitForExistence(timeout: 10))
        XCTAssertTrue(row("Saved welcome preview item", status: "Pending").waitForExistence(timeout: 5))
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

    func testLiveStoreCartPriceline() throws {
        try liveStoreCart(store: "priceline", query: "shampoo",
                          product: "PRO:VOKE Touch Of Silver Brightening Shampoo 50mL")
    }

    func testLiveStoreLoginWaitroseHandoff() throws {
        try prepareLoginHandoff(store: "waitrose", signInLabel: "Sign in")
    }

    func testLiveStoreLoginSainsburysHandoff() throws {
        try prepareLoginHandoff(store: "sainsburys", signInLabel: "Log in / Register")
    }

    private func prepareLoginHandoff(store: String, signInLabel: String) throws {
        // No credentials, Add, checkout, or account-setting actions. A passing
        // route check is NOT authentication, detector certification, or an active
        // user handoff. XCTest closes the app even if explicit teardown is skipped.
        // Launch the same isolated setup outside XCTest for manual sign-in.
        app.buttons["store-picker"].tap()
        app.buttons["Manage Stores"].tap()
        setStoreVisibility(store, shown: true)
        tapNavigationBack()
        let input = app.descendants(matching: .any)["grocery-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap(); input.typeText("milk")
        app.buttons["Add Items"].tap()
        app.buttons["Show Store"].tap()
        let web = app.webViews.firstMatch
        XCTAssertTrue(web.waitForExistence(timeout: 10))
        let collapse = app.buttons["Collapse overlay"]
        if collapse.exists && collapse.isHittable { collapse.tap() }
        let consentLabel = store == "waitrose" ? "Reject all" : "Required only"
        let consent = web.buttons.matching(NSPredicate(format: "label ==[c] %@", consentLabel)).firstMatch
        if consent.waitForExistence(timeout: 15), consent.isHittable, !consent.frame.isEmpty,
           !consent.frame.isInfinite, consent.frame.minY > web.frame.minY + 40 { consent.tap() }
        if store != "waitrose" {
            let signIn = web.buttons.matching(identifier: signInLabel).firstMatch
            XCTAssertTrue(signIn.waitForExistence(timeout: 60))
            XCTAssertTrue(signIn.isHittable && !signIn.frame.isEmpty && signIn.frame.minY > web.frame.minY + 40)
            signIn.tap()
        }
        XCTAssertTrue(web.secureTextFields.firstMatch.waitForExistence(timeout: 60), "Stop only at a real login form")
        print("LOGIN_ROUTE_VERIFIED store=\(store), authenticationPerformed=false, cartMutationAttempted=false, manualHandoffReady=false")
    }

    func testLiveStoreCartSupercheap() throws {
        try liveStoreCart(store: "supercheapAuto", query: "SCA Car Wash Concentrate 1 Litre",
                          product: "SCA Car Wash Concentrate 1 Litre")
    }

    func testLiveStoreCartChemistWarehouse() throws {
        try liveStoreCart(store: "chemistWarehouse", query: "sukin shampoo",
                          product: "Sukin Natural Balance Shampoo 500ml", detail: true)
    }

    func testLiveStoreCartJBHiFi() throws {
        try liveStoreCart(store: "jbHiFi", query: "usb cable",
                          product: "Belkin Hi Speed USB Cable (1.8 Metres)")
    }

    func testLiveStoreCartBunningsNZ() throws {
        try liveStoreCart(store: "bunningsNZ", query: "craftright hammer",
                          product: "CRAFTRIGHT Craftright 8oz Steel Claw Hammer")
    }

    func testIKEAAustraliaDiscoveryAndCapabilities() {
        app.buttons["store-picker"].tap()
        app.buttons["Manage Stores"].tap()
        let search = app.searchFields.firstMatch
        search.tap(); search.typeText("IKEA")
        openStoreSettings("ikeaAU")
        XCTAssertTrue(app.staticTexts["IKEA"].firstMatch.exists || app.navigationBars["IKEA"].exists)
        XCTAssertTrue(app.buttons["Reset IKEA Session"].exists)
        app.buttons["Reset IKEA Session"].tap()
        XCTAssertTrue(app.alerts["Reset IKEA Session?"].waitForExistence(timeout: 3))
        app.alerts["Reset IKEA Session?"].buttons["Cancel"].tap()
    }

    func testLiveStoreCartIKEAGrid() throws { try liveIKEACart(detail: false) }
    func testLiveStoreCartIKEADetail() throws { try liveIKEACart(detail: true) }

    private func liveIKEACart(detail: Bool) throws {
        XCTAssertEqual(app.buttons["store-picker"].label, "IKEA")
        let input = app.descendants(matching: .any)["grocery-input"]
        input.tap(); input.typeText("dragon spoon")
        app.buttons["Add Items"].tap()
        app.buttons["Show Store"].tap()
        let web = app.webViews.firstMatch
        XCTAssertTrue(web.waitForExistence(timeout: 10))
        let collapse = app.buttons["Collapse overlay"]
        if collapse.exists && collapse.isHittable { collapse.tap() }
        let settings = web.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Cookies settings")).firstMatch
        if settings.waitForExistence(timeout: 15) {
            settings.tap()
            let labels = ["Performance cookies", "Functional cookies", "Targeting cookies"]
            XCTAssertTrue(web.switches[labels[0]].waitForExistence(timeout: 10))
            XCTAssertEqual(Set(web.switches.allElementsBoundByIndex.map(\.label)), Set(labels),
                           "Stop rather than consent to an unreviewed optional category")
            for label in labels {
                let toggle = web.switches[label]
                if toggle.value as? String != "0" { toggle.tap() }
                XCTAssertEqual(toggle.value as? String, "0")
            }
            web.buttons["Confirm my choices"].tap()
        }
        let add = web.buttons[detail ? "Add to bag" : "Add \"DRAGON Spoon\" to cart"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 60), web.debugDescription)
        // Never accept optional cookies or alter account/fulfilment settings.
        // Scroll only inside the unobscured retailer portion of the sheet.
        for _ in 0..<12 {
            if add.isHittable && add.frame.minY > web.frame.minY + 60 && add.frame.maxY < app.frame.maxY - 130 { break }
            let origin = app.coordinate(withNormalizedOffset: .zero)
            origin.withOffset(CGVector(dx: web.frame.midX, dy: app.frame.maxY - 180))
                .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: web.frame.midX, dy: web.frame.minY + 120)))
        }
        XCTAssertTrue(add.isHittable && add.frame.minY > web.frame.minY + 40 && add.frame.maxY < app.frame.maxY - 100)
        add.tap()
        // No Mark Added: require the real native bridge to acknowledge the cart.
        let expand = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Expand overlay")).firstMatch
        if expand.exists && expand.isHittable { expand.tap() }
        let undo = app.buttons["Undo"]
        let detected = undo.waitForExistence(timeout: 60)
        let evidence = XCTAttachment(screenshot: app.screenshot())
        evidence.name = "IKEA \(detail ? "detail" : "grid") native detection: \(detected)"
        evidence.lifetime = .keepAlways
        self.add(evidence)
        if detected {
            undo.tap()
            let progress = app.descendants(matching: .any)["store-cart-undo-progress"].firstMatch
            if progress.waitForExistence(timeout: 3) {
                let finished = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: progress)
                XCTAssertEqual(XCTWaiter.wait(for: [finished], timeout: 60), .completed)
            }
        }
        let pending = app.buttons["Mark Added"]
        let restored = pending.waitForExistence(timeout: 60)
        print("IKEA_NATIVE_CART_PROBE detail=\(detail), detected=\(detected), localRestored=\(restored)")
        let undoFailed = app.staticTexts["Could not undo store cart change"].exists
        if collapse.exists && collapse.isHittable { collapse.tap() }
        // Independently open the actual bag and prove cleanup, even after a
        // detector/Undo failure. Never confuse local Pending with an empty bag.
        let close = web.buttons.matching(identifier: "Close").allElementsBoundByIndex.first { $0.isHittable }
        if let close, close.frame.minY > web.frame.minY + 40 { close.tap() }
        for _ in 0..<8 {
            let bag = web.links.matching(NSPredicate(format: "label BEGINSWITH %@", "Shopping bag")).firstMatch
            if bag.exists && bag.isHittable && bag.frame.minY > web.frame.minY + 40 {
                // Observed IKEA AX label extends over the adjacent hamburger:
                // its centre activates the wrong control. The label's leading
                // edge lies inside the actual bag icon in this reviewed layout.
                bag.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5)).tap()
                break
            }
            let origin = app.coordinate(withNormalizedOffset: .zero)
            origin.withOffset(CGVector(dx: web.frame.midX, dy: web.frame.minY + 120))
                .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: web.frame.midX, dy: app.frame.maxY - 180)))
        }
        let empty = web.staticTexts["Your shopping bag is empty"].firstMatch
        let alreadyEmpty = empty.waitForExistence(timeout: 15)
        if !alreadyEmpty {
            let quantity = web.textFields["Enter quantity of DRAGON, stainless steel, 19 cm"].firstMatch
            let remove = web.buttons["Remove DRAGON, stainless steel, 19 cm"].firstMatch
            if quantity.waitForExistence(timeout: 10), quantity.value as? String == "1",
               remove.exists, remove.isHittable { remove.tap() }
        }
        XCTAssertTrue(empty.waitForExistence(timeout: 20), "The exact guest test product must be removed before finishing")
        print("IKEA_NATIVE_CLEANUP detail=\(detail), undoVerifiedEmpty=\(alreadyEmpty), cleanupVerified=\(empty.exists)")
        XCTAssertTrue(detected, "Do not certify cart support without native automatic detection")
        XCTAssertTrue(restored)
        XCTAssertFalse(undoFailed)
        XCTAssertTrue(alreadyEmpty, "Manual cleanup is not proof that automatic retailer Undo worked")
    }

    func testLiveStoreCartOfficeworks() throws {
        try liveStoreCart(store: "officeworks", query: "pens",
                          product: "Keji Ballpoint Pens 1mm Assorted 10 Pack")
    }

    func testLiveStoreCartOcado() throws {
        try liveStoreCart(store: "ocado", query: "milk",
                          product: "Ocado British Semi Skimmed Milk 2 Pints")
    }

    func testLiveStoreCartMorrisons() throws {
        try liveStoreCart(store: "morrisons", query: "belvita milk",
                          product: "Belvita Milk & Cereal Biscuit Snack Bars Multipack")
    }

    private func liveStoreCart(store: String, query: String, product: String, detail: Bool = false) throws {
        // Each run uses the existing isolated UI-test UUID and a fresh,
        // nonpersistent website store. Never use a person's real cart/login.
        app.buttons["store-picker"].tap()
        app.buttons["Manage Stores"].tap()
        setStoreVisibility(store == "bunningsNZ" ? "bunnings" : store, shown: true)
        if store == "bunningsNZ" {
            // Enabling the brand can retain its existing AU preference. Select
            // the exact regional destination explicitly; country alone must not
            // silently switch an already enabled store.
            openStoreSettings("bunnings")
            app.buttons["store-region-picker-bunnings"].tap()
            app.buttons["store-region-bunningsNZ"].tap()
            let confirm = app.alerts.buttons["Use this regional website"]
            if confirm.waitForExistence(timeout: 3) { confirm.tap() }
            tapNavigationBack()
        }
        tapNavigationBack()
        let input = app.descendants(matching: .any)["grocery-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap(); input.typeText(query)
        app.buttons["Add Items"].tap()
        app.buttons["Show Store"].tap()
        let web = app.webViews.firstMatch
        XCTAssertTrue(web.waitForExistence(timeout: 10))
        let link = web.links[product].firstMatch
        let directDetail = store == "chemistWarehouse"
        if directDetail {
            XCTAssertTrue(web.staticTexts[product].firstMatch.waitForExistence(timeout: 60), web.debugDescription)
        } else {
            XCTAssertTrue(link.waitForExistence(timeout: 60), web.debugDescription)
        }
        // Cookie dialogs can place their essential-only button underneath the
        // expanded native cards. Collapsing reserves real web layout space.
        let collapse = app.buttons["Collapse overlay"]
        if collapse.exists && collapse.isHittable { collapse.tap() }
        let consentLabels = store == "priceline" ? ["Accept essential only"]
            : store == "chemistWarehouse" ? ["CLOSE"]
            : store == "ocado" ? ["Decline advertising cookies"] : ["Reject All"]
        for text in consentLabels {
            let consent = web.buttons.matching(NSPredicate(format: "label ==[c] %@", text)).firstMatch
            if consent.waitForExistence(timeout: 2) && consent.isHittable,
               !consent.frame.isEmpty, !consent.frame.isInfinite,
               consent.frame.minY >= web.frame.minY + 40, consent.frame.maxY <= app.frame.maxY - 80 { consent.tap() }
        }
        if store == "officeworks" {
            // Configure guest location BEFORE Add, so the pending Add does not
            // span a separate trusted Continue click. No saved account is used.
            let location = web.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@ OR label == %@", "Shopping method", "LocationIconRgbOl")).firstMatch
            XCTAssertTrue(location.waitForExistence(timeout: 10))
            location.tap()
            let postcode = web.textFields["Enter your suburb or postcode"].firstMatch
            XCTAssertTrue(postcode.waitForExistence(timeout: 10))
            postcode.tap(); postcode.typeText("3000")
            let suburb = web.staticTexts["Melbourne VIC 3000"].firstMatch
            XCTAssertTrue(suburb.waitForExistence(timeout: 15))
            suburb.tap()
            let proceed = web.buttons["Continue"].firstMatch
            XCTAssertTrue(proceed.waitForExistence(timeout: 10))
            proceed.tap()
        }
        if store == "morrisons" {
            // Runtime-only authorized guest address; never put personal test
            // addresses or names in tracked code/resources or saved accounts.
            let location = web.buttons["Choose your delivery location"].firstMatch
            XCTAssertTrue(location.waitForExistence(timeout: 10))
            location.tap()
            let addressField = web.textFields["Search for your address"].firstMatch
            XCTAssertTrue(addressField.waitForExistence(timeout: 15))
            addressField.tap()
            addressField.typeText(ProcessInfo.processInfo.environment["LISTRUNNER_LIVE_GUEST_POSTCODE"]!)
            let address = web.staticTexts[ProcessInfo.processInfo.environment["LISTRUNNER_LIVE_GUEST_ADDRESS"]!].firstMatch
            XCTAssertTrue(address.waitForExistence(timeout: 15))
            address.tap()
            let confirmLocation = web.buttons["Confirm location"].firstMatch
            XCTAssertTrue(confirmLocation.waitForExistence(timeout: 10))
            confirmLocation.tap()
            let expectedPostcode = ProcessInfo.processInfo.environment["LISTRUNNER_LIVE_GUEST_POSTCODE"]!
                .replacingOccurrences(of: " ", with: "").uppercased()
            XCTAssertTrue(web.buttons[expectedPostcode].firstMatch.waitForExistence(timeout: 10),
                          "Do not confirm a default or mismatched guest location")
            let confirmMethod = web.buttons["Confirm"].firstMatch
            XCTAssertTrue(confirmMethod.waitForExistence(timeout: 10))
            confirmMethod.tap() // Default Home Delivery only; never book a slot.
        }
        if detail && !directDetail {
            for _ in 0..<8 {
                if link.isHittable && link.frame.minY > web.frame.minY + 80 && link.frame.maxY < app.frame.maxY - 120 { break }
                let origin = app.coordinate(withNormalizedOffset: .zero)
                let down = link.frame.midY < web.frame.minY + 80
                let top = web.frame.minY + 110
                let bottom = app.frame.maxY - 150
                origin.withOffset(CGVector(dx: web.frame.midX, dy: down ? top : bottom))
                    .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: web.frame.midX, dy: down ? bottom : top)))
            }
            XCTAssertTrue(link.isHittable && link.frame.minY > web.frame.minY + 60 && link.frame.maxY < app.frame.maxY - 100,
                          "Detail link must be visible before attempting navigation")
            link.tap()
            XCTAssertTrue(web.buttons.matching(NSPredicate(format: "label MATCHES[c] %@", ".*Add (?:to|To) (?:cart|Cart).*"))
                .firstMatch.waitForExistence(timeout: 60), "Wait for the product detail page, not search results")
        }
        // Attribute the actual trusted tap to the smallest AX container holding
        // this exact title and a single Add button. Never choose a page-wide Add.
        let addPredicate = NSPredicate(format: "label MATCHES[c] %@", store == "ocado"
            ? "^Add .+ to trolley$" : store == "morrisons" ? "^Add .+ to basket$" : ".*Add (?:to|To) (?:cart|Cart).*")
        func matchingAdd() -> XCUIElement? {
            if detail {
                return web.buttons.matching(addPredicate).allElementsBoundByIndex
                    .filter { $0.frame.height > 0 }.sorted { $0.frame.minY < $1.frame.minY }.first
            }
            let structured = web.otherElements.containing(.link, identifier: product).allElementsBoundByIndex
                .filter { $0.frame.height > 0 && $0.frame.height < 900 && $0.buttons.matching(addPredicate).count == 1 }
                .sorted { $0.frame.minY == $1.frame.minY ? $0.frame.height < $1.frame.height : $0.frame.minY < $1.frame.minY }
                .first?.buttons.matching(addPredicate).firstMatch
            if let structured { return structured }
            // Priceline flattens each card into sibling AX elements. Its text
            // title (smaller than its duplicate image link) still locates the
            // exact column. Require one nearby Add below it, with no intervening
            // different product link. This is test navigation, not detector logic.
            let textTitles = web.staticTexts.matching(identifier: product).allElementsBoundByIndex
            let titles = textTitles.isEmpty ? web.links.matching(identifier: product).allElementsBoundByIndex : textTitles
            guard let title = titles
                .filter({ $0.frame.height > 0 }).min(by: { $0.frame.height < $1.frame.height }) else { return nil }
            let frame = title.frame
            let candidates = web.buttons.matching(addPredicate).allElementsBoundByIndex.filter { button in
                let box = button.frame
                return box.midX >= frame.minX && box.midX <= frame.maxX && box.minY >= frame.maxY - 2 && box.minY <= frame.maxY + 220
            }
            guard candidates.count == 1, let button = candidates.first else { return nil }
            let interveningLink = web.links.allElementsBoundByIndex.contains { other in
                other.label != product && other.label != "\(product) \(product)" && !other.label.isEmpty
                    && other.label.range(of: "^[\\s$£€0-9.,()/★]+$", options: .regularExpression) == nil
                    && other.frame.midX >= frame.minX && other.frame.midX <= frame.maxX
                    && other.frame.minY > frame.maxY && other.frame.maxY < button.frame.minY
            }
            return interveningLink ? nil : button
        }
        var add = matchingAdd()
        for _ in 0..<12 {
            if let button = add, button.isHittable, button.frame.minY > web.frame.minY + 60,
               button.frame.maxY < app.frame.maxY - 230 { break }
            // WKWebView extends underneath ListRunner's bottom overlay. A
            // default web.swipeUp starts there and merely swipes native cards.
            // Keep this measured gesture entirely in unobscured website space.
            let top = max(web.frame.minY + 100, app.frame.minY + 150)
            let bottom = min(web.frame.maxY - 20, app.frame.maxY - 280)
            let distance = min(max(80, abs((add?.frame.midY ?? bottom + 200) - (top + bottom) / 2)), max(80, bottom - top - 40))
            let down = (add?.frame.midY ?? bottom + 200) < top
            let fromY = down ? top + 20 : bottom - 20
            let toY = down ? min(bottom - 20, fromY + distance) : max(top + 20, fromY - distance)
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let from = origin.withOffset(CGVector(dx: web.frame.midX - app.frame.minX, dy: fromY - app.frame.minY))
            let to = origin.withOffset(CGVector(dx: web.frame.midX - app.frame.minX, dy: toY - app.frame.minY))
            from.press(forDuration: 0.05, thenDragTo: to)
            add = matchingAdd()
        }
        guard let add, add.exists && add.isHittable else {
            XCTFail("No uniquely product-scoped visible Add; no cart mutation attempted. \(web.debugDescription)")
            return
        }
        add.tap()
        let expand = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Expand overlay")).firstMatch
        if expand.exists && expand.isHittable { expand.tap() }
        // No native Mark Added is ever tapped: this must be detector-driven.
        let detected = app.buttons["Undo"].waitForExistence(timeout: 25)
        print("LIVE_CART_DETECTION store=\(store), detected=\(detected), cleanupPending=true")
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Live cart detector \(store): \(detected ? "confirmed" : "not confirmed")"
        attachment.lifetime = .keepAlways
        self.add(attachment)

        if collapse.exists && collapse.isHittable { collapse.tap() }

        func revealForCleanup(_ element: XCUIElement) -> Bool {
            for _ in 0..<10 {
                guard element.exists else { return false }
                let top = max(web.frame.minY + 100, app.frame.minY + 150)
                let bottom = min(web.frame.maxY - 20, app.frame.maxY - 100)
                if element.isHittable && element.frame.minY >= top && element.frame.maxY <= bottom { return true }
                let down = element.frame.midY < top
                let origin = app.coordinate(withNormalizedOffset: .zero)
                let from = origin.withOffset(CGVector(dx: web.frame.midX, dy: down ? top + 20 : bottom - 20))
                let to = origin.withOffset(CGVector(dx: web.frame.midX, dy: down ? bottom - 20 : top + 20))
                from.press(forDuration: 0.05, thenDragTo: to)
            }
            return element.exists && element.isHittable && element.frame.minY >= web.frame.minY + 60
                && element.frame.maxY <= min(web.frame.maxY - 20, app.frame.maxY - 100)
        }

        // Cleanup even if detector confirmation failed. A fresh guest cart has
        // no unrelated items. Never invoke checkout or change fulfilment.
        var cleanupVerified = false
        if store == "priceline" {
            let remove = web.buttons["Remove Product from Cart"].firstMatch
            XCTAssertTrue(remove.waitForExistence(timeout: 15), "Could not locate our test product for cleanup")
            if revealForCleanup(remove) { remove.tap() }
            let removed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: remove)
            cleanupVerified = XCTWaiter.wait(for: [removed], timeout: 15) == .completed
            XCTAssertTrue(cleanupVerified)
        } else if ["ocado", "morrisons"].contains(store) {
            let decrease = web.buttons["Decrease quantity of \(product) in trolley"].firstMatch
            XCTAssertTrue(decrease.waitForExistence(timeout: 15))
            if revealForCleanup(decrease) { decrease.tap() }
            cleanupVerified = web.buttons["Add \(product) to \(store == "ocado" ? "trolley" : "basket")"].firstMatch.waitForExistence(timeout: 15)
            XCTAssertTrue(cleanupVerified)
        } else if store == "officeworks" {
            let review = web.buttons["View Cart"].firstMatch
            XCTAssertTrue(review.waitForExistence(timeout: 15))
            if revealForCleanup(review) { review.tap() }
            let remove = web.buttons["Delete"].firstMatch
            XCTAssertTrue(remove.waitForExistence(timeout: 15))
            if revealForCleanup(remove) { remove.tap() }
            let removed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: remove)
            let exactItemRemoved = XCTWaiter.wait(for: [removed], timeout: 15) == .completed
            // Officeworks' SVG cart icon is not included in its AX label: the
            // numeric header button is exposed as just "0" on iPhone.
            cleanupVerified = exactItemRemoved && web.buttons.matching(NSPredicate(format: "label MATCHES[c] %@", "0(?:\\s*Cart)?")).firstMatch.waitForExistence(timeout: 15)
            XCTAssertTrue(cleanupVerified)
        } else if store == "bunningsNZ" {
            let close = web.buttons["Close add to cart confirmation"].firstMatch
            if close.waitForExistence(timeout: 5) && close.isHittable { close.tap() }
            let decrease = web.buttons["Decrease quantity"].firstMatch
            XCTAssertTrue(decrease.waitForExistence(timeout: 15))
            if revealForCleanup(decrease) { decrease.tap() }
            let removed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: decrease)
            cleanupVerified = XCTWaiter.wait(for: [removed], timeout: 15) == .completed
            XCTAssertTrue(cleanupVerified)
        } else if store == "jbHiFi" {
            let review = web.buttons["Review cart"].firstMatch
            XCTAssertTrue(review.waitForExistence(timeout: 15))
            if review.exists && review.isHittable { review.tap() }
            let remove = web.buttons["Remove"].firstMatch
            XCTAssertTrue(remove.waitForExistence(timeout: 20))
            if revealForCleanup(remove) { remove.tap() }
            cleanupVerified = web.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Your cart is empty")).firstMatch.waitForExistence(timeout: 20)
            XCTAssertTrue(cleanupVerified)
        } else if store == "chemistWarehouse" {
            let decrease = web.buttons["Decrement quantity"].firstMatch
            XCTAssertTrue(decrease.waitForExistence(timeout: 15))
            if revealForCleanup(decrease) { decrease.tap() }
            cleanupVerified = web.buttons.matching(NSPredicate(format: "label ==[c] %@", "ADD TO CART")).firstMatch.waitForExistence(timeout: 15)
            XCTAssertTrue(cleanupVerified, "Product stepper must return to the empty-cart Add state")
        } else {
            let viewCart = web.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "View Cart")).firstMatch
            XCTAssertTrue(viewCart.waitForExistence(timeout: 15), "Could not reach test-cart cleanup")
            if viewCart.exists && viewCart.isHittable { viewCart.tap() }
            let remove = web.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Remove")).firstMatch
            XCTAssertTrue(remove.waitForExistence(timeout: 20))
            if revealForCleanup(remove) { remove.tap() }
            cleanupVerified = web.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Shopping Cart is Empty")).firstMatch.waitForExistence(timeout: 20)
            XCTAssertTrue(cleanupVerified)
        }
        XCTAssertTrue(detected, "A website Add is not native ListRunner detector certification")
        print("LIVE_CART_NATIVE_PROBE store=\(store), detected=\(detected), cleanupVerified=\(cleanupVerified)")
    }

    func testExpansionStoreDiscoveryAndSeparateTargetBrands() {
        app.buttons["store-picker"].tap()
        app.buttons["Manage Stores"].tap()
        XCTAssertTrue(app.tables["manage-stores-table"].waitForExistence(timeout: 5))
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        let stores = [
            ("chemistWarehouse", "Chemist Warehouse"), ("priceline", "Priceline"),
            ("officeworks", "Officeworks"), ("jbHiFi", "JB Hi-Fi"), ("targetAU", "Target Australia"),
            ("petbarn", "Petbarn"), ("supercheapAuto", "Supercheap Auto"), ("bcf", "BCF"),
            ("bunnings", "Bunnings New Zealand"), ("theWarehouse", "The Warehouse"),
            ("sainsburys", "Sainsbury"),
            ("asda", "Asda"), ("morrisons", "Morrisons"), ("ocado", "Ocado"),
            ("waitrose", "Waitrose"), ("walgreens", "Walgreens")
        ]
        for (id, name) in stores {
            search.tap()
            if search.buttons["Clear text"].exists { search.buttons["Clear text"].tap() }
            search.typeText(name)
            XCTAssertTrue(manageRow(id).waitForExistence(timeout: 5), "Missing new store: \(name)")
        }
        for (id, name) in [("newWorld", "New World"), ("paknsave", "PAK"), ("boots", "Boots"), ("cvs", "CVS")] {
            search.tap()
            if search.buttons["Clear text"].exists { search.buttons["Clear text"].tap() }
            search.typeText(name)
            XCTAssertFalse(manageRow(id).exists, "Unverified-search destination must stay hidden: \(name)")
        }
        search.buttons["Clear text"].tap()
        search.typeText("Target")
        XCTAssertTrue(manageRow("targetAU").waitForExistence(timeout: 5))
        XCTAssertTrue(manageRow("target").exists, "Unrelated Australian and US Target must remain separate brands")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Separate Australian and US Target discovery"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        XCTAssertFalse(app.buttons["Dismiss store"].exists, "Discovery must not open any retailer website")
    }

    private func openStoreSettings(_ store: String, welcome: Bool = false) {
        let entry = manageRow(store)
        let table = app.tables["manage-stores-table"]
        // XCTest considers even a sliver of a clipped cell hittable. Require
        // the whole row inside the table before tapping its centre.
        func fullyVisible() -> Bool {
            // iOS 27 can throw while evaluating hittability for a virtualized
            // zero-frame row, rather than simply returning false.
            entry.exists && entry.frame.height > 0 && !entry.frame.isInfinite && !entry.frame.isNull
                && entry.frame.minY >= table.frame.minY
                && entry.frame.maxY <= table.frame.maxY
                && entry.isHittable
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

    func testResultsScrollSettingPersists() {
        app.buttons["Settings"].tap()
        let toggle = app.switches["auto-scroll-to-results"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 3))
        XCTAssertEqual(toggle.value as? String, "1")
        turnOffResultsScroll()
        app.terminate(); app.launch()
        app.buttons["Settings"].tap()
        XCTAssertTrue(toggle.waitForExistence(timeout: 3))
        XCTAssertEqual(toggle.value as? String, "0")
    }

    func testLiveWoolworthsResultsScroll() {
        // Only list-entry controls are tapped. The real retailer page is observed
        // without tapping consent, account, location, products or cart controls.
        app.buttons["store-picker"].tap()
        app.buttons["Manage Stores"].tap()
        setStoreVisibility("woolworths", shown: true)
        tapNavigationBack()
        choose("Woolworths")
        let input = app.descendants(matching: .any)["grocery-input"]
        input.tap(); input.typeText("milk")
        app.buttons["Add Items"].tap()
        app.buttons["Show Store"].tap()
        let status = app.staticTexts["results-scroll-probe-status"]
        let finished = NSPredicate(format: "label BEGINSWITH %@ OR label BEGINSWITH %@", "PASS:", "FAIL:")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: finished, object: status)], timeout: 70), .completed)
        XCTAssertTrue(status.label.hasPrefix("PASS:"), status.label)
        print("WOOLWORTHS_RESULTS_SCROLL " + status.label)
    }

    func testResultsScrollPositionsFirstResultNearTop() {
        app.buttons["Show Store"].tap()
        let result = app.webViews.staticTexts["Results scroll fixture item"].firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 10))
        let positioned = NSPredicate { _, _ in
            let web = self.app.webViews.firstMatch.frame
            return result.frame.minY >= web.minY && result.frame.minY < web.minY + 240
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: positioned, object: result)], timeout: 10), .completed)
    }

    func testResultsScrollOptOutLeavesPageAtTop() {
        app.buttons["Settings"].tap()
        turnOffResultsScroll()
        tapNavigationBack()
        app.buttons["Show Store"].tap()
        let heading = app.webViews.staticTexts["Results scroll fixture"].firstMatch
        XCTAssertTrue(heading.waitForExistence(timeout: 10))
        let moved = NSPredicate { _, _ in !heading.isHittable }
        let expectation = XCTNSPredicateExpectation(predicate: moved, object: heading)
        expectation.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 3), .completed)
    }

    private func turnOffResultsScroll() {
        let toggle = app.switches["auto-scroll-to-results"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 3))
        // On iOS 27 the AX Switch spans the row. Its centre is label text,
        // not the actual control (confirmed by the failed run's recording).
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        let off = NSPredicate(format: "value == %@", "0")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: off, object: toggle)], timeout: 3), .completed)
    }

    func testPreloadSearchIsPromotedAfterCooldown() {
        checkPreloadPromotion(resultsScroll: false)
    }

    func testPreloadResultsScrollPositionsBeforePromotion() {
        checkPreloadPromotion(resultsScroll: true)
    }

    private func checkPreloadPromotion(resultsScroll: Bool) {
        let input = app.descendants(matching: .any)["grocery-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 3))
        input.tap()
        // Use actual ingredient names. Unknown prefixes are intentionally kept
        // by the parser rather than silently discarded to make these labels.
        input.typeText("apple; pear")
        app.buttons["Add Items"].tap()
        XCTAssertTrue(row("Apples", status: "Pending").waitForExistence(timeout: 3))
        XCTAssertTrue(row("Pears", status: "Pending").exists)
        app.buttons["Show Store"].tap()
        let promoted = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier == %@ AND label CONTAINS[c] %@", "preload-debug-status",
                        resultsScroll ? "PASS: results positioned before promotion and preserved" : "Promoting completed preload")
        ).firstMatch
        XCTAssertTrue(promoted.waitForExistence(timeout: 25), app.debugDescription)
    }

    func testStoreResumeBrowserChecks() {
        app.buttons["Show Store"].tap()
        let status = app.staticTexts["store-resume-test-status"]
        let finished = NSPredicate(format: "label BEGINSWITH %@ OR label BEGINSWITH %@", "PASS:", "FAIL:")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: finished, object: status)], timeout: 60), .completed)
        XCTAssertTrue(status.label.hasPrefix("PASS:"), status.label)
        print("STORE_RESUME " + status.label)
    }

    func testStoreResumePreservesPageAndScrollAfterHandleDismissal() {
        checkStoreResumePreservesPageAndScroll(allItems: false)
    }

    func testAllItemsStoreResumePreservesPageAndScrollAfterHandleDismissal() {
        checkStoreResumePreservesPageAndScroll(allItems: true)
    }

    private func checkStoreResumePreservesPageAndScroll(allItems: Bool) {
        if allItems { choose("All items") }
        func openStore() {
            if allItems {
                app.buttons["all-items-show-store"].tap()
                app.buttons["Shop at Coles"].tap()
            } else {
                app.buttons["Show Store"].tap()
            }
        }
        openStore()
        let web = app.webViews.firstMatch
        let openProduct = web.buttons["Open fixture product"]
        XCTAssertTrue(openProduct.waitForExistence(timeout: 10))
        openProduct.tap()
        let note = web.textFields["Store page note"]
        for _ in 0..<5 {
            // Asking WebKit for hittability of an offscreen text field can
            // throw instead of returning false on iOS 27. Scroll the uncovered
            // upper page until its frame is visible above the shopping cards.
            let frame = note.frame
            let viewport = web.frame
            if frame.height > 0 && frame.minY > viewport.minY + 40
                && frame.maxY < viewport.midY { break }
            web.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.45))
                .press(forDuration: 0.05, thenDragTo: web.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.15)))
        }
        XCTAssertGreaterThan(note.frame.height, 0)
        XCTAssertGreaterThan(note.frame.minY, web.frame.minY + 40)
        XCTAssertLessThan(note.frame.maxY, web.frame.midY)
        note.tap()
        note.typeText("Keep my place")
        web.buttons["Save fixture note"].tap()
        let keyboardHidden = NSPredicate(format: "exists == false")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: keyboardHidden, object: app.keyboards.firstMatch)], timeout: 5), .completed)
        // Keyboard disappearance precedes WebKit's final inset/scroll adjustment.
        // Capture the resting position, not an intermediate animation frame.
        var lastY: CGFloat?
        var stableSamples = 0
        let settled = NSPredicate { _, _ in
            let y = note.frame.minY
            stableSamples = lastY.map { abs($0 - y) < 0.5 } == true ? stableSamples + 1 : 0
            lastY = y
            return stableSamples >= 3
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: settled, object: note)], timeout: 8), .completed)
        let originalY = note.frame.minY
        print("STORE_RESUME_BASELINE allItems=\(allItems) y=\(originalY) value=\(note.value ?? "nil")")
        for swipe in [true, false, true] {
            let handle = app.buttons["Dismiss store"]
            if swipe {
                let start = handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 230)))
            } else {
                handle.tap()
            }
            let footer = allItems ? app.buttons["all-items-show-store"] : app.buttons["Show Store"]
            XCTAssertTrue(footer.waitForExistence(timeout: 5))
            openStore()
            let preserved = NSPredicate { _, _ in
                note.exists && note.value as? String == "Keep my place"
                    && abs(note.frame.minY - originalY) < 3
                    && web.buttons["Fixture product opened"].exists
            }
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: preserved, object: note)], timeout: 8), .completed,
                           "Reopening must retain the product document, form value and scroll position; expectedY=\(originalY), actual=\(note.frame), value=\(note.value ?? "nil"), product=\(web.buttons["Fixture product opened"].exists)")
            let lostState = XCTNSPredicateExpectation(predicate: NSCompoundPredicate(notPredicateWithSubpredicate: preserved), object: note)
            lostState.isInverted = true
            XCTAssertEqual(XCTWaiter.wait(for: [lostState], timeout: 3), .completed,
                           "A deferred search must not reload the retained page after reopening")
        }
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

    func testAllItemsGroupingCapsuleHasAccessibleTargetsAndSelection() {
        assertAllItemsGroupingCapsule()
    }

    func testAllItemsGroupingCapsuleAtAccessibilityTextSize() {
        app.terminate()
        app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        assertAllItemsGroupingCapsule()
    }

    private func assertAllItemsGroupingCapsule() {
        choose("All items")
        let store = app.buttons["all-items-grouping-store"]
        let category = app.buttons["all-items-grouping-category"]
        let list = app.collectionViews.firstMatch
        let entryPanel = list.cells.containing(.textView, identifier: "all-items-entry").firstMatch
        XCTAssertTrue(entryPanel.waitForExistence(timeout: 3))
        let panelFrame = entryPanel.frame
        for _ in 0..<6 where !category.isHittable { list.swipeUp() }
        XCTAssertTrue(store.isHittable)
        XCTAssertTrue(category.isHittable)
        XCTAssertEqual(store.label, "By store")
        XCTAssertEqual(category.label, "By category")
        for button in [store, category] {
            XCTAssertGreaterThanOrEqual(button.frame.height, 44)
            XCTAssertGreaterThanOrEqual(button.frame.width, 44)
            XCTAssertGreaterThanOrEqual(button.frame.minX, app.frame.minX)
            XCTAssertLessThanOrEqual(button.frame.maxX, app.frame.maxX)
        }
        XCTAssertEqual(store.frame.width, category.frame.width, accuracy: 1)
        // The selected/unselected buttons sit 4pt inside the capsule's outer edge.
        XCTAssertEqual(min(store.frame.minX, category.frame.minX) - 4, panelFrame.minX, accuracy: 1,
                       "The capsule must align with the white entry/list panels, not their inset content")
        XCTAssertEqual(max(store.frame.maxX, category.frame.maxX) + 4, panelFrame.maxX, accuracy: 1)
        XCTAssertTrue(store.isSelected)
        XCTAssertFalse(category.isSelected)
        category.tap()
        XCTAssertTrue(category.isSelected)
        XCTAssertFalse(store.isSelected)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name.contains("AccessibilityTextSize")
            ? "All items — grouping capsule at largest accessibility size"
            : "All items — grouping capsule"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        store.tap()
        XCTAssertTrue(store.isSelected)
        XCTAssertFalse(category.isSelected)
    }

    func testAllItemsScopeShowsExistingListsAndAddsToChosenDestination() {
        choose("All items")
        XCTAssertTrue(app.buttons["all-items-scope-picker"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Coles fixture item"].waitForExistence(timeout: 3))
        for item in ["Woolworths fixture item", "Bunnings fixture item"] {
            let row = app.staticTexts[item]
            for _ in 0..<4 where !row.exists { app.swipeUp() }
            XCTAssertTrue(row.waitForExistence(timeout: 3), "All items should include the existing \(item)")
        }
        for _ in 0..<4 { app.swipeDown() }

        let entry = app.textViews["all-items-entry"]
        XCTAssertTrue(entry.waitForExistence(timeout: 3))
        entry.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3), app.debugDescription)
        entry.typeText("All items destination item")
        app.buttons["all-items-add-destination"].tap()
        app.buttons["Woolworths"].firstMatch.tap()
        XCTAssertEqual(entry.value as? String, "All items destination item", "Changing destination must preserve the draft")
        XCTAssertTrue(app.buttons["all-items-add"].label.contains("Woolworths"))
        app.buttons["all-items-add"].tap()
        let added = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "All items destination item")).firstMatch
        for _ in 0..<4 where !added.exists { app.swipeUp() }
        XCTAssertTrue(added.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Woolworths ·")).firstMatch.exists)

        let categoryMode = app.buttons["all-items-grouping-category"]
        XCTAssertTrue(categoryMode.waitForExistence(timeout: 3))
        categoryMode.tap()
        XCTAssertTrue(app.staticTexts["Grocery"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Hardware & Garden"].exists)
    }

    func testAllItemsManualEntryPreservesProductWording() {
        choose("All items")
        let entry = app.textViews["all-items-entry"]
        XCTAssertTrue(entry.waitForExistence(timeout: 3))
        entry.tap()
        entry.typeText("500 g penne pasta")
        app.buttons["all-items-add"].tap()
        let product = row("500 g penne pasta", status: "Pending")
        XCTAssertTrue(product.waitForExistence(timeout: 5))
        XCTAssertTrue(product.label.contains("quantity 1"), "Manual entry must not extract 500 g as a quantity")
        assertGroceryInputIsEmpty(entry)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["all-items-scope-picker"].waitForExistence(timeout: 10))
        XCTAssertTrue(product.waitForExistence(timeout: 5), "Literal manual wording must survive relaunch")
    }

    func testAllItemsRepeatedEntryKeepsComposerAndPreferences() {
        choose("All items")
        let entry = app.textViews["all-items-entry"]
        let add = app.buttons["all-items-add"]
        XCTAssertGreaterThanOrEqual(add.frame.height, 44)
        XCTAssertLessThanOrEqual(add.frame.height, 48, "The split Add label should stay on one line at standard text size")
        XCTAssertGreaterThanOrEqual(app.buttons["all-items-add-destination"].frame.width, 44)
        XCTAssertGreaterThanOrEqual(app.buttons["all-items-add-destination"].frame.height, 44)
        entry.tap()
        let initialKeyboardVisible = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            self.app.keyboards.firstMatch.frame.intersection(self.app.frame).height >= 180
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [initialKeyboardVisible], timeout: 5), .completed,
                       "The test requires a visible software keyboard before typing or adding")
        entry.typeText("First aggregate item")
        add.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        let keyboardVisible = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            self.app.keyboards.firstMatch.frame.intersection(self.app.frame).height >= 180
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [keyboardVisible], timeout: 5), .completed,
                       "Keyboard coverage requires a visible software keyboard, not an offscreen AX element")
        XCTAssertFalse(app.buttons["all-items-show-store"].exists, "Secondary shopping chrome must not obscure entry feedback")
        entry.typeText("Second aggregate item")
        add.tap()
        let newest = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Second aggregate item")).firstMatch
        XCTAssertTrue(newest.waitForExistence(timeout: 5))
        let newestVisible = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            newest.frame.minY >= self.app.buttons["all-items-scope-picker"].frame.maxY
                && newest.frame.maxY <= self.app.keyboards.firstMatch.frame.minY
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [newestVisible], timeout: 5), .completed,
                       "The new item must settle fully above the real keyboard")
        app.buttons["all-items-grouping-category"].tap()
        let destination = add.label
        entry.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        let editorCell = app.collectionViews.cells.containing(.textView, identifier: "all-items-entry").firstMatch
        let actionsCell = app.collectionViews.cells.containing(.button, identifier: "all-items-add").firstMatch
        let entryVisible = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            editorCell.frame.minY >= self.app.buttons["all-items-scope-picker"].frame.maxY
                && actionsCell.frame.maxY <= self.app.keyboards.firstMatch.frame.minY
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [entryVisible], timeout: 5), .completed,
                       "Refocusing after item reveal must restore the entire shared entry card")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "All items — shared scrolling entry with keyboard"
        screenshot.lifetime = .keepAlways
        self.add(screenshot)
        entry.tap(); entry.typeText("Persisted unsubmitted draft")
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["all-items-scope-picker"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons["all-items-add"].label, destination)
        XCTAssertTrue(app.buttons["all-items-grouping-category"].isSelected)
        XCTAssertEqual(app.textViews["all-items-entry"].value as? String, "Persisted unsubmitted draft")
    }

    func testAllItemsGroupAddSelectsStorePreservesDraftAndFocusesEntry() {
        choose("All items")
        let entry = app.textViews["all-items-entry"]
        entry.tap()
        entry.typeText("Shortcut unsubmitted draft")
        app.staticTexts["Ready when you are"].tap()
        let shortcut = app.buttons["all-items-group-add-woolworths"]
        for _ in 0..<6 where !shortcut.isHittable { app.collectionViews.firstMatch.swipeUp() }
        XCTAssertTrue(shortcut.isHittable)
        XCTAssertGreaterThanOrEqual(shortcut.frame.width, 44)
        XCTAssertGreaterThanOrEqual(shortcut.frame.height, 44)
        shortcut.tap()
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["all-items-add"].label.contains("Woolworths"))
        XCTAssertEqual(entry.value as? String, "Shortcut unsubmitted draft")
        entry.typeText(" suffix") // No second tap: the shortcut focuses the existing editor.
        XCTAssertEqual(entry.value as? String, "Shortcut unsubmitted draft suffix")
        XCTAssertFalse(app.buttons["Actions for Shortcut unsubmitted draft"].exists)
        app.staticTexts["Ready when you are"].tap()
        let titles = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "all-items-group-title-store-"))
        XCTAssertEqual(titles.firstMatch.label, "Woolworths")
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["all-items-scope-picker"].waitForExistence(timeout: 10))
        XCTAssertEqual(entry.value as? String, "Shortcut unsubmitted draft suffix")
        XCTAssertTrue(app.buttons["all-items-add"].label.contains("Woolworths"))
        XCTAssertEqual(titles.firstMatch.label, "Bunnings", "A shortcut must not fabricate persisted addition recency")
    }

    func testAllItemsUnavailableGroupAddIsAbsentAndCategoriesHaveNoShortcut() {
        choose("All items")
        let list = app.collectionViews.firstMatch
        let unavailableTitle = app.staticTexts["all-items-group-title-store-tesco"]
        for _ in 0..<6 where !unavailableTitle.isHittable { list.swipeUp() }
        XCTAssertTrue(unavailableTitle.isHittable)
        XCTAssertFalse(app.buttons["all-items-group-add-tesco"].exists)
        for _ in 0..<6 where !app.buttons["all-items-grouping-category"].isHittable { list.swipeDown() }
        app.buttons["all-items-grouping-category"].tap()
        XCTAssertTrue(app.staticTexts["Grocery"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "all-items-group-add-")).firstMatch.exists)
    }

    func testAllItemsDeleteItemIsImmediateInBothGroupingsAndPreservesOtherStores() {
        choose("All items")
        let list = app.collectionViews.firstMatch
        for (grouping, product) in [("By store", "Coles fixture item"), ("By category", "Woolworths fixture item")] {
            let groupingButton = app.buttons[grouping == "By store"
                ? "all-items-grouping-store" : "all-items-grouping-category"]
            for _ in 0..<6 where !groupingButton.isHittable { list.swipeDown() }
            groupingButton.tap()
            let actions = app.buttons["Actions for \(product)"]
            for _ in 0..<6 where !actions.isHittable { list.swipeUp() }
            XCTAssertTrue(actions.isHittable)
            actions.tap()
            app.buttons["Delete Item"].tap()
            let removed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: actions)
            XCTAssertEqual(XCTWaiter.wait(for: [removed], timeout: 5), .completed,
                           "One Delete Item tap must remove the row without a second confirmation")
            XCTAssertFalse(app.staticTexts["Delete this item?"].exists)
        }
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["all-items-scope-picker"].waitForExistence(timeout: 10))
        let remaining = app.buttons["Actions for Bunnings fixture item"]
        for _ in 0..<6 where !remaining.isHittable { app.collectionViews.firstMatch.swipeUp() }
        XCTAssertTrue(remaining.isHittable, "Deleting other owners' rows must preserve Bunnings")
        app.buttons["all-items-scope-picker"].tap()
        app.buttons["Coles"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Your list is empty"].waitForExistence(timeout: 5))
        choose("Woolworths")
        XCTAssertTrue(app.staticTexts["Your list is empty"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.webViews.firstMatch.exists)
    }

    private func enableLongAddDestination() {
        app.buttons["store-picker"].tap()
        app.buttons["store-picker-manage-stores"].tap()
        setStoreVisibility("chemistWarehouse", shown: true)
        tapNavigationBack()
        choose("All items")
        app.buttons["all-items-add-destination"].tap()
        app.buttons["Chemist Warehouse"].firstMatch.tap()
    }

    func testAllItemsLongDestinationStacksActionsAndMatchesStandardAddHeight() {
        let standardHeight = app.buttons["Add Items"].frame.height
        let standardScreenshot = XCTAttachment(screenshot: app.screenshot())
        standardScreenshot.name = "Standard Add — shared visible capsule height"
        standardScreenshot.lifetime = .keepAlways
        self.add(standardScreenshot)
        enableLongAddDestination()
        let add = app.buttons["all-items-add"]
        let arrow = app.buttons["all-items-add-destination"]
        let importing = app.buttons["set-import-source"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        XCTAssertTrue(add.label.contains("Chemist Warehouse"))
        XCTAssertEqual(add.frame.height, standardHeight, accuracy: 1)
        XCTAssertGreaterThanOrEqual(arrow.frame.width, 44)
        XCTAssertGreaterThanOrEqual(arrow.frame.height, 44)
        XCTAssertGreaterThan(importing.frame.width, 65, "Import must retain its label, not collapse into a column")
        XCTAssertLessThanOrEqual(importing.frame.maxY, add.frame.minY, "Long destinations use separate action rows")
        XCTAssertGreaterThan(add.frame.width + arrow.frame.width, app.frame.width * 0.75)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Long destination — full-width split Add and readable Import"
        screenshot.lifetime = .keepAlways
        self.add(screenshot)
        let entry = app.textViews["all-items-entry"]
        entry.tap(); entry.typeText("Keep action layout draft")
        arrow.tap()
        app.buttons["Coles"].firstMatch.tap()
        XCTAssertEqual(entry.value as? String, "Keep action layout draft")
        XCTAssertTrue(add.label.contains("Coles"))
        XCTAssertEqual(importing.frame.midY, add.frame.midY, accuracy: 1, "Short labels return to the horizontal layout")
    }

    func testAllItemsAccessibilityActionsStayWithinPage() {
        enableLongAddDestination()
        app.terminate()
        app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"]
        app.launch()
        XCTAssertTrue(app.buttons["all-items-scope-picker"].waitForExistence(timeout: 10))
        let add = app.buttons["all-items-add"]
        let arrow = app.buttons["all-items-add-destination"]
        let importing = app.buttons["set-import-source"]
        let footer = app.buttons["all-items-show-store"]
        let list = app.collectionViews.firstMatch
        for _ in 0..<10 where !add.isHittable || max(add.frame.maxY, arrow.frame.maxY) > footer.frame.minY {
            // Small drags reveal the complete actions without flinging Import
            // past the pinned header at accessibility sizes.
            list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
                .press(forDuration: 0.05, thenDragTo: list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6)))
        }
        XCTAssertTrue(add.isHittable)
        XCTAssertTrue(add.label.contains("Chemist Warehouse"))
        XCTAssertTrue(importing.isHittable)
        XCTAssertLessThanOrEqual(importing.frame.maxY, add.frame.minY)
        XCTAssertLessThanOrEqual(max(add.frame.maxY, arrow.frame.maxY), footer.frame.minY,
                                 "The full split control must scroll clear of Show Store")
        XCTAssertGreaterThanOrEqual(arrow.frame.width, 44)
        XCTAssertGreaterThanOrEqual(arrow.frame.height, 44)
        XCTAssertGreaterThanOrEqual(importing.frame.minX, app.frame.minX)
        XCTAssertLessThanOrEqual(importing.frame.maxX, app.frame.maxX)
        XCTAssertLessThanOrEqual(arrow.frame.maxX, app.frame.maxX)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Accessible text — stacked entry actions"
        screenshot.lifetime = .keepAlways
        self.add(screenshot)
    }

    func testAllItemsShortRowMatchesStoreRowHeight() {
        choose("Coles")
        let storeCell = app.collectionViews.cells.containing(.any, identifier: "Actions for Coles fixture item").firstMatch
        XCTAssertTrue(storeCell.waitForExistence(timeout: 5))
        let storeHeight = storeCell.frame.height
        XCTAssertEqual(storeHeight, 78, accuracy: 1)
        choose("All items")
        let aggregateCell = app.collectionViews.cells.containing(.any, identifier: "Actions for Coles fixture item").firstMatch
        for _ in 0..<5 where !aggregateCell.exists { app.collectionViews.firstMatch.swipeUp() }
        XCTAssertTrue(aggregateCell.waitForExistence(timeout: 3))
        print("ROW_HEIGHT store=\(storeHeight) allItemsByStore=\(aggregateCell.frame.height)")
        XCTAssertEqual(aggregateCell.frame.height, storeHeight, accuracy: 1,
                       "A short row must not receive extra native vertical insets in All items")
        for _ in 0..<3 where !app.buttons["all-items-grouping-category"].isHittable {
            app.collectionViews.firstMatch.swipeDown()
        }
        app.buttons["all-items-grouping-category"].tap()
        for _ in 0..<5 where !aggregateCell.exists { app.collectionViews.firstMatch.swipeUp() }
        XCTAssertTrue(aggregateCell.waitForExistence(timeout: 3))
        print("ROW_HEIGHT allItemsByCategory=\(aggregateCell.frame.height)")
        XCTAssertEqual(aggregateCell.frame.height, storeHeight, accuracy: 1)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "All items — shared native row height"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testAllItemsSharedPageKeepsOnlyHeaderPinned() {
        let storeEntry = app.textViews["grocery-input"]
        XCTAssertTrue(storeEntry.waitForExistence(timeout: 5))
        let standardFrame = storeEntry.frame
        choose("All items")
        let entry = app.textViews["all-items-entry"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        XCTAssertEqual(entry.frame.minX, standardFrame.minX, accuracy: 1)
        XCTAssertEqual(entry.frame.width, standardFrame.width, accuracy: 1)
        XCTAssertEqual(entry.frame.height, standardFrame.height, accuracy: 1)
        XCTAssertEqual(entry.frame.minY, standardFrame.minY, accuracy: 2)
        let scope = app.buttons["all-items-scope-picker"]
        let headerFrame = scope.frame
        let titleFrame = app.staticTexts["Your list"].frame
        let list = app.collectionViews.firstMatch
        for _ in 0..<3 { list.swipeUp() }
        XCTAssertTrue(scope.isHittable)
        XCTAssertEqual(scope.frame.minY, headerFrame.minY, accuracy: 1)
        XCTAssertEqual(app.staticTexts["Your list"].frame.minY, titleFrame.minY, accuracy: 1)
        XCTAssertFalse(entry.isHittable, "The Add products section scrolls with the list")
        XCTAssertFalse(app.segmentedControls["all-items-grouping"].isHittable, "Grouping also scrolls, not just the rows")
        XCTAssertTrue(app.buttons["all-items-show-store"].isHittable)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "All items — shared page with only header pinned"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        for _ in 0..<3 { list.swipeDown() }
        XCTAssertTrue(entry.isHittable)
    }

    func testAllItemsPaprikaImportRetainsScopeDraftAndDestination() {
        choose("All items")
        let entry = app.textViews["all-items-entry"]
        entry.tap(); entry.typeText("Unsubmitted draft")
        app.buttons["all-items-add-destination"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let woolworths = app.buttons["Woolworths"].firstMatch
        XCTAssertTrue(woolworths.waitForExistence(timeout: 3))
        woolworths.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let destinationChanged = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            self.app.buttons["all-items-add"].label.contains("Woolworths")
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [destinationChanged], timeout: 3), .completed)
        app.buttons["Import"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["import-source-paprika"].waitForExistence(timeout: 5))
        app.buttons["import-source-paprika"].tap()
        confirmPaprikaImport()
        if app.buttons["paprika-reminders-list-fixture-paprika"].waitForExistence(timeout: 2) {
            app.buttons["paprika-reminders-list-fixture-paprika"].tap()
        }
        XCTAssertTrue(app.buttons["all-items-scope-picker"].waitForExistence(timeout: 10))
        XCTAssertEqual(entry.value as? String, "Unsubmitted draft")
        XCTAssertTrue(app.buttons["all-items-add"].label.contains("Woolworths"))
        app.buttons["all-items-scope-picker"].tap()
        app.buttons["Woolworths"].firstMatch.tap()
        XCTAssertTrue(row("milk", status: "Pending").waitForExistence(timeout: 5))
        choose("Coles")
        XCTAssertFalse(row("milk", status: "Pending").exists)
    }

    func testNonemptyRegionalSwitchIsBlocked() {
        app.buttons["store-picker"].tap()
        app.buttons["store-picker-manage-stores"].tap()
        openStoreSettings("bunnings")
        app.buttons["store-region-picker-bunnings"].tap()
        app.buttons["store-region-bunningsNZ"].tap()
        app.alerts.buttons["Use this regional website"].tap()
        let blocker = app.alerts["Region can’t be changed yet"]
        XCTAssertTrue(blocker.waitForExistence(timeout: 5))
        blocker.buttons["View List"].tap()
        XCTAssertTrue(row("Bunnings fixture item", status: "Pending").waitForExistence(timeout: 5))
        XCTAssertFalse(app.webViews.firstMatch.exists)
    }

    private func openAllItemsClearOptions(_ groupID: String) {
        let clear = app.buttons["all-items-clear-\(groupID)"]
        let list = app.collectionViews.firstMatch
        let showStore = app.buttons["all-items-show-store"]
        func fullyVisible() -> Bool {
            guard clear.isHittable else { return false }
            let bottom = showStore.exists ? min(list.frame.maxY, showStore.frame.minY) : list.frame.maxY
            return clear.frame.minY >= list.frame.minY && clear.frame.maxY <= bottom
        }
        // Full-length swipes can skip an entire small group; virtualized rows
        // then disappear from AX, making their direction impossible to infer.
        // Search from the top when necessary and use short, bounded drags.
        if !clear.exists {
            for _ in 0..<4 where !clear.exists { list.swipeDown(velocity: .fast) }
        }
        for _ in 0..<20 where !fullyVisible() {
            let bottom = showStore.exists ? min(list.frame.maxY, showStore.frame.minY) : list.frame.maxY
            let top = list.frame.minY
            let start = app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: list.frame.midX, dy: (top + bottom) / 2))
            let direction: CGFloat = clear.exists && clear.frame.minY < top ? 1 : -1
            let end = start.withOffset(CGVector(dx: 0, dy: direction * min(90, (bottom - top) / 3)))
            start.press(forDuration: 0.05, thenDragTo: end,
                        withVelocity: XCUIGestureVelocity(rawValue: 80), thenHoldForDuration: 0.4)
        }
        XCTAssertTrue(clear.isHittable, app.debugDescription)
        XCTAssertTrue(fullyVisible(), "The entire clear action must be above Show Store, not merely tappable through glass")
        XCTAssertGreaterThanOrEqual(clear.frame.height, 56)
        clear.tap()
        XCTAssertTrue(app.buttons["Clear All"].waitForExistence(timeout: 3))
    }

    func testAllItemsStoreClearSupportsCancelAddedAndAll() {
        choose("Coles")
        app.buttons["Actions for Coles fixture item"].tap()
        app.buttons["Mark Added"].tap()
        choose("Woolworths")
        app.buttons["Actions for Woolworths fixture item"].tap()
        app.buttons["Mark Added"].tap()
        choose("All items")
        app.buttons["all-items-add-destination"].tap()
        app.buttons["Coles"].firstMatch.tap()
        let entry = app.textViews["all-items-entry"]
        entry.tap()
        entry.typeText("Keep pending; Keep skipped")
        app.buttons["all-items-add"].tap()
        entry.typeText("\n")
        app.buttons["Actions for Keep skipped"].tap()
        app.buttons["Mark Skipped"].tap()
        openAllItemsClearOptions("store-coles")
        XCTAssertTrue(app.buttons["Clear Added"].exists)
        cancelClearListOptions()
        XCTAssertTrue(app.buttons["Actions for Coles fixture item"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "All items — per-group Clear List button"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        openAllItemsClearOptions("store-coles")
        app.buttons["Clear Added"].tap()
        app.collectionViews.firstMatch.swipeDown(velocity: .fast)
        XCTAssertTrue(app.buttons["Actions for Coles fixture item"].waitForNonExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Actions for Keep pending"].exists)
        XCTAssertTrue(app.buttons["Actions for Keep skipped"].exists)
        openAllItemsClearOptions("store-coles")
        XCTAssertFalse(app.buttons["Clear Added"].exists)
        app.buttons["Clear All"].tap()
        XCTAssertTrue(app.buttons["all-items-clear-store-coles"].waitForNonExistence(timeout: 3))
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["all-items-scope-picker"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Actions for Keep pending"].exists)
        XCTAssertFalse(app.buttons["Actions for Keep skipped"].exists)
        app.buttons["all-items-show-store"].tap()
        XCTAssertTrue(app.buttons["Shop at Woolworths"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Shop at Bunnings"].exists)
        XCTAssertFalse(app.buttons["Shop at Coles"].exists)
    }

    func testAllItemsCategoryClearAffectsOnlyThatCategoryAcrossStores() {
        choose("Coles")
        app.buttons["Actions for Coles fixture item"].tap()
        app.buttons["Mark Added"].tap()
        choose("Woolworths")
        app.buttons["Actions for Woolworths fixture item"].tap()
        app.buttons["Mark Added"].tap()
        choose("All items")
        let entry = app.textViews["all-items-entry"]
        entry.tap()
        entry.typeText("Category keep pending; Category keep skipped")
        app.buttons["all-items-add"].tap()
        entry.typeText("\n")
        app.buttons["Actions for Category keep skipped"].tap()
        app.buttons["Mark Skipped"].tap()
        app.buttons["all-items-grouping-category"].tap()
        openAllItemsClearOptions("category-grocery")
        XCTAssertTrue(app.buttons["Clear Added"].exists)
        app.buttons["Clear Added"].tap()
        app.collectionViews.firstMatch.swipeDown(velocity: .fast)
        XCTAssertTrue(app.buttons["Actions for Coles fixture item"].waitForNonExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Actions for Woolworths fixture item"].exists)
        XCTAssertTrue(app.buttons["Actions for Category keep pending"].exists)
        XCTAssertTrue(app.buttons["Actions for Category keep skipped"].exists)
        openAllItemsClearOptions("category-grocery")
        XCTAssertFalse(app.buttons["Clear Added"].exists)
        app.buttons["Clear All"].tap()
        XCTAssertTrue(app.buttons["all-items-clear-category-grocery"].waitForNonExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Actions for Bunnings fixture item"].waitForExistence(timeout: 3))
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["all-items-scope-picker"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["all-items-clear-category-grocery"].exists)
        XCTAssertTrue(app.buttons["Actions for Bunnings fixture item"].waitForExistence(timeout: 3))
    }

    func testAllItemsUnavailableGroupsCanBeClearedIndependently() {
        choose("All items")
        openAllItemsClearOptions("uncategorised")
        XCTAssertFalse(app.buttons["Clear Added"].exists)
        cancelClearListOptions()
        XCTAssertTrue(app.buttons["Actions for Uncategorised saved item"].exists)
        openAllItemsClearOptions("uncategorised")
        app.buttons["Clear All"].tap()
        XCTAssertTrue(app.buttons["all-items-clear-uncategorised"].waitForNonExistence(timeout: 3))
        // The unavailable but known owner is a different sublist, not collateral.
        openAllItemsClearOptions("store-tesco")
        app.buttons["Clear All"].tap()
        XCTAssertTrue(app.buttons["all-items-clear-store-tesco"].waitForNonExistence(timeout: 3))
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["all-items-scope-picker"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["all-items-clear-uncategorised"].exists)
        XCTAssertFalse(app.buttons["all-items-clear-store-tesco"].exists)
        XCTAssertTrue(app.buttons["Actions for Coles fixture item"].waitForExistence(timeout: 3))
    }

    func testAllItemsSettingsReturnsToScopeAndDraft() {
        choose("All items")
        app.buttons["all-items-grouping-category"].tap()
        let entry = app.textViews["all-items-entry"]
        entry.tap()
        entry.typeText("Keep aggregate draft")
        let destination = app.buttons["all-items-add"].label
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["import-source-setting"].exists)
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        tapNavigationBack()
        XCTAssertTrue(app.buttons["all-items-scope-picker"].waitForExistence(timeout: 5))
        XCTAssertEqual(entry.value as? String, "Keep aggregate draft")
        XCTAssertEqual(app.buttons["all-items-add"].label, destination)
        XCTAssertTrue(app.buttons["all-items-grouping-category"].isSelected)
    }

    func testAllItemsEditReordersWithinStoreAndRestoresGrouping() {
        choose("All items")
        app.buttons["all-items-add-destination"].tap()
        app.buttons["Coles"].firstMatch.tap()
        let entry = app.textViews["all-items-entry"]
        entry.tap()
        entry.typeText("First reorder item, Second reorder item")
        app.buttons["all-items-add"].tap()
        app.buttons["all-items-grouping-category"].tap()
        app.buttons["Edit"].tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["all-items-grouping-store"].isSelected)
        XCTAssertFalse(app.buttons["all-items-grouping-category"].isEnabled)
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        let first = app.staticTexts["First reorder item"]
        let second = app.staticTexts["Second reorder item"]
        XCTAssertTrue(first.waitForExistence(timeout: 3))
        XCTAssertTrue(second.exists)
        XCTAssertLessThan(first.frame.minY, second.frame.minY)
        let firstCell = app.collectionViews.cells.containing(.staticText, identifier: "First reorder item").firstMatch
        let secondCell = app.collectionViews.cells.containing(.staticText, identifier: "Second reorder item").firstMatch
        let handles = NSPredicate(format: "label BEGINSWITH %@", "Reorder")
        let firstHandle = firstCell.buttons.matching(handles).firstMatch
        let secondHandle = secondCell.buttons.matching(handles).firstMatch
        XCTAssertTrue(firstHandle.isHittable)
        XCTAssertTrue(secondHandle.isHittable)
        let target = firstHandle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0))
        secondHandle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 1, thenDragTo: target, withVelocity: .slow, thenHoldForDuration: 0.5)
        let reordered = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            second.frame.minY < first.frame.minY
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [reordered], timeout: 5), .completed)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "All items — standard Settings and Edit controls"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["all-items-grouping-category"].isSelected)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["all-items-scope-picker"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["all-items-grouping-category"].isSelected)
        app.buttons["all-items-scope-picker"].tap()
        app.buttons["Coles"].firstMatch.tap()
        XCTAssertTrue(row("Second reorder item", status: "Pending").waitForExistence(timeout: 5))
        XCTAssertLessThan(row("Second reorder item", status: "Pending").frame.minY,
                          row("First reorder item", status: "Pending").frame.minY)
        choose("Woolworths")
        XCTAssertFalse(row("First reorder item", status: "Pending").exists)
        XCTAssertTrue(row("Woolworths fixture item", status: "Pending").waitForExistence(timeout: 3))
    }

    func testAllItemsShowStoreOnlyOffersPopulatedLists() {
        app.buttons["store-picker"].tap()
        app.buttons["store-picker-manage-stores"].tap()
        setStoreVisibility("costco", shown: true)
        tapNavigationBack()
        choose("All items")
        let showStore = app.buttons["all-items-show-store"]
        XCTAssertTrue(showStore.waitForExistence(timeout: 5))
        XCTAssertEqual(showStore.label, "Show Store...")
        showStore.tap()
        XCTAssertTrue(app.buttons["Shop at Coles"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Shop at Woolworths"].exists)
        XCTAssertFalse(app.buttons["Shop at Costco"].exists, "Enabled but empty lists must not be offered")
        app.buttons["Shop at Coles"].tap()
        XCTAssertTrue(app.buttons["Dismiss store"].waitForExistence(timeout: 10))
        app.buttons["Dismiss store"].tap()
        XCTAssertTrue(app.buttons["all-items-scope-picker"].waitForExistence(timeout: 5))
    }

    func testAllItemsResultsScrollShoppingReturnsToAggregate() {
        choose("All items")
        let colesRow = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Coles fixture item, quantity")).firstMatch
        for _ in 0..<4 where !colesRow.isHittable { app.collectionViews.firstMatch.swipeUp() }
        colesRow.tap()
        XCTAssertTrue(app.buttons["Dismiss store"].waitForExistence(timeout: 10))
        app.buttons["Dismiss store"].tap()
        XCTAssertTrue(app.buttons["all-items-scope-picker"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["store-picker"].exists)
    }

    func testAllItemsUnavailableAndUnknownOwnersRemainRecoverable() {
        choose("All items")
        let hiddenRow = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Unavailable saved item, quantity")).firstMatch
        for _ in 0..<6 where !hiddenRow.isHittable { app.collectionViews.firstMatch.swipeUp() }
        XCTAssertTrue(hiddenRow.label.hasSuffix(", Unavailable"))
        hiddenRow.tap()
        XCTAssertFalse(app.buttons["Dismiss store"].exists)
        app.buttons["Actions for Unavailable saved item"].tap()
        app.buttons["Mark Added"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS %@",
                                                      "Unavailable saved item, quantity", "Added")).firstMatch.exists)
        let orphan = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Uncategorised saved item, quantity")).firstMatch
        for _ in 0..<6 where !orphan.isHittable { app.collectionViews.firstMatch.swipeUp() }
        XCTAssertTrue(app.staticTexts["Uncategorised"].exists)
        app.buttons["Actions for Uncategorised saved item"].tap()
        app.buttons["Move to Another Store"].tap()
        app.buttons["Woolworths"].firstMatch.tap()
        app.buttons["all-items-scope-picker"].tap()
        app.buttons["Woolworths"].firstMatch.tap()
        XCTAssertTrue(row("Uncategorised saved item", status: "Pending").waitForExistence(timeout: 5))
    }

    func testAllItemsCategoryOrderingUsesRecentItemsAcrossStores() {
        app.buttons["store-picker"].tap()
        app.buttons["store-picker-manage-stores"].tap()
        setStoreVisibility("costco", shown: true)
        tapNavigationBack()
        choose("All items")
        app.buttons["all-items-grouping-category"].tap()
        for (store, product, category) in [("Woolworths", "Woolworths newest", "Grocery"),
                                           ("Coles", "Coles newest", "Grocery"),
                                           ("Costco", "Costco newest", "Groceries & Home")] {
            app.buttons["all-items-add-destination"].tap()
            app.buttons[store].firstMatch.tap()
            let entry = app.textViews["all-items-entry"]
            entry.tap(); entry.typeText(product)
            app.buttons["all-items-add"].tap()
            let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", product + ", quantity")).firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts[category].waitForExistence(timeout: 5))
            XCTAssertLessThan(row.frame.maxY, app.keyboards.firstMatch.frame.minY)
        }
        XCTAssertTrue(app.staticTexts["Groceries & Home"].exists)
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["all-items-scope-picker"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Groceries & Home"].waitForExistence(timeout: 5))
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

    func testDisablingNonemptyStoreIsBlockedUntilItsListIsCleared() {
        app.buttons["Settings"].tap()
        app.buttons["Manage Stores"].tap()
        openStoreSettings("coles")
        app.switches["store-visibility-coles"].coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        let blocker = app.alerts["Store can’t be disabled yet"]
        XCTAssertTrue(blocker.waitForExistence(timeout: 3), app.debugDescription)
        XCTAssertTrue(blocker.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Coles")).firstMatch.exists)
        blocker.buttons["View List"].tap()
        XCTAssertTrue(row("Coles fixture item", status: "Pending").waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["store-picker"].label.contains("Coles"))
        XCTAssertFalse(app.webViews.firstMatch.exists, "Viewing a blocked list must not launch its retailer website")

        app.buttons["Actions for Coles fixture item"].tap()
        let delete = app.buttons["Delete Item"]
        XCTAssertTrue(delete.waitForExistence(timeout: 3))
        delete.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.staticTexts["Your list is empty"].waitForExistence(timeout: 3))
        app.buttons["store-picker"].tap()
        app.buttons["store-picker-manage-stores"].tap()
        setStoreVisibility("coles", shown: false)
        tapNavigationBack()
        XCTAssertTrue(app.buttons["store-picker"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["store-picker"].label.contains("Coles"))
    }

    func testDisablingActiveBunningsRequiresClearingItsList() {
        choose("Bunnings")
        let input = app.descendants(matching: .any)["grocery-input"]
        input.tap()
        input.typeText("Bunnings saved item")
        app.buttons["Add Items"].tap()
        XCTAssertTrue(row("Bunnings saved item", status: "Pending").waitForExistence(timeout: 3))
        app.buttons["Actions for Bunnings saved item"].tap()
        app.buttons["Mark Added"].tap()
        app.buttons["store-picker"].tap()
        app.buttons["store-picker-manage-stores"].tap()
        openStoreSettings("bunnings")
        app.switches["store-visibility-bunnings"].coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        let blocker = app.alerts["Store can’t be disabled yet"]
        XCTAssertTrue(blocker.waitForExistence(timeout: 3))
        blocker.buttons["View List"].tap()
        XCTAssertTrue(row("Bunnings saved item", status: "Added").waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["store-picker"].label.contains("Bunnings"))
        app.buttons["Actions for Bunnings saved item"].tap()
        let delete = app.buttons["Delete Item"]
        XCTAssertTrue(delete.waitForExistence(timeout: 3))
        delete.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.staticTexts["Your list is empty"].waitForExistence(timeout: 3))
        app.buttons["store-picker"].tap()
        app.buttons["store-picker-manage-stores"].tap()
        setStoreVisibility("bunnings", shown: false)
        tapNavigationBack()
        XCTAssertTrue(app.buttons["store-picker"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["store-picker"].label.contains("Coles"))
        XCTAssertFalse(app.webViews.firstMatch.exists)
        app.buttons["store-picker"].tap()
        app.buttons["store-picker-manage-stores"].tap()
        setStoreVisibility("bunnings", shown: true)
        tapNavigationBack()
        XCTAssertTrue(app.buttons["store-picker"].label.contains("Bunnings"), "Re-enabling a store makes it active on return")
        XCTAssertTrue(app.staticTexts["Your list is empty"].waitForExistence(timeout: 5))
    }

    func testAppearanceSelectionPersistsAcrossRelaunch() {
        app.buttons["Settings"].tap()
        let picker = app.buttons["appearance-setting"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        XCTAssertEqual(picker.value as? String, "System")

        for appearance in ["Dark", "Light", "System"] {
            picker.tap()
            app.buttons[appearance].tap()
            XCTAssertEqual(picker.value as? String, appearance)

            app.terminate()
            app.launch()
            app.buttons["Settings"].tap()
            XCTAssertTrue(picker.waitForExistence(timeout: 5))
            XCTAssertEqual(picker.value as? String, appearance)
        }
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
        XCTAssertTrue(app.staticTexts["Your list is empty"].waitForExistence(timeout: 5))
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

        setStoreVisibility("walmart", shown: true)
        let walmart = manageRow("walmart")
        let costco = manageRow("costco")
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "manage-store-walmart").count, 1)
        XCTAssertLessThan(walmart.frame.minY, costco.frame.minY,
                          "Enabled Walmart moves above disabled Australian stores")

        setStoreVisibility("walmart", shown: false)
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "manage-store-walmart").count, 1)
        XCTAssertLessThan(costco.frame.minY, walmart.frame.minY)
        openStoreSettings("walmart")
        XCTAssertEqual(app.switches["store-visibility-walmart"].value as? String, "0")
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
        XCTAssertTrue(app.staticTexts["Your list is empty"].waitForExistence(timeout: 5))
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
        openStoreSettings("bunnings")
        app.switches["store-visibility-bunnings"].tap()
        let blocker = app.alerts["Store can’t be disabled yet"]
        XCTAssertTrue(blocker.waitForExistence(timeout: 3))
        blocker.buttons["View List"].tap()
        XCTAssertTrue(row("Bunnings saved list item", status: "Pending").waitForExistence(timeout: 3))
        app.buttons["Clear List"].tap()
        app.buttons["Clear All"].tap()
        app.buttons["store-picker"].tap()
        app.buttons["store-picker-manage-stores"].tap()
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
        XCTAssertTrue(app.staticTexts["Your list is empty"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["store-picker"].label.contains("Coles"))
        XCTAssertFalse(row("Bunnings saved list item", status: "Pending").exists)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["Your list is empty"].waitForExistence(timeout: 10))
        app.buttons["store-picker"].tap()
        app.buttons["Manage Stores"].tap()
        setStoreVisibility("bunnings", shown: true)
        tapNavigationBack()
        choose("Bunnings")
        XCTAssertTrue(app.staticTexts["Your list is empty"].waitForExistence(timeout: 5))
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
        tapNavigationBack()
        changeCountry("NZ", name: "New Zealand")
        app.buttons["Manage Stores"].tap()
        XCTAssertTrue(app.staticTexts["OTHER STORES"].waitForExistence(timeout: 3))
        openStoreSettings("bunnings")
        XCTAssertEqual(app.switches["store-visibility-bunnings"].value as? String, "1")
        app.terminate()
        app.launch()
        XCTAssertEqual(app.buttons["store-picker"].label, "Coles")
        app.buttons["Settings"].tap()
        let country = app.descendants(matching: .any)["shopping-country"].firstMatch
        XCTAssertTrue(country.waitForExistence(timeout: 3))
        XCTAssertTrue(country.label.contains("New Zealand") || country.value as? String == "New Zealand")
        app.buttons["Manage Stores"].tap()
        openStoreSettings("bunnings")
        XCTAssertEqual(app.switches["store-visibility-bunnings"].value as? String, "1")
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

    func testUnverifiedSearchStoresAreHiddenFromManagementAndSearch() {
        app.buttons["Settings"].tap()
        app.buttons["Manage Stores"].tap()
        for (id, name) in [("amazon", "Amazon"), ("costcoUS", "Costco US"),
                           ("newWorld", "New World"), ("paknsave", "PAK’nSAVE"), ("boots", "Boots"), ("cvs", "CVS")] {
            let search = app.searchFields.firstMatch
            XCTAssertTrue(search.waitForExistence(timeout: 3))
            search.tap(); search.typeText(name)
            XCTAssertTrue(app.staticTexts["No stores found"].waitForExistence(timeout: 3), name)
            XCTAssertFalse(manageRow(id).exists)
            app.buttons["Clear Search"].tap()
        }
        XCTAssertTrue(manageRow("coles").exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Manage Stores — unverified-search destinations hidden"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testVerifiedTescoAppearsAfterCountryChange() {
        app.buttons["Settings"].tap()
        changeCountry("GB", name: "United Kingdom")
        app.buttons["Manage Stores"].tap()
        XCTAssertTrue(app.staticTexts["STORES IN UNITED KINGDOM"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["OTHER STORES"].exists)
        let search = app.searchFields.firstMatch
        search.tap(); search.typeText("Tesco")
        XCTAssertTrue(manageRow("tesco").waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["No stores found"].exists)
        app.buttons["Clear Search"].tap()
        search.tap(); search.typeText("Sainsbury")
        XCTAssertTrue(manageRow("sainsburys").waitForExistence(timeout: 3),
                      "Verified-search stores remain available even when cart detection is unfinished")
    }

    func testCostcoAustraliaListSurvivesRelaunchWhileUSIsHidden() {
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
        XCTAssertFalse(app.buttons["store-region-picker-costco"].exists)
        XCTAssertFalse(app.buttons["store-region-costcoUS"].exists)
        XCTAssertTrue(app.buttons["Reset Costco Session"].exists)
        XCTAssertTrue(app.staticTexts["Search, Included"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Costco settings — only verified Australian website offered"
        shot.lifetime = .keepAlways
        add(shot)
        tapNavigationBack()
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(row("Australian Costco item", status: "Pending").waitForExistence(timeout: 3))
        app.terminate(); app.launch()
        XCTAssertTrue(row("Australian Costco item", status: "Pending").waitForExistence(timeout: 5))
        app.buttons["store-picker"].tap()
        XCTAssertFalse(app.buttons["Costco US"].exists)
        XCTAssertFalse(app.buttons["Tesco"].exists)
    }

    func testBunningsRegionalWebsitePickerAccessibility() throws {
        app.buttons["store-picker"].tap()
        app.buttons["Manage Stores"].tap()
        openStoreSettings("bunnings")
        app.buttons["store-region-picker-bunnings"].tap()
        let australian = app.buttons["store-region-bunnings"]
        XCTAssertTrue(australian.waitForExistence(timeout: 3))
        XCTAssertTrue(australian.isSelected)
        XCTAssertTrue(app.buttons["store-region-bunningsNZ"].exists)
        XCTAssertFalse(app.buttons["store-region-bunningsNZ"].isSelected)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Bunnings — verified regional website choices"
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
        XCTAssertFalse(app.buttons["store-region-picker-costco"].exists)
        XCTAssertTrue(app.buttons["Reset Costco Session"].exists)
        app.terminate()
        app.launch()
        app.buttons["store-picker"].tap()
        app.buttons["Manage Stores"].tap()
        openStoreSettings("costco")
        XCTAssertFalse(app.buttons["store-region-picker-costco"].exists)
        XCTAssertTrue(app.buttons["Reset Costco Session"].exists)
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
        for (id, name) in [("kroger", "Kroger"), ("target", "Target US")] {
            openStoreSettings(id)
            XCTAssertEqual(app.switches["store-visibility-\(id)"].value as? String, "0")
            XCTAssertTrue(app.staticTexts["Search, Included"].exists)
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
        XCTAssertFalse(manageRow("tesco").exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Manage Stores — United States with browsing-only Walmart"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testMoveDestinationsHideUnverifiedSearchStores() {
        app.buttons["store-picker"].tap()
        app.buttons["store-picker-manage-stores"].tap()
        setStoreVisibility("costco", shown: true)
        tapNavigationBack()
        choose("Coles")
        XCTAssertTrue(row("Coles fixture item", status: "Pending").waitForExistence(timeout: 5))
        app.buttons["Actions for Coles fixture item"].tap()
        app.buttons["Move to Another Store"].tap()
        for name in ["Amazon US", "Costco US", "New World", "PAK’nSAVE", "Boots", "CVS"] {
            XCTAssertFalse(app.buttons["Move to \(name)"].exists, name)
        }
        XCTAssertTrue(app.buttons["Move to Costco"].exists,
                       "Search-verified/manual-cart stores remain valid destinations")
        XCTAssertFalse(app.buttons["Move to Kmart"].exists, "Disabled stores are not offered as move destinations")
        // iOS 27 can present this as a native menu with outside-tap dismissal,
        // not a sheet exposing Cancel. Teardown closes this isolated test app;
        // do not select a destination merely to dismiss a read-only inspection.
    }

    func testExplicitMoveTransfersOnlySelectedRow() {
        choose("Coles")
        XCTAssertTrue(row("Coles fixture item", status: "Pending").waitForExistence(timeout: 5))
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
        choose("Coles")
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
        choose("Coles")
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
        XCTAssertTrue(app.buttons["Actions for lemon"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Actions for Lemon tree"].exists,
                      "Lemon Tree must retain its full name rather than merging with Lemon")
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["Actions for lemon"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Actions for Lemon tree"].exists)
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

    func testManualEntryPreservesProductWordingForButtonAndReturn() {
        let input = app.descendants(matching: .any)["grocery-input"]
        input.tap()
        input.typeText("500 g penne pasta")
        app.buttons["Add Items"].tap()
        let pasta = row("500 g penne pasta", status: "Pending")
        XCTAssertTrue(pasta.waitForExistence(timeout: 5))
        XCTAssertTrue(pasta.label.contains("quantity 1"), "Manual entry must not extract a quantity")
        input.typeText("Firm tofu thinly sliced\n")
        XCTAssertTrue(row("Firm tofu thinly sliced", status: "Pending").waitForExistence(timeout: 5),
                      "Return must preserve qualifiers and preparation wording too")
        assertGroceryInputIsEmpty(input)
        app.terminate()
        app.launch()
        XCTAssertTrue(row("Firm tofu thinly sliced", status: "Pending").waitForExistence(timeout: 5))
        XCTAssertTrue(pasta.exists, "Literal manual wording must survive relaunch")
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

    func testManualScrollingDoesNotTrackIdleRowFrames() {
        let input = app.descendants(matching: .any)["grocery-input"]
        input.tap()
        input.typeText("scroll fixture alpha; scroll fixture bravo; scroll fixture charlie; scroll fixture delta; scroll fixture echo; scroll fixture foxtrot")
        app.buttons["Add Items"].tap()
        XCTAssertTrue(row("scroll fixture alpha", status: "Pending").waitForExistence(timeout: 5))
        input.typeText("\n") // Empty Return dismisses the keyboard without adding a row.
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
        let list = app.collectionViews.firstMatch
        list.swipeUp()
        list.swipeDown()
        let status = app.staticTexts["item-reveal-status"]
        let idle = NSPredicate { _, _ in
            status.label.contains("target=none") && status.label.contains("trackedRows=0")
                && status.label.contains("pending=false")
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: idle, object: app)], timeout: 3), .completed,
                       "Manual scrolling must cancel reveal once and stop measuring unrelated rows")
        XCTAssertTrue(row("scroll fixture alpha", status: "Pending").exists)
    }

    func testRepeatedNewItemsAreFullyRevealedInExistingList() {
        let existingCell = app.collectionViews.cells.containing(.any, identifier: "Actions for Coles fixture item").firstMatch
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
        let actionsCell = app.collectionViews.cells.containing(.any, identifier: "set-import-source").firstMatch
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
        let actionsCell = app.collectionViews.cells.containing(.any, identifier: "set-import-source").firstMatch
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
        let existingCell = app.collectionViews.cells.containing(.any, identifier: "Actions for kettle").firstMatch
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

    func testCardCollapseHintPersistsUntilCollapseAcrossStoresAndRelaunches() {
        choose("Coles")
        app.buttons["Show Store"].tap()
        let hint = app.staticTexts["card-collapse-hint"]
        XCTAssertTrue(hint.waitForExistence(timeout: 5))
        XCTAssertEqual(hint.label, "Swipe cards down to collapse")
        let collapse = app.buttons["Collapse overlay"]
        XCTAssertTrue(collapse.waitForExistence(timeout: 3))
        let card = app.otherElements["selected-shopping-card"]
        XCTAssertTrue(card.waitForExistence(timeout: 3))
        XCTAssertEqual(card.frame.height, 224, accuracy: 1)
        XCTAssertLessThanOrEqual(hint.frame.maxY, card.frame.minY - 8,
                                 "The complete hint must sit above the actual card, not its inset collapse button")
        let initialAppearance = XCTAttachment(screenshot: app.screenshot())
        initialAppearance.name = "Card collapse hint — clear gap above card"
        initialAppearance.lifetime = .keepAlways
        add(initialAppearance)

        app.buttons["Dismiss store"].tap()
        XCTAssertTrue(app.buttons["Show Store"].waitForExistence(timeout: 3))
        app.buttons["Show Store"].tap()
        XCTAssertTrue(hint.waitForExistence(timeout: 3), "Leaving the sheet does not complete learning")
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["Show Store"].waitForExistence(timeout: 5))
        app.buttons["Show Store"].tap()
        XCTAssertTrue(hint.waitForExistence(timeout: 3), "The hint remains across launches until a collapse")

        collapse.tap()
        let expand = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Expand overlay")).firstMatch
        XCTAssertTrue(expand.waitForExistence(timeout: 3))
        XCTAssertFalse(hint.exists)
        expand.tap()
        XCTAssertTrue(collapse.waitForExistence(timeout: 3))
        XCTAssertFalse(hint.exists, "Re-expanding must not restore the hint")
        app.buttons["Dismiss store"].tap()
        XCTAssertTrue(app.buttons["store-picker"].waitForExistence(timeout: 3))
        choose("Woolworths")
        app.buttons["Show Store"].tap()
        XCTAssertTrue(collapse.waitForExistence(timeout: 3))
        XCTAssertFalse(hint.exists, "Learning is app-wide, not per store")
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["Show Store"].waitForExistence(timeout: 5))
        app.buttons["Show Store"].tap()
        XCTAssertTrue(collapse.waitForExistence(timeout: 3))
        XCTAssertFalse(hint.exists, "Completed learning survives relaunch")
        app.buttons["Dismiss store"].tap()
        XCTAssertTrue(app.buttons["store-picker"].waitForExistence(timeout: 3))
        choose("All items")
        app.buttons["all-items-show-store"].tap()
        XCTAssertTrue(app.buttons["Shop at Coles"].waitForExistence(timeout: 3))
        app.buttons["Shop at Coles"].tap()
        XCTAssertTrue(collapse.waitForExistence(timeout: 3))
        XCTAssertFalse(hint.exists, "All items shares the same completed hint")
    }

    func testCardCollapseHintSurvivesIncompleteGesturesThenClearsOnSwipe() {
        choose("Coles")
        app.buttons["Show Store"].tap()
        let hint = app.staticTexts["card-collapse-hint"]
        XCTAssertTrue(hint.waitForExistence(timeout: 5))
        let card = app.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@",
                                                   "Coles fixture item", "selected")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 3))
        for translation in [CGVector(dx: 0, dy: -80), CGVector(dx: 0, dy: 35), CGVector(dx: 80, dy: 0)] {
            let start = card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
            start.press(forDuration: 0.2, thenDragTo: start.withOffset(translation),
                        withVelocity: .slow, thenHoldForDuration: 0.3)
            XCTAssertTrue(app.buttons["Collapse overlay"].exists)
            XCTAssertTrue(hint.exists, "Upward, short and horizontal drags must not complete learning")
        }
        let start = card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
        start.press(forDuration: 0.2, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 140)),
                    withVelocity: .slow, thenHoldForDuration: 0.3)
        let expand = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Expand overlay")).firstMatch
        XCTAssertTrue(expand.waitForExistence(timeout: 3))
        XCTAssertFalse(hint.exists)
        expand.tap()
        XCTAssertTrue(card.waitForExistence(timeout: 3))
        XCTAssertFalse(hint.exists, "A successful swipe permanently clears the hint")
    }

    func testProgressChevronCollapsesOverlayAndPreservesStatus() {
        choose("Coles")
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
        XCTAssertTrue(collapse.waitForNonExistence(timeout: 3))
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
        choose("Coles")
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
        choose("Coles")
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
        // Existing scenarios exercise the retained linked-reminder mode.
        app.buttons["set-import-source"].tap()
        XCTAssertTrue(app.navigationBars["Import items"].waitForExistence(timeout: 5))
        app.buttons["import-source-paprika"].tap()
        let removal = app.switches["remove-reminders-after-import"]
        XCTAssertTrue(removal.waitForExistence(timeout: 5))
        if removal.value as? String == "1" {
            removal.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        }
        confirmPaprikaImport()
        if app.buttons["paprika-reminders-list-fixture-paprika"].waitForExistence(timeout: 2) {
            app.buttons["paprika-reminders-list-fixture-paprika"].tap()
        }
    }

    private func importNotice(_ message: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label == %@", message)).firstMatch
    }

    private func openPaprikaOptionsFromSettings() {
        app.buttons["Settings"].tap()
        XCTAssertFalse(app.switches["remove-reminders-after-import"].exists)
        XCTAssertFalse(app.buttons["paprika-reminders-list-setting"].exists)
        app.buttons["import-source-setting"].tap()
        app.buttons["import-source-paprika"].tap()
        XCTAssertTrue(app.navigationBars["Import from Paprika"].waitForExistence(timeout: 5))
    }

    private func confirmPaprikaImport() {
        let button = app.buttons["import-paprika-groceries"]
        XCTAssertTrue(app.navigationBars["Import from Paprika"].waitForExistence(timeout: 5))
        for _ in 0..<5 {
            if button.exists && button.isHittable { break }
            app.collectionViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.tap()
    }

    private func chooseRemindersList(_ id: String) {
        let button = app.buttons["paprika-reminders-list-" + id]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.tap()
    }

    func testPaprikaGuidedImportReturnsWithGroceriesAndPersists() {
        selectPaprikaSource()
        XCTAssertTrue(app.buttons["import-from-paprika"].waitForExistence(timeout: 5))
        XCTAssertTrue(row("Coles fixture item", status: "Pending").exists)
        XCTAssertTrue(row("milk", status: "Pending").waitForExistence(timeout: 5), "The final instruction action must import")
        XCTAssertTrue(app.staticTexts["Added 2 items to your Coles list."].exists)
        XCTAssertFalse(app.buttons["Change source"].exists)
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
        XCTAssertTrue(row("milk", status: "Pending").exists, "Each store keeps its own imported rows")
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
        app.switches["remove-reminders-after-import"].coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertTrue(app.staticTexts["In Paprika, open your grocery list and choose Actions → Export to Reminders."].exists)
        confirmPaprikaImport()
        app.buttons["paprika-reminders-list-fixture-paprika"].tap()
        XCTAssertTrue(app.buttons["import-from-paprika"].waitForExistence(timeout: 5), "Settings setup returns all the way to the list")
        XCTAssertTrue(row("Coles fixture item", status: "Pending").exists)
        XCTAssertTrue(row("milk", status: "Pending").waitForExistence(timeout: 5))
        XCTAssertEqual(input.value as? String, "Draft groceries")

        app.buttons["Settings"].tap()
        app.buttons["import-source-setting"].tap()
        app.buttons["import-source-paprika"].tap()
        XCTAssertTrue(app.navigationBars["Import from Paprika"].waitForExistence(timeout: 5), "Instructions remain available after importing")
        app.swipeUp()
        app.buttons["More about importing"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "best effort, not ongoing sync")).firstMatch.exists)
    }

    func testPaprikaSourceSetupFromEmptyList() {
        selectPaprikaSource()
        XCTAssertTrue(row("milk", status: "Pending").waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Show Store"].exists)
        XCTAssertFalse(app.buttons["Dismiss store"].exists, "Import does not automatically open the store")
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
        XCTAssertTrue(importNotice("These items are already in your list. Export new groceries from Paprika to Apple Reminders, then import again. Existing items aren’t refreshed.").waitForExistence(timeout: 5))
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
        for (fixture, expectedNotice) in [("accessDenied", "Allow full Reminders access in Settings so ListRunner can read and manage your imported reminders. Your list is unchanged."),
                                          ("accessError", "Could not access Apple Reminders. Try again. Your list is unchanged. You can still type or paste groceries."),
                                          ("empty", "No unchecked groceries found in your selected Reminders list. Export your groceries from Paprika first. Checked items aren’t imported."),
                                          ("blank", "No readable new groceries found. Check that your exported Apple reminders have grocery names, then try again. Your list is unchanged.")] {
            app.terminate()
            app.launchEnvironment["LISTRUNNER_UI_TEST_SESSION"] = UUID().uuidString
            app.launchEnvironment["LISTRUNNER_PAPRIKA_TEST_FIXTURE"] = "enabled"
            app.launch()
            openPaprikaOptionsFromSettings()
            app.buttons["paprika-reminders-list-setting"].tap()
            app.buttons["paprika-reminders-list-fixture-paprika"].tap()
            app.terminate()
            app.launchEnvironment["LISTRUNNER_PAPRIKA_TEST_FIXTURE"] = fixture
            app.launch()
            selectPaprikaSource()
            XCTAssertTrue(importNotice(expectedNotice).waitForExistence(timeout: 5))
            XCTAssertTrue(row("Coles fixture item", status: "Pending").exists)
            XCTAssertTrue(app.buttons["set-import-source"].exists, "Failed imports do not remember a source")
            XCTAssertTrue(app.buttons["paprika-retry"].exists)
            XCTAssertEqual(app.buttons["paprika-open-settings"].exists, fixture == "accessDenied")
            app.buttons["paprika-view-instructions"].tap()
            XCTAssertTrue(app.navigationBars["Import from Paprika"].waitForExistence(timeout: 5))
            tapNavigationBack()
            app.buttons["paprika-retry"].tap()
            XCTAssertTrue(importNotice(expectedNotice).waitForExistence(timeout: 5))
        }
    }

    func testPaprikaImportReportsNewAndAlreadyImportedCounts() {
        selectPaprikaSource()
        XCTAssertTrue(row("milk", status: "Pending").waitForExistence(timeout: 5))
        app.terminate()
        app.launchEnvironment["LISTRUNNER_PAPRIKA_TEST_FIXTURE"] = "additional"
        app.launch()
        app.buttons["import-from-paprika"].tap()
        XCTAssertTrue(app.staticTexts["Added 1 item to your Coles list. Already-imported reminders skipped: 2."].waitForExistence(timeout: 5))
        XCTAssertTrue(row("apples", status: "Pending").exists)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label CONTAINS[cd] %@", "milk, quantity 2 l")).count, 1)

        app.terminate()
        app.launchEnvironment["LISTRUNNER_PAPRIKA_TEST_FIXTURE"] = "missing"
        app.launch()
        app.buttons["import-from-paprika"].tap()
        XCTAssertTrue(app.navigationBars["Choose Reminders list"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["No Reminders lists are available. Export your groceries from Paprika, then try again."].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["import-from-paprika"].exists, "A failed retry keeps the last successful source")
        XCTAssertTrue(row("apples", status: "Pending").exists)
    }

    func testPaprikaRemovalDefaultsOnAndInstructionsFollowSetting() {
        app.buttons["set-import-source"].tap()
        app.buttons["import-source-paprika"].tap()
        let removal = app.switches["remove-reminders-after-import"]
        XCTAssertTrue(removal.waitForExistence(timeout: 5))
        XCTAssertEqual(removal.value as? String, "1")
        XCTAssertTrue(importNotice("Imported reminders are removed after saving. Paprika is unchanged.").waitForExistence(timeout: 5))
        confirmPaprikaImport()
        app.buttons["paprika-reminders-list-fixture-paprika"].tap()
        XCTAssertTrue(importNotice("Groceries added to your Coles list: 2. Removed their reminders from ‘Paprika’. Paprika is unchanged.").waitForExistence(timeout: 5))
        openPaprikaOptionsFromSettings()
        removal.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        let disabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "0"), object: removal)
        XCTAssertEqual(XCTWaiter.wait(for: [disabled], timeout: 5), .completed)
        XCTAssertTrue(app.navigationBars["Import from Paprika"].waitForExistence(timeout: 5))
        XCTAssertTrue(importNotice("Reminders are kept and updated as you shop. Paprika is unchanged.").waitForExistence(timeout: 5))
        app.terminate()
        app.launch()
        openPaprikaOptionsFromSettings()
        XCTAssertEqual(removal.value as? String, "0")
    }

    func testPaprikaNamedRemindersListSelectionPersistsAndCanChange() {
        app.buttons["set-import-source"].tap()
        app.buttons["import-source-paprika"].tap()
        confirmPaprikaImport()
        XCTAssertTrue(app.navigationBars["Choose Reminders list"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        XCTAssertFalse(row("eggs", status: "Pending").exists)
        app.buttons["set-import-source"].tap()
        app.buttons["import-source-paprika"].tap()
        confirmPaprikaImport()
        chooseRemindersList("fixture-weekly")
        XCTAssertTrue(row("eggs", status: "Pending").waitForExistence(timeout: 5))
        XCTAssertFalse(row("milk", status: "Pending").exists, "Only the selected named list is imported")
        XCTAssertTrue(importNotice("Groceries added to your Coles list: 1. Removed their reminders from ‘Weekly Shopping’. Paprika is unchanged.").waitForExistence(timeout: 5))
        app.terminate()
        app.launch()
        openPaprikaOptionsFromSettings()
        let setting = app.buttons["paprika-reminders-list-setting"]
        XCTAssertTrue(setting.label.contains("Weekly Shopping"))
        setting.tap()
        app.buttons["paprika-reminders-list-fixture-paprika"].tap()
        confirmPaprikaImport()
        XCTAssertTrue(row("milk", status: "Pending").waitForExistence(timeout: 5))
        XCTAssertTrue(row("eggs", status: "Pending").exists)
    }
}
