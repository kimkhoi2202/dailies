import SwiftUI
import UIKit

// Dailies design system: the parts every screen is built from.

/// The dark frosted backing behind anything that floats on video or game art.
private struct MediaGlass<S: Shape>: View {
    let shape: S
    var dim: Double = 0.4
    var body: some View {
        shape.fill(.ultraThinMaterial)
            .overlay(shape.fill(.black.opacity(dim)))
            .environment(\.colorScheme, .dark)
    }
}

// MARK: Gold

/// The gold coin, seen slightly from above like the keys: a bright face resting on a darker edge,
/// with one thin inner ring and a short shine on the upper left.
struct DLCoin: View {
    var size: CGFloat = 20

    var body: some View {
        let rim = max(1, size * 0.09)
        Circle().fill(DL.coinFace)
            .overlay {
                Circle().inset(by: size * 0.17)
                    .strokeBorder(DL.coinEdge.opacity(0.55), lineWidth: max(0.75, size * 0.05))
            }
            .overlay {
                Circle().inset(by: size * 0.3).trim(from: 0.56, to: 0.72)
                    .stroke(DL.coinShine, style: StrokeStyle(lineWidth: max(1, size * 0.075), lineCap: .round))
            }
            .background(Circle().fill(DL.coinEdge).offset(y: rim))
            .frame(width: size, height: size)
            .padding(.bottom, rim)
            .accessibilityHidden(true)
    }
}

/// A ring that fills toward a goal, and shows a tick once it gets there.
struct DLRing: View {
    var progress: Double
    var size: CGFloat = 50
    var line: CGFloat = 7
    var showTick: Bool = true

    var body: some View {
        let track = Circle().inset(by: line / 2)
        ZStack {
            track.stroke(DL.sunken, lineWidth: line)
            track.trim(from: 0, to: min(1, max(0.001, progress)))
                .stroke(DL.gold, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if showTick && progress >= 1 {
                Image(systemName: "checkmark").font(.system(size: size * 0.34, weight: .black)).foregroundStyle(DL.ink)
            }
        }
        .frame(width: size, height: size)
    }
}

/// A horizontal meter, as in "12 of 100 today".
struct DLMeter: View {
    var value: Double
    var total: Double = 100
    var height: CGFloat = 6
    var fill: Color = DL.gold

    var body: some View {
        Capsule().fill(DL.sunken)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    // Any gold at all shows as at least a full dot.
                    Capsule().fill(fill)
                        .frame(width: value > 0 ? max(height, proxy.size.width * min(1, value / total)) : 0)
                }
            }
            .frame(height: height)
    }
}

/// The balance chip. On media it is frosted glass with white numerals. On a page it is a plain surface.
struct DLGoldChip: View {
    /// nil shows the player's balance and follows it as it changes.
    var balance: Int? = nil
    var onMedia: Bool = true
    @ObservedObject private var store = LiveStore.shared

    var body: some View {
        let amount = balance ?? store.s.balance
        HStack(spacing: 7) {
            DLCoin(size: 20)
            Text(groupedNumber(amount))
                .font(DL.display(22)).monospacedDigit()
                .foregroundStyle(onMedia ? Color.white : DL.ink)
                .contentTransition(.numericText(value: Double(amount)))
                .animation(.snappy(duration: 0.5), value: amount)
        }
        .padding(.leading, 8).padding(.trailing, 13)
        .frame(height: 38)
        .background {
            if onMedia { MediaGlass(shape: Capsule(), dim: 0.42) } else { Capsule().fill(DL.surface) }
        }
        .accessibilityLabel("\(amount) gold")
    }
}

/// An amount of gold with its sign, "+3" or "-5", for rows and results.
struct DLAmount: View {
    var amount: Int
    var size: CGFloat = 26

    var body: some View {
        Text(amount > 0 ? "+\(amount)" : "\(amount)")
            .font(DL.display(size)).monospacedDigit()
            .foregroundStyle(amount < 0 ? DL.ink2 : DL.ink)
    }
}

