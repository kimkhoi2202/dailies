import SwiftUI

// Short Stack: no-limit Texas Hold'em at a table of six, one short sitting.
//
// The picture is painted into a Canvas by ShortStackPainter from a ShortStackFrame: what is on
// the table at one moment. The clip in the video feed builds a frame from a phase (0...1) and a
// fixed hand; the playable game keeps one frame up to date as its hand goes on.
// No assets, any frame size.

public struct ShortStackScene: View {
    public var phase: Double
    public var showHUD: Bool

    public init(phase: Double, showHUD: Bool) {
        self.phase = phase
        self.showHUD = showHUD
    }

    public var body: some View {
        Canvas(opaque: true, colorMode: .nonLinear, rendersAsynchronously: false) { context, size in
            if size.width <= 8 || size.height <= 8 { return }
            let painter = ShortStackPainter(size: size)
            painter.drawStill(&context)
            painter.drawLive(&context, ShortStackClip.frame(at: phase), showHUD: showHUD)
        }
    }
}

// MARK: - Numbers

enum ShortStackMath {
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

    /// 1240 as "1,240".
    static func grouped(_ value: Int) -> String {
        let digits = String(Swift.max(0, value))
        if digits.count <= 3 { return digits }
        var out = ""
        for (k, digit) in digits.enumerated() {
            if k > 0, (digits.count - k) % 3 == 0 { out.append(",") }
            out.append(digit)
        }
        return out
    }
}

/// SplitMix64. The deck, the other seats and the scripted player each have a salt of their own,
/// so none of them ever shares a sequence.
struct ShortStackRandom {
    static let deck: UInt64 = 0xA24BAED4963EE407
    static let others: UInt64 = 0x9FB21C651E98DF25
    static let pilot: UInt64 = 0xD6E8FEB86659FD93

    private var state: UInt64

    init(seed: UInt64, salt: UInt64) {
        state = seed &* 0x9E3779B97F4A7C15 &+ salt
    }

    mutating func bits() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var v = state
        v = (v ^ (v >> 30)) &* 0xBF58476D1CE4E5B9
        v = (v ^ (v >> 27)) &* 0x94D049BB133111EB
        return v ^ (v >> 31)
    }

    /// 0 ..< 1
    mutating func next() -> Double { Double(bits() >> 11) / 9007199254740992.0 }

    mutating func range(_ lo: Double, _ hi: Double) -> Double { lo + (hi - lo) * next() }

    /// 0 ..< count
    mutating func below(_ count: Int) -> Int { Int(bits() % UInt64(Swift.max(1, count))) }
}

// MARK: - Cards

struct ShortStackCard: Equatable {
    /// 2...14, the ace high.
    var rank: Int
    /// 0 spades, 1 hearts, 2 diamonds, 3 clubs.
    var suit: Int

    static let labels = ["", "", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K", "A"]

    var label: String { Self.labels[rank] }

    static func fresh() -> [ShortStackCard] {
        var deck: [ShortStackCard] = []
        deck.reserveCapacity(52)
        for suit in 0..<4 {
            for rank in 2...14 { deck.append(ShortStackCard(rank: rank, suit: suit)) }
        }
        return deck
    }
}

/// Ranks the best five cards out of five, six or seven. A higher score is a better hand, equal
/// scores split. The score is the kind of hand, then the ranks that decide it, four bits each.
enum ShortStackRank {
    static func score(_ cards: [ShortStackCard]) -> Int {
        var ranks = 0
        var counts: UInt64 = 0
        var s0 = 0, s1 = 0, s2 = 0, s3 = 0
        for card in cards {
            let bit = 1 << card.rank
            ranks |= bit
            counts &+= UInt64(1) << UInt64(4 * card.rank)
            switch card.suit {
            case 0: s0 |= bit
            case 1: s1 |= bit
            case 2: s2 |= bit
            default: s3 |= bit
            }
        }
        var flush = 0
        if s0.nonzeroBitCount >= 5 { flush = s0 }
        else if s1.nonzeroBitCount >= 5 { flush = s1 }
        else if s2.nonzeroBitCount >= 5 { flush = s2 }
        else if s3.nonzeroBitCount >= 5 { flush = s3 }

        if flush != 0 {
            let high = straightHigh(flush)
            if high != 0 { return 8 << 20 | high << 16 }
        }

        var four = 0, threeA = 0, threeB = 0, pairA = 0, pairB = 0
        var rank = 14
        while rank >= 2 {
            switch Int((counts >> UInt64(4 * rank)) & 15) {
            case 4: four = rank
            case 3: if threeA == 0 { threeA = rank } else if threeB == 0 { threeB = rank }
            case 2: if pairA == 0 { pairA = rank } else if pairB == 0 { pairB = rank }
            default: break
            }
            rank -= 1
        }

        if four != 0 { return 7 << 20 | four << 16 | top(ranks & ~(1 << four), 1) << 12 }
        if threeA != 0, Swift.max(threeB, pairA) != 0 { return 6 << 20 | threeA << 16 | Swift.max(threeB, pairA) << 12 }
        if flush != 0 { return 5 << 20 | top(flush, 5) }
        let high = straightHigh(ranks)
        if high != 0 { return 4 << 20 | high << 16 }
        if threeA != 0 { return 3 << 20 | threeA << 16 | top(ranks & ~(1 << threeA), 2) << 8 }
        if pairB != 0 {
            return 2 << 20 | pairA << 16 | pairB << 12 | top(ranks & ~(1 << pairA) & ~(1 << pairB), 1) << 8
        }
        if pairA != 0 { return 1 << 20 | pairA << 16 | top(ranks & ~(1 << pairA), 3) << 4 }
        return top(ranks, 5)
    }

    /// The top card of the best straight in a set of ranks, 0 when there is none. The ace also
    /// plays low.
    private static func straightHigh(_ mask: Int) -> Int {
        let low = mask | ((mask >> 14) & 1) << 1
        var high = 14
        while high >= 5 {
            let run = 0b11111 << (high - 4)
            if low & run == run { return high }
            high -= 1
        }
        return 0
    }

