import SwiftUI

// Gulp City, the clip. A hole wanders a bright toy city, swallows whatever fits and grows.
// One Canvas draws the whole frame from the phase (0...1). The city, the hole's route and the
// moment each prop goes down all come from fixed seeds, so a phase always gives the same picture
// at any frame size.

public struct GulpCityScene: View {
    public var phase: Double
    public var showHUD: Bool

    public init(phase: Double, showHUD: Bool) {
        self.phase = phase
        self.showHUD = showHUD
    }

    public var body: some View {
        Canvas(opaque: true, colorMode: .nonLinear, rendersAsynchronously: false) { context, size in
            guard size.width > 8, size.height > 8 else { return }
            GulpCityClip(size: size, phase: phase, showHUD: showHUD, art: GulpCityArt(context)).draw(&context)
        }
    }
}

// MARK: - Numbers

enum GulpCityCurve {
    static func clamp(_ v: Double, _ lo: Double = 0, _ hi: Double = 1) -> Double {
        Swift.min(Swift.max(v, lo), hi)
    }

    static func mix(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }

    /// Smooth step: 0 at a, 1 at b.
    static func ramp(_ a: Double, _ b: Double, _ v: Double) -> Double {
        let t = clamp((v - a) / (b - a))
        return t * t * (3 - 2 * t)
    }

    /// Fast start, soft landing.
    static func settle(_ v: Double) -> Double {
        let k = 1 - clamp(v)
        return 1 - k * k * k
    }

    /// Overshoots a little, then comes back to 1.
    static func spring(_ v: Double) -> Double {
        let k = clamp(v) - 1
        return 1 + 2.70158 * k * k * k + 1.70158 * k * k
    }
}

/// Seeded random numbers (splitmix64). The city depends on the exact sequence.
struct GulpCityDice {
    private var word: UInt64

    init(seed: UInt64) { word = seed &* 0x9E3779B97F4A7C15 &+ 0xD1B54A32D192ED03 }

    /// 0 ..< 1
    mutating func roll() -> Double {
        word &+= 0x9E3779B97F4A7C15
        var z = word
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        z ^= z >> 31
        return Double(z >> 11) / 9007199254740992.0
    }

    mutating func roll(_ lo: Double, _ hi: Double) -> Double { lo + (hi - lo) * roll() }

    /// 0 ..< count
    mutating func pick(_ count: Int) -> Int { Swift.min(count - 1, Int(roll() * Double(count))) }
}

struct GulpCityHue {
    var r: Double
    var g: Double
    var b: Double

    init(r: Double, g: Double, b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    init(_ hex: UInt32) {
        self.init(r: Double((hex >> 16) & 0xFF) / 255, g: Double((hex >> 8) & 0xFF) / 255, b: Double(hex & 0xFF) / 255)
    }

    static let white = GulpCityHue(r: 1, g: 1, b: 1)

    func toward(_ other: GulpCityHue, _ t: Double) -> GulpCityHue {
        GulpCityHue(r: r + (other.r - r) * t, g: g + (other.g - g) * t, b: b + (other.b - b) * t)
    }

    /// The side turned away from the sun: cooler, still colourful.
    var shade: GulpCityHue { GulpCityHue(r: r * 0.85, g: g * 0.76, b: b * 0.90) }

    /// The side in full sun: warmer and paler.
    var sunlit: GulpCityHue { toward(GulpCityHue(r: 1.0, g: 0.985, b: 0.93), 0.46) }

    func paint(_ alpha: Double = 1) -> Color { Color(.sRGB, red: r, green: g, blue: b, opacity: alpha) }
}

struct GulpCityVec {
    var x: Double
    var y: Double
    var z: Double

    init(_ x: Double, _ y: Double, _ z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    static func + (l: GulpCityVec, r: GulpCityVec) -> GulpCityVec { GulpCityVec(l.x + r.x, l.y + r.y, l.z + r.z) }
    static func - (l: GulpCityVec, r: GulpCityVec) -> GulpCityVec { GulpCityVec(l.x - r.x, l.y - r.y, l.z - r.z) }
    static func * (v: GulpCityVec, k: Double) -> GulpCityVec { GulpCityVec(v.x * k, v.y * k, v.z * k) }

    func dot(_ o: GulpCityVec) -> Double { x * o.x + y * o.y + z * o.z }

    func cross(_ o: GulpCityVec) -> GulpCityVec {
        GulpCityVec(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x)
    }

    var unit: GulpCityVec {
        let length = Swift.max(1e-9, (x * x + y * y + z * z).squareRoot())
        return GulpCityVec(x / length, y / length, z / length)
    }
}

// MARK: - Colours

enum GulpCitySwatch {
    typealias Hue = GulpCityHue

    static let road = Hue(0xBDCCE8)
    static let laneDash = Hue(0xF8F9FF)
    static let pavement = Hue(0xFFF4DE)
    static let curb = Hue(0xE0C59C)
    static let lot = Hue(0xFFE9CC)
    static let pad = Hue(0xF3D6B0)
    static let lawn = Hue(0xA9E8BA)
    static let lawnEdge = Hue(0x86D3A2)
    static let path = Hue(0xFFF0D0)
    static let water = Hue(0x86D6F3)
    static let waterPale = Hue(0xC9F1FC)
    static let pitFloor = Hue(0x110D24)
    static let pitMid = Hue(0x231A47)
    static let pitWall = Hue(0x43337A)
    static let shadow = Hue(0x5A49A8)
    static let ink = Hue(0x2C2356)
    static let coral = Hue(0xFF6B5E)
    static let sun = Hue(0xFFC83D)
    static let violet = Hue(0x7357F6)
    static let pink = Hue(0xFF7EB6)
    static let cream = Hue(0xFFF6E4)

    static let facades: [Hue] = [
        Hue(0x7FC5FF), Hue(0xFFAB7C), Hue(0xFFD466), Hue(0xBBA8FF),
        Hue(0x7FDCC6), Hue(0xFF94AA), Hue(0xFFEFD6), Hue(0x69AEF5)
    ]
    static let roofs: [Hue] = [Hue(0xFF8370), Hue(0x55C9BE), Hue(0xFFCF62), Hue(0xA996F5), Hue(0x6FB4F7), Hue(0xFF94B8)]
    static let houseWalls: [Hue] = [Hue(0xFFF6E6), Hue(0xFFE9DA), Hue(0xEAF4FF), Hue(0xFFF1C9)]
    static let leaves: [Hue] = [Hue(0x5FD08F), Hue(0x43C088), Hue(0x7EDD8A), Hue(0x4CC8B0), Hue(0xFFA9C6), Hue(0xA9E26B)]
    static let cars: [Hue] = [Hue(0xFF6B5E), Hue(0xFFC83D), Hue(0x39C6B8), Hue(0xFFFFFF), Hue(0x6F8CFF), Hue(0xFF8FB3), Hue(0x9B7BFF)]
    static let shirts: [Hue] = [Hue(0xFF6B5E), Hue(0x39C6B8), Hue(0xFFC83D), Hue(0x7357F6), Hue(0xFF8FB3), Hue(0x4FA3F7), Hue(0xFFFFFF)]
    static let skin: [Hue] = [Hue(0xFFD9B8), Hue(0xF2B98D), Hue(0xC98A62), Hue(0x8E5B3F)]
    static let hair: [Hue] = [Hue(0x4A3428), Hue(0x2C2356), Hue(0xE8A742), Hue(0xB5522E)]
    static let canvas: [Hue] = [Hue(0xFF6B5E), Hue(0x39C6B8), Hue(0xFFC83D), Hue(0x7357F6)]
}

// MARK: - The city

enum GulpCityKind {
    case building, house, car, bus, tree, bush, flowers, bench, person, lamp, parasol, kiosk, bin, cone, fountain
}

/// One thing a hole can swallow.
struct GulpCityProp {
    var kind: GulpCityKind
    var x: Double
    var y: Double
    /// Half the footprint along the ground axes.
    var halfW = 0.3
    var halfD = 0.3
    var tall = 0.5
    /// Quarter turns about the vertical.
    var turns = 0
    var tint = 0
    var style = 0
    var scale = 1.0
    var seed: UInt64 = 1
    /// Smallest hole radius that takes it.
    var needs = 0.0
    var worth = 1
    /// Length of the fall, in phase units of the clip.
    var sink = 0.04
    /// Clip phase at which it starts to go down. 9 = the route never reaches it.
    var eatAt = 9.0
    /// Stands in a pit in the pavement that stays behind.
    var pit = false

    init(_ kind: GulpCityKind, _ x: Double, _ y: Double) {
        self.kind = kind
        self.x = x
        self.y = y
    }

    var isTower: Bool { kind == .building && halfW > 1.5 && halfD > 1.5 }
}

enum GulpCityLotUse: Int {
    case park, midrise, houses, plaza, tower
}

/// One city block.
struct GulpCityLot {
    var cx: Double
    var cy: Double
    var use: GulpCityLotUse
    var style: Int
    /// Which quarter holds the pond (parks) or the pocket garden (mid-rise blocks).
    var pond: Int
}

struct GulpCityTown {
    /// Block centre to block centre.
    static let pitch = 8.4
    static let lotSize = 6.1
    static let roadWidth = 2.3
    static let pavementWidth = 0.55

    let lots: [GulpCityLot]
    let props: [GulpCityProp]
    /// Props the clip's hole swallows on its way.
    let route: [Int]

    init(lots: [GulpCityLot], props: [GulpCityProp], route: [Int] = []) {
        self.lots = lots
        self.props = props
        self.route = route
    }

    /// The endless-looking city of the clip, built once.
    static let clip: GulpCityTown = {
        var mason = GulpCityMason()
        var lots: [GulpCityLot] = []
        for j in -5...5 {
            for i in -4...4 {
                var dice = GulpCityDice(seed: UInt64(1000 + (i + 10) * 97 + (j + 10) * 1013))
                let use = clipUse(i, j, dice.roll())
                var lot = GulpCityLot(cx: Double(i) * pitch, cy: Double(j) * pitch, use: use,
                                      style: dice.pick(4), pond: dice.pick(4))
                // the two blocks the camera opens on are composed by hand
                let showcase = j == 0 && (i == 0 || i == 1)
                if showcase {
                    lot.style = 0
                    lot.pond = 1
                }
                if i == 1 && j == 1 {
                    // an open corner by the crossroads
                    lot.style = 3
                    lot.pond = 0
                }
                lots.append(lot)
                mason.furnish(lot, &dice, showcase: showcase)
            }
        }
        mason.clipTraffic()
        mason.stampSeeds()
        GulpCityRoute.schedule(&mason.props)
        var route: [Int] = []
        for k in mason.props.indices where mason.props[k].eatAt < 2 { route.append(k) }
        return GulpCityTown(lots: lots, props: mason.props, route: route)
    }()

    private static func clipUse(_ i: Int, _ j: Int, _ chance: Double) -> GulpCityLotUse {
        switch (i, j) {
        case (0, 0): return .park
        case (1, 0), (-1, 0), (1, -1), (1, 1), (-1, -1): return .midrise
        case (0, 1), (-1, 1): return .houses
        case (0, -1): return .plaza
        default: break
        }
        if chance < 0.36 { return .midrise }
        if chance < 0.60 { return .houses }
        if chance < 0.74 { return .park }
        if chance < 0.86 { return .plaza }
        return .tower
    }
}

/// The path the clip's hole takes: a loop of the park, over the crossroads, up the east street
/// and into the mid-rise block.
enum GulpCityRoute {
    private static let stops: [(x: Double, y: Double)] = [
        (-0.3, -0.3), (0.9, -0.6), (1.0, 0.6), (0.4, 1.7), (1.6, 2.3), (3.0, 3.2),
        (4.55, 4.5), (4.6, 3.0), (4.4, 1.6), (5.2, 1.3), (5.1, -0.3), (5.3, -2.2), (6.4, -3.4)
    ]

    /// A Catmull-Rom curve through the stops.
    static func spot(_ phase: Double) -> (x: Double, y: Double) {
        let last = stops.count - 1
        let along = GulpCityCurve.clamp(phase) * Double(last)
        let leg = Swift.min(Int(along), last - 1)
        let t = along - Double(leg)
        let a = stops[Swift.max(leg - 1, 0)], b = stops[leg], c = stops[leg + 1], d = stops[Swift.min(leg + 2, last)]
        func curve(_ a: Double, _ b: Double, _ c: Double, _ d: Double) -> Double {
            let t2 = t * t, t3 = t2 * t
            return 0.5 * (2 * b + (c - a) * t + (2 * a - 5 * b + 4 * c - d) * t2 + (3 * b - a - 3 * c + d) * t3)
        }
        return (curve(a.x, b.x, c.x, d.x), curve(a.y, b.y, c.y, d.y))
    }

    static func radius(_ phase: Double) -> Double {
        0.85 + 2.35 * pow(GulpCityCurve.clamp(phase), 1.05)
    }

    /// For each prop near the route: the phase at which the hole is first under it and big enough.
    static func schedule(_ props: inout [GulpCityProp]) {
        let samples = 600
        var path: [(x: Double, y: Double, r: Double)] = []
        path.reserveCapacity(samples + 1)
        for k in 0...samples {
            let phase = Double(k) / Double(samples)
            let at = spot(phase)
            path.append((at.x, at.y, radius(phase)))
        }
        for i in props.indices {
            let prop = props[i]
            if prop.x < -7 || prop.x > 13 || prop.y < -10 || prop.y > 10 { continue }
            for k in 0...samples where path[k].r >= prop.needs {
                let dx = prop.x - path[k].x, dy = prop.y - path[k].y
                let reach = path[k].r * 0.9
                if dx * dx + dy * dy <= reach * reach {
                    props[i].eatAt = Double(k) / Double(samples)
                    break
                }
            }
        }
    }
}

// MARK: - Laying out blocks

/// Fills blocks with props. Every roll of the dice happens in a fixed order, so a seed always
/// gives the same block.
struct GulpCityMason {
    typealias Prop = GulpCityProp
    typealias Dice = GulpCityDice
    typealias Lot = GulpCityLot

    var props: [Prop] = []

    /// The four quarters of a block in the order the layouts walk them.
    private static let quarters: [(x: Double, y: Double)] = [(1, -1), (-1, -1), (1, 1), (-1, 1)]
    /// The four building plots of a mid-rise block.
    private static let plots: [(x: Double, y: Double)] = [(-1, -1), (1, -1), (-1, 1), (1, 1)]

    mutating func furnish(_ lot: Lot, _ dice: inout Dice, showcase: Bool) {
        switch lot.use {
        case .park: park(lot, &dice, showcase: showcase)
        case .midrise: midrise(lot, &dice, showcase: showcase)
        case .houses: houses(lot, &dice)
        case .plaza: plaza(lot, &dice)
        case .tower: tower(lot, &dice)
        }
        pavement(lot, &dice)
    }

    /// Every prop gets its own seed for the little random details of its drawing.
    mutating func stampSeeds() {
        for k in props.indices { props[k].seed = UInt64(k + 1) &* 2654435761 }
    }

    // MARK: Props

    mutating func tree(_ x: Double, _ y: Double, _ dice: inout Dice, pit: Bool, scale: Double = 1) {
        var p = Prop(.tree, x, y)
        let size = scale * dice.roll(0.9, 1.08)
        p.scale = size
        p.halfW = 0.46 * size
        p.halfD = 0.46 * size
        p.tall = 1.65 * size
        let c = dice.roll()
        p.tint = c < 0.3 ? 0 : (c < 0.5 ? 1 : (c < 0.68 ? 2 : (c < 0.82 ? 3 : (c < 0.92 ? 4 : 5))))
        p.style = dice.pick(3)
        p.needs = 1.1
        p.worth = 4
        p.sink = 0.055
        p.pit = pit
        props.append(p)
    }

    mutating func bush(_ x: Double, _ y: Double, _ dice: inout Dice) {
        let jx = dice.roll(-0.08, 0.08), jy = dice.roll(-0.08, 0.08)
        var p = Prop(.bush, x + jx, y + jy)
        p.halfW = 0.36
        p.halfD = 0.3
        p.tall = 0.5
        p.tint = dice.pick(4)
        p.style = dice.pick(3)
        p.sink = 0.035
        props.append(p)
    }

    mutating func flowers(_ x: Double, _ y: Double, _ dice: inout Dice) {
        var p = Prop(.flowers, x, y)
        p.halfW = 0.3
        p.halfD = 0.26
        p.tall = 0.25
        p.tint = dice.pick(4)
        p.sink = 0.03
        props.append(p)
    }

    mutating func bench(_ x: Double, _ y: Double, turns: Int) {
        var p = Prop(.bench, x, y)
        p.turns = turns
        let sideways = turns % 2 != 0
        p.halfW = sideways ? 0.24 : 0.6
        p.halfD = sideways ? 0.6 : 0.24
        p.tall = 0.56
        p.worth = 2
        p.sink = 0.045
        props.append(p)
    }

    mutating func person(_ x: Double, _ y: Double, _ dice: inout Dice) {
        var p = Prop(.person, x, y)
        p.halfW = 0.16
        p.halfD = 0.16
        p.tall = 0.8
        p.tint = dice.pick(7)
        p.style = dice.pick(16)
        p.sink = 0.032
        props.append(p)
    }

