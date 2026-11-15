import SwiftUI

// Jam Slide: drag bright toy blocks out of a white tray, each through a gate of its own color.
// Some gates carry a number: that many more blocks may pass before the gate shuts. A cleared tray
// opens a chest, and its sparks fly up to the points counter.
//
// This file holds what the clip in Videos and the playable game share: numbers, colors, the level
// maker, where everything sits on the screen, and the painter. JamSlideGame.swift holds the rules
// of a live round, the scripted player and the view the app shows.

public struct JamSlideScene: View {
    public var phase: Double
    public var showHUD: Bool

    public init(phase: Double, showHUD: Bool) {
        self.phase = phase
        self.showHUD = showHUD
    }

    public var body: some View {
        Canvas(opaque: true, colorMode: .nonLinear, rendersAsynchronously: false) { context, size in
            if size.width <= 8 || size.height <= 8 { return }
            let frame = JamSlideClip.frame(phase: phase, showHUD: showHUD)
            JamSlidePainter(size: size).draw(&context, frame)
        }
    }
}

// MARK: - Numbers

enum JamSlideMath {
    static func clamp(_ v: Double, _ lo: Double = 0, _ hi: Double = 1) -> Double {
        Swift.max(lo, Swift.min(hi, v))
    }

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
        return k * k * (3 - 2 * k)
    }

    /// 1 at both ends, a little over 1 in the middle: the scale of something that just popped.
    static func pop(_ v: Double) -> Double {
        let k = clamp(v)
        return 1 + 0.28 * sin(k * .pi) * (1 - k)
    }
}

/// SplitMix64. The level maker, the round and the scripted player use different salts.
struct JamSlideRandom {
    static let level: UInt64 = 0x4A61_6D53_6C69_6465
    static let round: UInt64 = 0x2545_F491_4F6C_DD1D
    static let pilot: UInt64 = 0x7069_6C6F_744A_616D

    private var state: UInt64

    init(seed: UInt64, salt: UInt64) {
        state = seed &* 0x9E37_79B9_7F4A_7C15 &+ salt
    }

    /// A fresh 64-bit value, also used as the seed of something that needs its own sequence.
    mutating func bits() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var v = state
        v = (v ^ (v >> 30)) &* 0xBF58_476D_1CE4_E5B9
        v = (v ^ (v >> 27)) &* 0x94D0_49BB_1331_11EB
        return v ^ (v >> 31)
    }

    /// 0 ..< 1
    mutating func next() -> Double { Double(bits() >> 11) / 9007199254740992.0 }

    mutating func range(_ lo: Double, _ hi: Double) -> Double { lo + (hi - lo) * next() }

    mutating func int(_ bounds: ClosedRange<Int>) -> Int {
        bounds.lowerBound + Swift.min(bounds.count - 1, Int(next() * Double(bounds.count)))
    }

    mutating func chance(_ p: Double) -> Bool { next() < p }
}

// MARK: - Color

struct JamSlideTint {
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

    static let white = JamSlideTint(1, 1, 1)
    static let black = JamSlideTint(0, 0, 0)

    func mix(_ other: JamSlideTint, _ k: Double) -> JamSlideTint {
        JamSlideTint(r + (other.r - r) * k, g + (other.g - g) * k, b + (other.b - b) * k)
    }

    func scaled(_ k: Double) -> JamSlideTint {
        JamSlideTint(Swift.min(1, r * k), Swift.min(1, g * k), Swift.min(1, b * k))
    }

    func color(_ alpha: Double = 1) -> Color { Color(.sRGB, red: r, green: g, blue: b, opacity: alpha) }
}

enum JamSlidePalette {
    /// Block colors by index. A gate of the same index lets the block out.
    static let blocks: [JamSlideTint] = [0xF23F5D, 0xFF8A1F, 0xFFC61F, 0x22C35E, 0x2C7BFF, 0xA459FF]
        .map { JamSlideTint(hex: $0) }

    static let skyTop = JamSlideTint(hex: 0xDDF0FF)
    static let skyBottom = JamSlideTint(hex: 0xA6CEF6)
    static let frameSide = JamSlideTint(hex: 0xC2D2EA)
    static let frameRim = JamSlideTint(hex: 0xE8F0FA)
    static let floor = JamSlideTint(hex: 0xDAE4F2)
    static let floorLine = JamSlideTint(hex: 0xC6D3E6)
    static let ink = JamSlideTint(hex: 0x1C2A4A)
    static let shadow = JamSlideTint(hex: 0x2B4B80)
    static let badge = JamSlideTint(hex: 0x2F6FE6)
    static let badgeDark = JamSlideTint(hex: 0x1C4AAE)
    static let trim = JamSlideTint(hex: 0xF3F8FF)
    static let trimDark = JamSlideTint(hex: 0xB4CBE4)
    static let ice = JamSlideTint(hex: 0x3FB6F5)
    static let alarm = JamSlideTint(hex: 0xE5304C)
    static let chest = JamSlideTint(hex: 0x1FA89F)
    static let chestDark = JamSlideTint(hex: 0x10746E)

    static func block(_ index: Int) -> JamSlideTint {
        blocks[Swift.max(0, Swift.min(blocks.count - 1, index))]
    }
}

// MARK: - A level

enum JamSlideSide: Int, CaseIterable {
    case top = 0, right, bottom, left

    /// 0: a block leaves along x. 1: along y.
    var axis: Int { self == .left || self == .right ? 0 : 1 }
    /// -1 toward the top or the left edge, +1 toward the bottom or the right edge.
    var dir: Double { self == .top || self == .left ? -1 : 1 }
}

/// A colored opening in the frame. It spans `length` edge cells from `start`.
struct JamSlideGate {
    var side: JamSlideSide
    var start: Int
    var length: Int
    var color: Int
    /// true: only `left` more blocks may pass, then the gate shuts.
    var counted = false
    var left = 0
    var shut = false
    /// Seconds since its number last went down.
    var age = 10.0
}

/// A block on the board, in cells. Its top left cell is (x, y).
struct JamSlideBlock {
    var id: Int
    var x: Int
    var y: Int
    var w: Int
    var h: Int
    var color: Int
    /// The side it came in from, so the side it can leave by in one slide.
    var exit: JamSlideSide
    /// The gate it came in through, by index.
    var gate: Int
    /// -1: it slides both ways. 0: only along x. 1: only along y.
    var lane: Int

    var cells: Int { w * h }
}

/// One board. Made by sliding blocks in through the gates, so sliding them out in the reverse
/// order, each through the gate it came in by, always clears it, numbered gates included.
struct JamSlideLevel {
    var number: Int
    var cols: Int
    var rows: Int
    var gates: [JamSlideGate] = []
    var blocks: [JamSlideBlock] = []
    /// Block ids in an order that clears the board with one slide each.
    var solution: [Int] = []
    var moveBudget = 0

