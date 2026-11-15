import SwiftUI

// Can Cannon: knock every can off the shelf with a cannon ball.
//
// CanCannonPainter paints a CanCannonModel into one Canvas: the beach, the shelves, the pieces, the
// ball and its aim line, the cannon, the score and the banners. The playable game hands it the live
// model. The clip in the video feed builds a model, lets the scripted pilot clear a five-row pyramid
// in three shots, and stops the clock at the phase. No assets, any frame size.

public struct CanCannonScene: View {
    public var phase: Double
    public var showHUD: Bool

    public init(phase: Double, showHUD: Bool) {
        self.phase = phase
        self.showHUD = showHUD
    }

    public var body: some View {
        Canvas(opaque: true, colorMode: .nonLinear, rendersAsynchronously: false) { context, size in
            if size.width <= 8 || size.height <= 8 { return }
            let model = CanCannonClip.model(at: phase)
            CanCannonPainter(model: model, size: size, showHUD: showHUD).draw(&context)
        }
    }
}

/// The clip: level 5 of a round, played by the careful pilot. Phase 0 is the full pyramid with
/// the hint up, 0.5 the second ball landing, 0.85 the pyramid gone and the banner up.
enum CanCannonClip {
    static let length = 7.0
    static let seed: UInt64 = 7
    /// Steps run before phase 0, so the pieces have dropped in.
    static let preroll = 72

    /// The last clip played, so a feed that plays it forward only runs the new steps each frame.
    private static var kept: CanCannonModel?
    private static var keptPilot = CanCannonPilot(seed: seed, careful: true)
    private static var keptSteps = 0

    static func model(at phase: Double) -> CanCannonModel {
        let dt = CanCannonModel.substep
        let target = Swift.max(0, Int((CanCannonMath.clamp(phase) * length / dt).rounded()))
        let model: CanCannonModel
        if let old = kept, keptSteps <= target {
            model = old
        } else {
            model = CanCannonModel(options: GameOptions(solo: true, seed: seed), startLevel: 4, startScore: 620)
            for _ in 0..<preroll { model.step(dt: dt) }
            kept = model
            keptPilot = CanCannonPilot(seed: seed, careful: true)
            keptSteps = 0
        }
        while keptSteps < target {
            model.step(dt: dt)
            switch keptPilot.next(model, dt: dt) {
            case .none:
                break
            case .aim(let x, let y):
                model.setAim(x: x, y: y)
            case .fire:
                model.fire()
            }
            keptSteps += 1
        }
        return model
    }
}

// MARK: - Numbers

enum CanCannonMath {
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

    /// A fixed number in 0 ..< 1 for a pair of integers. Scenery uses it so nothing is stored.
    static func hash(_ k: Int, _ salt: Int) -> Double {
        var v = UInt64(truncatingIfNeeded: k) &* 0x9E37_79B9_7F4A_7C15 &+ UInt64(truncatingIfNeeded: salt) &* 0xD1B5_4A32_D192_ED03
        v = (v ^ (v >> 30)) &* 0xBF58_476D_1CE4_E5B9
        v = (v ^ (v >> 27)) &* 0x94D0_49BB_1331_11EB
        v ^= v >> 31
        return Double(v >> 11) / 9_007_199_254_740_992.0
    }

    /// 1240 as "1,240".
    static func grouped(_ n: Int) -> String {
        let digits = String(abs(n))
        var out = ""
        let count = digits.count
        for (i, ch) in digits.enumerated() {
            if i > 0 && (count - i) % 3 == 0 { out.append(",") }
            out.append(ch)
        }
        return n < 0 ? "-" + out : out
    }
}

/// SplitMix64. The rules and the effects use different salts so they never share a sequence.
struct CanCannonRandom {
    static let scenery: UInt64 = 0xD1B5_4A32_D192_ED03
    static let round: UInt64 = 0x2545_F491_4F6C_DD1D

    private var state: UInt64

    init(seed: UInt64, salt: UInt64 = CanCannonRandom.scenery) {
        state = seed &* 0x9E37_79B9_7F4A_7C15 &+ salt
    }

    /// 0 ..< 1
    mutating func next() -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var v = state
        v = (v ^ (v >> 30)) &* 0xBF58_476D_1CE4_E5B9
        v = (v ^ (v >> 27)) &* 0x94D0_49BB_1331_11EB
        v ^= v >> 31
        return Double(v >> 11) / 9_007_199_254_740_992.0
    }

    mutating func range(_ lo: Double, _ hi: Double) -> Double { lo + (hi - lo) * next() }

    mutating func int(_ bounds: ClosedRange<Int>) -> Int {
        bounds.lowerBound + Swift.min(bounds.count - 1, Int(next() * Double(bounds.count)))
    }
}

// MARK: - Colour

struct CanCannonTint {
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

    static let white = CanCannonTint(1, 1, 1)
    static let ink = CanCannonTint(hex: 0x151412)

    func mix(_ other: CanCannonTint, _ k: Double) -> CanCannonTint {
        CanCannonTint(r + (other.r - r) * k, g + (other.g - g) * k, b + (other.b - b) * k)
    }

    func scaled(_ k: Double) -> CanCannonTint {
        CanCannonTint(Swift.min(1, r * k), Swift.min(1, g * k), Swift.min(1, b * k))
    }

    func color(_ alpha: Double = 1) -> Color { Color(.sRGB, red: r, green: g, blue: b, opacity: alpha) }
}

enum CanCannonPalette {
    /// Can labels: blue, coral, teal, violet, orange, pink.
    static let cans: [CanCannonTint] = [0x3D6BE0, 0xFF6B57, 0x19B8A6, 0x7C5CFF, 0xFF9F43, 0xFF5FA2]
        .map { CanCannonTint(hex: $0) }
    static let wood = CanCannonTint(hex: 0xEE9B36)
    static let stone = CanCannonTint(hex: 0x5A6BB6)
    static let sand = CanCannonTint(hex: 0xF2D49B)
    static let card = CanCannonTint(hex: 0xF8F6F1)
    static let ballDark = CanCannonTint(hex: 0x262A3A)
    static let star = CanCannonTint(hex: 0xFF9F43)

    static func can(_ i: Int) -> CanCannonTint { cans[index(i)] }

    static func index(_ i: Int) -> Int { ((i % cans.count) + cans.count) % cans.count }

    // Gradients are made once and shared by every piece in every frame.
    static let canBodies: [Gradient] = cans.map { (tint: CanCannonTint) -> Gradient in
        let deep = tint.scaled(0.62)
        return Gradient(colors: [deep.color(), tint.color(), tint.mix(.white, 0.42).color(), tint.color(), deep.scaled(0.9).color()])
    }
    static let paper = Gradient(colors: [CanCannonTint.white.scaled(0.72).color(), Color.white, Color.white,
                                         CanCannonTint.white.scaled(0.68).color()])
    static let metal = Gradient(colors: [CanCannonTint(hex: 0x7E8792).color(), CanCannonTint(hex: 0xE3E8EE).color(), Color.white,
                                         CanCannonTint(hex: 0xC2C9D2).color(), CanCannonTint(hex: 0x737C88).color()])
    static let lidInner = CanCannonTint(hex: 0xAEB6C0).color()
    static let crateOuter = Gradient(colors: [CanCannonTint(hex: 0xFFC56B).color(), CanCannonTint(hex: 0xEE9B36).color(),
                                              CanCannonTint(hex: 0xD27E25).color()])
    static let crateInner = Gradient(colors: [CanCannonTint(hex: 0xE89632).color(), CanCannonTint(hex: 0xC97520).color()])
    static let stoneBody = Gradient(colors: [CanCannonTint(hex: 0x8495DE).color(), CanCannonTint(hex: 0x5A6BB6).color(),
                                             CanCannonTint(hex: 0x45529A).color()])

