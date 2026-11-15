import SwiftUI

// Deep End: one prompt at a time, one typed answer each. Rarer answers sink the krill deeper.
//
// Drawn like an old rubber-hose cartoon by DeepEndPainter from a DeepEndPicture: cream paper, ink
// outlines, flat 1930s colours and a little film wear. The playable game fills the picture from its
// model; the clip in the video feed builds one from a phase (0...1) and a fixed script. The krill,
// fish, kelp, sun, clouds, boat and seabed are painted pictures in Resources/GameArt; the rest is
// drawn in code at any frame size.

public struct DeepEndScene: View {
    public var phase: Double
    public var showHUD: Bool

    public init(phase: Double, showHUD: Bool) {
        self.phase = phase
        self.showHUD = showHUD
    }

    public var body: some View {
        Canvas(opaque: true, colorMode: .nonLinear, rendersAsynchronously: false) { context, size in
            if size.width <= 8 || size.height <= 8 { return }
            let picture = DeepEndClip.picture(at: phase, size: size)
            DeepEndPainter(size: size, picture: picture, showHUD: showHUD).draw(&context)
        }
    }
}

// MARK: - Rules the game and the clip share

enum DeepEndRules {
    static let round = 7
    static let answerTime = 25.0
    static let introTime = 0.9
    static let revealTime = 1.8
    static let endTime = 2.2
    static let maxLength = 30

    static let tierNames = ["SURFACE", "SUNLIT", "TWILIGHT", "MIDNIGHT", "ABYSS", "TRENCH"]
    static let points = [10, 25, 45, 65, 85, 100]

    /// Key codes: 0...25 are the letters in keyboard order, then these.
    static let back = 26
    static let space = 27
    static let dive = 28
    static let keyRows = ["QWERTYUIOP", "ASDFGHJKL", "ZXCVBNM"]
    static let keyLetters: [Character] = Array("QWERTYUIOPASDFGHJKLZXCVBNM")
    static let keyLabels: [String] = keyLetters.map { String($0) } + ["<", "SPACE"]

    static func code(for letter: Character) -> Int? {
        letter == " " ? space : keyLetters.firstIndex(of: letter)
    }

    static func headline(_ metres: Int) -> String {
        if metres >= 7000 { return "Touched the trench floor" }
        if metres >= 6000 { return "Reached the hadal zone" }
        if metres >= 4000 { return "Reached the abyss" }
        if metres >= 1000 { return "Reached the midnight zone" }
        if metres >= 200 { return "Reached the twilight zone" }
        return "Stayed in the sunlit zone"
    }

    static func grouped(_ n: Int) -> String {
        let digits = Array(String(abs(n)))
        var out = n < 0 ? "-" : ""
        for (i, ch) in digits.enumerated() {
            if i > 0, (digits.count - i) % 3 == 0 { out.append(",") }
            out.append(ch)
        }
        return out
    }
}

struct DeepEndZone {
    let depth: Double
    let text: String
    let major: Bool
}

enum DeepEndOcean {
    static let zones: [DeepEndZone] = [
        DeepEndZone(depth: 120, text: "LIGHT STARTS TO FADE", major: false),
        DeepEndZone(depth: 200, text: "THE TWILIGHT ZONE", major: true),
        DeepEndZone(depth: 332, text: "DEEPEST SCUBA DIVE, 332M", major: false),
        DeepEndZone(depth: 500, text: "EMPEROR PENGUINS DIVE THIS DEEP", major: false),
        DeepEndZone(depth: 1000, text: "THE MIDNIGHT ZONE", major: true),
        DeepEndZone(depth: 1500, text: "ANGLERFISH TERRITORY", major: false),
        DeepEndZone(depth: 2000, text: "THE WATER IS NEAR FREEZING", major: false),
        DeepEndZone(depth: 2250, text: "SPERM WHALES HUNT THIS DEEP", major: false),
        DeepEndZone(depth: 3800, text: "THE TITANIC RESTS HERE", major: false),
        DeepEndZone(depth: 4000, text: "THE ABYSSAL ZONE", major: true),
        DeepEndZone(depth: 5000, text: "THE ABYSSAL PLAIN", major: false),
        DeepEndZone(depth: 6000, text: "THE HADAL ZONE", major: true),
        DeepEndZone(depth: 6990, text: "THE TRENCH FLOOR", major: false)
    ]
}

/// SplitMix64. Everything that decides the round comes from one of these, seeded from the options.
struct DeepEndRandom {
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

    /// A steady 0 ..< 1 for a whole number, for things that change on a film frame.
    static func hash(_ n: Int) -> Double {
        var v = UInt64(bitPattern: Int64(n)) &* 0x9E3779B97F4A7C15 &+ 0x632BE59BD9B4E019
        v = (v ^ (v >> 30)) &* 0xBF58476D1CE4E5B9
        v = (v ^ (v >> 27)) &* 0x94D049BB133111EB
        v ^= v >> 31
        return Double(v >> 11) / 9007199254740992.0
    }

    /// 0 ..< count
    mutating func int(_ count: Int) -> Int {
        Swift.min(Swift.max(count - 1, 0), Int(next() * Double(count)))
    }
}

// MARK: - Colour

enum DeepEndInk {
    static func hex(_ value: UInt32, _ alpha: Double = 1) -> Color {
        Color(.sRGB, red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255,
              blue: Double(value & 255) / 255, opacity: alpha)
    }

    static func rgb(_ r: Double, _ g: Double, _ b: Double, _ alpha: Double = 1) -> Color {
        Color(.sRGB, red: r / 255, green: g / 255, blue: b / 255, opacity: alpha)
    }

    static let paper = hex(0xF3E6C8)
    static let paperLight = hex(0xFBF3DF)
    static let paperShade = hex(0xEBD6A8)
    static let sepia = hex(0x8A6A43)
    static let ink = hex(0x1E1712)
    static let red = hex(0xC8453A)
    static let mustard = hex(0xD9A441)
    static let rock = hex(0x4A3B2C)
    static let seabed = hex(0x231B14)
    static let glove = hex(0xFFFBF0)
    static let tiers: [Color] = [0xD9E6CF, 0xA9CDB4, 0x5E9E98, 0x8C7BB0, 0xC8453A, 0xD9A441].map { hex($0) }
    static let missed = hex(0x9C8C74)

    static let ruler = hex(0xF3E6C8, 0.3)
    static let rulerShallow = hex(0x1E1712, 0.35)
    static let mote = hex(0xF3E6C8, 0.3)
    static let current = hex(0xF3E6C8, 0.16)
    static let grainDark = hex(0x1E1712, 0.13)
    static let grainLight = hex(0xFBF3DF, 0.10)
    static let scratch = hex(0xFBF3DF, 0.35)
    static let shadow = hex(0x1E1712, 0.85)

    static let sky = Gradient(colors: [hex(0xF7EDD3), hex(0xEBD6A8)])
    static let halo = Gradient(colors: [hex(0xF3E6C8, 0.2), hex(0xF3E6C8, 0)])
    static let vignette = Gradient(stops: [.init(color: hex(0x1E1712, 0), location: 0),
                                           .init(color: hex(0x1E1712, 0.12), location: 0.45),
                                           .init(color: hex(0x1E1712, 0.55), location: 1)])

    /// The water's colour every 10 m from the surface to 8,000 m: pale sea green, teal, deep
    /// blue-green, then ink.
    static let water: [Color] = {
        let stops: [[Double]] = [[0, 169, 205, 180], [150, 122, 178, 166], [500, 78, 138, 138], [1200, 47, 94, 98],
                                 [3000, 31, 62, 66], [6000, 22, 32, 34], [8000, 16, 19, 20]]
        var out: [Color] = []
        out.reserveCapacity(801)
        for i in 0..<801 {
            let d = Double(i * 10)
            var s = 0
            while s < stops.count - 2, d > stops[s + 1][0] { s += 1 }
            let a = stops[s], b = stops[s + 1]
            let k = Swift.max(0, Swift.min(1, (d - a[0]) / (b[0] - a[0])))
            out.append(rgb((a[1] + (b[1] - a[1]) * k).rounded(), (a[2] + (b[2] - a[2]) * k).rounded(),
                           (a[3] + (b[3] - a[3]) * k).rounded()))
        }
        return out
    }()
}

// MARK: - Layout

