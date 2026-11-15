import SwiftUI

// Pour Party: sort the colours into their own tubes, one pour at a time.
//
// The whole picture is painted into one Canvas by PourPartyPainter from a PourPartyFrame. The clip
// in the video feed builds a frame from a phase (0...1) and a fixed script; the playable game builds
// one from its live model. The backdrop, the glass, the ribbon and the crown are pictures in
// Resources/GameArt; the liquid and everything that moves inside the glass is drawn here.

public struct PourPartyScene: View {
    public var phase: Double
    public var showHUD: Bool

    public init(phase: Double, showHUD: Bool) {
        self.phase = phase
        self.showHUD = showHUD
    }

    public var body: some View {
        Canvas(opaque: true, colorMode: .nonLinear, rendersAsynchronously: false) { context, size in
            if size.width <= 8 || size.height <= 8 { return }
            let frame = PourPartyClip.frame(at: phase, showHUD: showHUD)
            PourPartyPainter(layout: PourPartyLayout(size: size, count: frame.tubes.count)).draw(&context, frame)
        }
    }
}

// MARK: - Numbers

enum PourPartyMath {
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

    /// Overshoots a little before it settles on 1.
    static func outBack(_ v: Double) -> Double {
        let x = clamp(v) - 1
        let spring = 1.7
        return 1 + (spring + 1) * x * x * x + spring * x * x
    }

    /// How much of a pour has left the tube at one point of the pour animation (0...1): nothing
    /// while the tube travels over the target, all of it before the tube travels back.
    static func pourShare(_ t: Double) -> Double { clamp((t - 0.22) / 0.56) }

    /// How far the pouring tube is from its slot: 0 at rest, 1 while it hangs over the target.
    static func pourReach(_ t: Double) -> Double { smooth(0, 0.22, t) - smooth(0.78, 1, t) }
}

/// SplitMix64. The scenery and the round use different salts so they never share a sequence.
struct PourPartyRandom {
    static let scenery: UInt64 = 0xD1B54A32D192ED03
    static let round: UInt64 = 0x2545F4914F6CDD1D

    private var state: UInt64

    init(seed: UInt64, salt: UInt64 = PourPartyRandom.round) {
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

    /// 0 ..< count
    mutating func int(_ count: Int) -> Int {
        count <= 1 ? 0 : Swift.min(count - 1, Int(next() * Double(count)))
    }
}

// MARK: - Colour

enum PourPartyInk {
    static func hex(_ value: UInt32, _ alpha: Double = 1) -> Color {
        Color(.sRGB, red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255,
              blue: Double(value & 255) / 255, opacity: alpha)
    }

    /// The colour moved towards white (k > 0) or towards black (k < 0).
    static func shade(_ value: UInt32, _ k: Double) -> Color {
        let r = Double((value >> 16) & 255) / 255
        let g = Double((value >> 8) & 255) / 255
        let b = Double(value & 255) / 255
        if k >= 0 {
            return Color(.sRGB, red: r + (1 - r) * k, green: g + (1 - g) * k, blue: b + (1 - b) * k, opacity: 1)
        }
        return Color(.sRGB, red: r * (1 + k), green: g * (1 + k), blue: b * (1 + k), opacity: 1)
    }

    static let night = hex(0x18171D)
    static let nightDeep = hex(0x0E0D12)
    static let gold = hex(0xF5B301)
    static let ribbon = hex(0xE8445A)

    /// The liquids, flat and bright. A level uses the first few.
    static let liquidHex: [UInt32] = [0xFF4D5E, 0xFF9A3D, 0xFFD93D, 0x7BDB3F, 0x1FC98F, 0x3D8BFF, 0xA25BFF, 0xFF6BC0]
    static let liquid: [Color] = liquidHex.map { hex($0) }
    static let liquidLight: [Color] = liquidHex.map { shade($0, 0.42) }

    static func color(_ index: Int) -> Color {
        liquid[((index % liquid.count) + liquid.count) % liquid.count]
    }