    mutating func lamp(_ x: Double, _ y: Double) {
        var p = Prop(.lamp, x, y)
        p.halfW = 0.1
        p.halfD = 0.1
        p.tall = 1.2
        p.sink = 0.04
        props.append(p)
    }

    mutating func parasol(_ x: Double, _ y: Double, _ dice: inout Dice) {
        var p = Prop(.parasol, x, y)
        p.halfW = 0.56
        p.halfD = 0.56
        p.tall = 0.95
        p.tint = dice.pick(4)
        p.worth = 3
        p.sink = 0.045
        props.append(p)
    }

    mutating func kiosk(_ x: Double, _ y: Double, _ dice: inout Dice) {
        var p = Prop(.kiosk, x, y)
        p.halfW = 0.6
        p.halfD = 0.5
        p.tall = 1.0
        p.tint = dice.pick(4)
        p.needs = 1.2
        p.worth = 10
        p.sink = 0.05
        props.append(p)
    }

    /// A car, or a bus. Pass a tint to choose the colour; otherwise the dice choose.
    mutating func car(_ x: Double, _ y: Double, turns: Int, _ dice: inout Dice, bus: Bool = false, tint: Int? = nil) {
        var p = Prop(bus ? .bus : .car, x, y)
        p.turns = turns
        let long = bus ? 1.3 : 0.84, wide = bus ? 0.46 : 0.42
        let sideways = turns % 2 != 0
        p.halfW = sideways ? wide : long
        p.halfD = sideways ? long : wide
        p.tall = bus ? 0.95 : 0.74
        p.tint = tint ?? dice.pick(7)
        p.needs = bus ? 1.7 : 1.3
        p.worth = bus ? 15 : 8
        p.sink = bus ? 0.07 : 0.06
        props.append(p)
    }

    mutating func building(_ x: Double, _ y: Double, halfW: Double, halfD: Double, tall: Double,
                           tint: Int, style: Int, needs: Double? = nil) {
        var p = Prop(.building, x, y)
        p.halfW = halfW
        p.halfD = halfD
        p.tall = tall
        p.tint = tint
        p.style = style
        p.needs = needs ?? 2.3 + (Swift.max(halfW, halfD) - 1.1) * 1.3
        p.worth = 40 + Int(tall * 10)
        p.sink = 0.1
        props.append(p)
    }

    // MARK: Blocks

    private mutating func park(_ lot: Lot, _ dice: inout Dice, showcase: Bool) {
        let cx = lot.cx, cy = lot.cy
        let standQuarter = showcase ? 3 : dice.pick(4)
        // benches round the middle, backs to the lawn
        let seats: [(x: Double, y: Double, turns: Int)] = [
            (1.72, -0.64, 0), (1.72, 0.64, 2), (-1.72, -0.64, 0), (-1.72, 0.64, 2),
            (0.64, 1.72, 1), (-0.64, 1.72, 3), (0.64, -1.72, 1), (-0.64, -1.72, 3)
        ]
        for seat in seats where showcase || dice.roll() >= 0.3 {
            bench(cx + seat.x, cy + seat.y, turns: seat.turns)
        }
        for (q, sign) in Self.quarters.enumerated() {
            let sx = sign.x, sy = sign.y
            if q == lot.pond {
                tree(cx + sx * 2.2, cy + sy * 2.28, &dice, pit: false, scale: 1.12)
                bush(cx + sx * 0.74, cy + sy * 2.2, &dice)
                flowers(cx + sx * 2.25, cy + sy * 0.82, &dice)
                continue
            }
            if q == standQuarter {
                kiosk(cx + sx * 1.38, cy + sy * 1.32, &dice)
                parasol(cx + sx * 2.2, cy + sy * 2.2, &dice)
                tree(cx + sx * 2.26, cy + sy * 0.9, &dice, pit: false, scale: 0.86)
                continue
            }
            // the showcase park keeps its south-east lawn low, so the opening shot stays open
            let low = showcase && q == 2
            if low {
                flowers(cx + sx * 2.0, cy + sy * 2.05, &dice)
                bush(cx + sx * 2.15, cy + sy * 1.05, &dice)
            } else {
                tree(cx + sx * 2.04, cy + sy * 2.04, &dice, pit: false, scale: 1.14)
                if dice.roll() < 0.55 {
                    tree(cx + sx * 2.22, cy + sy * 0.98, &dice, pit: false, scale: 0.84)
                } else {
                    bush(cx + sx * 2.15, cy + sy * 1.05, &dice)
                }
            }
            bush(cx + sx * 1.06, cy + sy * 2.12, &dice)
            bush(cx + sx * 1.2, cy + sy * 1.22, &dice)
            flowers(cx + sx * 1.68, cy + sy * 1.6, &dice)
        }
        lamp(cx + 0.98, cy - 0.98)
        lamp(cx - 0.98, cy + 0.98)
        let strollers: [(x: Double, y: Double)] = [
            (0.42, 0.52), (-0.1, 2.35), (2.3, -0.12), (-2.3, 0.1), (0.1, -2.3), (1.05, 0.2), (-1.1, -0.12), (-0.2, 1.05)
        ]
        for spot in strollers where showcase || dice.roll() >= 0.4 {
            let jx = dice.roll(-0.06, 0.06), jy = dice.roll(-0.06, 0.06)
            person(cx + spot.x + jx, cy + spot.y + jy, &dice)
        }
    }

    private mutating func midrise(_ lot: Lot, _ dice: inout Dice, showcase: Bool) {
        let cx = lot.cx, cy = lot.cy
        let off = 1.37
        if showcase {
            building(cx - off, cy - off, halfW: 1.1, halfD: 1.1, tall: 3.8, tint: 1, style: 0)
            building(cx - off, cy + off, halfW: 1.1, halfD: 1.1, tall: 2.4, tint: 0, style: 7)
            building(cx + off, cy - off, halfW: 1.1, halfD: 1.1, tall: 4.3, tint: 3, style: 8)
            building(cx + off, cy + off, halfW: 1.1, halfD: 1.1, tall: 3.2, tint: 2, style: 4)
            return
        }
        let firstTint = dice.pick(8)
        func tint(_ k: Int) -> Int { (firstTint + k * 3) % 8 }
        /// One ordinary square building: the dice choose its height, then its style.
        func block(_ x: Double, _ y: Double, _ k: Int, _ dice: inout Dice) {
            let tall = dice.roll(1.9, 4.3)
            building(x, y, halfW: 1.1, halfD: 1.1, tall: tall, tint: tint(k), style: dice.pick(12))
        }
        switch lot.style {
        case 1:
            // a long building across the north side
            let tall = dice.roll(1.8, 3.0)
            building(cx, cy - off, halfW: 2.47, halfD: 1.1, tall: tall, tint: tint(0), style: dice.pick(6))
            block(cx - off, cy + off, 1, &dice)
            block(cx + off, cy + off, 2, &dice)
        case 2:
            // a long building down the west side
            let tall = dice.roll(1.8, 3.0)
            building(cx - off, cy, halfW: 1.1, halfD: 2.47, tall: tall, tint: tint(0), style: dice.pick(6))
            block(cx + off, cy - off, 1, &dice)
            block(cx + off, cy + off, 2, &dice)
        case 3:
            // three buildings and a pocket garden
            for (k, sign) in Self.plots.enumerated() {
                let gx = cx + sign.x * off, gy = cy + sign.y * off
                if k == lot.pond {
                    tree(gx + 0.45, gy + 0.4, &dice, pit: false, scale: 1.0)
                    tree(gx - 0.55, gy - 0.45, &dice, pit: false, scale: 0.86)
                    bench(gx - 0.3, gy + 0.68, turns: 2)
                    bush(gx + 0.6, gy - 0.55, &dice)
                    flowers(gx - 0.6, gy + 0.2, &dice)
                } else {
                    block(gx, gy, k, &dice)
                }
            }
        default:
            for (k, sign) in Self.plots.enumerated() {
                block(cx + sign.x * off, cy + sign.y * off, k, &dice)
            }
        }
    }

    private mutating func houses(_ lot: Lot, _ dice: inout Dice) {
        let cx = lot.cx, cy = lot.cy
        let firstRoof = dice.pick(6)
        var count = 0
        for row in 0..<2 {
            let y = cy + (row == 0 ? -1.62 : 1.62)
            for col in 0..<3 {
                let x = cx + Double(col - 1) * 1.68
                var p = Prop(.house, x, y)
                p.halfW = 0.72
                p.halfD = 0.62
                p.tall = 1.3
                p.tint = (firstRoof + count * 5) % 6
                p.style = dice.pick(4)
                p.needs = 1.9
                p.worth = 20
                p.sink = 0.08
                props.append(p)
                count += 1
                // a hedge between neighbours, on the garden side
                if col < 2 && dice.roll() < 0.7 { bush(x + 0.84, y + (row == 0 ? 0.3 : -0.3), &dice) }
            }
        }
        if lot.style < 2 {
            // the shared garden has a pool on its west side
            tree(cx + 1.55, cy + 0.05, &dice, pit: false, scale: 0.95)
            parasol(cx + 0.55, cy - 0.1, &dice)
            person(cx + 0.95, cy + 0.3, &dice)
        } else {
            tree(cx - 1.7, cy, &dice, pit: false, scale: 1.0)
            tree(cx + 1.7, cy + 0.05, &dice, pit: false, scale: 0.92)
            flowers(cx - 0.6, cy + 0.1, &dice)
            flowers(cx + 0.55, cy - 0.1, &dice)
            bench(cx, cy - 0.15, turns: 0)
        }
    }

    private mutating func plaza(_ lot: Lot, _ dice: inout Dice) {
        let cx = lot.cx, cy = lot.cy
        var fountain = Prop(.fountain, cx, cy)
        fountain.halfW = 1.0
        fountain.halfD = 1.0
        fountain.tall = 0.7
        fountain.needs = 1.8
        fountain.worth = 30
        fountain.sink = 0.07
        props.append(fountain)
        // a ring of cafe parasols, some missing
        for k in 0..<6 {
            let a = (Double(k) * 60 + 30) * Double.pi / 180
            if dice.roll() < 0.2 { continue }
            parasol(cx + cos(a) * 1.95, cy + sin(a) * 1.95, &dice)
        }
        for sign in Self.quarters {
            tree(cx + sign.x * 2.12, cy + sign.y * 2.12, &dice, pit: true, scale: 0.95)
        }
        for _ in 0..<6 {
            let a = dice.roll(0, 2 * Double.pi)
            let r = dice.roll(1.25, 1.6)
            person(cx + cos(a) * r, cy + sin(a) * r * 0.9, &dice)
        }
        bench(cx, cy - 2.2, turns: 0)
        bench(cx, cy + 2.2, turns: 2)
    }

    private mutating func tower(_ lot: Lot, _ dice: inout Dice) {
        let cx = lot.cx, cy = lot.cy
        let tall = dice.roll(4.8, 6.2)
        let tint = dice.pick(8)
        building(cx, cy, halfW: 1.7, halfD: 1.7, tall: tall, tint: tint, style: 6 + dice.pick(6), needs: 3.6)
        for sign in Self.quarters {
            tree(cx + sign.x * 2.14, cy + sign.y * 2.14, &dice, pit: true, scale: 0.9)
        }
        bench(cx, cy + 2.15, turns: 2)
        bush(cx - 1.1, cy + 2.15, &dice)
        bush(cx + 1.1, cy + 2.15, &dice)
    }

    /// Street trees, lamps, bins, cones and passers-by on the pavement round a block.
    private mutating func pavement(_ lot: Lot, _ dice: inout Dice) {
        let mid = GulpCityTown.lotSize / 2 - GulpCityTown.pavementWidth / 2
        /// A point on one of the four sides (north, south, west, east), "along" from its middle.
        func kerb(_ side: Int, _ along: Double, _ out: Double) -> (x: Double, y: Double) {
            switch side {
            case 0: return (lot.cx + along, lot.cy - out)
            case 1: return (lot.cx + along, lot.cy + out)
            case 2: return (lot.cx - out, lot.cy + along)
            default: return (lot.cx + out, lot.cy + along)
            }
        }
        let treeChance = lot.use == .park ? 0.8 : 0.48
        for side in 0..<4 {
            for along in [-1.8, 0, 1.8] {
                let at = kerb(side, along, mid)
                let c = dice.roll()
                if c < treeChance {
                    tree(at.x, at.y, &dice, pit: true, scale: 0.78)
                } else if c < treeChance + 0.2 {
                    lamp(at.x, at.y)
                } else if c < treeChance + 0.32 {
                    var p = Prop(dice.roll() < 0.6 ? .bin : .cone, at.x, at.y)
                    p.halfW = 0.14
                    p.halfD = 0.14
                    p.tall = 0.34
                    p.tint = dice.pick(3)
                    p.sink = 0.03
                    props.append(p)
                }
            }
        }
        for sign in Self.quarters where dice.roll() < 0.78 {
            tree(lot.cx + sign.x * 2.66, lot.cy + sign.y * 2.66, &dice, pit: true, scale: 0.8)
        }
        for _ in 0..<3 {
            let side = dice.pick(4)
            let along = dice.roll(-2.5, 2.5)
            // not where a street tree or lamp may stand
            if abs(abs(along) - 1.8) < 0.45 || abs(along) < 0.45 { continue }
            let at = kerb(side, along, mid + 0.05)
            person(at.x, at.y, &dice)
        }
    }

    // MARK: Traffic

    /// One lane's worth of traffic beside a block: nothing, a bus, a car, or two cars.
    /// The lane runs along x when alongX is true, else along y. "fixed" is the lane's other coordinate.
    mutating func lane(alongX: Bool, mid: Double, fixed: Double, turns: Int, _ dice: inout Dice,
                       empty: Double, bus: Double, single: Double, gap: (near: Double, far: Double)) {
        func put(_ along: Double, _ dice: inout Dice, bus isBus: Bool = false) {
            if alongX {
                car(along, fixed, turns: turns, &dice, bus: isBus)
            } else {
                car(fixed, along, turns: turns, &dice, bus: isBus)
            }
        }
        let c = dice.roll()
        if c < empty { return }
        if c < bus {
            put(mid + dice.roll(-0.9, 0.9), &dice, bus: true)
        } else if c < single {
            put(mid + dice.roll(-1.8, 1.8), &dice)
        } else {
            put(mid + dice.roll(-2.0, -gap.near), &dice)
            put(mid + dice.roll(gap.far, 2.0), &dice)
        }
    }

    fileprivate mutating func clipTraffic() {
        var dice = Dice(seed: 4242)
        let pitch = GulpCityTown.pitch
        for j in -6...5 {
            for i in -4...4 where !(i == 0 && j == 0) {
                // the street south of block (i, j), then the street east of it
                let south = (Double(j) + 0.5) * pitch, east = (Double(i) + 0.5) * pitch
                for n in 0..<2 {
                    lane(alongX: true, mid: Double(i) * pitch, fixed: south + (n == 0 ? -0.57 : 0.57), turns: n == 0 ? 2 : 0,
                         &dice, empty: 0.34, bus: 0.46, single: 0.8, gap: (0.8, 0.9))
                }
                for n in 0..<2 {
                    lane(alongX: false, mid: Double(j) * pitch, fixed: east + (n == 0 ? -0.57 : 0.57), turns: n == 0 ? 1 : 3,
                         &dice, empty: 0.4, bus: 0.5, single: 0.84, gap: (0.8, 0.9))
                }
            }
        }
        // placed by hand round the crossroads and up the east street, where the hole passes
        let south = 0.5 * pitch, east = 0.5 * pitch
        car(0.2, south + 0.57, turns: 0, &dice, bus: true, tint: 1)
        car(-1.9, south - 0.57, turns: 2, &dice, tint: 4)
        car(2.9, south - 0.57, turns: 2, &dice, tint: 5)
        car(5.0, south + 0.57, turns: 0, &dice, tint: 0)
        car(5.95, south - 0.57, turns: 2, &dice, tint: 1)
        car(east + 0.57, 5.9, turns: 3, &dice, tint: 2)
        car(east - 0.57, 2.2, turns: 1, &dice, tint: 3)
        car(east + 0.57, 1.2, turns: 3, &dice, tint: 4)
        car(east - 0.57, 0.1, turns: 1, &dice, tint: 0)
        car(east + 0.57, -2.6, turns: 3, &dice, bus: true, tint: 0)
        car(east - 0.57, -2.0, turns: 1, &dice, tint: 6)
    }
}

// MARK: - Camera

/// The fixed three-quarter view: the ground is turned 19 degrees and squashed, height lifts
/// straight up the screen.
struct GulpCityLens {
    static let cosTurn = cos(-19.0 * Double.pi / 180)
    static let sinTurn = sin(-19.0 * Double.pi / 180)
    /// Screen height of one ground unit running away from the camera.
    static let squash = 0.84
    /// Screen lift of one unit of height.
    static let lift = 0.56

    let w: Double
    let h: Double
    /// One design point: the art is tuned on a 402 point wide screen.
    let unit: Double
    /// Screen points per ground unit.
    let zoom: Double
    let eyeX: Double
    let eyeY: Double
    /// Where on screen the eye point lands.
    let midX: Double
    let midY: Double
    /// Flat ground to screen.
    let ground: CGAffineTransform
    /// The ground rectangle that covers the screen.
    let seen: (x0: Double, x1: Double, y0: Double, y1: Double)

