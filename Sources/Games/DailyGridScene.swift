import SwiftUI

// Daily Grid: one calm logic puzzle a day, the same grid for everyone.
//
// A 6 x 6 board split into six soft colour regions. Place one crown in every row, every column and
// every region, and no two crowns may touch, not even at a corner. Tap a square once for a cross,
// twice for a crown.
//
// DailyGridPuzzle  makes the day's board from a seed and proves it has exactly one answer.
// DailyGridPainter paints the whole screen into a Canvas. The clip in the video feed builds its
//                  state from a phase (0...1); the playable game builds it from its model.

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
            let painter = DailyGridPainter(size: size)
            let clip = DailyGridClip.state(at: phase)
            painter.paintBackdrop(&context, showHUD: showHUD)
            painter.paintBoard(&context, clip.board)
            if showHUD { painter.paintHUD(&context, clip.hud) }
            painter.paintChips(&context, clip.chips, ambient: clip.board.ambient)
            painter.paintSparks(&context, clip.sparks)
            if let praise = clip.praise { painter.paintPraise(&context, praise, age: clip.praiseAge) }
        }
    }
}

// MARK: - Colours and curves

enum DailyGridInk {
    static func hex(_ value: UInt32, _ alpha: Double = 1) -> Color {
        Color(.sRGB, red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255,
              blue: Double(value & 255) / 255, opacity: alpha)
    }

    static let bone = hex(0xECE8E1)
    static let card = hex(0xF8F6F1)
    static let ink = hex(0x151412)
    static let ink2 = hex(0x57534C)
    static let ink3 = hex(0x8A857C)
    static let line = hex(0xD8D2C7)
    static let red = hex(0xC2331F)
    static let gold = hex(0xF5B301)
    static let goldWash = hex(0xFBEFC8)
    static let white = hex(0xFFFFFF)

    /// The six regions: peach, sky, mint, butter, lilac, rose.
    static let regions: [Color] = [hex(0xF6C9B3), hex(0xBFD8F3), hex(0xCDE8C4),
                                   hex(0xF4E2A1), hex(0xDCCEF2), hex(0xF3C6D9)]
    /// A deeper tone of each region, for sparks.
    static let deep: [Color] = [hex(0xE58F68), hex(0x6FA3DB), hex(0x7FBF6E),
                                hex(0xE0B83A), hex(0x9C83D8), hex(0xDE7FA8)]
    /// Friends' avatars.
    static let avatars: [Color] = [hex(0x7DC3F5), hex(0xF6A55B), hex(0xF27FA8), hex(0x9C83D8)]
}

enum DailyGridEase {
    static func unit(_ v: Double) -> Double { Swift.min(Swift.max(v, 0), 1) }

    static func smooth(_ edge0: Double, _ edge1: Double, _ v: Double) -> Double {
        let k = unit((v - edge0) / (edge1 - edge0))
        return k * k * (3 - 2 * k)
    }

    static func outCubic(_ v: Double) -> Double {
        let rest = 1 - unit(v)
        return 1 - rest * rest * rest
    }

    /// Overshoots a little before it settles on 1.
    static func outBack(_ v: Double) -> Double {
        let x = unit(v) - 1
        let spring = 2.2
        return 1 + (spring + 1) * x * x * x + spring * x * x
    }

    static func clock(_ seconds: Int) -> String {
        let total = Swift.max(0, seconds)
        let rest = total % 60
        return "\(total / 60):" + (rest < 10 ? "0\(rest)" : "\(rest)")
    }
}

/// SplitMix64.
struct DailyGridRandom {
    private var state: UInt64

    init(seed: UInt64, salt: UInt64 = 0xD1B54A32D192ED03) {
        state = seed &* 0x9E3779B97F4A7C15 &+ salt
    }

    mutating func bits() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    /// 0 ..< 1
    mutating func next() -> Double { Double(bits() >> 11) / 9007199254740992.0 }
    mutating func range(_ lo: Double, _ hi: Double) -> Double { lo + (hi - lo) * next() }
    /// 0 ..< count
    mutating func int(_ count: Int) -> Int { count <= 1 ? 0 : Int(bits() % UInt64(count)) }
    mutating func int(_ range: ClosedRange<Int>) -> Int { range.lowerBound + int(range.count) }
}

// MARK: - The puzzle

enum DailyGridMark: UInt8 { case empty, cross, crown }

struct DailyGridPuzzle {
    static let n = 6

    /// The region of every square, row by row.
    let regions: [Int]
    /// The crown's column in each row.
    let solution: [Int]

    func region(_ cell: Int) -> Int { regions[cell] }
    func isAnswer(_ cell: Int) -> Bool { solution[cell / Self.n] == cell % Self.n }

