import SwiftUI

// Spiral Drop, the picture.
//
// One painter draws both the feed clip and the playable game, every frame, in a single canvas.
// The clip is a scripted round sampled at a phase (0 ... 1). The game hands the same painter a
// snapshot of its live round instead (see SpiralDropGame.swift).

public struct SpiralDropScene: View {
    public var phase: Double
    public var showHUD: Bool

    public init(phase: Double, showHUD: Bool) {
        self.phase = phase
        self.showHUD = showHUD
    }

    public var body: some View {
        Canvas(opaque: true, colorMode: .nonLinear, rendersAsynchronously: false) { context, size in
            guard size.width > 8, size.height > 8 else { return }
            let painter = SpiralDrop.Painter(size: size, shot: .clip(phase: phase), hud: showHUD)
            painter.drawClip(&context)
        }
    }
}

/// Home of everything Spiral Drop's two files share.
///
/// Heights are counted in floors (floor n sits at height n, larger is lower) and time in bounces:
/// one unit is the time the ball needs to bounce once on the spot.
enum SpiralDrop {
    /// How high one bounce takes the ball, in floors.
    static let bounceHeight = 0.85
    static let pointsPerFloor = 7
    /// Where the ball sits around the tower, in screen degrees. The tower turns under it.
    static let ballAngle = 120.0

    static func clamp(_ v: Double, _ lo: Double = 0, _ hi: Double = 1) -> Double {
        min(max(v, lo), hi)
    }

    static func blend(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }

    /// A smooth step from 0 at a to 1 at b. a may be the larger one, which turns the step around.
    static func ramp(_ a: Double, _ b: Double, _ v: Double) -> Double {
        let t = clamp((v - a) / (b - a))
        return t * t * (3 - 2 * t)
    }

    static func easeOut(_ v: Double) -> Double {
        let rest = 1 - clamp(v)
        return 1 - rest * rest * rest
    }

    static func fract(_ v: Double) -> Double { v - v.rounded(.down) }

    /// A tile index brought back into 0 ..< 12.
    static func tile(_ j: Int) -> Int { ((j % 12) + 12) % 12 }
}

// MARK: - Random numbers

extension SpiralDrop {
    /// SplitMix64: the same numbers for the same seed on every device, so a round can be replayed.
    struct Dice {
        private var state: UInt64

        init(seed: UInt64) {
            state = seed &* 0x9E3779B97F4A7C15 &+ 0xD1B54A32D192ED03
        }

        /// The next number in 0 ..< 1.
        mutating func unit() -> Double {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            z ^= z >> 31
            return Double(z >> 11) / 9007199254740992.0
        }

        mutating func between(_ lo: Double, _ hi: Double) -> Double { lo + (hi - lo) * unit() }

        /// A whole number in 0 ..< n.
        mutating func index(below n: Int) -> Int { min(n - 1, Int(unit() * Double(n))) }
    }
}

// MARK: - Colour

extension SpiralDrop {
    struct RGB {
        var r: Double
        var g: Double
        var b: Double

        init(_ r: Double, _ g: Double, _ b: Double) {
            self.r = r
            self.g = g
            self.b = b
        }

        init(hex: UInt32) {
            self.init(Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255)
        }

        static let white = RGB(1, 1, 1)

        func toward(_ other: RGB, _ t: Double) -> RGB {
            RGB(r + (other.r - r) * t, g + (other.g - g) * t, b + (other.b - b) * t)
        }

        /// Every channel multiplied by k, stopping at full.
        func gained(_ k: Double) -> RGB {
            RGB(min(1, r * k), min(1, g * k), min(1, b * k))
        }

        func color(_ alpha: Double = 1) -> Color {
            Color(.sRGB, red: r, green: g, blue: b, opacity: alpha)
        }

        /// The colour with its hue turned by some degrees and its saturation and brightness scaled.
        func recolored(hue degrees: Double, saturation: Double = 1, value: Double = 1) -> RGB {
            let hi = max(r, g, b)
            let spread = hi - min(r, g, b)
            var hue = 0.0
            if spread > 1e-9 {
                if hi == r {
                    hue = (g - b) / spread
                } else if hi == g {
                    hue = 2 + (b - r) / spread
                } else {
                    hue = 4 + (r - g) / spread
                }
                hue *= 60
            }
            hue = (hue + degrees).truncatingRemainder(dividingBy: 360)
            if hue < 0 { hue += 360 }
            let s = hi <= 0 ? 0 : min(1, spread / hi * saturation)
            let v = min(1, hi * value)
            func channel(_ n: Double) -> Double {
                let k = (n + hue / 60).truncatingRemainder(dividingBy: 6)
                return v - v * s * max(0, min(k, 4 - k, 1))
            }
            return RGB(channel(5), channel(3), channel(1))
        }
    }

    /// The water behind the tower: five bands from the surface down, the light pooling in it and its mist.
    struct Water {
        var surface: RGB
        var upper: RGB
        var middle: RGB
        var lower: RGB
        var bed: RGB
        var glow: RGB
        var mistNear: RGB
        var mistFar: RGB

        func remade(_ change: (RGB) -> RGB) -> Water {
            Water(surface: change(surface), upper: change(upper), middle: change(middle), lower: change(lower),
                  bed: change(bed), glow: change(glow), mistNear: change(mistNear), mistFar: change(mistFar))
        }

        func toward(_ other: Water, _ t: Double) -> Water {
            Water(surface: surface.toward(other.surface, t), upper: upper.toward(other.upper, t),
                  middle: middle.toward(other.middle, t), lower: lower.toward(other.lower, t),
                  bed: bed.toward(other.bed, t), glow: glow.toward(other.glow, t),
                  mistNear: mistNear.toward(other.mistNear, t), mistFar: mistFar.toward(other.mistFar, t))
        }
    }

    /// Everything that changes colour from level to level.
    struct Skin {
        var topHi: RGB
        var top: RGB
        var topLo: RGB
        var topSeam: RGB
        var rimHi: RGB
        var rim: RGB
        var rimLo: RGB
        var poleShine: RGB
        var poleLit: RGB
        var pole: RGB
        var poleLo: RGB
        var poleEdge: RGB
        var poleShadow: RGB
        var shallows: Water
        var depths: Water

        /// The water some way down a level: 0 near the surface, 1 in the deep.
        func water(depth: Double) -> Water { shallows.toward(depths, depth) }

        /// A new skin from this one: the water and the pole turn their hue by one angle, the rims by another.
        func variant(water: Double, waterSaturation: Double = 1, waterValue: Double = 1,
                     rim: Double, rimSaturation: Double = 1) -> Skin {
            func wet(_ c: RGB) -> RGB { c.recolored(hue: water, saturation: waterSaturation, value: waterValue) }
            func edge(_ c: RGB) -> RGB { c.recolored(hue: rim, saturation: rimSaturation) }
            var skin = self
            skin.rimHi = edge(rimHi)
            skin.rim = edge(self.rim)
            skin.rimLo = edge(rimLo)
            skin.poleShine = wet(poleShine)
            skin.poleLit = wet(poleLit)
            skin.pole = wet(pole)
            skin.poleLo = wet(poleLo)
            skin.poleEdge = wet(poleEdge)
            skin.poleShadow = wet(poleShadow)
            skin.shallows = shallows.remade(wet)
            skin.depths = depths.remade(wet)
            return skin
        }
    }

    enum Palette {
        // Red tiles: coral on top, crimson on the rim.
        static let hazardHi = RGB(hex: 0xFF9080)
        static let hazard = RGB(hex: 0xFF5A64)
        static let hazardLo = RGB(hex: 0xF23C56)
        static let hazardSeam = RGB(hex: 0xC92445)
        static let hazardEdge = RGB(hex: 0xFFC2B0)
        static let hazardRimHi = RGB(hex: 0xE8425C)
        static let hazardRim = RGB(hex: 0xC72A4B)
        static let hazardRimLo = RGB(hex: 0x8F1A3B)

        // The ball and the paint it leaves.
        static let ballShine = RGB(hex: 0xFCFFD8)
        static let ballLit = RGB(hex: 0xE0FF4E)
        static let ball = RGB(hex: 0xB2F01E)
        static let ballLo = RGB(hex: 0x62B80E)
        static let ballDeep = RGB(hex: 0x2F7C08)
        static let paint = RGB(hex: 0xB4EE2C)
        static let paintHi = RGB(hex: 0xE0FF78)

        static let warmShadow = RGB(hex: 0xC2581E)
        static let depthTint = RGB(hex: 0x1A4F7C)
        static let ink = RGB(hex: 0x05304A)
        static let scoreLo = RGB(hex: 0xD6FFF4)
        static let comboLo = RGB(hex: 0xFFD27A)

        /// The first level, and the clip: a lagoon with cream floors and orange rims.
        static let lagoon = Skin(
            topHi: RGB(hex: 0xFFFBEE), top: RGB(hex: 0xFFEFCB), topLo: RGB(hex: 0xFFDDA6), topSeam: RGB(hex: 0xE9B272),
            rimHi: RGB(hex: 0xFFBE58), rim: RGB(hex: 0xFF9632), rimLo: RGB(hex: 0xE0621A),
            poleShine: RGB(hex: 0x9AEAF2), poleLit: RGB(hex: 0x3FA9CE), pole: RGB(hex: 0x1F75AA),
            poleLo: RGB(hex: 0x124C84), poleEdge: RGB(hex: 0x3493C2), poleShadow: RGB(hex: 0x072452),
            shallows: Water(surface: RGB(hex: 0x0A5C7A), upper: RGB(hex: 0x16B4AA), middle: RGB(hex: 0x1195B2),
                            lower: RGB(hex: 0x0C68A6), bed: RGB(hex: 0x073E7C), glow: RGB(hex: 0x8CFBE0),
                            mistNear: RGB(hex: 0x1CA2BA), mistFar: RGB(hex: 0x1280B0)),
            depths: Water(surface: RGB(hex: 0x073A62), upper: RGB(hex: 0x0D82A4), middle: RGB(hex: 0x0A62A0),
                          lower: RGB(hex: 0x083F88), bed: RGB(hex: 0x04225A), glow: RGB(hex: 0x58DCEC),
                          mistNear: RGB(hex: 0x1483B4), mistFar: RGB(hex: 0x0C62A4)))

        /// One skin per level, in order, then round again.
        static let skins: [Skin] = [
            lagoon,
            lagoon.variant(water: 58, waterSaturation: 0.92, rim: 148, rimSaturation: 0.86),                     // violet water, teal rims
            lagoon.variant(water: 24, waterValue: 0.94, rim: 20),                                                // blue water, gold rims
            lagoon.variant(water: -22, waterSaturation: 0.9, waterValue: 0.95, rim: 232, rimSaturation: 0.72),   // green water, violet rims
            lagoon.variant(water: 96, waterSaturation: 0.82, waterValue: 0.96, rim: 176, rimSaturation: 0.8)     // plum water, blue rims
        ]
    }
}

// MARK: - What the painter is given

