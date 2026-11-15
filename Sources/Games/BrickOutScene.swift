import SwiftUI

// Brick Out: swipe toy bricks out of the board through the gate of their own colour.
//
// This file holds what the cover and the playable game share: the board rules, the seeded deal,
// the layout and BrickOutPainter, which paints everything into one Canvas. BrickOutScene draws a
// scripted moment of a round from a phase (0...1). No assets, any frame size.

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
            BrickOutCover.paint(&context, size: size, phase: phase, showHUD: showHUD)
        }
    }
}

// MARK: - Numbers

enum BrickOutMath {
    static func clamp(_ v: Double, _ lo: Double = 0, _ hi: Double = 1) -> Double {
        Swift.max(lo, Swift.min(hi, v))
    }

    static func lerp(_ a: Double, _ b: Double, _ k: Double) -> Double { a + (b - a) * k }

    static func smooth(_ e0: Double, _ e1: Double, _ v: Double) -> Double {
        let k = clamp((v - e0) / (e1 - e0))
        return k * k * (3 - 2 * k)
    }

    static func easeOut(_ v: Double) -> Double {
        let rest = 1 - clamp(v)
        return 1 - rest * rest * rest
    }

    /// Overshoots a little past 1 and settles, for pops.
    static func easeOutBack(_ v: Double) -> Double {
        let t = clamp(v) - 1
        let s = 1.9
        return 1 + t * t * ((s + 1) * t + s)
    }
}

/// SplitMix64.
struct BrickOutRandom {
    static let deal: UInt64 = 0x2545F4914F6CDD1D
    static let friends: UInt64 = 0x9E6C63D0676A9A99
    static let sparks: UInt64 = 0xD1B54A32D192ED03
    static let pilot: UInt64 = 0x7069_6C6F_7421_0042

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

// MARK: - Colour

struct BrickOutTint {
    let r: Double
    let g: Double
    let b: Double

    func color(_ a: Double = 1) -> Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }

    func mix(_ o: BrickOutTint, _ k: Double) -> BrickOutTint {
        BrickOutTint(r: r + (o.r - r) * k, g: g + (o.g - g) * k, b: b + (o.b - b) * k)
    }

    static let black = BrickOutTint(r: 0.05, g: 0.03, b: 0.12)
    static let white = BrickOutTint(r: 1, g: 1, b: 1)
}

/// Every colour the game paints with, made once.
enum BrickOutInk {
    static let tints: [BrickOutTint] = [
        BrickOutTint(r: 0.98, g: 0.32, b: 0.36),
        BrickOutTint(r: 1.00, g: 0.77, b: 0.16),
        BrickOutTint(r: 0.36, g: 0.82, b: 0.32),
        BrickOutTint(r: 0.20, g: 0.62, b: 1.00),
        BrickOutTint(r: 0.66, g: 0.42, b: 1.00),
        BrickOutTint(r: 1.00, g: 0.47, b: 0.74),
    ]
    static let face: [Color] = tints.map { $0.color() }
    static let side: [Color] = tints.map { $0.mix(.black, 0.42).color() }
    static let stud: [Color] = tints.map { $0.mix(.white, 0.16).color() }
    static let studShade: [Color] = tints.map { $0.mix(.black, 0.3).color() }
    static let gateDark: [Color] = tints.map { $0.mix(.black, 0.3).color() }

    static let bgTop = Color(.sRGB, red: 0.19, green: 0.13, blue: 0.38, opacity: 1)
    static let bgBottom = Color(.sRGB, red: 0.09, green: 0.06, blue: 0.20, opacity: 1)
    static let background = Gradient(colors: [bgTop, bgBottom])
    static let glow = Gradient(colors: [Color(.sRGB, red: 0.52, green: 0.36, blue: 1, opacity: 0.30),
                                        Color(.sRGB, red: 0.52, green: 0.36, blue: 1, opacity: 0)])
    static let frame = Color(.sRGB, red: 0.33, green: 0.26, blue: 0.66, opacity: 1)
    static let frameLip = Color(.sRGB, red: 0.20, green: 0.15, blue: 0.42, opacity: 1)
    static let frameHi = Color(.sRGB, red: 0.52, green: 0.45, blue: 0.90, opacity: 1)
    static let well = Color(.sRGB, red: 0.12, green: 0.09, blue: 0.25, opacity: 1)
    static let wellCell = Color(.sRGB, red: 0.17, green: 0.13, blue: 0.33, opacity: 1)
    static let shadow = Color(.sRGB, red: 0.03, green: 0.01, blue: 0.08, opacity: 1)
    static let ice = Color(.sRGB, red: 0.55, green: 0.86, blue: 1, opacity: 1)
    static let warn = Color(.sRGB, red: 1, green: 0.42, blue: 0.40, opacity: 1)
    static let gold = Color(.sRGB, red: 0.96, green: 0.70, blue: 0.0, opacity: 1)
    static let boosterTints: [BrickOutTint] = [
        BrickOutTint(r: 0.30, g: 0.70, b: 1.00),
        BrickOutTint(r: 1.00, g: 0.56, b: 0.20),
        BrickOutTint(r: 0.36, g: 0.80, b: 0.40),
    ]
}

// MARK: - Board

/// A coloured opening in the frame. Sides: 0 top, 1 right, 2 bottom, 3 left.
struct BrickOutGate {
    var side: Int
    var start: Int
    var length: Int
    var color: Int
    /// Seconds since a brick last went through. Large when idle.
    var flash: Double = 9
}

struct BrickOutBrick {
    var col: Int
    var row: Int
    var w: Int
    var h: Int
    var color: Int
    /// When the deal placed it. The highest goes out first in the order the deal was built for.
    var order: Int
    /// Where it is drawn, in cells. Eases toward col/row.
    var x: Double
    var y: Double
    /// -1 while on the board, else the side it is leaving through.
    var exitSide = -1
    /// The gate it is leaving through until it reaches it, then -1.
    var gate = -1
    var exitAge = 0.0
    /// 0 to 1 as it pops in. Negative values wait before growing.
    var appear = 1.0
    /// Seconds since it was bumped against something, and which way.
    var bumpAge = 9.0
    var bumpSide = 0
    /// Seconds since it landed after a slide.
    var landAge = 9.0
    /// Held by a finger.
    var held = false

