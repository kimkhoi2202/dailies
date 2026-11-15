import SwiftUI

/// Dailies design tokens. The idea is a pocket arcade: a bone body in light mode, graphite in dark,
/// ink type, and gold as the one colour. Every colour carries both appearances, so screens use these
/// names and never a raw hex value.
enum DL {
    // Surfaces, from the page upward
    static let body = Color(light: "ECE8E1", dark: "0E0E0F")
    /// Cards and grouped rows.
    static let surface = Color(light: "F8F6F1", dark: "1A1A1C")
    /// Sheets, and anything that sits on a card.
    static let raised = Color(light: "FFFFFF", dark: "252528")
    /// Tracks, wells and the empty part of a meter.
    static let sunken = Color(light: "DDD7CC", dark: "2B2B2E")
    static let line = Color(light: "D8D2C7", dark: "2C2C2F")

    // Ink
    static let ink = Color(light: "151412", dark: "F3F0E9")
    static let ink2 = Color(light: "57534C", dark: "A9A59D")
    static let ink3 = Color(light: "6B665D", dark: "86837B")
    /// Text and icons on an ink fill.
    static let onInk = Color(light: "F8F6F1", dark: "151412")

    // Gold
    /// Gold as a fill: the Play key and full meters.
    static let gold = Color(light: "F5B301", dark: "FFC531")
    /// The darker edge a gold key sits on.
    static let goldLip = Color(light: "C48A00", dark: "A87A08")
    /// Gold as text or a thin stroke on the page. Dark enough to read on bone.
    static let goldText = Color(light: "855600", dark: "FFC531")
    static let goldWash = Color(light: "F7E7B8", dark: "33290F")
    /// Whatever sits on gold is this ink in both appearances.
    static let onGold = Color(hex: "151412")
    /// The coin is brighter than the key, so it reads as a coin and not as a button.
    static let coinFace = Color(hex: "FFCB2E")
    static let coinEdge = Color(hex: "D99400")
    static let coinShine = Color(hex: "FFE9A6")

    // Functional
    static let danger = Color(light: "C2331F", dark: "FF6B57")
    static let success = Color(light: "1F7A4D", dark: "4CC38A")

    // Type
    /// Big Shoulders Black, for numerals, titles and key labels. Titles are set in capitals.
    static func display(_ size: CGFloat) -> Font { .custom("BigShoulders-Black", size: size) }
    static func displayBold(_ size: CGFloat) -> Font { .custom("BigShoulders-ExtraBold", size: size) }
    /// SF Pro, for everything that is read.
    static func text(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight) }
    /// SF Mono, for the small capital labels.
    static func label(_ size: CGFloat = 11) -> Font { .system(size: size, weight: .semibold, design: .monospaced) }

    // Shape
    static let cardRadius: CGFloat = 26
    static let tileRadius: CGFloat = 14
    static let keyRadius: CGFloat = 24
    static let margin: CGFloat = 16
    /// Media that runs edge to edge at the top of a screen. The phone rounds the top corners itself,
    /// so only the bottom ones are rounded, where the media meets the page.
    static let screenShape = UnevenRoundedRectangle(cornerRadii: RectangleCornerRadii(bottomLeading: 30, bottomTrailing: 30),
                                                    style: .continuous)
}

extension View {
    /// A small capital label in SF Mono.
    func dlLabel(_ size: CGFloat = 11, color: Color = DL.ink2) -> some View {
        font(DL.label(size)).foregroundStyle(color).textCase(.uppercase)
    }

    /// The standard card: full width, content at the leading edge, on a rounded surface.
    func dlCard(padding: CGFloat = 16, fill: Color = DL.surface, radius: CGFloat = DL.cardRadius) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}