extension SpiralDrop {
    enum Tile {
        case solid, hazard, hole
        /// The floor that ends a level wears the ball's own colour.
        case finish
    }

    struct Floor {
        /// Twelve tiles of 30 degrees each.
        var tiles: [Tile]
        /// The floor's own turn on top of the tower's, in degrees.
        var twist = 0.0
        /// Index into Palette.skins.
        var skin = 0
        /// When the ball went through it. Infinity while it is whole.
        var brokenAt = Double.infinity
        /// Its place in the run of floors broken in one fall: 1 for the first.
        var chain = 1
        var points = 0
    }

    /// A dab of paint where the ball touched the floor it is on.
    struct Mark {
        var slot: Double
        var age: Double
        var power: Int
        var id: Int
    }

    /// The ball, the camera and the score at one moment.
    struct Ball {
        /// Height of the ball's underside.
        var height = 0.0
        var camera = 0.0
        /// Positive is down.
        var speed = 0.0
        /// Counts the landings so far. -1 before the first.
        var visit = -1
        /// The floor the ball last touched. -1 before the first touch.
        var restFloor = -1
        /// The first floor that is still whole.
        var nextFloor = 0
        var falling = false
        /// The height the current fall began at.
        var fallStart = 0.0
        /// Floors this fall goes through in a row, once it is known to be a combo. Otherwise 0.
        var fallFloors = 0
        /// Floors broken so far in this fall.
        var chain = 0
        var sinceTouch = 99.0
        /// 0 for the landing on a floor, then 1, 2 ... for each bounce there.
        var touchIndex = 0
        /// How hard the last touch was: 0 a bounce, 1 a landing, more after a combo.
        var impact = 0
        var marks: [Mark] = []
        var sinceLanding = 99.0
        /// The combo the ball landed with.
        var landedChain = 0
        var sinceBreak = 99.0
        var score = 0
        var hidden = false
    }

    /// One frame's worth of everything.
    struct Shot {
        var ball = Ball()
        var time = 0.0
        /// Slow drift for the bubbles and the light, about 0 ... 1 over a clip.
        var drift = 0.0
        /// The tower's turn in degrees.
        var turn = SpiralDrop.ballAngle
        var floors: [Floor] = []
        /// The floor number of the first entry in floors.
        var firstFloor = 0
        /// The water blends from one skin and depth to another when the level changes.
        var skinFrom = 0
        var depthFrom = 0.0
        var skinTo = 0
        var depthTo = 0.0
        var skinBlend = 0.0
        var level = 4
        var levelProgress = 0.0
        var sinceLevelUp = 99.0
        /// Sideways shake of the tower, in scene units.
        var shake = 0.0

        static func clip(phase: Double) -> Shot {
            let clip = Clip.shared
            var shot = Shot()
            shot.drift = clamp(phase)
            shot.time = clip.time(at: shot.drift)
            let slot = clip.read(at: shot.time, into: &shot.ball)
            shot.turn = SpiralDrop.ballAngle - slot * 30
            shot.floors = clip.floors
            shot.depthFrom = ramp(0, 1, shot.ball.camera / 16)
            shot.depthTo = shot.depthFrom
            shot.levelProgress = clamp((shot.ball.height + 0.9) / 20, 0.03, 1)
            return shot
        }
    }
}

// MARK: - The clip

extension SpiralDrop {
    /// The scripted round the feed shows: nine landings down seventeen floors, with two long combos.
    struct Clip {
        /// One stop on a floor: land, bounce some more times while the tower turns a few tiles,
        /// then drop through one or more floors in a row.
        struct Visit {
            var floor: Int
            var hops: Int
            var drop: Int
            var shift: Int
            var landAt = 0.0
            var peakAt = 0.0
            var leaveAt = 0.0
            var slotFrom = 0.0
            var slotTo = 0.0
        }

        static let shared = Clip()

        private(set) var visits: [Visit] = []
        private(set) var floors: [Floor] = []
        private var keys: [(phase: Double, time: Double)] = []

        /// Time from the top of a bounce down through a number of floors.
        static func dropTime(_ count: Int) -> Double {
            0.5 * ((bounceHeight + Double(count)) / bounceHeight).squareRoot()
        }

        init() {
            let script: [(floor: Int, hops: Int, drop: Int, shift: Int)] = [
                (0, 0, 1, 2), (1, 2, 1, -4), (2, 2, 1, 3), (3, 1, 4, -3), (7, 1, 1, 4),
                (8, 1, 2, -2), (10, 1, 5, 3), (15, 2, 1, -4), (16, 8, 1, 3)
            ]
            var clock = 0.5
            var slot = 0.0
            for step in script {
                var visit = Visit(floor: step.floor, hops: step.hops, drop: step.drop, shift: step.shift)
                visit.landAt = clock
                visit.peakAt = clock + Double(step.hops) + 0.5
                visit.leaveAt = visit.peakAt + Self.dropTime(step.drop)
                visit.slotFrom = slot
                slot += Double(step.shift)
                visit.slotTo = slot
                clock = visit.leaveAt
                visits.append(visit)
            }

            // Where each floor's hole is, and how far the tower turned to get there from the floor above.
            let count = 40
            var hole = [Int](repeating: 0, count: count)
            var shift = [Int](repeating: 0, count: count)
            var brokenAt = [Double](repeating: .infinity, count: count)
            var chain = [Int](repeating: 1, count: count)
            var scripted = 0
            for visit in visits {
                let span = bounceHeight + Double(visit.drop)
                for i in 0..<visit.drop {
                    let n = visit.floor + i
                    hole[n] = Int(visit.slotTo.rounded())
                    shift[n] = i == 0 ? visit.shift : 0
                    // a floor goes a little after the ball's underside reaches it
                    let part = ((Double(i) + 0.55 + bounceHeight) / span).squareRoot()
                    brokenAt[n] = visit.peakAt + Self.dropTime(visit.drop) * part
                    chain[n] = i + 1
                    scripted = n + 1
                }
            }
            // The floors below the script are only ever seen from above.
            let wander = [-3, 4, -2, 3, -4, 2]
            var at = hole[scripted - 1]
            for n in scripted..<count {
                let step = wander[(n - scripted) % wander.count]
                at += step
                hole[n] = at
                shift[n] = step
            }

            // Red tiles, counted along the part of each floor the ball never has to cross.
            let reds: [[Int]] = [
                [0, 1, 5], [0, 1, 3], [1, 2, 5], [0, 4, 5], [1, 2, 6], [0, 4, 5, 8],
                [0, 7, 8], [0, 3, 4], [0, 3, 4, 7], [1, 5, 6], [0, 1, 4], [2, 6, 7],
                [0, 1, 5], [3, 4, 8], [1, 2, 6, 9], [0, 1, 4], [1, 2, 5]
            ]
            for n in 0..<count {
                var places: [Int]
                if n < reds.count {
                    places = reds[n]
                } else {
                    var dice = Dice(seed: UInt64(n) &* 977 &+ 13)
                    let pair = Int(dice.between(0, 2))
                    let single = 3 + Int(dice.between(0, 2))
                    places = [pair, pair + 1, single]
                    if dice.unit() > 0.5 { places.append(single + 1) }
                }
                floors.append(Floor(tiles: Self.layout(hole: hole[n], shift: shift[n], reds: places),
                                    brokenAt: brokenAt[n], chain: chain[n], points: pointsPerFloor * chain[n]))
            }

            // Phase to time, pinned so the stills at 0.15, 0.5 and 0.85 land on good moments:
            // a bounce, the middle of the first long combo and a hard landing.
            let bounce = visits[1].landAt + 1.2
            let combo = visits[3].peakAt + 0.919 * Self.dropTime(4)
            let landing = visits[7].landAt + 0.2
            keys = [(0, 0), (0.15, bounce), (0.5, combo), (0.85, landing), (1, landing + 3.2)]
        }

        /// A floor with a hole two tiles wide ending at the given tile. The tower turned by shift tiles to
        /// bring the hole under the ball, so the red tiles go on the far side of it.
        static func layout(hole: Int, shift: Int, reds: [Int]) -> [Tile] {
            var tiles = [Tile](repeating: .solid, count: 12)
            tiles[tile(hole - 1)] = .hole
            tiles[tile(hole)] = .hole
            let room = 10 - abs(shift)
            for place in reds where place < room {
                tiles[tile(shift >= 0 ? hole + 1 + place : hole - 2 - place)] = .hazard
            }
            return tiles
        }

        func time(at phase: Double) -> Double {
            let p = clamp(phase)
            for (from, to) in zip(keys, keys.dropFirst()) where p <= to.phase {
                return from.time + (to.time - from.time) * (p - from.phase) / (to.phase - from.phase)
            }
            return keys[keys.count - 1].time
        }

        /// Which tile of the floor is under the ball at a time during a visit. Not a whole number while the tower turns.
        func slot(_ index: Int, at t: Double) -> Double {
            let visit = visits[index]
            let travel = visit.slotTo - visit.slotFrom
            let lastHop = visit.landAt + Double(visit.hops)
            // the turn is over as the ball dips below the floor it is leaving
            let dip = ((bounceHeight - 0.12) / (bounceHeight + Double(visit.drop))).squareRoot()
            let turnEnd = visit.peakAt + Self.dropTime(visit.drop) * dip
            // with bounces to fill, part of the turn is spread over them and the rest saved for the last one
            var early = 0.0
            if visit.hops > 0 { early = min(0.6, max(0, 1 - 1.6 / max(abs(travel), 0.001))) }
            var done = 1.0
            if t <= visit.landAt {
                done = 0
            } else if t <= lastHop {
                done = early * ramp(0, 1, (t - visit.landAt) / (lastHop - visit.landAt))
            } else if t < turnEnd {
                done = early + (1 - early) * ramp(0, 1, (t - lastHop) / (turnEnd - lastHop))
            }
            return visit.slotFrom + travel * done
        }