    init(col: Int, row: Int, w: Int, h: Int, color: Int, order: Int) {
        self.col = col
        self.row = row
        self.w = w
        self.h = h
        self.color = color
        self.order = order
        x = Double(col)
        y = Double(row)
    }

    var onBoard: Bool { exitSide < 0 }
}

enum BrickOutRules {
    static let cols = 6
    static let rows = 7

    static func step(_ side: Int) -> (dx: Int, dy: Int) {
        switch side {
        case 0: return (0, -1)
        case 1: return (1, 0)
        case 2: return (0, 1)
        default: return (-1, 0)
        }
    }

    static func overlaps(_ bricks: [BrickOutBrick], skip: Int, col: Int, row: Int, w: Int, h: Int) -> Bool {
        for k in bricks.indices where k != skip {
            let b = bricks[k]
            if !b.onBoard { continue }
            if col < b.col + b.w && b.col < col + w && row < b.row + b.h && b.row < row + h { return true }
        }
        return false
    }

    /// The gate on this side the brick fits through, if any.
    static func gate(for b: BrickOutBrick, side: Int, gates: [BrickOutGate]) -> Int? {
        for k in gates.indices {
            let g = gates[k]
            if g.side != side || g.color != b.color { continue }
            let lo = side % 2 == 0 ? b.col : b.row
            let span = side % 2 == 0 ? b.w : b.h
            if g.start <= lo && lo + span <= g.start + g.length { return k }
        }
        return nil
    }

    /// How far a brick slides toward a side, and whether it leaves through a gate at the end.
    static func travel(_ bricks: [BrickOutBrick], _ index: Int, side: Int, gates: [BrickOutGate]) -> (steps: Int, gate: Int?) {
        let b = bricks[index]
        let d = step(side)
        var steps = 0
        while true {
            let c = b.col + d.dx * (steps + 1)
            let r = b.row + d.dy * (steps + 1)
            if c < 0 || r < 0 || c + b.w > cols || r + b.h > rows {
                return (steps, gate(for: b, side: side, gates: gates))
            }
            if overlaps(bricks, skip: index, col: c, row: r, w: b.w, h: b.h) { return (steps, nil) }
            steps += 1
        }
    }
}

/// Deals a solvable board. Bricks are placed one by one, each with an open path to its own gate
/// past the bricks already placed, so taking them out newest first always works.
enum BrickOutDeal {
    static func gates(level: Int, rng: inout BrickOutRandom) -> [BrickOutGate] {
        let colorCount = Swift.min(6, 2 + level)
        var palette = Array(0..<BrickOutInk.tints.count)
        var last = palette.count - 1
        while last > 0 {
            palette.swapAt(last, rng.int(0...last))
            last -= 1
        }
        let perColor = colorCount <= 4 ? 2 : 1
        var gates: [BrickOutGate] = []
        for c in 0..<colorCount {
            var placed = 0
            var tries = 0
            while placed < perColor && tries < 60 {
                tries += 1
                let side = rng.int(0...3)
                let span = side % 2 == 0 ? BrickOutRules.cols : BrickOutRules.rows
                let length = rng.int(2...3)
                let start = rng.int(0...(span - length))
                var clash = false
                for g in gates where g.side == side {
                    if start < g.start + g.length + 1 && g.start < start + length + 1 { clash = true }
                    if g.color == palette[c] { clash = true }
                }
                if clash { continue }
                gates.append(BrickOutGate(side: side, start: start, length: length, color: palette[c]))
                placed += 1
            }
        }
        return gates
    }

    static func bricks(level: Int, count: Int, gates: [BrickOutGate], rng: inout BrickOutRandom) -> [BrickOutBrick] {
        var bricks: [BrickOutBrick] = []
        bricks.reserveCapacity(count)
        if gates.isEmpty { return bricks }
        var cells = 0
        var tries = 0
        while bricks.count < count && tries < 900 && cells < 36 {
            tries += 1
            let g = gates[rng.int(0...(gates.count - 1))]
            let across = rng.int(1...Swift.min(2, g.length))
            let roll = rng.next()
            let along = roll < 0.18 ? 1 : (roll < 0.68 ? 2 : 3)
            if across * along == 1 && rng.next() < 0.6 { continue }
            var b: BrickOutBrick
            if g.side % 2 == 0 {
                let col = rng.int(g.start...(g.start + g.length - across))
                let row = rng.int(0...(BrickOutRules.rows - along))
                b = BrickOutBrick(col: col, row: row, w: across, h: along, color: g.color, order: bricks.count)
            } else {
                let row = rng.int(g.start...(g.start + g.length - across))
                let col = rng.int(0...(BrickOutRules.cols - along))
                b = BrickOutBrick(col: col, row: row, w: along, h: across, color: g.color, order: bricks.count)
            }
            if BrickOutRules.overlaps(bricks, skip: -1, col: b.col, row: b.row, w: b.w, h: b.h) { continue }
            bricks.append(b)
            if BrickOutRules.travel(bricks, bricks.count - 1, side: g.side, gates: gates).gate == nil {
                bricks.removeLast()
                continue
            }
            cells += b.w * b.h
        }
        return bricks
    }

    static func count(level: Int) -> Int { Swift.min(15, 5 + 2 * level) }
}

// MARK: - Layout

struct BrickOutLayout {
    let W: Double
    let H: Double
    let u: Double
    let cell: Double
    let frame: Double
    let gridX: Double
    let gridY: Double
    let scoreY: Double
    let timerY: Double
    let chipsY: Double
    let boosterY: Double
    let boosterSize: Double

