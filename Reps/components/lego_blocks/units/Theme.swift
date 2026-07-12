import SwiftUI
import UIKit

/// "The Ledger" palette — see docs/DESIGN.md.
/// One accent (madder), spent only on *now* and personal records.
/// Every token is a dynamic color: the light values are the original Ledger
/// paper; the dark values are its night edition (dark paper, light ink), so the
/// app follows the system appearance without any per-view branching.
enum Palette {
    /// Light/dark RGB pair → a system-appearance-aware SwiftUI color.
    private static func dynamic(_ light: (Double, Double, Double),
                                _ dark: (Double, Double, Double)) -> Color {
        Color(uiColor: UIColor { traits in
            let c = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: c.0 / 255, green: c.1 / 255, blue: c.2 / 255, alpha: 1)
        })
    }

    static let paper    = dynamic((250, 250, 247), (20, 20, 18))    // #FAFAF7 / #141412
    static let ink      = dynamic((28, 27, 24),    (236, 235, 230)) // #1C1B18 / #ECEBE6
    static let graphite = dynamic((110, 107, 99),  (150, 146, 136)) // #6E6B63 / #969288
    static let chalk    = dynamic((239, 238, 233), (38, 37, 32))    // #EFEEE9 / #262520
    static let madder   = dynamic((140, 58, 46),   (216, 108, 92))  // #8C3A2E / #D86C5C

    /// Hairline rules and quiet strokes.
    static let hairline = graphite.opacity(0.35)

    /// Card shadow — a real drop in light, a deeper one in dark (never a light halo).
    static let cardShadow = dynamic((28, 27, 24), (0, 0, 0)).opacity(0.10)

    // Card stocks (v2): each domain gets its own quiet paper color.
    static let sage   = dynamic((227, 234, 224), (30, 40, 32))  // #E3EAE0 — activity
    static let butter = dynamic((245, 237, 218), (44, 40, 29))  // #F5EDDA — food
}

/// A section card cut from its own paper stock.
struct CardStock: ViewModifier {
    let stock: Color

    func body(content: Content) -> some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(stock, in: RoundedRectangle(cornerRadius: 20))
            .shadow(color: Palette.cardShadow, radius: 12, y: 4)
    }
}

/// A shadowless card — same paper, no drop shadow. Use inside scrolling editors
/// where many shadowed cards would force per-frame offscreen rendering and make
/// scrolling stutter.
struct FlatCard: ViewModifier {
    let stock: Color

    func body(content: Content) -> some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(stock, in: RoundedRectangle(cornerRadius: 20))
    }
}

extension View {
    func cardStock(_ stock: Color) -> some View {
        modifier(CardStock(stock: stock))
    }

    func flatCard(_ stock: Color) -> some View {
        modifier(FlatCard(stock: stock))
    }
}

enum Typo {
    /// Date masthead eyebrow — small caps feel via tracking.
    static let eyebrow = Font.system(size: 13, weight: .medium).uppercaseSmallCaps()
    /// The big weight numeral — New York light.
    static let numeral = Font.system(size: 76, weight: .light, design: .serif)
    /// Serif for section-level display moments.
    static let display = Font.system(size: 22, weight: .regular, design: .serif)
    /// Ledger data: sets, deltas, timestamps.
    static let mono = Font.system(size: 14, weight: .regular, design: .monospaced)
    static let monoSmall = Font.system(size: 11, weight: .regular, design: .monospaced)
    /// Body/UI.
    static let body = Font.system(size: 16, weight: .regular)
    static let label = Font.system(size: 14, weight: .medium)
}