    /// The colour of a chip or puff.
    static func shard(_ code: Int) -> CanCannonTint {
        switch code {
        case 10: return wood
        case 11: return stone
        case 20: return CanCannonTint(hex: 0xE9CB93)
        case 21: return CanCannonTint(hex: 0xFFF8EC)
        default: return can(code)
        }
    }
}

// MARK: - Stage

/// Where the world lands on the screen. The camera looks level over the beach; the shelf stands
/// CanCannonModel.shelfZ away and fills most of the width.
struct CanCannonStage {
    let W: Double
    let H: Double
    /// Points per design point (the design is 402 wide).
    let u: Double
    let horizonY: Double
    let plankY: Double
    /// Points per shelf unit on the shelf.
    let ppu: Double
    let focal: Double
    let camY: Double

    init(size: CGSize) {
        W = Swift.max(1, Double(size.width))
        H = Swift.max(1, Double(size.height))
        u = Swift.min(W / 402, H / 700)
        horizonY = H * 0.255
        plankY = H * 0.6
        let fitWidth = W / 10.6
        let room = plankY - (Double(GameLayout.topBand) + 60)
        ppu = Swift.max(8, Swift.min(fitWidth, room / 9.0))
        focal = ppu * CanCannonModel.shelfZ
        camY = (plankY - horizonY) / ppu
    }

    /// z is the distance from the camera.
    func point(_ x: Double, _ y: Double, _ z: Double) -> CGPoint {
        let d = Swift.max(z, 0.5)
        return CGPoint(x: W / 2 + x * focal / d, y: horizonY + (camY - y) * focal / d)
    }

    /// Points per shelf unit at a distance.
    func scale(_ z: Double) -> Double { focal / Swift.max(z, 0.5) }

    /// A point near the shelf, z measured from the middle of the shelf.
    func shelf(_ x: Double, _ y: Double, _ z: Double = 0) -> CGPoint {
        point(x, y, CanCannonModel.shelfZ + z)
    }
}

// MARK: - Painter

struct CanCannonPainter {
    typealias M = CanCannonMath
    typealias Tint = CanCannonTint
    typealias Model = CanCannonModel

    let model: CanCannonModel
    let showHUD: Bool
    let stage: CanCannonStage
    let W: Double
    let H: Double
    let u: Double

    init(model: CanCannonModel, size: CGSize, showHUD: Bool) {
        self.model = model
        self.showHUD = showHUD
        stage = CanCannonStage(size: size)
        W = stage.W
        H = stage.H
        u = stage.u
    }

