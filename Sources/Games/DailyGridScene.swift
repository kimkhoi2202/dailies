import SwiftUI

// Daily Grid: one crown in every row, column and colour, and no two crowns touching.
//
// The whole screen is painted into one Canvas by DailyGridPainter from a DailyGridFrame, a plain
// description of one moment. The clip in the Videos feed builds a frame from a phase (0...1) and
// a fixed script; the playable game builds one from its live model. No assets, any frame size.

public struct DailyGridScene: View {
    public var phase: Double
    public var showHUD: Bool

    public init(phase: Double, showHUD: Bool) {
        self.phase = phase
        self.showHUD = showHUD
    }

    public var body: some View {
        Canvas(opaque: true, colorMode: .nonLinear, rendersAsynchronously: false) { context, size in
            if size.width <= 8 || size.height <= 8 { return }
            let frame = DailyGridClip.frame(at: phase, showHUD: showHUD)
            DailyGridPainter(size: size).draw(&context, frame)
        }
    }
}

// MARK: - Numbers

enum DailyGridMath {
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

    /// The scale of something that just landed: a quick overshoot that settles at 1.
    static func pop(_ age: Double, length: Double = 0.22) -> Double {
        if age < 0 || age >= length { return 1 }
        let k = age / length
        return 1 + 0.3 * sin(k * .pi) * (1 - 0.45 * k)
    }
}

/// SplitMix64. The round and the scripted player use different salts so they never share a sequence.
struct DailyGridRandom {
    static let round: UInt64 = 0x2545F4914F6CDD1D
    static let pilot: UInt64 = 0xD1B54A32D192ED03
    static let scenery: UInt64 = 0x9E3779B97F4A7C15

    private var state: UInt64

    init(seed: UInt64, salt: UInt64 = DailyGridRandom.round) {
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
        if count <= 1 { return 0 }
        return Swift.min(count - 1, Int(next() * Double(count)))
    }

    mutating func int(_ bounds: ClosedRange<Int>) -> Int {
        bounds.lowerBound + int(bounds.count)
    }

    mutating func shuffle(_ items: inout [Int]) {
        var last = items.count - 1
        while last > 0 {
            items.swapAt(last, int(last + 1))
            last -= 1
        }
    }
}

// MARK: - Colour

struct DailyGridTint {
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

    static let white = DailyGridTint(1, 1, 1)

    func mix(_ other: DailyGridTint, _ k: Double) -> DailyGridTint {
        DailyGridTint(r + (other.r - r) * k, g + (other.g - g) * k, b + (other.b - b) * k)
    }

    func color(_ alpha: Double = 1) -> Color { Color(.sRGB, red: r, green: g, blue: b, opacity: alpha) }
}

enum DailyGridPalette {
    static let paper = DailyGridTint(hex: 0xECE8E1)
    static let card = DailyGridTint(hex: 0xF8F6F1)
    static let ink = DailyGridTint(hex: 0x151412)
    static let soft = DailyGridTint(hex: 0x6E6A63)
    static let cross = DailyGridTint(hex: 0x8A857C)
    static let red = DailyGridTint(hex: 0xE0553F)
    /// Peach, sky, mint, butter, lilac, rose: one for each colour region.
    static let regions: [DailyGridTint] = [0xF6C9B2, 0xBFD9F2, 0xC8E8C9, 0xF5E3A5, 0xD9CFF2, 0xF7C4D9]
        .map { DailyGridTint(hex: $0) }
}

// MARK: - The puzzle

/// What a square holds.
enum DailyGridMark: Int {
    case empty, cross, crown
}

/// A 6 x 6 board split into six colour regions, with its one solution.
struct DailyGridPuzzle {
    static let size = 6
    static let cells = 36

    /// The column of the crown in each row.
    let solution: [Int]
    /// The colour region of each square, row by row.
    let regions: [Int]

    /// The square that holds the crown of the given row.
    func solutionCell(row: Int) -> Int { row * DailyGridPuzzle.size + solution[row] }

    func isSolutionCell(_ cell: Int) -> Bool {
        solution[cell / DailyGridPuzzle.size] == cell % DailyGridPuzzle.size
    }

