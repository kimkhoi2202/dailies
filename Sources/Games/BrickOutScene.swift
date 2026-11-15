import SwiftUI

// Brick Out: slide toy bricks out of the board through gates of their own colour.
//
// This file holds what the clip in Videos and the playable game share: numbers, colours, the
// level maker, where the board sits on the screen, and the painter. BrickOutGame.swift holds the
// rules of a live round, the scripted player and the view the app shows. The pictures are the
// brick-out-* images in Resources/GameArt.

public struct BrickOutScene: View {
    public var phase: Double
    public var showHUD: Bool

    public init(phase: Double, showHUD: Bool) {
        self.phase = phase
        self.showHUD = showHUD
    }

    public var body: some View {
        Canvas(opaque: true, colorMode: .nonLinear, rendersAsynchronously: false) { context, size in
            if size.width <= 8 || size.height <= 8 { return }
            let frame = BrickOutClip.frame(phase: phase, showHUD: showHUD)
            BrickOutPainter(size: size).draw(&context, frame)
        }
    }
}

// MARK: - Numbers

enum BrickOutMath {
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

    /// 1 at both ends, a little over 1 in the middle: the scale of something that just popped.
    static func pop(_ v: Double) -> Double {
        let k = clamp(v)
        return 1 + 0.28 * sin(k * .pi) * (1 - k)
    }
}

/// SplitMix64. The level maker, the round and the scripted player use different salts.
struct BrickOutRandom {
    static let level: UInt64 = 0x9E6C_5B4A_3D2E_1F00
    static let round: UInt64 = 0x2545_F491_4F6C_DD1D
    static let pilot: UInt64 = 0x7069_6C6F_7442_7269

    private var state: UInt64

    init(seed: UInt64, salt: UInt64) {
        state = seed &* 0x9E37_79B9_7F4A_7C15 &+ salt
    }

    /// 0 ..< 1
    mutating func next() -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var v = state
        v = (v ^ (v >> 30)) &* 0xBF58_476D_1CE4_E5B9
        v = (v ^ (v >> 27)) &* 0x94D0_49BB_1331_11EB
        v ^= v >> 31
        return Double(v >> 11) / 9007199254740992.0
    }

    mutating func range(_ lo: Double, _ hi: Double) -> Double { lo + (hi - lo) * next() }

    mutating func int(_ bounds: ClosedRange<Int>) -> Int {
        bounds.lowerBound + Swift.min(bounds.count - 1, Int(next() * Double(bounds.count)))
    }

    mutating func chance(_ p: Double) -> Bool { next() < p }

    /// A fresh seed for something that needs its own sequence.
    mutating func seed() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var v = state
        v = (v ^ (v >> 30)) &* 0xBF58_476D_1CE4_E5B9
        v = (v ^ (v >> 27)) &* 0x94D0_49BB_1331_11EB
        return v ^ (v >> 31)
    }
}

// MARK: - Colour

struct BrickOutTint {
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

    static let white = BrickOutTint(1, 1, 1)
    static let black = BrickOutTint(0, 0, 0)

    func mix(_ other: BrickOutTint, _ k: Double) -> BrickOutTint {
        BrickOutTint(r + (other.r - r) * k, g + (other.g - g) * k, b + (other.b - b) * k)
    }

    func scaled(_ k: Double) -> BrickOutTint {
        BrickOutTint(Swift.min(1, r * k), Swift.min(1, g * k), Swift.min(1, b * k))
    }

    func color(_ alpha: Double = 1) -> Color { Color(.sRGB, red: r, green: g, blue: b, opacity: alpha) }
}

enum BrickOutPalette {
    /// Brick colours by index. A gate of the same index lets the brick out.
    static let bricks: [BrickOutTint] = [0xF4506C, 0xFF8E3C, 0xFFD23F, 0x4FD46A, 0x3E8BFF, 0xB46BFF]
        .map { BrickOutTint(hex: $0) }

    static let skyBottom = BrickOutTint(hex: 0x150C2C)
    static let frame = BrickOutTint(hex: 0x4D3C8E)
    static let frameDark = BrickOutTint(hex: 0x2A1F5C)
    static let frameLight = BrickOutTint(hex: 0x7A68C4)
    static let floorLine = BrickOutTint(hex: 0x2F2360)
    static let card = BrickOutTint(hex: 0x1C1240)
    static let ice = BrickOutTint(hex: 0x8FE3FF)
    static let shadow = BrickOutTint(hex: 0x0C0620)

    static func brick(_ index: Int) -> BrickOutTint {
        bricks[Swift.max(0, Swift.min(bricks.count - 1, index))]
    }
}

// MARK: - A level

enum BrickOutSide: Int {
    case top = 0, right, bottom, left

    /// 0: a brick leaves along x. 1: along y.
    var axis: Int { self == .left || self == .right ? 0 : 1 }
    /// -1 toward the top or the left edge, +1 toward the bottom or the right edge.
    var dir: Double { self == .top || self == .left ? -1 : 1 }
}