    /// Today's puzzle number, counted in Pacific time. Puzzle 212 is Sunday 15 November 2026.
    static func number(on date: Date) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .current
        guard let start = calendar.date(from: DateComponents(year: 2026, month: 4, day: 17)) else { return 0 }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: start),
                                           to: calendar.startOfDay(for: date)).day ?? 0
        return Swift.max(0, days)
    }

    /// The board for one seed. The crowns are planted first, so the board always has an answer, and
    /// a board is kept only once the solver finds that answer is the only one.
    static func make(seed: UInt64) -> DailyGridPuzzle {
        var rng = DailyGridRandom(seed: seed, salt: 0x6772_6964)
        for attempt in 0..<4000 {
            guard let queens = plantCrowns(&rng) else { continue }
            let regions = grow(from: queens, &rng)
            // Early on, also ask for a tidy board: at most one single square, no huge region.
            if attempt < 1500 && !isTidy(regions) { continue }
            if solutions(regions, limit: 2) == 1 { return DailyGridPuzzle(regions: regions, solution: queens) }
        }
        return fallback
    }

    /// A board with one answer, used only if the generator ever gives up.
    static let fallback = DailyGridPuzzle(
        regions: [1, 2, 2, 0, 3, 3,
                  1, 1, 2, 0, 3, 3,
                  1, 1, 2, 3, 3, 5,
                  2, 2, 2, 3, 3, 5,
                  5, 4, 5, 3, 3, 5,
                  5, 5, 5, 5, 5, 5],
        solution: [3, 0, 2, 4, 1, 5])

    private static func plantCrowns(_ rng: inout DailyGridRandom) -> [Int]? {
        var cols = Array(0..<n)
        for _ in 0..<200 {
            var k = n - 1
            while k > 0 {
                cols.swapAt(k, rng.int(k + 1))
                k -= 1
            }
            var apart = true
            for r in 1..<n where abs(cols[r] - cols[r - 1]) < 2 { apart = false }
            if apart { return cols }
        }
        return nil
    }

    /// Each region starts at its crown and takes a free neighbour, bigger regions more often.
    private static func grow(from queens: [Int], _ rng: inout DailyGridRandom) -> [Int] {
        var regions = Array(repeating: -1, count: n * n)
        var sizes = Array(repeating: 1, count: n)
        for r in 0..<n { regions[r * n + queens[r]] = r }
        var left = n * n - n
        var choices = [Int]()
        choices.reserveCapacity(n * n)
        var steps = 0
        while left > 0 && steps < 20000 {
            steps += 1
            var pick = rng.int(n * n - left)
            var k = 0
            while k < n - 1 && pick >= sizes[k] {
                pick -= sizes[k]
                k += 1
            }
            choices.removeAll(keepingCapacity: true)
            for cell in 0..<(n * n) where regions[cell] == -1 {
                let r = cell / n, c = cell % n
                let up = r > 0 && regions[cell - n] == k
                let down = r < n - 1 && regions[cell + n] == k
                let leftSide = c > 0 && regions[cell - 1] == k
                let rightSide = c < n - 1 && regions[cell + 1] == k
                if up || down || leftSide || rightSide { choices.append(cell) }
            }
            if choices.isEmpty { continue }
            regions[choices[rng.int(choices.count)]] = k
            sizes[k] += 1
            left -= 1
        }
        return regions
    }

    private static func isTidy(_ regions: [Int]) -> Bool {
        var sizes = Array(repeating: 0, count: n)
        for k in regions where k >= 0 { sizes[k] += 1 }
        sizes.sort()
        return sizes[1] >= 2 && sizes[n - 1] <= 12
    }

    /// Counts the boards answers, stopping at limit.
    static func solutions(_ regions: [Int], limit: Int) -> Int {
        if regions.contains(-1) { return 0 }
        var found = 0
        func place(_ row: Int, _ cols: Int, _ used: Int, _ prev: Int) {
            if found >= limit { return }
            if row == n {
                found += 1
                return
            }
            for c in 0..<n {
                if cols & (1 << c) != 0 { continue }
                let k = regions[row * n + c]
                if used & (1 << k) != 0 { continue }
                if prev >= 0 && abs(prev - c) < 2 { continue }
                place(row + 1, cols | (1 << c), used | (1 << k), c)
            }
        }
        place(0, 0, 0, -1)
        return found
    }

    /// Marks every crown that breaks a rule against another crown.
    static func conflicts(_ marks: [DailyGridMark], regions: [Int], into out: inout [Bool]) {
        let count = n * n
        for i in 0..<count { out[i] = false }
        for a in 0..<count where marks[a] == .crown {
            for b in (a + 1)..<count where marks[b] == .crown {
                let ra = a / n, ca = a % n, rb = b / n, cb = b % n
                let near = abs(ra - rb) <= 1 && abs(ca - cb) <= 1
                if ra == rb || ca == cb || regions[a] == regions[b] || near {
                    out[a] = true
                    out[b] = true
                }
            }
        }
    }
}

// MARK: - What gets painted

struct DailyGridBoard {
    var puzzle: DailyGridPuzzle
    var marks: [DailyGridMark]
    var conflict: [Bool]
    /// Seconds since each square last changed.
    var age: [Double]
    var hintCell = -1
    var hintAge = 99.0
    /// Seconds since the grid was solved. Below zero: not solved.
    var solveAge = -1.0
    /// Out of time: the answer shows faintly.
    var reveal = false
    var ambient = 0.0

    init(puzzle: DailyGridPuzzle) {
        self.puzzle = puzzle
        let count = DailyGridPuzzle.n * DailyGridPuzzle.n
        marks = Array(repeating: .empty, count: count)
        conflict = Array(repeating: false, count: count)
        age = Array(repeating: 99, count: count)
    }
}

