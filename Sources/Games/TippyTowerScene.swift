import SwiftUI

// Tippy Tower: stack sliding slabs into a tower, one tap per slab.
//
// The whole picture is painted into one Canvas by TippyTowerPainter. The clip in the video feed
// builds a painter from a phase (0...1) and a fixed script; the playable game builds one from its
// live state. The skies, sun, moon, clouds, balloon and pillar are painted images from
// Resources/GameArt; the slabs are drawn in code so they can be cut to any size. Any frame size.

public struct TippyTowerScene: View {
    public var phase: Double
    public var showHUD: Bool

    public init(phase: Double, showHUD: Bool) {
        self.phase = phase
        self.showHUD = showHUD
    }

    public var body: some View {
        Canvas(opaque: true, colorMode: .nonLinear, rendersAsynchronously: false) { context, size in
            if size.width <= 8 || size.height <= 8 { return }
            TippyTowerPainter(size: size, clipPhase: phase, showHUD: showHUD).draw(&context)
        }
    }
}

// MARK: - Numbers

enum TippyTowerMath {
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
}

/// SplitMix64. The scenery and the round use different salts so they never share a sequence.
struct TippyTowerRandom {
    static let scenery: UInt64 = 0xD1B54A32D192ED03
    static let round: UInt64 = 0x2545F4914F6CDD1D

    private var state: UInt64

