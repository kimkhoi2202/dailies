import SwiftUI

// Deep End: one prompt at a time, one typed answer each. Rarer answers sink the krill deeper.
//
// A pixel ocean drawn in code by DeepEndPainter from a DeepEndPicture. The playable game fills the
// picture from its model; the clip in the video feed builds one from a phase (0...1) and a fixed
// script. No assets, any frame size.

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

    static let cyan = hex(0x41D6F2)
    static let pink = hex(0xFF5C8A)
    static let white = hex(0xF2F7FB)
    static let dim = hex(0x7891AD)
    static let key = hex(0x1B2C47)
    static let keyDown = hex(0x2A4266)
    static let keyEdge = hex(0x0A1424)
    static let keyText = hex(0xCFE6F5)
    static let tiers: [Color] = [0xBFE9FF, 0x7FD4F5, 0x41D6F2, 0x9C8CFF, 0xFF5C8A, 0xFFC531].map { hex($0) }
    static let missed = hex(0x3A4A5E)
    static let ink = hex(0x081222)
    static let placeholder = hex(0x3E5670)
    static let diveBase = hex(0x8E2944)
    static let diveTop = hex(0xE0587C)
    static let diveText = hex(0x2A0B16)
    static let titleDeep = hex(0x1D6E8C)
    static let titleSoft = hex(0x3D6F8A)
    static let foam = hex(0xBFE6F7)
    static let floor = hex(0x02040A)

    static let cardFill = rgb(10, 19, 34, 0.9)
    static let pipEmpty = rgb(10, 20, 36, 0.8)
    static let shelf = rgb(4, 9, 18, 0.84)
    static let hintFill = rgb(8, 16, 30, 0.86)
    static let ringBack = rgb(65, 214, 242, 0.18)
    static let barBack = rgb(65, 214, 242, 0.15)
    static let majorZone = rgb(65, 214, 242, 0.55)
    static let zoneTick = rgb(160, 190, 220, 0.35)
    static let zoneText = rgb(170, 200, 230, 0.6)
    static let ruler = rgb(150, 180, 210, 0.3)
    static let rulerMajor = rgb(150, 180, 210, 0.55)
    static let mote = rgb(200, 225, 245, 0.25)
    static let bubble = rgb(200, 235, 255, 0.55)
    static let kelp = rgb(5, 18, 34, 0.55)
    static let surfaceGlare = rgb(255, 255, 255, 0.35)
    static let friend = rgb(255, 197, 49, 0.75)
    static let scanLight = rgb(255, 255, 255, 0.035)
    static let scanDark = rgb(0, 0, 0, 0.09)

    static let sunGlow = Gradient(colors: [rgb(255, 236, 170, 0.55), rgb(255, 236, 170, 0)])
    static let krillGlow = Gradient(colors: [rgb(255, 77, 103, 0.32), rgb(255, 77, 103, 0)])

    /// The water's colour every 10 m from the surface to 8,000 m.
    static let water: [Color] = {
        let stops: [[Double]] = [[0, 58, 127, 181], [150, 37, 96, 143], [500, 23, 63, 102], [1200, 14, 38, 67],
                                 [3000, 8, 22, 41], [6000, 5, 11, 22], [8000, 3, 6, 13]]
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

    /// Fourteen bands of sky, from the top down to the horizon.
    static let sky: [Color] = (0..<14).map { i in
        let k = Double(i) / 13
        return rgb((126 + 88 * k).rounded(), (200 + 40 * k).rounded(), (234 + 14 * k).rounded())
    }
}

// MARK: - Pixel type

/// A 5 x 7 pixel font. Every string becomes one path, made the first time it is drawn and kept.
enum DeepEndText {
    private struct Key: Hashable {
        let text: String
        let scale: CGFloat
        let track: CGFloat
    }

    private struct Run {
        let x: Int
        let y: Int
        let length: Int
    }