/// A coloured opening in the frame. It spans `length` edge cells from `start`.
struct BrickOutGate {
    var side: BrickOutSide
    var start: Int
    var length: Int
    var color: Int
}

/// A brick on the board, in cells. Its top left cell is (x, y).
struct BrickOutBlock {
    var id: Int
    var x: Int
    var y: Int
    var w: Int
    var h: Int
    var color: Int
    /// The side it came in from, so the side it can leave by in one slide.
    var exit: BrickOutSide

    var cells: Int { w * h }
}

/// One board. Made by sliding bricks in from the gates, so sliding them out in the reverse order
/// always clears it.
struct BrickOutLevel {
    var number: Int
    var cols: Int
    var rows: Int
    var gates: [BrickOutGate] = []
    var blocks: [BrickOutBlock] = []
    /// Block ids in an order that clears the board with one slide each.
    var solution: [Int] = []
    var moveBudget: Int = 0

    static let colorsAtStart = 4

    /// The gate colour at one edge cell, or -1 where the frame is solid.
    func gateColor(side: BrickOutSide, at index: Int) -> Int {
        for gate in gates where gate.side == side {
            if index >= gate.start && index < gate.start + gate.length { return gate.color }
        }
        return -1
    }

    static func make(number: Int, seed: UInt64) -> BrickOutLevel {
        var rng = BrickOutRandom(seed: seed, salt: BrickOutRandom.level &+ UInt64(Swift.max(0, number)))
        let sizes: [(Int, Int)] = [(5, 6), (5, 7), (6, 7), (6, 8), (7, 8), (7, 9)]
        let size = sizes[Swift.max(0, Swift.min(sizes.count - 1, number - 1))]
        let cols = size.0
        let rows = size.1
        let colors = Swift.min(BrickOutPalette.bricks.count, colorsAtStart + number / 2)
        var level = BrickOutLevel(number: number, cols: cols, rows: rows)

        // Gates tile each edge in runs of one to three cells. Later levels keep a few solid stretches.
        let sides: [BrickOutSide] = [.top, .right, .bottom, .left]
        for side in sides {
            let edge = side.axis == 1 ? cols : rows
            var pos = 0
            while pos < edge {
                if number >= 3, rng.chance(0.12) {
                    pos += 1
                    continue
                }
                let len = rng.int(1...Swift.min(3, edge - pos))
                level.gates.append(BrickOutGate(side: side, start: pos, length: len, color: rng.int(0...(colors - 1))))
                pos += len
            }
        }
        if level.gates.isEmpty {
            level.gates.append(BrickOutGate(side: .top, start: 0, length: 1, color: 0))
        }

        var grid = [Int](repeating: -1, count: cols * rows)
        let fill = Swift.min(0.70, 0.52 + 0.03 * Double(number))
        let target = Int(Double(cols * rows) * fill)
        var filled = 0
        var attempts = 0
        while filled < target, attempts < 600 {
            attempts += 1
            let gate = level.gates[rng.int(0...(level.gates.count - 1))]
            let span = rng.int(1...gate.length)
            let along = gate.start + rng.int(0...(gate.length - span))
            let depth = rng.int(1...3)
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
            // Most bricks slide all the way in, so the middle of the board fills up too.
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
            level.blocks.append(BrickOutBlock(id: id, x: x0, y: y0, w: x1 - x0, h: y1 - y0, color: gate.color, exit: gate.side))
            filled += (x1 - x0) * (y1 - y0)
        }

        level.solution = level.blocks.map { $0.id }.reversed()
        level.moveBudget = level.blocks.count + 4 + level.blocks.count / 3
        return level
    }

    /// The cell at a distance inward from one edge cell.
    static func cell(side: BrickOutSide, along: Int, inward: Int, cols: Int, rows: Int) -> (x: Int, y: Int) {
        switch side {
        case .top: return (along, inward)
        case .bottom: return (along, rows - 1 - inward)
        case .left: return (inward, along)
        case .right: return (cols - 1 - inward, along)
        }
    }
}

// MARK: - What is on screen

/// A brick as the painter wants it. Positions are in cells and may be fractional.
struct BrickOutSprite {
    var x: Double
    var y: Double
    var w: Int
    var h: Int
    var color: Int
    /// 0...1: how far it is lifted by a finger.
    var lift: Double = 0
    var scale: Double = 1
    var alpha: Double = 1
}

/// A bit of a burst brick. Positions and speeds are in cells.
struct BrickOutParticle {
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
struct BrickOutFloat {
    var text: String
    var x: Double
    var y: Double
    var age: Double
    var big: Bool
}

/// One frame of the game, as the painter wants it.
struct BrickOutFrame {
    var cols = 5
    var rows = 6
    var gates: [BrickOutGate] = []
    var sprites: [BrickOutSprite] = []
    var particles: [BrickOutParticle] = []
    var floats: [BrickOutFloat] = []
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
    /// Uses left on each booster: hold time, smash, new deal.
    var boosters: [Int] = [1, 1, 1]
    /// The booster waiting for a tap on a brick, or -1.
    var armed = -1
    var showHUD = true
    var ambient = 0.0
    /// 0...1: the dim and the message when the round is over.
    var endFade = 0.0
    var endText = ""
}

// MARK: - Layout

/// Where the board, the HUD and the boosters sit. Design points scale from a 402 x 874 phone.
struct BrickOutLayout {
    static let frameBand = 16.0
    static let boosterSize = 62.0
    static let boosterGap = 96.0

