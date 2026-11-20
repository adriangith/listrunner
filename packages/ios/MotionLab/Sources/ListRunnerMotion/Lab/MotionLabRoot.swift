import SwiftUI

/// Index of every Motion Lab playground, used by the Motion Lab host app so
/// the animations can run on a simulator or device as well as in Previews.
public struct MotionLabRoot: View {
    public init() {}

    public var body: some View {
        NavigationStack {
            List {
                Section("1 · Marking items Added") {
                    NavigationLink("Playground") {
                        MarkAddedPlayground().navigationTitle("Mark Added")
                    }
                    NavigationLink("Playground · Reduce Motion") {
                        MarkAddedPlayground(tuning: reduced).navigationTitle("Reduce Motion")
                    }
                    NavigationLink("Status badge loop") {
                        ScrollView { BadgeLoop() }
                            .background(Color(.systemGroupedBackground))
                            .navigationTitle("Badge loop")
                    }
                }
            }
            .navigationTitle("Motion Lab")
        }
    }

    private var reduced: MotionTuning {
        var tuning = MotionTuning.standard
        tuning.forceReduceMotion = true
        return tuning
    }
}

#Preview("Motion Lab") {
    MotionLabRoot()
}