    init(seed: UInt64, salt: UInt64 = TippyTowerRandom.scenery) {
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

struct TippyTowerTint {
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

    static let white = TippyTowerTint(1, 1, 1)
    static let black = TippyTowerTint(0, 0, 0)

    func mix(_ other: TippyTowerTint, _ k: Double) -> TippyTowerTint {
        TippyTowerTint(r + (other.r - r) * k, g + (other.g - g) * k, b + (other.b - b) * k)
    }

    func scaled(_ k: Double) -> TippyTowerTint {
        TippyTowerTint(Swift.min(1, r * k), Swift.min(1, g * k), Swift.min(1, b * k))
    }

    func color(_ alpha: Double = 1) -> Color { Color(.sRGB, red: r, green: g, blue: b, opacity: alpha) }
}

enum TippyTowerPalette {
    /// Aqua at the first slab through to violet.
    static let ramp: [TippyTowerTint] = [0x22D1C8, 0x3FDF9A, 0x9CE957, 0xF6E347, 0xFFB23F, 0xFF7A59, 0xFF5B98, 0xC86BFF]
        .map { TippyTowerTint(hex: $0) }

    /// Colour of the slab at a floor. Floors 0...27 walk the ramp once; above that the colour eases
    /// back to aqua over nine floors and the ramp runs again, so a tall tower never stops shifting.
    static func slab(_ floor: Int) -> TippyTowerTint {
        var step = Swift.max(0, floor)
        if step > 27 {
            let lap = (step - 27) % 36
            if lap <= 9 { return ramp[ramp.count - 1].mix(ramp[0], Double(lap) / 9) }
            step = lap - 9
        }
        let at = TippyTowerMath.clamp(Double(step) / 27) * Double(ramp.count - 1)
        let low = Swift.min(Int(at), ramp.count - 2)
        return ramp[low].mix(ramp[low + 1], at - Double(low))
    }
}

/// The colours of the sky at one height.
struct TippyTowerSky {
    var top: TippyTowerTint
    var lower: TippyTowerTint
    var cloudRim: TippyTowerTint
    var cloudBody: TippyTowerTint
    var cloudDeep: TippyTowerTint
    var halo: TippyTowerTint
    var ambient: TippyTowerTint

    private init(_ hex: [UInt32]) {
        let c = hex.map { TippyTowerTint(hex: $0) }
        top = c[0]; lower = c[1]
        cloudRim = c[2]; cloudBody = c[3]; cloudDeep = c[4]; halo = c[5]; ambient = c[6]
    }

    static let dusk = TippyTowerSky([0x2A2473, 0xF0647C, 0xFFE6BF, 0xF28A8C, 0x84429A, 0xFFE3B0, 0x3E1A66])
    static let blueHour = TippyTowerSky([0x0E0F45, 0x5B57DB, 0xEADCFF, 0x8A78EA, 0x312E92, 0xCDBEFF, 0x1A1560])
    static let space = TippyTowerSky([0x03051A, 0x0D3B68, 0xA6F5E8, 0x1D7E90, 0x0A2A57, 0x8FE9FF, 0x061338])

    func mix(_ other: TippyTowerSky, _ k: Double) -> TippyTowerSky {
        var out = self
        out.top = top.mix(other.top, k)
        out.lower = lower.mix(other.lower, k)
        out.cloudRim = cloudRim.mix(other.cloudRim, k)
        out.cloudBody = cloudBody.mix(other.cloudBody, k)
        out.cloudDeep = cloudDeep.mix(other.cloudDeep, k)
        out.halo = halo.mix(other.halo, k)
        out.ambient = ambient.mix(other.ambient, k)
        return out
    }

    /// Dusk near the ground, blue hour half way up, the edge of space at the top. The height is 0...1.
    static func at(_ height: Double) -> TippyTowerSky {
        if height < 0.53 { return dusk.mix(blueHour, TippyTowerMath.smooth(0.20, 0.53, height)) }
        return blueHour.mix(space, TippyTowerMath.smooth(0.53, 0.86, height))
    }
}

/// Face colours of a slab under the scene's light.
struct TippyTowerFaces {
    let topLit: TippyTowerTint
    let top: TippyTowerTint
    let left: TippyTowerTint
    let leftShade: TippyTowerTint
    let right: TippyTowerTint
    let rightShade: TippyTowerTint
    let under: TippyTowerTint

    init(_ base: TippyTowerTint, ambient: TippyTowerTint) {
        topLit = base.mix(.white, 0.34)
        top = base.mix(.white, 0.05)
        left = base.scaled(0.88).mix(ambient, 0.08)
        leftShade = base.scaled(0.74).mix(ambient, 0.18)
        right = base.scaled(0.62).mix(ambient, 0.26)
        rightShade = base.scaled(0.48).mix(ambient, 0.38)
        under = base.scaled(0.34).mix(ambient, 0.5)
    }
}

// MARK: - What is on screen

/// The part sliced off a slab. The side is +1 when it hangs off the near side, -1 off the far side.
struct TippyTowerOffcut {
    var x0: Double
    var x1: Double
    var z0: Double
    var z1: Double
    var side: Double
}

/// A slab in the tower. Lengths are in slab units: the base slab runs from -1 to 1 both ways.
struct TippyTowerSlab {
    var x0 = -1.0
    var x1 = 1.0
    var z0 = -1.0
    var z1 = 1.0
    /// 0: it slid in along x, from the back left. 1: along z, from the back right.
    var axis = 0
    /// How far off it was let go, signed, along its axis.
    var error = 0.0
    var perfect = false
    /// Perfect drops in a row, this one included.
    var streak = 0
    var offcut: TippyTowerOffcut?

    func width(along axis: Int) -> Double { axis == 0 ? x1 - x0 : z1 - z0 }

    /// The slab left on top after a drop that was off by the given error, with the overhang cut away.
    static func sliced(on top: TippyTowerSlab, axis: Int, error: Double) -> TippyTowerSlab {
        var slab = TippyTowerSlab(x0: top.x0, x1: top.x1, z0: top.z0, z1: top.z1, axis: axis, error: error)
        var cut = TippyTowerOffcut(x0: top.x0, x1: top.x1, z0: top.z0, z1: top.z1, side: error > 0 ? 1 : -1)
        switch (axis, error > 0) {
        case (0, true): cut.x0 = top.x1; cut.x1 = top.x1 + error; slab.x0 += error
        case (0, false): cut.x0 = top.x0 + error; cut.x1 = top.x0; slab.x1 += error
        case (_, true): cut.z0 = top.z1; cut.z1 = top.z1 + error; slab.z0 += error
        case (_, false): cut.z0 = top.z0 + error; cut.z1 = top.z0; slab.z1 += error
        }
        slab.offcut = cut
        return slab
    }
}

/// The slab sliding above the tower.
struct TippyTowerMover {
    var x0: Double
    var x1: Double
    var z0: Double
    var z1: Double
    var axis: Int
    /// 0...1 as it fades in.
    var appear: Double
    /// +1 while it travels toward the near side, -1 on the way back.
    var dir: Double
}

/// An offcut on its way down.
struct TippyTowerPiece {
    var cut: TippyTowerOffcut
    var axis: Int
    /// The floor it was cut from.
    var floor: Int
    /// In drops.
    var age: Double
}

/// One frame of the playable game, as the painter wants it.
struct TippyTowerLiveFrame {
    /// Landed slabs, bottom first. Never empty.
    var slabs: [TippyTowerSlab] = []
    /// Since the last landing, in drops.
    var landAge = 10.0
    /// The world height the camera looks at.
    var camLevel = TippyTowerPainter.slabH
    /// Clock for the slow sway of a tall tower.
    var sway = 0.0
    /// Seconds, for clouds, stars and birds.
    var ambient = 0.0
    /// 0...1: the pull back when a round ends.
    var zoomOut = 0.0
    var mover: TippyTowerMover?
    var pieces: [TippyTowerPiece] = []
    var score = 0
    var bestText: String?
}

/// The round the clip shows: thirty drops with fixed errors.
enum TippyTowerClipScript {
    private static let errors: [Double] = [
        0, -0.10, 0.12, 0.06, -0.16, 0.10, 0, -0.12, 0.09, 0,
        -0.11, 0.13, 0.08, -0.17, -0.08, 0.10, 0.12, -0.09, -0.10, 0.08,
        0, 0, 0, 0.07, -0.08, 0.06, 0, -0.07, 0.05, 0
    ]

    static let slabs: [TippyTowerSlab] = {
        var tower: [TippyTowerSlab] = []
        var top = TippyTowerSlab()
        var streak = 0
        for (k, raw) in errors.enumerated() {
            let error = raw * 1.2
            var slab: TippyTowerSlab
            if abs(error) < 0.0001 {
                streak += 1
                slab = TippyTowerSlab(x0: top.x0, x1: top.x1, z0: top.z0, z1: top.z1, axis: k % 2, error: error)
                slab.perfect = true
            } else {
                streak = 0
                slab = TippyTowerSlab.sliced(on: top, axis: k % 2, error: error)
            }
            slab.streak = streak
            tower.append(slab)
            top = slab
        }
        return tower
    }()
}

// MARK: - Painter

struct TippyTowerPainter {
    typealias Tint = TippyTowerTint
    typealias M = TippyTowerMath

    static let slabH = 0.36
    /// How far above the tower the sliding slab floats.
    static let hover = 0.07

    let W: Double
    let H: Double
    /// Design points: 1 on a 402 x 874 phone.
    let u: Double
    let showHUD: Bool

    let slabs: [TippyTowerSlab]
    /// Slabs landed.
    let n: Int
    /// Lowest slab still worth drawing.
    let first: Int
    /// Since the last landing, in drops.
    let f: Double
    let mover: TippyTowerMover?
    let pieces: [TippyTowerPiece]
    let score: Int
    let bestText: String?
    /// How long the perfect call-out stays up, in drops.
    let calloutSpan: Double

    /// Clock for twinkles, wing beats and the balloon's bob.
    let flutter: Double
    /// 0...1: sideways position of clouds and balloon.
    let drift: Double
    let birdDrift: Double

    // Camera
    let scale: Double       // points per slab unit
    let ox: Double
    let topY: Double
    let camLevel: Double
    let altitude: Double    // 0 at the ground, 1 at 27 floors
    let scroll: Double
    let leanAmp: Double
    let leanSpan: Double
    let sky: TippyTowerSky

    var slabH: Double { TippyTowerPainter.slabH }

    /// A moment of the clip. Phase 0.15 is 5.75 drops in, 0.5 is 14.45, 0.85 is 23.15.
    init(size: CGSize, clipPhase: Double, showHUD: Bool) {
        let tower = TippyTowerClipScript.slabs
        let p = clipPhase.isFinite ? M.clamp(clipPhase) : 0
        let drops = 5.75 + (p - 0.15) * (8.7 / 0.35)
        let landed = Swift.min(Swift.max(Int(drops.rounded(.down)), 1), tower.count - 2)
        let since = M.clamp(drops - Double(landed))

        W = Double(size.width)
        H = Double(size.height)
        u = Swift.min(W / 402, H / 720)
        self.showHUD = showHUD
        slabs = tower
        n = landed
        first = 0
        f = since
        score = landed
        bestText = "BEST 31"
        calloutSpan = 0.75
        flutter = p
        drift = p
        birdDrift = p

        let rise = M.smooth(2, 25, drops)
        scale = u * M.lerp(76, 52, rise)
        ox = W * 0.47
        topY = H * M.lerp(0.46, 0.405, rise)
        camLevel = (Double(landed) - 1 + M.smooth(0, 0.5, since)) * TippyTowerPainter.slabH
        altitude = M.clamp(drops / 27)
        scroll = camLevel * 60 * u
        sky = TippyTowerSky.at(altitude)
        leanAmp = TippyTowerPainter.lean(height: drops, swayClock: drops, sinceLanding: since)
        leanSpan = Swift.max(1, Double(landed) * TippyTowerPainter.slabH)

        // The next slab of the script is on its way in, and the last two offcuts are still falling.
        let top = tower[landed - 1]
        let coming = tower[landed]
        let offset = coming.error - 2.25 * (1 - since)
        var sliding = TippyTowerMover(x0: top.x0, x1: top.x1, z0: top.z0, z1: top.z1, axis: coming.axis,
                                      appear: M.smooth(0, 0.10, since), dir: 1)
        if coming.axis == 0 {
            sliding.x0 += offset
            sliding.x1 += offset
        } else {
            sliding.z0 += offset
            sliding.z1 += offset
        }
        mover = sliding

        var falling: [TippyTowerPiece] = []
        for back in 0...1 {
            let floor = landed - 1 - back
            let age = since + Double(back)
            if floor >= 1, age < 1.5, let cut = tower[floor].offcut {
                falling.append(TippyTowerPiece(cut: cut, axis: tower[floor].axis, floor: floor, age: age))
            }
        }
        pieces = falling
    }

    /// A frame of the playable game.
    init(size: CGSize, live: TippyTowerLiveFrame) {
        W = Double(size.width)
        H = Double(size.height)
        u = Swift.min(W / 402, H / 720)
        showHUD = true
        slabs = live.slabs
        n = live.slabs.count
        f = Swift.max(0, live.landAge)
        mover = live.mover
        pieces = live.pieces
        score = live.score
        bestText = live.bestText
        calloutSpan = 1.5
        flutter = live.ambient / 8
        drift = 0.5 + 0.5 * sin(live.ambient * 0.09)
        birdDrift = 0.15 + live.ambient / 22

        let height = Swift.max(0, live.camLevel / TippyTowerPainter.slabH)
        let rise = M.smooth(2, 25, height)
        let pull = M.clamp(live.zoomOut)
        scale = u * M.lerp(76, 52, rise) * (1 - 0.26 * pull)
        ox = W * 0.47
        topY = H * (M.lerp(0.46, 0.405, rise) + 0.05 * pull)
        camLevel = live.camLevel
        altitude = M.clamp(height / 27)
        scroll = camLevel * 60 * u
        sky = TippyTowerSky.at(altitude)
        leanAmp = TippyTowerPainter.lean(height: height, swayClock: live.sway, sinceLanding: f)
        leanSpan = Swift.max(1, Double(n) * TippyTowerPainter.slabH)

        // Skip the slabs far below the bottom edge: a tall tower then costs what a short one does.
        let lowest = camLevel - 1 - (H - topY) / Swift.max(1, scale)
        let floor = Int((lowest / TippyTowerPainter.slabH).rounded(.down)) - 2
        first = Swift.min(Swift.max(0, floor), Swift.max(0, n - 1))
    }

    /// A taller tower sways more, and every landing gives it a kick.
    private static func lean(height: Double, swayClock: Double, sinceLanding: Double) -> Double {
        let reach = 0.20 * M.smooth(7, 24, height)
        let slow = 0.45 * sin(2 * .pi * 0.31 * swayClock + 0.8)
        let kick = 0.55 * exp(-3.2 * sinceLanding) * sin(2 * .pi * 2.2 * sinceLanding)
        return reach * (slow + kick)
    }

    // MARK: Projection

    /// Slab space to the screen. Pass leanY when the sway should be taken at another height than y.
    func pt(_ x: Double, _ y: Double, _ z: Double, leanY: Double? = nil) -> CGPoint {
        let bend = Swift.max(0, leanY ?? y) / leanSpan
        let lean = leanAmp * bend * bend
        return CGPoint(x: ox + ((x - z) * 0.866 + lean) * scale,
                       y: topY + ((x + z) * 0.5 - (y - camLevel)) * scale)
    }

    /// A flat rectangle at height y.
    func deck(_ x0: Double, _ x1: Double, _ z0: Double, _ z1: Double, _ y: Double) -> Path {
        shape([pt(x0, y, z0), pt(x1, y, z0), pt(x1, y, z1), pt(x0, y, z1)])
    }

    private func shape(_ corners: [CGPoint]) -> Path {
        var path = Path()
        path.addLines(corners)
        path.closeSubpath()
        return path
    }

    private func disc(_ cx: Double, _ cy: Double, _ r: Double) -> Path {
        Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r))
    }

