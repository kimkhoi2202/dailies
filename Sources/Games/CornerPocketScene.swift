import SwiftUI

// Corner Pocket: top-down pool against a friend. Drag to aim, pull the meter, let go to shoot.
//
// Everything is painted into one Canvas by CornerPocketPainter. The clip in the video feed builds a
// frame from a phase (0...1) and a fixed script; the playable game builds one from its live model.
// Lengths in the table's own units: the felt is 300 x 600 and a ball has a radius of 10.

public struct CornerPocketScene: View {
    public var phase: Double
    public var showHUD: Bool

    public init(phase: Double, showHUD: Bool) {
        self.phase = phase
        self.showHUD = showHUD
    }

    public var body: some View {
        Canvas(opaque: true, colorMode: .nonLinear, rendersAsynchronously: false) { context, size in
            if size.width <= 8 || size.height <= 8 { return }
            let frame = CornerPocketScript.frame(phase: phase, showHUD: showHUD)
            CornerPocketPainter(size: size, frame: frame).draw(&context)
        }
    }
}

// MARK: - Numbers

enum CornerPocketMath {
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

    /// The shortest turn from one angle to another, in -pi...pi.
    static func turn(from a: Double, to b: Double) -> Double {
        var d = (b - a).truncatingRemainder(dividingBy: 2 * Double.pi)
        if d > Double.pi { d -= 2 * Double.pi }
        if d < -Double.pi { d += 2 * Double.pi }
        return d
    }
}

/// SplitMix64. The rack, the friend's hand and the sparks each use their own salt.
struct CornerPocketRandom {
    static let round: UInt64 = 0x2545F4914F6CDD1D
    static let effects: UInt64 = 0xD1B54A32D192ED03
    static let pilot: UInt64 = 0x9E6C63D0676A9A99

    private var state: UInt64

    init(seed: UInt64, salt: UInt64) {
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
}

// MARK: - Table

enum CornerPocketTable {
    static let w = 300.0
    static let h = 600.0
    static let r = 10.0
    /// Pockets: four corners, then the two sides. Centres sit just outside the felt.
    static let pocketX: [Double] = [-3, 303, -3, 303, -8, 308]
    static let pocketY: [Double] = [-3, -3, 603, 603, 300, 300]
    static let pocketR: [Double] = [19, 19, 19, 19, 16, 16]
    /// Where a shot sends a ball to drop it in each pocket.
    static let aimX: [Double] = [5, 295, 5, 295, -2, 302]
    static let aimY: [Double] = [5, 5, 595, 595, 300, 300]
    /// No cushion within this far of a corner, or of the middle of a long side.
    static let cornerMouth = 20.0
    static let sideMouth = 15.0
    static let headX = 150.0
    static let headY = 462.0
    static let footY = 160.0

    /// 1 solids, 2 stripes, 0 the cue ball and the 8.
    static func group(_ n: Int) -> Int {
        if n >= 1 && n <= 7 { return 1 }
        if n >= 9 && n <= 15 { return 2 }
        return 0
    }

    /// Where a straight line from a point first meets a ball (as a ghost ball would) or a cushion.
    static func cast(_ balls: [CornerPocketBall], x: Double, y: Double, dx: Double, dy: Double) -> CornerPocketRay {
        var best = 1e9
        var hit = -1
        let reach = 4 * r * r
        for i in balls.indices where i > 0 && !balls[i].sunk {
            let bx = balls[i].x - x
            let by = balls[i].y - y
            let along = bx * dx + by * dy
            if along <= 0 { continue }
            let side = bx * bx + by * by - along * along
            if side >= reach { continue }
            let t = along - (reach - side).squareRoot()
            if t < best {
                best = Swift.max(0, t)
                hit = i
            }
        }
        var wall = 1e9
        if dx > 1e-6 { wall = Swift.min(wall, (w - r - x) / dx) }
        if dx < -1e-6 { wall = Swift.min(wall, (r - x) / dx) }
        if dy > 1e-6 { wall = Swift.min(wall, (h - r - y) / dy) }
        if dy < -1e-6 { wall = Swift.min(wall, (r - y) / dy) }
        if wall < best { return CornerPocketRay(t: Swift.max(0, wall), ball: -1) }
        return CornerPocketRay(t: best, ball: hit)
    }
}

struct CornerPocketRay {
    var t: Double
    /// Index into the balls, or -1 for a cushion.
    var ball: Int
}

struct CornerPocketBall {
    var number: Int
    var x: Double
    var y: Double
    var vx = 0.0
    var vy = 0.0
    var sunk = false
    /// Seconds since it dropped.
    var sinkAge = 0.0
    var pocket = 0
}

struct CornerPocketFloat {
    var x: Double
    var y: Double
    var text: String
    var age: Double
}

struct CornerPocketSpark {
    var x: Double
    var y: Double
    var vx: Double
    var vy: Double
    var age: Double
    var life: Double
    var tint: Int
}

struct CornerPocketRing {
    var x: Double
    var y: Double
    var age: Double
}

// MARK: - Colour

struct CornerPocketRGB {
    var r: Double
    var g: Double
    var b: Double

