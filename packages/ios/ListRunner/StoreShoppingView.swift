import SwiftUI
import UIKit
import WebKit

struct StoreShoppingView: View {
    let items: [GroceryItem]
    let browser: ColesBrowser
    let initialSelectedID: UUID?
    let onSelectionChange: (UUID) -> Void
    let onStatusChange: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedID: UUID?
    @State private var isCollapsed = false
    @State private var secondsRemaining = 0
    @State private var undoRecord: (id: UUID, previous: GroceryStatus)?
    @State private var task: Task<Void, Never>?
    @State private var searchUnavailable = false
    @State private var manuallyPaused = false

    init(items: [GroceryItem], browser: ColesBrowser, initialSelectedID: UUID?, onSelectionChange: @escaping (UUID) -> Void, onStatusChange: @escaping () -> Void) {
        self.items = items
        self.browser = browser
        self.initialSelectedID = initialSelectedID
        self.onSelectionChange = onSelectionChange
        self.onStatusChange = onStatusChange
        _selectedID = State(initialValue: initialSelectedID)
    }

    private var selected: GroceryItem? {
        items.first(where: { $0.id == selectedID }) ?? items.first
    }
    private var pending: [GroceryItem] { items.filter { $0.status == .pending } }
    private var isFinalConfirmation: Bool { pending.isEmpty && undoRecord != nil }

    var body: some View {
        ZStack(alignment: .bottom) {
            ColesWebView(browser: browser)
                .ignoresSafeArea(edges: .top)

            VStack(spacing: 0) {
                Capsule().fill(.secondary.opacity(0.65)).frame(width: 42, height: 5)
                    .padding(.top, 10).padding(.bottom, 9)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture { dismissStore() }
                    .accessibilityElement()
                    .accessibilityLabel("Dismiss store")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { dismissStore() }
                    .gesture(DragGesture(minimumDistance: 12).onEnded { value in
                        if value.translation.height > 24 { dismissStore() }
                    })

                Spacer(minLength: 0)
                if isCollapsed {
                    collapsedBar
                } else {
                    expandedPanel
                }
            }
        }
        .background(Color(uiColor: .systemBackground))
        .onAppear {
            if selectedID == nil || !items.contains(where: { $0.id == selectedID }) { selectedID = items.first?.id }
            searchUnavailable = true
        }
        .onDisappear { task?.cancel() }
    }

