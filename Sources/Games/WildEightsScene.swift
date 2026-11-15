import SwiftUI

// Wild Eights, drawn.
//
// WildEightsFrame    everything on the table at one moment, in plain values.
// WildEightsPainter  paints a frame into a Canvas at any size, and knows where every card sits,
//                    so the playable game can test touches against the same geometry.
// WildEightsClip     builds a frame from a phase (0...1) for covers and the Videos feed.
// WildEightsScene    the view the app shows for a cover or a clip.

public struct WildEightsScene: View {
    public var phase: Double
    public var showHUD: Bool

    public init(phase: Double, showHUD: Bool) {
        self.phase = phase
        self.showHUD = showHUD
    }

    public var body: some View {
        Canvas(opaque: true, colorMode: .nonLinear, rendersAsynchronously: false) { context, size in
            if size.width <= 8 || size.height <= 8 { return }
            let frame = WildEightsClip.frame(at: phase, showHUD: showHUD)
            WildEightsPainter(size: size).draw(frame, &context)
        }
    }
}

// MARK: - Numbers

enum WildEightsMath {
    static func clamp(_ v: Double, _ lo: Double = 0, _ hi: Double = 1) -> Double {
        Swift.max(lo, Swift.min(hi, v))
    }

    static func lerp(_ from: Double, _ to: Double, _ k: Double) -> Double { from + (to - from) * k }

    static func smooth(_ edge0: Double, _ edge1: Double, _ v: Double) -> Double {
        let k = clamp((v - edge0) / (edge1 - edge0))
        return k * k * (3 - 2 * k)
    }

    static func easeOut(_ v: Double) -> Double {
        let rest = 1 - clamp(v)
        return 1 - rest * rest * rest
    }

    static func easeInOut(_ v: Double) -> Double {
        let k = clamp(v)
        return k < 0.5 ? 2 * k * k : 1 - 2 * (1 - k) * (1 - k)
    }

    /// A scale that overshoots a little and settles at 1. 1 at 0, back to 1 by 1.
    static func pop(_ v: Double) -> Double {
        let k = clamp(v)
        return 1 + 0.22 * exp(-3.5 * k) * sin(k * 7.5)
    }
}

/// SplitMix64. The clip and the round use different salts so they never share a sequence.
struct WildEightsRandom {
    static let clip: UInt64 = 0xA0761D6478BD642F
    static let round: UInt64 = 0xE7037ED1A0B428DB

    private var state: UInt64

    init(seed: UInt64, salt: UInt64 = WildEightsRandom.clip) {
        state = seed &* 0x9E3779B97F4A7C15 &+ salt
    }

    /// 0 ..< 1
    mutating func next() -> Double {
        state &+= 0x9E3779B97F4A7C15
        var v = state
        v = (v ^ (v >> 30)) &* 0xBF58476D1CE4E5B9
        v = (v ^ (v >> 27)) &* 0x94D049BB133111EB
        v ^= v >> 31
        return Double(v >> 11) / 9007199254740992.0
    }

    mutating func range(_ lo: Double, _ hi: Double) -> Double { lo + (hi - lo) * next() }

    mutating func int(_ bounds: ClosedRange<Int>) -> Int {
        bounds.lowerBound + Swift.min(bounds.count - 1, Int(next() * Double(bounds.count)))
    }

    mutating func chance(_ p: Double) -> Bool { next() < p }
}

// MARK: - Colour

struct WildEightsTint {
    var r: Double
    var g: Double
    var b: Double

    init(_ r: Double, _ g: Double, _ b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    init(hex: UInt32) {
        self.init(Double((hex >> 16) & 255) / 255, Double((hex >> 8) & 255) / 255, Double(hex & 255) / 255)
    }

    func mix(_ other: WildEightsTint, _ k: Double) -> WildEightsTint {
        WildEightsTint(r + (other.r - r) * k, g + (other.g - g) * k, b + (other.b - b) * k)
    }

    func color(_ alpha: Double = 1) -> Color {
        Color(red: r, green: g, blue: b, opacity: alpha)
    }
}

enum WildEightsPalette {
    static let card = WildEightsTint(hex: 0xF8F6F1)
    static let cardDim = WildEightsTint(hex: 0xC9CFC9)
    static let ink = WildEightsTint(hex: 0x151412)
    static let red = WildEightsTint(hex: 0xC93A2E)
    static let gold = WildEightsTint(hex: 0xF5B301)
    static let pill = WildEightsTint(hex: 0x0E2A22)
    static let sheet = WildEightsTint(hex: 0xF8F6F1)
    static let sheetText = WildEightsTint(hex: 0x8A8780)
    static let white = WildEightsTint(1, 1, 1)
    static let black = WildEightsTint(0, 0, 0)
    /// Seat colours for the other players, in the order they sit.
    static let seats = [WildEightsTint(hex: 0xF6A23A), WildEightsTint(hex: 0x6EC1F5), WildEightsTint(hex: 0xF58FB8)]
}

// MARK: - Cards

enum WildEightsSuit: Int, CaseIterable {
    case spades, hearts, diamonds, clubs

    var symbol: String {
        switch self {
        case .spades: return "\u{2660}"
        case .hearts: return "\u{2665}"
        case .diamonds: return "\u{2666}"
        case .clubs: return "\u{2663}"
        }
    }

    var isRed: Bool { self == .hearts || self == .diamonds }