struct DailyGridHUD {
    var timeText = "0:00"
    var timePop = 99.0
    var alert = false
    var sub = ""
    /// Above zero: the line under the timer breathes.
    var pulse = 0.0
    var keyDown = -1
    var keyAge = 99.0
}

struct DailyGridChip {
    var name: String
    var seconds: Int
    var doneAge: Double?
}

/// Positions and speeds are in squares, from the board's top left corner.
struct DailyGridSpark {
    var x = 0.0, y = 0.0, vx = 0.0, vy = 0.0
    var age = 99.0, life = 1.0, size = 4.0
    /// A region colour, or -1 for gold.
    var tint = 0
}

/// Positions are in squares, from the board's top left corner.
struct DailyGridFloat {
    var text = ""
    var x = 0.0, y = 0.0
    var age = 99.0
    /// 0 ink, 1 red.
    var tint = 0
}

struct DailyGridRow {
    var rank: Int
    var name: String
    var time: String
    var you: Bool
}

struct DailyGridCard {
    var title: String
    var time: String
    var line: String
    var rows: [DailyGridRow]
    var age: Double
}

// MARK: - Layout

/// Where everything sits. Built from the view size; the same numbers place touches and paint.
struct DailyGridLayout {
    static let keyTitles = ["UNDO", "HINT", "CLEAR"]

    let size: CGSize
    let s: CGFloat
    let cx: CGFloat
    let titleY: CGFloat
    let timerY: CGFloat
    let subY: CGFloat
    let board: CGRect
    let cell: CGFloat
    let keysTop: CGFloat
    let keyH: CGFloat
    let keyW: CGFloat
    let keyGap: CGFloat
    let rules: CGRect
    let chips: CGRect

    init(size: CGSize) {
        self.size = size
        let w = size.width, h = size.height
        let usable = h - GameLayout.topBand - GameLayout.bottomInset
        s = Swift.max(0.5, Swift.min(w / 402, usable / 728))
        cx = w / 2
        titleY = GameLayout.statusBarHeight + 22
        let top = GameLayout.topBand
        timerY = top + 24 * s
        subY = top + 60 * s
        let side = Swift.min(w - 36, 356 * s)
        board = CGRect(x: cx - side / 2, y: top + 84 * s, width: side, height: side)
        cell = side / CGFloat(DailyGridPuzzle.n)
        keysTop = board.maxY + 20 * s
        keyH = 50 * s
        keyGap = 12 * s
        keyW = (side - 2 * keyGap) / 3
        rules = CGRect(x: board.minX, y: keysTop + keyH + 18 * s, width: side, height: 78 * s)
        chips = CGRect(x: board.minX, y: rules.maxY + 14 * s, width: side, height: 46 * s)
    }

    func cellRect(_ i: Int) -> CGRect {
        let r = i / DailyGridPuzzle.n, c = i % DailyGridPuzzle.n
        return CGRect(x: board.minX + CGFloat(c) * cell, y: board.minY + CGFloat(r) * cell, width: cell, height: cell)
    }

    func cellCenter(_ i: Int) -> CGPoint {
        let rect = cellRect(i)
        return CGPoint(x: rect.midX, y: rect.midY)
    }

    func keyRect(_ k: Int) -> CGRect {
        CGRect(x: board.minX + CGFloat(k) * (keyW + keyGap), y: keysTop, width: keyW, height: keyH)
    }

    func cell(at p: CGPoint) -> Int? {
        guard board.contains(p) else { return nil }
        let c = Swift.min(DailyGridPuzzle.n - 1, Int((p.x - board.minX) / cell))
        let r = Swift.min(DailyGridPuzzle.n - 1, Int((p.y - board.minY) / cell))
        return r * DailyGridPuzzle.n + c
    }

    func key(at p: CGPoint) -> Int? {
        for k in 0..<3 where keyRect(k).insetBy(dx: -4, dy: -8).contains(p) { return k }
        return nil
    }
}

// MARK: - Painter

struct DailyGridPainter {
    let L: DailyGridLayout
    var s: CGFloat { L.s }

    init(size: CGSize) {
        L = DailyGridLayout(size: size)
    }

    // MARK: Still parts

    /// The page, the title, the three keys at rest and the rules card.
    func paintBackdrop(_ ctx: inout GraphicsContext, showHUD: Bool) {
        ctx.fill(Path(CGRect(origin: .zero, size: L.size)), with: .color(DailyGridInk.bone))
        if showHUD {
            let title = Text("DAILY GRID").font(.custom("BigShoulders-Black", size: 30)).kerning(1.2)
            ctx.draw(title.foregroundColor(DailyGridInk.ink), at: CGPoint(x: L.cx, y: L.titleY), anchor: .center)
        }
        for k in 0..<3 { paintKey(&ctx, k, down: 0) }
        paintRules(&ctx)
    }