// MARK: Keys and buttons

enum DLKeyStyle { case gold, ink, neutral }

private extension DLKeyStyle {
    var face: Color {
        switch self {
        case .gold: DL.gold
        case .ink: DL.ink
        case .neutral: DL.surface
        }
    }

    var lip: Color {
        switch self {
        case .gold: DL.goldLip
        case .ink: Color(light: "000000", dark: "B9B5AC")
        case .neutral: DL.line
        }
    }

    var content: Color {
        switch self {
        case .gold: DL.onGold
        case .ink: DL.onInk
        case .neutral: DL.ink
        }
    }
}

/// A key you can feel: a face resting on a darker lip. When pressed the face travels down onto the lip.
/// Gold is kept for the one main action on a screen.
struct DLKey<Label: View>: View {
    var style: DLKeyStyle = .gold
    var radius: CGFloat = DL.keyRadius
    var depth: CGFloat = 6
    @ViewBuilder var label: () -> Label
    @Environment(\.dlPressed) private var pressed

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let travel = pressed ? depth : 0
        label()
            .foregroundStyle(style.content)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(style.face, in: shape)
            .offset(y: travel)
            .padding(.bottom, depth)
            .background(shape.fill(style.lip).padding(.top, travel))
            .animation(.easeOut(duration: 0.09), value: pressed)
            .preference(key: DLHasKey.self, value: true)
    }
}

/// The wide Play key on a game's page.
struct DLPlayKey: View {
    var title: String = "PLAY"
    var trailing: String? = nil
    var style: DLKeyStyle = .gold

    var body: some View {
        DLKey(style: style, depth: 6) {
            HStack(spacing: 10) {
                Image(systemName: "play.fill").font(.system(size: 20, weight: .black))
                Text(title).font(DL.display(32)).tracking(1)
                Spacer(minLength: 8)
                if let trailing {
                    Text(trailing).font(DL.label(11)).lineLimit(1).opacity(0.72)
                }
            }
            .padding(.horizontal, 22)
        }
        .frame(height: 70)
    }
}

/// The standard key with a text label. At most one gold key on a screen.
struct DLTextKey: View {
    var title: String
    var symbol: String? = nil
    var style: DLKeyStyle = .gold

    var body: some View {
        DLKey(style: style, radius: 20, depth: 5) {
            HStack(spacing: 8) {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 16, weight: .bold))
                }
                Text(title.uppercased()).font(DL.display(22)).tracking(0.8)
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            .padding(.horizontal, 8)
        }
        .frame(height: 58)
    }
}

/// The round Play key, the one gold control on a video.
struct DLRoundPlayKey: View {
    var size: CGFloat = 66
    var style: DLKeyStyle = .gold
    @Environment(\.dlPressed) private var pressed

    var body: some View {
        let lip = size * 0.09
        let travel = pressed ? lip : 0
        let isGold = style == .gold
        Image(systemName: "play.fill")
            .font(.system(size: size * 0.4, weight: .black))
            .foregroundStyle(DL.onGold)
            // a play triangle looks centred only when it sits a little to the right
            .offset(x: size * 0.03)
            .frame(width: size, height: size)
            .background(isGold ? DL.gold : Color.white, in: Circle())
            .offset(y: travel)
            .background(Circle().fill(isGold ? DL.goldLip : Color(hex: "B9B5AC")).offset(y: lip))
            .padding(.bottom, lip)
            .animation(.easeOut(duration: 0.09), value: pressed)
            .preference(key: DLHasKey.self, value: true)
            .accessibilityLabel("Play")
    }
}

/// A quiet round icon button on a page.
struct DLIconButton: View {
    var symbol: String
    var size: CGFloat = 40

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.38, weight: .semibold))
            .foregroundStyle(DL.ink)
            .frame(width: size, height: size)
            .background(DL.surface, in: Circle())
    }
}

