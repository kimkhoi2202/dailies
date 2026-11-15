import SwiftUI

// Can Cannon: knock every can off the shelf with a cannon ball.
//
// CanCannonPainter paints a CanCannonModel into one Canvas: the beach, the shelves, the pieces, the
// ball and its aim line, the cannon, the score and the banners. The playable game hands it the live
// model. The clip in the video feed builds a model, lets the scripted pilot clear a five-row pyramid
// in three shots, and stops the clock at the phase. The beach, the cans, crates, stones, ball and
// cannon are pictures in Resources/GameArt; shelves, aim, effects and words are drawn here.

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

// MARK: - Art

/// The painted pictures, looked up once per frame. Cans come in every colour of CanCannonPalette.cans.
struct CanCannonArt {
    static let canNames = (0..<6).map { "can-cannon-can-\($0)" }
    /// Where the horizon sits in the backdrop picture, from the top.
    static let horizon: Double = 0.238
    /// How far the lid in a can picture rises above the can's box, over its height.
    static let canLid: Double = 0.08
    /// The cannon base picture's height over its width.
    static let baseAspect: Double = 0.538

    let backdrop: GraphicsContext.ResolvedImage
    let cans: [GraphicsContext.ResolvedImage]
    let crate: GraphicsContext.ResolvedImage
    let crateLong: GraphicsContext.ResolvedImage
    let stone: GraphicsContext.ResolvedImage
    let stoneLong: GraphicsContext.ResolvedImage
    let ball: GraphicsContext.ResolvedImage
    let barrel: GraphicsContext.ResolvedImage
    let base: GraphicsContext.ResolvedImage

    init(_ ctx: GraphicsContext) {
        backdrop = ctx.resolve(Image("can-cannon-backdrop"))
        cans = Self.canNames.map { ctx.resolve(Image($0)) }
        crate = ctx.resolve(Image("can-cannon-crate"))
        crateLong = ctx.resolve(Image("can-cannon-crate-long"))
        stone = ctx.resolve(Image("can-cannon-stone"))
        stoneLong = ctx.resolve(Image("can-cannon-stone-long"))
        ball = ctx.resolve(Image("can-cannon-ball"))
        barrel = ctx.resolve(Image("can-cannon-barrel"))
        base = ctx.resolve(Image("can-cannon-base"))
    }

    func can(_ tint: Int) -> GraphicsContext.ResolvedImage { cans[CanCannonPalette.index(tint)] }
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
        let art = CanCannonArt(ctx)
        drawBackdrop(&world, art)
        drawShadows(&world)
        drawPieces(&world, behind: true, art)
        let ballBehind = model.ball.active && model.ball.z > Model.shelfZ + Model.shelfDepth
        if ballBehind { drawBall(&world, art) }
        drawShelves(&world)
        drawPieces(&world, behind: false, art)
        drawShards(&world)
        if model.aiming && model.stage == .playing { drawAim(&world) }
        if !ballBehind { drawBall(&world, art) }
        drawCannon(&world, art)
        drawPopups(&world)

        drawConfetti(&ctx)
        if showHUD { drawHUD(&ctx) }
        drawBanner(&ctx)
        drawHint(&ctx)
    }

    // MARK: Beach

    private func drawBackdrop(_ ctx: inout GraphicsContext, _ art: CanCannonArt) {
        let pad = 16 * u
        ctx.fill(Path(CGRect(x: -pad, y: -pad, width: W + pad * 2, height: H + pad * 2)), with: .color(CanCannonPalette.sand.color()))
        let size = art.backdrop.size
        if size.width < 1 || size.height < 1 { return }
        // Big enough to cover the screen, and to put the picture's horizon on the stage's horizon.
        let k = Swift.max((W + pad * 2) / Double(size.width), (H + pad * 2) / Double(size.height),
                          (stage.horizonY + pad) / (CanCannonArt.horizon * Double(size.height)))
        let w = Double(size.width) * k
        let h = Double(size.height) * k
        let y = M.clamp(stage.horizonY - CanCannonArt.horizon * h, H + pad - h, -pad)
        ctx.draw(art.backdrop, in: CGRect(x: (W - w) / 2, y: y, width: w, height: h))
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
    private func drawPieces(_ ctx: inout GraphicsContext, behind: Bool, _ art: CanCannonArt) {
        for p in model.pieces {
            if p.pose == .gone { continue }
            let isBehind = p.z > Model.shelfDepth + 0.05
            if isBehind != behind { continue }
            drawPiece(&ctx, p, art)
        }
    }

    private func drawPiece(_ ctx: inout GraphicsContext, _ p: CanCannonPiece, _ art: CanCannonArt) {
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
        case .can:
            let lid = p.h * CanCannonArt.canLid
            c.draw(art.can(p.tint), in: CGRect(x: -p.w / 2, y: -p.h / 2 - lid, width: p.w, height: p.h + lid))
        case .crate:
            c.draw(p.w > p.h * 1.8 ? art.crateLong : art.crate, in: CGRect(x: -p.w / 2, y: -p.h / 2, width: p.w, height: p.h))
        case .stone:
            c.draw(p.w > p.h * 1.8 ? art.stoneLong : art.stone, in: CGRect(x: -p.w / 2, y: -p.h / 2, width: p.w, height: p.h))
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

    // MARK: Ball, aim, cannon

    private func drawBall(_ ctx: inout GraphicsContext, _ art: CanCannonArt) {
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
        c.draw(art.ball, in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
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

    private func drawCannon(_ ctx: inout GraphicsContext, _ art: CanCannonArt) {
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

        // The barrel, turned toward the aim.
        var barrel = ctx
        barrel.translateBy(x: pivotX, y: pivotY)
        barrel.rotate(by: .radians(turn))
        let tipY = -length + recoil
        let barrelW = 64 * u
        let barrelTop = tipY - 8 * u
        barrel.draw(art.barrel, in: CGRect(x: -barrelW / 2, y: barrelTop, width: barrelW, height: 30 * u - barrelTop))
        if since < 0.14 {
            let k = since / 0.14
            let r = (18 + 26 * k) * u
            barrel.fill(ellipse(0, tipY - 10 * u - 10 * u * k, r, r * 0.8), with: .radialGradient(
                Gradient(colors: [Color.white.opacity(1 - k), Tint(hex: 0xFFD27A).color(0.8 * (1 - k)), Color.white.opacity(0)]),
                center: pt(0, tipY - 10 * u - 10 * u * k), startRadius: 0, endRadius: r))
        }

        // The housing and the wheels, over the base of the barrel.
        let baseW = 184 * u
        let baseH = baseW * CanCannonArt.baseAspect
        ctx.draw(art.base, in: CGRect(x: pivotX - baseW / 2, y: pivotY + 20 * u - baseH / 2, width: baseW, height: baseH))
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