    init(_ hex: UInt32) {
        r = Double((hex >> 16) & 0xFF) / 255
        g = Double((hex >> 8) & 0xFF) / 255
        b = Double(hex & 0xFF) / 255
    }

    func color(_ alpha: Double = 1) -> Color { Color(.sRGB, red: r, green: g, blue: b, opacity: alpha) }
}

enum CornerPocketPalette {
    static let backdrop = CornerPocketRGB(0x17171A)
    static let feltCore = CornerPocketRGB(0x2A9479)
    static let feltEdge = CornerPocketRGB(0x1B6B58)
    static let cushion = CornerPocketRGB(0x155646)
    static let woodLight = CornerPocketRGB(0x8A4E26)
    static let woodDark = CornerPocketRGB(0x55290F)
    static let hole = CornerPocketRGB(0x0B1412)
    static let rim = CornerPocketRGB(0x2B1608)
    static let cueBall = CornerPocketRGB(0xF7F3EA)
    static let ink = CornerPocketRGB(0x151412)
    static let gold = CornerPocketRGB(0xF5B301)
    static let coral = CornerPocketRGB(0xF26D5B)
    static let you = CornerPocketRGB(0xD7F23A)
    static let friend = CornerPocketRGB(0xFFA85C)
    static let maple = CornerPocketRGB(0xE6C792)
    static let butt = CornerPocketRGB(0x4A2510)
    static let chalk = CornerPocketRGB(0x5D8FD8)

    /// Ball 1 to 7; the stripes 9 to 15 share them.
    static let tints: [CornerPocketRGB] = [
        CornerPocketRGB(0xF2B630), CornerPocketRGB(0x2F6FD6), CornerPocketRGB(0xE0453A), CornerPocketRGB(0x8E63C9),
        CornerPocketRGB(0xF07C2E), CornerPocketRGB(0x23A26B), CornerPocketRGB(0x9B2D3A),
    ]

    static func ball(_ n: Int) -> CornerPocketRGB {
        if n == 0 { return cueBall }
        if n == 8 { return ink }
        return tints[n >= 9 ? n - 9 : n - 1]
    }

    static let shade = Gradient(colors: [Color.white.opacity(0.0), Color.black.opacity(0.10), Color.black.opacity(0.42)])
    static let feltGlow = Gradient(colors: [feltCore.color(), feltEdge.color()])
    static let wood = Gradient(colors: [woodLight.color(), woodDark.color(), woodLight.color(0.95), woodDark.color()])
    static let backGlow = Gradient(colors: [feltCore.color(0.20), feltCore.color(0)])
    static let meterFill = Gradient(colors: [gold.color(), coral.color()])
}

// MARK: - Frame

/// Everything the painter needs for one picture.
struct CornerPocketFrame {
    var balls: [CornerPocketBall] = []
    var clock = 0.0
    var showCue = false
    var showGuide = false
    var guideAlpha = 1.0
    var aimAngle = -Double.pi / 2
    /// How far the cue is drawn back, 0...1.
    var pull = 0.0

    var showHUD = true
    var score = 0
    var sinceScore = 10.0
    var bestText: String?
    var names = ["You", "kaz"]
    /// 1 solids, 2 stripes, 0 not decided. Index 0 is the player.
    var groups = [0, 0]
    var versus = true
    var active = 0
    var lives = 3
    var status = ""
    var statusPulse = false
    var meterPower = 0.0
    var meterLive = false
    var praise: String?
    var praiseAge = 0.0
    var floats: [CornerPocketFloat] = []
    var sparks: [CornerPocketSpark] = []
    var rings: [CornerPocketRing] = []
    var dim = 0.0
}

// MARK: - Layout

/// Where the table, the meter and the labels sit on a screen of any size.
struct CornerPocketLayout {
    let W: Double
    let H: Double
    let u: Double
    /// Screen points per table unit.
    let s: Double
    /// The felt's top left corner on screen.
    let ox: Double
    let oy: Double
    let rail: Double
    let feltW: Double
    let feltH: Double
    let meterX: Double
    let meterY: Double
    let meterW: Double
    let meterH: Double
    /// Touches right of this line work the meter.
    let meterHitX: Double

    init(size: CGSize) {
        W = Double(size.width)
        H = Double(size.height)
        u = W / 402
        rail = 15 * u
        let top = Double(GameLayout.topBand) + 50 * u
        let bottom = H - Double(GameLayout.bottomInset) - 40 * u
        let column = 64 * u
        let maxW = W - column - 14 * u - 2 * rail
        let maxH = bottom - top - 2 * rail
        s = Swift.min(maxW / CornerPocketTable.w, maxH / CornerPocketTable.h)
        feltW = CornerPocketTable.w * s
        feltH = CornerPocketTable.h * s
        let tableW = feltW + 2 * rail
        let left = Swift.max(14 * u, (W - column - tableW) / 2)
        ox = left + rail
        oy = top + rail + Swift.max(0, (maxH - feltH) * 0.35)
        let tableRight = ox + feltW + rail
        meterW = 26 * u
        meterX = (tableRight + W) / 2 - meterW / 2
        meterY = oy + feltH * 0.16
        meterH = feltH * 0.68
        meterHitX = tableRight - 2 * u
    }

