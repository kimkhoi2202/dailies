import SwiftUI

// Wild Eights, drawn. The cover and the Videos feed show a round the scripted player is playing;
// the game paints its live round with the same painter.

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
            let model = WildEightsReplay.model(at: 0.4 + WildEightsMath.clamp(phase) * 15)
            WildEightsPainter(model: model, size: size, showHUD: showHUD, live: false).paint(&context)
        }
    }
}

/// One round played by the scripted player, kept between draws so a moving phase steps it forward
/// instead of replaying it from the deal every frame.
enum WildEightsReplay {
    private static var current: WildEightsModel?
    private static var pilot = WildEightsPilot(seed: seed)
    private static let seed: UInt64 = 0x00C0_FFEE_0808

    static func model(at time: Double) -> WildEightsModel {
        var m: WildEightsModel
        if let kept = current, kept.clock <= time + 1e-6 {
            m = kept
        } else {
            m = WildEightsModel(options: GameOptions(solo: false, playerName: "mira",
                                                     friendNames: ["kaz", "devon.plays", "noor.runs"], seed: seed))
            pilot = WildEightsPilot(seed: seed)
            current = m
        }
        var guardSteps = 0
        while m.clock < time - 1e-6 && guardSteps < 4000 {
            let dt = Swift.min(1.0 / 60, time - m.clock)
            m.step(dt: dt)
            if let move = pilot.next(m, dt: dt, loseAfter: nil) {
                m.apply(.touch)
                m.apply(move)
            }
            guardSteps += 1
        }
        return m
    }
}

// MARK: - Numbers

enum WildEightsMath {
    static func clamp(_ v: Double, _ lo: Double = 0, _ hi: Double = 1) -> Double { Swift.max(lo, Swift.min(hi, v)) }
    static func easeOut(_ v: Double) -> Double {
        let rest = 1 - clamp(v)
        return 1 - rest * rest * rest
    }
    static func smooth(_ a: Double, _ b: Double, _ v: Double) -> Double {
        let k = clamp((v - a) / (b - a))
        return k * k * (3 - 2 * k)
    }
    /// Overshoots a little and settles, for pops.
    static func pop(_ age: Double, _ amount: Double) -> Double {
        if age < 0 { return 1 }
        return 1 + amount * exp(-9 * age) * cos(age * 18)
    }
}

// MARK: - Colours and shapes

enum WildEightsInk {
    static let feltDark = Color(red: 0.08, green: 0.25, blue: 0.21)
    static let felt = Color(red: 0.13, green: 0.35, blue: 0.30)
    static let feltLight = Color(red: 0.19, green: 0.43, blue: 0.37)
    static let face = Color(red: 0.973, green: 0.965, blue: 0.945)
    static let ink = Color(red: 0.082, green: 0.078, blue: 0.071)
    static let red = Color(red: 0.80, green: 0.22, blue: 0.16)
    static let back = Color(red: 0.11, green: 0.62, blue: 0.56)
    static let backStripe = Color(red: 0.08, green: 0.50, blue: 0.46)
    static let gold = Color(red: 0.961, green: 0.702, blue: 0.004)
    static let sheet = Color(red: 0.969, green: 0.957, blue: 0.933)
    static let sheetLip = Color(red: 0.86, green: 0.83, blue: 0.78)
    static let muted = Color(red: 0.45, green: 0.43, blue: 0.40)
    static let seats = [Color(red: 1.0, green: 0.69, blue: 0.34), Color(red: 0.50, green: 0.79, blue: 1.0),
                        Color(red: 1.0, green: 0.53, blue: 0.71)]
    static let sparks = [Color.white, Color(red: 0.55, green: 0.93, blue: 0.82), Color(red: 1.0, green: 0.62, blue: 0.52),
                         Color(red: 1.0, green: 0.84, blue: 0.45), Color(red: 0.64, green: 0.82, blue: 1.0)]
    static let feltGradient = Gradient(colors: [feltLight, felt, feltDark])

    static func suit(_ s: WildEightsSuit) -> Color { s.isRed ? red : ink }
}

/// Paths made once, in a unit box centred on the origin. Drawn by scaling the context.
enum WildEightsShapes {
    static let aspect: CGFloat = 1.42