    func paintKey(_ ctx: inout GraphicsContext, _ k: Int, down: Double) {
        let rect = L.keyRect(k)
        let lip = 4 * s
        let press = CGFloat(down) * lip
        let base = Path(roundedRect: rect.offsetBy(dx: 0, dy: lip), cornerRadius: rect.height / 2, style: .continuous)
        ctx.fill(base, with: .color(DailyGridInk.line))
        let capRect = rect.offsetBy(dx: 0, dy: press)
        let cap = Path(roundedRect: capRect, cornerRadius: rect.height / 2, style: .continuous)
        ctx.fill(cap, with: .color(down > 0.01 ? DailyGridInk.card : DailyGridInk.white))
        let label = Text(DailyGridLayout.keyTitles[k])
            .font(.system(size: 15 * s, weight: .heavy, design: .rounded)).kerning(1.4 * s)
        ctx.draw(label.foregroundColor(DailyGridInk.ink), at: CGPoint(x: capRect.midX, y: capRect.midY), anchor: .center)
    }

    private func paintRules(_ ctx: inout GraphicsContext) {
        let card = Path(roundedRect: L.rules, cornerRadius: 22 * s, style: .continuous)
        ctx.fill(card, with: .color(DailyGridInk.card))
        let size = 14 * s
        let x = L.rules.minX + 18 * s
        let line1 = L.rules.minY + 22 * s
        let crownSize = 14 * s
        let one = Text("One").font(.system(size: size, weight: .medium))
        ctx.draw(one.foregroundColor(DailyGridInk.ink), at: CGPoint(x: x, y: line1), anchor: .leading)
        let afterOne = x + 31 * s
        paintCrown(&ctx, center: CGPoint(x: afterOne + crownSize * 0.5, y: line1 + 1 * s), size: crownSize, color: DailyGridInk.ink)
        let rest = Text("in each row, column and colour.").font(.system(size: size, weight: .medium))
        ctx.draw(rest.foregroundColor(DailyGridInk.ink), at: CGPoint(x: afterOne + crownSize + 5 * s, y: line1), anchor: .leading)
        let second = Text("Crowns never touch, not even at corners.").font(.system(size: size, weight: .medium))
        ctx.draw(second.foregroundColor(DailyGridInk.ink), at: CGPoint(x: x, y: L.rules.minY + 42 * s), anchor: .leading)
        let third = Text("Tap once for a cross, twice for a crown.").font(.system(size: 13 * s, weight: .regular))
        ctx.draw(third.foregroundColor(DailyGridInk.ink2), at: CGPoint(x: x, y: L.rules.minY + 61 * s), anchor: .leading)
    }

    // MARK: Marks

    func crownPath(center: CGPoint, size: CGFloat) -> Path {
        let k = size
        let cx = center.x, cy = center.y
        var p = Path()
        p.move(to: CGPoint(x: cx - 0.42 * k, y: cy + 0.24 * k))
        p.addLine(to: CGPoint(x: cx - 0.50 * k, y: cy - 0.22 * k))
        p.addLine(to: CGPoint(x: cx - 0.20 * k, y: cy + 0.01 * k))
        p.addLine(to: CGPoint(x: cx, y: cy - 0.34 * k))
        p.addLine(to: CGPoint(x: cx + 0.20 * k, y: cy + 0.01 * k))
        p.addLine(to: CGPoint(x: cx + 0.50 * k, y: cy - 0.22 * k))
        p.addLine(to: CGPoint(x: cx + 0.42 * k, y: cy + 0.24 * k))
        p.closeSubpath()
        p.addRoundedRect(in: CGRect(x: cx - 0.42 * k, y: cy + 0.30 * k, width: 0.84 * k, height: 0.12 * k),
                         cornerSize: CGSize(width: 0.04 * k, height: 0.04 * k))
        let r = 0.075 * k
        p.addEllipse(in: CGRect(x: cx - 0.50 * k - r, y: cy - 0.26 * k - r, width: 2 * r, height: 2 * r))
        p.addEllipse(in: CGRect(x: cx - r, y: cy - 0.39 * k - r, width: 2 * r, height: 2 * r))
        p.addEllipse(in: CGRect(x: cx + 0.50 * k - r, y: cy - 0.26 * k - r, width: 2 * r, height: 2 * r))
        return p
    }

    func paintCrown(_ ctx: inout GraphicsContext, center: CGPoint, size: CGFloat, color: Color) {
        ctx.fill(crownPath(center: center, size: size), with: .color(color))
    }

    private func paintCross(_ ctx: inout GraphicsContext, center: CGPoint, size: CGFloat, alpha: Double) {
        let d = size * 0.5
        var p = Path()
        p.move(to: CGPoint(x: center.x - d, y: center.y - d))
        p.addLine(to: CGPoint(x: center.x + d, y: center.y + d))
        p.move(to: CGPoint(x: center.x + d, y: center.y - d))
        p.addLine(to: CGPoint(x: center.x - d, y: center.y + d))
        ctx.stroke(p, with: .color(DailyGridInk.ink2.opacity(alpha)),
                   style: StrokeStyle(lineWidth: Swift.max(1.5, 2.6 * s), lineCap: .round))
    }

    // MARK: Board

