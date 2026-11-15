import SwiftUI

// Letter Rush: drag through touching letters on a 4 x 4 grid to make words, against an 80-second clock.
//
// Everything is painted into one Canvas by LetterRushPainter from a LetterRushFrame, which is
// one moment of the game. The clip in the video feed builds a frame from a phase (0...1) and a
// fixed script; the playable game builds one from its live model. The pictures are the
// letter-rush-* images in Resources/GameArt, resolved once per frame by LetterRushArt. Any frame size.

public struct LetterRushScene: View {
    public var phase: Double
    public var showHUD: Bool

    public init(phase: Double, showHUD: Bool) {
        self.phase = phase
        self.showHUD = showHUD
    }

    public var body: some View {
        Canvas(opaque: true, colorMode: .nonLinear, rendersAsynchronously: false) { context, size in
            if size.width <= 8 || size.height <= 8 { return }
            let frame = LetterRushClip.frame(at: phase)
            LetterRushPainter(size: size, frame: frame, showHUD: showHUD).draw(&context)
        }
    }
}

// MARK: - Numbers

enum LetterRushMath {
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

    /// Overshoots a little past 1 on the way in, like a spring.
    static func outBack(_ v: Double) -> Double {
        let k = clamp(v) - 1
        let s = 1.70158
        return 1 + k * k * ((s + 1) * k + s)
    }
}

/// SplitMix64. The board, the other player and the scripted player use different salts.
struct LetterRushRandom {
    static let board: UInt64 = 0x6C65_7474_6572_7331
    static let rival: UInt64 = 0x7269_7661_6C21_0042
    static let pilot: UInt64 = 0x7069_6C6F_7400_1337

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

    /// 0 ..< count
    mutating func index(_ count: Int) -> Int {
        Swift.max(0, Swift.min(count - 1, Int(next() * Double(count))))
    }
}

// MARK: - Colour

enum LetterRushInk {
    static let paper = Color(red: 0.925, green: 0.910, blue: 0.882)       // ECE8E1
    static let card = Color(red: 0.973, green: 0.965, blue: 0.945)        // F8F6F1
    static let cardEdge = Color(red: 0.835, green: 0.815, blue: 0.780)    // D5D0C7
    static let ink = Color(red: 0.082, green: 0.078, blue: 0.071)         // 151412
    static let inkSoft = Color(red: 0.42, green: 0.40, blue: 0.37)
    static let muted = Color(red: 0.56, green: 0.54, blue: 0.50)
    static let gold = Color(red: 0.961, green: 0.702, blue: 0.004)        // F5B301
    static let goldEdge = Color(red: 0.788, green: 0.557, blue: 0.0)      // C98E00
    static let goldLine = Color(red: 0.86, green: 0.60, blue: 0.0)
    static let goldText = Color(red: 0.62, green: 0.42, blue: 0.0)
    static let coral = Color(red: 0.90, green: 0.33, blue: 0.27)
    static let peach = Color(red: 1.0, green: 0.73, blue: 0.47)
    static let white = Color.white
}

// MARK: - One moment of the game

enum LetterRushWordState: Equatable {
    /// Nothing is being dragged.
    case empty
    /// Fewer than three letters.
    case short
    /// A real word that has not been found yet. The points it is worth.
    case valid(Int)
    /// A real word found earlier in this round.
    case found
    /// Not a word the game knows.
    case unknown
}

/// A "+400" rising from a tile.
struct LetterRushPop {
    var text: String
    var cell: Int
    var age: Double
    var big: Bool
}

/// A speck of gold from a good word.
struct LetterRushSpark {
    var cell: Int
    var angle: Double
    var speed: Double
    var age: Double
}

