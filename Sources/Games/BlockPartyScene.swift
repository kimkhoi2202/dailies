import SwiftUI

// Block Party: drag blocks onto an 8 x 8 board, fill a row or a column to clear it.
//
// BlockPartyPainter paints one frame of a BlockPartyModel into a Canvas. The playable game paints
// its live model; the cover and the Videos feed paint a short scripted round at a given phase.

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
            let model = BlockPartyModel.clip(phase: phase, size: size)
            BlockPartyPainter(model: model, showHUD: showHUD).draw(&context)
        }
    }
}

// MARK: - Numbers

enum BlockPartyMath {
    static func clamp(_ v: Double, _ lo: Double = 0, _ hi: Double = 1) -> Double {
        Swift.max(lo, Swift.min(hi, v))
    }

    static func smooth(_ a: Double, _ b: Double, _ v: Double) -> Double {
        let t = clamp((v - a) / (b - a))
        return t * t * (3 - 2 * t)
    }

    static func easeOut(_ t: Double) -> Double {
        let k = 1 - clamp(t)
        return 1 - k * k * k
    }

    static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
}

enum BlockPartyFormat {
    /// 12480 as "12,480".
    static func grouped(_ value: Int) -> String {
        let n = Swift.max(0, value)
        if n < 1000 { return String(n) }
        if n < 1_000_000 { return String(n / 1000) + "," + String(format: "%03d", n % 1000) }
        return String(n / 1_000_000) + "," + String(format: "%03d", (n / 1000) % 1000) + "," + String(format: "%03d", n % 1000)
    }
}

struct BlockPartyRandom {
    static let pieces: UInt64 = 0x2545F4914F6CDD1D
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

// MARK: - Pieces

struct BlockPartyShape {
    let w: Int
    let h: Int
    let cols: [Int]
    let rows: [Int]
    let weight: Int
    var count: Int { cols.count }

    init(_ lines: [String], weight: Int) {
        var c: [Int] = []
        var r: [Int] = []
        var widest = 1
        for (y, line) in lines.enumerated() {
            widest = Swift.max(widest, line.count)
            for (x, ch) in line.enumerated() where ch == "X" {
                c.append(x)
                r.append(y)
            }
        }
        w = widest
        h = lines.count
        cols = c
        rows = r
        self.weight = weight
    }

    static let all: [BlockPartyShape] = [
        BlockPartyShape(["X"], weight: 3),
        BlockPartyShape(["XX"], weight: 4),
        BlockPartyShape(["X", "X"], weight: 4),
        BlockPartyShape(["XXX"], weight: 4),
        BlockPartyShape(["X", "X", "X"], weight: 4),
        BlockPartyShape(["XXXX"], weight: 3),
        BlockPartyShape(["X", "X", "X", "X"], weight: 3),
        BlockPartyShape(["XXXXX"], weight: 1),
        BlockPartyShape(["X", "X", "X", "X", "X"], weight: 1),
        BlockPartyShape(["XX", "XX"], weight: 5),
        BlockPartyShape(["XXX", "XXX", "XXX"], weight: 2),
        BlockPartyShape(["XXX", "XXX"], weight: 2),
        BlockPartyShape(["XX", "XX", "XX"], weight: 2),
        BlockPartyShape(["X.", "XX"], weight: 2),
        BlockPartyShape([".X", "XX"], weight: 2),
        BlockPartyShape(["XX", "X."], weight: 2),
        BlockPartyShape(["XX", ".X"], weight: 2),
        BlockPartyShape(["X..", "X..", "XXX"], weight: 1),
        BlockPartyShape(["..X", "..X", "XXX"], weight: 1),
        BlockPartyShape(["XXX", "X..", "X.."], weight: 1),
        BlockPartyShape(["XXX", "..X", "..X"], weight: 1),
        BlockPartyShape(["X.", "X.", "XX"], weight: 2),
        BlockPartyShape(["XX", ".X", ".X"], weight: 2),
        BlockPartyShape(["XXX", "X.."], weight: 2),
        BlockPartyShape(["..X", "XXX"], weight: 2),
        BlockPartyShape(["XXX", ".X."], weight: 2),
        BlockPartyShape([".X.", "XXX"], weight: 2),
        BlockPartyShape(["X.", "XX", "X."], weight: 2),
        BlockPartyShape([".X", "XX", ".X"], weight: 2),
        BlockPartyShape(["XX.", ".XX"], weight: 2),
        BlockPartyShape([".XX", "XX."], weight: 2),
        BlockPartyShape(["X.", "XX", ".X"], weight: 1),
        BlockPartyShape([".X", "XX", "X."], weight: 1),
        BlockPartyShape(["X.", ".X"], weight: 1),
        BlockPartyShape([".X", "X."], weight: 1)
    ]