    let W: Double
    let H: Double
    let u: Double
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
        self.cols = Swift.max(1, cols)
        self.rows = Swift.max(1, rows)
        let top = 218 * u
        let bottom = H - Double(GameLayout.bottomInset) - 118 * u
        let band = Self.frameBand * u
        let wide = (W - 48 * u - 2 * band) / Double(self.cols)
        let tall = (bottom - top - 2 * band - 24 * u) / Double(self.rows)
        cell = Swift.max(8, Swift.min(66 * u, Swift.min(wide, tall)))
        originX = (W - cell * Double(self.cols)) / 2
        originY = (top + bottom - cell * Double(self.rows)) / 2
    }

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

    var boosterY: Double { H - Double(GameLayout.bottomInset) - 46 * u }

    func boosterRect(_ k: Int) -> CGRect {
        let s = Self.boosterSize * u
        let cx = W / 2 + Double(k - 1) * Self.boosterGap * u
        return CGRect(x: cx - s / 2, y: boosterY - s / 2, width: s, height: s)
    }

    /// The booster under a touch, or -1.
    func booster(at p: CGPoint) -> Int {
        for k in 0..<3 where boosterRect(k).insetBy(dx: -8 * u, dy: -8 * u).contains(p) { return k }
        return -1
    }
}

// MARK: - Pictures

/// The images, resolved once per frame.
struct BrickOutArt {
    let backdrop: GraphicsContext.ResolvedImage
    let tray: GraphicsContext.ResolvedImage
    /// One brick body and one stud per brick colour.
    let bodies: [GraphicsContext.ResolvedImage]
    let studs: [GraphicsContext.ResolvedImage]
    /// Hold time, smash, new deal.
    let boosters: [GraphicsContext.ResolvedImage]

    init(_ ctx: GraphicsContext) {
        backdrop = ctx.resolve(Image("brick-out-backdrop"))
        tray = ctx.resolve(Image("brick-out-tray"))
        let colours = 0..<BrickOutPalette.bricks.count
        bodies = colours.map { ctx.resolve(Image("brick-out-body-\($0)")) }
        studs = colours.map { ctx.resolve(Image("brick-out-stud-\($0)")) }
        boosters = ["brick-out-hold", "brick-out-smash", "brick-out-new"].map { ctx.resolve(Image($0)) }
    }

    func body(_ index: Int) -> GraphicsContext.ResolvedImage { bodies[Swift.max(0, Swift.min(bodies.count - 1, index))] }
    func stud(_ index: Int) -> GraphicsContext.ResolvedImage { studs[Swift.max(0, Swift.min(studs.count - 1, index))] }
}

// MARK: - Painter

struct BrickOutPainter {
    typealias M = BrickOutMath
    typealias P = BrickOutPalette

    let W: Double
    let H: Double
    let u: Double

    init(size: CGSize) {
        W = Double(size.width)
        H = Double(size.height)
        u = Swift.min(W / 402, H / 874)
    }

    func draw(_ ctx: inout GraphicsContext, _ f: BrickOutFrame) {
        let lay = BrickOutLayout(size: CGSize(width: W, height: H), cols: f.cols, rows: f.rows)
        let art = BrickOutArt(ctx)
        drawSky(&ctx, f, art)
        drawBoard(&ctx, lay, f, art)
        drawBricks(&ctx, lay, f, art)
        drawParticles(&ctx, lay, f)
        drawFloats(&ctx, lay, f)
        if f.endFade > 0.01 { drawEnd(&ctx, lay, f) }
        if let words = f.callout { drawCallout(&ctx, lay, words, sub: f.calloutSub, age: f.calloutAge) }
        if f.showHUD {
            drawHUD(&ctx, f)
            drawBoosters(&ctx, lay, f, art)
            if let hint = f.hint, f.hintAlpha > 0.01 { drawHint(&ctx, lay, hint, alpha: f.hintAlpha, pulse: f.hintPulse) }
        }
    }

    // MARK: Helpers

    private func rounded(_ r: CGRect, _ radius: Double) -> Path {
        Path(roundedRect: r, cornerRadius: Swift.max(0, Swift.min(radius, Swift.min(r.width, r.height) / 2)), style: .continuous)
    }

    private func label(_ ctx: inout GraphicsContext, _ text: Text, at p: CGPoint, anchor: UnitPoint, alpha: Double = 1, shadow: Double = 0.4) {
        if shadow > 0 {
            ctx.draw(text.foregroundColor(P.shadow.color(shadow * alpha)), at: CGPoint(x: p.x, y: p.y + 2 * u), anchor: anchor)
        }
        ctx.draw(text.foregroundColor(Color.white.opacity(alpha)), at: p, anchor: anchor)
    }

