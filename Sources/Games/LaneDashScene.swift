import SwiftUI

// MARK: - Lane Dash, the picture
//
// A three-lane runner on a causeway over the sea at dusk. Every pixel is drawn in code.
//
// LaneDashFrame says what one frame shows. LaneDashPainter draws it. The feed clip fills a frame
// from phase (one seamless loop, below); the playable game in LaneDashGame.swift fills one from
// its live round and adds the things only a real round has (gates, the crash, the hint).
//
// The clip loop, by phase:
//   0.06 to 0.12   swerve left into a row of gems
//   0.43 to 0.51   late dodge back to the centre, with a near miss at about 0.5
//   0.79 to 0.93   ramp, boost and a flight over a hurdle, top of the arc at about 0.86

public struct LaneDashScene: View {
    public var phase: Double
    public var showHUD: Bool

    public init(phase: Double, showHUD: Bool) {
        self.phase = phase
        self.showHUD = showHUD
    }

    public var body: some View {
        Canvas(opaque: true, rendersAsynchronously: false) { context, size in
            guard size.width > 8, size.height > 8 else { return }
            let painter = LaneDashPainter(size: size, frame: .clip(phase: phase), showHUD: showHUD)
            painter.backdrop(context)
            painter.front(context)
        }
    }
}

// MARK: - Fixed scatter

/// Xorshift numbers for scenery that must sit in the same place on every frame.
struct LaneDashScatter {
    private var bits: UInt64

    init(_ seed: UInt64) {
        bits = (seed &+ 1) &* 0x9E37_79B9_7F4A_7C15
        if bits == 0 { bits = 0xDEAD_BEEF }
        _ = unit()
        _ = unit()
    }

    /// 0 ..< 1
    mutating func unit() -> CGFloat {
        bits ^= bits << 13
        bits ^= bits >> 7
        bits ^= bits << 17
        return CGFloat(bits >> 11) / 9_007_199_254_740_992
    }

    mutating func between(_ low: CGFloat, _ high: CGFloat) -> CGFloat {
        low + (high - low) * unit()
    }
}

// MARK: - Projection

/// One-point perspective. Depth 1 is where the kart sits; the horizon is depth infinity.
struct LaneDashLens {
    let unit: CGFloat       // 1 on a phone 402 points wide
    let centreX: CGFloat
    let horizonY: CGFloat
    let kartY: CGFloat      // where the road meets the kart's depth
    let eyeX: CGFloat       // the camera follows the kart a little

    private func nearness(_ depth: CGFloat) -> CGFloat { 1 / max(depth, 0.04) }

    func scale(_ depth: CGFloat) -> CGFloat { unit * nearness(depth) }

    func point(_ x: CGFloat, _ depth: CGFloat, up: CGFloat = 0) -> CGPoint {
        let k = nearness(depth)
        return CGPoint(x: centreX + (x - eyeX) * unit * k,
                       y: horizonY + (kartY - horizonY) * k - up * unit * k)
    }
}

// MARK: - What a frame shows

enum LaneDashPropKind {
    case barrier, cones, block, hurdle, ramp, gem
}

/// One thing on the road. depth is relative to the kart (1 = level with it).
struct LaneDashProp {
    var kind: LaneDashPropKind
    var lane: CGFloat
    var depth: CGFloat
    var lift: CGFloat = 0
    var seed: CGFloat = 0
    var wobble: CGFloat = 0
}

/// A named arch over the road. Only the game has these.
struct LaneDashGate {
    var depth: CGFloat
    var name: String
    var gold: Bool
}

struct LaneDashFrame {
    /// Cosmetic clock, in clip loops (1 = six seconds). Twinkles, lamps, flags, flames.
    var clock: CGFloat = 0
    /// Clock for the speed lines. It runs with the road, so they hurry when the kart does.
    var roadClock: CGFloat = 0
    /// Road travelled, in depth units.
    var scroll: CGFloat = 0

    var kartX: CGFloat = 0
    var lean: CGFloat = 0           // -1...1, into the lane change
    var height: CGFloat = 0         // above the road
    var climb: CGFloat = 0          // 1 rising, -1 falling
    var boost: CGFloat = 0          // 0...1
    var squash: CGFloat = 0         // 0...1 while landing
    var landRing: CGFloat = 0       // progress of the ring on the road, drawn while squash > 0
    var roll: CGFloat = 0           // extra roll in radians (the crash)
    var rush: CGFloat = 1           // how strong the speed lines and tyre dust are
    var shake: CGFloat = 0          // sideways camera nudge

    var props: [LaneDashProp] = []
    var pops: [(age: CGFloat, seed: CGFloat)] = []      // gem pickups, age 0...1

    var nearMiss: CGFloat? = nil    // progress 0...1
    var nearMissX: CGFloat = 0      // where the sparks fly, world x
    var nearMissTitle = "NEAR MISS"
    var nearMissNote = "+50"

    var flight: CGFloat? = nil      // progress 0...1 through a boosted jump
    var flightTitle = "BOOST"
    var flightNote = "x2"

    /// Where the kart was this many depth units of road ago.
    var wake: (CGFloat) -> (x: CGFloat, height: CGFloat) = { _ in (0, 0) }

    var distance = 0
    var gems = 0
    var pill: String? = nil         // second HUD pill; nil hides it
    var pillCool = false            // cyan instead of pink

    // The game only.
    var gates: [LaneDashGate] = []
    var crash: (age: CGFloat, x: CGFloat)? = nil        // seconds since the hit, world x of it
    var notice: (text: String, age: CGFloat)? = nil     // "Passed kaz", seconds on screen
    var hint: (text: String, alpha: CGFloat)? = nil
}

// MARK: - The clip

/// The scripted loop behind the feed clip.
enum LaneDashClip {
    static let roadPerLoop: CGFloat = 12
    static let laneWidth: CGFloat = 86

    struct Cue {
        var kind: LaneDashPropKind
        var lane: CGFloat
        var phase: CGFloat      // when it draws level with the kart
        var lift: CGFloat
        var seed: CGFloat
        var rocks = false       // the barrier the kart shaves past
    }

    static func ease(_ from: CGFloat, _ to: CGFloat, _ x: CGFloat) -> CGFloat {
        let t = min(max((x - from) / (to - from), 0), 1)
        return t * t * (3 - 2 * t)
    }

    static func wrap(_ x: CGFloat) -> CGFloat { x - x.rounded(.down) }

    /// The kart's lane: -1 left, 0 centre.
    static func lane(_ phase: CGFloat) -> CGFloat {
        let p = wrap(phase)
        return ease(0.432, 0.512, p) - ease(0.055, 0.115, p)
    }

    /// The kart's height above the road.
    static func height(_ phase: CGFloat) -> CGFloat {
        let s = (wrap(phase) - 0.795) / 0.14
        return s > 0 && s < 1 ? 82 * 4 * s * (1 - s) : 0
    }

    static let cues: [Cue] = {
        var list: [Cue] = []
        func put(_ kind: LaneDashPropKind, _ lane: CGFloat, _ phase: CGFloat, lift: CGFloat = 0, rocks: Bool = false) {
            list.append(Cue(kind: kind, lane: lane, phase: phase, lift: lift, seed: CGFloat(list.count), rocks: rocks))
        }

        let leftRow: [CGFloat] = [0.13, 0.17, 0.21, 0.25, 0.29, 0.33]
        let middleRow: [CGFloat] = [0.54, 0.58, 0.62, 0.66, 0.70]
        let arc: [CGFloat] = [0.82, 0.85, 0.88, 0.91]
        for at in leftRow { put(.gem, -1, at, lift: 25) }
        for at in middleRow { put(.gem, 0, at, lift: 25) }
        for at in arc { put(.gem, 0, at, lift: height(at) + 42) }
        put(.gem, 0, 0.985, lift: 25)
        put(.gem, 0, 0.025, lift: 25)

        put(.barrier, 1, 0.065)
        put(.cones, 0, 0.19)
        put(.block, 1, 0.26)
        put(.barrier, 0, 0.37)
        put(.cones, 1, 0.425)
        put(.barrier, -1, 0.49, rocks: true)
        put(.cones, 1, 0.585)
        put(.block, -1, 0.655)
        put(.barrier, -1, 0.775)
        put(.barrier, 1, 0.775)
        put(.ramp, 0, 0.782)
        put(.hurdle, 0, 0.868)
        put(.cones, -1, 0.93)
        put(.block, 1, 0.975)
        return list
    }()
}

extension LaneDashFrame {
    /// The feed clip at phase 0...1. Phase 1 is phase 0 again.
    static func clip(phase: Double) -> LaneDashFrame {
        let whole = CGFloat(phase.isFinite ? phase : 0)
        let p = LaneDashClip.wrap(whole)
        let road = LaneDashClip.roadPerLoop
        let laneWidth = LaneDashClip.laneWidth
        let nudge: CGFloat = 0.004

        var frame = LaneDashFrame()
        frame.clock = p
        frame.roadClock = p
        frame.scroll = p * road
        frame.kartX = LaneDashClip.lane(p) * laneWidth
        frame.height = LaneDashClip.height(p)

        let sideways = (LaneDashClip.lane(p + nudge) - LaneDashClip.lane(p - nudge)) / (2 * nudge)
        let upward = (LaneDashClip.height(p + nudge) - LaneDashClip.height(p - nudge)) / (2 * nudge)
        frame.lean = min(1, max(-1, sideways / 18.75))
        frame.climb = min(1, max(-1, upward / 2343))
        frame.boost = LaneDashClip.ease(0.765, 0.80, p) * (1 - LaneDashClip.ease(0.93, 0.975, p))

        let landing = (p - 0.935) / 0.04
        frame.landRing = landing
        if landing > 0 && landing < 1 { frame.squash = sin(landing * .pi) }

        for cue in LaneDashClip.cues {
            // depth, wrapped so that every cue is on the road exactly once per loop
            var depth = 1 + (cue.phase - p) * road
            depth -= ((depth + 0.7) / road).rounded(.down) * road
            if cue.kind == .gem {
                let age = (1 - depth) / road / 0.055
                if age >= 0 && age <= 1 { frame.pops.append((age, cue.seed)) }
                if depth <= 1 { continue }      // already collected
            }
            if depth < 0.3 { continue }
            var wobble: CGFloat = 0
            if cue.rocks {
                let a = (p - 0.485) / 0.07
                if a > 0 && a < 1 { wobble = sin(a * 3 * .pi) * 0.09 * (1 - a) }
            }
            frame.props.append(LaneDashProp(kind: cue.kind, lane: cue.lane, depth: depth,
                                            lift: cue.lift, seed: cue.seed, wobble: wobble))
        }

        let miss = (p - 0.478) / 0.1
        if miss > 0 && miss < 1 { frame.nearMiss = miss }
        frame.nearMissX = 44 - laneWidth

        let air = (p - 0.795) / 0.14
        if air > 0 && air < 1 { frame.flight = air }

        frame.wake = { back in
            let then = p - back / road
            return (LaneDashClip.lane(then) * laneWidth, LaneDashClip.height(then))
        }

        frame.distance = 1180 + Int(p * 520)
        frame.gems = 24 + LaneDashClip.cues.filter { $0.kind == .gem && LaneDashClip.wrap($0.phase) <= p }.count
        frame.pillCool = frame.boost > 0.3
        frame.pill = frame.pillCool ? "x4" : "x3"
        return frame
    }
}

// MARK: - Shapes

enum LaneDashShape {
    static func through(_ points: [CGPoint]) -> Path {
        var path = Path()
        guard points.count > 1 else { return path }
        path.addLines(points)
        path.closeSubpath()
        return path
    }

    static func corners(_ xy: (CGFloat, CGFloat)...) -> Path {
        through(xy.map { CGPoint(x: $0.0, y: $0.1) })
    }

    /// A polygon with every corner rounded off.
    static func softCorners(radius: CGFloat, _ xy: (CGFloat, CGFloat)...) -> Path {
        var path = Path()
        let points = xy.map { CGPoint(x: $0.0, y: $0.1) }
        guard points.count > 2 else { return path }
        func halfway(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }
        path.move(to: halfway(points[points.count - 1], points[0]))
        for (i, corner) in points.enumerated() {
            let next = points[(i + 1) % points.count]
            path.addArc(tangent1End: corner, tangent2End: halfway(corner, next), radius: radius)
        }
        path.closeSubpath()
        return path
    }

