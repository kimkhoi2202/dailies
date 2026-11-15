import SwiftUI

// Letter Rush: drag through touching letters on a 4x4 board to make words before the clock runs out.
//
// The whole picture is painted into one Canvas by LetterRushPainter from a LetterRushFrame, plain
// data that says what is on screen. The clip in the video feed builds a frame from a phase (0...1)
// and a fixed script; the playable game builds one from its live model. No assets, any frame size.

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
            let frame = LetterRushFrame.scripted(phase: phase, showHUD: showHUD)
            LetterRushPainter(size: size, frame: frame).draw(&context)
        }
    }
}

// MARK: - Numbers

enum LetterRushMath {
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

    /// 0 -> 1 with a springy overshoot, settling at 1.
    static func spring(_ t: Double) -> Double {
        if t <= 0 { return 0 }
        if t >= 1 { return 1 }
        return 1 - exp(-6 * t) * cos(9 * t)
    }

    /// A quick bump: 0 at rest, up to 1 and back over `length` seconds.
    static func bump(_ age: Double, _ length: Double) -> Double {
        if age < 0 || age >= length { return 0 }
        return sin(Double.pi * age / length)
    }

    /// 12400 -> "12,400".
    static func grouped(_ value: Int) -> String {
        let digits = String(abs(value))
        if digits.count <= 3 { return value < 0 ? "-" + digits : digits }
        var out = ""
        for (k, ch) in digits.enumerated() {
            if k > 0, (digits.count - k) % 3 == 0 { out.append(",") }
            out.append(ch)
        }
        return value < 0 ? "-" + out : out
    }

    /// Points for a word of this many letters.
    static func points(_ letters: Int) -> Int {
        switch letters {
        case ..<3: return 0
        case 3: return 100
        case 4: return 400
        case 5: return 800
        case 6: return 1400
        case 7: return 1800
        default: return 2200
        }
    }
}

/// SplitMix64. The board, the friend and the scripted player use different salts.
struct LetterRushRandom {
    static let board: UInt64 = 0x2545F4914F6CDD1D
    static let friend: UInt64 = 0xD1B54A32D192ED03
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

    /// 0 ..< count
    mutating func int(_ count: Int) -> Int {
        count <= 1 ? 0 : Swift.min(count - 1, Int(next() * Double(count)))
    }
}

// MARK: - Colour

enum LetterRushInk {
    static let paper = Color(red: 0.925, green: 0.910, blue: 0.882)
    static let paperDeep = Color(red: 0.890, green: 0.871, blue: 0.835)
    static let card = Color(red: 0.973, green: 0.965, blue: 0.945)
    static let cardLip = Color(red: 0.835, green: 0.808, blue: 0.761)
    static let ink = Color(red: 0.082, green: 0.078, blue: 0.071)
    static let mute = Color(red: 0.44, green: 0.42, blue: 0.39)
    static let gold = Color(red: 0.961, green: 0.702, blue: 0.004)
    static let goldLight = Color(red: 1.0, green: 0.80, blue: 0.22)
    static let goldLip = Color(red: 0.76, green: 0.53, blue: 0.0)
    static let goldText = Color(red: 0.58, green: 0.38, blue: 0.0)
    static let coral = Color(red: 0.93, green: 0.38, blue: 0.33)
    static let coralLip = Color(red: 0.70, green: 0.24, blue: 0.21)
    static let slate = Color(red: 0.66, green: 0.65, blue: 0.62)
    static let slateLip = Color(red: 0.50, green: 0.49, blue: 0.46)
    static let you = Color(red: 0.84, green: 0.96, blue: 0.24)
    static let friend = Color(red: 1.0, green: 0.68, blue: 0.36)
    static let mint = Color(red: 0.20, green: 0.72, blue: 0.56)
}

// MARK: - Frame

struct LetterRushFloater {
    var text: String
    var x: Double
    var y: Double
    var age: Double
}

struct LetterRushParticle {
    var x: Double
    var y: Double
    var vx: Double
    var vy: Double
    var age: Double
    var life: Double
    var turn: Double
    var size: Double
    var tone: Int
}

struct LetterRushWordRow {
    let word: String
    let points: Int
}

enum LetterRushWordState { case none, short, valid, found, unknown }
enum LetterRushVerdict { case none, good, bad, dup }

/// The end of the round, as the results card shows it.
struct LetterRushResults {
    var youScore = 0
    var youWords = 0
    var friendName: String?
    var friendScore = 0
    var friendWords = 0
    var top: [LetterRushWordRow] = []
    var bestMissed: String?
}