    static func make(number: Int, seed: UInt64) -> JamSlideLevel {
        var rng = JamSlideRandom(seed: seed, salt: JamSlideRandom.level &+ UInt64(Swift.max(0, number)))
        let sizes: [(Int, Int)] = [(5, 6), (5, 7), (6, 7), (6, 8), (7, 8), (7, 9)]
        let size = sizes[Swift.max(0, Swift.min(sizes.count - 1, number - 1))]
        let cols = size.0
        let rows = size.1
        let colors = Swift.min(JamSlidePalette.blocks.count, 4 + number / 2)
        var level = JamSlideLevel(number: number, cols: cols, rows: rows)

        // Gates tile each edge in runs of one to three cells. Later levels keep a few solid stretches.
        // Two gates side by side never share a color.
        var last = -1
        for side in JamSlideSide.allCases {
            let edge = side.axis == 1 ? cols : rows
            var pos = 0
            while pos < edge {
                if number >= 3, rng.chance(0.12) {
                    pos += 1
                    continue
                }
                let len = rng.int(1...Swift.min(3, edge - pos))
                var color = rng.int(0...(colors - 1))
                if color == last { color = (color + rng.int(1...(colors - 1))) % colors }
                level.gates.append(JamSlideGate(side: side, start: pos, length: len, color: color))
                last = color
                pos += len
            }
        }
        if level.gates.isEmpty {
            level.gates.append(JamSlideGate(side: .top, start: 0, length: 1, color: 0))
        }

        var grid = [Int](repeating: -1, count: cols * rows)
        var through = [Int](repeating: 0, count: level.gates.count)
        let fill = Swift.min(0.70, 0.52 + 0.03 * Double(number))
        let target = Int(Double(cols * rows) * fill)
        var filled = 0
        var attempts = 0
        while filled < target, attempts < 600 {
            attempts += 1
            let gi = rng.int(0...(level.gates.count - 1))
            let gate = level.gates[gi]
            // Mostly one or two cells across, so the tray holds many small toys and few slabs.
            let span = rng.chance(0.2) ? gate.length : rng.int(1...Swift.min(2, gate.length))
            let along = gate.start + rng.int(0...(gate.length - span))
            let depth = span >= 3 ? rng.int(1...2) : rng.int(1...3)
            let lane = gate.side.axis == 1 ? rows : cols
            if depth > lane { continue }

            // How far in the lane is clear.
            var free = 0
            scan: while free < lane {
                for k in 0..<span {
                    let c = cell(side: gate.side, along: along + k, inward: free, cols: cols, rows: rows)
                    if grid[c.y * cols + c.x] >= 0 { break scan }
                }
                free += 1
            }
            if free < depth { continue }
            let far = free - depth
            // Most blocks slide all the way in, so the middle of the board fills up too.
            let d = rng.chance(0.6) ? far : rng.int(0...far)

            var x0 = cols
            var y0 = rows
            var x1 = 0
            var y1 = 0
            for k in 0..<span {
                for j in 0..<depth {
                    let c = cell(side: gate.side, along: along + k, inward: d + j, cols: cols, rows: rows)
                    x0 = Swift.min(x0, c.x)
                    y0 = Swift.min(y0, c.y)
                    x1 = Swift.max(x1, c.x + 1)
                    y1 = Swift.max(y1, c.y + 1)
                }
            }
            let id = level.blocks.count
            for y in y0..<y1 {
                for x in x0..<x1 { grid[y * cols + x] = id }
            }
            // From board 2 some blocks only slide along the lane they came in by.
            let locked = number >= 2 && rng.chance(0.22)
            level.blocks.append(JamSlideBlock(id: id, x: x0, y: y0, w: x1 - x0, h: y1 - y0, color: gate.color,
                                              exit: gate.side, gate: gi, lane: locked ? gate.side.axis : -1))
            through[gi] += 1
            filled += (x1 - x0) * (y1 - y0)
        }

        // A few gates count down: exactly as many blocks as came in through them may go out.
        let most = Swift.min(3, 1 + number / 2)
        var counted = 0
        let from = rng.int(0...(level.gates.count - 1))
        for k in 0..<level.gates.count where counted < most {
            let gi = (from + k) % level.gates.count
            if through[gi] < 2 || !rng.chance(0.6) { continue }
            level.gates[gi].counted = true
            level.gates[gi].left = through[gi]
            counted += 1
        }

        level.solution = level.blocks.map { $0.id }.reversed()
        level.moveBudget = level.blocks.count + 4 + level.blocks.count / 3
        return level
    }

    /// The cell at a distance inward from one edge cell.
    static func cell(side: JamSlideSide, along: Int, inward: Int, cols: Int, rows: Int) -> (x: Int, y: Int) {
        switch side {
        case .top: return (along, inward)
        case .bottom: return (along, rows - 1 - inward)
        case .left: return (inward, along)
        case .right: return (cols - 1 - inward, along)
        }
    }
}

// MARK: - What is on screen

/// A block as the painter wants it. Positions are in cells and may be fractional.
struct JamSlideSprite {
    var x: Double
    var y: Double
    var w: Int
    var h: Int
    var color: Int
    var lane: Int
    /// 0...1: how far it is lifted by a finger.
    var lift: Double = 0
    var scale: Double = 1
}

/// A bit of a burst block. Positions and speeds are in cells.
struct JamSlideParticle {
    var x: Double
    var y: Double
    var vx: Double
    var vy: Double
    var age: Double
    var life: Double
    var size: Double
    var color: Int
    var spin: Double
}

/// Words that rise and fade over the board, in cells.
struct JamSlideFloat {
    var text: String
    var x: Double
    var y: Double
    var age: Double
    var big: Bool
}

/// When the chest after a cleared board does what, in seconds from the clear.
enum JamSlideChest {
    static let length = 2.1
    static let sparks = 12
    static let flight = 0.55

    static func launch(_ k: Int) -> Double { 0.5 + 0.06 * Double(k) }

    /// Sparks that have reached the counter by this time.
    static func landed(at t: Double) -> Int {
        var n = 0
        for k in 0..<sparks where launch(k) + flight <= t { n += 1 }
        return n
    }

    /// Where spark k is, 0...1 along its flight from the chest to the counter.
    static func position(_ k: Int, _ v: Double, from a: CGPoint, to b: CGPoint, u: Double) -> CGPoint {
        let s = JamSlideMath.easeInOut(v)
        let spread = (Double(k % 6) - 2.5) * 38 * u
        let rise = (170 + Double(k % 3) * 34) * u
        let cx = Double(a.x) + spread
        let cy = Double(a.y) - rise
        let one = 1 - s
        let x = one * one * Double(a.x) + 2 * one * s * cx + s * s * Double(b.x)
        let y = one * one * Double(a.y) + 2 * one * s * cy + s * s * Double(b.y)
        return CGPoint(x: x, y: y)
    }
}

/// One frame of the game, as the painter wants it.
struct JamSlideFrame {
    var cols = 5
    var rows = 6
    var gates: [JamSlideGate] = []
    var sprites: [JamSlideSprite] = []
    var particles: [JamSlideParticle] = []
    var floats: [JamSlideFloat] = []
    var timeLeft = 120.0
    var frozen = false
    var score = 0
    /// Seconds since the score last changed.
    var scoreAge = 10.0
    var level = 1
    var movesLeft = 0
    var hint: String?
    var hintAlpha = 0.0
    var hintPulse = 0.5
    var callout: String?
    var calloutAge = 0.0
    var calloutSub: String?
    /// Uses left on each booster: freeze, hammer, shuffle.
    var boosters: [Int] = [1, 1, 1]
    /// The booster waiting for a tap on a block, or -1.
    var armed = -1
    /// Seconds since the chest appeared, nil when there is none.
    var chestAge: Double?
    var showHUD = true
    var ambient = 0.0
    /// 0...1: the veil and the message when the round is over.
    var endFade = 0.0
    var endText = ""
}

