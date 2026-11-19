import SwiftUI

/// A count that rolls to its new value instead of jumping.
public struct RollingCount: View {
    let value: Int
    let tint: Color

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.motionTuning) private var tuning

    public init(_ value: Int, tint: Color) {
        self.value = value
        self.tint = tint
    }

    private var reduceMotion: Bool { systemReduceMotion || tuning.forceReduceMotion }

    public var body: some View {
        Text(value, format: .number)
            .font(.headline.monospacedDigit())
            .foregroundStyle(tint)
            .contentTransition(reduceMotion ? .opacity : .numericText(value: Double(value)))
            .animation(reduceMotion ? tuning.reduced : tuning.count, value: value)
    }
}

/// The list page's Pending / Added / Skipped summary, matching
/// `ListPageSummary` in the app, with rolling counts and a heading that
/// blurs across when the list becomes Complete.
public struct SummaryCounts: View {
    let pending: Int
    let added: Int
    let skipped: Int
    let tint: Color

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.motionTuning) private var tuning

    public init(pending: Int, added: Int, skipped: Int, tint: Color) {
        self.pending = pending
        self.added = added
        self.skipped = skipped
        self.tint = tint
    }

    private var reduceMotion: Bool { systemReduceMotion || tuning.forceReduceMotion }
    private var heading: String {
        pending + added + skipped > 0 && pending == 0 ? "Complete" : "Ready when you are"
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(heading)
                .font(.subheadline).foregroundStyle(.secondary)
                .id(heading)
                .transition(reduceMotion ? .opacity : AnyTransition(.blurReplace))
                .animation(reduceMotion ? tuning.reduced : tuning.count, value: heading)
            HStack(spacing: 0) {
                metric(pending, "Pending", tint)
                Divider().frame(height: 32)
                metric(added, "Added", tint)
                Divider().frame(height: 32)
                metric(skipped, "Skipped", .secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(pending) pending, \(added) added, \(skipped) skipped")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metric(_ count: Int, _ title: String, _ tint: Color) -> some View {
        VStack(spacing: 1) {
            RollingCount(count, tint: tint)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview("Summary counts") {
    @Previewable @State var added = 0
    VStack(spacing: 24) {
        SummaryCounts(pending: 4 - added, added: added, skipped: 0, tint: DemoStore.coles.tint)
        HStack {
            Button("Add one") { if added < 4 { added += 1 } }
            Button("Reset") { added = 0 }
        }
        .buttonStyle(.bordered)
    }
    .padding()
}
