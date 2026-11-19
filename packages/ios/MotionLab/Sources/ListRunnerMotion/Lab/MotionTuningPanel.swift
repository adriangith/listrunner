import SwiftUI

/// Sliders for every MotionTuning value, shown under each Preview so timings
/// can be adjusted live. "Values" prints the current numbers for copying.
struct MotionTuningPanel: View {
    @Binding var tuning: MotionTuning
    @State private var showValues = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Tuning").font(.headline)
                Spacer()
                Button("Values") { showValues.toggle() }
                Button("Reset") { tuning = .standard }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Toggle("Simulate Reduce Motion", isOn: $tuning.forceReduceMotion)
            slider("Slow motion", $tuning.slowMotion, 1...6, step: 0.5, unit: "×")
            slider("Badge spring", $tuning.badgeDuration, 0.15...0.8, unit: "s")
            slider("Badge bounce", $tuning.badgeBounce, 0...0.5)
            slider("Pop scale", $tuning.pulseScale, 1...1.3)
            slider("Pop length", $tuning.pulseDuration, 0.2...0.8, unit: "s")
            slider("Tick draw", $tuning.tickDuration, 0.1...0.8, unit: "s")
            slider("Tick delay", $tuning.tickDelay, 0...0.3, unit: "s")
            slider("Quiet fade", $tuning.quietDuration, 0.1...0.8, unit: "s")
            slider("Count roll", $tuning.countDuration, 0.1...1, unit: "s")

            if showValues {
                Text(tuning.swiftDescription)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .font(.subheadline)
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 22))
    }

    private func slider(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>,
                        step: Double = 0.01, unit: String = "") -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text("\(value.wrappedValue, specifier: "%.2f")\(unit)")
                    .monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: step)
        }
    }
}
