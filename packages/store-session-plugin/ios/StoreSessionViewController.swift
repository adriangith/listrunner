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
    let secondaryEnabled: Bool
    let cooldownSeconds: Int?
    let cooldownProgress: Double?
    let itemName: String
    let searchTerm: String
}

private final class OverlayHitView: UIView {
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        if super.point(inside: point, with: event) {
            return true
        }

        return subviews.contains { subview in
            guard !subview.isHidden, subview.alpha > 0.01, subview.isUserInteractionEnabled else {
                return false
            }
            return subview.point(inside: convert(point, to: subview), with: event)
        }
    }
}

private final class AddedGradientCardView: UIView {
    private let addedGradientLayer = CAGradientLayer()
    private let currentGradientLayer = CAGradientLayer()
    private var hasAddedGradient = false
    private var hasCurrentGradient = false

    func applyCurrentGradient() {
        guard !hasCurrentGradient else { return }

        currentGradientLayer.type = .radial
        currentGradientLayer.colors = [
            UIColor(red: 0.00, green: 0.48, blue: 1.00, alpha: 1).cgColor,
            UIColor(red: 0.10, green: 0.44, blue: 0.82, alpha: 1).cgColor,
        ]
        currentGradientLayer.locations = [0, 1]
        currentGradientLayer.startPoint = CGPoint(x: 1.0, y: 0.26)
        currentGradientLayer.endPoint = CGPoint(x: 0.0, y: 0.74)
        currentGradientLayer.cornerRadius = 18
        layer.insertSublayer(currentGradientLayer, at: 0)
        hasCurrentGradient = true
        setNeedsLayout()
    }

    func applyAddedGradient() {
        guard !hasAddedGradient else { return }

        addedGradientLayer.type = .radial
        addedGradientLayer.colors = [
            UIColor(red: 0.88, green: 1.00, blue: 0.93, alpha: 1).cgColor,
            UIColor(red: 0.63, green: 0.91, blue: 0.74, alpha: 1).cgColor,
        ]
        addedGradientLayer.locations = [0, 1]
        addedGradientLayer.startPoint = CGPoint(x: 0.37, y: 0.25)
        addedGradientLayer.endPoint = CGPoint(x: 0.63, y: 0.75)
        addedGradientLayer.cornerRadius = 18
        layer.insertSublayer(addedGradientLayer, at: 0)
        hasAddedGradient = true
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        currentGradientLayer.frame = bounds
        addedGradientLayer.frame = bounds
    }
}

public class StoreSessionViewController: UIViewController, WKNavigationDelegate, WKScriptMessageHandler, UIGestureRecognizerDelegate {
    var webView: WKWebView!
    var overlayView: UIView!
    private let carouselScrollView = UIScrollView()
    private let carouselStack = UIStackView()
    private let secondaryButton = UIButton(type: .system)
    private let primaryButton = UIButton(type: .system)
    private let progressView = UIProgressView(progressViewStyle: .bar)
    private let panelGradientLayer = CAGradientLayer()
    private var manualBadgeView: UILabel?
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
        if let scriptURL = cartDetectionScriptURL(),
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

    private func cartDetectionScriptURL() -> URL? {
        return Bundle.module.url(forResource: "cart-detection", withExtension: "js")
            ?? Bundle.module.url(forResource: "cart-detection", withExtension: "js", subdirectory: "Resources")
    }

