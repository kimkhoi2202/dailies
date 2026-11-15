import SwiftUI

// Corner Pocket: top-down pool against a friend. Sink your group, then the 8.
//
// Shared by the playable game and the clip:
// CornerPocketTable    the balls and one fixed physics step with no randomness in it, so one angle and
//                      one power always roll out the same way and a stored shot replays exactly.
// CornerPocketLayout   where the table, the meter and the labels sit on a screen of any size.
// CornerPocketPainter  paints one CornerPocketFrame into a Canvas.
// CornerPocketClip     a scripted moment for covers and the Videos feed, built from a phase.

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
            let frame = CornerPocketClip.frame(at: phase, showHUD: showHUD)
            CornerPocketPainter(size: size).draw(frame, &context)
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

    /// A scale that springs up and settles in about 0.15 s with a small overshoot. 1 at rest.
    static func pop(_ age: Double, _ amount: Double = 0.3) -> Double {
        if age < 0 || age > 0.7 { return 1 }
        return 1 + amount * 1.6 * exp(-age * 11) * sin(age * 26)
    }

    /// The signed turn from one angle to another, the short way round.
    static func turn(from a: Double, to b: Double) -> Double {
        var d = (b - a).truncatingRemainder(dividingBy: 2 * Double.pi)
        if d > Double.pi { d -= 2 * Double.pi } else if d < -Double.pi { d += 2 * Double.pi }
        return d
    }
}

/// SplitMix64. The round and the scripted player use different salts so they never share a sequence.
struct CornerPocketRandom {
    static let round: UInt64 = 0x2545F4914F6CDD1D
    static let pilot: UInt64 = 0xD1B54A32D192ED03

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

    /// Roughly normal, centred on 0 with a spread of 1.
    mutating func gauss() -> Double {
        (next() + next() + next() + next() - 2) * 1.732
    }
}

// MARK: - Colour

struct CornerPocketTint {
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

    func color(_ alpha: Double = 1) -> Color { Color(.sRGB, red: r, green: g, blue: b, opacity: alpha) }
}

enum CornerPocketPalette {
    typealias T = CornerPocketTint

    static let ink = T(hex: 0x151412)
    static let cream = T(hex: 0xF8F6F1)
    static let white = T(1, 1, 1)
    static let black = T(0, 0, 0)
    static let cushion = T(hex: 0x226F59)
    static let track = T(hex: 0x2E2C29)
    static let amber = T(hex: 0xF2A93B)
    static let coral = T(hex: 0xF0654F)
    static let lime = T(hex: 0xD9F25A)
    static let peach = T(hex: 0xFFB27A)
    static let chalk = T(hex: 0x7FB2E5)
    static let cueBall = T(hex: 0xF7F4EC)

    static let meterFill = Gradient(colors: [amber.color(), coral.color()])
    static let lamp = Gradient(colors: [white.color(0.06), white.color(0)])

    /// Solids are 1 to 4, stripes 9 to 12, the cue ball 0.
    static func ball(_ number: Int) -> T {
        switch number {
        case 0: return cueBall
        case 1: return T(hex: 0xF2B83A)
        case 2: return T(hex: 0x3B6FE0)
        case 3: return T(hex: 0xE04B3A)
        case 4: return T(hex: 0x8B66D6)
        case 8: return T(hex: 0x1A1917)
        case 9: return T(hex: 0x1FA595)
        case 10: return T(hex: 0xF07A35)
        case 11: return T(hex: 0xE65F8E)
        default: return T(hex: 0x5BB65A)
        }
    }
}

// MARK: - The table

struct CornerPocketHole {
    let x: Double
    let y: Double
    /// A ball whose centre comes this close drops.
    let reach: Double
    let drawRadius: Double
}

struct CornerPocketBall {
    var number: Int
    var x: Double
    var y: Double
    var vx = 0.0
    var vy = 0.0
    var live = true
    /// Seconds since it dropped. Below zero while it is on the table.
    var sunk = -1.0
    var hole = 0
    var dropX = 0.0
    var dropY = 0.0

    init(_ number: Int, _ x: Double, _ y: Double) {
        self.number = number
        self.x = x
        self.y = y
    }
}

/// What the aim line shows: where the cue ball meets the first ball or cushion along the aim.
struct CornerPocketAim {
    var angle: Double
    var cueX: Double
    var cueY: Double
    var ghostX: Double
    var ghostY: Double
    /// Index of the ball it meets, or -1 for a cushion.
    var target: Int
    /// The way the struck ball goes.
    var nx: Double
    var ny: Double
    /// The way the cue ball glances off.
    var tx: Double
    var ty: Double
    /// 1 for a full hit, 0 for a thin one.
    var along: Double
}

/// The balls and the physics. Lengths are in table widths: the felt runs 0...1 across and 0...2 down,
/// the rack at the top. Times are in seconds.
struct CornerPocketTable {
    static let radius = 0.036
    static let length = 2.0
    static let step = 1.0 / 240
    static let rollDrag = 0.7
    static let speedDrag = 0.55
    static let stopSpeed = 0.012
    static let ballBounce = 0.95
    static let railBounce = 0.76
    static let railGrip = 0.95
    static let cornerMouth = 0.1
    static let sideMouth = 0.058
    static let minSpeed = 0.3
    static let maxSpeed = 4.2
    static let sinkLength = 0.3
    static let headY = 1.5
    static let footY = 0.5

    static let holes: [CornerPocketHole] = [
        CornerPocketHole(x: -0.016, y: -0.016, reach: 0.07, drawRadius: 0.084),
        CornerPocketHole(x: 1.016, y: -0.016, reach: 0.07, drawRadius: 0.084),
        CornerPocketHole(x: -0.03, y: 1, reach: 0.05, drawRadius: 0.062),
        CornerPocketHole(x: 1.03, y: 1, reach: 0.05, drawRadius: 0.062),
        CornerPocketHole(x: -0.016, y: 2.016, reach: 0.07, drawRadius: 0.084),
        CornerPocketHole(x: 1.016, y: 2.016, reach: 0.07, drawRadius: 0.084),
    ]