    var name: String {
        switch self {
        case .spades: return "spades"
        case .hearts: return "hearts"
        case .diamonds: return "diamonds"
        case .clubs: return "clubs"
        }
    }
}

struct WildEightsCard: Equatable {
    /// 1 is the ace, 11 to 13 are jack, queen and king.
    var rank: Int
    var suit: WildEightsSuit

    var isEight: Bool { rank == 8 }

    var label: String {
        switch rank {
        case 1: return "A"
        case 11: return "J"
        case 12: return "Q"
        case 13: return "K"
        default: return "\(rank)"
        }
    }

    /// What the card scores when played, and what it costs when left in a hand at the end.
    var points: Int {
        if rank == 8 { return 20 }
        if rank >= 10 { return 10 }
        return rank
    }
}

// MARK: - A moment on the table

/// Where a card is, or is going. Hand slots carry the hand size the slot was laid out for.
enum WildEightsSpot {
    case deck
    case pile
    case hand(Int, Int)
    case seat(Int)
}

struct WildEightsSeat {
    var name: String
    var count: Int
    var active: Bool
    var color: WildEightsTint
}

struct WildEightsHandCard {
    var card: WildEightsCard
    /// 0 at rest, 1 fully lifted.
    var lift: Double
    var playable: Bool
    /// True while the card is still flying in from the deck: the flight draws it instead.
    var hidden: Bool
    var dragX: Double = 0
    var dragY: Double = 0
}

struct WildEightsFlight {
    var card: WildEightsCard
    var from: WildEightsSpot
    var to: WildEightsSpot
    /// 0 at the start, 1 landed.
    var progress: Double
    /// False: the back shows all the way. True from a seat: it turns over on the way.
    var faceUp: Bool
}

struct WildEightsNote {
    var text: String
    var age: Double
    /// Where it starts, as a share of the stage.
    var x: Double
    var y: Double
}

struct WildEightsFrame {
    var seats: [WildEightsSeat] = []
    /// The discard pile, oldest first. Only the last three are drawn.
    var pile: [WildEightsCard] = []
    var deckCount: Int = 0
    /// True once the player has drawn this turn: a second tap on the deck passes.
    var deckPass: Bool = false
    var hand: [WildEightsHandCard] = []
    var flights: [WildEightsFlight] = []
    /// The suit an eight asked for, shown as a badge on the pile.
    var wildSuit: WildEightsSuit? = nil
    var pill: String = ""
    /// True when the pill is about the player's own turn.
    var pillHot: Bool = false
    var score: Int = 0
    var showHUD: Bool = true
    /// 0 hidden, 1 fully up.
    var sheet: Double = 0
    var sheetCard: WildEightsCard? = nil
    var sheetPressed: WildEightsSuit? = nil
    var notes: [WildEightsNote] = []
    var praise: String? = nil
    var praiseAge: Double = 0
    /// Darkens the table at the end of the round.
    var dim: Double = 0
    var banner: String? = nil
    var bannerAge: Double = 0
    /// Scenery clock, for pulses.
    var time: Double = 0
}

// MARK: - Pictures

/// The pictures in Resources/GameArt, resolved once for each frame.
struct WildEightsArt {
    let felt: GraphicsContext.ResolvedImage
    let back: GraphicsContext.ResolvedImage
    let face: GraphicsContext.ResolvedImage
    /// The face every eight wears.
    let wild: GraphicsContext.ResolvedImage
    /// In WildEightsSuit order.
    let suits: [GraphicsContext.ResolvedImage]

    init(_ ctx: GraphicsContext) {
        felt = ctx.resolve(Image("wild-eights-felt"))
        back = ctx.resolve(Image("wild-eights-card-back"))
        face = ctx.resolve(Image("wild-eights-card-face"))
        wild = ctx.resolve(Image("wild-eights-card-eight"))
        suits = ["spade", "heart", "diamond", "club"].map { ctx.resolve(Image("wild-eights-suit-\($0)")) }
    }

    func suit(_ suit: WildEightsSuit) -> GraphicsContext.ResolvedImage { suits[suit.rawValue] }
}

// MARK: - Painter

struct WildEightsPainter {
    typealias M = WildEightsMath
    typealias P = WildEightsPalette

    static let stage = CGSize(width: 402, height: 874)
    static let noteLength = 1.1
    static let praiseLength = 1.3
    static let flightLift = 36.0

    let W: Double
    let H: Double
    let u: Double
    let cardW: Double
    let cardH: Double
    let handW: Double
    let handH: Double
    let deckCenter: CGPoint
    let pileCenter: CGPoint
    let scoreY: Double
    let seatY: Double
    let pillY: Double
    /// The bottom edge of a hand card at rest.
    let handBase: Double
    let sheetHeight: Double

    init(size: CGSize) {
        W = Double(size.width)
        H = Double(size.height)
        u = W / 402
        cardW = 88 * u
        cardH = 124 * u
        handW = 82 * u
        handH = 116 * u
        scoreY = Double(GameLayout.statusBarHeight + GameLayout.topBand) / 2
        seatY = Double(GameLayout.topBand) + 46 * u
        let pileY = Swift.max(H * 0.43, seatY + 70 * u + 62 * u)
        deckCenter = CGPoint(x: W / 2 - 52 * u, y: pileY)
        pileCenter = CGPoint(x: W / 2 + 52 * u, y: pileY)
        pillY = pileY + 62 * u + 46 * u
        handBase = H - Double(GameLayout.bottomInset) - 6 * u
        sheetHeight = 444 * u + Double(GameLayout.bottomInset)
    }