/// Everything the painter needs for one picture.
struct LetterRushFrame {
    var letters: [String] = Array(repeating: "A", count: 16)
    var path: [Int] = []
    var selected: [Bool] = Array(repeating: false, count: 16)
    /// Seconds since each tile last popped.
    var popAge: [Double] = Array(repeating: 9, count: 16)
    var verdict = LetterRushVerdict.none
    var verdictTiles: [Int] = []
    var verdictWord = ""
    var verdictAge = 9.0
    var word = ""
    var wordState = LetterRushWordState.none
    var score = 0
    var words = 0
    var timeLeft = 80.0
    var roundLength = 80.0
    var showHUD = true
    var friendName: String?
    var friendScore = 0
    var friendWords = 0
    var friendFlash = 9.0
    var floaters: [LetterRushFloater] = []
    var particles: [LetterRushParticle] = []
    var praise = ""
    var praiseAge = 9.0
    var hint = ""
    var hintAlpha = 0.0
    var recent: [LetterRushWordRow] = []
    var ambient = 0.0
    /// Seconds into the ending. nil while the round runs.
    var ending: Double?
    var results = LetterRushResults()
    var canContinue = false
}

// MARK: - Layout

/// Where everything sits. The game and the painter use the same numbers, so a touch lands on the
/// tile the player sees.
struct LetterRushLayout {
    let width: Double
    let height: Double
    let u: Double
    let tile: Double
    let gap: Double
    let gridX: Double
    let gridY: Double

    init(size: CGSize) {
        width = Double(size.width)
        height = Double(size.height)
        u = Swift.min(width / 402, height / 760)
        let side = 18 * u
        gap = 11 * u
        tile = (width - 2 * side - 3 * gap) / 4
        gridX = (width - (4 * tile + 3 * gap)) / 2
        let roomy = 268 * u + (height - 874 * u) * 0.25
        gridY = Swift.min(Swift.max(height * 0.305, 238 * u), roomy)
    }

    var gridSize: Double { 4 * tile + 3 * gap }
    var scoreY: Double { Double(GameLayout.statusBarHeight) + 22 }
    var wordsY: Double { scoreY + 27 }
    var infoY: Double { Double(GameLayout.topBand) + 26 * u }
    var barY: Double { infoY + 26 * u }
    var pillY: Double { gridY - 46 * u }
    var hintY: Double { gridY + gridSize + 34 * u }
    var recentTop: Double { hintY + 28 * u }

    func center(_ index: Int) -> CGPoint {
        let col = Double(index % 4)
        let row = Double(index / 4)
        return CGPoint(x: gridX + col * (tile + gap) + tile / 2, y: gridY + row * (tile + gap) + tile / 2)
    }

    /// The cell under a point, gaps included. nil outside the board.
    func cell(at p: CGPoint) -> Int? {
        let x = (Double(p.x) - gridX + gap / 2) / (tile + gap)
        let y = (Double(p.y) - gridY + gap / 2) / (tile + gap)
        if x < 0 || y < 0 || x >= 4 || y >= 4 { return nil }
        return Int(y) * 4 + Int(x)
    }

    /// The tile under a point, counting only a circle in the middle of each tile, so a diagonal
    /// drag passes the corners of its neighbours without picking them.
    func tile(at p: CGPoint) -> Int? {
        guard let index = cell(at: p) else { return nil }
        let c = center(index)
        let dx = Double(p.x - c.x)
        let dy = Double(p.y - c.y)
        let r = tile * 0.46
        return dx * dx + dy * dy <= r * r ? index : nil
    }
}

// MARK: - Painter

struct LetterRushPainter {
    typealias M = LetterRushMath
    typealias Ink = LetterRushInk

    let frame: LetterRushFrame
    let layout: LetterRushLayout
    let size: CGSize
    let u: Double

    init(size: CGSize, frame: LetterRushFrame) {
        self.size = size
        self.frame = frame
        layout = LetterRushLayout(size: size)
        u = layout.u
    }

    func draw(_ ctx: inout GraphicsContext) {
        drawBackground(&ctx)
        var endK = 0.0
        if let ending = frame.ending { endK = M.smooth(0, 0.45, ending) }
        if frame.showHUD { drawHUD(&ctx, fade: 1 - endK) }
        drawPill(&ctx)
        drawTiles(&ctx, letters: false)
        drawPathLine(&ctx)
        drawTiles(&ctx, letters: true)
        drawParticles(&ctx)
        drawFloaters(&ctx)
        drawPraise(&ctx)
        if frame.showHUD {
            drawHint(&ctx)
            drawRecent(&ctx)
        }
        if let ending = frame.ending { drawEnding(&ctx, ending) }
    }

    // MARK: Background