/// Where everything sits on a screen of a given size, in points.
struct DeepEndLayout {
    let w: CGFloat
    let h: CGFloat
    let top: CGFloat
    /// Short screens get a smaller card and keyboard.
    let compact: Bool
    let cardX: CGFloat
    let cardY: CGFloat
    let cardW: CGFloat
    let cardH: CGFloat
    let kbTop: CGFloat
    let kw: CGFloat
    let kh: CGFloat
    let gx: CGFloat
    let gy: CGFloat
    let side: CGFloat
    let inX: CGFloat
    let inY: CGFloat
    let inW: CGFloat
    let inH: CGFloat
    let timerX: CGFloat
    let dive: CGRect
    let msgY: CGFloat
    /// The surface sits here while the camera is at the top.
    let baseY: CGFloat
    /// The krill is held at this height once the camera follows it down.
    let anchorY: CGFloat

    init(size: CGSize) {
        w = Swift.max(size.width, 1)
        h = Swift.max(size.height, 1)
        top = GameLayout.statusBarHeight
        compact = h - top - GameLayout.bottomInset < 700
        cardX = 16
        cardY = top + (compact ? 84 : 116)
        cardW = w - 32
        cardH = compact ? 100 : 136
        let kbBottom = h - GameLayout.bottomInset - 12
        kh = compact ? 34 : 42
        gy = compact ? 5 : 8
        gx = 4
        side = 6
        kw = (w - side * 2 - gx * 9) / 10
        kbTop = kbBottom - (kh * 4 + gy * 3)
        inH = compact ? 42 : 50
        inY = kbTop - (compact ? 10 : 16) - inH
        timerX = 16 + inH / 2
        inX = 16 + inH + 10
        dive = CGRect(x: w - 16 - 80, y: inY, width: 80, height: inH)
        inW = dive.minX - 8 - inX
        msgY = inY - 22
        baseY = cardY + cardH + 34
        anchorY = ((cardY + cardH + msgY) / 2).rounded()
    }

    func keyRect(_ code: Int) -> CGRect {
        let pitch = kw + gx
        if code == DeepEndRules.back {
            let x = side + pitch * 1.5 + 7 * pitch
            return CGRect(x: x, y: kbTop + 2 * (kh + gy), width: w - side - x, height: kh)
        }
        if code == DeepEndRules.space {
            return CGRect(x: side + pitch * 2, y: kbTop + 3 * (kh + gy), width: pitch * 6 - gx, height: kh)
        }
        let row = code < 10 ? 0 : code < 19 ? 1 : 2
        let index = code - (row == 0 ? 0 : row == 1 ? 10 : 19)
        let start = side + pitch * (row == 0 ? 0 : row == 1 ? 0.5 : 1.5)
        return CGRect(x: start + CGFloat(index) * pitch, y: kbTop + CGFloat(row) * (kh + gy), width: kw, height: kh)
    }

    /// The key under a touch, with the same slack around each key as the original.
    func key(at p: CGPoint) -> Int? {
        if dive.insetBy(dx: -4, dy: -4).contains(p) { return DeepEndRules.dive }
        for code in 0...DeepEndRules.space {
            let r = keyRect(code)
            if p.x >= r.minX - 2, p.x <= r.maxX + 2, p.y >= r.minY - 4, p.y <= r.maxY + 4 { return code }
        }
        return nil
    }
}

// MARK: - One frame's worth of the game

enum DeepEndStep { case intro, answer, reveal, done }

struct DeepEndFish {
    var x: Double
    var depth: Double
    var vx: Double
}

struct DeepEndMote {
    var x: Double
    var y: Double
    var size: Double
}

struct DeepEndBubble {
    var x: Double
    var y: Double
    var r: Double
    var life: Double
}

struct DeepEndCloud {
    var x: Double
    var y: Double
    var s: Double
}

/// A friend's depth today, shown as a flag on the way down.
struct DeepEndMarker {
    let name: String
    let depth: Double
}

struct DeepEndReveal {
    let name: String
    let tier: Int
    let points: Int
}

/// Everything the painter draws. The game's model keeps one and changes it in place; the clip
/// builds one from a phase.
struct DeepEndPicture {
    var clock = 0.0
    var started = false
    var ending = false
    var showHint = false
    var titleAlpha = 1.0
    var keyboard = 0.0
    var step = DeepEndStep.intro
    var stepTime = 0.0
    var promptIndex = 0
    var question = ""
    /// The tier of each answer so far, 0 for a prompt that ran out of time.
    var results: [Int] = []
    var points = 0
    /// The depth readout, rolling towards points x 10.
    var shown = 0.0
    var krill = 14.0
    var cam = 0.0
    var input = ""
    var timeLeft = DeepEndRules.answerTime
    var message = ""
    var messageColor = DeepEndInk.red
    var messageTime = 0.0
    var shake = 0.0
    var pressKey = -1
    var pressTime = 0.0
    var reveal: DeepEndReveal?
    var best = 0
    var fish: [DeepEndFish] = []
    var motes: [DeepEndMote] = []
    var bubbles: [DeepEndBubble] = []
    var clouds: [DeepEndCloud] = []
    var friends: [DeepEndMarker] = []
    var headline = ""
    var endTime = 0.0
}

// MARK: - Kept between frames

/// Paths that only change with the canvas size, made once per size and kept.
enum DeepEndCache {
    struct Key: Hashable {
        let w: Int
        let h: Int
    }

    struct Keys {
        let shadows: Path
        let caps: Path
    }

    struct Grain {
        let dark: Path
        let light: Path
    }

    static var keys: [Key: Keys] = [:]
    static var grain: [Key: Grain] = [:]

    static func keys(for lay: DeepEndLayout) -> Keys {
        let key = Key(w: Int(lay.w.rounded()), h: Int(lay.h.rounded()))
        if let kept = keys[key] { return kept }
        var shadows = Path(), caps = Path()
        for code in 0...DeepEndRules.space {
            let r = lay.keyRect(code)
            caps.addRoundedRect(in: r.insetBy(dx: 1, dy: 1), cornerSize: CGSize(width: 7, height: 7))
            shadows.addRoundedRect(in: r.insetBy(dx: 1, dy: 1).offsetBy(dx: 2, dy: 3), cornerSize: CGSize(width: 7, height: 7))
        }
        let made = Keys(shadows: shadows, caps: caps)
        if keys.count >= 8 { keys.removeAll(keepingCapacity: true) }
        keys[key] = made
        return made
    }

    /// Film grain over an area a little larger than the screen, so it can jump about each frame.
    static func grain(for lay: DeepEndLayout) -> Grain {
        let key = Key(w: Int(lay.w.rounded()), h: Int(lay.h.rounded()))
        if let kept = grain[key] { return kept }
        var rng = DeepEndRandom(seed: UInt64(key.w * 4099 + key.h), salt: 0x677261696E)
        var dark = Path(), light = Path()
        let w = Double(lay.w) + 64, h = Double(lay.h) + 64
        let count = Int(w * h / 260)
        for i in 0..<count {
            let size = rng.range(0.8, 1.8)
            let dot = CGRect(x: rng.next() * w, y: rng.next() * h, width: size, height: size)
            if i % 3 == 0 { light.addEllipse(in: dot) } else { dark.addEllipse(in: dot) }
        }
        let made = Grain(dark: dark, light: light)
        if grain.count >= 8 { grain.removeAll(keepingCapacity: true) }
        grain[key] = made
        return made
    }
}

// MARK: - Painter

/// Paints a DeepEndPicture as an old cartoon: cream paper, ink outlines, flat muted colours and a
/// bit of film wear.
struct DeepEndPainter {
    private typealias Ink = DeepEndInk

    /// Eight directions for drawing an outline around type.
    private static let ring: [CGPoint] = (0..<8).map { k in
        CGPoint(x: cos(Double(k) * .pi / 4), y: sin(Double(k) * .pi / 4))
    }

    let pic: DeepEndPicture
    let lay: DeepEndLayout
    let showHUD: Bool

    init(size: CGSize, picture: DeepEndPicture, showHUD: Bool) {
        pic = picture
        lay = DeepEndLayout(size: size)
        self.showHUD = showHUD
    }

    private func screenY(_ depth: Double) -> CGFloat { lay.baseY + CGFloat(depth - pic.cam) }