    // MARK: Geometry

    static let fanAngle = 13.5      // degrees at the ends of a full fan
    static let fanArc = 22.0        // how far the ends of a full fan sit below the middle

    func handSpacing(_ n: Int) -> Double {
        if n <= 1 { return 0 }
        return Swift.min(60 * u, (W - 70 * u - handW) / Double(n - 1))
    }

    /// Where a card sits across the fan: 0 in the middle, 1 at the end of a full fan of seven or more.
    /// A small hand keeps the curve of a full one, a big hand never curves further.
    private func fanShare(_ i: Int, _ n: Int) -> Double {
        let off = Double(i) - Double(n - 1) / 2
        return off / Swift.max(Double(n - 1) / 2, 3)
    }

    /// Degrees.
    func handAngle(_ i: Int, _ n: Int) -> Double {
        fanShare(i, n) * Self.fanAngle
    }

    /// How far the lowest corner of the fan's outer cards sits below a flat row.
    private func fanDrop(_ n: Int) -> Double {
        let t = abs(fanShare(0, n))
        let a = t * Self.fanAngle * Double.pi / 180
        return t * t * Self.fanArc * u + handW / 2 * sin(a) + handH / 2 * (cos(a) - 1)
    }

    func handCenter(_ i: Int, _ n: Int, lift: Double) -> CGPoint {
        let off = Double(i) - Double(n - 1) / 2
        let x = W / 2 + off * handSpacing(n)
        let t = fanShare(i, n)
        // The whole fan sits high enough that its lowest corner stays above the line.
        let y = handBase - handH / 2 - Swift.max(0, fanDrop(n)) + t * t * Self.fanArc * u - lift * Self.flightLift * u
        return CGPoint(x: x, y: y)
    }

    func seatCenter(_ k: Int, _ m: Int) -> CGPoint {
        let off = Double(k) - Double(Swift.max(m, 1) - 1) / 2
        return CGPoint(x: W / 2 + off * 112 * u, y: seatY)
    }

    var deckRect: CGRect {
        CGRect(x: deckCenter.x - cardW / 2 - 10 * u, y: deckCenter.y - cardH / 2 - 10 * u,
               width: cardW + 20 * u, height: cardH + 20 * u)
    }

    /// The hand card under a point, topmost first. Lifts are the frame's, one per card.
    func handIndex(at p: CGPoint, lifts: [Double]) -> Int? {
        let n = lifts.count
        var i = n - 1
        while i >= 0 {
            let c = handCenter(i, n, lift: lifts[i])
            let a = -handAngle(i, n) * Double.pi / 180
            let dx = Double(p.x - c.x)
            let dy = Double(p.y - c.y)
            let lx = dx * cos(a) - dy * sin(a)
            let ly = dx * sin(a) + dy * cos(a)
            if abs(lx) <= handW / 2 + 4 * u, abs(ly) <= handH / 2 + 4 * u { return i }
            i -= 1
        }
        return nil
    }

    /// Where the sheet's top edge sits for a given openness.
    func sheetTop(_ openness: Double) -> Double {
        H - sheetHeight * M.easeOut(openness)
    }

    /// The four suit buttons, in WildEightsSuit order, as a two by two grid.
    func suitButtonRect(_ k: Int, top: Double) -> CGRect {
        let gap = 16 * u
        let w = (W - 40 * u - gap) / 2
        let h = 118 * u
        let x = 20 * u + Double(k % 2) * (w + gap)
        let y = top + 168 * u + Double(k / 2) * (h + gap)
        return CGRect(x: x, y: y, width: w, height: h)
    }

    /// The centre, angle (degrees) and scale a card has at a spot.
    func place(_ spot: WildEightsSpot) -> (center: CGPoint, angle: Double, scale: Double) {
        switch spot {
        case .deck: return (deckCenter, 0, 1)
        case .pile: return (pileCenter, 0, 1)
        case .hand(let i, let n): return (handCenter(i, n, lift: 0), handAngle(i, n), handW / cardW)
        case .seat(let k): return (seatCenter(k, 3), 0, 0.42)
        }
    }

    // MARK: Drawing

    func draw(_ frame: WildEightsFrame, _ ctx: inout GraphicsContext) {
        let art = WildEightsArt(ctx)
        drawFelt(&ctx, art)
        drawSeats(&ctx, frame)
        drawDeck(&ctx, art, count: frame.deckCount, pass: frame.deckPass)
        drawPile(&ctx, art, frame)
        drawPill(&ctx, frame)
        drawHand(&ctx, art, frame)
        for flight in frame.flights { drawFlight(&ctx, art, flight, seats: frame.seats.count) }
        if frame.showHUD {
            drawScore(&ctx, frame)
            for note in frame.notes { drawNote(&ctx, note) }
        }
        if let praise = frame.praise { drawPraise(&ctx, praise, age: frame.praiseAge) }
        if frame.dim > 0.001 {
            ctx.fill(Path(CGRect(x: 0, y: 0, width: W, height: H)), with: .color(P.black.color(0.42 * frame.dim)))
        }
        if let banner = frame.banner { drawBanner(&ctx, banner, age: frame.bannerAge) }
        if frame.sheet > 0.001 { drawSheet(&ctx, art, frame) }
    }