    /// Puzzles checked ahead of time to have exactly one solution. The round uses them when the
    /// generator fails to find one in its allotted tries, and the clip uses the first.
    static let stock: [DailyGridPuzzle] = [
        DailyGridPuzzle(solution: [0, 4, 1, 3, 5, 2], regions: [0, 0, 0, 0, 1, 1, 0, 2, 2, 0, 1, 1, 0, 2, 2, 0, 0, 4, 2, 2, 2, 3, 3, 4, 2, 2, 5, 3, 4, 4, 2, 2, 5, 3, 4, 4]),
        DailyGridPuzzle(solution: [4, 2, 5, 1, 3, 0], regions: [0, 0, 0, 0, 0, 2, 0, 1, 1, 0, 0, 2, 1, 1, 1, 4, 2, 2, 5, 3, 5, 4, 2, 2, 5, 3, 5, 4, 2, 2, 5, 5, 5, 2, 2, 2]),
        DailyGridPuzzle(solution: [2, 0, 3, 5, 1, 4], regions: [0, 0, 0, 0, 0, 3, 1, 0, 0, 0, 0, 3, 1, 1, 1, 2, 2, 3, 4, 4, 4, 5, 3, 3, 4, 4, 4, 5, 5, 5, 4, 4, 5, 5, 5, 5]),
        DailyGridPuzzle(solution: [3, 5, 2, 0, 4, 1], regions: [0, 0, 0, 0, 0, 1, 0, 0, 0, 1, 0, 1, 3, 2, 2, 1, 1, 1, 3, 3, 4, 4, 4, 1, 3, 5, 5, 5, 4, 1, 5, 5, 4, 4, 4, 4]),
        DailyGridPuzzle(solution: [5, 1, 4, 2, 0, 3], regions: [1, 1, 1, 1, 0, 0, 4, 1, 1, 1, 2, 0, 4, 4, 3, 2, 2, 0, 4, 4, 3, 3, 5, 5, 4, 4, 4, 3, 5, 5, 4, 4, 5, 5, 5, 5]),
        DailyGridPuzzle(solution: [2, 5, 3, 1, 4, 0], regions: [5, 0, 0, 0, 0, 1, 5, 5, 0, 0, 0, 1, 5, 3, 2, 2, 2, 1, 5, 3, 2, 2, 2, 1, 5, 3, 2, 2, 4, 4, 5, 5, 5, 2, 2, 2]),
        DailyGridPuzzle(solution: [2, 5, 3, 1, 4, 0], regions: [0, 0, 0, 1, 1, 1, 0, 2, 1, 1, 1, 1, 0, 2, 2, 2, 2, 1, 0, 3, 2, 2, 2, 1, 5, 3, 3, 4, 4, 4, 5, 3, 4, 4, 4, 4]),
        DailyGridPuzzle(solution: [3, 5, 2, 0, 4, 1], regions: [2, 2, 0, 0, 0, 1, 2, 2, 0, 0, 0, 1, 2, 2, 2, 1, 1, 1, 3, 3, 2, 4, 4, 4, 3, 5, 4, 4, 4, 4, 5, 5, 4, 4, 4, 4]),
    ]
}

// MARK: - One moment

/// A bit of confetti released when a board is solved. Its place at any age is worked out from
/// where it started and how fast it left, so nothing has to be stepped.
struct DailyGridSpark {
    /// Start, as a share of the board's width and height.
    var x: Double
    var y: Double
    /// Speed, in board widths per second.
    var vx: Double
    var vy: Double
    var size: Double
    /// A region colour, or -1 for ink.
    var tint: Int
    var spin: Double
}