    static func disc(_ centre: CGPoint, _ radius: CGFloat) -> Path {
        oval(centre, radius, radius)
    }

    static func oval(_ centre: CGPoint, _ rx: CGFloat, _ ry: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: centre.x - rx, y: centre.y - ry, width: rx * 2, height: ry * 2))
    }

    static func box(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, _ radius: CGFloat = 0) -> Path {
        let rect = CGRect(x: x, y: y, width: width, height: height)
        return radius > 0 ? Path(roundedRect: rect, cornerRadius: radius) : Path(rect)
    }

    static func segment(_ a: CGPoint, _ b: CGPoint) -> Path {
        var path = Path()
        path.move(to: a)
        path.addLine(to: b)
        return path
    }

    /// A four-point twinkle.
    static func star(_ centre: CGPoint, _ radius: CGFloat, waist: CGFloat = 0.26) -> Path {
        var points: [CGPoint] = []
        points.reserveCapacity(8)
        for i in 0..<8 {
            let angle = CGFloat(i) * .pi / 4 - .pi / 2
            let reach = i % 2 == 0 ? radius : radius * waist
            points.append(CGPoint(x: centre.x + cos(angle) * reach, y: centre.y + sin(angle) * reach))
        }
        return through(points)
    }
}

// MARK: - Scenery that never changes

/// The skyline and the hills are the same on every frame for a given canvas size, so their
/// outlines are worked out once and kept.
private struct LaneDashSkyline {
    var farHills = Path()
    var nearHills = Path()
    var towers = Path()
    var warmWindows = Path()
    var pinkWindows = Path()
    var coolWindows = Path()
    var rims = Path()
    var mirror = Path()         // the towers, upside down and squashed, for the water

    private static var kept: (size: CGSize, art: LaneDashSkyline)?
    private static let door = NSLock()

    static func art(for size: CGSize, unit u: CGFloat, centreX: CGFloat, horizonY: CGFloat) -> LaneDashSkyline {
        door.lock()
        defer { door.unlock() }
        if let kept, kept.size == size { return kept.art }
        let art = LaneDashSkyline(size: size, u: u, cx: centreX, hy: horizonY)
        kept = (size, art)
        return art
    }

    private init(size: CGSize, u: CGFloat, cx: CGFloat, hy: CGFloat) {
        farHills = Self.ridge(size.width, u, cx, hy, base: 31, swell: (13, 0.019, 1.2), ripple: (7, 0.047, 0.3), dip: 0.78)
        nearHills = Self.ridge(size.width, u, cx, hy, base: 16, swell: (8, 0.031, 4.0), ripple: (4, 0.071, 2.2), dip: 0.88)

        // Towers, in design units from the centre line: small by the sun, tall beside it, fading out.
        var blocks: [(x: CGFloat, w: CGFloat, h: CGFloat, top: Int)] = []
        let reach = size.width / u / 2 + 24
        for side in [-1, 1] as [CGFloat] {
            var dice = LaneDashScatter(side < 0 ? 7 : 19)
            var x: CGFloat = 5
            while x < reach {
                let w = dice.between(9, 19)
                let mid = x + w / 2
                let rise = LaneDashClip.ease(22, 78, mid) * (1 - 0.55 * LaneDashClip.ease(105, 230, mid))
                let h = 7 + 52 * max(rise, 0.08) * dice.between(0.42, 1.0)
                let top = Int(dice.unit() * 4)
                blocks.append((side > 0 ? x : -(x + w), w, h, top))
                x += w + dice.between(0.4, 3.2)
            }
        }

        var lights = LaneDashScatter(301)
        for b in blocks {
            let left = cx + b.x * u
            let roof = hy - b.h * u
            let width = b.w * u
            let soft = min(2.6 * u, width * 0.22)
            towers.addRoundedRect(in: CGRect(x: left, y: roof, width: width, height: (b.h + 5) * u),
                                  cornerSize: CGSize(width: soft, height: soft))
            switch b.top {
            case 1:     // dome
                towers.addEllipse(in: CGRect(x: left + width * 0.12, y: roof - width * 0.32, width: width * 0.76, height: width * 0.64))
            case 2:     // mast
                towers.addRect(CGRect(x: left + width / 2 - 0.6 * u, y: roof - 9 * u, width: 1.2 * u, height: 10 * u))
                towers.addEllipse(in: CGRect(x: left + width / 2 - 1.5 * u, y: roof - 11 * u, width: 3 * u, height: 3 * u))
            case 3:     // penthouse
                towers.addRoundedRect(in: CGRect(x: left + width * 0.2, y: roof - 6 * u, width: width * 0.6, height: 8 * u),
                                      cornerSize: CGSize(width: 1.5 * u, height: 1.5 * u))
            default:
                break
            }

            let columns = max(1, Int((b.w - 3) / 3.6))
            let floors = Int((b.h - 5) / 4.6)
            if floors > 0 {
                let gap = (b.w - CGFloat(columns) * 1.7) / CGFloat(columns + 1)
                for floor in 0..<floors {
                    for column in 0..<columns {
                        let roll = lights.unit()
                        if roll > 0.56 { continue }
                        let pane = CGRect(x: cx + (b.x + gap + CGFloat(column) * (1.7 + gap)) * u,
                                          y: hy - (b.h - 3.5 - CGFloat(floor) * 4.6) * u,
                                          width: 1.7 * u, height: 2.3 * u)
                        if roll < 0.36 {
                            warmWindows.addRect(pane)
                        } else if roll < 0.5 {
                            pinkWindows.addRect(pane)
                        } else {
                            coolWindows.addRect(pane)
                        }
                    }
                }
            }
            // the edge that faces the sun catches the light
            let edge = b.x + b.w / 2 < 0 ? b.x + b.w - 1.2 : b.x
            rims.addRect(CGRect(x: cx + edge * u, y: hy - (b.h - 2) * u, width: 1.2 * u, height: (b.h - 2) * u))
        }

        let flip = CGAffineTransform(translationX: 0, y: hy).scaledBy(x: 1, y: -0.55).translatedBy(x: 0, y: -hy)
        mirror = towers.applying(flip)
    }

    private static func ridge(_ width: CGFloat, _ u: CGFloat, _ cx: CGFloat, _ hy: CGFloat, base: CGFloat,
                              swell: (CGFloat, CGFloat, CGFloat), ripple: (CGFloat, CGFloat, CGFloat), dip: CGFloat) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: -2, y: hy + 2))
        let steps = 72
        for i in 0...steps {
            let x = width * CGFloat(i) / CGFloat(steps)
            let d = (x - cx) / u
            // the hills sink behind the sun
            let valley = 1 - dip + dip * LaneDashClip.ease(24, 150, abs(d))
            let h = (base + swell.0 * sin(d * swell.1 + swell.2) + ripple.0 * sin(d * ripple.1 + ripple.2)) * valley
            path.addLine(to: CGPoint(x: x, y: hy - max(h, 0) * u))
        }
        path.addLine(to: CGPoint(x: width + 2, y: hy + 2))
        path.closeSubpath()
        return path
    }
}

/// Random numbers behind the moving scenery. They do not depend on the canvas, so one table each.
private enum LaneDashTables {
    struct Glint { var x, start, width, beat: CGFloat }
    struct Streak { var angle, pace, start, length, width: CGFloat }
    struct Scuff { var x, start, length: CGFloat }

    static let glints: [Glint] = {
        var dice = LaneDashScatter(23)
        return (0..<330).map { _ in
            let side: CGFloat = dice.unit() < 0.5 ? -1 : 1
            let x = side * dice.between(LaneDashPainter.walkEdge + 16, 2700)
            let start = dice.between(0, LaneDashClip.roadPerLoop)
            let width = dice.unit()
            return Glint(x: x, start: start, width: width, beat: dice.unit())
        }
    }()

    static let streaksBehind = streaks(seed: 91, count: 30)
    static let streaksInFront = streaks(seed: 92, count: 16)

    private static func streaks(seed: UInt64, count: Int) -> [Streak] {
        var dice = LaneDashScatter(seed)
        return (0..<count).map { _ in
            let angle = dice.unit() * 2 * .pi
            let pace = dice.between(2, 5).rounded(.down)
            let start = dice.unit()
            let length = dice.between(0.07, 0.17)
            return Streak(angle: angle, pace: pace, start: start, length: length, width: dice.between(1.0, 2.6))
        }
    }

    static let scuffs: [Scuff] = {
        var dice = LaneDashScatter(57)
        let half = LaneDashPainter.roadHalf
        return (0..<16).map { _ in
            let x = dice.between(12 - half, half - 12)
            let start = dice.between(0, 6)
            return Scuff(x: x, start: start, length: dice.between(0.25, 0.6))
        }
    }()
}

// MARK: - Painter

struct LaneDashPainter {
    private typealias S = LaneDashShape

    // The road's cross-section, in world units from the centre line.
    static let roadHalf: CGFloat = 129
    static let kerbInner: CGFloat = 132
    static let kerbOuter: CGFloat = 146
    static let walkEdge: CGFloat = 174
    static let kerbHeight: CGFloat = 7

    private static let nearEdge: CGFloat = 0.34     // the road is drawn from just behind the camera
    private static let farEdge: CGFloat = 90        // to (as good as) the horizon

    let width: CGFloat
    let height: CGFloat
    let u: CGFloat
    let midX: CGFloat
    let horizon: CGFloat
    let kartLine: CGFloat
    let lens: LaneDashLens
    let frame: LaneDashFrame
    let showHUD: Bool

    private var tick: CGFloat { frame.clock }
    private var drop: CGFloat { kartLine - horizon }

    init(size: CGSize, frame: LaneDashFrame, showHUD: Bool) {
        width = size.width
        height = size.height
        u = min(size.width / 402, size.height / 874 * 1.25)
        midX = size.width / 2
        horizon = size.height * 0.345
        kartLine = size.height * 0.66
        lens = LaneDashLens(unit: u, centreX: midX, horizonY: horizon, kartY: kartLine,
                            eyeX: frame.kartX * 0.3 + frame.shake)
        self.frame = frame
        self.showHUD = showHUD
    }

    // MARK: The frame, in two layers

    /// Everything above the horizon. It needs the clock only, so the game redraws it a few times a second.
    func backdrop(_ ctx: GraphicsContext) {
        sky(ctx)
        skyline(ctx)
    }

    /// Everything from the horizon down, then the effects and the HUD on top.
    func front(_ ctx: GraphicsContext) {
        sea(ctx)
        road(ctx)
        speedLines(ctx, LaneDashTables.streaksBehind, inFront: false)
        world(ctx)
        effects(ctx)
        speedLines(ctx, LaneDashTables.streaksInFront, inFront: true)
        if let crash = frame.crash { crashBurst(ctx, progress: crash.age / 0.5, x: crash.x) }
        vignette(ctx)
        if showHUD { hud(ctx) }
        if let crash = frame.crash, crash.age < 0.2 {
            let white = Color.white.opacity(Double(0.55 * (1 - crash.age / 0.2)))
            ctx.fill(S.box(0, 0, width, height), with: .color(white))
        }
        if let notice = frame.notice {
            let pop = 1 + 0.35 * exp(-notice.age * 14)
            write(ctx, notice.text, size: 19 * u * pop, at: CGPoint(x: midX, y: height * 0.219 + 36 * u),
                  fill: [ink(0xFFFFFF), ink(0xFFE566)], edge: ink(0x2A1466), edgeWidth: 2.2 * u,
                  alpha: 1 - LaneDashClip.ease(1.3, 1.7, notice.age), weight: .heavy)
        }
        if let hint = frame.hint {
            write(ctx, hint.text, size: 23 * u, at: CGPoint(x: midX, y: height * 0.80),
                  fill: [ink(0xFFFFFF), ink(0xFFE4EE)], edge: ink(0x2A1466), edgeWidth: 2.4 * u,
                  alpha: hint.alpha, weight: .heavy)
        }
    }

    // MARK: Tools