    static let totalWeight: Int = all.reduce(0) { $0 + $1.weight }
}

struct BlockPartyPiece: Equatable {
    let shape: Int
    let color: UInt8
}

// MARK: - Colour

enum BlockPartyPalette {
    static func rgb(_ hex: UInt32, _ alpha: Double = 1) -> Color {
        Color(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
              blue: Double(hex & 0xFF) / 255, opacity: alpha)
    }

    // Index 0 is the grey every block turns at the end of a round. 1 to 7 are the block colours.
    static let base: [Color] = [0x8C90B8, 0xFF5D62, 0xFF9A2E, 0xFFCF3A, 0x44CF7C, 0x2EC4C0, 0x3D8BFF, 0xA067F0].map { rgb($0) }
    static let light: [Color] = [0xC3C6E0, 0xFFA3A5, 0xFFC888, 0xFFE89A, 0x9AF0BC, 0x93ECE6, 0x9CC4FF, 0xD3B2FF].map { rgb($0) }
    static let dark: [Color] = [0x5A5E86, 0xC23440, 0xC86410, 0xC99A10, 0x239455, 0x18908E, 0x2559C2, 0x6C3DB8].map { rgb($0) }

    static let sky = Gradient(colors: [rgb(0x4048B8), rgb(0x2C318E), rgb(0x1E2266)])
    static let glow = rgb(0x6E7BFF, 0.28)
    static let board = rgb(0x161A4E)
    static let boardShadow = rgb(0x0C0E30, 0.55)
    static let slot = rgb(0x22276A)
    static let shine = Color.white.opacity(0.32)
    static let ink = rgb(0x151412)
    static let card = rgb(0xF8F6F1)
    static let crown = rgb(0xFFD23F)
    static let crownDark = rgb(0xD99A12)
    static let combo = rgb(0xFFE066)
    static let shadow = rgb(0x0E1036)
}

// MARK: - Layout

/// Where everything sits on a screen of a given size. Points, with u = 1 on a 402 x 874 phone.
struct BlockPartyLayout {
    let W: Double
    let H: Double
    let u: Double
    let cell: Double
    let boardX: Double
    let boardY: Double
    let boardSize: Double
    let pad: Double
    let scoreY: Double
    let bestY: Double
    let friendsY: Double
    let trayTop: Double
    let trayY: Double
    let lift: Double
    let trayScale = 0.55

    init(size: CGSize) {
        W = Double(size.width)
        H = Double(size.height)
        u = Swift.min(W / 402, H / 874)
        let status = Double(GameLayout.statusBarHeight)
        scoreY = status + 40 * u
        bestY = scoreY + 42 * u
        friendsY = bestY + 29 * u
        pad = 7 * u
        let top = status + 136 * u
        let bottomRoom = 200 * u + Double(GameLayout.bottomInset)
        boardSize = Swift.max(120, Swift.min(W - 28 * u - 2 * pad, H - top - bottomRoom - 2 * pad))
        cell = boardSize / 8
        boardX = (W - boardSize) / 2
        boardY = top + pad
        trayTop = boardY + boardSize + pad
        trayY = (trayTop + H - Double(GameLayout.bottomInset)) / 2
        lift = 30 * u
    }