    /// The highest ranks in a set, packed four bits each, highest first.
    private static func top(_ mask: Int, _ count: Int) -> Int {
        var packed = 0
        var taken = 0
        var rank = 14
        while rank >= 2, taken < count {
            if mask & (1 << rank) != 0 {
                packed = packed << 4 | rank
                taken += 1
            }
            rank -= 1
        }
        return packed << (4 * (count - taken))
    }

    private static let plural = ["", "", "twos", "threes", "fours", "fives", "sixes", "sevens", "eights", "nines",
                                 "tens", "jacks", "queens", "kings", "aces"]
    private static let single = ["", "", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine",
                                 "Ten", "Jack", "Queen", "King", "Ace"]

    /// "Two pair", "Pair of kings", "Ace high".
    static func name(_ score: Int) -> String {
        let lead = (score >> 16) & 15
        switch score >> 20 {
        case 8: return lead == 14 ? "Royal flush" : "Straight flush"
        case 7: return "Four of a kind"
        case 6: return "Full house"
        case 5: return "Flush"
        case 4: return "Straight"
        case 3: return "Three of a kind"
        case 2: return "Two pair"
        case 1: return "Pair of \(plural[lead])"
        default: return "\(single[lead]) high"
        }
    }

    /// The same hand inside a sentence: "a pair of kings", "two pair", "a flush".
    static func phrase(_ score: Int) -> String {
        let words = name(score)
        let kind = score >> 20
        let lowered = words.prefix(1).lowercased() + words.dropFirst()
        return kind == 2 || kind == 3 || kind == 7 || kind == 0 ? lowered : "a " + lowered
    }
}

// MARK: - What is on screen

enum ShortStackKey: Equatable {
    case fold, call, raise
    /// One of the raise sizes, left to right.
    case size(Int)
}

struct ShortStackSeatView {
    var name = ""
    /// The chips shown on the plate. It ticks toward the real count.
    var chips = 0
    /// Chips in front of the seat this round.
    var stake = 0
    /// 0: the chips are still at the seat. 1: they are at their spot on the felt.
    var stakeSlide = 1.0
    var cards: [ShortStackCard] = []
    /// 0 no cards yet, 1 the first has arrived, 2 both.
    var dealt = 0.0
    /// 0 backs, 1 faces.
    var face = 0.0
    /// 0 in the hand, 1 the cards are gone.
    var folded = 0.0
    var out = false
    /// The share of this seat's turn that is left. Below 0 when it is not its turn.
    var turn = -1.0
    var label = ""
    var labelAge = 100.0
    var button = false
    /// The hand this seat holds, once it may be shown.
    var hand = ""
    /// 1 as the pot arrives, fading to 0.
    var glow = 0.0
}

struct ShortStackAward {
    var seat: Int
    var amount: Int
}

struct ShortStackControls {
    /// It is the player's turn.
    var live = false
    var call = "Check"
    var callSub = ""
    var canRaise = false
    /// 0 the raise sizes are away, 1 they are out.
    var menu = 0.0
    var sizeTitles: [String] = []
    var sizeAmounts: [Int] = []
    /// The share of the player's turn that is left.
    var clock = 1.0
    var pressed: ShortStackKey?
    var pressedAge = 100.0
}

struct ShortStackFrame {
    var seats: [ShortStackSeatView] = []
    var board: [ShortStackCard] = []
    /// How far each board card has come, 0...1: it slides out, then turns over.
    var shown = [0.0, 0.0, 0.0, 0.0, 0.0]
    /// Chips already in the middle.
    var pot = 0
    /// The middle and every seat's chips in front together.
    var total = 0
    /// 0...1 while the chips in front slide to the middle.
    var gather = 0.0
    var awards: [ShortStackAward] = []
    /// Seconds since the pot left for its taker. Below 0 when it has not.
    var awardAge = -1.0
    var message = ""
    var messageAge = 100.0
    var messageLife = 2.0
    var hand = 1
    var hands = 8
    var small = 10
    var big = 20
    var controls = ShortStackControls()
    var clock = 0.0
    /// 0...1 as the sitting's last card comes up.
    var fade = 0.0
    var endTitle = ""
    var endScore = ""
}

// MARK: - Layout

/// Where everything sits on the 402 x 874 stage, and how the stage fits a view.
struct ShortStackLayout {
    /// The seats at the table. Seat 0 is the player, at the bottom; the rest go clockwise.
    static let seatCount = 6

    static let seats: [(x: Double, y: Double)] = [(201, 640), (56, 478), (56, 250), (201, 150), (346, 250), (346, 478)]
    static let stakes: [(x: Double, y: Double)] = [(201, 470), (140, 432), (132, 290), (201, 232), (270, 290), (262, 432)]
    static let pot = (x: 201.0, y: 326.0)
    static let pile = (x: 201.0, y: 298.0)
    static let boardY = 382.0
    static let awardSlide = 0.6

    static func boardX(_ k: Int) -> Double { 89 + 56 * Double(k) }

    /// The seats on the right keep their cards and numbers on their left.
    static func mirrored(_ seat: Int) -> Bool { seats[seat].x > 300 }

    /// The middle of a seat's badge, where chips come from and go to.
    static func heart(_ seat: Int) -> (x: Double, y: Double) {
        seat == 0 ? seats[0] : (seats[seat].x, seats[seat].y - 4)
    }

    /// Where one of a seat's two cards rests.
    static func hole(_ seat: Int, _ card: Int, face: Double) -> (x: Double, y: Double, angle: Double, w: Double) {
        if seat == 0 { return (201 + (card == 0 ? -35 : 35), 566, card == 0 ? -4 : 4, 66) }
        let at = seats[seat]
        let gap = 20 + 8 * face
        let lean = card == 0 ? -6.0 : 6.0
        let w = 34 + 6 * face
        if mirrored(seat) { return (at.x - 40 - gap * Double(1 - card), at.y - 12 + 4 * Double(card), lean, w) }
        return (at.x + 40 + gap * Double(card), at.y - 12 + 4 * Double(card), lean, w)
    }