    static let glyphs: [Character: String] = [
        "0": ".###.#...##..###.#.###..##...#.###.",
        "1": "..#...##....#....#....#....#...###.",
        "2": ".###.#...#....#...#...#...#...#####",
        "3": "####.....#....#.###.....#....#####.",
        "4": "...#...##..#.#.#..#.#####...#....#.",
        "5": "######....####.....#....##...#.###.",
        "6": ".###.#....#....####.#...##...#.###.",
        "7": "#####....#...#...#...#....#....#...",
        "8": ".###.#...##...#.###.#...##...#.###.",
        "9": ".###.#...##...#.####....#....#.###.",
        "A": ".###.#...##...#######...##...##...#",
        "B": "####.#...##...#####.#...##...#####.",
        "C": ".###.#...##....#....#....#...#.###.",
        "D": "####.#...##...##...##...##...#####.",
        "E": "######....#....####.#....#....#####",
        "F": "######....#....####.#....#....#....",
        "G": ".###.#...##....#.####...##...#.####",
        "H": "#...##...##...#######...##...##...#",
        "I": ".###...#....#....#....#....#...###.",
        "J": "..###...#....#....#....#.#..#..##..",
        "K": "#...##..#.#.#..##...#.#..#..#.#...#",
        "L": "#....#....#....#....#....#....#####",
        "M": "#...###.###.#.##.#.##...##...##...#",
        "N": "#...##...###..##.#.##..###...##...#",
        "O": ".###.#...##...##...##...##...#.###.",
        "P": "####.#...##...#####.#....#....#....",
        "Q": ".###.#...##...##...##.#.##..#..##.#",
        "R": "####.#...##...#####.#.#..#..#.#...#",
        "S": ".#####....#.....###.....#....#####.",
        "T": "#####..#....#....#....#....#....#..",
        "U": "#...##...##...##...##...##...#.###.",
        "V": "#...##...##...##...##...#.#.#...#..",
        "W": "#...##...##...##.#.##.#.##.#.#.#.#.",
        "X": "#...##...#.#.#...#...#.#.#...##...#",
        "Y": "#...##...#.#.#...#....#....#....#..",
        "Z": "#####....#...#...#...#...#....#####",
        ".": "................................#..",
        ",": "...........................#...#...",
        "-": "................###................",
        "+": ".......#....#..#####..#....#.......",
        ":": ".......#...................#.......",
        "?": ".###.#...#....#...#...#.........#..",
        "<": ".......#...#...#####.#.....#.......",
        "v": "##########.###..###...#....#......."
    ]

    /// Each glyph as runs of lit pixels along its rows.
    private static let runs: [Character: [Run]] = {
        var out: [Character: [Run]] = [:]
        for (ch, bits) in glyphs {
            let cells = Array(bits)
            var list: [Run] = []
            for y in 0..<7 {
                var x = 0
                while x < 5 {
                    let at = y * 5 + x
                    guard at < cells.count, cells[at] == "#" else { x += 1; continue }
                    var length = 1
                    while x + length < 5, at + length < cells.count, cells[at + length] == "#" { length += 1 }
                    list.append(Run(x: x, y: y, length: length))
                    x += length
                }
            }
            out[ch] = list
        }
        return out
    }()

    private static var paths: [Key: Path] = [:]
    private static var wraps: [Key: [String]] = [:]

    static func width(_ text: String, _ s: CGFloat, _ track: CGFloat = 0) -> CGFloat {
        let n = CGFloat(text.count)
        return n > 0 ? (n * 6 - 1) * s + (n - 1) * track : 0
    }

    /// The string with its top left corner at the origin.
    static func path(_ text: String, _ s: CGFloat, _ track: CGFloat) -> Path {
        let key = Key(text: text, scale: s, track: track)
        if let kept = paths[key] { return kept }
        if paths.count > 600 { paths.removeAll(keepingCapacity: true) }
        var path = Path()
        var x: CGFloat = 0
        for ch in text {
            if let list = runs[ch] {
                for run in list {
                    path.addRect(CGRect(x: x + CGFloat(run.x) * s, y: CGFloat(run.y) * s,
                                        width: CGFloat(run.length) * s, height: s))
                }
            }
            x += 6 * s + track
        }
        paths[key] = path
        return path
    }

    /// Breaks a line of words to fit a width.
    static func wrap(_ text: String, _ s: CGFloat, _ maxWidth: CGFloat) -> [String] {
        let key = Key(text: text, scale: s, track: maxWidth)
        if let kept = wraps[key] { return kept }
        if wraps.count > 200 { wraps.removeAll(keepingCapacity: true) }
        var lines: [String] = []
        var line = ""
        for word in text.split(separator: " ") {
            let next = line.isEmpty ? String(word) : line + " " + word
            if !line.isEmpty, width(next, s) > maxWidth {
                lines.append(line)
                line = String(word)
            } else {
                line = next
            }
        }
        if !line.isEmpty { lines.append(line) }
        wraps[key] = lines
        return lines
    }
}

// MARK: - Pixel sprites

struct DeepEndSprite {
    let layers: [(color: Color, path: Path)]
    let width: CGFloat
    let height: CGFloat

    init(_ rows: [String], _ palette: [Character: Color], _ s: CGFloat) {
        var paths: [Character: Path] = [:]
        for (y, row) in rows.enumerated() {
            let cells = Array(row)
            var x = 0
            while x < cells.count {
                let ch = cells[x]
                guard palette[ch] != nil else { x += 1; continue }
                var length = 1
                while x + length < cells.count, cells[x + length] == ch { length += 1 }
                paths[ch, default: Path()].addRect(CGRect(x: CGFloat(x) * s, y: CGFloat(y) * s,
                                                          width: CGFloat(length) * s, height: s))
                x += length
            }
        }
        layers = paths.compactMap { ch, path in palette[ch].map { (color: $0, path: path) } }
        width = CGFloat(rows.first?.count ?? 0) * s
        height = CGFloat(rows.count) * s
    }