    /// Everything bounces on the beat: two poses, swapped a little over twice a second.
    private var offBeat: Bool { Int(pic.clock * 2.4) % 2 == 1 }

    private var labelTop: CGFloat { pic.started ? lay.cardY + lay.cardH + 8 : -20 }

    private var krillPoint: CGPoint {
        CGPoint(x: lay.w / 2 + CGFloat(sin(pic.clock * 1.3) * 14),
                y: screenY(pic.krill) + CGFloat(sin(pic.clock * 2.1) * 3) - (offBeat ? 3 : 0))
    }

    func draw(_ ctx: inout GraphicsContext) {
        let sy = screenY(0).rounded()
        drawSky(&ctx, sy)
        drawWater(&ctx, sy)
        drawZones(&ctx)
        drawKelp(&ctx)
        drawFloor(&ctx)
        drawRuler(&ctx, sy)
        drawMotes(&ctx, sy)
        drawFriends(&ctx)
        drawFish(&ctx)
        drawSurface(&ctx, sy)
        drawKrill(&ctx)
        drawBubbles(&ctx, sy)
        if pic.titleAlpha > 0 { drawTitle(&ctx) }
        if pic.ending { drawIris(&ctx) }
        if pic.started, showHUD { drawHud(&ctx) }
        if pic.started, !pic.ending { drawCard(&ctx) }
        if pic.step == .reveal, let reveal = pic.reveal { drawReveal(&ctx, reveal) }
        if pic.keyboard > 0 { drawInput(&ctx) }
        if pic.ending { drawEnding(&ctx) }
        if pic.showHint { drawHint(&ctx) }
        drawFilm(&ctx)
    }

    // MARK: Helpers

