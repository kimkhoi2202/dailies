import SwiftUI

// Blind Box: pick one box off the shelf, sit through fifteen seconds of anime, get a pebble.
//
// BlindBoxScene    the game at one moment, 0 to 1, for covers and the Videos feed.
// BlindBoxItem     what can be inside a box, with its deadpan rarity and its points.
// BlindBoxShot     one shot of the cut scene.
// BlindBoxRules    timings, the items, the shots.
// BlindBoxLayout   where the shelves and the boxes sit, shared by drawing and touches.
// BlindBoxFrame    everything the painter needs for one frame.
// BlindBoxClip     turns a clip phase into a frame.
// BlindBoxPainter  draws a frame. The game draws with it too.
// BlindBoxFX       speed lines, petals and sparkles, made once.

public struct BlindBoxScene: View {
    public var phase: Double
    public var showHUD: Bool

    public init(phase: Double, showHUD: Bool) {
        self.phase = phase
        self.showHUD = showHUD
    }

    public var body: some View {
        Canvas(opaque: true, colorMode: .nonLinear, rendersAsynchronously: false) { context, size in
            if size.width <= 8 || size.height <= 8 { return }
            BlindBoxPainter(size: size, frame: BlindBoxClip.frame(at: phase), showHUD: showHUD).draw(&context)
        }
    }
}

// MARK: - Items

struct BlindBoxItem {
    let image: String
    let name: String
    /// How the results screen says it: "a used tea bag".
    let said: String
    let rarity: String
    let stars: Int
    let flavour: String
    let points: Int
    /// Words drawn on the art, and where, as a share of the image.
    var label: String? = nil
    var labelRect = CGRect.zero
    var labelColor = Color.black
}

// MARK: - Shots

struct BlindBoxShot {
    enum Move { case pushIn, pullOut, panRight, panUp, punch, spin, slowPush }
    let image: String
    let start: Double
    let end: Double
    let caption: String?
    let move: Move
    var shake: Double = 0
    var lines = false
    var petals = false
    var rainbow = false
    var power = false
    var rumble = false
    /// A quick cross cut inside a longer shot: a softer flash and no caption of its own.
    var insert = false
}

// MARK: - Rules

enum BlindBoxRules {
    static let boxCount = 9
    static let teaseTime = 1.4
    static let cutLength = 15.0
    static let whiteFrom = 14.2
    static let beatTime = 1.3
    static let holdTime = 4.8
    static let skipAfter = 6.0
    static let skipTo = 12.8
    static let noteTime = 1.8

    static let tags = ["SSR", "???", "MYTHIC", "SECRET", "UR", "LIMITED", "EX", "No. 0", "OMEGA"]
    /// Which tinted box art each shelf slot uses.
    static let colours = [0, 1, 2, 3, 4, 0, 2, 4, 1]

    static let items: [BlindBoxItem] = [
        BlindBoxItem(image: "blind-box-item-sign", name: "A Sign", said: "a sign that says DUMDUM",
                     rarity: "ULTRA LEGENDARY", stars: 6, flavour: "It is about you.", points: 3,
                     label: "DUMDUM", labelRect: CGRect(x: 0.06, y: 0.1, width: 0.88, height: 0.42),
                     labelColor: Color(red: 0.24, green: 0.13, blue: 0.07)),
        BlindBoxItem(image: "blind-box-item-rose", name: "Wilting Rose", said: "a wilting rose",
                     rarity: "MYTHIC PRIME", stars: 6, flavour: "It was lovely yesterday.", points: 7),
        BlindBoxItem(image: "blind-box-item-sock", name: "One Sock", said: "one sock",
                     rarity: "CELESTIAL RARE", stars: 5, flavour: "The other one is gone for good.", points: 2),
        BlindBoxItem(image: "blind-box-item-teabag", name: "Used Tea Bag", said: "a used tea bag",
                     rarity: "SECRET SUPER RARE", stars: 6, flavour: "Steeped twice. Still damp.", points: 4),
        BlindBoxItem(image: "blind-box-item-pebble", name: "A Pebble", said: "a pebble",
                     rarity: "DIVINE ANCIENT", stars: 7, flavour: "It is a pebble.", points: 1),
        BlindBoxItem(image: "blind-box-item-duck", name: "Duck With One Eye", said: "a duck with one eye",
                     rarity: "ULTRA RAINBOW", stars: 6, flavour: "It has seen enough.", points: 6),
        BlindBoxItem(image: "blind-box-item-bread", name: "Plain White Bread", said: "one slice of plain white bread",
                     rarity: "SACRED LEGENDARY", stars: 5, flavour: "One slice. No butter.", points: 5),
        BlindBoxItem(image: "blind-box-item-ribbon", name: "Participation Ribbon", said: "a participation ribbon",
                     rarity: "GRAND CHAMPION TIER", stars: 7, flavour: "You showed up. That is all.", points: 10,
                     label: "I TRIED", labelRect: CGRect(x: 0.27, y: 0.24, width: 0.46, height: 0.26),
                     labelColor: Color(red: 0.22, green: 0.36, blue: 0.62)),
        BlindBoxItem(image: "blind-box-item-paperclip", name: "A Paperclip", said: "a paperclip",
                     rarity: "COSMIC EXCLUSIVE", stars: 5, flavour: "Holds up to four sheets.", points: 2),
        BlindBoxItem(image: "blind-box-item-fry", name: "Soggy Fry", said: "a soggy fry",
                     rarity: "LIMITED EDITION", stars: 5, flavour: "Found under the car seat.", points: 3),
        BlindBoxItem(image: "blind-box-item-cactus", name: "Sad Cactus", said: "a sad cactus",
                     rarity: "MYTHIC ULTRA", stars: 6, flavour: "Needs water. Will not get any.", points: 4),
        BlindBoxItem(image: "blind-box-item-emptybox", name: "Empty Box", said: "an empty box",
                     rarity: "COLLECTOR GRADE", stars: 7, flavour: "The box was the gift.", points: 0),
        BlindBoxItem(image: "blind-box-item-lint", name: "Pocket Lint", said: "some pocket lint",
                     rarity: "ASTRAL SUPREME", stars: 6, flavour: "Still warm.", points: 1),
        BlindBoxItem(image: "blind-box-item-spoon", name: "Bent Plastic Spoon", said: "a bent plastic spoon",
                     rarity: "FINAL FORM", stars: 7, flavour: "It bent during the cut scene.", points: 3),
    ]