        /// Fills in the ball for a time and returns the tile under it.
        func read(at t: Double, into ball: inout Ball) -> Double {
            let hop = bounceHeight
            for (n, floor) in floors.enumerated() {
                guard floor.brokenAt <= t else { break }
                ball.nextFloor = n + 1
                ball.score += floor.points
                ball.sinceBreak = t - floor.brokenAt
            }

            // the opening: the ball comes down onto the first floor
            let opening = visits[0]
            if t < opening.landAt {
                let part = clamp(t / opening.landAt)
                ball.fallStart = Double(opening.floor) - hop
                ball.height = ball.fallStart + hop * part * part
                ball.speed = 2 * hop * part / opening.landAt
                ball.camera = Double(opening.floor)
                ball.falling = true
                return opening.slotFrom
            }

            let index = visits.firstIndex { t < $0.leaveAt } ?? visits.count - 1
            let visit = visits[index]
            let level = Double(visit.floor)
            let now = min(t, visit.leaveAt - 1e-6)
            let arrivedWith = index > 0 ? visits[index - 1].drop : 0
            let landingPower = index > 0 ? arrivedWith : 1
            ball.visit = index
            ball.restFloor = visit.floor
            ball.sinceLanding = now - visit.landAt
            ball.landedChain = arrivedWith

            if now < visit.peakAt {
                let since = now - visit.landAt
                let bounces = Int(since)
                let part = since - Double(bounces)
                ball.height = level - hop * 4 * part * (1 - part)
                ball.speed = -hop * 4 * (1 - 2 * part)
                // the camera trails a long drop and settles just after the landing
                ball.camera = level - 0.14 * Double(arrivedWith) * exp(-since * 5)
                ball.sinceTouch = part
                ball.touchIndex = bounces
                ball.impact = bounces == 0 ? landingPower : 0
            } else {
                let length = Self.dropTime(visit.drop)
                let part = (now - visit.peakAt) / length
                let span = hop + Double(visit.drop)
                ball.fallStart = level - hop
                ball.height = ball.fallStart + span * part * part
                ball.speed = 2 * span * part / length
                ball.camera = level + Double(visit.drop) * 0.86 * pow(part, 2.2)
                ball.falling = true
                ball.fallFloors = visit.drop
                ball.sinceTouch = 0.5 + (now - visit.peakAt)
                ball.touchIndex = visit.hops
                for n in visit.floor..<(visit.floor + visit.drop) where floors[n].brokenAt <= t {
                    ball.chain += 1
                }
            }

            if t < floors[visit.floor].brokenAt {
                let touches = min(visit.hops, Int(max(0, now - visit.landAt)))
                for k in 0...touches {
                    let at = visit.landAt + Double(k)
                    ball.marks.append(Mark(slot: slot(index, at: at), age: now - at,
                                           power: k == 0 ? landingPower : 0, id: k))
                }
            }
            return slot(index, at: now)
        }
    }
}

// MARK: - Painter

extension SpiralDrop {
    /// Draws one frame. Made fresh for every frame from the canvas size and a shot.
    struct Painter {
        /// Where a height on the tower lands on screen, and how big and how flat things are there.
        struct Lens {
            var y: Double
            var scale: Double
            var squash: Double
        }

        /// A floor, or a piece of one, on screen: a squashed ring with a rim hanging below it.
        struct Disc {
            var cx: Double
            var cy: Double
            var outer: Double
            var inner: Double
            var squash: Double
            var rim: Double

            func point(_ radius: Double, _ degrees: Double) -> CGPoint {
                let a = degrees * .pi / 180
                return CGPoint(x: cx + radius * cos(a), y: cy + radius * squash * sin(a))
            }
        }

        /// Neighbouring tiles of one kind, in screen degrees.
        struct Span {
            var tile: Tile
            var from: Double
            var to: Double
            /// A hole lies before it, or after it. There the floor shows a cut face.
            var openFrom: Bool
            var openTo: Bool
        }

        struct Material {
            var topHi, top, topLo, seam, edge, rimHi, rim, rimLo: RGB
        }

        /// How far something has sunk into the colour of the water.
        struct Mist {
            var amount: Double
            var dim: Double
            var tint: RGB
        }

        /// The materials of one floor, worked out once and used for every face of it.
        struct Looks {
            let solid: Material
            let hazard: Material
            let finish: Material

            init(skin: Skin, mist: Mist) {
                func sunk(_ c: RGB) -> RGB { c.toward(Palette.depthTint, mist.dim).toward(mist.tint, mist.amount) }
                // red pales toward cream before it sinks, so far red tiles do not turn to mud
                func red(_ c: RGB) -> RGB { sunk(c.toward(Palette.lagoon.top, 0.6 * mist.amount)) }
                solid = Material(topHi: sunk(skin.topHi), top: sunk(skin.top), topLo: sunk(skin.topLo),
                                 seam: sunk(skin.topSeam), edge: sunk(skin.topHi),
                                 rimHi: sunk(skin.rimHi), rim: sunk(skin.rim), rimLo: sunk(skin.rimLo))
                hazard = Material(topHi: red(Palette.hazardHi), top: red(Palette.hazard), topLo: red(Palette.hazardLo),
                                  seam: red(Palette.hazardSeam), edge: red(Palette.hazardEdge),
                                  rimHi: red(Palette.hazardRimHi), rim: red(Palette.hazardRim),
                                  rimLo: red(Palette.hazardRimLo))
                finish = Material(topHi: sunk(Palette.paintHi), top: sunk(Palette.paint), topLo: sunk(Palette.ball),
                                  seam: sunk(Palette.ballLo), edge: sunk(Palette.ballShine),
                                  rimHi: sunk(Palette.ball), rim: sunk(Palette.ballLo), rimLo: sunk(Palette.ballDeep))
            }

            subscript(tile: Tile) -> Material {
                switch tile {
                case .hazard: return hazard
                case .finish: return finish
                default: return solid
                }
            }
        }

        /// A piece of a broken floor in flight.
        struct Shard {
            var front: Bool
            var disc: Disc
            var span: Span
            var alpha: Double
            var looks: Looks
        }

        static let perspective = 0.065
        static let towerTop = -0.5
        static let shardLife = 0.8

        let width: Double
        let height: Double
        /// Points per scene unit. The scene is laid out for a 402 by 640 frame.
        let unit: Double
        let shot: Shot
        let ball: Ball
        let hud: Bool

        let centerX: Double
        /// Screen height of whatever is level with the camera.
        let eyeY: Double
        let hudY: Double
        let floorGap: Double
        let floorR: Double
        let poleR: Double
        let rimHeight: Double
        let ballR: Double
        /// Distance of the ball from the tower's axis.
        let trackR: Double
        let water: Water

        init(size: CGSize, shot: Shot, hud: Bool) {
            width = Double(size.width)
            height = Double(size.height)
            unit = min(width / 402, height / 640)
            self.shot = shot
            self.hud = hud
            ball = shot.ball
            centerX = width * 0.5 + shot.shake * unit
            eyeY = height * 0.445
            hudY = max(eyeY - 228 * unit, 36 * unit)
            floorGap = 88 * unit
            floorR = 132 * unit
            poleR = 25 * unit
            rimHeight = 18 * unit
            ballR = 19 * unit
            trackR = 80 * unit
            let before = Palette.skins[shot.skinFrom].water(depth: shot.depthFrom)
            let after = Palette.skins[shot.skinTo].water(depth: shot.depthTo)
            water = before.toward(after, shot.skinBlend)
        }

        // MARK: Frames

        /// The clip: the world, and the score on top when asked for.
        func drawClip(_ ctx: inout GraphicsContext) {
            drawWorld(&ctx)
            guard hud else { return }
            drawCallouts(&ctx)
            drawScore(&ctx)
        }

        /// Everything under the score, back to front.
        func drawWorld(_ ctx: inout GraphicsContext) {
            let shards = flyingShards()
            drawWater(&ctx)
            drawShards(&ctx, shards, front: false)
            drawTower(&ctx)
            drawRush(&ctx)
            drawShards(&ctx, shards, front: true)
            drawPunches(&ctx)
            drawTrail(&ctx)
            drawBall(&ctx)
            drawSpray(&ctx)
            drawVeil(&ctx)
        }

        // MARK: Geometry

        var floorEnd: Int { shot.firstFloor + shot.floors.count }

        func floor(_ n: Int) -> Floor { shot.floors[n - shot.firstFloor] }

        /// The view of a plane some floors below the camera (above it when negative).
        func lens(_ below: Double) -> Lens {
            let d = max(below, -10)
            let z = 1 + Self.perspective * d
            return Lens(y: eyeY + floorGap * log(z) / Self.perspective, scale: 1 / z,
                        squash: clamp(0.35 + 0.014 * d, 0.2, 0.5))
        }

        func disc(_ n: Int) -> Disc {
            let view = lens(Double(n) - ball.camera)
            return Disc(cx: centerX, cy: view.y, outer: floorR * view.scale, inner: poleR * view.scale,
                        squash: view.squash, rim: rimHeight * view.scale)
        }

        func mist(_ below: Double) -> Mist {
            Mist(amount: 0.86 * ramp(1, 9, below), dim: 0.10 * ramp(0.3, 5, below),
                 tint: water.mistNear.toward(water.mistFar, ramp(3, 9.5, below)))
        }

        /// The point of a plane the ball comes down on.
        func track(_ below: Double) -> (point: CGPoint, view: Lens) {
            let view = lens(below)
            let a = ballAngle * .pi / 180
            let reach = trackR * view.scale
            return (CGPoint(x: centerX + reach * cos(a), y: view.y + reach * view.squash * sin(a)), view)
        }

        /// Adds an arc of the disc's ellipse to the path, as straight pieces of four degrees or less.
        static func trace(_ path: inout Path, _ disc: Disc, radius: Double, from: Double, to: Double,
                          lowered: Double = 0, fresh: Bool) {
            let pieces = max(2, Int((abs(to - from) / 4).rounded(.up)))
            for i in 0...pieces {
                var p = disc.point(radius, from + (to - from) * Double(i) / Double(pieces))
                p.y += lowered
                if i == 0 && fresh {
                    path.move(to: p)
                } else {
                    path.addLine(to: p)
                }
            }
        }

        /// A slice of the disc's top from the outer edge in to a radius, or to the centre when that is 0.
        static func wedge(_ disc: Disc, from: Double, to: Double, inner: Double) -> Path {
            var path = Path()
            trace(&path, disc, radius: disc.outer, from: from, to: to, fresh: true)
            if inner > 0.01 {
                trace(&path, disc, radius: inner, from: to, to: from, fresh: false)
            } else {
                path.addLine(to: CGPoint(x: disc.cx, y: disc.cy))
            }
            path.closeSubpath()
            return path
        }

        static func oval(_ center: CGPoint, _ rx: Double, _ ry: Double) -> Path {
            Path(ellipseIn: CGRect(x: center.x - rx, y: center.y - ry, width: 2 * rx, height: 2 * ry))
        }

        /// A four-pointed glint.
        static func glint(_ c: CGPoint, _ r: Double) -> Path {
            let pinch = r * 0.26
            let tips = [CGPoint(x: c.x, y: c.y - r), CGPoint(x: c.x + r, y: c.y),
                        CGPoint(x: c.x, y: c.y + r), CGPoint(x: c.x - r, y: c.y)]
            let waists = [CGPoint(x: c.x + pinch, y: c.y - pinch), CGPoint(x: c.x + pinch, y: c.y + pinch),
                          CGPoint(x: c.x - pinch, y: c.y + pinch), CGPoint(x: c.x - pinch, y: c.y - pinch)]
            var path = Path()
            path.move(to: tips[0])
            for i in 0..<4 { path.addQuadCurve(to: tips[(i + 1) % 4], control: waists[i]) }
            path.closeSubpath()
            return path
        }