    /// Index 0 is always the cue ball.
    var balls: [CornerPocketBall]
    /// The first ball the cue ball touched on this shot.
    private(set) var firstHit: Int?
    /// Numbers of the balls that dropped on this shot, in order.
    private(set) var potted: [Int] = []
    /// The hardest contact since the game last read it, as a closing speed.
    var impact = 0.0
    /// Time simulated on this shot.
    private(set) var elapsed = 0.0
    private var carry = 0.0

    init(balls: [CornerPocketBall]) {
        self.balls = balls
        potted.reserveCapacity(16)
    }

    static func speed(forPower power: Double) -> Double {
        minSpeed + (maxSpeed - minSpeed) * CornerPocketMath.clamp(power)
    }

    static func power(forSpeed speed: Double) -> Double {
        (speed - minSpeed) / (maxSpeed - minSpeed)
    }

    /// A fresh rack: a diamond on the foot spot with the 8 in the middle. order fills the other eight places.
    static func racked(_ order: [Int], cueX: Double) -> CornerPocketTable {
        var balls = [CornerPocketBall(0, cueX, headY)]
        let gap = 2 * radius + 0.0008
        let rowGap = gap * 0.8660254
        let rows = [1, 2, 3, 2, 1]
        var next = 0
        for (k, n) in rows.enumerated() {
            for j in 0..<n {
                let x = 0.5 + (Double(j) - Double(n - 1) / 2) * gap
                let y = footY - Double(k) * rowGap
                if k == 2 && j == 1 {
                    balls.append(CornerPocketBall(8, x, y))
                } else {
                    balls.append(CornerPocketBall(order[next % order.count], x, y))
                    next += 1
                }
            }
        }
        return CornerPocketTable(balls: balls)
    }

    var cue: CornerPocketBall { balls[0] }

    var moving: Bool {
        for b in balls where b.live && (b.vx != 0 || b.vy != 0) { return true }
        return false
    }

    func index(of number: Int) -> Int? { balls.firstIndex { $0.number == number } }

    /// Bit k is set while ball k of the group is on the table. Group 1 is 1...4, group 2 is 9...12.
    func left(group: Int) -> Int {
        var mask = 0
        for b in balls where b.live && b.number != 0 && b.number != 8 {
            let solid = b.number < 8
            if (group == 1) == solid { mask |= 1 << (solid ? b.number - 1 : b.number - 9) }
        }
        return mask
    }

    /// Object balls other than the 8 still on the table.
    var colorsLeft: Int {
        var n = 0
        for b in balls where b.live && b.number != 0 && b.number != 8 { n += 1 }
        return n
    }

    // MARK: Shots

    mutating func strike(angle: Double, power: Double) {
        let speed = Self.speed(forPower: power)
        balls[0].vx = cos(angle) * speed
        balls[0].vy = sin(angle) * speed
        firstHit = nil
        potted.removeAll(keepingCapacity: true)
        impact = 0
        elapsed = 0
        carry = 0
    }

    /// Runs the fixed step for as long as dt covers. Only the number of steps decides the outcome,
    /// never the frame rate.
    mutating func advance(_ dt: Double) {
        if dt <= 0 { return }
        carry += dt
        while carry >= Self.step {
            carry -= Self.step
            if moving { substep() } else { ageSunk(Self.step) }
        }
    }

    private mutating func ageSunk(_ h: Double) {
        for i in balls.indices where balls[i].sunk >= 0 && balls[i].sunk < 10 { balls[i].sunk += h }
    }

    private mutating func substep() {
        let h = Self.step
        let r = Self.radius
        let far = Self.length
        elapsed += h
        ageSunk(h)
        for i in balls.indices where balls[i].live {
            var b = balls[i]
            if b.vx != 0 || b.vy != 0 {
                let speed = (b.vx * b.vx + b.vy * b.vy).squareRoot()
                let slower = speed - (Self.rollDrag + Self.speedDrag * speed) * h
                if slower <= Self.stopSpeed {
                    b.vx = 0
                    b.vy = 0
                } else {
                    let k = slower / speed
                    b.vx *= k
                    b.vy *= k
                    b.x += b.vx * h
                    b.y += b.vy * h
                }
            }
            // Cushions, with gaps where the pockets open.
            let nearEnd = b.y < Self.cornerMouth || b.y > far - Self.cornerMouth
            let nearSide = abs(b.y - far / 2) < Self.sideMouth
            let nearCorner = b.x < Self.cornerMouth || b.x > 1 - Self.cornerMouth
            if !nearEnd && !nearSide {
                if b.x < r {
                    b.x = 2 * r - b.x
                    if b.vx < 0 { b.vx = -b.vx * Self.railBounce; b.vy *= Self.railGrip }
                } else if b.x > 1 - r {
                    b.x = 2 * (1 - r) - b.x
                    if b.vx > 0 { b.vx = -b.vx * Self.railBounce; b.vy *= Self.railGrip }
                }
            }
            if !nearCorner {
                if b.y < r {
                    b.y = 2 * r - b.y
                    if b.vy < 0 { b.vy = -b.vy * Self.railBounce; b.vx *= Self.railGrip }
                } else if b.y > far - r {
                    b.y = 2 * (far - r) - b.y
                    if b.vy > 0 { b.vy = -b.vy * Self.railBounce; b.vx *= Self.railGrip }
                }
            }
            balls[i] = b
            catchIfDropped(i)
        }
        collide()
    }

    private mutating func catchIfDropped(_ i: Int) {
        let b = balls[i]
        var hit = -1
        for (k, hole) in Self.holes.enumerated() {
            let dx = b.x - hole.x
            let dy = b.y - hole.y
            if dx * dx + dy * dy < hole.reach * hole.reach { hit = k; break }
        }
        if hit < 0 {
            // Past the cushion line in a pocket mouth: it is in.
            let out = 0.6 * Self.radius
            if b.x > -out && b.x < 1 + out && b.y > -out && b.y < Self.length + out { return }
            var best = Double.infinity
            for (k, hole) in Self.holes.enumerated() {
                let d = (b.x - hole.x) * (b.x - hole.x) + (b.y - hole.y) * (b.y - hole.y)
                if d < best { best = d; hit = k }
            }
        }
        balls[i].live = false
        balls[i].sunk = 0
        balls[i].hole = hit
        balls[i].dropX = b.x
        balls[i].dropY = b.y
        balls[i].vx = 0
        balls[i].vy = 0
        potted.append(b.number)
    }