    private var screen: Path { Path(CGRect(x: 0, y: 0, width: W, height: H)) }

    /// How far a backdrop item has moved down the screen since the camera was at the given level.
    private func parallax(from level: Double, _ depth: Double) -> Double { (camLevel - level) * 60 * u * depth }

    // MARK: Frame

    func draw(_ ctx: inout GraphicsContext) {
        drawSky(&ctx)
        drawStars(&ctx)
        drawSun(&ctx)
        drawMoon(&ctx)
        drawFarClouds(&ctx)
        drawBalloon(&ctx)
        drawBirds(&ctx)
        drawTowerGlow(&ctx)
        drawPieces(&ctx, near: false)
        drawBase(&ctx)
        drawTower(&ctx)
        drawMover(&ctx)
        drawPieces(&ctx, near: true)
        drawPerfectBurst(&ctx)
        drawCloudSea(&ctx)
        drawHaze(&ctx)
        if showHUD { drawHUD(&ctx) }
    }

    // MARK: Sky

    /// Painted skies for dusk, blue hour and the edge of space, faded into each other with height.
    private func drawSky(_ ctx: inout GraphicsContext) {
        ctx.fill(screen, with: .color(sky.top.color()))
        let cover = Swift.max(W / 2, H / 3)
        let frame = CGRect(x: (W - 2 * cover) / 2, y: (H - 3 * cover) / 2, width: 2 * cover, height: 3 * cover)
        let layers: [(name: String, alpha: Double)] = [
            ("tippy-tower-sky-dusk", 1 - M.smooth(0.20, 0.53, altitude)),
            ("tippy-tower-sky-night", M.smooth(0.20, 0.53, altitude) * (1 - M.smooth(0.53, 0.86, altitude))),
            ("tippy-tower-sky-space", M.smooth(0.53, 0.86, altitude))
        ]
        for layer in layers where layer.alpha > 0.005 {
            var painted = ctx
            painted.opacity = layer.alpha
            painted.draw(ctx.resolve(Image(layer.name)), in: frame)
        }
    }