    static let shots: [BlindBoxShot] = [
        BlindBoxShot(image: "blind-box-kf-glow", start: 0.0, end: 1.7, caption: "SOMETHING STIRS INSIDE", move: .pushIn,
                     petals: true),
        BlindBoxShot(image: "blind-box-kf-eye", start: 1.7, end: 3.2, caption: "THAT LIGHT...", move: .panRight),
        BlindBoxShot(image: "blind-box-kf-sky", start: 3.2, end: 4.9, caption: "THE SKY TEARS OPEN", move: .pullOut,
                     shake: 5),
        BlindBoxShot(image: "blind-box-kf-rival", start: 4.9, end: 6.5, caption: "IT CANNOT BE. NOT THAT BOX.",
                     move: .punch, lines: true, rumble: true),
        BlindBoxShot(image: "blind-box-kf-transform", start: 6.5, end: 8.2, caption: "ASCENSION FORM", move: .spin,
                     petals: true),
        BlindBoxShot(image: "blind-box-kf-hero", start: 8.2, end: 9.25, caption: "POWER LEVEL RISING", move: .panUp,
                     shake: 4, lines: true, power: true),
        BlindBoxShot(image: "blind-box-kf-rival", start: 9.25, end: 9.45, caption: nil, move: .punch, lines: true,
                     insert: true),
        BlindBoxShot(image: "blind-box-kf-hero", start: 9.45, end: 9.9, caption: nil, move: .panUp, shake: 7,
                     lines: true, power: true, insert: true),
        BlindBoxShot(image: "blind-box-kf-aura", start: 9.9, end: 10.85, caption: "RAINBOW AURA CONFIRMED",
                     move: .pushIn, shake: 6, rainbow: true, rumble: true),
        BlindBoxShot(image: "blind-box-kf-eye", start: 10.85, end: 11.0, caption: nil, move: .panRight, insert: true),
        BlindBoxShot(image: "blind-box-kf-aura", start: 11.0, end: 11.4, caption: nil, move: .pushIn, shake: 8,
                     lines: true, rainbow: true, rumble: true, insert: true),
        BlindBoxShot(image: "blind-box-kf-beam", start: 11.4, end: 12.8, caption: "THE HEAVENS ANSWER", move: .pullOut,
                     shake: 3),
        BlindBoxShot(image: "blind-box-kf-lid", start: 12.8, end: 15.0, caption: "AND INSIDE IS...", move: .slowPush,
                     petals: true),
    ]

    static let keyFrames = ["blind-box-kf-glow", "blind-box-kf-eye", "blind-box-kf-sky", "blind-box-kf-rival",
                            "blind-box-kf-transform", "blind-box-kf-hero", "blind-box-kf-aura", "blind-box-kf-beam",
                            "blind-box-kf-lid"]

    static let boxImages = ["blind-box-box-0", "blind-box-box-1", "blind-box-box-2", "blind-box-box-3", "blind-box-box-4"]

    static func shotIndex(at t: Double) -> Int {
        var found = 0
        for (i, shot) in shots.enumerated() where t >= shot.start { found = i }
        return found
    }

    /// The caption showing at this moment and when it appeared. Inserts keep the caption before them.
    static func caption(at t: Double) -> (text: String, since: Double)? {
        var found: (text: String, since: Double)?
        for shot in shots where t >= shot.start {
            if let c = shot.caption { found = (c, shot.start) }
        }
        return found
    }
}