    init(size: CGSize) {
        W = Double(size.width)
        H = Double(size.height)
        u = BrickOutMath.clamp(W / 402, 0.75, 1.35)
        frame = 14 * u
        scoreY = Double(GameLayout.statusBarHeight) + 24
        timerY = Double(GameLayout.topBand) + 20 * u
        chipsY = timerY + 36 * u
        boosterSize = 60 * u
        boosterY = H - Double(GameLayout.bottomInset) - boosterSize * 0.5 - 16 * u
        let top = chipsY + 24 * u
        let bottom = boosterY - boosterSize * 0.5 - 30 * u
        let byWidth = (W - 40 * u - 2 * frame) / Double(BrickOutRules.cols)
        let byHeight = (bottom - top - 2 * frame) / Double(BrickOutRules.rows)
        cell = Swift.max(18, Swift.min(byWidth, byHeight))
        let boardW = cell * Double(BrickOutRules.cols)
        let boardH = cell * Double(BrickOutRules.rows)
        gridX = (W - boardW) * 0.5
        gridY = top + frame + Swift.max(0, (bottom - top - 2 * frame - boardH) * 0.42)
    }

    var boardW: Double { cell * Double(BrickOutRules.cols) }
    var boardH: Double { cell * Double(BrickOutRules.rows) }
    var gridRect: CGRect { CGRect(x: gridX, y: gridY, width: boardW, height: boardH) }

    /// The cell under a point, or nil off the board.
    func cell(at p: CGPoint) -> (col: Int, row: Int)? {
        let c = Int(floor((Double(p.x) - gridX) / cell))
        let r = Int(floor((Double(p.y) - gridY) / cell))
        if c < 0 || r < 0 || c >= BrickOutRules.cols || r >= BrickOutRules.rows { return nil }
        return (c, r)
    }

    func boosterCenter(_ k: Int) -> CGPoint {
        CGPoint(x: W * 0.5 + Double(k - 1) * 92 * u, y: boosterY)
    }

    /// The middle of a gate on the frame, and the outward direction.
    func gateCenter(_ g: BrickOutGate) -> (x: Double, y: Double, dx: Double, dy: Double) {
        let mid = Double(g.start) + Double(g.length) * 0.5
        switch g.side {
        case 0: return (gridX + mid * cell, gridY - frame * 0.5, 0, -1)
        case 1: return (gridX + boardW + frame * 0.5, gridY + mid * cell, 1, 0)
        case 2: return (gridX + mid * cell, gridY + boardH + frame * 0.5, 0, 1)
        default: return (gridX - frame * 0.5, gridY + mid * cell, -1, 0)
        }
    }
}

// MARK: - Short-lived bits

/// A brick crumb or a star. Kept in a fixed pool.
struct BrickOutSpark {
    var x = 0.0
    var y = 0.0
    var vx = 0.0
    var vy = 0.0
    var age = 9.0
    var life = 1.0
    var size = 4.0
    var spin = 0.0
    /// Palette index, or -1 for gold stars.
    var color = 0
    var alive: Bool { age < life }
}

struct BrickOutFloater {
    var x: Double
    var y: Double
    var text: String
    /// Palette index, or -1 for ice blue.
    var color: Int
    var age = 0.0
}

// MARK: - Painting

struct BrickOutFriendChip {
    var name: String
    var score: Int
}

struct BrickOutHUD {
    var score = 0
    var scorePop = 9.0
    var clock = 60.0
    var frozen = 0.0
    var level = 1
    var left = 0
    var boosters = [1, 1, 1]
    var armed = -1
    var friends: [BrickOutFriendChip] = []
    var ambient = 0.0
    var best = 0
}

struct BrickOutPainter {
    let L: BrickOutLayout
    var u: Double { L.u }

    init(size: CGSize) { L = BrickOutLayout(size: size) }

    // MARK: Scenery

