import UIKit
import WebKit

public class StoreSessionViewController: UIViewController, WKNavigationDelegate {
    var webView: WKWebView!
    var overlayView: UIView!
    var currentItemLabel: UILabel!
    var searchInput: UITextField!
    var plugin: StoreSessionPlugin?

    private var activeStoreId: String?

    public override func viewDidLoad() {
        super.viewDidLoad()
        setupWebView()
        setupOverlay()
    }

    private func setupWebView() {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        webView = WKWebView(frame: view.bounds, configuration: config)
        webView.navigationDelegate = self
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(webView)
    }

    private func setupOverlay() {
        overlayView = UIView()
        overlayView.backgroundColor = UIColor.white.withAlphaComponent(0.95)
        overlayView.layer.shadowColor = UIColor.black.cgColor
        overlayView.layer.shadowOpacity = 0.2
        overlayView.layer.shadowOffset = CGSize(width: 0, height: -2)
        overlayView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(overlayView)

        NSLayoutConstraint.activate([
            overlayView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            overlayView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            overlayView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            overlayView.heightAnchor.constraint(equalToConstant: 200)
        ])

        currentItemLabel = UILabel()
        currentItemLabel.font = UIFont.boldSystemFont(ofSize: 18)
        currentItemLabel.translatesAutoresizingMaskIntoConstraints = false
        overlayView.addSubview(currentItemLabel)

        searchInput = UITextField()
        searchInput.borderStyle = .roundedRect
        searchInput.placeholder = "Search term..."
        searchInput.translatesAutoresizingMaskIntoConstraints = false
        overlayView.addSubview(searchInput)

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
        webView.load(URLRequest(url: url))
    }

    public func setStore(storeId: String) {
        activeStoreId = storeId
    }

    public func performSearch(query: String) {
        guard let storeId = activeStoreId else { return }

        if storeId == "coles-au" {
            let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
            let searchURL = "https://www.coles.com.au/search?q=\(encodedQuery)"
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

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        plugin?.notifyEvent(eventName: "pageReady")
    }

    @objc func skipTapped() {
        plugin?.notifyEvent(eventName: "skipRequested")
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