// MARK: - Layout

enum BlindBoxLayout {
    static let shelfLines: [CGFloat] = [0.41, 0.61, 0.81]
    static let columns: [CGFloat] = [0.2, 0.5, 0.8]

    static func side(_ size: CGSize) -> CGFloat { min(size.width * 0.25, size.height * 0.12, 110) }

    /// The top of a shelf plank, where boxes stand.
    static func shelfTop(_ row: Int, _ size: CGSize) -> CGFloat { size.height * shelfLines[row] }

    static func boxRect(_ i: Int, _ size: CGSize) -> CGRect {
        let s = side(size)
        let cx = size.width * columns[i % 3]
        return CGRect(x: cx - s / 2, y: shelfTop(i / 3, size) - s + 2, width: s, height: s)
    }

    static func box(at p: CGPoint, _ size: CGSize) -> Int? {
        for i in 0..<BlindBoxRules.boxCount where boxRect(i, size).insetBy(dx: -14, dy: -14).contains(p) { return i }
        return nil
    }
}

// MARK: - Frame

struct BlindBoxFrame {
    enum Stage { case shelf, cut, beat, reveal }
    var stage: Stage = .shelf
    /// Seconds since the round opened. Drives idle motion.
    var clock = 0.0
    var picked = -1
    var pickTime = 0.0
    var cutTime = 0.0
    var beatTime = 0.0
    var revealTime = 0.0
    var item = 0
    /// Seconds since the player tried to skip too early, or -1.
    var noteTime = -1.0
}

// MARK: - The clip

enum BlindBoxClip {
    /// Pieces of the cut scene the clip keeps, as (start, end) in cut scene seconds.
    static let pieces: [(Double, Double)] = [(0.0, 1.7), (4.9, 6.5), (9.9, 11.4), (12.8, 15.0)]
    static let piecesLength = pieces.reduce(0) { $0 + $1.1 - $1.0 }

    static let shelfEnd = 0.16
    static let cutEnd = 0.66
    static let beatEnd = 0.71
    /// The clip runs about this long, in seconds, as phase goes 0 to 1.
    static let length = 14.0

    static func frame(at phase: Double) -> BlindBoxFrame {
        let p = phase - floor(phase)
        var f = BlindBoxFrame()
        f.clock = p * length
        f.picked = 4
        f.item = 0
        if p < shelfEnd {
            f.stage = .shelf
            f.pickTime = max(0, p / shelfEnd * (BlindBoxRules.teaseTime + 0.4) - 0.4)
            if f.pickTime <= 0 { f.picked = -1 }
        } else if p < cutEnd {
            f.stage = .cut
            var left = (p - shelfEnd) / (cutEnd - shelfEnd) * piecesLength
            f.cutTime = pieces[pieces.count - 1].1
            for piece in pieces {
                let span = piece.1 - piece.0
                if left < span { f.cutTime = piece.0 + left; break }
                left -= span
            }
        } else if p < beatEnd {
            f.stage = .beat
            f.beatTime = (p - cutEnd) / (beatEnd - cutEnd) * BlindBoxRules.beatTime
        } else {
            f.stage = .reveal
            f.revealTime = (p - beatEnd) * length
        }
        return f
    }
}

// MARK: - Painter

struct BlindBoxPainter {
    let size: CGSize
    let frame: BlindBoxFrame
    let showHUD: Bool

    private var w: CGFloat { size.width }
    private var h: CGFloat { size.height }
    private var whole: Path { Path(CGRect(origin: .zero, size: size)) }

    func draw(_ ctx: inout GraphicsContext) {
        switch frame.stage {
        case .shelf: drawShelf(&ctx)
        case .cut: drawCut(&ctx)
        case .beat: drawBeat(&ctx)
        case .reveal: drawReveal(&ctx)
        }
    }

    // MARK: Shelf