    func drawBackground(_ ctx: inout GraphicsContext, ambient: Double) {
        let all = CGRect(x: 0, y: 0, width: L.W, height: L.H)
        ctx.fill(Path(all), with: .linearGradient(BrickOutInk.background, startPoint: .zero, endPoint: CGPoint(x: 0, y: L.H)))
        let cx = L.W * 0.5 + sin(ambient * 0.4) * 30 * u
        let cy = L.gridY + L.boardH * 0.45
        let r = L.W * 0.95
        ctx.fill(Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r)),
                 with: .radialGradient(BrickOutInk.glow, center: CGPoint(x: cx, y: cy), startRadius: 0, endRadius: r))
        let step = 58 * u
        let s = 9 * u
        var row = 0
        var y = step * 0.6
        while y < L.H {
            var x = row % 2 == 0 ? step * 0.5 : step
            while x < L.W {
                ctx.fill(Path(ellipseIn: CGRect(x: x - s, y: y - s, width: 2 * s, height: 2 * s)), with: .color(.white.opacity(0.035)))
                x += step
            }
            y += step
            row += 1
        }
    }

    func drawBoard(_ ctx: inout GraphicsContext, gates: [BrickOutGate], ambient: Double) {
        let g = L.gridRect
        let f = L.frame
        let outer = g.insetBy(dx: -f, dy: -f)
        let corner = 22 * u
        ctx.fill(Path(roundedRect: outer.offsetBy(dx: 0, dy: 12 * u), cornerRadius: corner), with: .color(BrickOutInk.shadow.opacity(0.45)))
        ctx.fill(Path(roundedRect: outer.offsetBy(dx: 0, dy: 6 * u), cornerRadius: corner), with: .color(BrickOutInk.frameLip))
        ctx.fill(Path(roundedRect: outer, cornerRadius: corner), with: .color(BrickOutInk.frame))
        ctx.stroke(Path(roundedRect: outer.insetBy(dx: 1.5 * u, dy: 1.5 * u), cornerRadius: corner - u),
                   with: .color(BrickOutInk.frameHi.opacity(0.55)), lineWidth: 2 * u)
        ctx.fill(Path(roundedRect: g.insetBy(dx: -2 * u, dy: -2 * u), cornerRadius: 10 * u), with: .color(BrickOutInk.well))
        let inset = 3 * u
        let side = L.cell - 2 * inset
        for r in 0..<BrickOutRules.rows {
            for c in 0..<BrickOutRules.cols {
                let rect = CGRect(x: L.gridX + Double(c) * L.cell + inset, y: L.gridY + Double(r) * L.cell + inset,
                                  width: side, height: side)
                ctx.fill(Path(roundedRect: rect, cornerRadius: 6 * u), with: .color(BrickOutInk.wellCell))
            }
        }
        for gate in gates { drawGate(&ctx, gate, ambient: ambient) }
    }

    func gateRect(_ gate: BrickOutGate) -> CGRect {
        let f = L.frame
        let pad = 3 * u
        let thick = f + 5 * u
        let a = Double(gate.start) * L.cell + pad
        let len = Double(gate.length) * L.cell - 2 * pad
        switch gate.side {
        case 0: return CGRect(x: L.gridX + a, y: L.gridY - f - 3 * u, width: len, height: thick)
        case 1: return CGRect(x: L.gridX + L.boardW - 2 * u, y: L.gridY + a, width: thick, height: len)
        case 2: return CGRect(x: L.gridX + a, y: L.gridY + L.boardH - 2 * u, width: len, height: thick)
        default: return CGRect(x: L.gridX - f - 3 * u, y: L.gridY + a, width: thick, height: len)
        }
    }

    func drawGate(_ ctx: inout GraphicsContext, _ gate: BrickOutGate, ambient: Double) {
        let flash = Swift.max(0, 1 - gate.flash / 0.45)
        let grow = 3 * u * flash
        let rect = gateRect(gate).insetBy(dx: -grow, dy: -grow)
        let radius = 6 * u
        ctx.fill(Path(roundedRect: rect.offsetBy(dx: 0, dy: 3 * u), cornerRadius: radius), with: .color(BrickOutInk.gateDark[gate.color]))
        ctx.fill(Path(roundedRect: rect, cornerRadius: radius), with: .color(BrickOutInk.face[gate.color]))
        if flash > 0 {
            ctx.fill(Path(roundedRect: rect, cornerRadius: radius), with: .color(.white.opacity(0.55 * flash)))
        }
        let d = BrickOutRules.step(gate.side)
        let fx = Double(d.dx)
        let fy = Double(d.dy)
        let drift = (sin(ambient * 4 + Double(gate.start)) * 0.5 + 0.5) * 1.6 * u
        let s = Double(Swift.min(rect.width, rect.height)) * 0.26
        for k in 0..<gate.length {
            let along = (Double(k) + 0.5) / Double(gate.length)
            let horizontal = gate.side % 2 == 0
            let cx: Double = horizontal ? Double(rect.minX) + along * Double(rect.width) : Double(rect.midX)
            let cy: Double = horizontal ? Double(rect.midY) : Double(rect.minY) + along * Double(rect.height)
            let px = cx + fx * drift
            let py = cy + fy * drift
            var p = Path()
            p.move(to: CGPoint(x: px + fx * s, y: py + fy * s))
            p.addLine(to: CGPoint(x: px - fx * s * 0.6 - fy * s, y: py - fy * s * 0.6 - fx * s))
            p.addLine(to: CGPoint(x: px - fx * s * 0.6 + fy * s, y: py - fy * s * 0.6 + fx * s))
            p.closeSubpath()
            ctx.fill(p, with: .color(.white.opacity(0.9)))
        }
    }

    // MARK: Bricks

    func brickRect(_ b: BrickOutBrick) -> CGRect {
        let inset = 2.2 * u
        return CGRect(x: L.gridX + b.x * L.cell + inset, y: L.gridY + b.y * L.cell + inset,
                      width: Double(b.w) * L.cell - 2 * inset, height: Double(b.h) * L.cell - 2 * inset)
    }

    func drawBricks(_ ctx: inout GraphicsContext, _ bricks: [BrickOutBrick], hint: Int, ambient: Double) {
        var leaving = false
        for k in bricks.indices {
            if bricks[k].onBoard {
                drawBrick(&ctx, bricks[k], glow: k == hint ? 0.5 + 0.5 * sin(ambient * 6) : 0)
            } else if bricks[k].appear > 0 {
                leaving = true
            }
        }
        if !leaving { return }
        let f = L.frame
        let clip = L.gridRect.insetBy(dx: -f * 0.6, dy: -f * 0.6)
        ctx.drawLayer { layer in
            layer.clip(to: Path(roundedRect: clip, cornerRadius: 10 * u))
            for b in bricks where !b.onBoard {
                drawBrick(&layer, b, glow: 0)
            }
        }
    }

    func drawBrick(_ ctx: inout GraphicsContext, _ b: BrickOutBrick, glow: Double) {
        if b.appear <= 0 { return }
        var rect = brickRect(b)
        let appear = BrickOutMath.easeOutBack(b.appear)
        if b.bumpAge < 0.3 {
            let d = BrickOutRules.step(b.bumpSide)
            let shake = sin(b.bumpAge * 55) * (1 - b.bumpAge / 0.3) * 4 * u
            rect = rect.offsetBy(dx: Double(d.dx) * shake, dy: Double(d.dy) * shake)
        }
        var scale = appear
        if b.landAge < 0.2 { scale *= 1 + 0.05 * sin(b.landAge / 0.2 * Double.pi) }
        if b.held { scale *= 1.05 }
        if b.exitSide >= 0 { scale *= 1 - 0.25 * BrickOutMath.clamp(b.exitAge / 0.35) }
        if abs(scale - 1) > 0.001 {
            let w = Double(rect.width) * scale
            let h = Double(rect.height) * scale
            rect = CGRect(x: Double(rect.midX) - w * 0.5, y: Double(rect.midY) - h * 0.5, width: w, height: h)
        }
        let depth = Swift.min(6 * u, Double(rect.height) * 0.12)
        let radius = Swift.min(9 * u, Double(Swift.min(rect.width, rect.height)) * 0.22)
        let c = b.color

        if b.held {
            ctx.fill(Path(roundedRect: rect.offsetBy(dx: 0, dy: 7 * u), cornerRadius: radius), with: .color(BrickOutInk.shadow.opacity(0.4)))
        }
        ctx.fill(Path(roundedRect: rect, cornerRadius: radius), with: .color(BrickOutInk.side[c]))
        let face = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height - depth)
        ctx.fill(Path(roundedRect: face, cornerRadius: radius), with: .color(BrickOutInk.face[c]))
        let shine = CGRect(x: Double(face.minX) + radius * 0.7, y: Double(face.minY) + 2.5 * u,
                           width: Double(face.width) - radius * 1.4, height: 2.6 * u)
        ctx.fill(Path(roundedRect: shine, cornerRadius: 1.3 * u), with: .color(.white.opacity(0.32)))

        let studR = L.cell * 0.17 * scale
        let hr = studR * 0.38
        let cw = Double(face.width) / Double(b.w)
        let ch = Double(face.height) / Double(b.h)
        for j in 0..<b.h {
            for i in 0..<b.w {
                let x = Double(face.minX) + (Double(i) + 0.5) * cw
                let y = Double(face.minY) + (Double(j) + 0.5) * ch
                let disc = CGRect(x: x - studR, y: y - studR, width: 2 * studR, height: 2 * studR)
                ctx.fill(Path(ellipseIn: disc.offsetBy(dx: 0, dy: 2.4 * u)), with: .color(BrickOutInk.studShade[c]))
                ctx.fill(Path(ellipseIn: disc), with: .color(BrickOutInk.stud[c]))
                let glint = CGRect(x: x - studR * 0.45 - hr, y: y - studR * 0.45 - hr, width: 2 * hr, height: 2 * hr)
                ctx.fill(Path(ellipseIn: glint), with: .color(.white.opacity(0.5)))
            }
        }
        if b.held || glow > 0 {
            let a = b.held ? 0.9 : 0.35 + 0.5 * glow
            ctx.stroke(Path(roundedRect: rect.insetBy(dx: -1.5 * u, dy: -1.5 * u), cornerRadius: radius + 1.5 * u),
                       with: .color(.white.opacity(a)), lineWidth: 2.5 * u)
        }
    }

    // MARK: Juice

    func drawSparks(_ ctx: inout GraphicsContext, _ sparks: [BrickOutSpark]) {
        for s in sparks where s.alive {
            let k = s.age / s.life
            let alpha = 1 - BrickOutMath.smooth(0.55, 1, k)
            let size = s.size * (1 - 0.4 * k)
            if s.color < 0 {
                drawStar(&ctx, x: s.x, y: s.y, r: size, spin: s.spin + s.age * 3, color: BrickOutInk.gold.opacity(alpha))
            } else {
                let rect = CGRect(x: s.x - size * 0.5, y: s.y - size * 0.5, width: size, height: size)
                ctx.fill(Path(roundedRect: rect, cornerRadius: size * 0.25), with: .color(BrickOutInk.face[s.color].opacity(alpha)))
            }
        }
    }

    func drawStar(_ ctx: inout GraphicsContext, x: Double, y: Double, r: Double, spin: Double, color: Color) {
        var p = Path()
        for k in 0..<10 {
            let a = spin + Double(k) * Double.pi / 5 - Double.pi / 2
            let rr = k % 2 == 0 ? r : r * 0.45
            let pt = CGPoint(x: x + cos(a) * rr, y: y + sin(a) * rr)
            if k == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        ctx.fill(p, with: .color(color))
    }

    func drawFloaters(_ ctx: inout GraphicsContext, _ floaters: [BrickOutFloater]) {
        for f in floaters {
            let k = f.age / 0.9
            if k >= 1 { continue }
            let alpha = 1 - BrickOutMath.smooth(0.55, 1, k)
            let pop = 0.7 + 0.3 * BrickOutMath.easeOutBack(Swift.min(1, f.age / 0.14))
            let y = f.y - 46 * u * BrickOutMath.easeOut(k)
            let text = Text(f.text).font(.system(size: 22 * u * pop, weight: .black, design: .rounded))
            let tint: Color = f.color < 0 ? BrickOutInk.ice : BrickOutInk.stud[f.color]
            ctx.draw(text.foregroundColor(BrickOutInk.shadow.opacity(0.6 * alpha)), at: CGPoint(x: f.x, y: y + 2 * u))
            ctx.draw(text.foregroundColor(Color.white.opacity(alpha)), at: CGPoint(x: f.x, y: y))
            ctx.draw(text.foregroundColor(tint.opacity(0.55 * alpha)), at: CGPoint(x: f.x, y: y))
        }
    }

    func drawPraise(_ ctx: inout GraphicsContext, _ words: String, age: Double) {
        let length = 1.0
        if age >= length { return }
        let pop = BrickOutMath.easeOutBack(age / 0.22)
        let alpha = 1 - BrickOutMath.smooth(length - 0.3, length, age)
        let size = 46 * u * (0.6 + 0.4 * pop)
        let y = L.gridY + L.boardH * 0.5 - 10 * u * BrickOutMath.easeOut(age / length)
        let text = Text(words).font(.system(size: size, weight: .black, design: .rounded))
        let x = L.W * 0.5
        ctx.draw(text.foregroundColor(BrickOutInk.shadow.opacity(0.65 * alpha)), at: CGPoint(x: x, y: y + 4 * u))
        ctx.draw(text.foregroundColor(Color.white.opacity(alpha)), at: CGPoint(x: x, y: y))
    }

    // MARK: HUD

    func drawHUD(_ ctx: inout GraphicsContext, _ hud: BrickOutHUD) {
        let pop = Swift.max(0, 1 - hud.scorePop / 0.22)
        let size = 46 * u * (1 + 0.16 * pop)
        let score = Text("\(hud.score)").font(.system(size: size, weight: .black, design: .rounded)).monospacedDigit()
        let x = L.W * 0.5
        ctx.draw(score.foregroundColor(BrickOutInk.shadow.opacity(0.55)), at: CGPoint(x: x, y: L.scoreY + 3 * u))
        ctx.draw(score.foregroundColor(.white), at: CGPoint(x: x, y: L.scoreY))

        let pillW = 104 * u
        let pillH = 34 * u
        let pill = CGRect(x: x - pillW * 0.5, y: L.timerY - pillH * 0.5, width: pillW, height: pillH)
        let frozen = hud.frozen > 0
        let urgent = !frozen && hud.clock < 10
        let beat = urgent ? 0.5 + 0.5 * sin(hud.ambient * 9) : 0
        let pillFill: Color = frozen ? BrickOutInk.ice.opacity(0.32) : BrickOutInk.shadow.opacity(0.5)
        let pillEdge: Color = urgent ? BrickOutInk.warn.opacity(0.5 + 0.5 * beat) : .white.opacity(0.14)
        ctx.fill(Path(roundedRect: pill, cornerRadius: pillH * 0.5), with: .color(pillFill))
        ctx.stroke(Path(roundedRect: pill, cornerRadius: pillH * 0.5), with: .color(pillEdge), lineWidth: 1.5 * u)
        let secs = Int(ceil(Swift.max(0, hud.clock)))
        let clockText = String(format: "%d:%02d", secs / 60, secs % 60)
        let ink: Color = frozen ? BrickOutInk.ice : (urgent ? BrickOutInk.warn : .white)
        let iconX = Double(pill.minX) + 20 * u
        let r = 8 * u
        ctx.stroke(Path(ellipseIn: CGRect(x: iconX - r, y: L.timerY - r, width: 2 * r, height: 2 * r)), with: .color(ink), lineWidth: 2 * u)
        var hands = Path()
        hands.move(to: CGPoint(x: iconX, y: L.timerY - r * 0.6))
        hands.addLine(to: CGPoint(x: iconX, y: L.timerY))
        hands.addLine(to: CGPoint(x: iconX + r * 0.5, y: L.timerY + r * 0.2))
        ctx.stroke(hands, with: .color(ink), style: StrokeStyle(lineWidth: 1.8 * u, lineCap: .round, lineJoin: .round))
        let t = Text(clockText).font(.system(size: 20 * u * (1 + 0.08 * beat), weight: .heavy, design: .rounded)).monospacedDigit()
        ctx.draw(t.foregroundColor(ink), at: CGPoint(x: Double(pill.midX) + 10 * u, y: L.timerY))

        let labelFont = Font.system(size: 12 * u, weight: .heavy, design: .rounded)
        let boardText = Text("BOARD \(hud.level)").font(labelFont).kerning(0.8 * u)
        let leftText = Text("\(hud.left) LEFT").font(labelFont).kerning(0.8 * u)
        ctx.draw(boardText.foregroundColor(.white.opacity(0.7)), at: CGPoint(x: Double(pill.minX) - 12 * u, y: L.timerY), anchor: .trailing)
        ctx.draw(leftText.foregroundColor(.white.opacity(0.7)), at: CGPoint(x: Double(pill.maxX) + 12 * u, y: L.timerY), anchor: .leading)

        if hud.best > 0 {
            let best = Text("BEST \(Swift.max(hud.best, hud.score))").font(.system(size: 11 * u, weight: .heavy, design: .rounded)).kerning(1 * u)
            ctx.draw(best.foregroundColor(.white.opacity(0.5)), at: CGPoint(x: x, y: L.timerY + pillH * 0.5 + 10 * u))
        }
        if !hud.friends.isEmpty { drawFriends(&ctx, hud.friends, mine: hud.score) }
    }

    func drawFriends(_ ctx: inout GraphicsContext, _ friends: [BrickOutFriendChip], mine: Int) {
        let n = Double(friends.count)
        let gap = 8 * u
        let chipW = Swift.min(118 * u, (L.W - 32 * u) / n - gap)
        let chipH = 24 * u
        let total = n * chipW + (n - 1) * gap
        var x = (L.W - total) * 0.5
        let y = L.chipsY + 8 * u
        for k in friends.indices {
            let f = friends[k]
            let rect = CGRect(x: x, y: y - chipH * 0.5, width: chipW, height: chipH)
            ctx.fill(Path(roundedRect: rect, cornerRadius: chipH * 0.5), with: .color(BrickOutInk.shadow.opacity(0.42)))
            let dot = 4 * u
            let dx = Double(rect.minX) + 11 * u
            ctx.fill(Path(ellipseIn: CGRect(x: dx - dot, y: y - dot, width: 2 * dot, height: 2 * dot)),
                     with: .color(BrickOutInk.face[(k * 2 + 3) % BrickOutInk.face.count]))
            let name = Text(String(f.name.prefix(9))).font(.system(size: 11.5 * u, weight: .bold, design: .rounded))
            ctx.draw(name.foregroundColor(.white.opacity(0.75)), at: CGPoint(x: dx + 9 * u, y: y), anchor: .leading)
            let s = Text("\(f.score)").font(.system(size: 12 * u, weight: .heavy, design: .rounded)).monospacedDigit()
            let ink: Color = f.score > mine ? BrickOutInk.warn : .white
            ctx.draw(s.foregroundColor(ink), at: CGPoint(x: Double(rect.maxX) - 10 * u, y: y), anchor: .trailing)
            x += chipW + gap
        }
    }

    func drawBoosters(_ ctx: inout GraphicsContext, _ hud: BrickOutHUD) {
        for k in 0..<3 {
            let c = L.boosterCenter(k)
            let s = L.boosterSize
            let left = hud.boosters[k]
            let armed = hud.armed == k
            let tint = BrickOutInk.boosterTints[k]
            let lift = armed ? -4 * u : 0
            let rect = CGRect(x: Double(c.x) - s * 0.5, y: Double(c.y) - s * 0.5 + lift, width: s, height: s)
            let alpha = left > 0 || armed ? 1.0 : 0.35
            let corner = 16 * u
            ctx.fill(Path(roundedRect: rect.offsetBy(dx: 0, dy: 5 * u - lift), cornerRadius: corner), with: .color(tint.mix(.black, 0.45).color(alpha)))
            ctx.fill(Path(roundedRect: rect, cornerRadius: corner), with: .color(tint.color(alpha)))
            let shine = CGRect(x: Double(rect.minX) + 10 * u, y: Double(rect.minY) + 4 * u, width: s - 20 * u, height: 4 * u)
            ctx.fill(Path(roundedRect: shine, cornerRadius: 2 * u), with: .color(.white.opacity(0.3 * alpha)))
            if armed {
                let ring = 0.5 + 0.5 * sin(hud.ambient * 8)
                ctx.stroke(Path(roundedRect: rect.insetBy(dx: -4 * u, dy: -4 * u), cornerRadius: corner + 3 * u),
                           with: .color(.white.opacity(0.5 + 0.5 * ring)), lineWidth: 3 * u)
            }
            let icon = CGPoint(x: rect.midX, y: rect.midY)
            switch k {
            case 0: drawSnowflake(&ctx, icon, alpha: alpha)
            case 1: drawHammer(&ctx, icon, alpha: alpha)
            default: drawShuffle(&ctx, icon, alpha: alpha)
            }
            let br = 10 * u
            let badge = CGRect(x: Double(rect.maxX) - br * 1.4, y: Double(rect.maxY) - br * 1.4, width: 2 * br, height: 2 * br)
            ctx.fill(Path(ellipseIn: badge), with: .color(BrickOutInk.shadow.opacity(0.85)))
            let n = Text("\(left)").font(.system(size: 12 * u, weight: .heavy, design: .rounded))
            ctx.draw(n.foregroundColor(.white.opacity(alpha)), at: CGPoint(x: badge.midX, y: badge.midY))
        }
    }

    private func drawSnowflake(_ ctx: inout GraphicsContext, _ c: CGPoint, alpha: Double) {
        var p = Path()
        let r = 15 * u
        let ox = Double(c.x)
        let oy = Double(c.y)
        for k in 0..<3 {
            let a = Double(k) * Double.pi / 3 + Double.pi / 2
            let dx = cos(a) * r
            let dy = sin(a) * r
            p.move(to: CGPoint(x: ox - dx, y: oy - dy))
            p.addLine(to: CGPoint(x: ox + dx, y: oy + dy))
            for sgn in [-1.0, 1.0] {
                let ex = ox + sgn * dx * 0.62
                let ey = oy + sgn * dy * 0.62
                let b1 = a + (sgn > 0 ? 0 : Double.pi)
                p.move(to: CGPoint(x: ex + cos(b1 + 0.8) * r * 0.32, y: ey + sin(b1 + 0.8) * r * 0.32))
                p.addLine(to: CGPoint(x: ex, y: ey))
                p.addLine(to: CGPoint(x: ex + cos(b1 - 0.8) * r * 0.32, y: ey + sin(b1 - 0.8) * r * 0.32))
            }
        }
        ctx.stroke(p, with: .color(.white.opacity(alpha)), style: StrokeStyle(lineWidth: 3 * u, lineCap: .round, lineJoin: .round))
    }

    private func drawHammer(_ ctx: inout GraphicsContext, _ c: CGPoint, alpha: Double) {
        let ox = Double(c.x)
        let oy = Double(c.y)
        var handle = Path()
        handle.move(to: CGPoint(x: ox - 9 * u, y: oy + 13 * u))
        handle.addLine(to: CGPoint(x: ox + 3 * u, y: oy - 2 * u))
        ctx.stroke(handle, with: .color(.white.opacity(alpha)), style: StrokeStyle(lineWidth: 5 * u, lineCap: .round))
        let turn = CGAffineTransform(rotationAngle: -Double.pi / 4)
        let move = CGAffineTransform(translationX: ox + 5 * u, y: oy - 5 * u)
        let head = Path(roundedRect: CGRect(x: -12 * u, y: -6 * u, width: 24 * u, height: 12 * u), cornerRadius: 3 * u)
            .applying(turn.concatenating(move))
        ctx.fill(head, with: .color(.white.opacity(alpha)))
    }

    private func drawShuffle(_ ctx: inout GraphicsContext, _ c: CGPoint, alpha: Double) {
        let r = 12 * u
        let ox = Double(c.x)
        let oy = Double(c.y)
        var p = Path()
        p.addArc(center: c, radius: r, startAngle: .degrees(200), endAngle: .degrees(330), clockwise: false)
        p.move(to: CGPoint(x: ox + r * cos(Double.pi / 9), y: oy + r * sin(Double.pi / 9)))
        p.addArc(center: c, radius: r, startAngle: .degrees(20), endAngle: .degrees(150), clockwise: false)
        ctx.stroke(p, with: .color(.white.opacity(alpha)), style: StrokeStyle(lineWidth: 3.6 * u, lineCap: .round))
        for deg in [330.0, 150.0] {
            let rad = deg * Double.pi / 180
            let tx = ox + r * cos(rad)
            let ty = oy + r * sin(rad)
            let fx = -sin(rad)
            let fy = cos(rad)
            var head = Path()
            head.move(to: CGPoint(x: tx + fx * 7 * u, y: ty + fy * 7 * u))
            head.addLine(to: CGPoint(x: tx - fy * 5 * u, y: ty + fx * 5 * u))
            head.addLine(to: CGPoint(x: tx + fy * 5 * u, y: ty - fx * 5 * u))
            head.closeSubpath()
            ctx.fill(head, with: .color(.white.opacity(alpha)))
        }
    }

    /// One plain line below the board.
    func drawHint(_ ctx: inout GraphicsContext, _ words: String, pulse: Double) {
        let y = L.gridY + L.boardH + L.frame + 22 * u
        let text = Text(words).font(.system(size: 16 * u, weight: .heavy, design: .rounded))
        let a = 0.75 + 0.25 * pulse
        ctx.draw(text.foregroundColor(BrickOutInk.shadow.opacity(0.5 * a)), at: CGPoint(x: L.W * 0.5, y: y + 2 * u))
        ctx.draw(text.foregroundColor(.white.opacity(a)), at: CGPoint(x: L.W * 0.5, y: y))
    }

    /// Chevrons sliding from a brick toward the side it can leave through.
    func drawSwipeGuide(_ ctx: inout GraphicsContext, _ b: BrickOutBrick, side: Int, ambient: Double) {
        let rect = brickRect(b)
        let d = BrickOutRules.step(side)
        let fx = Double(d.dx)
        let fy = Double(d.dy)
        let t = (ambient * 1.2).truncatingRemainder(dividingBy: 1)
        let s = 9 * u
        for k in 0..<3 {
            let k2 = (t + Double(k) / 3).truncatingRemainder(dividingBy: 1)
            let dist = L.cell * (0.1 + 1.4 * k2)
            let px = Double(rect.midX) + fx * dist
            let py = Double(rect.midY) + fy * dist
            let alpha = sin(k2 * Double.pi) * 0.95
            var p = Path()
            p.move(to: CGPoint(x: px - fx * s - fy * s, y: py - fy * s - fx * s))
            p.addLine(to: CGPoint(x: px, y: py))
            p.addLine(to: CGPoint(x: px - fx * s + fy * s, y: py - fy * s + fx * s))
            ctx.stroke(p, with: .color(BrickOutInk.shadow.opacity(0.5 * alpha)), style: StrokeStyle(lineWidth: 7 * u, lineCap: .round, lineJoin: .round))
            ctx.stroke(p, with: .color(.white.opacity(alpha)), style: StrokeStyle(lineWidth: 4 * u, lineCap: .round, lineJoin: .round))
        }
    }
}