    func paintBoard(_ ctx: inout GraphicsContext, _ b: DailyGridBoard) {
        let n = DailyGridPuzzle.n
        let frame = L.board.insetBy(dx: -4 * s, dy: -4 * s)
        let radius = 12 * s
        ctx.fill(Path(roundedRect: frame.offsetBy(dx: 0, dy: 5 * s), cornerRadius: radius, style: .continuous),
                 with: .color(DailyGridInk.ink.opacity(0.10)))
        ctx.fill(Path(roundedRect: frame, cornerRadius: radius, style: .continuous), with: .color(DailyGridInk.ink))

        var inner = ctx
        inner.clip(to: Path(roundedRect: L.board, cornerRadius: radius - 4 * s, style: .continuous))
        for i in 0..<(n * n) {
            let rect = L.cellRect(i)
            inner.fill(Path(rect), with: .color(DailyGridInk.regions[b.puzzle.region(i) % 6]))
            if b.conflict[i] && b.marks[i] == .crown {
                inner.fill(Path(rect), with: .color(DailyGridInk.red.opacity(0.22)))
            }
        }
        paintHintGlow(&inner, b)
        paintSolveWave(&inner, b)
        paintGridLines(&inner, b)
        paintMarks(&ctx, b)
    }

    private func paintGridLines(_ ctx: inout GraphicsContext, _ b: DailyGridBoard) {
        let n = DailyGridPuzzle.n
        var thin = Path()
        var thick = Path()
        let x0 = L.board.minX, y0 = L.board.minY, c = L.cell
        for r in 0..<n {
            for col in 0..<n {
                let i = r * n + col
                if col < n - 1 {
                    let x = x0 + CGFloat(col + 1) * c
                    let a = CGPoint(x: x, y: y0 + CGFloat(r) * c)
                    let z = CGPoint(x: x, y: y0 + CGFloat(r + 1) * c)
                    if b.puzzle.region(i) != b.puzzle.region(i + 1) {
                        thick.move(to: a)
                        thick.addLine(to: z)
                    } else {
                        thin.move(to: a)
                        thin.addLine(to: z)
                    }
                }
                if r < n - 1 {
                    let y = y0 + CGFloat(r + 1) * c
                    let a = CGPoint(x: x0 + CGFloat(col) * c, y: y)
                    let z = CGPoint(x: x0 + CGFloat(col + 1) * c, y: y)
                    if b.puzzle.region(i) != b.puzzle.region(i + n) {
                        thick.move(to: a)
                        thick.addLine(to: z)
                    } else {
                        thin.move(to: a)
                        thin.addLine(to: z)
                    }
                }
            }
        }
        ctx.stroke(thin, with: .color(DailyGridInk.ink.opacity(0.13)), lineWidth: 1)
        ctx.stroke(thick, with: .color(DailyGridInk.ink.opacity(0.85)),
                   style: StrokeStyle(lineWidth: Swift.max(2, 2.8 * s), lineCap: .square))
    }

    private func paintHintGlow(_ ctx: inout GraphicsContext, _ b: DailyGridBoard) {
        guard b.hintCell >= 0, b.hintAge < 1.6 else { return }
        let fade = 1 - DailyGridEase.smooth(0.9, 1.6, b.hintAge)
        let pulse = 0.5 + 0.5 * sin(b.hintAge * 14)
        ctx.fill(Path(L.cellRect(b.hintCell)), with: .color(DailyGridInk.white.opacity((0.35 + 0.35 * pulse) * fade)))
    }

    private func paintSolveWave(_ ctx: inout GraphicsContext, _ b: DailyGridBoard) {
        guard b.solveAge >= 0, b.solveAge < 1.6 else { return }
        let n = DailyGridPuzzle.n
        for i in 0..<(n * n) {
            let delay = Double(i / n + i % n) * 0.06
            let t = b.solveAge - delay
            if t <= 0 || t >= 0.45 { continue }
            let bump = sin(t / 0.45 * Double.pi)
            ctx.fill(Path(L.cellRect(i)), with: .color(DailyGridInk.white.opacity(0.65 * bump)))
        }
    }

    private func paintMarks(_ ctx: inout GraphicsContext, _ b: DailyGridBoard) {
        let n = DailyGridPuzzle.n
        let crownSize = L.cell * 0.58
        for i in 0..<(n * n) {
            let center = L.cellCenter(i)
            switch b.marks[i] {
            case .empty:
                if b.reveal && b.puzzle.isAnswer(i) {
                    paintCrown(&ctx, center: center, size: crownSize, color: DailyGridInk.ink.opacity(0.28))
                }
            case .cross:
                let grow = DailyGridEase.outBack(b.age[i] / 0.14)
                paintCross(&ctx, center: center, size: L.cell * 0.26 * CGFloat(0.4 + 0.6 * grow), alpha: 0.75)
            case .crown:
                paintPlacedCrown(&ctx, b, i, center: center, size: crownSize)
            }
        }
    }

