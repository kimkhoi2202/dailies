import SwiftUI

// Slip Out: a board of bent arrows. Tap one and it slides out along its head, unless another
// arrow is in the way.
//
// The whole picture is painted into one Canvas by SlipOutPainter from a SlipOutFrame. The clip in
// the video feed builds a frame from a phase (0...1) and a fixed level; the playable game builds
// one from its live state. The pictures are the slip-out-* images in Resources/GameArt; any frame
// size, drawn for a 402 x 874 stage.

public struct SlipOutScene: View {
    public var phase: Double
    public var showHUD: Bool

    public init(phase: Double, showHUD: Bool) {
        self.phase = phase
        self.showHUD = showHUD
    }

    public var body: some View {
        Canvas(opaque: true, colorMode: .nonLinear, rendersAsynchronously: false) { context, size in
            if size.width <= 8 || size.height <= 8 { return }
            let frame = SlipOutClip.frame(at: phase)
            SlipOutPainter(size: size, frame: frame, showHUD: showHUD).draw(&context)
        }
    }
}

// MARK: - Numbers

enum SlipOutMath {
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

    static func easeIn(_ v: Double) -> Double {
        let k = clamp(v)
        return k * k * k
    }

    /// Rises fast, overshoots a little and settles: a pop. 0 at 0, 1 at 1.
    static func pop(_ v: Double) -> Double {
        let k = clamp(v)
        return 1 - exp(-6 * k) * cos(2.4 * .pi * k) * (1 - k)
    }
}

/// SplitMix64. The level and the pilot use different salts so they never share a sequence.
struct SlipOutRandom {
    static let level: UInt64 = 0xA24BAED4963EE407
    static let pilot: UInt64 = 0x2545F4914F6CDD1D

    private var state: UInt64

    init(seed: UInt64, salt: UInt64) {
        state = seed &* 0x9E3779B97F4A7C15 &+ salt
    }