    static func light(_ index: Int) -> Color {
        liquidLight[((index % liquidLight.count) + liquidLight.count) % liquidLight.count]
    }
}

// MARK: - What a frame shows

/// A run of one colour inside a tube, in units. A full tube holds 4 units.
struct PourPartyBand {
    var color: Int
    var units: Double
}

/// One pour on its way: the tube moves over the target, tips, and comes back.
struct PourPartyPourPose {
    var from: Int
    var to: Int
    var color: Int
    var units: Int
    /// 0 at the start of the animation, 1 when the tube is back in its slot.
    var progress: Double
}

struct PourPartyFloat {
    var text: String
    /// The tube it rises from. -1: it rises from the score.
    var tube: Int
    var age: Double
}

enum PourPartyBanner {
    case solved
    case timeUp
}

/// Everything the painter needs for one frame. The playable game fills one from its model each
/// frame; the clip fills one from its script.
struct PourPartyFrame {
    /// Each tube's colours from the bottom up, as the frame should show them.
    var tubes: [[PourPartyBand]] = []
    var lifted: Int?
    /// 0...1: how far the lifted tube has risen.
    var lift: Double = 1
    var pours: [PourPartyPourPose] = []
    var shaking: Int?
    var shakeAge: Double = 0
    var popped: Int?
    var popAge: Double = 10
    /// 0...1: the tubes of a new level arriving.
    var levelIn: Double = 1
    var level: Int = 1
    var score: Int = 0
    var best: Int = 0
    /// Seconds left in the round.
    var clock: Double = 120
    var undos: Int = 3
    var canRestart: Bool = true
    var banner: PourPartyBanner?
    var bannerAge: Double = 0
    var bannerLength: Double = 1.7
    var confettiAge: Double?
    var floats: [PourPartyFloat] = []
    var hint: String?
    var hintAlpha: Double = 0
    /// 0...1: the board darkened when the round is over.
    var dim: Double = 0
    var showHUD: Bool = true
}

/// Turns the logical tubes into the bands a frame shows, with the pours in flight taken into account:
/// what is still leaving the source is drawn in the source, and not yet in the target.
enum PourPartyPoses {
    static func build(tubes: [[Int]], pours: [PourPartyPourPose], into poses: inout [[PourPartyBand]]) {
        if poses.count != tubes.count {
            poses = Array(repeating: [], count: tubes.count)
            for k in poses.indices { poses[k].reserveCapacity(6) }
        }
        for i in tubes.indices {
            poses[i].removeAll(keepingCapacity: true)
            for color in tubes[i] {
                let last = poses[i].count - 1
                if last >= 0, poses[i][last].color == color {
                    poses[i][last].units += 1
                } else {
                    poses[i].append(PourPartyBand(color: color, units: 1))
                }
            }
        }
        for pour in pours {
            let moving = Double(pour.units) * (1 - PourPartyMath.pourShare(pour.progress))
            if moving <= 0.0005 { continue }
            if pour.from >= 0, pour.from < poses.count {
                let last = poses[pour.from].count - 1
                if last >= 0, poses[pour.from][last].color == pour.color {
                    poses[pour.from][last].units += moving
                } else {
                    poses[pour.from].append(PourPartyBand(color: pour.color, units: moving))
                }
            }
            if pour.to >= 0, pour.to < poses.count {
                let last = poses[pour.to].count - 1
                if last >= 0 {
                    poses[pour.to][last].units -= moving
                    if poses[pour.to][last].units <= 0.0005 { poses[pour.to].removeLast() }
                }
            }
        }
    }
}

// MARK: - Layout

/// Where everything sits on a screen of a given size, for a given number of tubes.
struct PourPartyLayout {
    let W: CGFloat
    let H: CGFloat
    /// One design point. The design is 402 wide and 874 tall.
    let u: CGFloat
    let tubeW: CGFloat
    let tubeH: CGFloat
    /// Glass thickness.
    let inset: CGFloat
    /// Height of one unit of liquid.
    let unitH: CGFloat
    /// How far a lifted tube rises.
    let lift: CGFloat
    /// Each tube's slot, at rest.
    let rects: [CGRect]
    let restart: CGRect
    let undo: CGRect
    let hintY: CGFloat
    let scoreY: CGFloat
    /// Touches above this line belong to the top row, below it to the bottom row.
    let rowSplit: CGFloat

    init(size: CGSize, count: Int) {
        W = size.width
        H = size.height
        let u = Swift.min(W / 402, H / 874)
        self.u = u
        let tubeW: CGFloat = 54 * u
        let tubeH: CGFloat = 168 * u
        let inset: CGFloat = 3.5 * u
        self.tubeW = tubeW
        self.tubeH = tubeH
        self.inset = inset
        unitH = (tubeH - inset * 2 - 8 * u) / 4
        lift = 24 * u

        let gap = 18 * u
        let first = count <= 5 ? count : (count + 1) / 2
        let second = count - first
        let rowYs: [CGFloat] = second == 0 ? [H * 0.5] : [H * 0.375, H * 0.625]
        var slots: [CGRect] = []
        slots.reserveCapacity(count)
        for (row, n) in [first, second].enumerated() where n > 0 {
            let width: CGFloat = CGFloat(n) * tubeW + CGFloat(n - 1) * gap
            let left: CGFloat = (W - width) / 2
            for k in 0..<n {
                let x: CGFloat = left + CGFloat(k) * (tubeW + gap)
                slots.append(CGRect(x: x, y: rowYs[row] - tubeH / 2, width: tubeW, height: tubeH))
            }
        }
        rects = slots
        if second == 0 {
            rowSplit = CGFloat.greatestFiniteMagnitude
        } else {
            let topBottom: CGFloat = rowYs[0] + tubeH / 2
            let lowTop: CGFloat = rowYs[1] - tubeH / 2 - 24 * u
            rowSplit = (topBottom + lowTop) / 2
        }

        let buttonY = H - GameLayout.bottomInset - 30 * u
        restart = CGRect(x: W / 2 - 152 * u, y: buttonY - 26 * u, width: 140 * u, height: 52 * u)
        undo = CGRect(x: W / 2 + 12 * u, y: buttonY - 26 * u, width: 140 * u, height: 52 * u)
        hintY = buttonY - 72 * u
        scoreY = GameLayout.topBand + 30 * u
    }