/// Everything the painter needs for one frame.
struct DailyGridFrame {
    var showHUD = true
    var regions: [Int] = DailyGridPuzzle.stock[0].regions
    var marks: [DailyGridMark] = Array(repeating: .empty, count: DailyGridPuzzle.cells)
    var conflict: [Bool] = Array(repeating: false, count: DailyGridPuzzle.cells)
    /// The frame's clock, in seconds, which changedAt and pressedAt are read against.
    var clock = 10.0
    /// When each square last changed, on the clock, for the pop.
    var changedAt: [Double] = Array(repeating: -10, count: DailyGridPuzzle.cells)
    /// Seconds since this board came up.
    var boardAge = 10.0
    var timerText = "3:00"
    var timerUrgent = false
    var scoreText = "0 points"
    var gridText = "Grid 1"
    var lives = 3
    /// The one instruction, and how visible it is.
    var hintText = "Tap a square to start"
    var hintAlpha = 0.0
    var praise: String?
    var praiseAge = 0.0
    var floatText: String?
    var floatAge = 0.0
    /// Seconds since the board was solved. nil while it is not.
    var solvedAge: Double?
    var sparks: [DailyGridSpark] = []
    /// When each of the three keys was last pressed, on the clock.
    var pressedAt: [Double] = [-10, -10, -10]
    var endText: String?
    var endAge = 0.0
}

// MARK: - Layout

/// Where everything sits, for any frame size. Lengths scale with the stage (402 x 874); the top of
/// the screen keeps the room the app wants for its own controls.
struct DailyGridLayout {
    static let keys = ["UNDO", "HINT", "CLEAR"]

    let W: Double
    let H: Double
    let u: Double
    let titleY: Double
    let timerY: Double
    let infoY: Double
    let grid: CGRect
    let cell: Double
    let keyY: Double
    let keyW: Double
    let keyH: Double
    let keyGap: Double
    let rules: CGRect

    init(size: CGSize) {
        W = Double(size.width)
        H = Double(size.height)
        u = Swift.min(W / 402, H / 874)
        titleY = Double(GameLayout.statusBarHeight) + 22
        timerY = Swift.max(titleY + 46 * u, Double(GameLayout.topBand) + 30 * u)
        infoY = timerY + 40 * u
        let side = Swift.min(346 * u, W - 28 * u)
        grid = CGRect(x: (W - side) / 2, y: infoY + 24 * u, width: side, height: side)
        cell = side / Double(DailyGridPuzzle.size)
        keyH = 52 * u
        keyGap = 12 * u
        keyW = (side - 2 * keyGap) / 3
        keyY = grid.maxY + 30 * u
        let rulesTop = keyY + keyH + 22 * u
        let room = H - Double(GameLayout.bottomInset) - 8 - rulesTop
        rules = CGRect(x: grid.minX, y: rulesTop, width: side, height: Swift.max(40, Swift.min(100 * u, room)))
    }

    func cellRect(_ cell: Int) -> CGRect {
        let row = cell / DailyGridPuzzle.size
        let col = cell % DailyGridPuzzle.size
        return CGRect(x: grid.minX + Double(col) * self.cell, y: grid.minY + Double(row) * self.cell,
                      width: self.cell, height: self.cell)
    }

    func key(_ k: Int) -> CGRect {
        CGRect(x: grid.minX + Double(k) * (keyW + keyGap), y: keyY, width: keyW, height: keyH)
    }

    /// The square under a touch, with a little slack past the board's edge.
    func cell(at point: CGPoint) -> Int? {
        let slack = 6 * u
        let x = Double(point.x) - grid.minX
        let y = Double(point.y) - grid.minY
        if x < -slack || y < -slack || x > grid.width + slack || y > grid.height + slack { return nil }
        let col = Swift.max(0, Swift.min(DailyGridPuzzle.size - 1, Int(floor(x / cell))))
        let row = Swift.max(0, Swift.min(DailyGridPuzzle.size - 1, Int(floor(y / cell))))
        return row * DailyGridPuzzle.size + col
    }

    func key(at point: CGPoint) -> Int? {
        for k in 0..<3 where key(k).insetBy(dx: -4 * u, dy: -8 * u).contains(point) { return k }
        return nil
    }
}

// MARK: - Painter

struct DailyGridPainter {
    typealias M = DailyGridMath
    typealias P = DailyGridPalette

    let L: DailyGridLayout
    var u: Double { L.u }

    init(size: CGSize) {
        L = DailyGridLayout(size: size)
    }

    func draw(_ ctx: inout GraphicsContext, _ f: DailyGridFrame) {
        ctx.fill(Path(CGRect(x: 0, y: 0, width: L.W, height: L.H)), with: .color(P.paper.color()))
        if f.showHUD { drawHUD(&ctx, f) }
        drawBoard(&ctx, f)
        if f.showHUD {
            drawKeys(&ctx, f)
            drawRules(&ctx)
        }
        drawOverlays(&ctx, f)
    }