/// A round icon button that floats on video or game art.
struct DLMediaButton: View {
    var symbol: String
    var size: CGFloat = 42

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.44, weight: .semibold))
            .foregroundStyle(.white)
            .contentTransition(.symbolEffect(.replace))
            .animation(.spring(duration: 0.35, bounce: 0), value: symbol)
            .frame(width: size, height: size)
            .background(MediaGlass(shape: Circle()))
    }
}

// MARK: Votes

/// Like and dislike side by side, with both counts always showing. A vote belongs to the game.
struct DLVotePill: View {
    let game: MockGame
    /// Kept for callers. The pill shows the player's own vote, which LiveStore holds.
    var voted: Bool? = nil
    var onMedia: Bool = false
    @ObservedObject private var store = LiveStore.shared

    var body: some View {
        HStack(spacing: 0) {
            half(like: true)
            Rectangle().fill(onMedia ? Color.white.opacity(0.3) : DL.line).frame(width: 1, height: 20)
            half(like: false)
        }
        .frame(height: 40)
        .background {
            if onMedia {
                MediaGlass(shape: Capsule())
            } else {
                Capsule().fill(DL.surface).overlay(Capsule().strokeBorder(DL.line))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(game.likes) likes, \(game.dislikes) dislikes")
    }

    /// One side of the pill. The whole half takes the tap, not only the icon and the count.
    private func half(like: Bool) -> some View {
        let chosen = store.vote(for: game.id) == like
        let colour: Color = onMedia ? .white : DL.ink
        let thumb = like ? "hand.thumbsup" : "hand.thumbsdown"
        return HStack(spacing: 6) {
            Image(systemName: chosen ? thumb + ".fill" : thumb)
                .font(.system(size: 14, weight: .semibold))
                .likeCelebration(like && chosen, tint: colour, burst: false)
            Text(like ? game.likes : game.dislikes)
                .font(.system(size: 14, weight: .semibold)).monospacedDigit()
        }
        .foregroundStyle(colour)
        .fixedSize()
        .padding(.leading, like ? 13 : 10).padding(.trailing, like ? 10 : 13)
        .frame(maxHeight: .infinity)
        .tap { store.setVote(game.id, like: like) }
    }
}

/// The approval line on a game's page: "94% liked it", with the split drawn as a bar.
struct DLApprovalBar: View {
    let game: MockGame

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(game.approval)%").font(DL.display(34)).foregroundStyle(DL.ink)
                Text("liked it").font(DL.text(15, .medium)).foregroundStyle(DL.ink2)
                Spacer()
                HStack(spacing: 12) {
                    count("hand.thumbsup.fill", game.likes)
                    count("hand.thumbsdown.fill", game.dislikes)
                }
                .font(DL.text(13, .semibold)).monospacedDigit().foregroundStyle(DL.ink2)
            }
            GeometryReader { proxy in
                HStack(spacing: 3) {
                    Capsule().fill(DL.ink).frame(width: proxy.size.width * CGFloat(game.approval) / 100)
                    Capsule().fill(DL.sunken)
                }
            }
            .frame(height: 8)
        }
    }

    private func count(_ symbol: String, _ votes: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
            Text(votes)
        }
    }
}

// MARK: Media

/// A rounded square of a game's art.
struct DLThumb: View {
    let game: MockGame
    var size: CGFloat = 48
    var radius: CGFloat? = nil

    var body: some View {
        ClipStill(game: game, showHUD: false, focusY: 0.35)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: radius ?? size * 0.28, style: .continuous))
    }
}

/// A portrait card of a game's clip, for grids and shelves.
struct DLClipCard: View {
    let game: MockGame
    var width: CGFloat = 150
    var height: CGFloat = 210
    var showTitle: Bool = true

    var body: some View {
        ClipStill(game: game, showHUD: false, focusY: 0.2)
            .overlay(alignment: .bottomLeading) {
                if showTitle { caption }
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(game.title.uppercased()).font(DL.display(20)).foregroundStyle(.white)
                .lineLimit(1).minimumScaleFactor(0.7)
            HStack(spacing: 4) {
                Image(systemName: "hand.thumbsup.fill").font(.system(size: 9, weight: .bold))
                Text("\(game.approval)%").font(DL.label(10))
            }
            .foregroundStyle(.white.opacity(0.85))
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        // the lower half darkens so the title reads on any art
        .background(LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom))
    }
}