    /// A brush line: the stroke, and a thinner one nudged down and right so the line swells a little.
    private func inked(_ ctx: inout GraphicsContext, _ path: Path, _ width: CGFloat = 3, _ color: Color = DeepEndInk.ink) {
        ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
        var c = ctx
        c.translateBy(x: 0.7, y: 0.9)
        c.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width * 0.45, lineCap: .round, lineJoin: .round))
    }

    private func type(_ s: String, _ size: CGFloat, _ weight: Font.Weight, _ design: Font.Design, _ color: Color,
                      tracking: CGFloat = 0) -> Text {
        Text(s).font(.system(size: size, weight: weight, design: design)).tracking(tracking).foregroundStyle(color)
    }

    private func label(_ ctx: inout GraphicsContext, _ s: String, _ size: CGFloat, _ weight: Font.Weight, _ design: Font.Design,
                       _ color: Color, at p: CGPoint, anchor: UnitPoint = .center, tracking: CGFloat = 0) {
        ctx.draw(type(s, size, weight, design, color, tracking: tracking), at: p, anchor: anchor)
    }

    /// Type filled with one colour inside an outline of another, with an optional drop shadow.
    private func outlined(_ ctx: inout GraphicsContext, _ s: String, _ size: CGFloat, fill: Color, edge: Color = DeepEndInk.ink,
                          width: CGFloat = 2.5, shadow: CGFloat = 0, at p: CGPoint, anchor: UnitPoint = .center,
                          weight: Font.Weight = .black, design: Font.Design = .rounded, tracking: CGFloat = 0) {
        let back = ctx.resolve(type(s, size, weight, design, edge, tracking: tracking))
        let face = ctx.resolve(type(s, size, weight, design, fill, tracking: tracking))
        if shadow > 0 { ctx.draw(back, at: CGPoint(x: p.x + shadow * 0.6, y: p.y + shadow + width), anchor: anchor) }
        for d in Self.ring { ctx.draw(back, at: CGPoint(x: p.x + d.x * width, y: p.y + d.y * width), anchor: anchor) }
        ctx.draw(face, at: p, anchor: anchor)
    }

    private func width(_ ctx: inout GraphicsContext, _ text: Text) -> CGFloat {
        ctx.resolve(text).measure(in: CGSize(width: 2000, height: 400)).width
    }

    /// A cream card with an ink outline and a hard ink shadow.
    private func card(_ ctx: inout GraphicsContext, _ r: CGRect, radius: CGFloat, fill: Color = DeepEndInk.paperLight,
                      shadow: CGSize = CGSize(width: 4, height: 5), line: CGFloat = 3) {
        let corner = CGSize(width: radius, height: radius)
        ctx.fill(Path(roundedRect: r.offsetBy(dx: shadow.width, dy: shadow.height), cornerSize: corner), with: .color(Ink.shadow))
        let body = Path(roundedRect: r, cornerSize: corner)
        ctx.fill(body, with: .color(fill))
        inked(&ctx, body, line)
    }

    /// A ribbon banner with swallowtail ends.
    private func ribbon(_ ctx: inout GraphicsContext, center c: CGPoint, width w: CGFloat, height h: CGFloat, fill: Color) {
        let x0 = c.x - w / 2, x1 = c.x + w / 2, y0 = c.y - h / 2, y1 = c.y + h / 2
        var p = Path()
        p.move(to: CGPoint(x: x0 - 12, y: y0))
        p.addLine(to: CGPoint(x: x1 + 12, y: y0))
        p.addLine(to: CGPoint(x: x1 + 3, y: c.y))
        p.addLine(to: CGPoint(x: x1 + 12, y: y1))
        p.addLine(to: CGPoint(x: x0 - 12, y: y1))
        p.addLine(to: CGPoint(x: x0 - 3, y: c.y))
        p.closeSubpath()
        var s = ctx
        s.translateBy(x: 2, y: 3)
        s.fill(p, with: .color(Ink.shadow))
        ctx.fill(p, with: .color(fill))
        inked(&ctx, p, 2.5)
    }

    /// Where a picture goes, kept to its own proportions, from its centre and its width or height.
    private func artRect(_ art: GraphicsContext.ResolvedImage, center c: CGPoint, width: CGFloat? = nil, height: CGFloat? = nil) -> CGRect {
        let aspect = art.size.height > 0 ? art.size.width / art.size.height : 1
        let w = width ?? (height ?? 0) * aspect
        let h = height ?? w / aspect
        return CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h)
    }

    /// Colour for small words over the water at a depth: ink near the pale top, cream below.
    private func onWater(_ depth: Double, _ alpha: Double = 0.75) -> Color {
        depth < 420 ? Ink.ink.opacity(alpha * 0.8) : Ink.paper.opacity(alpha)
    }

    // MARK: Sky and surface

    private func drawSky(_ ctx: inout GraphicsContext, _ sy: CGFloat) {
        guard sy > 0 else { return }
        let W = lay.w, t = pic.clock
        ctx.fill(Path(CGRect(x: 0, y: 0, width: W, height: sy)),
                 with: .linearGradient(Ink.sky, startPoint: .zero, endPoint: CGPoint(x: 0, y: sy)))

        // A sun with a face, low on the horizon, rocking on the beat.
        var sun = ctx
        sun.translateBy(x: (W * 0.86).rounded(), y: sy - 24 - (offBeat ? 2 : 0))
        sun.rotate(by: .radians(sin(t * 0.8) * 0.12))
        let face = sun.resolve(Image("deep-end-sun"))
        sun.draw(face, in: artRect(face, center: .zero, height: 100))

        let cloud = ctx.resolve(Image("deep-end-cloud"))
        for puff in pic.clouds {
            let s = CGFloat(puff.s)
            let center = CGPoint(x: CGFloat(puff.x) + 26 * s, y: sy - 12 - CGFloat(puff.y) * 0.3 - 8 * s)
            ctx.draw(cloud, in: artRect(cloud, center: center, width: 84 * s))
        }
    }

    private func drawSurface(_ ctx: inout GraphicsContext, _ sy: CGFloat) {
        guard sy > -20, sy < lay.h + 20 else { return }
        let W = lay.w, t = pic.clock
        func wave(_ x: CGFloat) -> CGFloat { sy + CGFloat(sin(Double(x) * 0.045 + t * 2.2) * 3.5) }

        // The sky dips into every trough.
        var air = Path()
        air.move(to: CGPoint(x: 0, y: sy - 9))
        var x: CGFloat = 0
        while x <= W + 6 {
            air.addLine(to: CGPoint(x: x, y: wave(x)))
            x += 6
        }
        air.addLine(to: CGPoint(x: W + 6, y: sy - 9))
        air.closeSubpath()
        ctx.fill(air, with: .color(Ink.paperShade))

        var line = Path()
        line.move(to: CGPoint(x: 0, y: wave(0)))
        x = 6
        while x <= W + 6 {
            line.addLine(to: CGPoint(x: x, y: wave(x)))
            x += 6
        }
        // Curls riding the crests.
        let drift = CGFloat((t * 14).truncatingRemainder(dividingBy: 70))
        var cx: CGFloat = -70 + drift
        while cx < W + 20 {
            let cy = wave(cx) - 1
            line.move(to: CGPoint(x: cx - 6, y: cy + 3))
            line.addArc(center: CGPoint(x: cx, y: cy - 2), radius: 6, startAngle: .degrees(180), endAngle: .degrees(430), clockwise: false)
            cx += 70
        }
        inked(&ctx, line, 3)

        var under = Path()
        x = 0
        under.move(to: CGPoint(x: 0, y: wave(0) + 11))
        while x <= W + 6 {
            under.addLine(to: CGPoint(x: x, y: sy + 11 + CGFloat(sin(Double(x) * 0.06 - t * 1.7) * 2)))
            x += 8
        }
        ctx.stroke(under, with: .color(Ink.paper.opacity(0.45)), style: StrokeStyle(lineWidth: 2, lineCap: .round))

        // The boat, bobbing on the beat.
        let bx = (W * 0.26).rounded()
        let by = wave(bx) - 3 - (offBeat ? 2 : 0)
        let boat = ctx.resolve(Image("deep-end-boat"))
        let hull = artRect(boat, center: .zero, width: 52)
        ctx.draw(boat, in: hull.offsetBy(dx: bx, dy: by + 8 - hull.maxY))
    }

    // MARK: Water

    private func drawWater(_ ctx: inout GraphicsContext, _ sy: CGFloat) {
        let W = lay.w, H = lay.h, t = pic.clock
        let band: CGFloat = 4
        var y = Swift.max(0, sy - 9)
        var runStart = y
        var runIndex = -1
        while y < H {
            let d = pic.cam + Double(y + band / 2 - lay.baseY)
            let index = d <= 0 ? 0 : Swift.min(Ink.water.count - 1, Int(d / 10))
            if index != runIndex {
                if runIndex >= 0 { ctx.fill(Path(CGRect(x: 0, y: runStart, width: W, height: y - runStart)), with: .color(Ink.water[runIndex])) }
                runIndex = index
                runStart = y
            }
            y += band
        }
        if runIndex >= 0 { ctx.fill(Path(CGRect(x: 0, y: runStart, width: W, height: y - runStart)), with: .color(Ink.water[runIndex])) }

        // Hand-drawn current lines drifting through the water.
        let top = pic.cam - Double(lay.baseY), bottom = top + Double(H)
        var currents = Path()
        var m = Swift.max(60, (top / 110).rounded(.up) * 110)
        while m <= bottom {
            let cy = screenY(m)
            let span = Double(W) * 0.75
            let start = CGFloat((m * 53 + t * 9).truncatingRemainder(dividingBy: span)) - 40
            currents.move(to: CGPoint(x: start, y: cy))
            for k in 1...10 {
                currents.addLine(to: CGPoint(x: start + CGFloat(k) * 10, y: cy + CGFloat(sin(Double(k) * 0.9 + t * 1.5) * 2.5)))
            }
            m += 110
        }
        ctx.stroke(currents, with: .color(Ink.current), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
    }

    private func drawZones(_ ctx: inout GraphicsContext) {
        let W = lay.w, H = lay.h
        for (z, zone) in DeepEndOcean.zones.enumerated() {
            let zy = screenY(zone.depth)
            if zy < labelTop + 14 || zy > H + 20 { continue }
            if zone.major {
                // A title card: a cream cartouche with a double outline.
                let words = type(zone.text, 13, .heavy, .serif, Ink.ink, tracking: 1.6)
                let w = width(&ctx, words) + 40
                let box = CGRect(x: (W / 2 - 12 - w / 2).rounded(), y: zy - 14, width: w, height: 28)
                card(&ctx, box, radius: 14, fill: Ink.paper, shadow: CGSize(width: 3, height: 3), line: 2.5)
                inked(&ctx, Path(roundedRect: box.insetBy(dx: 4, dy: 4), cornerSize: CGSize(width: 10, height: 10)), 1)
                ctx.draw(words, at: CGPoint(x: box.midX, y: box.midY), anchor: .center)
            } else if z % 2 == 1 {
                ctx.fill(Path(CGRect(x: 16, y: zy.rounded(), width: 18, height: 1.5)), with: .color(onWater(zone.depth, 0.6)))
                label(&ctx, zone.text, 10, .semibold, .serif, onWater(zone.depth), at: CGPoint(x: 40, y: zy), anchor: .leading, tracking: 1)
            } else {
                ctx.fill(Path(CGRect(x: W - 70, y: zy.rounded(), width: 18, height: 1.5)), with: .color(onWater(zone.depth, 0.6)))
                label(&ctx, zone.text, 10, .semibold, .serif, onWater(zone.depth), at: CGPoint(x: W - 76, y: zy), anchor: .trailing, tracking: 1)
            }
        }
    }

    private func drawKelp(_ ctx: inout GraphicsContext) {
        let base = screenY(330)
        guard base > -10, base - 240 < lay.h else { return }
        let t = pic.clock
        let kelp = ctx.resolve(Image("deep-end-kelp"))
        let roots: [CGFloat] = [14, 38, 62, lay.w - 62, lay.w - 36]
        for (s, root) in roots.enumerated() {
            // Each stalk leans from its root, so the tip sways and the base stays put.
            let tall = CGFloat(20 + (s * 7) % 5) * 9.5 + 12
            let lean = CGFloat(sin(t * 1.1 + Double(s) * 1.7) * 0.07)
            var c = ctx
            c.concatenate(CGAffineTransform(a: s % 2 == 0 ? 1 : -1, b: 0, c: lean, d: 1, tx: root - lean * base, ty: 0))
            c.draw(kelp, in: artRect(kelp, center: CGPoint(x: 0, y: base + 4 - tall / 2), height: tall))
        }
    }

    private func drawFloor(_ ctx: inout GraphicsContext) {
        let floorY = screenY(7000)
        guard floorY < lay.h + 20 else { return }
        let W = lay.w
        var ground = Path()
        ground.move(to: CGPoint(x: -5, y: lay.h + 5))
        ground.addLine(to: CGPoint(x: -5, y: floorY))
        var x: CGFloat = 0
        while x <= W + 20 {
            ground.addQuadCurve(to: CGPoint(x: x + 20, y: floorY + CGFloat(Int(x * 37) % 7) - 3),
                                control: CGPoint(x: x + 10, y: floorY - 6))
            x += 20
        }
        ground.addLine(to: CGPoint(x: W + 25, y: lay.h + 5))
        ground.closeSubpath()
        ctx.fill(ground, with: .color(Ink.seabed))
        inked(&ctx, ground, 3)
        var rocks = Path()
        for (rx, w, h) in [(0.06, 46.0, 26.0), (0.24, 30, 18), (0.46, 58, 30), (0.7, 36, 20), (0.88, 50, 28)] {
            rocks.addEllipse(in: CGRect(x: W * CGFloat(rx) - CGFloat(w) / 2, y: floorY - CGFloat(h) * 0.55, width: CGFloat(w), height: CGFloat(h)))
        }
        ctx.fill(rocks, with: .color(Ink.rock))
        inked(&ctx, rocks, 3)
    }

    private func drawRuler(_ ctx: inout GraphicsContext, _ sy: CGFloat) {
        let H = lay.h
        let rx = lay.w - 22
        let lineTop = Swift.max(0, sy + 8)
        if lineTop < H { ctx.fill(Path(CGRect(x: rx, y: lineTop, width: 1.5, height: H - lineTop)), with: .color(Ink.ruler)) }
        let dTop = Swift.max(0, pic.cam - Double(lay.baseY))
        let dBottom = pic.cam + Double(H - lay.baseY)
        var ticks = Path()
        var m = Int((dTop / 50).rounded(.down)) * 50
        while Double(m) <= dBottom {
            let my = screenY(Double(m)).rounded()
            if m > 0 {
                let major = m % 100 == 0
                ticks.addRect(CGRect(x: rx - (major ? 10 : 5), y: my, width: major ? 10 : 5, height: 1.5))
                if major, my > labelTop {
                    label(&ctx, DeepEndRules.grouped(m) + " m", 9, .semibold, .serif, onWater(Double(m), 0.6),
                          at: CGPoint(x: rx - 14, y: my + 1), anchor: .trailing)
                }
            }
            m += 50
        }
        ctx.fill(ticks, with: .color(pic.cam < 300 ? Ink.rulerShallow : Ink.ruler))
    }

    private func drawMotes(_ ctx: inout GraphicsContext, _ sy: CGFloat) {
        var motes = Path()
        for mote in pic.motes where CGFloat(mote.y) >= sy + 6 {
            let s = CGFloat(mote.size) + 0.5
            motes.addEllipse(in: CGRect(x: CGFloat(mote.x), y: CGFloat(mote.y), width: s, height: s))
        }
        ctx.fill(motes, with: .color(Ink.mote))
    }

    private func drawFriends(_ ctx: inout GraphicsContext) {
        for friend in pic.friends {
            let fy = screenY(friend.depth).rounded()
            if fy < labelTop + 20 || fy > lay.h + 10 { continue }
            var pole = Path()
            pole.move(to: CGPoint(x: 10, y: fy))
            pole.addLine(to: CGPoint(x: 10, y: fy - 22))
            pole.move(to: CGPoint(x: 4, y: fy))
            pole.addLine(to: CGPoint(x: 36, y: fy))
            inked(&ctx, pole, 2, Ink.paper.opacity(0.8))
            var pennant = Path()
            pennant.move(to: CGPoint(x: 11, y: fy - 22))
            pennant.addLine(to: CGPoint(x: 27, y: fy - 17 - (offBeat ? 1.5 : 0)))
            pennant.addLine(to: CGPoint(x: 11, y: fy - 12))
            pennant.closeSubpath()
            ctx.fill(pennant, with: .color(Ink.mustard))
            inked(&ctx, pennant, 1.6)
            label(&ctx, friend.name, 10, .bold, .serif, onWater(friend.depth, 0.85), at: CGPoint(x: 31, y: fy - 9), anchor: .leading, tracking: 0.6)
        }
    }

    private func drawFish(_ ctx: inout GraphicsContext) {
        let kinds = [ctx.resolve(Image("deep-end-fish-gold")), ctx.resolve(Image("deep-end-fish-red")),
                     ctx.resolve(Image("deep-end-fish-blue"))]
        for (i, fish) in pic.fish.enumerated() where fish.depth > 10 {
            let fy = screenY(fish.depth)
            if fy < -24 || fy > lay.h + 24 { continue }
            let art = kinds[i % kinds.count]
            var c = ctx
            c.translateBy(x: CGFloat(fish.x), y: fy - ((i % 2 == 0) == offBeat ? 2.5 : 0))
            if fish.vx < 0 { c.scaleBy(x: -1, y: 1) }
            c.draw(art, in: artRect(art, center: .zero, width: i % kinds.count == 2 ? 48 : 36))
        }
    }

    // MARK: The krill

    private func drawKrill(_ ctx: inout GraphicsContext) {
        let p = krillPoint
        let dark = pic.cam > 900
        if dark {
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - 70, y: p.y - 70, width: 140, height: 140)),
                     with: .radialGradient(Ink.halo, center: p, startRadius: 0, endRadius: 70))
        }
        var c = ctx
        c.translateBy(x: p.x, y: p.y)
        // A squash and stretch on every reveal, and a small squash on each beat.
        var sx: CGFloat = 1, sy: CGFloat = 1
        if pic.step == .reveal, pic.stepTime < 0.7 {
            let k = pic.stepTime
            let wobble = CGFloat(exp(-6 * k) * cos(k * 20) * 0.26)
            sx += wobble
            sy -= wobble
        } else if offBeat {
            sx = 1.04
            sy = 0.96
        }
        c.translateBy(x: 0, y: 18)
        c.scaleBy(x: sx, y: sy)
        c.translateBy(x: 0, y: -18)

        // Two poses, swapped on the beat like an old cartoon cycle.
        let krill = c.resolve(Image(offBeat ? "deep-end-krill-b" : "deep-end-krill"))
        c.draw(krill, in: artRect(krill, center: CGPoint(x: -4, y: -4), height: 98))
    }

    private func drawBubbles(_ ctx: inout GraphicsContext, _ sy: CGFloat) {
        for bubble in pic.bubbles where bubble.life > 0 && CGFloat(bubble.y) >= sy + 4 {
            var c = ctx
            c.opacity = Swift.min(1, bubble.life)
            let r = CGFloat(bubble.r) + 1
            let x = CGFloat(bubble.x), y = CGFloat(bubble.y)
            let ring = Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
            c.fill(ring, with: .color(Ink.paper.opacity(0.22)))
            c.stroke(ring, with: .color(Ink.ink), lineWidth: 1.5)
            c.fill(Path(ellipseIn: CGRect(x: x - r * 0.55, y: y - r * 0.6, width: r * 0.55, height: r * 0.45)), with: .color(Ink.glove))
        }
    }

    // MARK: Words over the water

    private func drawTitle(_ ctx: inout GraphicsContext) {
        var c = ctx
        c.opacity = Swift.max(0, Swift.min(1, pic.titleAlpha))
        let W = lay.w
        let ty = lay.top + (lay.compact ? 36 : 86)
        let big = Swift.min(62, (W - 40) / 5.4)
        outlined(&c, "DEEP END", big, fill: Ink.paperLight, width: 3.5, shadow: 4, at: CGPoint(x: W / 2, y: ty + 28))
        ribbon(&c, center: CGPoint(x: W / 2, y: ty + 76), width: 190, height: 28, fill: Ink.red)
        label(&c, "THE DAILY DIVE", 14, .heavy, .serif, Ink.paperLight, at: CGPoint(x: W / 2, y: ty + 76), tracking: 3)
        label(&c, "7 PROMPTS. 25 SECONDS EACH.", 12, .semibold, .serif, Ink.sepia, at: CGPoint(x: W / 2, y: ty + 110), tracking: 1.6)
        label(&c, "RARER ANSWERS SINK DEEPER.", 12, .semibold, .serif, Ink.sepia, at: CGPoint(x: W / 2, y: ty + 128), tracking: 1.6)
        if pic.best > 0 {
            label(&c, "BEST " + DeepEndRules.grouped(pic.best) + " M", 12, .heavy, .serif, Ink.ink,
                  at: CGPoint(x: W / 2, y: ty + 152), tracking: 2)
        }
    }

    private func drawHud(_ ctx: inout GraphicsContext) {
        let W = lay.w, top = lay.top
        let count = DeepEndRules.round
        let pw = CGFloat(count * 12 + (count - 1) * 5)
        let px = Swift.max(GameLayout.cornerWidth, Swift.min(W - GameLayout.cornerWidth - pw, W / 2 - pw / 2)).rounded()
        let y = top + 24
        for i in 0..<count {
            let x = px + CGFloat(i * 17) + 6
            if i < pic.results.count {
                let tier = pic.results[i]
                let dot = Path(ellipseIn: CGRect(x: x - 6.5, y: y - 6.5, width: 13, height: 13))
                ctx.fill(dot, with: .color(tier > 0 ? Ink.tiers[tier - 1] : Ink.missed))
                inked(&ctx, dot, 2)
            } else if i == pic.promptIndex, !pic.ending {
                let r: CGFloat = offBeat ? 8.5 : 7.5
                let dot = Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
                ctx.fill(dot, with: .color(Ink.paperLight))
                inked(&ctx, dot, 2.8)
                ctx.fill(Path(ellipseIn: CGRect(x: x - 2.5, y: y - 2.5, width: 5, height: 5)), with: .color(Ink.red))
            } else {
                let dot = Path(ellipseIn: CGRect(x: x - 5, y: y - 5, width: 10, height: 10))
                ctx.fill(dot, with: .color(Ink.paper.opacity(0.4)))
                ctx.stroke(dot, with: .color(Ink.ink.opacity(0.5)), lineWidth: 1.5)
            }
        }
        let depth = DeepEndRules.grouped(Int(pic.shown.rounded())) + " m"
        if lay.compact {
            outlined(&ctx, depth, 28, fill: Ink.paperLight, width: 2.5, shadow: 2, at: CGPoint(x: W / 2, y: top + 60))
            return
        }
        outlined(&ctx, depth, 36, fill: Ink.paperLight, width: 3, shadow: 3, at: CGPoint(x: W / 2, y: top + 70))
        outlined(&ctx, "\(pic.points) POINTS", 11, fill: Ink.paperLight, width: 1.5, at: CGPoint(x: W / 2, y: top + 103),
                 weight: .heavy, design: .serif, tracking: 1.6)
    }

    private func drawCard(_ ctx: inout GraphicsContext) {
        let r = CGRect(x: lay.cardX, y: lay.cardY, width: lay.cardW, height: lay.cardH)
        card(&ctx, r, radius: 14, shadow: CGSize(width: 5, height: 6))
        inked(&ctx, Path(roundedRect: r.insetBy(dx: 6, dy: 6), cornerSize: CGSize(width: 9, height: 9)), 1, Ink.sepia.opacity(0.6))
        let compact = lay.compact
        label(&ctx, "PROMPT \(pic.promptIndex + 1) OF \(DeepEndRules.round)", compact ? 11 : 12, .heavy, .serif, Ink.red,
              at: CGPoint(x: r.minX + 18, y: r.minY + (compact ? 16 : 22)), anchor: .leading, tracking: 2)

        // The question types itself out while the prompt opens. The unseen letters keep their room,
        // so the lines break the same way from the first letter to the last.
        let chars = pic.step == .intro ? Swift.max(0, Int(pic.stepTime * 70)) : Int.max
        let question = pic.question
        let shown = chars >= question.count ? question : String(question.prefix(chars))
        let rest = chars >= question.count ? "" : String(question.dropFirst(chars))
        let size: CGFloat = compact ? 19 : 25
        let font = Font.system(size: size, weight: .heavy, design: .serif)
        let words = Text(shown).font(font).foregroundStyle(Ink.ink) + Text(rest).font(font).foregroundStyle(Color.clear)
        let box = CGRect(x: r.minX + 18, y: r.minY + (compact ? 28 : 38), width: r.width - 36, height: r.height - (compact ? 44 : 62))
        ctx.draw(words, in: box)

        let footer = type("RARER ANSWERS SINK DEEPER", compact ? 9 : 10, .bold, .serif, Ink.sepia, tracking: 1.6)
        let fy = r.maxY - (compact ? 12 : 17)
        let fw = width(&ctx, footer)
        ctx.draw(footer, at: CGPoint(x: r.midX, y: fy), anchor: .center)
        var arrows = Path()
        for side in [-1.0, 1.0] {
            let ax = r.midX + CGFloat(side) * (fw / 2 + 12)
            arrows.move(to: CGPoint(x: ax - 4, y: fy - 2))
            arrows.addLine(to: CGPoint(x: ax + 4, y: fy - 2))
            arrows.addLine(to: CGPoint(x: ax, y: fy + 3))
            arrows.closeSubpath()
        }
        ctx.fill(arrows, with: .color(Ink.sepia))
    }

    private func drawReveal(_ ctx: inout GraphicsContext, _ reveal: DeepEndReveal) {
        let W = lay.w
        let k = pic.stepTime
        let a = Swift.min(1, k / 0.15)
        var c = ctx
        c.opacity = a
        let top = lay.cardY + lay.cardH + (lay.compact ? 10 : 18) - CGFloat(1 - a) * 8
        let base: CGFloat = lay.compact ? 26 : 34
        let pop = CGFloat(1 + 0.22 * exp(-9 * k))
        let name = reveal.tier > 0 ? reveal.name : "TIME"
        let natural = width(&c, type(name, base, .black, .rounded, Ink.ink))
        let size = Swift.max(14, base * Swift.min(1, (W - 44) / Swift.max(natural, 1))) * pop
        outlined(&c, name, size, fill: reveal.tier > 0 ? Ink.paperLight : Ink.red, width: 3, shadow: 3,
                 at: CGPoint(x: W / 2, y: top + base * 0.6))
        let line = reveal.tier > 0 ? "+\(reveal.points)  " + DeepEndRules.tierNames[reveal.tier - 1] : "+0"
        let words = type(line, 13, .heavy, .serif, Ink.ink, tracking: 2)
        let ribbonWidth = width(&c, words) + 26
        let ry = top + base * 0.6 + base * 0.5 + 18
        ribbon(&c, center: CGPoint(x: W / 2, y: ry), width: ribbonWidth, height: 24,
               fill: reveal.tier > 0 ? Ink.tiers[reveal.tier - 1] : Ink.missed)
        c.draw(words, at: CGPoint(x: W / 2, y: ry), anchor: .center)
    }

    private func drawInput(_ ctx: inout GraphicsContext) {
        let W = lay.w, H = lay.h
        let e = 1 - pow(1 - Swift.min(1, pic.keyboard), 3)
        let off = (CGFloat(1 - e) * (H - lay.inY + 34)).rounded()

        if pic.messageTime > 0, !pic.message.isEmpty {
            var m = ctx
            m.opacity = Swift.min(1, pic.messageTime / 0.3)
            outlined(&m, pic.message, 18, fill: pic.messageColor, edge: Ink.paperLight, width: 2.5,
                     at: CGPoint(x: W / 2, y: lay.msgY - 26 + off), tracking: 1.5)
        }

        // The shelf: printed card stock with an ink edge.
        let shelfTop = lay.inY - 30 + off
        var shelf = Path()
        shelf.move(to: CGPoint(x: -4, y: H + 4))
        shelf.addLine(to: CGPoint(x: -4, y: shelfTop))
        var x: CGFloat = 0
        while x <= W + 20 {
            shelf.addQuadCurve(to: CGPoint(x: x + 20, y: shelfTop), control: CGPoint(x: x + 10, y: shelfTop + (Int(x / 20) % 2 == 0 ? -2 : 2)))
            x += 20
        }
        shelf.addLine(to: CGPoint(x: W + 24, y: H + 4))
        shelf.closeSubpath()
        ctx.fill(shelf, with: .color(Ink.paper))
        inked(&ctx, shelf, 3)
        ctx.fill(Path(CGRect(x: 0, y: shelfTop + 7, width: W, height: 1.5)), with: .color(Ink.sepia.opacity(0.4)))

        // The clock: a dial with a pie of the time left, red for the last six seconds.
        let center = CGPoint(x: lay.timerX, y: lay.inY + lay.inH / 2 + off)
        let frac = Swift.max(0, pic.timeLeft / DeepEndRules.answerTime)
        let low = pic.step == .answer && pic.timeLeft <= 6
        let hot = low ? Ink.red : Ink.tiers[2]
        let rr = lay.inH / 2 - 2
        let dial = Path(ellipseIn: CGRect(x: center.x - rr, y: center.y - rr, width: rr * 2, height: rr * 2))
        var dropped = ctx
        dropped.translateBy(x: 2, y: 3)
        dropped.fill(dial, with: .color(Ink.shadow))
        ctx.fill(dial, with: .color(Ink.paperLight))
        if frac > 0 {
            var pie = Path()
            pie.move(to: center)
            pie.addArc(center: center, radius: rr - 3, startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * frac), clockwise: false)
            pie.closeSubpath()
            ctx.fill(pie, with: .color(hot))
        }
        inked(&ctx, dial, 3)
        outlined(&ctx, "\(Int(pic.timeLeft.rounded(.up)))", lay.compact ? 15 : 17, fill: Ink.ink, edge: Ink.paperLight, width: 1.8, at: center)

        // The answer box shakes, and its outline turns red, when the answer is not on the list.
        let sx = pic.shake > 0 ? CGFloat((sin(pic.shake * 70) * 5 * (pic.shake / 0.35)).rounded()) : 0
        let field = CGRect(x: lay.inX + sx, y: lay.inY + off, width: lay.inW, height: lay.inH)
        card(&ctx, field, radius: 10, shadow: CGSize(width: 3, height: 4), line: 3)
        if pic.shake > 0 { inked(&ctx, Path(roundedRect: field, cornerSize: CGSize(width: 10, height: 10)), 3, Ink.red) }
        let blink = (pic.clock * 2).truncatingRemainder(dividingBy: 2) < 1.2
        let textSize: CGFloat = lay.compact ? 19 : 22
        if !pic.input.isEmpty {
            let room = Swift.max(1, Int((lay.inW - 30) / (textSize * 0.72)))
            let visible = pic.input.count > room ? String(pic.input.suffix(room)) : pic.input
            let words = ctx.resolve(type(visible, textSize, .black, .rounded, Ink.ink))
            let w = words.measure(in: CGSize(width: 2000, height: 200)).width
            ctx.draw(words, at: CGPoint(x: field.minX + 13, y: field.midY), anchor: .leading)
            if blink { ctx.fill(Path(CGRect(x: field.minX + 15 + w, y: field.minY + 12, width: 2.5, height: field.height - 24)), with: .color(Ink.red)) }
        } else {
            let hint = lay.inW >= 180 ? "Type one answer" : "Answer"
            label(&ctx, hint, lay.compact ? 16 : 17, .semibold, .serif, Ink.sepia.opacity(0.75),
                  at: CGPoint(x: field.minX + 16, y: field.midY), anchor: .leading)
            if blink { ctx.fill(Path(CGRect(x: field.minX + 11, y: field.minY + 12, width: 2.5, height: field.height - 24)), with: .color(Ink.red)) }
        }
        let bar = CGRect(x: lay.inX, y: field.maxY + 7, width: lay.inW, height: 5)
        let barPath = Path(roundedRect: bar, cornerSize: CGSize(width: 2.5, height: 2.5))
        ctx.fill(barPath, with: .color(Ink.paperShade))
        ctx.fill(Path(roundedRect: CGRect(x: bar.minX, y: bar.minY, width: (bar.width * CGFloat(frac)).rounded(), height: bar.height),
                      cornerSize: CGSize(width: 2.5, height: 2.5)), with: .color(hot))
        ctx.stroke(barPath, with: .color(Ink.ink), lineWidth: 1.5)

        // DIVE: a red button that sinks into its shadow when pressed.
        let dive = lay.dive.offsetBy(dx: 0, dy: off)
        let divePressed = pic.pressKey == DeepEndRules.dive && pic.pressTime > 0
        let face = CGRect(x: dive.minX, y: dive.minY + (divePressed ? 4 : 0), width: dive.width, height: dive.height - 4)
        ctx.fill(Path(roundedRect: CGRect(x: dive.minX + 2, y: dive.minY + 4, width: dive.width, height: dive.height - 4),
                      cornerSize: CGSize(width: 10, height: 10)), with: .color(Ink.ink))
        let button = Path(roundedRect: face, cornerSize: CGSize(width: 10, height: 10))
        ctx.fill(button, with: .color(Ink.red))
        inked(&ctx, button, 3)
        outlined(&ctx, "DIVE", 20, fill: Ink.paperLight, width: 2, at: CGPoint(x: face.midX, y: face.midY), tracking: 1.5)

        drawKeys(&ctx, off: off)
    }

    /// Cream card keys with ink outlines and an offset ink shadow. A pressed key squashes down onto its shadow.
    private func drawKeys(_ ctx: inout GraphicsContext, off: CGFloat) {
        let kept = DeepEndCache.keys(for: lay)
        var c = ctx
        c.translateBy(x: 0, y: off)
        c.fill(kept.shadows, with: .color(Ink.ink))
        c.fill(kept.caps, with: .color(Ink.paperLight))
        inked(&c, kept.caps, 2.2)
        let pressed = pic.pressTime > 0 && pic.pressKey >= 0 && pic.pressKey <= DeepEndRules.space ? pic.pressKey : -1
        if pressed >= 0 {
            let r = lay.keyRect(pressed).insetBy(dx: 1, dy: 1)
            c.fill(Path(r.insetBy(dx: -2, dy: -2).union(r.offsetBy(dx: 2, dy: 3).insetBy(dx: -2, dy: -2))), with: .color(Ink.paper))
            let squashed = Path(roundedRect: CGRect(x: r.minX + 1, y: r.minY + 4, width: r.width + 1, height: r.height - 2),
                                cornerSize: CGSize(width: 7, height: 7))
            c.fill(squashed, with: .color(Ink.paperShade))
            inked(&c, squashed, 2.2)
        }
        for code in 0...DeepEndRules.space {
            let r = lay.keyRect(code)
            let down: CGFloat = code == pressed ? 3.5 : 0
            let mid = CGPoint(x: r.midX + (code == pressed ? 1 : 0), y: r.midY - 1 + down)
            if code == DeepEndRules.space {
                label(&c, "space", lay.compact ? 13 : 14, .semibold, .serif, Ink.sepia, at: mid, tracking: 1.5)
            } else if code == DeepEndRules.back {
                var arrow = Path()
                arrow.move(to: CGPoint(x: mid.x - 11, y: mid.y))
                arrow.addLine(to: CGPoint(x: mid.x - 4, y: mid.y - 7))
                arrow.addLine(to: CGPoint(x: mid.x + 11, y: mid.y - 7))
                arrow.addLine(to: CGPoint(x: mid.x + 11, y: mid.y + 7))
                arrow.addLine(to: CGPoint(x: mid.x - 4, y: mid.y + 7))
                arrow.closeSubpath()
                arrow.move(to: CGPoint(x: mid.x - 1, y: mid.y - 3))
                arrow.addLine(to: CGPoint(x: mid.x + 6, y: mid.y + 3))
                arrow.move(to: CGPoint(x: mid.x + 6, y: mid.y - 3))
                arrow.addLine(to: CGPoint(x: mid.x - 1, y: mid.y + 3))
                inked(&c, arrow, 2)
            } else {
                label(&c, DeepEndRules.keyLabels[code], lay.compact ? 16 : 18, .black, .rounded, Ink.ink, at: mid)
            }
        }
    }

    // MARK: Ending

    /// The iris closes on the krill.
    private func drawIris(_ ctx: inout GraphicsContext) {
        let k = pic.endTime
        let close = k < 0.35 ? 0 : 1 - pow(1 - Swift.min(1, (k - 0.35) / 1.2), 3)
        if close <= 0 { return }
        let p = krillPoint
        let far = (lay.w * lay.w + lay.h * lay.h).squareRoot()
        let r = far + (82 - far) * CGFloat(close)
        var shade = Path(CGRect(x: -10, y: -10, width: lay.w + 20, height: lay.h + 20))
        shade.addEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
        ctx.fill(shade, with: .color(Ink.ink), style: FillStyle(eoFill: true))
        ctx.stroke(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                   with: .color(Ink.sepia.opacity(0.8)), lineWidth: 2)
    }

    private func drawEnding(_ ctx: inout GraphicsContext) {
        let a = Swift.min(1, pic.endTime / 0.4)
        var c = ctx
        c.opacity = a
        let y = Swift.max(lay.cardY + 24, krillPoint.y - 150) - CGFloat(1 - a) * 8
        outlined(&c, pic.headline, lay.compact ? 18 : 21, fill: Ink.paperLight, width: 2.5, shadow: 2,
                 at: CGPoint(x: lay.w / 2, y: y), tracking: 1)
    }

    private func drawHint(_ ctx: inout GraphicsContext) {
        let W = lay.w
        let y = lay.h - GameLayout.bottomInset - 56
        let words = type("TAP TO DIVE", 18, .black, .rounded, Ink.ink, tracking: 2.5)
        let w = width(&ctx, words) + 44
        let pulse = offBeat ? 2 : 0
        let pill = CGRect(x: (W / 2 - w / 2).rounded(), y: y - 21 - CGFloat(pulse), width: w.rounded(), height: 42)
        card(&ctx, pill, radius: 21, shadow: CGSize(width: 3, height: 4 + CGFloat(pulse)))
        ctx.draw(words, at: CGPoint(x: pill.midX, y: pill.midY), anchor: .center)
    }

    // MARK: Film

    private func drawFilm(_ ctx: inout GraphicsContext) {
        let W = lay.w, H = lay.h
        let frame = Int(pic.clock * 18)
        let screen = Path(CGRect(x: 0, y: 0, width: W, height: H))
        let far = (W * W + H * H).squareRoot() / 2

        // Grain that jumps every frame.
        let grain = DeepEndCache.grain(for: lay)
        var g = ctx
        g.translateBy(x: -CGFloat(DeepEndRandom.hash(frame) * 64), y: -CGFloat(DeepEndRandom.hash(frame &+ 7919) * 64))
        g.fill(grain.dark, with: .color(Ink.grainDark))
        g.fill(grain.light, with: .color(Ink.grainLight))

        // Now and then a faint scratch runs down the film.
        let reel = frame / 5
        if DeepEndRandom.hash(reel &* 31) < 0.3 {
            let x = CGFloat(DeepEndRandom.hash(reel &* 31 &+ 1)) * W
            var line = Path()
            line.move(to: CGPoint(x: x, y: 0))
            line.addQuadCurve(to: CGPoint(x: x + 3, y: H), control: CGPoint(x: x - 4, y: H * 0.5))
            ctx.stroke(line, with: .color(Ink.scratch), lineWidth: 1)
        }

        // A little flicker and a soft vignette.
        ctx.fill(screen, with: .color(Ink.ink.opacity(DeepEndRandom.hash(frame &* 3) * 0.035)))
        ctx.fill(screen, with: .radialGradient(Ink.vignette, center: CGPoint(x: W / 2, y: H * 0.46), startRadius: 0, endRadius: far))
    }
}