    private var expandedPanel: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .bottom, spacing: 12) {
                        ForEach(items) { item in card(item) }
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 5)
                    .padding(.bottom, 14)
                }
            }
            .frame(height: 242)
            .padding(.top, -112)

            HStack(spacing: 10) {
                if secondsRemaining > 0 || isFinalConfirmation || manuallyPaused, undoRecord != nil {
                    Button("Undo", action: undo)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .buttonStyle(.bordered)
                } else {
                    Button(action: selectPrevious) {
                        Label("Back", systemImage: "chevron.left")
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.bordered)
                    .disabled(selectedID == items.first?.id || isFinalConfirmation)
                }

                VStack(spacing: 3) {
                    if isFinalConfirmation { Text("Final item") }
                    else if secondsRemaining > 0 { Text("Next in \(secondsRemaining)s") }
                    else if manuallyPaused { Text("Paused · Next when ready") }
                    else if searchUnavailable { Label("Search unavailable", systemImage: "exclamationmark.triangle") }
                    else { Text("Swipe cards to browse") }
                    if searchUnavailable { Text("Search manually in Coles").font(.caption2) }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 48)
                .accessibilityElement(children: .combine)

                if isFinalConfirmation {
                    Button("Finish", action: finish)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .buttonStyle(.borderedProminent)
                } else if pending.isEmpty {
                    VStack(spacing: 2) {
                        Text("All items handled").font(.caption.weight(.semibold))
                        Text("Continue to checkout when ready.").font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 48)
                } else if selected?.status == .pending {
                    Button("Skip", action: skip)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .buttonStyle(.bordered)
                } else {
                    Button("Next", action: next)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .buttonStyle(.borderedProminent)
                        .disabled(pending.isEmpty)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .background(.regularMaterial)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24))
        .gesture(DragGesture(minimumDistance: 20).onEnded { value in
            if value.translation.height > 35 { collapse() }
        })
    }

    private var collapsedBar: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { isCollapsed = false }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "chevron.up")
                VStack(alignment: .leading, spacing: 2) {
                    Text(selected?.name ?? "Shopping").font(.headline)
                    Text("\(selected?.displayQuantity ?? "") · \(selected?.status.rawValue ?? "")")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("Expand overlay").font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 20)
            .frame(minHeight: 70)
            .background(.regularMaterial)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(selected?.name ?? "Selected item"), Expand overlay")
        .accessibilityHint("Shows shopping controls")
    }

    private func card(_ item: GroceryItem) -> some View {
        let current = item.id == selectedID
        return VStack(alignment: .leading, spacing: 5) {
            Button { select(item) } label: {
                VStack(alignment: .leading, spacing: 8) {
                    if item.status != .pending {
                        Text(item.status.rawValue.uppercased())
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 7).padding(.vertical, 4)
                            .background(.white.opacity(0.2), in: Capsule())
                    } else { Spacer().frame(height: 18) }
                    Spacer(minLength: 0)
                    Text(sentenceCase(item.name))
                        .font(current ? .title3.bold() : .subheadline.bold())
                        .lineLimit(4).minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(item.displayQuantity)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .background(.white.opacity(current ? 0.20 : 0.6), in: Capsule())
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .disabled(isFinalConfirmation && !current)
            .accessibilityLabel("\(item.name), quantity \(item.displayQuantity), \(item.status.rawValue)\(current ? ", selected" : "")")
            .accessibilityAddTraits(current ? .isSelected : [])

            if current && (item.status != .added || !pending.isEmpty) {
                Button(action: primaryAction) {
                    Text(item.status == .added ? "Pause" : "Mark Added")
                        .font(.subheadline.weight(.bold))
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .foregroundStyle(item.status == .added ? Color.listRunnerGreen : .white)
                        .background(item.status == .added ? Color.white : Color.white.opacity(0.2), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityHint(item.status == .added ? "Stop automatic progression. Continue with Next when ready." : "Marks this grocery item added in ListRunner only")
            }
        }
            .padding(13)
            .frame(width: current ? 160 : 145, height: current ? 224 : 203)
            .foregroundStyle(cardForeground(item.status))
            .background(cardBackground(item.status), in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.3), lineWidth: 1))
            .shadow(color: .black.opacity(current ? 0.18 : 0.08), radius: current ? 12 : 6, y: 5)
    }

    private func cardBackground(_ status: GroceryStatus) -> LinearGradient {
        switch status {
        case .pending: LinearGradient(colors: [Color(red: 0.09, green: 0.36, blue: 0.80), Color(red: 0.26, green: 0.61, blue: 1)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .added: LinearGradient(colors: [Color(red: 0.08, green: 0.48, blue: 0.31), Color(red: 0.18, green: 0.68, blue: 0.43)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .skipped: LinearGradient(colors: [Color.gray.opacity(0.85), Color.gray.opacity(0.65)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    private func cardForeground(_ status: GroceryStatus) -> Color { .white }

    private func primaryAction() {
        guard let item = selected else { return }
        if item.status == .added {
            // Pause is a manual hold; it never edits cart quantities.
            guard !pending.isEmpty else { return }
            task?.cancel()
            secondsRemaining = 0
            manuallyPaused = true
        } else {
            markAdded(item)
        }
    }

    private func markAdded(_ item: GroceryItem) {
        task?.cancel()
        undoRecord = (item.id, item.status)
        item.status = .added
        onStatusChange()
        if pending.isEmpty { secondsRemaining = 0 }
        else if manuallyPaused { secondsRemaining = 0 }
        else { beginCooldown() }
    }

    private func beginCooldown() {
        secondsRemaining = 3
        task = Task { @MainActor in
            while secondsRemaining > 0 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                secondsRemaining -= 1
            }
            undoRecord = nil
            advanceToNextPending()
        }
    }

    private func undo() {
        task?.cancel()
        secondsRemaining = 0
        manuallyPaused = false
        guard let record = undoRecord, let item = items.first(where: { $0.id == record.id }) else { return }
        item.status = record.previous
        undoRecord = nil
        onStatusChange()
    }

    private func finish() {
        task?.cancel()
        undoRecord = nil
        secondsRemaining = 0
    }

    private func next() {
        task?.cancel()
        undoRecord = nil
        secondsRemaining = 0
        manuallyPaused = false
        advanceToNextPending()
    }

    private func skip() {
        guard let item = selected else { return }
        task?.cancel()
        undoRecord = nil
        secondsRemaining = 0
        manuallyPaused = false
        item.status = .skipped
        onStatusChange()
        advanceToNextPending()
    }

    private func advanceToNextPending() {
        guard !pending.isEmpty else { return }
        let currentIndex = items.firstIndex(where: { $0.id == selectedID }) ?? -1
        let after = items.dropFirst(max(0, currentIndex + 1)).first(where: { $0.status == .pending })
        let next = after ?? pending.first
        guard let next else { return }
        select(next)
    }

    private func selectPrevious() {
        guard let index = items.firstIndex(where: { $0.id == selectedID }), index > 0 else { return }
        select(items[index - 1])
    }

    private func select(_ item: GroceryItem) {
        guard item.id != selectedID, !isFinalConfirmation else { return }
        task?.cancel()
        secondsRemaining = 0
        undoRecord = nil
        manuallyPaused = false
        selectedID = item.id
        onSelectionChange(item.id)
        // Automatic search is deliberately not claimed until the isolated bridge is implemented.
    }

    private func collapse() {
        if secondsRemaining > 0 {
            task?.cancel()
            secondsRemaining = 0
            undoRecord = nil
        }
        withAnimation(.easeInOut(duration: 0.2)) { isCollapsed = true }
    }

    private func dismissStore() {
        if secondsRemaining > 0 { task?.cancel(); secondsRemaining = 0; undoRecord = nil }
        dismiss()
    }
}

@MainActor
final class ColesBrowser: ObservableObject {
    let webView: WKWebView
    private var hasLoaded = false

    init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        self.webView = WKWebView(frame: .zero, configuration: configuration)
        let coordinator = Coordinator()
        self.coordinator = coordinator
        webView.navigationDelegate = coordinator
        webView.uiDelegate = coordinator
    }

    private let coordinator: Coordinator

    func loadIfNeeded() {
        guard !hasLoaded else { return }
        hasLoaded = true
        webView.load(URLRequest(url: URL(string: "https://www.coles.com.au")!))
    }

    @MainActor
    private final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        private let allowedHost = "www.coles.com.au"

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url,
                  url.scheme?.lowercased() == "https",
                  url.host?.lowercased() == allowedHost else {
                if let url = navigationAction.request.url,
                   url.scheme?.lowercased() == "https", url.host != nil {
                    UIApplication.shared.open(url)
                }
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = navigationAction.request.url,
               url.scheme?.lowercased() == "https", url.host != nil {
                UIApplication.shared.open(url)
            }
            return nil
        }
    }
}

private struct ColesWebView: UIViewRepresentable {
    let browser: ColesBrowser

    func makeUIView(context: Context) -> WKWebView {
        browser.loadIfNeeded()
        return browser.webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) { browser.loadIfNeeded() }
}

private extension Color {
    static let listRunnerGreen = Color(red: 0.10, green: 0.52, blue: 0.37)
}
