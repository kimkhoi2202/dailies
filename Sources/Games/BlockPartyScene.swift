import SwiftUI

// Block Party: fit pieces on an 8 x 8 board and clear full rows and columns.
//
// Everything is painted into one Canvas by BlockPartyPainter from a BlockPartyFrame. The clip in the
// video feed builds a frame from a phase (0...1) and a fixed script; the playable game builds one
// from its live state. The pictures are the block-party-* images in Resources/GameArt; any frame size.

public struct BlockPartyScene: View {
    public var phase: Double
    public var showHUD: Bool

    public init(phase: Double, showHUD: Bool) {
        self.phase = phase
        self.showHUD = showHUD
    }

    public var body: some View {
        Canvas(opaque: true, colorMode: .nonLinear, rendersAsynchronously: false) { context, size in
            if size.width <= 8 || size.height <= 8 { return }
            let layout = BlockPartyLayout(size: size)
            let frame = BlockPartyClip.frame(phase: phase, layout: layout, showHUD: showHUD)
            BlockPartyPainter(layout: layout, frame: frame).draw(&context)
        }
    }
}

// MARK: - Numbers

enum BlockPartyMath {
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

    static func easeInOut(_ v: Double) -> Double {
        let k = clamp(v)
        return k < 0.5 ? 2 * k * k : 1 - 2 * (1 - k) * (1 - k)
    }

    /// Overshoots a little before settling, for pops.
    static func easeOutBack(_ v: Double) -> Double {
        let k = clamp(v) - 1
        return 1 + k * k * (2.7 * k + 1.7)
    }
}

/// SplitMix64. The round and the scripted player use different salts so they never share a sequence.
struct BlockPartyRandom {
    static let round: UInt64 = 0x3C6EF372FE94F82A
    static let pilot: UInt64 = 0x9E3779B97F4A7C15

    private var state: UInt64