// MARK: - The clip

/// A scripted round for covers and the video feed: seven prompts, each read, typed and answered,
/// the krill sinking past the zones. The phase runs from the first prompt to the end of the round.
enum DeepEndClip {
    private struct Beat {
        let question: String
        let answer: String
        let tier: Int
    }

    private static let beats: [Beat] = [
        Beat(question: "NAME AN OCEAN ANIMAL", answer: "NARWHAL", tier: 3),
        Beat(question: "NAME A BIRD", answer: "KAKAPO", tier: 5),
        Beat(question: "NAME A FRUIT", answer: "DURIAN", tier: 4),
        Beat(question: "NAME A CHEESE", answer: "STILTON", tier: 4),
        Beat(question: "NAME A COLOR", answer: "VERDIGRIS", tier: 6),
        Beat(question: "NAME A SPORT", answer: "CURLING", tier: 4),
        Beat(question: "NAME A FLOWER", answer: "PROTEA", tier: 5)
    ]

    private static let think = 0.9
    private static let perKey = 0.12
    private static let hold = 0.35
    private static let lead = 0.5

    /// When each prompt opens, then when the round ends.
    private static let starts: [Double] = {
        var out: [Double] = []
        var t = 0.0
        for beat in beats {
            out.append(t)
            t += DeepEndRules.introTime + think + Double(beat.answer.count) * perKey + hold + DeepEndRules.revealTime
        }
        out.append(t)
        return out
    }()