    private mutating func collide() {
        let r = Self.radius
        let touch = 4 * r * r
        let n = balls.count
        for i in 0..<n where balls[i].live {
            for j in (i + 1)..<n where balls[j].live {
                let dx = balls[j].x - balls[i].x
                let dy = balls[j].y - balls[i].y
                let d2 = dx * dx + dy * dy
                if d2 >= touch || d2 < 1e-12 { continue }
                let d = d2.squareRoot()
                let nx = dx / d
                let ny = dy / d
                let push = (2 * r - d) / 2
                balls[i].x -= nx * push
                balls[i].y -= ny * push
                balls[j].x += nx * push
                balls[j].y += ny * push
                let closing = (balls[i].vx - balls[j].vx) * nx + (balls[i].vy - balls[j].vy) * ny
                if closing <= 0 { continue }
                let kick = (1 + Self.ballBounce) / 2 * closing
                balls[i].vx -= kick * nx
                balls[i].vy -= kick * ny
                balls[j].vx += kick * nx
                balls[j].vy += kick * ny
                if i == 0 && firstHit == nil { firstHit = balls[j].number }
                impact = Swift.max(impact, closing)
            }
        }
    }

    // MARK: Placing

    func isFree(_ x: Double, _ y: Double, except i: Int) -> Bool {
        let room = 2 * Self.radius + 0.004
        for k in balls.indices where k != i && balls[k].live {
            let dx = balls[k].x - x
            let dy = balls[k].y - y
            if dx * dx + dy * dy < room * room { return false }
        }
        return true
    }

    /// Puts a ball back on the table at the nearest free place up or down from a spot.
    mutating func respot(_ number: Int, x: Double, y: Double) {
        guard let i = index(of: number) else { return }
        let r = Self.radius
        var spotY = y
        for k in 0..<60 {
            let off = Double((k + 1) / 2) * 0.03 * (k % 2 == 0 ? 1 : -1)
            let ty = y + off
            if ty < r || ty > Self.length - r { continue }
            if isFree(x, ty, except: i) { spotY = ty; break }
        }
        balls[i].live = true
        balls[i].sunk = -1
        balls[i].x = x
        balls[i].y = spotY
        balls[i].vx = 0
        balls[i].vy = 0
    }

    // MARK: Aiming

    /// The first ball or cushion the cue ball meets along an angle.
    func trace(angle: Double) -> CornerPocketAim {
        let c = balls[0]
        let r = Self.radius
        let dx = cos(angle)
        let dy = sin(angle)
        var best = Double.infinity
        var target = -1
        let reach2 = 4 * r * r
        for i in 1..<balls.count where balls[i].live {
            let ox = balls[i].x - c.x
            let oy = balls[i].y - c.y
            let proj = ox * dx + oy * dy
            if proj <= 0 { continue }
            let perp2 = ox * ox + oy * oy - proj * proj
            if perp2 >= reach2 { continue }
            let t = proj - (reach2 - perp2).squareRoot()
            if t < best { best = t; target = i }
        }
        var rail = Double.infinity
        if dx > 1e-9 { rail = Swift.min(rail, (1 - r - c.x) / dx) }
        if dx < -1e-9 { rail = Swift.min(rail, (r - c.x) / dx) }
        if dy > 1e-9 { rail = Swift.min(rail, (Self.length - r - c.y) / dy) }
        if dy < -1e-9 { rail = Swift.min(rail, (r - c.y) / dy) }
        rail = Swift.max(0, rail)

        var aim = CornerPocketAim(angle: angle, cueX: c.x, cueY: c.y, ghostX: c.x, ghostY: c.y, target: -1,
                                  nx: 0, ny: 0, tx: 0, ty: 0, along: 0)
        if target >= 0 && best <= rail {
            let t = Swift.max(0, best)
            aim.ghostX = c.x + dx * t
            aim.ghostY = c.y + dy * t
            aim.target = target
            aim.nx = (balls[target].x - aim.ghostX) / (2 * r)
            aim.ny = (balls[target].y - aim.ghostY) / (2 * r)
            aim.along = Swift.max(0, dx * aim.nx + dy * aim.ny)
            aim.tx = dx - aim.along * aim.nx
            aim.ty = dy - aim.along * aim.ny
        } else {
            aim.ghostX = c.x + dx * rail
            aim.ghostY = c.y + dy * rail
        }
        return aim
    }
}

// MARK: - Layout

struct CornerPocketLayout {
    let W: Double
    let H: Double
    let u: Double
    /// The playing surface in points.
    let felt: CGRect
    /// Points per table width.
    let s: Double
    let rail: Double
    let outer: CGRect
    let meter: CGRect
    let rowY: Double
    let pipY: Double
    let scoreY: Double
    let hintY: Double

    init(size: CGSize) {
        W = Double(size.width)
        H = Double(size.height)
        u = W / 402
        let top = Double(GameLayout.topBand)
        rowY = top + 22 * u
        pipY = top + 42 * u
        scoreY = Double(GameLayout.statusBarHeight + GameLayout.topBand) / 2
        rail = 15 * u
        let meterW = 26 * u
        let gap = 12 * u
        let side = 12 * u
        let tableTop = top + 64 * u
        let availW = W - 2 * side - gap - meterW
        let availH = H - Double(GameLayout.bottomInset) - 34 * u - tableTop
        let feltW = Swift.max(40, Swift.min(availW - 2 * rail, (availH - 2 * rail) / 2))
        s = feltW
        let outerW = feltW + 2 * rail
        let outerH = 2 * feltW + 2 * rail
        let x0 = (W - (outerW + gap + meterW)) / 2
        outer = CGRect(x: x0, y: tableTop, width: outerW, height: outerH)
        felt = outer.insetBy(dx: rail, dy: rail)
        meter = CGRect(x: x0 + outerW + gap, y: tableTop + outerH * 0.3, width: meterW, height: outerH * 0.58)
        hintY = tableTop + outerH + 17 * u
    }