// MARK: - Layout

/// Where the board, the HUD and the boosters sit. Design points scale from a 402 x 874 phone.
/// The top of the HUD keeps to the app's fixed bands, which do not scale.
struct JamSlideLayout {
    static let frameBand = 16.0
    static let boosterSize = 62.0
    static let boosterGap = 96.0

    let W: Double
    let H: Double
    let u: Double
    /// The scale of the HUD and the boosters. It follows the width alone, so text stays readable
    /// on short phones, where u shrinks with the height.
    let ui: Double
    let cols: Int
    let rows: Int
    let cell: Double
    /// Top left of cell (0, 0).
    let originX: Double
    let originY: Double

    init(size: CGSize, cols: Int, rows: Int) {
        W = Double(size.width)
        H = Double(size.height)
        u = Swift.min(W / 402, H / 874)
        ui = Self.hudScale(width: W)
        self.cols = Swift.max(1, cols)
        self.rows = Swift.max(1, rows)
        let top = Double(GameLayout.topBand) + 8 + 38 * ui + 22 * u
        let bottom = H - Double(GameLayout.bottomInset) - 112 * ui
        let band = Self.frameBand * u
        let wide = (W - 48 * u - 2 * band) / Double(self.cols)
        let tall = (bottom - top - 2 * band - 24 * u) / Double(self.rows)
        cell = Swift.max(8, Swift.min(66 * u, Swift.min(wide, tall)))
        originX = (W - cell * Double(self.cols)) / 2
        originY = (top + bottom - cell * Double(self.rows)) / 2
    }

    static func hudScale(width: Double) -> Double { Swift.min(width / 402, 1.08) }

    var band: Double { Self.frameBand * u }

    /// The cells, without the frame.
    var board: CGRect {
        CGRect(x: originX, y: originY, width: cell * Double(cols), height: cell * Double(rows))
    }

    var frame: CGRect { board.insetBy(dx: -band, dy: -band) }

    func point(_ x: Double, _ y: Double) -> CGPoint {
        CGPoint(x: originX + x * cell, y: originY + y * cell)
    }

    /// A screen point in cells.
    func position(at p: CGPoint) -> (x: Double, y: Double) {
        ((Double(p.x) - originX) / cell, (Double(p.y) - originY) / cell)
    }

    /// The clock, between the app's two corners and under the status bar.
    var timerRect: CGRect {
        CGRect(x: W / 2 - 66 * ui, y: Double(GameLayout.statusBarHeight) + 2, width: 132 * ui, height: 40 * ui)
    }

    /// The row under the app's band: level on the left, moves in the middle, points on the right.
    var rowY: Double { Double(GameLayout.topBand) + 8 }

    var levelRect: CGRect { CGRect(x: 16 * ui, y: rowY, width: 108 * ui, height: 38 * ui) }

    var scoreRect: CGRect { CGRect(x: W - 140 * ui, y: rowY, width: 124 * ui, height: 38 * ui) }

    var scoreIcon: CGPoint { CGPoint(x: scoreRect.minX + 20 * ui, y: scoreRect.midY) }

    var chestCenter: CGPoint { CGPoint(x: board.midX, y: board.midY + 34 * u) }

    var boosterY: Double { H - Double(GameLayout.bottomInset) - 44 * ui }

    func boosterRect(_ k: Int) -> CGRect {
        let s = Self.boosterSize * ui
        let cx = W / 2 + Double(k - 1) * Self.boosterGap * ui
        return CGRect(x: cx - s / 2, y: boosterY - s / 2, width: s, height: s)
    }

    /// The booster under a touch, or -1.
    func booster(at p: CGPoint) -> Int {
        for k in 0..<3 where boosterRect(k).insetBy(dx: -8 * ui, dy: -8 * ui).contains(p) { return k }
        return -1
    }
}

// MARK: - Painter

struct JamSlidePainter {
    typealias M = JamSlideMath
    typealias P = JamSlidePalette

    let W: Double
    let H: Double
    let u: Double
    /// The HUD's own scale, from JamSlideLayout.
    let ui: Double

    init(size: CGSize) {
        W = Double(size.width)
        H = Double(size.height)
        u = Swift.min(W / 402, H / 874)
        ui = JamSlideLayout.hudScale(width: W)
    }

    func draw(_ ctx: inout GraphicsContext, _ f: JamSlideFrame) {
        let lay = JamSlideLayout(size: CGSize(width: W, height: H), cols: f.cols, rows: f.rows)
        drawSky(&ctx, f)
        drawBoard(&ctx, lay, f)
        drawBlocks(&ctx, lay, f)
        drawParticles(&ctx, lay, f)
        drawFloats(&ctx, lay, f)
        if f.endFade > 0.01 { drawEnd(&ctx, lay, f) }
        if f.showHUD { drawHUD(&ctx, lay, f) }
        if let age = f.chestAge { drawChest(&ctx, lay, age: age) }
        if let words = f.callout { drawCallout(&ctx, lay, words, sub: f.calloutSub, age: f.calloutAge) }
        if f.showHUD {
            drawBoosters(&ctx, lay, f)
            if let hint = f.hint, f.hintAlpha > 0.01 { drawHint(&ctx, lay, hint, alpha: f.hintAlpha, pulse: f.hintPulse) }
        }
    }

    // MARK: Helpers

    private var screen: Path { Path(CGRect(x: 0, y: 0, width: W, height: H)) }

    private func rounded(_ r: CGRect, _ radius: Double) -> Path {
        Path(roundedRect: r, cornerRadius: Swift.max(0, Swift.min(radius, Swift.min(r.width, r.height) / 2)), style: .continuous)
    }

    private func circle(_ c: CGPoint, _ r: Double) -> Path {
        Path(ellipseIn: CGRect(x: Double(c.x) - r, y: Double(c.y) - r, width: 2 * r, height: 2 * r))
    }

    /// White words with a soft shadow, for over the blocks.
    private func label(_ ctx: inout GraphicsContext, _ text: Text, at p: CGPoint, anchor: UnitPoint, alpha: Double = 1, shadow: Double = 0.45) {
        if shadow > 0 {
            ctx.draw(text.foregroundColor(P.shadow.color(shadow * alpha)), at: CGPoint(x: p.x, y: p.y + 2 * u), anchor: anchor)
        }
        ctx.draw(text.foregroundColor(Color.white.opacity(alpha)), at: p, anchor: anchor)
    }

    private func font(_ size: Double, _ weight: Font.Weight = .heavy) -> Font {
        .system(size: size * u, weight: weight, design: .rounded)
    }

    private func hudFont(_ size: Double, _ weight: Font.Weight = .heavy) -> Font {
        .system(size: size * ui, weight: weight, design: .rounded)
    }

    /// A four-pointed spark in a block color with a white heart. angle turns it.
    private func drawSpark(_ ctx: inout GraphicsContext, _ c: CGPoint, _ r: Double, tint: JamSlideTint, angle: Double = -.pi / 2) {
        var star = Path()
        for k in 0..<8 {
            let a = angle + Double(k) * .pi / 4
            let reach = k % 2 == 0 ? r : r * 0.42
            let p = CGPoint(x: Double(c.x) + cos(a) * reach, y: Double(c.y) + sin(a) * reach)
            if k == 0 { star.move(to: p) } else { star.addLine(to: p) }
        }
        star.closeSubpath()
        ctx.fill(star.offsetBy(dx: 0, dy: 1.5 * u), with: .color(tint.scaled(0.62).color()))
        ctx.fill(star, with: .color(tint.color()))
        ctx.fill(circle(c, r * 0.26), with: .color(Color.white.opacity(0.92)))
    }