    func draw(_ ctx: inout GraphicsContext, x: CGFloat, y: CGFloat, scale: CGFloat = 1) {
        var c = ctx
        c.translateBy(x: x, y: y)
        if scale != 1 { c.scaleBy(x: scale, y: scale) }
        for layer in layers { c.fill(layer.path, with: .color(layer.color)) }
    }
}

enum DeepEndSprites {
    static let krill: [DeepEndSprite] = {
        let palette: [Character: Color] = [
            "a": DeepEndInk.hex(0xFF9AAA), "r": DeepEndInk.hex(0xFF4D67), "R": DeepEndInk.hex(0xFF8E9C),
            "w": DeepEndInk.hex(0xFFFFFF), "k": DeepEndInk.hex(0x1A0F14), "l": DeepEndInk.hex(0xD12C47)
        ]
        let body = ["..a...........", ".a.a..........", "a...a.rrrr....", "....rrRRRRrr..",
                    "...rwkrRRRRrr.", "..rrrrrrrrrrrr", "...rrrrrrrr.rr"]
        return [DeepEndSprite(body + ["....l.l.l.l.r.", "...l.l.l.l..rr"], palette, 3),
                DeepEndSprite(body + ["...l.l.l.l..r.", "....l.l.l.l.rr"], palette, 3)]
    }()

    private static let fishRows = ["..###...", ".#####.#", "########", ".#####.#", "..###..."]
    private static let fishInk: [Character: Color] = ["#": DeepEndInk.rgb(6, 16, 30, 0.8)]
    static let fishLeft = DeepEndSprite(fishRows, fishInk, 3)
    static let fishRight = DeepEndSprite(fishRows.map { String($0.reversed()) }, fishInk, 3)

    static let sun: DeepEndSprite = {
        var rows: [String] = []
        for y in 0..<20 {
            var row = ""
            for x in 0..<20 {
                let dx = Double(x) - 9.5, dy = Double(y) - 9.5
                let d = (dx * dx + dy * dy).squareRoot()
                row.append(d < 8 ? "c" : d < 9.6 ? "r" : ".")
            }
            rows.append(row)
        }
        return DeepEndSprite(rows, ["c": DeepEndInk.hex(0xFFF1B8), "r": DeepEndInk.hex(0xFFE08A)], 3)
    }()

    static let cloud = DeepEndSprite(["......####........", "....########..##..", "..##############..",
                                      ".################.", "##################", ".gggggggggggggggg."],
                                     ["#": DeepEndInk.hex(0xFFFFFF), "g": DeepEndInk.hex(0xDCEEF6)], 4)

    static let boat = DeepEndSprite(["....f.....", "....fpp...", "....f.....", "..dddd....", "dddddddddd", ".dddddddd."],
                                    ["d": DeepEndInk.hex(0x1E2B3A), "f": DeepEndInk.hex(0x1E2B3A), "p": DeepEndInk.pink], 3)
}

// MARK: - Layout

/// Where everything sits on a screen of a given size, in points. One point is one pixel of the art.
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
    var messageColor = DeepEndInk.pink
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

// MARK: - Painter

struct DeepEndPainter {
    enum Align { case left, center, right }

    private typealias Ink = DeepEndInk
    private typealias Txt = DeepEndText

    let pic: DeepEndPicture
    let lay: DeepEndLayout
    let showHUD: Bool

    init(size: CGSize, picture: DeepEndPicture, showHUD: Bool) {
        pic = picture
        lay = DeepEndLayout(size: size)
        self.showHUD = showHUD
    }

    private func screenY(_ depth: Double) -> CGFloat { lay.baseY + CGFloat(depth - pic.cam) }

    func draw(_ ctx: inout GraphicsContext) {
        drawScene(&ctx)
        if pic.titleAlpha > 0 { drawTitle(&ctx) }
        if pic.started, showHUD { drawHud(&ctx) }
        if pic.started, !pic.ending { drawCard(&ctx) }
        if pic.step == .reveal, let reveal = pic.reveal { drawReveal(&ctx, reveal) }
        if pic.keyboard > 0 { drawInput(&ctx) }
        if pic.ending { drawEnding(&ctx) }
        if pic.showHint { drawHint(&ctx) }
        drawScanlines(&ctx)
    }

    // MARK: Helpers

    private func rect(_ ctx: inout GraphicsContext, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ color: Color) {
        ctx.fill(Path(CGRect(x: x, y: y, width: w, height: h)), with: .color(color))
    }