    func px(_ x: Double) -> Double { Double(felt.minX) + x * s }
    func py(_ y: Double) -> Double { Double(felt.minY) + y * s }
    func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: px(x), y: py(y)) }

    /// A screen point in table units.
    func table(_ p: CGPoint) -> (x: Double, y: Double) {
        ((Double(p.x) - Double(felt.minX)) / s, (Double(p.y) - Double(felt.minY)) / s)
    }

    /// The whole column right of the table drives the power meter, so the thumb finds it without looking.
    func inMeter(_ p: CGPoint) -> Bool {
        Double(p.x) >= Double(outer.maxX) + 2 && Double(p.y) >= Double(outer.minY) - 20 * u
            && Double(p.y) <= Double(outer.maxY) + 30 * u
    }
}

// MARK: - What is on screen

struct CornerPocketSeat {
    var label: String
    var letter: String
    var color: CornerPocketTint
    var active = false
    /// 1 solids, 2 stripes, 0 not decided yet.
    var group = 0
    /// Bit k set while ball k of the group is on the table.
    var left = 0
    /// Share of the shot clock left, 0...1, or below zero for none.
    var clock = -1.0
}

struct CornerPocketNote {
    var text: String
    var x: Double
    var y: Double
    var age: Double
}

struct CornerPocketBurst {
    var x: Double
    var y: Double
    var number: Int
    var age: Double
}

struct CornerPocketFrame {
    var balls: [CornerPocketBall] = []
    var aim: CornerPocketAim?
    var power = 0.0
    /// True while the meter is the player's to pull.
    var meterLive = false
    var seats: [CornerPocketSeat] = []
    /// Solo only: misses left before the round ends.
    var misses: Int?
    var score = 0
    var scoreAge = 10.0
    var showHUD = true
    var notes: [CornerPocketNote] = []
    var bursts: [CornerPocketBurst] = []
    var praise: String?
    var praiseAge = 0.0
    var callout: String?
    var calloutAge = 0.0
    var hint = ""
    /// Seconds since a new rack went down, for its fade in.
    var rackAge = 10.0
    var dim = 0.0
    var banner: String?
    var bannerAge = 0.0
    var time = 0.0
}

// MARK: - Pictures

/// The pictures in Resources/GameArt, resolved once for each frame.
struct CornerPocketArt {
    let room: GraphicsContext.ResolvedImage
    let wood: GraphicsContext.ResolvedImage
    let felt: GraphicsContext.ResolvedImage
    let pocket: GraphicsContext.ResolvedImage
    /// Lying flat, the tip on the right.
    let cue: GraphicsContext.ResolvedImage
    /// The cue ball, 1 to 4, the 8, then 9 to 12.
    let balls: [GraphicsContext.ResolvedImage]

    init(_ ctx: GraphicsContext) {
        room = ctx.resolve(Image("corner-pocket-room"))
        wood = ctx.resolve(Image("corner-pocket-wood"))
        felt = ctx.resolve(Image("corner-pocket-felt"))
        pocket = ctx.resolve(Image("corner-pocket-pocket"))
        cue = ctx.resolve(Image("corner-pocket-cue"))
        balls = [0, 1, 2, 3, 4, 8, 9, 10, 11, 12].map { ctx.resolve(Image("corner-pocket-ball-\($0)")) }
    }

    func ball(_ number: Int) -> GraphicsContext.ResolvedImage {
        switch number {
        case 0...4: return balls[number]
        case 8: return balls[5]
        default: return balls[Swift.min(9, number - 3)]
        }
    }
}

// MARK: - Painter

struct CornerPocketPainter {
    typealias M = CornerPocketMath
    typealias P = CornerPocketPalette
    typealias T = CornerPocketTable

    static let noteLength = 1.0
    static let burstLength = 0.55
    static let praiseLength = 1.2
    static let calloutLength = 1.7

    let L: CornerPocketLayout
    private var u: Double { L.u }

    init(size: CGSize) {
        L = CornerPocketLayout(size: size)
    }

    func draw(_ f: CornerPocketFrame, _ ctx: inout GraphicsContext) {
        let art = CornerPocketArt(ctx)
        drawBackdrop(&ctx, art)
        drawSeats(&ctx, art, f)
        if f.showHUD { drawScore(&ctx, f) }
        drawTable(&ctx, art)
        drawSinking(&ctx, art, f.balls)
        if let aim = f.aim { drawGuide(&ctx, aim) }
        drawBalls(&ctx, art, f)
        if let aim = f.aim {
            drawGhost(&ctx, aim, f.balls)
            drawCue(&ctx, art, aim, power: f.power)
        }
        drawMeter(&ctx, f)
        for burst in f.bursts { drawBurst(&ctx, burst) }
        if f.showHUD {
            for note in f.notes { drawNote(&ctx, note) }
            if !f.hint.isEmpty { drawHint(&ctx, f.hint) }
        }
        if let words = f.callout { drawCallout(&ctx, words, age: f.calloutAge) }
        if let words = f.praise { drawPraise(&ctx, words, age: f.praiseAge) }
        if f.dim > 0.001 {
            ctx.fill(Path(CGRect(x: 0, y: 0, width: L.W, height: L.H)), with: .color(P.black.color(0.5 * f.dim)))
        }
        if let words = f.banner { drawBanner(&ctx, words, age: f.bannerAge) }
    }

    private func disc(_ x: Double, _ y: Double, _ r: Double) -> Path {
        Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
    }

    private func shadowed(_ ctx: inout GraphicsContext, _ text: Text, _ x: Double, _ y: Double,
                          color: Color, shade: Double) {
        ctx.draw(text.foregroundColor(P.black.color(shade)), at: CGPoint(x: x, y: y + 2 * u), anchor: .center)
        ctx.draw(text.foregroundColor(color), at: CGPoint(x: x, y: y), anchor: .center)
    }

    // MARK: Room and players

    private func drawBackdrop(_ ctx: inout GraphicsContext, _ art: CornerPocketArt) {
        let fill = Swift.max(L.W / Double(art.room.size.width), L.H / Double(art.room.size.height))
        let roomW = Double(art.room.size.width) * fill
        let roomH = Double(art.room.size.height) * fill
        ctx.draw(art.room, in: CGRect(x: (L.W - roomW) / 2, y: (L.H - roomH) / 2, width: roomW, height: roomH))
        let c = CGPoint(x: L.felt.midX, y: L.felt.midY)
        ctx.fill(Path(ellipseIn: L.outer.insetBy(dx: -60 * u, dy: -40 * u)),
                 with: .radialGradient(P.lamp, center: c, startRadius: 0, endRadius: Double(L.outer.height) * 0.62))
    }