    /// span = ground units across the width of the screen.
    init(size: CGSize, eyeX: Double, eyeY: Double, span: Double) {
        w = Double(size.width)
        h = Double(size.height)
        unit = w / 402
        zoom = w / span
        self.eyeX = eyeX
        self.eyeY = eyeY
        midX = w * 0.455
        // wider frames (the feed crops) look a little further down
        midY = h * (0.455 + 0.28 * Swift.max(0, w / h - 0.46))
        let c = Self.cosTurn, s = Self.sinTurn
        let xx = zoom * c, xy = zoom * Self.squash * s
        let yx = -zoom * s, yy = zoom * Self.squash * c
        ground = CGAffineTransform(a: xx, b: xy, c: yx, d: yy,
                                   tx: midX - (xx * eyeX + yx * eyeY), ty: midY - (xy * eyeX + yy * eyeY))
        var x0 = Double.infinity, x1 = -Double.infinity, y0 = Double.infinity, y1 = -Double.infinity
        for corner in [(0.0, 0.0), (w, 0.0), (w, h), (0.0, h)] {
            let sx = (corner.0 - midX) / zoom
            let sy = (corner.1 - midY) / (zoom * Self.squash)
            let gx = eyeX + sx * c + sy * s
            let gy = eyeY - sx * s + sy * c
            x0 = Swift.min(x0, gx)
            x1 = Swift.max(x1, gx)
            y0 = Swift.min(y0, gy)
            y1 = Swift.max(y1, gy)
        }
        seen = (x0, x1, y0, y1)
    }

    func spot(_ x: Double, _ y: Double, _ z: Double = 0) -> CGPoint {
        let dx = x - eyeX, dy = y - eyeY
        return CGPoint(x: midX + zoom * (dx * Self.cosTurn - dy * Self.sinTurn),
                       y: midY + zoom * (Self.squash * (dx * Self.sinTurn + dy * Self.cosTurn) - Self.lift * z))
    }

    func spot(_ v: GulpCityVec) -> CGPoint { spot(v.x, v.y, v.z) }

    /// Above zero when a surface with this normal is turned to the camera.
    func facing(_ n: GulpCityVec) -> Double {
        (n.x * Self.sinTurn + n.y * Self.cosTurn) * Self.lift + n.z * Self.squash
    }
}

/// The edge of a city that ends (the playable game). Blocks are 0..<cols by 0..<rows.
struct GulpCityEdge {
    var west: Double
    var east: Double
    var north: Double
    var south: Double
    var cols: Int
    var rows: Int
}

// MARK: - One frame's worth of a prop

/// Where a prop is this frame: standing, leaning towards a hole, or on its way down one.
struct GulpCityPose {
    var prop: Int
    var x: Double
    var y: Double
    var z: Double
    var lean: Double
    /// Unit direction on the ground towards its hole.
    var towardX: Double
    var towardY: Double
    /// Progress of the fall, 0...1. -1 while it stands.
    var fall: Double
    var dim: Double
    var alpha: Double
    // ground box, for telling which of two props is behind
    var west: Double
    var east: Double
    var north: Double
    var south: Double
    var depth: Double
    // screen box
    var left: Double
    var right: Double
    var top: Double
    var bottom: Double
    // the hole it leans or falls into
    var holeX: Double
    var holeY: Double
    var holeR: Double
}

/// A prop's own axes in the world, plus what is needed to draw it going under.
struct GulpCityStance {
    typealias Vec = GulpCityVec

    var base = Vec(0, 0, 0)
    var right = Vec(1, 0, 0)
    var ahead = Vec(0, 1, 0)
    var up = Vec(0, 0, 1)
    /// up, scaled while props pop out of the ground at the start.
    var grow = Vec(0, 0, 1)
    var sinking = false
    var dim = 0.0
    var holeR = 1.0
    /// Clipped to the mouth of the hole: whatever is below ground shows only through it.
    var below: GraphicsContext? = nil

    /// A point given in the prop's own coordinates.
    func point(_ x: Double, _ y: Double, _ z: Double) -> Vec {
        Vec(base.x + right.x * x + ahead.x * y + grow.x * z,
            base.y + right.y * x + ahead.y * y + grow.y * z,
            base.z + right.z * x + ahead.z * y + grow.z * z)
    }

    /// A level direction given in the prop's own coordinates.
    func level(_ x: Double, _ y: Double) -> Vec {
        Vec(right.x * x + ahead.x * y, right.y * x + ahead.y * y, right.z * x + ahead.z * y)
    }
}

/// One wall of a box: a start corner, the direction along the wall, and the way it faces.
struct GulpCityWall {
    var x: Double
    var y: Double
    var alongX: Double
    var alongY: Double
    var outX: Double
    var outY: Double
    var length: Double
}

// MARK: - Drawing

/// The painted pictures, resolved once per frame.
struct GulpCityArt {
    let hole: GraphicsContext.ResolvedImage
    let park: GraphicsContext.ResolvedImage
    let plaza: GraphicsContext.ResolvedImage
    let yard: GraphicsContext.ResolvedImage
    let yardPool: GraphicsContext.ResolvedImage
    let treeRound: GraphicsContext.ResolvedImage
    let treeTall: GraphicsContext.ResolvedImage
    let treePink: GraphicsContext.ResolvedImage
    let bush: GraphicsContext.ResolvedImage
    let bushBloom: GraphicsContext.ResolvedImage

    init(_ ctx: GraphicsContext) {
        hole = ctx.resolve(Image("gulp-city-hole"))
        park = ctx.resolve(Image("gulp-city-park"))
        plaza = ctx.resolve(Image("gulp-city-plaza"))
        yard = ctx.resolve(Image("gulp-city-yard"))
        yardPool = ctx.resolve(Image("gulp-city-yard-pool"))
        treeRound = ctx.resolve(Image("gulp-city-tree-round"))
        treeTall = ctx.resolve(Image("gulp-city-tree-tall"))
        treePink = ctx.resolve(Image("gulp-city-tree-pink"))
        bush = ctx.resolve(Image("gulp-city-bush"))
        bushBloom = ctx.resolve(Image("gulp-city-bush-bloom"))
    }
}

/// Draws the city through a lens. The clip and the playable game both use it.
struct GulpCityArtist {
    typealias Curve = GulpCityCurve
    typealias Hue = GulpCityHue
    typealias Vec = GulpCityVec
    typealias Tone = GulpCitySwatch
    typealias Prop = GulpCityProp
    typealias Town = GulpCityTown
    typealias Lens = GulpCityLens
    typealias Pose = GulpCityPose
    typealias Stance = GulpCityStance
    typealias Wall = GulpCityWall
    typealias Dice = GulpCityDice
    typealias Flat = (x: Double, y: Double)

    static let sun = GulpCityVec(-0.5, -0.3, 0.81).unit

    let lens: Lens
    let town: Town
    /// 0.62...1: props pop up out of the ground as the scene opens.
    let rise: Double
    /// nil = the city runs past every edge of the screen.
    let edge: GulpCityEdge?
    let art: GulpCityArt

    var W: Double { lens.w }
    var H: Double { lens.h }
    var u: Double { lens.unit }
    var s: Double { lens.zoom }

    func spot(_ x: Double, _ y: Double, _ z: Double = 0) -> CGPoint { lens.spot(x, y, z) }

    func sunlight(_ hue: Hue, _ normal: Vec) -> Hue {
        let t = Curve.clamp((normal.dot(Self.sun) + 0.55) / 1.36)
        if t < 0.5 { return hue.shade.toward(hue, t / 0.5) }
        return hue.toward(hue.sunlit, (t - 0.5) / 0.5)
    }

    func disc(_ c: CGPoint, _ r: Double) -> Path {
        Path(ellipseIn: CGRect(x: Double(c.x) - r, y: Double(c.y) - r, width: 2 * r, height: 2 * r))
    }

    // MARK: Footprints

    /// A rounded rectangle as a polygon, counter-clockwise from the south-east corner.
    static func rounded(_ hw: Double, _ hd: Double, _ radius: Double, _ cx: Double = 0, _ cy: Double = 0, steps: Int = 3) -> [Flat] {
        let r = Swift.min(radius, Swift.min(hw, hd))
        if r < 0.01 { return box(hw, hd, cx, cy) }
        let ax = hw - r, ay = hd - r
        let centres: [Flat] = [(ax, ay), (-ax, ay), (-ax, -ay), (ax, -ay)]
        var out: [Flat] = []
        out.reserveCapacity(4 * (steps + 1))
        for (q, c) in centres.enumerated() {
            for k in 0...steps {
                let a = (Double(q) + Double(k) / Double(steps)) * Double.pi / 2
                out.append((cx + c.x + r * cos(a), cy + c.y + r * sin(a)))
            }
        }
        return out
    }

    static func box(_ hw: Double, _ hd: Double, _ cx: Double = 0, _ cy: Double = 0) -> [Flat] {
        [(cx + hw, cy + hd), (cx - hw, cy + hd), (cx - hw, cy - hd), (cx + hw, cy - hd)]
    }

    static func ring(_ r: Double, _ sides: Int, _ cx: Double = 0, _ cy: Double = 0) -> [Flat] {
        var out: [Flat] = []
        out.reserveCapacity(sides)
        for k in 0..<sides {
            let a = (Double(k) + 0.5) / Double(sides) * 2 * Double.pi
            out.append((cx + r * cos(a), cy + r * sin(a)))
        }
        return out
    }

    /// The four walls of a box: south (the front), west, north, east.
    static func walls(_ hw: Double, _ hd: Double, _ cx: Double = 0, _ cy: Double = 0) -> [Wall] {
        [Wall(x: cx - hw, y: cy + hd, alongX: 1, alongY: 0, outX: 0, outY: 1, length: 2 * hw),
         Wall(x: cx - hw, y: cy - hd, alongX: 0, alongY: 1, outX: -1, outY: 0, length: 2 * hd),
         Wall(x: cx + hw, y: cy - hd, alongX: -1, alongY: 0, outX: 0, outY: -1, length: 2 * hw),
         Wall(x: cx + hw, y: cy + hd, alongX: 0, alongY: -1, outX: 1, outY: 0, length: 2 * hd)]
    }

    /// Cuts a polygon at ground level.
    static func cutAtGround(_ poly: [Vec]) -> (above: [Vec], below: [Vec]) {
        var above: [Vec] = [], below: [Vec] = []
        for i in poly.indices {
            let a = poly[i], b = poly[(i + 1) % poly.count]
            if a.z >= 0 { above.append(a) } else { below.append(a) }
            if (a.z >= 0) != (b.z >= 0) {
                let t = a.z / (a.z - b.z)
                let cut = Vec(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, 0)
                above.append(cut)
                below.append(cut)
            }
        }
        return (above, below)
    }

    // MARK: Solids

    /// A flat colour, or a gradient between two world points, darkened by how deep in the hole it is.
    private func paint(_ hue: Hue, _ hue2: Hue?, _ from: Vec?, _ to: Vec?, dim: Double) -> GraphicsContext.Shading {
        let first = dim > 0.001 ? hue.toward(Tone.pitFloor, dim) : hue
        guard let hue2, let from, let to else { return .color(first.paint()) }
        let second = dim > 0.001 ? hue2.toward(Tone.pitFloor, dim) : hue2
        return .linearGradient(Gradient(colors: [first.paint(), second.paint()]),
                               startPoint: lens.spot(from), endPoint: lens.spot(to))
    }

    private func fill(_ ctx: inout GraphicsContext, _ poly: [Vec], _ shading: GraphicsContext.Shading, seal: Bool) {
        var path = Path()
        path.addLines(poly.map { lens.spot($0) })
        path.closeSubpath()
        ctx.fill(path, with: shading)
        // a hairline of the same paint closes the seams between neighbouring faces
        if seal {
            ctx.stroke(path, with: shading, style: StrokeStyle(lineWidth: Swift.max(0.3, 0.7 * u), lineJoin: .round))
        }
    }

    /// Fills a polygon given in world space. A sinking prop is cut at ground level, and the part
    /// below ground goes to the context clipped to the mouth of the hole.
    func face(_ ctx: inout GraphicsContext, _ st: Stance, _ poly: [Vec], _ hue: Hue,
              _ hue2: Hue? = nil, _ from: Vec? = nil, _ to: Vec? = nil, seal: Bool = true) {
        guard st.sinking else {
            fill(&ctx, poly, paint(hue, hue2, from, to, dim: st.dim), seal: seal)
            return
        }
        let cut = Self.cutAtGround(poly)
        if cut.above.count >= 3 {
            fill(&ctx, cut.above, paint(hue, hue2, from, to, dim: st.dim), seal: seal)
        }
        if cut.below.count >= 3, var under = st.below {
            var depth = 0.0
            for p in cut.below { depth += p.z }
            depth /= Double(cut.below.count)
            let deeper = Curve.clamp(-depth / (st.holeR * 1.4)) * 0.6
            fill(&under, cut.below, paint(hue, hue2, from, to, dim: 1 - (1 - st.dim) * (1 - deeper)), seal: seal)
        }
    }

    /// An upright solid over a footprint, from height z0 to z1. Only the walls that face the camera
    /// are drawn. fade > 0 shades the walls darker towards the ground.
    func solid(_ ctx: inout GraphicsContext, _ st: Stance, _ foot: [Flat], _ z0: Double, _ z1: Double,
               _ wall: Hue, _ top: Hue, fade: Double = 0.12, lid: Bool = true) {
        let n = foot.count
        guard n >= 3 else { return }
        var mx = 0.0, my = 0.0
        for f in foot {
            mx += f.x
            my += f.y
        }
        mx /= Double(n)
        my /= Double(n)
        for i in 0..<n {
            let a = foot[i], b = foot[(i + 1) % n]
            var nx = b.y - a.y, ny = a.x - b.x
            let length = (nx * nx + ny * ny).squareRoot()
            if length < 1e-9 { continue }
            nx /= length
            ny /= length
            // outwards: away from the middle of the footprint
            if nx * ((a.x + b.x) * 0.5 - mx) + ny * ((a.y + b.y) * 0.5 - my) < 0 {
                nx = -nx
                ny = -ny
            }
            let out = st.level(nx, ny)
            if lens.facing(out) <= 0 { continue }
            let hue = sunlight(wall, out)
            let a0 = st.point(a.x, a.y, z0), b0 = st.point(b.x, b.y, z0)
            let b1 = st.point(b.x, b.y, z1), a1 = st.point(a.x, a.y, z1)
            if fade > 0 {
                face(&ctx, st, [a0, b0, b1, a1], hue.toward(hue.sunlit, 0.14), hue.toward(hue.shade, fade * 3),
                     (a1 + b1) * 0.5, (a0 + b0) * 0.5)
            } else {
                face(&ctx, st, [a0, b0, b1, a1], hue)
            }
        }
        guard lid else { return }
        if lens.facing(st.up) > 0 {
            face(&ctx, st, foot.map { st.point($0.x, $0.y, z1) }, sunlight(top, st.up))
        } else {
            // tipped so far over that the underside shows
            face(&ctx, st, foot.map { st.point($0.x, $0.y, z0) }, sunlight(wall.shade, st.up * -1))
        }
    }

    /// A rectangle on a wall: from a0 to a1 along it, from z0 to z1 up it.
    func panel(_ ctx: inout GraphicsContext, _ st: Stance, _ wall: Wall, _ a0: Double, _ a1: Double,
               _ z0: Double, _ z1: Double, _ hue: Hue, _ hue2: Hue? = nil) {
        let lowA = st.point(wall.x + wall.alongX * a0, wall.y + wall.alongY * a0, z0)
        let lowB = st.point(wall.x + wall.alongX * a1, wall.y + wall.alongY * a1, z0)
        let highB = st.point(wall.x + wall.alongX * a1, wall.y + wall.alongY * a1, z1)
        let highA = st.point(wall.x + wall.alongX * a0, wall.y + wall.alongY * a0, z1)
        if let hue2 {
            face(&ctx, st, [lowA, lowB, highB, highA], hue, hue2, (highA + highB) * 0.5, (lowA + lowB) * 0.5, seal: false)
        } else {
            face(&ctx, st, [lowA, lowB, highB, highA], hue, seal: false)
        }
    }

    /// A flat shape lying on a level surface of the prop, at height z.
    func plate(_ ctx: inout GraphicsContext, _ st: Stance, _ shape: [Flat], _ z: Double, _ hue: Hue) {
        if lens.facing(st.up) <= 0 { return }
        face(&ctx, st, shape.map { st.point($0.x, $0.y, z) }, hue)
    }

    /// A shaded ball: three stacked discs and an optional glint.
    func orb(_ ctx: inout GraphicsContext, _ st: Stance, _ x: Double, _ y: Double, _ z: Double, _ r: Double,
             _ hue: Hue, gloss: Double = 0.45) {
        let centre = st.point(x, y, z)
        let c = lens.spot(centre)
        let cx = Double(c.x), cy = Double(c.y)
        let R = r * s
        var dim = st.dim
        var target = ctx
        if st.sinking && centre.z < -r * 0.4 {
            guard let under = st.below else { return }
            target = under
            dim = 1 - (1 - st.dim) * (1 - Curve.clamp(-centre.z / (st.holeR * 1.4)) * 0.6)
        }
        let dark = Tone.pitFloor
        target.fill(disc(c, R), with: .color(hue.shade.toward(dark, dim).paint()))
        target.fill(disc(CGPoint(x: cx - 0.10 * R, y: cy - 0.11 * R), 0.87 * R), with: .color(hue.toward(dark, dim).paint()))
        target.fill(disc(CGPoint(x: cx - 0.27 * R, y: cy - 0.30 * R), 0.5 * R),
                    with: .color(hue.sunlit.toward(dark, dim).paint(0.85)))
        if gloss > 0 {
            target.fill(disc(CGPoint(x: cx - 0.40 * R, y: cy - 0.44 * R), 0.14 * R),
                        with: .color(Color.white.opacity(gloss * (1 - dim))))
        }
    }

