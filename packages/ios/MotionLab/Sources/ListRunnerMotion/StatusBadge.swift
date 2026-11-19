import SwiftUI

/// Mirrors the app's GroceryStatus without depending on the app target.
public enum ItemStatus: String, CaseIterable, Sendable {
    case pending = "Pending"
    case added = "Added"
    case skipped = "Skipped"
}

/// The list-row status capsule, matching `ListItemContent` in the app
/// (caption2 semibold, store tint on an 11% tint capsule). The colour never
/// changes with status; only the label and tick do.
///
/// - `prominent`: the row the user acted on. Pending → Added pops slightly,
///   resizes with a spring, blurs the label across and draws the tick.
/// - `quiet`: a mirrored update, such as a shared item on its other list.
///   A plain crossfade with the tick already drawn: it should be noticed, not felt.
/// - Reduce Motion: a short crossfade, no pop, no drawing.
public struct StatusBadge: View {
    public enum Emphasis: Sendable { case prominent, quiet }

    let status: ItemStatus
    let tint: Color
    let emphasis: Emphasis

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.motionTuning) private var tuning
    @State private var tickProgress: CGFloat
    @State private var pulse = 0

    public init(status: ItemStatus, tint: Color, emphasis: Emphasis = .prominent) {
        self.status = status
        self.tint = tint
        self.emphasis = emphasis
        _tickProgress = State(initialValue: status == .added ? 1 : 0)
    }

    private var reduceMotion: Bool { systemReduceMotion || tuning.forceReduceMotion }
    private var animatesFully: Bool { emphasis == .prominent && !reduceMotion }

    private var layoutAnimation: Animation {
        if reduceMotion { return tuning.reduced }
        return emphasis == .quiet ? tuning.quiet : tuning.badgeSpring
    }

    public var body: some View {
        HStack(spacing: 4) {
            if status == .added {
                DrawnCheckmark(progress: animatesFully ? tickProgress : 1, lineWidth: 1.6)
                    .frame(width: 8, height: 7)
                    .transition(.opacity)
            }
            Text(status.rawValue)
                .id(status)
                .transition(animatesFully ? AnyTransition(.blurReplace) : .opacity)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, 9).padding(.vertical, 6)
        .background(tint.opacity(0.11), in: Capsule())
        .keyframeAnimator(initialValue: 1.0, trigger: pulse) { content, scale in
            content.scaleEffect(scale)
        } keyframes: { _ in
            KeyframeTrack {
                SpringKeyframe(tuning.pulseScale, duration: tuning.seconds(tuning.pulseDuration * 0.35))
                SpringKeyframe(1.0, duration: tuning.seconds(tuning.pulseDuration * 0.65), spring: .bouncy)
            }
        }
        .animation(layoutAnimation, value: status)
        .onChange(of: status) { _, new in
            guard new == .added else {
                tickProgress = 0
                return
            }
            guard animatesFully else { return }
            tickProgress = 0
            withAnimation(.easeOut(duration: tuning.seconds(tuning.tickDuration))
                .delay(tuning.seconds(tuning.tickDelay))) {
                tickProgress = 1
            }
            pulse += 1
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(status.rawValue)
    }
}

// MARK: - Previews

/// Flips every badge on a loop so timing can be judged without tapping.
private struct BadgeLoop: View {
    @State private var added = false
    @State private var tuning = MotionTuning.standard

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(DemoStore.all) { store in
                HStack(spacing: 16) {
                    Text(store.name).font(.subheadline).foregroundStyle(store.tint)
                        .frame(width: 96, alignment: .leading)
                    StatusBadge(status: added ? .added : .pending, tint: store.tint, emphasis: .prominent)
                    StatusBadge(status: added ? .added : .pending, tint: store.tint, emphasis: .quiet)
                }
            }
            Text("Left: prominent (the row you tapped). Right: quiet (the same item on another list).")
                .font(.caption).foregroundStyle(.secondary)
            MotionTuningPanel(tuning: $tuning)
        }
        .padding()
        .environment(\.motionTuning, tuning)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.6 * tuning.slowMotion))
                added.toggle()
            }
        }
    }
}

#Preview("Status badge · loop") {
    ScrollView { BadgeLoop() }
}

#Preview("Status badge · all states") {
    VStack(alignment: .leading, spacing: 12) {
        ForEach(ItemStatus.allCases, id: \.self) { status in
            HStack {
                ForEach(DemoStore.all) { store in
                    StatusBadge(status: status, tint: store.tint)
                }
            }
        }
    }
    .padding()
}