    func slotX(_ k: Int) -> Double { W * Double(2 * k + 1) / 6 }

    /// Where a dragged piece sits for a finger: lifted clear above it.
    func dragCenter(x: Double, y: Double, h: Int) -> CGPoint {
        CGPoint(x: x, y: y - lift - Double(h) * cell / 2)
    }

    /// The finger position that puts a piece's top-left cell on (col, row).
    func finger(col: Int, row: Int, w: Int, h: Int) -> CGPoint {
        let cx = boardX + (Double(col) + Double(w) / 2) * cell
        let cy = boardY + (Double(row) + Double(h) / 2) * cell
        return CGPoint(x: cx, y: cy + lift + Double(h) * cell / 2)
    }

    func cellRect(_ c: Int, _ r: Int) -> CGRect {
        CGRect(x: boardX + Double(c) * cell, y: boardY + Double(r) * cell, width: cell, height: cell)
    }
}

// MARK: - Painter

struct BlockPartyPainter {
    typealias P = BlockPartyPalette
    typealias M = BlockPartyMath

    let m: BlockPartyModel
    let L: BlockPartyLayout
    let showHUD: Bool
    var u: Double { L.u }

    init(model: BlockPartyModel, showHUD: Bool) {
        m = model
        L = model.layout
        self.showHUD = showHUD
    }

    func draw(_ ctx: inout GraphicsContext) {
        drawBackground(&ctx)
        var board = ctx
        if m.shake > 0.001 {
            let k = m.shake * m.shake
            board.translateBy(x: sin(m.ambient * 71) * 6 * u * k, y: cos(m.ambient * 63) * 5 * u * k)
        }
        drawBoard(&board)
        drawCells(&board)
        drawPreview(&board)
        drawClearing(&board)
        drawParticles(&ctx)
        if m.stage == .ending || m.stage == .finished { drawEnding(&board) }
        drawTray(&ctx)
        drawReturning(&ctx)
        drawDragged(&ctx)
        drawFloaters(&ctx)
        drawCombo(&ctx)
        if showHUD { drawHUD(&ctx) }
        if m.stage == .ready { drawHint(&ctx) }
    }

    // MARK: Blocks

    /// One chunky block: a darker bottom lip, a light bevel along the top and a small shine.
    func drawBlock(_ ctx: inout GraphicsContext, x: Double, y: Double, size s: Double, color: Int) {
        let k = Swift.min(Swift.max(color, 0), 7)
        let half = s * 0.46
        let outer = CGRect(x: x - half, y: y - half, width: 2 * half, height: 2 * half)
        let radius = s * 0.15
        ctx.fill(Path(roundedRect: outer, cornerRadius: radius), with: .color(P.dark[k]))
        let face = CGRect(x: outer.minX, y: outer.minY, width: outer.width, height: outer.height - s * 0.12)
        ctx.fill(Path(roundedRect: face, cornerRadius: radius), with: .color(P.base[k]))
        let lid = CGRect(x: outer.minX + s * 0.09, y: outer.minY + s * 0.06, width: outer.width - s * 0.18, height: s * 0.14)
        ctx.fill(Path(roundedRect: lid, cornerRadius: s * 0.07), with: .color(P.light[k]))
        let shine = CGRect(x: outer.minX + s * 0.1, y: outer.minY + s * 0.27, width: s * 0.1, height: s * 0.26)
        ctx.fill(Path(roundedRect: shine, cornerRadius: s * 0.05), with: .color(P.shine))
    }

    func drawPiece(_ ctx: inout GraphicsContext, _ piece: BlockPartyPiece, center: CGPoint, cell: Double, color: Int) {
        let shape = BlockPartyShape.all[piece.shape]
        let ox = Double(center.x) - Double(shape.w) * cell / 2
        let oy = Double(center.y) - Double(shape.h) * cell / 2
        for k in 0..<shape.count {
            let x = ox + (Double(shape.cols[k]) + 0.5) * cell
            let y = oy + (Double(shape.rows[k]) + 0.5) * cell
            drawBlock(&ctx, x: x, y: y, size: cell, color: color)
        }
    }