    // MARK: Sky

    private func drawSky(_ ctx: inout GraphicsContext, _ f: JamSlideFrame) {
        let bands = Gradient(colors: [P.skyTop.color(), P.skyBottom.color()])
        ctx.fill(screen, with: .linearGradient(bands, startPoint: CGPoint(x: W / 2, y: 0), endPoint: CGPoint(x: W / 2, y: H)))
        ctx.fill(screen, with: .radialGradient(Gradient(colors: [Color.white.opacity(0.55), Color.white.opacity(0)]),
                                               center: CGPoint(x: W * 0.5, y: H * 0.45), startRadius: 0, endRadius: H * 0.48))
        // Big soft bubbles drifting up, so the backdrop is never still.
        var rng = JamSlideRandom(seed: 7, salt: JamSlideRandom.level)
        let wrap = H + 120 * u
        for _ in 0..<14 {
            let x = rng.next() * W
            let speed = 5 + rng.next() * 9
            let y0 = rng.next() * wrap
            var y = (y0 - f.ambient * speed * u).truncatingRemainder(dividingBy: wrap)
            if y < 0 { y += wrap }
            let r = (16 + rng.next() * 34) * u
            ctx.fill(circle(CGPoint(x: x, y: y - 60 * u), r), with: .color(Color.white.opacity(0.13)))
        }
    }

    // MARK: Board

    private func drawBoard(_ ctx: inout GraphicsContext, _ lay: JamSlideLayout, _ f: JamSlideFrame) {
        let frame = lay.frame
        let radius = 22 * u
        // Drop shadow, the frame's side, the frame's top.
        ctx.fill(rounded(frame.offsetBy(dx: 0, dy: 14 * u).insetBy(dx: 4 * u, dy: 0), radius), with: .color(P.shadow.color(0.16)))
        ctx.fill(rounded(frame.offsetBy(dx: 0, dy: 7 * u), radius), with: .color(P.frameSide.color()))
        ctx.fill(rounded(frame, radius), with: .color(.white))
        ctx.stroke(rounded(frame.insetBy(dx: 2 * u, dy: 2 * u), radius - 2 * u), with: .color(P.frameRim.color()), lineWidth: 2 * u)

        // The tray and its grid.
        let board = lay.board
        let tray = rounded(board, 6 * u)
        ctx.fill(tray, with: .color(P.floor.color()))
        var lines = Path()
        for c in 1..<lay.cols {
            let x = lay.originX + Double(c) * lay.cell
            lines.move(to: CGPoint(x: x, y: board.minY))
            lines.addLine(to: CGPoint(x: x, y: board.maxY))
        }
        for r in 1..<lay.rows {
            let y = lay.originY + Double(r) * lay.cell
            lines.move(to: CGPoint(x: board.minX, y: y))
            lines.addLine(to: CGPoint(x: board.maxX, y: y))
        }
        ctx.stroke(lines, with: .color(P.floorLine.color()), lineWidth: Swift.max(1, 1.4 * u))
        var inner = ctx
        inner.clip(to: tray)
        inner.fill(Path(CGRect(x: board.minX, y: board.minY, width: board.width, height: 6 * u)), with: .color(P.shadow.color(0.10)))

        // Gates on the frame.
        let band = lay.band
        for gate in f.gates {
            let a0 = Double(gate.start) * lay.cell
            let len = Double(gate.length) * lay.cell
            let rect: CGRect
            switch gate.side {
            case .top: rect = CGRect(x: board.minX + a0, y: frame.minY, width: len, height: band)
            case .bottom: rect = CGRect(x: board.minX + a0, y: board.maxY, width: len, height: band)
            case .left: rect = CGRect(x: frame.minX, y: board.minY + a0, width: band, height: len)
            case .right: rect = CGRect(x: board.maxX, y: board.minY + a0, width: band, height: len)
            }
            drawGate(&ctx, gate, rect)
        }
    }

    private func drawGate(_ ctx: inout GraphicsContext, _ gate: JamSlideGate, _ rect: CGRect) {
        let tint = P.block(gate.color)
        let pad = rect.insetBy(dx: 2 * u, dy: 2 * u)
        let open = gate.shut ? 1 - M.smooth(0, 0.35, gate.age) : 1
        if gate.shut {
            ctx.fill(rounded(pad, 5 * u), with: .color(P.frameSide.color(0.8)))
        }
        if open > 0.01 {
            let shrink = 1 - open
            let face = pad.insetBy(dx: pad.width * 0.5 * shrink, dy: pad.height * 0.5 * shrink)
            ctx.fill(rounded(face, 5 * u), with: .color(tint.scaled(0.72).color(open)))
            ctx.fill(rounded(face.insetBy(dx: 1.6 * u, dy: 1.6 * u), 4 * u), with: .color(tint.color(open)))
        }
        if gate.shut { return }

        let c = CGPoint(x: rect.midX, y: rect.midY)
        if gate.counted {
            // The count, in a bubble that pops when it goes down.
            let bump = M.pop(gate.age / 0.35)
            let r = 12 * u * bump
            ctx.fill(circle(CGPoint(x: c.x, y: c.y + 1.5 * u), r), with: .color(tint.scaled(0.6).color()))
            ctx.fill(circle(c, r), with: .color(.white))
            ctx.stroke(circle(c, r - 1.2 * u), with: .color(tint.color()), lineWidth: 2.4 * u)
            let number = Text("\(gate.left)").font(font(14 * bump, .black))
            ctx.draw(number.foregroundColor(tint.scaled(0.7).color()), at: c, anchor: .center)
            return
        }
        let arrow = 5 * u
        let out = 3 * u
        var head = Path()
        switch gate.side {
        case .top:
            head.addLines([CGPoint(x: c.x, y: c.y - out), CGPoint(x: c.x - arrow, y: c.y + out), CGPoint(x: c.x + arrow, y: c.y + out)])
        case .bottom:
            head.addLines([CGPoint(x: c.x, y: c.y + out), CGPoint(x: c.x - arrow, y: c.y - out), CGPoint(x: c.x + arrow, y: c.y - out)])
        case .left:
            head.addLines([CGPoint(x: c.x - out, y: c.y), CGPoint(x: c.x + out, y: c.y - arrow), CGPoint(x: c.x + out, y: c.y + arrow)])
        case .right:
            head.addLines([CGPoint(x: c.x + out, y: c.y), CGPoint(x: c.x - out, y: c.y - arrow), CGPoint(x: c.x - out, y: c.y + arrow)])
        }
        head.closeSubpath()
        ctx.fill(head, with: .color(Color.white.opacity(0.9)))
    }

    // MARK: Blocks

    private func drawBlocks(_ ctx: inout GraphicsContext, _ lay: JamSlideLayout, _ f: JamSlideFrame) {
        if f.sprites.isEmpty { return }
        var inside = ctx
        inside.clip(to: rounded(lay.frame.insetBy(dx: 3 * u, dy: 3 * u), 18 * u))
        for s in f.sprites where s.lift < 0.01 { drawBlock(&inside, lay, s) }
        for s in f.sprites where s.lift >= 0.01 { drawBlock(&inside, lay, s) }
    }

