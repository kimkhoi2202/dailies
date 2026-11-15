import SwiftUI

// Bus Rush: a lot packed with buses. Tap one and it drives out to a waiting slot, unless another
// bus is in the way. Riders queue along the path and climb into the waiting bus of their colour,
// in order. A full bus leaves and frees its slot. Five slots of buses nobody in front can ride
// jams the lot.
//
// The whole picture is painted into one Canvas by BusRushPainter from a BusRushFrame. Everything
// that moves is worked out from the times kept in a BusRushTimeline, so the clip and the playable
// game share one painter: the clip replays a recorded round at any moment, the game paints its own.
// The buses, riders, ground, hedge, bushes and sign are pictures in Resources/GameArt; roads, bays,
// seats and effects are drawn here. Any frame size, drawn for a 402 x 874 stage.

public struct BusRushScene: View {
    public var phase: Double
    public var showHUD: Bool

    public init(phase: Double, showHUD: Bool) {
        self.phase = phase
        self.showHUD = showHUD
    }

    public var body: some View {
        Canvas(opaque: true, colorMode: .nonLinear, rendersAsynchronously: false) { context, size in
            if size.width <= 8 || size.height <= 8 { return }
            BusRushPainter(size: size, frame: BusRushClip.frame(at: phase), showHUD: showHUD).draw(&context)
        }
    }
}

// MARK: - Numbers

enum BusRushMath {
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

    static func easeIn(_ v: Double) -> Double {
        let k = clamp(v)
        return k * k * k
    }

    static func easeInOut(_ v: Double) -> Double {
        let k = clamp(v)
        return k < 0.5 ? 4 * k * k * k : 1 - pow(2 - 2 * k, 3) / 2
    }

    /// Rises fast, overshoots a little and settles: a pop. 0 at 0, 1 at 1.
    static func pop(_ v: Double) -> Double {
        let k = clamp(v)
        return 1 - exp(-6 * k) * cos(2.4 * .pi * k) * (1 - k)
    }

    /// From one heading to another the short way round.
    static func turn(_ from: Double, _ to: Double, _ k: Double) -> Double {
        from + atan2(sin(to - from), cos(to - from)) * k
    }

    static func clock(_ seconds: Int) -> String {
        let total = Swift.max(0, seconds)
        let rest = total % 60
        return "\(total / 60):\(rest < 10 ? "0" : "")\(rest)"
    }
}

/// SplitMix64. The lot and the pilot use different salts so they never share a sequence.
struct BusRushRandom {
    static let level: UInt64 = 0xA24BAED4963EE407
    static let pilot: UInt64 = 0x2545F4914F6CDD1D

    private var state: UInt64

    init(seed: UInt64, salt: UInt64) {
        state = seed &* 0x9E3779B97F4A7C15 &+ salt
    }