    /// The tube under a touch, if any. A lifted tube is still hit above its slot. The two rows'
    /// areas meet at rowSplit and never overlap.
    func tube(at point: CGPoint) -> Int? {
        var best: Int?
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for (i, r) in rects.enumerated() {
            var top: CGFloat = r.minY - lift - 16 * u
            var bottom: CGFloat = r.maxY + 8 * u
            if r.midY < rowSplit {
                bottom = Swift.min(bottom, rowSplit)
            } else {
                top = Swift.max(top, rowSplit)
            }
            if point.y < top || point.y > bottom { continue }
            if point.x < r.minX - 9 * u || point.x > r.maxX + 9 * u { continue }
            let distance = abs(point.x - r.midX)
            if distance < bestDistance {
                bestDistance = distance
                best = i
            }
        }
        return best
    }
}

// MARK: - Shapes

enum PourPartyShapes {
    /// A test tube: straight sides, open top, round bottom.
    static func tube(x0: CGFloat, y0: CGFloat, width w: CGFloat, height h: CGFloat) -> Path {
        let r = w / 2
        let k: CGFloat = 0.5523
        let cx = x0 + r
        let cy = y0 + h - r
        var p = Path()
        p.move(to: CGPoint(x: x0, y: y0))
        p.addLine(to: CGPoint(x: x0, y: cy))
        p.addCurve(to: CGPoint(x: cx, y: cy + r), control1: CGPoint(x: x0, y: cy + k * r), control2: CGPoint(x: cx - k * r, y: cy + r))
        p.addCurve(to: CGPoint(x: x0 + w, y: cy), control1: CGPoint(x: cx + k * r, y: cy + r), control2: CGPoint(x: x0 + w, y: cy + k * r))
        p.addLine(to: CGPoint(x: x0 + w, y: y0))
        p.closeSubpath()
        return p
    }

    static func polygon(_ points: [CGPoint]) -> Path {
        var p = Path()
        p.addLines(points)
        p.closeSubpath()
        return p
    }
}

/// One piece of confetti: where it starts across the screen and how it flies.
struct PourPartyConfetto {
    var x: Double
    var vx: Double
    var vy: Double
    var color: Int
    var spin: Double
    var size: Double
}

/// The painted pictures, looked up once per frame.
struct PourPartyArt {
    let backdrop: GraphicsContext.ResolvedImage
    let tube: GraphicsContext.ResolvedImage
    let ribbon: GraphicsContext.ResolvedImage
    let ribbonGrey: GraphicsContext.ResolvedImage
    let crown: GraphicsContext.ResolvedImage

    /// The tube picture is this much wider than the glass, for the rim.
    static let tubeRim: CGFloat = 1.19
    /// The tube picture's height over its width.
    static let tubeAspect: CGFloat = 2.68
    /// The ribbon picture's height over its width, and where the middle of its front sits, from the top.
    static let ribbonAspect: CGFloat = 0.297
    static let ribbonMid: CGFloat = 0.4
    /// The crown picture's height over its width.
    static let crownAspect: CGFloat = 0.99

    init(_ ctx: GraphicsContext) {
        backdrop = ctx.resolve(Image("pour-party-backdrop"))
        tube = ctx.resolve(Image("pour-party-tube"))
        ribbon = ctx.resolve(Image("pour-party-ribbon"))
        ribbonGrey = ctx.resolve(Image("pour-party-ribbon-grey"))
        crown = ctx.resolve(Image("pour-party-crown"))
    }
}

// MARK: - Painter

struct PourPartyPainter {
    typealias M = PourPartyMath

    let L: PourPartyLayout
    let W: CGFloat
    let H: CGFloat
    let u: CGFloat

    init(layout: PourPartyLayout) {
        L = layout
        W = layout.W
        H = layout.H
        u = layout.u
    }