    private func text(_ ctx: inout GraphicsContext, _ str: String, _ x: CGFloat, _ y: CGFloat, _ s: CGFloat,
                      _ color: Color, _ align: Align = .left, _ track: CGFloat = 0) {
        if str.isEmpty { return }
        let w = Txt.width(str, s, track)
        let x0 = align == .center ? x - w / 2 : align == .right ? x - w : x
        var c = ctx
        c.translateBy(x: x0.rounded(), y: y.rounded())
        c.fill(Txt.path(str, s, track), with: .color(color))
    }

    /// White type with a pink and a cyan ghost either side.
    private func chroma(_ ctx: inout GraphicsContext, _ str: String, _ x: CGFloat, _ y: CGFloat, _ s: CGFloat,
                        _ align: Align = .left, _ track: CGFloat = 0) {
        let o = Swift.max(1, (s / 2).rounded())
        text(&ctx, str, x - o, y + o, s, Ink.pink, align, track)
        text(&ctx, str, x + o, y - o, s, Ink.cyan, align, track)
        text(&ctx, str, x, y, s, Ink.white, align, track)
    }

    /// A box with its corners knocked off, pixel style.
    private func panel(_ ctx: inout GraphicsContext, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ color: Color) {
        var p = Path()
        p.addRect(CGRect(x: x + 6, y: y, width: w - 12, height: h))
        p.addRect(CGRect(x: x, y: y + 6, width: w, height: h - 12))
        p.addRect(CGRect(x: x + 2, y: y + 2, width: w - 4, height: h - 4))
        ctx.fill(p, with: .color(color))
    }