    private func drawFelt(_ ctx: inout GraphicsContext, _ art: WildEightsArt) {
        let fill = Swift.max(W / Double(art.felt.size.width), H / Double(art.felt.size.height))
        let feltW = Double(art.felt.size.width) * fill
        let feltH = Double(art.felt.size.height) * fill
        ctx.draw(art.felt, in: CGRect(x: (W - feltW) / 2, y: (H - feltH) / 2, width: feltW, height: feltH))
        // A soft lighter patch where the cards go, like a lamp over the table.
        ctx.fill(Path(ellipseIn: CGRect(x: W / 2 - 190 * u, y: pileCenter.y - 170 * u, width: 380 * u, height: 340 * u)),
                 with: .radialGradient(Gradient(colors: [P.white.color(0.07), P.white.color(0)]),
                                       center: pileCenter, startRadius: 0, endRadius: 190 * u))
    }

    private func drawScore(_ ctx: inout GraphicsContext, _ frame: WildEightsFrame) {
        let number = Text("\(frame.score)").font(.system(size: 30 * u, weight: .heavy, design: .rounded))
        ctx.draw(number.foregroundColor(P.black.color(0.35)), at: CGPoint(x: W / 2, y: scoreY + 2 * u), anchor: .center)
        ctx.draw(number.foregroundColor(.white), at: CGPoint(x: W / 2, y: scoreY), anchor: .center)
    }