    static let confetti: [PourPartyConfetto] = {
        var rng = PourPartyRandom(seed: 99, salt: PourPartyRandom.scenery)
        var list: [PourPartyConfetto] = []
        for _ in 0..<72 {
            list.append(PourPartyConfetto(x: rng.range(0.08, 0.92), vx: rng.range(-110, 110), vy: rng.range(-300, -60),
                                          color: rng.int(8), spin: rng.range(-7, 7), size: rng.range(5, 9)))
        }
        return list
    }()

    func draw(_ ctx: inout GraphicsContext, _ f: PourPartyFrame) {
        let art = PourPartyArt(ctx)
        drawBackground(&ctx, art)
        if f.showHUD {
            drawHUD(&ctx, f)
            drawButtons(&ctx, f)
        }
        // Tubes in their slots first, then the ones in the air, so a pouring tube passes over the rest.
        for i in f.tubes.indices where !isAirborne(i, f) {
            drawResting(&ctx, index: i, f, art)
        }
        for pour in f.pours where M.pourReach(pour.progress) > 0.001 {
            drawPouring(&ctx, pour, f, art)
        }
        if f.dim > 0.01 {
            ctx.fill(Path(CGRect(x: 0, y: 0, width: W, height: H)), with: .color(PourPartyInk.nightDeep.opacity(0.5 * f.dim)))
        }
        drawFloats(&ctx, f)
        if let age = f.confettiAge { drawConfetti(&ctx, age: age) }
        if let banner = f.banner { drawBanner(&ctx, banner, age: f.bannerAge, length: f.bannerLength, art) }
        if let hint = f.hint, f.hintAlpha > 0.01, f.showHUD { drawHint(&ctx, hint, alpha: f.hintAlpha) }
    }

    private func isAirborne(_ i: Int, _ f: PourPartyFrame) -> Bool {
        for pour in f.pours where pour.from == i && M.pourReach(pour.progress) > 0.001 { return true }
        return false
    }

    // MARK: Background

    private func drawBackground(_ ctx: inout GraphicsContext, _ art: PourPartyArt) {
        ctx.fill(Path(CGRect(x: 0, y: 0, width: W, height: H)), with: .color(PourPartyInk.night))
        let size = art.backdrop.size
        if size.width < 1 || size.height < 1 { return }
        let k = Swift.max(W / size.width, H / size.height)
        let w = size.width * k
        let h = size.height * k
        ctx.draw(art.backdrop, in: CGRect(x: (W - w) / 2, y: (H - h) / 2, width: w, height: h))
    }

    // MARK: HUD

    static func grouped(_ n: Int) -> String {
        let digits = Array(String(Swift.max(0, n)))
        var out = ""
        for (k, ch) in digits.enumerated() {
            if k > 0, (digits.count - k) % 3 == 0 { out.append(",") }
            out.append(ch)
        }
        return out
    }

    static func clockText(_ seconds: Double) -> String {
        let whole = Int(Swift.max(0, seconds).rounded(.up))
        let rest = whole % 60
        return "\(whole / 60):" + (rest < 10 ? "0\(rest)" : "\(rest)")
    }

    private func drawHUD(_ ctx: inout GraphicsContext, _ f: PourPartyFrame) {
        let x = W / 2
        let shadow = PourPartyInk.nightDeep.opacity(0.6)
        let level = Text("LEVEL \(f.level)").font(.system(size: 15 * u, weight: .heavy, design: .rounded)).kerning(1.6 * u)
        ctx.draw(level.foregroundColor(shadow), at: CGPoint(x: x, y: GameLayout.statusBarHeight + 16 * u + 1.5 * u), anchor: .center)
        ctx.draw(level.foregroundColor(Color.white.opacity(0.92)), at: CGPoint(x: x, y: GameLayout.statusBarHeight + 16 * u), anchor: .center)

        let late = f.clock <= 10.5 && f.dim < 0.01
        let pulse = late ? 0.5 + 0.5 * sin(f.clock * 6.28) : 0
        let clockColor = late ? PourPartyInk.ribbon.opacity(0.75 + 0.25 * pulse) : Color.white.opacity(0.62)
        let clock = Text(Self.clockText(f.clock)).font(.system(size: CGFloat(13.5 + 2 * pulse) * u, weight: .bold, design: .rounded)).kerning(0.8 * u)
        ctx.draw(clock.foregroundColor(clockColor), at: CGPoint(x: x, y: GameLayout.statusBarHeight + 36 * u), anchor: .center)

        let score = Text(Self.grouped(f.score)).font(.system(size: 38 * u, weight: .heavy, design: .rounded))
        ctx.draw(score.foregroundColor(shadow), at: CGPoint(x: x, y: L.scoreY + 2.5 * u), anchor: .center)
        ctx.draw(score.foregroundColor(.white), at: CGPoint(x: x, y: L.scoreY), anchor: .center)
        if f.best > 0 {
            let best = Text("BEST \(Self.grouped(Swift.max(f.best, f.score)))").font(.system(size: 12 * u, weight: .bold, design: .rounded)).kerning(1.8 * u)
            ctx.draw(best.foregroundColor(Color.white.opacity(0.45)), at: CGPoint(x: x, y: L.scoreY + 28 * u), anchor: .center)
        }
    }