        /// Groups a floor's tiles into spans, leaving the holes out.
        static func spans(_ tiles: [Tile], turned: Double) -> [Span] {
            let n = tiles.count
            // start where the kind changes, so no span is split across the end of the list
            let first = (0..<n).first { tiles[$0] != tiles[($0 + n - 1) % n] } ?? 0
            var out: [Span] = []
            var walked = 0
            while walked < n {
                let j = (first + walked) % n
                let kind = tiles[j]
                var length = 1
                while walked + length < n, tiles[(j + length) % n] == kind { length += 1 }
                if kind != .hole {
                    let from = Double(j) * 30 + turned
                    out.append(Span(tile: kind, from: from, to: from + Double(length) * 30,
                                    openFrom: tiles[(j + n - 1) % n] == .hole,
                                    openTo: tiles[(j + length) % n] == .hole))
                }
                walked += length
            }
            return out
        }

        // MARK: Water

        func drawWater(_ ctx: inout GraphicsContext) {
            let bands = Gradient(stops: [
                .init(color: water.surface.color(), location: 0),
                .init(color: water.upper.color(), location: 0.30),
                .init(color: water.middle.color(), location: 0.56),
                .init(color: water.lower.color(), location: 0.78),
                .init(color: water.bed.color(), location: 1)
            ])
            ctx.fill(Path(CGRect(x: 0, y: 0, width: width, height: height)),
                     with: .linearGradient(bands, startPoint: .zero, endPoint: CGPoint(x: 0, y: height)))

            // two far towers, under the glow and the light so the water covers them
            drawFarTower(&ctx, x: -0.01 * width, size: 0.34, parallax: 0.34, seed: 11, strength: 0.8)
            drawFarTower(&ctx, x: 1.02 * width, size: 0.44, parallax: 0.46, seed: 29, strength: 1)

            // light pooling behind the action
            let pool = CGPoint(x: centerX, y: eyeY - 26 * unit)
            let reach = 350 * unit
            let glow = Gradient(stops: [
                .init(color: water.glow.color(0.60), location: 0),
                .init(color: water.glow.color(0.30), location: 0.42),
                .init(color: water.glow.color(0), location: 1)
            ])
            ctx.fill(Self.oval(pool, reach, reach),
                     with: .radialGradient(glow, center: pool, startRadius: 0, endRadius: reach))

            // slanted shafts of light from the surface
            let beams: [(x: Double, width: Double, alpha: Double)] = [
                (-0.10, 0.16, 0.10), (0.16, 0.07, 0.07), (0.34, 0.20, 0.09), (0.70, 0.10, 0.06), (0.92, 0.18, 0.07)
            ]
            let sway = 0.02 * sin(shot.drift * 2 * .pi)
            let foot = 0.86 * height
            let lean = 0.30 * height
            for (i, beam) in beams.enumerated() {
                let x = (beam.x + (i % 2 == 0 ? sway : -sway)) * width
                let w = beam.width * width
                var shaft = Path()
                shaft.move(to: CGPoint(x: x, y: -4))
                shaft.addLine(to: CGPoint(x: x + w, y: -4))
                shaft.addLine(to: CGPoint(x: x + 2.3 * w + lean, y: foot))
                shaft.addLine(to: CGPoint(x: x - 0.3 * w + lean, y: foot))
                shaft.closeSubpath()
                let light = Gradient(stops: [
                    .init(color: Color.white.opacity(beam.alpha * 1.25), location: 0),
                    .init(color: water.glow.color(beam.alpha * 0.7), location: 0.45),
                    .init(color: water.glow.color(0), location: 1)
                ])
                ctx.fill(shaft, with: .linearGradient(light, startPoint: CGPoint(x: x, y: 0),
                                                      endPoint: CGPoint(x: x + lean, y: foot)))
            }

            drawBubbles(&ctx)

            // the deep darkens the water behind the tower, not the tower
            let from = 0.60 * height
            let dark = Gradient(colors: [water.bed.color(0), water.bed.toward(Palette.ink, 0.3).color(0.55)])
            ctx.fill(Path(CGRect(x: 0, y: from, width: width, height: height - from)),
                     with: .linearGradient(dark, startPoint: CGPoint(x: 0, y: from), endPoint: CGPoint(x: 0, y: height)))
        }

        /// The colour of the plain water at a screen height.
        func waterColor(at y: Double) -> RGB {
            let f = clamp(y / height)
            if f <= 0.30 { return water.surface.toward(water.upper, f / 0.30) }
            if f <= 0.56 { return water.upper.toward(water.middle, (f - 0.30) / 0.26) }
            if f <= 0.78 { return water.middle.toward(water.lower, (f - 0.56) / 0.22) }
            return water.lower.toward(water.bed, (f - 0.78) / 0.22)
        }

        /// A tower far away: flat shapes only a shade off the water, to give depth without detail.
        func drawFarTower(_ ctx: inout GraphicsContext, x: Double, size: Double, parallax: Double,
                          seed: UInt64, strength: Double) {
            let gap = floorGap * size * 1.15
            let pole = poleR * size
            let rim = rimHeight * size
            let squash = 0.34
            let scroll = ball.camera * gap * parallax + 0.37 * gap
            let passed = Int((scroll / gap).rounded(.down))
            let shift = scroll - Double(passed) * gap
            let topTone = water.glow.toward(.white, 0.35)
            let rimTone = water.lower.toward(Palette.ink, 0.35)
            let poleTone = water.middle.toward(Palette.ink, 0.30)

            // bottom up, so nearer floors cover the ones behind
            for row in stride(from: Int(height / gap) + 2, through: -1, by: -1) {
                let y = Double(row) * gap - shift
                let lowFade = 0.35 + 0.65 * ramp(height * 0.95, height * 0.40, y)
                let show = strength * lowFade * ramp(0.02 * height, 0.24 * height, y)
                guard show > 0.02 else { continue }
                var dice = Dice(seed: seed &+ UInt64(row + passed + 400) &* 7919)
                let notch = dice.between(0, 360) + shot.turn * 0.5
                let r = floorR * size * dice.between(0.82, 1.0)
                let here = waterColor(at: y)
                let tint = 0.20 * show
                let far = Disc(cx: x, cy: y, outer: r, inner: pole, squash: squash, rim: rim)

                var band = Path()
                Self.trace(&band, far, radius: r, from: 0, to: 180, fresh: true)
                Self.trace(&band, far, radius: r, from: 180, to: 0, lowered: rim, fresh: false)
                band.closeSubpath()
                ctx.fill(band, with: .color(here.toward(rimTone, tint).color()))
                ctx.fill(Self.oval(CGPoint(x: x, y: y), r, r * squash), with: .color(here.toward(topTone, tint).color()))
                ctx.fill(Self.wedge(far, from: notch, to: notch + 60, inner: 0),
                         with: .color(here.toward(topTone.toward(rimTone, 0.55), tint).color()))
                let poleTop = y - gap + r * squash + rim
                ctx.fill(Path(CGRect(x: x - pole, y: poleTop, width: 2 * pole, height: y - poleTop)),
                         with: .color(waterColor(at: y - gap * 0.4).toward(poleTone, tint).color()))
                ctx.fill(Self.oval(CGPoint(x: x, y: y), pole, pole * squash),
                         with: .color(here.toward(poleTone, tint).color()))
            }
        }

        func drawBubbles(_ ctx: inout GraphicsContext) {
            var dice = Dice(seed: 4242)
            let loop = height * 1.25
            let small = water.glow.toward(.white, 0.5)
            for i in 0..<44 {
                let column = dice.unit()
                let start = dice.unit()
                let size = dice.between(0.9, 4.2) * unit
                let nearness = dice.between(0.25, 1.0)
                let alpha = dice.between(0.12, 0.42)
                let wobble = dice.between(0, 6.28)
                let risen = ball.camera * floorGap * nearness / loop + shot.drift * 0.12 * nearness
                let y = fract(start - risen) * loop - 0.1 * height
                let x = column * width + sin(shot.drift * 2 * .pi + wobble) * 5 * unit
                // fewer distractions behind the tower
                let calm = abs(x - centerX) < floorR * 0.7 ? 0.55 : 1.0
                let c = CGPoint(x: x, y: y)
                if i % 5 == 0 {
                    // every fifth is a big hollow one with a highlight
                    let r = size * 2.6
                    let ring = Self.oval(c, r, r)
                    ctx.fill(ring, with: .color(Color.white.opacity(0.05 * calm)))
                    ctx.stroke(ring, with: .color(Color.white.opacity(0.20 * calm)), lineWidth: max(0.6, unit))
                    ctx.fill(Self.oval(CGPoint(x: x - r * 0.35, y: y - r * 0.35), r * 0.2, r * 0.2),
                             with: .color(Color.white.opacity(0.38 * calm)))
                } else {
                    ctx.fill(Self.oval(c, size, size), with: .color(small.color(alpha * calm)))
                }
            }
        }

        // MARK: Tower

        func drawTower(_ ctx: inout GraphicsContext) {
            let first = ball.nextFloor
            // floors are drawn down to the first one that starts below the screen
            var last = first
            while last < floorEnd - 2 {
                let view = lens(Double(last + 1) - ball.camera)
                if view.y - floorR * view.scale * view.squash > height + 24 * unit { break }
                last += 1
            }
            let spans = (first...last).map { n -> [Span] in
                let floor = self.floor(n)
                return Self.spans(floor.tiles, turned: shot.turn + floor.twist)
            }

            for n in stride(from: last, through: first, by: -1) {
                let below = Double(n) - ball.camera
                let disc = self.disc(n)
                let skin = Palette.skins[floor(n).skin]
                let fog = mist(below)
                let looks = Looks(skin: skin, mist: fog)
                let own = spans[n - first]

                for span in own { drawCuts(&ctx, disc, span, looks[span.tile], front: false) }
                drawPole(&ctx, from: below, to: below + 1, underFloor: true, skin)
                drawTops(&ctx, disc, own, looks)
                drawOnTop(&ctx, floor: n, disc, own, above: n > first ? spans[n - first - 1] : nil, fog)
                drawRims(&ctx, disc, own, looks)
            }

            let skin = first >= shot.firstFloor && first < floorEnd ? Palette.skins[floor(first).skin] : Palette.skins[0]
            let top = Self.towerTop - ball.camera
            drawPole(&ctx, from: max(top, -9.6), to: Double(first) - ball.camera, underFloor: false, skin)
            drawCap(&ctx)
        }