    // MARK: Ground

    /// Shapes drawn flat on the ground, given in ground coordinates.
    func slab(_ x: Double, _ y: Double, _ hw: Double, _ hd: Double, _ corner: Double) -> Path {
        Path(roundedRect: CGRect(x: x - hw, y: y - hd, width: 2 * hw, height: 2 * hd), cornerRadius: corner).applying(lens.ground)
    }

    func oval(_ x: Double, _ y: Double, _ rx: Double, _ ry: Double) -> Path {
        Path(ellipseIn: CGRect(x: x - rx, y: y - ry, width: 2 * rx, height: 2 * ry)).applying(lens.ground)
    }

    private var roadShading: GraphicsContext.Shading {
        .linearGradient(
            Gradient(colors: [Tone.road.toward(.white, 0.1).paint(), Tone.road.paint(), Tone.road.toward(Tone.shadow, 0.12).paint()]),
            startPoint: .zero, endPoint: CGPoint(x: W * 0.35, y: H))
    }

    func drawGround(_ ctx: inout GraphicsContext) {
        if let edge {
            drawIsland(&ctx, edge)
        } else {
            ctx.fill(Path(CGRect(x: 0, y: 0, width: W, height: H)), with: roadShading)
        }
        drawRoadMarkings(&ctx)
        let reach = Town.lotSize / 2 + 1
        let seen = lens.seen
        for lot in town.lots {
            if lot.cx + reach < seen.x0 || lot.cx - reach > seen.x1 || lot.cy + reach < seen.y0 || lot.cy - reach > seen.y1 { continue }
            drawLot(&ctx, lot)
        }
        drawFootings(&ctx)
    }

    /// A city with an edge sits on a slab in the water.
    private func drawIsland(_ ctx: inout GraphicsContext, _ edge: GulpCityEdge) {
        ctx.fill(Path(CGRect(x: 0, y: 0, width: W, height: H)), with: .linearGradient(
            Gradient(colors: [Tone.waterPale.toward(Tone.water, 0.45).paint(), Tone.water.paint(),
                              Tone.water.toward(Tone.shadow, 0.16).paint()]),
            startPoint: .zero, endPoint: CGPoint(x: W * 0.35, y: H)))
        let hw = (edge.east - edge.west) / 2, hd = (edge.south - edge.north) / 2
        let mx = (edge.west + edge.east) / 2, my = (edge.north + edge.south) / 2
        let shore = slab(mx, my, hw, hd, 1.1)
        let cliff = 0.55 * Lens.lift * s
        ctx.fill(shore.offsetBy(dx: 0, dy: cliff + 5 * u), with: .color(Tone.shadow.paint(0.2)))
        ctx.fill(shore.offsetBy(dx: 0, dy: cliff), with: .color(Tone.curb.toward(Tone.shadow, 0.14).paint()))
        ctx.fill(shore.offsetBy(dx: 0, dy: cliff * 0.45), with: .color(Tone.curb.paint()))
        ctx.fill(shore, with: .color(Tone.pavement.paint()))
        ctx.stroke(shore, with: .color(Color.white.opacity(0.7)), lineWidth: Swift.max(0.4, 1.0 * u))
        ctx.fill(slab(mx, my, hw - 0.45, hd - 0.45, 0.75), with: roadShading)
    }

    /// Lane dashes, arrows, stop lines and zebra crossings for every crossroads in view.
    private func drawRoadMarkings(_ ctx: inout GraphicsContext) {
        let pitch = Town.pitch
        let seen = lens.seen
        var i0 = Int((seen.x0 / pitch).rounded(.down)) - 1, i1 = Int((seen.x1 / pitch).rounded(.up)) + 1
        var j0 = Int((seen.y0 / pitch).rounded(.down)) - 1, j1 = Int((seen.y1 / pitch).rounded(.up)) + 1
        // with an edge, the ring road puts one street outside the blocks on every side
        let cols = edge?.cols ?? Int.max, rows = edge?.rows ?? Int.max
        let ends = edge != nil
        if ends {
            i0 = Swift.max(i0, -1)
            i1 = Swift.min(i1, cols - 1)
            j0 = Swift.max(j0, -1)
            j1 = Swift.min(j1, rows - 1)
        }
        guard i0 <= i1, j0 <= j1 else { return }
        var dashes = Path(), arrows = Path(), zebra = Path()
        let half = Town.roadWidth / 2
        let dashRound = CGSize(width: 0.05, height: 0.05)
        for j in j0...j1 {
            for i in i0...i1 {
                // the lot (i, j), and the crossroads to its south-east
                let lx = Double(i) * pitch, ly = Double(j) * pitch
                let cx = (Double(i) + 0.5) * pitch, cy = (Double(j) + 0.5) * pitch
                // the street south of the lot and the street east of it only exist beside a block
                let hasRow = !ends || i >= 0, hasCol = !ends || j >= 0
                for k in 0..<5 {
                    let off = -2.02 + Double(k) * 0.9
                    if hasRow {
                        dashes.addRoundedRect(in: CGRect(x: lx + off, y: cy - 0.055, width: 0.46, height: 0.11), cornerSize: dashRound)
                    }
                    if hasCol {
                        dashes.addRoundedRect(in: CGRect(x: cx - 0.055, y: ly + off, width: 0.11, height: 0.46), cornerSize: dashRound)
                    }
                }
                let west = hasRow, east = !ends || i + 1 < cols
                let north = hasCol, south = !ends || j + 1 < rows
                for k in 0..<5 {
                    let off = -0.8 + Double(k) * 0.4
                    if west { zebra.addRect(CGRect(x: cx - half - 0.84, y: cy + off - 0.1, width: 0.56, height: 0.2)) }
                    if east { zebra.addRect(CGRect(x: cx + half + 0.28, y: cy + off - 0.1, width: 0.56, height: 0.2)) }
                    if north { zebra.addRect(CGRect(x: cx + off - 0.1, y: cy - half - 0.84, width: 0.2, height: 0.56)) }
                    if south { zebra.addRect(CGRect(x: cx + off - 0.1, y: cy + half + 0.28, width: 0.2, height: 0.56)) }
                }
                if hasRow {
                    Self.addArrow(&arrows, lx + 1.5, cy + 0.57, 1, 0)
                    Self.addArrow(&arrows, lx - 1.5, cy - 0.57, -1, 0)
                    arrows.addRect(CGRect(x: lx + 2.02, y: cy + 0.13, width: 0.09, height: 0.9))
                    arrows.addRect(CGRect(x: lx - 2.11, y: cy - 1.03, width: 0.09, height: 0.9))
                }
                if hasCol {
                    Self.addArrow(&arrows, cx + 0.57, ly - 1.5, 0, -1)
                    Self.addArrow(&arrows, cx - 0.57, ly + 1.5, 0, 1)
                    arrows.addRect(CGRect(x: cx + 0.13, y: ly - 2.11, width: 0.9, height: 0.09))
                    arrows.addRect(CGRect(x: cx - 1.03, y: ly + 2.02, width: 0.9, height: 0.09))
                }
            }
        }
        ctx.fill(dashes.applying(lens.ground), with: .color(Tone.laneDash.paint(0.95)))
        ctx.fill(arrows.applying(lens.ground), with: .color(Color.white.opacity(0.6)))
        ctx.fill(zebra.applying(lens.ground), with: .color(Color.white.opacity(0.86)))
    }

    /// A lane arrow pointing along (dx, dy).
    private static func addArrow(_ path: inout Path, _ x: Double, _ y: Double, _ dx: Double, _ dy: Double) {
        let outline: [Flat] = [(-0.42, -0.045), (0.08, -0.045), (0.08, -0.17), (0.42, 0), (0.08, 0.17), (0.08, 0.045), (-0.42, 0.045)]
        // (along, across) -> ground
        path.addLines(outline.map { CGPoint(x: x + dx * $0.x - dy * $0.y, y: y + dy * $0.x + dx * $0.y) })
        path.closeSubpath()
    }

    private func drawLot(_ ctx: inout GraphicsContext, _ lot: GulpCityLot) {
        let half = Town.lotSize / 2
        let inside = half - Town.pavementWidth
        let cx = lot.cx, cy = lot.cy
        let kerb = slab(cx, cy, half, half, 0.62)
        let kerbHeight = 0.15 * Lens.lift * s
        ctx.fill(kerb.offsetBy(dx: 0, dy: kerbHeight + 1.8 * u), with: .color(Tone.shadow.paint(0.16)))
        ctx.fill(kerb.offsetBy(dx: 0, dy: kerbHeight), with: .color(Tone.curb.paint()))
        ctx.fill(kerb, with: .color(Tone.pavement.paint()))
        ctx.stroke(kerb, with: .color(Color.white.opacity(0.7)), lineWidth: Swift.max(0.4, 1.0 * u))
        let inner = slab(cx, cy, inside, inside, 0.34)
        switch lot.use {
        case .park:
            // the painted pond sits in the north-east quarter: mirror it into the lot's own
            let sx: Double = lot.pond % 2 == 0 ? 1 : -1
            let sy: Double = lot.pond < 2 ? 1 : -1
            drawGroundPicture(&ctx, art.park, cx, cy, inside, inner, flipX: sx, flipY: sy)
            ctx.stroke(inner, with: .color(Tone.lawnEdge.paint(0.9)), lineWidth: Swift.max(0.5, 1.6 * u))
        case .midrise, .tower:
            ctx.fill(inner, with: .color(Tone.lot.paint()))
            var seams = Path()
            seams.addRect(CGRect(x: cx - inside, y: cy - 0.03, width: 2 * inside, height: 0.06))
            seams.addRect(CGRect(x: cx - 0.03, y: cy - inside, width: 0.06, height: 2 * inside))
            ctx.fill(seams.applying(lens.ground), with: .color(Tone.pad.paint(0.6)))
            if lot.use == .midrise && lot.style == 3 {
                // the pocket garden takes one of the four plots
                let gx = cx + (lot.pond % 2 == 0 ? -1.37 : 1.37), gy = cy + (lot.pond < 2 ? -1.37 : 1.37)
                let patch = slab(gx, gy, 1.16, 1.16, 0.34)
                ctx.fill(patch, with: .color(Tone.lawn.paint()))
                ctx.stroke(patch, with: .color(Tone.lawnEdge.paint(0.9)), lineWidth: Swift.max(0.5, 1.4 * u))
            }
        case .houses:
            // a shared pool on the first two styles
            drawGroundPicture(&ctx, lot.style < 2 ? art.yardPool : art.yard, cx, cy, inside, inner)
            ctx.stroke(inner, with: .color(Tone.lawnEdge.paint(0.7)), lineWidth: Swift.max(0.5, 1.4 * u))
        case .plaza:
            drawGroundPicture(&ctx, art.plaza, cx, cy, inside, inner)
        }
    }

    /// A painted square laid flat on the ground over a lot, mirrored when asked, inside its rounded edge.
    private func drawGroundPicture(_ ctx: inout GraphicsContext, _ image: GraphicsContext.ResolvedImage,
                                   _ cx: Double, _ cy: Double, _ half: Double, _ edge: Path,
                                   flipX: Double = 1, flipY: Double = 1) {
        var flat = ctx
        flat.clip(to: edge)
        flat.concatenate(lens.ground)
        flat.translateBy(x: cx, y: cy)
        flat.scaleBy(x: flipX, y: flipY)
        flat.draw(image, in: CGRect(x: -half, y: -half, width: 2 * half, height: 2 * half))
    }

    /// What a prop stands on. It stays behind as a bare patch once the prop is gone.
    private func drawFootings(_ ctx: inout GraphicsContext) {
        let seen = lens.seen
        for prop in town.props {
            if prop.x < seen.x0 - 3 || prop.x > seen.x1 + 3 || prop.y < seen.y0 - 3 || prop.y > seen.y1 + 3 { continue }
            switch prop.kind {
            case .building:
                ctx.fill(slab(prop.x, prop.y, prop.halfW + 0.13, prop.halfD + 0.13, 0.36), with: .color(Tone.pad.paint()))
                ctx.fill(slab(prop.x, prop.y, prop.halfW - 0.02, prop.halfD - 0.02, 0.26), with: .color(Hue(0xE9C79E).paint()))
                ctx.fill(slab(prop.x + 0.05, prop.y + 0.05, prop.halfW - 0.1, prop.halfD - 0.1, 0.22), with: .color(Hue(0xF0D2AC).paint()))
            case .house:
                ctx.fill(slab(prop.x, prop.y, prop.halfW + 0.06, prop.halfD + 0.06, 0.16), with: .color(Hue(0xF4DDB8).paint()))
            case .kiosk:
                ctx.fill(slab(prop.x, prop.y, prop.halfW + 0.06, prop.halfD + 0.06, 0.16), with: .color(Tone.path.paint()))
            case .tree where prop.pit:
                ctx.fill(slab(prop.x, prop.y, 0.23, 0.23, 0.09), with: .color(Hue(0xE2BE94).paint()))
                ctx.fill(slab(prop.x, prop.y, 0.15, 0.15, 0.07), with: .color(Hue(0xCFA57C).paint()))
            default:
                break
            }
        }
    }

    /// A four-pointed sparkle.
    static func glint(_ c: CGPoint, _ r: Double, pinch: Double = 0.22) -> Path {
        var path = Path()
        var points: [CGPoint] = []
        points.reserveCapacity(8)
        for k in 0..<8 {
            let a = Double(k) * Double.pi / 4 - Double.pi / 2
            let reach = k % 2 == 0 ? r : r * pinch
            points.append(CGPoint(x: Double(c.x) + cos(a) * reach, y: Double(c.y) + sin(a) * reach))
        }
        path.addLines(points)
        path.closeSubpath()
        return path
    }

    // MARK: Poses

    /// How far a prop tips over on its way down.
    private static func fullLean(_ kind: GulpCityKind) -> Double {
        switch kind {
        case .building: return 0.92
        case .house, .kiosk, .fountain: return 1.0
        case .car, .bus: return 1.2
        default: return 1.35
        }
    }

    /// This frame's pose of one prop. fall is the progress of its fall (-1 while it stands), nudge
    /// (0...1) is how far a standing prop already leans towards the hole. nil when it is off screen.
    func pose(_ index: Int, _ prop: Prop, fall: Double, nudge: Double,
              holeX: Double, holeY: Double, holeR: Double) -> Pose? {
        var x = prop.x, y = prop.y, z = 0.0, lean = 0.0, dim = 0.0, alpha = 1.0
        var tx = holeX - prop.x, ty = holeY - prop.y
        let away = Swift.max(1e-6, (tx * tx + ty * ty).squareRoot())
        tx /= away
        ty /= away
        let narrow = Swift.min(prop.halfW, prop.halfD)
        if fall >= 0 {
            // tips, slides to the middle of the hole, then drops and fades into the dark
            lean = 0.12 + (Self.fullLean(prop.kind) - 0.12) * Curve.ramp(0, 0.9, fall)
            let slide = Curve.ramp(0.22, 1.0, fall) * 0.84
            x += (holeX - prop.x) * slide
            y += (holeY - prop.y) * slide
            let hop = narrow * sin(0.12) * (1 - Curve.ramp(0, 0.3, fall))
            z = hop - (0.25 * fall * fall + 0.75 * fall * fall * fall) * (prop.tall * 0.85 + holeR * 0.7)
            dim = Curve.ramp(0.5, 1.0, fall) * 0.4
            alpha = 1 - Curve.ramp(0.84, 1.0, fall)
        } else if nudge > 0 {
            lean = 0.12 * nudge
            z = narrow * sin(lean)
        }
        let spill = lean > 0.001 ? prop.tall * sin(lean) + 0.05 : 0
        let west = x - prop.halfW - spill, east = x + prop.halfW + spill
        let north = y - prop.halfD - spill, south = y + prop.halfD + spill
        let high = Swift.max(0.1, z + prop.tall * rise), low = Swift.min(0, z)
        var left = Double.infinity, right = -Double.infinity, top = Double.infinity, bottom = -Double.infinity
        for corner in [(west, north), (east, north), (east, south), (west, south)] {
            for height in [low, high] {
                let p = lens.spot(corner.0, corner.1, height)
                left = Swift.min(left, Double(p.x))
                right = Swift.max(right, Double(p.x))
                top = Swift.min(top, Double(p.y))
                bottom = Swift.max(bottom, Double(p.y))
            }
        }
        if right < -6 || left > W + 6 || bottom < -6 || top > H + 6 { return nil }
        return Pose(prop: index, x: x, y: y, z: z, lean: lean, towardX: tx, towardY: ty, fall: fall, dim: dim, alpha: alpha,
                    west: west, east: east, north: north, south: south,
                    depth: x * Lens.sinTurn + y * Lens.cosTurn,
                    left: left, right: right, top: top, bottom: bottom, holeX: holeX, holeY: holeY, holeR: holeR)
    }