    private func drawSeats(_ ctx: inout GraphicsContext, _ frame: WildEightsFrame) {
        let m = frame.seats.count
        let r = 26 * u
        for (k, seat) in frame.seats.enumerated() {
            let c = seatCenter(k, m)
            if seat.active {
                let pulse = 0.5 + 0.5 * sin(frame.time * 4)
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - r - 9 * u, y: c.y - r - 9 * u, width: 2 * r + 18 * u, height: 2 * r + 18 * u)),
                         with: .color(P.gold.color(0.22 + 0.14 * pulse)))
                ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r - 3 * u, y: c.y - r - 3 * u, width: 2 * r + 6 * u, height: 2 * r + 6 * u)),
                           with: .color(P.gold.color(0.95)), lineWidth: 3 * u)
            }
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r + 2 * u, width: 2 * r, height: 2 * r)), with: .color(P.black.color(0.25)))
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(seat.color.color()))
            let letter = String(seat.name.prefix(1)).uppercased()
            ctx.draw(Text(letter).font(.system(size: 24 * u, weight: .heavy, design: .rounded)).foregroundColor(P.ink.color()),
                     at: CGPoint(x: c.x, y: c.y), anchor: .center)
            let words: String
            if seat.count == 0 { words = "out" } else if seat.count == 1 { words = "1 card" } else { words = "\(seat.count) cards" }
            let label = Text(words).font(.system(size: 15 * u, weight: .bold, design: .rounded))
            ctx.draw(label.foregroundColor(P.black.color(0.35)), at: CGPoint(x: c.x, y: c.y + r + 15 * u), anchor: .center)
            ctx.draw(label.foregroundColor(P.white.color(seat.active ? 1 : 0.85)), at: CGPoint(x: c.x, y: c.y + r + 13.5 * u), anchor: .center)
        }
    }

    private func drawDeck(_ ctx: inout GraphicsContext, _ art: WildEightsArt, count: Int, pass: Bool) {
        if count <= 0 {
            let rect = CGRect(x: deckCenter.x - cardW / 2, y: deckCenter.y - cardH / 2, width: cardW, height: cardH)
            let dash: [CGFloat] = [CGFloat(6 * u), CGFloat(6 * u)]
            ctx.stroke(Path(roundedRect: rect, cornerRadius: 10 * u, style: .continuous),
                       with: .color(P.white.color(0.25)), style: StrokeStyle(lineWidth: CGFloat(2 * u), dash: dash))
            if pass { drawPassTag(&ctx) }
            return
        }
        let layers = Swift.min(3, 1 + count / 12)
        var k = layers - 1
        while k >= 0 {
            let c = CGPoint(x: deckCenter.x - Double(k) * 2.5 * u, y: deckCenter.y - Double(k) * 2.5 * u)
            drawBack(&ctx, art, center: c, w: cardW, h: cardH, angle: 0, alpha: 1, squeeze: 1)
            k -= 1
        }
        if pass { drawPassTag(&ctx) }
    }

    /// A tag on the deck once the player has drawn: tapping it again passes the turn.
    private func drawPassTag(_ ctx: inout GraphicsContext) {
        let rect = CGRect(x: deckCenter.x - 32 * u, y: deckCenter.y - 16 * u, width: 64 * u, height: 32 * u)
        ctx.fill(Path(roundedRect: rect.offsetBy(dx: 0, dy: 2 * u), cornerRadius: 16 * u, style: .continuous), with: .color(P.black.color(0.3)))
        ctx.fill(Path(roundedRect: rect, cornerRadius: 16 * u, style: .continuous), with: .color(P.card.color()))
        ctx.draw(Text("Pass").font(.system(size: 16 * u, weight: .heavy, design: .rounded)).foregroundColor(P.ink.color()),
                 at: CGPoint(x: rect.midX, y: rect.midY), anchor: .center)
    }

    private func drawPile(_ ctx: inout GraphicsContext, _ art: WildEightsArt, _ frame: WildEightsFrame) {
        let shown = frame.pile.suffix(3)
        let first = frame.pile.count - shown.count
        for (j, card) in shown.enumerated() {
            let order = first + j
            // Earlier cards lie a little askew under the top one, each at its own fixed tilt.
            let tilt = order == frame.pile.count - 1 ? 0 : Double((order * 7) % 11) - 5
            drawFace(&ctx, art, card, center: pileCenter, w: cardW, h: cardH, angle: tilt, alpha: 1, dim: false)
        }
        guard let suit = frame.wildSuit else { return }
        let r = 17 * u
        let c = CGPoint(x: pileCenter.x + cardW / 2 - 2 * u, y: pileCenter.y - cardH / 2 + 2 * u)
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r + 2 * u, width: 2 * r, height: 2 * r)), with: .color(P.black.color(0.3)))
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(P.gold.color()))
        ctx.draw(art.suit(suit), in: CGRect(x: c.x - 10 * u, y: c.y - 10 * u, width: 20 * u, height: 20 * u))
    }

    private func drawPill(_ ctx: inout GraphicsContext, _ frame: WildEightsFrame) {
        if frame.pill.isEmpty { return }
        let text = Text(frame.pill).font(.system(size: 17 * u, weight: .bold, design: .rounded))
        let resolved = ctx.resolve(text.foregroundColor(.white))
        let size = resolved.measure(in: CGSize(width: W - 40 * u, height: 60 * u))
        let w = Double(size.width) + 44 * u
        let h = Double(size.height) + 22 * u
        let rect = CGRect(x: W / 2 - w / 2, y: pillY - h / 2, width: w, height: h)
        ctx.fill(Path(roundedRect: rect, cornerRadius: h / 2, style: .continuous), with: .color(P.pill.color(frame.pillHot ? 0.92 : 0.7)))
        if frame.pillHot {
            ctx.stroke(Path(roundedRect: rect, cornerRadius: h / 2, style: .continuous), with: .color(P.gold.color(0.75)), lineWidth: 1.5 * u)
        }
        ctx.draw(resolved, at: CGPoint(x: W / 2, y: pillY), anchor: .center)
    }

    private func drawHand(_ ctx: inout GraphicsContext, _ art: WildEightsArt, _ frame: WildEightsFrame) {
        let n = frame.hand.count
        for (i, slot) in frame.hand.enumerated() where !slot.hidden {
            var c = handCenter(i, n, lift: slot.lift)
            c.x += slot.dragX
            c.y += slot.dragY
            let dragging = slot.dragX != 0 || slot.dragY != 0
            let angle = dragging ? handAngle(i, n) * 0.3 : handAngle(i, n)
            let dim = !slot.playable && frame.pillHot
            drawFace(&ctx, art, slot.card, center: c, w: handW, h: handH, angle: angle, alpha: dim ? 0.55 : 1, dim: dim)
        }
    }

    private func drawFlight(_ ctx: inout GraphicsContext, _ art: WildEightsArt, _ flight: WildEightsFlight, seats: Int) {
        let from = placeIn(flight.from, seats: seats)
        let to = placeIn(flight.to, seats: seats)
        let k = M.easeInOut(flight.progress)
        let lift = sin(k * Double.pi) * Self.flightLift * u
        let c = CGPoint(x: M.lerp(Double(from.center.x), Double(to.center.x), k),
                        y: M.lerp(Double(from.center.y), Double(to.center.y), k) - lift)
        let angle = M.lerp(from.angle, to.angle, k)
        let scale = M.lerp(from.scale, to.scale, k)
        let w = cardW * scale
        let h = cardH * scale
        if !flight.faceUp {
            drawBack(&ctx, art, center: c, w: w, h: h, angle: angle, alpha: 1, squeeze: 1)
            return
        }
        // Turns over on the way: the back narrows to nothing, then the face opens.
        let turn = cos(k * Double.pi)
        if turn > 0 {
            drawBack(&ctx, art, center: c, w: w, h: h, angle: angle, alpha: 1, squeeze: Swift.max(0.02, turn))
        } else {
            drawFace(&ctx, art, flight.card, center: c, w: w, h: h, angle: angle, alpha: 1, dim: false, squeeze: Swift.max(0.02, -turn))
        }
    }

    private func placeIn(_ spot: WildEightsSpot, seats: Int) -> (center: CGPoint, angle: Double, scale: Double) {
        if case .seat(let k) = spot { return (seatCenter(k, seats), 0, 0.42) }
        return place(spot)
    }

    private func drawNote(_ ctx: inout GraphicsContext, _ note: WildEightsNote) {
        let life = M.clamp(note.age / Self.noteLength)
        let alpha = M.easeOut(M.clamp(note.age / 0.12)) * (1 - M.smooth(0.55, 1, life))
        if alpha <= 0.01 { return }
        let size = 24 * u * M.pop(note.age / 0.5)
        let text = Text(note.text).font(.system(size: size, weight: .heavy, design: .rounded))
        let p = CGPoint(x: note.x * W, y: note.y * H - M.easeOut(life) * 54 * u)
        ctx.draw(text.foregroundColor(P.black.color(0.4 * alpha)), at: CGPoint(x: p.x, y: p.y + 2 * u), anchor: .center)
        ctx.draw(text.foregroundColor(P.gold.color(alpha)), at: p, anchor: .center)
    }

    private func drawPraise(_ ctx: inout GraphicsContext, _ words: String, age: Double) {
        let life = M.clamp(age / Self.praiseLength)
        let arrive = M.easeOut(M.clamp(age / 0.14))
        let alpha = arrive * (1 - M.smooth(0.65, 1, life))
        if alpha <= 0.01 { return }
        let size = 40 * u * (0.7 + 0.3 * arrive) * M.pop(age / 0.6)
        let text = Text(words).font(.system(size: size, weight: .black, design: .rounded)).italic()
        let p = CGPoint(x: W / 2, y: pileCenter.y - cardH / 2 - 34 * u - life * 16 * u)
        ctx.draw(text.foregroundColor(P.black.color(0.45 * alpha)), at: CGPoint(x: p.x, y: p.y + 3 * u), anchor: .center)
        ctx.draw(text.foregroundColor(P.white.color(alpha)), at: p, anchor: .center)
    }

    private func drawBanner(_ ctx: inout GraphicsContext, _ words: String, age: Double) {
        let arrive = M.easeOut(M.clamp(age / 0.3))
        if arrive <= 0.01 { return }
        let size = 34 * u * (0.8 + 0.2 * arrive) * M.pop(age / 0.7)
        let text = Text(words).font(.system(size: size, weight: .heavy, design: .rounded))
        let p = CGPoint(x: W / 2, y: pillY + 2 * u)
        ctx.draw(text.foregroundColor(P.black.color(0.5 * arrive)), at: CGPoint(x: p.x, y: p.y + 3 * u), anchor: .center)
        ctx.draw(text.foregroundColor(P.white.color(arrive)), at: p, anchor: .center)
    }

    private func drawSheet(_ ctx: inout GraphicsContext, _ art: WildEightsArt, _ frame: WildEightsFrame) {
        let openness = M.clamp(frame.sheet)
        ctx.fill(Path(CGRect(x: 0, y: 0, width: W, height: H)), with: .color(P.black.color(0.45 * openness)))
        let top = sheetTop(openness)
        let panel = CGRect(x: 0, y: top, width: W, height: sheetHeight + 60 * u)
        ctx.fill(Path(roundedRect: panel, cornerRadius: 30 * u, style: .continuous), with: .color(P.sheet.color()))
        ctx.fill(Path(roundedRect: CGRect(x: W / 2 - 24 * u, y: top + 12 * u, width: 48 * u, height: 5 * u), cornerRadius: 2.5 * u),
                 with: .color(P.sheetText.color(0.45)))

        if let card = frame.sheetCard {
            drawFace(&ctx, art, card, center: CGPoint(x: 56 * u, y: top + 98 * u), w: 60 * u, h: 84 * u, angle: 0, alpha: 1, dim: false)
        }
        ctx.draw(Text("WILD EIGHT").font(.system(size: 32 * u, weight: .heavy, design: .rounded)).foregroundColor(P.ink.color()),
                 at: CGPoint(x: 104 * u, y: top + 84 * u), anchor: .leading)
        ctx.draw(Text("Pick the next suit").font(.system(size: 17 * u, weight: .medium, design: .rounded)).foregroundColor(P.sheetText.color()),
                 at: CGPoint(x: 104 * u, y: top + 116 * u), anchor: .leading)

        for suit in WildEightsSuit.allCases {
            let rect = suitButtonRect(suit.rawValue, top: top)
            let pressed = frame.sheetPressed == suit
            let shape = Path(roundedRect: rect, cornerRadius: 20 * u, style: .continuous)
            ctx.fill(Path(roundedRect: rect.offsetBy(dx: 0, dy: 4 * u), cornerRadius: 20 * u, style: .continuous), with: .color(P.black.color(0.08)))
            ctx.fill(shape, with: .color(pressed ? P.gold.color() : P.white.color()))
            ctx.draw(art.suit(suit), in: CGRect(x: rect.midX - 27 * u, y: rect.midY - 29 * u, width: 54 * u, height: 54 * u))
        }
    }

    // MARK: One card

    func drawFace(_ ctx: inout GraphicsContext, _ art: WildEightsArt, _ card: WildEightsCard, center: CGPoint, w: Double, h: Double,
                  angle: Double, alpha: Double, dim: Bool, squeeze: Double = 1) {
        ctx.drawLayer { layer in
            layer.opacity = alpha
            layer.translateBy(x: center.x, y: center.y)
            if angle != 0 { layer.rotate(by: Angle.degrees(angle)) }
            if squeeze != 1 { layer.scaleBy(x: squeeze, y: 1) }
            let rect = CGRect(x: -w / 2, y: -h / 2, width: w, height: h)
            let radius = w * 0.12
            layer.fill(Path(roundedRect: rect.offsetBy(dx: 0, dy: 3 * u), cornerRadius: radius, style: .continuous),
                       with: .color(P.black.color(0.28)))
            layer.draw(card.isEight ? art.wild : art.face, in: rect)
            if dim {
                layer.fill(Path(roundedRect: rect, cornerRadius: radius, style: .continuous), with: .color(P.cardDim.color(0.55)))
            }
            let ink = card.suit.isRed ? P.red : P.ink
            let paint = dim ? ink.mix(P.cardDim, 0.35).color() : ink.color()
            let corner = CGPoint(x: -w / 2 + w * 0.16, y: -h / 2 + h * 0.15)
            layer.draw(Text(card.label).font(.system(size: w * 0.28, weight: .heavy, design: .rounded)).foregroundColor(paint),
                       at: corner, anchor: .center)
            var pip = layer
            if dim { pip.opacity = 0.65 }
            let suit = art.suit(card.suit)
            pip.draw(suit, in: CGRect(x: corner.x - w * 0.08, y: corner.y + h * 0.17 - w * 0.08, width: w * 0.16, height: w * 0.16))
            pip.draw(suit, in: CGRect(x: w * 0.2 - w * 0.16, y: h * 0.24 - w * 0.16, width: w * 0.32, height: w * 0.32))
        }
    }

    func drawBack(_ ctx: inout GraphicsContext, _ art: WildEightsArt, center: CGPoint, w: Double, h: Double, angle: Double, alpha: Double, squeeze: Double) {
        ctx.drawLayer { layer in
            layer.opacity = alpha
            layer.translateBy(x: center.x, y: center.y)
            if angle != 0 { layer.rotate(by: Angle.degrees(angle)) }
            if squeeze != 1 { layer.scaleBy(x: squeeze, y: 1) }
            let rect = CGRect(x: -w / 2, y: -h / 2, width: w, height: h)
            let radius = w * 0.12
            layer.fill(Path(roundedRect: rect.offsetBy(dx: 0, dy: 3 * u), cornerRadius: radius, style: .continuous),
                       with: .color(P.black.color(0.28)))
            layer.draw(art.back, in: rect)
        }
    }
}