/// Everything the painter needs for one frame.
struct LetterRushFrame {
    var letters: [Character] = Array(repeating: " ", count: 16)
    /// The tiles under the finger, in order.
    var path: [Int] = []
    /// Seconds since each tile joined the path. 10 when it is not in the path.
    var joinAge: [Double] = Array(repeating: 10, count: 16)
    var word: String = ""
    var wordState: LetterRushWordState = .empty
    var score: Int = 0
    /// The score as the counter shows it, on its way up to the real score.
    var shownScore: Double = 0
    var wordCount: Int = 0
    var timeLeft: Double = 80
    var rivalName: String? = nil
    var rivalScore: Int = 0
    var rivalWords: Int = 0
    /// Seconds since the other player last found a word.
    var rivalAge: Double = 10
    var pops: [LetterRushPop] = []
    var sparks: [LetterRushSpark] = []
    /// The last words found, newest last.
    var recent: [String] = []
    /// Seconds since a word was turned down.
    var shakeAge: Double = 10
    var praise: String? = nil
    var praiseAge: Double = 10
    /// Shown over the board once the clock runs out.
    var banner: String? = nil
    var bannerAge: Double = 0
    var ambient: Double = 0
    var hintAlpha: Double = 1
}

// MARK: - Layout

/// Where everything sits, in points. The stage is 402 x 874; smaller phones scale the part under
/// the app's top band, thumbnails centre the grid.
struct LetterRushLayout {
    static let tileSize: CGFloat = 84
    static let tilePitch: CGFloat = 98
    static let gridWidth: CGFloat = 3 * 98 + 84

    let w: CGFloat
    let h: CGFloat
    let u: CGFloat
    let midX: CGFloat
    let timerY: CGFloat
    let rivalY: CGFloat
    let bubbleY: CGFloat
    let gridTop: CGFloat
    let gridLeft: CGFloat
    let tile: CGFloat
    let pitch: CGFloat
    let hintY: CGFloat
    let margin: CGFloat

    init(size: CGSize, showHUD: Bool) {
        let width: CGFloat = Swift.max(size.width, 1)
        let height: CGFloat = Swift.max(size.height, 1)
        w = width
        h = height
        midX = width / 2
        let unit: CGFloat
        if height / width >= 1.7 {
            // A phone. The app's buttons own the top band; everything under it scales to fit.
            let band: CGFloat = GameLayout.topBand
            let room: CGFloat = height - band - GameLayout.bottomInset
            unit = Swift.min(width / 402, room / (874 - 108 - 38))
            timerY = band + 22 * unit
            rivalY = band + 62 * unit
            bubbleY = band + 130 * unit
            gridTop = band + 178 * unit
            hintY = band + 178 * unit + LetterRushLayout.gridWidth * unit + 42 * unit
        } else {
            // A thumbnail or a crop: the grid and the word above it, centred.
            let head: CGFloat = showHUD ? 92 : 0
            let block: CGFloat = head + 70 + LetterRushLayout.gridWidth + 24
            unit = Swift.min(width / 402, height / (block + 40))
            let top: CGFloat = (height - block * unit) / 2
            timerY = top + 18 * unit
            rivalY = top + 56 * unit
            bubbleY = top + (head + 32) * unit
            gridTop = top + (head + 70) * unit
            hintY = top + (head + 70) * unit + LetterRushLayout.gridWidth * unit + 20 * unit
        }
        u = unit
        tile = LetterRushLayout.tileSize * unit
        pitch = LetterRushLayout.tilePitch * unit
        gridLeft = width / 2 - LetterRushLayout.gridWidth * unit / 2
        margin = Swift.max(16 * unit, width / 2 - 190 * unit)
    }

    func center(_ cell: Int) -> CGPoint {
        let row = cell / 4
        let column = cell % 4
        return CGPoint(x: gridLeft + tile / 2 + CGFloat(column) * pitch, y: gridTop + tile / 2 + CGFloat(row) * pitch)
    }

    func tileRect(_ cell: Int) -> CGRect {
        let c = center(cell)
        return CGRect(x: c.x - tile / 2, y: c.y - tile / 2, width: tile, height: tile)
    }

    /// The tile under a finger. A drag only catches a tile near its middle, so a diagonal pass
    /// between two tiles picks up neither. loose takes the whole tile, for the first touch.
    func cell(at point: CGPoint, loose: Bool) -> Int? {
        let column = Int(floor((point.x - gridLeft) / pitch))
        let row = Int(floor((point.y - gridTop) / pitch))
        guard row >= 0, row < 4, column >= 0, column < 4 else { return nil }
        let cell = row * 4 + column
        let c = center(cell)
        let dx = point.x - c.x
        let dy = point.y - c.y
        let reach: CGFloat = loose ? tile * 0.52 : tile * 0.44
        return dx * dx + dy * dy <= reach * reach ? cell : nil
    }
}