    /// Back to front. Sorting by depth alone gets long props wrong, so every pair that overlaps on
    /// screen is also asked which one is behind, and the answers are honoured where they agree.
    func paintOrder(_ poses: [Pose]) -> [Int] {
        let n = poses.count
        if n < 2 { return Array(0..<n) }
        let byDepth = (0..<n).sorted { poses[$0].depth < poses[$1].depth }
        var before: [Int32] = [], after: [Int32] = []
        before.reserveCapacity(n * 4)
        after.reserveCapacity(n * 4)
        var waiting = [Int32](repeating: 0, count: n)
        var start = [Int32](repeating: 0, count: n + 1)
        let slack = 0.02
        for ai in 0..<(n - 1) {
            let ia = byDepth[ai]
            let a = poses[ia]
            for bi in (ai + 1)..<n {
                let ib = byDepth[bi]
                let b = poses[ib]
                if a.right < b.left || b.right < a.left || a.bottom < b.top || b.bottom < a.top { continue }
                // a comes first unless b is clearly north of it, or clearly east of it
                var bFirst = false
                if a.south <= b.north + slack {
                    bFirst = false
                } else if b.south <= a.north + slack {
                    bFirst = true
                } else if a.west >= b.east - slack {
                    bFirst = false
                } else if b.west >= a.east - slack {
                    bFirst = true
                }
                let first = bFirst ? ib : ia, second = bFirst ? ia : ib
                before.append(Int32(first))
                after.append(Int32(second))
                waiting[second] += 1
                start[first + 1] += 1
            }
        }
        // followers of each pose, packed into one array
        for k in 0..<n { start[k + 1] += start[k] }
        var fill = start
        var followers = [Int32](repeating: 0, count: before.count)
        for e in before.indices {
            let first = Int(before[e])
            followers[Int(fill[first])] = after[e]
            fill[first] += 1
        }
        var order: [Int] = []
        order.reserveCapacity(n)
        var placed = [Bool](repeating: false, count: n)
        var head = 0
        while order.count < n {
            // the farthest pose that nothing still has to go behind
            var next = -1
            var k = head
            while k < n {
                let c = byDepth[k]
                if !placed[c] && waiting[c] == 0 {
                    next = c
                    break
                }
                k += 1
            }
            // the answers ran in a circle: fall back to plain depth
            if next < 0 { next = byDepth[head] }
            placed[next] = true
            order.append(next)
            for e in Int(start[next])..<Int(start[next + 1]) { waiting[Int(followers[e])] -= 1 }
            while head < n && placed[byDepth[head]] { head += 1 }
        }
        return order
    }

    private func stance(_ pose: Pose, _ prop: Prop) -> Stance {
        let headings: [Flat] = [(1, 0), (0, 1), (-1, 0), (0, -1)]
        let heading = headings[((prop.turns % 4) + 4) % 4]
        var right = Vec(heading.x, heading.y, 0), ahead = Vec(-heading.y, heading.x, 0), up = Vec(0, 0, 1)
        if pose.lean > 0.0005 {
            // tip about the level axis square to the way to the hole
            let axis = Vec(-pose.towardY, pose.towardX, 0)
            let c = cos(pose.lean), sn = sin(pose.lean)
            func tip(_ v: Vec) -> Vec { v * c + axis.cross(v) * sn + axis * (axis.dot(v) * (1 - c)) }
            right = tip(right)
            ahead = tip(ahead)
            up = tip(up)
        }
        var st = Stance()
        st.base = Vec(pose.x, pose.y, pose.z)
        st.right = right
        st.ahead = ahead
        st.up = up
        st.grow = up * rise
        st.sinking = pose.fall >= 0
        st.dim = pose.dim
        st.holeR = pose.holeR
        return st
    }

    func mouth(_ x: Double, _ y: Double, _ r: Double) -> Path {
        let c = spot(x, y)
        let rx = r * s, ry = r * s * Lens.squash
        return Path(ellipseIn: CGRect(x: Double(c.x) - rx, y: Double(c.y) - ry, width: 2 * rx, height: 2 * ry))
    }

    func drawProps(_ ctx: inout GraphicsContext, _ poses: [Pose]) {
        for i in paintOrder(poses) {
            let pose = poses[i]
            let prop = town.props[pose.prop]
            var st = stance(pose, prop)
            if pose.fall < 0 {
                drawProp(&ctx, st, prop)
                continue
            }
            let hole = mouth(pose.holeX, pose.holeY, pose.holeR)
            if pose.alpha < 0.999 {
                // fade the prop as one piece, not face by face
                var fading = ctx
                fading.opacity = pose.alpha
                fading.drawLayer { layer in
                    var under = layer
                    under.clip(to: hole)
                    st.below = under
                    self.drawProp(&layer, st, prop)
                }
            } else {
                var under = ctx
                under.clip(to: hole)
                st.below = under
                drawProp(&ctx, st, prop)
            }
        }
    }

    // MARK: Shadows

    /// Every shadow goes into one layer, so overlapping shadows do not add up.
    func drawShadows(_ ctx: inout GraphicsContext, _ poses: [Pose]) {
        // the sun's direction along the ground, per unit of height
        let castX = 0.857 * 0.42, castY = 0.514 * 0.42
        var group = ctx
        group.opacity = 0.36
        group.drawLayer { layer in
            for pose in poses {
                let prop = self.town.props[pose.prop]
                var strength = 1.0
                if pose.fall >= 0 { strength = 1 - Curve.ramp(0.0, 0.5, pose.fall) }
                if strength < 0.03 { continue }
                let shade = GraphicsContext.Shading.color(Tone.shadow.paint(strength))
                let tall = prop.tall * self.rise
                let ox = castX * tall, oy = castY * tall
                let x = pose.x, y = pose.y
                switch prop.kind {
                case .tree:
                    let r = 0.47 * prop.scale
                    let crown = 1.05 * prop.scale * self.rise
                    let cx = x + castX * crown, cy = y + castY * crown
                    layer.fill(self.oval(cx, cy, r * 1.08, r * 0.92), with: shade)
                    layer.fill(self.groundPoly([(x - 0.03, y - 0.07), (cx, cy - 0.1), (cx, cy + 0.1), (x + 0.03, y + 0.07)]), with: shade)
                case .bush, .flowers:
                    layer.fill(self.oval(x + 0.12, y + 0.07, 0.4, 0.27), with: shade)
                case .person:
                    layer.fill(self.oval(x + ox * 0.5, y + oy * 0.5, 0.15 + ox * 0.5, 0.14), with: shade)
                case .lamp:
                    layer.fill(self.groundPoly([(x, y - 0.035), (x + ox, y + oy - 0.035), (x + ox, y + oy + 0.035), (x, y + 0.035)]), with: shade)
                    layer.fill(self.oval(x + ox, y + oy, 0.13, 0.12), with: shade)
                case .parasol:
                    layer.fill(self.oval(x + castX * 0.75, y + castY * 0.75, 0.56, 0.52), with: shade)
                case .fountain:
                    layer.fill(self.oval(x + castX * 0.3, y + castY * 0.3, 1.0, 1.0), with: shade)
                case .bin, .cone:
                    layer.fill(self.oval(x + ox * 0.6, y + oy * 0.6, 0.13 + ox * 0.5, 0.12), with: shade)
                default:
                    // boxes: the footprint swept along the sun's direction
                    let x0 = x - prop.halfW + 0.04, x1 = x + prop.halfW - 0.02
                    let y0 = y - prop.halfD + 0.04, y1 = y + prop.halfD - 0.02
                    let sweep = self.groundPoly([(x0, y0), (x1, y0), (x1 + ox, y0 + oy), (x1 + ox, y1 + oy), (x0 + ox, y1 + oy), (x0, y1)])
                    layer.fill(sweep, with: shade)
                    layer.stroke(sweep, with: shade, style: StrokeStyle(lineWidth: 0.2 * self.s, lineJoin: .round))
                }
            }
        }
    }

    private func groundPoly(_ points: [Flat]) -> Path {
        var path = Path()
        path.addLines(points.map { CGPoint(x: $0.x, y: $0.y) })
        path.closeSubpath()
        return path.applying(lens.ground)
    }

    // MARK: The hole

    /// Part of an ellipse as an open line.
    private func sweep(_ c: CGPoint, _ rx: Double, _ ry: Double, _ from: Double, _ to: Double, steps: Int = 30) -> Path {
        var points: [CGPoint] = []
        points.reserveCapacity(steps + 1)
        for k in 0...steps {
            let a = from + (to - from) * Double(k) / Double(steps)
            points.append(CGPoint(x: Double(c.x) + rx * cos(a), y: Double(c.y) + ry * sin(a)))
        }
        var path = Path()
        path.addLines(points)
        return path
    }

    /// Streaks on the ground being drawn in towards the hole.
    func drawWhirl(_ ctx: inout GraphicsContext, _ x: Double, _ y: Double, _ r: Double, turn: Double) {
        let streaks = 7
        let arc = 0.95, pull = r * 0.38
        let style = StrokeStyle(lineWidth: Swift.max(0.6, 2.4 * u), lineCap: .round, lineJoin: .round)
        for m in 0..<streaks {
            let a0 = turn + Double(m) / Double(streaks) * 2 * Double.pi
            let r0 = r * (1.62 - 0.1 * Double(m % 3))
            var points: [CGPoint] = []
            points.reserveCapacity(17)
            for k in 0...16 {
                let f = Double(k) / 16
                let a = a0 + f * arc
                let reach = r0 - f * pull
                points.append(spot(x + cos(a) * reach, y + sin(a) * reach))
            }
            var streak = Path()
            streak.addLines(points)
            // invisible at the tail, bright where it reaches the hole
            ctx.stroke(streak, with: .linearGradient(
                Gradient(colors: [Color.white.opacity(0), Color.white.opacity(0.75)]),
                startPoint: points[0], endPoint: points[16]), style: style)
        }
    }

    func drawHole(_ ctx: inout GraphicsContext, _ x: Double, _ y: Double, _ r: Double, turn: Double) {
        let c = spot(x, y)
        let cx = Double(c.x), cy = Double(c.y)
        let rx = r * s, ry = r * s * Lens.squash
        let hole = Path(ellipseIn: CGRect(x: cx - rx, y: cy - ry, width: 2 * rx, height: 2 * ry))

        // the ground darkens towards the mouth
        ctx.drawLayer { layer in
            layer.translateBy(x: cx, y: cy)
            layer.scaleBy(x: 1, y: Lens.squash)
            let glow = rx * 1.36
            layer.fill(Path(ellipseIn: CGRect(x: -glow, y: -glow, width: 2 * glow, height: 2 * glow)),
                       with: .radialGradient(Gradient(stops: [
                        .init(color: Tone.shadow.paint(0.5), location: 0),
                        .init(color: Tone.shadow.paint(0.5), location: 0.735),
                        .init(color: Tone.shadow.paint(0.2), location: 0.83),
                        .init(color: Tone.shadow.paint(0), location: 1)]),
                                             center: .zero, startRadius: 0, endRadius: glow))
        }
        // a pale bevel round the rim
        let rim = Swift.max(1.0, 0.085 * r * s)
        ctx.stroke(Path(ellipseIn: CGRect(x: cx - rx - rim * 0.5, y: cy - ry - rim * 0.5 * Lens.squash,
                                          width: 2 * rx + rim, height: 2 * ry + rim * Lens.squash)),
                   with: .linearGradient(
                    Gradient(colors: [Color.white.opacity(0.9), Color.white.opacity(0.55), Hue(0xD9C7F2).paint(0.75)]),
                    startPoint: CGPoint(x: cx - rx, y: cy - ry), endPoint: CGPoint(x: cx + rx, y: cy + ry)),
                   lineWidth: rim)

        ctx.drawLayer { layer in
            layer.clip(to: hole)
            // a sliver of pavement in section at the far lip, then the vortex turning below it
            layer.fill(hole, with: .color(Hue(0xE8CFA6).paint()))
            let crust = Swift.max(1.2, 0.1 * self.s)
            var swirl = layer
            swirl.clip(to: hole.offsetBy(dx: 0, dy: crust))
            swirl.translateBy(x: cx, y: cy + crust)
            swirl.scaleBy(x: 1, y: Lens.squash)
            swirl.rotate(by: .radians(turn))
            swirl.draw(self.art.hole, in: CGRect(x: -rx * 1.04, y: -rx * 1.04, width: 2.08 * rx, height: 2.08 * rx))
            // the far wall falls into shade under the lip
            layer.fill(hole, with: .linearGradient(
                Gradient(colors: [Tone.pitFloor.paint(0.55), Tone.pitFloor.paint(0)]),
                startPoint: CGPoint(x: cx, y: cy - ry), endPoint: CGPoint(x: cx, y: cy - ry * 0.3)))
        }
        // a dark line on the far lip, a bright one on the near lip
        ctx.stroke(sweep(c, rx, ry, Double.pi * 1.02, Double.pi * 1.98), with: .color(Tone.ink.paint(0.55)),
                   style: StrokeStyle(lineWidth: Swift.max(0.5, 1.3 * u), lineCap: .round))
        ctx.stroke(sweep(c, rx, ry, Double.pi * 0.06, Double.pi * 0.94), with: .color(Color.white.opacity(0.75)),
                   style: StrokeStyle(lineWidth: Swift.max(0.6, 1.8 * u), lineCap: .round))
    }

    /// The ground splits at the rim while something heavy goes down.
    func drawCracks(_ ctx: inout GraphicsContext, _ poses: [Pose]) {
        for pose in poses where pose.fall >= 0 {
            let prop = town.props[pose.prop]
            if prop.worth < 20 { continue }
            let alpha = Curve.ramp(0, 0.08, pose.fall) * (1 - Curve.ramp(0.7, 1.0, pose.fall))
            if alpha < 0.02 { continue }
            var dice = Dice(seed: prop.seed &+ 404)
            let towards = atan2(prop.y - pose.holeY, prop.x - pose.holeX)
            let spread = 0.45 + 0.55 * Curve.settle(pose.fall / 0.5)
            let size = prop.kind == .building ? 1.3 : 0.95
            for _ in 0..<6 {
                // a wandering line out from the rim
                var heading = towards + dice.roll(-1.15, 1.15)
                var gx = pose.holeX + cos(heading) * pose.holeR * 0.99, gy = pose.holeY + sin(heading) * pose.holeR * 0.99
                var spine: [(x: Double, y: Double, dx: Double, dy: Double)] = [(gx, gy, cos(heading), sin(heading))]
                let pieces = 3 + dice.pick(2)
                for _ in 0..<pieces {
                    heading += dice.roll(-0.55, 0.55)
                    let step = dice.roll(0.18, 0.36) * spread * size
                    gx += cos(heading) * step
                    gy += sin(heading) * step
                    spine.append((gx, gy, cos(heading), sin(heading)))
                }
                // widest at the rim, closing to a point
                let width = dice.roll(0.07, 0.12) * size
                var left: [CGPoint] = [], right: [CGPoint] = []
                for (k, joint) in spine.enumerated() {
                    let half = width * (1 - Double(k) / Double(spine.count - 1))
                    left.append(spot(joint.x - joint.dy * half, joint.y + joint.dx * half))
                    right.append(spot(joint.x + joint.dy * half, joint.y - joint.dx * half))
                }
                var lip = Path()
                lip.addLines(right)
                ctx.stroke(lip.offsetBy(dx: 0, dy: Swift.max(0.5, 1.1 * u)), with: .color(Color.white.opacity(0.6 * alpha)),
                           style: StrokeStyle(lineWidth: Swift.max(0.4, 1.1 * u), lineCap: .round, lineJoin: .round))
                var wedge = Path()
                wedge.addLines(left + right.reversed())
                wedge.closeSubpath()
                ctx.fill(wedge, with: .color(Tone.pitWall.toward(Tone.pitMid, 0.4).paint(0.8 * alpha)))
            }
        }
    }

    // MARK: Dust and debris

    private func puff(_ ctx: inout GraphicsContext, _ c: CGPoint, _ r: Double, _ alpha: Double) {
        let x = Double(c.x), y = Double(c.y)
        ctx.fill(disc(CGPoint(x: x + 0.08 * r, y: y + 0.12 * r), r), with: .color(Hue(0xCDB9DE).paint(alpha * 0.85)))
        ctx.fill(disc(c, r * 0.94), with: .color(Hue(0xFFF3E2).paint(alpha)))
        ctx.fill(disc(CGPoint(x: x - 0.2 * r, y: y - 0.24 * r), r * 0.5), with: .color(Hue(0xFFFDF8).paint(alpha * 0.95)))
    }

    /// How much commotion a prop makes on its way down, 0...1.
    private static func commotion(_ kind: GulpCityKind) -> Double {
        switch kind {
        case .building: return 1.0
        case .house, .fountain: return 0.7
        case .bus: return 0.62
        case .car, .kiosk: return 0.5
        case .tree: return 0.4
        default: return 0.26
        }
    }