    private func drawBlock(_ ctx: inout GraphicsContext, _ lay: JamSlideLayout, _ s: JamSlideSprite) {
        if s.scale <= 0.02 { return }
        let tint = P.block(s.color)
        let gap = 2.4 * u
        let full = CGRect(x: lay.originX + s.x * lay.cell, y: lay.originY + s.y * lay.cell,
                          width: Double(s.w) * lay.cell, height: Double(s.h) * lay.cell)
        let box = full.insetBy(dx: gap, dy: gap)
        let grow = (s.scale - 1) + 0.06 * s.lift
        let rect = box.insetBy(dx: -box.width * grow / 2, dy: -box.height * grow / 2).offsetBy(dx: 0, dy: -6 * u * s.lift)
        let depth = 6 * u
        let radius = 10 * u

        if s.lift > 0.01 {
            ctx.fill(rounded(rect.offsetBy(dx: 0, dy: 12 * u * s.lift).insetBy(dx: -2 * u, dy: -2 * u), radius),
                     with: .color(P.shadow.color(0.28 * s.lift)))
        }
        // The side, then the top face with a glossy strip.
        ctx.fill(rounded(rect, radius), with: .color(tint.scaled(0.66).color()))
        let top = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height - depth)
        let faces = Gradient(colors: [tint.mix(.white, 0.28).color(), tint.color()])
        ctx.fill(rounded(top, radius), with: .linearGradient(faces, startPoint: CGPoint(x: top.minX, y: top.minY), endPoint: CGPoint(x: top.minX, y: top.maxY)))
        let gloss = CGRect(x: top.minX + 5 * u, y: top.minY + 3 * u, width: top.width - 10 * u, height: Swift.min(7 * u, top.height * 0.2))
        ctx.fill(rounded(gloss, 4 * u), with: .color(Color.white.opacity(0.32)))

        // One round stud per cell.
        let sx = rect.width / Double(s.w)
        let sy = top.height / Double(s.h)
        let r = Swift.min(sx, sy) * 0.27
        let ring = tint.scaled(0.74).color()
        let face = tint.mix(.white, 0.14).color()
        let shine = Color.white.opacity(0.42)
        for i in 0..<s.w {
            for j in 0..<s.h {
                let cx = rect.minX + sx * (Double(i) + 0.5)
                let cy = top.minY + sy * (Double(j) + 0.5)
                ctx.fill(circle(CGPoint(x: cx, y: cy + 2 * u), r), with: .color(ring))
                ctx.fill(circle(CGPoint(x: cx, y: cy), r), with: .color(face))
                ctx.fill(Path(ellipseIn: CGRect(x: cx - r * 0.55, y: cy - r * 0.7, width: r * 0.75, height: r * 0.45)), with: .color(shine))
            }
        }