    func sx(_ x: Double) -> Double { ox + x * s }
    func sy(_ y: Double) -> Double { oy + y * s }
    func point(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: ox + x * s, y: oy + y * s) }
}

// MARK: - Painter

struct CornerPocketPainter {
    typealias M = CornerPocketMath
    typealias T = CornerPocketTable
    typealias P = CornerPocketPalette

    let L: CornerPocketLayout
    let f: CornerPocketFrame
    var u: Double { L.u }

    init(size: CGSize, frame: CornerPocketFrame) {
        L = CornerPocketLayout(size: size)
        f = frame
    }

    func draw(_ ctx: inout GraphicsContext) {
        drawBackdrop(&ctx)
        drawTable(&ctx)
        drawBalls(&ctx)
        if f.showGuide { drawGuide(&ctx) }
        if f.showCue { drawCue(&ctx) }
        drawEffects(&ctx)
        if f.showHUD {
            drawPlayers(&ctx)
            drawMeter(&ctx)
            drawStatus(&ctx)
            drawScore(&ctx)
        }
        drawPraise(&ctx)
        if f.dim > 0.01 {
            ctx.fill(Path(CGRect(x: 0, y: 0, width: L.W, height: L.H)), with: .color(.black.opacity(0.35 * f.dim)))
        }
    }

    // MARK: Table

    private func drawBackdrop(_ ctx: inout GraphicsContext) {
        let all = CGRect(x: 0, y: 0, width: L.W, height: L.H)
        ctx.fill(Path(all), with: .color(P.backdrop.color()))
        let centre = L.point(T.w / 2, T.h / 2)
        ctx.fill(Path(all), with: .radialGradient(P.backGlow, center: centre, startRadius: 0, endRadius: L.H * 0.62))
    }