    func drawDebris(_ ctx: inout GraphicsContext, _ poses: [Pose]) {
        for pose in poses where pose.fall >= 0 {
            let prop = town.props[pose.prop]
            let big = Self.commotion(prop.kind)
            let t = pose.fall
            let alpha = Curve.ramp(0, 0.1, t) * (1 - Curve.ramp(0.6, 1.0, t))
            if alpha < 0.02 { continue }
            var dice = Dice(seed: prop.seed &+ 99)
            let towards = atan2(prop.y - pose.holeY, prop.x - pose.holeX)
            // chips of the prop's own colours fly off the heavy ones
            if big >= 0.5 {
                let colours: [Hue]
                switch prop.kind {
                case .building: colours = [Tone.facades[prop.tint % 8], Tone.cream, Tone.facades[prop.tint % 8].sunlit]
                case .house: colours = [Tone.roofs[prop.tint % 6], Tone.cream]
                default: colours = [Tone.cars[prop.tint % 7], Hue(0xDCDFF0)]
                }
                let chips = Int(6 + big * 10)
                for k in 0..<chips {
                    let a = towards + dice.roll(-1.3, 1.3)
                    let speed = dice.roll(0.5, 1.9) * big
                    let gx = pose.x + cos(a) * (prop.halfW * 0.6 + speed * t * 1.6)
                    let gy = pose.y + sin(a) * (prop.halfD * 0.6 + speed * t * 1.6)
                    let start = prop.tall * dice.roll(0.15, 0.8)
                    let toss = dice.roll(1.5, 4.0)
                    let z = start + toss * big * t - 5.2 * big * t * t
                    if z < 0 { continue }
                    let at = spot(gx, gy, z)
                    let size = dice.roll(1.6, 4.2) * u * (0.6 + big * 0.5)
                    let tilt = dice.roll(0, 3.1)
                    let spin = tilt + t * dice.roll(-9, 9)
                    // a lopsided diamond
                    var chip = Path()
                    chip.addLines((0..<4).map { m in
                        let ca = spin + Double(m) * Double.pi / 2
                        let reach = m % 2 == 0 ? size : size * 0.62
                        return CGPoint(x: Double(at.x) + cos(ca) * reach, y: Double(at.y) + sin(ca) * reach)
                    })
                    chip.closeSubpath()
                    ctx.fill(chip, with: .color(colours[k % colours.count].paint(alpha)))
                }
            }
            // dust rising along the stretch of rim the prop went over
            let puffs = Int(3 + big * 7)
            let arc = Swift.min(0.95, (Swift.max(prop.halfW, prop.halfD) + 0.3) / Swift.max(0.5, pose.holeR))
            for _ in 0..<puffs {
                let a = towards + dice.roll(-1, 1) * arc
                let ring = pose.holeR * dice.roll(0.97, 1.08)
                let reach = ring + t * dice.roll(0.0, 0.5) * big
                let low = dice.roll(0.02, 0.25) * big
                let z = low + t * dice.roll(0.2, 1.1) * big
                let r = (0.13 + 0.3 * big) * dice.roll(0.5, 1.3) * (0.55 + 0.8 * t) * s * pow(alpha, 0.7)
                puff(&ctx, spot(pose.holeX + cos(a) * reach, pose.holeY + sin(a) * reach, z), r,
                     Swift.min(1, alpha * 2.5) * dice.roll(0.85, 1))
            }
        }
    }

    /// A ring that widens from the rim just after a bite. age runs 0...1.
    func drawRipple(_ ctx: inout GraphicsContext, _ x: Double, _ y: Double, _ r: Double, age: Double) {
        let c = spot(x, y)
        let rx = r * s * (1.06 + 0.4 * Curve.settle(age)), ry = rx * Lens.squash
        ctx.stroke(Path(ellipseIn: CGRect(x: Double(c.x) - rx, y: Double(c.y) - ry, width: 2 * rx, height: 2 * ry)),
                   with: .color(Color.white.opacity(0.8 * (1 - age))), lineWidth: Swift.max(0.6, 3.2 * u * (1 - age * 0.6)))
    }

    /// Warm light from the top left, pale haze at the top, a cool tint at the bottom.
    func drawHaze(_ ctx: inout GraphicsContext) {
        let screen = Path(CGRect(x: 0, y: 0, width: W, height: H))
        let warm = Hue(0xFFF1C4)
        ctx.fill(screen, with: .radialGradient(
            Gradient(colors: [warm.paint(0.26), warm.paint(0.08), warm.paint(0)]),
            center: CGPoint(x: -W * 0.08, y: H * 0.04), startRadius: 0, endRadius: W * 1.5))
        ctx.fill(screen, with: .linearGradient(
            Gradient(stops: [
                .init(color: Hue(0xEAF6FF).paint(0.24), location: 0),
                .init(color: Hue(0xEAF6FF).paint(0), location: 0.18),
                .init(color: Hue(0x6F86DC).paint(0), location: 0.74),
                .init(color: Hue(0x6F86DC).paint(0.13), location: 1)]),
            startPoint: .zero, endPoint: CGPoint(x: 0, y: H)))
    }

    // MARK: Props

    func drawProp(_ ctx: inout GraphicsContext, _ st: Stance, _ prop: Prop) {
        switch prop.kind {
        case .building: drawBuilding(&ctx, st, prop)
        case .house: drawHouse(&ctx, st, prop)
        case .car, .bus: drawVehicle(&ctx, st, prop)
        case .tree: drawTree(&ctx, st, prop)
        case .bush: drawBush(&ctx, st, prop)
        case .flowers: drawFlowers(&ctx, st, prop)
        case .bench: drawBench(&ctx, st, prop)
        case .person: drawPerson(&ctx, st, prop)
        case .lamp: drawLamp(&ctx, st, prop)
        case .parasol: drawParasol(&ctx, st, prop)
        case .kiosk: drawKiosk(&ctx, st, prop)
        case .bin: drawBin(&ctx, st, prop)
        case .cone: drawCone(&ctx, st)
        case .fountain: drawFountain(&ctx, st)
        }
    }

    /// Window glass on a wall: brighter where the wall faces the sun, darker towards the sill.
    private func glass(_ out: Vec, warm: Bool) -> (top: Hue, sill: Hue) {
        let k = Curve.clamp((out.dot(Self.sun) + 0.4) / 0.9)
        let dull = warm ? Hue(0xF6E2BC) : Hue(0xA6CFF5)
        let bright = warm ? Hue(0xFFFBEA) : Hue(0xF2FAFF)
        let top = dull.toward(bright, k)
        return (top, top.toward(dull.shade, 0.4))
    }

    private func drawBuilding(_ ctx: inout GraphicsContext, _ st: Stance, _ prop: Prop) {
        let hw = prop.halfW, hd = prop.halfD, tall = prop.tall
        let tintIndex = prop.tint % Tone.facades.count
        let body = Tone.facades[tintIndex]
        let warm = tintIndex == 0 || tintIndex == 7 || tintIndex == 4
        solid(&ctx, st, Self.rounded(hw, hd, 0.26), 0, tall, body, body, fade: 0.13)

        // 0 = a grid of windows, 1 = ribbon windows, 2 = tall strips
        let windows = prop.style % 3
        let margin = 0.36
        let sill = 0.9, head = tall - 0.32
        for (side, wall) in Self.walls(hw, hd).enumerated() {
            let out = st.level(wall.outX, wall.outY)
            if lens.facing(out) <= 0 { continue }
            var dice = Dice(seed: prop.seed &+ UInt64(side) &* 977)
            let pane = glass(out, warm: warm)
            if head - sill > 0.3 {
                if windows == 1 {
                    let floors = Swift.max(1, Int((head - sill) / 0.6))
                    let step = (head - sill) / Double(floors)
                    for floor in 0..<floors {
                        let z = sill + Double(floor) * step + step * 0.2
                        panel(&ctx, st, wall, margin - 0.08, wall.length - margin + 0.08, z, z + step * 0.52, pane.top, pane.sill)
                    }
                } else {
                    let strips = windows == 2
                    let across = Swift.max(1, Int((wall.length - 2 * margin) / (strips ? 0.5 : 0.58)))
                    let bay = (wall.length - 2 * margin) / Double(across)
                    let floors = strips ? 1 : Swift.max(1, Int((head - sill) / 0.58))
                    let step = (head - sill) / Double(floors)
                    for floor in 0..<floors {
                        for k in 0..<across {
                            let a = margin + Double(k) * bay + bay * 0.19
                            let z = sill + Double(floor) * step + (strips ? 0.0 : step * 0.2)
                            let height = strips ? head - sill : step * 0.56
                            // a few rooms in a grid have their blinds down
                            if windows == 0 && dice.roll() < 0.16 {
                                let blind = pane.top.toward(body.shade, 0.55)
                                panel(&ctx, st, wall, a, a + bay * 0.62, z, z + height, blind, blind)
                            } else {
                                panel(&ctx, st, wall, a, a + bay * 0.62, z, z + height, pane.top, pane.sill)
                            }
                        }
                    }
                }
            }
            // a pale band over the ground floor
            panel(&ctx, st, wall, 0.22, wall.length - 0.22, 0.66, 0.75, sunlight(body.sunlit, out))
            if side == 0 {
                // the front: a door between two shop windows
                let mid = wall.length / 2
                panel(&ctx, st, wall, mid - 0.2, mid + 0.2, 0, 0.5, sunlight(body.shade.toward(Tone.ink, 0.3), out))
                panel(&ctx, st, wall, margin - 0.06, mid - 0.34, 0.14, 0.52, pane.top, pane.sill)
                panel(&ctx, st, wall, mid + 0.34, wall.length - margin + 0.06, 0.14, 0.52, pane.top, pane.sill)
            } else {
                panel(&ctx, st, wall, margin - 0.06, wall.length - margin + 0.06, 0.2, 0.5, pane.top, pane.sill)
            }
        }
        // a striped awning over the door
        if (prop.style / 3) % 2 == 0 {
            let cloth = Tone.canvas[(prop.tint + prop.style) % Tone.canvas.count]
            solid(&ctx, st, Self.box(0.58, 0.17, 0, hd + 0.17), 0.55, 0.63, cloth, cloth, fade: 0)
            for k in 0..<3 {
                plate(&ctx, st, Self.box(0.09, 0.17, -0.36 + Double(k) * 0.36, hd + 0.17), 0.63, sunlight(Tone.cream, st.up))
            }
        }

        guard lens.facing(st.up) > 0 else { return }
        // the roof: a parapet, then the deck inside it
        let deck = body.sunlit.toward(Tone.cream, 0.55)
        plate(&ctx, st, Self.rounded(hw - 0.15, hd - 0.15, 0.17), tall, sunlight(deck, st.up).toward(deck.shade, 0.6))
        plate(&ctx, st, Self.rounded(hw - 0.22, hd - 0.21, 0.14, 0.07, 0.06), tall, sunlight(deck, st.up))
        if (prop.style / 6) % 2 == 1 && tall > 2.5 {
            // a set-back top floor with a mast
            let tw = hw * 0.6, td = hd * 0.6, top = tall + 0.85
            solid(&ctx, st, Self.rounded(tw, td, 0.2), tall, top, body, body, fade: 0.1)
            for wall in Self.walls(tw, td) {
                let out = st.level(wall.outX, wall.outY)
                if lens.facing(out) <= 0 { continue }
                let pane = glass(out, warm: warm)
                panel(&ctx, st, wall, 0.22, wall.length - 0.22, tall + 0.26, tall + 0.58, pane.top, pane.sill)
            }
            plate(&ctx, st, Self.rounded(tw - 0.12, td - 0.12, 0.12), top, sunlight(deck, st.up).toward(deck.shade, 0.45))
            let mast = Hue(0x8A84AE)
            solid(&ctx, st, Self.ring(0.035, 4, tw * 0.3, -td * 0.3), top, top + 0.8, mast, mast, fade: 0)
            orb(&ctx, st, tw * 0.3, -td * 0.3, top + 0.84, 0.075, Tone.coral, gloss: 0.6)
            return
        }
        // roof clutter on a grid, east side first because it is farther from the camera
        var dice = Dice(seed: prop.seed &+ 31)
        let across = hw > 1.5 ? 4 : 2, down = hd > 1.5 ? 4 : 2
        for j in 0..<down {
            for i in (0..<across).reversed() {
                let x = (-1 + (2 * Double(i) + 1) / Double(across)) * (hw - 0.34)
                let y = (-1 + (2 * Double(j) + 1) / Double(down)) * (hd - 0.34)
                let chance = dice.roll()
                let what = dice.pick(6)
                if chance > 0.66 { continue }
                switch what {
                case 0:
                    // an air conditioner
                    solid(&ctx, st, Self.rounded(0.25, 0.19, 0.05, x, y, steps: 2), tall, tall + 0.2, Hue(0xE3E7F3), Hue(0xF4F6FC), fade: 0)
                    plate(&ctx, st, Self.ring(0.1, 8, x, y), tall + 0.2, Hue(0xB7BEDB))
                case 1:
                    // a water tank
                    let tank = Tone.facades[(tintIndex + 3) % Tone.facades.count]
                    solid(&ctx, st, Self.ring(0.25, 10, x, y), tall, tall + 0.44, tank, tank, fade: 0.08)
                    plate(&ctx, st, Self.ring(0.15, 10, x, y), tall + 0.44, sunlight(tank.sunlit, st.up))
                case 2:
                    // a roof garden
                    plate(&ctx, st, Self.rounded(0.32, 0.27, 0.09, x, y, steps: 2), tall, Hue(0xA9E6B8))
                    orb(&ctx, st, x - 0.1, y - 0.02, tall + 0.12, 0.15, Tone.leaves[1], gloss: 0.3)
                    orb(&ctx, st, x + 0.13, y + 0.06, tall + 0.1, 0.12, Tone.leaves[2], gloss: 0.3)
                case 3:
                    // a skylight
                    plate(&ctx, st, Self.rounded(0.28, 0.22, 0.06, x, y, steps: 2), tall, Hue(0xFFFFFF))
                    plate(&ctx, st, Self.rounded(0.23, 0.17, 0.05, x, y, steps: 2), tall, Hue(0x9AD6F7))
                    plate(&ctx, st, [(x - 0.2, y - 0.14), (x - 0.02, y - 0.14), (x - 0.2, y + 0.06)], tall, Hue(0xD5F1FD))
                case 4:
                    // a pair of solar panels
                    for q in 0..<2 {
                        let px = x - 0.15 + Double(q) * 0.3
                        plate(&ctx, st, Self.box(0.12, 0.22, px, y), tall, Hue(0x5F78CF))
                        plate(&ctx, st, Self.box(0.12, 0.015, px, y), tall, Hue(0xA9BBF2))
                        plate(&ctx, st, Self.box(0.012, 0.22, px, y), tall, Hue(0xA9BBF2))
                    }
                default:
                    // the stair hut, with its door
                    solid(&ctx, st, Self.rounded(0.23, 0.2, 0.04, x, y, steps: 2), tall, tall + 0.36, body, body.sunlit, fade: 0)
                    let front = st.level(0, 1)
                    if lens.facing(front) > 0 {
                        panel(&ctx, st, Self.walls(0.23, 0.2, x, y)[0], 0.13, 0.33, tall, tall + 0.26,
                              sunlight(body.shade.toward(Tone.ink, 0.3), front))
                    }
                }
            }
        }
    }

    private func drawHouse(_ ctx: inout GraphicsContext, _ st: Stance, _ prop: Prop) {
        let hw = prop.halfW - 0.08, hd = prop.halfD - 0.08
        let walls = Tone.houseWalls[prop.style % Tone.houseWalls.count]
        let roof = Tone.roofs[prop.tint % Tone.roofs.count]
        let eaves = 0.72
        solid(&ctx, st, Self.rounded(hw, hd, 0.07, steps: 2), 0, eaves, walls, walls, fade: 0.1, lid: false)
        for (side, wall) in Self.walls(hw, hd).enumerated() {
            let out = st.level(wall.outX, wall.outY)
            if lens.facing(out) <= 0 { continue }
            let pane = glass(out, warm: false)
            let mid = wall.length / 2
            if side == 0 {
                panel(&ctx, st, wall, mid - 0.12, mid + 0.12, 0, 0.44, sunlight(roof.shade, out))
                panel(&ctx, st, wall, 0.13, mid - 0.25, 0.24, 0.52, pane.top, pane.sill)
                panel(&ctx, st, wall, mid + 0.25, wall.length - 0.13, 0.24, 0.52, pane.top, pane.sill)
            } else {
                panel(&ctx, st, wall, 0.15, mid - 0.09, 0.24, 0.52, pane.top, pane.sill)
                panel(&ctx, st, wall, mid + 0.09, wall.length - 0.15, 0.24, 0.52, pane.top, pane.sill)
            }
        }
        // a hipped roof that overhangs the walls, with its ridge running east to west
        let ox = hw + 0.11, oy = hd + 0.11, peak = 0.52
        let ridge = Swift.max(0.06, ox - oy * 0.9)
        let sw = st.point(-ox, oy, eaves), se = st.point(ox, oy, eaves)
        let ne = st.point(ox, -oy, eaves), nw = st.point(-ox, -oy, eaves)
        let ridgeW = st.point(-ridge, 0, eaves + peak), ridgeE = st.point(ridge, 0, eaves + peak)
        let inside = st.point(0, 0, eaves + 0.1)
        for slope in [[ne, nw, ridgeW, ridgeE], [se, ne, ridgeE], [nw, sw, ridgeW], [sw, se, ridgeE, ridgeW]] {
            var normal = (slope[1] - slope[0]).cross(slope[2] - slope[0]).unit
            var middle = Vec(0, 0, 0)
            for corner in slope { middle = middle + corner }
            middle = middle * (1 / Double(slope.count))
            if normal.dot(middle - inside) < 0 { normal = normal * -1 }
            if lens.facing(normal) <= 0 { continue }
            let tile = sunlight(roof, normal)
            let last = slope.count - 1
            face(&ctx, st, slope, tile.toward(tile.sunlit, 0.12), tile.toward(tile.shade, 0.25),
                 (slope[last] + slope[last - 1]) * 0.5, (slope[0] + slope[1]) * 0.5)
        }
        if lens.facing(st.up) <= 0 {
            face(&ctx, st, [sw, se, ne, nw], sunlight(walls.shade, st.up * -1))
        }
        // chimney
        solid(&ctx, st, Self.box(0.085, 0.085, ridge * 0.45, -oy * 0.38), eaves + peak * 0.6, eaves + peak + 0.12,
              Hue(0xF4A98F), Hue(0xFFE9DA), fade: 0)
    }