    private func glow(_ ctx: inout GraphicsContext, _ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, _ gradient: Gradient) {
        let center = CGPoint(x: cx, y: cy)
        ctx.fill(Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)),
                 with: .radialGradient(gradient, center: center, startRadius: 0, endRadius: r))
    }

    // MARK: The ocean

    private func drawScene(_ ctx: inout GraphicsContext) {
        let W = lay.w, H = lay.h
        let t = pic.clock
        let sy = screenY(0).rounded()

        if sy > 0 {
            let bh = (sy / CGFloat(Ink.sky.count)).rounded(.up)
            for b in 0..<Ink.sky.count { rect(&ctx, 0, CGFloat(b) * bh, W, bh + 1, Ink.sky[b]) }
            let sunX = (W * 0.84).rounded(), sunY = (sy - 56).rounded()
            glow(&ctx, sunX, sunY, 85, Ink.sunGlow)
            DeepEndSprites.sun.draw(&ctx, x: sunX - 30, y: sunY - 30)
            for cloud in pic.clouds {
                DeepEndSprites.cloud.draw(&ctx, x: CGFloat(cloud.x).rounded(), y: (sy - CGFloat(cloud.y)).rounded(), scale: CGFloat(cloud.s))
            }
            rect(&ctx, 0, sy - 18, W, 18, Ink.surfaceGlare)
        }

        // Water in 6 point bands, one fill per run of the same colour.
        let band: CGFloat = 6
        var y = Swift.max(0, sy)
        var runStart = y
        var runIndex = -1
        while y < H {
            let d = pic.cam + Double(y + band / 2 - lay.baseY)
            let index = d <= 0 ? 0 : Swift.min(Ink.water.count - 1, Int(d / 10))
            if index != runIndex {
                if runIndex >= 0 { rect(&ctx, 0, runStart, W, y - runStart, Ink.water[runIndex]) }
                runIndex = index
                runStart = y
            }
            y += band
        }
        if runIndex >= 0 { rect(&ctx, 0, runStart, W, y - runStart, Ink.water[runIndex]) }

        if sy > -12, sy < H {
            var foam = Path()
            var wx: CGFloat = 0
            while wx < W {
                let lift = (sin(Double(wx) * 0.035 + t * 1.6) * 1.5).rounded()
                foam.addRect(CGRect(x: wx, y: sy - 2 + CGFloat(lift), width: 4, height: 3))
                wx += 4
            }
            ctx.fill(foam, with: .color(Ink.foam))
            let bob = CGFloat((sin(t * 1.4) * 1.5).rounded())
            DeepEndSprites.boat.draw(&ctx, x: (W * 0.26).rounded(), y: sy - DeepEndSprites.boat.height + 4 + bob)
        }

        let labelTop = pic.started ? lay.cardY + lay.cardH + 8 : -20
        for (z, zone) in DeepEndOcean.zones.enumerated() {
            let zy = screenY(zone.depth)
            if zy < labelTop || zy > H + 20 { continue }
            if zone.major {
                text(&ctx, zone.text, W / 2 - 12, zy - 7, 2, Ink.majorZone, .center, 2)
            } else if z % 2 == 1 {
                rect(&ctx, 16, zy.rounded(), 18, 1, Ink.zoneTick)
                text(&ctx, zone.text, 40, zy - 3, 1, Ink.zoneText, .left, 1)
            } else {
                rect(&ctx, W - 70, zy.rounded(), 18, 1, Ink.zoneTick)
                text(&ctx, zone.text, W - 76, zy - 3, 1, Ink.zoneText, .right, 1)
            }
        }

        let kelpBase = screenY(330)
        if kelpBase > -10, kelpBase - 240 < H {
            var kelp = Path()
            let strands: [CGFloat] = [8, 30, 54, W - 66, W - 40]
            for (s, root) in strands.enumerated() {
                for seg in 0..<26 {
                    let sway = sin(t * 1.1 + Double(seg) * 0.45 + Double(s) * 1.7) * Double(seg) * 0.5
                    let kx = (root + CGFloat(sway)).rounded()
                    let ky = (kelpBase - CGFloat(seg) * 8).rounded()
                    kelp.addRect(CGRect(x: kx, y: ky - 8, width: 6, height: 8))
                    if seg % 3 == 1 { kelp.addRect(CGRect(x: seg % 2 == 1 ? kx + 6 : kx - 6, y: ky - 6, width: 6, height: 4)) }
                }
            }
            ctx.fill(kelp, with: .color(Ink.kelp))
        }

        for fish in pic.fish where fish.depth > 8 {
            let fy = screenY(fish.depth)
            if fy < -20 || fy > H + 20 { continue }
            let sprite = fish.vx > 0 ? DeepEndSprites.fishRight : DeepEndSprites.fishLeft
            sprite.draw(&ctx, x: CGFloat(fish.x).rounded(), y: fy.rounded())
        }

        let floorY = screenY(7000)
        if floorY < H {
            var ground = Path()
            ground.addRect(CGRect(x: 0, y: floorY.rounded(), width: W, height: H - floorY + 1))
            var fx = 0
            while CGFloat(fx) < W {
                ground.addRect(CGRect(x: CGFloat(fx), y: (floorY - CGFloat((fx * 37) % 5) * 3).rounded(), width: 8, height: 16))
                fx += 8
            }
            ctx.fill(ground, with: .color(Ink.floor))
        }

        drawRuler(&ctx, surface: sy, labelTop: labelTop)

        var motes = Path()
        for mote in pic.motes where CGFloat(mote.y) >= sy + 4 {
            motes.addRect(CGRect(x: CGFloat(mote.x).rounded(), y: CGFloat(mote.y).rounded(), width: CGFloat(mote.size), height: CGFloat(mote.size)))
        }
        ctx.fill(motes, with: .color(Ink.mote))

        for friend in pic.friends {
            let fy = screenY(friend.depth).rounded()
            if fy < labelTop || fy > H + 10 { continue }
            rect(&ctx, 6, fy, 26, 2, Ink.friend)
            rect(&ctx, 6, fy - 9, 2, 9, Ink.friend)
            text(&ctx, friend.name, 12, fy - 9, 1, Ink.friend, .left, 1)
        }

        let kx = lay.w / 2 + CGFloat(sin(t * 1.3) * 14)
        let ky = screenY(pic.krill) + CGFloat(sin(t * 2.1) * 3)
        glow(&ctx, kx.rounded(), ky.rounded(), 60, Ink.krillGlow)
        let busy = pic.started && !pic.ending
        let frame = Int(t * (busy ? 6 : 3)) % 2
        let sprite = DeepEndSprites.krill[frame]
        sprite.draw(&ctx, x: (kx - sprite.width / 2).rounded(), y: (ky - sprite.height / 2).rounded())

        for bubble in pic.bubbles where bubble.life > 0 && CGFloat(bubble.y) >= sy {
            var c = ctx
            c.opacity = Swift.min(1, bubble.life)
            let r = CGFloat(bubble.r)
            c.stroke(Path(ellipseIn: CGRect(x: CGFloat(bubble.x) - r, y: CGFloat(bubble.y) - r, width: r * 2, height: r * 2)),
                     with: .color(Ink.bubble), lineWidth: 1.5)
        }
    }

    private func drawRuler(_ ctx: inout GraphicsContext, surface sy: CGFloat, labelTop: CGFloat) {
        let H = lay.h
        let rx = lay.w - 22
        let lineTop = Swift.max(0, sy)
        if lineTop < H { rect(&ctx, rx, lineTop, 1, H - lineTop, Ink.ruler) }
        let dTop = Swift.max(0, pic.cam - Double(lay.baseY))
        let dBottom = pic.cam + Double(H - lay.baseY)
        var minor = Path()
        var major = Path()
        var m = Int((dTop / 50).rounded(.down)) * 50
        while Double(m) <= dBottom {
            let my = screenY(Double(m)).rounded()
            if m % 100 == 0 {
                major.addRect(CGRect(x: rx - 10, y: my, width: 10, height: 1))
                if my > labelTop { text(&ctx, m == 0 ? "0M" : "-\(m)M", rx - 14, my - 3, 1, Ink.zoneText, .right) }
            } else {
                minor.addRect(CGRect(x: rx - 5, y: my, width: 5, height: 1))
            }
            m += 50
        }
        ctx.fill(minor, with: .color(Ink.ruler))
        ctx.fill(major, with: .color(Ink.rulerMajor))
    }

    // MARK: Words over the water

    private func drawTitle(_ ctx: inout GraphicsContext) {
        var c = ctx
        c.opacity = Swift.max(0, Swift.min(1, pic.titleAlpha))
        let W = lay.w
        let ty = lay.top + (lay.compact ? 50 : 108)
        let big = Swift.max(2, Swift.min(6, ((W - 40) / 47).rounded(.down)))
        chroma(&c, "DEEP END", W / 2, ty, big, .center)
        text(&c, "THE DAILY DIVE", W / 2, ty + 60, 2, Ink.titleDeep, .center, 6)
        text(&c, "7 PROMPTS. 25 SECONDS EACH.", W / 2, ty + 92, 1, Ink.titleSoft, .center, 3)
        text(&c, "RARER ANSWERS SINK DEEPER.", W / 2, ty + 108, 1, Ink.titleSoft, .center, 3)
        if pic.best > 0 {
            text(&c, "BEST " + DeepEndRules.grouped(pic.best) + "M", W / 2, ty + 132, 1, Ink.titleDeep, .center, 3)
        }
    }

    private func drawHud(_ ctx: inout GraphicsContext) {
        let W = lay.w, top = lay.top
        let count = DeepEndRules.round
        let pw = CGFloat(count * 12 + (count - 1) * 5)
        let px = Swift.max(GameLayout.cornerWidth, Swift.min(W - GameLayout.cornerWidth - pw, W / 2 - pw / 2)).rounded()
        let y = top + 18
        for i in 0..<count {
            let x = px + CGFloat(i * 17)
            if i < pic.results.count {
                let tier = pic.results[i]
                rect(&ctx, x, y, 12, 12, tier > 0 ? Ink.tiers[tier - 1] : Ink.missed)
            } else if i == pic.promptIndex, !pic.ending {
                rect(&ctx, x - 2, y - 2, 16, 16, Ink.white)
                rect(&ctx, x, y, 12, 12, Ink.pink)
            } else {
                rect(&ctx, x, y, 12, 12, Ink.pipEmpty)
            }
        }
        let depth = DeepEndRules.grouped(Int(pic.shown.rounded())) + "M"
        if lay.compact {
            chroma(&ctx, depth, W / 2, top + 58, 3, .center, 1)
            return
        }
        text(&ctx, "DEPTH", W / 2, top + 60, 1, Ink.dim, .center, 3)
        chroma(&ctx, depth, W / 2, top + 74, 4, .center, 1)
        text(&ctx, "\(pic.points) PTS", W / 2, top + 108, 1, Ink.dim, .center, 2)
    }

    private func drawCard(_ ctx: inout GraphicsContext) {
        let x = lay.cardX, y = lay.cardY, w = lay.cardW, h = lay.cardH
        panel(&ctx, x, y, w, h, Ink.cardFill)
        text(&ctx, "PROMPT \(pic.promptIndex + 1) OF \(DeepEndRules.round)", x + 18, y + 16, 2, Ink.pink, .left, 3)
        var s: CGFloat = lay.compact ? 2 : 3
        var lines = Txt.wrap(pic.question, s, w - 36)
        if lines.count > 2 {
            s = 2
            lines = Txt.wrap(pic.question, s, w - 36)
        }
        // The question types itself out while the prompt opens.
        var left = pic.step == .intro ? Int(pic.stepTime * 70) : 999
        let lh = 7 * s + 8
        let ty = y + (lay.compact ? 40 : s == 3 ? 46 : 52)
        for (i, line) in lines.enumerated() {
            let count = line.count
            let visible = Swift.min(count, Swift.max(0, left))
            left -= count + 1
            if visible <= 0 { continue }
            let ly = ty + CGFloat(i) * lh
            if visible >= count {
                text(&ctx, line, x + 18, ly, s, Ink.white)
            } else {
                var c = ctx
                c.clip(to: Path(CGRect(x: x + 18, y: ly - 2, width: CGFloat(visible) * 6 * s, height: 7 * s + 4)))
                text(&c, line, x + 18, ly, s, Ink.white)
            }
        }
        text(&ctx, "v RARER ANSWERS SINK DEEPER v", x + 18, y + h - (lay.compact ? 14 : 19), 1, Ink.dim, .left, 2)
    }

    private func drawReveal(_ ctx: inout GraphicsContext, _ reveal: DeepEndReveal) {
        let W = lay.w
        let a = Swift.min(1, pic.stepTime / 0.15)
        let y = lay.cardY + lay.cardH + (lay.compact ? 10 : 18) - CGFloat(1 - a) * 8
        var c = ctx
        c.opacity = a
        let s: CGFloat = lay.compact || Txt.width(reveal.name, 3) > W - 40 ? 2 : 3
        if reveal.tier > 0 {
            let lines = Txt.wrap(reveal.name, s, W - 32)
            for (i, line) in lines.enumerated() { chroma(&c, line, W / 2, y + CGFloat(i) * (7 * s + 6), s, .center) }
            let below = y + CGFloat(lines.count) * (7 * s + 6) + 4
            text(&c, "+\(reveal.points)  " + DeepEndRules.tierNames[reveal.tier - 1], W / 2, below, 2,
                 Ink.tiers[reveal.tier - 1], .center, 3)
        } else {
            text(&c, "TIME", W / 2, y, s, Ink.pink, .center, 3)
            text(&c, "+0", W / 2, y + 7 * s + 10, 2, Ink.dim, .center, 3)
        }
    }

    private func drawInput(_ ctx: inout GraphicsContext) {
        let W = lay.w, H = lay.h
        let e = 1 - pow(1 - Swift.min(1, pic.keyboard), 3)
        let off = (CGFloat(1 - e) * (H - lay.inY + 30)).rounded()
        rect(&ctx, 0, lay.inY - 30 + off, W, H - lay.inY + 30, Ink.shelf)

        if pic.messageTime > 0, !pic.message.isEmpty {
            text(&ctx, pic.message, W / 2, lay.msgY - 7 + off - 26, 2,
                 pic.messageColor.opacity(Swift.min(1, pic.messageTime / 0.3)), .center, 3)
        }

        // The clock: a ring that empties, pink for the last six seconds.
        let cx = lay.timerX, cy = lay.inY + lay.inH / 2 + off
        let frac = Swift.max(0, pic.timeLeft / DeepEndRules.answerTime)
        let low = pic.step == .answer && pic.timeLeft <= 6
        let hot = low ? Ink.pink : Ink.cyan
        let rr = lay.inH / 2 - 4
        ctx.fill(Path(ellipseIn: CGRect(x: cx - rr - 4, y: cy - rr - 4, width: (rr + 4) * 2, height: (rr + 4) * 2)), with: .color(Ink.ink))
        ctx.stroke(Path(ellipseIn: CGRect(x: cx - rr, y: cy - rr, width: rr * 2, height: rr * 2)), with: .color(Ink.ringBack), lineWidth: 3)
        if frac > 0 {
            var arc = Path()
            arc.addArc(center: CGPoint(x: cx, y: cy), radius: rr, startAngle: .degrees(-90),
                       endAngle: .degrees(-90 + 360 * frac), clockwise: false)
            ctx.stroke(arc, with: .color(hot), lineWidth: 3)
        }
        text(&ctx, "\(Int(pic.timeLeft.rounded(.up)))", cx, cy - 7, 2, hot, .center)

        // The answer box shakes when the answer is not on the list.
        let sx = pic.shake > 0 ? CGFloat((sin(pic.shake * 70) * 5 * (pic.shake / 0.35)).rounded()) : 0
        let ix = lay.inX + sx, iy = lay.inY + off
        rect(&ctx, ix, iy, lay.inW, lay.inH, pic.shake > 0 ? Ink.pink : Ink.cyan)
        rect(&ctx, ix + 2, iy + 2, lay.inW - 4, lay.inH - 4, Ink.ink)
        let room = Swift.max(1, Int(((lay.inW - 24) / 12).rounded(.down)))
        let blink = (pic.clock * 2).truncatingRemainder(dividingBy: 2) < 1.2
        if !pic.input.isEmpty {
            let visible = pic.input.count > room ? String(pic.input.suffix(room)) : pic.input
            text(&ctx, visible, ix + 12, iy + lay.inH / 2 - 7, 2, Ink.white)
            if blink { rect(&ctx, ix + 12 + Txt.width(visible, 2) + 3, iy + 12, 2, lay.inH - 24, Ink.pink) }
        } else {
            text(&ctx, room >= 15 ? "TYPE ONE ANSWER" : "ANSWER", ix + 12, iy + lay.inH / 2 - 7, 2, Ink.placeholder)
            if blink { rect(&ctx, ix + 10, iy + 12, 2, lay.inH - 24, Ink.pink) }
        }
        rect(&ctx, lay.inX, iy + lay.inH + 4, lay.inW, 3, Ink.barBack)
        rect(&ctx, lay.inX, iy + lay.inH + 4, (lay.inW * CGFloat(frac)).rounded(), 3, hot)

        let dive = lay.dive
        let divePressed = pic.pressKey == DeepEndRules.dive && pic.pressTime > 0
        let diveTop = dive.minY + off + (divePressed ? 4 : 0)
        rect(&ctx, dive.minX, dive.minY + off + 4, dive.width, dive.height - 4, Ink.diveBase)
        rect(&ctx, dive.minX, diveTop, dive.width, dive.height - 4, Ink.diveTop)
        text(&ctx, "DIVE", dive.midX, diveTop + (dive.height - 4) / 2 - 7, 2, Ink.diveText, .center, 2)

        // The keys: every edge in one fill and every cap in another.
        var edges = Path()
        var caps = Path()
        var pressedCap: CGRect?
        for code in 0...DeepEndRules.space {
            let r = lay.keyRect(code)
            let kx = r.minX.rounded(), ky = (r.minY + off).rounded()
            let kw = r.maxX.rounded() - kx
            edges.addRect(CGRect(x: kx, y: ky + 3, width: kw, height: r.height - 3))
            if pic.pressKey == code && pic.pressTime > 0 {
                pressedCap = CGRect(x: kx, y: ky + 3, width: kw, height: r.height - 3)
            } else {
                caps.addRect(CGRect(x: kx, y: ky, width: kw, height: r.height - 3))
            }
        }
        ctx.fill(edges, with: .color(Ink.keyEdge))
        ctx.fill(caps, with: .color(Ink.key))
        if let pressedCap { ctx.fill(Path(pressedCap), with: .color(Ink.keyDown)) }
        for code in 0...DeepEndRules.space {
            let r = lay.keyRect(code)
            let kx = r.minX.rounded(), kw = r.maxX.rounded() - kx
            let down: CGFloat = pic.pressKey == code && pic.pressTime > 0 ? 3 : 0
            let ky = (r.minY + off).rounded() + down
            let isSpace = code == DeepEndRules.space
            let s: CGFloat = isSpace ? 1 : 2
            text(&ctx, DeepEndRules.keyLabels[code], kx + kw / 2, ky + (r.height - 3) / 2 - 3.5 * s, s, Ink.keyText, .center, isSpace ? 3 : 0)
        }
    }

    private func drawEnding(_ ctx: inout GraphicsContext) {
        let W = lay.w
        let a = Swift.min(1, pic.endTime / 0.4)
        var c = ctx
        c.opacity = a
        let lines = Txt.wrap(pic.headline, 2, W - 48)
        let y = lay.cardY + 20 - CGFloat(1 - a) * 8
        for (i, line) in lines.enumerated() { chroma(&c, line, W / 2, y + CGFloat(i) * 22, 2, .center, 2) }
    }

    private func drawHint(_ ctx: inout GraphicsContext) {
        let W = lay.w
        let y = lay.h - GameLayout.bottomInset - 76
        let hint = "TAP TO DIVE"
        let w = Txt.width(hint, 2, 3) + 40
        panel(&ctx, (W / 2 - w / 2).rounded(), y, w.rounded(), 40, Ink.hintFill)
        var c = ctx
        c.opacity = 0.75 + sin(pic.clock * 3) * 0.25
        text(&c, hint, W / 2, y + 13, 2, Ink.cyan, .center, 3)
    }

    private func drawScanlines(_ ctx: inout GraphicsContext) {
        let key = DeepEndScan.Key(w: Int(lay.w.rounded()), h: Int(lay.h.rounded()))
        let lines: DeepEndScan.Lines
        if let kept = DeepEndScan.kept[key] {
            lines = kept
        } else {
            var light = Path(), dark = Path()
            var y: CGFloat = 0
            while y < lay.h {
                light.addRect(CGRect(x: 0, y: y, width: lay.w, height: 1))
                dark.addRect(CGRect(x: 0, y: y + 2, width: lay.w, height: 1))
                y += 3
            }
            lines = DeepEndScan.Lines(light: light, dark: dark)
            if DeepEndScan.kept.count >= 8 { DeepEndScan.kept.removeAll(keepingCapacity: true) }
            DeepEndScan.kept[key] = lines
        }
        ctx.fill(lines.light, with: .color(Ink.scanLight))
        ctx.fill(lines.dark, with: .color(Ink.scanDark))
    }
}

/// The scanline paths for each canvas size drawn so far, kept between frames.
enum DeepEndScan {
    struct Key: Hashable {
        let w: Int
        let h: Int
    }

    struct Lines {
        let light: Path
        let dark: Path
    }

    static var kept: [Key: Lines] = [:]
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