    private func drawTable(_ ctx: inout GraphicsContext) {
        let felt = CGRect(x: L.ox, y: L.oy, width: L.feltW, height: L.feltH)
        let outer = felt.insetBy(dx: -L.rail, dy: -L.rail)
        let corner = 13 * u

        ctx.fill(Path(roundedRect: outer.offsetBy(dx: 0, dy: 7 * u), cornerRadius: corner), with: .color(.black.opacity(0.5)))
        ctx.fill(Path(roundedRect: outer, cornerRadius: corner),
                 with: .linearGradient(P.wood, startPoint: CGPoint(x: outer.minX, y: outer.minY),
                                       endPoint: CGPoint(x: outer.maxX, y: outer.maxY)))
        ctx.stroke(Path(roundedRect: outer.insetBy(dx: 1.2 * u, dy: 1.2 * u), cornerRadius: corner - 1),
                   with: .color(.white.opacity(0.14)), lineWidth: 1.4 * u)

        let lip = felt.insetBy(dx: -4.5 * u, dy: -4.5 * u)
        ctx.fill(Path(lip), with: .color(P.cushion.color()))
        let centre = CGPoint(x: felt.midX, y: felt.midY)
        ctx.fill(Path(felt), with: .radialGradient(P.feltGlow, center: centre, startRadius: 0, endRadius: L.feltH * 0.62))

        // The head string and the foot spot.
        var head = Path()
        head.move(to: L.point(0, T.headY))
        head.addLine(to: L.point(T.w, T.headY))
        ctx.stroke(head, with: .color(.white.opacity(0.07)), lineWidth: 1.2 * u)
        let spot = L.point(T.w / 2, T.footY)
        ctx.fill(Path(ellipseIn: CGRect(x: spot.x - 2 * u, y: spot.y - 2 * u, width: 4 * u, height: 4 * u)),
                 with: .color(.white.opacity(0.12)))

        // Sights on the rails.
        let sight = 2.3 * u
        let railMid = L.rail * 0.5
        for k in 1...3 {
            let x = L.sx(T.w * Double(k) / 4)
            for y in [Double(outer.minY) + railMid, Double(outer.maxY) - railMid] {
                ctx.fill(Path(ellipseIn: CGRect(x: x - sight, y: y - sight, width: 2 * sight, height: 2 * sight)),
                         with: .color(P.maple.color(0.75)))
            }
        }
        for k in 1...7 where k != 4 {
            let y = L.sy(T.h * Double(k) / 8)
            for x in [Double(outer.minX) + railMid, Double(outer.maxX) - railMid] {
                ctx.fill(Path(ellipseIn: CGRect(x: x - sight, y: y - sight, width: 2 * sight, height: 2 * sight)),
                         with: .color(P.maple.color(0.75)))
            }
        }

        for p in 0..<6 {
            let c = L.point(T.pocketX[p], T.pocketY[p])
            let rad = T.pocketR[p] * L.s * 1.08
            let rim = rad + 3.5 * u
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - rim, y: c.y - rim, width: 2 * rim, height: 2 * rim)), with: .color(P.rim.color()))
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - rad, y: c.y - rad, width: 2 * rad, height: 2 * rad)), with: .color(P.hole.color()))
        }
    }

    // MARK: Balls

    private func drawBalls(_ ctx: inout GraphicsContext) {
        let rad = T.r * L.s
        for b in f.balls where !b.sunk {
            let c = L.point(b.x, b.y)
            let shadow = CGRect(x: c.x - rad * 0.95 + 2.2 * u, y: c.y - rad * 0.9 + 3.4 * u, width: rad * 1.9, height: rad * 1.8)
            ctx.fill(Path(ellipseIn: shadow), with: .color(.black.opacity(0.32)))
        }
        for b in f.balls {
            if b.sunk {
                if b.sinkAge >= 0.28 { continue }
                let k = b.sinkAge / 0.28
                let pocket = L.point(T.pocketX[b.pocket], T.pocketY[b.pocket])
                drawBall(&ctx, b.number, pocket.x, pocket.y, rad * (1 - 0.6 * k), alpha: 1 - k)
            } else {
                let c = L.point(b.x, b.y)
                drawBall(&ctx, b.number, c.x, c.y, rad, alpha: 1)
            }
        }
    }

    func drawBall(_ ctx: inout GraphicsContext, _ n: Int, _ cx: Double, _ cy: Double, _ rad: Double, alpha: Double) {
        let box = CGRect(x: cx - rad, y: cy - rad, width: 2 * rad, height: 2 * rad)
        let circle = Path(ellipseIn: box)
        let tint = P.ball(n)
        if n >= 9 {
            ctx.fill(circle, with: .color(P.cueBall.color(alpha)))
            var band = ctx
            band.clip(to: circle)
            band.fill(Path(CGRect(x: cx - rad, y: cy - rad * 0.55, width: 2 * rad, height: rad * 1.1)), with: .color(tint.color(alpha)))
        } else {
            ctx.fill(circle, with: .color(tint.color(alpha)))
        }
        if n > 0 && rad > 4 {
            let dot = rad * 0.5
            ctx.fill(Path(ellipseIn: CGRect(x: cx - dot, y: cy - dot, width: 2 * dot, height: 2 * dot)),
                     with: .color(.white.opacity(0.96 * alpha)))
            if rad > 7 {
                let label = Text("\(n)").font(.system(size: rad * 0.68, weight: .heavy, design: .rounded))
                ctx.draw(label.foregroundColor(P.ink.color(alpha)), at: CGPoint(x: cx, y: cy), anchor: .center)
            }
        }
        let light = CGPoint(x: cx - rad * 0.38, y: cy - rad * 0.42)
        ctx.fill(circle, with: .radialGradient(P.shade, center: light, startRadius: 0, endRadius: rad * 1.6))
        let gleam = CGRect(x: cx - rad * 0.6, y: cy - rad * 0.66, width: rad * 0.46, height: rad * 0.32)
        ctx.fill(Path(ellipseIn: gleam), with: .color(.white.opacity(0.6 * alpha)))
    }

    // MARK: Aim

    private func drawGuide(_ ctx: inout GraphicsContext) {
        guard let cue = f.balls.first, !cue.sunk else { return }
        let dx = cos(f.aimAngle)
        let dy = sin(f.aimAngle)
        let ray = T.cast(f.balls, x: cue.x, y: cue.y, dx: dx, dy: dy)
        let gx = cue.x + dx * ray.t
        let gy = cue.y + dy * ray.t
        let alpha = f.guideAlpha
        let width = 2 * u

        if ray.t > T.r {
            var line = Path()
            line.move(to: L.point(cue.x + dx * T.r * 1.3, cue.y + dy * T.r * 1.3))
            line.addLine(to: L.point(gx - dx * T.r, gy - dy * T.r))
            let dash: [CGFloat] = [CGFloat(6 * u), CGFloat(5 * u)]
            ctx.stroke(line, with: .color(.white.opacity(0.85 * alpha)),
                       style: StrokeStyle(lineWidth: width, lineCap: .round, dash: dash, dashPhase: CGFloat(-f.clock * 18 * u)))
        }

        let g = L.point(gx, gy)
        let rad = T.r * L.s
        ctx.stroke(Path(ellipseIn: CGRect(x: g.x - rad, y: g.y - rad, width: 2 * rad, height: 2 * rad)),
                   with: .color(.white.opacity(0.95 * alpha)), lineWidth: 1.8 * u)

        if ray.ball > 0 {
            let b = f.balls[ray.ball]
            var nx = b.x - gx
            var ny = b.y - gy
            let len = Swift.max(1e-6, (nx * nx + ny * ny).squareRoot())
            nx /= len
            ny /= len
            let cut = Swift.max(0, dx * nx + dy * ny)
            let reach = 18 + 70 * cut
            var object = Path()
            object.move(to: L.point(b.x + nx * T.r, b.y + ny * T.r))
            object.addLine(to: L.point(b.x + nx * (T.r + reach), b.y + ny * (T.r + reach)))
            ctx.stroke(object, with: .color(.white.opacity(0.9 * alpha)), style: StrokeStyle(lineWidth: width, lineCap: .round))

            let tx = dx - cut * nx
            let ty = dy - cut * ny
            let tlen = (tx * tx + ty * ty).squareRoot()
            if tlen > 0.05 {
                let tr = 10 + 34 * (1 - cut)
                var glance = Path()
                glance.move(to: g)
                glance.addLine(to: L.point(gx + tx / tlen * tr, gy + ty / tlen * tr))
                ctx.stroke(glance, with: .color(.white.opacity(0.4 * alpha)), style: StrokeStyle(lineWidth: width * 0.8, lineCap: .round))
            }
        } else {
            var rx = dx
            var ry = dy
            if gx <= T.r + 0.5 || gx >= T.w - T.r - 0.5 { rx = -rx } else { ry = -ry }
            var bounce = Path()
            bounce.move(to: g)
            bounce.addLine(to: L.point(gx + rx * 42, gy + ry * 42))
            ctx.stroke(bounce, with: .color(.white.opacity(0.4 * alpha)), style: StrokeStyle(lineWidth: width * 0.8, lineCap: .round))
        }
    }

    private func drawCue(_ ctx: inout GraphicsContext) {
        guard let cue = f.balls.first, !cue.sunk else { return }
        let dx = cos(f.aimAngle)
        let dy = sin(f.aimAngle)
        let c = L.point(cue.x, cue.y)
        let gap = (T.r + 3) * L.s + (4 + 62 * f.pull) * u
        let length = 300 * u
        func at(_ d: Double) -> CGPoint { CGPoint(x: c.x - dx * d, y: c.y - dy * d) }

        var whole = Path()
        whole.move(to: at(gap))
        whole.addLine(to: at(gap + length))
        ctx.stroke(whole.offsetBy(dx: 3 * u, dy: 6 * u), with: .color(.black.opacity(0.35)),
                   style: StrokeStyle(lineWidth: 7 * u, lineCap: .round))

        var shaft = Path()
        shaft.move(to: at(gap + 4 * u))
        shaft.addLine(to: at(gap + length * 0.62))
        ctx.stroke(shaft, with: .color(P.maple.color()), style: StrokeStyle(lineWidth: 5.4 * u, lineCap: .butt))

        var buttEnd = Path()
        buttEnd.move(to: at(gap + length * 0.62))
        buttEnd.addLine(to: at(gap + length))
        ctx.stroke(buttEnd, with: .color(P.butt.color()), style: StrokeStyle(lineWidth: 7.4 * u, lineCap: .round))

        var wrap = Path()
        wrap.move(to: at(gap + length * 0.62))
        wrap.addLine(to: at(gap + length * 0.66))
        ctx.stroke(wrap, with: .color(P.gold.color()), style: StrokeStyle(lineWidth: 7.6 * u, lineCap: .butt))

        var tip = Path()
        tip.move(to: at(gap))
        tip.addLine(to: at(gap + 4 * u))
        ctx.stroke(tip, with: .color(P.chalk.color()), style: StrokeStyle(lineWidth: 5 * u, lineCap: .round))

        var gleam = Path()
        gleam.move(to: at(gap + 8 * u))
        gleam.addLine(to: at(gap + length * 0.6))
        ctx.stroke(gleam.offsetBy(dx: -dy * 1.2 * u, dy: dx * 1.2 * u), with: .color(.white.opacity(0.35)),
                   style: StrokeStyle(lineWidth: 1.2 * u, lineCap: .round))
    }

    // MARK: Effects

    private func drawEffects(_ ctx: inout GraphicsContext) {
        for ring in f.rings {
            let k = M.clamp(ring.age / 0.55)
            let c = L.point(ring.x, ring.y)
            let rad = (14 + 40 * M.easeOut(k)) * L.s
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - rad, y: c.y - rad, width: 2 * rad, height: 2 * rad)),
                       with: .color(P.gold.color(0.9 * (1 - k))), lineWidth: (4 - 3 * k) * u)
        }
        for spark in f.sparks {
            let k = M.clamp(spark.age / spark.life)
            let c = L.point(spark.x, spark.y)
            let rad = (3.2 - 2.2 * k) * u
            let tint = spark.tint == 0 ? P.gold : P.ball(spark.tint)
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - rad, y: c.y - rad, width: 2 * rad, height: 2 * rad)), with: .color(tint.color(1 - k)))
        }
        for float in f.floats {
            let k = M.clamp(float.age / 1.1)
            let rise = 46 * u * M.easeOut(k)
            let pop = 1 + 0.35 * exp(-12 * float.age)
            let alpha = M.smooth(0, 0.06, float.age) * (1 - M.smooth(0.65, 1, k))
            let x = M.clamp(L.sx(float.x), L.ox + 30 * u, L.ox + L.feltW - 30 * u)
            let y = M.clamp(L.sy(float.y), L.oy + 30 * u, L.oy + L.feltH - 10 * u) - rise
            let text = Text(float.text).font(.system(size: 22 * u * pop, weight: .black, design: .rounded))
            ctx.draw(text.foregroundColor(.black.opacity(0.4 * alpha)), at: CGPoint(x: x, y: y + 2 * u), anchor: .center)
            ctx.draw(text.foregroundColor(P.gold.color(alpha)), at: CGPoint(x: x, y: y), anchor: .center)
        }
    }

    private func drawPraise(_ ctx: inout GraphicsContext) {
        guard let praise = f.praise else { return }
        let age = f.praiseAge
        let arrive = M.easeOut(M.clamp(age / 0.14))
        let alpha = arrive * (1 - M.smooth(0.9, 1.3, age))
        if alpha <= 0.01 { return }
        let size = 44 * u * (0.7 + 0.3 * arrive + 0.18 * exp(-10 * age))
        let text = Text(praise).font(.system(size: size, weight: .black, design: .rounded)).italic()
        let x = L.ox + L.feltW / 2
        let y = L.oy + L.feltH * 0.42 - 18 * u * age
        ctx.draw(text.foregroundColor(.black.opacity(0.35 * alpha)), at: CGPoint(x: x, y: y + 3.5 * u), anchor: .center)
        ctx.draw(text.foregroundColor(.white.opacity(alpha)), at: CGPoint(x: x, y: y), anchor: .center)
    }

    // MARK: HUD

    private func drawScore(_ ctx: inout GraphicsContext) {
        let y = (Double(GameLayout.statusBarHeight) + Double(GameLayout.topBand)) / 2 + 1
        let pop = 1 + 0.22 * exp(-9 * f.sinceScore) * M.smooth(0, 0.04, f.sinceScore)
        let text = Text("\(f.score)").font(.system(size: 38 * u * pop, weight: .heavy, design: .rounded)).monospacedDigit()
        ctx.draw(text.foregroundColor(.black.opacity(0.4)), at: CGPoint(x: L.W / 2, y: y + 2.5 * u), anchor: .center)
        ctx.draw(text.foregroundColor(.white), at: CGPoint(x: L.W / 2, y: y), anchor: .center)
        if let best = f.bestText {
            let label = Text(best).font(.system(size: 10 * u, weight: .bold, design: .rounded)).kerning(1.6 * u)
            ctx.draw(label.foregroundColor(.white.opacity(0.55)), at: CGPoint(x: L.W / 2, y: y + 24 * u), anchor: .center)
        }
    }

    private func groupWord(_ g: Int) -> String {
        g == 1 ? "solids" : (g == 2 ? "stripes" : "")
    }

    private func drawPlayers(_ ctx: inout GraphicsContext) {
        let y = Double(GameLayout.topBand) + 12 * u
        let left = L.ox - L.rail + 2 * u
        let right = L.ox + L.feltW + L.rail - 2 * u
        drawPlayer(&ctx, side: 0, edge: left, y: y)
        if f.versus {
            drawPlayer(&ctx, side: 1, edge: right, y: y)
        } else {
            drawLives(&ctx, edge: right, y: y)
        }
    }

    private func drawPlayer(_ ctx: inout GraphicsContext, side: Int, edge: Double, y: Double) {
        let on = f.active == side
        let dir = side == 0 ? 1.0 : -1.0
        let rad = 13 * u
        let cx = edge + dir * rad
        let tint = side == 0 ? P.you : P.friend
        let alpha = on ? 1.0 : 0.5
        if on {
            let glow = rad + (3 + 1.5 * sin(f.clock * 5)) * u
            ctx.fill(Path(ellipseIn: CGRect(x: cx - glow, y: y - glow, width: 2 * glow, height: 2 * glow)), with: .color(tint.color(0.28)))
        }
        ctx.fill(Path(ellipseIn: CGRect(x: cx - rad, y: y - rad, width: 2 * rad, height: 2 * rad)), with: .color(tint.color(alpha)))
        let name = f.names[side]
        let initial = Text(String(name.prefix(1)).uppercased()).font(.system(size: 14 * u, weight: .heavy, design: .rounded))
        ctx.draw(initial.foregroundColor(P.ink.color()), at: CGPoint(x: cx, y: y), anchor: .center)

        let group = groupWord(f.groups[side])
        let line = group.isEmpty ? name : "\(name) · \(group)"
        let label = Text(line).font(.system(size: 14.5 * u, weight: .heavy, design: .rounded))
        let tx = cx + dir * (rad + 7 * u)
        let color = on ? (side == 0 ? P.gold.color() : Color.white) : Color.white.opacity(0.55)
        ctx.draw(label.foregroundColor(color), at: CGPoint(x: tx, y: y - 5 * u), anchor: side == 0 ? .leading : .trailing)

        // The balls still to sink, small, under the name.
        let g = f.groups[side]
        let mini = 4.6 * u
        for k in 0..<7 {
            let n = g == 2 ? 9 + k : 1 + k
            var down = false
            if g != 0 { for b in f.balls where b.number == n { down = b.sunk } }
            let mx = tx + dir * (mini + Double(k) * (2 * mini + 2.6 * u))
            let my = y + 10 * u
            if g == 0 {
                ctx.stroke(Path(ellipseIn: CGRect(x: mx - mini, y: my - mini, width: 2 * mini, height: 2 * mini)),
                           with: .color(.white.opacity(0.22)), lineWidth: 1.2 * u)
            } else if down {
                ctx.fill(Path(ellipseIn: CGRect(x: mx - mini, y: my - mini, width: 2 * mini, height: 2 * mini)), with: .color(.white.opacity(0.12)))
            } else {
                drawBall(&ctx, n, mx, my, mini, alpha: alpha)
            }
        }
    }

    private func drawLives(_ ctx: inout GraphicsContext, edge: Double, y: Double) {
        let label = Text("MISSES LEFT").font(.system(size: 10.5 * u, weight: .heavy, design: .rounded)).kerning(1.4 * u)
        ctx.draw(label.foregroundColor(.white.opacity(0.6)), at: CGPoint(x: edge, y: y - 5 * u), anchor: .trailing)
        let rad = 5.2 * u
        for k in 0..<3 {
            let x = edge - rad - Double(k) * (2 * rad + 4 * u)
            let box = CGRect(x: x - rad, y: y + 10 * u - rad, width: 2 * rad, height: 2 * rad)
            if k < f.lives {
                ctx.fill(Path(ellipseIn: box), with: .color(P.coral.color()))
            } else {
                ctx.stroke(Path(ellipseIn: box), with: .color(.white.opacity(0.3)), lineWidth: 1.4 * u)
            }
        }
    }

    private func drawMeter(_ ctx: inout GraphicsContext) {
        let track = CGRect(x: L.meterX, y: L.meterY, width: L.meterW, height: L.meterH)
        let corner = L.meterW / 2
        ctx.fill(Path(roundedRect: track, cornerRadius: corner), with: .color(.white.opacity(0.09)))
        let power = M.clamp(f.meterPower)
        if power > 0.005 {
            let fill = CGRect(x: track.minX, y: track.minY, width: track.width, height: Swift.max(track.width, track.height * power))
            ctx.fill(Path(roundedRect: fill, cornerRadius: corner),
                     with: .linearGradient(P.meterFill, startPoint: CGPoint(x: fill.midX, y: track.minY),
                                           endPoint: CGPoint(x: fill.midX, y: track.maxY)))
            let knobY = fill.maxY
            let knob = CGRect(x: track.minX - 4 * u, y: knobY - 5 * u, width: track.width + 8 * u, height: 10 * u)
            ctx.fill(Path(roundedRect: knob, cornerRadius: 5 * u), with: .color(.white))
        } else {
            let knob = CGRect(x: track.minX - 4 * u, y: track.minY - 5 * u, width: track.width + 8 * u, height: 10 * u)
            ctx.fill(Path(roundedRect: knob, cornerRadius: 5 * u), with: .color(.white.opacity(f.meterLive ? 0.95 : 0.35)))
        }
        if f.meterLive && power < 0.02 {
            // Chevrons that point the way to pull.
            let pulse = 0.5 + 0.5 * sin(f.clock * 4)
            for k in 0..<3 {
                let cy = track.minY + 26 * u + Double(k) * 13 * u + pulse * 5 * u
                var v = Path()
                v.move(to: CGPoint(x: track.midX - 6 * u, y: cy - 3 * u))
                v.addLine(to: CGPoint(x: track.midX, y: cy + 3 * u))
                v.addLine(to: CGPoint(x: track.midX + 6 * u, y: cy - 3 * u))
                let a = (0.25 + 0.25 * Double(k)) * (0.6 + 0.4 * pulse)
                ctx.stroke(v, with: .color(.white.opacity(a)), style: StrokeStyle(lineWidth: 2.4 * u, lineCap: .round, lineJoin: .round))
            }
        }
        let word = Text("POWER").font(.system(size: 9 * u, weight: .heavy, design: .rounded)).kerning(1.2 * u)
        ctx.draw(word.foregroundColor(.white.opacity(0.5)), at: CGPoint(x: track.midX, y: track.maxY + 14 * u), anchor: .center)
    }

    private func drawStatus(_ ctx: inout GraphicsContext) {
        if f.status.isEmpty { return }
        let y = L.oy + L.feltH + L.rail + 22 * u
        let alpha = f.statusPulse ? 0.75 + 0.25 * sin(f.clock * 3.2) : 0.92
        let text = Text(f.status).font(.system(size: 15.5 * u, weight: .heavy, design: .rounded))
        ctx.draw(text.foregroundColor(.white.opacity(alpha)), at: CGPoint(x: L.W / 2, y: y), anchor: .center)
    }
}