    private func drawSeats(_ ctx: inout GraphicsContext, _ art: CornerPocketArt, _ f: CornerPocketFrame) {
        let r = 15 * u
        for (k, seat) in f.seats.enumerated() {
            let right = k == 1
            let cx = right ? L.W - 16 * u - r : 16 * u + r
            let cy = L.rowY
            if seat.active {
                ctx.fill(disc(cx, cy, r + 6 * u), with: .color(P.amber.color(0.16 + 0.06 * sin(f.time * 4))))
                if seat.clock >= 0 {
                    ctx.stroke(disc(cx, cy, r + 3.5 * u), with: .color(P.white.color(0.14)), lineWidth: 2.5 * u)
                    var arc = Path()
                    let start = -Double.pi / 2
                    arc.addArc(center: CGPoint(x: cx, y: cy), radius: r + 3.5 * u, startAngle: .radians(start),
                               endAngle: .radians(start + 2 * Double.pi * M.clamp(seat.clock)), clockwise: false)
                    let low = seat.clock < 0.34
                    ctx.stroke(arc, with: .color((low ? P.coral : P.amber).color()),
                               style: StrokeStyle(lineWidth: 2.5 * u, lineCap: .round))
                } else {
                    ctx.stroke(disc(cx, cy, r + 3.5 * u), with: .color(P.amber.color()), lineWidth: 2.5 * u)
                }
            }
            ctx.fill(disc(cx, cy + 1.5 * u, r), with: .color(P.black.color(0.3)))
            ctx.fill(disc(cx, cy, r), with: .color(seat.color.color()))
            ctx.draw(Text(seat.letter).font(.system(size: 17 * u, weight: .heavy, design: .rounded)).foregroundColor(P.ink.color()),
                     at: CGPoint(x: cx, y: cy), anchor: .center)

            let labelX = right ? cx - r - 9 * u : cx + r + 9 * u
            let label = Text(seat.label).font(.system(size: 16 * u, weight: .bold, design: .rounded))
            ctx.draw(label.foregroundColor(seat.active ? P.amber.color() : P.white.color(0.62)),
                     at: CGPoint(x: labelX, y: cy - 4 * u), anchor: right ? .trailing : .leading)

            guard seat.group != 0 else { continue }
            let pr = 5 * u
            let stepX = 13 * u
            if seat.left == 0 {
                drawBall(&ctx, art, 8, right ? labelX - pr : labelX + pr, L.pipY, pr)
                continue
            }
            for p in 0..<4 {
                let x = right ? labelX - pr - Double(p) * stepX : labelX + pr + Double(p) * stepX
                let number = seat.group == 1 ? p + 1 : p + 9
                if seat.left & (1 << p) != 0 {
                    drawBall(&ctx, art, number, x, L.pipY, pr)
                } else {
                    ctx.stroke(disc(x, L.pipY, pr - 0.5 * u), with: .color(P.white.color(0.2)), lineWidth: 1.2 * u)
                }
            }
        }
        if let misses = f.misses {
            let x = L.W - 16 * u
            let words = misses == 1 ? "1 miss left" : "\(misses) misses left"
            let label = Text(words).font(.system(size: 16 * u, weight: .bold, design: .rounded))
            ctx.draw(label.foregroundColor(misses <= 2 ? P.coral.color() : P.white.color(0.75)),
                     at: CGPoint(x: x, y: L.rowY - 4 * u), anchor: .trailing)
            for p in 0..<misses {
                let rect = CGRect(x: x - 9 * u - Double(p) * 13 * u, y: L.pipY - 4.5 * u, width: 9 * u, height: 9 * u)
                ctx.fill(Path(roundedRect: rect, cornerRadius: 2 * u), with: .color(P.chalk.color(0.9)))
            }
        }
    }

    private func drawScore(_ ctx: inout GraphicsContext, _ f: CornerPocketFrame) {
        let size = 32 * u * M.pop(f.scoreAge, 0.28)
        let number = Text("\(f.score)").font(.system(size: size, weight: .heavy, design: .rounded))
        shadowed(&ctx, number, L.W / 2, L.scoreY, color: .white, shade: 0.4)
    }

    // MARK: Table

    private func drawTable(_ ctx: inout GraphicsContext, _ art: CornerPocketArt) {
        let o = L.outer
        let f = L.felt
        let s = L.s
        ctx.fill(Path(roundedRect: o.offsetBy(dx: 0, dy: 8 * u), cornerRadius: 18 * u, style: .continuous),
                 with: .color(P.black.color(0.45)))
        var rail = ctx
        rail.clip(to: Path(roundedRect: o, cornerRadius: 18 * u, style: .continuous))
        rail.draw(art.wood, in: o)
        ctx.stroke(Path(roundedRect: o.insetBy(dx: 1.5 * u, dy: 1.5 * u), cornerRadius: 17 * u, style: .continuous),
                   with: .color(P.white.color(0.13)), lineWidth: 1.2 * u)
        ctx.fill(Path(roundedRect: f.insetBy(dx: -5 * u, dy: -5 * u), cornerRadius: 3 * u), with: .color(P.cushion.color()))
        ctx.draw(art.felt, in: f)

        // The head string and the foot spot.
        var head = Path()
        head.move(to: L.pt(0, T.headY))
        head.addLine(to: L.pt(1, T.headY))
        ctx.stroke(head, with: .color(P.white.color(0.1)), lineWidth: 1.2 * u)
        ctx.fill(disc(L.px(0.5), L.py(T.footY), 2.2 * u), with: .color(P.white.color(0.2)))

        // Sights on the rails.
        let mid = L.rail / 2 + 2.5 * u
        for k in 1...3 {
            let x = L.px(Double(k) / 4)
            drawSight(&ctx, x, Double(f.minY) - mid)
            drawSight(&ctx, x, Double(f.maxY) + mid)
        }
        for k in 1...7 where k != 4 {
            let y = L.py(Double(k) / 4)
            drawSight(&ctx, Double(f.minX) - mid, y)
            drawSight(&ctx, Double(f.maxX) + mid, y)
        }

        for hole in T.holes {
            let x = L.px(hole.x)
            let y = L.py(hole.y)
            let r = hole.drawRadius * s
            ctx.fill(disc(x, y, r + 2.5 * u), with: .color(P.black.color(0.28)))
            ctx.draw(art.pocket, in: CGRect(x: x - r - 2.5 * u, y: y - r - 2.5 * u, width: 2 * r + 5 * u, height: 2 * r + 5 * u))
        }
    }