    // MARK: Top

    private func drawHUD(_ ctx: inout GraphicsContext, _ f: DailyGridFrame) {
        let title = Text("DAILY GRID").font(.system(size: 18 * u, weight: .heavy, design: .rounded)).kerning(1.4 * u)
        ctx.draw(title.foregroundColor(P.ink.color()), at: CGPoint(x: L.W / 2, y: L.titleY), anchor: .center)

        let timerTint: DailyGridTint = f.timerUrgent ? P.red : P.ink
        let timer = Text(f.timerText).font(.system(size: 38 * u, weight: .heavy, design: .rounded)).monospacedDigit()
        var scaled = ctx
        scaled.translateBy(x: L.W / 2, y: L.timerY)
        if f.timerUrgent {
            let beat = 1 + 0.05 * Swift.max(0, sin(f.boardAge * 2 * .pi))
            scaled.scaleBy(x: beat, y: beat)
        }
        scaled.draw(timer.foregroundColor(timerTint.color()), at: .zero, anchor: .center)

        let small = Font.system(size: 14.5 * u, weight: .bold, design: .rounded)
        ctx.draw(Text(f.scoreText).font(small).monospacedDigit().foregroundColor(P.soft.color()),
                 at: CGPoint(x: L.grid.minX + 2 * u, y: L.infoY), anchor: .leading)
        ctx.draw(Text(f.gridText).font(small).foregroundColor(P.soft.color()),
                 at: CGPoint(x: L.W / 2, y: L.infoY), anchor: .center)

        // Tries left, as little crowns. A spent one is only an outline.
        let step = 20 * u
        for k in 0..<3 {
            let x = L.grid.maxX - 9 * u - Double(2 - k) * step
            let crown = Self.crown(at: CGPoint(x: x, y: L.infoY), size: 13 * u)
            if k < f.lives {
                ctx.fill(crown, with: .color(P.ink.color()))
            } else {
                ctx.stroke(crown, with: .color(P.cross.color(0.8)), lineWidth: Swift.max(1, 1.2 * u))
            }
        }
    }

    // MARK: Board