    private func paintPlacedCrown(_ ctx: inout GraphicsContext, _ b: DailyGridBoard, _ i: Int, center: CGPoint, size: CGFloat) {
        var scale = 0.35 + 0.65 * DailyGridEase.outBack(b.age[i] / 0.16)
        let wrong = b.conflict[i]
        if b.solveAge >= 0 {
            let t = b.solveAge - Double(i / DailyGridPuzzle.n) * 0.09
            if t > 0 && t < 0.5 { scale *= 1 + 0.32 * sin(t / 0.5 * Double.pi) }
        }
        let k = size * CGFloat(scale)
        if wrong {
            let a = b.age[i]
            let shake = a < 0.35 ? sin(a * 60) * 3 * (1 - a / 0.35) : 0
            paintCrown(&ctx, center: CGPoint(x: center.x + CGFloat(shake) * s, y: center.y), size: k, color: DailyGridInk.red)
            return
        }
        paintCrown(&ctx, center: CGPoint(x: center.x, y: center.y + 2 * s), size: k, color: DailyGridInk.white.opacity(0.55))
        paintCrown(&ctx, center: center, size: k, color: DailyGridInk.ink)
        if b.solveAge >= 0 {
            let glint = 0.5 + 0.5 * sin(b.ambient * 3 + Double(i))
            let gem = 0.085 * k
            let tip = CGPoint(x: center.x, y: center.y - 0.39 * k)
            ctx.fill(Path(ellipseIn: CGRect(x: tip.x - gem, y: tip.y - gem, width: 2 * gem, height: 2 * gem)),
                     with: .color(DailyGridInk.gold.opacity(0.6 + 0.4 * glint)))
        }
    }

    // MARK: Heads-up

    func paintHUD(_ ctx: inout GraphicsContext, _ hud: DailyGridHUD) {
        let pop = 1 + 0.12 * (1 - DailyGridEase.outCubic(hud.timePop / 0.22))
        let timer = Text(hud.timeText).font(.custom("BigShoulders-Black", size: 46 * s * CGFloat(pop))).monospacedDigit()
        ctx.draw(timer.foregroundColor(hud.alert ? DailyGridInk.red : DailyGridInk.ink),
                 at: CGPoint(x: L.cx, y: L.timerY), anchor: .center)
        if !hud.sub.isEmpty {
            let alpha = hud.pulse > 0 ? 0.55 + 0.45 * (0.5 + 0.5 * sin(hud.pulse * 3.2)) : 1
            let sub = Text(hud.sub).font(.system(size: 14 * s, weight: .semibold, design: .rounded))
            ctx.draw(sub.foregroundColor(DailyGridInk.ink2.opacity(alpha)), at: CGPoint(x: L.cx, y: L.subY), anchor: .center)
        }
        if hud.keyDown >= 0 && hud.keyAge < 0.18 {
            paintKey(&ctx, hud.keyDown, down: 1 - DailyGridEase.smooth(0.08, 0.18, hud.keyAge))
        }
    }

    // MARK: Friends

    func paintChips(_ ctx: inout GraphicsContext, _ chips: [DailyGridChip], ambient: Double) {
        guard !chips.isEmpty else { return }
        let count = chips.count
        let gap = 8 * s
        let w = (L.chips.width - gap * CGFloat(count - 1)) / CGFloat(count)
        for k in 0..<count {
            let rect = CGRect(x: L.chips.minX + CGFloat(k) * (w + gap), y: L.chips.minY, width: w, height: L.chips.height)
            paintChip(&ctx, chips[k], rect: rect, tint: DailyGridInk.avatars[k % DailyGridInk.avatars.count], ambient: ambient, index: k)
        }
    }

    private func paintChip(_ ctx: inout GraphicsContext, _ chip: DailyGridChip, rect: CGRect, tint: Color, ambient: Double, index: Int) {
        var flash = 0.0
        if let done = chip.doneAge { flash = Swift.max(0, 1 - done / 0.6) }
        let bg = Path(roundedRect: rect, cornerRadius: rect.height / 2, style: .continuous)
        ctx.fill(bg, with: .color(DailyGridInk.card))
        if flash > 0 { ctx.fill(bg, with: .color(DailyGridInk.goldWash.opacity(flash))) }
        let grow = 1 + 0.25 * CGFloat(flash)
        let r = rect.height * 0.32 * grow
        let dot = CGPoint(x: rect.minX + rect.height * 0.5, y: rect.midY)
        ctx.fill(Path(ellipseIn: CGRect(x: dot.x - r, y: dot.y - r, width: 2 * r, height: 2 * r)), with: .color(tint))
        let initial = Text(String(chip.name.prefix(1)).uppercased()).font(.system(size: 13 * s, weight: .heavy, design: .rounded))
        ctx.draw(initial.foregroundColor(DailyGridInk.ink), at: dot, anchor: .center)
        let textX = dot.x + rect.height * 0.32 + 7 * s
        let name = Text(String(chip.name.prefix(9))).font(.system(size: 12 * s, weight: .bold, design: .rounded))
        ctx.draw(name.foregroundColor(DailyGridInk.ink), at: CGPoint(x: textX, y: rect.midY - 7 * s), anchor: .leading)
        if chip.doneAge != nil {
            let time = Text(DailyGridEase.clock(chip.seconds)).font(.system(size: 12 * s, weight: .semibold, design: .rounded)).monospacedDigit()
            ctx.draw(time.foregroundColor(DailyGridInk.ink2), at: CGPoint(x: textX, y: rect.midY + 8 * s), anchor: .leading)
            return
        }
        let dr = 2.2 * s
        for d in 0..<3 {
            let wave = ambient * 4 - Double(d) * 0.6 + Double(index)
            let a = 0.3 + 0.5 * (0.5 + 0.5 * sin(wave))
            let at = CGPoint(x: textX + dr + CGFloat(d) * 7 * s, y: rect.midY + 8 * s)
            ctx.fill(Path(ellipseIn: CGRect(x: at.x - dr, y: at.y - dr, width: 2 * dr, height: 2 * dr)),
                     with: .color(DailyGridInk.ink3.opacity(a)))
        }
    }