    private func drawSight(_ ctx: inout GraphicsContext, _ x: Double, _ y: Double) {
        let r = 2.6 * u
        var p = Path()
        p.addLines([CGPoint(x: x - r, y: y), CGPoint(x: x, y: y - r), CGPoint(x: x + r, y: y), CGPoint(x: x, y: y + r)])
        p.closeSubpath()
        ctx.fill(p, with: .color(P.cream.color(0.7)))
    }

    // MARK: Balls

    func drawBall(_ ctx: inout GraphicsContext, _ art: CornerPocketArt, _ number: Int, _ x: Double, _ y: Double, _ r: Double) {
        ctx.draw(art.ball(number), in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
    }

    private func drawBalls(_ ctx: inout GraphicsContext, _ art: CornerPocketArt, _ f: CornerPocketFrame) {
        let r = T.radius * L.s
        let fade = M.smooth(0, 0.35, f.rackAge)
        for b in f.balls where b.live {
            let a = b.number == 0 ? 1 : fade
            ctx.fill(disc(L.px(b.x) + 1.6 * u, L.py(b.y) + 2.6 * u, r), with: .color(P.black.color(0.32 * a)))
        }
        for b in f.balls where b.live {
            if b.number != 0 && fade < 1 {
                var layer = ctx
                layer.opacity = fade
                drawBall(&layer, art, b.number, L.px(b.x), L.py(b.y), r * (0.7 + 0.3 * M.easeOut(fade)))
            } else {
                drawBall(&ctx, art, b.number, L.px(b.x), L.py(b.y), r)
            }
        }
    }

    private func drawSinking(_ ctx: inout GraphicsContext, _ art: CornerPocketArt, _ balls: [CornerPocketBall]) {
        let r = T.radius * L.s
        for b in balls where !b.live && b.sunk >= 0 && b.sunk < T.sinkLength {
            let k = b.sunk / T.sinkLength
            let hole = T.holes[b.hole]
            let e = M.easeOut(k)
            var layer = ctx
            layer.opacity = 1 - k * k
            drawBall(&layer, art, b.number, L.px(M.lerp(b.dropX, hole.x, e)), L.py(M.lerp(b.dropY, hole.y, e)), r * (1 - 0.45 * k))
        }
    }

    // MARK: Aim

    private func drawGuide(_ ctx: inout GraphicsContext, _ aim: CornerPocketAim) {
        let r = T.radius * L.s
        let dx = cos(aim.angle)
        let dy = sin(aim.angle)
        let x0 = L.px(aim.cueX) + dx * r * 1.2
        let y0 = L.py(aim.cueY) + dy * r * 1.2
        let x1 = L.px(aim.ghostX) - dx * r
        let y1 = L.py(aim.ghostY) - dy * r
        if (x1 - x0) * dx + (y1 - y0) * dy <= 2 * u { return }
        var line = Path()
        line.move(to: CGPoint(x: x0, y: y0))
        line.addLine(to: CGPoint(x: x1, y: y1))
        ctx.stroke(line, with: .color(P.white.color(0.85)),
                   style: StrokeStyle(lineWidth: 2 * u, lineCap: .round, dash: [6 * u, 6 * u]))
    }

    private func drawGhost(_ ctx: inout GraphicsContext, _ aim: CornerPocketAim, _ balls: [CornerPocketBall]) {
        let r = T.radius * L.s
        let gx = L.px(aim.ghostX)
        let gy = L.py(aim.ghostY)
        ctx.stroke(disc(gx, gy, r), with: .color(P.white.color(0.92)), lineWidth: 2 * u)
        guard aim.target >= 0, aim.target < balls.count else { return }
        let b = balls[aim.target]
        let bx = L.px(b.x)
        let by = L.py(b.y)
        let reach = (0.1 + 0.32 * aim.along) * L.s
        var path = Path()
        path.move(to: CGPoint(x: bx + aim.nx * r, y: by + aim.ny * r))
        path.addLine(to: CGPoint(x: bx + aim.nx * (r + reach), y: by + aim.ny * (r + reach)))
        ctx.stroke(path, with: .color(P.white.color(0.9)), style: StrokeStyle(lineWidth: 2.5 * u, lineCap: .round))
        let glance = (aim.tx * aim.tx + aim.ty * aim.ty).squareRoot()
        if glance > 0.05 {
            let len = (0.05 + 0.16 * glance) * L.s / glance
            var side = Path()
            side.move(to: CGPoint(x: gx + aim.tx / glance * r, y: gy + aim.ty / glance * r))
            side.addLine(to: CGPoint(x: gx + aim.tx * len, y: gy + aim.ty * len))
            ctx.stroke(side, with: .color(P.white.color(0.4)), style: StrokeStyle(lineWidth: 1.6 * u, lineCap: .round))
        }
    }

    private func drawCue(_ ctx: inout GraphicsContext, _ art: CornerPocketArt, _ aim: CornerPocketAim, power: Double) {
        let r = T.radius * L.s
        let dx = cos(aim.angle)
        let dy = sin(aim.angle)
        let cx = L.px(aim.cueX)
        let cy = L.py(aim.cueY)
        let gap = r + 5 * u + M.clamp(power) * 70 * u
        let length = 250 * u
        let tipHalf = 2.6 * u
        let buttHalf = 5.2 * u

        func at(_ along: Double, _ half: Double) -> CGPoint {
            CGPoint(x: cx - dx * along - dy * half, y: cy - dy * along + dx * half)
        }
        func slab(_ from: Double, _ to: Double) -> Path {
            let w0 = M.lerp(tipHalf, buttHalf, (from - gap) / length)
            let w1 = M.lerp(tipHalf, buttHalf, (to - gap) / length)
            var p = Path()
            p.addLines([at(from, w0), at(to, w1), at(to, -w1), at(from, -w0)])
            p.closeSubpath()
            return p
        }

        // The cue never reaches up into the player row, the score or the app's buttons.
        let top = Double(L.outer.minY) - 12 * u
        var cue = ctx
        cue.clip(to: Path(CGRect(x: 0, y: top, width: L.W, height: L.H - top)))
        var shadow = cue
        shadow.translateBy(x: 3 * u, y: 6 * u)
        shadow.fill(slab(gap, gap + length), with: .color(P.black.color(0.3)))
        cue.translateBy(x: cx, y: cy)
        cue.rotate(by: .radians(aim.angle))
        let thick = length * Double(art.cue.size.height) / Swift.max(1, Double(art.cue.size.width))
        cue.draw(art.cue, in: CGRect(x: -gap - length, y: -thick / 2, width: length, height: thick))
    }

    // MARK: Meter

    private func drawMeter(_ ctx: inout GraphicsContext, _ f: CornerPocketFrame) {
        let m = L.meter
        let w = Double(m.width)
        let mid = Double(m.midX)
        let track = Path(roundedRect: m, cornerRadius: w / 2, style: .continuous)
        var layer = ctx
        layer.opacity = f.meterLive ? 1 : 0.45
        layer.fill(track, with: .color(P.track.color()))
        layer.stroke(track, with: .color(P.white.color(0.08)), lineWidth: 1 * u)
        let travel = Double(m.height) - w
        let level = M.clamp(f.power)
        if level > 0.001 {
            let fill = CGRect(x: Double(m.minX), y: Double(m.minY), width: w, height: w + travel * level)
            layer.fill(Path(roundedRect: fill, cornerRadius: w / 2, style: .continuous),
                       with: .linearGradient(P.meterFill, startPoint: CGPoint(x: m.midX, y: m.minY),
                                             endPoint: CGPoint(x: m.midX, y: m.maxY)))
        }
        let knobY = Double(m.minY) + w / 2 + travel * level
        let knob = CGRect(x: Double(m.minX) - 4 * u, y: knobY - 7 * u, width: w + 8 * u, height: 14 * u)
        layer.fill(Path(roundedRect: knob.offsetBy(dx: 0, dy: 2 * u), cornerRadius: 7 * u, style: .continuous),
                   with: .color(P.black.color(0.35)))
        layer.fill(Path(roundedRect: knob, cornerRadius: 7 * u, style: .continuous), with: .color(P.cream.color()))
        for k in -1...1 {
            var grip = Path()
            grip.move(to: CGPoint(x: mid - 6 * u, y: knobY + Double(k) * 3 * u))
            grip.addLine(to: CGPoint(x: mid + 6 * u, y: knobY + Double(k) * 3 * u))
            layer.stroke(grip, with: .color(P.ink.color(0.3)), lineWidth: 1 * u)
        }
        if f.meterLive && level < 0.01 {
            // Chevrons drifting down: pull here.
            for k in 0..<2 {
                let drift = (f.time * 0.9 + Double(k) * 0.5).truncatingRemainder(dividingBy: 1)
                let y = knobY + 16 * u + drift * 22 * u
                var chevron = Path()
                chevron.move(to: CGPoint(x: mid - 5 * u, y: y - 3 * u))
                chevron.addLine(to: CGPoint(x: mid, y: y + 2 * u))
                chevron.addLine(to: CGPoint(x: mid + 5 * u, y: y - 3 * u))
                layer.stroke(chevron, with: .color(P.amber.color(0.8 * sin(drift * Double.pi))),
                             style: StrokeStyle(lineWidth: 2 * u, lineCap: .round, lineJoin: .round))
            }
        }
    }

    // MARK: Juice

    private func drawBurst(_ ctx: inout GraphicsContext, _ burst: CornerPocketBurst) {
        let k = M.clamp(burst.age / Self.burstLength)
        if k >= 1 { return }
        let tint = P.ball(burst.number)
        let x = L.px(burst.x)
        let y = L.py(burst.y)
        let spread = T.radius * L.s * (1 + 4.5 * M.easeOut(k))
        for i in 0..<10 {
            let a = Double(i) * 0.6283 + Double(burst.number) * 0.7
            let d = spread * (0.75 + 0.25 * Double(i % 3))
            ctx.fill(disc(x + cos(a) * d, y + sin(a) * d, 3.2 * u * (1 - k)), with: .color(tint.color(1 - k)))
        }
        ctx.stroke(disc(x, y, spread * 0.9), with: .color(P.cream.color(0.5 * (1 - k))), lineWidth: 2 * u * (1 - k))
    }

    private func drawNote(_ ctx: inout GraphicsContext, _ note: CornerPocketNote) {
        let life = M.clamp(note.age / Self.noteLength)
        let alpha = M.easeOut(M.clamp(note.age / 0.1)) * (1 - M.smooth(0.6, 1, life))
        if alpha <= 0.01 { return }
        let size = 21 * u * M.pop(note.age, 0.35)
        let text = Text(note.text).font(.system(size: size, weight: .heavy, design: .rounded))
        let x = M.clamp(L.px(note.x), Double(L.felt.minX) + 24 * u, Double(L.felt.maxX) - 24 * u)
        let y = M.clamp(L.py(note.y), Double(L.felt.minY) + 48 * u, Double(L.felt.maxY) - 18 * u) - M.easeOut(life) * 34 * u
        shadowed(&ctx, text, x, y, color: P.cream.color(alpha), shade: 0.45 * alpha)
    }

    private func drawHint(_ ctx: inout GraphicsContext, _ words: String) {
        let text = Text(words).font(.system(size: 15 * u, weight: .semibold, design: .rounded))
        ctx.draw(text.foregroundColor(P.white.color(0.86)), at: CGPoint(x: L.W / 2, y: L.hintY), anchor: .center)
    }

    private func drawCallout(_ ctx: inout GraphicsContext, _ words: String, age: Double) {
        let life = M.clamp(age / Self.calloutLength)
        let alpha = M.easeOut(M.clamp(age / 0.12)) * (1 - M.smooth(0.75, 1, life))
        if alpha <= 0.01 { return }
        let text = Text(words).font(.system(size: 15 * u, weight: .bold, design: .rounded))
        let resolved = ctx.resolve(text.foregroundColor(P.cream.color()))
        let size = resolved.measure(in: CGSize(width: L.W - 40 * u, height: 60 * u))
        let w = Double(size.width) + 32 * u
        let h = Double(size.height) + 16 * u
        let y = Double(L.felt.midY) + Double(L.felt.height) * 0.16
        let scale = M.pop(age, 0.2)
        var layer = ctx
        layer.opacity = alpha
        layer.translateBy(x: L.W / 2, y: y)
        layer.scaleBy(x: scale, y: scale)
        let rect = CGRect(x: -w / 2, y: -h / 2, width: w, height: h)
        layer.fill(Path(roundedRect: rect, cornerRadius: h / 2, style: .continuous), with: .color(P.ink.color(0.82)))
        layer.draw(resolved, at: .zero, anchor: .center)
    }

    private func drawPraise(_ ctx: inout GraphicsContext, _ words: String, age: Double) {
        let life = M.clamp(age / Self.praiseLength)
        let arrive = M.easeOut(M.clamp(age / 0.12))
        let alpha = arrive * (1 - M.smooth(0.65, 1, life))
        if alpha <= 0.01 { return }
        let size = 44 * u * (0.75 + 0.25 * arrive) * M.pop(age, 0.3)
        let text = Text(words).font(.system(size: size, weight: .black, design: .rounded)).italic()
        let y = Double(L.felt.midY) - Double(L.felt.height) * 0.15 - life * 14 * u
        shadowed(&ctx, text, L.W / 2, y, color: P.cream.color(alpha), shade: 0.5 * alpha)
    }

    private func drawBanner(_ ctx: inout GraphicsContext, _ words: String, age: Double) {
        let arrive = M.easeOut(M.clamp(age / 0.25))
        if arrive <= 0.01 { return }
        let text = Text(words).font(.system(size: 26 * u, weight: .heavy, design: .rounded))
        let resolved = ctx.resolve(text.foregroundColor(P.ink.color()))
        let size = resolved.measure(in: CGSize(width: L.W - 60 * u, height: 120 * u))
        let w = Double(size.width) + 48 * u
        let h = Double(size.height) + 34 * u
        let scale = (0.85 + 0.15 * arrive) * M.pop(age, 0.18)
        var layer = ctx
        layer.opacity = arrive
        layer.translateBy(x: L.W / 2, y: Double(L.felt.midY))
        layer.scaleBy(x: scale, y: scale)
        let rect = CGRect(x: -w / 2, y: -h / 2, width: w, height: h)
        layer.fill(Path(roundedRect: rect.offsetBy(dx: 0, dy: 5 * u), cornerRadius: 22 * u, style: .continuous),
                   with: .color(P.black.color(0.35)))
        layer.fill(Path(roundedRect: rect, cornerRadius: 22 * u, style: .continuous), with: .color(P.cream.color()))
        layer.draw(resolved, at: .zero, anchor: .center)
    }
}

// MARK: - The clip

/// A scripted moment for covers and the Videos feed: mid rack, the player lines up the 2, pulls the
/// meter, sinks it in the top corner and settles on the next shot.
enum CornerPocketClip {
    typealias M = CornerPocketMath
    typealias T = CornerPocketTable