    private func drawShelf(_ ctx: inout GraphicsContext) {
        let t = frame.clock
        fill(&ctx, "blind-box-shop", zoom: 1.06 + 0.01 * sin(t * 0.4), dx: 0, dy: 0)
        ctx.fill(whole, with: .color(.black.opacity(0.32)))
        if frame.picked < 0 { warmKeyFrames(&ctx) }

        let picking = frame.picked >= 0
        let dim = picking ? min(1, frame.pickTime / 0.5) : 0

        for row in 0..<3 { drawPlank(&ctx, row) }

        for i in 0..<BlindBoxRules.boxCount where i != frame.picked {
            drawBox(&ctx, i, tilt: sin(t * 1.6 + Double(i) * 1.3) * 1.2, scale: 1, glow: 0)
            drawTag(&ctx, i)
        }
        if dim > 0 { ctx.fill(whole, with: .color(.black.opacity(0.55 * dim))) }
        if picking {
            let k = min(1, frame.pickTime / BlindBoxRules.teaseTime)
            let amp = 3 + 12 * k
            let tilt = sin(frame.pickTime * (26 + 20 * k)) * amp
            drawBox(&ctx, frame.picked, tilt: tilt, scale: 1 + 0.35 * easeOut(k), glow: k)
        }

        if showHUD {
            let top = GameLayout.topBand + 14
            outlined(&ctx, "BLIND BOX", font: .system(size: min(44, w * 0.11), weight: .black, design: .rounded).italic(),
                     fill: Color(red: 1, green: 0.86, blue: 0.95), edge: Color(red: 0.35, green: 0.05, blue: 0.3), width: 3,
                     at: CGPoint(x: w / 2, y: top + 18))
            outlined(&ctx, picking ? "A choice has been made." : "Nine boxes. One destiny.",
                     font: .system(size: 16, weight: .bold, design: .rounded), fill: .white, edge: .black.opacity(0.7), width: 1.5,
                     at: CGPoint(x: w / 2, y: top + 56))
            if !picking {
                let pulse = 0.55 + 0.45 * (0.5 + 0.5 * sin(t * 4))
                outlined(&ctx, "Tap a box", font: .system(size: 20, weight: .heavy, design: .rounded),
                         fill: .white.opacity(pulse), edge: .black.opacity(0.6 * pulse), width: 2,
                         at: CGPoint(x: w / 2, y: h - GameLayout.bottomInset - 26))
            }
        }

        let flash = picking ? max(0, (frame.pickTime - (BlindBoxRules.teaseTime - 0.3)) / 0.3) : 0
        if flash > 0 { ctx.fill(whole, with: .color(.white.opacity(min(1, flash)))) }
    }

    /// Draws every key frame once, almost invisible, so none of them decodes in the middle of the cut scene.
    private func warmKeyFrames(_ ctx: inout GraphicsContext) {
        var c = ctx
        c.opacity = 0.01
        for name in BlindBoxRules.keyFrames {
            c.draw(c.resolve(Image(name)), in: CGRect(x: 0, y: 0, width: 2, height: 2))
        }
    }

    private func drawPlank(_ ctx: inout GraphicsContext, _ row: Int) {
        let y = BlindBoxLayout.shelfTop(row, size)
        let plank = CGRect(x: 10, y: y, width: w - 20, height: 14)
        ctx.fill(Path(CGRect(x: 14, y: y + 14, width: w - 28, height: 16)), with: .color(.black.opacity(0.35)))
        ctx.fill(Path(roundedRect: plank, cornerRadius: 3),
                 with: .linearGradient(BlindBoxFX.wood, startPoint: CGPoint(x: 0, y: y), endPoint: CGPoint(x: 0, y: y + 14)))
        ctx.fill(Path(CGRect(x: 12, y: y + 1, width: w - 24, height: 2)),
                 with: .color(Color(red: 0.9, green: 0.7, blue: 0.5).opacity(0.8)))
    }

    private func drawTag(_ ctx: inout GraphicsContext, _ i: Int) {
        let box = BlindBoxLayout.boxRect(i, size)
        let y = BlindBoxLayout.shelfTop(i / 3, size) + 18
        let rect = CGRect(x: box.midX - 32, y: y, width: 64, height: 22)
        ctx.fill(Path(CGRect(x: box.midX - 0.75, y: y - 6, width: 1.5, height: 6)), with: .color(.white.opacity(0.7)))
        ctx.fill(Path(roundedRect: rect, cornerRadius: 5), with: .color(Color(red: 1, green: 0.97, blue: 0.9)))
        ctx.stroke(Path(roundedRect: rect.insetBy(dx: 2, dy: 2), cornerRadius: 4),
                   with: .color(Color(red: 0.85, green: 0.3, blue: 0.55)), lineWidth: 1)
        ctx.draw(Text(BlindBoxRules.tags[i]).font(.system(size: 11, weight: .black, design: .rounded))
                    .foregroundColor(Color(red: 0.55, green: 0.1, blue: 0.35)),
                 at: CGPoint(x: rect.midX, y: rect.midY))
    }