    /// 0 ..< 1
    mutating func next() -> Double {
        state &+= 0x9E3779B97F4A7C15
        var v: UInt64 = state
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

enum BusRushInk {
    static func hex(_ value: UInt32, _ alpha: Double = 1) -> Color {
        Color(.sRGB, red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255,
              blue: Double(value & 255) / 255, opacity: alpha)
    }

    /// The colour part way to another one.
    static func mix(_ value: UInt32, _ other: UInt32, _ k: Double) -> Color {
        func part(_ v: UInt32, _ shift: UInt32) -> Double { Double((v >> shift) & 255) / 255 }
        return Color(.sRGB, red: BusRushMath.lerp(part(value, 16), part(other, 16), k),
                     green: BusRushMath.lerp(part(value, 8), part(other, 8), k),
                     blue: BusRushMath.lerp(part(value, 0), part(other, 0), k), opacity: 1)
    }

    static let ground = hex(0xECE8E1)
    static let card = hex(0xF8F6F1)
    static let ink = hex(0x151412)
    static let inkSoft = hex(0x151412, 0.55)
    static let path = hex(0xDCD4C6)
    static let pathEdge = hex(0xCFC6B6)
    static let asphalt = hex(0x55565E)
    static let asphaltDark = hex(0x48494F)
    static let lot = hex(0xDBD8D1)
    static let lotLine = hex(0xEAE7E1)
    static let red = hex(0xE8503F)
    static let green = hex(0x2EB872)

    /// The bus and rider colours: red, blue, green, purple, orange, teal.
    static let busHex: [UInt32] = [0xF0484E, 0x3A7BFF, 0x2DBE6C, 0x9B5CF6, 0xFF8A1F, 0x14BFC6]
    static let body: [Color] = busHex.map { hex($0) }
    static let light: [Color] = busHex.map { mix($0, 0xFFFFFF, 0.4) }
}

// MARK: - The lot

enum BusRushDir: Int, CaseIterable {
    case up, right, down, left

    var dx: Int {
        switch self {
        case .right: return 1
        case .left: return -1
        case .up, .down: return 0
        }
    }

    var dy: Int {
        switch self {
        case .down: return 1
        case .up: return -1
        case .left, .right: return 0
        }
    }

    /// Heading on screen, in radians. 0 points right.
    var angle: Double {
        switch self {
        case .up: return -Double.pi / 2
        case .right: return 0
        case .down: return Double.pi / 2
        case .left: return Double.pi
        }
    }
}

/// A bus parked in the lot. It covers `length` cells in a line, front first, and can only drive forward.
struct BusRushBus {
    let id: Int
    let headX: Int
    let headY: Int
    let length: Int
    let dir: BusRushDir
    var color: Int

    /// Two seats a cell.
    var capacity: Int { length * 2 }

    func covers(_ x: Int, _ y: Int) -> Bool {
        for k in 0..<length where headX - dir.dx * k == x && headY - dir.dy * k == y { return true }
        return false
    }

    /// The middle of the bus, in cells.
    var middle: (x: Double, y: Double) {
        let back = Double(length - 1) / 2
        return (Double(headX) + 0.5 - Double(dir.dx) * back, Double(headY) + 0.5 - Double(dir.dy) * back)
    }
}

struct BusRushLevel {
    let index: Int
    let cols: Int
    let rows: Int
    let buses: [BusRushBus]
    /// Rider colours, front of the queue first.
    let queue: [Int]

    /// Lot size, colours in play, and how many buses the queue asks for at once.
    static func shape(_ index: Int) -> (cols: Int, rows: Int, colors: Int, window: Int) {
        switch index {
        case 0: return (5, 6, 3, 2)
        case 1: return (6, 7, 4, 2)
        case 2: return (6, 8, 5, 3)
        default: return (7, 8, 6, 3)
        }
    }

    /// A lot that can always be cleared.
    ///
    /// Buses are laid one at a time, and each new bus needs a clear road out past the buses already
    /// down. So the bus laid last can always leave, and so can the last one of whatever is left:
    /// the lot never locks. The queue is dealt from the buses in that leaving order, a few at a time,
    /// so a player who finds the order needs only two or three of the five slots.
    static func make(index: Int, seed: UInt64) -> BusRushLevel {
        let shape = Self.shape(index)
        let cols = shape.cols
        let rows = shape.rows
        var rng = BusRushRandom(seed: seed &+ UInt64(index) &* 0x517C_C1B7_2722_0A95, salt: BusRushRandom.level)
        let want = Int(Double(cols * rows) * 0.8)

        var best: [BusRushBus] = []
        var bestFill = -1
        for _ in 0..<10 {
            var grid = [Int](repeating: -1, count: cols * rows)
            var buses: [BusRushBus] = []
            var fill = 0
            for _ in 0..<1500 {
                if fill >= want { break }
                let length = rng.next() < 0.55 ? 3 : 2
                let dir = BusRushDir(rawValue: rng.int(0...3)) ?? .up
                let hx = rng.int(0...(cols - 1))
                let hy = rng.int(0...(rows - 1))
                var ok = true
                for k in 0..<length {
                    let x = hx - dir.dx * k
                    let y = hy - dir.dy * k
                    if x < 0 || y < 0 || x >= cols || y >= rows || grid[y * cols + x] >= 0 {
                        ok = false
                        break
                    }
                }
                if !ok { continue }
                var x = hx + dir.dx
                var y = hy + dir.dy
                while x >= 0, y >= 0, x < cols, y < rows {
                    if grid[y * cols + x] >= 0 {
                        ok = false
                        break
                    }
                    x += dir.dx
                    y += dir.dy
                }
                if !ok { continue }
                for k in 0..<length { grid[(hy - dir.dy * k) * cols + hx - dir.dx * k] = buses.count }
                buses.append(BusRushBus(id: buses.count, headX: hx, headY: hy, length: length, dir: dir, color: 0))
                fill += length
            }
            if fill > bestFill {
                bestFill = fill
                best = buses
            }
            if fill >= want { break }
        }

        // Colours: an even share each, dealt at random.
        var palette = Array(0..<BusRushInk.busHex.count)
        shuffle(&palette, &rng)
        let used = Array(palette.prefix(shape.colors))
        var deal = best.indices.map { used[$0 % used.count] }
        shuffle(&deal, &rng)
        for k in best.indices { best[k].color = deal[k] }

        // The queue, from the buses in leaving order: the last one laid leaves first.
        var left = best.map { $0.capacity }
        var queue: [Int] = []
        queue.reserveCapacity(left.reduce(0, +))
        var waiting: [Int] = []
        var next = best.count - 1
        while waiting.count < shape.window, next >= 0 {
            waiting.append(next)
            next -= 1
        }
        while !waiting.isEmpty {
            let pick = rng.next() < 0.5 ? 0 : rng.int(0...(waiting.count - 1))
            let id = waiting[pick]
            let run = Swift.min(left[id], rng.int(1...3))
            for _ in 0..<run { queue.append(best[id].color) }
            left[id] -= run
            if left[id] == 0 {
                waiting.remove(at: pick)
                if next >= 0 {
                    waiting.append(next)
                    next -= 1
                }
            }
        }
        return BusRushLevel(index: index, cols: cols, rows: rows, buses: best, queue: queue)
    }

    private static func shuffle(_ list: inout [Int], _ rng: inout BusRushRandom) {
        var last = list.count - 1
        while last > 0 {
            list.swapAt(last, rng.int(0...last))
            last -= 1
        }
    }

    /// The bus still in the lot on a cell.
    func bus(atX x: Int, y: Int, launch: [Double]) -> Int? {
        if x < 0 || y < 0 || x >= cols || y >= rows { return nil }
        for bus in buses where launch[bus.id] == .infinity && bus.covers(x, y) { return bus.id }
        return nil
    }

    /// The first bus still in the lot on the road ahead of a bus, with the free cells before it.
    func blocker(for id: Int, launch: [Double]) -> (id: Int, free: Int)? {
        let bus = buses[id]
        var x = bus.headX + bus.dir.dx
        var y = bus.headY + bus.dir.dy
        var free = 0
        while x >= 0, y >= 0, x < cols, y < rows {
            if let other = self.bus(atX: x, y: y, launch: launch) { return (other, free) }
            free += 1
            x += bus.dir.dx
            y += bus.dir.dy
        }
        return nil
    }
}

// MARK: - What happened when

/// A tap on a bus that could not go: it rolls up to what is in the way and back.
struct BusRushBump {
    let id: Int
    let time: Double
    /// Cells it rolls forward.
    let reach: Double
    /// The bus in the way, or -1 when every slot was taken.
    let blocker: Int
}

/// A word for buses leaving close together.
struct BusRushPraise {
    let text: String
    let time: Double
}

/// One lot as a list of times on the lot's clock. A time not reached yet has not happened.
struct BusRushTimeline {
    static let slots = 5
    /// From the tap to parked in the slot.
    static let drive = 0.6
    /// A rider's walk from the front of the queue into the bus.
    static let walk = 0.26
    /// A full bus waits this long after its last rider sits down.
    static let hold = 0.12
    /// A full bus takes this long to leave.
    static let leave = 0.5
    /// Riders step out of the queue this far apart.
    static let gap = 0.085
    static let bumpLength = 0.42

    let level: BusRushLevel
    /// When each bus was sent out. Infinity while it is in the lot.
    var launch: [Double]
    /// The slot each bus drives to. -1 while it is in the lot.
    var slot: [Int]
    /// When each bus left its slot full. Infinity until it is full.
    var depart: [Double]
    /// When each rider stepped out of the queue, in queue order. Infinity while queuing.
    var board: [Double]
    /// The bus each rider took.
    var rider: [Int]
    var bumps: [BusRushBump] = []
    var praises: [BusRushPraise] = []

    init(level: BusRushLevel) {
        self.level = level
        launch = [Double](repeating: .infinity, count: level.buses.count)
        slot = [Int](repeating: -1, count: level.buses.count)
        depart = [Double](repeating: .infinity, count: level.buses.count)
        board = [Double](repeating: .infinity, count: level.queue.count)
        rider = [Int](repeating: -1, count: level.queue.count)
        bumps.reserveCapacity(10)
        praises.reserveCapacity(10)
    }

    /// Riders out of the queue by a time. They leave it in order.
    func boarded(at t: Double) -> Int {
        var n = 0
        while n < board.count, board[n] <= t { n += 1 }
        return n
    }
}

/// One frame, as the painter wants it.
struct BusRushFrame {
    var line: BusRushTimeline
    /// The lot's clock.
    var t: Double = 0
    /// Scenery clock.
    var ambient: Double = 0
    /// Seconds since the lot came up.
    var levelAge: Double = 10
    var levelNumber = 1
    /// Riders from the lots before this one.
    var scoreBase = 0
    var clockText = "2:30"
    var clockUrgent = false
    var hint: String? = nil
    var hintAlpha: Double = 0
    var note: String? = nil
    var noteAge: Double = 0
    /// Seconds since the lot was cleared. nil while it is played.
    var clearAge: Double? = nil
    /// Seconds since the round ended. nil while it runs.
    var endAge: Double? = nil
    var endText = ""
    var jammed = false

    init(line: BusRushTimeline) {
        self.line = line
    }
}

// MARK: - The clip

/// The round the clip shows: a recorded run of the scripted player on one fixed lot.
enum BusRushClip {
    static let start = 0.9
    static let span = 8.0

    static let recorded: BusRushTimeline = {
        let model = BusRushModel(options: GameOptions(solo: true, seed: 20_261_115), firstLevel: 3)
        var pilot = BusRushPilot(seed: 41, loseAfter: nil)
        let dt = 1.0 / 60
        for _ in 0..<2400 {
            model.step(dt: dt)
            if let at = pilot.nextTap(model, dt: dt) { model.tap(x: at.x, y: at.y) }
            if model.now > start + span + 0.5 || (model.stage != .ready && model.stage != .playing) { break }
        }
        return model.line
    }()

    static func frame(at phase: Double) -> BusRushFrame {
        let p = phase.isFinite ? BusRushMath.clamp(phase) : 0
        let t = start + p * span
        var frame = BusRushFrame(line: recorded)
        frame.t = t
        frame.ambient = t
        frame.levelAge = 10 + t
        frame.levelNumber = 4
        frame.scoreBase = 96
        frame.clockText = BusRushMath.clock(Int((104 - t).rounded(.up)))
        return frame
    }
}

// MARK: - Layout

/// Up to seven points the bus drives through on its way to a slot. Kept inline, so working out a
/// route allocates nothing.
struct BusRushRoute {
    private var p0 = CGPoint.zero
    private var p1 = CGPoint.zero
    private var p2 = CGPoint.zero
    private var p3 = CGPoint.zero
    private var p4 = CGPoint.zero
    private var p5 = CGPoint.zero
    private var p6 = CGPoint.zero
    private(set) var count = 0

    subscript(i: Int) -> CGPoint {
        switch i {
        case 0: return p0
        case 1: return p1
        case 2: return p2
        case 3: return p3
        case 4: return p4
        case 5: return p5
        default: return p6
        }
    }

    mutating func add(_ p: CGPoint) {
        if count > 0 {
            let last = self[count - 1]
            if hypot(Double(p.x - last.x), Double(p.y - last.y)) < 0.5 { return }
        }
        switch count {
        case 0: p0 = p
        case 1: p1 = p
        case 2: p2 = p
        case 3: p3 = p
        case 4: p4 = p
        case 5: p5 = p
        case 6: p6 = p
        default: return
        }
        count += 1
    }
}

/// Where everything sits on screen. Top to bottom: the app's band, the queue on its path, the five
/// slots, then the lot inside a ring road.
struct BusRushLayout {
    typealias M = BusRushMath

    let W: Double
    let H: Double
    /// Design points: 1 on a 402 x 874 phone.
    let s: Double

    // The queue path: the front stands at frontX on the low lane; the line runs right, turns up
    // and runs back left along the high lane and off the screen.
    let laneHigh: Double
    let laneLow: Double
    let turnR: Double
    let frontX: Double
    let turnX: Double
    let spacing: Double
    let person: Double

    let slotTop: Double
    let slotW: Double
    let slotH: Double
    let slotGap: Double
    /// Size of one bus cell when parked in a slot.
    let slotCell: Double

    let cell: Double
    let ox: Double
    let oy: Double
    let lotW: Double
    let lotH: Double

    /// The ring road around the lot, by its centre line.
    let road: Double
    let ringL: Double
    let ringR: Double
    let ringT: Double
    let ringB: Double

    init(size: CGSize, cols: Int, rows: Int, showHUD: Bool) {
        W = Double(size.width)
        H = Double(size.height)
        let u = Swift.min(W / 402, H / 874)
        s = u
        let top = showHUD ? Double(GameLayout.topBand) : 66 * u
        laneHigh = top + 26 * u
        turnR = 28 * u
        laneLow = laneHigh + 2 * turnR
        frontX = W * 0.5
        turnX = W - 48 * u
        spacing = 15.5 * u
        person = 6.6 * u

        slotTop = laneLow + 26 * u
        slotCell = 30 * u
        slotH = 3.25 * slotCell
        slotW = 1.6 * slotCell
        slotGap = 72 * u

        road = 34 * u
        let edge = 6 * u
        let outerTop = slotTop + slotH + 10 * u
        let bottom = H - Double(GameLayout.bottomInset) - 4 * u
        let innerTop = outerTop + road + edge
        let innerBottom = bottom - road - edge
        let side = 8 * u + road + edge
        let c = Swift.max(8, Swift.min((W - 2 * side) / Double(Swift.max(1, cols)),
                                       (innerBottom - innerTop) / Double(Swift.max(1, rows)), 56 * u))
        cell = c
        lotW = c * Double(cols)
        lotH = c * Double(rows)
        ox = (W - lotW) / 2
        oy = innerTop + Swift.max(0, innerBottom - innerTop - lotH) * 0.3
        ringL = ox - edge - road / 2
        ringR = ox + lotW + edge + road / 2
        ringT = oy - edge - road / 2
        ringB = oy + lotH + edge + road / 2
    }

    func slotX(_ k: Int) -> Double { W / 2 + Double(k - 2) * slotGap }

    func lotPoint(_ x: Double, _ y: Double) -> CGPoint {
        CGPoint(x: ox + x * cell, y: oy + y * cell)
    }

    /// Screen point to lot cells.
    func lotCell(_ p: CGPoint) -> (x: Double, y: Double) {
        ((Double(p.x) - ox) / cell, (Double(p.y) - oy) / cell)
    }

    func lotCentre(_ bus: BusRushBus) -> CGPoint {
        let m = bus.middle
        return lotPoint(m.x, m.y)
    }

    /// A parked bus noses up to the top of its slot.
    func parkedCentre(_ bus: BusRushBus, slot k: Int) -> CGPoint {
        CGPoint(x: slotX(k), y: slotTop + 0.14 * slotCell + Double(bus.length) * slotCell / 2)
    }

    /// Where riders climb in.
    func door(_ k: Int) -> CGPoint {
        CGPoint(x: slotX(k), y: slotTop + 0.4 * slotCell)
    }

    /// A point on the queue path, a distance back from the front.
    func queuePoint(_ d: Double) -> CGPoint {
        let straight = turnX - frontX
        if d <= straight { return CGPoint(x: frontX + d, y: laneLow) }
        let bend = Double.pi * turnR
        if d <= straight + bend {
            let a = Double.pi / 2 - (d - straight) / turnR
            return CGPoint(x: turnX + turnR * cos(a), y: (laneLow + laneHigh) / 2 + turnR * sin(a))
        }
        return CGPoint(x: turnX - (d - straight - bend), y: laneHigh)
    }

    /// Distance along the ring road, clockwise from its top left corner.
    private func around(_ p: CGPoint) -> Double {
        let w = ringR - ringL
        let h = ringB - ringT
        let x = Double(p.x)
        let y = Double(p.y)
        if abs(y - ringT) < 0.5 { return x - ringL }
        if abs(x - ringR) < 0.5 { return w + (y - ringT) }
        if abs(y - ringB) < 0.5 { return w + h + (ringR - x) }
        return 2 * w + h + (ringB - y)
    }

    private func corner(_ i: Int) -> (at: Double, p: CGPoint) {
        let w = ringR - ringL
        let h = ringB - ringT
        switch i & 3 {
        case 0: return (w, CGPoint(x: ringR, y: ringT))
        case 1: return (w + h, CGPoint(x: ringR, y: ringB))
        case 2: return (2 * w + h, CGPoint(x: ringL, y: ringB))
        default: return (0, CGPoint(x: ringL, y: ringT))
        }
    }

    /// Out of the lot straight ahead, the short way round the ring road, and up into the slot.
    func route(_ bus: BusRushBus, slot k: Int) -> BusRushRoute {
        var route = BusRushRoute()
        let start = lotCentre(bus)
        route.add(start)
        let exit: CGPoint
        switch bus.dir {
        case .up: exit = CGPoint(x: start.x, y: ringT)
        case .down: exit = CGPoint(x: start.x, y: ringB)
        case .left: exit = CGPoint(x: ringL, y: start.y)
        case .right: exit = CGPoint(x: ringR, y: start.y)
        }
        route.add(exit)

        let goal = CGPoint(x: M.clamp(slotX(k), ringL, ringR), y: ringT)
        let total = 2 * ((ringR - ringL) + (ringB - ringT))
        let from = around(exit)
        var ahead = around(goal) - from
        if ahead < 0 { ahead += total }
        let clockwise = ahead <= total - ahead
        let span = clockwise ? ahead : total - ahead

        func offset(_ i: Int) -> Double {
            let raw = clockwise ? corner(i).at - from : from - corner(i).at
            var o = raw.truncatingRemainder(dividingBy: total)
            if o <= 1e-6 { o += total }
            return o
        }
        var first = 0
        var least = Double.infinity
        for i in 0..<4 {
            let o = offset(i)
            if o < least {
                least = o
                first = i
            }
        }
        for j in 0..<4 {
            let i = clockwise ? (first + j) & 3 : (first + 4 - j) & 3
            if offset(i) >= span - 0.5 { break }
            route.add(corner(i).p)
        }
        route.add(goal)
        route.add(parkedCentre(bus, slot: k))
        return route
    }

    /// Where a bus is along its route, 0 to 1: its middle, its heading, and its cell size, which
    /// shrinks to the slot's on the last stretch.
    func ride(_ route: BusRushRoute, _ q: Double) -> (p: CGPoint, angle: Double, cell: Double) {
        let n = route.count
        if n < 2 { return (route[0], -Double.pi / 2, slotCell) }
        var total = 0.0
        for i in 1..<n { total += hypot(Double(route[i].x - route[i - 1].x), Double(route[i].y - route[i - 1].y)) }
        let lastLen = hypot(Double(route[n - 1].x - route[n - 2].x), Double(route[n - 1].y - route[n - 2].y))
        let d = M.clamp(q) * total
        let blend = 0.45 * cell
        let size = M.lerp(cell, slotCell, M.smooth(total - lastLen, total, d))
        var at = 0.0
        for i in 1..<n {
            let a = route[i - 1]
            let b = route[i]
            let len = hypot(Double(b.x - a.x), Double(b.y - a.y))
            if d <= at + len || i == n - 1 {
                let k = len > 0 ? M.clamp((d - at) / len) : 1
                let p = CGPoint(x: Double(a.x) + Double(b.x - a.x) * k, y: Double(a.y) + Double(b.y - a.y) * k)
                var angle = atan2(Double(b.y - a.y), Double(b.x - a.x))
                if i + 1 < n, d > at + len - blend {
                    let c = route[i + 1]
                    let next = atan2(Double(c.y - b.y), Double(c.x - b.x))
                    angle = M.turn(angle, next, 0.5 * M.smooth(at + len - blend, at + len, d))
                } else if i > 1, d < at + blend {
                    let z = route[i - 2]
                    let before = atan2(Double(a.y - z.y), Double(a.x - z.x))
                    angle = M.turn(before, angle, 0.5 + 0.5 * M.smooth(at, at + blend, d))
                }
                return (p, angle, size)
            }
            at += len
        }
        return (route[n - 1], -Double.pi / 2, slotCell)
    }
}

// MARK: - Art

/// The painted pictures, looked up once per frame. Buses and riders come in every colour of
/// BusRushInk.busHex, in the same order.
struct BusRushArt {
    static let shortNames = (0..<6).map { "bus-rush-bus2-\($0)" }
    static let longNames = (0..<6).map { "bus-rush-bus3-\($0)" }
    static let riderNames = (0..<6).map { "bus-rush-rider-\($0)" }

    let ground: GraphicsContext.ResolvedImage
    let hedge: GraphicsContext.ResolvedImage
    let bush: GraphicsContext.ResolvedImage
    let sign: GraphicsContext.ResolvedImage
    let short: [GraphicsContext.ResolvedImage]
    let long: [GraphicsContext.ResolvedImage]
    let riders: [GraphicsContext.ResolvedImage]

    /// Width over height of the stop sign picture and of a rider picture.
    static let signAspect: Double = 0.685
    static let riderAspect: Double = 0.99

    init(_ ctx: GraphicsContext) {
        ground = ctx.resolve(Image("bus-rush-ground"))
        hedge = ctx.resolve(Image("bus-rush-hedge"))
        bush = ctx.resolve(Image("bus-rush-bush"))
        sign = ctx.resolve(Image("bus-rush-sign"))
        short = Self.shortNames.map { ctx.resolve(Image($0)) }
        long = Self.longNames.map { ctx.resolve(Image($0)) }
        riders = Self.riderNames.map { ctx.resolve(Image($0)) }
    }

    func bus(_ bus: BusRushBus) -> GraphicsContext.ResolvedImage {
        let list = bus.length >= 3 ? long : short
        return list[((bus.color % list.count) + list.count) % list.count]
    }

    func rider(_ color: Int) -> GraphicsContext.ResolvedImage {
        riders[((color % riders.count) + riders.count) % riders.count]
    }
}

// MARK: - Painter

struct BusRushPainter {
    typealias M = BusRushMath
    typealias Ink = BusRushInk
    typealias Line = BusRushTimeline

    let L: BusRushLayout
    let frame: BusRushFrame
    let showHUD: Bool

    init(size: CGSize, frame: BusRushFrame, showHUD: Bool) {
        L = BusRushLayout(size: size, cols: frame.line.level.cols, rows: frame.line.level.rows, showHUD: showHUD)
        self.frame = frame
        self.showHUD = showHUD
    }

    /// Bushes left of the queue: across the screen, down between the lanes, radius.
    private static let bushes: [(Double, Double, Double)] = [(0.09, 0.2, 11), (0.19, 0.55, 8), (0.31, 0.25, 9.5)]

    private var s: Double { L.s }

    func label(_ ctx: inout GraphicsContext, _ words: String, size: Double, weight: Font.Weight,
               design: Font.Design = .rounded, tracking: Double = 0, color: Color,
               at p: CGPoint, anchor: UnitPoint = .center) {
        let text = Text(words).font(.system(size: size, weight: weight, design: design)).tracking(tracking).foregroundColor(color)
        ctx.draw(text, at: p, anchor: anchor)
    }

    func draw(_ ctx: inout GraphicsContext) {
        let art = BusRushArt(ctx)
        ctx.fill(Path(CGRect(x: 0, y: 0, width: L.W, height: L.H)), with: .color(Ink.ground))
        let size = art.ground.size
        if size.width >= 1 && size.height >= 1 {
            let k = Swift.max(L.W / Double(size.width), L.H / Double(size.height))
            let w = Double(size.width) * k
            let h = Double(size.height) * k
            ctx.draw(art.ground, in: CGRect(x: (L.W - w) / 2, y: (L.H - h) / 2, width: w, height: h))
        }
        drawPath(&ctx, art)
        drawStation(&ctx)
        drawLot(&ctx)
        drawBuses(&ctx, art)
        drawRiders(&ctx, art)
        drawFloats(&ctx)
        drawClear(&ctx)
        if showHUD { drawHUD(&ctx) }
        drawPills(&ctx)
        drawEnd(&ctx)
    }

    // MARK: Ground

    private func drawPath(_ ctx: inout GraphicsContext, _ art: BusRushArt) {
        let mid = (L.laneLow + L.laneHigh) / 2
        // A hedge between the two lanes of the queue.
        let hedge = CGRect(x: L.frontX - 30 * s, y: mid - 10 * s, width: L.turnX - L.frontX + 30 * s, height: 21 * s)
        ctx.draw(art.hedge, in: hedge)

        var road = Path()
        road.move(to: CGPoint(x: L.frontX - 12 * s, y: L.laneLow))
        road.addLine(to: CGPoint(x: L.turnX, y: L.laneLow))
        for i in 1...16 {
            let a = Double.pi / 2 - Double.pi * Double(i) / 16
            road.addLine(to: CGPoint(x: L.turnX + L.turnR * cos(a), y: mid + L.turnR * sin(a)))
        }
        road.addLine(to: CGPoint(x: -20 * s, y: L.laneHigh))
        ctx.stroke(road, with: .color(Ink.pathEdge), style: StrokeStyle(lineWidth: 25 * s, lineCap: .round, lineJoin: .round))
        ctx.stroke(road, with: .color(Ink.path), style: StrokeStyle(lineWidth: 21 * s, lineCap: .round, lineJoin: .round))

        // Bushes on the free ground left of the front of the queue.
        for (fx, fy, r) in Self.bushes {
            let c = CGPoint(x: L.W * fx, y: L.laneHigh + 14 * s + (L.laneLow - L.laneHigh) * fy)
            let rr = r * s * 1.15
            ctx.draw(art.bush, in: CGRect(x: c.x - rr, y: c.y - rr, width: 2 * rr, height: 2 * rr))
        }

        // The stop sign at the front of the queue.
        let pole = CGPoint(x: L.frontX - 22 * s, y: L.laneLow - 4 * s)
        let signH = 36 * s
        let signW = signH * BusRushArt.signAspect
        ctx.draw(art.sign, in: CGRect(x: pole.x - signW / 2, y: pole.y + 13 * s - signH, width: signW, height: signH))
    }

    private func drawStation(_ ctx: inout GraphicsContext) {
        let left = L.ringL - L.road / 2
        let right = L.ringR + L.road / 2
        let apronTop = L.slotTop - 12 * s
        let apron = CGRect(x: left, y: apronTop, width: right - left, height: L.ringT - apronTop + L.road / 2)
        ctx.fill(Path(roundedRect: apron, cornerRadius: 16 * s), with: .color(Ink.asphalt))
        let ringRect = CGRect(x: L.ringL, y: L.ringT, width: L.ringR - L.ringL, height: L.ringB - L.ringT)
        let ring = Path(roundedRect: ringRect, cornerRadius: 6 * s)
        ctx.stroke(ring, with: .color(Ink.asphalt), style: StrokeStyle(lineWidth: L.road, lineJoin: .round))
        ctx.stroke(ring, with: .color(Color.white.opacity(0.32)),
                   style: StrokeStyle(lineWidth: 1.6 * s, lineCap: .round, dash: [7 * s, 8 * s]))

        let jamPulse = frame.jammed ? 0.5 + 0.5 * sin(frame.ambient * 12) : 0
        for k in 0..<Line.slots {
            let x = L.slotX(k)
            let r = CGRect(x: x - L.slotW / 2, y: L.slotTop, width: L.slotW, height: L.slotH)
            let bay = Path(roundedRect: r, cornerRadius: 8 * s)
            ctx.fill(bay, with: .color(Ink.asphaltDark))
            let edge: Color = frame.jammed ? Ink.red.opacity(0.55 + 0.45 * jamPulse) : Color.white.opacity(0.45)
            ctx.stroke(bay, with: .color(edge), style: StrokeStyle(lineWidth: (frame.jammed ? 2.6 : 1.5) * s, dash: [6 * s, 4 * s]))
        }
    }

    private func drawLot(_ ctx: inout GraphicsContext) {
        let panel = CGRect(x: L.ox - 4 * s, y: L.oy - 4 * s, width: L.lotW + 8 * s, height: L.lotH + 8 * s)
        ctx.fill(Path(roundedRect: panel, cornerRadius: 10 * s), with: .color(Ink.lot))
        let level = frame.line.level
        var lines = Path()
        for x in 1..<level.cols {
            let p = L.lotPoint(Double(x), 0)
            lines.move(to: p)
            lines.addLine(to: CGPoint(x: p.x, y: L.oy + L.lotH))
        }
        for y in 1..<level.rows {
            let p = L.lotPoint(0, Double(y))
            lines.move(to: p)
            lines.addLine(to: CGPoint(x: L.ox + L.lotW, y: p.y))
        }
        ctx.stroke(lines, with: .color(Ink.lotLine), style: StrokeStyle(lineWidth: 1.4 * s))
    }

    // MARK: Buses

    /// One bus, lying along its heading. Its seats fill with riders, front first.
    func drawBus(_ ctx: inout GraphicsContext, _ art: BusRushArt, _ bus: BusRushBus, at c: CGPoint, angle: Double, cell: Double,
                 scale: Double = 1, alpha: Double = 1, seated: Int = 0, arrow: Double = 1, flash: Double = 0) {
        if alpha <= 0.01 || scale <= 0.01 { return }
        let k = cell * scale
        let len = (Double(bus.length) - 0.14) * k
        let wid = 0.74 * k
        let box = CGRect(x: -len / 2, y: -wid / 2, width: len, height: wid)
        let corner = 0.2 * k

        var shade = ctx
        shade.translateBy(x: c.x, y: c.y + 0.09 * k)
        shade.rotate(by: .radians(angle))
        shade.fill(Path(roundedRect: box, cornerRadius: corner), with: .color(Color.black.opacity(0.17 * alpha)))

        var g = ctx
        g.translateBy(x: c.x, y: c.y)
        g.rotate(by: .radians(angle))
        g.opacity = alpha
        let color = bus.color
        g.draw(art.bus(bus), in: box)

        if arrow < 0.99 {
            let stripe = CGRect(x: -len / 2 + 0.24 * k, y: -0.06 * k, width: len - 0.56 * k, height: 0.12 * k)
            g.fill(Path(roundedRect: stripe, cornerRadius: 0.06 * k), with: .color(Ink.light[color].opacity(1 - arrow)))
        }

        let perSide = bus.capacity / 2
        let x0 = -len / 2 + 0.34 * k
        let x1 = len / 2 - 0.52 * k
        let step = perSide > 1 ? (x1 - x0) / Double(perSide - 1) : 0
        let seat = 0.15 * k
        for i in 0..<bus.capacity {
            let x = x1 - Double(i / 2) * step
            let y = i % 2 == 0 ? -wid / 2 + 0.18 * k : wid / 2 - 0.18 * k
            let r = CGRect(x: x - seat / 2, y: y - seat / 2, width: seat, height: seat)
            if i < seated {
                g.fill(Path(ellipseIn: r.insetBy(dx: -0.02 * k, dy: -0.02 * k)), with: .color(Ink.ink.opacity(0.82)))
            } else {
                g.fill(Path(roundedRect: r, cornerRadius: 0.04 * k), with: .color(Color.white.opacity(0.72)))
            }
        }

        if arrow > 0.01 {
            var mark = Path()
            mark.move(to: CGPoint(x: -0.26 * k, y: 0))
            mark.addLine(to: CGPoint(x: 0.2 * k, y: 0))
            mark.move(to: CGPoint(x: 0.04 * k, y: -0.13 * k))
            mark.addLine(to: CGPoint(x: 0.2 * k, y: 0))
            mark.addLine(to: CGPoint(x: 0.04 * k, y: 0.13 * k))
            g.stroke(mark, with: .color(Color.white.opacity(arrow)),
                     style: StrokeStyle(lineWidth: 0.08 * k, lineCap: .round, lineJoin: .round))
        }
        if flash > 0.01 {
            g.fill(Path(roundedRect: box, cornerRadius: corner), with: .color(Ink.red.opacity(0.55 * flash)))
        }
    }

    private func drawBuses(_ ctx: inout GraphicsContext, _ art: BusRushArt) {
        let line = frame.line
        let level = line.level
        let t = frame.t

        // Still in the lot.
        for bus in level.buses {
            let id = bus.id
            if t >= line.launch[id] { continue }
            var c = L.lotCentre(bus)
            var scale = 1.0
            if frame.levelAge < 1 {
                // A new lot fills from the top, bus by bus.
                let order = (Double(bus.headY) + 0.4 * Double(bus.headX)) / Double(level.rows + level.cols)
                scale = M.pop((frame.levelAge - order * 0.45) / 0.3)
                if scale <= 0.01 { continue }
            }
            var flash = 0.0
            for bump in line.bumps where bump.id == id || bump.blocker == id {
                let age = t - bump.time
                if age < 0 || age >= Line.bumpLength { continue }
                let q = age / Line.bumpLength
                if bump.id == id {
                    let roll = bump.reach * sin(Double.pi * M.clamp(q * 1.4)) * L.cell
                    c.x += Double(bus.dir.dx) * roll
                    c.y += Double(bus.dir.dy) * roll
                } else {
                    flash = Swift.max(flash, M.smooth(0.15, 0.3, q) * (1 - M.smooth(0.45, 1, q)))
                }
            }
            drawBus(&ctx, art, bus, at: c, angle: bus.dir.angle, cell: L.cell, scale: scale, flash: flash)
        }

        // Parked, filling up.
        let riders = line.boarded(at: t)
        for bus in level.buses {
            let id = bus.id
            let arrived = line.launch[id] + Line.drive
            if t < arrived || t >= line.depart[id] { continue }
            var seated = 0
            var last = -100.0
            for k in 0..<riders where line.rider[k] == id {
                let sat = line.board[k] + Line.walk
                if sat <= t {
                    seated += 1
                    last = Swift.max(last, sat)
                }
            }
            let scale = 1 + 0.08 * exp(-16 * (t - last)) + 0.06 * exp(-14 * (t - arrived))
            drawBus(&ctx, art, bus, at: L.parkedCentre(bus, slot: line.slot[id]), angle: -Double.pi / 2,
                    cell: L.slotCell, scale: scale, seated: seated, arrow: 0)
        }

        // Full and leaving: a pop, a burst, and off up the road.
        for bus in level.buses {
            let id = bus.id
            let age = t - line.depart[id]
            if !(age >= 0 && age < Line.leave) { continue }
            let home = L.parkedCentre(bus, slot: line.slot[id])
            let burst = M.clamp(age / 0.5)
            if burst < 1 {
                for i in 0..<12 {
                    let a = (Double(i) + 0.31 * Double(id)) / 12 * 2 * Double.pi
                    let d = (14 + 40 * M.easeOut(burst)) * s
                    let r = (i % 2 == 0 ? 3.8 : 2.6) * s * (1 - burst)
                    let p = CGPoint(x: Double(home.x) + cos(a) * d, y: Double(home.y) + sin(a) * d)
                    let tint = i % 2 == 0 ? Ink.body[bus.color] : Ink.light[bus.color]
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)),
                             with: .color(tint.opacity(1 - burst)))
                }
            }
            let scale = 1 + 0.16 * sin(Double.pi * M.clamp(age / 0.2))
            let lift = M.easeIn((age - 0.08) / 0.42) * 120 * s
            let alpha = 1 - M.smooth(0.22, 0.5, age)
            drawBus(&ctx, art, bus, at: CGPoint(x: home.x, y: Double(home.y) - lift), angle: -Double.pi / 2,
                    cell: L.slotCell, scale: scale, alpha: alpha, seated: bus.capacity, arrow: 0)
        }