    private func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x, y: y) }

    private func ellipse(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double) -> Path {
        Path(ellipseIn: CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2))
    }

    private func shape(_ points: [CGPoint]) -> Path {
        var p = Path()
        p.addLines(points)
        p.closeSubpath()
        return p
    }

    private func across(_ x0: Double, _ x1: Double, _ y: Double, _ colors: [Color]) -> GraphicsContext.Shading {
        .linearGradient(Gradient(colors: colors), startPoint: pt(x0, y), endPoint: pt(x1, y))
    }

    private func across(_ x0: Double, _ x1: Double, _ y: Double, _ gradient: Gradient) -> GraphicsContext.Shading {
        .linearGradient(gradient, startPoint: pt(x0, y), endPoint: pt(x1, y))
    }

    private func down(_ y0: Double, _ y1: Double, _ gradient: Gradient) -> GraphicsContext.Shading {
        .linearGradient(gradient, startPoint: pt(0, y0), endPoint: pt(0, y1))
    }

    private func down(_ y0: Double, _ y1: Double, _ colors: [Color]) -> GraphicsContext.Shading {
        .linearGradient(Gradient(colors: colors), startPoint: pt(0, y0), endPoint: pt(0, y1))
    }

    func draw(_ ctx: inout GraphicsContext) {
        var world = ctx
        if model.shake > 0 {
            let a = model.shake * 7 * u
            let t = model.ambient
            world.translateBy(x: sin(t * 83) * a, y: cos(t * 71) * a * 0.7)
        }
        drawBackdrop(&world)
        drawShadows(&world)
        drawPieces(&world, behind: true)
        let ballBehind = model.ball.active && model.ball.z > Model.shelfZ + Model.shelfDepth
        if ballBehind { drawBall(&world) }
        drawShelves(&world)
        drawPieces(&world, behind: false)
        drawShards(&world)
        if model.aiming && model.stage == .playing { drawAim(&world) }
        if !ballBehind { drawBall(&world) }
        drawCannon(&world)
        drawPopups(&world)

        drawConfetti(&ctx)
        if showHUD { drawHUD(&ctx) }
        drawBanner(&ctx)
        drawHint(&ctx)
    }

    // MARK: Beach

    private func drawBackdrop(_ ctx: inout GraphicsContext) {
        let pad = 16 * u
        let hy = stage.horizonY
        let seaLow = hy + 22 * u

        ctx.fill(Path(CGRect(x: -pad, y: -pad, width: W + pad * 2, height: hy + pad)),
                 with: down(0, hy, [Tint(hex: 0x58B4EC).color(), Tint(hex: 0x95D3F4).color(), Tint(hex: 0xDDF2FB).color()]))

        // Sun glow, top right, background only.
        let sun = pt(W * 0.8, hy * 0.42)
        ctx.fill(ellipse(Double(sun.x), Double(sun.y), 90 * u, 90 * u),
                 with: .radialGradient(Gradient(colors: [Color.white.opacity(0.85), Color.white.opacity(0)]),
                                       center: sun, startRadius: 8 * u, endRadius: 90 * u))

        // Clouds drift slowly.
        for k in 0..<3 {
            let speed = (3 + 2 * Double(k)) * u
            let span = W + 160 * u
            var x = M.hash(k, 11) * span + model.ambient * speed
            x = x.truncatingRemainder(dividingBy: span) - 80 * u
            let y = hy * (0.22 + 0.42 * M.hash(k, 12))
            let r = (18 + 10 * M.hash(k, 13)) * u
            var cloud = Path()
            cloud.addEllipse(in: CGRect(x: x - r * 1.6, y: y - r * 0.5, width: r * 3.2, height: r * 1.1))
            cloud.addEllipse(in: CGRect(x: x - r * 0.9, y: y - r * 1.05, width: r * 1.5, height: r * 1.4))
            cloud.addEllipse(in: CGRect(x: x - r * 0.1, y: y - r * 0.8, width: r * 1.3, height: r * 1.1))
            ctx.fill(cloud, with: .color(Color.white.opacity(0.88)))
        }

        // A green headland on the left of the sea.
        var land = Path()
        land.move(to: pt(-pad, hy + 2 * u))
        land.addQuadCurve(to: pt(W * 0.34, hy + 2 * u), control: pt(W * 0.1, hy - 30 * u))
        land.closeSubpath()
        ctx.fill(land, with: .color(Tint(hex: 0x5DB57A).color()))

        // Sea and foam.
        ctx.fill(Path(CGRect(x: -pad, y: hy, width: W + pad * 2, height: seaLow - hy + 2 * u)),
                 with: down(hy, seaLow, [Tint(hex: 0x1C97BC).color(), Tint(hex: 0x4FCAD6).color()]))
        for k in 0..<7 {
            let sx = M.hash(k, 21) * W
            let sy = hy + 4 * u + M.hash(k, 22) * (seaLow - hy - 8 * u)
            let glint = 0.35 + 0.35 * sin(model.ambient * 2 + Double(k) * 1.7)
            ctx.fill(Path(CGRect(x: sx, y: sy, width: 10 * u, height: 1.6 * u)), with: .color(Color.white.opacity(glint)))
        }

        // Sand.
        ctx.fill(Path(CGRect(x: -pad, y: seaLow, width: W + pad * 2, height: H - seaLow + pad)),
                 with: down(seaLow, H, [Tint(hex: 0xF9E6BC).color(), Tint(hex: 0xF2D49B).color(), Tint(hex: 0xE7BF82).color()]))
        var foam = Path()
        let wave = sin(model.ambient * 1.3) * 2 * u
        foam.move(to: pt(-pad, seaLow + wave))
        var fx = -pad
        while fx <= W + pad {
            fx += 24 * u
            foam.addQuadCurve(to: pt(fx, seaLow + wave), control: pt(fx - 12 * u, seaLow + wave + 5 * u))
        }
        ctx.stroke(foam, with: .color(Color.white.opacity(0.85)), lineWidth: 3 * u)

        // Ripples in the sand, wider nearer the camera.
        let ripple = Tint(hex: 0xD6AA66).color(0.45)
        for k in 0..<16 {
            let depth = M.hash(k, 31)
            let y = seaLow + 26 * u + depth * (H - seaLow - 40 * u)
            let x = M.hash(k, 32) * W
            let half = (14 + 26 * depth) * u
            var line = Path()
            line.move(to: pt(x - half, y))
            line.addQuadCurve(to: pt(x + half, y), control: pt(x, y - 5 * u * (0.5 + depth)))
            ctx.stroke(line, with: .color(ripple), style: StrokeStyle(lineWidth: (1 + depth) * u, lineCap: .round))
        }

        drawPalm(&ctx, x: W * 0.05, base: seaLow + 10 * u, height: 128 * u, lean: 1)
        drawPalm(&ctx, x: W * 0.95, base: seaLow + 6 * u, height: 112 * u, lean: -1)
        if hy - 40 * u >= Double(GameLayout.topBand) + 72 * u { drawBunting(&ctx, y: hy - 40 * u) }

        // A starfish and two shells, away from the cannon.
        drawStarfish(&ctx, x: W * 0.12, y: H * 0.79, r: 11 * u, turn: 0.3)
        drawStarfish(&ctx, x: W * 0.88, y: H * 0.71, r: 9 * u, turn: -0.4)
        drawShell(&ctx, x: W * 0.86, y: H * 0.87, r: 9 * u)
        drawShell(&ctx, x: W * 0.2, y: H * 0.66, r: 7 * u)
    }

    private func drawPalm(_ ctx: inout GraphicsContext, x: Double, base: Double, height: Double, lean: Double) {
        let top = pt(x + lean * height * 0.28, base - height)
        var trunk = Path()
        trunk.move(to: pt(x, base))
        trunk.addQuadCurve(to: top, control: pt(x + lean * height * 0.02, base - height * 0.6))
        ctx.stroke(trunk, with: .color(Tint(hex: 0x9C6B3F).color()), style: StrokeStyle(lineWidth: 7 * u, lineCap: .round))
        ctx.stroke(trunk, with: .color(Tint(hex: 0xB98552).color()), style: StrokeStyle(lineWidth: 2.5 * u, lineCap: .round, dash: [4 * u, 5 * u]))
        let sway = sin(model.ambient * 1.1 + x) * 0.05
        for k in 0..<6 {
            let a = -Double.pi / 2 + (Double(k) - 2.5) * 0.52 + sway
            var leaf = ctx
            leaf.translateBy(x: top.x, y: top.y)
            leaf.rotate(by: .radians(a + Double.pi / 2))
            let length = height * 0.42
            var frond = Path()
            frond.move(to: .zero)
            frond.addQuadCurve(to: pt(0, -length), control: pt(length * 0.32, -length * 0.5))
            frond.addQuadCurve(to: .zero, control: pt(-length * 0.12, -length * 0.55))
            leaf.fill(frond, with: .color(Tint(hex: k % 2 == 0 ? 0x2E9E5B : 0x3DBA6C).color()))
        }
    }

    private func drawBunting(_ ctx: inout GraphicsContext, y: Double) {
        let x0 = W * 0.16
        let x1 = W * 0.84
        let sag = 16 * u
        var rope = Path()
        rope.move(to: pt(x0, y))
        rope.addQuadCurve(to: pt(x1, y), control: pt((x0 + x1) / 2, y + sag * 2))
        ctx.stroke(rope, with: .color(Tint.ink.color(0.35)), lineWidth: 1.2 * u)
        let flags = 9
        for k in 0..<flags {
            let t = (Double(k) + 0.5) / Double(flags)
            let fx = x0 + (x1 - x0) * t
            let fy = y + sag * 2 * 2 * t * (1 - t)
            let wobble = sin(model.ambient * 2.4 + Double(k)) * 1.5 * u
            let colour = CanCannonPalette.can(k)
            ctx.fill(shape([pt(fx - 7 * u, fy), pt(fx + 7 * u, fy), pt(fx + wobble, fy + 15 * u)]), with: .color(colour.color()))
        }
    }

    private func drawStarfish(_ ctx: inout GraphicsContext, x: Double, y: Double, r: Double, turn: Double) {
        var star = Path()
        for k in 0..<10 {
            let a = turn + Double(k) * Double.pi / 5 - Double.pi / 2
            let rr = k % 2 == 0 ? r : r * 0.45
            let p = pt(x + cos(a) * rr, y + sin(a) * rr * 0.62)
            if k == 0 { star.move(to: p) } else { star.addLine(to: p) }
        }
        star.closeSubpath()
        ctx.fill(star, with: .color(Tint(hex: 0xF27A4F).color()))
        ctx.stroke(star, with: .color(Tint(hex: 0xC8552F).color(0.7)), lineWidth: 1 * u)
    }

    private func drawShell(_ ctx: inout GraphicsContext, x: Double, y: Double, r: Double) {
        var fan = Path()
        fan.move(to: pt(x, y + r * 0.4))
        fan.addArc(center: pt(x, y + r * 0.4), radius: r, startAngle: .degrees(200), endAngle: .degrees(340), clockwise: false)
        fan.closeSubpath()
        ctx.fill(fan, with: .color(Tint(hex: 0xFFF3E4).color()))
        ctx.stroke(fan, with: .color(Tint(hex: 0xD9B99A).color()), lineWidth: 1 * u)
    }

    // MARK: Shelves

    private func drawShadows(_ ctx: inout GraphicsContext) {
        for plank in model.planks {
            let front = stage.shelf(plank.x + 0.5, Model.groundY, -0.2)
            let back = stage.shelf(plank.x + 0.9, Model.groundY, 1.9)
            let half = (plank.half + 0.3) * stage.ppu
            let cx = Double(front.x + back.x) / 2
            let cy = Double(front.y + back.y) / 2
            let ry = Swift.max(4 * u, Double(front.y - back.y) / 2)
            ctx.fill(ellipse(cx, cy, half, ry), with: .color(Tint(hex: 0x8A5A22).color(0.16)))
        }
    }

    private func drawShelves(_ ctx: inout GraphicsContext) {
        let depth = Model.shelfDepth
        let thick = Model.plankThick
        let s = stage.scale(Model.shelfZ)
        for plank in model.planks {
            let x0 = plank.x - plank.half
            let x1 = plank.x + plank.half

            // The post: turned wood with a teal collar and a round foot.
            let top = stage.shelf(plank.x, -thick)
            let foot = stage.shelf(plank.x, Model.groundY)
            let topY = Double(top.y)
            let footY = Double(foot.y)
            let cx = Double(top.x)
            let wTop = 0.26 * s
            let wLow = 0.34 * s
            let post = shape([pt(cx - wTop, topY), pt(cx + wTop, topY), pt(cx + wLow, footY), pt(cx - wLow, footY)])
            ctx.fill(post, with: across(cx - wLow, cx + wLow, topY, [
                Tint(hex: 0x7A3F1B).color(), Tint(hex: 0xC77A3E).color(), Tint(hex: 0xEDA562).color(),
                Tint(hex: 0xB06633).color(), Tint(hex: 0x6E3818).color(),
            ]))
            let collarTop = footY - 0.75 * s
            let collarLow = footY - 0.42 * s
            let cw = wLow * 1.08
            ctx.fill(Path(roundedRect: CGRect(x: cx - cw, y: collarTop, width: cw * 2, height: collarLow - collarTop), cornerRadius: 2 * u),
                     with: across(cx - cw, cx + cw, collarTop, [Tint(hex: 0x0F8A7C).color(), Tint(hex: 0x3FD3C2).color(), Tint(hex: 0x0E7A6E).color()]))
            var zig = Path()
            let teeth = 5
            for k in 0...teeth {
                let zx = cx - cw + Double(k) * (cw * 2) / Double(teeth)
                let zy = k % 2 == 0 ? collarTop + 0.08 * s : collarLow - 0.08 * s
                if k == 0 { zig.move(to: pt(zx, zy)) } else { zig.addLine(to: pt(zx, zy)) }
            }
            ctx.stroke(zig, with: .color(CanCannonPalette.card.color(0.9)), lineWidth: 1.6 * u)
            ctx.fill(ellipse(cx, footY, 0.62 * s, 0.17 * s), with: .color(Tint(hex: 0x7A3F1B).color()))
            ctx.fill(ellipse(cx, footY - 0.06 * s, 0.55 * s, 0.13 * s), with: .color(Tint(hex: 0xB86E37).color()))

            // The board: its top, then its front edge.
            let fl = stage.shelf(x0, 0, -depth)
            let fr = stage.shelf(x1, 0, -depth)
            let bl = stage.shelf(x0, 0, depth)
            let br = stage.shelf(x1, 0, depth)
            let ll = stage.shelf(x0, -thick, -depth)
            let lr = stage.shelf(x1, -thick, -depth)
            ctx.fill(shape([fl, fr, br, bl]), with: down(Double(bl.y), Double(fl.y), [Tint(hex: 0xF7D3A0).color(), Tint(hex: 0xE9B072).color()]))
            ctx.fill(shape([fl, fr, lr, ll]), with: down(Double(fl.y), Double(ll.y), [Tint(hex: 0xD58E4C).color(), Tint(hex: 0xA5602C).color()]))
            var grain = Path()
            let gy = Double(fl.y) + Double(ll.y - fl.y) * 0.55
            grain.move(to: pt(Double(fl.x) + 10 * u, gy))
            grain.addLine(to: pt(Double(fr.x) - 26 * u, gy))
            ctx.stroke(grain, with: .color(Tint(hex: 0x8F5124).color(0.45)), lineWidth: 1 * u)
            var lip = Path()
            lip.move(to: fl)
            lip.addLine(to: fr)
            ctx.stroke(lip, with: .color(Tint(hex: 0xFFE7C2).color(0.85)), lineWidth: 1.6 * u)
            ctx.stroke(shape([fl, fr, lr, ll]), with: .color(Tint(hex: 0x6E3818).color(0.5)), lineWidth: 1 * u)
        }
    }

    // MARK: Pieces

    /// Pieces knocked off the back are drawn behind the shelves, the rest in front.
    private func drawPieces(_ ctx: inout GraphicsContext, behind: Bool) {
        for p in model.pieces {
            if p.pose == .gone { continue }
            let isBehind = p.z > Model.shelfDepth + 0.05
            if isBehind != behind { continue }
            drawPiece(&ctx, p)
        }
    }

    private func drawPiece(_ ctx: inout GraphicsContext, _ p: CanCannonPiece) {
        var alpha = 1.0
        if p.pose == .blasted { alpha = 1 - M.smooth(1.0, 1.4, p.age) }
        if p.pose == .grounded { alpha = 1 - M.smooth(1.9, 2.5, p.age) }
        var y = p.y
        if model.levelAge < 1.2 && p.pose == .resting {
            let k = M.clamp((model.levelAge - p.delay) / 0.3)
            let rest = 1 - k
            y += rest * rest * 7
            alpha *= M.smooth(0, 0.4, k)
        }
        if alpha <= 0.01 { return }
        var angle = p.angle
        if p.pose == .resting && p.tilt != 0 {
            let k = M.clamp(p.age / 0.12)
            angle += p.tilt * (1 - k) * (1 - k)
        }
        let z = Model.shelfZ + p.z
        let centre = stage.point(p.x, y, z)
        let s = stage.scale(z)

        var c = ctx
        c.opacity = alpha
        c.translateBy(x: centre.x, y: centre.y)
        c.scaleBy(x: s, y: s)
        if angle != 0 { c.rotate(by: .radians(-angle)) }
        switch p.kind {
        case .can: drawCan(&c, w: p.w, h: p.h, tint: p.tint)
        case .crate: drawCrate(&c, w: p.w, h: p.h)
        case .stone: drawStone(&c, w: p.w, h: p.h)
        }
        if model.aiming && model.stage == .playing && (p.pose == .resting || p.pose == .falling) && aimed(p) {
            let glow = 0.32 + 0.12 * sin(model.ambient * 10)
            c.fill(Path(roundedRect: CGRect(x: -p.w / 2, y: -p.h / 2, width: p.w, height: p.h), cornerRadius: 0.08),
                   with: .color(Color.white.opacity(glow)))
        }
    }

    /// Whether the ball would knock this piece off if it flew now.
    private func aimed(_ p: CanCannonPiece) -> Bool {
        if p.z > 0.9 { return false }
        let dx = Swift.max(0, abs(model.aimX - p.x) - p.halfW)
        let dy = Swift.max(0, abs(model.aimY - p.y) - p.halfH)
        return dx * dx + dy * dy <= Model.ballR * Model.ballR
    }

    /// A can, in shelf units around its middle, y down.
    private func drawCan(_ c: inout GraphicsContext, w: Double, h: Double, tint: Int) {
        let x0 = -w / 2
        let x1 = w / 2
        let top = -h / 2
        let rect = CGRect(x: x0, y: top, width: w, height: h)
        let body = Path(roundedRect: rect, cornerRadius: w * 0.1)
        c.fill(body, with: across(x0, x1, 0, CanCannonPalette.canBodies[CanCannonPalette.index(tint)]))

        // A white wave across the label.
        let waveTop = -h * 0.06
        let thick = h * 0.2
        var wave = Path()
        let samples = 8
        for k in 0...samples {
            let f = Double(k) / Double(samples)
            let wx = x0 + w * f
            let wy = waveTop + sin(f * 6.283 + 0.6) * h * 0.07
            if k == 0 { wave.move(to: pt(wx, wy)) } else { wave.addLine(to: pt(wx, wy)) }
        }
        for k in stride(from: samples, through: 0, by: -1) {
            let f = Double(k) / Double(samples)
            let wx = x0 + w * f
            let wy = waveTop + thick + sin(f * 6.283 + 1.4) * h * 0.06
            wave.addLine(to: pt(wx, wy))
        }
        wave.closeSubpath()
        c.fill(wave, with: across(x0, x1, 0, CanCannonPalette.paper))

        // Metal rims and the lid.
        let metal = CanCannonPalette.metal
        let rim = h * 0.075
        c.fill(Path(CGRect(x: x0, y: top, width: w, height: rim)), with: across(x0, x1, 0, metal))
        c.fill(Path(roundedRect: CGRect(x: x0, y: h / 2 - rim, width: w, height: rim), cornerRadius: w * 0.06),
               with: across(x0, x1, 0, metal))
        let lid = w * 0.2
        c.fill(Path(ellipseIn: CGRect(x: x0, y: top - lid / 2, width: w, height: lid)), with: across(x0, x1, 0, metal))
        c.fill(Path(ellipseIn: CGRect(x: x0 + w * 0.12, y: top - lid * 0.32, width: w * 0.76, height: lid * 0.64)),
               with: .color(CanCannonPalette.lidInner))
        c.stroke(body, with: .color(Tint.ink.color(0.32)), lineWidth: 0.03)
    }

    private func drawCrate(_ c: inout GraphicsContext, w: Double, h: Double) {
        let rect = CGRect(x: -w / 2, y: -h / 2, width: w, height: h)
        let outer = Path(roundedRect: rect, cornerRadius: 0.06)
        c.fill(outer, with: down(-h / 2, h / 2, CanCannonPalette.crateOuter))
        let b = Swift.min(w, h) * 0.14
        let inner = CGRect(x: -w / 2 + b, y: -h / 2 + b, width: w - 2 * b, height: h - 2 * b)
        c.fill(Path(roundedRect: inner, cornerRadius: 0.03),
               with: down(-h / 2, h / 2, CanCannonPalette.crateInner))
        let lines = Swift.max(1, Int((h - 2 * b) / 0.22))
        var planks = Path()
        for k in 1...lines {
            let ly = -h / 2 + b + (h - 2 * b) * Double(k) / Double(lines + 1)
            planks.move(to: pt(-w / 2 + b, ly))
            planks.addLine(to: pt(w / 2 - b, ly))
        }
        c.stroke(planks, with: .color(Tint(hex: 0xA65A16).color(0.75)), lineWidth: 0.025)
        let nail = 0.035
        for corner in [pt(-w / 2 + b * 0.5, -h / 2 + b * 0.5), pt(w / 2 - b * 0.5, -h / 2 + b * 0.5),
                       pt(-w / 2 + b * 0.5, h / 2 - b * 0.5), pt(w / 2 - b * 0.5, h / 2 - b * 0.5)] {
            c.fill(ellipse(Double(corner.x), Double(corner.y), nail, nail), with: .color(Tint(hex: 0x7C4312).color()))
        }
        c.stroke(outer, with: .color(Tint.ink.color(0.35)), lineWidth: 0.03)
    }

    private func drawStone(_ c: inout GraphicsContext, w: Double, h: Double) {
        let rect = CGRect(x: -w / 2, y: -h / 2, width: w, height: h)
        let outer = Path(roundedRect: rect, cornerRadius: 0.07)
        c.fill(outer, with: down(-h / 2, h / 2, CanCannonPalette.stoneBody))
        let b = 0.07
        c.stroke(Path(roundedRect: rect.insetBy(dx: b, dy: b), cornerRadius: 0.05), with: .color(Tint(hex: 0xA4B2EE).color(0.7)), lineWidth: 0.03)
        let r = Swift.min(w, h) * 0.18
        let gem = shape([pt(0, -r), pt(r * 1.2, 0), pt(0, r), pt(-r * 1.2, 0)])
        c.fill(gem, with: .color(Tint(hex: 0x6C7DCB).color()))
        c.stroke(gem, with: .color(Tint(hex: 0x35407A).color()), lineWidth: 0.04)
        c.stroke(outer, with: .color(Tint.ink.color(0.38)), lineWidth: 0.03)
    }

    // MARK: Ball, aim, cannon

    private func drawBall(_ ctx: inout GraphicsContext) {
        let b = model.ball
        if !b.active { return }
        var alpha = 1.0
        if b.mode != 0 { alpha = 1 - M.smooth(0.42, 0.6, b.age) }
        if alpha <= 0.01 { return }
        var c = ctx
        c.opacity = alpha
        let r = Swift.min(0.45 * stage.scale(b.z), 32 * u)
        if b.mode == 0 {
            // A short trail.
            for k in 1...3 {
                let back = Swift.max(0, b.t / b.length - 0.035 * Double(k))
                let q = Model.path(back, tx: b.tx, ty: b.ty)
                let p = stage.point(q.x, q.y, q.z)
                let tr = Swift.min(0.45 * stage.scale(q.z), 32 * u) * (1 - 0.18 * Double(k))
                c.fill(ellipse(Double(p.x), Double(p.y), tr, tr), with: .color(Color.white.opacity(0.22 - 0.06 * Double(k))))
            }
        }
        let p = stage.point(b.x, b.y, b.z)
        let x = Double(p.x)
        let y = Double(p.y)
        let lightAt = pt(x - r * 0.35, y - r * 0.4)
        c.fill(ellipse(x, y, r, r), with: .radialGradient(
            Gradient(colors: [Tint(hex: 0x6A7290).color(), CanCannonPalette.ballDark.color(), Tint(hex: 0x0D0E14).color()]),
            center: lightAt, startRadius: 0, endRadius: r * 1.5))
        c.fill(ellipse(x - r * 0.38, y - r * 0.42, r * 0.26, r * 0.18), with: .color(Color.white.opacity(0.75)))
        c.stroke(ellipse(x, y, r, r), with: .color(Tint.ink.color(0.6)), lineWidth: 1 * u)
    }

    private func drawAim(_ ctx: inout GraphicsContext) {
        let tx = model.aimX
        let ty = model.aimY
        let count = 18
        let drift = (model.ambient * 1.6).truncatingRemainder(dividingBy: 1)
        for k in 0..<count {
            let f = (Double(k) + drift) / Double(count)
            if f < 0.07 { continue }
            let q = Model.path(f, tx: tx, ty: ty)
            let p = stage.point(q.x, q.y, q.z)
            let r = 3.4 * u * (stage.scale(q.z) / stage.ppu).squareRoot()
            let fade = 0.55 + 0.45 * M.smooth(0.07, 0.25, f)
            ctx.fill(ellipse(Double(p.x), Double(p.y), r + 1.3 * u, r + 1.3 * u), with: .color(Tint.ink.color(0.28 * fade)))
            ctx.fill(ellipse(Double(p.x), Double(p.y), r, r), with: .color(Color.white.opacity(0.95 * fade)))
        }
        let target = stage.shelf(tx, ty)
        let x = Double(target.x)
        let y = Double(target.y)
        let ring = Model.ballR * stage.ppu
        let pulse = 1 + 0.06 * sin(model.ambient * 8)
        ctx.stroke(ellipse(x, y, ring * pulse, ring * pulse), with: .color(Tint.ink.color(0.35)), lineWidth: 4.5 * u)
        ctx.stroke(ellipse(x, y, ring * pulse, ring * pulse), with: .color(Color.white), lineWidth: 2.5 * u)
        var ticks = Path()
        for k in 0..<4 {
            let a = Double(k) * Double.pi / 2
            ticks.move(to: pt(x + cos(a) * ring * 0.55, y + sin(a) * ring * 0.55))
            ticks.addLine(to: pt(x + cos(a) * ring * 0.85, y + sin(a) * ring * 0.85))
        }
        ctx.stroke(ticks, with: .color(Color.white), style: StrokeStyle(lineWidth: 2.2 * u, lineCap: .round))
        ctx.fill(ellipse(x, y, 2.6 * u, 2.6 * u), with: .color(Color.white))
    }

    private func drawCannon(_ ctx: inout GraphicsContext) {
        let muzzle = stage.point(0, Model.muzzleY, Model.muzzleZ)
        let pivotX = W / 2
        // On a short screen the barrel gets shorter so the housing and wheels stay in view.
        let muzzleY = Double(muzzle.y)
        let pivotY = Swift.min(muzzleY + 118 * u, H - Double(GameLayout.bottomInset) - 30 * u)
        let length = Swift.max(64 * u, pivotY - muzzleY)

        // Which way the barrel points: at the aim, at the ball's target, or at the shelf.
        var goalX = 0.0
        var goalY = 2.0
        if model.aiming {
            goalX = model.aimX
            goalY = model.aimY
        } else if model.ball.active {
            goalX = model.ball.tx
            goalY = model.ball.ty
        }
        let ahead = Model.path(0.2, tx: goalX, ty: goalY)
        let toward = stage.point(ahead.x, ahead.y, ahead.z)
        let dx = Double(toward.x) - pivotX
        let dy = Double(toward.y) - pivotY
        let turn = M.clamp(atan2(dx, -dy), -0.5, 0.5)
        let since = model.sinceFire
        let recoil = since < 1 ? 16 * u * exp(-since * 8) * M.clamp(since / 0.03) : 0

        // The sandy pit.
        ctx.fill(ellipse(pivotX, pivotY + 30 * u, 150 * u, 62 * u),
                 with: down(pivotY - 30 * u, pivotY + 90 * u, [Tint(hex: 0xE4B979).color(), Tint(hex: 0xC99A5A).color()]))
        ctx.stroke(ellipse(pivotX, pivotY + 30 * u, 128 * u, 50 * u), with: .color(Tint(hex: 0xB07D42).color(0.7)), lineWidth: 3 * u)

        // Back wheels.
        for side in [-1.0, 1.0] {
            let wx = pivotX + side * 58 * u
            let wy = pivotY + 18 * u
            ctx.fill(ellipse(wx, wy, 27 * u, 27 * u), with: .color(Tint(hex: 0x2B2A33).color()))
            ctx.stroke(ellipse(wx, wy, 20 * u, 20 * u), with: .color(Tint(hex: 0x4A4957).color()), lineWidth: 3 * u)
            ctx.fill(ellipse(wx, wy, 8 * u, 8 * u), with: .color(CanCannonPalette.card.color()))
        }

        // The barrel, turned toward the aim.
        var barrel = ctx
        barrel.translateBy(x: pivotX, y: pivotY)
        barrel.rotate(by: .radians(turn))
        let tipY = -length + recoil
        let baseHalf = 36 * u
        let tipHalf = 27 * u
        let tube = shape([pt(-baseHalf, 14 * u), pt(baseHalf, 14 * u), pt(tipHalf, tipY), pt(-tipHalf, tipY)])
        barrel.fill(tube, with: across(-baseHalf, baseHalf, 0, [
            Tint(hex: 0x10506A).color(), Tint(hex: 0x2A8FB5).color(), Tint(hex: 0x74CDE9).color(),
            Tint(hex: 0x2A8FB5).color(), Tint(hex: 0x0E4458).color(),
        ]))
        let bandY = tipY + (14 * u - tipY) * 0.42
        let bandHalf = tipHalf + (baseHalf - tipHalf) * 0.42 + 2 * u
        barrel.fill(Path(roundedRect: CGRect(x: -bandHalf, y: bandY - 6 * u, width: bandHalf * 2, height: 12 * u), cornerRadius: 3 * u),
                    with: across(-bandHalf, bandHalf, 0, [Tint(hex: 0xCFC8BA).color(), CanCannonPalette.card.color(), Tint(hex: 0xBDB6A8).color()]))
        let ringHalf = tipHalf + 5 * u
        barrel.fill(Path(roundedRect: CGRect(x: -ringHalf, y: tipY - 4 * u, width: ringHalf * 2, height: 17 * u), cornerRadius: 5 * u),
                    with: across(-ringHalf, ringHalf, 0, [Tint(hex: 0xC8402F).color(), Tint(hex: 0xFF7B63).color(), Tint(hex: 0xC8402F).color()]))
        barrel.fill(ellipse(0, tipY - 4 * u, tipHalf * 0.92, 7.5 * u), with: .color(Tint.ink.color()))
        barrel.stroke(tube, with: .color(Tint.ink.color(0.4)), lineWidth: 1.2 * u)
        if since < 0.14 {
            let k = since / 0.14
            let r = (18 + 26 * k) * u
            barrel.fill(ellipse(0, tipY - 10 * u - 10 * u * k, r, r * 0.8), with: .radialGradient(
                Gradient(colors: [Color.white.opacity(1 - k), Tint(hex: 0xFFD27A).color(0.8 * (1 - k)), Color.white.opacity(0)]),
                center: pt(0, tipY - 10 * u - 10 * u * k), startRadius: 0, endRadius: r))
        }

        // The round housing over the base of the barrel.
        let dome = ellipse(pivotX, pivotY + 18 * u, 50 * u, 34 * u)
        ctx.fill(dome, with: down(pivotY - 16 * u, pivotY + 52 * u, [Tint(hex: 0xFF8A70).color(), Tint(hex: 0xE5533F).color(), Tint(hex: 0xB8392A).color()]))
        var stripe = Path()
        stripe.move(to: pt(pivotX - 44 * u, pivotY + 12 * u))
        stripe.addQuadCurve(to: pt(pivotX + 44 * u, pivotY + 12 * u), control: pt(pivotX, pivotY - 6 * u))
        ctx.stroke(stripe, with: .color(CanCannonPalette.card.color(0.9)), lineWidth: 4 * u)
        ctx.stroke(dome, with: .color(Tint.ink.color(0.35)), lineWidth: 1.2 * u)
    }

    // MARK: Effects

    private func drawShards(_ ctx: inout GraphicsContext) {
        for s in model.shards where s.life > 0 {
            let z = Model.shelfZ + s.z
            let p = stage.point(s.x, s.y, z)
            let sc = stage.scale(z)
            let k = M.clamp(s.life / Swift.max(0.01, s.span))
            let colour = CanCannonPalette.shard(s.colour)
            if s.colour >= 20 {
                let r = s.size * sc * (1.7 - 0.7 * k)
                ctx.fill(ellipse(Double(p.x), Double(p.y), r, r * 0.8), with: .color(colour.color(0.6 * k)))
            } else {
                let size = s.size * sc
                var c = ctx
                c.opacity = M.clamp(k * 2)
                c.translateBy(x: p.x, y: p.y)
                c.rotate(by: .radians(s.angle))
                c.fill(Path(CGRect(x: -size / 2, y: -size * 0.35, width: size, height: size * 0.7)), with: .color(colour.color()))
            }
        }
    }

    private func drawPopups(_ ctx: inout GraphicsContext) {
        for p in model.popups where p.life > 0 {
            let k = M.clamp(p.age / p.life)
            let at = stage.shelf(p.x, p.y, p.z)
            let rise = 44 * u * M.easeOut(k)
            let alpha = 1 - M.smooth(0.55, 1, k)
            let pop = 1 + 0.4 * exp(-p.age * 14)
            let text = Text(p.text).font(.system(size: 15 * u * pop, weight: .heavy, design: .rounded))
            let x = Double(at.x)
            let y = Double(at.y) - rise
            ctx.draw(text.foregroundColor(Tint.ink.color(0.45 * alpha)), at: pt(x, y + 1.8 * u), anchor: .center)
            ctx.draw(text.foregroundColor(Color.white.opacity(alpha)), at: pt(x, y), anchor: .center)
        }
    }

    private func drawConfetti(_ ctx: inout GraphicsContext) {
        for c in model.confetti where c.life > 0 {
            var layer = ctx
            layer.opacity = M.clamp(c.life * 2)
            layer.translateBy(x: c.x * W, y: c.y * H)
            layer.rotate(by: .radians(c.angle))
            layer.scaleBy(x: 1, y: Swift.max(0.2, abs(cos(c.angle * 0.7 + c.spin))))
            layer.fill(Path(CGRect(x: -4.5 * u, y: -2.5 * u, width: 9 * u, height: 5 * u)),
                       with: .color(CanCannonPalette.can(c.colour).color()))
        }
    }

    // MARK: Words

    private func drawHUD(_ ctx: inout GraphicsContext) {
        // The score sits between the app's corners, under the status bar.
        let since = model.sinceScore
        let pop = 1 + 0.2 * exp(-since * 9) * cos(since * 20)
        let scoreText = Text(M.grouped(Int(model.shownScore.rounded())))
            .font(.system(size: 34 * u * pop, weight: .black, design: .rounded))
        let scoreY = (Double(GameLayout.statusBarHeight) + Double(GameLayout.topBand)) / 2 + 2
        ctx.draw(scoreText.foregroundColor(Color.white.opacity(0.7)), at: pt(W / 2, scoreY + 2 * u), anchor: .center)
        ctx.draw(scoreText.foregroundColor(Tint.ink.color()), at: pt(W / 2, scoreY), anchor: .center)

        // Level and balls, on a card just under the app's band.
        let cardW = 186 * u
        let cardH = 34 * u
        let cardY = Double(GameLayout.topBand) + 4 * u
        let card = CGRect(x: W / 2 - cardW / 2, y: cardY, width: cardW, height: cardH)
        ctx.fill(Path(roundedRect: card.offsetBy(dx: 0, dy: 2 * u), cornerRadius: cardH / 2), with: .color(Tint.ink.color(0.14)))
        ctx.fill(Path(roundedRect: card, cornerRadius: cardH / 2), with: .color(CanCannonPalette.card.color()))
        let label = Text("Level \(model.level + 1)").font(.system(size: 15 * u, weight: .bold, design: .rounded))
        ctx.draw(label.foregroundColor(Tint.ink.color()), at: pt(Double(card.minX) + 16 * u, Double(card.midY)), anchor: .leading)
        let dotR = 6.5 * u
        let gap = 17 * u
        let total = Model.ballsPerLevel
        for k in 0..<total {
            let cx = Double(card.maxX) - 18 * u - Double(total - 1 - k) * gap
            let cy = Double(card.midY)
            if k < model.balls {
                ctx.fill(ellipse(cx, cy, dotR, dotR), with: .color(CanCannonPalette.ballDark.color()))
                ctx.fill(ellipse(cx - dotR * 0.32, cy - dotR * 0.36, dotR * 0.3, dotR * 0.22), with: .color(Color.white.opacity(0.7)))
            } else if k == model.balls && model.sinceFire < 0.25 && model.stage == .playing {
                let shrink = 1 - model.sinceFire / 0.25
                ctx.fill(ellipse(cx, cy, dotR * shrink, dotR * shrink), with: .color(CanCannonPalette.ballDark.color()))
                ctx.stroke(ellipse(cx, cy, dotR, dotR), with: .color(Tint.ink.color(0.25)), lineWidth: 1.4 * u)
            } else {
                ctx.stroke(ellipse(cx, cy, dotR, dotR), with: .color(Tint.ink.color(0.25)), lineWidth: 1.4 * u)
            }
        }

        // A friend passed, or the best so far.
        let lineY = cardY + cardH + 14 * u
        if let note = model.note {
            let age = model.noteAge
            let alpha = M.easeOut(M.clamp(age / 0.16)) * (1 - M.smooth(Model.noteLength - 0.35, Model.noteLength, age))
            let words = Text(note).font(.system(size: 14.5 * u, weight: .heavy, design: .rounded))
            ctx.draw(words.foregroundColor(Color.white.opacity(0.75 * alpha)), at: pt(W / 2, lineY + 1.5 * u), anchor: .center)
            ctx.draw(words.foregroundColor(Tint.ink.color(alpha)), at: pt(W / 2, lineY), anchor: .center)
        } else if model.bestScore > 0 {
            let best = Text("Best \(M.grouped(Swift.max(model.bestScore, model.score)))")
                .font(.system(size: 13 * u, weight: .bold, design: .rounded))
            ctx.draw(best.foregroundColor(Tint.ink.color(0.55)), at: pt(W / 2, lineY), anchor: .center)
        }
    }

    private func drawBanner(_ ctx: inout GraphicsContext) {
        let kind = model.banner
        if kind == .none { return }
        let age = model.bannerAge
        let pop: Double
        if age < 0.14 {
            pop = 0.55 + 0.6 * M.easeOut(age / 0.14)
        } else {
            pop = 1 + 0.12 * exp(-(age - 0.14) * 10) * cos((age - 0.14) * 24)
        }
        var alpha = M.clamp(age / 0.08)
        if kind == .smashed { alpha *= 1 - M.smooth(Model.bannerLength - 0.25, Model.bannerLength, age) }
        if alpha <= 0.01 { return }

        let title: String
        let size: Double
        let base: Tint
        switch kind {
        case .smashed:
            title = "SMASHED"
            size = 42
            base = Tint(hex: 0xFF6B57)
        case .outOfBalls:
            title = "Out of balls"
            size = 32
            base = Tint(hex: 0x2B2A33)
        case .allClear:
            title = "Every shelf cleared"
            size = 26
            base = Tint(hex: 0x19B8A6)
        case .none:
            return
        }

        var c = ctx
        c.opacity = alpha
        c.translateBy(x: W / 2, y: H * 0.3)
        c.scaleBy(x: pop, y: pop)
        let ribbonW = 292 * u
        let ribbonH = 70 * u
        let deep = base.scaled(0.72)
        for side in [-1.0, 1.0] {
            let inner = side * (ribbonW / 2 - 16 * u)
            let outer = side * (ribbonW / 2 + 26 * u)
            let tail = shape([pt(inner, -ribbonH * 0.28), pt(outer, -ribbonH * 0.28), pt(outer - side * 12 * u, ribbonH * 0.22),
                              pt(outer, ribbonH * 0.72), pt(inner, ribbonH * 0.72)])
            c.fill(tail, with: .color(deep.color()))
        }
        let band = CGRect(x: -ribbonW / 2, y: -ribbonH / 2, width: ribbonW, height: ribbonH)
        c.fill(Path(roundedRect: band.offsetBy(dx: 0, dy: 4 * u), cornerRadius: 16 * u), with: .color(Tint.ink.color(0.18)))
        c.fill(Path(roundedRect: band, cornerRadius: 16 * u),
               with: down(-ribbonH / 2, ribbonH / 2, [base.mix(.white, 0.25).color(), base.color(), deep.color()]))
        c.stroke(Path(roundedRect: band.insetBy(dx: 4 * u, dy: 4 * u), cornerRadius: 12 * u),
                 with: .color(Color.white.opacity(0.35)), style: StrokeStyle(lineWidth: 1.5 * u, dash: [5 * u, 4 * u]))
        let words = Text(title).font(.system(size: size * u, weight: .black, design: .rounded)).kerning(1.2 * u)
        c.draw(words.foregroundColor(Tint.ink.color(0.35)), at: pt(0, 3 * u), anchor: .center)
        c.draw(words.foregroundColor(Color.white), at: pt(0, 0), anchor: .center)

        switch kind {
        case .smashed:
            for k in 0..<3 {
                let start = 0.16 + 0.1 * Double(k)
                if age < start { continue }
                let local = age - start
                let grow = local < 0.12 ? 0.4 + 0.75 * M.easeOut(local / 0.12) : 1 + 0.1 * exp(-(local - 0.12) * 12)
                let sx = (Double(k) - 1) * 38 * u
                let sy = ribbonH / 2 + 30 * u - (k == 1 ? 6 * u : 0)
                let earned = k < model.levelStars
                let star = starPath(x: sx, y: sy, r: 16 * u * grow)
                c.fill(star, with: .color(earned ? CanCannonPalette.star.color() : Tint.ink.color(0.12)))
                c.stroke(star, with: .color(Tint.ink.color(earned ? 0.6 : 0.25)), style: StrokeStyle(lineWidth: 1.6 * u, lineJoin: .round))
            }
            if age > 0.3 {
                let k = M.easeOut(M.clamp((age - 0.3) / 0.15))
                let praise = Text(model.praise).font(.system(size: 24 * u * (0.8 + 0.2 * k), weight: .heavy, design: .rounded))
                let py = ribbonH / 2 + 74 * u
                c.draw(praise.foregroundColor(Color.white.opacity(0.75 * k)), at: pt(0, py + 2 * u), anchor: .center)
                c.draw(praise.foregroundColor(Tint.ink.color(k)), at: pt(0, py), anchor: .center)
                if model.ballPoints > 0 {
                    let left = model.ballPoints / Model.pointsPerBall
                    let line = left == 1 ? "1 ball left  +\(model.ballPoints)" : "\(left) balls left  +\(model.ballPoints)"
                    let extra = Text(line).font(.system(size: 15 * u, weight: .bold, design: .rounded))
                    c.draw(extra.foregroundColor(Tint.ink.color(0.7 * k)), at: pt(0, py + 28 * u), anchor: .center)
                }
            }
        case .outOfBalls:
            let line = Text("Reached level \(model.level + 1)").font(.system(size: 16 * u, weight: .bold, design: .rounded))
            c.draw(line.foregroundColor(Tint.ink.color(0.75)), at: pt(0, ribbonH / 2 + 24 * u), anchor: .center)
        case .allClear:
            let line = Text("\(model.stars) stars").font(.system(size: 16 * u, weight: .bold, design: .rounded))
            c.draw(line.foregroundColor(Tint.ink.color(0.75)), at: pt(0, ribbonH / 2 + 24 * u), anchor: .center)
        case .none:
            break
        }
    }

    private func starPath(x: Double, y: Double, r: Double) -> Path {
        var star = Path()
        for k in 0..<10 {
            let a = Double(k) * Double.pi / 5 - Double.pi / 2
            let rr = k % 2 == 0 ? r : r * 0.48
            let p = pt(x + cos(a) * rr, y + sin(a) * rr)
            if k == 0 { star.move(to: p) } else { star.addLine(to: p) }
        }
        star.closeSubpath()
        return star
    }

    /// The one instruction, until the first ball is fired.
    private func drawHint(_ ctx: inout GraphicsContext) {
        if model.stage != .playing || model.shotsTotal > 0 || model.aiming { return }
        let shown = M.smooth(0.3, 0.55, model.levelAge)
        if shown <= 0.01 { return }
        let pulse = 0.5 + 0.5 * sin(model.ambient * 3.4)
        let alpha = shown * (0.8 + 0.2 * pulse)
        let sand = Double(stage.shelf(0, Model.groundY).y)
        let muzzle = Double(stage.point(0, Model.muzzleY, Model.muzzleZ).y)
        let y = Swift.min(sand + (muzzle - sand) * 0.42, H - Double(GameLayout.bottomInset) - 40 * u)
        let words = Text("Drag back to aim").font(.system(size: 21 * u, weight: .heavy, design: .rounded)).kerning(0.5 * u)
        ctx.draw(words.foregroundColor(Color.white.opacity(0.8 * alpha)), at: pt(W / 2, y + 1.8 * u), anchor: .center)
        ctx.draw(words.foregroundColor(Tint.ink.color(alpha)), at: pt(W / 2, y), anchor: .center)
        let ay = y + 22 * u + 5 * u * pulse
        var arrow = Path()
        arrow.move(to: pt(W / 2 - 9 * u, ay))
        arrow.addLine(to: pt(W / 2, ay + 8 * u))
        arrow.addLine(to: pt(W / 2 + 9 * u, ay))
        ctx.stroke(arrow, with: .color(Color.white.opacity(0.8 * alpha)), style: StrokeStyle(lineWidth: 5.5 * u, lineCap: .round, lineJoin: .round))
        ctx.stroke(arrow, with: .color(Tint.ink.color(alpha)), style: StrokeStyle(lineWidth: 3 * u, lineCap: .round, lineJoin: .round))
    }
}