    // MARK: Juice

    func paintSparks(_ ctx: inout GraphicsContext, _ sparks: [DailyGridSpark]) {
        for spark in sparks where spark.age < spark.life {
            let k = spark.age / spark.life
            let r = CGFloat(spark.size * (1 - k * 0.7)) * s
            let color = spark.tint < 0 ? DailyGridInk.gold : DailyGridInk.deep[spark.tint % 6]
            let x = L.board.minX + CGFloat(spark.x) * L.cell, y = L.board.minY + CGFloat(spark.y) * L.cell
            let rect = CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)
            ctx.fill(Path(ellipseIn: rect), with: .color(color.opacity(1 - k * k)))
        }
    }

    func paintFloats(_ ctx: inout GraphicsContext, _ floats: [DailyGridFloat]) {
        for f in floats where f.age < 1.0 {
            let rise = CGFloat(DailyGridEase.outCubic(f.age) * 34) * s
            let alpha = 1 - DailyGridEase.smooth(0.55, 1.0, f.age)
            let pop = 1 + 0.3 * (1 - DailyGridEase.unit(f.age / 0.15))
            let text = Text(f.text).font(.system(size: 17 * s * CGFloat(pop), weight: .heavy, design: .rounded))
            let color = f.tint == 1 ? DailyGridInk.red : DailyGridInk.ink
            let at = CGPoint(x: L.board.minX + CGFloat(f.x) * L.cell, y: L.board.minY + CGFloat(f.y) * L.cell - rise)
            ctx.draw(text.foregroundColor(DailyGridInk.white.opacity(alpha * 0.8)), at: CGPoint(x: at.x, y: at.y + 1.5 * s), anchor: .center)
            ctx.draw(text.foregroundColor(color.opacity(alpha)), at: at, anchor: .center)
        }
    }

    func paintPraise(_ ctx: inout GraphicsContext, _ word: String, age: Double) {
        if age < 0 || age > 1.5 { return }
        let grow = DailyGridEase.outBack(age / 0.22)
        let alpha = 1 - DailyGridEase.smooth(1.1, 1.5, age)
        let size = 66 * s * CGFloat(0.5 + 0.5 * grow)
        let text = Text(word).font(.custom("BigShoulders-Black", size: size)).kerning(2 * s)
        let at = CGPoint(x: L.cx, y: L.board.midY)
        ctx.draw(text.foregroundColor(DailyGridInk.ink.opacity(0.25 * alpha)), at: CGPoint(x: at.x, y: at.y + 5 * s), anchor: .center)
        ctx.draw(text.foregroundColor(DailyGridInk.white.opacity(alpha)), at: CGPoint(x: at.x + 2.5 * s, y: at.y + 2.5 * s), anchor: .center)
        ctx.draw(text.foregroundColor(DailyGridInk.ink.opacity(alpha)), at: at, anchor: .center)
    }

    // MARK: The solved card

    func paintCard(_ ctx: inout GraphicsContext, _ card: DailyGridCard) {
        let k = DailyGridEase.outCubic(card.age / 0.35)
        if k <= 0 { return }
        ctx.fill(Path(CGRect(origin: .zero, size: L.size)), with: .color(DailyGridInk.bone.opacity(0.95 * k)))
        var c = ctx
        c.opacity = k
        c.translateBy(x: 0, y: CGFloat(1 - k) * 60 * s)

        let top = GameLayout.topBand + 6 * s
        let label = Text(card.title).font(.system(size: 14 * s, weight: .semibold, design: .monospaced)).kerning(1.5 * s)
        c.draw(label.foregroundColor(DailyGridInk.ink2), at: CGPoint(x: L.cx, y: top + 10 * s), anchor: .center)
        let time = Text(card.time).font(.custom("BigShoulders-Black", size: 124 * s)).monospacedDigit()
        c.draw(time.foregroundColor(DailyGridInk.ink), at: CGPoint(x: L.cx, y: top + 94 * s), anchor: .center)
        let line = Text(card.line).font(.system(size: 17 * s, weight: .bold, design: .rounded))
        c.draw(line.foregroundColor(DailyGridInk.ink), at: CGPoint(x: L.cx, y: top + 174 * s), anchor: .center)

        guard !card.rows.isEmpty else { return }
        let rowH = 56 * s
        let box = CGRect(x: L.board.minX, y: top + 208 * s, width: L.board.width,
                         height: rowH * CGFloat(card.rows.count) + 20 * s)
        c.fill(Path(roundedRect: box, cornerRadius: 26 * s, style: .continuous), with: .color(DailyGridInk.card))
        for k in 0..<card.rows.count {
            let a = DailyGridEase.outCubic((card.age - 0.25 - Double(k) * 0.08) / 0.25)
            if a <= 0 { continue }
            let rect = CGRect(x: box.minX + 10 * s, y: box.minY + 10 * s + CGFloat(k) * rowH, width: box.width - 20 * s, height: rowH)
            paintRow(&c, card.rows[k], rect: rect, alpha: a, tint: DailyGridInk.avatars[k % DailyGridInk.avatars.count])
        }
    }

    private func paintRow(_ c: inout GraphicsContext, _ row: DailyGridRow, rect: CGRect, alpha: Double, tint: Color) {
        if row.you {
            c.fill(Path(roundedRect: rect.insetBy(dx: 0, dy: 3 * s), cornerRadius: 16 * s, style: .continuous),
                   with: .color(DailyGridInk.goldWash.opacity(alpha)))
        }
        let rank = Text("\(row.rank)").font(.system(size: 15 * s, weight: .semibold, design: .rounded))
        c.draw(rank.foregroundColor(DailyGridInk.ink2.opacity(alpha)), at: CGPoint(x: rect.minX + 18 * s, y: rect.midY), anchor: .center)
        let r = 17 * s
        let dot = CGPoint(x: rect.minX + 58 * s, y: rect.midY)
        let fill = row.you ? DailyGridInk.gold : tint
        c.fill(Path(ellipseIn: CGRect(x: dot.x - r, y: dot.y - r, width: 2 * r, height: 2 * r)), with: .color(fill.opacity(alpha)))
        let initial = Text(String(row.name.prefix(1)).uppercased()).font(.system(size: 15 * s, weight: .heavy, design: .rounded))
        c.draw(initial.foregroundColor(DailyGridInk.ink.opacity(alpha)), at: dot, anchor: .center)
        let name = Text(row.name).font(.system(size: 18 * s, weight: .bold, design: .rounded))
        c.draw(name.foregroundColor(DailyGridInk.ink.opacity(alpha)), at: CGPoint(x: rect.minX + 88 * s, y: rect.midY), anchor: .leading)
        let time = Text(row.time).font(.system(size: 18 * s, weight: .bold, design: .rounded)).monospacedDigit()
        c.draw(time.foregroundColor(DailyGridInk.ink.opacity(alpha)), at: CGPoint(x: rect.maxX - 14 * s, y: rect.midY), anchor: .trailing)
    }
}