    private func ink(_ hex: UInt32, _ alpha: CGFloat = 1) -> Color {
        Color(.sRGB,
              red: Double((hex >> 16) & 0xFF) / 255,
              green: Double((hex >> 8) & 0xFF) / 255,
              blue: Double(hex & 0xFF) / 255,
              opacity: Double(min(max(alpha, 0), 1)))
    }

    private func down(_ colors: [Color], _ top: CGFloat, _ bottom: CGFloat) -> GraphicsContext.Shading {
        .linearGradient(Gradient(colors: colors), startPoint: CGPoint(x: 0, y: top), endPoint: CGPoint(x: 0, y: bottom))
    }

    private func down(_ stops: [(UInt32, CGFloat)], _ top: CGFloat, _ bottom: CGFloat) -> GraphicsContext.Shading {
        .linearGradient(Gradient(stops: stops.map { Gradient.Stop(color: ink($0.0), location: $0.1) }),
                        startPoint: CGPoint(x: 0, y: top), endPoint: CGPoint(x: 0, y: bottom))
    }

    private func across(_ colors: [Color], _ left: CGFloat, _ right: CGFloat) -> GraphicsContext.Shading {
        .linearGradient(Gradient(colors: colors), startPoint: CGPoint(x: left, y: 0), endPoint: CGPoint(x: right, y: 0))
    }

    private func halo(_ ctx: GraphicsContext, _ centre: CGPoint, _ radius: CGFloat, _ colors: [Color]) {
        guard radius > 0 else { return }
        ctx.fill(S.disc(centre, radius),
                 with: .radialGradient(Gradient(colors: colors), center: centre, startRadius: 0, endRadius: radius))
    }

    /// A context whose origin is the given point and whose unit is scale, so art can be drawn in its own numbers.
    private func easel(_ ctx: GraphicsContext, at origin: CGPoint, scale: CGFloat, turn: CGFloat = 0,
                       wide: CGFloat = 1, tall: CGFloat = 1) -> GraphicsContext {
        var c = ctx
        c.translateBy(x: origin.x, y: origin.y)
        if turn != 0 { c.rotate(by: .radians(Double(turn))) }
        c.scaleBy(x: scale * wide, y: scale * tall)
        return c
    }

    /// The same context, flattened: for shadows and rings that lie on the road.
    private func flattened(_ ctx: GraphicsContext, _ squash: CGFloat) -> GraphicsContext {
        var c = ctx
        c.scaleBy(x: 1, y: squash)
        return c
    }

    private func clipped(_ ctx: GraphicsContext, to shape: Path) -> GraphicsContext {
        var c = ctx
        c.clip(to: shape)
        return c
    }

    /// A strip lying on the ground between two world x and two depths.
    private func strip(_ x0: CGFloat, _ x1: CGFloat, _ near: CGFloat, _ far: CGFloat, up: CGFloat = 0) -> Path {
        S.through([lens.point(x0, near, up: up), lens.point(x1, near, up: up),
                   lens.point(x1, far, up: up), lens.point(x0, far, up: up)])
    }

    /// An upright face that runs along the road at one world x.
    private func face(_ x: CGFloat, _ near: CGFloat, _ far: CGFloat, _ low: CGFloat, _ high: CGFloat) -> Path {
        S.through([lens.point(x, near, up: low), lens.point(x, far, up: low),
                   lens.point(x, far, up: high), lens.point(x, near, up: high)])
    }

    private func unitRange(_ x: CGFloat) -> CGFloat { min(1, max(0, x)) }

    // MARK: Sky

    private func sky(_ ctx: GraphicsContext) {
        ctx.fill(S.box(0, 0, width, horizon + 2),
                 with: down([(0x1B1250, 0), (0x43208A, 0.22), (0x8A2FA6, 0.45), (0xE0488F, 0.66),
                             (0xFF7A7F, 0.84), (0xFFAE6B, 0.95), (0xFFD98A, 1)], 0, horizon))

        var dice = LaneDashScatter(11)
        let band = horizon * 0.72
        for i in 0..<54 {
            let x = dice.unit() * width
            let fall = dice.unit()
            let y = fall * fall * band
            let size = dice.between(0.5, 1.5) * u
            let beat = dice.unit()
            let twinkle = 0.3 + 0.7 * abs(sin(.pi * (tick * CGFloat(2 + i % 3) + beat)))
            let fade = 1 - y / band
            let at = CGPoint(x: x, y: y)
            if i % 9 == 0 {
                ctx.fill(S.star(at, size * 3.4 * (0.7 + 0.3 * twinkle)), with: .color(ink(0xFFF6E6, 0.9 * twinkle * fade)))
            } else {
                ctx.fill(S.disc(at, size), with: .color(ink(0xFFF1E0, 0.85 * twinkle * fade)))
            }
        }

        let sun = CGPoint(x: midX, y: horizon - 16 * u)
        let radius = 80 * u
        halo(ctx, sun, 270 * u, [ink(0xFFF0B0, 0.62), ink(0xFFB070, 0.30), ink(0xFF7AA0, 0.10), ink(0xFF7AA0, 0)])
        ctx.stroke(S.disc(sun, radius + 30 * u), with: .color(ink(0xFFE9C0, 0.10)), lineWidth: 12 * u)
        ctx.stroke(S.disc(sun, radius + 13 * u), with: .color(ink(0xFFF1CC, 0.20)), lineWidth: 8 * u)
        ctx.fill(S.disc(sun, radius),
                 with: down([(0xFFFCE0, 0), (0xFFE27A, 0.45), (0xFFA76B, 0.85), (0xFF7F8F, 1)], sun.y - radius, sun.y + radius))

        // bars of cloud that slide a little with the loop
        let drift = sin(tick * 2 * .pi) * 5 * u
        cloud(ctx, x: midX - 128 * u + drift, y: horizon - 74 * u, scale: u, lean: 1)
        cloud(ctx, x: midX + 132 * u - drift, y: horizon - 104 * u, scale: 0.86 * u, lean: -1)
        cloud(ctx, x: midX - 150 * u - drift * 0.6, y: horizon - 196 * u, scale: 0.62 * u, lean: -1)
        cloud(ctx, x: midX + 150 * u + drift * 0.6, y: horizon - 232 * u, scale: 0.56 * u, lean: 1)
    }

    private func cloud(_ ctx: GraphicsContext, x: CGFloat, y: CGFloat, scale k: CGFloat, lean: CGFloat) {
        let bars: [(dx: CGFloat, dy: CGFloat, w: CGFloat, h: CGFloat)] = [(-12, -10, 56, 9), (6, 0, 98, 11), (-20, 10, 62, 8)]
        for bar in bars {
            let rect = CGRect(x: x + (bar.dx * lean - bar.w / 2) * k, y: y + (bar.dy - bar.h / 2) * k,
                              width: bar.w * k, height: bar.h * k)
            ctx.fill(Path(roundedRect: rect, cornerRadius: rect.height / 2),
                     with: down([ink(0xC65AB8, 0.78), ink(0xFFB79A, 0.95)], rect.minY, rect.maxY))
            let lit = CGRect(x: rect.minX + rect.height * 0.5, y: rect.maxY - rect.height * 0.32,
                             width: rect.width - rect.height, height: rect.height * 0.2)
            ctx.fill(Path(roundedRect: lit, cornerRadius: lit.height / 2), with: .color(ink(0xFFE9C8, 0.75)))
        }
    }

    // MARK: Hills and skyline

    private var skylineArt: LaneDashSkyline {
        LaneDashSkyline.art(for: CGSize(width: width, height: height), unit: u, centreX: midX, horizonY: horizon)
    }

    private func skyline(_ ctx: GraphicsContext) {
        let art = skylineArt
        ctx.fill(art.farHills, with: down([ink(0xB358B6, 0.92), ink(0xFF9C98, 0.92)], horizon - 48 * u, horizon))
        ctx.fill(art.nearHills, with: down([ink(0x8842A8), ink(0xE8769A)], horizon - 28 * u, horizon))
        ctx.fill(art.towers, with: down([ink(0x4A2288), ink(0x74369E), ink(0xC25C9C)], horizon - 64 * u, horizon + 3 * u))
        ctx.fill(art.warmWindows, with: .color(ink(0xFFE3A6, 0.95)))
        ctx.fill(art.pinkWindows, with: .color(ink(0xFFA9C8, 0.9)))
        ctx.fill(art.coolWindows, with: .color(ink(0x9DF3FF, 0.9)))
        ctx.fill(art.rims, with: .color(ink(0xFFC0A8, 0.55)))

        bigWheel(ctx, hub: CGPoint(x: midX - 124 * u, y: horizon - 33 * u), radius: 25 * u)
        needle(ctx, x: midX + 116 * u)

        // the sun's bloom along the horizon
        var bloom = ctx
        bloom.translateBy(x: midX, y: horizon)
        bloom.scaleBy(x: 1, y: 0.2)
        halo(bloom, .zero, 210 * u, [ink(0xFFF0C0, 0.7), ink(0xFFC090, 0.25), ink(0xFFC090, 0)])
    }

    private func bigWheel(_ ctx: GraphicsContext, hub: CGPoint, radius: CGFloat) {
        let steel = ink(0x4A2288)
        var legs = Path()
        for side in [-1, 1] as [CGFloat] {
            legs.move(to: hub)
            legs.addLine(to: CGPoint(x: hub.x + side * radius * 0.45, y: horizon + 2))
        }
        ctx.stroke(legs, with: .color(steel), style: StrokeStyle(lineWidth: 2.2 * u, lineCap: .round))
        ctx.stroke(S.disc(hub, radius), with: .color(steel), lineWidth: 2 * u)
        ctx.stroke(S.disc(hub, radius * 0.58), with: .color(steel), lineWidth: u)

        // one eighth of a turn per loop, so the loop closes
        let turn = tick * .pi / 4
        let rim = (0..<8).map { i -> CGPoint in
            let angle = turn + CGFloat(i) * .pi / 4
            return CGPoint(x: hub.x + cos(angle) * radius, y: hub.y + sin(angle) * radius)
        }
        var spokes = Path()
        for end in rim {
            spokes.move(to: hub)
            spokes.addLine(to: end)
        }
        ctx.stroke(spokes, with: .color(steel), lineWidth: 0.9 * u)
        let cabins: [UInt32] = [0xFFE3A6, 0xFF9EC4, 0x9DF3FF, 0xFFE3A6]
        for (i, end) in rim.enumerated() {
            ctx.fill(S.disc(CGPoint(x: end.x, y: end.y + 1.2 * u), 2.7 * u), with: .color(ink(cabins[i % 4])))
        }
        ctx.fill(S.disc(hub, 2.6 * u), with: .color(ink(0xFFC0A8)))
    }

    private func needle(_ ctx: GraphicsContext, x: CGFloat) {
        let steel = ink(0x4A2288)
        let tip = horizon - 74 * u
        ctx.fill(S.corners((x - 3.2 * u, horizon + 2), (x + 3.2 * u, horizon + 2), (x + 1.1 * u, tip + 16 * u), (x - 1.1 * u, tip + 16 * u)),
                 with: .color(steel))
        ctx.fill(S.oval(CGPoint(x: x, y: tip + 15 * u), 9.5 * u, 4.2 * u), with: .color(steel))
        ctx.fill(S.box(x - 7 * u, tip + 13.6 * u, 14 * u, 1.7 * u, 0.8 * u), with: .color(ink(0xFFE3A6, 0.95)))
        ctx.fill(S.box(x - 0.6 * u, tip, 1.2 * u, 12 * u), with: .color(steel))
        let blink = 0.35 + 0.65 * abs(sin(tick * 6 * .pi))
        let beacon = CGPoint(x: x, y: tip)
        halo(ctx, beacon, 7 * u, [ink(0xFF6A8E, 0.7 * blink), ink(0xFF6A8E, 0)])
        ctx.fill(S.disc(beacon, 1.6 * u), with: .color(ink(0xFFD0DC, 0.6 + 0.4 * blink)))
    }

    // MARK: Sea