        // A block that only slides one way wears a double arrow along that way.
        if s.lane >= 0 {
            let c = CGPoint(x: top.midX, y: top.midY)
            let reach = (s.lane == 0 ? top.width : top.height) * 0.5 - Swift.min(sx, sy) * 0.18
            let tip = Swift.min(9 * u, reach * 0.5)
            var arrow = Path()
            if s.lane == 0 {
                arrow.move(to: CGPoint(x: c.x - reach, y: c.y))
                arrow.addLine(to: CGPoint(x: c.x + reach, y: c.y))
                arrow.move(to: CGPoint(x: c.x - reach + tip, y: c.y - tip))
                arrow.addLine(to: CGPoint(x: c.x - reach, y: c.y))
                arrow.addLine(to: CGPoint(x: c.x - reach + tip, y: c.y + tip))
                arrow.move(to: CGPoint(x: c.x + reach - tip, y: c.y - tip))
                arrow.addLine(to: CGPoint(x: c.x + reach, y: c.y))
                arrow.addLine(to: CGPoint(x: c.x + reach - tip, y: c.y + tip))
            } else {
                arrow.move(to: CGPoint(x: c.x, y: c.y - reach))
                arrow.addLine(to: CGPoint(x: c.x, y: c.y + reach))
                arrow.move(to: CGPoint(x: c.x - tip, y: c.y - reach + tip))
                arrow.addLine(to: CGPoint(x: c.x, y: c.y - reach))
                arrow.addLine(to: CGPoint(x: c.x + tip, y: c.y - reach + tip))
                arrow.move(to: CGPoint(x: c.x - tip, y: c.y + reach - tip))
                arrow.addLine(to: CGPoint(x: c.x, y: c.y + reach))
                arrow.addLine(to: CGPoint(x: c.x + tip, y: c.y + reach - tip))
            }
            let line = StrokeStyle(lineWidth: 4.2 * u, lineCap: .round, lineJoin: .round)
            ctx.stroke(arrow.offsetBy(dx: 0, dy: 1.5 * u), with: .color(tint.scaled(0.6).color(0.8)), style: line)
            ctx.stroke(arrow, with: .color(Color.white.opacity(0.95)), style: line)
        }
    }

    // MARK: Bursts and words

    private func drawParticles(_ ctx: inout GraphicsContext, _ lay: JamSlideLayout, _ f: JamSlideFrame) {
        for p in f.particles {
            let k = M.clamp(p.age / Swift.max(0.01, p.life))
            if k >= 1 { continue }
            let alpha = 1 - M.smooth(0.55, 1, k)
            let size = p.size * lay.cell * (1 - 0.4 * k)
            let c = lay.point(p.x, p.y)
            if Double(c.y) < Double(GameLayout.topBand) { continue }
            var local = ctx
            local.translateBy(x: c.x, y: c.y)
            local.rotate(by: .radians(p.spin * p.age))
            let box = CGRect(x: -size / 2, y: -size / 2, width: size, height: size)
            let tint = p.color < 0 ? JamSlideTint.white : P.block(p.color)
            local.fill(rounded(box, size * 0.45), with: .color(tint.color(alpha)))
            local.fill(Path(ellipseIn: box.insetBy(dx: size * 0.28, dy: size * 0.28)), with: .color(Color.white.opacity(0.4 * alpha)))
        }
    }

    private func drawFloats(_ ctx: inout GraphicsContext, _ lay: JamSlideLayout, _ f: JamSlideFrame) {
        for w in f.floats {
            let k = M.clamp(w.age / 1.1)
            let alpha = M.easeOut(M.clamp(w.age / 0.12)) * (1 - M.smooth(0.55, 1, k))
            if alpha <= 0.01 { continue }
            let rise = (w.big ? 54.0 : 40.0) * u * M.easeOut(k)
            let grow = 0.8 + 0.2 * M.easeOut(M.clamp(w.age / 0.14))
            let size = (w.big ? 28.0 : 22.0) * grow * M.pop(w.age / 0.3)
            let c = lay.point(w.x, w.y)
            let text = Text(w.text).font(font(size, .black))
            label(&ctx, text, at: CGPoint(x: c.x, y: c.y - rise), anchor: .center, alpha: alpha, shadow: 0.6)
        }
    }

    private func drawCallout(_ ctx: inout GraphicsContext, _ lay: JamSlideLayout, _ words: String, sub: String?, age: Double) {
        let arrive = M.easeOut(M.clamp(age / 0.18))
        let alpha = arrive * (1 - M.smooth(1.1, 1.5, age))
        if alpha <= 0.01 { return }
        let size = 40 * (0.6 + 0.4 * arrive) * M.pop(age / 0.5)
        let cx = Double(lay.board.midX)
        let cy = Double(lay.frame.minY) + 64 * u
        let tall = (sub == nil ? 72.0 : 96.0) * u
        let backing = CGRect(x: cx - 124 * u, y: cy - 38 * u, width: 248 * u, height: tall)
        ctx.fill(rounded(backing.offsetBy(dx: 0, dy: 5 * u), 24 * u), with: .color(P.shadow.color(0.18 * alpha)))
        ctx.fill(rounded(backing, 24 * u), with: .color(Color.white.opacity(0.96 * alpha)))
        let text = Text(words).font(font(size, .black)).kerning(1 * u)
        ctx.draw(text.foregroundColor(P.badge.color(alpha)), at: CGPoint(x: cx, y: Double(backing.minY) + 35 * u), anchor: .center)
        if let sub {
            let line = Text(sub).font(font(16, .bold))
            ctx.draw(line.foregroundColor(P.ink.color(0.75 * alpha)), at: CGPoint(x: cx, y: Double(backing.minY) + 72 * u), anchor: .center)
        }
    }

    private func drawHint(_ ctx: inout GraphicsContext, _ lay: JamSlideLayout, _ words: String, alpha: Double, pulse: Double) {
        let strength = alpha * (0.7 + 0.3 * pulse)
        let text = Text(words).font(font(16, .bold))
        ctx.draw(text.foregroundColor(P.ink.color(0.85 * strength)), at: CGPoint(x: W / 2, y: Double(lay.frame.maxY) + 26 * u), anchor: .center)
    }

    private func drawEnd(_ ctx: inout GraphicsContext, _ lay: JamSlideLayout, _ f: JamSlideFrame) {
        let k = M.clamp(f.endFade)
        ctx.fill(rounded(lay.frame, 22 * u), with: .color(Color.white.opacity(0.8 * k)))
        let board = lay.board
        let size = 34 * (0.7 + 0.3 * M.easeOut(k))
        let text = Text(f.endText).font(font(size, .black))
        ctx.draw(text.foregroundColor(P.ink.color(k)), at: CGPoint(x: board.midX, y: board.midY - 18 * u), anchor: .center)
        let line = Text(f.score == 1 ? "1 point" : "\(f.score) points").font(font(19, .bold))
        ctx.draw(line.foregroundColor(P.ink.color(0.7 * k)), at: CGPoint(x: board.midX, y: board.midY + 20 * u), anchor: .center)
    }

    // MARK: Chest

    private func drawChest(_ ctx: inout GraphicsContext, _ lay: JamSlideLayout, age t: Double) {
        let appear = M.easeOut(M.clamp(t / 0.22)) * M.pop(t / 0.42)
        let fade = 1 - M.smooth(JamSlideChest.length - 0.35, JamSlideChest.length, t)
        let open = M.easeOut(M.clamp((t - 0.3) / 0.22))
        let c = lay.chestCenter
        let mouth = CGPoint(x: c.x, y: c.y - 20 * u)

        if fade > 0.01, open > 0.01 {
            let glowR = 190 * u * (0.6 + 0.4 * open)
            let glow = Gradient(colors: [Color.white.opacity(0.85 * open * fade), Color.white.opacity(0)])
            ctx.fill(circle(mouth, glowR), with: .radialGradient(glow, center: mouth, startRadius: 0, endRadius: glowR))
            var rays = Path()
            let turn = t * 0.6
            let mx = Double(mouth.x)
            let my = Double(mouth.y)
            for k in 0..<12 {
                let a0 = turn + Double(k) * .pi / 6
                rays.move(to: mouth)
                rays.addLine(to: CGPoint(x: mx + cos(a0) * glowR, y: my + sin(a0) * glowR))
                rays.addLine(to: CGPoint(x: mx + cos(a0 + 0.14) * glowR, y: my + sin(a0 + 0.14) * glowR))
                rays.closeSubpath()
            }
            ctx.fill(rays, with: .color(Color.white.opacity(0.3 * open * fade)))
        }

        if fade > 0.01, appear > 0.01 {
            var local = ctx
            local.opacity = fade
            local.translateBy(x: c.x, y: c.y)
            local.scaleBy(x: appear, y: appear)
            let body = CGRect(x: -74 * u, y: -8 * u, width: 148 * u, height: 74 * u)
            local.fill(rounded(body.offsetBy(dx: 0, dy: 8 * u), 14 * u), with: .color(P.shadow.color(0.22)))
            local.fill(rounded(body, 14 * u), with: .color(P.chestDark.color()))
            local.fill(rounded(CGRect(x: body.minX, y: body.minY, width: body.width, height: body.height - 8 * u), 14 * u), with: .color(P.chest.color()))
            for x in [-54.0, 42.0] {
                local.fill(Path(CGRect(x: x * u, y: body.minY, width: 12 * u, height: body.height - 2 * u)), with: .color(P.trim.color()))
            }
            if open > 0.01 {
                local.fill(Path(ellipseIn: CGRect(x: -66 * u, y: -20 * u, width: 132 * u, height: 24 * u)), with: .color(P.chestDark.scaled(0.55).color()))
                for k in 0..<7 {
                    let x = (Double(k) - 3) * 17 * u
                    let y = -12 * u - (k % 2 == 0 ? 5 * u : 0)
                    let tint = P.block(k % P.blocks.count)
                    local.fill(circle(CGPoint(x: x, y: y + 2 * u), 10 * u), with: .color(tint.scaled(0.66).color()))
                    local.fill(circle(CGPoint(x: x, y: y), 10 * u), with: .color(tint.color()))
                    local.fill(Path(ellipseIn: CGRect(x: x - 5.5 * u, y: y - 7 * u, width: 7.5 * u, height: 4.5 * u)), with: .color(Color.white.opacity(0.45)))
                }
            }
            local.fill(Path(CGRect(x: body.minX, y: body.minY, width: body.width, height: 9 * u)), with: .color(P.trimDark.color()))
            local.fill(rounded(CGRect(x: -13 * u, y: -2 * u, width: 26 * u, height: 28 * u), 6 * u), with: .color(P.trim.color()))
            local.fill(circle(CGPoint(x: 0, y: 9 * u), 4 * u), with: .color(P.chestDark.color()))

            var lid = local
            lid.translateBy(x: 0, y: -8 * u - 34 * u * open)
            lid.rotate(by: .radians(-0.22 * open))
            let lidRect = CGRect(x: -78 * u, y: -40 * u, width: 156 * u, height: 40 * u)
            lid.fill(rounded(lidRect, 18 * u), with: .color(P.chest.mix(.white, 0.12).color()))
            lid.fill(Path(CGRect(x: lidRect.minX, y: -12 * u, width: lidRect.width, height: 12 * u)), with: .color(P.chestDark.color()))
            for x in [-56.0, 44.0] {
                lid.fill(Path(CGRect(x: x * u, y: -38 * u, width: 12 * u, height: 38 * u)), with: .color(P.trim.color()))
            }
            lid.fill(Path(CGRect(x: lidRect.minX, y: -6 * u, width: lidRect.width, height: 7 * u)), with: .color(P.trim.color()))
            lid.fill(rounded(CGRect(x: -60 * u, y: -34 * u, width: 120 * u, height: 7 * u), 3.5 * u), with: .color(Color.white.opacity(0.28)))
        }

        // The sparks on their way to the points counter, each in a block color.
        for k in 0..<JamSlideChest.sparks {
            let tk = t - JamSlideChest.launch(k)
            if tk < 0 || tk > JamSlideChest.flight { continue }
            let v = tk / JamSlideChest.flight
            let p = JamSlideChest.position(k, v, from: mouth, to: lay.scoreIcon, u: u)
            drawSpark(&ctx, p, 13 * u * (1 - 0.3 * v), tint: P.block(k % P.blocks.count), angle: -.pi / 2 + tk * 7 + Double(k))
        }
    }

    // MARK: HUD

    private func drawHUD(_ ctx: inout GraphicsContext, _ lay: JamSlideLayout, _ f: JamSlideFrame) {
        let u = ui
        // The clock, between the app's corners.
        let pill = lay.timerRect
        let r = Double(pill.height) / 2
        let low = f.timeLeft < 10 && !f.frozen
        let pulse = low ? 0.5 + 0.5 * sin(f.ambient * 9) : 0
        let edge = f.frozen ? P.ice : (low ? P.alarm : P.frameSide)
        ctx.fill(rounded(pill.offsetBy(dx: 0, dy: 3 * u), r), with: .color(P.shadow.color(0.16)))
        ctx.fill(rounded(pill, r), with: .color(.white))
        ctx.stroke(rounded(pill.insetBy(dx: 1.2 * u, dy: 1.2 * u), r - 1.2 * u), with: .color(edge.color(low ? 0.5 + 0.5 * pulse : 1)), lineWidth: 2.2 * u)
        let whole = Swift.max(0, Int(f.timeLeft.rounded(.up)))
        let clock = String(format: "%d:%02d", whole / 60, whole % 60)
        let ink = f.frozen ? P.ice : (low ? P.alarm : P.ink)
        let clockText = Text(clock).font(hudFont(22, .heavy)).monospacedDigit()
        ctx.draw(clockText.foregroundColor(ink.color()), at: CGPoint(x: Double(pill.midX) + 11 * u, y: Double(pill.midY)), anchor: .center)
        let iconC = CGPoint(x: Double(pill.minX) + 22 * u, y: Double(pill.midY))
        if f.frozen {
            var flake = Path()
            for k in 0..<3 {
                let t = Double(k) * .pi / 3
                flake.move(to: CGPoint(x: iconC.x + cos(t) * 8 * u, y: iconC.y + sin(t) * 8 * u))
                flake.addLine(to: CGPoint(x: iconC.x - cos(t) * 8 * u, y: iconC.y - sin(t) * 8 * u))
            }
            ctx.stroke(flake, with: .color(P.ice.color()), style: StrokeStyle(lineWidth: 2.2 * u, lineCap: .round))
        } else {
            ctx.stroke(circle(iconC, 7.5 * u), with: .color(ink.color(0.8)), lineWidth: 2 * u)
            var hands = Path()
            hands.move(to: CGPoint(x: iconC.x, y: iconC.y - 4.5 * u))
            hands.addLine(to: iconC)
            hands.addLine(to: CGPoint(x: iconC.x + 3.5 * u, y: iconC.y))
            ctx.stroke(hands, with: .color(ink.color(0.8)), style: StrokeStyle(lineWidth: 2 * u, lineCap: .round))
        }

        // The level badge.
        let badge = lay.levelRect
        let br = Double(badge.height) / 2
        ctx.fill(rounded(badge.offsetBy(dx: 0, dy: 4 * u), br), with: .color(P.badgeDark.color()))
        ctx.fill(rounded(badge, br), with: .color(P.badge.color()))
        let sheen = CGRect(x: Double(badge.minX) + 10 * u, y: Double(badge.minY) + 4 * u, width: Double(badge.width) - 20 * u, height: 9 * u)
        ctx.fill(rounded(sheen, 4.5 * u), with: .color(Color.white.opacity(0.18)))
        let levelText = Text("LEVEL \(f.level)").font(hudFont(16, .black)).kerning(0.8 * u)
        ctx.draw(levelText.foregroundColor(.white), at: CGPoint(x: badge.midX, y: badge.midY), anchor: .center)

        // Moves left, between the two.
        let left = Swift.max(0, f.movesLeft)
        let movesText = Text(left == 1 ? "1 move" : "\(left) moves").font(hudFont(15, .heavy))
        let movesInk = left <= 2 ? P.alarm.color(0.75 + 0.25 * sin(f.ambient * 8)) : P.ink.color(0.62)
        ctx.draw(movesText.foregroundColor(movesInk), at: CGPoint(x: W / 2, y: Double(badge.midY)), anchor: .center)

        // The points, popping as they count up.
        let purse = lay.scoreRect
        let cr = Double(purse.height) / 2
        let pop = 1 + 0.2 * exp(-9 * f.scoreAge) * Swift.max(0, 1 - f.scoreAge * 2)
        ctx.fill(rounded(purse.offsetBy(dx: 0, dy: 3 * u), cr), with: .color(P.shadow.color(0.16)))
        ctx.fill(rounded(purse, cr), with: .color(.white))
        drawSpark(&ctx, lay.scoreIcon, 15 * u * pop, tint: P.badge)
        let number = Text("\(f.score)").font(hudFont(21 * pop, .heavy)).monospacedDigit()
        ctx.draw(number.foregroundColor(P.ink.color()), at: CGPoint(x: Double(purse.maxX) - 14 * u, y: Double(purse.midY)), anchor: .trailing)
    }

    // MARK: Boosters

    private func drawBoosters(_ ctx: inout GraphicsContext, _ lay: JamSlideLayout, _ f: JamSlideFrame) {
        let u = ui
        for k in 0..<3 {
            let rect = lay.boosterRect(k)
            let left = k < f.boosters.count ? f.boosters[k] : 0
            let alive = left > 0
            let alpha = alive ? 1.0 : 0.45
            let armed = f.armed == k
            let radius = 20 * u
            ctx.fill(rounded(rect.offsetBy(dx: 0, dy: 5 * u), radius), with: .color(P.frameSide.color(alpha)))
            ctx.fill(rounded(rect, radius), with: .color(armed ? P.badge.mix(.white, 0.75).color() : Color.white.opacity(alive ? 1 : 0.7)))
            let rim = armed ? P.badge.color(0.7 + 0.3 * sin(f.ambient * 8)) : P.frameRim.color()
            ctx.stroke(rounded(rect.insetBy(dx: 1.5 * u, dy: 1.5 * u), radius - 1.5 * u), with: .color(rim), lineWidth: 2.5 * u)

            let c = CGPoint(x: rect.midX, y: rect.midY)
            let stroke = StrokeStyle(lineWidth: 3.4 * u, lineCap: .round, lineJoin: .round)
            switch k {
            case 0:
                var flake = Path()
                for i in 0..<3 {
                    let t = Double(i) * .pi / 3 + .pi / 6
                    let dx = cos(t) * 14 * u
                    let dy = sin(t) * 14 * u
                    flake.move(to: CGPoint(x: c.x + dx, y: c.y + dy))
                    flake.addLine(to: CGPoint(x: c.x - dx, y: c.y - dy))
                }
                ctx.stroke(flake, with: .color(P.ice.color(alpha)), style: stroke)
                ctx.fill(circle(c, 4 * u), with: .color(P.ice.scaled(0.8).color(alpha)))
            case 1:
                var local = ctx
                local.translateBy(x: c.x, y: c.y)
                local.rotate(by: .degrees(-40))
                var handle = Path()
                handle.move(to: CGPoint(x: 0, y: -2 * u))
                handle.addLine(to: CGPoint(x: 0, y: 16 * u))
                local.stroke(handle, with: .color(P.block(1).color(alpha)), style: StrokeStyle(lineWidth: 6 * u, lineCap: .round))
                local.fill(rounded(CGRect(x: -14 * u, y: -15 * u, width: 28 * u, height: 14 * u), 4 * u), with: .color(P.block(4).color(alpha)))
                local.fill(rounded(CGRect(x: -10 * u, y: -13 * u, width: 20 * u, height: 4 * u), 2 * u), with: .color(Color.white.opacity(0.4 * alpha)))
            default:
                let x = Double(c.x)
                let y = Double(c.y)
                var swap = Path()
                swap.move(to: CGPoint(x: x - 13 * u, y: y - 5 * u))
                swap.addLine(to: CGPoint(x: x + 11 * u, y: y - 5 * u))
                swap.move(to: CGPoint(x: x + 5 * u, y: y - 11 * u))
                swap.addLine(to: CGPoint(x: x + 11 * u, y: y - 5 * u))
                swap.addLine(to: CGPoint(x: x + 5 * u, y: y + 1 * u))
                swap.move(to: CGPoint(x: x + 13 * u, y: y + 7 * u))
                swap.addLine(to: CGPoint(x: x - 11 * u, y: y + 7 * u))
                swap.move(to: CGPoint(x: x - 5 * u, y: y + 1 * u))
                swap.addLine(to: CGPoint(x: x - 11 * u, y: y + 7 * u))
                swap.addLine(to: CGPoint(x: x - 5 * u, y: y + 13 * u))
                ctx.stroke(swap, with: .color(P.block(3).color(alpha)), style: stroke)
            }

            let dot = CGRect(x: Double(rect.maxX) - 15 * u, y: Double(rect.minY) - 6 * u, width: 22 * u, height: 22 * u)
            ctx.fill(Path(ellipseIn: dot), with: .color(alive ? P.badge.color() : P.frameSide.color()))
            ctx.draw(Text("\(left)").font(hudFont(12, .heavy)).foregroundColor(.white), at: CGPoint(x: dot.midX, y: dot.midY), anchor: .center)
        }
    }
}

