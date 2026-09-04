import SwiftUI

struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5))
            )
    }
}

struct UsageBar: View {
    var fraction: Double
    var threshold: Double?
    var tint: Color = .accentColor

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color(nsColor: .quaternaryLabelColor).opacity(0.4))
                Capsule()
                    .fill(tint)
                    .frame(width: max(3, geometry.size.width * clamp(fraction)))
                if let threshold, threshold > 0, threshold < 1 {
                    Rectangle()
                        .fill(Color.primary.opacity(0.55))
                        .frame(width: 2)
                        .offset(x: geometry.size.width * threshold - 1)
                }
            }
        }
        .frame(height: 6)
    }

    private func clamp(_ value: Double) -> Double { min(max(value, 0), 1) }
}