    private func drawVehicle(_ ctx: inout GraphicsContext, _ st: Stance, _ prop: Prop) {
        let paintwork = Tone.cars[prop.tint % Tone.cars.count]
        let bus = prop.kind == .bus
        let long = bus ? 1.3 : 0.84, wide = bus ? 0.46 : 0.42
        let floor = 0.1, roof = bus ? 0.9 : 0.46
        let tyre = Hue(0x4A4470)
        let axle = long * 0.6
        for sx in [-1.0, 1.0] {
            for sy in [-1.0, 1.0] {
                solid(&ctx, st, Self.box(0.17, 0.06, sx * axle, sy * (wide - 0.04)), 0, 0.26, tyre, tyre, fade: 0)
            }
        }
        solid(&ctx, st, Self.rounded(long, wide, 0.2), floor, roof, paintwork, paintwork, fade: 0.1)
        let walls = Self.walls(long, wide)
        // the two long sides: wheels, and on a bus a row of windows with pillars
        for side in [0, 2] {
            let wall = walls[side]
            let out = st.level(wall.outX, wall.outY)
            if lens.facing(out) <= 0 { continue }
            for sx in [-1.0, 1.0] {
                var rim: [Vec] = [], hub: [Vec] = []
                for k in 0..<10 {
                    let a = Double(k) / 10 * 2 * Double.pi
                    rim.append(st.point(sx * axle + cos(a) * 0.17, wall.y, 0.17 + sin(a) * 0.17))
                    hub.append(st.point(sx * axle + cos(a) * 0.075, wall.y, 0.17 + sin(a) * 0.075))
                }
                face(&ctx, st, rim, tyre)
                face(&ctx, st, hub, Hue(0xDCDFF0))
            }
            if bus {
                let pane = glass(out, warm: false)
                panel(&ctx, st, wall, 0.2, wall.length - 0.2, 0.48, 0.78, pane.top, pane.sill)
                for k in 1..<5 {
                    let a = 0.2 + (wall.length - 0.4) * Double(k) / 5
                    panel(&ctx, st, wall, a - 0.025, a + 0.025, 0.48, 0.78, sunlight(paintwork, out))
                }
            }
        }
        // head lights and windscreen, then tail lights and rear window
        let nose = walls[3], tail = walls[1]
        let forward = st.level(1, 0), backward = st.level(-1, 0)
        if lens.facing(forward) > 0 {
            panel(&ctx, st, nose, 0.07, 0.25, 0.22, 0.36, Hue(0xFFF7CF))
            panel(&ctx, st, nose, nose.length - 0.25, nose.length - 0.07, 0.22, 0.36, Hue(0xFFF7CF))
            if bus {
                let pane = glass(forward, warm: false)
                panel(&ctx, st, nose, 0.1, nose.length - 0.1, 0.46, 0.8, pane.top, pane.sill)
            }
        }
        if lens.facing(backward) > 0 {
            panel(&ctx, st, tail, 0.07, 0.25, 0.24, 0.36, Hue(0xFF5A70))
            panel(&ctx, st, tail, tail.length - 0.25, tail.length - 0.07, 0.24, 0.36, Hue(0xFF5A70))
            if bus {
                let pane = glass(backward, warm: false)
                panel(&ctx, st, tail, 0.12, tail.length - 0.12, 0.5, 0.8, pane.top, pane.sill)
            }
        }
        if bus {
            // a white roof with two hatches
            plate(&ctx, st, Self.rounded(long - 0.16, wide - 0.12, 0.14, steps: 2), roof, sunlight(Hue(0xFFFFFF), st.up))
            for x in [-0.5, 0.45] {
                solid(&ctx, st, Self.rounded(0.2, 0.16, 0.05, x, 0, steps: 2), roof, roof + 0.07, Hue(0xD9DDEE), Hue(0xEEF0F8), fade: 0)
            }
        } else {
            // the cabin: glass all round under a painted roof
            solid(&ctx, st, Self.rounded(long * 0.5, wide * 0.84, 0.15, -0.07, 0), roof, roof + 0.26, Hue(0xBFE3FB), paintwork, fade: 0.1)
            plate(&ctx, st, Self.rounded(long * 0.5 - 0.09, wide * 0.84 - 0.08, 0.1, -0.07, 0, steps: 2), roof + 0.26,
                  sunlight(paintwork.sunlit, st.up))
        }
    }

    private func drawTree(_ ctx: inout GraphicsContext, _ st: Stance, _ prop: Prop) {
        let k = prop.scale
        let bark = Hue(0xBC8465)
        solid(&ctx, st, Self.ring(0.1 * k, 6), 0, 0.72 * k, bark, bark, fade: 0)
        // the crown is a painted picture: tall for the second style, pink for the fifth leaf colour
        let tall = prop.style % 3 == 1
        let pink = prop.tint % Tone.leaves.count == 4
        let picture = pink ? art.treePink : (tall ? art.treeTall : art.treeRound)
        crown(&ctx, st, picture, z: (tall ? 1.15 : 1.3) * k, width: (tall ? 0.8 : 1.25) * k)
    }

    /// A painted crown standing on the prop's axis at height z, leaning with it and dimming as it goes under.
    private func crown(_ ctx: inout GraphicsContext, _ st: Stance, _ image: GraphicsContext.ResolvedImage, z: Double, width: Double) {
        let centre = st.point(0, 0, z)
        let half = width / 2
        var dim = st.dim
        var target = ctx
        if st.sinking && centre.z < -half * 0.4 {
            guard let under = st.below else { return }
            target = under
            dim = 1 - (1 - st.dim) * (1 - Curve.clamp(-centre.z / (st.holeR * 1.4)) * 0.6)
        }
        let c = lens.spot(centre)
        let foot = lens.spot(st.point(0, 0, 0))
        let w = width * s
        let h = w * Double(image.size.height) / Swift.max(1, Double(image.size.width))
        target.translateBy(x: c.x, y: c.y)
        target.rotate(by: .radians(atan2(Double(c.x - foot.x), Double(foot.y - c.y))))
        if dim > 0.01 { target.addFilter(.colorMultiply(Hue.white.toward(Tone.pitFloor, dim).paint())) }
        target.draw(image, in: CGRect(x: -w / 2, y: -h / 2, width: w, height: h))
    }

    private func drawBush(_ ctx: inout GraphicsContext, _ st: Stance, _ prop: Prop) {
        // style 0 is in bloom
        crown(&ctx, st, prop.style == 0 ? art.bushBloom : art.bush, z: 0.4, width: 0.82)
    }

    private func drawFlowers(_ ctx: inout GraphicsContext, _ st: Stance, _ prop: Prop) {
        let petals: [Hue] = [Hue(0xFF8FB3), Hue(0xFFD45E), Hue(0xFFFFFF), Hue(0xB39BFF)]
        var dice = Dice(seed: prop.seed)
        for k in 0..<6 {
            let x = dice.roll(-0.26, 0.26), y = dice.roll(-0.2, 0.2)
            orb(&ctx, st, x, y, 0.06, 0.1, Hue(0x6FD39A), gloss: 0)
            orb(&ctx, st, x, y, 0.17, 0.075, petals[(prop.tint + k) % petals.count], gloss: 0)
        }
    }

    private func drawBench(_ ctx: inout GraphicsContext, _ st: Stance, _ prop: Prop) {
        let wood = Hue(0xF0AC6C), iron = Hue(0x8A84AE)
        // the back rest goes first or last, whichever side of the seat it is on from here
        let backInFront = lens.facing(st.level(0, -1)) > 0
        func backRest(_ ctx: inout GraphicsContext) {
            solid(&ctx, st, Self.box(0.56, 0.04, 0, -0.19), 0.2, 0.58, wood.toward(wood.shade, 0.3), wood, fade: 0)
        }
        if !backInFront { backRest(&ctx) }
        solid(&ctx, st, Self.box(0.04, 0.17, -0.44, 0), 0, 0.2, iron, iron, fade: 0)
        solid(&ctx, st, Self.box(0.04, 0.17, 0.44, 0), 0, 0.2, iron, iron, fade: 0)
        solid(&ctx, st, Self.rounded(0.58, 0.2, 0.05, steps: 2), 0.2, 0.29, wood, wood, fade: 0)
        plate(&ctx, st, Self.box(0.5, 0.018, 0, 0.02), 0.29, sunlight(wood, st.up).toward(wood.shade, 0.5))
        if backInFront { backRest(&ctx) }
    }

    private func drawPerson(_ ctx: inout GraphicsContext, _ st: Stance, _ prop: Prop) {
        let shirt = Tone.shirts[prop.tint % Tone.shirts.count]
        solid(&ctx, st, Self.ring(0.15, 8), 0, 0.42, shirt, shirt, fade: 0.1)
        orb(&ctx, st, 0, 0, 0.6, 0.16, Tone.skin[prop.style % 4], gloss: 0)
        orb(&ctx, st, 0, -0.03, 0.71, 0.115, Tone.hair[(prop.style / 4) % 4], gloss: 0)
    }

    private func drawLamp(_ ctx: inout GraphicsContext, _ st: Stance, _ prop: Prop) {
        let iron = Hue(0x7F79A6)
        solid(&ctx, st, Self.ring(0.06, 6), 0, 0.08, iron, iron, fade: 0)
        solid(&ctx, st, Self.ring(0.035, 5), 0.08, 1.05, iron, iron, fade: 0)
        orb(&ctx, st, 0, 0, 1.12, 0.12, Hue(0xFFF1B5), gloss: 0.8)
    }

    private func drawParasol(_ ctx: inout GraphicsContext, _ st: Stance, _ prop: Prop) {
        // a cafe table, a pole, and a canopy of eight gores in two colours
        solid(&ctx, st, Self.ring(0.22, 8), 0, 0.3, Hue(0xFFFFFF), Hue(0xFFF6E4), fade: 0.06)
        solid(&ctx, st, Self.ring(0.03, 5), 0.3, 0.78, Hue(0xC9CCDF), Hue(0xC9CCDF), fade: 0)
        let cloth = Tone.canvas[prop.tint % Tone.canvas.count]
        let tip = st.point(0, 0, 0.96)
        let inside = st.point(0, 0, 0.5)
        let gores = 8
        for k in 0..<gores {
            let a0 = Double(k) / Double(gores) * 2 * Double.pi + 0.2
            let a1 = Double(k + 1) / Double(gores) * 2 * Double.pi + 0.2
            let p0 = st.point(cos(a0) * 0.56, sin(a0) * 0.56, 0.72), p1 = st.point(cos(a1) * 0.56, sin(a1) * 0.56, 0.72)
            var normal = (p0 - tip).cross(p1 - tip).unit
            if normal.dot((p0 + p1) * 0.5 - inside) < 0 { normal = normal * -1 }
            if lens.facing(normal) <= 0 { continue }
            face(&ctx, st, [tip, p0, p1], sunlight(k % 2 == 0 ? cloth : Tone.cream, normal))
        }
        orb(&ctx, st, 0, 0, 0.98, 0.05, cloth, gloss: 0)
    }

    private func drawKiosk(_ ctx: inout GraphicsContext, _ st: Stance, _ prop: Prop) {
        let trim = Tone.canvas[prop.tint % Tone.canvas.count]
        let body = Hue(0xFFF4E2)
        solid(&ctx, st, Self.rounded(0.5, 0.4, 0.08, steps: 2), 0, 0.62, body, body, fade: 0.1, lid: false)
        for (side, wall) in Self.walls(0.5, 0.4).enumerated() {
            let out = st.level(wall.outX, wall.outY)
            if lens.facing(out) <= 0 { continue }
            panel(&ctx, st, wall, 0.06, wall.length - 0.06, 0.04, 0.2, sunlight(trim, out))
            if side == 0 {
                // the serving hatch
                panel(&ctx, st, wall, 0.14, wall.length - 0.14, 0.3, 0.54, sunlight(Hue(0x8E7FD0), out), sunlight(Hue(0x6E5FB6), out))
            }
        }
        // a striped roof with an ice cream on it
        solid(&ctx, st, Self.rounded(0.6, 0.5, 0.1, steps: 2), 0.62, 0.72, trim, trim, fade: 0)
        for k in 0..<3 {
            plate(&ctx, st, Self.box(0.085, 0.47, -0.34 + Double(k) * 0.34, 0), 0.72, sunlight(Tone.cream, st.up))
        }
        solid(&ctx, st, Self.ring(0.07, 6, 0.2, -0.1), 0.72, 0.86, Hue(0xE9B57C), Hue(0xF5CFA0), fade: 0)
        orb(&ctx, st, 0.2, -0.1, 0.98, 0.15, Hue(0xFF9CC2), gloss: 0.6)
    }

    private func drawBin(_ ctx: inout GraphicsContext, _ st: Stance, _ prop: Prop) {
        let body = [Hue(0x39C6B8), Hue(0x6F8CFF), Hue(0xFF8FB3)][prop.tint % 3]
        solid(&ctx, st, Self.ring(0.12, 8), 0, 0.3, body, body, fade: 0.1)
        plate(&ctx, st, Self.ring(0.08, 8), 0.3, Hue(0x4A4470))
    }

    private func drawCone(_ ctx: inout GraphicsContext, _ st: Stance) {
        let orange = Hue(0xFF8A4C), band = Hue(0xFFFFFF)
        solid(&ctx, st, Self.ring(0.13, 6), 0, 0.05, orange, orange, fade: 0)
        solid(&ctx, st, Self.ring(0.09, 6), 0.05, 0.16, orange, orange, fade: 0)
        solid(&ctx, st, Self.ring(0.07, 6), 0.16, 0.24, band, band, fade: 0)
        solid(&ctx, st, Self.ring(0.05, 6), 0.24, 0.34, orange, orange, fade: 0)
    }

    private func drawFountain(_ ctx: inout GraphicsContext, _ st: Stance) {
        let stone = Hue(0xFFF1DA)
        // the basin and its water, then the bowl on its stem, then the spout
        solid(&ctx, st, Self.ring(1.0, 18), 0, 0.26, stone, stone, fade: 0.1)
        plate(&ctx, st, Self.ring(0.84, 18), 0.26, Hue(0x86D6F3))
        plate(&ctx, st, Self.ring(0.6, 18, -0.1, -0.08), 0.26, Hue(0xA9E5F8))
        plate(&ctx, st, Self.ring(0.2, 10, -0.36, -0.3), 0.26, Hue(0xE4F8FE))
        solid(&ctx, st, Self.ring(0.3, 12), 0.2, 0.5, stone, stone, fade: 0.1)
        plate(&ctx, st, Self.ring(0.22, 12), 0.5, Hue(0x9FDFF6))
        solid(&ctx, st, Self.ring(0.07, 6), 0.5, 0.74, stone, stone, fade: 0)
        orb(&ctx, st, 0, 0, 0.82, 0.13, Hue(0xD6F4FD), gloss: 0.8)
    }

    // MARK: Words and the HUD

    /// What the game shouts when a prop starts to go down. nil for the small stuff.
    static func shout(for prop: Prop) -> String? {
        switch prop.kind {
        case .building: return "MEGA GULP"
        case .house: return "GULP"
        case .bus: return "BIG BITE"
        case .car: return "CRUNCH"
        case .kiosk: return "YUM"
        case .fountain: return "SPLASH"
        case .bench: return prop.seed % 2 == 0 ? "NOM" : nil
        default: return nil
        }
    }

    /// Chunky rounded text with an outline, and optionally a solid drop below it. Canvas text has no
    /// stroke, so the outline is the same text stamped in a ring behind the fill.
    func caption(_ ctx: inout GraphicsContext, _ string: String, at p: CGPoint, size: Double, fill: Hue, rim: Hue,
                 rimWidth: Double, drop: Double = 0, italic: Bool = false, kerning: Double = 0, alpha: Double = 1,
                 weight: Font.Weight = .black) {
        if alpha < 0.01 { return }
        if alpha < 0.995 {
            // fade the finished caption, or the stamps would show through each other
            var group = ctx
            group.opacity = alpha
            group.drawLayer { layer in
                self.caption(&layer, string, at: p, size: size, fill: fill, rim: rim, rimWidth: rimWidth, drop: drop,
                             italic: italic, kerning: kerning, alpha: 1, weight: weight)
            }
            return
        }
        var text = Text(string).font(.system(size: size, weight: weight, design: .rounded)).kerning(kerning)
        if italic { text = text.italic() }
        let back = ctx.resolve(text.foregroundColor(rim.paint()))
        let front = ctx.resolve(text.foregroundColor(fill.paint()))
        let stamps = 14
        let layers = drop > 0 ? 3 : 1
        for layer in 0..<layers {
            let down = drop * Double(layer) / Double(Swift.max(1, layers - 1))
            for k in 0..<stamps {
                let a = Double(k) / Double(stamps) * 2 * Double.pi
                ctx.draw(back, at: CGPoint(x: Double(p.x) + cos(a) * rimWidth, y: Double(p.y) + sin(a) * rimWidth + down), anchor: .center)
            }
        }
        ctx.draw(front, at: p, anchor: .center)
    }