        /// A stretch of the pole between two heights (floors below the camera).
        func drawPole(_ ctx: inout GraphicsContext, from: Double, to: Double, underFloor: Bool, _ skin: Skin) {
            guard to > from else { return }
            let upper = lens(from)
            let lower = lens(to)

            // the sides bend with the perspective, so follow them in half-floor steps
            let steps = max(1, Int(((to - from) / 0.5).rounded(.up)))
            let views = (0...steps).map { lens(from + (to - from) * Double($0) / Double(steps)) }
            var shape = Path()
            shape.move(to: CGPoint(x: centerX - poleR * upper.scale, y: upper.y))
            for view in views { shape.addLine(to: CGPoint(x: centerX + poleR * view.scale, y: view.y)) }
            let foot = Disc(cx: centerX, cy: lower.y, outer: poleR * lower.scale, inner: 0, squash: lower.squash, rim: 0)
            Self.trace(&shape, foot, radius: foot.outer, from: 0, to: 180, fresh: false)
            for view in views.reversed() { shape.addLine(to: CGPoint(x: centerX - poleR * view.scale, y: view.y)) }
            shape.closeSubpath()

            let fog = mist((from + to) * 0.5)
            func misted(_ c: RGB) -> Color { c.toward(fog.tint, fog.amount).color() }
            let widest = poleR * max(upper.scale, lower.scale)
            let round = Gradient(stops: [
                .init(color: misted(skin.poleLit), location: 0),
                .init(color: misted(skin.poleShine), location: 0.17),
                .init(color: misted(skin.poleLit), location: 0.36),
                .init(color: misted(skin.pole), location: 0.64),
                .init(color: misted(skin.poleLo), location: 0.90),
                .init(color: misted(skin.poleEdge), location: 1)
            ])
            ctx.fill(shape, with: .linearGradient(round, startPoint: CGPoint(x: centerX - widest, y: 0),
                                                  endPoint: CGPoint(x: centerX + widest, y: 0)))
            guard underFloor else { return }

            var inside = ctx
            inside.clip(to: shape)
            let dark = skin.poleShadow.toward(fog.tint, fog.amount * 0.7)
            let box = Path(CGRect(x: centerX - widest - 1, y: upper.y, width: 2 * widest + 2,
                                  height: lower.y - upper.y + widest))
            // the floor above takes light off the whole stretch
            inside.fill(box, with: .linearGradient(Gradient(colors: [dark.color(0.34), dark.color(0)]),
                                                   startPoint: CGPoint(x: 0, y: upper.y),
                                                   endPoint: CGPoint(x: 0, y: upper.y + floorGap * upper.scale)))
            // and throws a hard shadow right under its rim
            let under = upper.y + (floorR * upper.squash + rimHeight) * upper.scale
            inside.fill(box, with: .linearGradient(Gradient(colors: [dark.color(0.58), dark.color(0)]),
                                                   startPoint: CGPoint(x: 0, y: under),
                                                   endPoint: CGPoint(x: 0, y: under + 28 * unit * upper.scale)))
        }

        /// The knob on top of the tower.
        func drawCap(_ ctx: inout GraphicsContext) {
            let below = Self.towerTop - ball.camera
            guard below > -9.5 else { return }
            let view = lens(below)
            guard view.y > -60 * unit else { return }
            let r = poleR * view.scale * 1.36
            let thickness = 10 * unit * view.scale
            let cap = Disc(cx: centerX, cy: view.y, outer: r, inner: 0, squash: view.squash, rim: thickness)
            let lagoon = Palette.lagoon

            var band = Path()
            Self.trace(&band, cap, radius: r, from: 0, to: 180, fresh: true)
            Self.trace(&band, cap, radius: r, from: 180, to: 0, lowered: thickness, fresh: false)
            band.closeSubpath()
            let side = Gradient(stops: [
                .init(color: lagoon.rimHi.color(), location: 0),
                .init(color: lagoon.rim.color(), location: 0.45),
                .init(color: lagoon.rimLo.color(), location: 1)
            ])
            ctx.fill(band, with: .linearGradient(side, startPoint: CGPoint(x: centerX - r, y: 0),
                                                 endPoint: CGPoint(x: centerX + r, y: 0)))

            let middle = CGPoint(x: centerX, y: view.y)
            let ry = r * view.squash
            let lid = Self.oval(middle, r, ry)
            ctx.fill(lid, with: .linearGradient(Gradient(colors: [lagoon.topHi.color(), lagoon.topLo.color()]),
                                                startPoint: CGPoint(x: centerX - r, y: view.y - ry),
                                                endPoint: CGPoint(x: centerX + r, y: view.y + ry)))
            ctx.stroke(lid, with: .color(lagoon.topHi.color(0.9)), lineWidth: max(0.6, 1.2 * unit))
            ctx.fill(Self.oval(CGPoint(x: centerX, y: view.y + 0.6 * unit), r * 0.46, ry * 0.46),
                     with: .color(lagoon.rim.color(0.9)))
            ctx.fill(Self.oval(CGPoint(x: centerX, y: view.y - 0.4 * unit), r * 0.40, ry * 0.40),
                     with: .color(lagoon.rimHi.color()))
        }

        // MARK: Floors

        /// The flat faces where a span ends at a hole. Those turned to the viewer on the far half of the
        /// floor are drawn before the pole (front: false), those on the near half after the rim.
        func drawCuts(_ ctx: inout GraphicsContext, _ disc: Disc, _ span: Span, _ look: Material, front: Bool) {
            if span.openFrom { drawCut(&ctx, disc, at: span.from, closing: false, look, front: front) }
            if span.openTo { drawCut(&ctx, disc, at: span.to, closing: true, look, front: front) }
        }

        func drawCut(_ ctx: inout GraphicsContext, _ disc: Disc, at degrees: Double, closing: Bool,
                     _ look: Material, front: Bool) {
            let a = degrees * .pi / 180
            // the face looks along the floor, away from its span
            let sideways = closing ? -sin(a) : sin(a)
            let toViewer = closing ? cos(a) : -cos(a)
            guard toViewer > 0.03, (sin(a) >= 0) == front else { return }
            let inner = disc.point(disc.inner, degrees)
            let outer = disc.point(disc.outer, degrees)
            var face = Path()
            face.move(to: inner)
            face.addLine(to: outer)
            face.addLine(to: CGPoint(x: outer.x, y: outer.y + disc.rim))
            face.addLine(to: CGPoint(x: inner.x, y: inner.y + disc.rim))
            face.closeSubpath()
            // lit from the left
            let lit = clamp(0.5 - 0.5 * sideways)
            let upper = look.rimLo.toward(look.rim, 0.15 + 0.75 * lit)
            let lower = upper.toward(look.rimLo.gained(0.72), 0.6)
            ctx.fill(face, with: .linearGradient(Gradient(colors: [upper.color(), lower.color()]),
                                                 startPoint: CGPoint(x: 0, y: min(inner.y, outer.y)),
                                                 endPoint: CGPoint(x: 0, y: max(inner.y, outer.y) + disc.rim)))
            var lip = Path()
            lip.move(to: inner)
            lip.addLine(to: outer)
            ctx.stroke(lip, with: .color(look.edge.color(0.85)), lineWidth: max(0.5, 1.1 * disc.outer / 132))
        }

        func drawTops(_ ctx: inout GraphicsContext, _ disc: Disc, _ spans: [Span], _ looks: Looks) {
            let hair = disc.outer / 132
            let lightFrom = CGPoint(x: disc.cx - disc.outer * 0.9, y: disc.cy - disc.outer * disc.squash)
            let lightTo = CGPoint(x: disc.cx + disc.outer * 0.9, y: disc.cy + disc.outer * disc.squash)
            // one fill per kind. Red goes last and a hair wide, to cover the joins with its neighbours.
            for kind in [Tile.solid, .finish, .hazard] {
                var faces = Path()
                let overlap = kind == .hazard ? 0.35 : 0
                for span in spans where span.tile == kind {
                    faces.addPath(Self.wedge(disc, from: span.from - (span.openFrom ? 0 : overlap),
                                             to: span.to + (span.openTo ? 0 : overlap), inner: disc.inner))
                }
                guard !faces.isEmpty else { continue }
                let look = looks[kind]
                let sheen = Gradient(stops: [
                    .init(color: look.topHi.color(), location: 0),
                    .init(color: look.top.color(), location: 0.5),
                    .init(color: look.topLo.color(), location: 1)
                ])
                ctx.fill(faces, with: .linearGradient(sheen, startPoint: lightFrom, endPoint: lightTo))
            }
            for span in spans {
                let look = looks[span.tile]
                let tiles = Int(((span.to - span.from) / 30).rounded())
                if tiles > 1 {
                    var seams = Path()
                    for i in 1..<tiles {
                        let a = span.from + Double(i) * 30
                        seams.move(to: disc.point(disc.inner, a))
                        seams.addLine(to: disc.point(disc.outer, a))
                    }
                    ctx.stroke(seams, with: .color(look.seam.color(0.42)), lineWidth: max(0.5, hair))
                }
                // a groove just inside the edge, and a bright lip on it
                var groove = Path()
                Self.trace(&groove, disc, radius: disc.outer * 0.90, from: span.from, to: span.to, fresh: true)
                ctx.stroke(groove, with: .color(look.seam.color(0.36)), lineWidth: max(0.5, 1.2 * hair))
                var lip = Path()
                Self.trace(&lip, disc, radius: disc.outer - 0.6 * hair, from: span.from, to: span.to, fresh: true)
                ctx.stroke(lip, with: .color(look.edge.color(0.95)), lineWidth: max(0.6, 1.5 * hair))
            }
        }

        /// The part of the rim that faces the viewer, and the cut faces on the near half.
        func drawRims(_ ctx: inout GraphicsContext, _ disc: Disc, _ spans: [Span], _ looks: Looks) {
            let hair = disc.outer / 132
            for span in spans {
                let look = looks[span.tile]
                let from = span.from - (span.from / 360).rounded(.down) * 360
                let to = from + (span.to - span.from)
                let padFrom = span.openFrom ? 0 : 0.3
                let padTo = span.openTo ? 0 : 0.3
                // the near half is 0 ... 180 degrees. A span that runs past 360 can reach it a second time.
                for lap in [0.0, 360.0] {
                    let a0 = max(from - padFrom, lap)
                    let a1 = min(to + padTo, lap + 180)
                    guard a1 - a0 >= 0.25 else { continue }
                    var band = Path()
                    Self.trace(&band, disc, radius: disc.outer, from: a0, to: a1, fresh: true)
                    Self.trace(&band, disc, radius: disc.outer, from: a1, to: a0, lowered: disc.rim, fresh: false)
                    band.closeSubpath()
                    let across = Gradient(stops: [
                        .init(color: look.rimHi.color(), location: 0),
                        .init(color: look.rim.color(), location: 0.42),
                        .init(color: look.rimLo.color(), location: 1)
                    ])
                    ctx.fill(band, with: .linearGradient(across, startPoint: CGPoint(x: disc.cx - disc.outer, y: 0),
                                                         endPoint: CGPoint(x: disc.cx + disc.outer, y: 0)))
                    var underside = Path()
                    Self.trace(&underside, disc, radius: disc.outer, from: a0, to: a1, lowered: disc.rim * 0.60, fresh: true)
                    Self.trace(&underside, disc, radius: disc.outer, from: a1, to: a0, lowered: disc.rim, fresh: false)
                    underside.closeSubpath()
                    ctx.fill(underside, with: .color(look.rimLo.gained(0.70).color(0.50)))
                    var lip = Path()
                    Self.trace(&lip, disc, radius: disc.outer, from: a0, to: a1, lowered: 0.5 * hair, fresh: true)
                    ctx.stroke(lip, with: .color(look.edge.color(0.9)), lineWidth: max(0.6, 1.5 * hair))
                }
                drawCuts(&ctx, disc, span, look, front: true)
            }
        }