    private func setupOverlay() {
        overlayView = OverlayHitView()
        overlayView.backgroundColor = .clear
        overlayView.layer.shadowColor = UIColor.black.cgColor
        overlayView.layer.shadowOpacity = 0.08
        overlayView.layer.shadowRadius = 18
        overlayView.layer.shadowOffset = CGSize(width: 0, height: -8)
        overlayView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(overlayView)

        panelGradientLayer.type = .radial
        panelGradientLayer.colors = [
            UIColor.white.withAlphaComponent(0.98).cgColor,
            UIColor.white.withAlphaComponent(0.94).cgColor,
        ]
        panelGradientLayer.locations = [0, 1]
        panelGradientLayer.startPoint = CGPoint(x: 0.5, y: 0.0)
        panelGradientLayer.endPoint = CGPoint(x: 0.95, y: 1.0)
        overlayView.layer.insertSublayer(panelGradientLayer, at: 0)

        carouselScrollView.showsHorizontalScrollIndicator = false
        carouselScrollView.alwaysBounceHorizontal = true
        carouselScrollView.clipsToBounds = false
        carouselScrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(carouselScrollView)

        carouselStack.axis = .horizontal
        carouselStack.alignment = .center
        carouselStack.distribution = .fill
        carouselStack.spacing = 10
        carouselStack.translatesAutoresizingMaskIntoConstraints = false
        carouselScrollView.addSubview(carouselStack)

        secondaryButton.translatesAutoresizingMaskIntoConstraints = false
        primaryButton.translatesAutoresizingMaskIntoConstraints = false
        progressView.translatesAutoresizingMaskIntoConstraints = false
        overlayView.addSubview(secondaryButton)
        overlayView.addSubview(primaryButton)
        primaryButton.addSubview(progressView)

        styleActionButton(secondaryButton, background: UIColor(red: 0.94, green: 0.95, blue: 0.97, alpha: 1), foreground: UIColor(red: 0.17, green: 0.19, blue: 0.23, alpha: 1))
        styleActionButton(primaryButton, background: UIColor(red: 0.00, green: 0.48, blue: 1.00, alpha: 1), foreground: .white)

        secondaryButton.addTarget(self, action: #selector(secondaryTapped), for: .touchUpInside)
        primaryButton.addTarget(self, action: #selector(primaryTapped), for: .touchUpInside)

        NSLayoutConstraint.activate([
            overlayView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            overlayView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            overlayView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            overlayView.heightAnchor.constraint(equalToConstant: 202),

            carouselScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: -43),
            carouselScrollView.topAnchor.constraint(equalTo: overlayView.topAnchor, constant: -46),
            carouselScrollView.widthAnchor.constraint(equalToConstant: 482),
            carouselScrollView.heightAnchor.constraint(equalToConstant: 120),
            carouselScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: 43),

            carouselStack.leadingAnchor.constraint(equalTo: carouselScrollView.contentLayoutGuide.leadingAnchor),
            carouselStack.trailingAnchor.constraint(equalTo: carouselScrollView.contentLayoutGuide.trailingAnchor),
            carouselStack.topAnchor.constraint(equalTo: carouselScrollView.contentLayoutGuide.topAnchor, constant: -47),
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

    func updateOverlay(payload: StoreSessionOverlayPayload) {
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

    private func isBlueCurrentState(_ state: String) -> Bool {
        return state == "current"
    }

    private func backgroundColor(for state: String) -> UIColor {
        if isBlueCurrentState(state) {
            return UIColor(red: 0.00, green: 0.48, blue: 1.00, alpha: 1)
        }
        return UIColor(red: 0.98, green: 0.97, blue: 0.94, alpha: 1)
    }

    private func textColor(for state: String) -> UIColor {
        return isBlueCurrentState(state) ? .white : UIColor(red: 0.17, green: 0.19, blue: 0.23, alpha: 1)
    }

    private func actionTextColor(for state: String) -> UIColor {
        return state == "currentAdded"
            ? UIColor(red: 0.12, green: 0.65, blue: 0.19, alpha: 1)
            : UIColor(red: 0.00, green: 0.32, blue: 0.88, alpha: 1)
    }

    private func makeAddedStateLabel() -> UILabel {
        let label = UILabel()
        label.text = "✓ Added"
        label.textAlignment = .center
        label.textColor = UIColor(red: 0.17, green: 0.19, blue: 0.23, alpha: 1)
        label.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    private func makeManualBadge() -> UILabel {
        let badge = UILabel()
        badge.text = "Manual"
        badge.textAlignment = .center
        badge.textColor = .white
        badge.font = UIFont.systemFont(ofSize: 8, weight: .semibold)
        badge.backgroundColor = UIColor(red: 0.70, green: 0.70, blue: 0.70, alpha: 1)
        badge.layer.cornerRadius = 4
        badge.clipsToBounds = true
        badge.translatesAutoresizingMaskIntoConstraints = false
        return badge
    }

    private func makeCarouselSpacer(width: CGFloat) -> UIView {
        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.widthAnchor.constraint(equalToConstant: width).isActive = true
        return spacer
    }

    private func isAddedState(_ state: String) -> Bool {
        return state == "added" || state == "currentAdded"
    }

    private func applyAddedGradient(to cardView: UIView) {
        (cardView as? AddedGradientCardView)?.applyAddedGradient()
    }

    private func applyCurrentGradient(to cardView: UIView) {
        (cardView as? AddedGradientCardView)?.applyCurrentGradient()
    }

    private func quantityFontSize(for state: String) -> CGFloat {
        if state == "inactive" || state == "added" {
            return 12
        }
        return state == "current" ? 38 : 46
    }

    private func makeQuantityPill(text: String, state: String) -> UILabel {
        let quantityPill = UILabel()
        quantityPill.text = text
        quantityPill.textAlignment = .center
        quantityPill.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
        quantityPill.textColor = isAddedState(state) ? UIColor(red: 0.12, green: 0.65, blue: 0.19, alpha: 1) : textColor(for: state)
        quantityPill.backgroundColor = isAddedState(state) ? UIColor.white : UIColor(red: 0.96, green: 0.94, blue: 0.90, alpha: 1)
        quantityPill.layer.cornerRadius = 12
        quantityPill.clipsToBounds = true
        quantityPill.translatesAutoresizingMaskIntoConstraints = false
        return quantityPill
    }

    private func updateManualBadge(for payload: StoreSessionOverlayPayload) {
        manualBadgeView?.removeFromSuperview()
        manualBadgeView = nil

        guard payload.mode == "manual" else { return }

        let badge = makeManualBadge()
        overlayView.addSubview(badge)
        manualBadgeView = badge

        NSLayoutConstraint.activate([
            badge.leadingAnchor.constraint(equalTo: overlayView.leadingAnchor, constant: 134),
            badge.topAnchor.constraint(equalTo: overlayView.topAnchor, constant: 90),
            badge.widthAnchor.constraint(equalToConstant: 72),
            badge.heightAnchor.constraint(equalToConstant: 16),
        ])
    }

    private func makeCard(_ card: StoreSessionOverlayCard, index: Int) -> UIView {
        let cardView = AddedGradientCardView()
        cardView.isUserInteractionEnabled = true
        cardView.translatesAutoresizingMaskIntoConstraints = false
        cardView.layer.cornerRadius = 18
        cardView.clipsToBounds = false
        cardView.backgroundColor = backgroundColor(for: card.state)
        cardView.layer.shadowColor = UIColor.black.cgColor
        cardView.layer.shadowOpacity = 0.12
        cardView.layer.shadowRadius = 12
        cardView.layer.shadowOffset = CGSize(width: 0, height: 6)

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(cardTapped(_:)))
        tapGesture.name = String(index)
        tapGesture.delegate = self
        cardView.addGestureRecognizer(tapGesture)

        if isAddedState(card.state) {
            applyAddedGradient(to: cardView)
        } else if isBlueCurrentState(card.state) {
            applyCurrentGradient(to: cardView)
        }

        let titleLabel = UILabel()
        titleLabel.text = card.title
        titleLabel.numberOfLines = 2
        titleLabel.textAlignment = .center
        titleLabel.font = UIFont.systemFont(ofSize: card.state == "inactive" || card.state == "added" ? 16 : 19, weight: .semibold)
        titleLabel.textColor = textColor(for: card.state)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(titleLabel)

        let quantityLabel = UILabel()
        quantityLabel.text = card.quantity
        quantityLabel.textAlignment = .center
        quantityLabel.font = UIFont.systemFont(ofSize: quantityFontSize(for: card.state), weight: .bold)
        quantityLabel.adjustsFontSizeToFitWidth = true
        quantityLabel.minimumScaleFactor = 0.75
        quantityLabel.textColor = textColor(for: card.state)
        quantityLabel.translatesAutoresizingMaskIntoConstraints = false

        let quantityPill = card.state == "inactive" || card.state == "added"
            ? makeQuantityPill(text: card.quantity, state: card.state)
            : nil

        if let quantityPill = quantityPill {
            cardView.addSubview(quantityPill)
        } else {
            cardView.addSubview(quantityLabel)
        }

        if isAddedState(card.state) {
            let addedLabel = makeAddedStateLabel()
            cardView.addSubview(addedLabel)
            NSLayoutConstraint.activate([
                addedLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: card.state == "currentAdded" ? 0 : 8),
                addedLabel.topAnchor.constraint(equalTo: cardView.topAnchor, constant: card.state == "currentAdded" ? 11 : 9),
                addedLabel.widthAnchor.constraint(equalToConstant: card.state == "currentAdded" ? 72 : 88),
                addedLabel.heightAnchor.constraint(equalToConstant: 14),
            ])
        }

        let actionTitle = card.state == "current" ? "Mark added" : card.state == "currentAdded" ? "Add another" : nil
        var actionButton: UIButton?
        if let actionTitle = actionTitle {
            let button = UIButton(type: .system)
            button.setTitle(actionTitle, for: .normal)
            button.setTitleColor(actionTextColor(for: card.state), for: .normal)
            button.titleLabel?.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
            button.backgroundColor = .white
            button.layer.cornerRadius = 14
            button.translatesAutoresizingMaskIntoConstraints = false
            button.addTarget(self, action: card.state == "current" ? #selector(markAddedTapped) : #selector(addAnotherTapped), for: .touchUpInside)
            cardView.addSubview(button)
            actionButton = button
        }

        var constraints: [NSLayoutConstraint] = [
            cardView.widthAnchor.constraint(equalToConstant: card.state == "current" || card.state == "currentAdded" ? 132 : 116),
            cardView.heightAnchor.constraint(equalToConstant: card.state == "current" || card.state == "currentAdded" ? 182 : card.state == "added" ? 166 : 177),
            titleLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: card.state == "added" ? 6 : 14),
            titleLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: card.state == "added" ? -6 : -14),
            titleLabel.topAnchor.constraint(equalTo: cardView.topAnchor, constant: card.state == "current" ? 22 : card.state == "currentAdded" ? 39 : card.state == "added" ? 27 : 31),
        ]

        if let quantityPill = quantityPill {
            constraints.append(contentsOf: [
                quantityPill.centerXAnchor.constraint(equalTo: cardView.centerXAnchor),
                quantityPill.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: card.state == "added" ? 48 : 44),
                quantityPill.widthAnchor.constraint(equalToConstant: 54),
                quantityPill.heightAnchor.constraint(equalToConstant: 24),
            ])
        } else {
            constraints.append(contentsOf: [
                quantityLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 14),
                quantityLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -14),
            ])
            constraints.append(
                card.state == "currentAdded"
                    ? quantityLabel.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 86)
                    : quantityLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4)
            )
        }

        NSLayoutConstraint.activate(constraints)

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

        carouselStack.addArrangedSubview(makeCarouselSpacer(width: 165))
        for (index, card) in payload.cards.enumerated() {
            carouselStack.addArrangedSubview(makeCard(card, index: index))
        }
        carouselStack.addArrangedSubview(makeCarouselSpacer(width: 165))

        updateManualBadge(for: payload)

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
            primaryTitle = "Skip"
            progressView.isHidden = true
            styleActionButton(primaryButton, background: UIColor(red: 0.00, green: 0.48, blue: 1.00, alpha: 1), foreground: .white)
        }
        primaryButton.setTitle(primaryTitle, for: .normal)

        secondaryButton.setTitle(payload.secondaryAction == "undo" ? "Undo" : "Previous", for: .normal)
        secondaryButton.isEnabled = payload.secondaryEnabled
        secondaryButton.alpha = payload.secondaryEnabled ? 1 : 0.45

        view.layoutIfNeeded()
        centerActiveCard(for: payload.activeIndex + 1)
    }

    private func centerActiveCard(for activeIndex: Int) {
        guard activeIndex >= 0,
              activeIndex < carouselStack.arrangedSubviews.count else { return }

        let card = carouselStack.arrangedSubviews[activeIndex]
        let targetCenter = carouselScrollView.convert(card.center, from: carouselStack)
        let targetX = targetCenter.x - carouselScrollView.bounds.width / 2
        let maxX = max(0, carouselScrollView.contentSize.width - carouselScrollView.bounds.width)
        carouselScrollView.setContentOffset(
            CGPoint(x: min(max(0, targetX), maxX), y: 0),
            animated: false
        )
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
        guard payload.secondaryEnabled else { return }
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

    @objc private func cardTapped(_ gesture: UITapGestureRecognizer) {
        guard let rawIndex = gesture.name,
              let index = Int(rawIndex) else { return }
        plugin?.notifyEvent(eventName: "cardSelected", data: ["index": index])
    }

    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var view: UIView? = touch.view
        while let current = view {
            if current is UIControl {
                return false
            }
            view = current.superview
        }
        return true
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        webView.frame = view.bounds
        panelGradientLayer.frame = overlayView.bounds
    }
}