// MARK: - Pictures

/// The game's pictures, resolved once per frame.
struct LetterRushArt {
    let background: GraphicsContext.ResolvedImage
    let tray: GraphicsContext.ResolvedImage
    let tile: GraphicsContext.ResolvedImage
    let tilePicked: GraphicsContext.ResolvedImage
    let spark: GraphicsContext.ResolvedImage

    init(_ ctx: GraphicsContext) {
        func load(_ name: String) -> GraphicsContext.ResolvedImage { ctx.resolve(Image("letter-rush-" + name)) }
        background = load("background")
        tray = load("tray")
        tile = load("tile")
        tilePicked = load("tile-picked")
        spark = load("spark")
    }
}

// MARK: - Painter

struct LetterRushPainter {
    typealias M = LetterRushMath
    typealias Ink = LetterRushInk

    let frame: LetterRushFrame
    let showHUD: Bool
    let layout: LetterRushLayout

    init(size: CGSize, frame: LetterRushFrame, showHUD: Bool) {
        self.frame = frame
        self.showHUD = showHUD
        layout = LetterRushLayout(size: size, showHUD: showHUD)
    }

    var u: CGFloat { layout.u }

    func draw(_ ctx: inout GraphicsContext) {
        let art = LetterRushArt(ctx)
        let back = art.background.size
        let fill = Swift.max(layout.w / back.width, layout.h / back.height)
        let bw = back.width * fill
        let bh = back.height * fill
        ctx.draw(art.background, in: CGRect(x: (layout.w - bw) / 2, y: (layout.h - bh) / 2, width: bw, height: bh))
        let side = LetterRushLayout.gridWidth * u
        drawTray(&ctx, art.tray, in: CGRect(x: layout.gridLeft - 12 * u, y: layout.gridTop - 12 * u, width: side + 24 * u, height: side + 29 * u))
        if showHUD { drawHeader(&ctx) }
        drawBubble(&ctx)
        drawTiles(&ctx, art)
        drawPath(&ctx)
        drawLetters(&ctx)
        drawSparks(&ctx, art)
        drawPops(&ctx)
        if showHUD { drawFooter(&ctx) }
        drawPraise(&ctx)
        drawBanner(&ctx)
    }

    // MARK: Text

    func styled(_ words: String, size: CGFloat, weight: Font.Weight, design: Font.Design = .default,
                tracking: CGFloat = 0, color: Color) -> Text {
        Text(words).font(.system(size: size, weight: weight, design: design)).tracking(tracking).foregroundColor(color)
    }

    func label(_ ctx: inout GraphicsContext, _ words: String, size: CGFloat, weight: Font.Weight,
               design: Font.Design = .default, tracking: CGFloat = 0, color: Color,
               at point: CGPoint, anchor: UnitPoint = .center) {
        let text = styled(words, size: size, weight: weight, design: design, tracking: tracking, color: color)
        ctx.draw(ctx.resolve(text), at: point, anchor: anchor)
    }

    func width(_ ctx: GraphicsContext, _ text: Text) -> CGFloat {
        ctx.resolve(text).measure(in: CGSize(width: 2000, height: 200)).width
    }

    func soft(_ rect: CGRect, _ radius: CGFloat) -> Path {
        Path(roundedRect: rect, cornerRadius: radius, style: .continuous)
    }

    func pill(_ rect: CGRect) -> Path {
        Path(roundedRect: rect, cornerRadius: rect.height / 2, style: .circular)
    }

    static func grouped(_ n: Int) -> String {
        var digits = String(Swift.max(0, n))
        var out = ""
        while digits.count > 3 {
            out = "," + String(digits.suffix(3)) + out
            digits = String(digits.dropLast(3))
        }
        return digits + out
    }

    static func clock(_ seconds: Double) -> String {
        let whole = Swift.max(0, Int(ceil(seconds)))
        let tail = whole % 60
        return "\(whole / 60):" + (tail < 10 ? "0" : "") + "\(tail)"
    }

    static func words(_ n: Int) -> String { n == 1 ? "1 word" : "\(n) words" }

    // MARK: Tray