        /// What lies on a floor's top: the shadow of the floor above, the dark around the pole and, on the
        /// floor the ball is over, its paint, the ring of its last touch and its shadow.
        func drawOnTop(_ ctx: inout GraphicsContext, floor n: Int, _ disc: Disc, _ spans: [Span],
                       above: [Span]?, _ fog: Mist) {
            var top = ctx
            var face = Path()
            for span in spans { face.addPath(Self.wedge(disc, from: span.from, to: span.to, inner: disc.inner)) }
            top.clip(to: face)
            let shadow = Palette.warmShadow.toward(fog.tint, fog.amount * 0.8)

            if let above {
                // the light comes from the front left, so the shadow falls right and back
                var cast = disc
                cast.cx += disc.outer * 0.30
                cast.cy -= disc.outer * disc.squash * 0.10
                var shape = Path()
                for span in above { shape.addPath(Self.wedge(cast, from: span.from, to: span.to, inner: 0)) }
                shape.addPath(Self.oval(CGPoint(x: cast.cx, y: cast.cy), disc.inner * 1.05, disc.inner * 1.05 * disc.squash))
                top.fill(shape, with: .color(shadow.color(0.30)))
            }

            var around = top
            around.translateBy(x: disc.cx, y: disc.cy)
            around.scaleBy(x: 1, y: disc.squash)
            let reach = disc.inner * 2.5
            let dark = Gradient(stops: [
                .init(color: shadow.color(0.46), location: 0),
                .init(color: shadow.color(0.40), location: 0.40),
                .init(color: shadow.color(0), location: 1)
            ])
            around.fill(Self.oval(.zero, reach, reach),
                        with: .radialGradient(dark, center: .zero, startRadius: 0, endRadius: reach))

            guard n == ball.nextFloor else { return }
            let size = disc.outer / floorR
            let turned = shot.turn + floor(n).twist

            if ball.restFloor == n {
                for mark in ball.marks {
                    let grow = 0.55 + 0.45 * easeOut(mark.age / 0.16)
                    let weight = mark.power >= 3 ? 1.5 : (mark.power == 2 ? 1.2 : 1.0)
                    let paint = splat(on: disc, at: mark.slot * 30 + turned, seed: UInt64(n * 53 + mark.id * 7 + 3),
                                      size: weight * grow * size)
                    top.fill(paint.body.offsetBy(dx: 0, dy: 1.6 * unit * size), with: .color(Palette.ballLo.color(0.75)))
                    top.fill(paint.body, with: .color(Palette.paint.color()))
                    top.fill(paint.shine, with: .color(Palette.paintHi.color(0.85)))
                }
                // a ring spreading from the last touch
                let life = ball.impact >= 2 ? 0.52 : 0.36
                if ball.sinceTouch < life, let last = ball.marks.last {
                    let part = ball.sinceTouch / life
                    let center = disc.point(trackR * size, last.slot * 30 + turned)
                    let push = 1 + 0.22 * Double(min(ball.impact, 5))
                    let r = ballR * size * (1.1 + 2.6 * push * easeOut(part))
                    let alpha = pow(1 - part, 1.3)
                    top.stroke(Self.oval(center, r, r * disc.squash), with: .color(Color.white.opacity(0.95 * alpha)),
                               lineWidth: max(0.8, (5.0 - 3.6 * part) * unit * size))
                    if ball.impact >= 2 {
                        let r2 = r * 0.62
                        top.stroke(Self.oval(center, r2, r2 * disc.squash), with: .color(Palette.paintHi.color(0.8 * alpha)),
                                   lineWidth: max(0.8, 3.0 * unit * size * (1 - part)))
                    }
                }
            }

            // the ball's shadow: wider, fainter and further right the higher the ball is
            let clearance = Double(n) - ball.height
            guard clearance > -0.05, !ball.hidden else { return }
            let up = max(0, clearance)
            let spot = track(Double(n) - ball.camera)
            let scale = spot.view.scale
            let r = ballR * scale * (1 + 0.55 * up)
            let tone = Palette.warmShadow.gained(0.75)
            let alpha = 0.62 * (1 - 0.5 * clamp(up / 0.85))
            var ground = top
            ground.translateBy(x: spot.point.x + up * floorGap * 0.26 * scale,
                               y: spot.point.y - up * floorGap * 0.08 * scale * spot.view.squash)
            ground.scaleBy(x: 1, y: spot.view.squash * 1.1)
            let soft = Gradient(stops: [
                .init(color: tone.color(alpha), location: 0),
                .init(color: tone.color(alpha * 0.85), location: 0.55),
                .init(color: Palette.warmShadow.color(0), location: 1)
            ])
            ground.fill(Self.oval(.zero, r, r), with: .radialGradient(soft, center: .zero, startRadius: 0, endRadius: r))
        }

        /// A blot of paint lying on a floor: a middle, eight lobes round it and a few flecks further out.
        func splat(on disc: Disc, at degrees: Double, seed: UInt64, size: Double) -> (body: Path, shine: Path) {
            var dice = Dice(seed: seed)
            let a = degrees * .pi / 180
            let reach = trackR * (disc.outer / floorR)
            let x = reach * cos(a)
            let z = reach * sin(a)
            let r = 14.5 * unit * size
            func blot(_ dx: Double, _ dz: Double, _ radius: Double) -> Path {
                Self.oval(CGPoint(x: disc.cx + x + dx, y: disc.cy + (z + dz) * disc.squash), radius, radius * disc.squash)
            }
            var body = blot(0, 0, r)
            for lobe in 0..<8 {
                let around = a + (Double(lobe) + dice.between(-0.28, 0.28)) / 8 * 2 * .pi
                let out = r * dice.between(0.62, 0.95)
                let radius = r * dice.between(0.30, 0.52)
                body.addPath(blot(cos(around) * out, sin(around) * out, radius))
            }
            for _ in 0..<7 {
                let around = dice.between(0, 2 * .pi)
                let out = r * dice.between(1.45, 2.25)
                let radius = r * dice.between(0.09, 0.22)
                body.addPath(blot(cos(around) * out, sin(around) * out, radius))
            }
            var shine = blot(-r * 0.26, -r * 0.34, r * 0.46)
            shine.addPath(blot(r * 0.36, -r * 0.50, r * 0.16))
            return (body, shine)
        }

        // MARK: Broken floors

        /// The pieces of every floor broken in the last moments, where they are now.
        func flyingShards() -> [Shard] {
            let next = ball.nextFloor
            let first = max(shot.firstFloor, next - 6)
            guard next > first else { return [] }
            var out: [Shard] = []
            for n in first..<next {
                let floor = self.floor(n)
                let age = shot.time - floor.brokenAt
                guard age >= 0, age < Self.shardLife else { continue }
                let part = age / Self.shardLife
                let view = lens(Double(n) - ball.camera)
                let turned = shot.turn + floor.twist
                let looks = Looks(skin: Palette.skins[floor.skin], mist: Mist(amount: 0, dim: 0, tint: water.mistNear))
                let tiles = floor.tiles
                var dice = Dice(seed: UInt64(n * 131 + 5))
                var j = 0
                while j < tiles.count {
                    let kind = tiles[j]
                    if kind == .hole {
                        j += 1
                        continue
                    }
                    // pieces are one tile wide or two
                    let wide = dice.unit() > 0.45 && j + 1 < tiles.count && tiles[j + 1] == kind
                    let sweep = wide ? 60.0 : 30.0
                    let middle = Double(j) * 30 + turned + sweep * 0.5
                    j += wide ? 2 : 1
                    let pace = dice.between(0.7, 1.35)
                    let hop = dice.between(0.12, 0.5)
                    let tumble = dice.between(-120, 120) * part
                    let tip = dice.between(-0.8, 0.95)

                    // thrown outward, up a little, then down
                    let a = middle * .pi / 180
                    let out_ = floorR * view.scale * (0.10 + 1.30 * pace * easeOut(part))
                    let rise = floorGap * view.scale * hop * sin(min(1, part * 1.5) * .pi)
                    let sink = floorGap * view.scale * 1.25 * part * part
                    let squash = clamp(view.squash * (1 + tip * ramp(0, 0.45, part)), 0.06, 0.70)
                    let outer = floorR * view.scale * (1 - 0.30 * part)
                    let inner = floorR * view.scale * blend(poleR / floorR, 0.44, ramp(0, 0.6, part))
                    let arm = (outer + inner) * 0.5
                    // each piece turns about its own middle, not about the tower
                    let pivot = CGPoint(x: centerX + cos(a) * (arm + out_),
                                        y: view.y + sin(a) * (arm + out_) * view.squash - rise + sink)
                    // pieces that stay in front of the tower go early
                    let aside = ramp(0.5 * floorR, 1.15 * floorR, abs(pivot.x - centerX))
                    let clear = blend(1, aside, ramp(0.06, 0.26, part))
                    let underScore = ramp(hudY + 78 * unit, hudY + 150 * unit, pivot.y)
                    let life = (1 - ramp(0.45, 1, part)) * clear * underScore
                    guard life > 0.03 else { continue }
                    // they shrink away and stay solid almost to the end
                    let shrink = 0.30 + 0.70 * pow(life, 0.6)
                    let facing = (middle + tumble) * .pi / 180
                    let disc = Disc(cx: pivot.x - cos(facing) * arm * shrink,
                                    cy: pivot.y - sin(facing) * arm * squash * shrink,
                                    outer: outer * shrink, inner: inner * shrink, squash: squash,
                                    rim: rimHeight * view.scale * (1 - 0.2 * part) * shrink)
                    let from = middle + tumble - sweep * 0.5
                    out.append(Shard(front: sin(a) >= 0, disc: disc,
                                     span: Span(tile: kind, from: from, to: from + sweep, openFrom: true, openTo: true),
                                     alpha: ramp(0, 0.30, life), looks: looks))
                }
            }
            return out
        }

        /// Pieces thrown toward the viewer are drawn over the tower, the others behind it.
        func drawShards(_ ctx: inout GraphicsContext, _ shards: [Shard], front: Bool) {
            for shard in shards where shard.front == front {
                if shard.alpha > 0.985 {
                    drawPiece(&ctx, shard)
                } else {
                    var faded = ctx
                    faded.opacity = shard.alpha
                    faded.drawLayer { layer in drawPiece(&layer, shard) }
                }
            }
        }

        func drawPiece(_ ctx: inout GraphicsContext, _ shard: Shard) {
            drawCuts(&ctx, shard.disc, shard.span, shard.looks[shard.span.tile], front: false)
            drawTops(&ctx, shard.disc, [shard.span], shard.looks)
            drawRims(&ctx, shard.disc, [shard.span], shard.looks)
        }