    private func drawButtons(_ ctx: inout GraphicsContext, _ f: PourPartyFrame) {
        drawButton(&ctx, L.restart, "Restart", enabled: f.canRestart)
        drawButton(&ctx, L.undo, "Undo", enabled: f.undos > 0)
        for k in 0..<3 {
            let cx = L.undo.midX + 26 * u + CGFloat(k) * 10 * u
            let dot = Path(ellipseIn: CGRect(x: cx - 3 * u, y: L.undo.midY - 3 * u, width: 6 * u, height: 6 * u))
            ctx.fill(dot, with: .color(Color.white.opacity(k < f.undos ? 0.9 : 0.2)))
        }
    }

    private func drawButton(_ ctx: inout GraphicsContext, _ rect: CGRect, _ label: String, enabled: Bool) {
        let pill = Path(roundedRect: rect, cornerRadius: rect.height / 2)
        ctx.fill(pill, with: .color(Color.white.opacity(enabled ? 0.11 : 0.05)))
        ctx.stroke(pill, with: .color(Color.white.opacity(enabled ? 0.28 : 0.12)), lineWidth: Swift.max(1, 1.5 * u))
        let text = Text(label).font(.system(size: 17 * u, weight: .bold, design: .rounded))
        let dx: CGFloat = label == "Undo" ? -14 * u : 0
        ctx.draw(text.foregroundColor(Color.white.opacity(enabled ? 0.95 : 0.4)), at: CGPoint(x: rect.midX + dx, y: rect.midY), anchor: .center)
    }

    private func drawHint(_ ctx: inout GraphicsContext, _ words: String, alpha: Double) {
        let text = Text(words).font(.system(size: 17 * u, weight: .semibold, design: .rounded)).kerning(0.3 * u)
        ctx.draw(text.foregroundColor(PourPartyInk.nightDeep.opacity(0.5 * alpha)), at: CGPoint(x: W / 2, y: L.hintY + 1.5 * u), anchor: .center)
        ctx.draw(text.foregroundColor(Color.white.opacity(0.8 * alpha)), at: CGPoint(x: W / 2, y: L.hintY), anchor: .center)
    }

    // MARK: Tubes

    private func drawResting(_ ctx: inout GraphicsContext, index i: Int, _ f: PourPartyFrame, _ art: PourPartyArt) {
        let rect = L.rects[i]
        var scale = CGFloat(0.7 + 0.3 * M.outBack(f.levelIn))
        let alpha = M.clamp(f.levelIn * 1.6)
        var dx: CGFloat = 0
        var dy: CGFloat = 0
        var glow = 0.0
        if f.lifted == i {
            let rise = M.outBack(f.lift)
            dy = -L.lift * CGFloat(rise)
            glow = M.clamp(f.lift)
        }
        if f.shaking == i, f.shakeAge < 0.4 {
            dx = CGFloat(sin(f.shakeAge * 42) * (1 - f.shakeAge / 0.4)) * 5 * u
        }
        if f.popped == i, f.popAge < 0.32 {
            scale *= 1 + CGFloat(0.12 * sin(Double.pi * M.clamp(f.popAge / 0.32)))
        }
        drawGlass(&ctx, bands: f.tubes[i], center: CGPoint(x: rect.midX + dx, y: rect.midY + dy),
                  angle: 0, side: 0, scale: scale, alpha: alpha, glow: glow, art: art)
    }

    /// How far a pouring tube tips: a little as it arrives, more as it empties.
    static let tiltStart = 0.6
    static let tiltEnd = 0.9
    /// How far the lowest point of a pouring tube reaches below the target's rim, in design points.
    /// The lip rises or falls with the tilt to keep it there, so the tube hangs above its neighbours.
    static let hangDepth: CGFloat = 52