// MARK: - The clip

/// A scripted shot for covers and the Videos feed: aim, pull, strike, and the red ball drops in the top corner.
enum CornerPocketScript {
    typealias M = CornerPocketMath

    static let cueX = 110.0
    static let cueY = 420.0
    static let targetX = 232.0
    static let targetY = 92.0
    static let pocket = 1
    static let layout: [(Int, Double, Double)] = [
        (1, 60, 250), (2, 195, 322), (4, 95, 140), (5, 250, 380), (7, 40, 520), (8, 150, 200),
        (9, 244, 212), (10, 70, 335), (12, 268, 262), (13, 128, 88), (14, 205, 476), (15, 28, 162),
    ]

    static func frame(phase raw: Double, showHUD: Bool) -> CornerPocketFrame {
        let phase = M.clamp(raw)
        var f = CornerPocketFrame()
        f.showHUD = showHUD
        f.clock = phase * 6
        f.names = ["You", "kaz"]
        f.groups = [1, 2]
        f.versus = true
        f.active = 0

        let ax = CornerPocketTable.aimX[pocket]
        let ay = CornerPocketTable.aimY[pocket]
        var ox = ax - targetX
        var oy = ay - targetY
        let olen = (ox * ox + oy * oy).squareRoot()
        ox /= olen
        oy /= olen
        let gx = targetX - ox * 2 * CornerPocketTable.r
        let gy = targetY - oy * 2 * CornerPocketTable.r
        var cx = gx - cueX
        var cy = gy - cueY
        let clen = (cx * cx + cy * cy).squareRoot()
        cx /= clen
        cy /= clen
        let angle = atan2(cy, cx)
        let cut = cx * ox + cy * oy

        // The cue ball: still, then to the ghost spot, then off along the tangent.
        let travel = M.easeOut(M.clamp((phase - 0.42) / 0.18))
        var bx = cueX + (gx - cueX) * travel
        var by = cueY + (gy - cueY) * travel
        if phase > 0.6 {
            var tx = cx - cut * ox
            var ty = cy - cut * oy
            let tlen = Swift.max(1e-6, (tx * tx + ty * ty).squareRoot())
            tx /= tlen
            ty /= tlen
            let drift = 46 * M.easeOut(M.clamp((phase - 0.6) / 0.3))
            bx = gx + tx * drift
            by = gy + ty * drift
        }
        f.balls.append(CornerPocketBall(number: 0, x: bx, y: by))

        let roll = M.easeOut(M.clamp((phase - 0.6) / 0.2))
        var red = CornerPocketBall(number: 3, x: targetX + (ax - targetX) * roll, y: targetY + (ay - targetY) * roll)
        if phase >= 0.8 {
            red.sunk = true
            red.pocket = pocket
            red.sinkAge = (phase - 0.8) * 2
        }
        f.balls.append(red)
        for (n, x, y) in layout { f.balls.append(CornerPocketBall(number: n, x: x, y: y)) }
        f.balls.append(CornerPocketBall(number: 6, x: 0, y: 0, sunk: true, sinkAge: 9))
        f.balls.append(CornerPocketBall(number: 11, x: 0, y: 0, sunk: true, sinkAge: 9))

        if phase < 0.43 {
            f.showCue = true
            f.showGuide = phase < 0.4
            let settle = M.easeOut(M.clamp(phase / 0.22))
            f.aimAngle = angle - 0.32 * (1 - settle)
            let draw = M.smooth(0.18, 0.38, phase)
            let strike = M.clamp((phase - 0.4) / 0.03)
            f.pull = 0.85 * draw * (1 - strike)
            f.meterPower = f.pull
        } else {
            f.aimAngle = angle
        }
        f.meterLive = phase < 0.18
        f.status = phase < 0.43 ? "Your shot" : ""

        f.score = 1200
        if phase >= 0.8 {
            let age = (phase - 0.8) * 5
            let pocketX = CornerPocketTable.pocketX[pocket]
            let pocketY = CornerPocketTable.pocketY[pocket]
            f.score = 1200 + Int(100 * M.clamp(age / 0.4))
            f.sinceScore = age
            f.rings.append(CornerPocketRing(x: pocketX, y: pocketY, age: age * 0.5))
            for k in 0..<12 {
                let a = Double.pi * 0.5 + Double(k) / 12 * Double.pi * 1.1
                let speed = 90 + Double(k % 4) * 30
                let t = age * 0.6
                f.sparks.append(CornerPocketSpark(x: pocketX + cos(a) * speed * t, y: pocketY + sin(a) * speed * t,
                                                  vx: 0, vy: 0, age: t, life: 0.9, tint: k % 3 == 0 ? 0 : 3))
            }
            f.floats.append(CornerPocketFloat(x: targetX - 20, y: targetY + 30, text: "+100", age: Swift.min(age * 0.5, 0.9)))
            f.praise = "Nice"
            f.praiseAge = Swift.min(age * 0.5, 0.85)
        }
        return f
    }
}