// MARK: - Cover

/// A scripted moment of a round: bricks go out newest first, one every quarter of the phase.
enum BrickOutCover {
    static let deal: (gates: [BrickOutGate], bricks: [BrickOutBrick]) = {
        var rng = BrickOutRandom(seed: 20261115, salt: BrickOutRandom.deal)
        let gates = BrickOutDeal.gates(level: 3, rng: &rng)
        let bricks = BrickOutDeal.bricks(level: 3, count: 13, gates: gates, rng: &rng)
        return (gates, bricks)
    }()

    /// Bricks in the order they go out.
    static let exitOrder: [Int] = deal.bricks.indices.sorted { deal.bricks[$0].order > deal.bricks[$1].order }

    static func paint(_ ctx: inout GraphicsContext, size: CGSize, phase: Double, showHUD: Bool) {
        let painter = BrickOutPainter(size: size)
        let L = painter.L
        var gates = deal.gates
        var bricks = deal.bricks
        let p = BrickOutMath.clamp(phase)
        let beats = 4.0
        let beat = Swift.min(beats - 1, floor(p * beats))
        let local = p * beats - beat
        let gone = Swift.min(Int(beat), exitOrder.count)
        for k in 0..<gone {
            bricks[exitOrder[k]].exitSide = 9
            bricks[exitOrder[k]].appear = 0
        }

        var sparks: [BrickOutSpark] = []
        var floaters: [BrickOutFloater] = []
        if gone < exitOrder.count {
            let i = exitOrder[gone]
            var side = 0
            var gateIndex = 0
            for s in 0..<4 {
                if let g = BrickOutRules.travel(bricks, i, side: s, gates: gates).gate {
                    side = s
                    gateIndex = g
                    break
                }
            }
            let b = bricks[i]
            let d = BrickOutRules.step(side)
            let along = side % 2 == 0 ? Double(b.h) : Double(b.w)
            let toEdge: Double
            switch side {
            case 0: toEdge = Double(b.row)
            case 1: toEdge = Double(BrickOutRules.cols - b.col - b.w)
            case 2: toEdge = Double(BrickOutRules.rows - b.row - b.h)
            default: toEdge = Double(b.col)
            }
            let move = BrickOutMath.easeOut(BrickOutMath.clamp((local - 0.12) / 0.4)) * (toEdge + along + 0.4)
            bricks[i].x += Double(d.dx) * move
            bricks[i].y += Double(d.dy) * move
            bricks[i].held = local < 0.12
            if local > 0.35 {
                bricks[i].exitSide = side
                bricks[i].exitAge = (local - 0.35) * 1.2
                gates[gateIndex].flash = (local - 0.35) * 1.0
                let gc = L.gateCenter(gates[gateIndex])
                var rng = BrickOutRandom(seed: UInt64(gone + 3), salt: BrickOutRandom.sparks)
                let age = (local - 0.35) * 1.3
                for _ in 0..<18 {
                    let a = atan2(gc.dy, gc.dx) + rng.range(-1.2, 1.2)
                    let speed = rng.range(120, 320) * L.u
                    var s = BrickOutSpark()
                    s.x = gc.x + cos(a) * speed * age
                    s.y = gc.y + sin(a) * speed * age + 300 * L.u * age * age
                    s.age = age
                    s.life = rng.range(0.55, 0.9)
                    s.size = rng.range(5, 10) * L.u
                    s.color = b.color
                    sparks.append(s)
                }
                floaters.append(BrickOutFloater(x: gc.x - gc.dx * 44 * L.u, y: gc.y - gc.dy * 44 * L.u,
                                                text: "+\(10 * b.w * b.h + 10)", color: b.color, age: age * 0.8))
            }
        }

        let ambient = p * 6
        painter.drawBackground(&ctx, ambient: ambient)
        painter.drawBoard(&ctx, gates: gates, ambient: ambient)
        painter.drawBricks(&ctx, bricks, hint: -1, ambient: ambient)
        painter.drawSparks(&ctx, sparks)
        painter.drawFloaters(&ctx, floaters)
        if gone >= 1, local > 0.35 { painter.drawPraise(&ctx, gone >= 2 ? "Great" : "Nice", age: (local - 0.35) * 1.1) }
        guard showHUD else { return }
        var hud = BrickOutHUD()
        hud.score = 180 + gone * 40
        hud.clock = 48 - p * 14
        hud.level = 3
        hud.left = bricks.filter { $0.onBoard }.count
        hud.boosters = [1, 0, 1]
        hud.friends = [BrickOutFriendChip(name: "kaz", score: 220), BrickOutFriendChip(name: "devon.plays", score: 150)]
        hud.ambient = ambient
        painter.drawHUD(&ctx, hud)
        painter.drawBoosters(&ctx, hud)
    }
}
