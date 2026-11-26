import SwiftUI

/// Training Strokes' look: fairway greens with a flag-yellow highlight and
/// condensed, scoreboard-style numbers. Colors live in Assets.xcassets with
/// light and dark variants.
enum Theme {
    static let pine = Color.accentColor
    static let ground = Color("Ground")
    static let card = Color("Card")
    static let fairway = Color("Fairway")
    static let flag = Color("Flag")
    static let ink = Color("Ink")

    /// Big numbers: condensed bold, with digits that line up.
    static func score(_ style: Font.TextStyle = .title) -> Font {
        .system(style, weight: .bold).width(.condensed).monospacedDigit()
    }

    /// Screen titles and the wordmark.
    static func display(_ style: Font.TextStyle = .largeTitle) -> Font {
        .system(style, weight: .heavy).width(.condensed)
    }
}

/// The app icon's ball flight, drawn live for the welcome screen.
struct BallFlightMark: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let start = CGPoint(x: w * 0.16, y: h * 0.74)
            let end = CGPoint(x: w * 0.84, y: h * 0.59)
            let control = CGPoint(x: w * 0.46, y: -h * 0.15)
            ZStack {
                Capsule()
                    .fill(Theme.fairway)
                    .frame(width: w * 0.76, height: h * 0.028)
                    .position(x: w * 0.5, y: h * 0.74)
                Path { path in
                    path.move(to: start)
                    path.addQuadCurve(to: end, control: control)
                }
                .stroke(Color.white, style: StrokeStyle(lineWidth: w * 0.05, lineCap: .round))
                Circle()
                    .fill(Theme.flag)
                    .frame(width: w * 0.13, height: w * 0.13)
                    .position(end)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .background(
            LinearGradient(colors: [Color(red: 0.14, green: 0.40, blue: 0.25), Color(red: 0.06, green: 0.20, blue: 0.13)],
                           startPoint: .top, endPoint: .bottom),
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
        .accessibilityHidden(true)
    }
}
