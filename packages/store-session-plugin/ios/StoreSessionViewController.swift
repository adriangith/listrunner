import UIKit
import WebKit

struct StoreSessionOverlayCard {
    let id: String
    let title: String
    let quantity: String
    let state: String
    let badge: String?
}

struct StoreSessionOverlayPayload {
    let mode: String
    let cards: [StoreSessionOverlayCard]
    let activeIndex: Int
    let primaryAction: String
    let secondaryAction: String
    let cooldownSeconds: Int?
    let cooldownProgress: Double?
    let itemName: String
    let searchTerm: String
}

public class StoreSessionViewController: UIViewController, WKNavigationDelegate, WKScriptMessageHandler {
    var webView: WKWebView!
    var overlayView: UIView!
    private let carouselStack = UIStackView()
    private let secondaryButton = UIButton(type: .system)
    private let primaryButton = UIButton(type: .system)
    private let progressView = UIProgressView(progressViewStyle: .bar)
    var plugin: StoreSessionPlugin?

    private var currentPayload: StoreSessionOverlayPayload?
    private var activeStoreId: String?
    private var pendingStoreURL: URL?
    private var automationLoaded = false

    public override func viewDidLoad() {
        super.viewDidLoad()
        setupWebView()
        setupOverlay()
        loadPendingStoreIfReady()
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

        // Inject the cart-detection content script (posts pageLoaded and addToCartDetected).
        if let scriptURL = Bundle.module.url(forResource: "cart-detection", withExtension: "js", subdirectory: "Resources"),
           let scriptSource = try? String(contentsOf: scriptURL, encoding: .utf8) {
            let cartScript = WKUserScript(
                source: scriptSource,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
            webView.configuration.userContentController.addUserScript(cartScript)
        } else {
            let readyScript = WKUserScript(
                source: "window.webkit.messageHandlers.storeSessionBridge.postMessage({type: 'pageLoaded'});",
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
            webView.configuration.userContentController.addUserScript(readyScript)
        }
    }

    private func setupOverlay() {
        overlayView = UIView()
        overlayView.backgroundColor = UIColor.white.withAlphaComponent(0.94)
        overlayView.layer.shadowColor = UIColor.black.cgColor
        overlayView.layer.shadowOpacity = 0.12
        overlayView.layer.shadowRadius = 18
        overlayView.layer.shadowOffset = CGSize(width: 0, height: -8)
        overlayView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(overlayView)

        carouselStack.axis = .horizontal
        carouselStack.alignment = .center
        carouselStack.distribution = .equalSpacing
        carouselStack.spacing = 10
        carouselStack.translatesAutoresizingMaskIntoConstraints = false
        overlayView.addSubview(carouselStack)

        secondaryButton.translatesAutoresizingMaskIntoConstraints = false
        primaryButton.translatesAutoresizingMaskIntoConstraints = false
        progressView.translatesAutoresizingMaskIntoConstraints = false
        overlayView.addSubview(secondaryButton)
        overlayView.addSubview(primaryButton)
        primaryButton.addSubview(progressView)

        styleActionButton(secondaryButton, background: UIColor(red: 0.94, green: 0.95, blue: 0.97, alpha: 1), foreground: .darkText)
        styleActionButton(primaryButton, background: UIColor(red: 0.00, green: 0.48, blue: 1.00, alpha: 1), foreground: .white)

        secondaryButton.addTarget(self, action: #selector(secondaryTapped), for: .touchUpInside)
        primaryButton.addTarget(self, action: #selector(primaryTapped), for: .touchUpInside)

        NSLayoutConstraint.activate([
            overlayView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            overlayView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            overlayView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            overlayView.heightAnchor.constraint(equalToConstant: 202),

            carouselStack.leadingAnchor.constraint(equalTo: overlayView.leadingAnchor, constant: -42),
            carouselStack.trailingAnchor.constraint(equalTo: overlayView.trailingAnchor, constant: 42),
            carouselStack.topAnchor.constraint(equalTo: overlayView.topAnchor, constant: -92),
            carouselStack.heightAnchor.constraint(equalToConstant: 182),

            secondaryButton.leadingAnchor.constraint(equalTo: overlayView.leadingAnchor, constant: 20),
            secondaryButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -10),
            secondaryButton.widthAnchor.constraint(equalToConstant: 108),
            secondaryButton.heightAnchor.constraint(equalToConstant: 44),

            primaryButton.leadingAnchor.constraint(equalTo: secondaryButton.trailingAnchor, constant: 12),
            primaryButton.trailingAnchor.constraint(equalTo: overlayView.trailingAnchor, constant: -20),
            primaryButton.bottomAnchor.constraint(equalTo: secondaryButton.bottomAnchor),
            primaryButton.heightAnchor.constraint(equalToConstant: 44),

            progressView.leadingAnchor.constraint(equalTo: primaryButton.leadingAnchor, constant: 16),
            progressView.trailingAnchor.constraint(equalTo: primaryButton.trailingAnchor, constant: -16),
            progressView.bottomAnchor.constraint(equalTo: primaryButton.bottomAnchor, constant: -8),
            progressView.heightAnchor.constraint(equalToConstant: 4),
        ])
    }

    public func loadStore(url: URL, storeId: String) {
        activeStoreId = storeId
        pendingStoreURL = url
        automationLoaded = false
        loadPendingStoreIfReady()
    }

    private func loadPendingStoreIfReady() {
        guard let webView = webView, let url = pendingStoreURL else { return }
        pendingStoreURL = nil
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

    public func updateOverlay(payload: StoreSessionOverlayPayload) {
        DispatchQueue.main.async {
            self.currentPayload = payload
            self.renderOverlay()
        }
    }

    // MARK: - Helpers

    private func styleActionButton(_ button: UIButton, background: UIColor, foreground: UIColor) {
        button.backgroundColor = background
        button.setTitleColor(foreground, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        button.layer.cornerRadius = 10
        button.clipsToBounds = true
    }

    private func backgroundColor(for state: String) -> UIColor {
        switch state {
        case "current", "currentAdded":
            return UIColor(red: 0.00, green: 0.48, blue: 1.00, alpha: 1)
        case "added":
            return UIColor(red: 0.88, green: 1.00, blue: 0.92, alpha: 1)
        default:
            return UIColor(red: 0.98, green: 0.97, blue: 0.94, alpha: 1)
        }
    }

    private func textColor(for state: String) -> UIColor {
        return state == "current" || state == "currentAdded" ? .white : UIColor(red: 0.17, green: 0.19, blue: 0.23, alpha: 1)
    }

    private func addBadge(text: String, to cardView: UIView, color: UIColor) {
        let badge = UILabel()
        badge.text = text
        badge.textAlignment = .center
        badge.textColor = .white
        badge.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
        badge.backgroundColor = color
        badge.layer.cornerRadius = 11
        badge.clipsToBounds = true
        badge.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(badge)
        NSLayoutConstraint.activate([
            badge.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 14),
            badge.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 13),
            badge.widthAnchor.constraint(equalToConstant: text == "Manual" ? 72 : 78),
            badge.heightAnchor.constraint(equalToConstant: 22),
        ])
    }

    private func makeCard(_ card: StoreSessionOverlayCard) -> UIView {
        let cardView = UIView()
        cardView.translatesAutoresizingMaskIntoConstraints = false
        cardView.layer.cornerRadius = 18
        cardView.clipsToBounds = false
        cardView.backgroundColor = backgroundColor(for: card.state)
        cardView.layer.shadowColor = UIColor.black.cgColor
        cardView.layer.shadowOpacity = 0.12
        cardView.layer.shadowRadius = 12
        cardView.layer.shadowOffset = CGSize(width: 0, height: 6)

        let titleLabel = UILabel()
        titleLabel.text = card.title
        titleLabel.numberOfLines = 2
        titleLabel.textAlignment = .center
        titleLabel.font = UIFont.systemFont(ofSize: card.state == "inactive" ? 16 : 19, weight: .semibold)
        titleLabel.textColor = textColor(for: card.state)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(titleLabel)

        let quantityLabel = UILabel()
        quantityLabel.text = card.quantity
        quantityLabel.textAlignment = .center
        quantityLabel.font = UIFont.systemFont(ofSize: card.state == "inactive" ? 12 : 46, weight: .bold)
        quantityLabel.textColor = textColor(for: card.state)
        quantityLabel.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(quantityLabel)

        if let badge = card.badge {
            addBadge(text: badge, to: cardView, color: UIColor(red: 0.93, green: 0.55, blue: 0.10, alpha: 1))
        } else if card.state == "currentAdded" || card.state == "added" {
            addBadge(text: "✓ Added", to: cardView, color: UIColor(red: 0.10, green: 0.62, blue: 0.33, alpha: 1))
        } else {
            let dot = UIView()
            dot.backgroundColor = card.state == "current" ? .white : UIColor(red: 0.86, green: 0.88, blue: 0.91, alpha: 1)
            dot.layer.cornerRadius = 7
            dot.translatesAutoresizingMaskIntoConstraints = false
            cardView.addSubview(dot)
            NSLayoutConstraint.activate([
                dot.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 14),
                dot.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 14),
                dot.widthAnchor.constraint(equalToConstant: 14),
                dot.heightAnchor.constraint(equalToConstant: 14),
            ])
        }

        let actionTitle = card.state == "current" ? "Mark added" : card.state == "currentAdded" ? "Add another" : nil
        var actionButton: UIButton?
        if let actionTitle = actionTitle {
            let button = UIButton(type: .system)
            button.setTitle(actionTitle, for: .normal)
            button.titleLabel?.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
            button.backgroundColor = .white
            button.layer.cornerRadius = 14
            button.translatesAutoresizingMaskIntoConstraints = false
            button.addTarget(self, action: card.state == "current" ? #selector(markAddedTapped) : #selector(addAnotherTapped), for: .touchUpInside)
            cardView.addSubview(button)
            actionButton = button
        }

        NSLayoutConstraint.activate([
            cardView.widthAnchor.constraint(equalToConstant: card.state == "inactive" ? 116 : 132),
            cardView.heightAnchor.constraint(equalToConstant: card.state == "inactive" ? 168 : 182),
            titleLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 14),
            titleLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -14),
            titleLabel.topAnchor.constraint(equalTo: cardView.topAnchor, constant: card.state == "inactive" ? 35 : 42),
            quantityLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 14),
            quantityLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -14),
            quantityLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: card.state == "inactive" ? 48 : 4),
        ])

        if let actionButton = actionButton {
            NSLayoutConstraint.activate([
                actionButton.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 14),
                actionButton.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -14),
                actionButton.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -11),
                actionButton.heightAnchor.constraint(equalToConstant: 28),
            ])
        }

        return cardView
    }

    private func renderOverlay() {
        guard let payload = currentPayload else { return }

        carouselStack.arrangedSubviews.forEach { view in
            carouselStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        for card in payload.cards {
            carouselStack.addArrangedSubview(makeCard(card))
        }

        let primaryTitle: String
        switch payload.primaryAction {
        case "nextCooldown":
            primaryTitle = "Next \(payload.cooldownSeconds ?? 0)s"
            progressView.isHidden = false
            progressView.progress = Float(payload.cooldownProgress ?? 0)
            progressView.tintColor = UIColor.white.withAlphaComponent(0.9)
            progressView.trackTintColor = UIColor.white.withAlphaComponent(0.28)
            styleActionButton(primaryButton, background: UIColor(red: 0.10, green: 0.62, blue: 0.33, alpha: 1), foreground: .white)
        default:
            primaryTitle = "Next"
            progressView.isHidden = true
            styleActionButton(primaryButton, background: UIColor(red: 0.00, green: 0.48, blue: 1.00, alpha: 1), foreground: .white)
        }
        primaryButton.setTitle(primaryTitle, for: .normal)

        secondaryButton.setTitle(payload.secondaryAction == "undo" ? "Undo" : "Previous", for: .normal)
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

    @objc private func secondaryTapped() {
        guard let payload = currentPayload else { return }
        plugin?.notifyEvent(eventName: payload.secondaryAction == "undo" ? "undoRequested" : "previousRequested")
    }

    @objc private func primaryTapped() {
        plugin?.notifyEvent(eventName: "nextRequested")
    }

    @objc private func markAddedTapped() {
        plugin?.notifyEvent(eventName: "markAddedRequested")
    }

    @objc private func addAnotherTapped() {
        plugin?.notifyEvent(eventName: "addAnotherRequested")
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        webView.frame = view.bounds
    }
}