    // MARK: Backdrop and board

    private func drawBackground(_ ctx: inout GraphicsContext) {
        let full = CGRect(x: 0, y: 0, width: L.W, height: L.H)
        ctx.fill(Path(full), with: .linearGradient(P.sky, startPoint: CGPoint(x: L.W / 2, y: 0),
                                                   endPoint: CGPoint(x: L.W / 2, y: L.H)))
        let step = 38 * u
        let drift = (m.ambient * 5 * u).truncatingRemainder(dividingBy: step)
        var tiles = Path()
        var y = -step + drift
        while y < L.H {
            var x = -step * 0.5
            while x < L.W {
                tiles.addRoundedRect(in: CGRect(x: x + 3 * u, y: y + 3 * u, width: step - 6 * u, height: step - 6 * u),
                                     cornerSize: CGSize(width: 7 * u, height: 7 * u))
                x += step
            }
            y += step
        }
        ctx.fill(tiles, with: .color(Color.white.opacity(0.035)))

        let center = CGPoint(x: L.W / 2, y: L.boardY + L.boardSize / 2)
        let reach = L.boardSize * 0.95
        ctx.fill(Path(ellipseIn: CGRect(x: Double(center.x) - reach, y: Double(center.y) - reach, width: 2 * reach, height: 2 * reach)),
                 with: .radialGradient(Gradient(colors: [P.glow, P.glow.opacity(0)]), center: center, startRadius: 0, endRadius: reach))
    }

    private var boardFrame: CGRect {
        CGRect(x: L.boardX - L.pad, y: L.boardY - L.pad, width: L.boardSize + 2 * L.pad, height: L.boardSize + 2 * L.pad)
    }

    private func drawBoard(_ ctx: inout GraphicsContext) {
        let outer = boardFrame
        let radius = 16 * u
        ctx.fill(Path(roundedRect: outer.offsetBy(dx: 0, dy: 6 * u), cornerRadius: radius), with: .color(P.boardShadow))
        ctx.fill(Path(roundedRect: outer, cornerRadius: radius), with: .color(P.board))
        ctx.stroke(Path(roundedRect: outer.insetBy(dx: u, dy: u), cornerRadius: radius - u),
                   with: .color(Color.white.opacity(0.09)), lineWidth: 1.5 * u)
        var slots = Path()
        let inset = 1.8 * u
        let corner = CGSize(width: 5 * u, height: 5 * u)
        for r in 0..<8 {
            for c in 0..<8 {
                slots.addRoundedRect(in: L.cellRect(c, r).insetBy(dx: inset, dy: inset), cornerSize: corner)
            }
        }
        ctx.fill(slots, with: .color(P.slot))
    }

    private func grayed(row r: Int) -> Bool {
        guard m.stage == .ending || m.stage == .finished else { return false }
        return m.endClock - Double(7 - r) * 0.07 > 0.05
    }

    private func drawCells(_ ctx: inout GraphicsContext) {
        let hotColor: Int? = m.ghostCol >= 0 ? m.dragPiece.map { Int($0.color) } : nil
        for i in 0..<64 {
            let v = Int(m.grid[i])
            if v == 0 { continue }
            let c = i % 8
            let r = i / 8
            var color = v
            if let hot = hotColor, m.hotRows[r] || m.hotCols[c] { color = hot }
            if grayed(row: r) { color = 0 }
            let age = m.popAge[i]
            let pop: Double = age < 0.5 ? 1 + 0.17 * exp(-13 * age) * cos(21 * age) : 1
            let rect = L.cellRect(c, r)
            drawBlock(&ctx, x: Double(rect.midX), y: Double(rect.midY), size: L.cell * pop, color: color)
        }
    }

    // MARK: Ghost and the lines it would clear