    private func drawBackground(_ ctx: inout GraphicsContext) {
        let full = CGRect(origin: .zero, size: size)
        ctx.fill(Path(full), with: .linearGradient(
            Gradient(colors: [Ink.paper, Ink.paperDeep]),
            startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: size.width * 0.4, y: size.height)))
        // Soft round shapes drifting slowly behind the board.
        let t = frame.ambient
        for k in 0..<4 {
            let kk = Double(k)
            let x: Double = layout.width * (0.12 + 0.28 * kk) + 18 * u * sin(t * 0.21 + kk * 1.7)
            let band: Double = kk.truncatingRemainder(dividingBy: 3)
            let y: Double = layout.height * (0.16 + 0.23 * band) + 22 * u * cos(t * 0.17 + kk)
            let r: Double = (90 + 40 * kk.truncatingRemainder(dividingBy: 2)) * u
            let rect = CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)
            ctx.fill(Path(ellipseIn: rect), with: .color(Ink.card.opacity(0.32)))
        }
        // The board's tray.
        let pad = 9 * u
        let tray = CGRect(x: layout.gridX - pad, y: layout.gridY - pad,
                          width: layout.gridSize + 2 * pad, height: layout.gridSize + 2 * pad + 6 * u)
        ctx.fill(Path(roundedRect: tray, cornerRadius: 26 * u), with: .color(Ink.cardLip.opacity(0.38)))
    }

    // MARK: Top

    private func drawHUD(_ ctx: inout GraphicsContext, fade: Double) {
        if fade <= 0.01 { return }
        let mid = layout.width / 2
        let scoreText = Text(M.grouped(frame.score))
            .font(.system(size: 34, weight: .black, design: .rounded))
            .foregroundColor(Ink.ink.opacity(fade))
        ctx.draw(scoreText, at: CGPoint(x: mid, y: layout.scoreY), anchor: .center)
        let wordsLine = frame.words == 1 ? "1 word" : "\(frame.words) words"
        let wordsText = Text(wordsLine)
            .font(.system(size: 13.5, weight: .bold, design: .rounded))
            .foregroundColor(Ink.mute.opacity(fade))
        ctx.draw(wordsText, at: CGPoint(x: mid, y: layout.wordsY), anchor: .center)

        // The clock.
        let left = Swift.max(0, frame.timeLeft)
        let secs = Int(left.rounded(.up))
        let urgent = left <= 10 && left > 0
        let pulse: Double = urgent ? 1 + 0.08 * M.bump(1 - left.truncatingRemainder(dividingBy: 1), 1) : 1
        let clockColor = urgent ? Ink.coral : Ink.ink
        let iconX = 31 * u
        let y = layout.infoY
        let ring = CGRect(x: iconX - 9 * u, y: y - 9 * u, width: 18 * u, height: 18 * u)
        ctx.stroke(Path(ellipseIn: ring), with: .color(clockColor.opacity(fade)), lineWidth: 2.4 * u)
        var hand = Path()
        hand.move(to: CGPoint(x: iconX, y: y))
        let angle: Double = (1 - left / frame.roundLength) * 2 * Double.pi - Double.pi / 2
        hand.addLine(to: CGPoint(x: iconX + 5.5 * u * cos(angle), y: y + 5.5 * u * sin(angle)))
        ctx.stroke(hand, with: .color(clockColor.opacity(fade)), style: StrokeStyle(lineWidth: 2.2 * u, lineCap: .round))
        let clockLine = String(format: "%d:%02d", secs / 60, secs % 60)
        let clock = Text(clockLine)
            .font(.system(size: 20 * pulse * u, weight: .heavy, design: .rounded).monospacedDigit())
            .foregroundColor(clockColor.opacity(fade))
        ctx.draw(clock, at: CGPoint(x: iconX + 15 * u, y: y), anchor: .leading)

        if let name = frame.friendName { drawFriendChip(&ctx, name: name, y: y, fade: fade) }

        // Time bar.
        let barX = 22 * u
        let barW = layout.width - 44 * u
        let barH = 6 * u
        let track = CGRect(x: barX, y: layout.barY, width: barW, height: barH)
        ctx.fill(Path(roundedRect: track, cornerRadius: barH / 2), with: .color(Ink.cardLip.opacity(0.6 * fade)))
        let k = M.clamp(left / frame.roundLength)
        if k > 0 {
            let fill = CGRect(x: barX, y: layout.barY, width: Swift.max(barH, barW * k), height: barH)
            let barColor = urgent ? Ink.coral : Ink.ink
            ctx.fill(Path(roundedRect: fill, cornerRadius: barH / 2), with: .color(barColor.opacity(fade)))
        }
    }

    private func drawFriendChip(_ ctx: inout GraphicsContext, name: String, y: Double, fade: Double) {
        let flash = M.bump(frame.friendFlash, 0.45)
        let nameText = Text(String(name.prefix(12)))
            .font(.system(size: 15 * u, weight: .bold, design: .rounded)).foregroundColor(Ink.mute)
        let scoreText = Text("  " + M.grouped(frame.friendScore))
            .font(.system(size: 15 * u, weight: .heavy, design: .rounded)).foregroundColor(Ink.ink)
        let countLine = frame.friendWords == 1 ? " · 1 word" : " · \(frame.friendWords) words"
        let countText = Text(countLine)
            .font(.system(size: 13 * u, weight: .semibold, design: .rounded)).foregroundColor(Ink.mute)
        var layer = ctx
        layer.opacity = fade
        let resolved = layer.resolve(nameText + scoreText + countText)
        let w = Double(resolved.measure(in: size).width)
        let right = layout.width - 22 * u
        let chipH = 34 * u
        let chipX = right - w - chipH - 8 * u
        let chip = CGRect(x: chipX, y: y - chipH / 2, width: right + 12 * u - chipX, height: chipH)
        layer.fill(Path(roundedRect: chip, cornerRadius: chipH / 2), with: .color(Ink.card.opacity(0.75 + 0.25 * flash)))
        let r = 12 * u * (1 + 0.2 * flash)
        let cx = chipX + 17 * u
        let avatar = CGRect(x: cx - r, y: y - r, width: 2 * r, height: 2 * r)
        layer.fill(Path(ellipseIn: avatar), with: .color(Ink.friend))
        let initial = Text(String(name.prefix(1)).uppercased())
            .font(.system(size: 13 * u, weight: .black, design: .rounded)).foregroundColor(Ink.ink)
        layer.draw(initial, at: CGPoint(x: cx, y: y), anchor: .center)
        layer.draw(resolved, at: CGPoint(x: right, y: y), anchor: .trailing)
    }

    // MARK: Current word

    private func drawPill(_ ctx: inout GraphicsContext) {
        let y = layout.pillY
        let x = layout.width / 2
        var word = frame.word
        var fill = Ink.ink
        var textColor = Color.white
        var scale = 1.0
        var alpha = 1.0
        var shake = 0.0
        var note = ""

        if word.isEmpty {
            // After a lift, the word stays a moment to show what it was worth.
            let age = frame.verdictAge
            guard frame.verdict != .none, age < 0.75, !frame.verdictWord.isEmpty else { return }
            word = frame.verdictWord
            alpha = 1 - M.smooth(0.45, 0.75, age)
            switch frame.verdict {
            case .good:
                fill = Ink.gold
                textColor = Ink.ink
                scale = 1 + 0.16 * M.bump(age, 0.24)
            case .bad:
                fill = Ink.coral
                shake = sin(age * 46) * 7 * u * (1 - M.clamp(age / 0.35))
                note = "Not in the list"
            case .dup:
                fill = Ink.slate
                note = "Already found"
            case .none:
                break
            }
        } else {
            switch frame.wordState {
            case .valid:
                fill = Ink.gold
                textColor = Ink.ink
            case .found:
                fill = Ink.slate
            default:
                break
            }
            let last = frame.path.last ?? 0
            scale = 1 + 0.06 * M.bump(frame.popAge[last], 0.14)
        }
        if alpha <= 0.01 { return }

        let letters = Double(word.count)
        let fontSize = 30 * u
        let w: Double = Swift.max(84 * u, letters * fontSize * 0.82 + 44 * u) * scale
        let h: Double = 56 * u * scale
        let rect = CGRect(x: x - w / 2 + shake, y: y - h / 2, width: w, height: h)
        ctx.fill(Path(roundedRect: rect.offsetBy(dx: 0, dy: 4 * u), cornerRadius: 17 * u),
                 with: .color(Ink.ink.opacity(0.18 * alpha)))
        ctx.fill(Path(roundedRect: rect, cornerRadius: 17 * u), with: .color(fill.opacity(alpha)))
        let text = Text(word).font(.system(size: fontSize * scale, weight: .black, design: .rounded))
            .kerning(3 * u).foregroundColor(textColor.opacity(alpha))
        ctx.draw(text, at: CGPoint(x: x + shake, y: y), anchor: .center)

        if !frame.word.isEmpty, frame.wordState == .valid {
            let pts = Text("+\(M.points(frame.word.count))")
                .font(.system(size: 19 * u, weight: .heavy, design: .rounded)).foregroundColor(Ink.goldText)
            ctx.draw(pts, at: CGPoint(x: rect.maxX + 10 * u, y: y), anchor: .leading)
        }
        if !note.isEmpty {
            let caption = Text(note).font(.system(size: 13 * u, weight: .bold, design: .rounded))
                .foregroundColor(Ink.mute.opacity(alpha))
            ctx.draw(caption, at: CGPoint(x: x, y: rect.minY - 13 * u), anchor: .center)
        }
    }

    // MARK: Tiles

    /// Two passes: the faces, then (over the path line) the letters.
    private func drawTiles(_ ctx: inout GraphicsContext, letters: Bool) {
        let lip = 6 * u
        let radius = layout.tile * 0.2
        let showVerdict = frame.verdict != .none && frame.verdictAge < 0.6
        let age = frame.verdictAge
        let k = 1 - M.smooth(0.2, 0.6, age)
        for index in 0..<16 {
            let c = layout.center(index)
            var face = Ink.card
            var under = Ink.cardLip
            var press = 0.0
            var dx = 0.0
            var scale: Double = 1 + 0.12 * M.bump(frame.popAge[index], 0.16)

            if frame.selected[index] {
                face = Ink.gold
                under = Ink.goldLip
                press = 2 * u
            } else if showVerdict, frame.verdictTiles.contains(index) {
                switch frame.verdict {
                case .good:
                    face = k > 0.5 ? Ink.goldLight : Ink.card
                    under = k > 0.5 ? Ink.goldLip : Ink.cardLip
                    scale += 0.14 * M.bump(age, 0.26)
                case .bad:
                    face = k > 0.5 ? Ink.coral : Ink.card
                    under = k > 0.5 ? Ink.coralLip : Ink.cardLip
                    dx = sin(age * 50) * 6 * u * (1 - M.clamp(age / 0.35))
                case .dup:
                    face = k > 0.5 ? Ink.slate : Ink.card
                    under = k > 0.5 ? Ink.slateLip : Ink.cardLip
                case .none:
                    break
                }
            }

            let s = layout.tile * scale
            let x = Double(c.x) - s / 2 + dx
            let y = Double(c.y) - s / 2
            if !letters {
                let base = CGRect(x: x, y: y + lip, width: s, height: s)
                ctx.fill(Path(roundedRect: base, cornerRadius: radius), with: .color(under))
                let top = CGRect(x: x, y: y + press, width: s, height: s)
                ctx.fill(Path(roundedRect: top, cornerRadius: radius), with: .color(face))
                continue
            }
            let letter = Text(frame.letters[index])
                .font(.system(size: s * 0.5, weight: .black, design: .rounded))
                .foregroundColor(Ink.ink)
            ctx.draw(letter, at: CGPoint(x: x + s / 2, y: y + press + s / 2), anchor: .center)
        }
    }

    private func drawPathLine(_ ctx: inout GraphicsContext) {
        if frame.path.isEmpty { return }
        var line = Path()
        for (k, index) in frame.path.enumerated() {
            let c = layout.center(index)
            let p = CGPoint(x: c.x, y: c.y + 2 * u)
            if k == 0 { line.move(to: p) } else { line.addLine(to: p) }
        }
        let color = frame.wordState == .valid ? Ink.goldLip : Ink.ink
        if frame.path.count > 1 {
            ctx.stroke(line, with: .color(color.opacity(0.3)),
                       style: StrokeStyle(lineWidth: 14 * u, lineCap: .round, lineJoin: .round))
        }
        let r = layout.tile * 0.3
        for index in frame.path {
            let c = layout.center(index)
            let dot = CGRect(x: Double(c.x) - r, y: Double(c.y) + 2 * u - r, width: 2 * r, height: 2 * r)
            ctx.fill(Path(ellipseIn: dot), with: .color(color.opacity(0.16)))
        }
    }

    // MARK: Juice

    private func drawParticles(_ ctx: inout GraphicsContext) {
        for p in frame.particles {
            let k = p.age / p.life
            if k >= 1 { continue }
            let alpha = 1 - M.smooth(0.55, 1, k)
            let s = p.size * u * (1 - 0.4 * k)
            let color: Color
            switch p.tone {
            case 0: color = Ink.gold
            case 1: color = Ink.goldLight
            case 2: color = Ink.ink
            default: color = Ink.mint
            }
            var shape = ctx
            shape.translateBy(x: p.x, y: p.y)
            shape.rotate(by: .radians(p.turn + 6 * p.age))
            let piece = CGRect(x: -s / 2, y: -s * 0.3, width: s, height: s * 0.6)
            shape.fill(Path(roundedRect: piece, cornerRadius: s * 0.15), with: .color(color.opacity(alpha)))
        }
    }

    private func drawFloaters(_ ctx: inout GraphicsContext) {
        for f in frame.floaters {
            let k = f.age / 0.95
            if k >= 1 { continue }
            let rise = 46 * u * M.easeOut(k)
            let alpha = 1 - M.smooth(0.55, 1, k)
            let pop = 1 + 0.35 * M.bump(f.age, 0.18)
            let text = Text(f.text).font(.system(size: 26 * u * pop, weight: .black, design: .rounded))
            let y = f.y - rise
            ctx.draw(text.foregroundColor(Ink.ink.opacity(0.18 * alpha)), at: CGPoint(x: f.x, y: y + 2.5 * u), anchor: .center)
            ctx.draw(text.foregroundColor(Ink.goldText.opacity(alpha)), at: CGPoint(x: f.x, y: y), anchor: .center)
        }
    }

    private static let praiseOffsets: [CGSize] = [
        CGSize(width: -2.6, height: 0), CGSize(width: 2.6, height: 0),
        CGSize(width: 0, height: -2.6), CGSize(width: 0, height: 4.4),
    ]

    private func drawPraise(_ ctx: inout GraphicsContext) {
        let age = frame.praiseAge
        if frame.praise.isEmpty || age >= 1.0 { return }
        let grow = M.spring(age / 0.3)
        let alpha = 1 - M.smooth(0.7, 1.0, age)
        let fontSize = 46 * u * (0.6 + 0.4 * grow)
        let y = layout.gridY + layout.gridSize / 2 - 12 * u * M.easeOut(age)
        let text = Text(frame.praise).font(.system(size: fontSize, weight: .black, design: .rounded)).kerning(1.5 * u)
        let x = layout.width / 2
        let edge = text.foregroundColor(Ink.ink.opacity(alpha))
        for o in Self.praiseOffsets {
            ctx.draw(edge, at: CGPoint(x: x + Double(o.width) * u, y: y + Double(o.height) * u), anchor: .center)
        }
        ctx.draw(text.foregroundColor(Ink.gold.opacity(alpha)), at: CGPoint(x: x, y: y), anchor: .center)
    }

    // MARK: Bottom

    private func drawHint(_ ctx: inout GraphicsContext) {
        if frame.hintAlpha <= 0.01 || frame.hint.isEmpty { return }
        let text = Text(frame.hint).font(.system(size: 15.5 * u, weight: .semibold, design: .rounded))
            .foregroundColor(Ink.mute.opacity(frame.hintAlpha))
        ctx.draw(text, at: CGPoint(x: layout.width / 2, y: layout.hintY), anchor: .center)
    }

    private func drawRecent(_ ctx: inout GraphicsContext) {
        if frame.recent.isEmpty { return }
        let floorY = layout.height - Double(GameLayout.bottomInset)
        let chipH = 30 * u
        let gap = 8 * u
        let left = 22 * u
        let right = layout.width - 22 * u
        var x = left
        var y = layout.recentTop
        if y + chipH > floorY { return }
        var k = 0
        for row in frame.recent.reversed() {
            let wordText = Text(row.word).font(.system(size: 14 * u, weight: .heavy, design: .rounded)).foregroundColor(Ink.ink)
            let ptsText = Text("  \(row.points)").font(.system(size: 12 * u, weight: .bold, design: .rounded)).foregroundColor(Ink.goldText)
            let resolved = ctx.resolve(wordText + ptsText)
            let w = Double(resolved.measure(in: size).width) + 24 * u
            if x + w > right {
                x = left
                y += chipH + gap
                if y + chipH > floorY { break }
            }
            let fresh: Double = k == 0 && frame.verdict == .good ? M.spring(Swift.min(1, frame.verdictAge / 0.3)) : 1
            let rect = CGRect(x: x, y: y, width: w, height: chipH)
            var chip = ctx
            chip.opacity = 0.35 + 0.65 * fresh
            chip.fill(Path(roundedRect: rect.offsetBy(dx: 0, dy: 3 * u), cornerRadius: chipH / 2), with: .color(Ink.cardLip))
            chip.fill(Path(roundedRect: rect, cornerRadius: chipH / 2), with: .color(Ink.card))
            chip.draw(resolved, at: CGPoint(x: rect.midX, y: rect.midY), anchor: .center)
            x += w + gap
            k += 1
        }
    }

    // MARK: Ending

    private func drawEnding(_ ctx: inout GraphicsContext, _ age: Double) {
        let veil = M.smooth(0, 0.5, age)
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Ink.paper.opacity(0.94 * veil)))

        let x = layout.width / 2
        let drop = M.spring(M.clamp(age / 0.5))
        let titleY = Double(GameLayout.topBand) + 14 * u - 30 * u * (1 - drop)
        let title = Text("TIME").font(.system(size: 50 * u, weight: .black, design: .rounded)).kerning(2 * u)
            .foregroundColor(Ink.ink.opacity(M.clamp(age / 0.2)))
        ctx.draw(title, at: CGPoint(x: x, y: titleY), anchor: .center)

        let k = M.easeOut(M.clamp((age - 0.35) / 0.45))
        if k <= 0 { return }
        var card = ctx
        card.opacity = k
        card.translateBy(x: 0, y: 40 * u * (1 - k))
        let scoresY = titleY + 84 * u
        drawScores(&card, age: age, y: scoresY)
        let box = drawWordList(&card, top: scoresY + 112 * u)

        if frame.canContinue {
            let pulse = 0.7 + 0.3 * sin(age * 3.4)
            let more = Text("Tap to continue").font(.system(size: 16 * u, weight: .bold, design: .rounded))
                .foregroundColor(Ink.mute.opacity(pulse))
            let y = Swift.min(Double(box.maxY) + 40 * u, layout.height - Double(GameLayout.bottomInset) - 10 * u)
            card.draw(more, at: CGPoint(x: x, y: y), anchor: .center)
        }
    }

    private func drawScores(_ ctx: inout GraphicsContext, age: Double, y: Double) {
        let r = frame.results
        let count = r.friendName == nil ? 1 : 2
        let counting = M.easeOut(M.clamp((age - 0.5) / 0.9))
        for column in 0..<count {
            let isYou = column == 0
            let name = isYou ? "You" : String((r.friendName ?? "").prefix(12))
            let initial = isYou ? "Y" : String(name.prefix(1)).uppercased()
            let score = isYou ? r.youScore : r.friendScore
            let words = isYou ? r.youWords : r.friendWords
            let cx = count == 1 ? layout.width / 2 : layout.width * (isYou ? 0.29 : 0.71)
            let ar = 26 * u
            ctx.fill(Path(ellipseIn: CGRect(x: cx - ar, y: y - ar, width: 2 * ar, height: 2 * ar)),
                     with: .color(isYou ? Ink.you : Ink.friend))
            ctx.draw(Text(initial).font(.system(size: 20 * u, weight: .black, design: .rounded)).foregroundColor(Ink.ink),
                     at: CGPoint(x: cx, y: y), anchor: .center)
            let shown = Int(Double(score) * counting)
            ctx.draw(Text(M.grouped(shown)).font(.system(size: 38 * u, weight: .black, design: .rounded).monospacedDigit())
                        .foregroundColor(Ink.ink),
                     at: CGPoint(x: cx, y: y + 54 * u), anchor: .center)
            let wordsLine = words == 1 ? "1 word" : "\(words) words"
            ctx.draw(Text(name + " · " + wordsLine).font(.system(size: 15 * u, weight: .semibold, design: .rounded))
                        .foregroundColor(Ink.mute),
                     at: CGPoint(x: cx, y: y + 84 * u), anchor: .center)
        }
    }

    private func drawWordList(_ ctx: inout GraphicsContext, top: Double) -> CGRect {
        let r = frame.results
        let rowH = 40 * u
        let room = Int((layout.height - top - 200 * u) / rowH)
        let shown = Swift.min(r.top.count, Swift.max(3, room))
        let extra: Double = r.bestMissed == nil ? 26 * u : 70 * u
        let boxH = Double(Swift.max(shown, 1)) * rowH + extra
        let box = CGRect(x: 26 * u, y: top, width: layout.width - 52 * u, height: boxH)
        ctx.fill(Path(roundedRect: box, cornerRadius: 26 * u), with: .color(Ink.card))
        let inX = Double(box.minX) + 24 * u
        let outX = Double(box.maxX) - 24 * u
        if shown == 0 {
            let empty = Text("No words this round").font(.system(size: 16 * u, weight: .bold, design: .rounded)).foregroundColor(Ink.mute)
            ctx.draw(empty, at: CGPoint(x: Double(box.midX), y: Double(box.minY) + 13 * u + rowH / 2), anchor: .center)
        }
        for i in 0..<shown {
            let row = r.top[i]
            let ry = Double(box.minY) + 13 * u + Double(i) * rowH + rowH / 2
            ctx.draw(Text(row.word).font(.system(size: 17 * u, weight: .heavy, design: .rounded)).foregroundColor(Ink.ink),
                     at: CGPoint(x: inX, y: ry), anchor: .leading)
            ctx.draw(Text("\(row.points)").font(.system(size: 17 * u, weight: .heavy, design: .rounded)).foregroundColor(Ink.ink),
                     at: CGPoint(x: outX, y: ry), anchor: .trailing)
            var rule = Path()
            rule.move(to: CGPoint(x: inX, y: ry + rowH / 2))
            rule.addLine(to: CGPoint(x: outX, y: ry + rowH / 2))
            ctx.stroke(rule, with: .color(Ink.cardLip.opacity(0.7)), lineWidth: 1.2 * u)
        }
        if r.top.count > shown {
            let more = Text("and \(r.top.count - shown) more").font(.system(size: 13 * u, weight: .semibold, design: .rounded))
                .foregroundColor(Ink.mute)
            ctx.draw(more, at: CGPoint(x: outX, y: Double(box.maxY) - extra + 18 * u), anchor: .trailing)
        }
        if let missed = r.bestMissed {
            let lead = Text("Best word nobody found: ").font(.system(size: 15 * u, weight: .medium, design: .rounded)).foregroundColor(Ink.mute)
            let word = Text(missed).font(.system(size: 15 * u, weight: .heavy, design: .rounded)).foregroundColor(Ink.ink)
            ctx.draw(lead + word, at: CGPoint(x: inX, y: Double(box.maxY) - 28 * u), anchor: .leading)
        }
        return box
    }
}