    private func drawBox(_ ctx: inout GraphicsContext, _ i: Int, tilt: Double, scale: CGFloat, glow: Double) {
        let rect = BlindBoxLayout.boxRect(i, size)
        var c = ctx
        if glow > 0 {
            let r = rect.width * (0.9 + 0.8 * glow)
            let center = CGPoint(x: rect.midX, y: rect.maxY - rect.height * 0.5 * scale)
            c.fill(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)),
                   with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.9, blue: 0.5).opacity(0.85 * glow), .clear]),
                                         center: center, startRadius: 0, endRadius: r))
            drawRays(&c, center: center, radius: r * 1.6, turn: frame.pickTime * 0.8, alpha: 0.35 * glow)
        }
        c.translateBy(x: rect.midX, y: rect.maxY)
        c.rotate(by: .degrees(tilt))
        c.scaleBy(x: scale, y: scale)
        let img = c.resolve(Image(BlindBoxRules.boxImages[BlindBoxRules.colours[i]]))
        c.draw(img, in: CGRect(x: -rect.width / 2, y: -rect.height, width: rect.width, height: rect.height))
    }

    // MARK: Cut scene

    private func drawCut(_ ctx: inout GraphicsContext) {
        let t = frame.cutTime
        let index = BlindBoxRules.shotIndex(at: t)
        let shot = BlindBoxRules.shots[index]
        let p = min(1, max(0, (t - shot.start) / (shot.end - shot.start)))

        ctx.fill(whole, with: .color(.black))
        var c = ctx
        if shot.shake > 0 {
            let a = shot.shake * (0.6 + 0.4 * sin(t * 9))
            c.translateBy(x: sin(t * 63) * a, y: cos(t * 71) * a)
        }
        switch shot.move {
        case .pushIn: fill(&c, shot.image, zoom: 1.08 + 0.14 * p, dx: 0, dy: 0)
        case .pullOut: fill(&c, shot.image, zoom: 1.3 - 0.2 * easeOut(p), dx: 0, dy: 0)
        case .panRight: fill(&c, shot.image, zoom: 1.3, dx: -0.09 + 0.18 * p, dy: 0)
        case .panUp: fill(&c, shot.image, zoom: 1.22, dx: 0, dy: 0.08 - 0.14 * p)
        case .punch:
            let k = easeOut(min(1, p * 5))
            fill(&c, shot.image, zoom: 1.02 + 0.28 * k + 0.04 * p, dx: 0, dy: -0.04 * k)
        case .spin:
            c.translateBy(x: w / 2, y: h / 2)
            c.rotate(by: .degrees(-8 * (1 - easeOut(p))))
            c.translateBy(x: -w / 2, y: -h / 2)
            fill(&c, shot.image, zoom: 1.3 - 0.12 * p, dx: 0, dy: 0)
        case .slowPush: fill(&c, shot.image, zoom: 1.04 + 0.3 * p * p, dx: 0, dy: 0.03 * p)
        }

        if shot.rainbow { drawRainbow(&ctx, t: t) }
        if shot.lines { drawSpeedLines(&ctx, t: t, white: index % 2 == 0) }
        if shot.petals { drawPetals(&ctx, t: t) }
        drawSparkles(&ctx, t: t, amount: shot.move == .slowPush ? 1 : 0.6)
        if shot.rumble && showHUD { drawRumble(&ctx, t: t) }
        if shot.power && showHUD { drawPower(&ctx, t: t) }

        let bar = h * 0.1 * easeOut(min(1, t / 0.35))
        ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: bar)), with: .color(.black))
        ctx.fill(Path(CGRect(x: 0, y: h - bar, width: w, height: bar)), with: .color(.black))

        if showHUD, let cap = BlindBoxRules.caption(at: t) {
            let k = min(1, (t - cap.since) / 0.15)
            outlined(&ctx, cap.text, font: .system(size: min(25, w * 0.062), weight: .black).italic(),
                     fill: Color(red: 1, green: 0.95, blue: 0.75).opacity(k), edge: .black.opacity(k), width: 2.5,
                     at: CGPoint(x: w / 2 + 12 * (1 - k), y: h - GameLayout.bottomInset - 26))
        }
        if showHUD, t >= BlindBoxRules.skipAfter, t < BlindBoxRules.skipTo {
            ctx.draw(Text("Tap to skip").font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.55)),
                     at: CGPoint(x: w - 20, y: h - bar - 16), anchor: .trailing)
        }
        if showHUD, frame.noteTime >= 0 {
            let a = min(1, frame.noteTime / 0.12) * min(1, (BlindBoxRules.noteTime - frame.noteTime) / 0.3)
            let y = h * 0.5
            ctx.fill(Path(CGRect(x: 0, y: y - 28, width: w, height: 56)), with: .color(.black.opacity(0.6 * a)))
            ctx.draw(Text("You cannot skip destiny.").font(.system(size: 20, weight: .heavy, design: .rounded))
                        .foregroundColor(.white.opacity(a)), at: CGPoint(x: w / 2, y: y))
        }

        let flash = shot.insert ? 0.35 * max(0, 1 - (t - shot.start) / 0.08) : max(0, 1 - (t - shot.start) / 0.16)
        if flash > 0 { ctx.fill(whole, with: .color(.white.opacity(flash * 0.9))) }
        if t > BlindBoxRules.whiteFrom {
            let k = min(1, (t - BlindBoxRules.whiteFrom) / (BlindBoxRules.cutLength - BlindBoxRules.whiteFrom))
            ctx.fill(whole, with: .color(.white.opacity(k * k)))
        }
    }

    private func drawSpeedLines(_ ctx: inout GraphicsContext, t: Double, white: Bool) {
        let center = CGPoint(x: w / 2, y: h * 0.45)
        let far = hypot(w, h)
        let all = BlindBoxFX.lines
        let shift = Int(t * 24) % all.count
        var path = Path()
        for n in 0..<all.count {
            let angle = all[n].angle
            let inner = far * (0.22 + 0.2 * all[(n + shift) % all.count].reach)
            let spread = all[n].width
            path.move(to: CGPoint(x: center.x + cos(angle) * inner, y: center.y + sin(angle) * inner))
            path.addLine(to: CGPoint(x: center.x + cos(angle - spread) * far, y: center.y + sin(angle - spread) * far))
            path.addLine(to: CGPoint(x: center.x + cos(angle + spread) * far, y: center.y + sin(angle + spread) * far))
            path.closeSubpath()
        }
        ctx.fill(path, with: .color(white ? .white.opacity(0.75) : .black.opacity(0.6)))
    }

    private func drawPetals(_ ctx: inout GraphicsContext, t: Double) {
        for petal in BlindBoxFX.petals {
            let y = (petal.y + t * petal.speed).truncatingRemainder(dividingBy: 1.2) - 0.1
            let x = petal.x + 0.05 * sin(t * 1.3 + petal.wobble)
            var c = ctx
            c.translateBy(x: x * w, y: y * h)
            c.rotate(by: .radians(t * petal.spin + petal.wobble))
            let s = petal.size
            c.fill(Path(ellipseIn: CGRect(x: -s, y: -s * 0.55, width: s * 2, height: s * 1.1)),
                   with: .color(Color(red: 1, green: 0.72, blue: 0.84).opacity(0.9)))
            c.fill(Path(ellipseIn: CGRect(x: -s * 0.4, y: -s * 0.22, width: s * 0.8, height: s * 0.44)),
                   with: .color(Color(red: 1, green: 0.9, blue: 0.95).opacity(0.9)))
        }
    }

    private func drawSparkles(_ ctx: inout GraphicsContext, t: Double, amount: Double) {
        for sparkle in BlindBoxFX.sparkles {
            let life = (t * sparkle.rate + sparkle.offset).truncatingRemainder(dividingBy: 1)
            let a = sin(life * .pi) * amount
            if a < 0.05 { continue }
            star(&ctx, at: CGPoint(x: sparkle.x * w, y: sparkle.y * h), radius: sparkle.size * (0.5 + 0.5 * a), color: .white.opacity(a))
        }
    }

    private func drawRainbow(_ ctx: inout GraphicsContext, t: Double) {
        var c = ctx
        c.blendMode = .screen
        c.opacity = 0.32 + 0.1 * sin(t * 12)
        let turn = t * 1.5
        c.fill(whole, with: .linearGradient(BlindBoxFX.rainbow,
                                            startPoint: CGPoint(x: w * (0.5 + 0.7 * cos(turn)), y: h * (0.5 + 0.7 * sin(turn))),
                                            endPoint: CGPoint(x: w * (0.5 - 0.7 * cos(turn)), y: h * (0.5 - 0.7 * sin(turn)))))
    }

    /// The menacing sound effect, drawn big down the sides.
    private func drawRumble(_ ctx: inout GraphicsContext, t: Double) {
        let font = Font.system(size: min(54, w * 0.13), weight: .black).italic()
        let fill = Color(red: 0.62, green: 0.3, blue: 0.95)
        for n in 0..<3 {
            let wob = sin(t * 18 + Double(n) * 2) * 3
            outlined(&ctx, "ゴ", font: font, fill: fill, edge: .white, width: 2.5,
                     at: CGPoint(x: w * 0.12 + wob, y: h * (0.2 + 0.1 * Double(n))))
            outlined(&ctx, "ゴ", font: font, fill: fill, edge: .white, width: 2.5,
                     at: CGPoint(x: w * 0.88 - wob, y: h * (0.55 + 0.1 * Double(n))))
        }
    }

    private func drawPower(_ ctx: inout GraphicsContext, t: Double) {
        let k = min(1, max(0, (t - 8.2) / 1.6))
        let value = Int(pow(10, 2.7 + 4.3 * k))
        let y = h * 0.1 + 34
        outlined(&ctx, "POWER LEVEL", font: .system(size: 16, weight: .heavy, design: .monospaced),
                 fill: Color(red: 0.6, green: 1, blue: 0.7), edge: .black, width: 2, at: CGPoint(x: w / 2, y: y))
        outlined(&ctx, k >= 1 ? BlindBoxPainter.grouped(value) + "+" : BlindBoxPainter.grouped(value),
                 font: .system(size: min(46, w * 0.115), weight: .black, design: .monospaced),
                 fill: Color(red: 1, green: 0.92, blue: 0.3), edge: .black, width: 3, at: CGPoint(x: w / 2, y: y + 38))
    }

    // MARK: Beat and reveal

    private static let flat = Color(red: 0.86, green: 0.86, blue: 0.84)
    private static let ink = Color(red: 0.16, green: 0.16, blue: 0.17)

    private func drawBeat(_ ctx: inout GraphicsContext) {
        ctx.fill(whole, with: .color(BlindBoxPainter.flat))
        let white = max(0, 1 - frame.beatTime / 0.35)
        if white > 0 { ctx.fill(whole, with: .color(.white.opacity(white))) }
    }

    private func drawReveal(_ ctx: inout GraphicsContext) {
        let item = BlindBoxRules.items[frame.item]
        let t = frame.revealTime
        let ink = BlindBoxPainter.ink
        ctx.fill(whole, with: .color(BlindBoxPainter.flat))

        let img = ctx.resolve(Image(item.image))
        let box = CGRect(x: w * 0.17, y: h * 0.28, width: w * 0.66, height: h * 0.33)
        let s = img.size
        if s.width > 0, s.height > 0 {
            let k = min(box.width / s.width, box.height / s.height)
            let rect = CGRect(x: box.midX - s.width * k / 2, y: box.midY - s.height * k / 2, width: s.width * k, height: s.height * k)
            ctx.fill(Path(ellipseIn: CGRect(x: rect.midX - rect.width * 0.4, y: rect.maxY - 6, width: rect.width * 0.8, height: 14)),
                     with: .color(.black.opacity(0.1)))
            ctx.draw(img, in: rect)
            if let label = item.label {
                let area = CGRect(x: rect.minX + item.labelRect.minX * rect.width, y: rect.minY + item.labelRect.minY * rect.height,
                                  width: item.labelRect.width * rect.width, height: item.labelRect.height * rect.height)
                let type = min(area.height * 0.55, area.width / CGFloat(label.count) * 1.12)
                var c = ctx
                c.translateBy(x: area.midX, y: area.midY)
                c.rotate(by: .degrees(-3))
                c.draw(Text(label).font(.system(size: type, weight: .black, design: .rounded))
                        .foregroundColor(item.labelColor.opacity(0.88)), at: .zero)
            }
        }

        let top = h * 0.17
        if t >= 1.1 {
            let n = item.stars
            for i in 0..<n {
                let x = w / 2 + (CGFloat(i) - CGFloat(n - 1) / 2) * 22
                star5(&ctx, at: CGPoint(x: x, y: top), radius: 9, color: Color(red: 0.86, green: 0.62, blue: 0.1))
            }
            ctx.draw(Text(item.rarity).font(.system(size: 17, weight: .heavy, design: .rounded)).tracking(2)
                        .foregroundColor(Color(red: 0.72, green: 0.5, blue: 0.05)),
                     at: CGPoint(x: w / 2, y: top + 28))
        }
        if t >= 0.5 {
            ctx.draw(Text(item.name).font(.system(size: min(32, w * 0.08), weight: .heavy, design: .rounded)).foregroundColor(ink),
                     at: CGPoint(x: w / 2, y: h * 0.67))
        }
        if t >= 1.7 {
            ctx.draw(Text(item.flavour).font(.system(size: 17, weight: .medium, design: .rounded)).foregroundColor(ink.opacity(0.7)),
                     at: CGPoint(x: w / 2, y: h * 0.67 + 38))
        }
        if t >= 2.4 {
            let words = item.points == 1 ? "+1 point" : "+" + String(item.points) + " points"
            let pill = CGRect(x: w / 2 - 70, y: h * 0.67 + 70, width: 140, height: 36)
            ctx.fill(Path(roundedRect: pill, cornerRadius: 18), with: .color(.white.opacity(0.7)))
            ctx.draw(Text(words).font(.system(size: 17, weight: .bold, design: .rounded)).foregroundColor(ink),
                     at: CGPoint(x: pill.midX, y: pill.midY))
        }
    }

    // MARK: Helpers

    /// Draws a catalog image so it covers the whole view, zoomed and moved by a share of the view.
    private func fill(_ ctx: inout GraphicsContext, _ name: String, zoom: CGFloat, dx: CGFloat, dy: CGFloat) {
        let img = ctx.resolve(Image(name))
        let s = img.size
        guard s.width > 0, s.height > 0 else { return }
        let k = max(w / s.width, h / s.height) * zoom
        let iw = s.width * k, ih = s.height * k
        ctx.draw(img, in: CGRect(x: (w - iw) / 2 + dx * w, y: (h - ih) / 2 + dy * h, width: iw, height: ih))
    }

    private func outlined(_ ctx: inout GraphicsContext, _ s: String, font: Font, fill: Color, edge: Color, width: CGFloat,
                          at p: CGPoint) {
        let back = ctx.resolve(Text(s).font(font).foregroundColor(edge))
        let face = ctx.resolve(Text(s).font(font).foregroundColor(fill))
        for (dx, dy) in BlindBoxFX.ring {
            ctx.draw(back, at: CGPoint(x: p.x + dx * width, y: p.y + dy * width))
        }
        ctx.draw(face, at: p)
    }

    private func drawRays(_ ctx: inout GraphicsContext, center: CGPoint, radius: CGFloat, turn: Double, alpha: Double) {
        var path = Path()
        for n in 0..<12 {
            let a = turn + Double(n) / 12 * 2 * .pi
            path.move(to: center)
            path.addLine(to: CGPoint(x: center.x + cos(a - 0.09) * radius, y: center.y + sin(a - 0.09) * radius))
            path.addLine(to: CGPoint(x: center.x + cos(a + 0.09) * radius, y: center.y + sin(a + 0.09) * radius))
            path.closeSubpath()
        }
        ctx.fill(path, with: .color(Color(red: 1, green: 0.95, blue: 0.7).opacity(alpha)))
    }

    private func star(_ ctx: inout GraphicsContext, at p: CGPoint, radius r: CGFloat, color: Color) {
        let k = r * 0.18
        var path = Path()
        path.move(to: CGPoint(x: p.x, y: p.y - r))
        path.addLine(to: CGPoint(x: p.x + k, y: p.y - k))
        path.addLine(to: CGPoint(x: p.x + r, y: p.y))
        path.addLine(to: CGPoint(x: p.x + k, y: p.y + k))
        path.addLine(to: CGPoint(x: p.x, y: p.y + r))
        path.addLine(to: CGPoint(x: p.x - k, y: p.y + k))
        path.addLine(to: CGPoint(x: p.x - r, y: p.y))
        path.addLine(to: CGPoint(x: p.x - k, y: p.y - k))
        path.closeSubpath()
        ctx.fill(path, with: .color(color))
    }

    private func star5(_ ctx: inout GraphicsContext, at p: CGPoint, radius r: CGFloat, color: Color) {
        var path = Path()
        for n in 0..<10 {
            let a = -Double.pi / 2 + Double(n) * .pi / 5
            let rr = n % 2 == 0 ? r : r * 0.45
            let q = CGPoint(x: p.x + cos(a) * rr, y: p.y + sin(a) * rr)
            if n == 0 { path.move(to: q) } else { path.addLine(to: q) }
        }
        path.closeSubpath()
        ctx.fill(path, with: .color(color))
    }

    private func easeOut(_ x: Double) -> Double { 1 - pow(1 - x, 3) }

    static func grouped(_ n: Int) -> String {
        var digits = String(n)
        var i = digits.count - 3
        while i > 0 {
            digits.insert(",", at: digits.index(digits.startIndex, offsetBy: i))
            i -= 3
        }
        return digits
    }
}