    private func drawBoard(_ ctx: inout GraphicsContext, _ f: DailyGridFrame) {
        let n = DailyGridPuzzle.size
        let radius = 6 * u
        let shadow = L.grid.offsetBy(dx: 0, dy: 4 * u).insetBy(dx: -2 * u, dy: -2 * u)
        ctx.fill(Path(roundedRect: shadow, cornerRadius: radius + 2 * u), with: .color(P.ink.color(0.08)))
        ctx.fill(Path(roundedRect: L.grid.insetBy(dx: -2 * u, dy: -2 * u), cornerRadius: radius + 2 * u),
                 with: .color(P.card.color()))

        let arrive = M.easeOut(f.boardAge / 0.35)
        var board = ctx
        board.clip(to: Path(roundedRect: L.grid, cornerRadius: radius))

        for cell in 0..<DailyGridPuzzle.cells {
            let rect = L.cellRect(cell)
            let region = Swift.max(0, Swift.min(P.regions.count - 1, f.regions[cell]))
            var tint = P.card.mix(P.regions[region], arrive)
            if f.conflict[cell] { tint = tint.mix(P.red, 0.28) }
            if let age = f.solvedAge {
                // A wave of light runs from the top left corner to the bottom right.
                let d = Double(cell / n + cell % n) / 10
                let local = age * 2.4 - d
                if local > 0 && local < 1 { tint = tint.mix(DailyGridTint.white, 0.6 * sin(local * .pi)) }
            }
            board.fill(Path(rect), with: .color(tint.color()))
        }

        // Thin lines between squares, thick ones where the colour changes.
        var thin = Path()
        var thick = Path()
        for k in 1..<n {
            let x = L.grid.minX + Double(k) * L.cell
            thin.move(to: CGPoint(x: x, y: L.grid.minY))
            thin.addLine(to: CGPoint(x: x, y: L.grid.maxY))
            let y = L.grid.minY + Double(k) * L.cell
            thin.move(to: CGPoint(x: L.grid.minX, y: y))
            thin.addLine(to: CGPoint(x: L.grid.maxX, y: y))
        }
        for cell in 0..<DailyGridPuzzle.cells {
            let row = cell / n
            let col = cell % n
            let rect = L.cellRect(cell)
            if col < n - 1 && f.regions[cell] != f.regions[cell + 1] {
                thick.move(to: CGPoint(x: rect.maxX, y: rect.minY))
                thick.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            }
            if row < n - 1 && f.regions[cell] != f.regions[cell + n] {
                thick.move(to: CGPoint(x: rect.minX, y: rect.maxY))
                thick.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            }
        }
        board.stroke(thin, with: .color(P.ink.color(0.13 * arrive)), lineWidth: Swift.max(1, 1 * u))
        board.stroke(thick, with: .color(P.ink.color(0.9 * arrive)), style: StrokeStyle(lineWidth: 2.4 * u, lineCap: .square))

        // The marks.
        for cell in 0..<DailyGridPuzzle.cells where f.marks[cell] != .empty {
            let rect = L.cellRect(cell)
            let scale = M.pop(f.clock - f.changedAt[cell]) * (0.6 + 0.4 * arrive)
            var mark = board
            mark.translateBy(x: rect.midX, y: rect.midY)
            mark.scaleBy(x: scale, y: scale)
            if f.marks[cell] == .cross {
                let a = L.cell * 0.17
                var x = Path()
                x.move(to: CGPoint(x: -a, y: -a))
                x.addLine(to: CGPoint(x: a, y: a))
                x.move(to: CGPoint(x: a, y: -a))
                x.addLine(to: CGPoint(x: -a, y: a))
                mark.stroke(x, with: .color(P.cross.color()), style: StrokeStyle(lineWidth: 2.6 * u, lineCap: .round))
            } else {
                let crown = Self.crown(at: .zero, size: L.cell * 0.56)
                let tint: DailyGridTint = f.conflict[cell] ? P.red : P.ink
                mark.fill(crown, with: .color(tint.color()))
            }
        }

        if f.endText != nil {
            board.fill(Path(L.grid), with: .color(P.ink.color(0.1 * M.smooth(0, 0.3, f.endAge))))
        }

        ctx.stroke(Path(roundedRect: L.grid, cornerRadius: radius), with: .color(P.ink.color()), lineWidth: 3 * u)

        if let age = f.solvedAge { drawSparks(&ctx, f.sparks, age: age) }
    }

    private func drawSparks(_ ctx: inout GraphicsContext, _ sparks: [DailyGridSpark], age: Double) {
        let life = 1.3
        if age >= life { return }
        let side = L.grid.width
        for s in sparks {
            let t = age
            let x = L.grid.minX + (s.x + s.vx * t) * side
            let y = L.grid.minY + (s.y + s.vy * t + 0.9 * t * t) * side
            let alpha = 1 - M.smooth(life * 0.55, life, t)
            let r = s.size * u * (0.6 + 0.4 * M.easeOut(t / 0.2))
            var piece = ctx
            piece.translateBy(x: x, y: y)
            piece.rotate(by: Angle(radians: s.spin * t))
            let tint: DailyGridTint = s.tint < 0 ? P.ink : P.regions[s.tint % P.regions.count].mix(P.ink, 0.25)
            piece.fill(Path(roundedRect: CGRect(x: -r, y: -r * 0.6, width: 2 * r, height: 1.2 * r), cornerRadius: r * 0.3),
                       with: .color(tint.color(alpha)))
        }
    }

    // MARK: Keys and rules

    private func drawKeys(_ ctx: inout GraphicsContext, _ f: DailyGridFrame) {
        for k in 0..<3 {
            let rect = L.key(k)
            let press = f.clock - f.pressedAt[k]
            let scale = press < 0.16 ? 1 - 0.06 * sin(M.clamp(press / 0.16) * .pi) : 1
            var key = ctx
            key.translateBy(x: rect.midX, y: rect.midY)
            key.scaleBy(x: scale, y: scale)
            let local = CGRect(x: -rect.width / 2, y: -rect.height / 2, width: rect.width, height: rect.height)
            key.fill(Path(roundedRect: local.offsetBy(dx: 0, dy: 3 * u), cornerRadius: rect.height / 2), with: .color(P.ink.color(0.08)))
            key.fill(Path(roundedRect: local, cornerRadius: rect.height / 2), with: .color(P.card.color()))
            let label = Text(DailyGridLayout.keys[k]).font(.system(size: 14 * u, weight: .heavy, design: .rounded)).kerning(1.2 * u)
            key.draw(label.foregroundColor(P.ink.color()), at: .zero, anchor: .center)
        }
    }