    private func sea(_ ctx: GraphicsContext) {
        let water = S.box(0, horizon, width, height - horizon)
        ctx.fill(water, with: down([(0xFFCB96, 0), (0xFF8FA6, 0.05), (0xC466C8, 0.16), (0x6A63D8, 0.36),
                                    (0x2F8AD0, 0.68), (0x1B6DB2, 1)], horizon, horizon + drop * 1.5))
        let wet = clipped(ctx, to: water)

        wet.fill(skylineArt.mirror, with: down([ink(0x5A2A96, 0.5), ink(0x5A2A96, 0)], horizon, horizon + 36 * u))

        var glare = wet
        glare.translateBy(x: midX, y: horizon)
        glare.scaleBy(x: 1, y: 0.34)
        halo(glare, .zero, 230 * u, [ink(0xFFF1C4, 0.6), ink(0xFFB48A, 0.25), ink(0xFFB48A, 0)])

        // flecks of light on the water that travel with the road
        let loop = LaneDashClip.roadPerLoop
        for (i, glint) in LaneDashTables.glints.enumerated() {
            var depth = glint.start - frame.scroll
            depth -= (depth / loop).rounded(.down) * loop
            depth += 0.42
            let at = lens.point(glint.x, depth)
            let scale = lens.scale(depth)
            let half = (16 + 34 * glint.width) * scale
            if at.x < -half || at.x > width + half || at.y > height + 4 { continue }
            let thick = max(0.9 * u, 3.4 * scale)
            let fade = min(1, (depth - 0.42) / 0.5) * min(1, (loop + 0.42 - depth) / 1.5)
            let fleck = Path(roundedRect: CGRect(x: at.x - half, y: at.y - thick / 2, width: half * 2, height: thick),
                             cornerRadius: thick / 2)
            if i % 4 == 3 {
                wet.fill(fleck, with: .color(ink(0x2440A8, 0.26 * fade)))
            } else {
                let twinkle = 0.35 + 0.65 * abs(sin(.pi * (tick * 3 + glint.beat)))
                let warm = (at.y - horizon) / (drop * 0.5) < 0.3
                wet.fill(fleck, with: .color(ink(warm ? 0xFFF0D2 : 0xD6F8FF, (warm ? 0.75 : 0.5) * twinkle * fade)))
            }
        }

        ctx.fill(S.box(0, horizon - 0.5 * u, width, 1.2 * u), with: .color(ink(0xFFF3D6, 0.55)))
    }

    // MARK: Road

    private func road(_ ctx: GraphicsContext) {
        let near = Self.nearEdge
        let far = Self.farEdge
        let half = Self.roadHalf
        let kerbIn = Self.kerbInner
        let kerbOut = Self.kerbOuter
        let walk = Self.walkEdge
        let lift = Self.kerbHeight
        let sides: [CGFloat] = [-1, 1]
        let scroll = frame.scroll

        // the deck's shadow on the water, then the boardwalk with its pale outer lip
        for side in sides {
            ctx.fill(strip(side * walk, side * (walk + 34), near, far, up: -26),
                     with: down([ink(0x1A1458, 0), ink(0x1A1458, 0.42)], horizon, horizon + drop * 0.8))
        }
        for side in sides {
            ctx.fill(strip(side * kerbOut, side * walk, near, far, up: lift),
                     with: down([(0xFFC2B0, 0), (0xD796D2, 0.1), (0x8E7BE6, 0.4), (0x6C5CD8, 1)], horizon, height))
            ctx.fill(strip(side * (walk - 3.5), side * walk, near, far, up: lift),
                     with: down([ink(0xFFF1E0, 0.3), ink(0xFFF6EC, 0.95)], horizon, horizon + drop * 0.5))
        }

        ctx.fill(strip(-kerbIn, kerbIn, near, far),
                 with: down([(0xD99AC6, 0), (0x9368BC, 0.05), (0x5D44A4, 0.16), (0x3D2F8A, 0.42), (0x2A2168, 1)], horizon, height))

        // faint bands of tone that roll toward the camera
        let bandShift = LaneDashClip.wrap(scroll)
        for k in 0..<26 {
            let start = CGFloat(k) - bandShift
            let fade = unitRange((18 - start) / 14)
            if start + 0.5 <= near || fade <= 0 { continue }
            ctx.fill(strip(-half, half, max(start, near), start + 0.5), with: .color(ink(0xFFFFFF, 0.05 * fade)))
        }

        // the sunset, mirrored down the middle of the road
        ctx.fill(S.through([CGPoint(x: midX - 3 * u, y: horizon), CGPoint(x: midX + 3 * u, y: horizon),
                            lens.point(lens.eyeX + 74, 0.9), lens.point(lens.eyeX - 74, 0.9)]),
                 with: down([ink(0xFFE2A8, 0.62), ink(0xFF9EB0, 0.2), ink(0xFF9EB0, 0)], horizon, horizon + drop * 0.9))

        for side in sides {
            ctx.fill(strip(side * (half - 6), side * (half - 2.5), near, far),
                     with: down([ink(0xFFF3E3, 0.5), ink(0xFFF3E3, 0.9)], horizon, horizon + drop))
        }

        // lane dashes, two to a depth unit
        let dashShift = LaneDashClip.wrap(scroll * 2)
        for k in 0..<30 {
            let start = (CGFloat(k) - dashShift) * 0.5
            let fade = unitRange((15 - start) / 9)
            if start + 0.25 <= near || fade <= 0 { continue }
            let paint = GraphicsContext.Shading.color(ink(0xFFF3E3, 0.92 * fade))
            for side in sides {
                let x = side * LaneDashClip.laneWidth / 2
                ctx.fill(strip(x - 2.9, x + 2.9, max(start, near), start + 0.25), with: paint)
            }
        }

        // short scuffs that streak past
        for scuff in LaneDashTables.scuffs {
            var depth = scuff.start - scroll
            depth -= (depth / 6).rounded(.down) * 6
            depth += 0.3
            let fade = min(1, (depth - 0.3) / 0.4) * min(1, (6.3 - depth) / 2)
            ctx.fill(strip(scuff.x - 1.1, scuff.x + 1.1, depth, depth + scuff.length), with: .color(ink(0xFFFFFF, 0.1 * fade)))
        }

        // kerbs: a cream step with pink blocks, four to a depth unit, and the face that looks at the road
        let kerbShift = LaneDashClip.wrap(scroll * 4)
        for side in sides {
            ctx.fill(face(side * kerbIn, near, far, 0, lift), with: down([ink(0xE8B4D0), ink(0xD8C6E2)], horizon, horizon + drop))
            ctx.fill(strip(side * kerbIn, side * kerbOut, near, far, up: lift),
                     with: down([ink(0xFFC6D2), ink(0xFFF4E6)], horizon, horizon + drop * 0.4))
            for k in 0..<64 {
                let start = (CGFloat(k) - kerbShift) * 0.25
                let end = start + 0.125
                if end <= near { continue }
                let fade = unitRange((17 - start) / 9)
                let from = max(start, near)
                ctx.fill(face(side * kerbIn, from, end, 0, lift), with: .color(ink(0xC42F6C, fade)))
                ctx.fill(strip(side * kerbIn, side * kerbOut, from, end, up: lift), with: .color(ink(0xFF5C8A, fade)))
            }
        }

        // seams between the boards
        for side in sides {
            for k in 0..<40 {
                let at = (CGFloat(k) - kerbShift) * 0.25
                let fade = unitRange((10 - at) / 8)
                if at <= near || fade <= 0 { continue }
                ctx.fill(strip(side * (kerbOut + 1), side * (walk - 4), at, at + 0.016), with: .color(ink(0x3D2F8A, 0.22 * fade)))
            }
        }

        // the rail: posts, then the two bars
        for side in sides {
            let x = side * (walk - 2)
            for k in 0..<40 {
                let at = (CGFloat(k) - dashShift) * 0.5
                let fade = unitRange((14 - at) / 8)
                if at <= near || fade <= 0 { continue }
                ctx.fill(face(x, at, at + 0.03, lift, lift + 21), with: .color(ink(0xEADCF8, 0.9 * fade)))
            }
            ctx.fill(face(x, near, far, lift + 19, lift + 23.5),
                     with: down([ink(0xFFE9D8, 0.6), ink(0xFFFFFF, 0.98)], horizon, horizon + drop * 0.5))
            ctx.fill(face(x, near, far, lift + 9, lift + 11.5),
                     with: down([ink(0xFFD0D8, 0.4), ink(0xD9CCF5, 0.9)], horizon, horizon + drop * 0.5))
        }
    }

    // MARK: The world, far to near

    private enum Actor {
        case lamp(side: CGFloat, index: Int)
        case prop(LaneDashProp)
        case gate(LaneDashGate)
        case kart
    }

    private func world(_ ctx: GraphicsContext) {
        var cast: [(depth: CGFloat, actor: Actor)] = []
        cast.reserveCapacity(17 + frame.props.count + frame.gates.count)

        // eight pairs of lamp posts, one and a half depth units apart
        let loop = LaneDashClip.roadPerLoop
        for index in 0..<8 {
            var depth = CGFloat(index) * 1.5 + 0.55 - frame.scroll
            depth -= ((depth - 0.3) / loop).rounded(.down) * loop
            cast.append((depth, .lamp(side: -1, index: index)))
            cast.append((depth, .lamp(side: 1, index: index)))
        }
        for prop in frame.props { cast.append((prop.depth, .prop(prop))) }
        for gate in frame.gates { cast.append((gate.depth, .gate(gate))) }
        cast.append((0.999, .kart))

        cast.sort { $0.depth > $1.depth }
        for member in cast {
            switch member.actor {
            case let .lamp(side, index): lamp(ctx, side: side, depth: member.depth, index: index)
            case let .prop(prop): self.prop(ctx, prop)
            case let .gate(gate): self.gate(ctx, gate)
            case .kart: kart(ctx)
            }
        }
    }

    private func prop(_ ctx: GraphicsContext, _ prop: LaneDashProp) {
        // things fade in out of the haze at the horizon
        let alpha = unitRange((11.25 - prop.depth) / 1.7)
        if alpha <= 0.01 { return }
        if alpha >= 0.995 {
            propBody(ctx, prop)
        } else {
            var hazy = ctx
            hazy.opacity = Double(alpha)
            hazy.drawLayer { layer in self.propBody(layer, prop) }
        }
    }

    private func propBody(_ ctx: GraphicsContext, _ prop: LaneDashProp) {
        let x = prop.lane * LaneDashClip.laneWidth
        let foot = lens.point(x, prop.depth)
        let scale = lens.scale(prop.depth)
        switch prop.kind {
        case .gem:
            let bob = sin(2 * .pi * (tick * 4 + prop.seed * 0.37)) * 3
            let shade = 0.3 * max(0.25, 1 - prop.lift / 160)
            easel(ctx, at: foot, scale: scale).fill(S.oval(.zero, 11, 3.4), with: .color(ink(0x120A3C, shade)))
            gem(ctx, at: lens.point(x, prop.depth, up: prop.lift + bob), scale: scale * 1.08,
                turn: LaneDashClip.wrap(tick * 3 + prop.seed * 0.23), glow: 1)
        case .barrier:
            barrier(ctx, foot, scale, wobble: prop.wobble, seed: prop.seed)
        case .cones:
            cone(ctx, CGPoint(x: foot.x - 20 * scale, y: foot.y - 6 * scale), scale * 0.9)
            cone(ctx, CGPoint(x: foot.x + 21 * scale, y: foot.y - 4 * scale), scale * 0.94)
            cone(ctx, CGPoint(x: foot.x + scale, y: foot.y + 4 * scale), scale)
        case .block:
            block(ctx, foot, scale, glance: (frame.kartX - x) / LaneDashClip.laneWidth)
        case .hurdle:
            hurdle(ctx, foot, scale)
        case .ramp:
            ramp(ctx, x: x, depth: prop.depth)
        }
    }

    /// A dark blur on the road under something.
    private func groundShadow(_ c: GraphicsContext, radius: CGFloat, squash: CGFloat, strength: CGFloat, mid: CGFloat) {
        halo(flattened(c, squash), .zero, radius, [ink(0x120A3C, strength), ink(0x120A3C, mid), ink(0x120A3C, 0)])
    }

    // MARK: Lamp posts