/// A player's avatar: the first letter of the name on a colour picked by the name.
struct DLAvatar: View {
    var name: String
    var size: CGFloat = 36

    private static let palette = ["E4572E", "2E86AB", "6A4C93", "1B998B", "C2185B", "5C6B73"].map { Color(hex: $0) }

    var body: some View {
        let sum = name.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        Text(name.prefix(1).uppercased())
            .font(DL.display(size * 0.5)).foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Self.palette[sum % Self.palette.count], in: Circle())
    }
}

/// A small tag that sits on video or game art.
struct DLMediaTag: View {
    var text: String
    var symbol: String? = nil

    var body: some View {
        HStack(spacing: 5) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 11, weight: .bold))
            }
            Text(text).font(DL.text(13, .semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(MediaGlass(shape: Capsule(), dim: 0.38))
    }
}

// MARK: Layout

/// Where a screen says which tab it belongs to (0 Home, 1 Videos, 2 You). The app has one tab bar
/// and LiveRoot owns it, so a screen only hands over its content.
struct DLTabs<Content: View>: View {
    let selected: Int
    var tint: Color = DL.ink
    @ViewBuilder var content: () -> Content

    var body: some View { content() }
}

/// A scrolling page on the body colour, with the standard margins.
struct DLPage<Content: View>: View {
    var spacing: CGFloat = 14
    /// Space under the last row. Left at 120, the page ends 20 points below its last row.
    var bottomInset: CGFloat = 120
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: spacing, content: content)
                .padding(.horizontal, DL.margin)
                .padding(.top, 6)
                .padding(.bottom, bottomInset == 120 ? 20 : bottomInset)
        }
        .scrollIndicators(.hidden)
        .background(DL.body.ignoresSafeArea())
        // A strip of page colour behind the status bar, so rows never show under the clock.
        .safeAreaInset(edge: .top, spacing: 0) {
            Color.clear.frame(height: 0).background(DL.body.ignoresSafeArea(edges: .top))
        }
    }
}

/// A page's heading: an optional small kicker, a big title in capitals, and a control at the trailing edge.
struct DLHeader<Trailing: View>: View {
    var kicker: String? = nil
    var title: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                if let kicker { Text(kicker).dlLabel() }
                Text(title.uppercased()).font(DL.display(44)).foregroundStyle(DL.ink)
            }
            Spacer()
            trailing()
        }
    }
}

extension DLHeader where Trailing == EmptyView {
    init(kicker: String? = nil, title: String) {
        self.init(kicker: kicker, title: title) { EmptyView() }
    }
}

/// The top bar of a pushed screen: back, a centred title, and one optional button on the right.
struct DLNavBar: View {
    var title: String
    var trailingSymbol: String? = nil
    var showBack: Bool = true
    var trailingAction: (() -> Void)? = nil

    var body: some View {
        HStack {
            if showBack {
                DLIconButton(symbol: "chevron.left").goesBack().accessibilityLabel("Back")
            } else {
                placeholder
            }
            Spacer()
            Text(title).font(DL.text(17, .semibold)).foregroundStyle(DL.ink)
            Spacer()
            if let trailingSymbol {
                DLIconButton(symbol: trailingSymbol).tap { trailingAction?() }
            } else {
                placeholder
            }
        }
    }

    /// Holds a missing button's place, so the title stays centred.
    private var placeholder: some View { Color.clear.frame(width: 40, height: 40) }
}

extension EnvironmentValues {
    /// true inside the system sheet LiveRoot presents for a sheet route.
    @Entry var dlInSystemSheet: Bool = false
}

