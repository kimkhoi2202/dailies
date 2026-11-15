import SwiftUI

// Group G2: the small parts shared by You, Inbox, History, Settings, the sheets and the offline feed.
// Each one is drawn with the design system's tokens and stands beside its components, never in place of one.

/// An on/off switch. On is ink, off is a quiet well.
struct G2Switch: View {
    @Environment(\.colorScheme) private var scheme
    var isOn: Bool = true

    private var knob: Color {
        if isOn { return DL.onInk }
        // A white knob would glare on the dark well, so it drops to the faintest ink.
        return scheme == .dark ? DL.ink3 : DL.raised
    }

    var body: some View {
        Capsule()
            .fill(isOn ? DL.ink : DL.sunken)
            .frame(width: 50, height: 30)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle().fill(knob).frame(width: 24, height: 24).padding(3)
            }
            .accessibilityLabel(isOn ? "On" : "Off")
    }
}

/// A segmented control in mono capitals. The chosen segment is an ink pill.
struct G2Segmented: View {
    var items: [String]
    var selected: Int = 0

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items.indices, id: \.self) { index in
                let chosen = index == selected
                Text(items[index])
                    .font(DL.label(12))
                    .textCase(.uppercase)
                    .tracking(0.4)
                    .foregroundStyle(chosen ? DL.onInk : DL.ink2)
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .background(Capsule().fill(chosen ? DL.ink : .clear))
            }
        }
        .padding(4)
        .background(Capsule().fill(DL.surface))
        .overlay(Capsule().strokeBorder(DL.line))
    }
}

/// A symbol in a small rounded well, for the leading edge of a row on a card.
struct G2SymbolTile: View {
    var symbol: String
    var size: CGFloat = 40
    var tint: Color = DL.ink
    var fill: Color = DL.body

    var body: some View {
        let corner = min(DL.tileRadius, size * 0.35)
        Image(systemName: symbol)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: corner, style: .continuous).fill(fill))
            .accessibilityHidden(true)
    }
}

/// One of a player's clips in a grid: a moment of play with the clip's play count on it.
struct G2ClipTile: View {
    let game: MockGame
    var phase: Double? = nil
    var plays: String
    var width: CGFloat = 118
    var height: CGFloat = 172

    var body: some View {
        ClipStill(game: game, phase: phase, showHUD: false, focusY: 0.2)
            .overlay(LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom))
            .overlay(alignment: .bottomLeading) {
                HStack(spacing: 4) {
                    Image(systemName: "play.fill").font(.system(size: 9, weight: .bold))
                    Text(plays).font(DL.label(10.5))
                }
                .foregroundStyle(.white)
                .padding(10)
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .accessibilityLabel("\(game.title) clip, \(plays) plays")
    }
}

/// Sign in with Apple, as Apple draws it: white on black, here in a capsule.
struct G2AppleButton: View {
    @Environment(\.colorScheme) private var scheme
    var title: String = "Sign in with Apple"

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "apple.logo")
                .font(.system(size: 19, weight: .semibold))
                .offset(y: -1)
            Text(title).font(.system(size: 20, weight: .semibold))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .frame(height: 56)
        .background(Capsule().fill(.black))
        // On a dark sheet a black button needs an edge to be seen.
        .overlay(Capsule().strokeBorder(.white.opacity(scheme == .dark ? 0.3 : 0), lineWidth: 1))
        .accessibilityLabel(title)
    }
}

/// The second choice under a key: plain text across the full width, tall enough to tap.
struct G2QuietButton: View {
    var title: String

    var body: some View {
        Text(title)
            .font(DL.text(16, .semibold))
            .foregroundStyle(DL.ink2)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
    }
}

/// A hairline as wide as the content of the card it is in.
struct G2Hairline: View {
    var body: some View {
        DL.line.frame(height: 1)
    }
}

extension Mock {
    /// The game a ledger row belongs to. Rows without one borrow Tippy Tower's art.
    static func g2Game(for kind: GameKind?) -> MockGame {
        games.first { $0.kind == kind } ?? tippyTower
    }
}