    static let card = Path(roundedRect: CGRect(x: -0.5, y: -aspect / 2, width: 1, height: aspect),
                           cornerRadius: 0.11, style: .continuous)
    static let cardInner = Path(roundedRect: CGRect(x: -0.44, y: -aspect / 2 + 0.06, width: 0.88, height: aspect - 0.12),
                                cornerRadius: 0.07, style: .continuous)
    static let stripes: Path = {
        var p = Path()
        var x: CGFloat = -1.6
        while x < 1.6 {
            p.move(to: CGPoint(x: x, y: -aspect / 2))
            p.addLine(to: CGPoint(x: x + aspect, y: aspect / 2))
            x += 0.16
        }
        return p
    }()

    static let heart: Path = {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: 0.46))
        p.addCurve(to: CGPoint(x: -0.5, y: -0.1), control1: CGPoint(x: -0.26, y: 0.26), control2: CGPoint(x: -0.5, y: 0.1))
        p.addCurve(to: CGPoint(x: 0, y: -0.26), control1: CGPoint(x: -0.5, y: -0.46), control2: CGPoint(x: -0.08, y: -0.5))
        p.addCurve(to: CGPoint(x: 0.5, y: -0.1), control1: CGPoint(x: 0.08, y: -0.5), control2: CGPoint(x: 0.5, y: -0.46))
        p.addCurve(to: CGPoint(x: 0, y: 0.46), control1: CGPoint(x: 0.5, y: 0.1), control2: CGPoint(x: 0.26, y: 0.26))
        p.closeSubpath()
        return p
    }()

    static let diamond: Path = {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: -0.5))
        p.addQuadCurve(to: CGPoint(x: 0.38, y: 0), control: CGPoint(x: 0.16, y: -0.22))
        p.addQuadCurve(to: CGPoint(x: 0, y: 0.5), control: CGPoint(x: 0.16, y: 0.22))
        p.addQuadCurve(to: CGPoint(x: -0.38, y: 0), control: CGPoint(x: -0.16, y: 0.22))
        p.addQuadCurve(to: CGPoint(x: 0, y: -0.5), control: CGPoint(x: -0.16, y: -0.22))
        p.closeSubpath()
        return p
    }()

    private static let stem: Path = {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: 0.0))
        p.addQuadCurve(to: CGPoint(x: -0.2, y: 0.5), control: CGPoint(x: -0.02, y: 0.4))
        p.addLine(to: CGPoint(x: 0.2, y: 0.5))
        p.addQuadCurve(to: CGPoint(x: 0, y: 0.0), control: CGPoint(x: 0.02, y: 0.4))
        p.closeSubpath()
        return p
    }()

    static let spade: Path = {
        var p = Path()
        let flip = CGAffineTransform(scaleX: 0.92, y: -0.78).translatedBy(x: 0, y: 0.2)
        p.addPath(heart, transform: flip)
        p.addPath(stem)
        return p
    }()

    static let club: Path = {
        var p = Path()
        let r: CGFloat = 0.215
        p.addEllipse(in: CGRect(x: -r, y: -0.47, width: 2 * r, height: 2 * r))
        p.addEllipse(in: CGRect(x: -0.47, y: -0.12, width: 2 * r, height: 2 * r))
        p.addEllipse(in: CGRect(x: 0.47 - 2 * r, y: -0.12, width: 2 * r, height: 2 * r))
        p.addEllipse(in: CGRect(x: -0.12, y: -0.2, width: 0.24, height: 0.3))
        p.addPath(stem)
        return p
    }()

    static func path(_ suit: WildEightsSuit) -> Path {
        switch suit {
        case .spades: return spade
        case .hearts: return heart
        case .clubs: return club
        case .diamonds: return diamond
        }
    }
}

// MARK: - Layout

/// Where everything sits on a screen of this size. The painter and the touch code share it.
struct WildEightsLayout {
    let W: CGFloat
    let H: CGFloat
    let u: CGFloat
    /// Card widths: in the hand and on the piles.
    let cw: CGFloat
    let pw: CGFloat
    let scoreY: CGFloat
    let seatY: CGFloat
    let pilesY: CGFloat
    let pillY: CGFloat
    let handY: CGFloat
    let deck: CGPoint
    let discard: CGPoint