    private static let friends = [DeepEndMarker(name: "KAZ 4,180M", depth: 4180),
                                  DeepEndMarker(name: "NOOR.RUNS 1,980M", depth: 1980)]

    static func picture(at phase: Double, size: CGSize) -> DeepEndPicture {
        let lay = DeepEndLayout(size: size)
        let roundEnd = starts[beats.count]
        let total = roundEnd + DeepEndRules.endTime
        let p = phase.isFinite ? Swift.max(0, Swift.min(1, phase)) : 0
        let t = lead + p * (total - lead)

        var pic = DeepEndPicture()
        pic.clock = t
        pic.started = true
        pic.titleAlpha = Swift.max(0, 1 - t * 3)
        pic.keyboard = Swift.min(1, t * 3.5)
        pic.friends = friends
        pic.results.reserveCapacity(beats.count)

        // The krill and the readout ease towards each new depth, as in the game.
        var krill = 14.0, krillGoal = 40.0, shown = 0.0, shownGoal = 0.0, last = 0.0
        func settle(until time: Double) {
            let k = exp(-2.2 * Swift.max(0, time - last))
            krill = krillGoal + (krill - krillGoal) * k
            shown = shownGoal + (shown - shownGoal) * k
            last = time
        }

        var placed = false
        for (k, beat) in beats.enumerated() {
            let open = starts[k]
            let answerFrom = open + DeepEndRules.introTime
            let typeFrom = answerFrom + think
            let keys = Array(beat.answer)
            let go = typeFrom + Double(keys.count) * perKey + hold
            pic.promptIndex = k
            pic.question = beat.question
            if t < go {
                pic.step = t < answerFrom ? .intro : .answer
                pic.stepTime = t < answerFrom ? t - open : t - answerFrom
                pic.timeLeft = DeepEndRules.answerTime - Swift.max(0, t - answerFrom)
                if t >= typeFrom {
                    let typed = Swift.min(keys.count, Int((t - typeFrom) / perKey) + 1)
                    pic.input = String(keys.prefix(typed))
                    let pressedAt = typeFrom + Double(typed - 1) * perKey
                    if t - pressedAt < 0.12, let code = DeepEndRules.code(for: keys[typed - 1]) {
                        pic.pressKey = code
                        pic.pressTime = 0.12 - (t - pressedAt)
                    }
                }
                placed = true
                break
            }
            settle(until: go)
            let points = DeepEndRules.points[beat.tier - 1]
            pic.points += points
            pic.results.append(beat.tier)
            shownGoal = Double(pic.points * 10)
            krillGoal = Swift.max(40, shownGoal)
            if t < go + DeepEndRules.revealTime {
                pic.step = .reveal
                pic.stepTime = t - go
                pic.input = beat.answer
                pic.timeLeft = DeepEndRules.answerTime - (go - answerFrom)
                pic.reveal = DeepEndReveal(name: beat.answer, tier: beat.tier, points: points)
                if t - go < 0.12 {
                    pic.pressKey = DeepEndRules.dive
                    pic.pressTime = 0.12 - (t - go)
                }
                placed = true
                break
            }
        }
        if !placed {
            pic.ending = true
            pic.step = .done
            pic.promptIndex = beats.count
            pic.endTime = t - roundEnd
            pic.keyboard = Swift.max(0, 1 - pic.endTime * 2.5)
            pic.headline = DeepEndRules.headline(pic.points * 10).uppercased()
        }
        settle(until: t)
        pic.krill = krill
        pic.shown = abs(shownGoal - shown) < 1 ? shownGoal : shown
        pic.cam = Swift.max(0, krill - Double(lay.anchorY - lay.baseY))

        // Scenery that only needs the time and the camera.
        let W = Double(lay.w), H = Double(lay.h), baseY = Double(lay.baseY)
        var rng = DeepEndRandom(seed: 7, salt: 0xD1B54A32D192ED03)
        pic.fish.reserveCapacity(9)
        for _ in 0..<9 {
            let x0 = rng.next() * W, d0 = rng.next() * (H + 40)
            let vx = (rng.next() < 0.5 ? -1.0 : 1.0) * rng.range(14, 40)
            let x = mod(x0 + vx * t + 30, W + 60) - 30
            let rel = mod(d0 - pic.cam, H + 40) - (baseY + 20)
            pic.fish.append(DeepEndFish(x: x, depth: pic.cam + rel, vx: vx))
        }
        pic.motes.reserveCapacity(36)
        for _ in 0..<36 {
            let x = rng.next() * W, y0 = rng.next() * H
            pic.motes.append(DeepEndMote(x: x, y: mod(y0 + 5 * t - 0.5 * pic.cam, H), size: rng.next() < 0.3 ? 2 : 1))
        }
        let clouds: [(x: Double, y: Double, s: Double)] = [(0.04, 52, 0.9), (0.6, 40, 0.7), (0.3, 30, 0.6)]
        for cloud in clouds {
            pic.clouds.append(DeepEndCloud(x: mod(W * cloud.x + 4 * cloud.s * t + 80, W + 100) - 80, y: cloud.y, s: cloud.s))
        }
        let speed = Swift.max(0, (krillGoal - krill) * 2.2)
        let gap = speed > 30 ? 0.1 : 0.45
        let rise = pic.cam > 0 ? speed : 0
        let krillY = baseY + krill - pic.cam
        for i in 0..<Int(1.6 / gap) {
            let age = mod(t + Double(i) * gap, 1.6)
            let x = W / 2 + sin((t - age) * 1.3) * 14 - 16 + rng.next() * 10
            pic.bubbles.append(DeepEndBubble(x: x, y: krillY - 6 - (40 + rise) * age, r: rng.range(1.5, 4), life: 1.6 - age))
        }
        return pic
    }

    private static func mod(_ a: Double, _ b: Double) -> Double {
        let r = a.truncatingRemainder(dividingBy: b)
        return r < 0 ? r + b : r
    }
}