// MARK: - The clip

/// A scripted round for covers and the Videos feed: the deal, a few turns, an eight and going out.
/// Every card that lands stays on the pile, and every play is one the rules allow.
enum WildEightsClip {
    typealias M = WildEightsMath

    private static func card(_ rank: Int, _ suit: WildEightsSuit) -> WildEightsCard {
        WildEightsCard(rank: rank, suit: suit)
    }

    static let names = ["kaz", "devon.plays", "noor.runs"]
    static let hand: [WildEightsCard] = [
        card(8, .spades), card(5, .hearts), card(13, .clubs), card(5, .clubs), card(2, .diamonds), card(11, .spades), card(9, .hearts),
    ]
    static let first = card(7, .hearts)
    /// Eight turns, ours first: 5 of hearts, then the 9 of hearts on the fifth turn.
    static let opening: [WildEightsCard] = [
        card(5, .hearts), card(5, .spades), card(9, .spades), card(9, .clubs),
        card(9, .hearts), card(3, .hearts), card(3, .clubs), card(12, .clubs),
    ]
    /// Four more turns, ours first: the king of clubs.
    static let middle: [WildEightsCard] = [card(13, .clubs), card(13, .diamonds), card(10, .diamonds), card(10, .spades)]
    /// Played between the middle and the end, off camera. Ours are the jack of spades and the 5 of clubs.
    static let between: [WildEightsCard] = [
        card(11, .spades), card(11, .clubs), card(7, .clubs), card(5, .clubs), card(5, .diamonds), card(6, .diamonds), card(6, .spades),
    ]
    static let eight = card(8, .spades)
    static let last = card(2, .diamonds)
    /// What the other hands are worth when we go out.
    static let sweep = 52