    private func lamp(_ ctx: GraphicsContext, side: CGFloat, depth: CGFloat, index: Int) {
        let alpha = unitRange((12.2 - depth) / 2.2) * min(1, (depth - 0.3) / 0.12)
        if alpha <= 0.01 { return }
        let foot = lens.point(side * (Self.walkEdge - 13), depth, up: Self.kerbHeight)
        let scale = lens.scale(depth)
        if foot.x < -70 * scale || foot.x > width + 70 * scale { return }

        var faded = ctx
        faded.opacity = Double(alpha)
        let c = easel(faded, at: foot, scale: scale)
        let top: CGFloat = -150

        // its pool of light on the boards
        halo(flattened(c, 0.3), .zero, 30, [ink(0xFFE9B8, 0.4), ink(0xFFE9B8, 0)])

        let dark = ink(0x3E2C8A)
        let bright = ink(0x9C8AF2)
        c.fill(S.box(-7, -7, 14, 8, 3), with: down([ink(0x8674E6), ink(0x4A379E)], -7, 1))
        c.fill(S.box(-2.6, top + 8, 5.2, -top - 12, 2.4), with: across(side < 0 ? [dark, bright] : [bright, dark], -2.6, 2.6))
        c.fill(S.box(-4.2, top + 8, 8.4, 5, 2), with: .color(ink(0x4A379E)))

        // a pennant that points at the road
        let flags: [UInt32] = [0xFF5C8A, 0x39E0F5, 0xFFD23F]
        let flutter = sin(2 * .pi * (tick * 6 + CGFloat(index) * 0.3)) * 2.5
        let inward = -side
        c.fill(S.corners((inward * 2.4, top + 26), (inward * 24, top + 33 + flutter), (inward * 2.4, top + 41)),
               with: .color(ink(flags[index % 3])))
        c.fill(S.corners((inward * 2.4, top + 26), (inward * 24, top + 33 + flutter), (inward * 2.4, top + 31)),
               with: .color(ink(0xFFFFFF, 0.3)))

        let globe = CGPoint(x: 0, y: top)
        halo(c, globe, 46, [ink(0xFFF3C8, 0.62), ink(0xFFB884, 0.24), ink(0xFFB884, 0)])
        c.fill(S.disc(globe, 11.5),
               with: .radialGradient(Gradient(colors: [ink(0xFFFFFF), ink(0xFFF2C2), ink(0xFFC68A)]),
                                     center: CGPoint(x: -3, y: top - 3), startRadius: 0, endRadius: 15))
        c.fill(S.box(-5.5, top - 15, 11, 5, 2.4), with: .color(ink(0x5A46B4)))
        c.fill(S.oval(CGPoint(x: -4, y: top - 3.5), 3, 2), with: .color(ink(0xFFFFFF, 0.9)))
    }

    // MARK: Gates

    /// An arch over the road with a name on it: where a friend's round ended, or the player's best.
    private func gate(_ ctx: GraphicsContext, _ gate: LaneDashGate) {
        let depth = gate.depth
        // out of the haze at the horizon, and gone just before it would sweep over the kart
        let alpha = unitRange((11.25 - depth) / 1.7) * unitRange((depth - 1) / 0.3)
        if alpha <= 0.01 { return }
        var c = ctx
        c.opacity = Double(alpha)
        let scale = lens.scale(depth)
        let half = Self.kerbInner + 7
        let lift = Self.kerbHeight
        let bannerLow: CGFloat = 138
        let bannerHigh: CGFloat = 196

        let dark = ink(0x3E2C8A)
        let bright = ink(0x9C8AF2)
        for side in [-1, 1] as [CGFloat] {
            let post = easel(c, at: lens.point(side * half, depth, up: lift), scale: scale)
            post.fill(S.box(-7, -7, 14, 8, 3), with: down([ink(0x8674E6), ink(0x4A379E)], -7, 1))
            post.fill(S.box(-2.8, 4 - bannerHigh, 5.6, bannerHigh - 8, 2.6),
                      with: across(side < 0 ? [dark, bright] : [bright, dark], -2.8, 2.8))
        }

        let topLeft = lens.point(-half - 6, depth, up: bannerHigh + lift)
        let bottomRight = lens.point(half + 6, depth, up: bannerLow + lift)
        let rect = CGRect(x: topLeft.x, y: topLeft.y, width: bottomRight.x - topLeft.x, height: bottomRight.y - topLeft.y)
        let round = rect.height * 0.3
        let banner = Path(roundedRect: rect, cornerRadius: round)
        c.fill(Path(roundedRect: rect.offsetBy(dx: 0, dy: 3 * scale), cornerRadius: round), with: .color(ink(0x120A3C, 0.35)))
        c.fill(banner, with: down(gate.gold ? [ink(0xFFF0B0), ink(0xFFC24A)] : [ink(0xFFFDF6), ink(0xFFC6DC)], rect.minY, rect.maxY))
        c.stroke(banner, with: .color(ink(0x2A1466)), lineWidth: max(0.6, 2.4 * scale))
        c.fill(S.box(rect.minX + round, rect.minY + rect.height * 0.12, rect.width - 2 * round, rect.height * 0.1, rect.height * 0.05),
               with: .color(ink(0xFFFFFF, 0.7)))

        let letters = 34 * scale
        if letters < 3 { return }
        var name = c.resolve(Text(verbatim: gate.name).font(.system(size: letters, weight: .black, design: .rounded)))
        name.shading = .color(ink(0x2A1466))
        let needs = name.measure(in: CGSize(width: 4000, height: 4000)).width
        let room = rect.width * 0.88
        c.translateBy(x: rect.midX, y: rect.midY)
        if needs > room && needs > 0 { c.scaleBy(x: room / needs, y: room / needs) }
        c.draw(name, at: .zero, anchor: .center)
    }

    // MARK: Gems

    private func gem(_ ctx: GraphicsContext, at centre: CGPoint, scale: CGFloat, turn: CGFloat, glow: CGFloat) {
        if glow > 0 {
            halo(ctx, centre, 32 * scale, [ink(0x9DF6FF, 0.6 * glow), ink(0x39C8FF, 0.2 * glow), ink(0x39C8FF, 0)])
        }
        let c = easel(ctx, at: centre, scale: scale)
        // it turns, so it narrows and widens
        let facing = 0.56 + 0.44 * abs(cos(turn * .pi))
        let wide = 15.5 * facing
        let table = 8.6 * facing
        let inner = 6.2 * facing
        let top: CGFloat = -15
        let girdle: CGFloat = -5
        let point: CGFloat = 17

        let outline = S.corners((-table, top), (table, top), (wide, girdle), (0, point), (-wide, girdle))
        c.stroke(outline, with: .color(ink(0x0B4FA8, 0.55)), style: StrokeStyle(lineWidth: 6, lineJoin: .round))
        c.stroke(outline, with: .color(ink(0xFFFFFF)), style: StrokeStyle(lineWidth: 3.2, lineJoin: .round))
        c.fill(S.corners((-table, top), (-wide, girdle), (-inner, girdle)), with: .color(ink(0xA4F7FF)))
        c.fill(S.corners((-table, top), (table, top), (inner, girdle), (-inner, girdle)), with: .color(ink(0xE6FEFF)))
        c.fill(S.corners((table, top), (wide, girdle), (inner, girdle)), with: .color(ink(0x5CE0FA)))
        c.fill(S.corners((-wide, girdle), (-inner, girdle), (0, point)), with: .color(ink(0x35CDF6)))
        c.fill(S.corners((-inner, girdle), (inner, girdle), (0, point)), with: .color(ink(0x82EEFF)))
        c.fill(S.corners((inner, girdle), (wide, girdle), (0, point)), with: .color(ink(0x1590E2)))
        let twinkle = 0.6 + 0.4 * sin(turn * 2 * .pi)
        c.fill(S.star(CGPoint(x: -wide * 0.78, y: top - 1), 6.5 * twinkle), with: .color(ink(0xFFFFFF)))
    }

    // MARK: Obstacles

    private func barrier(_ ctx: GraphicsContext, _ foot: CGPoint, _ scale: CGFloat, wobble: CGFloat, seed: CGFloat) {
        groundShadow(easel(ctx, at: foot, scale: scale), radius: 50, squash: 0.17, strength: 0.5, mid: 0.34)

        let c = easel(ctx, at: foot, scale: scale, turn: wobble)
        let ends: [CGFloat] = [-1, 1]
        for end in ends {
            let x = 26 * end
            c.fill(S.box(x - 11.5, -6.5, 23, 7, 3.2), with: down([ink(0x5446A6), ink(0x231A52)], -6.5, 0.5))
            c.fill(S.box(x - 3.6, -36, 7.2, 32, 2), with: across([ink(0x8674E6), ink(0x34287A)], x - 3.6, x + 3.6))
        }

        // two warning lamps that take turns
        let leftOn = LaneDashClip.wrap(tick * 8 + seed * 0.37) < 0.5
        for end in ends {
            let lit = (end < 0) == leftOn
            let bulb = CGPoint(x: 26 * end, y: -61)
            if lit { halo(c, bulb, 17, [ink(0xFFD27A, 0.75), ink(0xFF8A3C, 0.25), ink(0xFF8A3C, 0)]) }
            c.fill(S.box(bulb.x - 4.5, -58, 9, 4, 1.5), with: .color(ink(0x34287A)))
            c.fill(S.disc(bulb, 5.6), with: .color(ink(lit ? 0xFFC24A : 0xD9632A)))
            c.fill(S.disc(CGPoint(x: bulb.x - 1.6, y: bulb.y - 1.8), 1.8), with: .color(ink(0xFFFFFF, lit ? 0.95 : 0.5)))
        }

        c.fill(S.box(-35, -59, 70, 14, 5.5), with: .color(ink(0xFFE6DA)))
        let plank = S.box(-37.5, -54, 75, 27, 7)
        c.fill(plank, with: .color(ink(0xFFF8EE)))
        let on = clipped(c, to: plank)
        for i in -3...4 {
            let x = CGFloat(i) * 18.5 - 6
            on.fill(S.corners((x, -27), (x + 9.5, -27), (x + 20.5, -54), (x + 11, -54)), with: .color(ink(0xFF4259)))
        }
        on.fill(S.box(-40, -54, 80, 27), with: down([ink(0xFFFFFF, 0), ink(0x6A1C78, 0.3)], -44, -27))
        c.fill(S.box(-32, -52, 64, 2.6, 1.3), with: .color(ink(0xFFFFFF, 0.8)))
    }

    private func cone(_ ctx: GraphicsContext, _ foot: CGPoint, _ scale: CGFloat) {
        let c = easel(ctx, at: foot, scale: scale)
        groundShadow(c, radius: 26, squash: 0.24, strength: 0.5, mid: 0.3)

        c.fill(S.box(-17.5, -7.5, 35, 8, 3.4), with: down([ink(0xFF7A38), ink(0xD63A14)], -7.5, 0.5))
        c.fill(S.box(-15.5, -8.8, 31, 4.2, 2.1), with: .color(ink(0xFFA060)))
        var body = Path()
        body.move(to: CGPoint(x: -12, y: -6.5))
        body.addLine(to: CGPoint(x: -4.2, y: -44))
        body.addQuadCurve(to: CGPoint(x: 4.2, y: -44), control: CGPoint(x: 0, y: -50))
        body.addLine(to: CGPoint(x: 12, y: -6.5))
        body.closeSubpath()
        c.fill(body, with: across([ink(0xFFAA4A), ink(0xFF6E22), ink(0xE0460F)], -12, 12))
        let on = clipped(c, to: body)
        on.fill(S.box(-14, -33, 28, 10.5), with: across([ink(0xFFFFFF), ink(0xF3DCE0)], -10, 10))
        on.fill(S.corners((-12.5, -6.5), (-4.6, -46), (-2.4, -46), (-8.2, -6.5)), with: .color(ink(0xFFFFFF, 0.36)))
    }