// MARK: - Effects made once

enum BlindBoxFX {
    struct Line { let angle: Double; let width: Double; let reach: Double }
    struct Petal { let x: Double; let y: Double; let speed: Double; let size: CGFloat; let spin: Double; let wobble: Double }
    struct Sparkle { let x: CGFloat; let y: CGFloat; let size: CGFloat; let rate: Double; let offset: Double }

    static let ring: [(CGFloat, CGFloat)] = (0..<8).map { n in
        let a = Double(n) / 8 * 2 * .pi
        return (CGFloat(cos(a)), CGFloat(sin(a)))
    }

    static let wood = Gradient(colors: [Color(red: 0.72, green: 0.47, blue: 0.3), Color(red: 0.45, green: 0.25, blue: 0.15)])

    static let rainbow = Gradient(colors: [
        Color(red: 1, green: 0.3, blue: 0.4), Color(red: 1, green: 0.7, blue: 0.2), Color(red: 1, green: 1, blue: 0.4),
        Color(red: 0.3, green: 1, blue: 0.5), Color(red: 0.3, green: 0.7, blue: 1), Color(red: 0.7, green: 0.4, blue: 1),
        Color(red: 1, green: 0.3, blue: 0.4),
    ])

    private static func noise(_ n: Int, _ k: Int) -> Double {
        var x = UInt64(truncatingIfNeeded: n &* 7919 &+ k &* 104_729 &+ 1)
        x = (x ^ (x >> 30)) &* 0xBF58476D1CE4E5B9
        x = (x ^ (x >> 27)) &* 0x94D049BB133111EB
        x ^= x >> 31
        return Double(x % 10_000) / 10_000
    }

    static let lines: [Line] = (0..<72).map { n in
        Line(angle: Double(n) / 72 * 2 * .pi + noise(n, 1) * 0.06, width: 0.004 + 0.012 * noise(n, 2), reach: noise(n, 3))
    }

    static let petals: [Petal] = (0..<26).map { n in
        Petal(x: noise(n, 4), y: noise(n, 5) * 1.2, speed: 0.12 + 0.12 * noise(n, 6), size: CGFloat(5 + 6 * noise(n, 7)),
              spin: 1 + 3 * noise(n, 8), wobble: noise(n, 9) * 6)
    }

    static let sparkles: [Sparkle] = (0..<22).map { n in
        Sparkle(x: CGFloat(noise(n, 10)), y: CGFloat(0.12 + 0.76 * noise(n, 11)), size: CGFloat(6 + 12 * noise(n, 12)),
                rate: 0.8 + 1.2 * noise(n, 13), offset: noise(n, 14))
    }
}