    /// A key as centre and size.
    static func keyBox(_ key: ShortStackKey, sizes: Int) -> (x: Double, y: Double, w: Double, h: Double) {
        switch key {
        case .fold: return (74.33, 790, 116.67, 72)
        case .call: return (201, 790, 116.67, 72)
        case .raise: return (327.67, 790, 116.67, 72)
        case .size(let k):
            let count = Double(Swift.max(1, sizes))
            let first = 201 - (count * 85 + (count - 1) * 10) / 2 + 42.5
            return (first + 95 * Double(k), 712, 85, 52)
        }
    }

    let W: Double
    let H: Double
    let u: Double
    let ox: Double
    let oy: Double

    init(size: CGSize) {
        W = Double(size.width)
        H = Double(size.height)
        u = Swift.min(W / 402, H / 874)
        ox = (W - 402 * u) / 2
        oy = (H - 874 * u) / 2
    }

    func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: ox + x * u, y: oy + y * u) }

    /// The key under a touch. sizes is the number of raise sizes on show, 0 when they are away.
    func key(at point: CGPoint, sizes: Int) -> ShortStackKey? {
        let x = (Double(point.x) - ox) / u
        let y = (Double(point.y) - oy) / u
        func inside(_ key: ShortStackKey) -> Bool {
            let box = Self.keyBox(key, sizes: sizes)
            return abs(x - box.x) <= box.w / 2 + 4 && abs(y - box.y) <= box.h / 2 + 4
        }
        for k in 0..<sizes where inside(.size(k)) { return .size(k) }
        if inside(.fold) { return .fold }
        if inside(.call) { return .call }
        if inside(.raise) { return .raise }
        return nil
    }
}

// MARK: - Colour

enum ShortStackInk {
    static func hex(_ v: UInt32, _ alpha: Double = 1) -> Color {
        Color(.sRGB, red: Double((v >> 16) & 255) / 255, green: Double((v >> 8) & 255) / 255,
              blue: Double(v & 255) / 255, opacity: alpha)
    }

    static let roomTop = hex(0x0B1422)
    static let roomBottom = hex(0x05080F)
    static let railTop = hex(0x2A3446)
    static let railBottom = hex(0x141A26)
    static let feltLight = hex(0x13907A)
    static let feltDark = hex(0x0A5A4E)
    static let gold = hex(0xF6C453)
    static let teal = hex(0x1FC4A9)
    static let slate = hex(0x394257)
    static let paper = hex(0xFDFBF4)
    static let ink = hex(0x1B2231)
    static let red = hex(0xDA3B4B)
    static let back = hex(0x2947A3)
    static let plate = hex(0x0A0F18, 0.74)
    static let chips = [hex(0xE5484D), hex(0x3E8BFF), hex(0x2FBF71), hex(0xF6C453)]
    static let seats = [hex(0xF6C453), hex(0x7C5CFF), hex(0xFF6B57), hex(0x4DA3FF), hex(0xFF9F43), hex(0xFF7AB6)]
}

// MARK: - Painter

struct ShortStackPainter {
    typealias M = ShortStackMath
    typealias Ink = ShortStackInk
    typealias Lay = ShortStackLayout

    let lay: ShortStackLayout
    let u: Double

    init(size: CGSize) {
        lay = ShortStackLayout(size: size)
        u = lay.u
    }

    // MARK: Shapes

    private func pt(_ x: Double, _ y: Double) -> CGPoint { lay.pt(x, y) }

    /// A rectangle from its centre and size, in stage units.
    private func box(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> CGRect {
        CGRect(x: lay.ox + (x - w / 2) * u, y: lay.oy + (y - h / 2) * u, width: w * u, height: h * u)
    }

    private func pill(_ x: Double, _ y: Double, _ w: Double, _ h: Double, radius: Double? = nil) -> Path {
        Path(roundedRect: box(x, y, w, h), cornerRadius: (radius ?? h / 2) * u, style: .continuous)
    }

    private func disc(_ x: Double, _ y: Double, _ r: Double) -> Path { Path(ellipseIn: box(x, y, 2 * r, 2 * r)) }

    private func words(_ ctx: inout GraphicsContext, _ string: String, _ x: Double, _ y: Double, size: Double,
                       weight: Font.Weight = .bold, color: Color, anchor: UnitPoint = .center) {
        ctx.draw(Text(string).font(.system(size: size * u, weight: weight, design: .rounded)).foregroundColor(color),
                 at: pt(x, y), anchor: anchor)
    }

    /// A suit as a shape around a centre, r from the centre to its top.
    static func suit(_ suit: Int, _ cx: Double, _ cy: Double, _ r: Double) -> Path {
        var path = Path()
        func at(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: cx + x * r, y: cy + y * r) }
        switch suit {
        case 0:
            path.move(to: at(0, -1))
            path.addCurve(to: at(-0.95, 0.25), control1: at(-0.3, -0.55), control2: at(-0.95, -0.2))
            path.addCurve(to: at(0, 0.45), control1: at(-0.95, 0.9), control2: at(-0.2, 0.85))
            path.addCurve(to: at(0.95, 0.25), control1: at(0.2, 0.85), control2: at(0.95, 0.9))
            path.addCurve(to: at(0, -1), control1: at(0.95, -0.2), control2: at(0.3, -0.55))
            path.closeSubpath()
            path.addLines([at(0, 0.2), at(-0.34, 1), at(0.34, 1)])
            path.closeSubpath()
        case 1:
            path.move(to: at(0, 0.95))
            path.addCurve(to: at(-0.98, -0.25), control1: at(-0.35, 0.6), control2: at(-0.98, 0.2))
            path.addCurve(to: at(0, -0.5), control1: at(-0.98, -1), control2: at(-0.15, -1))
            path.addCurve(to: at(0.98, -0.25), control1: at(0.15, -1), control2: at(0.98, -1))
            path.addCurve(to: at(0, 0.95), control1: at(0.98, 0.2), control2: at(0.35, 0.6))
            path.closeSubpath()
        case 2:
            path.addLines([at(0, -1), at(0.74, 0), at(0, 1), at(-0.74, 0)])
            path.closeSubpath()
        default:
            let lobe = 0.44 * r
            for centre in [at(0, -0.5), at(-0.5, 0.14), at(0.5, 0.14)] {
                path.addEllipse(in: CGRect(x: centre.x - lobe, y: centre.y - lobe, width: 2 * lobe, height: 2 * lobe))
            }
            path.addEllipse(in: CGRect(x: cx - 0.3 * r, y: cy - 0.35 * r, width: 0.6 * r, height: 0.6 * r))
            path.addLines([at(0, 0.1), at(-0.34, 1), at(0.34, 1)])
            path.closeSubpath()
        }
        return path
    }