    /// A cross block of jelly. Its eyes follow the kart.
    private func block(_ ctx: GraphicsContext, _ foot: CGPoint, _ scale: CGFloat, glance: CGFloat) {
        let c = easel(ctx, at: foot, scale: scale)
        groundShadow(c, radius: 54, squash: 0.17, strength: 0.55, mid: 0.36)

        c.fill(S.box(-34, -76, 68, 28, 11), with: down([ink(0xFFC0A6), ink(0xFF9478)], -76, -56))
        let front = S.box(-37.5, -63, 75, 63, 11.5)
        c.fill(front, with: down([ink(0xFF705A), ink(0xEE3D5A)], -63, 0))
        clipped(c, to: front).fill(S.box(-40, -15, 80, 16), with: down([ink(0x9A1650, 0), ink(0x9A1650, 0.5)], -15, 0))
        c.fill(S.box(-30, -58.5, 26, 4.2, 2.1), with: .color(ink(0xFFFFFF, 0.5)))
        c.fill(S.disc(CGPoint(x: 1.5, y: -56.4), 2.1), with: .color(ink(0xFFFFFF, 0.5)))

        let plum = ink(0x7A1240)
        let look = min(1, max(-1, glance)) * 2.6
        for side in [-1, 1] as [CGFloat] {
            let eye = CGPoint(x: 15 * side, y: -35)
            c.fill(S.oval(CGPoint(x: eye.x, y: eye.y + 1.3), 9.8, 10.8), with: .color(ink(0x9A1650, 0.45)))
            c.fill(S.oval(eye, 9.8, 10.8), with: .color(ink(0xFFFDF6)))
            let pupil = CGPoint(x: eye.x + look - side * 1.5, y: eye.y + 2.6)
            c.fill(S.disc(pupil, 5), with: .color(ink(0x2C1248)))
            c.fill(S.disc(CGPoint(x: pupil.x - 1.6, y: pupil.y - 1.8), 1.7), with: .color(ink(0xFFFFFF)))
            c.stroke(S.segment(CGPoint(x: 27 * side, y: -51), CGPoint(x: 5 * side, y: -43)),
                     with: .color(plum), style: StrokeStyle(lineWidth: 6, lineCap: .round))
        }
        var frown = Path()
        frown.move(to: CGPoint(x: -10, y: -13))
        frown.addQuadCurve(to: CGPoint(x: 10, y: -13), control: CGPoint(x: 0, y: -22))
        c.stroke(frown, with: .color(plum), style: StrokeStyle(lineWidth: 4.4, lineCap: .round))
    }

    private func hurdle(_ ctx: GraphicsContext, _ foot: CGPoint, _ scale: CGFloat) {
        let c = easel(ctx, at: foot, scale: scale)
        groundShadow(c, radius: 52, squash: 0.16, strength: 0.5, mid: 0.34)

        c.fill(S.box(-37, -35, 74, 16, 6), with: .color(ink(0xFFD9D2)))
        let front = S.box(-40, -28, 80, 28, 7.5)
        c.fill(front, with: .color(ink(0xFF4259)))
        let on = clipped(c, to: front)
        for i in -3...4 {
            let x = CGFloat(i) * 20 - 4
            on.fill(S.corners((x, 0), (x + 10, 0), (x + 21, -28), (x + 11, -28)), with: .color(ink(0xFFF8EE)))
        }
        on.fill(S.box(-42, -28, 84, 28), with: down([ink(0xFFFFFF, 0), ink(0x6A1C78, 0.34)], -18, 0))
        c.fill(S.box(-34, -26, 68, 2.6, 1.3), with: .color(ink(0xFFFFFF, 0.75)))
    }

    /// A wedge on the road with arrows running up it.
    private func ramp(_ ctx: GraphicsContext, x: CGFloat, depth: CGFloat) {
        let back = depth + 0.36
        let half: CGFloat = 39
        let rise: CGFloat = 34
        let frontLeft = lens.point(x - half, depth)
        let frontRight = lens.point(x + half, depth)
        let topLeft = lens.point(x - half, back, up: rise)
        let topRight = lens.point(x + half, back, up: rise)
        let scale = lens.scale(depth)

        ctx.fill(S.through([lens.point(x - half - 5, depth - 0.02), lens.point(x + half + 5, depth - 0.02),
                            lens.point(x + half + 5, back + 0.05), lens.point(x - half - 5, back + 0.05)]),
                 with: .color(ink(0x120A3C, 0.3)))
        let flank = GraphicsContext.Shading.color(ink(0x9C1F72))
        ctx.fill(S.through([frontLeft, topLeft, lens.point(x - half, back)]), with: flank)
        ctx.fill(S.through([frontRight, topRight, lens.point(x + half, back)]), with: flank)

        let surface = S.through([frontLeft, frontRight, topRight, topLeft])
        ctx.fill(surface, with: down([ink(0xFF3F9A), ink(0xFF9AD0)], frontLeft.y, topLeft.y))

        // across -1...1, up 0...1, on the sloping surface
        func on(_ across: CGFloat, _ up: CGFloat) -> CGPoint {
            let l = CGPoint(x: frontLeft.x + (topLeft.x - frontLeft.x) * up, y: frontLeft.y + (topLeft.y - frontLeft.y) * up)
            let r = CGPoint(x: frontRight.x + (topRight.x - frontRight.x) * up, y: frontRight.y + (topRight.y - frontRight.y) * up)
            let f = (across + 1) / 2
            return CGPoint(x: l.x + (r.x - l.x) * f, y: l.y + (r.y - l.y) * f)
        }
        let arrows = clipped(ctx, to: surface)
        let run = LaneDashClip.wrap(tick * 12)
        for j in -1..<4 {
            let b = (CGFloat(j) + run) * 0.3
            arrows.fill(S.through([on(-0.62, b), on(0, b + 0.17), on(0.62, b), on(0.62, b + 0.12), on(0, b + 0.29), on(-0.62, b + 0.12)]),
                        with: .color(ink(0xFFFFFF, 0.92)))
        }

        let cream = GraphicsContext.Shading.color(ink(0xFFF8EE))
        ctx.stroke(S.segment(frontLeft, topLeft), with: cream, lineWidth: 3.4 * scale)
        ctx.stroke(S.segment(frontRight, topRight), with: cream, lineWidth: 3.4 * scale)
        ctx.stroke(S.segment(topLeft, topRight), with: .color(ink(0xFFFFFF)), lineWidth: 3.6 * scale)
        ctx.stroke(S.segment(frontLeft, frontRight), with: .color(ink(0x7EEBFF)), lineWidth: 3 * scale)
    }

    // MARK: The kart

    private var kartFoot: CGPoint { lens.point(frame.kartX, 1) }
    private var kartScale: CGFloat { u * 0.97 }

    /// A band of light along the path the kart has just driven.
    private func ribbon(_ ctx: GraphicsContext, offset: CGFloat, up: CGFloat, half: CGFloat, length: CGFloat, colors: [Color]) {
        let steps = 18
        var leftEdge: [CGPoint] = []
        var rightEdge: [CGPoint] = []
        leftEdge.reserveCapacity(2 * steps + 2)
        rightEdge.reserveCapacity(steps + 1)
        var head = CGPoint.zero
        var tail = CGPoint.zero
        for i in 0...steps {
            let f = CGFloat(i) / CGFloat(steps)
            let back = f * length
            let was = frame.wake(back)
            let x = was.x + offset
            let lift = was.height + up
            let w = half * (1 - 0.25 * f)
            leftEdge.append(lens.point(x - w, 1 - back, up: lift))
            rightEdge.append(lens.point(x + w, 1 - back, up: lift))
            tail = lens.point(x, 1 - back, up: lift)
            if i == 0 { head = tail }
        }
        leftEdge.append(contentsOf: rightEdge.reversed())
        ctx.fill(S.through(leftEdge), with: .linearGradient(Gradient(colors: colors), startPoint: head, endPoint: tail))
    }

    private func kart(_ ctx: GraphicsContext) {
        let foot = kartFoot
        let scale = kartScale
        let boost = frame.boost
        let sides: [CGFloat] = [-1, 1]

        // its shadow shrinks as it leaves the road
        let shadow = 60 * (1 - min(frame.height / 190, 0.42))
        halo(flattened(easel(ctx, at: foot, scale: scale), 0.2), .zero, shadow,
             [ink(0x0E0834, 0.62), ink(0x0E0834, 0.42), ink(0x0E0834, 0)])

        let tailGlow = [ink(0xFF4D7E, 0.75), ink(0xFF4D7E, 0.28), ink(0xFF4D7E, 0)]
        ribbon(ctx, offset: -19, up: 29, half: 4.6, length: 0.6, colors: tailGlow)
        ribbon(ctx, offset: 19, up: 29, half: 4.6, length: 0.6, colors: tailGlow)
        if boost > 0.02 {
            ribbon(ctx, offset: 0, up: 9, half: 15, length: 0.62,
                   colors: [ink(0x8FF4FF, 0.7 * boost), ink(0x39C8FF, 0.3 * boost), ink(0x39C8FF, 0)])
        }

        let airborne = frame.height > 0.5
        let stretch = 0.07 * frame.climb + (airborne ? 0.035 : 0) - 0.15 * frame.squash
        let rattle = airborne ? 0 : sin(2 * .pi * tick * 12) * 0.9 * u
        let roll = frame.lean * 0.2 - 0.05 * frame.climb + frame.roll
        let k = easel(ctx, at: CGPoint(x: foot.x, y: foot.y - frame.height * u + rattle), scale: scale,
                      turn: roll, wide: 1 - stretch * 0.6, tall: 1 + stretch)

        // front tyres and the nose, seen over the body
        for side in sides {
            k.fill(S.box(side * 31 - 6.5, -84, 13, 25, 4.8), with: .color(ink(0x231A52)))
            k.fill(S.box(side * 31 - 6.5, -84, 13, 7.5, 3.6), with: .color(ink(0x5A4BB0)))
        }
        k.fill(S.box(-17, -88, 34, 17, 7.5), with: down([ink(0xFFD24A), ink(0xFFA828)], -88, -71))

        // rear tyres with tread that rolls
        for side in sides {
            let left = side * 32 - 10.5
            let tyre = S.box(left, -32, 21, 32, 7.8)
            k.fill(tyre, with: down([ink(0x6656C4), ink(0x271C5C), ink(0x150E38)], -32, 0))
            let tread = clipped(k, to: tyre)
            for j in 0..<5 {
                let y = -32 + LaneDashClip.wrap(CGFloat(j) / 5 + tick * 36) * 32
                tread.fill(S.box(left, y, 21, 2.2), with: .color(ink(0xA898F5, 0.3)))
            }
            k.fill(S.box(left + 3, -31, 15, 3, 1.5), with: .color(ink(0xB8A9FF, 0.55)))
        }
        k.fill(S.box(-24, -18, 48, 14), with: .color(ink(0x160F3A)))

        // top deck
        let deck = S.softCorners(radius: 8, (-31, -40), (31, -40), (25, -78), (-25, -78))
        k.fill(deck, with: down([ink(0xFFF08A), ink(0xFFD63F)], -78, -40))
        let onDeck = clipped(k, to: deck)
        for side in sides {
            onDeck.fill(S.corners((side * 33, -40), (side * 26.5, -40), (side * 21, -78), (side * 27, -78)), with: .color(ink(0xFFB52E)))
        }
        onDeck.fill(S.corners((-25, -44), (-22, -44), (-17.5, -74), (-20, -74)), with: .color(ink(0xFFFFFF, 0.7)))
        onDeck.fill(S.box(-26, -79, 52, 3), with: .color(ink(0xFFFBD0, 0.9)))

        // cockpit and the driver: shoulders, scarf, helmet with cat ears
        k.fill(S.oval(CGPoint(x: 0, y: -57), 18, 11), with: .color(ink(0x2A2058)))
        k.fill(S.oval(CGPoint(x: 0, y: -63), 17, 8.5), with: down([ink(0xFFFDF6), ink(0xD9CBEA)], -71, -55))
        scarf(k)
        for side in sides {
            k.fill(S.softCorners(radius: 2.2, (side * 13.5, -87), (side * 10.5, -101.5), (side * 2, -92)), with: .color(ink(0xFFFDF6)))
            k.fill(S.softCorners(radius: 1.2, (side * 11.2, -89.5), (side * 9.8, -97), (side * 5.2, -92)), with: .color(ink(0xFF7AA0)))
        }
        let helmet = S.disc(CGPoint(x: 0, y: -81), 15)
        k.fill(helmet, with: .radialGradient(Gradient(colors: [ink(0xFFFFFF), ink(0xF4ECFA), ink(0xC2AEE2)]),
                                             center: CGPoint(x: -5, y: -87), startRadius: 1, endRadius: 24))
        let onHelmet = clipped(k, to: helmet)
        onHelmet.fill(S.box(-4.6, -97, 9.2, 32), with: down([ink(0xFF6A94), ink(0xE82E66)], -96, -66))
        onHelmet.fill(S.box(-16, -70.5, 32, 6), with: .color(ink(0x2A2058)))
        k.fill(S.oval(CGPoint(x: -7, y: -89), 3.6, 2.4), with: .color(ink(0xFFFFFF, 0.95)))

        // seat back
        k.fill(S.box(-13, -70, 26, 25, 7.5), with: down([ink(0x6A5AC8), ink(0x2E2270)], -70, -45))
        k.fill(S.box(-9.5, -68.5, 19, 2.6, 1.3), with: .color(ink(0xB8A9FF, 0.7)))

        // rear face, tail lights, the roundel with its bolt
        k.fill(S.box(-31.5, -43, 63, 29, 9.5), with: down([ink(0xFFC934), ink(0xFF961E)], -43, -14))
        k.fill(S.box(-26, -42, 52, 2.4, 1.2), with: .color(ink(0xFFF4B0, 0.9)))
        for side in sides {
            let light = CGPoint(x: side * 19.5, y: -30)
            halo(k, light, 17, [ink(0xFF5C8A, 0.7), ink(0xFF5C8A, 0)])
            k.fill(S.box(light.x - 8.5, light.y - 5.2, 17, 10.4, 5.2), with: .color(ink(0xFF2E62)))
            k.fill(S.box(light.x - 6.5, light.y - 3.8, 10, 5, 2.5), with: .color(ink(0xFF9AB4)))
            k.fill(S.disc(CGPoint(x: light.x - 4, y: light.y - 2.2), 1.5), with: .color(ink(0xFFFFFF)))
        }
        k.fill(S.disc(CGPoint(x: 0, y: -29.5), 8.6), with: .color(ink(0xFFFDF6)))
        k.fill(S.corners((1.8, -36), (-4.2, -28.4), (-0.6, -28.4), (-2.2, -23), (4.2, -30.8), (0.6, -30.8)), with: .color(ink(0xFF2E62)))

        // bumper and exhaust pipes
        k.fill(S.box(-34.5, -20, 69, 11.5, 5.5), with: down([ink(0x6656C4), ink(0x2A2058)], -20, -8.5))
        k.fill(S.box(-30, -19, 60, 2.2, 1.1), with: .color(ink(0xB8A9FF, 0.75)))
        for side in sides {
            let pipe = CGPoint(x: side * 11, y: -10)
            k.fill(S.disc(pipe, 4.6), with: .color(ink(0xCFC8F0)))
            k.fill(S.disc(pipe, 2.9), with: .color(ink(0x120A3C)))
        }

        // spoiler
        for side in sides {
            k.fill(S.box(side * 18 - 2.2, -53, 4.4, 12), with: .color(ink(0x2A2058)))
        }
        k.fill(S.box(-39, -60, 78, 9.5, 4.7), with: down([ink(0xFFFFFF), ink(0xE6D8F2)], -60, -50.5))
        k.fill(S.box(-35, -59.2, 70, 2, 1), with: .color(ink(0xFFFFFF)))
        for side in sides {
            k.fill(S.box(side * 39.5 - 3.6, -64, 7.2, 18, 3.2), with: down([ink(0xFF7AA0), ink(0xE82E66)], -64, -46))
        }

        // exhaust flames: short at a cruise, long and wide on boost
        let flicker = 0.75 + 0.25 * sin(tick * 2 * .pi * 40)
        let reach = (9 + 44 * boost) * flicker
        let girth = 4.4 + 4.2 * boost
        for side in sides {
            let x = side * 11
            if boost > 0.05 {
                halo(k, CGPoint(x: x, y: reach * 0.35 - 6), 26 * boost, [ink(0x7EEBFF, 0.6 * boost), ink(0x7EEBFF, 0)])
            }
            k.fill(flame(x, girth, reach), with: down([ink(0x49D6FF, 0.95), ink(0x3B8BFF, 0.75)], -9, reach - 9))
            k.fill(flame(x, girth * 0.62, reach * 0.68), with: .color(ink(0xB6F8FF)))
            k.fill(flame(x, girth * 0.3, reach * 0.38), with: .color(ink(0xFFFFFF)))
        }
    }

