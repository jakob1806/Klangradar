import SwiftUI

/// Google's official multi-color "G" glyph (redrawn from the standard
/// 18×18 `ic_googleg` mark used by Google's own sign-in buttons), so "Mit
/// Google anmelden" shows the real logo instead of a generic single-color
/// SF Symbol placeholder — Google's brand guidelines require the actual
/// mark, not a substitute.
struct GoogleLogoView: View {
    var body: some View {
        GeometryReader { proxy in
            let scale = min(proxy.size.width, proxy.size.height) / 18
            let transform = CGAffineTransform(scaleX: scale, y: scale)
            ZStack {
                Self.blue.applying(transform).fill(Color(red: 0.259, green: 0.522, blue: 0.957))
                Self.green.applying(transform).fill(Color(red: 0.204, green: 0.659, blue: 0.325))
                Self.yellow.applying(transform).fill(Color(red: 0.984, green: 0.737, blue: 0.020))
                Self.red.applying(transform).fill(Color(red: 0.918, green: 0.263, blue: 0.208))
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private static let blue = Path { path in
        path.move(to: CGPoint(x: 17.64, y: 9.20455))
        path.addCurve(
            to: CGPoint(x: 17.4764, y: 7.36364),
            control1: CGPoint(x: 17.64, y: 8.56636),
            control2: CGPoint(x: 17.5827, y: 7.95273)
        )
        path.addLine(to: CGPoint(x: 9, y: 7.36364))
        path.addLine(to: CGPoint(x: 9, y: 10.845))
        path.addLine(to: CGPoint(x: 13.8436, y: 10.845))
        path.addCurve(
            to: CGPoint(x: 12.0477, y: 13.5613),
            control1: CGPoint(x: 13.635, y: 11.97),
            control2: CGPoint(x: 13.0009, y: 12.9231)
        )
        path.addLine(to: CGPoint(x: 12.0477, y: 15.8195))
        path.addLine(to: CGPoint(x: 14.9564, y: 15.8195))
        path.addCurve(
            to: CGPoint(x: 17.64, y: 9.20455),
            control1: CGPoint(x: 16.6582, y: 14.2527),
            control2: CGPoint(x: 17.64, y: 11.9455)
        )
        path.closeSubpath()
    }

    private static let green = Path { path in
        path.move(to: CGPoint(x: 9, y: 18))
        path.addCurve(
            to: CGPoint(x: 14.9564, y: 15.8195),
            control1: CGPoint(x: 11.43, y: 18),
            control2: CGPoint(x: 13.4673, y: 17.1941)
        )
        path.addLine(to: CGPoint(x: 12.0477, y: 13.5613))
        path.addCurve(
            to: CGPoint(x: 9, y: 14.4204),
            control1: CGPoint(x: 11.2418, y: 14.1013),
            control2: CGPoint(x: 10.2109, y: 14.4204)
        )
        path.addCurve(
            to: CGPoint(x: 3.96409, y: 10.71),
            control1: CGPoint(x: 6.65591, y: 14.4204),
            control2: CGPoint(x: 4.67182, y: 12.8368)
        )
        path.addLine(to: CGPoint(x: 0.957273, y: 10.71))
        path.addLine(to: CGPoint(x: 0.957273, y: 13.0418))
        path.addCurve(
            to: CGPoint(x: 9, y: 18),
            control1: CGPoint(x: 2.43818, y: 15.9831),
            control2: CGPoint(x: 5.48182, y: 18)
        )
        path.closeSubpath()
    }

    private static let yellow = Path { path in
        path.move(to: CGPoint(x: 3.96409, y: 10.71))
        path.addCurve(
            to: CGPoint(x: 3.68182, y: 9),
            control1: CGPoint(x: 3.78409, y: 10.17),
            control2: CGPoint(x: 3.68182, y: 9.59318)
        )
        path.addCurve(
            to: CGPoint(x: 3.96409, y: 7.29),
            control1: CGPoint(x: 3.68182, y: 8.40682),
            control2: CGPoint(x: 3.78409, y: 7.83)
        )
        path.addLine(to: CGPoint(x: 3.96409, y: 4.95818))
        path.addLine(to: CGPoint(x: 0.957273, y: 4.95818))
        path.addCurve(
            to: CGPoint(x: 0, y: 9),
            control1: CGPoint(x: 0.347727, y: 6.17318),
            control2: CGPoint(x: 0, y: 7.54773)
        )
        path.addCurve(
            to: CGPoint(x: 0.957273, y: 13.0418),
            control1: CGPoint(x: 0, y: 10.4523),
            control2: CGPoint(x: 0.347727, y: 11.8268)
        )
        path.addLine(to: CGPoint(x: 3.96409, y: 10.71))
        path.closeSubpath()
    }

    private static let red = Path { path in
        path.move(to: CGPoint(x: 9, y: 3.57955))
        path.addCurve(
            to: CGPoint(x: 12.4405, y: 4.92545),
            control1: CGPoint(x: 10.3214, y: 3.57955),
            control2: CGPoint(x: 11.5077, y: 4.03364)
        )
        path.addLine(to: CGPoint(x: 15.0218, y: 2.34409))
        path.addCurve(
            to: CGPoint(x: 9, y: 0),
            control1: CGPoint(x: 13.4632, y: 0.891818),
            control2: CGPoint(x: 11.4259, y: 0)
        )
        path.addCurve(
            to: CGPoint(x: 0.957273, y: 4.95818),
            control1: CGPoint(x: 5.48182, y: 0),
            control2: CGPoint(x: 2.43818, y: 2.01682)
        )
        path.addLine(to: CGPoint(x: 3.96409, y: 7.29))
        path.addCurve(
            to: CGPoint(x: 9, y: 3.57955),
            control1: CGPoint(x: 4.67182, y: 5.16318),
            control2: CGPoint(x: 6.65591, y: 3.57955)
        )
        path.closeSubpath()
    }
}

#Preview {
    GoogleLogoView()
        .frame(width: 24, height: 24)
        .padding()
}