    init(size: CGSize) {
        W = size.width
        H = size.height
        u = Swift.min(W / 402, H / 760)
        cw = 76 * u
        pw = 90 * u
        scoreY = GameLayout.statusBarHeight + 24
        seatY = GameLayout.topBand + 44 * u
        let ph = pw * WildEightsShapes.aspect
        pilesY = Swift.max(seatY + 66 * u + ph / 2 + 18 * u, H * 0.45)
        pillY = pilesY + ph / 2 + 44 * u
        handY = H - GameLayout.bottomInset - cw * WildEightsShapes.aspect / 2 - 10 * u
        deck = CGPoint(x: W / 2 - 58 * u, y: pilesY)
        discard = CGPoint(x: W / 2 + 58 * u, y: pilesY)
    }

    var ph: CGFloat { pw * WildEightsShapes.aspect }
    var ch: CGFloat { cw * WildEightsShapes.aspect }

    var deckRect: CGRect { CGRect(x: deck.x - pw / 2 - 10 * u, y: deck.y - ph / 2 - 10 * u, width: pw + 20 * u, height: ph + 20 * u) }
    var discardRect: CGRect {
        CGRect(x: discard.x - pw / 2 - 10 * u, y: discard.y - ph / 2 - 10 * u, width: pw + 20 * u, height: ph + 20 * u)
    }

    func seat(_ k: Int, of n: Int) -> CGPoint {
        let off = CGFloat(k - 1) - CGFloat(n - 1) / 2
        return CGPoint(x: W / 2 + off * 118 * u, y: seatY)
    }

    func spacing(_ count: Int) -> CGFloat {
        if count <= 1 { return 0 }
        return Swift.min(cw * 0.7, (W - 22 * u - cw) / CGFloat(count - 1))
    }

    /// A card in the fan: its centre and its tilt. lift 1 is a card picked up to play.
    func hand(_ pos: Double, _ count: Int, lift: Double) -> (CGPoint, CGFloat) {
        let off = CGFloat(pos) - CGFloat(count - 1) / 2
        let dx = off * spacing(count)
        let tilt = Swift.min(0.075, 0.5 / CGFloat(Swift.max(count, 1)))
        let y = handY + dx * dx / (900 * u) - CGFloat(lift) * 40 * u
        return (CGPoint(x: W / 2 + dx, y: y), off * tilt)
    }

    /// A spot on the table as a centre, a tilt and a card width.
    func place(_ spot: WildEightsModel.Spot, seats: Int) -> (CGPoint, CGFloat, CGFloat) {
        switch spot {
        case .deck: return (deck, 0, pw)
        case .discard: return (discard, 0, pw)
        case .seat(let k): return (seat(k, of: seats), 0, pw * 0.4)
        case .hand(let pos, let count):
            let (p, a) = hand(pos, count, lift: 1)
            return (p, a, cw)
        }
    }

    /// The card under a finger, top card first.
    func handIndex(at point: CGPoint, model: WildEightsModel) -> Int? {
        let slots = model.slots
        var k = slots.count - 1
        while k >= 0 {
            let (c, a) = hand(slots[k].pos, slots.count, lift: slots[k].lift)
            let dx = point.x - c.x
            let dy = point.y - c.y
            let lx = dx * cos(-a) - dy * sin(-a)
            let ly = dx * sin(-a) + dy * cos(-a)
            let reach = CGFloat(slots[k].lift) * 40 * u
            if abs(lx) <= cw / 2 && ly >= -ch / 2 - 4 * u && ly <= ch / 2 + reach { return k }
            k -= 1
        }
        return nil
    }

    // The suit sheet.

    var sheetHeight: CGFloat { Swift.min(410 * u, H * 0.56) }

    func sheetTop(_ t: Double) -> CGFloat { H - sheetHeight * CGFloat(t) }

    func suitRect(_ k: Int, sheet t: Double) -> CGRect {
        let top = sheetTop(t)
        let margin = 22 * u
        let gap = 14 * u
        let head = 136 * u
        let w = (W - 2 * margin - gap) / 2
        let h = (sheetHeight - head - gap - GameLayout.bottomInset) / 2
        let col = CGFloat(k % 2)
        let row = CGFloat(k / 2)
        return CGRect(x: margin + col * (w + gap), y: top + head + row * (h + gap), width: w, height: h)
    }