    private func drawRules(_ ctx: inout GraphicsContext) {
        let rect = L.rules
        ctx.fill(Path(roundedRect: rect, cornerRadius: 18 * u), with: .color(P.card.color()))
        let lines = ["One crown in each row, column and colour.",
                     "Crowns never touch, not even diagonally.",
                     "Tap once for a cross, twice for a crown."]
        let size = Swift.min(13.5 * u, rect.height / 6.2)
        let gap = size * 1.5
        let top = rect.midY - gap
        for (k, line) in lines.enumerated() {
            let text = Text(line).font(.system(size: size, weight: .medium, design: .rounded))
            ctx.draw(text.foregroundColor(P.ink.color(0.82)), at: CGPoint(x: rect.midX, y: top + Double(k) * gap), anchor: .center)
        }
    }

    // MARK: Words over the board

    private func drawOverlays(_ ctx: inout GraphicsContext, _ f: DailyGridFrame) {
        let center = CGPoint(x: L.grid.midX, y: L.grid.midY)

        if f.hintAlpha > 0.01 {
            drawPill(&ctx, f.hintText, at: center, alpha: f.hintAlpha, scale: 1, size: 15 * u)
        }

        if let words = f.praise {
            let age = f.praiseAge
            let alpha = M.easeOut(age / 0.12) * (1 - M.smooth(1.0, 1.4, age))
            if alpha > 0.01 {
                let scale = M.pop(age, length: 0.3)
                var pop = ctx
                pop.translateBy(x: center.x, y: center.y - 10 * u)
                pop.scaleBy(x: scale, y: scale)
                let text = Text(words).font(.system(size: 44 * u, weight: .heavy, design: .rounded)).kerning(1 * u)
                pop.draw(text.foregroundColor(P.card.color(alpha)), at: CGPoint(x: 0, y: 3 * u), anchor: .center)
                pop.draw(text.foregroundColor(P.ink.color(alpha)), at: .zero, anchor: .center)
            }
        }

        if let words = f.floatText {
            let age = f.floatAge
            let alpha = M.easeOut(age / 0.1) * (1 - M.smooth(0.8, 1.3, age))
            if alpha > 0.01 {
                let rise = 48 * u * M.easeOut(age / 1.3)
                let text = Text(words).font(.system(size: 22 * u, weight: .heavy, design: .rounded)).monospacedDigit()
                ctx.draw(text.foregroundColor(P.ink.color(alpha)), at: CGPoint(x: center.x, y: center.y + 44 * u - rise), anchor: .center)
            }
        }

        if let words = f.endText {
            let alpha = M.easeOut(f.endAge / 0.15)
            drawPill(&ctx, words, at: center, alpha: alpha, scale: M.pop(f.endAge, length: 0.3), size: 22 * u)
        }
    }

    private func drawPill(_ ctx: inout GraphicsContext, _ words: String, at point: CGPoint, alpha: Double, scale: Double, size: Double) {
        let text = Text(words).font(.system(size: size, weight: .bold, design: .rounded))
        let resolved = ctx.resolve(text.foregroundColor(P.ink.color(alpha)))
        let measured = resolved.measure(in: CGSize(width: L.W, height: L.H))
        let w = Double(measured.width) + 36 * u
        let h = Double(measured.height) + 20 * u
        var pill = ctx
        pill.translateBy(x: point.x, y: point.y)
        pill.scaleBy(x: scale, y: scale)
        let rect = CGRect(x: -w / 2, y: -h / 2, width: w, height: h)
        pill.fill(Path(roundedRect: rect.offsetBy(dx: 0, dy: 3 * u), cornerRadius: h / 2), with: .color(P.ink.color(0.12 * alpha)))
        pill.fill(Path(roundedRect: rect, cornerRadius: h / 2), with: .color(P.card.color(0.97 * alpha)))
        pill.draw(resolved, at: .zero, anchor: .center)
    }