    /// The tray under the tiles, stretched with its rim kept thin: the outer 14% of the picture on
    /// each edge maps to a fixed corner size.
    func drawTray(_ ctx: inout GraphicsContext, _ image: GraphicsContext.ResolvedImage, in rect: CGRect) {
        let corner = 23 * u
        let cuts: [CGFloat] = [0, 0.14, 0.86, 1]
        let xs: [CGFloat] = [rect.minX, rect.minX + corner, rect.maxX - corner, rect.maxX]
        let ys: [CGFloat] = [rect.minY, rect.minY + corner, rect.maxY - corner, rect.maxY]
        for i in 0..<3 {
            for j in 0..<3 {
                let piece = CGRect(x: xs[i], y: ys[j], width: xs[i + 1] - xs[i], height: ys[j + 1] - ys[j])
                let fw = piece.width / (cuts[i + 1] - cuts[i])
                let fh = piece.height / (cuts[j + 1] - cuts[j])
                var part = ctx
                part.clip(to: Path(piece.insetBy(dx: -0.3, dy: -0.3)))
                part.draw(image, in: CGRect(x: xs[i] - cuts[i] * fw, y: ys[j] - cuts[j] * fh, width: fw, height: fh))
            }
        }
    }

    // MARK: Header

    func drawHeader(_ ctx: inout GraphicsContext) {
        let left = layout.margin
        let right = layout.w - layout.margin

        // The clock, red and beating through the last ten seconds.
        let low = frame.timeLeft <= 10 && frame.banner == nil
        var clockColor = Ink.ink
        var clockSize = 24 * u
        if low {
            clockColor = Ink.coral
            let beat = frame.timeLeft - floor(frame.timeLeft)
            clockSize *= 1 + 0.08 * CGFloat(1 - M.easeOut(1 - beat))
        }
        label(&ctx, LetterRushPainter.clock(frame.timeLeft), size: clockSize, weight: .bold, design: .rounded,
              color: clockColor, at: CGPoint(x: left, y: layout.timerY), anchor: .leading)

        // The player's score and word count, counting up.
        let shown = Int(frame.shownScore.rounded())
        let scoreText = "\(LetterRushPainter.grouped(shown)) pts  ·  \(LetterRushPainter.words(frame.wordCount))"
        label(&ctx, scoreText, size: 19 * u, weight: .bold, design: .rounded, color: Ink.ink,
              at: CGPoint(x: right, y: layout.timerY), anchor: .trailing)

        // The other player, with a little pulse when they find a word.
        guard let name = frame.rivalName else {
            label(&ctx, "Solo round", size: 15 * u, weight: .semibold, design: .rounded, color: Ink.muted,
                  at: CGPoint(x: left, y: layout.rivalY), anchor: .leading)
            return
        }
        let pulse = 1 - M.easeOut(frame.rivalAge / 0.5)
        let r = 14 * u * (1 + 0.18 * CGFloat(pulse))
        let badge = CGRect(x: left, y: layout.rivalY - r, width: 2 * r, height: 2 * r)
        ctx.fill(Path(ellipseIn: badge), with: .color(Ink.peach))
        let initial = String(name.prefix(1)).uppercased()
        label(&ctx, initial, size: 13 * u, weight: .heavy, design: .rounded, color: Ink.ink,
              at: CGPoint(x: badge.midX, y: badge.midY))
        let short = String(name.prefix(12))
        let line = "\(short) \(LetterRushPainter.grouped(frame.rivalScore))  ·  \(LetterRushPainter.words(frame.rivalWords))"
        label(&ctx, line, size: 16 * u, weight: .semibold, design: .rounded, color: pulse > 0.02 ? Ink.ink : Ink.inkSoft,
              at: CGPoint(x: left + 2 * r + 10 * u, y: layout.rivalY), anchor: .leading)
    }

    // MARK: The word being made