    /// One card. face 0 is the back, 1 the front, and it turns over on the way.
    func drawCard(_ ctx: inout GraphicsContext, _ card: ShortStackCard, x: Double, y: Double, w: Double,
                  angle: Double = 0, face: Double, alpha: Double = 1) {
        if alpha <= 0.01 { return }
        let cw = w * u
        let ch = cw * 1.4
        let turn = face < 0.5 ? 1 - 2 * face : 2 * face - 1
        var c = ctx
        c.opacity = alpha
        c.translateBy(x: lay.ox + x * u, y: lay.oy + y * u)
        if angle != 0 { c.rotate(by: .degrees(angle)) }
        c.scaleBy(x: Swift.max(0.04, turn), y: 1 + 0.05 * (1 - turn))
        let rect = CGRect(x: -cw / 2, y: -ch / 2, width: cw, height: ch)
        let shape = Path(roundedRect: rect, cornerRadius: cw * 0.13, style: .continuous)
        c.fill(shape.offsetBy(dx: 0, dy: 1.6 * u), with: .color(.black.opacity(0.3)))
        if face < 0.5 {
            c.fill(shape, with: .color(Ink.back))
            let inner = Path(roundedRect: rect.insetBy(dx: cw * 0.1, dy: cw * 0.1), cornerRadius: cw * 0.07, style: .continuous)
            c.stroke(inner, with: .color(.white.opacity(0.5)), lineWidth: Swift.max(0.8, cw * 0.035))
            c.fill(Self.suit(2, 0, 0, cw * 0.17), with: .color(.white.opacity(0.5)))
            return
        }
        c.fill(shape, with: .color(Ink.paper))
        let tint = card.suit == 1 || card.suit == 2 ? Ink.red : Ink.ink
        let rank = Text(card.label)
            .font(.system(size: cw * (card.rank == 10 ? 0.4 : 0.46), weight: .heavy, design: .rounded))
            .foregroundColor(tint)
        c.draw(rank, at: CGPoint(x: -cw * 0.2, y: -ch * 0.26), anchor: .center)
        c.fill(Self.suit(card.suit, -cw * 0.2, ch * 0.03, cw * 0.115), with: .color(tint))
        c.fill(Self.suit(card.suit, cw * 0.15, ch * 0.2, cw * 0.25), with: .color(tint))
    }

    private func drawChip(_ ctx: inout GraphicsContext, _ at: CGPoint, r: Double, tint: Color) {
        let rect = CGRect(x: Double(at.x) - r, y: Double(at.y) - r, width: 2 * r, height: 2 * r)
        ctx.fill(Path(ellipseIn: rect.offsetBy(dx: 0, dy: r * 0.24)), with: .color(.black.opacity(0.32)))
        ctx.fill(Path(ellipseIn: rect), with: .color(tint))
        let marks: [CGFloat] = [r * 0.5, r * 0.56]
        ctx.stroke(Path(ellipseIn: rect.insetBy(dx: r * 0.15, dy: r * 0.15)), with: .color(.white.opacity(0.9)),
                   style: StrokeStyle(lineWidth: r * 0.26, dash: marks))
        ctx.fill(Path(ellipseIn: rect.insetBy(dx: r * 0.44, dy: r * 0.44)), with: .color(.white.opacity(0.2)))
    }

    /// A small pile for an amount: more chips for more.
    private func drawPile(_ ctx: inout GraphicsContext, x: Double, y: Double, amount: Int, alpha: Double = 1) {
        if alpha <= 0.01 || amount <= 0 { return }
        let count = amount >= 800 ? 4 : amount >= 240 ? 3 : amount >= 60 ? 2 : 1
        var c = ctx
        c.opacity = alpha
        for k in 0..<count {
            drawChip(&c, pt(x, y - 3.4 * Double(k)), r: 9 * u, tint: Ink.chips[(k + amount / 20) % 4])
        }
    }

    // MARK: The room and the table, which never change

    func drawStill(_ ctx: inout GraphicsContext) {
        let whole = CGRect(x: 0, y: 0, width: lay.W, height: lay.H)
        ctx.fill(Path(whole), with: .linearGradient(Gradient(colors: [Ink.roomTop, Ink.roomBottom]),
                                                    startPoint: .zero, endPoint: CGPoint(x: 0, y: lay.H)))
        let rail = pill(201, 394, 384, 564, radius: 176)
        ctx.fill(rail.offsetBy(dx: 0, dy: 7 * u), with: .color(.black.opacity(0.45)))
        ctx.fill(rail, with: .linearGradient(Gradient(colors: [Ink.railTop, Ink.railBottom]),
                                             startPoint: pt(0, 112), endPoint: pt(0, 676)))
        ctx.stroke(pill(201, 394, 381, 561, radius: 175), with: .color(.white.opacity(0.1)), lineWidth: 1.2 * u)
        let felt = pill(201, 394, 356, 536, radius: 162)
        ctx.fill(felt, with: .radialGradient(Gradient(colors: [Ink.feltLight, Ink.feltDark]),
                                             center: pt(201, 370), startRadius: 0, endRadius: 330 * u))
        ctx.stroke(felt, with: .color(.black.opacity(0.35)), lineWidth: 2 * u)
        ctx.stroke(pill(201, 394, 326, 506, radius: 148), with: .color(.white.opacity(0.08)), lineWidth: 1.4 * u)
        for k in 0..<5 {
            ctx.stroke(pill(Lay.boardX(k), Lay.boardY, 50, 70, radius: 6.5), with: .color(.white.opacity(0.1)),
                       lineWidth: 1.2 * u)
        }
    }