    func suitButton(at point: CGPoint, sheet t: Double) -> WildEightsSuit? {
        for suit in WildEightsSuit.allCases where suitRect(suit.rawValue, sheet: t).insetBy(dx: -5 * u, dy: -5 * u).contains(point) {
            return suit
        }
        return nil
    }
}

// MARK: - Painter

struct WildEightsPainter {
    typealias Model = WildEightsModel
    typealias M = WildEightsMath

    let m: Model
    let L: WildEightsLayout
    let showHUD: Bool
    /// The real round, with its hint for a first-time player. The cover leaves it out.
    let live: Bool

    static let countLabels: [String] = (0...60).map { $0 == 1 ? "1 card" : "\($0) cards" }

    init(model: Model, size: CGSize, showHUD: Bool, live: Bool) {
        m = model
        L = WildEightsLayout(size: size)
        self.showHUD = showHUD
        self.live = live
    }

    private var u: CGFloat { L.u }
    private var now: Double { m.clock }

    func paint(_ ctx: inout GraphicsContext) {
        drawFelt(&ctx)
        drawSeats(&ctx)
        drawPiles(&ctx)
        if showHUD {
            drawScore(&ctx)
            drawPill(&ctx)
        }
        if live { drawHint(&ctx) }
        drawHand(&ctx)
        drawFlights(&ctx)
        drawParticles(&ctx)
        drawFloaters(&ctx)
        drawPraise(&ctx)
        drawSheet(&ctx)
        drawEnding(&ctx)
    }

    // MARK: Table

    private func drawFelt(_ ctx: inout GraphicsContext) {
        let rect = CGRect(x: 0, y: 0, width: L.W, height: L.H)
        let centre = CGPoint(x: L.W / 2, y: L.pilesY)
        ctx.fill(Path(rect), with: .radialGradient(WildEightsInk.feltGradient, center: centre,
                                                   startRadius: 0, endRadius: Swift.max(L.W, L.H) * 0.72))
    }

    private func shadowed(_ ctx: inout GraphicsContext, _ text: Text, at p: CGPoint, anchor: UnitPoint = .center,
                          color: Color = .white, alpha: Double = 1, drop: CGFloat = 2.5) {
        ctx.draw(text.foregroundColor(Color.black.opacity(0.28 * alpha)), at: CGPoint(x: p.x, y: p.y + drop * u), anchor: anchor)
        ctx.draw(text.foregroundColor(color.opacity(alpha)), at: p, anchor: anchor)
    }

    private func drawScore(_ ctx: inout GraphicsContext) {
        let value = Int(m.shownScore.rounded())
        let scale = CGFloat(M.pop(now - m.scorePoppedAt, 0.18))
        let text = Text("\(value)").font(.system(size: 40 * u * scale, weight: .heavy, design: .rounded))
        shadowed(&ctx, text, at: CGPoint(x: L.W / 2, y: L.scoreY))
    }