    func drawBubble(_ ctx: inout GraphicsContext) {
        let word = frame.word
        if word.isEmpty { return }
        var shake: CGFloat = 0
        if frame.shakeAge < 0.35 {
            let k = frame.shakeAge / 0.35
            shake = CGFloat(sin(k * .pi * 5) * (1 - k)) * 9 * u
        }

        var fill = Ink.ink
        var edge = Ink.ink
        var textColor = Ink.white
        var caption: String? = nil
        var captionColor = Ink.goldText
        switch frame.wordState {
        case .valid(let points):
            fill = Ink.gold
            edge = Ink.goldEdge
            textColor = Ink.ink
            caption = "+\(points)"
        case .found:
            fill = Ink.cardEdge
            edge = Ink.muted
            textColor = Ink.inkSoft
            caption = "found"
            captionColor = Ink.muted
        case .unknown, .short, .empty:
            break
        }

        let size = 30 * u
        let text = styled(word, size: size, weight: .heavy, design: .rounded, tracking: 4 * u, color: textColor)
        let textWidth = width(ctx, text)
        let boxW = Swift.max(textWidth + 48 * u, 110 * u)
        let boxH = 54 * u
        let box = CGRect(x: layout.midX - boxW / 2 + shake, y: layout.bubbleY - boxH / 2, width: boxW, height: boxH)
        ctx.fill(soft(box.offsetBy(dx: 0, dy: 4 * u), 16 * u), with: .color(edge))
        ctx.fill(soft(box, 16 * u), with: .color(fill))
        ctx.draw(ctx.resolve(text), at: CGPoint(x: box.midX + 2 * u, y: box.midY - 1 * u), anchor: .center)

        if let caption {
            label(&ctx, caption, size: 18 * u, weight: .heavy, design: .rounded, color: captionColor,
                  at: CGPoint(x: box.maxX + 10 * u, y: box.midY), anchor: .leading)
        }
    }

    // MARK: Grid

    func drawTiles(_ ctx: inout GraphicsContext, _ art: LetterRushArt) {
        let lift = 5 * u
        for cell in 0..<16 {
            let rect = layout.tileRect(cell)
            let picked = frame.joinAge[cell] < 10
            var scale: CGFloat = 1
            if picked {
                scale = 1 + 0.07 * CGFloat(M.outBack(frame.joinAge[cell] / 0.14))
            }
            let r = rect.insetBy(dx: rect.width * (1 - scale) / 2, dy: rect.height * (1 - scale) / 2)
            ctx.draw(picked ? art.tilePicked : art.tile, in: CGRect(x: r.minX, y: r.minY, width: r.width, height: r.height + lift))
        }
    }

    func drawPath(_ ctx: inout GraphicsContext) {
        guard frame.path.count >= 2 else { return }
        var line = Path()
        line.move(to: layout.center(frame.path[0]))
        for k in 1..<frame.path.count { line.addLine(to: layout.center(frame.path[k])) }
        ctx.stroke(line, with: .color(Ink.goldLine.opacity(0.55)),
                   style: StrokeStyle(lineWidth: 9 * u, lineCap: .round, lineJoin: .round))
    }

    func drawLetters(_ ctx: inout GraphicsContext) {
        let size = 40 * u
        for cell in 0..<16 {
            var c = layout.center(cell)
            if frame.joinAge[cell] < 10 {
                let scale = 1 + 0.07 * CGFloat(M.outBack(frame.joinAge[cell] / 0.14))
                c.y -= layout.tile * (scale - 1) / 2
            }
            label(&ctx, String(frame.letters[cell]), size: size, weight: .heavy, color: Ink.ink,
                  at: CGPoint(x: c.x, y: c.y - 1 * u))
        }
    }

    // MARK: Juice