/// A sheet over the screen below. A sheet route is shown as an iOS sheet: it follows a swipe down
/// from anywhere on it, and closes on a tap outside. Shown any other way, it draws its own sheet
/// that closes the same ways.
struct DLSheet<Background: View, Content: View>: View {
    var height: CGFloat
    /// Kept for callers. The sheet covers whatever is already on screen.
    @ViewBuilder var background: () -> Background
    @ViewBuilder var content: () -> Content
    @State private var raised = false
    @State private var pull: CGFloat = 0
    @Environment(\.dlInSystemSheet) private var inSystemSheet

    var body: some View {
        if inSystemSheet {
            VStack(spacing: 0) {
                content()
                Spacer(minLength: 0)
            }
            .padding(.top, 22)
            .frame(maxWidth: .infinity)
            .presentationDetents([.height(height + 14)])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(38)
            .presentationBackground(DL.raised)
        } else {
            drawn
        }
    }

    private var drawn: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.45).ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { LiveNav.shared.back() }
            VStack(spacing: 0) {
                Capsule().fill(DL.ink3.opacity(0.5)).frame(width: 36, height: 5)
                    .padding(.top, 8).padding(.bottom, 10)
                content()
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(DL.raised, in: RoundedRectangle(cornerRadius: 38, style: .continuous))
            .padding([.horizontal, .bottom], 8)
            .offset(y: (raised ? 0 : height + 40) + pull)
            .simultaneousGesture(DragGesture(minimumDistance: 12)
                .onChanged { pull = max(0, $0.translation.height) }
                .onEnded { drag in
                    if drag.translation.height > 110 || drag.predictedEndTranslation.height > 260 {
                        LiveNav.shared.back()
                    } else {
                        withAnimation(.snappy(duration: 0.25)) { pull = 0 }
                    }
                })
        }
        .ignoresSafeArea(.container)
        .onAppear {
            withAnimation(.snappy(duration: 0.32)) { raised = true }
        }
    }
}

/// A list row: something leading, a title over an optional detail, something trailing.
struct DLRow<Leading: View, Trailing: View>: View {
    var title: String
    var detail: String? = nil
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 12) {
            leading()
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(DL.text(16, .semibold)).foregroundStyle(DL.ink).lineLimit(1)
                if let detail {
                    Text(detail).font(DL.text(13)).foregroundStyle(DL.ink2).lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.vertical, 10)
    }
}

/// The hairline between rows in a card. The inset lines it up with the row's text.
struct DLDivider: View {
    var inset: CGFloat = 60

    var body: some View {
        DL.line.frame(height: 1).padding(.leading, inset)
    }
}

/// What a page shows when it has nothing yet: a big icon, a title, a line and one key, on a card.
struct DLEmptyState: View {
    var symbol: String
    var title: String
    var detail: String? = nil
    var key: String
    var action: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 42, weight: .semibold)).foregroundStyle(DL.ink3)
                .padding(.bottom, 4)
            Text(title.uppercased()).font(DL.display(28)).foregroundStyle(DL.ink).multilineTextAlignment(.center)
            if let detail {
                Text(detail).font(DL.text(15)).foregroundStyle(DL.ink2).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            DLTextKey(title: key, style: .ink).tap(action).frame(maxWidth: 260).padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .dlCard(padding: 22)
    }
}

/// A small capsule tag in capitals.
struct DLTag: View {
    var text: String
    var symbol: String? = nil
    var filled: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 10, weight: .bold))
            }
            Text(text.uppercased()).font(DL.label(10.5))
        }
        .foregroundStyle(filled ? DL.onInk : DL.ink)
        .padding(.horizontal, 9)
        .frame(height: 24)
        .background(filled ? DL.ink : DL.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(filled ? Color.clear : DL.line))
    }
}

/// A stat tile: a small label over a big number.
struct DLStat: View {
    var label: String
    var value: String
    var detail: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).dlLabel(10.5)
            Text(value).font(DL.display(34)).foregroundStyle(DL.ink).lineLimit(1).minimumScaleFactor(0.6)
            if let detail {
                Text(detail).font(DL.text(12, .medium)).foregroundStyle(DL.ink2)
            }
        }
        .dlCard(padding: 14)
    }
}