    // MARK: Everything that moves

    func drawLive(_ ctx: inout GraphicsContext, _ f: ShortStackFrame, showHUD: Bool) {
        if showHUD { drawHeader(&ctx, f) }
        drawBoard(&ctx, f)
        for k in f.seats.indices.reversed() { drawSeat(&ctx, f, k) }
        drawStakes(&ctx, f)
        drawPot(&ctx, f)
        drawAwards(&ctx, f)
        if showHUD { drawControls(&ctx, f) }
        if f.fade > 0.01 { drawEnding(&ctx, f) }
    }

    private func drawHeader(_ ctx: inout GraphicsContext, _ f: ShortStackFrame) {
        words(&ctx, "Hand \(f.hand) of \(f.hands)", 201, 79, size: 14.5, weight: .heavy, color: .white.opacity(0.94))
        words(&ctx, "Blinds \(f.small) / \(f.big)", 201, 97, size: 11.5, weight: .semibold, color: .white.opacity(0.62))
    }

    private func drawBoard(_ ctx: inout GraphicsContext, _ f: ShortStackFrame) {
        for k in f.board.indices where k < 5 && f.shown[k] > 0 {
            let a = f.shown[k]
            let slide = M.easeOut(a / 0.55)
            drawCard(&ctx, f.board[k], x: M.lerp(Lay.pile.x, Lay.boardX(k), slide), y: M.lerp(Lay.pile.y, Lay.boardY, slide),
                     w: 50, face: M.smooth(0.4, 1, a), alpha: Swift.min(1, a * 8))
        }
    }

    private func drawHole(_ ctx: inout GraphicsContext, _ seat: ShortStackSeatView, _ k: Int) {
        if seat.cards.count < 2 || seat.dealt <= 0 || seat.folded >= 1 { return }
        for card in 0..<2 {
            let arrive = M.clamp(seat.dealt - Double(card))
            if arrive <= 0 { continue }
            let home = Lay.hole(k, card, face: seat.face)
            let slide = M.easeOut(arrive)
            var x = M.lerp(Lay.pile.x, home.x, slide)
            var y = M.lerp(Lay.pile.y, home.y, slide)
            if seat.folded > 0 {
                x = M.lerp(x, Lay.pile.x, 0.45 * seat.folded)
                y = M.lerp(y, Lay.pile.y, 0.45 * seat.folded)
            }
            drawCard(&ctx, seat.cards[card], x: x, y: y, w: home.w, angle: home.angle * slide, face: seat.face,
                     alpha: Swift.min(1, arrive * 6) * (1 - seat.folded))
        }
    }

    private func drawLabel(_ ctx: inout GraphicsContext, _ seat: ShortStackSeatView, x: Double, y: Double) {
        if seat.label.isEmpty { return }
        // A fold stays up for the rest of the hand; anything else goes after a moment.
        let stays = seat.folded > 0
        let alpha = M.smooth(0, 0.12, seat.labelAge) * (stays ? 1 : 1 - M.smooth(1.5, 1.9, seat.labelAge))
        if alpha <= 0.01 { return }
        let pop = 1 + 0.18 * exp(-10 * seat.labelAge)
        let w = (18 + 7.4 * Double(seat.label.count)) * pop
        var c = ctx
        c.opacity = alpha
        c.fill(pill(x, y, w, 23 * pop), with: .color(Ink.hex(0x0A0F18, 0.9)))
        c.stroke(pill(x, y, w, 23 * pop), with: .color(.white.opacity(0.28)), lineWidth: 1 * u)
        words(&c, seat.label, x, y, size: 12.5 * pop, weight: .heavy, color: .white)
    }

    private func drawDealer(_ ctx: inout GraphicsContext, x: Double, y: Double) {
        ctx.fill(disc(x, y + 1, 9.5), with: .color(.black.opacity(0.35)))
        ctx.fill(disc(x, y, 9.5), with: .color(.white))
        words(&ctx, "D", x, y, size: 11.5, weight: .heavy, color: Ink.ink)
    }