// MARK: - The clip

extension LetterRushFrame {
    /// The board in the video feed: a long word traced, let go, and scored.
    static let clipLetters = ["P", "L", "A", "O", "E", "N", "T", "S", "R", "I", "M", "E", "D", "C", "H", "K"]
    static let clipPath = [0, 1, 2, 5, 6, 7]
    static let clipFound = [
        LetterRushWordRow(word: "TIME", points: 400), LetterRushWordRow(word: "SENT", points: 400),
        LetterRushWordRow(word: "MINT", points: 400), LetterRushWordRow(word: "PLAN", points: 400),
        LetterRushWordRow(word: "TEN", points: 100), LetterRushWordRow(word: "ANTS", points: 400),
        LetterRushWordRow(word: "RIME", points: 400), LetterRushWordRow(word: "PLANT", points: 800),
    ]

    static func scripted(phase raw: Double, showHUD: Bool) -> LetterRushFrame {
        typealias M = LetterRushMath
        let phase = raw - Foundation.floor(raw)
        var f = LetterRushFrame()
        f.letters = clipLetters
        f.showHUD = showHUD
        f.friendName = "kaz"
        f.ambient = phase * 8
        f.timeLeft = 47 - 6 * phase
        f.score = 3300
        f.words = clipFound.count
        f.recent = clipFound
        f.friendScore = 2800
        f.friendWords = 9
        f.friendFlash = (phase - 0.3) * 1.6
        let layout = LetterRushLayout(size: CGSize(width: 402, height: 874))

        // Tracing until 0.62, let go at 0.66.
        let traceEnd = 0.62
        let stepLength = traceEnd / Double(clipPath.count)
        if phase < 0.66 {
            let traced = Swift.min(clipPath.count, 1 + Int(phase / stepLength))
            f.path = Array(clipPath.prefix(traced))
            for i in f.path { f.selected[i] = true }
            if let last = f.path.last { f.popAge[last] = phase - Double(traced - 1) * stepLength }
            f.word = f.path.map { clipLetters[$0] }.joined()
            f.wordState = f.word.count >= 4 ? .valid : (f.word.count >= 3 ? .unknown : .short)
            return f
        }

        let age = (phase - 0.66) * 3.2
        f.verdict = .good
        f.verdictTiles = clipPath
        f.verdictWord = "PLANTS"
        f.verdictAge = age
        f.score = 3300 + Int(1400 * M.easeOut(M.clamp(age / 0.5)))
        f.words = clipFound.count + 1
        f.recent = clipFound + [LetterRushWordRow(word: "PLANTS", points: 1400)]
        f.praise = "Great"
        f.praiseAge = age
        f.floaters = [LetterRushFloater(text: "+1400", x: 201 + 112, y: layout.pillY, age: age)]
        var rng = LetterRushRandom(seed: 7, salt: LetterRushRandom.pilot)
        let t = Swift.min(age * 0.55, 0.9)
        for index in clipPath {
            let c = layout.center(index)
            for _ in 0..<7 {
                let a = rng.range(0, 2 * Double.pi)
                let v = rng.range(120, 300)
                let px = Double(c.x) + cos(a) * v * t
                let py = Double(c.y) + sin(a) * v * t + 380 * t * t
                f.particles.append(LetterRushParticle(x: px, y: py, vx: 0, vy: 0, age: t, life: rng.range(0.7, 1.0),
                                                      turn: rng.range(0, 6), size: rng.range(7, 12), tone: rng.int(4)))
            }
        }
        return f
    }
}