    private func font(_ size: Double, _ weight: Font.Weight = .heavy) -> Font {
        .system(size: size * u, weight: weight, design: .rounded)
    }

    /// An image at a rect, faded by alpha.
    private func image(_ ctx: inout GraphicsContext, _ art: GraphicsContext.ResolvedImage, in rect: CGRect, alpha: Double = 1) {
        if alpha <= 0.001 { return }
        let before = ctx.opacity
        ctx.opacity = before * Swift.min(1, alpha)
        ctx.draw(art, in: rect)
        ctx.opacity = before
    }

    /// Stretches an image over a rect of any shape the nine-slice way: the outer `cap` share of
    /// the image on each side keeps its proportions at `edge` points, only the middle stretches.
    private func sliced(_ ctx: inout GraphicsContext, _ art: GraphicsContext.ResolvedImage, in rect: CGRect,
                        cap: Double, edge: Double) {
        let iw = Double(art.size.width)
        let ih = Double(art.size.height)
        if iw < 1 || ih < 1 { return }
        let e = Swift.min(edge, Double(rect.width) / 2, Double(rect.height) / 2)
        let sx = [0, cap * iw, iw - cap * iw, iw]
        let sy = [0, cap * ih, ih - cap * ih, ih]
        let dx = [Double(rect.minX), Double(rect.minX) + e, Double(rect.maxX) - e, Double(rect.maxX)]
        let dy = [Double(rect.minY), Double(rect.minY) + e, Double(rect.maxY) - e, Double(rect.maxY)]
        // Pieces overlap by a hair so no seam shows between them.
        let hair = 0.3
        for i in 0..<3 {
            let scaleX = (dx[i + 1] - dx[i]) / (sx[i + 1] - sx[i])
            if dx[i + 1] - dx[i] <= 0.01 { continue }
            for j in 0..<3 {
                if dy[j + 1] - dy[j] <= 0.01 { continue }
                let scaleY = (dy[j + 1] - dy[j]) / (sy[j + 1] - sy[j])
                var piece = ctx
                piece.clip(to: Path(CGRect(x: dx[i] - (i > 0 ? hair : 0), y: dy[j] - (j > 0 ? hair : 0),
                                           width: dx[i + 1] - dx[i] + (i > 0 ? hair : 0),
                                           height: dy[j + 1] - dy[j] + (j > 0 ? hair : 0))))
                piece.draw(art, in: CGRect(x: dx[i] - sx[i] * scaleX, y: dy[j] - sy[j] * scaleY,
                                           width: iw * scaleX, height: ih * scaleY))
            }
        }
    }

    // MARK: Sky