    func drawSparks(_ ctx: inout GraphicsContext, _ art: LetterRushArt) {
        var glow = ctx
        for spark in frame.sparks {
            let k = M.clamp(spark.age / 0.7)
            if k >= 1 { continue }
            let travel = M.easeOut(k) * spark.speed
            let c = layout.center(spark.cell)
            let p = CGPoint(x: c.x + CGFloat(cos(spark.angle) * travel) * u,
                            y: c.y + CGFloat(sin(spark.angle) * travel - 30 * k * k) * u)
            let r = CGFloat(4.5 - 3.5 * k) * u * 2.4
            glow.opacity = 1 - k * k
            glow.draw(art.spark, in: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
        }
    }

    func drawPops(_ ctx: inout GraphicsContext) {
        for pop in frame.pops {
            let k = M.clamp(pop.age / 0.9)
            if k >= 1 { continue }
            let arrive = CGFloat(M.outBack(pop.age / 0.14))
            let rise = CGFloat(M.easeOut(k)) * 54 * u
            let alpha = 1 - M.smooth(0.6, 1, k)
            let c = layout.center(pop.cell)
            let size = (pop.big ? 30 : 24) * u * arrive
            let text = styled(pop.text, size: size, weight: .black, design: .rounded, color: Ink.goldText.opacity(alpha))
            let under = styled(pop.text, size: size, weight: .black, design: .rounded, color: Ink.white.opacity(alpha * 0.9))
            let at = CGPoint(x: c.x, y: c.y - rise)
            ctx.draw(ctx.resolve(under), at: CGPoint(x: at.x, y: at.y + 2 * u), anchor: .center)
            ctx.draw(ctx.resolve(text), at: at, anchor: .center)
        }
    }

    func drawPraise(_ ctx: inout GraphicsContext) {
        guard let praise = frame.praise, frame.praiseAge < 1.1 else { return }
        let arrive = CGFloat(M.outBack(frame.praiseAge / 0.16))
        let alpha = 1 - M.smooth(0.75, 1.1, frame.praiseAge)
        let y = layout.bubbleY - 48 * u - CGFloat(M.easeOut(frame.praiseAge / 1.1)) * 10 * u
        label(&ctx, praise, size: 22 * u * arrive, weight: .black, design: .rounded, tracking: 1.5 * u,
              color: Ink.ink.opacity(alpha), at: CGPoint(x: layout.midX, y: y))
    }

    // MARK: Under the grid

    func drawFooter(_ ctx: inout GraphicsContext) {
        if frame.recent.isEmpty {
            let alpha = frame.hintAlpha
            if alpha <= 0.01 { return }
            label(&ctx, "Drag through touching letters. Lift to submit.", size: 15 * u, weight: .medium,
                  design: .rounded, color: Ink.muted.opacity(alpha), at: CGPoint(x: layout.midX, y: layout.hintY))
            return
        }
        // The last few words as small chips, newest on the right.
        let size = 13 * u
        var chips: [Text] = []
        var widths: [CGFloat] = []
        var total: CGFloat = 0
        let gap = 8 * u
        for word in frame.recent.suffix(6).reversed() {
            let text = styled(word, size: size, weight: .bold, design: .rounded, tracking: 1 * u, color: Ink.inkSoft)
            let w = width(ctx, text) + 18 * u
            let lead: CGFloat = chips.isEmpty ? 0 : gap
            if total + w + lead > layout.w - 2 * layout.margin { break }
            total += w + lead
            chips.append(text)
            widths.append(w)
        }
        var x = layout.midX + total / 2
        for k in chips.indices {
            let w = widths[k]
            let rect = CGRect(x: x - w, y: layout.hintY - 13 * u, width: w, height: 26 * u)
            ctx.fill(pill(rect), with: .color(Ink.card))
            ctx.draw(ctx.resolve(chips[k]), at: CGPoint(x: rect.midX, y: rect.midY), anchor: .center)
            x -= w + gap
        }
    }

    // MARK: The end

    func drawBanner(_ ctx: inout GraphicsContext) {
        guard let banner = frame.banner else { return }
        let age = frame.bannerAge
        let veil = M.smooth(0, 0.3, age) * 0.55
        ctx.fill(Path(CGRect(x: 0, y: 0, width: layout.w, height: layout.h)), with: .color(Ink.paper.opacity(veil)))
        let arrive = CGFloat(M.outBack(age / 0.22))
        let y = layout.gridTop + LetterRushLayout.gridWidth * u / 2
        let text = styled(banner, size: 54 * u * arrive, weight: .black, design: .rounded, tracking: 4 * u, color: Ink.ink)
        let w = width(ctx, text) + 60 * u
        let box = CGRect(x: layout.midX - w / 2, y: y - 46 * u, width: w, height: 92 * u)
        ctx.fill(soft(box.offsetBy(dx: 0, dy: 6 * u), 24 * u), with: .color(Ink.goldEdge.opacity(Double(arrive))))
        ctx.fill(soft(box, 24 * u), with: .color(Ink.gold.opacity(Double(arrive))))
        ctx.draw(ctx.resolve(text), at: CGPoint(x: box.midX + 2 * u, y: box.midY), anchor: .center)
    }
}

// MARK: - The clip

/// A fixed round for covers and the Videos feed: the same board and the same words every time.
enum LetterRushClip {
    static let letters: [Character] = Array("STAOELRNPIMEDCHK")

