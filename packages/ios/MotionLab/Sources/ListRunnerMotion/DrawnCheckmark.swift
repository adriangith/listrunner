import SwiftUI

/// A tick drawn as one stroke, so it can be revealed from start to end.
/// A custom shape rather than an SF Symbol draw effect, because the app
/// still supports iOS 17.
struct CheckmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.55))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.36, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}

public struct DrawnCheckmark: View {
    /// 0 = not drawn, 1 = fully drawn. Animatable.
    var progress: CGFloat
    var lineWidth: CGFloat

    public init(progress: CGFloat, lineWidth: CGFloat = 1.6) {
        self.progress = progress
        self.lineWidth = lineWidth
    }

    public var body: some View {
        CheckmarkShape()
            .trim(from: 0, to: progress)
            .stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
    }
}

#Preview("Checkmark draw") {
    @Previewable @State var drawn = false
    VStack(spacing: 24) {
        DrawnCheckmark(progress: drawn ? 1 : 0, lineWidth: 6)
            .foregroundStyle(.red)
            .frame(width: 80, height: 64)
        Button(drawn ? "Erase" : "Draw") {
            withAnimation(.easeOut(duration: 0.6)) { drawn.toggle() }
        }
    }
    .padding(40)
}