    /// A teardrop hanging from an exhaust pipe.
    private func flame(_ x: CGFloat, _ half: CGFloat, _ length: CGFloat) -> Path {
        let y: CGFloat = -9.5
        var path = Path()
        path.move(to: CGPoint(x: x - half, y: y))
        path.addQuadCurve(to: CGPoint(x: x, y: y + length), control: CGPoint(x: x - half * 0.95, y: y + length * 0.55))
        path.addQuadCurve(to: CGPoint(x: x + half, y: y), control: CGPoint(x: x + half * 0.95, y: y + length * 0.55))
        path.addQuadCurve(to: CGPoint(x: x - half, y: y), control: CGPoint(x: x, y: y - half * 1.2))
        path.closeSubpath()
        return path
    }

    /// Two tails that stream from the driver's neck, away from the turn and flatter on boost.
    private func scarf(_ k: GraphicsContext) {
        var c = k
        c.translateBy(x: 9, y: -69)
        c.rotate(by: .radians(Double(-frame.lean * 0.5 - 0.16 - 0.25 * frame.boost)))
        let tails: [(length: CGFloat, slope: CGFloat, beat: CGFloat, hex: UInt32)] = [(27, 3.5, 0.9, 0xD92A66), (35, -1.5, 0, 0xFF4D7E)]
        let steps = 10
        for tail in tails {
            var upper: [CGPoint] = []
            var lower: [CGPoint] = []
            for i in 0...steps {
                let f = CGFloat(i) / CGFloat(steps)
                let wave = sin(f * 5.2 - tick * 2 * .pi * 9 + tail.beat) * 3.4 * f
                let y = tail.slope * f + wave
                let half = 3.6 * (1 - 0.45 * f)
                upper.append(CGPoint(x: f * tail.length, y: y - half))
                lower.append(CGPoint(x: f * tail.length, y: y + half))
            }
            c.fill(S.through(upper + lower.reversed()), with: .color(ink(tail.hex)))
        }
        c.fill(S.disc(.zero, 4.3), with: .color(ink(0xFF4D7E)))
    }

    // MARK: Speed lines

    /// Thin wedges that fly out from the vanishing point. One set goes behind the world, one in front.
    private func speedLines(_ ctx: GraphicsContext, _ streaks: [LaneDashTables.Streak], inFront: Bool) {
        let reach = (width * width + height * height).squareRoot() * 0.6
        let boost = frame.boost
        let power = (inFront ? 0.25 + 0.75 * boost : 0.55 + 0.45 * boost) * frame.rush
        let inner: CGFloat = inFront ? 0.5 : 0.2
        let origin = CGPoint(x: midX, y: horizon)
        for streak in streaks {
            let f = LaneDashClip.wrap(frame.roadClock * streak.pace + streak.start)
            let dx = cos(streak.angle)
            let dy = sin(streak.angle)
            // fainter toward the sky
            let alpha = sin(f * .pi) * (0.36 - 0.24 * max(0, -dy)) * power
            if alpha <= 0.01 { continue }
            let from = (inner + (1 - inner) * f * f) * reach
            let to = from + streak.length * reach * (0.7 + 0.9 * boost) * (0.4 + f)
            let half = streak.width * u
            let tip = CGPoint(x: origin.x + dx * from, y: origin.y + dy * from)
            let end = CGPoint(x: origin.x + dx * to, y: origin.y + dy * to)
            let wedge = S.through([tip, CGPoint(x: end.x - dy * half, y: end.y + dx * half),
                                   CGPoint(x: end.x + dy * half, y: end.y - dx * half)])
            ctx.fill(wedge, with: .linearGradient(Gradient(colors: [ink(0xFFFFFF, 0), ink(0xFFFFFF, alpha)]),
                                                  startPoint: tip, endPoint: end))
        }
    }

    // MARK: Effects around the kart

    private func effects(_ ctx: GraphicsContext) {
        let foot = kartFoot
        let scale = kartScale
        let middle = CGPoint(x: foot.x, y: foot.y - (frame.height + 44) * u)

        // dust off the rear tyres while they are on the road
        if frame.height < 1 {
            let strength = 0.42 * min(1, frame.rush)
            for side in [-1, 1] as [CGFloat] {
                for i in 0..<5 {
                    let f = LaneDashClip.wrap(tick * 24 + CGFloat(i) / 5 + (side > 0 ? 0.37 : 0))
                    let at = lens.point(frame.kartX + side * (32 + 10 * f) - frame.lean * 30 * f, 1 - 0.3 * f, up: 4 + 14 * f)
                    ctx.fill(S.disc(at, (2.5 + 5.5 * f) * u), with: .color(ink(0xFFE6F2, strength * (1 - f))))
                }
            }
        }

        // a gem going in
        for pop in frame.pops {
            let a = pop.age
            let c = CGPoint(x: middle.x, y: middle.y - (10 + 34 * a) * u)
            ctx.stroke(S.disc(c, (14 + 44 * a) * scale), with: .color(ink(0xBDF8FF, 0.9 * (1 - a))),
                       lineWidth: 5.5 * (1 - a) * scale + 0.5)
            for j in 0..<7 {
                let angle = CGFloat(j) / 7 * 2 * .pi + pop.seed
                let out = (16 + 50 * a) * scale
                ctx.fill(S.star(CGPoint(x: c.x + cos(angle) * out, y: c.y + sin(angle) * out), (7.5 - 4 * a) * scale),
                         with: .color(ink(j % 2 == 0 ? 0xFFFFFF : 0x8FF4FF, 1 - a * a)))
            }
            if showHUD {
                write(ctx, "+1", size: 19 * u, at: CGPoint(x: c.x + 34 * u, y: c.y - (22 + 10 * a) * u),
                      fill: [ink(0xFFFFFF), ink(0x9DF6FF)], edge: ink(0x10307E), edgeWidth: 2 * u, alpha: 1 - a * a, slant: 0.12)
            }
        }

        // sparks off the thing the kart just shaved past
        if let miss = frame.nearMiss {
            let c = lens.point(frame.nearMissX, 0.93, up: 34)
            let fade = 1 - miss
            halo(ctx, c, (30 + 50 * miss) * u, [ink(0xFFFFFF, 0.75 * fade), ink(0xFFE27A, 0.3 * fade), ink(0xFFE27A, 0)])
            var dice = LaneDashScatter(404)
            for j in 0..<11 {
                let angle = -.pi * 0.92 + CGFloat(j) / 10 * .pi * 0.84 + dice.between(-0.08, 0.08)
                let from = (10 + 46 * miss) * u * dice.between(0.7, 1.2)
                let to = from + (16 + 14 * dice.unit()) * u * fade
                ctx.stroke(S.segment(CGPoint(x: c.x + cos(angle) * from, y: c.y + sin(angle) * from),
                                     CGPoint(x: c.x + cos(angle) * to, y: c.y + sin(angle) * to)),
                           with: .color(ink(j % 3 == 0 ? 0xFFE27A : 0xFFFFFF, fade)),
                           style: StrokeStyle(lineWidth: 2.8 * u, lineCap: .round))
            }
            for j in 0..<5 {
                let angle = -.pi * 0.85 + CGFloat(j) * 0.42
                let out = (26 + 60 * miss) * u
                ctx.fill(S.star(CGPoint(x: c.x + cos(angle) * out, y: c.y + sin(angle) * out - 8 * u), (8 - 3 * miss) * u),
                         with: .color(ink(0xFFFFFF, fade)))
            }
            if showHUD {
                let pop = 1 + 0.5 * exp(-miss * 14)
                let at = CGPoint(x: c.x - 36 * u, y: c.y - (86 + 16 * miss) * u)
                let alpha = 1 - LaneDashClip.ease(0.7, 1, miss)
                write(ctx, frame.nearMissTitle, size: 25 * u * pop, at: at, fill: [ink(0xFFFFFF), ink(0xFFE566)],
                      edge: ink(0x2A1466), edgeWidth: 2.6 * u, alpha: alpha, tilt: -0.1, slant: 0.16)
                write(ctx, frame.nearMissNote, size: 20 * u * pop, at: CGPoint(x: at.x + 6 * u, y: at.y + 25 * u),
                      fill: [ink(0xFFFFFF), ink(0xFFB3C9)], edge: ink(0x2A1466), edgeWidth: 2.2 * u, alpha: alpha, tilt: -0.1, slant: 0.16)
            }
        }

        // a boosted jump: a ring where it left the road, air rushing past underneath
        if let air = frame.flight {
            let ring = max(0, 1 - air * 2.2)
            if ring > 0 {
                var flat = ctx
                flat.translateBy(x: foot.x, y: foot.y)
                flat.scaleBy(x: 1, y: 0.26)
                flat.stroke(S.disc(.zero, (40 + 150 * air) * u), with: .color(ink(0xBDF8FF, 0.8 * ring)), lineWidth: 7 * u * ring + 1)
            }
            for j in 0..<6 {
                let f = LaneDashClip.wrap(tick * 30 + CGFloat(j) * 0.17)
                let x = middle.x + (CGFloat(j) - 2.5) * 13 * u
                let y = foot.y - frame.height * u + (8 + 46 * f) * u
                ctx.fill(S.box(x - 1.4 * u, y, 2.8 * u, (12 + 14 * f) * u, 1.4 * u), with: .color(ink(0xDFFBFF, 0.55 * (1 - f))))
            }
            if showHUD {
                let pop = 1 + 0.55 * exp(-air * 16)
                let alpha = 1 - LaneDashClip.ease(0.72, 1, air)
                let at = CGPoint(x: middle.x - 92 * u, y: middle.y - (50 + 14 * air) * u)
                write(ctx, frame.flightTitle, size: 28 * u * pop, at: at, fill: [ink(0xFFFFFF), ink(0x7EEBFF)],
                      edge: ink(0x14246E), edgeWidth: 2.8 * u, alpha: alpha, tilt: -0.12, slant: 0.18)
                write(ctx, frame.flightNote, size: 19 * u * pop, at: CGPoint(x: at.x + 8 * u, y: at.y + 26 * u),
                      fill: [ink(0xFFFFFF), ink(0xFFE566)], edge: ink(0x14246E), edgeWidth: 2.2 * u, alpha: alpha, tilt: -0.12, slant: 0.18)
            }
        }

        // touchdown
        if frame.squash > 0 {
            let a = frame.landRing
            var flat = ctx
            flat.translateBy(x: foot.x, y: foot.y)
            flat.scaleBy(x: 1, y: 0.26)
            flat.stroke(S.disc(.zero, (44 + 80 * a) * u), with: .color(ink(0xFFFFFF, 0.6 * (1 - a))), lineWidth: 6 * u * (1 - a) + 1)
        }
    }