    /// 0 ..< 1
    mutating func next() -> Double {
        state &+= 0x9E3779B97F4A7C15
        var v: UInt64 = state
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

enum SlipOutInk {
    static func hex(_ value: UInt32, _ alpha: Double = 1) -> Color {
        Color(.sRGB, red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255,
              blue: Double(value & 255) / 255, opacity: alpha)
    }

    static let dot = hex(0xCDC7BC)
    static let ink = hex(0x151412)
    static let inkSoft = hex(0x151412, 0.55)
    static let red = hex(0xE8503F)
    static let green = hex(0x2EB872)
}

// MARK: - The board

enum SlipOutDir: Int, CaseIterable {
    case up, right, down, left

    var dx: Int {
        switch self {
        case .right: return 1
        case .left: return -1
        case .up, .down: return 0
        }
    }

    var dy: Int {
        switch self {
        case .down: return 1
        case .up: return -1
        case .left, .right: return 0
        }
    }

    var opposite: SlipOutDir {
        switch self {
        case .up: return .down
        case .down: return .up
        case .left: return .right
        case .right: return .left
        }
    }

    var turnedLeft: SlipOutDir {
        switch self {
        case .up: return .left
        case .left: return .down
        case .down: return .right
        case .right: return .up
        }
    }

    var turnedRight: SlipOutDir { turnedLeft.opposite }
}

struct SlipOutCell: Equatable {
    var x: Int
    var y: Int
}

/// One arrow: a path of cells from the tail to the head, and the way the head points.
struct SlipOutArrow {
    let id: Int
    /// Tail first, head last. At least two cells.
    let cells: [SlipOutCell]
    let dir: SlipOutDir

    var head: SlipOutCell { cells[cells.count - 1] }

    /// How far it has to slide before every cell is off the board, plus a little.
    func exitDistance(cols: Int, rows: Int) -> Double {
        var far = 0
        for c in cells {
            let d: Int
            switch dir {
            case .right: d = cols - c.x
            case .left: d = c.x + 1
            case .down: d = rows - c.y
            case .up: d = c.y + 1
            }
            far = Swift.max(far, d)
        }
        return Double(far) + 1.5
    }
}

/// A level: the board size and its arrows in the order they were laid down. Removing them from
/// the last to the first always works, so every level is solvable.
struct SlipOutLevel {
    let cols: Int
    let rows: Int
    let arrows: [SlipOutArrow]

    /// Builds a level backwards: each new arrow's way out is checked against the arrows already
    /// down, which are the ones that will still be there when it leaves.
    static func make(index: Int, seed: UInt64) -> SlipOutLevel {
        let step = Swift.max(0, index)
        let cols = Swift.min(10, 6 + step / 2)
        let rows = Swift.min(13, 8 + (step * 2) / 3)
        let salt = SlipOutRandom.level &+ UInt64(step + 1) &* 0x9E3779B97F4A7C15
        var rng = SlipOutRandom(seed: seed, salt: salt)
        let want = Swift.min(cols * rows * 68 / 100, 18 + step * 5)
        let maxLength = Swift.min(7, 3 + step / 2)

        var owner = [Int](repeating: -1, count: cols * rows)
        var arrows: [SlipOutArrow] = []
        var filled = 0
        var misses = 0

        while filled < want && misses < 400 {
            let hx = rng.int(0...(cols - 1))
            let hy = rng.int(0...(rows - 1))
            if owner[hy * cols + hx] >= 0 {
                misses += 1
                continue
            }

            // Which ways out are clear of the arrows already down.
            var open: [SlipOutDir] = []
            for d in SlipOutDir.allCases {
                var x = hx + d.dx
                var y = hy + d.dy
                var clear = true
                while x >= 0 && x < cols && y >= 0 && y < rows {
                    if owner[y * cols + x] >= 0 {
                        clear = false
                        break
                    }
                    x += d.dx
                    y += d.dy
                }
                if clear { open.append(d) }
            }
            if open.isEmpty {
                misses += 1
                continue
            }
            let dir = open[rng.int(0...(open.count - 1))]

            // The tail grows away from the head, mostly straight, never onto the way out and
            // never beside itself.
            var cells: [SlipOutCell] = [SlipOutCell(x: hx, y: hy)]
            let length = rng.int(2...maxLength)
            var cur = cells[0]
            var heading = dir.opposite
            while cells.count < length {
                let roll = rng.next()
                let order: [SlipOutDir]
                if roll < 0.58 {
                    order = [heading, heading.turnedLeft, heading.turnedRight]
                } else if roll < 0.79 {
                    order = [heading.turnedLeft, heading, heading.turnedRight]
                } else {
                    order = [heading.turnedRight, heading, heading.turnedLeft]
                }
                var placed = false
                for d in order {
                    let n = SlipOutCell(x: cur.x + d.dx, y: cur.y + d.dy)
                    if n.x < 0 || n.x >= cols || n.y < 0 || n.y >= rows { continue }
                    if owner[n.y * cols + n.x] >= 0 { continue }
                    let onWayOut: Bool = dir.dx != 0 ? (n.y == hy && (n.x - hx) * dir.dx > 0)
                                                     : (n.x == hx && (n.y - hy) * dir.dy > 0)
                    if onWayOut { continue }
                    // The cell must have a clear way out of its own, since the whole arrow moves.
                    var ahead = SlipOutCell(x: n.x + dir.dx, y: n.y + dir.dy)
                    var clearAhead = true
                    while ahead.x >= 0 && ahead.x < cols && ahead.y >= 0 && ahead.y < rows {
                        if owner[ahead.y * cols + ahead.x] >= 0 {
                            clearAhead = false
                            break
                        }
                        ahead = SlipOutCell(x: ahead.x + dir.dx, y: ahead.y + dir.dy)
                    }
                    if !clearAhead { continue }
                    var beside = false
                    for c in cells {
                        if c == n {
                            beside = true
                            break
                        }
                        if c == cur { continue }
                        if abs(c.x - n.x) + abs(c.y - n.y) == 1 {
                            beside = true
                            break
                        }
                    }
                    if beside { continue }
                    cells.append(n)
                    cur = n
                    heading = d
                    placed = true
                    break
                }
                if !placed { break }
            }
            if cells.count < 2 {
                misses += 1
                continue
            }

            cells.reverse()
            let id = arrows.count
            for c in cells { owner[c.y * cols + c.x] = id }
            arrows.append(SlipOutArrow(id: id, cells: cells, dir: dir))
            filled += cells.count
        }
        return SlipOutLevel(cols: cols, rows: rows, arrows: arrows)
    }

    /// The nearest arrow in the way of this one and how many free cells come before it, or nil
    /// when its way out is clear. Arrows in `gone` have left the board.
    func blocker(for arrow: SlipOutArrow, gone: Set<Int>) -> (arrow: SlipOutArrow, free: Int)? {
        var best: SlipOutArrow? = nil
        var bestFree = Int.max
        for cell in arrow.cells {
            var x = cell.x + arrow.dir.dx
            var y = cell.y + arrow.dir.dy
            var steps = 0
            while x >= 0 && x < cols && y >= 0 && y < rows && steps < bestFree {
                for other in arrows {
                    if other.id == arrow.id || gone.contains(other.id) { continue }
                    var hit = false
                    for c in other.cells where c.x == x && c.y == y {
                        hit = true
                        break
                    }
                    if hit {
                        best = other
                        bestFree = steps
                        break
                    }
                }
                if bestFree == steps { break }
                steps += 1
                x += arrow.dir.dx
                y += arrow.dir.dy
            }
        }
        guard let found = best else { return nil }
        return (found, bestFree)
    }

    /// The arrow under a point on the board, in cells. Half a cell of slack around every arrow.
    func arrow(at x: Double, _ y: Double, gone: Set<Int>) -> SlipOutArrow? {
        var best: SlipOutArrow? = nil
        var bestDistance = 0.62
        for arrow in arrows {
            if gone.contains(arrow.id) { continue }
            for c in arrow.cells {
                let dx = Double(c.x) + 0.5 - x
                let dy = Double(c.y) + 0.5 - y
                let d = Swift.max(abs(dx), abs(dy))
                if d < bestDistance {
                    bestDistance = d
                    best = arrow
                }
            }
        }
        return best
    }
}

// MARK: - What is on screen

/// An arrow as the painter wants it.
struct SlipOutArrowFrame {
    var arrow: SlipOutArrow
    /// How far it has slid along its head direction, in cells.
    var offset: Double = 0
    /// 0...1: how red it is after a bump.
    var hot: Double = 0
    /// 0...1: the swell when it is let go.
    var swell: Double = 0
    var alpha: Double = 1
}

/// A short line of text rising from a point on the board.
struct SlipOutFloat {
    /// Board coordinates, in cells.
    var x: Double
    var y: Double
    var text: String
    /// Seconds since it appeared.
    var age: Double
}

/// One frame, as the painter wants it.
struct SlipOutFrame {
    var cols: Int = 6
    var rows: Int = 8
    var arrows: [SlipOutArrowFrame] = []
    var hearts: Int = 3
    /// Seconds since a heart was lost. Large when none was.
    var heartAge: Double = 10
    var level: Int = 1
    var score: Int = 0
    var clockText: String = "2:00"
    var clockUrgent: Bool = false
    var floats: [SlipOutFloat] = []
    /// Seconds since the level was cleared. nil while it is being played.
    var clearAge: Double? = nil
    /// Seconds since the level came up.
    var levelAge: Double = 10
    /// The one hint, with its strength.
    var hint: String? = nil
    var hintAlpha: Double = 0
    /// Seconds since the round ended. nil while it runs.
    var endAge: Double? = nil
    var endText: String = ""
}

// MARK: - The clip

/// The round the clip shows: one fixed level solved from the last arrow laid to the first, with
/// one bump along the way.
enum SlipOutClip {
    static let level = SlipOutLevel.make(index: 5, seed: 7)
    static let slideLength = 0.42
    static let bumpLength = 0.5
    static let restLength = 0.5

    static func frame(at phase: Double) -> SlipOutFrame {
        let p = phase.isFinite ? SlipOutMath.clamp(phase) : 0
        let all = level.arrows
        let n = all.count
        // The clip removes most of the arrows. Event k removes the next arrow; one event is a bump.
        let events = Swift.max(1, (n * 7) / 10)
        let bumpAt = Swift.max(1, (events * 8) / 10)
        let span = slideLength + restLength
        let time = p * Double(events + 1) * span
        let event = Swift.min(events, Int(time / span))
        let within = time - Double(event) * span

        var frame = SlipOutFrame()
        frame.cols = level.cols
        frame.rows = level.rows
        frame.level = 6
        frame.levelAge = 10
        frame.hearts = (event > bumpAt || (event == bumpAt && within > 0.2)) ? 2 : 3
        frame.heartAge = event == bumpAt ? Swift.max(0, within - 0.2) : 10
        frame.clockText = clock(96 - Int(time))

        // Arrows already gone are the last ones in placement order, skipping the bump event.
        var gone = Set<Int>()
        var pointer = n - 1
        for k in 0..<event {
            if k == bumpAt { continue }
            if pointer >= 0 { gone.insert(all[pointer].id) }
            pointer -= 1
        }
        frame.score = 31 + gone.count
        let current: SlipOutArrow? = pointer >= 0 ? all[pointer] : nil

        for arrow in all {
            if gone.contains(arrow.id) { continue }
            var item = SlipOutArrowFrame(arrow: arrow)
            if let sliding = current, sliding.id == arrow.id, event < events, event != bumpAt {
                let t = SlipOutMath.clamp(within / slideLength)
                if within >= slideLength { continue }
                item.offset = SlipOutMath.easeIn(t) * arrow.exitDistance(cols: level.cols, rows: level.rows)
                item.swell = Swift.max(0, 1 - within / 0.25)
            }
            frame.arrows.append(item)
        }

        if event == bumpAt, let blocked = blockedArrow(gone: gone) {
            let t = SlipOutMath.clamp(within / bumpLength)
            for k in frame.arrows.indices where frame.arrows[k].arrow.id == blocked.arrow.id {
                frame.arrows[k].offset = (Double(blocked.free) + 0.38) * sin(.pi * SlipOutMath.clamp(t * 1.4))
                frame.arrows[k].hot = 1 - SlipOutMath.smooth(0.45, 1, t)
            }
        }

        // The float left by the arrow that went in the event before.
        if event > 0, event - 1 != bumpAt, within < 0.9, pointer + 1 < n {
            let head = all[pointer + 1].head
            frame.floats.append(SlipOutFloat(x: Double(head.x) + 0.5, y: Double(head.y) + 0.5, text: "+1", age: within + 0.1))
        }
        return frame
    }

    /// An arrow still down whose way out is blocked, with the free cells before the block.
    private static func blockedArrow(gone: Set<Int>) -> (arrow: SlipOutArrow, free: Int)? {
        for arrow in level.arrows {
            if gone.contains(arrow.id) { continue }
            if let block = level.blocker(for: arrow, gone: gone) { return (arrow, block.free) }
        }
        return nil
    }

    static func clock(_ seconds: Int) -> String {
        let s = Swift.max(0, seconds)
        let m = s / 60
        let r = s % 60
        return r < 10 ? "\(m):0\(r)" : "\(m):\(r)"
    }
}

// MARK: - Pictures

/// The images, resolved once per frame.
struct SlipOutArt {
    let backdrop: GraphicsContext.ResolvedImage
    /// Arrowheads, pointing up.
    let head: GraphicsContext.ResolvedImage
    let headHot: GraphicsContext.ResolvedImage
    let heart: GraphicsContext.ResolvedImage
    let heartOff: GraphicsContext.ResolvedImage
    let medal: GraphicsContext.ResolvedImage

    init(_ ctx: GraphicsContext) {
        backdrop = ctx.resolve(Image("slip-out-backdrop"))
        head = ctx.resolve(Image("slip-out-head"))
        headHot = ctx.resolve(Image("slip-out-head-hot"))
        heart = ctx.resolve(Image("slip-out-heart"))
        heartOff = ctx.resolve(Image("slip-out-heart-off"))
        medal = ctx.resolve(Image("slip-out-medal"))
    }
}

// MARK: - Painter

struct SlipOutPainter {
    typealias M = SlipOutMath

    let W: Double
    let H: Double
    /// Design points: 1 on a 402 x 874 phone.
    let u: Double
    let frame: SlipOutFrame
    let showHUD: Bool

    /// Side of one cell, in points.
    let cell: Double
    /// Top left of the board.
    let ox: Double
    let oy: Double
    let boardW: Double
    let boardH: Double

    init(size: CGSize, frame: SlipOutFrame, showHUD: Bool) {
        W = Double(size.width)
        H = Double(size.height)
        u = Swift.min(W / 402, H / 874)
        self.frame = frame
        self.showHUD = showHUD

        let top: Double = showHUD ? Double(GameLayout.topBand) + 48 * u : 40 * u
        let bottom: Double = H - Double(GameLayout.bottomInset) - 30 * u
        let side: Double = 28 * u
        let cols = Double(Swift.max(1, frame.cols))
        let rows = Double(Swift.max(1, frame.rows))
        cell = Swift.min((W - 2 * side) / cols, (bottom - top) / rows, 48 * u)
        boardW = cell * cols
        boardH = cell * rows
        ox = (W - boardW) / 2
        oy = top + (bottom - top - boardH) / 2
    }

    // MARK: Helpers

    func point(_ x: Double, _ y: Double) -> CGPoint {
        CGPoint(x: ox + x * cell, y: oy + y * cell)
    }

    func centre(_ c: SlipOutCell) -> CGPoint {
        point(Double(c.x) + 0.5, Double(c.y) + 0.5)
    }

    /// Screen point to board cells.
    func board(_ p: CGPoint) -> (x: Double, y: Double) {
        ((Double(p.x) - ox) / cell, (Double(p.y) - oy) / cell)
    }

    func label(_ ctx: inout GraphicsContext, _ words: String, size: Double, weight: Font.Weight,
               design: Font.Design = .rounded, tracking: Double = 0, color: Color,
               at p: CGPoint, anchor: UnitPoint = .center) {
        let text = Text(words).font(.system(size: size, weight: weight, design: design)).tracking(tracking).foregroundColor(color)
        ctx.draw(text, at: p, anchor: anchor)
    }

    /// An image at a rect, faded by alpha.
    private func image(_ ctx: inout GraphicsContext, _ art: GraphicsContext.ResolvedImage, in rect: CGRect, alpha: Double = 1) {
        if alpha <= 0.001 { return }
        let before = ctx.opacity
        ctx.opacity = before * Swift.min(1, alpha)
        ctx.draw(art, in: rect)
        ctx.opacity = before
    }

    // MARK: Frame

    func draw(_ ctx: inout GraphicsContext) {
        let art = SlipOutArt(ctx)
        // The backdrop fills the screen, cropped at the sides or the ends.
        let size = art.backdrop.size
        let fill = Swift.max(W / Swift.max(1, Double(size.width)), H / Swift.max(1, Double(size.height)))
        let w = Double(size.width) * fill
        let h = Double(size.height) * fill
        ctx.draw(art.backdrop, in: CGRect(x: (W - w) / 2, y: (H - h) / 2, width: w, height: h))
        drawDots(&ctx)
        drawArrows(&ctx, art)
        drawFloats(&ctx)
        drawClear(&ctx, art)
        if showHUD { drawHUD(&ctx, art) }
        drawEnd(&ctx)
    }

    private func drawDots(_ ctx: inout GraphicsContext) {
        let r = Swift.max(1, 1.6 * u)
        let fade = 1 - M.smooth(0, 0.6, frame.endAge ?? 0)
        let rise = M.easeOut(frame.levelAge / 0.4)
        var dots = Path()
        for y in 0...frame.rows {
            for x in 0...frame.cols {
                let p = point(Double(x), Double(y))
                dots.addEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
            }
        }
        ctx.fill(dots, with: .color(SlipOutInk.dot.opacity(fade * (0.4 + 0.6 * rise))))
    }

    /// The path of an arrow: through the cell centres, out to the tip of the head.
    func arrowPath(_ arrow: SlipOutArrow, shift: Double) -> Path {
        let sx = Double(arrow.dir.dx) * shift * cell
        let sy = Double(arrow.dir.dy) * shift * cell
        var path = Path()
        for (k, c) in arrow.cells.enumerated() {
            let p = centre(c)
            let q = CGPoint(x: p.x + sx, y: p.y + sy)
            if k == 0 { path.move(to: q) } else { path.addLine(to: q) }
        }
        let head = centre(arrow.head)
        let reach = 0.12 * cell
        path.addLine(to: CGPoint(x: head.x + sx + Double(arrow.dir.dx) * reach, y: head.y + sy + Double(arrow.dir.dy) * reach))
        return path
    }

    /// The arrowhead picture, its tip 0.36 of a cell past the head cell's centre.
    private func drawHead(_ ctx: inout GraphicsContext, _ arrow: SlipOutArrow, shift: Double, art: SlipOutArt,
                          hot: Double, alpha: Double) {
        let head = centre(arrow.head)
        let dx = Double(arrow.dir.dx)
        let dy = Double(arrow.dir.dy)
        let reach = shift * cell + 0.36 * cell
        var local = ctx
        local.translateBy(x: head.x + dx * reach, y: head.y + dy * reach)
        local.rotate(by: .degrees(Double(arrow.dir.rawValue) * 90))
        let w = 0.66 * cell
        let h = w * Double(art.head.size.height) / Swift.max(1, Double(art.head.size.width))
        let rect = CGRect(x: -w / 2, y: 0, width: w, height: h)
        if hot < 0.999 { image(&local, art.head, in: rect, alpha: alpha) }
        if hot > 0.001 { image(&local, art.headHot, in: rect, alpha: alpha * hot) }
    }

    private func drawArrows(_ ctx: inout GraphicsContext, _ art: SlipOutArt) {
        let fade = 1 - M.smooth(0, 0.6, frame.endAge ?? 0)
        let width = Swift.max(2.5, cell * 0.15)
        let style = StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)

        // Anything sliding is clipped to a little beyond the board, so it leaves cleanly.
        var inner = ctx
        let margin = cell * 0.9
        inner.clip(to: Path(CGRect(x: ox - margin, y: oy - margin, width: boardW + 2 * margin, height: boardH + 2 * margin)))

        for item in frame.arrows {
            var alpha = item.alpha * fade
            if alpha <= 0.01 { continue }
            // A new level's arrows come up one after another from the top.
            if frame.levelAge < 0.7 {
                let order = Double(item.arrow.head.y) / Double(Swift.max(1, frame.rows))
                alpha *= M.easeOut((frame.levelAge - order * 0.25) / 0.3)
                if alpha <= 0.01 { continue }
            }
            let inkColor: Color = item.hot > 0.01 ? Self.mixRed(item.hot) : SlipOutInk.ink
            let color = inkColor.opacity(alpha)
            let line = arrowPath(item.arrow, shift: item.offset)
            if item.swell > 0.01 {
                // A soft wider stroke around an arrow just let go.
                let soft = StrokeStyle(lineWidth: width * (1 + 2.6 * item.swell), lineCap: .round, lineJoin: .round)
                inner.stroke(line, with: .color(inkColor.opacity(alpha * 0.16 * item.swell)), style: soft)
            }
            inner.stroke(line, with: .color(color), style: style)
            drawHead(&inner, item.arrow, shift: item.offset, art: art, hot: item.hot, alpha: alpha)
        }
    }

    private static func mixRed(_ k: Double) -> Color {
        let t = M.clamp(k)
        return Color(.sRGB, red: M.lerp(0.082, 0.910, t), green: M.lerp(0.078, 0.314, t), blue: M.lerp(0.071, 0.247, t), opacity: 1)
    }

    private func drawFloats(_ ctx: inout GraphicsContext) {
        for item in frame.floats {
            let life = M.clamp(item.age / 0.9)
            if life >= 1 { continue }
            let alpha = M.easeOut(item.age / 0.12) * (1 - M.smooth(0.55, 1, life))
            let p = point(item.x, item.y)
            let y = Double(p.y) - 14 * u - 34 * u * M.easeOut(life)
            let size = (15 + 3 * M.pop(item.age / 0.3)) * u
            label(&ctx, item.text, size: size, weight: .heavy, color: SlipOutInk.green.opacity(alpha),
                  at: CGPoint(x: Double(p.x), y: y))
        }
    }

    /// The check and the word when a level is cleared.
    private func drawClear(_ ctx: inout GraphicsContext, _ art: SlipOutArt) {
        guard let age = frame.clearAge else { return }
        let cx = ox + boardW / 2
        let cy = oy + boardH * 0.46
        let arrive = M.pop(age / 0.35)
        let alpha = 1 - M.smooth(0.95, 1.25, age)
        if alpha <= 0.01 { return }
        let r = 46 * u * arrive
        if r > 0.5 {
            image(&ctx, art.medal, in: CGRect(x: cx - r * 1.12, y: cy - r * 1.12, width: 2.24 * r, height: 2.24 * r), alpha: alpha)
            // The check draws itself in.
            let drawn = M.easeOut((age - 0.1) / 0.3)
            if drawn > 0.01 {
                let a = CGPoint(x: cx - 18 * u, y: cy + 1 * u)
                let b = CGPoint(x: cx - 6 * u, y: cy + 13 * u)
                let c = CGPoint(x: cx + 20 * u, y: cy - 13 * u)
                var tick = Path()
                tick.move(to: a)
                if drawn < 0.4 {
                    let k = drawn / 0.4
                    tick.addLine(to: CGPoint(x: a.x + (b.x - a.x) * k, y: a.y + (b.y - a.y) * k))
                } else {
                    tick.addLine(to: b)
                    let k = (drawn - 0.4) / 0.6
                    tick.addLine(to: CGPoint(x: b.x + (c.x - b.x) * k, y: b.y + (c.y - b.y) * k))
                }
                ctx.stroke(tick, with: .color(Color.white.opacity(alpha)),
                           style: StrokeStyle(lineWidth: 6 * u, lineCap: .round, lineJoin: .round))
            }
        }
        let wordAlpha = M.easeOut((age - 0.15) / 0.25) * alpha
        if wordAlpha > 0.01 {
            label(&ctx, "Clear", size: 26 * u, weight: .black, tracking: 1.5 * u, color: SlipOutInk.ink.opacity(wordAlpha),
                  at: CGPoint(x: cx, y: cy + 78 * u))
        }
    }

    // MARK: HUD

    private func drawHUD(_ ctx: inout GraphicsContext, _ art: SlipOutArt) {
        let cx = W / 2
        let topLine = Double(GameLayout.statusBarHeight)
        let bandBottom = Double(GameLayout.topBand)
        // Between the app's two corners: the level above, the hearts below.
        label(&ctx, "LEVEL \(frame.level)", size: 11.5 * u, weight: .bold, tracking: 2 * u, color: SlipOutInk.inkSoft,
              at: CGPoint(x: cx, y: topLine + 10 * u))

        let r = 9.5 * u
        let gap = 26 * u
        let y = topLine + 31 * u
        for k in 0..<3 {
            let x = cx + Double(k - 1) * gap
            var scale = 1.0
            var shake = 0.0
            var full = k < frame.hearts
            if k == frame.hearts, frame.heartAge < 0.6 {
                // The heart just lost swells, shakes and goes grey.
                let t = frame.heartAge / 0.6
                scale = 1 + 0.4 * (1 - t)
                shake = sin(frame.heartAge * 70) * 3 * u * (1 - t)
                full = t < 0.55
            }
            let side = 2.3 * r * scale
            ctx.draw(full ? art.heart : art.heartOff, in: CGRect(x: x + shake - side / 2, y: y - side / 2, width: side, height: side))
        }

        // The clock and the score sit under the band, over the board.
        let rowY = bandBottom + 20 * u
        label(&ctx, frame.clockText, size: 15 * u, weight: .bold, design: .monospaced,
              color: frame.clockUrgent ? SlipOutInk.red : SlipOutInk.inkSoft, at: CGPoint(x: ox + 2 * u, y: rowY), anchor: .leading)
        label(&ctx, "\(frame.score)", size: 15 * u, weight: .heavy, color: SlipOutInk.ink,
              at: CGPoint(x: ox + boardW - 2 * u, y: rowY), anchor: .trailing)

        if let hint = frame.hint, frame.hintAlpha > 0.01 {
            let hintY = H - Double(GameLayout.bottomInset) - 14 * u
            label(&ctx, hint, size: 15 * u, weight: .semibold, color: SlipOutInk.inkSoft.opacity(frame.hintAlpha),
                  at: CGPoint(x: cx, y: hintY))
        }
    }

    private func drawEnd(_ ctx: inout GraphicsContext) {
        guard let age = frame.endAge, !frame.endText.isEmpty else { return }
        let alpha = M.easeOut((age - 0.2) / 0.35)
        if alpha <= 0.01 { return }
        let cx = W / 2
        let cy = oy + boardH * 0.46
        let scale = 0.9 + 0.1 * M.pop((age - 0.2) / 0.4)
        label(&ctx, frame.endText, size: 30 * u * scale, weight: .black, tracking: 0.5 * u,
              color: SlipOutInk.ink.opacity(alpha), at: CGPoint(x: cx, y: cy))
        label(&ctx, "\(frame.score) arrows out", size: 15 * u, weight: .semibold,
              color: SlipOutInk.inkSoft.opacity(alpha), at: CGPoint(x: cx, y: cy + 30 * u))
    }
}