    /// Where the pouring tube is right now, and the point the liquid leaves it. Over the target the
    /// tube turns about its lip, so the stream stays put while it tips.
    private func pourPose(_ p: PourPartyPourPose) -> (center: CGPoint, angle: Double, side: Double, lip: CGPoint) {
        let rest = L.rects[p.from]
        let target = L.rects[p.to]
        let w = Double(L.tubeW)
        let h = Double(L.tubeH)
        let tilt = M.lerp(Self.tiltStart, Self.tiltEnd, M.smooth(0, 1, M.pourShare(p.progress)))
        func spot(_ side: Double, _ amount: Double) -> (center: CGPoint, lip: CGPoint) {
            let theta = -side * amount
            let lx = -side * w / 2
            let ly = -h / 2
            let rx = lx * cos(theta) - ly * sin(theta)
            let ry = lx * sin(theta) + ly * cos(theta)
            let lowest = -ry + (h / 2 - w / 2) * cos(amount) + w / 2
            let lipY = Double(target.minY + Self.hangDepth * u) - lowest
            let lip = CGPoint(x: target.midX + CGFloat(side) * 4 * u, y: CGFloat(lipY))
            return (CGPoint(x: lip.x - CGFloat(rx), y: lip.y - CGFloat(ry)), lip)
        }
        var side: Double
        if rest.midX > target.midX + 1 {
            side = 1
        } else if rest.midX < target.midX - 1 {
            side = -1
        } else {
            side = target.midX < W / 2 ? 1 : -1
        }
        // At its steepest the tube reaches this far sideways from its centre: keep it on the screen.
        let reachOut = CGFloat((h / 2 - w / 2) * sin(Self.tiltEnd) + w / 2)
        let steep = spot(side, Self.tiltEnd).center.x
        if steep - reachOut < 0 || steep + reachOut > W {
            let other = spot(-side, Self.tiltEnd).center.x
            if other - reachOut >= 0 && other + reachOut <= W { side = -side }
        }
        let s = spot(side, tilt)
        let reach = M.pourReach(p.progress)
        let fromX = Double(rest.midX)
        let fromY = Double(rest.midY - L.lift)
        let x = M.lerp(fromX, Double(s.center.x), reach)
        let y = M.lerp(fromY, Double(s.center.y), reach) - sin(Double.pi * reach) * 10 * Double(u)
        return (CGPoint(x: x, y: y), -side * tilt * reach, side, s.lip)
    }

    private func drawPouring(_ ctx: inout GraphicsContext, _ p: PourPartyPourPose, _ f: PourPartyFrame, _ art: PourPartyArt) {
        let pose = pourPose(p)
        let share = M.pourShare(p.progress)
        if share > 0, share < 1 {
            let target = L.rects[p.to]
            var fill = 0.0
            for band in f.tubes[p.to] { fill += band.units }
            let surface = target.maxY - L.inset - CGFloat(fill) * L.unitH
            let alpha = M.smooth(0, 0.08, share) * (1 - M.smooth(0.9, 1, share))
            let top = pose.lip.y
            if surface > top + 2 {
                let width = 6 * u
                let stream = Path(roundedRect: CGRect(x: pose.lip.x - width / 2, y: top - 2 * u, width: width, height: surface - top + 3 * u), cornerRadius: width / 2)
                ctx.fill(stream, with: .color(PourPartyInk.color(p.color).opacity(alpha)))
                let shine = Path(roundedRect: CGRect(x: pose.lip.x - width / 2 + 1.2 * u, y: top + 4 * u, width: 1.6 * u, height: Swift.max(0, surface - top - 10 * u)), cornerRadius: u)
                ctx.fill(shine, with: .color(Color.white.opacity(0.35 * alpha)))
                let splash = Path(ellipseIn: CGRect(x: pose.lip.x - 9 * u, y: surface - 2.5 * u, width: 18 * u, height: 5 * u))
                ctx.fill(splash, with: .color(PourPartyInk.light(p.color).opacity(0.7 * alpha)))
            }
        }
        drawGlass(&ctx, bands: f.tubes[p.from], center: pose.center, angle: pose.angle, side: pose.side,
                  scale: 1, alpha: 1, glow: 0.6 * M.pourReach(p.progress), art: art)
    }

