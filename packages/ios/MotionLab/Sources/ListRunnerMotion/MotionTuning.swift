import SwiftUI

/// Every timing the Motion Lab components use, in one place so Previews can
/// adjust them live. Durations are in seconds at normal speed; `slowMotion`
/// stretches all of them for frame-by-frame inspection.
public struct MotionTuning: Equatable, Sendable {
    /// Spring that resizes the status badge when its label changes.
    public var badgeDuration: Double = 0.35
    public var badgeBounce: Double = 0.2
    /// Peak scale of the brief "pop" when an item becomes Added.
    public var pulseScale: Double = 1.12
    public var pulseDuration: Double = 0.42
    /// How long the tick takes to draw, and how long it waits for the badge to settle.
    public var tickDuration: Double = 0.28
    public var tickDelay: Double = 0.08
    /// Crossfade for mirrored updates, e.g. a shared item on its other list.
    public var quietDuration: Double = 0.3
    /// How long counts take to roll to their new value.
    public var countDuration: Double = 0.4
    /// 1 = real time; 4 = four times slower. Previews only.
    public var slowMotion: Double = 1
    /// Previews can't switch the system setting, so this simulates it.
    public var forceReduceMotion = false

    public init() {}

    public static let standard = MotionTuning()

    public func seconds(_ value: Double) -> Double { value * max(slowMotion, 0.1) }

    var badgeSpring: Animation { .spring(duration: seconds(badgeDuration), bounce: badgeBounce) }
    var quiet: Animation { .easeInOut(duration: seconds(quietDuration)) }
    var count: Animation { .smooth(duration: seconds(countDuration)) }
    /// The only motion left when Reduce Motion is on: a short crossfade.
    var reduced: Animation { .easeInOut(duration: seconds(0.2)) }

    /// The values as Swift, for copying tuned numbers back into the code.
    public var swiftDescription: String {
        func f(_ v: Double) -> String { String(format: "%.2f", v) }
        return """
        badgeDuration: \(f(badgeDuration)), badgeBounce: \(f(badgeBounce))
        pulseScale: \(f(pulseScale)), pulseDuration: \(f(pulseDuration))
        tickDuration: \(f(tickDuration)), tickDelay: \(f(tickDelay))
        quietDuration: \(f(quietDuration)), countDuration: \(f(countDuration))
        """
    }
}

private struct MotionTuningKey: EnvironmentKey {
    static let defaultValue = MotionTuning.standard
}

public extension EnvironmentValues {
    var motionTuning: MotionTuning {
        get { self[MotionTuningKey.self] }
        set { self[MotionTuningKey.self] = newValue }
    }
}

/// Haptics that go with the motion. Marking one item gets a light tap;
/// `success` is saved for finishing a whole list.
public enum MotionHaptics {
    public static let itemAdded = SensoryFeedback.impact(weight: .light)
}
