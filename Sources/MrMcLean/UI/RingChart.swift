import SwiftUI

struct RingSegment: Identifiable {
    let id = UUID()
    var value: Double
    var color: Color
}

struct RingChart: View {
    var segments: [RingSegment]
    var lineWidth: CGFloat = 20

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2 - lineWidth / 2 - 1

            var track = Path()
            track.addArc(center: center, radius: radius, startAngle: .zero,
                         endAngle: .degrees(360), clockwise: false)
            context.stroke(track,
                           with: .color(Color(nsColor: .quaternaryLabelColor).opacity(0.35)),
                           lineWidth: lineWidth)

            var start = Angle.degrees(-90)
            var remaining = 1.0
            for segment in segments where segment.value > 0 && remaining > 0 {
                let value = min(segment.value, remaining)
                remaining -= value
                let end = start + .degrees(360 * value)
                var arc = Path()
                arc.addArc(center: center, radius: radius, startAngle: start,
                           endAngle: end, clockwise: false)
                context.stroke(arc, with: .color(segment.color),
                               style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                start = end
            }
        }
    }
}