    init(seed: UInt64, salt: UInt64 = BlockPartyRandom.round) {
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

struct BlockPartyTint {
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

    static let white = BlockPartyTint(1, 1, 1)
    static let black = BlockPartyTint(0, 0, 0)

    func mix(_ other: BlockPartyTint, _ k: Double) -> BlockPartyTint {
        BlockPartyTint(r + (other.r - r) * k, g + (other.g - g) * k, b + (other.b - b) * k)
    }

    func color(_ alpha: Double = 1) -> Color { Color(.sRGB, red: r, green: g, blue: b, opacity: alpha) }
}

enum BlockPartyPalette {
    /// Block colours, 1 based: 0 is an empty cell.
    static let blocks: [BlockPartyTint] = [
        0x000000, 0xFF6B6B, 0xFFA23A, 0xFFD93D, 0x7BE27A, 0x3DD6C0, 0x4FB6FF, 0xA06BFF, 0xFF6FB5
    ].map { BlockPartyTint(hex: $0) }

    static let shadow = BlockPartyTint(hex: 0x0C0820)
    static let gold = BlockPartyTint(hex: 0xF5B301)

    static func block(_ index: Int) -> BlockPartyTint {
        blocks[Swift.max(0, Swift.min(blocks.count - 1, index))]
    }
}

// MARK: - Pieces

struct BlockPartyCell: Equatable {
    var x: Int
    var y: Int
}

/// One piece: its cells from its top left corner, its size and its colour.
struct BlockPartyShape: Equatable {
    let cells: [BlockPartyCell]
    let w: Int
    let h: Int
    let color: Int
    let weight: Double

    init(_ rows: [String], color: Int, weight: Double) {
        var found: [BlockPartyCell] = []
        var width = 0
        for (y, row) in rows.enumerated() {
            var x = 0
            for ch in row {
                if ch == "#" { found.append(BlockPartyCell(x: x, y: y)) }
                x += 1
            }
            width = Swift.max(width, x)
        }
        cells = found
        w = width
        h = rows.count
        self.color = color
        self.weight = weight
    }

    static let dot = BlockPartyShape(["#"], color: 8, weight: 2)
    static let bar2 = BlockPartyShape(["##"], color: 3, weight: 3)
    static let post2 = BlockPartyShape(["#", "#"], color: 3, weight: 3)
    static let bar3 = BlockPartyShape(["###"], color: 4, weight: 3)
    static let post3 = BlockPartyShape(["#", "#", "#"], color: 4, weight: 3)
    static let bar4 = BlockPartyShape(["####"], color: 6, weight: 2)
    static let post4 = BlockPartyShape(["#", "#", "#", "#"], color: 6, weight: 2)
    static let bar5 = BlockPartyShape(["#####"], color: 6, weight: 1)
    static let post5 = BlockPartyShape(["#", "#", "#", "#", "#"], color: 6, weight: 1)
    static let square = BlockPartyShape(["##", "##"], color: 1, weight: 4)
    static let bigSquare = BlockPartyShape(["###", "###", "###"], color: 7, weight: 1)
    static let brick = BlockPartyShape(["###", "###"], color: 1, weight: 1)
    static let tallBrick = BlockPartyShape(["##", "##", "##"], color: 1, weight: 1)
    static let corner1 = BlockPartyShape(["#.", "##"], color: 5, weight: 2)
    static let corner2 = BlockPartyShape([".#", "##"], color: 5, weight: 2)
    static let corner3 = BlockPartyShape(["##", "#."], color: 5, weight: 2)
    static let corner4 = BlockPartyShape(["##", ".#"], color: 5, weight: 2)
    static let hook1 = BlockPartyShape(["#..", "###"], color: 2, weight: 1.5)
    static let hook2 = BlockPartyShape(["..#", "###"], color: 2, weight: 1.5)
    static let hook3 = BlockPartyShape(["###", "#.."], color: 2, weight: 1.5)
    static let hook4 = BlockPartyShape(["###", "..#"], color: 2, weight: 1.5)
    static let hook5 = BlockPartyShape(["##", "#.", "#."], color: 2, weight: 1.5)
    static let hook6 = BlockPartyShape(["##", ".#", ".#"], color: 2, weight: 1.5)
    static let hook7 = BlockPartyShape(["#.", "#.", "##"], color: 2, weight: 1.5)
    static let hook8 = BlockPartyShape([".#", ".#", "##"], color: 2, weight: 1.5)
    static let tee1 = BlockPartyShape(["###", ".#."], color: 7, weight: 1.5)
    static let tee2 = BlockPartyShape([".#.", "###"], color: 7, weight: 1.5)
    static let tee3 = BlockPartyShape(["#.", "##", "#."], color: 7, weight: 1.5)
    static let tee4 = BlockPartyShape([".#", "##", ".#"], color: 7, weight: 1.5)
    static let step1 = BlockPartyShape(["##.", ".##"], color: 8, weight: 1)
    static let step2 = BlockPartyShape([".##", "##."], color: 8, weight: 1)
    static let step3 = BlockPartyShape(["#.", "##", ".#"], color: 8, weight: 1)
    static let step4 = BlockPartyShape([".#", "##", "#."], color: 8, weight: 1)

    static let catalog: [BlockPartyShape] = [
        dot, bar2, post2, bar3, post3, bar4, post4, bar5, post5, square, bigSquare, brick, tallBrick,
        corner1, corner2, corner3, corner4, hook1, hook2, hook3, hook4, hook5, hook6, hook7, hook8,
        tee1, tee2, tee3, tee4, step1, step2, step3, step4
    ]

    static let totalWeight: Double = catalog.reduce(0.0) { $0 + $1.weight }

    /// A piece drawn from the catalog, common ones more often. The same seed always deals the same run.
    static func deal(_ rng: inout BlockPartyRandom) -> BlockPartyShape {
        var pick = rng.next() * totalWeight
        for shape in catalog {
            pick -= shape.weight
            if pick < 0 { return shape }
        }
        return catalog[catalog.count - 1]
    }
}

/// A cell that just cleared: a burst of sparks drawn from its age alone.
struct BlockPartyBurst {
    /// In cells, the centre of the cell that cleared.
    var x: Double
    var y: Double
    var color: Int
    /// Seconds since the clear. Past the life it is not drawn.
    var age: Double
    static let life = 0.8
}

/// A score that floats up and fades.
struct BlockPartyFloat {
    var text: String
    /// In cells.
    var x: Double
    var y: Double
    var color: Int
    var age: Double
    static let life = 1.0
}

// MARK: - Layout

/// Where everything sits on a screen of the given size, in points.
struct BlockPartyLayout: Equatable {
    static let trayScale = 0.62

    let size: CGSize
    let W: Double
    let H: Double
    /// Design points: 1 on a 402 x 874 phone.
    let u: Double
    let cell: Double
    let boardX: Double
    let boardY: Double
    var boardSide: Double { cell * 8 }
    var boardRect: CGRect { CGRect(x: boardX, y: boardY, width: boardSide, height: boardSide) }
    /// Centre line of the tray.
    let trayY: Double
    let slotWidth: Double
    /// How far above the finger a lifted piece floats.
    let lift: Double
    let bestY: Double
    let scoreY: Double
    let hintY: Double

    init(size: CGSize) {
        self.size = size
        W = Double(size.width)
        H = Double(size.height)
        u = Swift.min(W / 402, H / 874)
        let top = Double(GameLayout.topBand) + 64 * u
        let bottom = H - Double(GameLayout.bottomInset) - 30 * u
        cell = Swift.max(10, Swift.min((W - 40 * u) / 8, (bottom - top - 60 * u) / 10.4))
        let content = cell * 8 + 26 * u + cell * 2.2 + 44 * u
        let slack = Swift.max(0, bottom - top - content)
        boardY = top + slack * 0.42
        boardX = (W - cell * 8) / 2
        trayY = boardY + cell * 8 + 26 * u + cell * 1.1
        slotWidth = cell * 8 / 3
        lift = cell * 1.3 + 30 * u
        bestY = Double(GameLayout.statusBarHeight) + 24
        scoreY = Double(GameLayout.topBand) + 30 * u
        hintY = trayY + cell * 1.15 + 24 * u
    }

    func slotCenter(_ slot: Int) -> CGPoint {
        CGPoint(x: boardX + slotWidth * (Double(slot) + 0.5), y: trayY)
    }

    /// The tray slot under a touch, if any.
    func slot(at p: CGPoint) -> Int? {
        let x = Double(p.x)
        let y = Double(p.y)
        if y < trayY - cell * 1.6 || y > trayY + cell * 1.6 { return nil }
        if x < boardX - 12 * u || x > boardX + boardSide + 12 * u { return nil }
        return Swift.max(0, Swift.min(2, Int((x - boardX) / slotWidth)))
    }

    /// The centre of a piece held above the finger. k is 0...1 as the piece rises.
    func heldCenter(finger: CGPoint, lift k: Double) -> CGPoint {
        CGPoint(x: Double(finger.x), y: Double(finger.y) - lift * k)
    }

    /// The top left cell a piece of this size would land on, given its centre in points. May be off the board.
    func landing(of shape: BlockPartyShape, center: CGPoint) -> (col: Int, row: Int) {
        let x = (Double(center.x) - Double(shape.w) * cell / 2 - boardX) / cell
        let y = (Double(center.y) - Double(shape.h) * cell / 2 - boardY) / cell
        return (col: Int(x.rounded()), row: Int(y.rounded()))
    }

    /// The centre, in points, of a piece landed at a cell.
    func center(of shape: BlockPartyShape, col: Int, row: Int) -> CGPoint {
        CGPoint(x: boardX + (Double(col) + Double(shape.w) / 2) * cell,
                y: boardY + (Double(row) + Double(shape.h) / 2) * cell)
    }

    func point(cellX: Double, cellY: Double) -> CGPoint {
        CGPoint(x: boardX + cellX * cell, y: boardY + cellY * cell)
    }
}

// MARK: - One frame

/// Everything the painter needs for one picture.
struct BlockPartyFrame {
    /// 64 cells, row by row. 0 is empty, else a palette index.
    var grid: [Int] = Array(repeating: 0, count: 64)
    /// Seconds since each cell was placed, for the landing pop. Large when old.
    var placedAge: [Double] = Array(repeating: 9, count: 64)
    /// Seconds since each cell cleared, for the flash. Large when old.
    var flash: [Double] = Array(repeating: 9, count: 64)
    var tray: [BlockPartyShape?] = [nil, nil, nil]
    /// Seconds since each slot was dealt.
    var trayAge: [Double] = [9, 9, 9]
    /// The slot being dragged. Its piece is drawn in the air, not in the tray.
    var dragSlot: Int? = nil
    var dragShape: BlockPartyShape? = nil
    var dragCenter: CGPoint = .zero
    /// 0...1 as the piece grows from tray size to full size.
    var dragLift: Double = 0
    var ghostCol = 0
    var ghostRow = 0
    var ghostValid = false
    /// Bits 0...7: rows that would clear. Bits 8...15: columns.
    var ghostLines: UInt16 = 0
    /// A piece on its way back to its slot after a drop that did not fit.
    var returnShape: BlockPartyShape? = nil
    var returnFrom: CGPoint = .zero
    var returnSlot = 0
    var returnAge = 0.0
    var bursts: [BlockPartyBurst] = []
    var floats: [BlockPartyFloat] = []
    var score = 0
    var best = 0
    /// Seconds since the score last changed.
    var scoreAge = 9.0
    var note: String? = nil
    var noteAge = 0.0
    var praise: String? = nil
    var praiseAge = 0.0
    var hint: String? = nil
    var hintAlpha = 0.0
    var ambient = 0.0
    /// Seconds since the round ended. Negative while it is on.
    var endClock = -1.0
    var showHUD = true
}

/// The moment the clip shows: a square lands and clears two rows.
enum BlockPartyClip {
    private static let rows: [String] = [
        "00000000",
        "77000000",
        "77000033",
        "44400033",
        "41100066",
        "22100556",
        "22800556",
        "88801111"
    ]

    static let grid: [Int] = {
        var cells: [Int] = []
        cells.reserveCapacity(64)
        for row in rows {
            for ch in row { cells.append(Int(String(ch)) ?? 0) }
        }
        return cells
    }()

    static func frame(phase raw: Double, layout: BlockPartyLayout, showHUD: Bool) -> BlockPartyFrame {
        let p = raw.isFinite ? BlockPartyMath.clamp(raw) : 0
        var f = BlockPartyFrame()
        f.showHUD = showHUD
        f.best = 2680
        f.score = 785
        f.ambient = p * 8
        f.grid = grid
        f.tray = [BlockPartyShape.corner2, BlockPartyShape.bar3, BlockPartyShape.square]
        f.trayAge = [9, 9, 9]

        let shape = BlockPartyShape.square
        let col = 3
        let row = 5
        let liftStart = 0.26
        let land = 0.70
        if p < liftStart { return f }

        if p < land {
            // The square rises out of its slot and travels to the gap.
            let k = BlockPartyMath.easeInOut((p - liftStart) / (land - liftStart - 0.06))
            let from = layout.slotCenter(2)
            let to = layout.center(of: shape, col: col, row: row)
            let arc = sin(k * Double.pi) * 22 * layout.u
            f.dragSlot = 2
            f.dragShape = shape
            f.dragLift = BlockPartyMath.smooth(liftStart, liftStart + 0.05, p)
            f.dragCenter = CGPoint(x: BlockPartyMath.lerp(Double(from.x), Double(to.x), k) + arc,
                                   y: BlockPartyMath.lerp(Double(from.y), Double(to.y), k))
            if k > 0.55 {
                f.ghostCol = col
                f.ghostRow = row
                f.ghostValid = true
                f.ghostLines = (1 << 5) | (1 << 6)
            }
            return f
        }

        // Landed: rows 5 and 6 are gone, the sparks fly and the score counts up.
        let since = (p - land) * 4
        f.tray[2] = nil
        f.trayAge[2] = 9
        for r in 5...6 {
            for c in 0..<8 {
                let was = grid[r * 8 + c]
                f.grid[r * 8 + c] = 0
                f.flash[r * 8 + c] = since
                f.bursts.append(BlockPartyBurst(x: Double(c) + 0.5, y: Double(r) + 0.5,
                                                color: was == 0 ? 1 : was, age: since))
            }
        }
        f.score = 785 + Int(440 * BlockPartyMath.easeOut(since / 0.7))
        f.scoreAge = since
        f.floats = [BlockPartyFloat(text: "+440", x: 4, y: 6, color: 1, age: since)]
        f.note = "Combo x2"
        f.noteAge = since
        f.praise = "Great"
        f.praiseAge = since
        return f
    }
}

// MARK: - Pictures

/// The images, resolved once per frame.
struct BlockPartyArt {
    let backdrop: GraphicsContext.ResolvedImage
    let board: GraphicsContext.ResolvedImage
    let cell: GraphicsContext.ResolvedImage
    let crown: GraphicsContext.ResolvedImage
    /// One per palette index, 1 based like the palette: index 0 is unused.
    let blocks: [GraphicsContext.ResolvedImage]
    let grey: GraphicsContext.ResolvedImage

    init(_ ctx: GraphicsContext) {
        backdrop = ctx.resolve(Image("block-party-backdrop"))
        board = ctx.resolve(Image("block-party-board"))
        cell = ctx.resolve(Image("block-party-cell"))
        crown = ctx.resolve(Image("block-party-crown"))
        blocks = (0..<BlockPartyPalette.blocks.count).map { ctx.resolve(Image("block-party-block-\(Swift.max(1, $0))")) }
        grey = ctx.resolve(Image("block-party-block-grey"))
    }

    func block(_ index: Int) -> GraphicsContext.ResolvedImage {
        blocks[Swift.max(1, Swift.min(blocks.count - 1, index))]
    }
}

// MARK: - Painter

struct BlockPartyPainter {
    typealias M = BlockPartyMath
    typealias P = BlockPartyPalette

    let L: BlockPartyLayout
    let f: BlockPartyFrame
    var u: Double { L.u }
    var cell: Double { L.cell }

    init(layout: BlockPartyLayout, frame: BlockPartyFrame) {
        L = layout
        f = frame
    }

    func draw(_ ctx: inout GraphicsContext) {
        let art = BlockPartyArt(ctx)
        drawBackground(&ctx, art)
        drawBoard(&ctx, art)
        drawGhost(&ctx, art)
        drawBlocks(&ctx, art)
        drawFlashes(&ctx)
        drawBursts(&ctx)
        drawTray(&ctx, art)
        drawReturning(&ctx, art)
        drawHeld(&ctx, art)
        drawFloats(&ctx)
        if f.showHUD { drawHUD(&ctx, art) }
    }

    /// An image at a rect, faded by alpha.
    private func image(_ ctx: inout GraphicsContext, _ art: GraphicsContext.ResolvedImage, in rect: CGRect, alpha: Double = 1) {
        if alpha <= 0.001 { return }
        if alpha >= 0.999 {
            ctx.draw(art, in: rect)
            return
        }
        let before = ctx.opacity
        ctx.opacity = before * alpha
        ctx.draw(art, in: rect)
        ctx.opacity = before
    }

    // MARK: Background and board

    /// Stretches an image over a rect the nine-slice way: the outer `cap` share of the image on
    /// each side keeps its proportions at `edge` points, only the middle stretches.
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
            if dx[i + 1] - dx[i] <= 0.01 { continue }
            let scaleX = (dx[i + 1] - dx[i]) / (sx[i + 1] - sx[i])
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

    private func drawBackground(_ ctx: inout GraphicsContext, _ art: BlockPartyArt) {
        // The backdrop fills the screen, cropped at the sides or the ends.
        let size = art.backdrop.size
        let fill = Swift.max(L.W / Swift.max(1, Double(size.width)), L.H / Swift.max(1, Double(size.height)))
        let w = Double(size.width) * fill
        let h = Double(size.height) * fill
        ctx.draw(art.backdrop, in: CGRect(x: (L.W - w) / 2, y: (L.H - h) / 2, width: w, height: h))

        // Faint tiles drift up behind everything, so the screen is never still.
        let tile = 46 * u
        let drift = (f.ambient * 6 * u).truncatingRemainder(dividingBy: tile * 2)
        var y = -tile * 2 + drift
        var rowIndex = 0
        while y < L.H {
            var x = rowIndex % 2 == 0 ? 0.0 : tile
            while x < L.W {
                let r = CGRect(x: x + 4 * u, y: y + 4 * u, width: tile - 8 * u, height: tile - 8 * u)
                ctx.fill(Path(roundedRect: r, cornerRadius: 6 * u), with: .color(Color.white.opacity(0.025)))
                x += tile * 2
            }
            y += tile
            rowIndex += 1
        }
    }

    private func drawBoard(_ ctx: inout GraphicsContext, _ art: BlockPartyArt) {
        let board = L.boardRect.insetBy(dx: -10 * u, dy: -10 * u)
        let shadow = board.offsetBy(dx: 0, dy: 6 * u)
        ctx.fill(Path(roundedRect: shadow, cornerRadius: 16 * u), with: .color(P.shadow.color(0.55)))
        // The panel's rim is a little under a tenth of the picture: keep it 10 points wide around the cells.
        sliced(&ctx, art.board, in: board, cap: 0.1, edge: 14.3 * u)

        let gap = Swift.max(1, 1.4 * u)
        for r in 0..<8 {
            for c in 0..<8 {
                ctx.draw(art.cell, in: cellRect(c, r).insetBy(dx: gap, dy: gap))
            }
        }
    }

    private func cellRect(_ c: Int, _ r: Int) -> CGRect {
        CGRect(x: L.boardX + Double(c) * cell, y: L.boardY + Double(r) * cell, width: cell, height: cell)
    }

    // MARK: Blocks

    /// One block of a palette colour. grey 0...1 turns it to stone.
    private func drawBlock(_ ctx: inout GraphicsContext, _ art: BlockPartyArt, _ rect: CGRect, color: Int,
                           grey: Double = 0, alpha: Double = 1) {
        let inset = Swift.max(0.8, Double(rect.width) * 0.045)
        let outer = rect.insetBy(dx: inset, dy: inset)
        if grey < 0.999 { image(&ctx, art.block(color), in: outer, alpha: alpha) }
        if grey > 0.001 { image(&ctx, art.grey, in: outer, alpha: alpha * grey) }
    }

    private func drawBlocks(_ ctx: inout GraphicsContext, _ art: BlockPartyArt) {
        let ending = f.endClock >= 0
        for r in 0..<8 {
            for c in 0..<8 {
                let k = r * 8 + c
                let color = f.grid[k]
                if color == 0 { continue }
                var grey = 0.0
                var rect = cellRect(c, r)
                let age = f.placedAge[k]
                if age < 0.3 {
                    // A fresh block lands with a little overshoot.
                    let pop = 1 + 0.16 * sin(M.clamp(age / 0.3) * Double.pi) * (1 - age / 0.3)
                    let grow = (pop - 1) * cell / 2
                    rect = rect.insetBy(dx: -grow, dy: -grow)
                }
                if ending {
                    // The board goes grey in a wave from the top left when there is no room left.
                    let wave = Double(r + c) * 0.055
                    grey = M.smooth(wave, wave + 0.35, f.endClock)
                }
                drawBlock(&ctx, art, rect, color: color, grey: grey)
            }
        }
    }

    private func drawGhost(_ ctx: inout GraphicsContext, _ art: BlockPartyArt) {
        guard f.ghostValid, let shape = f.dragShape else { return }
        let tint = P.block(shape.color)
        // Rows and columns that would fill light up in the piece's colour.
        if f.ghostLines != 0 {
            let glow = 0.22 + 0.08 * sin(f.ambient * 9)
            for r in 0..<8 {
                for c in 0..<8 {
                    let rowLit = (f.ghostLines & UInt16(1 << r)) != 0
                    let colLit = (f.ghostLines & UInt16(1 << (8 + c))) != 0
                    if !rowLit && !colLit { continue }
                    let rect = cellRect(c, r).insetBy(dx: 1.4 * u, dy: 1.4 * u)
                    ctx.fill(Path(roundedRect: rect, cornerRadius: 3 * u), with: .color(tint.color(glow)))
                }
            }
        }
        for c in shape.cells {
            let rect = cellRect(f.ghostCol + c.x, f.ghostRow + c.y).insetBy(dx: 2 * u, dy: 2 * u)
            image(&ctx, art.block(shape.color), in: rect, alpha: 0.42)
            ctx.stroke(Path(roundedRect: rect, cornerRadius: 4 * u), with: .color(tint.mix(.white, 0.5).color(0.7)), lineWidth: 1.5 * u)
        }
    }

    private func drawFlashes(_ ctx: inout GraphicsContext) {
        for r in 0..<8 {
            for c in 0..<8 {
                let age = f.flash[r * 8 + c]
                if age < 0 || age >= 0.32 { continue }
                let k = M.clamp(age / 0.32)
                let grow = k * cell * 0.35
                let rect = cellRect(c, r).insetBy(dx: -grow, dy: -grow)
                ctx.fill(Path(roundedRect: rect, cornerRadius: 5 * u), with: .color(Color.white.opacity(0.85 * (1 - k))))
            }
        }
    }

    private func drawBursts(_ ctx: inout GraphicsContext) {
        for burst in f.bursts {
            let t = burst.age
            if t < 0 || t >= BlockPartyBurst.life { continue }
            let fade = 1 - M.smooth(0.45, 1, t / BlockPartyBurst.life)
            let tint = P.block(burst.color)
            // Five sparks per cell, their directions fixed by where the cell sits.
            let base = burst.x * 7.3 + burst.y * 3.1
            for k in 0..<5 {
                let angle = base + Double(k) * 1.2566 + sin(base * 2.7 + Double(k)) * 0.5
                let speed = cell * (2.4 + 1.2 * abs(sin(base + Double(k) * 0.9)))
                let x = burst.x * cell + cos(angle) * speed * t
                let y = burst.y * cell + sin(angle) * speed * t + cell * 5.5 * t * t
                let size = cell * (0.22 - 0.1 * t) * (k % 2 == 0 ? 1 : 0.7)
                let rect = CGRect(x: L.boardX + x - size / 2, y: L.boardY + y - size / 2, width: size, height: size)
                let color = k % 3 == 0 ? tint.mix(.white, 0.6) : tint
                ctx.fill(Path(roundedRect: rect, cornerRadius: size * 0.3), with: .color(color.color(fade)))
            }
        }
    }

    // MARK: Pieces in the air and the tray

    /// A piece drawn at a centre and a scale, with a soft shadow under it when it is lifted.
    private func drawShape(_ ctx: inout GraphicsContext, _ art: BlockPartyArt, _ shape: BlockPartyShape, center: CGPoint,
                           scale: Double, shadow: Double, alpha: Double = 1) {
        let side = cell * scale
        let x0 = Double(center.x) - Double(shape.w) * side / 2
        let y0 = Double(center.y) - Double(shape.h) * side / 2
        if shadow > 0.01 {
            for c in shape.cells {
                let rect = CGRect(x: x0 + Double(c.x) * side, y: y0 + Double(c.y) * side + 14 * u * shadow,
                                  width: side, height: side).insetBy(dx: -1 * u, dy: -1 * u)
                ctx.fill(Path(roundedRect: rect, cornerRadius: side * 0.2), with: .color(P.shadow.color(0.35 * shadow * alpha)))
            }
        }
        for c in shape.cells {
            let rect = CGRect(x: x0 + Double(c.x) * side, y: y0 + Double(c.y) * side, width: side, height: side)
            drawBlock(&ctx, art, rect, color: shape.color, alpha: alpha)
        }
    }

    private func drawTray(_ ctx: inout GraphicsContext, _ art: BlockPartyArt) {
        for slot in 0..<3 {
            guard let shape = f.tray[slot] else { continue }
            if f.dragSlot == slot { continue }
            let age = f.trayAge[slot]
            // A fresh deal pops into the slot, one slot after the other.
            let arrive = age >= 0.5 ? 1 : M.easeOutBack(M.clamp((age - Double(slot) * 0.06) / 0.28))
            if arrive <= 0.001 { continue }
            var scale = BlockPartyLayout.trayScale * arrive
            var fade = 1.0
            if f.endClock >= 0 {
                fade = 1 - 0.55 * M.smooth(0.2, 0.8, f.endClock)
                scale *= 1 - 0.1 * M.smooth(0.2, 0.8, f.endClock)
            }
            drawShape(&ctx, art, shape, center: L.slotCenter(slot), scale: scale, shadow: 0.25, alpha: fade)
        }
    }

    private func drawReturning(_ ctx: inout GraphicsContext, _ art: BlockPartyArt) {
        guard let shape = f.returnShape else { return }
        let k = M.easeOut(M.clamp(f.returnAge / 0.2))
        if k >= 1 { return }
        let to = L.slotCenter(f.returnSlot)
        let center = CGPoint(x: M.lerp(Double(f.returnFrom.x), Double(to.x), k),
                             y: M.lerp(Double(f.returnFrom.y), Double(to.y), k))
        let scale = M.lerp(1, BlockPartyLayout.trayScale, k)
        drawShape(&ctx, art, shape, center: center, scale: scale, shadow: 1 - k)
    }

    private func drawHeld(_ ctx: inout GraphicsContext, _ art: BlockPartyArt) {
        guard let shape = f.dragShape, f.dragSlot != nil else { return }
        let k = f.dragLift
        let scale = M.lerp(BlockPartyLayout.trayScale, 1.04, k)
        drawShape(&ctx, art, shape, center: f.dragCenter, scale: scale, shadow: 0.25 + 0.75 * k)
    }

    // MARK: Words

    private func drawFloats(_ ctx: inout GraphicsContext) {
        for item in f.floats {
            let t = item.age
            if t < 0 || t >= BlockPartyFloat.life { continue }
            let arrive = M.easeOutBack(M.clamp(t / 0.18))
            let alpha = 1 - M.smooth(0.55, 1, t / BlockPartyFloat.life)
            let rise = M.easeOut(t / BlockPartyFloat.life) * cell * 1.4
            let at = L.point(cellX: item.x, cellY: item.y)
            let text = Text(item.text).font(.system(size: 26 * u * arrive, weight: .heavy, design: .rounded))
            let p = CGPoint(x: Double(at.x), y: Double(at.y) - rise)
            ctx.draw(text.foregroundColor(P.shadow.color(0.6 * alpha)), at: CGPoint(x: p.x, y: p.y + 2 * u), anchor: .center)
            ctx.draw(text.foregroundColor(P.block(item.color).mix(.white, 0.45).color(alpha)), at: p, anchor: .center)
        }
    }

    private func drawHUD(_ ctx: inout GraphicsContext, _ art: BlockPartyArt) {
        let cx = L.W / 2

        // Best, with a small crown, between the app's two corner controls.
        let best = Swift.max(f.best, f.score)
        if best > 0 {
            let label = Text("\(best)").font(.system(size: 15 * u, weight: .heavy, design: .rounded))
            let width = Double(ctx.resolve(label).measure(in: CGSize(width: 400, height: 100)).width)
            let crownW = 18 * u
            let left = cx - (width + crownW + 5 * u) / 2
            let crownH = crownW * Double(art.crown.size.height) / Swift.max(1, Double(art.crown.size.width))
            ctx.draw(art.crown, in: CGRect(x: left, y: L.bestY - crownH / 2 - 1 * u, width: crownW, height: crownH))
            ctx.draw(label.foregroundColor(P.gold.color()), at: CGPoint(x: left + crownW + 5 * u, y: L.bestY), anchor: .leading)
        }

        // The score, with a jump when it changes.
        let pop = 1 + 0.12 * exp(-6 * f.scoreAge) * Swift.max(0, 1 - f.scoreAge)
        let number = Text("\(f.score)").font(.system(size: 46 * u * pop, weight: .heavy, design: .rounded))
        ctx.draw(number.foregroundColor(P.shadow.color(0.45)), at: CGPoint(x: cx, y: L.scoreY + 3 * u), anchor: .center)
        ctx.draw(number.foregroundColor(.white), at: CGPoint(x: cx, y: L.scoreY), anchor: .center)

        // Praise and combo over the board.
        let midY = L.boardY + cell * 4
        if let praise = f.praise {
            let t = f.praiseAge
            let arrive = M.easeOutBack(M.clamp(t / 0.22))
            let alpha = 1 - M.smooth(0.9, 1.3, t)
            if alpha > 0.01 {
                let text = Text(praise.uppercased()).font(.system(size: 34 * u * arrive, weight: .black, design: .rounded)).kerning(2 * u)
                let y = midY - 30 * u - M.easeOut(t / 1.3) * 18 * u
                ctx.draw(text.foregroundColor(P.shadow.color(0.6 * alpha)), at: CGPoint(x: cx, y: y + 3 * u), anchor: .center)
                ctx.draw(text.foregroundColor(Color.white.opacity(alpha)), at: CGPoint(x: cx, y: y), anchor: .center)
            }
        }
        if let note = f.note {
            let t = f.noteAge
            let arrive = M.easeOutBack(M.clamp((t - 0.08) / 0.22))
            let alpha = 1 - M.smooth(0.9, 1.3, t)
            if alpha > 0.01 && arrive > 0.01 {
                let text = Text(note).font(.system(size: 22 * u * arrive, weight: .heavy, design: .rounded))
                let y = midY + 14 * u - M.easeOut(t / 1.3) * 18 * u
                ctx.draw(text.foregroundColor(P.shadow.color(0.6 * alpha)), at: CGPoint(x: cx, y: y + 2 * u), anchor: .center)
                ctx.draw(text.foregroundColor(P.gold.color(alpha)), at: CGPoint(x: cx, y: y), anchor: .center)
            }
        }

        if let hint = f.hint, f.hintAlpha > 0.01 {
            let text = Text(hint).font(.system(size: 16 * u, weight: .bold, design: .rounded))
            ctx.draw(text.foregroundColor(Color.white.opacity(0.75 * f.hintAlpha)), at: CGPoint(x: cx, y: L.hintY), anchor: .center)
        }

        if f.endClock >= 0 {
            let alpha = M.smooth(0.3, 0.7, f.endClock)
            if alpha > 0.01 {
                let text = Text("No room left").font(.system(size: 30 * u, weight: .black, design: .rounded))
                ctx.draw(text.foregroundColor(P.shadow.color(0.6 * alpha)), at: CGPoint(x: cx, y: midY + 3 * u), anchor: .center)
                ctx.draw(text.foregroundColor(Color.white.opacity(alpha)), at: CGPoint(x: cx, y: midY), anchor: .center)
            }
        }
    }
}