        /// A white ring left hanging for a moment where the ball went through a floor.
        func drawPunches(_ ctx: inout GraphicsContext) {
            let next = ball.nextFloor
            let first = max(shot.firstFloor, next - 4)
            guard next > first else { return }
            for n in first..<next {
                let age = shot.time - floor(n).brokenAt
                guard age >= 0, age < 0.34 else { continue }
                let part = age / 0.34
                let spot = track(Double(n) - ball.camera)
                let show = pow(1 - part, 1.5) * ramp(hudY + 70 * unit, hudY + 130 * unit, spot.point.y)
                guard show > 0.02 else { continue }
                let scale = spot.view.scale
                let r = ballR * scale * (1.2 + 2.3 * easeOut(part))
                let ring = Self.oval(CGPoint(x: spot.point.x, y: spot.point.y - ballR * scale * 0.3), r, r * spot.view.squash)
                ctx.fill(ring, with: .color(Color.white.opacity(0.16 * show)))
                ctx.stroke(ring, with: .color(Color.white.opacity(0.95 * show)),
                           lineWidth: max(0.8, (6.5 - 5 * part) * unit * scale))
            }
        }

        // MARK: Ball

        /// How much the ball glows: only during a combo, and more with every floor.
        var heat: Double {
            guard ball.falling, ball.fallFloors >= 2 else { return 0 }
            return clamp(0.35 + 0.3 * Double(ball.chain))
        }

        /// Lines rushing up past a fast fall.
        func drawRush(_ ctx: inout GraphicsContext) {
            guard ball.falling else { return }
            let power = ramp(2.5, 6.5, ball.speed)
            guard power > 0.02 else { return }
            var dice = Dice(seed: 808)
            for _ in 0..<11 {
                let x = centerX + dice.between(-1, 1) * 178 * unit
                let length = dice.between(34, 96) * unit * (0.5 + 0.5 * power)
                let pace = dice.between(1.6, 2.6)
                let along = fract(dice.unit() + shot.time * pace)
                let y = height * 0.82 - along * height * 0.74
                let alpha = power * dice.between(0.16, 0.36) * sin(along * .pi)
                let thickness = max(0.6, dice.between(1.2, 2.4) * unit)
                var line = Path()
                line.move(to: CGPoint(x: x, y: y))
                line.addLine(to: CGPoint(x: x, y: y + length))
                ctx.stroke(line, with: .color(Color.white.opacity(alpha)),
                           style: StrokeStyle(lineWidth: thickness, lineCap: .round))
            }
        }

        /// The streak a falling ball pulls behind it, and sparks off it during a combo.
        func drawTrail(_ ctx: inout GraphicsContext) {
            guard ball.falling, ball.speed > 1.6 else { return }
            let hot = heat
            let length = min(clamp(0.36 * (ball.speed - 1.6), 0, 2.7), ball.height - ball.fallStart)
            guard length > 0.08 else { return }

            // the ball's path from the tail (0) to the ball (14), and how wide the streak is at each step
            let steps = 14
            var spine: [CGPoint] = []
            var halfWidth: [Double] = []
            for i in 0...steps {
                let along = Double(i) / Double(steps)
                let spot = track(ball.height - length * (1 - along) - ball.camera)
                let r = ballR * spot.view.scale
                spine.append(CGPoint(x: spot.point.x, y: spot.point.y - r))
                halfWidth.append(r * (0.96 + 0.12 * hot) * pow(along, 0.62))
            }
            func ribbon(_ share: Double) -> Path {
                var path = Path()
                path.move(to: spine[0])
                for i in 1...steps { path.addLine(to: CGPoint(x: spine[i].x - halfWidth[i] * share, y: spine[i].y)) }
                for i in stride(from: steps, through: 1, by: -1) {
                    path.addLine(to: CGPoint(x: spine[i].x + halfWidth[i] * share, y: spine[i].y))
                }
                path.closeSubpath()
                return path
            }
            let tail = spine[0]
            let head = spine[steps]
            let power = ramp(1.6, 4.5, ball.speed)
            let green = Gradient(stops: [
                .init(color: Palette.ballLit.color(0), location: 0),
                .init(color: Palette.ballLit.color(0.42 * power), location: 0.45),
                .init(color: Palette.ball.color(0.95 * power), location: 1)
            ])
            ctx.fill(ribbon(1), with: .linearGradient(green, startPoint: tail, endPoint: head))
            let core = Gradient(stops: [
                .init(color: Palette.ballShine.color(0), location: 0),
                .init(color: Palette.ballShine.color(0.55 * power), location: 0.5),
                .init(color: Color.white.opacity((0.65 + 0.33 * hot) * power), location: 1)
            ])
            ctx.fill(ribbon(0.52), with: .linearGradient(core, startPoint: tail, endPoint: head))

            guard hot > 0.05 else { return }
            var dice = Dice(seed: 9090)
            for i in 0..<12 {
                let start = dice.unit()
                let age = fract(start + shot.time * dice.between(1.4, 2.4))
                let from = spine[min(steps, Int((1 - age) * Double(steps)))]
                let spread = ballR * (0.7 + 2.0 * age) * dice.between(0.7, 1.3)
                let r = dice.between(1.4, 3.4) * unit * (1 - 0.7 * age)
                let at = CGPoint(x: from.x + (i % 2 == 0 ? -spread : spread), y: from.y - age * 14 * unit)
                ctx.fill(Self.glint(at, r * 2.1), with: .color(Palette.ballShine.color(hot * (1 - age))))
            }
        }

        func drawBall(_ ctx: inout GraphicsContext) {
            guard !ball.hidden else { return }
            let spot = track(ball.height - ball.camera)
            let r = ballR * spot.view.scale

            // flat on a touch, long in flight
            var squash = 0.0
            var stretch = 0.0
            if ball.visit >= 0 && !ball.falling {
                squash = exp(-ball.sinceTouch * 16)
                stretch = 0.10 * clamp(abs(ball.speed) / 3.4) * (1 - squash)
            } else {
                stretch = 0.20 * clamp(ball.speed / 8)
            }
            let rx = r * (1 + 0.24 * squash - 0.55 * stretch)
            let ry = r * (1 - 0.30 * squash + stretch)
            let c = CGPoint(x: spot.point.x, y: spot.point.y - ry)

            let hot = heat
            let halo = r * (1.9 + 0.9 * hot)
            let aura = Gradient(stops: [
                .init(color: Palette.ballLit.color(0.22 + 0.40 * hot), location: 0),
                .init(color: Palette.ballLit.color(0.08 + 0.16 * hot), location: 0.5),
                .init(color: Palette.ballLit.color(0), location: 1)
            ])
            ctx.fill(Self.oval(c, halo, halo),
                     with: .radialGradient(aura, center: c, startRadius: r * 0.7, endRadius: halo))

            let body = Self.oval(c, rx, ry)
            let round = Gradient(stops: [
                .init(color: Palette.ballShine.color(), location: 0),
                .init(color: Palette.ballLit.color(), location: 0.20),
                .init(color: Palette.ball.color(), location: 0.50),
                .init(color: Palette.ballLo.color(), location: 0.82),
                .init(color: Palette.ballDeep.color(), location: 1)
            ])
            ctx.fill(body, with: .radialGradient(round, center: CGPoint(x: c.x - rx * 0.34, y: c.y - ry * 0.40),
                                                 startRadius: 0, endRadius: r * 1.46))

            // warm light off the floor below, cool light off the water around
            var inside = ctx
            inside.clip(to: body)
            let warmAt = CGPoint(x: c.x + rx * 0.10, y: c.y + ry * 1.10)
            let warmR = r * 0.92
            let warm = Gradient(colors: [Palette.lagoon.topHi.color(0.55), Palette.lagoon.topHi.color(0)])
            inside.fill(Self.oval(warmAt, warmR, warmR),
                        with: .radialGradient(warm, center: warmAt, startRadius: 0, endRadius: warmR))
            inside.stroke(Self.oval(CGPoint(x: c.x - rx * 0.10, y: c.y - ry * 0.10), rx * 1.04, ry * 1.04),
                          with: .color(water.glow.color(0.55)), lineWidth: max(0.6, 1.6 * unit))
            ctx.stroke(body, with: .color(Palette.ballDeep.color(0.55)), lineWidth: max(0.5, 1.1 * unit))

            var gloss = ctx
            gloss.translateBy(x: c.x - rx * 0.40, y: c.y - ry * 0.46)
            gloss.rotate(by: .degrees(-38))
            gloss.fill(Self.oval(.zero, r * 0.33, r * 0.18), with: .color(Color.white.opacity(0.96)))
            ctx.fill(Self.oval(CGPoint(x: c.x - rx * 0.02, y: c.y - ry * 0.70), r * 0.07, r * 0.07),
                     with: .color(Color.white.opacity(0.9)))
        }

        /// Drops of paint thrown up by a touch, and glints on a hard one.
        func drawSpray(_ ctx: inout GraphicsContext) {
            guard ball.visit >= 0, ball.restFloor >= 0, !ball.falling else { return }
            let hard = ball.impact >= 2
            let life = hard ? 0.66 : 0.5
            let age = ball.sinceTouch
            guard age < life else { return }
            let part = age / life
            let spot = track(Double(ball.restFloor) - ball.camera)
            let scale = spot.view.scale
            let power = Double(min(ball.impact, 5))
            var dice = Dice(seed: UInt64(ball.visit * 31 + ball.touchIndex * 7 + 1))
            for i in 0..<(9 + Int(power) * 3) {
                let around = dice.between(0, 2 * .pi)
                let outward = dice.between(0.7, 2.0) * floorGap * (1 + 0.14 * power)
                let upward = dice.between(1.5, 3.3) * floorGap * (1 + 0.10 * power)
                let size = dice.between(1.8, 4.6) * unit
                let up = upward * age - 3.9 * floorGap * age * age
                guard up >= 0 else { continue }
                let out_ = outward * age * (1 - 0.3 * part)
                let at = CGPoint(x: spot.point.x + cos(around) * out_ * scale,
                                 y: spot.point.y + sin(around) * out_ * scale * spot.view.squash - up * scale)
                let r = size * scale * (1 - 0.55 * part)
                let tone = i % 4 == 0 ? Palette.ballShine : Palette.ballLit
                ctx.fill(Self.oval(at, r, r * 1.12), with: .color(tone.color(1 - 0.5 * part * part)))
                ctx.fill(Self.oval(CGPoint(x: at.x - r * 0.3, y: at.y - r * 0.35), r * 0.32, r * 0.32),
                         with: .color(Color.white.opacity(0.8 * (1 - part))))
            }
            guard hard else { return }
            for _ in 0..<6 {
                let around = dice.between(0, 2 * .pi)
                let out_ = dice.between(44, 86) * unit * (0.55 + 0.45 * easeOut(part))
                let r = dice.between(4, 9) * unit * sin(min(1, part * 1.3 + 0.15) * .pi)
                let at = CGPoint(x: spot.point.x + cos(around) * out_, y: spot.point.y - 14 * unit + sin(around) * out_ * 0.55)
                ctx.fill(Self.glint(at, max(0, r)), with: .color(Color.white.opacity(0.95 * (1 - part))))
            }
        }