    /// A four-pointed star.
    static func sparkle(_ c: CGPoint, _ r: Double, pinch: Double = 0.2) -> Path {
        var path = Path()
        for k in 0..<8 {
            let turn = Double(k) * .pi / 4 - .pi / 2
            let reach = k % 2 == 0 ? r : r * pinch
            let p = CGPoint(x: Double(c.x) + cos(turn) * reach, y: Double(c.y) + sin(turn) * reach)
            if k == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        return path
    }

    private func drawStars(_ ctx: inout GraphicsContext) {
        let shown = M.smooth(0.30, 0.76, altitude)
        if shown <= 0.01 { return }
        let dot = sky.cloudRim.mix(.white, 0.5)
        var rng = TippyTowerRandom(seed: 77)
        for k in 0..<96 {
            let x = rng.next() * W
            let depth = rng.next()
            var y = depth * depth * H * 0.92 + scroll * 0.05
            // Only above the clip's height: stars that leave the bottom come back in at the top.
            if y > H * 1.05 { y = y.truncatingRemainder(dividingBy: H * 1.05) }
            let r = (0.55 + rng.next() * 1.15) * u
            let offset = rng.next() * 6.283
            let twinkle = 0.62 + 0.38 * sin(flutter * 2 * .pi * Double(2 + k % 5) + offset)
            let alpha = shown * twinkle * (0.25 + 0.75 * (1 - y / H))
            if k % 12 == 0 {
                ctx.fill(Self.sparkle(CGPoint(x: x, y: y), r * 4.2), with: .color(.white.opacity(alpha)))
            } else {
                ctx.fill(disc(x, y, r), with: .color(dot.color(alpha)))
            }
        }
    }

    private func drawSun(_ ctx: inout GraphicsContext) {
        let shown = 1 - M.smooth(0.30, 0.52, altitude)
        if shown <= 0.01 { return }
        let cx = W * 0.14
        let cy = H * 0.50 + parallax(from: 2.07, 0.45)
        let centre = CGPoint(x: cx, y: cy)

        let glowR = 200 * u
        let glow = Gradient(stops: [
            .init(color: Tint(hex: 0xFFF1C2).color(0.85 * shown), location: 0),
            .init(color: Tint(hex: 0xFFC38A).color(0.32 * shown), location: 0.35),
            .init(color: Tint(hex: 0xFF9E7A).color(0), location: 1)
        ])
        ctx.fill(disc(cx, cy, glowR), with: .radialGradient(glow, center: centre, startRadius: 0, endRadius: glowR))

        let r = 40 * u
        ctx.fill(disc(cx, cy, r * 1.9), with: .color(.white.opacity(0.08 * shown)))
        var sun = ctx
        sun.opacity = shown
        sun.draw(ctx.resolve(Image("tippy-tower-sun")), in: CGRect(x: cx - r * 1.3, y: cy - r * 1.3, width: r * 2.6, height: r * 2.6))
    }

    private func drawMoon(_ ctx: inout GraphicsContext) {
        let shown = M.smooth(0.52, 0.80, altitude)
        if shown <= 0.01 { return }
        let r = 25 * u
        let cx = W * 0.165
        let cy = H * 0.29 + parallax(from: 8.3, 0.6)

        let glowR = r * 4.6
        ctx.fill(disc(cx, cy, glowR), with: .radialGradient(
            Gradient(colors: [sky.halo.color(0.30 * shown), sky.halo.color(0.08 * shown), sky.halo.color(0)]),
            center: CGPoint(x: cx, y: cy), startRadius: r * 0.6, endRadius: glowR))

        var moon = ctx
        moon.opacity = shown
        moon.draw(ctx.resolve(Image("tippy-tower-moon")), in: CGRect(x: cx - r * 1.13, y: cy - r * 1.2, width: r * 2.26, height: r * 2.4))
    }

    // MARK: Clouds, balloon, birds

    /// Painted white clouds, wide over tall, tinted to the sky.
    private static let cloudArt: [(name: String, aspect: Double)] = [("tippy-tower-cloud-a", 0.414), ("tippy-tower-cloud-b", 0.349)]

    private func drawCloud(_ ctx: inout GraphicsContext, art: GraphicsContext.ResolvedImage, aspect: Double,
                           cx: Double, cy: Double, width w: Double, alpha: Double) {
        if alpha <= 0.01 || cy <= -w || cy >= H + w { return }
        let h = w * aspect
        var cloud = ctx
        cloud.opacity = alpha
        cloud.addFilter(.colorMultiply(sky.cloudRim.mix(sky.cloudBody, 0.3).color()))
        cloud.draw(art, in: CGRect(x: cx - w / 2, y: cy + 0.12 * w - h, width: w, height: h))
    }

    /// x, y at ground level, parallax, width, opacity.
    private static let farClouds: [(x: Double, y: Double, depth: Double, width: Double, alpha: Double)] = [
        (0.86, 0.245, 0.45, 150, 0.55),
        (0.08, 0.180, 0.60, 112, 0.45),
        (0.70, -0.02, 0.80, 120, 0.50),
        (0.20, 0.300, 0.95, 176, 0.42),
        (0.92, -0.30, 1.00, 140, 0.40),
        (0.10, -0.42, 0.90, 128, 0.36)
    ]

    private func drawFarClouds(_ ctx: inout GraphicsContext) {
        let thin = 1 - 0.75 * M.smooth(0.6, 0.9, altitude)
        let art = Self.cloudArt.map { ctx.resolve(Image($0.name)) }
        for (k, cloud) in Self.farClouds.enumerated() {
            let slide = (drift - 0.5) * 34 * u * (k % 2 == 0 ? -1 : 1)
            var cy = H * cloud.y + scroll * cloud.depth
            // Only above the clip's height: a cloud that leaves the bottom drifts in again from the top.
            if cy >= H * 1.1 { cy = -H * 0.5 + (cy + H * 0.5).truncatingRemainder(dividingBy: H * 1.6) }
            drawCloud(&ctx, art: art[k % 2], aspect: Self.cloudArt[k % 2].aspect, cx: W * cloud.x + slide, cy: cy,
                      width: cloud.width * u, alpha: cloud.alpha * thin)
        }
    }

    private func drawBalloon(_ ctx: inout GraphicsContext) {
        let shown = M.smooth(0.30, 0.44, altitude) * (1 - M.smooth(0.66, 0.80, altitude))
        if shown <= 0.01 { return }
        let r = 19 * u
        let cx = W * 0.80 - (drift - 0.5) * 60 * u
        let cy = H * 0.335 + parallax(from: 5.2, 1.1) + sin(flutter * 2 * .pi * 3) * 3 * u

        var balloon = ctx
        balloon.opacity = shown * 0.95
        let w = r * 2.2
        balloon.draw(ctx.resolve(Image("tippy-tower-balloon")), in: CGRect(x: cx - w / 2, y: cy - r * 1.1, width: w, height: w * 1.49))
    }

    /// Offset from the lead bird in design points, and size.
    private static let flock: [(dx: Double, dy: Double, size: Double)] = [(0, 0, 1.0), (-26, 13, 0.8), (-13, -17, 0.7)]

    private func drawBirds(_ ctx: inout GraphicsContext) {
        let shown = 1 - M.smooth(0.26, 0.40, altitude)
        if shown <= 0.01 { return }
        var leadX = W * 0.20 + (birdDrift - 0.15) * 150 * u
        // Never in the clip: once off the right edge the flock comes round again.
        if leadX > W + 40 * u { leadX = -40 * u + (leadX + 40 * u).truncatingRemainder(dividingBy: W + 80 * u) }
        let leadY = H * 0.325 + parallax(from: 2.07, 0.9)
        let ink = sky.ambient.color(0.7 * shown)
        for (k, bird) in Self.flock.enumerated() {
            let span = 8.5 * u * bird.size
            let beat = 0.5 + 0.5 * sin(flutter * 2 * .pi * 9 + Double(k) * 1.7)
            let x = leadX + bird.dx * u
            let y = leadY + bird.dy * u
            let tipY = y - span * (0.1 + 0.5 * beat)
            let archY = y - span * (0.55 + 0.3 * beat)
            var wings = Path()
            wings.move(to: CGPoint(x: x - span, y: tipY))
            wings.addQuadCurve(to: CGPoint(x: x, y: y), control: CGPoint(x: x - span * 0.45, y: archY))
            wings.addQuadCurve(to: CGPoint(x: x + span, y: tipY), control: CGPoint(x: x + span * 0.45, y: archY))
            ctx.stroke(wings, with: .color(ink),
                       style: StrokeStyle(lineWidth: Swift.max(0.6, 1.7 * u * bird.size), lineCap: .round, lineJoin: .round))
        }
    }

    private func drawTowerGlow(_ ctx: inout GraphicsContext) {
        let centre = CGPoint(x: ox, y: topY - 6 * u)
        let r = 250 * u
        let glow = Gradient(stops: [
            .init(color: sky.halo.color(0.34), location: 0),
            .init(color: sky.halo.color(0.14), location: 0.45),
            .init(color: sky.halo.color(0), location: 1)
        ])
        ctx.fill(disc(ox, topY - 6 * u, r), with: .radialGradient(glow, center: centre, startRadius: 0, endRadius: r))
    }

    /// Three banks of cloud the tower stands in. They sink out of view as the camera climbs.
    private func drawCloudSea(_ ctx: inout GraphicsContext) {
        let surface = H * 0.705 + parallax(from: 2.07, 0.62)
        if surface >= H + 70 * u { return }
        var rng = TippyTowerRandom(seed: 4242)
        for bank in 0..<3 {
            let depth = Double(bank)
            let base = surface + depth * 30 * u
            let slide = drift * 22 * (depth + 1) * u
            var puffs = Path()
            var x = -90 * u
            while x < W + 170 * u {
                let r = (24 + rng.next() * 22) * u * (1 + 0.16 * depth)
                let cy = base + r * 0.4 + rng.next() * 9 * u
                puffs.addEllipse(in: CGRect(x: x - slide - r, y: cy - r, width: 2 * r, height: 2 * r))
                x += r * (0.95 + rng.next() * 0.55)
            }
            let k = depth / 2
            let high = sky.cloudBody.mix(sky.cloudRim, 0.30 - 0.18 * k).mix(sky.cloudDeep, 0.15 + 0.3 * k)
            let low = sky.cloudDeep.mix(sky.top, 0.15 + 0.25 * k)
            let body = GraphicsContext.Shading.linearGradient(
                Gradient(colors: [high.color(), low.color()]),
                startPoint: CGPoint(x: 0, y: base - 30 * u), endPoint: CGPoint(x: 0, y: base + 190 * u))
            var rim = ctx
            rim.translateBy(x: 0, y: -2.6 * u)
            rim.fill(puffs, with: .color(sky.cloudRim.mix(sky.cloudBody, 0.25 * k).color(0.9 - 0.2 * k)))
            ctx.fill(puffs, with: body)
            ctx.fill(Path(CGRect(x: -4, y: base + 22 * u, width: W + 8, height: Swift.max(0, H - base) + 8)), with: body)
        }
    }

    private func drawHaze(_ ctx: inout GraphicsContext) {
        let fog = sky.cloudDeep.mix(sky.top, 0.35)
        ctx.fill(screen, with: .linearGradient(
            Gradient(stops: [
                .init(color: fog.color(0), location: 0),
                .init(color: fog.color(0.16), location: 0.5),
                .init(color: fog.color(0.62), location: 1)
            ]),
            startPoint: CGPoint(x: 0, y: H * 0.60), endPoint: CGPoint(x: 0, y: H)))
        let reach = Swift.max(W, H)
        ctx.fill(screen, with: .radialGradient(
            Gradient(colors: [Color.black.opacity(0), Color.black.opacity(0), sky.top.mix(.black, 0.6).color(0.42)]),
            center: CGPoint(x: W * 0.47, y: H * 0.44), startRadius: reach * 0.2, endRadius: reach * 0.82))
    }

    // MARK: Slabs

    /// A gradient that runs across a face: it starts on the edge a-b and ends level with the far point.
    private func across(_ a: CGPoint, _ b: CGPoint, far: CGPoint, _ colors: [Color]) -> GraphicsContext.Shading {
        let ex = Double(b.x - a.x)
        let ey = Double(b.y - a.y)
        let length = Swift.max(0.001, (ex * ex + ey * ey).squareRoot())
        let nx = -ey / length
        let ny = ex / length
        let depth = Double(far.x - a.x) * nx + Double(far.y - a.y) * ny
        return .linearGradient(Gradient(colors: colors), startPoint: a,
                               endPoint: CGPoint(x: Double(a.x) + nx * depth, y: Double(a.y) + ny * depth))
    }

    /// A box with its three visible faces lit. The edge value is the strength of the white rim on top.
    func drawSlab(_ ctx: inout GraphicsContext, x0: Double, x1: Double, z0: Double, z1: Double, y0: Double, y1: Double,
                  base: Tint, edge: Double = 0.55, flash: Double = 0, sheen: Double = 0) {
        let topBack = pt(x0, y1, z0), topRight = pt(x1, y1, z0), topFront = pt(x1, y1, z1), topLeft = pt(x0, y1, z1)
        let lowLeft = pt(x0, y0, z1), lowFront = pt(x1, y0, z1), lowRight = pt(x1, y0, z0)
        if Double(topBack.y) > H + 6 || Double(lowFront.y) < -6 { return }
        let faces = TippyTowerFaces(base, ambient: sky.ambient)

        let outline = shape([topBack, topRight, lowRight, lowFront, lowLeft, topLeft])
        ctx.fill(outline, with: .color(faces.right.color()))
        ctx.fill(shape([topLeft, topFront, lowFront, lowLeft]),
                 with: across(topLeft, topFront, far: lowLeft, [faces.left.color(), faces.left.color(), faces.leftShade.color()]))
        ctx.fill(shape([topFront, topRight, lowRight, lowFront]),
                 with: across(topFront, topRight, far: lowFront, [faces.right.color(), faces.right.color(), faces.rightShade.color()]))

        let lid = shape([topBack, topRight, topFront, topLeft])
        ctx.fill(lid, with: .linearGradient(Gradient(colors: [faces.topLit.color(), faces.top.color()]),
                                            startPoint: topLeft, endPoint: topRight))
        if sheen > 0 {
            ctx.fill(lid, with: .linearGradient(
                Gradient(colors: [Color.white.opacity(sheen), Color.white.opacity(0)]),
                startPoint: topBack, endPoint: CGPoint(x: (topBack.x + topFront.x) / 2, y: (topBack.y + topFront.y) / 2)))
        }

        let line = Swift.max(0.5, 1.35 * u)
        var rim = Path()
        rim.addLines([topLeft, topFront, topRight])
        ctx.stroke(rim, with: .color(.white.opacity(edge)), style: StrokeStyle(lineWidth: line, lineCap: .round, lineJoin: .round))
        var corner = Path()
        corner.move(to: topFront)
        corner.addLine(to: lowFront)
        ctx.stroke(corner, with: .color(.white.opacity(edge * 0.32)), style: StrokeStyle(lineWidth: line * 0.8, lineCap: .round))

        if flash > 0.01 { ctx.fill(outline, with: .color(.white.opacity(flash))) }
    }

    /// The pale plinth the tower stands on, and the stone pillar under it.
    private func drawBase(_ ctx: inout GraphicsContext) {
        if Double(pt(-1.3, 0, -1.3).y) > H + 6 { return }
        let plinth = 0.44
        let half = 1.07
        // The painted stone pillar, its top hidden under the plinth.
        let pillarLeft = Double(pt(-half, -plinth, half).x)
        let pillarWidth = Double(pt(half, -plinth, -half).x) - pillarLeft
        let pillarTop = Double(pt(-half, -plinth, -half).y)
        ctx.draw(ctx.resolve(Image("tippy-tower-pillar")),
                 in: CGRect(x: pillarLeft, y: pillarTop, width: pillarWidth, height: pillarWidth * 2.836))

        // The plinth's shadow on the top of the pillar.
        let high = -plinth
        let low = -plinth - 0.55
        let leftA = pt(-half, high, half), leftB = pt(half, high, half)
        let leftD = pt(-half, low, half)
        ctx.fill(shape([leftA, leftB, pt(half, low, half), leftD]),
                 with: across(leftA, leftB, far: leftD, [sky.ambient.color(0.45), sky.ambient.color(0)]))
        let rightA = pt(half, high, half), rightB = pt(half, high, -half)
        let rightD = pt(half, low, half)
        ctx.fill(shape([rightA, rightB, pt(half, low, -half), rightD]),
                 with: across(rightA, rightB, far: rightD, [sky.ambient.color(0.5), sky.ambient.color(0)]))

        drawSlab(&ctx, x0: -1.3, x1: 1.3, z0: -1.3, z1: 1.3, y0: -plinth, y1: 0,
                 base: Tint(hex: 0xFFF0DE).mix(sky.lower, 0.06), edge: 0.75)
    }

    /// The soft shadow a slab casts on the surface under it.
    private func drawContactShadow(_ ctx: inout GraphicsContext, on surface: Path, of slab: TippyTowerSlab,
                                   y: Double, spread: Double) {
        var shade = ctx
        shade.clip(to: surface)
        shade.fill(deck(slab.x0 - spread * 0.3, slab.x1 + spread * 2.2, slab.z0 - spread * 0.3, slab.z1 + spread * 2.2, y),
                   with: .color(sky.ambient.color(0.30 * 0.45)))
        shade.fill(deck(slab.x0 - spread * 0.15, slab.x1 + spread, slab.z0 - spread * 0.15, slab.z1 + spread, y),
                   with: .color(sky.ambient.color(0.30)))
    }

    private func drawTower(_ ctx: inout GraphicsContext) {
        if n <= 0 { return }
        for floor in first..<n {
            let slab = slabs[floor]
            let level = Double(floor) * slabH
            let isTop = floor == n - 1
            var y0 = level
            var y1 = level + slabH
            var flash = 0.0
            if isTop {
                // The newest slab drops the last little way, squashes and flashes.
                let fall = Swift.max(0, 1 - f / 0.06)
                y0 += Self.hover * fall * fall
                let since = f - 0.04
                let squash = since > 0 ? 0.24 * exp(-9 * since) * cos(2 * .pi * 3.2 * since) : 0
                y1 = y0 + slabH * (1 - squash)
                flash = slab.perfect ? 0.78 * Swift.max(0, 1 - f / 0.42) : 0.30 * Swift.max(0, 1 - f / 0.18)
            }

            if floor == 0 {
                drawContactShadow(&ctx, on: deck(-1.3, 1.3, -1.3, 1.3, 0), of: slab, y: 0, spread: 0.11)
            } else {
                let under = slabs[floor - 1]
                drawContactShadow(&ctx, on: deck(under.x0, under.x1, under.z0, under.z1, level), of: slab, y: level, spread: 0.07)
            }
            if isTop && slab.perfect { drawPerfectRings(&ctx, around: slab, level: level) }
            drawSlab(&ctx, x0: slab.x0, x1: slab.x1, z0: slab.z0, z1: slab.z1, y0: y0, y1: y1,
                     base: TippyTowerPalette.slab(floor), edge: isTop ? 0.8 : 0.5, flash: flash, sheen: isTop ? 0.22 : 0)
        }
    }

    /// Two rings that spread from under a slab that landed perfectly.
    private func drawPerfectRings(_ ctx: inout GraphicsContext, around slab: TippyTowerSlab, level: Double) {
        for k in 0..<2 {
            let age = f - Double(k) * 0.075
            if age <= 0 { continue }
            let life = M.clamp(age / 0.6)
            if life >= 1 { continue }
            let grow = 0.05 + (k == 0 ? 0.80 : 0.55) * M.easeOut(life)
            let alpha = (1 - life) * (k == 0 ? 1.0 : 0.6)
            let ring = deck(slab.x0 - grow, slab.x1 + grow, slab.z0 - grow, slab.z1 + grow, level)
            ctx.fill(ring, with: .color(.white.opacity(0.10 * alpha)))
            ctx.stroke(ring, with: .color(sky.halo.color(0.13 * alpha)),
                       style: StrokeStyle(lineWidth: 13 * u, lineCap: .round, lineJoin: .round))
            ctx.stroke(ring, with: .color(.white.opacity(0.24 * alpha)),
                       style: StrokeStyle(lineWidth: 6.5 * u, lineCap: .round, lineJoin: .round))
            ctx.stroke(ring, with: .color(.white.opacity(0.96 * alpha)),
                       style: StrokeStyle(lineWidth: Swift.max(0.8, 2.6 * u), lineCap: .round, lineJoin: .round))
        }
    }

    // MARK: The sliding slab

    private func drawMover(_ ctx: inout GraphicsContext) {
        guard n >= 1, let mv = mover, mv.appear > 0.01 else { return }
        let top = slabs[n - 1]
        let level = Double(n) * slabH
        let y0 = level + Self.hover
        let y1 = y0 + slabH
        let base = TippyTowerPalette.slab(n)
        let lit = TippyTowerFaces(base, ambient: sky.ambient).topLit
        let alongX = mv.axis == 0

        // Its shadow on the top of the tower.
        var shade = ctx
        shade.clip(to: deck(top.x0, top.x1, top.z0, top.z1, level))
        shade.fill(deck(mv.x0 + 0.02, mv.x1 + 0.10, mv.z0 + 0.02, mv.z1 + 0.10, level), with: .color(sky.ambient.color(0.20 * mv.appear)))
        shade.fill(deck(mv.x0 + 0.02, mv.x1 + 0.05, mv.z0 + 0.02, mv.z1 + 0.05, level), with: .color(sky.ambient.color(0.26 * mv.appear)))

        // Three ghosts of the top face trail behind it.
        for ghost in 1...3 {
            let lag = Double(ghost) * 0.13 * mv.dir
            let dx = alongX ? lag : 0
            let dz = alongX ? 0 : lag
            ctx.fill(deck(mv.x0 - dx, mv.x1 - dx, mv.z0 - dz, mv.z1 - dz, y1),
                     with: .color(lit.color(0.16 * mv.appear / Double(ghost))))
        }

        // Speed lines from its trailing edge.
        var rng = TippyTowerRandom(seed: UInt64(900 + n))
        for k in 0..<7 {
            let across = (Double(k) + 0.5) / 7 + rng.range(-0.04, 0.04)
            let length = rng.range(0.45, 1.15)
            let y = k % 3 == 2 ? y0 + 0.04 : y1
            let from: CGPoint
            let to: CGPoint
            if alongX {
                let z = M.lerp(mv.z0, mv.z1, across)
                let tail = mv.dir >= 0 ? mv.x0 : mv.x1
                from = pt(tail, y, z)
                to = pt(tail - length * mv.dir, y, z)
            } else {
                let x = M.lerp(mv.x0, mv.x1, across)
                let tail = mv.dir >= 0 ? mv.z0 : mv.z1
                from = pt(x, y, tail)
                to = pt(x, y, tail - length * mv.dir)
            }
            var line = Path()
            line.move(to: from)
            line.addLine(to: to)
            ctx.stroke(line,
                       with: .linearGradient(Gradient(colors: [Color.white.opacity(0.75 * mv.appear), Color.white.opacity(0)]),
                                             startPoint: from, endPoint: to),
                       style: StrokeStyle(lineWidth: Swift.max(0.6, rng.range(1.4, 2.6) * u), lineCap: .round))
        }

        var solid = ctx
        solid.opacity = mv.appear
        drawSlab(&solid, x0: mv.x0, x1: mv.x1, z0: mv.z0, z1: mv.z1, y0: y0, y1: y1, base: base, edge: 0.9, sheen: 0.28)
    }

    // MARK: Offcuts

    /// Offcuts on the far side are drawn behind the tower, the near ones in front of it.
    private func drawPieces(_ ctx: inout GraphicsContext, near: Bool) {
        for piece in pieces where (piece.cut.side > 0) == near {
            drawPiece(&ctx, piece)
        }
    }

    /// Corners of each face of a box, as indices into its eight corners (bit 0 = +x, bit 1 = +y,
    /// bit 2 = +z), with the face's outward normal.
    private static let boxFaces: [(corners: [Int], normal: (Double, Double, Double))] = [
        ([2, 3, 7, 6], (0, 1, 0)),
        ([0, 1, 5, 4], (0, -1, 0)),
        ([1, 3, 7, 5], (1, 0, 0)),
        ([0, 2, 6, 4], (-1, 0, 0)),
        ([4, 5, 7, 6], (0, 0, 1)),
        ([0, 1, 3, 2], (0, 0, -1))
    ]

    private func drawPiece(_ ctx: inout GraphicsContext, _ piece: TippyTowerPiece) {
        let cut = piece.cut
        let age = piece.age
        let alpha = 1 - M.smooth(1.05, 1.5, age)
        if alpha <= 0.01 { return }

        let alongX = piece.axis == 0
        let halfX = (cut.x1 - cut.x0) / 2
        let halfY = slabH / 2
        let halfZ = (cut.z1 - cut.z0) / 2
        let leanY = Double(piece.floor) * slabH
        let slide = cut.side * 1.5 * age
        let cx = (cut.x0 + cut.x1) / 2 + (alongX ? slide : 0)
        let cz = (cut.z0 + cut.z1) / 2 + (alongX ? 0 : slide)
        let cy = (Double(piece.floor) + 0.5) * slabH - 4.8 * age * age
        if Double(pt(cx, cy, cz, leanY: leanY).y) > H + 80 * u { return }

        // It tumbles away from the tower: about z when it was cut along x, about x otherwise.
        let turn = cut.side * 2.5 * pow(age, 1.15)
        let co = cos(turn), si = sin(turn)
        func turned(_ x: Double, _ y: Double, _ z: Double) -> (Double, Double, Double) {
            alongX ? (x * co + y * si, y * co - x * si, z) : (x, y * co - z * si, y * si + z * co)
        }
        let faces = TippyTowerFaces(TippyTowerPalette.slab(piece.floor), ambient: sky.ambient)

        // Streaks above it once it is falling fast.
        let rush = M.clamp(age / 0.5)
        if rush > 0.05 {
            for k in 0..<3 {
                let off = (Double(k) - 1) * 0.42 * (alongX ? halfZ : halfX)
                let length = (0.55 + 0.25 * Double(k % 2)) * rush
                let back = cut.side * 0.3 * length
                let from = alongX ? pt(cx, cy + 0.15, cz + off, leanY: leanY) : pt(cx + off, cy + 0.15, cz, leanY: leanY)
                let to = alongX ? pt(cx - back, cy + 0.15 + length * 1.6, cz + off, leanY: leanY)
                                : pt(cx + off, cy + 0.15 + length * 1.6, cz - back, leanY: leanY)
                var line = Path()
                line.move(to: from)
                line.addLine(to: to)
                ctx.stroke(line,
                           with: .linearGradient(Gradient(colors: [Color.white.opacity(0.55 * alpha), Color.white.opacity(0)]),
                                                 startPoint: from, endPoint: to),
                           style: StrokeStyle(lineWidth: Swift.max(0.6, 2.0 * u), lineCap: .round))
            }
        }

        var corners: [CGPoint] = []
        corners.reserveCapacity(8)
        for k in 0..<8 {
            let local = turned(k & 1 == 0 ? -halfX : halfX, k & 2 == 0 ? -halfY : halfY, k & 4 == 0 ? -halfZ : halfZ)
            corners.append(pt(cx + local.0, cy + local.1, cz + local.2, leanY: leanY))
        }
        var body = ctx
        body.opacity = alpha
        var edges = Path()
        for face in Self.boxFaces {
            let normal = turned(face.normal.0, face.normal.1, face.normal.2)
            if normal.0 + normal.1 + normal.2 <= 0.0001 { continue }
            let path = shape(face.corners.map { corners[$0] })
            // Blend the lit colours by how much the face looks up, left and right.
            let up = Swift.max(0, normal.1) * Swift.max(0, normal.1)
            let left = Swift.max(0, normal.2) * Swift.max(0, normal.2)
            let right = Swift.max(0, normal.0) * Swift.max(0, normal.0)
            let down = Swift.max(0, 1 - up - left - right)
            let tone = Tint(faces.top.r * up + faces.left.r * left + faces.right.r * right + faces.under.r * down,
                            faces.top.g * up + faces.left.g * left + faces.right.g * right + faces.under.g * down,
                            faces.top.b * up + faces.left.b * left + faces.right.b * right + faces.under.b * down).color()
            body.fill(path, with: .color(tone))
            body.stroke(path, with: .color(tone), style: StrokeStyle(lineWidth: 0.6, lineJoin: .round))
            edges.addPath(path)
        }
        body.stroke(edges, with: .color(.white.opacity(0.42)), style: StrokeStyle(lineWidth: Swift.max(0.5, 1.1 * u), lineJoin: .round))

        // Chips kicked out along the cut.
        let chipLife = M.clamp(age / 0.55)
        if chipLife < 1 {
            var rng = TippyTowerRandom(seed: UInt64(300 + piece.floor))
            let chipColor = faces.topLit.mix(.white, 0.3).color((1 - chipLife) * 0.95)
            let edgeX = cut.side > 0 ? cut.x0 : cut.x1
            let edgeZ = cut.side > 0 ? cut.z0 : cut.z1
            for _ in 0..<9 {
                let along = rng.range(-0.9, 0.9)
                let out = rng.range(0.6, 2.4) * cut.side
                let up = rng.range(0.6, 2.2)
                let size = rng.range(1.6, 3.6) * u * (1 - chipLife * 0.6)
                let x = alongX ? edgeX + out * age : cx - slide + along * halfX
                let z = alongX ? cz + along * halfZ : edgeZ + out * age
                let y = Double(piece.floor + 1) * slabH + up * age - 5.0 * age * age
                let at = pt(x, y, z, leanY: leanY)
                let px = Double(at.x), py = Double(at.y)
                ctx.fill(shape([CGPoint(x: px, y: py - size), CGPoint(x: px + size * 1.3, y: py),
                                CGPoint(x: px, y: py + size), CGPoint(x: px - size * 1.3, y: py)]),
                         with: .color(chipColor))
            }
        }
    }

    // MARK: Perfect drop

    private func drawPerfectBurst(_ ctx: inout GraphicsContext) {
        guard n > 1 else { return }
        let slab = slabs[n - 1]
        guard slab.perfect, slab.streak > 0 else { return }
        let life = M.clamp(f / 0.62)
        if life >= 1 { return }
        let fade = 1 - life
        let level = Double(n) * slabH
        let grow = M.easeOut(life)

        // Curtains of light rise from the four top edges.
        let back = pt(slab.x0, level, slab.z0), right = pt(slab.x1, level, slab.z0)
        let front = pt(slab.x1, level, slab.z1), left = pt(slab.x0, level, slab.z1)
        let rise = (0.55 + 0.75 * grow) * scale
        for (a, b, strength) in [(left, back, 0.20), (back, right, 0.16), (left, front, 0.50), (front, right, 0.36)] {
            let foot = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
            ctx.fill(shape([a, b, CGPoint(x: Double(b.x), y: Double(b.y) - rise), CGPoint(x: Double(a.x), y: Double(a.y) - rise)]),
                     with: .linearGradient(Gradient(colors: [Color.white.opacity(strength * fade), Color.white.opacity(0)]),
                                           startPoint: foot, endPoint: CGPoint(x: Double(foot.x), y: Double(foot.y) - rise)))
        }

        // Sparkles thrown out around the slab.
        var rng = TippyTowerRandom(seed: UInt64(5000 + n))
        let cx = (slab.x0 + slab.x1) / 2
        let cz = (slab.z0 + slab.z1) / 2
        let radius = (slab.x1 - slab.x0 + slab.z1 - slab.z0) / 4
        let tinted = TippyTowerPalette.slab(n - 1).mix(.white, 0.55).color(fade * 0.95)
        let plain = Color.white.opacity(fade * 0.95)
        let pulse = 0.55 + 0.45 * sin(.pi * Swift.min(1, life * 1.25 + 0.2))
        for k in 0..<14 {
            let turn = Double(k) / 14 * 2 * .pi + rng.range(-0.2, 0.2)
            let out = radius * 1.1 + rng.range(0.2, 1.0) * (0.25 + 0.75 * grow)
            let y = level + rng.range(-0.3, 1.1) * (0.4 + 0.6 * life)
            let size = rng.range(3.5, 9) * u * pulse
            ctx.fill(Self.sparkle(pt(cx + cos(turn) * out, y, cz + sin(turn) * out), size),
                     with: .color(k % 3 == 0 ? tinted : plain))
        }
    }

    // MARK: HUD

    /// The colour text casts as its shadow.
    var textShadow: Tint { sky.ambient.mix(.black, 0.3) }

    private func drawHUD(_ ctx: inout GraphicsContext) {
        let cx = W / 2
        let scoreY = H * 0.183
        // The number jumps a little on every landing.
        let pop = 1 + 0.20 * exp(-7 * f) * Swift.max(0, 1 - f * 1.5)
        let number = Text("\(score)").font(.system(size: 82 * u * pop, weight: .heavy, design: .rounded))
        ctx.draw(number.foregroundColor(textShadow.color(0.38)), at: CGPoint(x: cx, y: scoreY + 3.5 * u), anchor: .center)
        ctx.draw(number.foregroundColor(.white), at: CGPoint(x: cx, y: scoreY), anchor: .center)

        if let bestText {
            ctx.draw(Text(bestText).font(.system(size: 12.5 * u, weight: .bold, design: .rounded)).kerning(2.2 * u)
                        .foregroundColor(Color.white.opacity(0.72)),
                     at: CGPoint(x: cx, y: scoreY + 55 * u), anchor: .center)
        }

        guard n > 1, slabs[n - 1].perfect else { return }
        let life = M.clamp(f / calloutSpan)
        if life >= 1 { return }
        let streak = slabs[n - 1].streak
        let arrive = M.easeOut(M.clamp(f / 0.10))
        let alpha = arrive * (1 - M.smooth(0.6, 1, life))
        let size = 23 * u * (0.7 + 0.3 * arrive + 0.12 * exp(-10 * f))
        let callout = Text(streak > 1 ? "PERFECT ×\(streak)" : "PERFECT")
            .font(.system(size: size, weight: .black, design: .rounded)).italic().kerning(1.2 * u)
        let y = topY - (84 + 26 * life) * u
        let under = TippyTowerPalette.slab(n - 1).scaled(0.55).mix(sky.ambient, 0.4)
        ctx.draw(callout.foregroundColor(under.color(alpha * 0.9)), at: CGPoint(x: ox, y: y + 2.6 * u), anchor: .center)
        ctx.draw(callout.foregroundColor(Color.white.opacity(alpha)), at: CGPoint(x: ox, y: y), anchor: .center)
    }
}