    // MARK: Shapes

    /// A crown with three points and a base, centred on the point.
    static func crown(at c: CGPoint, size s: Double) -> Path {
        let w = s * 0.5
        var p = Path()
        p.move(to: CGPoint(x: c.x - w, y: c.y + s * 0.2))
        p.addLine(to: CGPoint(x: c.x - w, y: c.y - s * 0.16))
        p.addLine(to: CGPoint(x: c.x - w * 0.5, y: c.y + s * 0.02))
        p.addLine(to: CGPoint(x: c.x, y: c.y - s * 0.42))
        p.addLine(to: CGPoint(x: c.x + w * 0.5, y: c.y + s * 0.02))
        p.addLine(to: CGPoint(x: c.x + w, y: c.y - s * 0.16))
        p.addLine(to: CGPoint(x: c.x + w, y: c.y + s * 0.2))
        p.closeSubpath()
        p.addRoundedRect(in: CGRect(x: c.x - w, y: c.y + s * 0.26, width: 2 * w, height: s * 0.16),
                         cornerSize: CGSize(width: s * 0.04, height: s * 0.04))
        return p
    }
}

// MARK: - The clip

/// The fixed script the Videos feed and the covers play: one board being solved over the phase.
enum DailyGridClip {
    /// The whole clip stands for this many seconds of play.
    static let seconds = 40.0

    /// (phase, square, what it becomes). The board is DailyGridPuzzle.stock[0].
    private static let script: [(Double, Int, DailyGridMark)] = [
        (0.04, 1, .cross), (0.09, 2, .cross), (0.15, 6, .cross),
        (0.21, 0, .cross), (0.24, 0, .crown),
        (0.31, 11, .cross),
        (0.38, 10, .cross), (0.41, 10, .crown),
        (0.47, 13, .cross), (0.50, 13, .crown),
        (0.56, 21, .cross), (0.59, 21, .crown),
        (0.64, 29, .cross), (0.67, 29, .crown),
        (0.71, 32, .cross), (0.74, 32, .crown),
    ]

    static let solvedAt = 0.74

    static func frame(at phase: Double, showHUD: Bool) -> DailyGridFrame {
        let puzzle = DailyGridPuzzle.stock[0]
        var f = DailyGridFrame()
        f.showHUD = showHUD
        f.regions = puzzle.regions
        f.boardAge = phase * seconds
        f.clock = phase * seconds
        for (at, cell, mark) in script where phase >= at {
            f.marks[cell] = mark
            f.changedAt[cell] = at * seconds
        }
        let left = Swift.max(0, 142 - Int(phase * seconds))
        f.timerText = "\(left / 60):" + String(format: "%02d", left % 60)
        f.gridText = "Grid 2"
        f.lives = 3
        f.hintAlpha = 0
        if phase >= solvedAt {
            let age = (phase - solvedAt) * seconds
            f.scoreText = "250 points"
            if age < 1.5 {
                f.solvedAge = age
                f.praise = "Great"
                f.praiseAge = age
                f.floatText = "+132"
                f.floatAge = age
                f.sparks = sparks(seed: 3)
            }
        } else {
            f.scoreText = "118 points"
        }
        return f
    }

    /// Confetti for a solve. The game makes the same shape of burst from its own random numbers.
    static func sparks(seed: UInt64) -> [DailyGridSpark] {
        var rng = DailyGridRandom(seed: seed, salt: DailyGridRandom.scenery)
        var out: [DailyGridSpark] = []
        out.reserveCapacity(28)
        for k in 0..<28 {
            let angle = rng.range(0, 2 * .pi)
            let speed = rng.range(0.35, 1.1)
            out.append(DailyGridSpark(x: rng.range(0.3, 0.7), y: rng.range(0.3, 0.7),
                                      vx: cos(angle) * speed, vy: sin(angle) * speed - 0.5,
                                      size: rng.range(3.5, 6.5), tint: k % 7 == 6 ? -1 : k % 6,
                                      spin: rng.range(-9, 9)))
        }
        return out
    }
}