    private func drawPreview(_ ctx: inout GraphicsContext) {
        guard m.ghostCol >= 0, let piece = m.dragPiece else { return }
        let shape = BlockPartyShape.all[piece.shape]
        let color = Int(piece.color)
        let pulse = 0.5 + 0.5 * sin(m.ambient * 10)
        for r in 0..<8 where m.hotRows[r] {
            let band = L.cellRect(0, r).union(L.cellRect(7, r))
            drawLineGlow(&ctx, band, color: color, pulse: pulse)
        }
        for c in 0..<8 where m.hotCols[c] {
            let band = L.cellRect(c, 0).union(L.cellRect(c, 7))
            drawLineGlow(&ctx, band, color: color, pulse: pulse)
        }
        var ghost = ctx
        ghost.opacity = 0.42 + 0.12 * pulse
        for k in 0..<shape.count {
            let rect = L.cellRect(m.ghostCol + shape.cols[k], m.ghostRow + shape.rows[k])
            drawBlock(&ghost, x: Double(rect.midX), y: Double(rect.midY), size: L.cell, color: color)
        }
    }

    private func drawLineGlow(_ ctx: inout GraphicsContext, _ band: CGRect, color: Int, pulse: Double) {
        let path = Path(roundedRect: band.insetBy(dx: -1.5 * u, dy: -1.5 * u), cornerRadius: 8 * u)
        ctx.fill(path, with: .color(P.light[color].opacity(0.10 + 0.10 * pulse)))
        ctx.stroke(path, with: .color(Color.white.opacity(0.45 + 0.4 * pulse)), lineWidth: 2.4 * u)
    }

    // MARK: Clears and particles

    private func drawClearing(_ ctx: inout GraphicsContext) {
        let length = BlockPartyModel.clearLength
        for i in 0..<64 {
            let t = m.clearAge[i]
            if t >= length { continue }
            let color = Int(m.clearColor[i])
            if color == 0 { continue }
            let rect = L.cellRect(i % 8, i / 8)
            let x = Double(rect.midX)
            let y = Double(rect.midY)
            if t < 0 {
                drawBlock(&ctx, x: x, y: y, size: L.cell, color: color)
                continue
            }
            let p = t / length
            let swell = 1 + 0.24 * sin(M.clamp(p * 2.4) * .pi)
            let size = L.cell * swell * (1 - p * p)
            var fx = ctx
            fx.opacity = 1 - p * p
            drawBlock(&fx, x: x, y: y, size: size, color: color)
            let half = size * 0.46
            fx.fill(Path(roundedRect: CGRect(x: x - half, y: y - half, width: 2 * half, height: 2 * half), cornerRadius: size * 0.15),
                    with: .color(Color.white.opacity(0.85 * (1 - p))))
        }
    }

    private func drawParticles(_ ctx: inout GraphicsContext) {
        for p in m.particles where p.age < p.life {
            let a = 1 - p.age / p.life
            let s = p.size * (0.5 + 0.5 * a)
            let rect = CGRect(x: p.x - s / 2, y: p.y - s / 2, width: s, height: s)
            ctx.fill(Path(roundedRect: rect, cornerRadius: s * 0.28), with: .color(P.light[Int(p.color)].opacity(a)))
        }
    }

    // MARK: Tray and the piece in hand

    private func drawTray(_ ctx: inout GraphicsContext) {
        let cell = L.cell * L.trayScale
        for k in 0..<3 {
            guard let piece = m.tray[k], k != m.dragSlot, k != m.backSlot else { continue }
            let enter = M.clamp((m.dealAge - Double(k) * 0.07) / 0.3)
            if enter <= 0 { continue }
            let slide = (1 - M.easeOut(enter)) * L.W * 0.7
            var y = L.trayY
            if m.stage == .ready { y += sin(m.ambient * 3 + Double(k) * 1.7) * 2.5 * u }
            let stuck = !m.fits[k] && m.stage == .playing
            var tray = ctx
            if stuck { tray.opacity = 0.6 }
            drawPiece(&tray, piece, center: CGPoint(x: L.slotX(k) + slide, y: y), cell: cell, color: stuck ? 0 : Int(piece.color))
        }
    }