    static func frame(at phase: Double, showHUD: Bool) -> WildEightsFrame {
        let p = M.clamp(phase)
        var f = WildEightsFrame()
        f.showHUD = showHUD
        f.time = p * 30
        var seats: [WildEightsSeat] = []
        for (k, name) in names.enumerated() {
            seats.append(WildEightsSeat(name: name, count: 7, active: false, color: WildEightsPalette.seats[k]))
        }
        f.seats = seats
        f.deckCount = 23

        if p < 0.1 {
            // The deal: cards fly from the deck round the table, then the first card turns up.
            let dealt = p / 0.1 * 29
            let whole = Int(dealt)
            for k in 0..<3 { f.seats[k].count = Swift.min(7, (whole + 2 - k) / 4) }
            let mine = Swift.min(7, (whole + 3) / 4)
            var cards: [WildEightsHandCard] = []
            for i in 0..<mine { cards.append(WildEightsHandCard(card: hand[i], lift: 0, playable: true, hidden: false)) }
            f.hand = cards
            f.deckCount = 52 - whole
            let who = whole % 4
            if whole < 28 {
                let to: WildEightsSpot = who == 0 ? .hand(mine, mine + 1) : .seat(who - 1)
                f.flights = [WildEightsFlight(card: hand[Swift.min(6, mine)], from: .deck, to: to,
                                              progress: dealt - Double(whole), faceUp: false)]
            } else {
                f.flights = [WildEightsFlight(card: first, from: .deck, to: .pile, progress: dealt - Double(whole), faceUp: true)]
            }
            f.pill = "Dealing"
            return f
        }

        if p < 0.45 {
            let k = (p - 0.1) / 0.35 * 8
            let t = Swift.min(7, Int(k))
            var mine = hand
            var score = 0
            for j in 0..<t {
                let seat = j % 4
                if seat == 0 {
                    if let at = mine.firstIndex(of: opening[j]) { mine.remove(at: at) }
                    score += 2
                } else {
                    f.seats[seat - 1].count -= 1
                }
            }
            turn(&f, pile: [first] + Array(opening.prefix(t)), hand: mine, play: opening[t], seat: t % 4,
                 within: k - Double(t), score: score)
            return f
        }

        let afterOpening: [WildEightsCard] = [first] + opening
        if p < 0.75 {
            let k = (p - 0.45) / 0.3 * 4
            let t = Swift.min(3, Int(k))
            var mine = [hand[0], hand[2], hand[3], hand[4], hand[5]]
            var score = 4
            for s in 0..<3 { f.seats[s].count = 5 }
            for j in 0..<t {
                if j == 0 {
                    if let at = mine.firstIndex(of: middle[0]) { mine.remove(at: at) }
                    score += 2
                } else {
                    f.seats[j - 1].count -= 1
                }
            }
            turn(&f, pile: afterOpening + Array(middle.prefix(t)), hand: mine, play: middle[t], seat: t,
                 within: k - Double(t), score: score)
            return f
        }

        // The end: the eight, the suit picker, one more turn round the table and the last card.
        let before: [WildEightsCard] = afterOpening + middle + between
        f.seats[0].count = 2
        f.seats[1].count = 2
        f.seats[2].count = 4
        f.deckCount = 22
        if p < 0.95 {
            let k = (p - 0.75) / 0.2
            if k < 0.25 {
                turn(&f, pile: before, hand: [eight, last], play: eight, seat: 0, within: k / 0.25, score: 10)
                return f
            }
            f.pile = before + [eight]
            f.score = 15
            f.notes = [WildEightsNote(text: "+5", age: (k - 0.25) * 4, x: 0.63, y: 0.36)]
            f.praise = "Nice"
            f.praiseAge = (k - 0.25) * 4
            if k < 0.45 {
                f.hand = [WildEightsHandCard(card: last, lift: 0, playable: false, hidden: false)]
                f.sheet = M.smooth(0.25, 0.3, k) * (1 - M.smooth(0.4, 0.45, k))
                f.sheetCard = eight
                f.sheetPressed = k > 0.36 ? .diamonds : nil
                f.pill = "Pick a suit"
                if k >= 0.4 { f.wildSuit = .diamonds }
                return f
            }
            f.wildSuit = .diamonds
            if k < 0.75 {
                f.seats[0].active = true
                f.pill = "\(names[0]) is thinking"
                f.hand = [WildEightsHandCard(card: last, lift: 0, playable: true, hidden: false)]
                if k >= 0.52, k < 0.66 {
                    f.flights = [WildEightsFlight(card: last, from: .deck, to: .seat(0), progress: (k - 0.52) / 0.14, faceUp: false)]
                }
                if k >= 0.66 {
                    f.seats[0].count = 3
                    f.deckCount = 21
                }
                return f
            }
            f.seats[0].count = 3
            f.deckCount = 21
            f.pillHot = true
            f.pill = "Your turn. Match \(WildEightsSuit.diamonds.symbol)"
            if k < 0.88 {
                f.hand = [WildEightsHandCard(card: last, lift: M.smooth(0.77, 0.85, k), playable: true, hidden: false)]
            } else {
                f.flights = [WildEightsFlight(card: last, from: .hand(0, 1), to: .pile, progress: (k - 0.88) / 0.12, faceUp: true)]
            }
            return f
        }

        // Out. The last card is down, the other hands count for us and the table rests.
        let k = (p - 0.95) / 0.05
        f.seats[0].count = 3
        f.deckCount = 21
        f.pile = before + [eight, last]
        f.score = 17 + Int(M.easeOut(k * 1.6) * Double(50 + sweep))
        f.notes = [WildEightsNote(text: "+\(50 + sweep)", age: k * 1.0, x: 0.5, y: 0.3)]
        f.dim = M.smooth(0, 0.5, k)
        f.banner = "You went out"
        f.bannerAge = k * 2
        f.praise = "Great"
        f.praiseAge = k * 1.2
        return f
    }