    private func drawSky(_ ctx: inout GraphicsContext, _ f: BrickOutFrame, _ art: BrickOutArt) {
        // The backdrop fills the screen, cropped at the sides or the ends.
        let size = art.backdrop.size
        let fill = Swift.max(W / Swift.max(1, Double(size.width)), H / Swift.max(1, Double(size.height)))
        let w = Double(size.width) * fill
        let h = Double(size.height) * fill
        ctx.draw(art.backdrop, in: CGRect(x: (W - w) / 2, y: (H - h) / 2, width: w, height: h))
        // A few soft dots drifting up, so the backdrop is never still.
        var rng = BrickOutRandom(seed: 11, salt: BrickOutRandom.level)
        for _ in 0..<26 {
            let x = rng.next() * W
            let speed = 6 + rng.next() * 10
            let y0 = rng.next() * H
            let y = (y0 - f.ambient * speed * u).truncatingRemainder(dividingBy: H + 20 * u)
            let yy = y < -10 * u ? y + H + 20 * u : y
            let r = (1.2 + rng.next() * 1.8) * u
            ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: yy - r, width: 2 * r, height: 2 * r)), with: .color(Color.white.opacity(0.10)))
        }
    }

    // MARK: Board

    private func drawBoard(_ ctx: inout GraphicsContext, _ lay: BrickOutLayout, _ f: BrickOutFrame, _ art: BrickOutArt) {
        let frame = lay.frame
        let radius = 14 * u
        // Drop shadow, then the tray. Its rim is about a tenth of the picture: keep it one band wide.
        ctx.fill(rounded(frame.offsetBy(dx: 0, dy: 10 * u).insetBy(dx: -2 * u, dy: 0), radius + 2 * u), with: .color(P.shadow.color(0.45)))
        sliced(&ctx, art.tray, in: frame, cap: 0.13, edge: 1.3 * lay.band)

        // The floor's grid.
        let board = lay.board
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
        ctx.stroke(lines, with: .color(P.floorLine.color()), lineWidth: Swift.max(1, 1.2 * u))

        // Gates on the frame.
        let band = lay.band
        for gate in f.gates {
            let tint = P.brick(gate.color)
            let a0 = Double(gate.start) * lay.cell
            let len = Double(gate.length) * lay.cell
            var rect: CGRect
            var tip: CGPoint
            var base0: CGPoint
            var base1: CGPoint
            let arrow = 5 * u
            switch gate.side {
            case .top:
                rect = CGRect(x: board.minX + a0, y: frame.minY, width: len, height: band)
                tip = CGPoint(x: rect.midX, y: rect.minY + 3 * u)
                base0 = CGPoint(x: rect.midX - arrow, y: rect.maxY - 3 * u)
                base1 = CGPoint(x: rect.midX + arrow, y: rect.maxY - 3 * u)
            case .bottom:
                rect = CGRect(x: board.minX + a0, y: board.maxY, width: len, height: band)
                tip = CGPoint(x: rect.midX, y: rect.maxY - 3 * u)
                base0 = CGPoint(x: rect.midX - arrow, y: rect.minY + 3 * u)
                base1 = CGPoint(x: rect.midX + arrow, y: rect.minY + 3 * u)
            case .left:
                rect = CGRect(x: frame.minX, y: board.minY + a0, width: band, height: len)
                tip = CGPoint(x: rect.minX + 3 * u, y: rect.midY)
                base0 = CGPoint(x: rect.maxX - 3 * u, y: rect.midY - arrow)
                base1 = CGPoint(x: rect.maxX - 3 * u, y: rect.midY + arrow)
            case .right:
                rect = CGRect(x: board.maxX, y: board.minY + a0, width: band, height: len)
                tip = CGPoint(x: rect.maxX - 3 * u, y: rect.midY)
                base0 = CGPoint(x: rect.minX + 3 * u, y: rect.midY - arrow)
                base1 = CGPoint(x: rect.minX + 3 * u, y: rect.midY + arrow)
            }
            let inset = rect.insetBy(dx: 1.5 * u, dy: 1.5 * u)
            ctx.fill(rounded(inset, 4 * u), with: .color(tint.scaled(0.72).color()))
            ctx.fill(rounded(inset.insetBy(dx: 1.5 * u, dy: 1.5 * u), 3 * u), with: .color(tint.color()))
            var head = Path()
            head.move(to: tip)
            head.addLine(to: base0)
            head.addLine(to: base1)
            head.closeSubpath()
            ctx.fill(head, with: .color(Color.white.opacity(0.85)))
        }
    }

    // MARK: Bricks

    private func drawBricks(_ ctx: inout GraphicsContext, _ lay: BrickOutLayout, _ f: BrickOutFrame, _ art: BrickOutArt) {
        var inside = ctx
        inside.clip(to: rounded(lay.frame.insetBy(dx: 3 * u, dy: 3 * u), 10 * u))
        for s in f.sprites where s.lift < 0.01 { drawBrick(&inside, lay, s, art) }
        for s in f.sprites where s.lift >= 0.01 { drawBrick(&inside, lay, s, art) }
    }

    private func drawBrick(_ ctx: inout GraphicsContext, _ lay: BrickOutLayout, _ s: BrickOutSprite, _ art: BrickOutArt) {
        if s.scale <= 0.02 || s.alpha <= 0.01 { return }
        let gap = 2.2 * u
        let full = CGRect(x: lay.originX + s.x * lay.cell, y: lay.originY + s.y * lay.cell,
                          width: Double(s.w) * lay.cell, height: Double(s.h) * lay.cell)
        let box = full.insetBy(dx: gap, dy: gap)
        let grow = (s.scale - 1) + 0.06 * s.lift
        let rect = box.insetBy(dx: -box.width * grow / 2, dy: -box.height * grow / 2).offsetBy(dx: 0, dy: -6 * u * s.lift)
        let depth = 5 * u
        let radius = 7 * u
        let a = s.alpha

        if s.lift > 0.01 {
            ctx.fill(rounded(rect.offsetBy(dx: 0, dy: 10 * u * s.lift).insetBy(dx: -2 * u, dy: -2 * u), radius),
                     with: .color(P.shadow.color(0.40 * s.lift * a)))
        }
        // The body stretches to the brick's size; its studs, two per cell each way, sit on the top face.
        let before = ctx.opacity
        ctx.opacity = before * a
        sliced(&ctx, art.body(s.color), in: rect, cap: 0.3, edge: Swift.min(Double(rect.width) / Double(s.w), Double(rect.height) / Double(s.h)) * 0.3)
        let top = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height - depth)
        let sx = rect.width / Double(s.w)
        let sy = top.height / Double(s.h)
        let r = Swift.min(sx, sy) * 0.19
        let stud = art.stud(s.color)
        for i in 0..<s.w {
            for j in 0..<s.h {
                for q in 0..<4 {
                    let cx = rect.minX + sx * (Double(i) + 0.27 + 0.46 * Double(q % 2))
                    let cy = top.minY + sy * (Double(j) + 0.27 + 0.46 * Double(q / 2))
                    ctx.draw(stud, in: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r))
                }
            }
        }
        ctx.opacity = before
    }

    // MARK: Bursts and words

    private func drawParticles(_ ctx: inout GraphicsContext, _ lay: BrickOutLayout, _ f: BrickOutFrame) {
        for p in f.particles {
            let k = M.clamp(p.age / Swift.max(0.01, p.life))
            if k >= 1 { continue }
            let alpha = 1 - M.smooth(0.55, 1, k)
            let size = p.size * lay.cell * (1 - 0.4 * k)
            let c = lay.point(p.x, p.y)
            var local = ctx
            local.translateBy(x: c.x, y: c.y)
            local.rotate(by: .radians(p.spin * p.age))
            let box = CGRect(x: -size / 2, y: -size / 2, width: size, height: size)
            let tint = p.color < 0 ? BrickOutTint.white : P.brick(p.color)
            local.fill(rounded(box, size * 0.25), with: .color(tint.color(alpha)))
            local.fill(rounded(box.insetBy(dx: size * 0.2, dy: size * 0.2), size * 0.15), with: .color(Color.white.opacity(0.35 * alpha)))
        }
    }

    private func drawFloats(_ ctx: inout GraphicsContext, _ lay: BrickOutLayout, _ f: BrickOutFrame) {
        for w in f.floats {
            let k = M.clamp(w.age / 1.1)
            let alpha = M.easeOut(M.clamp(w.age / 0.12)) * (1 - M.smooth(0.55, 1, k))
            if alpha <= 0.01 { continue }
            let rise = (w.big ? 54.0 : 40.0) * u * M.easeOut(k)
            let size = (w.big ? 30.0 : 22.0) * (0.8 + 0.2 * M.easeOut(M.clamp(w.age / 0.14)))
            let c = lay.point(w.x, w.y)
            let text = Text(w.text).font(font(size, .black))
            label(&ctx, text, at: CGPoint(x: c.x, y: c.y - rise), anchor: .center, alpha: alpha, shadow: 0.5)
        }
    }

    private func drawCallout(_ ctx: inout GraphicsContext, _ lay: BrickOutLayout, _ words: String, sub: String?, age: Double) {
        let arrive = M.easeOut(M.clamp(age / 0.18))
        let alpha = arrive * (1 - M.smooth(1.1, 1.5, age))
        if alpha <= 0.01 { return }
        let size = 44 * (0.6 + 0.4 * arrive) * M.pop(age / 0.5)
        let board = lay.board
        let c = CGPoint(x: board.midX, y: board.midY - 10 * u)
        let backing = CGRect(x: c.x - 120 * u, y: c.y - 42 * u, width: 240 * u, height: sub == nil ? 76 * u : 100 * u)
        ctx.fill(rounded(backing, 22 * u), with: .color(P.card.color(0.78 * alpha)))
        let text = Text(words).font(font(size, .black)).kerning(1.2 * u)
        label(&ctx, text, at: CGPoint(x: c.x, y: c.y - (sub == nil ? 4 * u : 0)), anchor: .center, alpha: alpha, shadow: 0.5)
        if let sub {
            let line = Text(sub).font(font(16, .bold)).kerning(0.6 * u)
            label(&ctx, line, at: CGPoint(x: c.x, y: c.y + 38 * u), anchor: .center, alpha: 0.9 * alpha, shadow: 0.3)
        }
    }

    private func drawHint(_ ctx: inout GraphicsContext, _ lay: BrickOutLayout, _ words: String, alpha: Double, pulse: Double) {
        let strength = alpha * (0.75 + 0.25 * pulse)
        let text = Text(words).font(font(17, .bold)).kerning(0.3 * u)
        let y = lay.frame.maxY + 24 * u
        label(&ctx, text, at: CGPoint(x: W / 2, y: y), anchor: .center, alpha: strength, shadow: 0.4)
    }

    private func drawEnd(_ ctx: inout GraphicsContext, _ lay: BrickOutLayout, _ f: BrickOutFrame) {
        let k = M.clamp(f.endFade)
        ctx.fill(rounded(lay.frame, 14 * u), with: .color(P.shadow.color(0.6 * k)))
        let board = lay.board
        let size = 36 * (0.7 + 0.3 * M.easeOut(k))
        let text = Text(f.endText).font(font(size, .black))
        label(&ctx, text, at: CGPoint(x: board.midX, y: board.midY - 18 * u), anchor: .center, alpha: k, shadow: 0.5)
        let line = Text("\(f.score) points").font(font(18, .bold))
        label(&ctx, line, at: CGPoint(x: board.midX, y: board.midY + 20 * u), anchor: .center, alpha: 0.9 * k, shadow: 0.3)
    }

    // MARK: HUD

    private func drawHUD(_ ctx: inout GraphicsContext, _ f: BrickOutFrame) {
        let cx = W / 2
        // The clock, between the app's corners.
        let pillY = Swift.max(Double(GameLayout.statusBarHeight) + 4, 66 * u)
        let pill = CGRect(x: cx - 66 * u, y: pillY, width: 132 * u, height: 38 * u)
        let low = f.timeLeft < 10 && !f.frozen
        let pulse = low ? 0.5 + 0.5 * sin(f.ambient * 9) : 0
        let edge = f.frozen ? P.ice : (low ? P.brick(0) : P.frameLight)
        ctx.fill(rounded(pill.offsetBy(dx: 0, dy: 3 * u), 19 * u), with: .color(P.shadow.color(0.35)))
        ctx.fill(rounded(pill, 19 * u), with: .color(P.card.color(0.95)))
        ctx.stroke(rounded(pill, 19 * u), with: .color(edge.color(0.6 + 0.4 * pulse)), lineWidth: 1.8 * u)
        let whole = Swift.max(0, Int(f.timeLeft.rounded(.up)))
        let clock = String(format: "%d:%02d", whole / 60, whole % 60)
        let clockText = Text(clock).font(font(23, .heavy)).monospacedDigit()
        let clockTint = f.frozen ? P.ice : (low ? P.brick(0).mix(.white, 0.3) : BrickOutTint.white)
        ctx.draw(clockText.foregroundColor(clockTint.color()), at: CGPoint(x: cx + 8 * u, y: pill.midY), anchor: .center)
        // A small clock face, or a snowflake while time is held.
        let iconC = CGPoint(x: pill.minX + 22 * u, y: pill.midY)
        if f.frozen {
            var flake = Path()
            for k in 0..<3 {
                let t = Double(k) * .pi / 3
                flake.move(to: CGPoint(x: iconC.x + cos(t) * 8 * u, y: iconC.y + sin(t) * 8 * u))
                flake.addLine(to: CGPoint(x: iconC.x - cos(t) * 8 * u, y: iconC.y - sin(t) * 8 * u))
            }
            ctx.stroke(flake, with: .color(P.ice.color()), style: StrokeStyle(lineWidth: 2 * u, lineCap: .round))
        } else {
            ctx.stroke(Path(ellipseIn: CGRect(x: iconC.x - 7 * u, y: iconC.y - 7 * u, width: 14 * u, height: 14 * u)),
                       with: .color(Color.white.opacity(0.75)), lineWidth: 1.8 * u)
            var hands = Path()
            hands.move(to: CGPoint(x: iconC.x, y: iconC.y - 4.5 * u))
            hands.addLine(to: iconC)
            hands.addLine(to: CGPoint(x: iconC.x + 3.5 * u, y: iconC.y))
            ctx.stroke(hands, with: .color(Color.white.opacity(0.75)), style: StrokeStyle(lineWidth: 1.8 * u, lineCap: .round))
        }

        // The score, counting up when it changes.
        let pop = 1 + 0.18 * exp(-7 * f.scoreAge) * Swift.max(0, 1 - f.scoreAge * 1.5)
        let number = Text("\(f.score)").font(font(46 * pop, .heavy)).monospacedDigit()
        label(&ctx, number, at: CGPoint(x: cx, y: 150 * u), anchor: .center, shadow: 0.4)

        let level = Text("LEVEL \(f.level)").font(font(13, .bold)).kerning(2 * u)
        let moves = Text("MOVES \(Swift.max(0, f.movesLeft))").font(font(13, .bold)).kerning(2 * u)
        let moveTint = f.movesLeft <= 2 ? P.brick(0).mix(.white, 0.3) : BrickOutTint.white
        ctx.draw(level.foregroundColor(Color.white.opacity(0.75)), at: CGPoint(x: cx - 64 * u, y: 194 * u), anchor: .center)
        ctx.draw(moves.foregroundColor(moveTint.color(0.85)), at: CGPoint(x: cx + 64 * u, y: 194 * u), anchor: .center)
    }

    // MARK: Boosters

    private func drawBoosters(_ ctx: inout GraphicsContext, _ lay: BrickOutLayout, _ f: BrickOutFrame, _ art: BrickOutArt) {
        for k in 0..<3 {
            let rect = lay.boosterRect(k)
            let left = k < f.boosters.count ? f.boosters[k] : 0
            let alive = left > 0
            let alpha = alive ? 1.0 : 0.38
            let armed = f.armed == k
            let radius = 16 * u
            ctx.fill(rounded(rect.offsetBy(dx: 0, dy: 4 * u), radius), with: .color(P.shadow.color(0.4 * alpha)))
            ctx.fill(rounded(rect, radius), with: .color(P.frame.mix(.black, armed ? 0.0 : 0.15).color(alpha)))
            let rim = armed ? Color.white.opacity(0.7 + 0.3 * sin(f.ambient * 8)) : P.frameLight.color(0.6 * alpha)
            ctx.stroke(rounded(rect.insetBy(dx: 1.5 * u, dy: 1.5 * u), radius - 1.5 * u), with: .color(rim), lineWidth: 2 * u)

            let icon = 40 * u
            image(&ctx, art.boosters[k], in: CGRect(x: rect.midX - icon / 2, y: rect.midY - 2 * u - icon / 2, width: icon, height: icon), alpha: alpha)

            let badge = CGRect(x: rect.maxX - 14 * u, y: rect.maxY - 14 * u, width: 20 * u, height: 20 * u)
            ctx.fill(Path(ellipseIn: badge), with: .color(alive ? Color.white : P.frameDark.color()))
            ctx.draw(Text("\(left)").font(font(12, .heavy)).foregroundColor(alive ? P.skyBottom.color() : Color.white.opacity(0.5)),
                     at: CGPoint(x: badge.midX, y: badge.midY), anchor: .center)

            let names = ["Hold", "Smash", "New"]
            ctx.draw(Text(names[k]).font(font(11, .bold)).kerning(0.8 * u).foregroundColor(Color.white.opacity(0.6 * alpha)),
                     at: CGPoint(x: rect.midX, y: rect.maxY + 12 * u), anchor: .center)
        }
    }
}

