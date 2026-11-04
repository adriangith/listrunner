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
    let brand: StoreBrand
    @ObservedObject var visibility: StoreVisibilityPreferences
    @State private var confirmingReset = false
    @State private var diagnosticsNotice: String?
    @State private var choosingRegion = false

    private var configurationValid: Bool { browser.store.isConfigurationValid }

    private func supportState(_ included: Bool) -> String {
        guard configurationValid else { return "Unavailable — configuration invalid" }
        return included ? "Included" : "Not included"
    }

    private func sessionState(included: Bool, unavailable: Bool) -> String {
        guard configurationValid else { return "Unavailable" }
        guard included else { return "Not included" }
        return unavailable ? "Unavailable in this session" : "Available in this session"
    }

    var body: some View {
        Form {
            Section {
                Toggle("Enable store", isOn: Binding(
                    get: { !visibility.shoppingVisibleIDs(in: brand.regions).isEmpty },
                    set: { visibility.setBrandVisible($0, brand: brand) }
                ))
                .accessibilityLabel("Enable \(brand.name)")
                .accessibilityIdentifier("store-visibility-\(brand.id)")
                .disabled(browser.resetPhase != .ready)
                if brand.isRegional {
                    Button { choosingRegion = true } label: {
                        LabeledContent("Region", value: browser.store.id.regionalCountryCode.map { ShoppingCountry.name($0) } ?? browser.store.displayName)
                    }
                    .accessibilityLabel("Region")
                    .accessibilityValue(browser.store.id.regionalCountryCode.map { ShoppingCountry.name($0) } ?? browser.store.displayName)
                    .accessibilityIdentifier("store-region-picker-\(brand.id)")
                    .disabled(browser.resetPhase != .ready)
                }
            }
            if !configurationValid {
                Section("Store Configuration") {
                    Label("Store configuration is invalid", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("An app update is required to fix this configuration. Automatic shopping assistance is unavailable, but you can browse the store and update your ListRunner list manually.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section("Included Support") {
                LabeledContent("Search", value: supportState(browser.store.capabilities.search))
                LabeledContent("Cart detection", value: supportState(browser.store.capabilities.cartDetection))
                LabeledContent("Cart Undo", value: supportState(browser.store.capabilities.cartUndo))
            }
            Section("Current Session Status") {
                LabeledContent("Search", value: sessionState(included: browser.store.capabilities.search, unavailable: browser.searchUnavailable))
                LabeledContent("Cart detection", value: sessionState(included: browser.store.capabilities.cartDetection, unavailable: browser.cartDetectionUnavailable))
            }
            Section("Store Session") {
                Button("Reset \(browser.store.displayName) Session", role: .destructive) { confirmingReset = true }
                    .disabled(browser.resetPhase != .ready)
                Text("Clears this store's local browser data. It does not repair an invalid store configuration.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Diagnostics") {
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
        .sheet(isPresented: $choosingRegion) {
            NavigationStack { StoreRegionScreen(brand: brand, visibility: visibility) }
        }
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

private struct StoreSettingsScreen: View {
    let brand: StoreBrand
    @ObservedObject var sessions: StoreSessions
    @ObservedObject var visibility: StoreVisibilityPreferences

    var body: some View {
        let store = visibility.selectedRegion(for: brand).id
        SettingsScreen(browser: sessions.browser(for: store), brand: brand, visibility: visibility)
            .id(store)
    }
}

private struct WelcomeStoreSetupScreen: View {
    let store: StoreDefinition
    let enableStore: () -> Void

    var body: some View {
        Form {
            Section {
                Button(action: enableStore) {
                    Text("Enable \(store.displayName)")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("welcome-enable-store")
                .accessibilityHint("Returns to this store’s grocery list without opening its website")
                .listRowBackground(Color.clear)
            }
            Section {
                LabeledContent("Search", value: supportState(store.capabilities.search))
                LabeledContent("Cart detection", value: supportState(store.capabilities.cartDetection))
                LabeledContent("Cart Undo", value: supportState(store.capabilities.cartUndo))
            } header: {
                Text("Included Support")
            } footer: {
                Text(store.homepage.host ?? "")
            }
        }
        .navigationTitle(store.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func supportState(_ included: Bool) -> String {
        guard store.isConfigurationValid else { return "Unavailable — configuration invalid" }
        return included ? "Included" : "Not included"
    }
}

struct SettingsOverviewScreen: View {
    @ObservedObject var sessions: StoreSessions
    @ObservedObject var visibility: StoreVisibilityPreferences
    @State private var notice: String?
    @AppStorage(GroceryImportSource.preferenceKey) private var importSourceID = ""
    @AppStorage(GroceryImportSource.removeRemindersKey) private var removeRemindersAfterImport = true
    let importInProgress: Bool
    let importDestinationName: String
    let onImportSourceSelected: () -> Void

    var body: some View {
        Form {
            Section {
                NavigationLink("Manage Stores") {
                    StoreVisibilityScreen(sessions: sessions, visibility: visibility)
                }
                NavigationLink {
                    ShoppingCountryScreen(visibility: visibility)
                } label: {
                    LabeledContent("Country", value: visibility.shoppingCountryCode.map { ShoppingCountry.name($0) } ?? "Choose Country")
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Country")
                .accessibilityValue(visibility.shoppingCountryCode.map { ShoppingCountry.name($0) } ?? "Choose Country")
                .accessibilityIdentifier("shopping-country")
                Toggle("Use local ingredient names", isOn: Binding(
                    get: { visibility.useLocalIngredientNames },
                    set: { visibility.setUseLocalIngredientNames($0) }
                ))
                .accessibilityIdentifier("use-local-ingredient-names")
            } footer: {
                Text("Uses the Country setting to adapt ingredient names in retailer searches. Your list and quantities stay unchanged.")
            }
            Section("Importing") {
                Toggle("Remove reminders after import", isOn: $removeRemindersAfterImport)
                    .accessibilityIdentifier("remove-reminders-after-import")
                    .disabled(importInProgress)
                Text(removeRemindersAfterImport
                     ? "After groceries are saved in ListRunner, their Apple reminders are removed. Paprika is unchanged. Re-exporting from Paprika may import duplicates."
                     : "Imported reminders stay in Apple Reminders. ListRunner updates linked reminder text and checkmarks. Re-exporting from Paprika may import duplicates.")
                    .font(.footnote).foregroundStyle(.secondary)
                NavigationLink {
                    ImportSourceSelectionScreen(selectedSourceID: importSourceID, destinationName: importDestinationName) { _ in
                        onImportSourceSelected()
                    }
                } label: {
                    LabeledContent("Import source", value: GroceryImportSource(rawValue: importSourceID) == .paprika ? "Paprika" : "Choose source")
                }
                .accessibilityIdentifier("import-source-setting")
                .disabled(importInProgress)
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

struct ImportSourceSelectionScreen: View {
    let selectedSourceID: String
    let destinationName: String
    let onUseSource: (GroceryImportSource) -> Void

    var body: some View {
        List {
            Section {
                Text("Choose where to import your groceries from. Your last successful source is remembered for next time. You can choose a different source in Settings.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section("Sources") {
                NavigationLink {
                    PaprikaImportInstructionsScreen(destinationName: destinationName) {
                        onUseSource(.paprika)
                    }
                } label: {
                    HStack {
                        Label {
                            VStack(alignment: .leading) {
                                Text("Paprika")
                                Text("Via Apple Reminders").font(.subheadline).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "checklist")
                        }
                        Spacer()
                        if GroceryImportSource(rawValue: selectedSourceID) == .paprika {
                            Image(systemName: "checkmark").accessibilityHidden(true)
                        }
                    }
                    .frame(minHeight: 44)
                }
                .accessibilityIdentifier("import-source-paprika")
                .accessibilityValue(GroceryImportSource(rawValue: selectedSourceID) == .paprika ? "Last used" : "Not used yet")
            }
        }
        .navigationTitle("Import items")
        .navigationBarTitleDisplayMode(.large)
    }
}

struct PaprikaImportInstructionsScreen: View {
    @AppStorage(GroceryImportSource.removeRemindersKey) private var removeRemindersAfterImport = true
    let destinationName: String
    let onUse: () -> Void

    var body: some View {
        List {
            Section {
                Text("Bring your Paprika groceries into ListRunner using Apple Reminders. No Paprika account connection is needed.")
                Text("Items will be added to your \(destinationName) list. Existing items stay unchanged.")
                if removeRemindersAfterImport {
                    Text("After your groceries are saved, their Apple reminders will be removed. Your groceries in Paprika won’t be changed. You can turn this off in Settings.")
                } else {
                    Text("Your Apple reminders will be kept and linked to the imported groceries. You can change this in Settings.")
                }
            }
            Section("How to export from Paprika") {
                PaprikaImportInstructions()
            }
            Section {
                Button(action: onUse) {
                    Text("Import groceries")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .accessibilityIdentifier("import-paprika-groceries")
                .accessibilityHint("Imports unchecked groceries from Apple Reminders into your selected store list. Requests Reminders access if needed.")
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
            Section {
                Text(removeRemindersAfterImport
                     ? "ListRunner needs full Reminders access to read your groceries and remove the imported reminders after saving. Access is requested only when you tap Import groceries."
                     : "ListRunner needs full Reminders access to read your groceries and update linked reminders. Access is requested only when you tap Import groceries.")
                    .font(.footnote).foregroundStyle(.secondary)
                DisclosureGroup("How updates work") {
                    Text("Export from Paprika again, then import to add new groceries. Changes in Paprika or Apple Reminders won’t update items already imported into this store’s list.")
                    if removeRemindersAfterImport {
                        Text("Apple Reminders is a handoff tray, not ongoing sync. Only reminders for saved groceries are removed; checked or unreadable reminders are left alone. Import again to retry failed removal without duplicating saved groceries. Previously imported reminders still present in this store’s list can also be removed on that explicit import.")
                    } else {
                        Text("Marking an imported item Added checks off its linked Apple reminder. Pending or Skipped unchecks it. Editing the item in ListRunner also updates its linked reminder’s name and quantity. These updates are best effort, not ongoing sync with Paprika.")
                    }
                    Text("Paprika creates new reminders each time you export. Exporting the same groceries again may create duplicate items in ListRunner.")
                }
                Link("Paprika’s iOS export guide", destination: URL(string: "https://www.paprikaapp.com/help/ios/#grocerylistactions")!)
            }
        }
        .navigationTitle("Import from Paprika")
        .navigationBarTitleDisplayMode(.large)
    }
}

private struct PaprikaImportInstructions: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("1. In Paprika, open Groceries and select the list you want to export.")
            Text("2. Tap Actions in the grocery toolbar, then Export to Reminders.")
            Text("3. Make sure the export’s Reminders list is named exactly ‘Paprika’. You can change the export list name in Paprika’s grocery-list options.")
            Text("4. Return here and tap Import groceries.")
            Text("Only unchecked items from the Apple Reminders list named ‘Paprika’ are imported. Checked items are not imported.")
                .padding(.top, 8)
        }
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct StoreVisibilityScreen: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var sessions: StoreSessions
    @ObservedObject var visibility: StoreVisibilityPreferences
    // Non-nil only for the welcome entry point. Normal management retains all
    // settings, toggles and region/session controls.
    var onWelcomeStoreEnabled: ((StoreID) -> Void)? = nil
    @State private var searchText = ""
    @State private var selectedBrand: StoreBrand?

    private var catalogueDefinitions: [StoreDefinition] {
        #if DEBUG
        // Presentation-only fixture: no registry, browser or production metadata
        // changes. It exercises mixed sections without shipping another retailer.
        let environment = ProcessInfo.processInfo.environment
        if environment["LISTRUNNER_UI_TEST_SESSION"].flatMap(UUID.init(uuidString:)) != nil,
           environment["LISTRUNNER_COUNTRY_TEST_CATALOGUE"] == "mixed" {
            return sessions.definitions.map { definition in
                guard definition.id == .bunnings else { return definition }
                return StoreDefinition(schemaVersion: definition.schemaVersion, id: definition.id,
                    displayName: definition.displayName, serviceArea: .init(countryCodes: ["NZ"]),
                    homepage: definition.homepage, allowedHosts: definition.allowedHosts, search: definition.search,
                    addedColor: definition.addedColor, brandColors: definition.brandColors,
                    capabilities: definition.capabilities, cart: definition.cart)
            }
        }
        #endif
        return sessions.definitions
    }

    var body: some View {
        let sections = StoreBrand.sections(catalogueDefinitions, countryCode: visibility.shoppingCountryCode,
                                               search: searchText, enabledIDs: visibility.shoppingVisibleIDs(in: catalogueDefinitions))
        ZStack {
            // Keep the native scroll controller attached during empty searches.
            // Replacing it with a non-scrolling view disconnects the large-title
            // navigation bar while search/appearance transitions are in flight.
            StoreManagementTable(sections: sections, searching: !searchText.isEmpty,
                                 selectBrand: { selectedBrand = $0 })
                .accessibilityHidden(sections.isEmpty && !searchText.isEmpty)
            if sections.isEmpty && !searchText.isEmpty {
                VStack {
                    ContentUnavailableView("No stores found", systemImage: "magnifyingglass",
                                           description: Text("Try a different store name."))
                    Button("Clear Search") { searchText = "" }
                        .frame(minHeight: 44)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Colour the hosting view's safe areas as well as the UIKit table.
        // Extending only this background preserves native scroll/search insets.
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search stores")
        .navigationTitle("Manage Stores")
        // The inline native title avoids the large-title/search fade state
        // getting stuck across a live system appearance change.
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(Color(uiColor: .systemGroupedBackground), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        // Refresh the native title/search chrome when appearance changes even
        // while search owns the bar. Do not set a global UIKit appearance.
        .toolbarColorScheme(colorScheme, for: .navigationBar)
        .navigationDestination(isPresented: Binding(get: { selectedBrand != nil }, set: { if !$0 { selectedBrand = nil } })) {
            if let selectedBrand {
                if let onWelcomeStoreEnabled {
                    let store = visibility.selectedRegion(for: selectedBrand)
                    WelcomeStoreSetupScreen(store: store) {
                        visibility.setBrandVisible(true, brand: selectedBrand)
                        onWelcomeStoreEnabled(store.id)
                    }
                } else {
                    StoreSettingsScreen(brand: selectedBrand, sessions: sessions, visibility: visibility)
                }
            }
        }
    }
}

private struct StoreRegionScreen: View {
    let brand: StoreBrand
    @ObservedObject var visibility: StoreVisibilityPreferences
    @Environment(\.dismiss) private var dismiss
    @State private var pendingRegion: StoreID?
    private var availableRegions: [StoreDefinition] { brand.regions.filter(\.isAvailableForShopping) }

    var body: some View {
        List {
            Section {
                Text("Regional lists and logins are kept separate. Country never switches an enabled store. If your active region is disabled, returning to your list selects an enabled store.")
                    .font(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section {
                Text("Regional website").font(.headline).accessibilityAddTraits(.isHeader)
                ForEach(availableRegions, id: \.id) { region in
                    Button {
                        if region.id == visibility.selectedRegion(for: brand).id { dismiss() }
                        else { pendingRegion = region.id }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(region.id.regionalCountryCode.map { ShoppingCountry.name($0) } ?? region.displayName)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if region.id == visibility.selectedRegion(for: brand).id {
                                    Image(systemName: "checkmark").accessibilityHidden(true)
                                }
                            }
                            Text(region.homepage.host ?? "").font(.footnote).foregroundStyle(.primary)
                            if !region.capabilities.search { Text("Browsing only — no store automation").font(.footnote).foregroundStyle(.primary) }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityIdentifier("store-region-\(region.id.rawValue)")
                    .accessibilityAddTraits(region.id == visibility.selectedRegion(for: brand).id ? .isSelected : [])
                    .accessibilityHint("Selecting a different regional website asks for confirmation and keeps existing lists and sessions.")
                }
            }
        }
        .navigationTitle("\(brand.name) region")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button("Done") { dismiss() }
                .font(.body).frame(maxWidth: .infinity, minHeight: 44)
                .buttonStyle(.borderedProminent).padding()
                .background(Color(uiColor: .systemGroupedBackground))
        }
        .alert("Change \(brand.name) region?", isPresented: Binding(get: { pendingRegion != nil }, set: { if !$0 { pendingRegion = nil } })) {
            Button("Use this regional website") {
                if let id = pendingRegion { visibility.chooseRegion(id, for: brand) }
                pendingRegion = nil
                dismiss()
            }
            Button("Cancel", role: .cancel) { pendingRegion = nil }
        } message: {
            Text("Your old region's list and website session are kept. If this brand is enabled, the new region replaces it in the chooser. If your active region is disabled, returning to your list selects an enabled store. No store website is opened automatically.")
        }
    }
}

private struct ShoppingCountryScreen: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var visibility: StoreVisibilityPreferences
    @State private var searchText = ""

    private var codes: [String] {
        ShoppingCountry.codes.filter {
            searchText.isEmpty || ShoppingCountry.name($0).localizedCaseInsensitiveContains(searchText)
                || $0.localizedCaseInsensitiveContains(searchText)
        }.sorted { ShoppingCountry.name($0).localizedStandardCompare(ShoppingCountry.name($1)) == .orderedAscending }
    }

    var body: some View {
        List {
            Section {
                Text("Choose where you shop, not necessarily where you are. The initial suggestion comes from your device region, not your location. This choice stays on your device and does not restrict which stores you can enable.")
                    .font(.footnote).foregroundStyle(.primary)
            }
            Section {
                ForEach(codes, id: \.self) { code in
                    Button {
                        visibility.setShoppingCountry(code)
                        dismiss()
                    } label: {
                        HStack {
                            Text(ShoppingCountry.name(code)).foregroundStyle(.primary)
                            Spacer()
                            if code == visibility.shoppingCountryCode {
                                Image(systemName: "checkmark").accessibilityHidden(true)
                            }
                        }
                    }
                    .accessibilityIdentifier("shopping-country-\(code)")
                    .accessibilityAddTraits(code == visibility.shoppingCountryCode ? .isSelected : [])
                }
            }
            if codes.isEmpty { Text("No countries found. Try another name or country code.") }
        }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search countries")
        .navigationTitle("Country")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// UITableView supplies the actual native section index, including accessibility,
// tap/drag navigation on every supported iOS (17+).
// SwiftUI's sectionIndexLabel is only available from iOS 26.
private struct StoreManagementTable: UIViewControllerRepresentable {
    let sections: [StoreBrand.Section]
    let searching: Bool
    let selectBrand: (StoreBrand) -> Void

    func makeUIViewController(context: Context) -> Controller {
        Controller(model: self)
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.model = self
        controller.tableView.reloadData()
    }

    final class Controller: UITableViewController {
        var model: StoreManagementTable

        init(model: StoreManagementTable) {
            self.model = model
            super.init(style: .insetGrouped)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func viewDidLoad() {
            super.viewDidLoad()
            tableView.accessibilityIdentifier = "manage-stores-table"
            tableView.backgroundColor = .systemGroupedBackground
            tableView.rowHeight = UITableView.automaticDimension
            tableView.estimatedRowHeight = 54
            tableView.estimatedSectionHeaderHeight = 40
            tableView.sectionIndexColor = .systemBlue
            tableView.sectionIndexBackgroundColor = .clear
            tableView.sectionIndexMinimumDisplayRowCount = 0
            tableView.keyboardDismissMode = .interactive
        }

        override func numberOfSections(in tableView: UITableView) -> Int { model.sections.count }

        override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
            model.sections[section].brands.count
        }

        override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
            let brand = model.sections[indexPath.section].brands[indexPath.row]
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = brand.name
            cell.textLabel?.font = .preferredFont(forTextStyle: .body)
            cell.textLabel?.adjustsFontForContentSizeCategory = true
            cell.textLabel?.numberOfLines = 0
            cell.accessoryType = .disclosureIndicator
            cell.isAccessibilityElement = true
            cell.accessibilityLabel = brand.name
            cell.accessibilityTraits = .button
            cell.accessibilityIdentifier = "manage-store-\(brand.id)"
            return cell
        }

        override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
            tableView.deselectRow(at: indexPath, animated: false)
            model.selectBrand(model.sections[indexPath.section].brands[indexPath.row])
        }

        override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
            let group = model.sections[section]
            let header = UITableViewHeaderFooterView(reuseIdentifier: nil)
            header.contentConfiguration = UIHostingConfiguration {
                VStack(alignment: .leading, spacing: 12) {
                    if group.beginsOtherStores {
                        if model.sections.contains(where: { $0.indexTitle == nil && $0.title.hasPrefix("Stores in ") }) {
                            Divider().padding(.top, 8)
                        } else {
                            Text("No supported stores for this country yet.")
                                .font(.footnote).foregroundStyle(Color(uiColor: .label))
                        }
                        Text("OTHER STORES").font(.footnote).foregroundStyle(Color(uiColor: .label))
                    }
                    Text(group.title.uppercased()).font(.footnote).foregroundStyle(Color(uiColor: .label))
                        .accessibilityAddTraits(.isHeader)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .margins(.horizontal, 16)
            .margins(.vertical, 10)
            header.backgroundConfiguration = .clear()
            return header
        }

        override func sectionIndexTitles(for tableView: UITableView) -> [String]? {
            let titles = model.sections.compactMap(\.indexTitle)
            return model.searching || titles.isEmpty ? nil : titles
        }

        override func tableView(_ tableView: UITableView, sectionForSectionIndexTitle title: String, at index: Int) -> Int {
            model.sections.firstIndex { $0.indexTitle == title } ?? 0
        }
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