    static let length = 9.0
    static let shotAt = 4.1
    static let power = 0.5
    static let targetHole = 1

    static let start: [CornerPocketBall] = [
        CornerPocketBall(0, 0.56, 1.36),
        CornerPocketBall(1, 0.2, 0.66),
        CornerPocketBall(2, 0.8, 0.42),
        CornerPocketBall(3, 0.3, 1.06),
        CornerPocketBall(8, 0.5, 0.8),
        CornerPocketBall(9, 0.14, 1.62),
        CornerPocketBall(11, 0.84, 1.72),
        CornerPocketBall(12, 0.3, 0.24),
    ]

    /// Straight through the ghost ball that sends the 2 into the top right pocket.
    static let angle: Double = {
        let target = start[2]
        let hole = T.holes[targetHole]
        let dx = hole.x - target.x
        let dy = hole.y - target.y
        let d = (dx * dx + dy * dy).squareRoot()
        let gx = target.x - dx / d * 2 * T.radius
        let gy = target.y - dy / d * 2 * T.radius
        return atan2(gy - start[0].y, gx - start[0].x)
    }()

    static func frame(at phase: Double, showHUD: Bool) -> CornerPocketFrame {
        let t = M.clamp(phase) * length
        var f = CornerPocketFrame()
        f.showHUD = showHUD
        f.time = t
        f.score = 30
        var table = CornerPocketTable(balls: start)
        var you = CornerPocketSeat(label: "You \u{00B7} solids", letter: "M", color: CornerPocketPalette.lime)
        var friend = CornerPocketSeat(label: "kaz \u{00B7} stripes", letter: "K", color: CornerPocketPalette.peach)
        you.group = 1
        friend.group = 2
        you.active = true

        if t < shotAt {
            let a = angle - 0.38 * (1 - M.easeOut(t / 2.4)) + 0.04 * sin(t * 2.2) * (1 - M.smooth(1.6, 2.6, t))
            f.aim = table.trace(angle: a)
            f.power = power * M.smooth(3.0, 3.9, t)
            f.meterLive = true
            f.hint = "Your turn. Sink a solid"
            you.clock = 1 - t / 30
        } else {
            table.strike(angle: angle, power: power)
            table.advance(t - shotAt)
            if let i = table.index(of: 2), !table.balls[i].live {
                let b = table.balls[i]
                let hole = T.holes[b.hole]
                f.notes = [CornerPocketNote(text: "+10", x: hole.x, y: hole.y, age: b.sunk)]
                f.bursts = [CornerPocketBurst(x: hole.x, y: hole.y, number: 2, age: b.sunk)]
                f.score = 30 + Int(Swift.min(10, b.sunk * 40))
                f.scoreAge = b.sunk
            }
            let rest = (t - shotAt) - table.elapsed
            if !table.moving && rest > 0.5 {
                let cue = table.cue
                var next = angle
                if let i = table.index(of: 1) {
                    next = atan2(table.balls[i].y - cue.y, table.balls[i].x - cue.x)
                }
                f.aim = table.trace(angle: next + 0.05 * sin(rest * 1.8))
                f.meterLive = true
                f.hint = "Your turn. Sink a solid"
                you.clock = 1 - Swift.min(1, (rest - 0.5) / 30)
            }
        }
        you.left = table.left(group: 1)
        friend.left = table.left(group: 2)
        f.seats = [you, friend]
        f.balls = table.balls
        return f
    }
}
