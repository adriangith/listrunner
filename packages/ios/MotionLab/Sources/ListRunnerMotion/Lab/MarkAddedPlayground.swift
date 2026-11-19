import SwiftUI

/// Animation 1, "Marking items Added", in context: two store lists sharing
/// Milk. Tap a row to toggle Added; long-press for Skipped. The list you
/// tap animates prominently (pop, spring, drawn tick, light haptic); the
/// shared item's other list updates quietly; both summaries roll their counts.
struct MarkAddedPlayground: View {
    @State private var statuses: [String: ItemStatus] = [:]
    /// The list each item was last changed from: it gets the prominent animation.
    @State private var changedFrom: [String: DemoStore] = [:]
    @State private var addedTaps = 0
    @State private var tuning: MotionTuning
    @State private var showTuning = true

    init(tuning: MotionTuning = .standard) {
        _tuning = State(initialValue: tuning)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                controls
                ForEach(DemoData.lists) { store in
                    listCard(store)
                }
                if showTuning {
                    MotionTuningPanel(tuning: $tuning)
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .environment(\.motionTuning, tuning)
        .sensoryFeedback(MotionHaptics.itemAdded, trigger: addedTaps)
    }

    private var controls: some View {
        HStack {
            Button("Add all on Coles") {
                for item in DemoData.items(on: .coles) { set(item, .added, from: .coles) }
            }
            Button("Reset") {
                statuses = [:]
                changedFrom = [:]
            }
            Spacer()
            Toggle("Tuning", isOn: $showTuning).fixedSize()
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private func listCard(_ store: DemoStore) -> some View {
        let items = DemoData.items(on: store)
        let count = { (wanted: ItemStatus) in items.filter { status(of: $0) == wanted }.count }
        return VStack(alignment: .leading, spacing: 12) {
            Text(store.name).font(.title3.weight(.semibold)).foregroundStyle(store.tint)
            SummaryCounts(pending: count(.pending), added: count(.added), skipped: count(.skipped), tint: store.tint)
                .padding(.bottom, 4)
            VStack(spacing: 0) {
                ForEach(items) { item in
                    row(item, on: store)
                    if item.id != items.last?.id {
                        Divider().padding(.leading, 16)
                    }
                }
            }
            .background(.background, in: RoundedRectangle(cornerRadius: 26))
        }
    }

    private func row(_ item: DemoItem, on store: DemoStore) -> some View {
        let others = item.stores.filter { $0 != store }.map(\.name)
        let detail = others.isEmpty
            ? "Quantity \(item.quantity)"
            : "Quantity \(item.quantity) · Also in \(others.joined(separator: ", "))"
        let emphasis: StatusBadge.Emphasis = (changedFrom[item.id] ?? store) == store ? .prominent : .quiet
        return Button {
            set(item, status(of: item) == .added ? .pending : .added, from: store)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name).font(.body.weight(.medium)).foregroundStyle(.primary)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 6)
                StatusBadge(status: status(of: item), tint: store.tint, emphasis: emphasis)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 60)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Mark Pending") { set(item, .pending, from: store) }
            Button("Mark Added") { set(item, .added, from: store) }
            Button("Mark Skipped") { set(item, .skipped, from: store) }
        }
    }

    private func status(of item: DemoItem) -> ItemStatus { statuses[item.id] ?? .pending }

    private func set(_ item: DemoItem, _ status: ItemStatus, from store: DemoStore) {
        guard self.status(of: item) != status else { return }
        changedFrom[item.id] = store
        statuses[item.id] = status
        if status == .added { addedTaps += 1 }
    }
}

#Preview("Mark Added · playground") {
    MarkAddedPlayground()
}

#Preview("Mark Added · Reduce Motion") {
    var tuning = MotionTuning.standard
    tuning.forceReduceMotion = true
    return MarkAddedPlayground(tuning: tuning)
}

#Preview("Mark Added · dark") {
    MarkAddedPlayground()
        .preferredColorScheme(.dark)
}