    /// One turn: ours lifts a card and plays it, another player's thinks and plays one.
    private static func turn(_ f: inout WildEightsFrame, pile: [WildEightsCard], hand mine: [WildEightsCard],
                             play: WildEightsCard, seat: Int, within: Double, score: Int) {
        f.pile = pile
        f.score = score
        let top = pile.last ?? first
        if seat != 0 {
            f.seats[seat - 1].active = true
            f.pill = "\(names[seat - 1]) is thinking"
            var cards: [WildEightsHandCard] = []
            for c in mine { cards.append(WildEightsHandCard(card: c, lift: 0, playable: false, hidden: false)) }
            f.hand = cards
            if within > 0.55 {
                f.flights = [WildEightsFlight(card: play, from: .seat(seat - 1), to: .pile,
                                              progress: M.clamp((within - 0.55) / 0.4), faceUp: true)]
            }
            return
        }
        f.pillHot = true
        f.pill = "Your turn. Match \(top.suit.symbol) or \(top.label)"
        let index = mine.firstIndex(of: play) ?? 0
        if within >= 0.7 {
            // It leaves the hand and lands on the pile.
            var rest = mine
            if index < rest.count { rest.remove(at: index) }
            var cards: [WildEightsHandCard] = []
            for c in rest { cards.append(WildEightsHandCard(card: c, lift: 0, playable: false, hidden: false)) }
            f.hand = cards
            f.pillHot = false
            f.pill = "Nice match"
            f.flights = [WildEightsFlight(card: play, from: .hand(index, mine.count), to: .pile,
                                          progress: M.clamp((within - 0.7) / 0.28), faceUp: true)]
            f.score = score + (play.isEight ? 5 : 2)
            f.notes = [WildEightsNote(text: play.isEight ? "+5" : "+2", age: (within - 0.7) * 3, x: 0.63, y: 0.36)]
            return
        }
        var cards: [WildEightsHandCard] = []
        for (i, c) in mine.enumerated() {
            let playable = c.isEight || c.suit == top.suit || c.rank == top.rank
            let lift = i == index ? M.smooth(0.15, 0.45, within) : (playable ? 0.22 : 0)
            cards.append(WildEightsHandCard(card: c, lift: lift, playable: playable, hidden: false))
        }
        f.hand = cards
    }
}
