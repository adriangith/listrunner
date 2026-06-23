import UIKit
import WebKit

public class StoreSessionViewController: UIViewController, WKNavigationDelegate, WKScriptMessageHandler {
    var webView: WKWebView!
    var overlayView: UIView!
    var currentItemLabel: UILabel!
    var searchInput: UITextField!
    var plugin: StoreSessionPlugin?

    private var activeStoreId: String?
    private var automationLoaded = false

    public override func viewDidLoad() {
        super.viewDidLoad()
        setupWebView()
        setupOverlay()
    }

    private func setupWebView() {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true

        // Add script message handler for JS bridge
        let contentController = WKUserContentController()
        contentController.add(self, name: "storeSessionBridge")
        config.userContentController = contentController

        webView = WKWebView(frame: view.bounds, configuration: config)
        webView.navigationDelegate = self
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(webView)

        // Send page events to JS bridge
        let readyScript = WKUserScript(
            source: "window.webkit.messageHandlers.storeSessionBridge.postMessage({type: 'pageLoaded'});",
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        webView.configuration.userContentController.addUserScript(readyScript)
    }

    private func setupOverlay() {
        // Create overlay container
        overlayView = UIView()
        overlayView.backgroundColor = UIColor.white.withAlphaComponent(0.95)
        overlayView.layer.shadowColor = UIColor.black.cgColor
        overlayView.layer.shadowOpacity = 0.2
        overlayView.layer.shadowOffset = CGSize(width: 0, height: -2)
        overlayView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(overlayView)

        // Position at bottom
        NSLayoutConstraint.activate([
            overlayView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            overlayView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            overlayView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            overlayView.heightAnchor.constraint(equalToConstant: 200)
        ])

        // Current item label
        currentItemLabel = UILabel()
        currentItemLabel.font = UIFont.boldSystemFont(ofSize: 18)
        currentItemLabel.translatesAutoresizingMaskIntoConstraints = false
        overlayView.addSubview(currentItemLabel)

        // Search input
        searchInput = UITextField()
        searchInput.borderStyle = .roundedRect
        searchInput.placeholder = "Search term..."
        searchInput.translatesAutoresizingMaskIntoConstraints = false
        overlayView.addSubview(searchInput)

        // Buttons
        let skipBtn = UIButton(type: .system)
        skipBtn.setTitle("Skip", for: .normal)
        skipBtn.addTarget(self, action: #selector(skipTapped), for: .touchUpInside)
        skipBtn.translatesAutoresizingMaskIntoConstraints = false
        overlayView.addSubview(skipBtn)

        let addedBtn = UIButton(type: .system)
        addedBtn.setTitle("Added", for: .normal)
        addedBtn.addTarget(self, action: #selector(addedTapped), for: .touchUpInside)
        addedBtn.translatesAutoresizingMaskIntoConstraints = false
        overlayView.addSubview(addedBtn)

        NSLayoutConstraint.activate([
            currentItemLabel.topAnchor.constraint(equalTo: overlayView.topAnchor, constant: 16),
            currentItemLabel.leadingAnchor.constraint(equalTo: overlayView.leadingAnchor, constant: 16),

            searchInput.topAnchor.constraint(equalTo: currentItemLabel.bottomAnchor, constant: 8),
            searchInput.leadingAnchor.constraint(equalTo: overlayView.leadingAnchor, constant: 16),
            searchInput.trailingAnchor.constraint(equalTo: overlayView.trailingAnchor, constant: -16),

            skipBtn.topAnchor.constraint(equalTo: searchInput.bottomAnchor, constant: 12),
            skipBtn.leadingAnchor.constraint(equalTo: overlayView.leadingAnchor, constant: 16),

            addedBtn.topAnchor.constraint(equalTo: searchInput.bottomAnchor, constant: 12),
            addedBtn.leadingAnchor.constraint(equalTo: skipBtn.trailingAnchor, constant: 16),
        ])
    }

    public func loadStore(url: URL, storeId: String) {
        activeStoreId = storeId
        automationLoaded = false
        webView.load(URLRequest(url: url))
    }

    public func setStore(storeId: String) {
        activeStoreId = storeId
    }

    public func performSearch(query: String) {
        guard let storeId = activeStoreId else { return }

        // This is a simplified version - for Coles AU, we can navigate to search URL
        // In a full implementation, we'd inject JavaScript to fill search inputs
        if storeId == "coles-au" {
            let searchURL = "https://www.coles.com.au/search?q=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query)"
            if let url = URL(string: searchURL) {
                webView.load(URLRequest(url: url))
            }
        }
    }

    public func updateOverlay(itemName: String, searchTerm: String) {
        DispatchQueue.main.async {
            self.currentItemLabel.text = itemName
            self.searchInput.text = searchTerm
        }
    }

    // MARK: - WKNavigationDelegate

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        plugin?.notifyEvent(eventName: "pageReady")
    }

    // MARK: - WKScriptMessageHandler

    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let dict = message.body as? [String: Any],
              let type = dict["type"] as? String else { return }

        switch type {
        case "pageLoaded":
            plugin?.notifyEvent(eventName: "pageReady")
        case "addToCartDetected":
            let productName = dict["productName"] as? String ?? "Unknown"
            let productImageUrl = dict["productImageUrl"] as? String
            plugin?.notifyEvent(eventName: "addToCartDetected", data: [
                "productName": productName,
                "productImageUrl": productImageUrl ?? ""
            ])
        default:
            break
        }
    }

    // MARK: - Button Actions

    @objc func skipTapped() {
        plugin?.notifyEvent(eventName: "selectorReady") // Simplified - should send SKIP action
    }

    @objc func addedTapped() {
        plugin?.notifyEvent(eventName: "addToCartDetected", data: [
            "productName": searchInput.text ?? "Unknown",
            "productImageUrl": ""
        ])
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        webView.frame = view.bounds
    }
}