// MARK: - The clip

/// A fixed solve played out over the phase: crowns go down one by one with their crosses, then
/// the whole board lights up.
enum DailyGridClip {
    static let puzzle = DailyGridPuzzle.make(seed: 212)

    struct State {
        var board: DailyGridBoard
        var hud: DailyGridHUD
        var chips: [DailyGridChip]
        var sparks: [DailyGridSpark]
        var praise: String?
        var praiseAge: Double
    }

    static func state(at phase: Double) -> State {
        let p = DailyGridEase.unit(phase)
        let n = DailyGridPuzzle.n
        var board = DailyGridBoard(puzzle: puzzle)
        board.ambient = p * 20
        let placed = Swift.min(n, Int(p / 0.8 * Double(n) + 0.35))
        let rows = order(for: puzzle)
        for k in 0..<placed {
            let row = rows[k]
            let col = puzzle.solution[row]
            board.marks[row * n + col] = .crown
            for c in 0..<n where c != col && board.marks[row * n + c] == .empty { board.marks[row * n + c] = .cross }
        }
        if p >= 0.86 { board.solveAge = (p - 0.86) * 6 }
        let seconds = Int(8 + p * 59)
        var hud = DailyGridHUD()
        hud.timeText = DailyGridEase.clock(seconds)
        hud.sub = placed >= n ? "Solved" : "\(placed) of 6 crowns"
        let chips = [DailyGridChip(name: "kaz", seconds: 52, doneAge: seconds >= 52 ? 9 : nil),
                     DailyGridChip(name: "devon.plays", seconds: 91, doneAge: nil),
                     DailyGridChip(name: "noor.runs", seconds: 130, doneAge: nil)]
        var sparks: [DailyGridSpark] = []
        if board.solveAge >= 0 {
            var rng = DailyGridRandom(seed: 9)
            let t = Swift.min(board.solveAge, 0.9)
            for row in 0..<n {
                let cell = row * n + puzzle.solution[row]
                let cx = Double(cell % n) + 0.5, cy = Double(row) + 0.5
                for _ in 0..<8 {
                    let angle = rng.range(0, 2 * Double.pi)
                    let speed = rng.range(1.0, 3.2)
                    var spark = DailyGridSpark()
                    spark.x = cx + cos(angle) * speed * t
                    spark.y = cy + sin(angle) * speed * t + 2 * t * t
                    spark.age = t
                    spark.life = 1.1
                    spark.size = rng.range(3, 6)
                    spark.tint = rng.next() < 0.35 ? -1 : puzzle.regions[cell]
                    sparks.append(spark)
                }
            }
        }
        return State(board: board, hud: hud, chips: chips, sparks: sparks,
                     praise: board.solveAge >= 0 ? "PERFECT" : nil, praiseAge: Swift.max(0, board.solveAge - 0.1))
    }
}