    /// One tube with its liquid, drawn in its own frame: the centre of the glass is the origin.
    /// Liquid keeps a level surface in the world, so inside a tipped tube it slopes towards the lip.
    private func drawGlass(_ ctx: inout GraphicsContext, bands: [PourPartyBand], center: CGPoint, angle: Double,
                           side: Double, scale: CGFloat, alpha: Double, glow: Double, art: PourPartyArt) {
        if alpha <= 0.01 { return }
        var g = ctx
        g.translateBy(x: center.x, y: center.y)
        g.rotate(by: .radians(angle))
        g.scaleBy(x: scale, y: scale)
        g.opacity = alpha

        let w = L.tubeW
        let h = L.tubeH
        let inset = L.inset
        let glass = PourPartyShapes.tube(x0: -w / 2, y0: -h / 2, width: w, height: h)
        let inner = PourPartyShapes.tube(x0: -w / 2 + inset, y0: -h / 2, width: w - 2 * inset, height: h - inset)

        var liquid = g
        liquid.clip(to: inner)
        let base = h / 2 - inset
        // The surfaces stay level in the world, so inside the tipped tube they slope by the full angle.
        let slope = CGFloat(side * tan(Swift.min(abs(angle), 1.2)))
        let hx = w / 2 - inset
        var level: CGFloat = 0
        for (k, band) in bands.enumerated() {
            let lo: CGFloat = k == 0 ? -3 : level
            let hi = level + CGFloat(band.units)
            let yLo: CGFloat = base - lo * L.unitH
            let yHi: CGFloat = base - hi * L.unitH
            let tilt: CGFloat = slope * hx
            let a = CGPoint(x: -hx, y: yLo - tilt)
            let b = CGPoint(x: hx, y: yLo + tilt)
            let c = CGPoint(x: hx, y: yHi + tilt)
            let d = CGPoint(x: -hx, y: yHi - tilt)
            liquid.fill(PourPartyShapes.polygon([a, b, c, d]), with: .color(PourPartyInk.color(band.color)))
            if k == bands.count - 1 {
                var top = Path()
                top.move(to: d)
                top.addLine(to: c)
                liquid.stroke(top, with: .color(PourPartyInk.light(band.color).opacity(0.85)), lineWidth: 2.4 * u)
            }
            level = hi
        }

        let picW = w * PourPartyArt.tubeRim
        let picH = picW * PourPartyArt.tubeAspect
        g.draw(art.tube, in: CGRect(x: -picW / 2, y: h / 2 - picH, width: picW, height: picH))
        if glow > 0.01 {
            g.stroke(glass, with: .color(Color.white.opacity(0.6 * glow)), lineWidth: 2.2 * CGFloat(glow) * u)
        }
    }

    // MARK: Moments

    private func drawFloats(_ ctx: inout GraphicsContext, _ f: PourPartyFrame) {
        for item in f.floats {
            let k = M.clamp(item.age / 1.1)
            let alpha = M.clamp(item.age / 0.1) * (1 - M.smooth(0.6, 1, k))
            if alpha <= 0.01 { continue }
            var x = W / 2
            var y = L.scoreY + 42 * u
            if item.tube >= 0, item.tube < L.rects.count {
                x = L.rects[item.tube].midX
                y = L.rects[item.tube].minY - 14 * u
            }
            y -= CGFloat(M.easeOut(k)) * 44 * u
            let size = CGFloat(22 + 6 * M.outBack(M.clamp(item.age / 0.3))) * u
            let text = Text(item.text).font(.system(size: size, weight: .heavy, design: .rounded))
            ctx.draw(text.foregroundColor(PourPartyInk.nightDeep.opacity(0.6 * alpha)), at: CGPoint(x: x, y: y + 2 * u), anchor: .center)
            ctx.draw(text.foregroundColor(PourPartyInk.gold.opacity(alpha)), at: CGPoint(x: x, y: y), anchor: .center)
        }
    }

    private func drawConfetti(_ ctx: inout GraphicsContext, age: Double) {
        if age <= 0 || age > 2.2 { return }
        let alpha = 1 - M.smooth(1.5, 2.2, age)
        let originY = H * 0.3
        let gravity = 420.0
        for c in Self.confetti {
            let x = CGFloat(c.x) * W + CGFloat(c.vx * age) * u
            let y = originY + CGFloat(c.vy * age + 0.5 * gravity * age * age) * u
            if y > H + 10 { continue }
            var g = ctx
            g.translateBy(x: x, y: y)
            g.rotate(by: .radians(c.spin * age))
            let s = CGFloat(c.size) * u
            g.fill(Path(roundedRect: CGRect(x: -s / 2, y: -s / 4, width: s, height: s / 2), cornerRadius: u),
                   with: .color(PourPartyInk.color(c.color).opacity(alpha)))
        }
    }