    /// A word, the tiles it runs through, and the slice of the clip it takes.
    struct Beat {
        let word: String
        let path: [Int]
        let from: Double
        let to: Double
    }

    static let beats: [Beat] = [
        Beat(word: "STAR", path: [0, 1, 2, 6], from: 0.0, to: 0.14),
        Beat(word: "ONE", path: [3, 7, 11], from: 0.14, to: 0.24),
        Beat(word: "PLATE", path: [8, 5, 2, 1, 4], from: 0.24, to: 0.42),
        Beat(word: "MILE", path: [10, 9, 5, 4], from: 0.42, to: 0.54),
        Beat(word: "CHIME", path: [13, 14, 9, 10, 11], from: 0.54, to: 0.72),
        Beat(word: "STARE", path: [0, 1, 2, 6, 11], from: 0.72, to: 0.90),
        Beat(word: "ORE", path: [3, 6, 11], from: 0.90, to: 1.0),
    ]

    /// Words the scripted drags pass through on the way, so the bubble turns gold at the right moments.
    static let passing: Set<String> = ["ONE", "STAR", "ORE", "PLAT", "CHI"]

    static func points(_ length: Int) -> Int {
        switch length {
        case ..<3: return 0
        case 3: return 100
        case 4: return 400
        case 5: return 800
        case 6: return 1400
        case 7: return 1800
        default: return 2200
        }
    }

    static func frame(at raw: Double) -> LetterRushFrame {
        let phase = LetterRushMath.clamp(raw)
        var frame = LetterRushFrame()
        frame.letters = letters
        frame.rivalName = "kaz"
        frame.timeLeft = 80 * (1 - phase)
        frame.ambient = phase * 80
        frame.hintAlpha = 1
        frame.rivalWords = Swift.min(9, Int(phase * 10))
        let rivalScores = [0, 100, 500, 600, 1000, 1400, 1500, 1900, 2300, 2400]
        frame.rivalScore = rivalScores[frame.rivalWords]
        frame.rivalAge = 10

        // Beats that are over count as found; the one in progress is being dragged.
        let dragPart = 0.78
        for beat in beats {
            let length = beat.to - beat.from
            if phase >= beat.to {
                frame.score += points(beat.word.count)
                frame.wordCount += 1
                frame.recent.append(beat.word)
                continue
            }
            if phase < beat.from { break }
            let k = (phase - beat.from) / length
            if k < dragPart {
                let stepTime = dragPart / Double(beat.path.count)
                let lit = Swift.min(beat.path.count, Int(k / stepTime) + 1)
                let sinceJoin = (k - Double(lit - 1) * stepTime) * length * 80
                frame.path = Array(beat.path.prefix(lit))
                for n in 0..<lit {
                    frame.joinAge[beat.path[n]] = n == lit - 1 ? Swift.max(0, sinceJoin) : 9
                }
                frame.word = String(beat.word.prefix(lit))
                if lit < 3 {
                    frame.wordState = .short
                } else if lit == beat.path.count || passing.contains(frame.word) {
                    frame.wordState = .valid(points(lit))
                } else {
                    frame.wordState = .unknown
                }
            } else {
                // Lifted: the points pop from the last tile and the score counts up.
                let since = (k - dragPart) * length * 80
                let last = beat.path[beat.path.count - 1]
                frame.score += points(beat.word.count)
                frame.wordCount += 1
                frame.recent.append(beat.word)
                frame.pops.append(LetterRushPop(text: "+\(points(beat.word.count))", cell: last, age: since,
                                                big: beat.word.count >= 5))
                if beat.word.count >= 5 {
                    frame.praise = beat.word.count >= 6 ? "Great" : "Nice"
                    frame.praiseAge = since
                    for n in 0..<10 {
                        frame.sparks.append(LetterRushSpark(cell: last, angle: Double(n) / 10 * .pi * 2 + 0.3,
                                                            speed: 36 + Double(n % 3) * 12, age: since))
                    }
                }
            }
            break
        }
        frame.shownScore = Double(frame.score)
        return frame
    }
}
