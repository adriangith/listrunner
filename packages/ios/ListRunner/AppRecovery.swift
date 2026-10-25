import SwiftUI

struct LocalDataRecoveryScreen: View {
    @ObservedObject var storage: LocalDataController
    @State private var confirmingReset = false

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "externaldrive.badge.exclamationmark").font(.largeTitle)
            Text("Could not load ListRunner data").font(.title2.weight(.semibold))
            Text("Your saved data could not be opened. Retry before choosing to reset.")
                .foregroundStyle(.secondary)
            Button("Retry") { storage.open() }.buttonStyle(.borderedProminent)
            Button("Reset Local Data", role: .destructive) { confirmingReset = true }.buttonStyle(.bordered)
        }
        .multilineTextAlignment(.center)
        .padding(24)
        .alert("Reset Local Data?", isPresented: $confirmingReset) {
            Button("Reset Local Data", role: .destructive) { storage.resetAfterConfirmation() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This deletes all ListRunner store lists, app metadata and diagnostics only. Apple Reminders and store website data stay unchanged.")
        }
    }
}

struct SettingsScreen: View {
    @ObservedObject var browser: StoreBrowser
    @State private var confirmingReset = false
    @State private var diagnosticsNotice: String?

    var body: some View {
        Form {
            Section("Shopping") {
                Button("Reset \(browser.store.displayName) Session", role: .destructive) { confirmingReset = true }
                    .disabled(browser.resetPhase != .ready)
                Button("Clear \(browser.store.displayName) Diagnostics") {
                    do { try browser.diagnostics.clear(storeID: browser.store.id); diagnosticsNotice = "Diagnostics cleared" }
                    catch { diagnosticsNotice = "Could not clear diagnostics" }
                    UIAccessibility.post(notification: .announcement, argument: diagnosticsNotice)
                }
            }
            if browser.resetPhase == .resetting {
                Section {
                    ProgressView("Resetting…")
                    Text("Clearing \(browser.store.displayName) website data. Store access is unavailable until this finishes.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            if let diagnosticsNotice {
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(diagnosticsNotice).font(.subheadline.weight(.semibold))
                            Text("Your lists and store sessions are unchanged.").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { self.diagnosticsNotice = nil } label: {
                            Image(systemName: "xmark").frame(width: 44, height: 44)
                        }
                        .buttonStyle(.borderless).accessibilityLabel("Dismiss diagnostics notice")
                    }
                }
            }
            Section("About") {
                LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                Text("Your lists and shopping data stay on this device. ListRunner has no analytics or backend. Each retailer controls its own website and account data.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle(browser.store.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(browser.resetPhase != .ready)
        .alert(browser.resetPhase == .failed ? "Could not reset \(browser.store.displayName) session" : "Reset \(browser.store.displayName) Session?",
               isPresented: Binding(get: { confirmingReset || browser.resetPhase == .failed },
                                    set: { if !$0 { confirmingReset = false } })) {
            if browser.resetPhase == .failed {
                Button("Retry") { browser.resetStoreSession() }
                Button("Cancel", role: .cancel) { browser.cancelFailedSessionReset() }
            } else {
                Button("Reset \(browser.store.displayName) Session", role: .destructive) {
                    confirmingReset = false
                    browser.resetStoreSession()
                }
                Button("Cancel", role: .cancel) { confirmingReset = false }
            }
        } message: {
            if browser.resetPhase == .failed {
                Text("Could not confirm \(browser.store.displayName) data was cleared. Your lists are unchanged.")
            } else {
                Text("This signs you out of \(browser.store.displayName) on this device and clears its local website data. Your ListRunner lists and other store sessions stay unchanged. A server-side cart may return when you sign in again.")
            }
        }
    }
}

struct SettingsOverviewScreen: View {
    @ObservedObject var sessions: StoreSessions
    @State private var notice: String?

    var body: some View {
        Form {
            Section("Stores") {
                ForEach(StoreID.allCases) { store in
                    NavigationLink(store.displayName) { SettingsScreen(browser: sessions.browser(for: store)) }
                }
            }
            Section("Diagnostics") {
                Button("Clear All Diagnostics") {
                    do { try sessions.diagnostics.clear(); notice = "Diagnostics cleared" }
                    catch { notice = "Could not clear diagnostics" }
                    UIAccessibility.post(notification: .announcement, argument: notice)
                }
                if let notice {
                    HStack {
                        Text(notice).font(.subheadline.weight(.semibold))
                        Spacer()
                        Button { self.notice = nil } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
                            .buttonStyle(.borderless).accessibilityLabel("Dismiss diagnostics notice")
                    }
                }
            }
            Section("Privacy") {
                Text("Your lists stay on this device. Each store has its own list, browser session, reset and automation capabilities. Store account status is managed by the retailer; ListRunner does not read your credentials.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct PersistenceWarning: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Changes may not be saved", systemImage: "exclamationmark.triangle")
                .font(.subheadline.weight(.semibold))
            Text("Shopping can continue. ListRunner will retry on your next change or when you return to the app.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}