    private func drawBanner(_ ctx: inout GraphicsContext, _ kind: PourPartyBanner, age: Double, length: Double, _ art: PourPartyArt) {
        let pop = M.outBack(M.clamp(age / 0.38))
        let alpha = M.clamp(age / 0.12) * (1 - M.smooth(length - 0.3, length, age))
        if alpha <= 0.01 || pop <= 0.01 { return }
        let cx = W / 2
        let cy = H * 0.3
        var g = ctx
        g.translateBy(x: cx, y: cy)
        g.scaleBy(x: CGFloat(pop), y: CGFloat(pop))
        g.opacity = alpha

        let h = 66 * u
        let words = kind == .solved ? "Solved" : "Time is up"
        let ribbon = kind == .solved ? art.ribbon : art.ribbonGrey
        let ribbonW = 320 * u
        let ribbonH = ribbonW * PourPartyArt.ribbonAspect
        g.draw(ribbon, in: CGRect(x: -ribbonW / 2, y: -ribbonH * PourPartyArt.ribbonMid, width: ribbonW, height: ribbonH))
        let text = Text(words).font(.system(size: 32 * u, weight: .heavy, design: .rounded)).kerning(1.5 * u)
        g.draw(text.foregroundColor(PourPartyInk.nightDeep.opacity(0.35)), at: CGPoint(x: 0, y: 2 * u), anchor: .center)
        g.draw(text.foregroundColor(.white), at: CGPoint(x: 0, y: 0), anchor: .center)

        if kind == .solved {
            let crownW = 76 * u
            let crownH = crownW * PourPartyArt.crownAspect
            g.draw(art.crown, in: CGRect(x: -crownW / 2, y: -h / 2 + 2 * u - crownH, width: crownW, height: crownH))
        }
    }
}

// MARK: - The clip

/// The fixed story the video feed and the covers show: a level a few pours from solved, then solved.
enum PourPartyClip {
    /// A busy board: 5 colours in 7 tubes, bottom to top.
    static let busy: [[Int]] = [[0, 3, 3], [2, 0, 0, 1], [4, 4, 2, 2], [1, 3, 1], [3, 4, 4], [0, 2, 1], []]
    /// Two pours from solved: yellow-green from tube 1 onto tube 4, then pink-red from tube 5 into tube 1.
    static let nearlyDone: [[Int]] = [[0, 0, 0, 0], [1, 1, 4, 4], [2, 2, 2, 2], [3, 3, 3, 3], [4, 4], [1, 1], []]
    static let done: [[Int]] = [[0, 0, 0, 0], [1, 1, 1, 1], [2, 2, 2, 2], [3, 3, 3, 3], [4, 4, 4, 4], [], []]

    static func frame(at phase: Double, showHUD: Bool) -> PourPartyFrame {
        typealias M = PourPartyMath
        var f = PourPartyFrame()
        f.showHUD = showHUD
        f.level = 6
        f.best = 2100
        f.undos = 2
        var poses: [[PourPartyBand]] = []

        if phase < 0.5 {
            f.score = 1500
            f.clock = 74 - phase * 12
            var tubes = busy
            var pours: [PourPartyPourPose] = []
            if phase >= 0.24 {
                // One unit of the pink-red colour goes from tube 5 onto tube 3.
                let t = M.clamp((phase - 0.24) / 0.2)
                tubes[3].append(1)
                tubes[5].removeLast()
                pours.append(PourPartyPourPose(from: 5, to: 3, color: 1, units: 1, progress: t))
            } else if phase >= 0.14 {
                f.lifted = 5
                f.lift = M.clamp((phase - 0.14) / 0.04)
            }
            PourPartyPoses.build(tubes: tubes, pours: pours, into: &poses)
            f.pours = pours
        } else if phase < 0.79 {
            f.score = 1500
            f.clock = 70 - (phase - 0.5) * 12
            var tubes = nearlyDone
            var pours: [PourPartyPourPose] = []
            tubes[4].append(4)
            tubes[4].append(4)
            tubes[1].removeLast(2)
            if phase >= 0.665 {
                // Then the last two units of the pink-red colour go from tube 5 into tube 1.
                let t = M.clamp((phase - 0.665) / 0.125)
                tubes[1].append(1)
                tubes[1].append(1)
                tubes[5].removeAll()
                pours.append(PourPartyPourPose(from: 5, to: 1, color: 1, units: 2, progress: t))
                f.popped = 4
                f.popAge = (phase - 0.665) * 8
            } else if phase >= 0.54 {
                // The two yellow-green units go from tube 1 onto tube 4.
                let t = M.clamp((phase - 0.54) / 0.125)
                pours.append(PourPartyPourPose(from: 1, to: 4, color: 4, units: 2, progress: t))
            } else {
                tubes = nearlyDone
                f.lifted = 1
                f.lift = M.clamp((phase - 0.5) / 0.04)
            }
            PourPartyPoses.build(tubes: tubes, pours: pours, into: &poses)
            f.pours = pours
        } else {
            let age = (phase - 0.79) * 6
            f.score = 1500 + Int(600 * M.clamp(age / 0.4))
            f.clock = 67
            f.banner = .solved
            f.bannerAge = age
            f.bannerLength = 10
            f.confettiAge = age
            f.popped = 1
            f.popAge = age
            if age < 1.1 { f.floats = [PourPartyFloat(text: "+600", tube: -1, age: age)] }
            PourPartyPoses.build(tubes: done, pours: [], into: &poses)
        }
        f.tubes = poses
        return f
    }
}