    private func drawDragged(_ ctx: inout GraphicsContext) {
        guard let piece = m.dragPiece else { return }
        let shape = BlockPartyShape.all[piece.shape]
        let grow = M.easeOut(M.clamp(m.dragAge / 0.09))
        let cell = L.cell * M.lerp(L.trayScale, 1.02, grow)
        let target = L.dragCenter(x: m.dragX, y: m.dragY, h: shape.h)
        let x = M.lerp(L.slotX(m.dragSlot), Double(target.x), grow)
        let y = M.lerp(L.trayY, Double(target.y), grow)
        var shadow = ctx
        shadow.opacity = 0.3
        let ox = x - Double(shape.w) * cell / 2
        let oy = y - Double(shape.h) * cell / 2 + 12 * u
        var shade = Path()
        for k in 0..<shape.count {
            let rect = CGRect(x: ox + Double(shape.cols[k]) * cell + cell * 0.04, y: oy + Double(shape.rows[k]) * cell + cell * 0.04,
                              width: cell * 0.92, height: cell * 0.92)
            shade.addRoundedRect(in: rect, cornerSize: CGSize(width: cell * 0.15, height: cell * 0.15))
        }
        shadow.fill(shade, with: .color(P.shadow))
        drawPiece(&ctx, piece, center: CGPoint(x: x, y: y), cell: cell, color: Int(piece.color))
    }

    private func drawReturning(_ ctx: inout GraphicsContext) {
        guard m.backSlot >= 0, let piece = m.tray[m.backSlot] else { return }
        let t = M.easeOut(M.clamp(m.backAge / BlockPartyModel.backLength))
        let x = M.lerp(m.backX, L.slotX(m.backSlot), t)
        let y = M.lerp(m.backY, L.trayY, t)
        let cell = L.cell * M.lerp(1, L.trayScale, t)
        drawPiece(&ctx, piece, center: CGPoint(x: x, y: y), cell: cell, color: Int(piece.color))
    }

    // MARK: Words

    private func drawShadowed(_ ctx: inout GraphicsContext, _ text: Text, at point: CGPoint, color: Color, alpha: Double, drop: Double) {
        ctx.draw(text.foregroundColor(P.shadow.opacity(0.55 * alpha)), at: CGPoint(x: point.x, y: point.y + drop), anchor: .center)
        ctx.draw(text.foregroundColor(color.opacity(alpha)), at: point, anchor: .center)
    }

    private func drawFloaters(_ ctx: inout GraphicsContext) {
        for f in m.floaters where f.age < BlockPartyModel.floatLength {
            let t = f.age / BlockPartyModel.floatLength
            let rise = 66 * u * M.easeOut(t)
            let alpha = 1 - M.smooth(0.55, 1, t)
            let size = (f.big ? 30 : 22) * u * (1 + 0.35 * exp(-16 * f.age))
            let text = Text(f.text).font(.system(size: size, weight: .black, design: .rounded))
            drawShadowed(&ctx, text, at: CGPoint(x: f.x, y: f.y - rise), color: .white, alpha: alpha, drop: 2.5 * u)
        }
    }

    private func drawCombo(_ ctx: inout GraphicsContext) {
        let t = m.comboAge
        let length = BlockPartyModel.comboLength
        if t >= length { return }
        let arrive = M.easeOut(M.clamp(t / 0.14))
        let scale = 0.55 + 0.45 * arrive + 0.16 * sin(.pi * M.clamp(t / 0.26))
        let alpha = arrive * (1 - M.smooth(length - 0.3, length, t))
        let y = L.boardY + L.boardSize * 0.36 - 22 * u * t
        var below = y
        if m.combo >= 2 {
            let text = Text("Combo x\(m.combo)").font(.system(size: 42 * u * scale, weight: .black, design: .rounded)).italic()
            drawShadowed(&ctx, text, at: CGPoint(x: L.W / 2, y: y), color: P.combo, alpha: alpha, drop: 3.5 * u)
            below = y + 44 * u
        }
        if let praise = m.praise {
            let text = Text(praise).font(.system(size: 28 * u * scale, weight: .heavy, design: .rounded))
            drawShadowed(&ctx, text, at: CGPoint(x: L.W / 2, y: below), color: .white, alpha: alpha, drop: 2.5 * u)
        }
    }