    /// "+8" rising from where something went down. age runs 0...1.
    func drawGain(_ ctx: inout GraphicsContext, _ worth: Int, at base: CGPoint, age: Double) {
        let alpha = Curve.ramp(0, 0.12, age) * (1 - Curve.ramp(0.62, 1, age))
        let big = worth >= 40
        let points = big ? 26.0 : (worth >= 15 ? 20.0 : (worth >= 8 ? 17.0 : 13.5))
        caption(&ctx, "+\(worth)", at: CGPoint(x: Double(base.x), y: Double(base.y) - (14 + 40 * Curve.settle(age)) * u),
                size: points * u * (0.75 + 0.25 * Curve.spring(age / 0.2)), fill: big ? Tone.sun : .white, rim: Tone.ink,
                rimWidth: Swift.max(0.8, (big ? 2.4 : 1.9) * u), drop: (big ? 2.4 : 1.6) * u, alpha: alpha)
    }

    /// The shout over the hole. age runs 0...1, top is the screen y it has to clear.
    func drawShout(_ ctx: inout GraphicsContext, _ string: String, big: Bool, x: Double, top: Double, lift: Double,
                   age: Double, seed: UInt64) {
        let alpha = Curve.ramp(0, 0.03, age) * (1 - Curve.ramp(0.72, 1, age))
        let pop = 0.72 + 0.28 * Curve.spring(age / 0.16)
        // never over the big number at the top
        let y = Swift.max(H * 0.18 + 88 * u, top - (22 + lift + 12 * Curve.settle(age)) * u)
        caption(&ctx, string, at: CGPoint(x: x, y: y), size: (big ? 27 : 21) * u * pop, fill: .white,
                rim: big ? Tone.coral : Tone.violet, rimWidth: Swift.max(1, (big ? 3.0 : 2.4) * u),
                drop: 3 * u, italic: true, kerning: 0.6 * u, alpha: alpha)
        guard big else { return }
        var dice = Dice(seed: seed &+ 5)
        for _ in 0..<5 {
            let sx = x + dice.roll(-86, 86) * u, sy = y + dice.roll(-24, 20) * u
            ctx.fill(Self.glint(CGPoint(x: sx, y: sy), dice.roll(3.5, 7) * u * pop), with: .color(Color.white.opacity(alpha)))
        }
    }

    /// The big number, the clock on the left, and the size meter under the number.
    func drawHUD(_ ctx: inout GraphicsContext, score: String, seconds: Int, urgent: Bool,
                 size: Int, progress: Double, showNext: Bool) {
        let ink = Tone.ink
        let midX = W * 0.5
        let line = H * 0.18
        let outline = Swift.max(0.8, 2.4 * u)
        caption(&ctx, score, at: CGPoint(x: midX, y: line), size: 50 * u, fill: .white, rim: ink,
                rimWidth: Swift.max(1, 3.0 * u), drop: 4 * u, kerning: 0.5 * u)

        // the clock: a pill that turns coral when time is short
        let pillH = 32 * u
        let pillBox = CGRect(x: 16 * u, y: line - pillH / 2, width: 84 * u, height: pillH)
        let pill = Path(roundedRect: pillBox, cornerRadius: pillH / 2)
        let face = urgent ? Tone.coral : Hue.white
        let mark = urgent ? Hue.white : ink
        ctx.fill(pill.offsetBy(dx: 0, dy: 3 * u), with: .color(ink.paint(0.9)))
        ctx.fill(pill, with: .color(face.paint()))
        ctx.stroke(pill, with: .color(ink.paint()), lineWidth: outline)
        let dial = CGPoint(x: Double(pillBox.minX) + 18 * u, y: Double(pillBox.midY))
        ctx.fill(disc(dial, 8.5 * u), with: .color((urgent ? Hue.white : Tone.coral).paint()))
        ctx.fill(disc(dial, 5.6 * u), with: .color(face.paint()))
        var hands = Path()
        hands.move(to: CGPoint(x: Double(dial.x), y: Double(dial.y) - 3.8 * u))
        hands.addLine(to: dial)
        hands.addLine(to: CGPoint(x: Double(dial.x) + 2.8 * u, y: Double(dial.y) + 1.2 * u))
        ctx.stroke(hands, with: .color(mark.paint()),
                   style: StrokeStyle(lineWidth: Swift.max(0.6, 1.7 * u), lineCap: .round, lineJoin: .round))
        let rest = seconds % 60
        ctx.draw(Text("\(seconds / 60):" + (rest < 10 ? "0\(rest)" : "\(rest)"))
            .font(.system(size: 17 * u, weight: .heavy, design: .rounded)).foregroundColor(mark.paint()),
                 at: CGPoint(x: Double(pillBox.minX) + 31 * u, y: Double(pillBox.midY)), anchor: .leading)

        // the meter: this size on the left, the next one on the right
        let meterY = line + 47 * u
        let barW = 148 * u, barH = 15 * u
        let bar = CGRect(x: midX - barW / 2 + 8 * u, y: meterY - barH / 2, width: barW, height: barH)
        let track = Path(roundedRect: bar, cornerRadius: barH / 2)
        ctx.fill(track.offsetBy(dx: 0, dy: 3 * u), with: .color(ink.paint(0.9)))
        ctx.fill(track, with: .color(Color.white))
        let filled = Swift.max(barH, barW * (0.08 + 0.92 * progress))
        ctx.fill(Path(roundedRect: CGRect(x: Double(bar.minX), y: Double(bar.minY), width: filled, height: barH), cornerRadius: barH / 2),
                 with: .linearGradient(Gradient(colors: [Tone.violet.paint(), Tone.pink.paint()]),
                                       startPoint: CGPoint(x: Double(bar.minX), y: 0), endPoint: CGPoint(x: Double(bar.maxX), y: 0)))
        ctx.fill(Path(roundedRect: CGRect(x: Double(bar.minX) + 12 * u, y: Double(bar.minY) + 2.6 * u,
                                          width: Swift.max(0, filled - 20 * u), height: 3 * u), cornerRadius: 1.5 * u),
                 with: .color(Color.white.opacity(0.45)))
        ctx.stroke(track, with: .color(ink.paint()), lineWidth: outline)
        // this size, as a little hole
        let now = CGPoint(x: Double(bar.minX) - 3 * u, y: meterY)
        ctx.fill(disc(CGPoint(x: Double(now.x), y: Double(now.y) + 3 * u), 16 * u), with: .color(ink.paint(0.9)))
        ctx.fill(disc(now, 16 * u), with: .color(Color.white))
        ctx.fill(disc(now, 12.6 * u), with: .radialGradient(
            Gradient(colors: [Tone.pitWall.paint(), Tone.pitFloor.paint()]),
            center: CGPoint(x: Double(now.x), y: Double(now.y) - 7 * u), startRadius: 0, endRadius: 17 * u))
        ctx.stroke(disc(now, 16 * u), with: .color(ink.paint()), lineWidth: outline)
        ctx.draw(Text("\(size)").font(.system(size: 15 * u, weight: .black, design: .rounded)).foregroundColor(.white),
                 at: now, anchor: .center)
        guard showNext else { return }
        let next = CGPoint(x: Double(bar.maxX) + 2 * u, y: meterY)
        ctx.fill(disc(CGPoint(x: Double(next.x), y: Double(next.y) + 2.4 * u), 11.5 * u), with: .color(ink.paint(0.9)))
        ctx.fill(disc(next, 11.5 * u), with: .color(Color.white))
        ctx.stroke(disc(next, 11.5 * u), with: .color(ink.paint()), lineWidth: Swift.max(0.8, 2.2 * u))
        ctx.draw(Text("\(size + 1)").font(.system(size: 12 * u, weight: .black, design: .rounded)).foregroundColor(ink.paint()),
                 at: next, anchor: .center)
    }

    /// The round is over: the city dims and the words pop in. shown runs 0...1.
    func drawBanner(_ ctx: inout GraphicsContext, _ string: String, shown: Double) {
        guard shown > 0.01 else { return }
        ctx.fill(Path(CGRect(x: 0, y: 0, width: W, height: H)), with: .color(Tone.ink.paint(0.3 * shown)))
        caption(&ctx, string, at: CGPoint(x: W * 0.5, y: H * 0.43), size: 44 * u * (0.7 + 0.3 * Curve.spring(shown)),
                fill: Tone.sun, rim: Tone.ink, rimWidth: Swift.max(1, 3.4 * u), drop: 5 * u, italic: true, alpha: shown)
    }
}

// MARK: - The clip

/// One frame of the clip: the hole is wherever the route puts it at this phase.
struct GulpCityClip {
    typealias Curve = GulpCityCurve
    typealias Tone = GulpCitySwatch

    let artist: GulpCityArtist
    let phase: Double
    let showHUD: Bool
    let holeX: Double
    let holeY: Double
    let holeR: Double

    init(size: CGSize, phase rawPhase: Double, showHUD: Bool, art: GulpCityArt) {
        let phase = rawPhase.isFinite ? Curve.clamp(rawPhase) : 0
        self.phase = phase
        self.showHUD = showHUD
        let at = GulpCityRoute.spot(phase)
        holeX = at.x
        holeY = at.y
        holeR = GulpCityRoute.radius(phase)
        // the camera trails the hole, held back towards the middle of the route, and pulls out as it grows
        let lens = GulpCityLens(size: size, eyeX: Curve.mix(at.x, 2.5, 0.4), eyeY: Curve.mix(at.y, 1.0, 0.4),
                                span: 8.4 + 6.6 * Curve.ramp(0, 1, phase))
        artist = GulpCityArtist(lens: lens, town: .clip, rise: 0.62 + 0.38 * Curve.spring(phase / 0.05), edge: nil, art: art)
    }

    func draw(_ ctx: inout GraphicsContext) {
        artist.drawGround(&ctx)
        let poses = makePoses()
        artist.drawShadows(&ctx, poses)
        artist.drawWhirl(&ctx, holeX, holeY, holeR, turn: phase * 2 * Double.pi * 9)
        artist.drawHole(&ctx, holeX, holeY, holeR, turn: phase * 2 * Double.pi * 7)
        artist.drawCracks(&ctx, poses)
        artist.drawProps(&ctx, poses)
        artist.drawDebris(&ctx, poses)
        drawRipples(&ctx)
        artist.drawHaze(&ctx)
        if showHUD {
            drawGains(&ctx)
            drawShout(&ctx)
            drawStartled(&ctx)
            drawHUD(&ctx)
        }
    }

    private func makePoses() -> [GulpCityPose] {
        var poses: [GulpCityPose] = []
        poses.reserveCapacity(360)
        let seen = artist.lens.seen
        let props = artist.town.props
        for k in props.indices {
            let prop = props[k]
            // tall props south of the frame still reach up into it
            if prop.x < seen.x0 - 2 || prop.x > seen.x1 + 2 || prop.y < seen.y0 - 2 || prop.y > seen.y1 + 7 { continue }
            var fall = -1.0
            if phase >= prop.eatAt {
                fall = (phase - prop.eatAt) / prop.sink
                if fall >= 1 { continue }
            }
            // it starts to lean just before the hole gets there
            let nudge = fall < 0 && prop.eatAt < 2 ? Curve.ramp(prop.eatAt - 0.035, prop.eatAt, phase) : 0
            if let pose = artist.pose(k, prop, fall: fall, nudge: nudge, holeX: holeX, holeY: holeY, holeR: holeR) {
                poses.append(pose)
            }
        }
        return poses
    }

    private func drawRipples(_ ctx: inout GraphicsContext) {
        for k in artist.town.route {
            let prop = artist.town.props[k]
            if prop.worth < 4 { continue }
            let age = (phase - (prop.eatAt + prop.sink * 0.82)) / 0.03
            if age < 0 || age > 1 { continue }
            artist.drawRipple(&ctx, holeX, holeY, holeR, age: age)
        }
    }

    /// The numbers get pickier as the hole grows, or the screen would fill with them.
    private func drawGains(_ ctx: inout GraphicsContext) {
        for k in artist.town.route {
            let prop = artist.town.props[k]
            let least = prop.eatAt < 0.3 ? 2 : (prop.eatAt < 0.62 ? 4 : 8)
            if prop.worth < least { continue }
            let landed = prop.eatAt + prop.sink * 0.72
            let age = (phase - landed) / 0.07
            if age < 0 || age > 1 { continue }
            let hole = GulpCityRoute.spot(landed)
            artist.drawGain(&ctx, prop.worth, at: artist.spot(Curve.mix(prop.x, hole.x, 0.25), Curve.mix(prop.y, hole.y, 0.25), 0.5), age: age)
        }
    }

    /// One shout at a time: the most valuable thing that has just started to fall, newest on a tie.
    private func drawShout(_ ctx: inout GraphicsContext) {
        let props = artist.town.props
        var best = -1
        var bestAge = 0.0
        for k in artist.town.route {
            let age = phase - (props[k].eatAt + 0.008)
            if age < 0 || age >= 0.12 || GulpCityArtist.shout(for: props[k]) == nil { continue }
            if best < 0 || props[k].worth > props[best].worth || (props[k].worth == props[best].worth && age < bestAge) {
                best = k
                bestAge = age
            }
        }
        guard best >= 0, let words = GulpCityArtist.shout(for: props[best]) else { return }
        let prop = props[best]
        let u = artist.u
        let big = prop.worth >= 40
        let hole = artist.spot(holeX, holeY)
        // a tall building lifts the words clear of its roof
        let top = Double(hole.y) - holeR * artist.s * GulpCityLens.squash
            - (big ? Swift.max(0, prop.tall - 1.6) * GulpCityLens.lift * artist.s : 0)
        let x = Curve.clamp(Double(hole.x) + (big ? 14 : 0) * u, 92 * u, artist.W - 128 * u)
        artist.drawShout(&ctx, words, big: big, x: x, top: top, lift: 0, age: bestAge / 0.12, seed: prop.seed)
    }

    /// Bystanders near the rim who are about to go: a little burst of alarm over their heads.
    private func drawStartled(_ ctx: inout GraphicsContext) {
        let u = artist.u
        for prop in artist.town.props where prop.kind == .person && prop.eatAt > phase {
            let dx = prop.x - holeX, dy = prop.y - holeY
            let away = (dx * dx + dy * dy).squareRoot()
            if away > holeR + 1.6 || away < holeR * 0.9 { continue }
            let at = artist.spot(prop.x, prop.y, 1.25)
            let x = Double(at.x), y = Double(at.y)
            if x < 0 || x > artist.W || y < 0 || y > artist.H { continue }
            let near = 1 - Curve.ramp(holeR + 1.1, holeR + 1.6, away)
            if near < 0.01 { continue }
            let size = 13 * u * (0.6 + 0.4 * near)
            var rays = Path()
            for tilt in [-0.66, 0.0, 0.66] {
                let dx = sin(tilt), dy = -cos(tilt)
                rays.move(to: CGPoint(x: x + dx * size * 0.16, y: y + size * 0.3 + dy * size * 0.16))
                rays.addLine(to: CGPoint(x: x + dx * size * 0.62, y: y + size * 0.3 + dy * size * 0.62))
            }
            var group = ctx
            group.opacity = near
            group.drawLayer { layer in
                layer.stroke(rays, with: .color(Color.white),
                             style: StrokeStyle(lineWidth: size * 0.2 + 2 * Swift.max(0.7, 1.6 * u), lineCap: .round))
                layer.stroke(rays, with: .color(Tone.coral.paint()), style: StrokeStyle(lineWidth: size * 0.2, lineCap: .round))
            }
        }
    }

    private func drawHUD(_ ctx: inout GraphicsContext) {
        // ten points for every unit of worth that has gone all the way down
        var worth = 0
        for k in artist.town.route {
            let prop = artist.town.props[k]
            if prop.eatAt + prop.sink <= phase { worth += prop.worth }
        }
        let secondsLeft = Int(((1 - phase) * 120).rounded())
        let size = 1.6 + 6 * phase
        artist.drawHUD(&ctx, score: Self.grouped(worth * 10), seconds: secondsLeft, urgent: secondsLeft <= 20,
                       size: Int(size), progress: size - Double(Int(size)), showNext: true)
        artist.drawBanner(&ctx, "TIME UP", shown: Curve.ramp(0.962, 0.985, phase))
    }

    /// 12340 -> "12,340"
    private static func grouped(_ number: Int) -> String {
        var digits = String(number)
        var out = ""
        while digits.count > 3 {
            out = "," + digits.suffix(3) + out
            digits.removeLast(3)
        }
        return digits + out
    }
}
