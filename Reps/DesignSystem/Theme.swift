import SwiftUI

/// "The Ledger" palette — see docs/DESIGN.md.
/// One accent (madder), spent only on *now* and personal records.
enum Palette {
    static let paper    = Color(red: 250 / 255, green: 250 / 255, blue: 247 / 255) // #FAFAF7
    static let ink      = Color(red: 28 / 255,  green: 27 / 255,  blue: 24 / 255)  // #1C1B18
    static let graphite = Color(red: 110 / 255, green: 107 / 255, blue: 99 / 255)  // #6E6B63
    static let chalk    = Color(red: 239 / 255, green: 238 / 255, blue: 233 / 255) // #EFEEE9
    static let madder   = Color(red: 140 / 255, green: 58 / 255,  blue: 46 / 255)  // #8C3A2E

    /// Hairline rules and quiet strokes.
    static let hairline = graphite.opacity(0.35)

    // Card stocks (v2): each domain gets its own quiet paper color.
    static let sage   = Color(red: 227 / 255, green: 234 / 255, blue: 224 / 255) // #E3EAE0 — activity
    static let butter = Color(red: 245 / 255, green: 237 / 255, blue: 218 / 255) // #F5EDDA — food
}

/// A section card cut from its own paper stock.
struct CardStock: ViewModifier {
    let stock: Color

    func body(content: Content) -> some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(stock, in: RoundedRectangle(cornerRadius: 20))
            .shadow(color: Palette.ink.opacity(0.06), radius: 12, y: 4)
    }
}

extension View {
    func cardStock(_ stock: Color) -> some View {
        modifier(CardStock(stock: stock))
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