    // MARK: HUD

    private func drawHUD(_ ctx: inout GraphicsContext) {
        let cx = L.W / 2
        let pop = 1 + 0.12 * exp(-12 * m.scorePop)
        let number = Text(BlockPartyFormat.grouped(Int(m.shown.rounded())))
            .font(.system(size: 52 * u * pop, weight: .heavy, design: .rounded).monospacedDigit())
        drawShadowed(&ctx, number, at: CGPoint(x: cx, y: L.scoreY), color: .white, alpha: 1, drop: 3.5 * u)

        let best = Swift.max(m.bestScore, m.score)
        let label = ctx.resolve(Text(BlockPartyFormat.grouped(best))
            .font(.system(size: 17 * u, weight: .heavy, design: .rounded).monospacedDigit())
            .foregroundColor(P.crown))
        let width = Double(label.measure(in: CGSize(width: L.W, height: 60)).width)
        let total = 24 * u + 6 * u + width
        let left = cx - total / 2
        drawCrown(&ctx, x: left + 12 * u, y: L.bestY, size: 22 * u)
        ctx.draw(label, at: CGPoint(x: left + 30 * u, y: L.bestY), anchor: .leading)

        if !m.friends.isEmpty { drawFriends(&ctx) }
    }

    private func drawCrown(_ ctx: inout GraphicsContext, x: Double, y: Double, size s: Double) {
        var crown = Path()
        crown.move(to: CGPoint(x: x - 0.5 * s, y: y + 0.3 * s))
        crown.addLine(to: CGPoint(x: x - 0.5 * s, y: y - 0.22 * s))
        crown.addLine(to: CGPoint(x: x - 0.22 * s, y: y + 0.02 * s))
        crown.addLine(to: CGPoint(x: x, y: y - 0.36 * s))
        crown.addLine(to: CGPoint(x: x + 0.22 * s, y: y + 0.02 * s))
        crown.addLine(to: CGPoint(x: x + 0.5 * s, y: y - 0.22 * s))
        crown.addLine(to: CGPoint(x: x + 0.5 * s, y: y + 0.3 * s))
        crown.closeSubpath()
        ctx.fill(crown, with: .color(P.crown))
        ctx.fill(Path(CGRect(x: x - 0.5 * s, y: y + 0.18 * s, width: s, height: 0.12 * s)), with: .color(P.crownDark))
        let r = 0.08 * s
        for dx in [-0.5, 0.0, 0.5] {
            let ty = dx == 0 ? y - 0.36 * s : y - 0.22 * s
            ctx.fill(Path(ellipseIn: CGRect(x: x + dx * s - r, y: ty - r, width: 2 * r, height: 2 * r)), with: .color(P.crown))
        }
    }

