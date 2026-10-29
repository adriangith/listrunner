import Foundation

enum SessionResetPhase: Equatable { case ready, resetting, failed }
enum StoreRecovery: Equatable { case loadFailed, processTerminated }
enum CartDetectionIssue { case productIDUnavailable, quantityUnavailable, confirmationTimedOut }

// Limits app-initiated requests, not the retailer's own verification redirects.
// The latest requested search replaces earlier queued searches in StoreBrowser.
struct StoreNavigationPacing {
    static let minimumInterval: TimeInterval = 2
    static let verificationPause: TimeInterval = 30
    private(set) var lastRequest: TimeInterval?
    private(set) var blockedUntil: TimeInterval?

    func delay(at now: TimeInterval) -> TimeInterval {
        max(0, (lastRequest.map { $0 + Self.minimumInterval } ?? now) - now)
    }
    mutating func requested(at now: TimeInterval) { lastRequest = now }
    mutating func blocked(at now: TimeInterval) {
        blockedUntil = max(blockedUntil ?? now, now + Self.verificationPause)
    }
    func canRetry(at now: TimeInterval) -> Bool { now >= (blockedUntil ?? now) }
    mutating func clearBlock() { blockedUntil = nil }

    static func isVerificationPage(title: String, heading: String) -> Bool {
        [title, heading].contains {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "pardon our interruption"
        }
    }
}

struct SessionResetOperation {
    private(set) var phase: SessionResetPhase = .ready
    private var generation = UUID()

    mutating func begin() -> UUID? {
        guard phase != .resetting else { return nil }
        generation = UUID()
        phase = .resetting
        return generation
    }

    mutating func complete(_ token: UUID, verified: Bool) -> Bool {
        guard generation == token, phase == .resetting else { return false }
        phase = verified ? .ready : .failed
        return true
    }

    mutating func cancelFailure() -> Bool {
        guard phase == .failed else { return false }
        generation = UUID()
        phase = .ready
        return true
    }
}

// No arbitrary text, URLs, item names, identifiers, quantities or error descriptions
// can enter release diagnostics through this API.
struct DiagnosticEntry: Codable, Equatable {
    enum Category: String, Codable { case store, storage, automation }
    enum Event: String, Codable { case load, processExit, sessionReset, localOpen, localReset, localSave, cartDetection, cartUndo }
    enum Reason: String, Codable { case none, network, timedOut, verificationFailed, unavailable, staleContext, unsupported, storageFailure }
    enum Outcome: String, Codable { case succeeded, failed, cancelled, ignored }
    enum Host: String, Codable {
        case www = "www.coles.com.au", bare = "coles.com.au"
        case woolworths = "www.woolworths.com.au", woolworthsBare = "woolworths.com.au"
        case bunnings = "www.bunnings.com.au", bunningsBare = "bunnings.com.au"
        case costco = "www.costco.com.au", costcoBare = "costco.com.au"
        case costcoUS = "www.costco.com", costcoUSBare = "costco.com"
        case tesco = "www.tesco.com", tescoBare = "tesco.com"
        case walmart = "www.walmart.com", walmartBare = "walmart.com"
        case kmart = "www.kmart.com.au", kmartBare = "kmart.com.au"
        case bigW = "www.bigw.com.au", bigWBare = "bigw.com.au"
    }
    let timestamp: Date
    let sequence: UInt64
    let category: Category
    let event: Event
    let reason: Reason
    let outcome: Outcome
    let host: Host?
}

final class DiagnosticStore {
    static let lifetime: TimeInterval = 168 * 60 * 60
    static let countLimit = 2_000
    static let byteLimit = 2 * 1_024 * 1_024
    static var defaultURL: URL {
        URL.applicationSupportDirectory.appendingPathComponent("ListRunner/diagnostics.json")
    }
    private(set) var entries: [DiagnosticEntry] = []
    private var nextSequence: UInt64 = 0
    private let fileURL: URL?
    private let clock: () -> Date
    private let encoder: JSONEncoder = {
        let value = JSONEncoder()
        value.outputFormatting = [.sortedKeys]
        return value
    }()

    init(fileURL: URL? = DiagnosticStore.defaultURL, clock: @escaping () -> Date = Date.init) {
        self.fileURL = fileURL
        self.clock = clock
        if let fileURL, let data = try? Data(contentsOf: fileURL), data.count <= Self.byteLimit + 128_000,
           let saved = try? JSONDecoder().decode([DiagnosticEntry].self, from: data) {
            entries = saved
            nextSequence = (saved.map(\.sequence).max() ?? 0) &+ 1
        }
        purge()
    }

    var byteCount: Int { entries.reduce(0) { $0 + ((try? encoder.encode($1).count) ?? 0) } }

    func record(_ category: DiagnosticEntry.Category, _ event: DiagnosticEntry.Event,
                reason: DiagnosticEntry.Reason = .none, outcome: DiagnosticEntry.Outcome,
                host: DiagnosticEntry.Host? = nil) {
        let now = clock()
        purgeExpired(now)
        let duplicate = entries.contains {
            $0.category == category && $0.event == event && $0.reason == reason &&
            $0.outcome == outcome && $0.host == host && now.timeIntervalSince($0.timestamp) < 60
        }
        if !duplicate {
            entries.append(DiagnosticEntry(timestamp: now, sequence: nextSequence, category: category,
                                           event: event, reason: reason, outcome: outcome, host: host))
            nextSequence &+= 1
        }
        trim()
        persist()
    }

    func purge() {
        purgeExpired(clock())
        trim()
        persist()
    }

    func clear(storeID: StoreID? = nil) throws {
        if let storeID {
            let kept = entries.filter { entry in
                guard let host = entry.host else { return true }
                return !storeID.hosts.contains(host.rawValue)
            }
            if let fileURL {
                try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try encoder.encode(kept).write(to: fileURL, options: .atomic)
            }
            entries = kept
            return
        }
        // Do not report success if the on-disk records could not be removed.
        if let fileURL, FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
        entries.removeAll()
    }

    private func purgeExpired(_ now: Date) {
        entries.removeAll { $0.timestamp <= now.addingTimeInterval(-Self.lifetime) }
    }

    private func trim() {
        entries.sort { $0.timestamp == $1.timestamp ? $0.sequence < $1.sequence : $0.timestamp < $1.timestamp }
        var bytes = byteCount
        while entries.count > Self.countLimit || bytes > Self.byteLimit {
            bytes -= (try? encoder.encode(entries.removeFirst()).count) ?? 0
        }
    }

    private func persist() {
        guard let fileURL, let data = try? encoder.encode(entries) else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Diagnostics never interrupt shopping or masquerade as a grocery-save error.
        }
    }
}