// MARK: - The clip

/// The round the clip shows: one fixed board, cleared block by block in its solving order, then
/// the chest opens.
enum JamSlideClip {
    static let level: JamSlideLevel = JamSlideLevel.make(number: 3, seed: 0x5EED_1A2F)
    static let cleared = 0.72      // the share of the clip spent clearing the board
    static let gain = 200

    static func frame(phase: Double, showHUD: Bool) -> JamSlideFrame {
        let p = phase.isFinite ? JamSlideMath.clamp(phase) : 0
        let lv = level
        let n = lv.solution.count
        var f = JamSlideFrame()
        f.cols = lv.cols
        f.rows = lv.rows
        f.showHUD = showHUD
        f.level = lv.number
        f.ambient = p * 40
        f.timeLeft = 104 - p * 38
        f.boosters = [1, 0, 1]

        // Progress through the solution: whole blocks gone, one on its way.
        let progress = Swift.max(0, (p - 0.04) / (cleared - 0.04)) * Double(n)
        let gone = Swift.min(n, Int(progress.rounded(.down)))
        let frac = gone < n ? progress - Double(gone) : 1
        var gates = lv.gates
        var away = [Bool](repeating: false, count: lv.blocks.count)
        var score = 0
        for k in 0..<gone {
            let b = lv.blocks[lv.solution[k]]
            away[b.id] = true
            score += 10 * b.cells
            if gates[b.gate].counted {
                gates[b.gate].left -= 1
                gates[b.gate].age = k == gone - 1 && gone < n ? frac * 0.9 : 10
                if gates[b.gate].left <= 0 { gates[b.gate].shut = true }
            }
        }
        f.gates = gates
        f.movesLeft = lv.moveBudget - gone
        f.scoreAge = gone > 0 && gone < n ? frac * 0.4 : 10

        let moving = gone < n ? lv.solution[gone] : -1
        for b in lv.blocks where !away[b.id] {
            var s = JamSlideSprite(x: Double(b.x), y: Double(b.y), w: b.w, h: b.h, color: b.color, lane: b.lane)
            if b.id == moving, frac > 0.3 {
                let k = JamSlideMath.easeOut((frac - 0.3) / 0.7)
                let lane = b.exit.axis == 0 ? lv.cols : lv.rows
                let pos = b.exit.axis == 0 ? b.x : b.y
                let size = b.exit.axis == 0 ? b.w : b.h
                let before = Double(pos) + Double(size) * 0.5
                let after = Double(lane - pos - size) + Double(size) * 0.5
                let shift = b.exit.dir * (b.exit.dir < 0 ? before : after) * k
                if b.exit.axis == 0 { s.x += shift } else { s.y += shift }
                s.lift = JamSlideMath.smooth(0, 0.15, frac)
            }
            f.sprites.append(s)
        }

        // The last block out is still bursting at its gate.
        if gone > 0, gone < n, frac < 0.8 {
            let b = lv.blocks[lv.solution[gone - 1]]
            let age = frac * 0.9
            var rng = JamSlideRandom(seed: UInt64(b.id + 3), salt: JamSlideRandom.round)
            let cx = b.exit.axis == 0 ? (b.exit.dir < 0 ? 0.0 : Double(lv.cols)) : Double(b.x) + Double(b.w) / 2
            let cy = b.exit.axis == 1 ? (b.exit.dir < 0 ? 0.0 : Double(lv.rows)) : Double(b.y) + Double(b.h) / 2
            for _ in 0..<14 {
                let t = rng.range(0, 2 * .pi)
                let v = rng.range(2, 6)
                let vx = cos(t) * v
                let vy = sin(t) * v - 3
                f.particles.append(JamSlideParticle(x: cx + vx * age, y: cy + vy * age + 7 * age * age, vx: vx, vy: vy, age: age,
                                                    life: 0.75, size: rng.range(0.14, 0.26), color: rng.chance(0.3) ? -1 : b.color,
                                                    spin: rng.range(-6, 6)))
            }
            f.floats.append(JamSlideFloat(text: "+\(10 * b.cells)", x: Double(b.x) + Double(b.w) / 2,
                                          y: Double(b.y) + Double(b.h) / 2, age: age, big: false))
        }
        if gone >= 3, gone < n, gone % 3 == 0, frac < 0.9 {
            f.callout = "Quick"
            f.calloutAge = 0.3 + frac * 0.9
        }

        // The chest, once the board is clear.
        if gone == n, p >= cleared {
            let t = (p - cleared) / (1 - cleared) * 1.9
            f.chestAge = t
            let landed = JamSlideChest.landed(at: t)
            score += gain * landed / JamSlideChest.sparks
            if landed > 0 { f.scoreAge = Swift.max(0, t - (JamSlideChest.launch(landed - 1) + JamSlideChest.flight)) }
            f.callout = "Great"
            f.calloutSub = "Board \(lv.number) clear, +8s"
            f.calloutAge = t
        }
        f.score = score
        return f
    }
}