    private func drawSeat(_ ctx: inout GraphicsContext, _ f: ShortStackFrame, _ k: Int) {
        let seat = f.seats[k]
        let at = Lay.seats[k]
        let quiet = seat.out ? 0.35 : 1 - 0.45 * seat.folded
        let isTurn = seat.turn >= 0
        drawHole(&ctx, seat, k)

        if k == 0 {
            let plate = pill(at.x, at.y, 198, 38, radius: 13)
            ctx.fill(plate, with: .color(Ink.plate))
            ctx.stroke(plate, with: .color(isTurn ? Ink.gold : Color.white.opacity(0.14 + 0.6 * seat.glow)),
                       lineWidth: (isTurn ? 2 : 1.2) * u)
            words(&ctx, String(seat.name.prefix(13)), at.x - 86, at.y, size: 14, weight: .semibold,
                  color: .white.opacity(0.86 * quiet), anchor: .leading)
            words(&ctx, seat.out ? "Out" : M.grouped(seat.chips), at.x + 86, at.y, size: 18, weight: .heavy,
                  color: Ink.gold.opacity(quiet), anchor: .trailing)
            if !seat.hand.isEmpty, seat.folded < 0.5 {
                let w = 20 + 7.2 * Double(seat.hand.count)
                ctx.fill(pill(at.x, 607, w, 22), with: .color(Ink.hex(0x0A0F18, 0.88)))
                words(&ctx, seat.hand, at.x, 607, size: 12.5, weight: .heavy, color: Ink.gold)
            }
            if seat.button { drawDealer(&ctx, x: at.x - 112, y: at.y) }
            drawLabel(&ctx, seat, x: 332, y: 574)
            return
        }

        let plate = pill(at.x, at.y + 38, 100, 38, radius: 12)
        ctx.fill(plate, with: .color(Ink.plate))
        ctx.stroke(plate, with: .color(isTurn ? Ink.gold : Color.white.opacity(0.14 + 0.6 * seat.glow)),
                   lineWidth: (isTurn ? 1.8 : 1) * u)
        if seat.hand.isEmpty {
            words(&ctx, String(seat.name.prefix(12)), at.x, at.y + 30, size: 11.5, weight: .semibold,
                  color: .white.opacity(0.82 * quiet))
        } else {
            words(&ctx, seat.hand, at.x, at.y + 30, size: seat.hand.count > 14 ? 10 : 11.5, weight: .heavy, color: Ink.gold)
        }
        words(&ctx, seat.out ? "Out" : M.grouped(seat.chips), at.x, at.y + 45.5, size: 14, weight: .heavy,
              color: Ink.gold.opacity(quiet))

        let badge = disc(at.x, at.y - 4, 22)
        ctx.fill(badge, with: .color(Ink.hex(0x0A0F18)))
        ctx.fill(badge, with: .color(Ink.seats[k % Ink.seats.count].opacity(quiet)))
        ctx.stroke(badge, with: .color(.white.opacity(0.85 * quiet)), lineWidth: 2 * u)
        words(&ctx, String(seat.name.prefix(1)).uppercased(), at.x, at.y - 4, size: 19, weight: .heavy,
              color: .white.opacity(Swift.max(0.5, quiet)))
        if seat.glow > 0.01 {
            ctx.stroke(disc(at.x, at.y - 4, 26 + 8 * (1 - seat.glow)), with: .color(Ink.gold.opacity(seat.glow)),
                       lineWidth: 3 * u)
        }
        if isTurn {
            var ring = Path()
            ring.addArc(center: pt(at.x, at.y - 4), radius: 26.5 * u, startAngle: .degrees(-90),
                        endAngle: .degrees(-90 + 360 * Swift.max(0.02, seat.turn)), clockwise: false)
            ctx.stroke(ring, with: .color(Ink.gold), style: StrokeStyle(lineWidth: 3.2 * u, lineCap: .round))
        }
        if seat.button { drawDealer(&ctx, x: at.x + (Lay.mirrored(k) ? 21 : -21), y: at.y - 23) }
        drawLabel(&ctx, seat, x: at.x, y: at.y - 4)
    }

    private func drawStakes(_ ctx: inout GraphicsContext, _ f: ShortStackFrame) {
        let gather = M.smooth(0, 1, f.gather)
        for k in f.seats.indices where f.seats[k].stake > 0 {
            let seat = f.seats[k]
            let from = Lay.heart(k)
            let spot = Lay.stakes[k]
            let out = M.easeOut(seat.stakeSlide)
            var x = M.lerp(from.x, spot.x, out)
            var y = M.lerp(from.y, spot.y, out)
            x = M.lerp(x, Lay.pile.x, gather)
            y = M.lerp(y, Lay.pile.y, gather)
            drawPile(&ctx, x: x, y: y, amount: seat.stake, alpha: Swift.min(1, seat.stakeSlide * 5))
            let alpha = M.smooth(0.5, 1, seat.stakeSlide) * (1 - M.smooth(0, 0.3, f.gather))
            if alpha > 0.01 {
                let left = Lay.mirrored(k)
                words(&ctx, M.grouped(seat.stake), x + (left ? -14 : 14), y, size: 13.5, weight: .heavy,
                      color: .white.opacity(alpha), anchor: left ? .trailing : .leading)
            }
        }
    }

    private func drawPot(_ ctx: inout GraphicsContext, _ f: ShortStackFrame) {
        if f.pot > 0, f.awardAge < 0 { drawPile(&ctx, x: Lay.pile.x, y: Lay.pile.y, amount: f.pot) }
        let said = f.message.isEmpty ? 0 : M.smooth(0, 0.15, f.messageAge) * (1 - M.smooth(f.messageLife - 0.3, f.messageLife, f.messageAge))
        if said > 0.01 {
            let size = f.message.count > 40 ? 12.5 : 14.5
            let w = Swift.min(372, 30 + size * 0.56 * Double(f.message.count))
            let pop = 0.9 + 0.1 * M.easeOut(f.messageAge / 0.2)
            var c = ctx
            c.opacity = said
            c.fill(pill(Lay.pot.x, Lay.pot.y, w * pop, 32 * pop), with: .color(Ink.hex(0x0A0F18, 0.92)))
            c.stroke(pill(Lay.pot.x, Lay.pot.y, w * pop, 32 * pop), with: .color(Ink.gold.opacity(0.7)), lineWidth: 1.2 * u)
            words(&c, f.message, Lay.pot.x, Lay.pot.y, size: size * pop, weight: .heavy, color: .white)
            return
        }
        if f.total <= 0 { return }
        let line = "Pot \(M.grouped(f.total))"
        ctx.fill(pill(Lay.pot.x, Lay.pot.y, 26 + 8.4 * Double(line.count), 27), with: .color(Ink.hex(0x06231E, 0.72)))
        words(&ctx, line, Lay.pot.x, Lay.pot.y, size: 14.5, weight: .heavy, color: .white.opacity(0.95))
    }

    private func drawAwards(_ ctx: inout GraphicsContext, _ f: ShortStackFrame) {
        if f.awardAge < 0 { return }
        let slide = M.smooth(0, Lay.awardSlide, f.awardAge)
        for award in f.awards {
            let to = Lay.heart(award.seat)
            if slide < 1 {
                drawPile(&ctx, x: M.lerp(Lay.pile.x, to.x, slide), y: M.lerp(Lay.pile.y, to.y, slide), amount: award.amount)
                continue
            }
            let since = f.awardAge - Lay.awardSlide
            let alpha = 1 - M.smooth(0.9, 1.4, since)
            if alpha <= 0.01 { continue }
            let rise = 26 * M.easeOut(since / 0.5)
            // Over the player's cards it would hide the name of their hand, so it goes above them.
            let y = award.seat == 0 ? 506 - rise * 0.4 : to.y - 30 - rise * 0.5
            let line = "+\(M.grouped(award.amount))"
            var c = ctx
            c.opacity = alpha
            c.fill(pill(to.x, y, 22 + 9 * Double(line.count), 24), with: .color(Ink.gold))
            words(&c, line, to.x, y, size: 14, weight: .heavy, color: Ink.ink)
        }
    }