        // MARK: Over everything

        /// Dark water at the top, so the score and the app's buttons read, a little at the bottom, and a
        /// few big bubbles close to the lens at the sides.
        func drawVeil(_ ctx: inout GraphicsContext) {
            let end = hudY + (hud ? 92 : 44) * unit
            let over = Gradient(stops: [
                .init(color: water.surface.color(0.96), location: 0),
                .init(color: water.surface.color(0.84), location: 0.56),
                .init(color: water.surface.color(0.46), location: 0.80),
                .init(color: water.surface.color(0), location: 1)
            ])
            ctx.fill(Path(CGRect(x: 0, y: 0, width: width, height: end)),
                     with: .linearGradient(over, startPoint: .zero, endPoint: CGPoint(x: 0, y: end)))
            let from = 0.74 * height
            let under = Gradient(colors: [water.bed.color(0), water.bed.color(0.34)])
            ctx.fill(Path(CGRect(x: 0, y: from, width: width, height: height - from)),
                     with: .linearGradient(under, startPoint: CGPoint(x: 0, y: from), endPoint: CGPoint(x: 0, y: height)))

            var dice = Dice(seed: 606)
            let loop = height * 1.3
            for i in 0..<6 {
                let x = (i % 2 == 0 ? dice.between(0.02, 0.15) : dice.between(0.85, 0.98)) * width
                let r = dice.between(7, 15) * unit
                let nearness = dice.between(1.25, 1.7)
                let start = dice.unit()
                let y = fract(start - ball.camera * floorGap * nearness / loop - shot.drift * 0.3) * loop - 0.15 * height
                guard y > hudY + 110 * unit else { continue }
                let c = CGPoint(x: x + sin(shot.drift * 4 * .pi + Double(i)) * 4 * unit, y: y)
                let bubble = Self.oval(c, r, r)
                let glass = Gradient(colors: [Color.white.opacity(0.02), Color.white.opacity(0.16)])
                ctx.fill(bubble, with: .radialGradient(glass, center: c, startRadius: r * 0.4, endRadius: r))
                ctx.stroke(bubble, with: .color(Color.white.opacity(0.42)), lineWidth: max(0.6, 1.3 * unit))
                var shine = Path()
                shine.addArc(center: c, radius: r * 0.68, startAngle: .degrees(200), endAngle: .degrees(255), clockwise: false)
                ctx.stroke(shine, with: .color(Color.white.opacity(0.75)),
                           style: StrokeStyle(lineWidth: max(0.6, 1.8 * unit), lineCap: .round))
                ctx.fill(Self.oval(CGPoint(x: c.x + r * 0.34, y: c.y + r * 0.38), r * 0.10, r * 0.10),
                         with: .color(Color.white.opacity(0.55)))
            }
        }

        /// Heavy rounded text centred on a point. The outline and the soft shadow are the same text stamped round a circle.
        func write(_ ctx: inout GraphicsContext, _ string: String, size: Double, spacing: Double = 0, at point: CGPoint,
                   fill: GraphicsContext.Shading, outline: Color? = nil, outlineWidth: Double = 0,
                   shadow: Color? = nil, shadowDrop: Double = 0) {
            var text = ctx.resolve(Text(string).font(.system(size: size, weight: .black, design: .rounded)).kerning(spacing))
            if let shadow {
                text.shading = .color(shadow)
                if outlineWidth > 0 {
                    for i in 0..<10 {
                        let a = Double(i) / 10 * 2 * .pi
                        ctx.draw(text, at: CGPoint(x: point.x + cos(a) * outlineWidth,
                                                   y: point.y + sin(a) * outlineWidth + shadowDrop), anchor: .center)
                    }
                } else {
                    ctx.draw(text, at: CGPoint(x: point.x, y: point.y + shadowDrop), anchor: .center)
                }
            }
            if let outline, outlineWidth > 0 {
                text.shading = .color(outline)
                for i in 0..<14 {
                    let a = Double(i) / 14 * 2 * .pi
                    ctx.draw(text, at: CGPoint(x: point.x + cos(a) * outlineWidth, y: point.y + sin(a) * outlineWidth),
                             anchor: .center)
                }
            }
            text.shading = fill
            ctx.draw(text, at: point, anchor: .center)
        }

        /// The points each broken floor gave, rising beside the tower, and the combo counter.
        func drawCallouts(_ ctx: inout GraphicsContext) {
            let next = ball.nextFloor
            let first = max(shot.firstFloor, next - 5)
            if next > first {
                for n in first..<next {
                    let broken = floor(n)
                    let age = shot.time - broken.brokenAt
                    guard age >= 0, age < 0.9 else { continue }
                    let part = age / 0.9
                    let y = lens(Double(n) - ball.camera).y + 10 * unit - 46 * unit * easeOut(part)
                    let show = (1 - ramp(0.55, 1, part)) * ramp(hudY + 40 * unit, hudY + 96 * unit, y)
                    guard show > 0.03 else { continue }
                    let size = (17 + 2.0 * Double(min(broken.chain, 8))) * unit * (0.7 + 0.3 * easeOut(part * 5))
                    var faded = ctx
                    faded.opacity = show
                    write(&faded, "+\(broken.points)", size: size, at: CGPoint(x: centerX - 118 * unit, y: y),
                          fill: .color(.white), outline: Palette.ink.color(0.9), outlineWidth: 1.6 * unit,
                          shadow: Palette.ink.color(0.5), shadowDrop: 2.2 * unit)
                }
            }

            // the counter runs during a combo and lingers after the landing
            var count = 0
            var alpha = 0.0
            var pop = 0.0
            var lift = 0.0
            if ball.falling && ball.chain >= 2 {
                count = ball.chain
                alpha = 1
                pop = exp(-ball.sinceBreak * 7)
            } else if !ball.falling && ball.landedChain >= 2 && ball.sinceLanding < 1.25 {
                count = ball.landedChain
                alpha = 1 - ramp(0.8, 1.25, ball.sinceLanding)
                pop = exp(-ball.sinceLanding * 6)
                lift = ball.sinceLanding
            }
            guard count >= 2, alpha > 0.02 else { return }
            var tilted = ctx
            tilted.opacity = alpha
            tilted.translateBy(x: centerX + 106 * unit, y: hudY + (104 - 14 * lift) * unit)
            tilted.rotate(by: .degrees(-8))
            let swell = 1 + 0.30 * pop
            let big = 52 * unit * swell
            let gold = GraphicsContext.Shading.linearGradient(
                Gradient(colors: [.white, Palette.comboLo.color()]),
                startPoint: CGPoint(x: 0, y: -big * 0.30), endPoint: CGPoint(x: 0, y: big * 0.44))
            write(&tilted, "×\(count)", size: big, at: CGPoint(x: 0, y: 6 * unit), fill: gold,
                  outline: Palette.ink.color(), outlineWidth: 3.6 * unit, shadow: Palette.ink.color(0.5), shadowDrop: 5 * unit)
            write(&tilted, "COMBO", size: 13.5 * unit, spacing: 2.6 * unit, at: CGPoint(x: -2 * unit, y: -30 * unit * swell),
                  fill: .color(Palette.ballLit.color()), outline: Palette.ink.color(), outlineWidth: 2.2 * unit)

            // three glints round the number that flare with every floor
            for (x, y, r) in [(-56.0, -8.0, 8.0), (57, -22, 10), (50, 30, 6.5)] {
                let size = r * unit * (0.75 + 0.9 * pop)
                let at = CGPoint(x: x * unit * swell, y: y * unit * swell)
                tilted.fill(Self.glint(at, size + 2.2 * unit), with: .color(Palette.ink.color(0.9)))
                tilted.fill(Self.glint(at, size), with: .color(Color.white))
            }
        }

        /// The score, and under it the level bar: this level, how far through it, the next level.
        func drawScore(_ ctx: inout GraphicsContext) {
            let middle = CGPoint(x: width * 0.5, y: hudY)
            let size = 64 * unit * (1 + 0.13 * exp(-ball.sinceBreak * 5))
            let digits = "\(ball.score)"
            write(&ctx, digits, size: size, at: CGPoint(x: middle.x, y: middle.y + 4.5 * unit),
                  fill: .color(Palette.ink.color(0.55)))
            write(&ctx, digits, size: size, at: middle, fill: .linearGradient(
                Gradient(colors: [.white, Palette.scoreLo.color()]),
                startPoint: CGPoint(x: 0, y: middle.y - size * 0.36), endPoint: CGPoint(x: 0, y: middle.y + size * 0.36)))

            let y = hudY + 51 * unit
            let thickness = 7 * unit
            let left = middle.x - 46 * unit
            let length = 92 * unit
            let bubble = 12.5 * unit
            let groove = CGRect(x: left, y: y - thickness / 2, width: length, height: thickness)
            ctx.fill(Path(roundedRect: groove, cornerRadius: thickness / 2), with: .color(Palette.ink.color(0.46)))
            let filled = max(thickness, length * shot.levelProgress)
            let bar = CGRect(x: left, y: y - thickness / 2, width: filled, height: thickness)
            ctx.fill(Path(roundedRect: bar, cornerRadius: thickness / 2),
                     with: .linearGradient(Gradient(colors: [Palette.ballShine.color(), Palette.ball.color()]),
                                           startPoint: CGPoint(x: 0, y: bar.minY), endPoint: CGPoint(x: 0, y: bar.maxY)))
            let knob = CGPoint(x: left + filled - thickness * 0.5, y: y)
            ctx.fill(Self.oval(knob, thickness * 0.95, thickness * 0.95), with: .color(Color.white))
            ctx.fill(Self.oval(knob, thickness * 0.5, thickness * 0.5), with: .color(Palette.ball.color()))

            // this level, in a white bubble that swells for a moment when the number changes
            let swell = 1 + 0.45 * exp(-shot.sinceLevelUp * 3.0)
            let figure = (shot.level + 1 >= 10 ? 11.5 : 14.5) * unit
            let here = CGPoint(x: left - bubble - 6 * unit, y: y)
            ctx.fill(Self.oval(CGPoint(x: here.x, y: here.y + 2 * unit), bubble * swell, bubble * swell),
                     with: .color(Palette.ink.color(0.45)))
            ctx.fill(Self.oval(here, bubble * swell, bubble * swell), with: .color(Color.white))
            write(&ctx, "\(shot.level)", size: figure * swell, at: here, fill: .color(Palette.ink.color()))

            // the next one, hollow
            let there = CGPoint(x: left + length + bubble + 6 * unit, y: y)
            ctx.fill(Self.oval(there, bubble, bubble), with: .color(Palette.ink.color(0.46)))
            ctx.stroke(Self.oval(there, bubble - 0.8 * unit, bubble - 0.8 * unit),
                       with: .color(Color.white.opacity(0.85)), lineWidth: max(0.6, 1.6 * unit))
            write(&ctx, "\(shot.level + 1)", size: figure, at: there, fill: .color(Color.white.opacity(0.95)))
        }
    }
}