        // On the road, above everything else.
        for bus in level.buses {
            let id = bus.id
            let age = t - line.launch[id]
            if !(age >= 0 && age < Line.drive) { continue }
            let q = age / Line.drive
            let e = 1 - pow(1 - q, 2.2)
            let pose = L.ride(L.route(bus, slot: line.slot[id]), e)
            drawBus(&ctx, art, bus, at: pose.p, angle: pose.angle, cell: pose.cell, arrow: 1 - M.smooth(0.45, 0.9, q))
        }
    }

    // MARK: Riders

    private func drawRider(_ ctx: inout GraphicsContext, _ art: BusRushArt, at p: CGPoint, color: Int, scale: Double = 1, front: Bool = false) {
        let r = L.person * scale
        let x = Double(p.x)
        let y = Double(p.y)
        ctx.fill(Path(ellipseIn: CGRect(x: x - r * 0.9, y: y + r * 0.5, width: 1.8 * r, height: 0.75 * r)),
                 with: .color(Color.black.opacity(0.13)))
        if front {
            let ring = r + 2.6 * s
            ctx.fill(Path(ellipseIn: CGRect(x: x - ring, y: y - ring, width: 2 * ring, height: 2 * ring)), with: .color(.white))
        }
        let picH = 2.3 * r
        let picW = picH * BusRushArt.riderAspect
        ctx.draw(art.rider(color), in: CGRect(x: x - picW / 2, y: y - picH * 0.52, width: picW, height: picH))
    }

    private func drawRiders(_ ctx: inout GraphicsContext, _ art: BusRushArt) {
        let line = frame.line
        let queue = line.level.queue
        let t = frame.t
        let n = line.boarded(at: t)

        // The queue steps forward one place each time a rider leaves it.
        var advance = 0.0
        var j = n - 1
        while j >= 0 {
            let age = t - line.board[j]
            if age > 0.8 { break }
            advance += exp(-11 * age)
            j -= 1
        }
        let moving = M.clamp(advance * 2)
        if n < queue.count {
            for k in n..<queue.count {
                let d = (Double(k - n) + advance) * L.spacing
                var p = L.queuePoint(d)
                if Double(p.x) < -L.person * 2 { break }
                p.y += sin(frame.ambient * 9 + Double(k) * 0.9) * (0.5 + 1.1 * moving) * s
                drawRider(&ctx, art, at: p, color: queue[k], front: k == n)
            }
        }

        // Riders on their way from the front of the queue into a bus.
        let from = L.queuePoint(0)
        var k = Swift.max(0, n - 12)
        while k < n {
            let age = t - line.board[k]
            if age < Line.walk, line.rider[k] >= 0 {
                let q = M.easeInOut(age / Line.walk)
                let to = L.door(line.slot[line.rider[k]])
                let x = Double(from.x) + Double(to.x - from.x) * q
                let y = Double(from.y) + Double(to.y - from.y) * q - sin(Double.pi * q) * 16 * s
                drawRider(&ctx, art, at: CGPoint(x: x, y: y), color: queue[k], scale: 1 - 0.3 * q)
            }
            k += 1
        }
    }

    // MARK: Words

    private func drawFloats(_ ctx: inout GraphicsContext) {
        let line = frame.line
        let t = frame.t
        for bus in line.level.buses {
            let age = t - line.depart[bus.id]
            if !(age >= 0 && age < 0.9) { continue }
            let alpha = M.easeOut(age / 0.12) * (1 - M.smooth(0.55, 0.9, age))
            let y = L.slotTop - 4 * s - 30 * s * M.easeOut(age / 0.9)
            let size = (16 + 4 * (1 - M.pop(age / 0.3))) * s
            label(&ctx, "+\(bus.capacity)", size: size, weight: .black, color: Ink.green.opacity(alpha),
                  at: CGPoint(x: L.slotX(line.slot[bus.id]), y: y))
        }
    }

    /// A word on a card.
    private func pill(_ ctx: inout GraphicsContext, _ words: String, at c: CGPoint, size: Double, color: Color,
                      alpha: Double, scale: Double) {
        if alpha <= 0.01 { return }
        let text = Text(words).font(.system(size: size * scale, weight: .heavy, design: .rounded)).foregroundColor(color.opacity(alpha))
        let resolved = ctx.resolve(text)
        let box = resolved.measure(in: CGSize(width: L.W, height: 200))
        let padX = 14 * s * scale
        let padY = 7 * s * scale
        let card = CGRect(x: Double(c.x) - Double(box.width) / 2 - padX, y: Double(c.y) - Double(box.height) / 2 - padY,
                          width: Double(box.width) + 2 * padX, height: Double(box.height) + 2 * padY)
        ctx.fill(Path(roundedRect: card.offsetBy(dx: 0, dy: 3 * s), cornerRadius: card.height / 2),
                 with: .color(Color.black.opacity(0.12 * alpha)))
        ctx.fill(Path(roundedRect: card, cornerRadius: card.height / 2), with: .color(Ink.card.opacity(alpha)))
        ctx.draw(resolved, at: c, anchor: .center)
    }

    private func drawPills(_ ctx: inout GraphicsContext) {
        let mid = CGPoint(x: (L.frontX + L.turnX) / 2 + 8 * s, y: (L.laneLow + L.laneHigh) / 2 - 2 * s)
        if let hint = frame.hint, frame.hintAlpha > 0.01 {
            pill(&ctx, hint, at: CGPoint(x: L.W / 2, y: L.slotTop + L.slotH / 2), size: 16 * s, color: Ink.ink,
                 alpha: frame.hintAlpha, scale: 1)
        }
        if let note = frame.note {
            let age = frame.noteAge
            let alpha = M.easeOut(age / 0.12) * (1 - M.smooth(1.0, 1.3, age))
            pill(&ctx, note, at: mid, size: 15 * s, color: Ink.red, alpha: alpha, scale: 0.85 + 0.15 * M.pop(age / 0.3))
            return
        }
        let t = frame.t
        var latest: BusRushPraise? = nil
        for praise in frame.line.praises where praise.time <= t { latest = praise }
        guard let praise = latest else { return }
        let age = t - praise.time
        if age >= 1.0 { return }
        let alpha = M.easeOut(age / 0.1) * (1 - M.smooth(0.75, 1.0, age))
        pill(&ctx, praise.text, at: mid, size: 21 * s, color: Ink.ink, alpha: alpha, scale: 0.7 + 0.3 * M.pop(age / 0.3))
    }

    /// The tick and the words when a lot is cleared.
    private func drawClear(_ ctx: inout GraphicsContext) {
        guard let age = frame.clearAge else { return }
        let cx = L.W / 2
        let cy = L.oy + L.lotH * 0.42
        let arrive = M.pop(age / 0.35)
        let alpha = 1 - M.smooth(0.95, 1.25, age)
        if alpha <= 0.01 { return }
        let r = 46 * s * arrive
        if r > 0.5 {
            ctx.fill(Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r)), with: .color(Ink.green.opacity(alpha)))
            let drawn = M.easeOut((age - 0.1) / 0.3)
            if drawn > 0.01 {
                let a = CGPoint(x: cx - 18 * s, y: cy + 1 * s)
                let b = CGPoint(x: cx - 6 * s, y: cy + 13 * s)
                let c = CGPoint(x: cx + 20 * s, y: cy - 13 * s)
                var tick = Path()
                tick.move(to: a)
                if drawn < 0.4 {
                    let k = drawn / 0.4
                    tick.addLine(to: CGPoint(x: a.x + (b.x - a.x) * k, y: a.y + (b.y - a.y) * k))
                } else {
                    tick.addLine(to: b)
                    let k = (drawn - 0.4) / 0.6
                    tick.addLine(to: CGPoint(x: b.x + (c.x - b.x) * k, y: b.y + (c.y - b.y) * k))
                }
                ctx.stroke(tick, with: .color(Color.white.opacity(alpha)),
                           style: StrokeStyle(lineWidth: 6 * s, lineCap: .round, lineJoin: .round))
            }
        }
        let wordAlpha = M.easeOut((age - 0.15) / 0.25) * alpha
        if wordAlpha > 0.01 {
            label(&ctx, "Lot clear", size: 26 * s, weight: .black, tracking: 1 * s, color: Ink.ink.opacity(wordAlpha),
                  at: CGPoint(x: cx, y: cy + 76 * s))
        }
    }

    // MARK: HUD

    /// The score as it counts up: each rider adds one as they sit down. Also the seconds since the last one.
    private func shownScore() -> (value: Int, since: Double) {
        let line = frame.line
        let t = frame.t
        var value = Double(frame.scoreBase)
        var last = -100.0
        let n = line.boarded(at: t)
        for k in 0..<n {
            let sat = line.board[k] + Line.walk
            value += M.clamp((t - sat) / 0.25)
            if sat <= t { last = Swift.max(last, sat) }
        }
        return (Int(value + 1e-6), t - last)
    }

    private func drawHUD(_ ctx: inout GraphicsContext) {
        let cx = L.W / 2
        let topLine = Double(GameLayout.statusBarHeight)
        // Between the app's two corners: the level and the clock, the score under them.
        label(&ctx, "LEVEL \(frame.levelNumber)", size: 11.5 * s, weight: .bold, tracking: 1.6 * s, color: Ink.inkSoft,
              at: CGPoint(x: cx - 7 * s, y: topLine + 10 * s), anchor: .trailing)
        label(&ctx, frame.clockText, size: 12.5 * s, weight: .bold, design: .monospaced,
              color: frame.clockUrgent ? Ink.red : Ink.inkSoft, at: CGPoint(x: cx + 7 * s, y: topLine + 10 * s), anchor: .leading)
        let score = shownScore()
        let swell = 1 + 0.14 * exp(-12 * Swift.max(0, score.since))
        label(&ctx, "\(score.value)", size: 27 * s * swell, weight: .black, color: Ink.ink,
              at: CGPoint(x: cx, y: topLine + 33 * s))
    }

    private func drawEnd(_ ctx: inout GraphicsContext) {
        guard let age = frame.endAge, !frame.endText.isEmpty else { return }
        let dim = M.smooth(0.15, 0.5, age)
        let top = Double(GameLayout.topBand)
        ctx.fill(Path(CGRect(x: 0, y: top, width: L.W, height: L.H - top)), with: .color(Ink.ground.opacity(0.62 * dim)))
        let alpha = M.easeOut((age - 0.2) / 0.35)
        if alpha <= 0.01 { return }
        let cx = L.W / 2
        let cy = L.oy + L.lotH * 0.42
        let scale = 0.9 + 0.1 * M.pop((age - 0.2) / 0.4)
        let card = CGRect(x: cx - 130 * s * scale, y: cy - 44 * s * scale, width: 260 * s * scale, height: 100 * s * scale)
        ctx.fill(Path(roundedRect: card.offsetBy(dx: 0, dy: 4 * s), cornerRadius: 22 * s * scale),
                 with: .color(Color.black.opacity(0.12 * alpha)))
        ctx.fill(Path(roundedRect: card, cornerRadius: 22 * s * scale), with: .color(Ink.card.opacity(alpha)))
        label(&ctx, frame.endText, size: 30 * s * scale, weight: .black, tracking: 0.5 * s,
              color: Ink.ink.opacity(alpha), at: CGPoint(x: cx, y: cy - 6 * s * scale))
        let riders = shownScore().value
        label(&ctx, riders == 1 ? "1 rider on board" : "\(riders) riders on board", size: 15 * s * scale, weight: .semibold,
              color: Ink.inkSoft.opacity(alpha), at: CGPoint(x: cx, y: cy + 28 * s * scale))
    }
}