    private func drawKey(_ ctx: inout GraphicsContext, _ f: ShortStackFrame, _ key: ShortStackKey, title: String,
                         sub: String, fill: Color, text: Color, on: Bool, alpha: Double = 1) {
        let at = Lay.keyBox(key, sizes: f.controls.sizeAmounts.count)
        let pressed = f.controls.pressed == key ? exp(-9 * f.controls.pressedAge) : 0
        let grow = 1 - 0.05 * pressed
        var c = ctx
        c.opacity = alpha * (on ? 1 : 0.3)
        let shape = pill(at.x, at.y, at.w * grow, at.h * grow, radius: 17)
        c.fill(shape.offsetBy(dx: 0, dy: 3 * u), with: .color(.black.opacity(0.35)))
        c.fill(shape, with: .color(fill))
        c.fill(shape, with: .linearGradient(Gradient(colors: [.white.opacity(0.2 + 0.3 * pressed), .white.opacity(0)]),
                                            startPoint: pt(0, at.y - at.h / 2), endPoint: pt(0, at.y + at.h / 4)))
        let small = at.h < 60
        if sub.isEmpty {
            words(&c, title, at.x, at.y, size: small ? 15 : 20, weight: .heavy, color: text)
        } else {
            words(&c, title, at.x, at.y - (small ? 9 : 10), size: small ? 11.5 : 17, weight: .heavy,
                  color: small ? text.opacity(0.75) : text)
            words(&c, sub, at.x, at.y + (small ? 8 : 13), size: small ? 16 : 15, weight: .heavy,
                  color: small ? text : text.opacity(0.85))
        }
    }

    private func drawControls(_ ctx: inout GraphicsContext, _ f: ShortStackFrame) {
        let keys = f.controls
        drawKey(&ctx, f, .fold, title: "Fold", sub: "", fill: Ink.slate, text: .white, on: keys.live)
        drawKey(&ctx, f, .call, title: keys.call, sub: keys.callSub, fill: Ink.teal, text: Ink.hex(0x04221D), on: keys.live)
        drawKey(&ctx, f, .raise, title: "Raise", sub: "", fill: Ink.gold, text: Ink.hex(0x2B1D00), on: keys.live && keys.canRaise)
        if keys.live {
            // The turn clock, running down above the keys.
            ctx.fill(pill(201, 746, 370, 4), with: .color(.white.opacity(0.14)))
            let w = 370 * M.clamp(keys.clock)
            if w > 1 {
                ctx.fill(pill(16 + w / 2, 746, w, 4), with: .color(keys.clock < 0.25 ? Ink.red : Ink.gold))
            }
        }
        if keys.menu > 0.01 {
            for k in keys.sizeAmounts.indices where k < keys.sizeTitles.count {
                drawKey(&ctx, f, .size(k), title: keys.sizeTitles[k], sub: M.grouped(keys.sizeAmounts[k]),
                        fill: Ink.hex(0xFFE39A), text: Ink.hex(0x2B1D00), on: true, alpha: keys.menu)
            }
        }
    }

    private func drawEnding(_ ctx: inout GraphicsContext, _ f: ShortStackFrame) {
        var c = ctx
        c.opacity = f.fade
        c.fill(Path(CGRect(x: 0, y: 0, width: lay.W, height: lay.H)), with: .color(.black.opacity(0.62)))
        let rise = 14 * (1 - M.easeOut(f.fade))
        c.fill(pill(201, 420 + rise, 300, f.endScore.isEmpty ? 84 : 132, radius: 26), with: .color(Ink.hex(0x101826)))
        c.stroke(pill(201, 420 + rise, 300, f.endScore.isEmpty ? 84 : 132, radius: 26), with: .color(Ink.gold.opacity(0.6)),
                 lineWidth: 1.4 * u)
        if f.endScore.isEmpty {
            words(&c, f.endTitle, 201, 420 + rise, size: 24, weight: .heavy, color: .white)
        } else {
            words(&c, f.endTitle, 201, 390 + rise, size: 16, weight: .semibold, color: .white.opacity(0.75))
            words(&c, f.endScore, 201, 432 + rise, size: 36, weight: .heavy, color: Ink.gold)
        }
    }
}

// MARK: - The clip

/// One fixed hand for covers and the Videos feed: the deal, the flop, the turn, the river, the
/// showdown and the pot going to its taker.
enum ShortStackClip {
    private struct Step {
        let at: Double
        let seat: Int
        let label: String
        let stake: Int
        let chips: Int
        var fold = false
    }

    private struct Round {
        let steps: [Step]
        /// When the chips in front start for the middle. Below 0: nobody put any in.
        let gather: Double
        let potAfter: Int
    }