    private func drawSeats(_ ctx: inout GraphicsContext) {
        let n = m.rivals.count
        let r = 25 * u
        for (i, rival) in m.rivals.enumerated() {
            let k = i + 1
            let p = L.seat(k, of: n)
            let colour = WildEightsInk.seats[i % WildEightsInk.seats.count]
            let active = m.turn == k && (m.stage == .playing || m.stage == .ready)
            if active {
                let pulse = 0.75 + 0.25 * sin(now * 5)
                for (grow, alpha) in [(14.0, 0.16), (8.0, 0.28)] {
                    let g = CGFloat(grow) * u
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x - r - g, y: p.y - r - g, width: 2 * (r + g), height: 2 * (r + g))),
                             with: .color(colour.opacity(alpha * pulse)))
                }
            }
            let bump = CGFloat(M.pop(now - rival.playedAt, 0.12))
            let rr = r * bump
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - rr, y: p.y - rr + 3 * u, width: 2 * rr, height: 2 * rr)),
                     with: .color(Color.black.opacity(0.22)))
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - rr, y: p.y - rr, width: 2 * rr, height: 2 * rr)), with: .color(colour))
            ctx.draw(Text(rival.initial).font(.system(size: 22 * u * bump, weight: .heavy, design: .rounded))
                        .foregroundColor(WildEightsInk.ink), at: p, anchor: .center)

            let count = Swift.min(rival.hand.count, Self.countLabels.count - 1)
            let low = count <= 1 && m.stage != .dealing
            let label = Text(Self.countLabels[count]).font(.system(size: 15 * u, weight: .heavy, design: .rounded))
            shadowed(&ctx, label, at: CGPoint(x: p.x, y: p.y + r + 14 * u),
                     color: low ? Color(red: 1, green: 0.78, blue: 0.70) : .white, drop: 1.5)
            let name = Text(rival.name).font(.system(size: 12 * u, weight: .bold, design: .rounded))
            ctx.draw(name.foregroundColor(Color.white.opacity(0.62)), at: CGPoint(x: p.x, y: p.y + r + 31 * u), anchor: .center)
        }
    }

    private func drawPiles(_ ctx: inout GraphicsContext) {
        let pw = L.pw
        // The draw pile: a few backs, and a glow when drawing is the only move.
        let depth = Swift.min(3, m.deck.count)
        if depth == 0 {
            let rect = CGRect(x: L.deck.x - pw / 2, y: L.deck.y - L.ph / 2, width: pw, height: L.ph)
            ctx.stroke(Path(roundedRect: rect, cornerRadius: 10 * u), with: .color(Color.white.opacity(0.25)),
                       style: StrokeStyle(lineWidth: 2 * u, dash: [6 * u, 5 * u]))
        }
        let mustDraw = m.canAct && !m.hasPlayable && m.stage != .dealing
        for k in 0..<depth {
            let off = CGFloat(depth - 1 - k) * 2.2 * u
            let glow = (k == depth - 1 && mustDraw) ? 0.6 + 0.4 * sin(now * 6) : 0
            drawBack(&ctx, CGPoint(x: L.deck.x - off, y: L.deck.y - off), pw, angle: 0, glow: glow)
        }

        // The discard pile: the top card and two under it, each at its own slight angle.
        let visible = m.discard.count - m.discardInFlight
        if visible <= 0 { return }
        var k = Swift.max(0, visible - 3)
        while k < visible {
            let card = m.discard[k]
            let a = CGFloat((card.suit.rawValue * 13 + card.rank) * 37 % 11 - 5) * 0.022
            drawFace(&ctx, card, L.discard, pw, angle: a)
            k += 1
        }
        let top = m.discard[visible - 1]
        if top.isEight && now >= m.suitPickedAt {
            let s = CGFloat(M.pop(now - m.suitPickedAt, 0.45))
            let r = 17 * u * s
            let c = CGPoint(x: L.discard.x + pw / 2 - 2 * u, y: L.discard.y - L.ph / 2 + 2 * u)
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r + 2 * u, width: 2 * r, height: 2 * r)),
                     with: .color(Color.black.opacity(0.25)))
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(WildEightsInk.gold))
            drawSuit(&ctx, m.suit, c, 17 * u * s, WildEightsInk.suit(m.suit))
        }
    }

    private func drawPill(_ ctx: inout GraphicsContext) {
        if m.stage == .ending || m.stage == .finished { return }
        let mine = m.isPlayerTurn
        let text = Text(m.pill).font(.system(size: 17 * u, weight: .heavy, design: .rounded))
            .foregroundColor(.white)
        let resolved = ctx.resolve(text)
        let size = resolved.measure(in: CGSize(width: L.W, height: 60 * u))
        let s = CGFloat(mine ? M.pop(now - m.turnStartedAt, 0.08) : 1)
        let w = (size.width + 40 * u) * s
        let h = 44 * u * s
        let rect = CGRect(x: L.W / 2 - w / 2, y: L.pillY - h / 2, width: w, height: h)
        ctx.fill(Path(roundedRect: rect, cornerRadius: h / 2), with: .color(Color.black.opacity(mine ? 0.34 : 0.2)))
        if mine {
            ctx.stroke(Path(roundedRect: rect, cornerRadius: h / 2), with: .color(Color.white.opacity(0.22)), lineWidth: 1.5 * u)
        }
        var g = ctx
        g.opacity = mine ? 1 : 0.78
        g.translateBy(x: L.W / 2, y: L.pillY)
        g.scaleBy(x: s, y: s)
        g.draw(resolved, at: .zero, anchor: .center)
    }

    private func drawHint(_ ctx: inout GraphicsContext) {
        guard m.played == 0, m.canAct, m.draws == 0 else { return }
        let alpha = 0.6 + 0.3 * sin(now * 3.4)
        let text = Text(m.selected == nil ? "Tap a card to lift it" : "Tap it again to play")
            .font(.system(size: 15 * u, weight: .bold, design: .rounded))
        ctx.draw(text.foregroundColor(Color.white.opacity(alpha)), at: CGPoint(x: L.W / 2, y: L.pillY + 40 * u), anchor: .center)
    }

    // MARK: Cards

    private func drawHand(_ ctx: inout GraphicsContext) {
        let count = m.slots.count
        let mine = m.canAct
        for (k, slot) in m.slots.enumerated() {
            var (p, a) = L.hand(slot.pos, count, lift: slot.lift)
            var w = L.cw
            var flip: CGFloat = 1
            let age = now - slot.born
            if age < 0.34 {
                let e = CGFloat(M.easeOut(age / 0.34))
                p = CGPoint(x: L.deck.x + (p.x - L.deck.x) * e, y: L.deck.y + (p.y - L.deck.y) * e - sin(e * .pi) * 30 * u)
                a *= e
                w = L.pw + (L.cw - L.pw) * e
                flip = -cos(e * .pi)
            }
            if m.shakeCard == slot.card {
                let t = now - m.shakeAt
                if t < 0.35 { p.x += CGFloat(sin(t * 48) * (1 - t / 0.35)) * 7 * u }
            }
            let playable = m.isPlayable(slot.card)
            let dim: Double = mine && !playable ? 0.42 : 0
            let glow: Double = m.selected == k ? 1 : 0
            if flip > 0 {
                drawFace(&ctx, slot.card, p, w, angle: a, squeeze: flip, dim: dim, glow: glow)
            } else {
                drawBack(&ctx, p, w, angle: a, squeeze: -flip)
            }
        }
    }

    private func drawFlights(_ ctx: inout GraphicsContext) {
        let seats = m.rivals.count
        for flight in m.flights {
            let t = (now - flight.start) / flight.length
            if t < 0 || t >= 1 { continue }
            let e = CGFloat(M.easeOut(t))
            let (p0, a0, w0) = L.place(flight.from, seats: seats)
            let (p1, a1, w1) = L.place(flight.to, seats: seats)
            let p = CGPoint(x: p0.x + (p1.x - p0.x) * e, y: p0.y + (p1.y - p0.y) * e - sin(e * .pi) * 26 * u)
            let a = a0 + (a1 - a0) * e + CGFloat(flight.spin) * sin(e * .pi)
            let w = w0 + (w1 - w0) * e
            var face: CGFloat = flight.faceFrom ? 1 : -1
            if flight.faceFrom != flight.faceTo {
                face = flight.faceTo ? -cos(e * .pi) : cos(e * .pi)
            }
            if face > 0 {
                drawFace(&ctx, flight.card, p, w, angle: a, squeeze: face)
            } else {
                drawBack(&ctx, p, w, angle: a, squeeze: -face)
            }
        }
    }

    private func drawFace(_ ctx: inout GraphicsContext, _ card: WildEightsCard, _ c: CGPoint, _ w: CGFloat, angle: CGFloat,
                          squeeze: CGFloat = 1, dim: Double = 0, glow: Double = 0) {
        var g = ctx
        g.translateBy(x: c.x, y: c.y)
        g.rotate(by: .radians(Double(angle)))
        g.scaleBy(x: Swift.max(squeeze, 0.02), y: 1)
        var s = g
        s.scaleBy(x: w, y: w)
        var shade = s
        shade.translateBy(x: 0, y: 0.045)
        shade.fill(WildEightsShapes.card, with: .color(Color.black.opacity(0.24)))
        if glow > 0 {
            s.stroke(WildEightsShapes.card, with: .color(Color.white.opacity(0.95 * glow)), lineWidth: 0.07)
        }
        s.fill(WildEightsShapes.card, with: .color(WildEightsInk.face))

        let colour = WildEightsInk.suit(card.suit)
        let h = w * WildEightsShapes.aspect
        let ten = card.rank == 10
        let rank = Text(card.label).font(.system(size: w * (ten ? 0.25 : 0.29), weight: .heavy, design: .rounded))
            .foregroundColor(colour)
        g.draw(rank, at: CGPoint(x: -w / 2 + w * (ten ? 0.07 : 0.1), y: -h / 2 + w * 0.05), anchor: .topLeading)
        drawSuit(&g, card.suit, CGPoint(x: -w / 2 + w * 0.17, y: -h / 2 + w * 0.47), w * 0.17, colour)
        drawSuit(&g, card.suit, CGPoint(x: w / 2 - w * 0.25, y: h / 2 - w * 0.27), w * 0.33, colour)
        if dim > 0 {
            s.fill(WildEightsShapes.card, with: .color(WildEightsInk.felt.opacity(dim)))
        }
    }

    private func drawBack(_ ctx: inout GraphicsContext, _ c: CGPoint, _ w: CGFloat, angle: CGFloat,
                          squeeze: CGFloat = 1, glow: Double = 0) {
        var g = ctx
        g.translateBy(x: c.x, y: c.y)
        g.rotate(by: .radians(Double(angle)))
        g.scaleBy(x: Swift.max(squeeze, 0.02) * w, y: w)
        var shade = g
        shade.translateBy(x: 0, y: 0.045)
        shade.fill(WildEightsShapes.card, with: .color(Color.black.opacity(0.24)))
        if glow > 0 {
            g.stroke(WildEightsShapes.card, with: .color(Color.white.opacity(glow)), lineWidth: 0.09)
        }
        g.fill(WildEightsShapes.card, with: .color(.white))
        g.fill(WildEightsShapes.cardInner, with: .color(WildEightsInk.back))
        var inner = g
        inner.clip(to: WildEightsShapes.cardInner)
        inner.stroke(WildEightsShapes.stripes, with: .color(WildEightsInk.backStripe), lineWidth: 0.055)
    }

    private func drawSuit(_ ctx: inout GraphicsContext, _ suit: WildEightsSuit, _ c: CGPoint, _ size: CGFloat, _ colour: Color) {
        var g = ctx
        g.translateBy(x: c.x, y: c.y)
        g.scaleBy(x: size, y: size)
        g.fill(WildEightsShapes.path(suit), with: .color(colour))
    }

    // MARK: Juice

    private func drawParticles(_ ctx: inout GraphicsContext) {
        let seats = m.rivals.count
        for p in m.particles where p.age > 0 && p.age < p.life {
            let (origin, _, _) = L.place(p.spot, seats: seats)
            let k = p.age / p.life
            let r = CGFloat(p.size * (1 - k * 0.6)) * u
            let x = origin.x + CGFloat(p.x) * u
            let y = origin.y + CGFloat(p.y) * u
            ctx.fill(Path(roundedRect: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r), cornerRadius: r * 0.4),
                     with: .color(WildEightsInk.sparks[p.tone % WildEightsInk.sparks.count].opacity(1 - k * k)))
        }
    }

    private func drawFloaters(_ ctx: inout GraphicsContext) {
        let seats = m.rivals.count
        for f in m.floaters {
            let age = now - f.born
            if age < 0 || age > 1.2 { continue }
            let (origin, _, _) = L.place(f.spot, seats: seats)
            let rise = CGFloat(M.easeOut(age / 1.2)) * (f.big ? 70 : 52) * u
            let alpha = 1 - M.smooth(0.7, 1.2, age)
            let s = CGFloat(M.pop(age, 0.3))
            let size = (f.big ? 34 : 24) * u * s
            let text = Text(f.text).font(.system(size: size, weight: .black, design: .rounded))
            let negative = f.text.hasPrefix("-")
            shadowed(&ctx, text, at: CGPoint(x: origin.x + (f.big ? 0 : 30 * u), y: origin.y - L.ph * 0.4 - rise),
                     color: negative ? Color(red: 1, green: 0.62, blue: 0.55) : .white, alpha: alpha)
        }
    }

    private func drawPraise(_ ctx: inout GraphicsContext) {
        guard let word = m.praise else { return }
        let age = now - m.praiseAt
        if age < 0 { return }
        let alpha = M.easeOut(age / 0.08) * (1 - M.smooth(0.75, 1.1, age))
        let s = CGFloat(0.6 + 0.4 * M.easeOut(age / 0.14)) * CGFloat(M.pop(age, 0.12))
        let text = Text(word).font(.system(size: 34 * u * s, weight: .black, design: .rounded)).italic()
        let y = L.pilesY - L.ph / 2 - 34 * u - CGFloat(age) * 14 * u
        shadowed(&ctx, text, at: CGPoint(x: L.W / 2, y: y), alpha: alpha, drop: 3)
    }

    // MARK: Overlays

    private func drawSheet(_ ctx: inout GraphicsContext) {
        let t = m.sheet
        if t < 0.01 { return }
        ctx.fill(Path(CGRect(x: 0, y: 0, width: L.W, height: L.H)), with: .color(Color.black.opacity(0.45 * t)))
        let top = L.sheetTop(t)
        let body = CGRect(x: 0, y: top, width: L.W, height: L.sheetHeight + 60 * u)
        ctx.fill(Path(roundedRect: body, cornerRadius: 34 * u, style: .continuous), with: .color(WildEightsInk.sheet))
        let handle = CGRect(x: L.W / 2 - 22 * u, y: top + 12 * u, width: 44 * u, height: 5 * u)
        ctx.fill(Path(roundedRect: handle, cornerRadius: 2.5 * u), with: .color(WildEightsInk.sheetLip))

        drawFace(&ctx, m.sheetCard, CGPoint(x: 22 * u + 31 * u, y: top + 74 * u), 62 * u, angle: -0.05)
        let title = Text("WILD EIGHT").font(.system(size: 30 * u, weight: .black, design: .rounded))
            .foregroundColor(WildEightsInk.ink)
        ctx.draw(title, at: CGPoint(x: 104 * u, y: top + 62 * u), anchor: .leading)
        let line = Text("Pick the next suit").font(.system(size: 17 * u, weight: .semibold, design: .rounded))
            .foregroundColor(WildEightsInk.muted)
        ctx.draw(line, at: CGPoint(x: 104 * u, y: top + 94 * u), anchor: .leading)

        for suit in WildEightsSuit.allCases {
            let rect = L.suitRect(suit.rawValue, sheet: t)
            let lip = rect.offsetBy(dx: 0, dy: 5 * u)
            ctx.fill(Path(roundedRect: lip, cornerRadius: 22 * u, style: .continuous), with: .color(WildEightsInk.sheetLip))
            ctx.fill(Path(roundedRect: rect, cornerRadius: 22 * u, style: .continuous), with: .color(.white))
            let size = Swift.min(rect.height * 0.46, 60 * u)
            drawSuit(&ctx, suit, CGPoint(x: rect.midX, y: rect.midY), size, WildEightsInk.suit(suit))
        }
    }

    private func drawEnding(_ ctx: inout GraphicsContext) {
        guard m.stage == .ending || m.stage == .finished else { return }
        let k = M.smooth(0.35, 0.8, m.endClock)
        if k <= 0 { return }
        ctx.fill(Path(CGRect(x: 0, y: 0, width: L.W, height: L.H)), with: .color(Color.black.opacity(0.35 * k)))
        let s = CGFloat(0.85 + 0.15 * M.easeOut((m.endClock - 0.35) / 0.3))
        let title = Text(m.endTitle).font(.system(size: 30 * u * s, weight: .black, design: .rounded))
        shadowed(&ctx, title, at: CGPoint(x: L.W / 2, y: L.pillY - 4 * u), alpha: k, drop: 3)
        let line = Text(m.endLine).font(.system(size: 17 * u, weight: .bold, design: .rounded))
        ctx.draw(line.foregroundColor(Color.white.opacity(0.8 * k)), at: CGPoint(x: L.W / 2, y: L.pillY + 32 * u), anchor: .center)
    }
}