    private func drawFriends(_ ctx: inout GraphicsContext) {
        let count = m.friends.count
        let gap = 150 * u
        for (k, friend) in m.friends.enumerated() {
            let x = L.W / 2 + (Double(k) - Double(count - 1) / 2) * gap
            let words = String(friend.name.prefix(11)) + "  " + BlockPartyFormat.grouped(Int(friend.shown.rounded()))
            let label = ctx.resolve(Text(words).font(.system(size: 13.5 * u, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundColor(Color.white.opacity(friend.out ? 0.55 : 0.95)))
            let width = Double(label.measure(in: CGSize(width: L.W, height: 60)).width)
            let flash = friend.passedFor.map { Swift.max(0, 1 - $0 / 0.7) } ?? 0
            let grow = 1 + 0.16 * flash
            let chipW = (width + 30 * u) * grow
            let chipH = 24 * u * grow
            let chip = CGRect(x: x - chipW / 2, y: L.friendsY - chipH / 2, width: chipW, height: chipH)
            let ahead = Int(friend.shown) > m.score
            ctx.fill(Path(roundedRect: chip, cornerRadius: chipH / 2), with: .color(Color.white.opacity((ahead ? 0.18 : 0.10) + 0.5 * flash)))
            if flash > 0.01 {
                ctx.stroke(Path(roundedRect: chip.insetBy(dx: -3 * u * (1 - flash), dy: -3 * u * (1 - flash)), cornerRadius: chipH / 2),
                           with: .color(P.combo.opacity(flash)), lineWidth: 2 * u)
            }
            let dot = 7 * u
            ctx.fill(Path(ellipseIn: CGRect(x: chip.minX + 9 * u, y: L.friendsY - dot / 2, width: dot, height: dot)),
                     with: .color(friend.out ? P.base[0] : P.base[5 + k % 3]))
            ctx.draw(label, at: CGPoint(x: chip.minX + 21 * u, y: L.friendsY), anchor: .leading)
        }
    }

    // MARK: Start and end

    private func drawHint(_ ctx: inout GraphicsContext) {
        let t = m.ambient.truncatingRemainder(dividingBy: 1.9) / 1.9
        let move = M.smooth(0.15, 0.75, t)
        let x = M.lerp(L.slotX(1), L.W / 2, move)
        let y = M.lerp(L.trayY + 10 * u, L.boardY + L.boardSize * 0.58, move)
        let alpha = M.smooth(0, 0.12, t) * (1 - M.smooth(0.8, 1, t))
        let r = 19 * u
        let ring = Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
        ctx.fill(ring, with: .color(Color.white.opacity(0.25 * alpha)))
        ctx.stroke(ring, with: .color(Color.white.opacity(0.85 * alpha)), lineWidth: 3 * u)

        let pulse = 0.8 + 0.2 * sin(m.ambient * 3.2)
        let text = Text("Drag a block onto the board").font(.system(size: 17 * u, weight: .heavy, design: .rounded))
        let ty = L.H - Double(GameLayout.bottomInset) - 14 * u
        drawShadowed(&ctx, text, at: CGPoint(x: L.W / 2, y: ty), color: .white, alpha: pulse, drop: 2 * u)
    }

    private func drawEnding(_ ctx: inout GraphicsContext) {
        let t = m.endClock
        let dim = M.smooth(0.5, 0.9, t)
        if dim > 0 {
            ctx.fill(Path(roundedRect: boardFrame, cornerRadius: 16 * u), with: .color(P.shadow.opacity(0.45 * dim)))
        }
        let appear = M.smooth(0.55, 0.8, t)
        if appear <= 0 { return }
        let scale = 0.86 + 0.14 * M.easeOut(M.clamp((t - 0.55) / 0.25)) + 0.04 * sin(.pi * M.clamp((t - 0.55) / 0.35))
        let w = 236 * u * scale
        let h = 96 * u * scale
        let cx = L.W / 2
        let cy = L.boardY + L.boardSize / 2
        var card = ctx
        card.opacity = appear
        let rect = CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h)
        card.fill(Path(roundedRect: rect.offsetBy(dx: 0, dy: 5 * u), cornerRadius: 22 * u), with: .color(P.shadow.opacity(0.5)))
        card.fill(Path(roundedRect: rect, cornerRadius: 22 * u), with: .color(P.card))
        card.draw(Text("No room left").font(.system(size: 25 * u * scale, weight: .heavy, design: .rounded)).foregroundColor(P.ink),
                  at: CGPoint(x: cx, y: cy - 13 * u * scale), anchor: .center)
        card.draw(Text(BlockPartyFormat.grouped(m.score) + " points").font(.system(size: 15 * u * scale, weight: .semibold, design: .rounded))
                    .foregroundColor(P.ink.opacity(0.6)),
                  at: CGPoint(x: cx, y: cy + 19 * u * scale), anchor: .center)
    }
}