    /// Seconds the feed takes to play the clip once, to turn a phase into the age of a label.
    private static let seconds = 7.0
    private static let names = ["mira", "kaz", "devon.plays", "noor.runs", "tofu", "juno"]
    private static let chips = [1180, 940, 760, 1120, 1010, 990]
    private static let holes: [[ShortStackCard]] = [
        [ShortStackCard(rank: 14, suit: 0), ShortStackCard(rank: 13, suit: 0)],
        [ShortStackCard(rank: 13, suit: 3), ShortStackCard(rank: 12, suit: 3)],
        [ShortStackCard(rank: 7, suit: 1), ShortStackCard(rank: 3, suit: 2)],
        [ShortStackCard(rank: 10, suit: 1), ShortStackCard(rank: 9, suit: 2)],
        [ShortStackCard(rank: 5, suit: 0), ShortStackCard(rank: 2, suit: 1)],
        [ShortStackCard(rank: 8, suit: 3), ShortStackCard(rank: 4, suit: 0)],
    ]
    private static let board = [ShortStackCard(rank: 13, suit: 1), ShortStackCard(rank: 9, suit: 0),
                                ShortStackCard(rank: 4, suit: 2), ShortStackCard(rank: 14, suit: 2),
                                ShortStackCard(rank: 2, suit: 3)]
    /// When each board card starts out.
    private static let reveals = [0.335, 0.35, 0.365, 0.55, 0.67]
    private static let rounds = [
        Round(steps: [Step(at: 0.14, seat: 2, label: "Fold", stake: 0, chips: 760, fold: true),
                      Step(at: 0.165, seat: 3, label: "Call 40", stake: 40, chips: 1080),
                      Step(at: 0.19, seat: 4, label: "Fold", stake: 0, chips: 1010, fold: true),
                      Step(at: 0.21, seat: 5, label: "Fold", stake: 0, chips: 990, fold: true),
                      Step(at: 0.235, seat: 0, label: "Raise 120", stake: 120, chips: 1060),
                      Step(at: 0.26, seat: 1, label: "Call 80", stake: 120, chips: 820),
                      Step(at: 0.285, seat: 3, label: "Fold", stake: 40, chips: 1080, fold: true)],
              gather: 0.305, potAfter: 280),
        Round(steps: [Step(at: 0.44, seat: 0, label: "Raise 140", stake: 140, chips: 920),
                      Step(at: 0.48, seat: 1, label: "Call 140", stake: 140, chips: 680)],
              gather: 0.515, potAfter: 560),
        Round(steps: [Step(at: 0.61, seat: 0, label: "Check", stake: 0, chips: 920),
                      Step(at: 0.64, seat: 1, label: "Check", stake: 0, chips: 680)],
              gather: -1, potAfter: 560),
        Round(steps: [Step(at: 0.74, seat: 0, label: "Raise 300", stake: 300, chips: 620),
                      Step(at: 0.78, seat: 1, label: "Call 300", stake: 300, chips: 380)],
              gather: 0.805, potAfter: 1160),
    ]

    private static let base: ShortStackFrame = {
        var frame = ShortStackFrame()
        for k in 0..<ShortStackLayout.seatCount {
            var seat = ShortStackSeatView()
            seat.name = names[k]
            seat.chips = chips[k]
            seat.cards = holes[k]
            seat.button = k == 5
            frame.seats.append(seat)
        }
        frame.board = board
        frame.hand = 4
        frame.small = 20
        frame.big = 40
        return frame
    }()

    static func frame(at phase: Double) -> ShortStackFrame {
        typealias M = ShortStackMath
        let p = M.clamp(phase)
        var f = base
        f.clock = p * seconds

        // The deal goes round from the seat after the button, twice.
        for k in f.seats.indices {
            let first = 0.008 * Double(k), second = 0.008 * Double(k + 6)
            f.seats[k].dealt = M.clamp((p - first) / 0.03) + M.clamp((p - second) / 0.03)
        }
        f.seats[0].face = M.clamp((p - 0.1) / 0.025)
        if p >= 0.02 {
            f.seats[0].stake = 20
            f.seats[0].chips = 1160
            f.seats[1].stake = 40
            f.seats[1].chips = 900
            f.seats[0].stakeSlide = M.clamp((p - 0.02) * seconds / 0.22)
            f.seats[1].stakeSlide = f.seats[0].stakeSlide
        }

        var pot = 0
        for round in rounds {
            guard let opens = round.steps.first, p >= opens.at else { break }
            for k in f.seats.indices where f.seats[k].folded == 0 && f.seats[k].turn < 0 { f.seats[k].label = "" }
            for step in round.steps where p >= step.at {
                let age = (p - step.at) * seconds
                f.seats[step.seat].label = step.label
                f.seats[step.seat].labelAge = age
                f.seats[step.seat].chips = step.chips
                if step.fold {
                    f.seats[step.seat].folded = M.clamp(age / 0.3)
                } else if step.stake != f.seats[step.seat].stake {
                    f.seats[step.seat].stake = step.stake
                    f.seats[step.seat].stakeSlide = M.clamp(age / 0.22)
                }
            }
            if round.gather >= 0, p >= round.gather {
                f.gather = M.clamp((p - round.gather) / 0.03)
                if f.gather >= 1 {
                    f.gather = 0
                    pot = round.potAfter
                    for k in f.seats.indices { f.seats[k].stake = 0 }
                }
            }
        }
        f.pot = pot
        f.total = pot + f.seats.reduce(0) { $0 + $1.stake }

        // The keys light up while the table waits for the player.
        for (from, to, owed) in [(0.215, 0.235, 20), (0.405, 0.44, 0), (0.585, 0.61, 0), (0.71, 0.74, 0)] where p >= from && p < to {
            f.controls.live = true
            f.controls.canRaise = true
            f.controls.call = owed == 0 ? "Check" : "Call"
            f.controls.callSub = owed == 0 ? "" : "\(owed)"
            f.controls.clock = 1 - 0.2 * (p - from) / (to - from)
            f.seats[0].turn = f.controls.clock
        }

        for k in 0..<5 { f.shown[k] = M.clamp((p - reveals[k]) / 0.05) }
        if f.shown[2] >= 1 { f.seats[0].hand = "Pair of kings" }
        if f.shown[3] >= 1 { f.seats[0].hand = "Two pair" }

        // The showdown, then the pot goes to its taker.
        if p >= 0.835 {
            f.seats[1].face = M.clamp((p - 0.835) / 0.02)
            f.seats[1].hand = "Pair of kings"
            f.seats[1].label = ""
            f.seats[0].label = ""
        }
        if p >= 0.845 {
            f.message = "mira takes the pot. Two pair"
            f.messageAge = (p - 0.845) * seconds
            f.messageLife = 100
            f.awards = [ShortStackAward(seat: 0, amount: 1160)]
            f.awardAge = p < 0.87 ? -1 : (p - 0.87) * seconds
            if f.awardAge >= ShortStackLayout.awardSlide {
                let since = f.awardAge - ShortStackLayout.awardSlide
                f.pot = 0
                f.total = 0
                f.seats[0].chips = 620 + Int(1160 * M.easeOut(since / 0.28))
                f.seats[0].glow = M.clamp(1 - since / 0.6)
            }
        }
        return f
    }
}