// MARK: - The clip

/// The round the clip shows: one fixed level, cleared brick by brick in its solving order.
enum BrickOutClip {
    static let level: BrickOutLevel = BrickOutLevel.make(number: 3, seed: 0x5EED_B10C)
    static let span = 0.88     // the share of the clip spent clearing the board

    static func frame(phase: Double, showHUD: Bool) -> BrickOutFrame {
        let p = phase.isFinite ? BrickOutMath.clamp(phase) : 0
        let lv = level
        let n = lv.solution.count
        var f = BrickOutFrame()
        f.cols = lv.cols
        f.rows = lv.rows
        f.gates = lv.gates
        f.showHUD = showHUD
        f.level = 3
        f.ambient = p * 40
        f.timeLeft = 124 - p * 46
        f.boosters = [1, 0, 1]

        // Progress through the solution: whole bricks gone, one on its way.
        let progress = Swift.max(0, (p - 0.04) / span) * Double(n)
        let gone = Swift.min(n, Int(progress.rounded(.down)))
        let frac = progress - Double(gone)
        var away = Set<Int>()
        var score = 0
        for k in 0..<gone {
            away.insert(lv.solution[k])
            score += 20 * (lv.blocks[lv.solution[k]].cells)
        }
        f.score = score
        f.movesLeft = lv.moveBudget - gone
        f.scoreAge = gone > 0 ? frac * 0.4 : 10

        let moving = gone < n ? lv.solution[gone] : -1
        for b in lv.blocks where !away.contains(b.id) {
            var s = BrickOutSprite(x: Double(b.x), y: Double(b.y), w: b.w, h: b.h, color: b.color)
            if b.id == moving, frac > 0.3 {
                let k = BrickOutMath.easeOut((frac - 0.3) / 0.7)
                let lane = b.exit.axis == 0 ? lv.cols : lv.rows
                let pos = b.exit.axis == 0 ? b.x : b.y
                let size = b.exit.axis == 0 ? b.w : b.h
                let before = Double(pos) + Double(size) * 0.5
                let after = Double(lane - pos - size) + Double(size) * 0.5
                let reach = b.exit.dir < 0 ? before : after
                let shift = b.exit.dir * reach * k
                if b.exit.axis == 0 { s.x += shift } else { s.y += shift }
                s.lift = BrickOutMath.smooth(0, 0.15, frac)
            }
            f.sprites.append(s)
        }

        // The last brick out is still bursting at its gate.
        if gone > 0, frac < 0.8 {
            let b = lv.blocks[lv.solution[gone - 1]]
            var rng = BrickOutRandom(seed: UInt64(b.id + 3), salt: BrickOutRandom.round)
            let age = frac * 0.9
            let cx = b.exit.axis == 0 ? (b.exit.dir < 0 ? 0.0 : Double(lv.cols)) : Double(b.x) + Double(b.w) / 2
            let cy = b.exit.axis == 1 ? (b.exit.dir < 0 ? 0.0 : Double(lv.rows)) : Double(b.y) + Double(b.h) / 2
            for _ in 0..<14 {
                let t = rng.range(0, 2 * .pi)
                let v = rng.range(2, 6)
                let vx = cos(t) * v
                let vy = sin(t) * v - 3
                f.particles.append(BrickOutParticle(x: cx + vx * age + 0.0, y: cy + vy * age + 7 * age * age, vx: vx, vy: vy,
                                                    age: age, life: 0.75, size: rng.range(0.12, 0.24), color: rng.chance(0.3) ? -1 : b.color, spin: rng.range(-6, 6)))
            }
            f.floats.append(BrickOutFloat(text: "+\(20 * b.cells)", x: Double(b.x) + Double(b.w) / 2, y: Double(b.y) + Double(b.h) / 2, age: age, big: false))
        }
        if gone >= 3, gone % 3 == 0, frac < 0.9 {
            f.callout = gone >= 6 ? "Great" : "Nice"
            f.calloutAge = 0.3 + frac * 0.9
        }
        return f
    }
}