    /// The burst where the kart hits something. progress runs 0...1.
    private func crashBurst(_ ctx: GraphicsContext, progress t: CGFloat, x: CGFloat) {
        guard t >= 0, t < 1 else { return }
        let c = lens.point(x, 1.12, up: 50)
        let fade = 1 - t
        halo(ctx, c, (46 + 110 * t) * u, [ink(0xFFFFFF, 0.9 * fade), ink(0xFFE27A, 0.4 * fade), ink(0xFF6A8E, 0)])
        let rays: [UInt32] = [0xFFE27A, 0xFFFFFF, 0xFF9AB4]
        var dice = LaneDashScatter(808)
        for j in 0..<16 {
            let angle = CGFloat(j) / 16 * 2 * .pi + dice.between(-0.1, 0.1)
            let from = (16 + 80 * t) * u * dice.between(0.7, 1.2)
            let to = from + (20 + 18 * dice.unit()) * u * fade
            ctx.stroke(S.segment(CGPoint(x: c.x + cos(angle) * from, y: c.y + sin(angle) * from),
                                 CGPoint(x: c.x + cos(angle) * to, y: c.y + sin(angle) * to)),
                       with: .color(ink(rays[j % 3], fade)), style: StrokeStyle(lineWidth: 3.2 * u, lineCap: .round))
        }
        for j in 0..<7 {
            let angle = CGFloat(j) * 0.9 + 0.3
            let out = (34 + 96 * t) * u
            ctx.fill(S.star(CGPoint(x: c.x + cos(angle) * out, y: c.y + sin(angle) * out), (10 - 5 * t) * u),
                     with: .color(ink(0xFFFFFF, fade)))
        }
    }

    private func vignette(_ ctx: GraphicsContext) {
        ctx.fill(S.box(0, height * 0.7, width, height * 0.3), with: down([ink(0x140A40, 0), ink(0x140A40, 0.55)], height * 0.7, height))
        ctx.fill(S.box(0, 0, width, height * 0.14), with: down([ink(0x120A3C, 0.4), ink(0x120A3C, 0)], 0, height * 0.14))
        ctx.fill(S.box(0, 0, width * 0.16, height), with: across([ink(0x140A40, 0.22), ink(0x140A40, 0)], 0, width * 0.16))
        ctx.fill(S.box(width * 0.84, 0, width * 0.16, height), with: across([ink(0x140A40, 0), ink(0x140A40, 0.22)], width * 0.84, width))
    }

    // MARK: Lettering and HUD

    /// Text with a soft drop shadow, a ring of outline copies, and a vertical gradient on top.
    private func stamp(_ ctx: GraphicsContext, _ text: GraphicsContext.ResolvedText, at point: CGPoint, anchor: UnitPoint,
                       fill: [Color], edge: Color, edgeWidth: CGFloat, top: CGFloat, bottom: CGFloat) {
        var copy = text
        copy.shading = .color(ink(0x0C0630, 0.45))
        ctx.draw(copy, at: CGPoint(x: point.x, y: point.y + edgeWidth * 1.7), anchor: anchor)
        copy.shading = .color(edge)
        for i in 0..<12 {
            let angle = CGFloat(i) / 12 * 2 * .pi
            ctx.draw(copy, at: CGPoint(x: point.x + cos(angle) * edgeWidth, y: point.y + sin(angle) * edgeWidth), anchor: anchor)
        }
        copy.shading = down(fill, top, bottom)
        ctx.draw(copy, at: point, anchor: anchor)
    }

    /// One centred line of outlined lettering, optionally tilted and slanted like a comic caption.
    private func write(_ ctx: GraphicsContext, _ string: String, size: CGFloat, at point: CGPoint, fill: [Color], edge: Color,
                       edgeWidth: CGFloat, alpha: CGFloat = 1, tilt: CGFloat = 0, slant: CGFloat = 0, weight: Font.Weight = .black) {
        if alpha <= 0.01 { return }
        var c = ctx
        c.opacity = Double(min(1, alpha))
        c.translateBy(x: point.x, y: point.y)
        if tilt != 0 { c.rotate(by: .radians(Double(tilt))) }
        if slant != 0 { c.concatenate(CGAffineTransform(a: 1, b: 0, c: -slant, d: 1, tx: 0, ty: 0)) }
        let text = c.resolve(Text(verbatim: string).font(.system(size: size, weight: weight, design: .rounded)))
        let tall = text.measure(in: CGSize(width: 4000, height: 4000)).height
        stamp(c, text, at: .zero, anchor: .center, fill: fill, edge: edge, edgeWidth: edgeWidth, top: -tall * 0.32, bottom: tall * 0.36)
    }

    /// 1234567 -> "1,234,567"
    static func thousands(_ number: Int) -> String {
        var digits = String(abs(number))
        var cut = digits.count - 3
        while cut > 0 {
            digits.insert(",", at: digits.index(digits.startIndex, offsetBy: cut))
            cut -= 3
        }
        return number < 0 ? "-" + digits : digits
    }

    private func hud(_ ctx: GraphicsContext) {
        let room = CGSize(width: 4000, height: 4000)

        // distance: a big number with a small gold "m" sitting on its baseline
        let number = ctx.resolve(Text(verbatim: Self.thousands(frame.distance)).font(.system(size: 46 * u, weight: .black, design: .rounded)))
        let metres = ctx.resolve(Text(verbatim: "m").font(.system(size: 22 * u, weight: .heavy, design: .rounded)))
        let numberSize = number.measure(in: room)
        let metresWidth = metres.measure(in: room).width
        let numberBase = number.firstBaseline(in: room)
        let metresBase = metres.firstBaseline(in: room)
        let space = 3 * u
        let left = midX - (numberSize.width + space + metresWidth) / 2
        let top = height * 0.170 - numberSize.height / 2
        stamp(ctx, number, at: CGPoint(x: left, y: top), anchor: .topLeading, fill: [ink(0xFFFFFF), ink(0xFFE4EE)],
              edge: ink(0x2A1466), edgeWidth: 2.8 * u, top: top + numberSize.height * 0.2, bottom: top + numberSize.height * 0.85)
        let metresTop = top + numberBase - metresBase
        stamp(ctx, metres, at: CGPoint(x: left + numberSize.width + space, y: metresTop), anchor: .topLeading,
              fill: [ink(0xFFE9A8), ink(0xFFC46A)], edge: ink(0x2A1466), edgeWidth: 2.2 * u, top: metresTop, bottom: top + numberBase)

        // under it: the gem count, and a second pill when there is something to say
        var count = ctx.resolve(Text(verbatim: "\(frame.gems)").font(.system(size: 17 * u, weight: .heavy, design: .rounded)))
        count.shading = .color(ink(0xFFFFFF))
        var extra = ctx.resolve(Text(verbatim: frame.pill ?? "").font(.system(size: 16 * u, weight: .black, design: .rounded)))
        extra.shading = .color(ink(0xFFFFFF))
        let tall = 29 * u
        let gemWide = 50 * u + count.measure(in: room).width
        let extraWide = extra.measure(in: room).width + 22 * u
        let between = 7 * u
        let rowWide = frame.pill == nil ? gemWide : gemWide + between + extraWide
        let rowLeft = midX - rowWide / 2
        let rowMid = height * 0.219
        let rowTop = rowMid - tall / 2
        let shade = GraphicsContext.Shading.color(ink(0x0C0630, 0.3))

        let gemPill = CGRect(x: rowLeft, y: rowTop, width: gemWide, height: tall)
        ctx.fill(Path(roundedRect: gemPill.offsetBy(dx: 0, dy: 2.5 * u), cornerRadius: tall / 2), with: shade)
        ctx.fill(Path(roundedRect: gemPill, cornerRadius: tall / 2), with: down([ink(0x2E1C78, 0.86), ink(0x1A1052, 0.86)], rowTop, rowTop + tall))
        ctx.stroke(Path(roundedRect: gemPill.insetBy(dx: 0.7 * u, dy: 0.7 * u), cornerRadius: tall / 2),
                   with: .color(ink(0xFFFFFF, 0.3)), lineWidth: 1.3 * u)
        gem(ctx, at: CGPoint(x: rowLeft + 22 * u, y: rowMid - 0.5 * u), scale: u * 0.58, turn: 0, glow: 0)
        ctx.draw(count, at: CGPoint(x: rowLeft + 37 * u, y: rowMid), anchor: .leading)

        guard frame.pill != nil else { return }
        let extraPill = CGRect(x: rowLeft + gemWide + between, y: rowTop, width: extraWide, height: tall)
        ctx.fill(Path(roundedRect: extraPill.offsetBy(dx: 0, dy: 2.5 * u), cornerRadius: tall / 2), with: shade)
        ctx.fill(Path(roundedRect: extraPill, cornerRadius: tall / 2),
                 with: down(frame.pillCool ? [ink(0x5CE6FF), ink(0x1F9BE8)] : [ink(0xFF6E98), ink(0xE82E66)], rowTop, rowTop + tall))
        ctx.fill(S.box(extraPill.minX + 6 * u, rowTop + 3 * u, extraWide - 12 * u, 3 * u, 1.5 * u), with: .color(ink(0xFFFFFF, 0.4)))
        ctx.draw(extra, at: CGPoint(x: extraPill.midX, y: rowMid), anchor: .center)
    }
}