// MARK: Brand

/// The mark: a D whose counter is a play triangle, on a gold key. `plain` leaves the key out.
struct DLMonogram: View {
    var size: CGFloat = 96
    var plain: Bool = false
    var ink: Color = DL.onGold
    var counter: Color = DL.gold

    var body: some View {
        Canvas { context, canvas in
            // The artwork is drawn on a unit square.
            let unit = CGAffineTransform(scaleX: canvas.width, y: canvas.width)
            context.fill(Self.letter.applying(unit), with: .color(ink))
            let triangle = Self.triangle.applying(unit)
            context.fill(triangle, with: .color(counter))
            // a stroke in the same colour softens the triangle's corners
            context.stroke(triangle, with: .color(counter), style: StrokeStyle(lineWidth: 0.04 * canvas.width, lineJoin: .round))
        }
        .frame(width: size, height: size)
        .background {
            if !plain { RoundedRectangle(cornerRadius: size * 0.22, style: .continuous).fill(DL.gold) }
        }
        .accessibilityLabel("DEGEN")
    }

    /// The D: a tall stem with tight corners on the left and a wide bowl on the right.
    fileprivate static let letter = Path { d in
        d.move(to: CGPoint(x: 0.277, y: 0.186))
        d.addLine(to: CGPoint(x: 0.527, y: 0.186))
        d.addQuadCurve(to: CGPoint(x: 0.771, y: 0.430), control: CGPoint(x: 0.771, y: 0.186))
        d.addLine(to: CGPoint(x: 0.771, y: 0.570))
        d.addQuadCurve(to: CGPoint(x: 0.527, y: 0.814), control: CGPoint(x: 0.771, y: 0.814))
        d.addLine(to: CGPoint(x: 0.277, y: 0.814))
        d.addQuadCurve(to: CGPoint(x: 0.244, y: 0.781), control: CGPoint(x: 0.244, y: 0.814))
        d.addLine(to: CGPoint(x: 0.244, y: 0.219))
        d.addQuadCurve(to: CGPoint(x: 0.277, y: 0.186), control: CGPoint(x: 0.244, y: 0.186))
        d.closeSubpath()
    }

    fileprivate static let triangle = Path { t in
        t.addLines([CGPoint(x: 0.420, y: 0.375), CGPoint(x: 0.625, y: 0.5), CGPoint(x: 0.420, y: 0.625)])
        t.closeSubpath()
    }
}

/// The logo: the D of the mark, as tall as the capitals and standing on their baseline, then the
/// rest of the name in the display face.
struct DLLogo: View {
    var height: CGFloat = 30

    var body: some View {
        let size = height * 1.16
        let cap = UIFont(name: "BigShoulders-Black", size: size)?.capHeight ?? size * 0.7
        // The D's box on the unit square the mark is drawn on.
        let box = CGRect(x: 0.244, y: 0.186, width: 0.527, height: 0.628)
        let scale = cap / box.height
        HStack(alignment: .firstTextBaseline, spacing: cap * 0.1) {
            Canvas { context, _ in
                let fit = CGAffineTransform(translationX: -box.minX, y: -box.minY).concatenating(CGAffineTransform(scaleX: scale, y: scale))
                context.fill(DLMonogram.letter.applying(fit), with: .color(DL.ink))
                let triangle = DLMonogram.triangle.applying(fit)
                context.fill(triangle, with: .color(DL.gold))
                context.stroke(triangle, with: .color(DL.gold), style: StrokeStyle(lineWidth: 0.04 * scale, lineJoin: .round))
            }
            .frame(width: box.width * scale, height: cap)
            .alignmentGuide(.firstTextBaseline) { $0[.bottom] }
            Text("EGEN").font(DL.display(size)).foregroundStyle(DL.ink)
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("DEGEN")
    }
}
