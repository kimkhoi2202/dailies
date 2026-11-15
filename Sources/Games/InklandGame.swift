import SwiftUI

// Inkland, the playable game.
//
// InklandModel         the rules in plain Swift: who owns each cell of the board, the blobs, how the
//                      rivals think, the clock.
// InklandGameRenderer  draws one frame of a model with the painters from InklandScene.swift.
// InklandGame          the view. It steps the model once per frame, turns a drag into steering,
//                      plays the haptics and reports the result.

// MARK: - Small maths

private extension CGPoint {
    func distance(to other: CGPoint) -> Double {
        let dx = Double(other.x - x)
        let dy = Double(other.y - y)
        return (dx * dx + dy * dy).squareRoot()
    }

    /// The unit vector from here to other. Straight up when the two are the same point.
    func direction(to other: CGPoint) -> CGVector {
        let dx = Double(other.x - x)
        let dy = Double(other.y - y)
        let length = (dx * dx + dy * dy).squareRoot()
        return length > 0.001 ? CGVector(dx: dx / length, dy: dy / length) : CGVector(dx: 0, dy: -1)
    }
}

private func clamp(_ value: Double, _ low: Double, _ high: Double) -> Double {
    min(max(value, low), high)
}

// MARK: - Pieces of a round

/// What a self-steering blob has in mind.
struct InklandBrain {
    /// On its own land, out drawing a planned loop, running for home, or going for someone's trail.
    enum Mode { case inside, out, home, hunt }

    var mode = Mode.inside
    /// Scales the size of its loops.
    var bold: Double
    /// How readily it goes for a trail nearby.
    var aggression: Double
    /// How early it runs home when someone nears its trail.
    var caution: Double
    /// Seconds until it next reconsiders.
    var think: Double
    /// A multiplier on how long it rests on its own land between loops.
    var dwell = 1.0
    var rest = 0.0

    // The loop it means to draw next: out along one direction, across along the other, and back.
    var hasPlan = false
    var planAge = 0.0
    var outward = CGVector(dx: 1, dy: 0)
    var across = CGVector(dx: 0, dy: 1)
    var outLength = 40.0
    var acrossLength = 40.0

    // The loop it is drawing now.
    var corners: [CGPoint] = []
    var nextCorner = 0
    /// The longest trail it will risk before turning for home.
    var trailBudget = 300.0

    var goal = CGPoint.zero
    var victim = -1
    var huntLeft = 0.0

    // Swerving round someone's trail.
    var swerveLeft = 0.0
    var swerve = CGVector.zero
    /// No fresh look at a trail in the way until the clock passes this.
    var shyUntil = 0.0

    init(bold: Double, aggression: Double, caution: Double, think: Double) {
        self.bold = bold
        self.aggression = aggression
        self.caution = caution
        self.think = think
    }
}

struct InklandBlob {
    let id: Int
    let name: String
    let isLocal: Bool
    var pos: CGPoint
    var heading: CGVector
    /// Where it wants to be heading. The heading turns towards this at a limited rate.
    var target: CGVector
    /// Points per second.
    var cruise: Double
    /// 0 to 1: how much of its speed it is making good, for the squash and the streaks.
    var pace = 0.0
    var alive = true
    var respawnIn = 0.0
    /// Cells of land.
    var cells = 0
    /// Percent of the board, eased for the HUD.
    var shownShare = 0.0
    /// Row on the leaderboard counted from 0, eased while rows trade places.
    var shownRank = 0.0

    /// The open trail, oldest point first. Empty while it is on its own land.
    var trail: [CGPoint] = []
    var trailCells: [Int32] = []
    var trailLength = 0.0
    var trailSpacing = 2.5
    var drawing = false
    /// Solo only: out of ink until it touches its own land again.
    var dry = false
    var lowInkWarned = false

    /// The smoothed edge of its land, one closed loop per piece. Holes wind the other way.
    var outline: [[CGPoint]] = []
    var outlineVersion = 0
    var dirty = true

    var biggestLoop = 0
    var loops = 0
    var cuts = 0
    var lastCell: Int32 = 0
    /// nil for a blob steered by a finger.
    var brain: InklandBrain?
}

/// A loop that has just closed, kept for a moment so it can flash.
struct InklandClaim {
    let id: Int
    let owner: Int
    /// Percent of the board gained.
    let gain: Double
    let region: [[CGPoint]]
    let centroid: CGPoint
    let rim: [CGPoint]
    let origin: CGPoint
    let born: Double
    let life: Double
}

/// What a blob lost when it was cut, kept for a moment so it can fade out.
struct InklandWipe {
    static let life = 0.6

    let id: Int
    let owner: Int
    let outline: [[CGPoint]]
    let trail: [CGPoint]
    let at: CGPoint
    let born: Double
}

struct InklandPopup {
    let id: Int
    let at: CGPoint
    let label: String
    let ink: Int
    let born: Double
    let life: Double
    let big: Bool
}

/// A rival closing in on the local player's open trail.
struct InklandThreat {
    var rival: Int
    /// Which point of the local trail is in danger.
    var index: Int
    var level: Double
}

/// The board as a grid of square cells.
private struct InklandGrid {
    let cols: Int
    let rows: Int
    let cell: Double

    var count: Int { cols * rows }
    var width: Double { Double(cols) * cell }
    var height: Double { Double(rows) * cell }

    /// The cell under a point. Points off the board count as the nearest edge cell.
    func index(at p: CGPoint) -> Int {
        let x = min(max(Int(Double(p.x) / cell), 0), cols - 1)
        let y = min(max(Int(Double(p.y) / cell), 0), rows - 1)
        return y * cols + x
    }

    func centre(of index: Int) -> CGPoint {
        CGPoint(x: (Double(index % cols) + 0.5) * cell, y: (Double(index / cols) + 0.5) * cell)
    }

    func holds(_ p: CGPoint, margin: Double) -> Bool {
        let x = Double(p.x)
        let y = Double(p.y)
        return x >= margin && x <= width - margin && y >= margin && y <= height - margin
    }
}

/// Finds the outline of a set of cells.
private struct InklandTracer {
    let grid: InklandGrid
    /// For every corner of the grid, the outline edges that leave it: 1 east, 2 south, 4 west, 8 north.
    private var exits: [UInt8]

    private static let stepX = [1, 0, -1, 0]
    private static let stepY = [0, 1, 0, -1]

    init(grid: InklandGrid) {
        self.grid = grid
        exits = [UInt8](repeating: 0, count: (grid.cols + 1) * (grid.rows + 1))
    }

    /// Closed loops around the cells that hold value, with the grid's corners rounded off.
    mutating func loops(around value: Int8, in cells: [Int8]) -> [[CGPoint]] {
        let cols = grid.cols
        let rows = grid.rows
        let span = cols + 1
        for k in exits.indices { exits[k] = 0 }

        // Go clockwise round every cell of the set and keep the sides that face something else.
        var any = false
        for y in 0..<rows {
            for x in 0..<cols {
                let c = y * cols + x
                guard cells[c] == value else { continue }
                any = true
                if y == 0 || cells[c - cols] != value { exits[y * span + x] |= 1 }
                if x == cols - 1 || cells[c + 1] != value { exits[y * span + x + 1] |= 2 }
                if y == rows - 1 || cells[c + cols] != value { exits[(y + 1) * span + x + 1] |= 4 }
                if x == 0 || cells[c - 1] != value { exits[(y + 1) * span + x] |= 8 }
            }
        }
        guard any else { return [] }

        var out: [[CGPoint]] = []
        for corner in exits.indices {
            while exits[corner] != 0 {
                let ring = follow(from: corner, heading: exits[corner].trailingZeroBitCount)
                if ring.count >= 4 { out.append(Self.relaxed(ring)) }
            }
        }
        return out
    }

    /// Follows one outline from a corner until it comes back round, using up its edges. The points
    /// returned are the middles of the edges.
    private mutating func follow(from origin: Int, heading first: Int) -> [CGPoint] {
        let span = grid.cols + 1
        var ring: [CGPoint] = []
        var corner = origin
        var heading = first
        while true {
            let x = corner % span + Self.stepX[heading]
            let y = corner / span + Self.stepY[heading]
            ring.append(CGPoint(x: (Double(x) - 0.5 * Double(Self.stepX[heading])) * grid.cell,
                                y: (Double(y) - 0.5 * Double(Self.stepY[heading])) * grid.cell))
            // The first edge stays on the map until the end, so the way back to it can be recognised.
            if corner != origin || heading != first { exits[corner] &= ~(1 << UInt8(heading)) }
            corner = y * span + x

            // Keep the land close on the right: turn right if that is an edge, else go straight, else left.
            let open = exits[corner]
            let choices = [(heading + 1) & 3, heading, (heading + 3) & 3]
            guard let turn = choices.first(where: { open & (1 << UInt8($0)) != 0 }) else { break }
            if corner == origin, turn == first { break }
            heading = turn
        }
        exits[origin] &= ~(1 << UInt8(first))
        return ring
    }

    /// Three rounds of pulling every point a little towards its two neighbours.
    private static func relaxed(_ ring: [CGPoint]) -> [CGPoint] {
        let n = ring.count
        guard n > 6 else { return ring }
        var now = ring
        var next = ring
        for _ in 0..<3 {
            for k in 0..<n {
                let before = now[k == 0 ? n - 1 : k - 1]
                let after = now[k == n - 1 ? 0 : k + 1]
                next[k] = CGPoint(x: (before.x + 2 * now[k].x + after.x) / 4, y: (before.y + 2 * now[k].y + after.y) / 4)
            }
            swap(&now, &next)
        }
        return now
    }
}

// MARK: - Model

final class InklandModel {
    enum Stage { case ready, playing, ending, finished }
    enum Event { case started, claimed(big: Bool), cutRival, gotCut, respawned, threat, lowInk, dried, tick, timeUp }

    static let cell = 5.4
    static let cols = 70
    /// Solo only: how far one stroke of ink reaches before it runs out.
    static let inkSupply = 520.0
    static let respawnDelay = 1.5
    static let endingLength = 1.2
    static let playerSpeed = 95.0

    let solo: Bool
    let rows: Int
    let cellCount: Int
    let width: Double
    let height: Double
    let roundLength: Double

    private(set) var stage = Stage.ready
    /// Seconds of play so far.
    private(set) var elapsed = 0.0
    /// Runs in every stage. Idle animation and the ages of effects are measured on it.
    private(set) var clock = 0.0
    private(set) var endingAge = 0.0
    private(set) var blobs: [InklandBlob] = []
    private(set) var claims: [InklandClaim] = []
    private(set) var wipes: [InklandWipe] = []
    private(set) var popups: [InklandPopup] = []
    private(set) var threat: InklandThreat?
    /// How many cuts each cause has made, for test rounds: a hunt, a rival straying across a trail,
    /// the local player, and land all taken.
    private(set) var cutCauses = [0, 0, 0, 0]

    private let grid: InklandGrid
    /// Who owns each cell, -1 for nobody.
    private var land: [Int8]
    /// Whose open trail crosses each cell, -1 for none.
    private var lines: [Int8]
    /// Scratch for claiming: cells the flood from the walls has reached, and cells that just changed hands.
    private var reached: [Bool]
    private var fresh: [Int8]
    private var frontier: [Int32] = []
    private var tracer: InklandTracer
    private var rng: InklandSceneRNG
    private var events: [Event] = []
    private var effectCount = 0
    private var lastThreatEvent = -10.0

    /// autopilot makes the local blob steer itself, for test rounds and demo recordings.
    init(solo: Bool, friendNames: [String], seed: UInt64, roundLength: Double = 75, autopilot: Bool = false) {
        self.solo = solo
        self.roundLength = roundLength
        grid = InklandGrid(cols: InklandModel.cols, rows: solo ? 126 : 112, cell: InklandModel.cell)
        rows = grid.rows
        cellCount = grid.count
        width = grid.width
        height = grid.height
        land = [Int8](repeating: -1, count: grid.count)
        lines = [Int8](repeating: -1, count: grid.count)
        reached = [Bool](repeating: false, count: grid.count)
        fresh = [Int8](repeating: 0, count: grid.count)
        frontier.reserveCapacity(grid.count)
        tracer = InklandTracer(grid: grid)
        rng = InklandSceneRNG(seed &+ 0x1D4)

        // Three to five rivals. A missing or blank name gets a spare one.
        var rivals: [String] = []
        if !solo {
            let spares = ["kaz", "noor", "tofu", "juno", "pim"]
            for slot in 0..<min(max(friendNames.count, 3), 5) {
                let given = slot < friendNames.count ? friendNames[slot].trimmingCharacters(in: .whitespaces) : ""
                rivals.append(given.isEmpty ? spares[slot] : given)
            }
        }

        // Where everyone starts, as fractions of the board. The local player is first.
        let starts: [(x: Double, y: Double)]
        switch rivals.count {
        case 0: starts = [(0.5, 0.55)]
        case 3: starts = [(0.27, 0.76), (0.26, 0.20), (0.74, 0.26), (0.73, 0.80)]
        case 4: starts = [(0.25, 0.83), (0.24, 0.16), (0.76, 0.16), (0.50, 0.49), (0.75, 0.83)]
        default: starts = [(0.25, 0.85), (0.25, 0.15), (0.75, 0.15), (0.25, 0.50), (0.75, 0.50), (0.75, 0.85)]
        }

        let middle = CGPoint(x: width / 2, y: height / 2)
        for (id, start) in starts.enumerated() {
            let local = id == 0
            let wander = local ? 0.0 : 0.025
            let spot = CGPoint(x: (start.x + rng.range(-wander, wander)) * width,
                               y: (start.y + rng.range(-wander, wander)) * height)
            let facing = spot.direction(to: middle)
            var blob = InklandBlob(id: id, name: local ? "You" : rivals[id - 1], isLocal: local, pos: spot, heading: facing,
                                   target: facing, cruise: local ? InklandModel.playerSpeed : rng.range(80, 86))
            if !local {
                var brain = InklandBrain(bold: rng.range(0.72, 1.1), aggression: rng.range(0.15, 0.7),
                                         caution: rng.range(0.7, 1.3), think: rng.range(0.05, 0.5))
                brain.rest = rng.range(0.1, 0.9)
                blob.brain = brain
            } else if autopilot {
                // A calm, quick player that never goes after anyone.
                var brain = InklandBrain(bold: solo ? 1.5 : 1.0, aggression: 0, caution: 1.15, think: 0.05)
                brain.dwell = 0.15
                blob.brain = brain
            }
            blob.brain?.goal = spot
            blob.lastCell = Int32(grid.index(at: spot))
            blobs.append(blob)
            pour(id, at: spot, radius: 31)
        }

        retraceOutlines()
        for i in blobs.indices {
            blobs[i].shownShare = share(of: i)
            blobs[i].shownRank = Double(rank(of: i))
        }
    }

    // MARK: Read-outs

    var remaining: Double { max(roundLength - elapsed, 0) }

    /// Percent of the board.
    func share(of i: Int) -> Double { Double(blobs[i].cells) * 100 / Double(cellCount) }

    func shareTenths(of i: Int) -> Int { tenths(ofCells: blobs[i].cells) }

    private func tenths(ofCells cells: Int) -> Int { Int((Double(cells) * 1000 / Double(cellCount)).rounded()) }

    /// Solo only: how much of this stroke's ink is left, 0 to 1.
    var inkLevel: Double {
        let me = blobs[0]
        if me.dry { return 0 }
        return me.drawing ? max(1 - me.trailLength / InklandModel.inkSupply, 0) : 1
    }

    /// Whoever has the most land, or nil while nobody has any. Equal land goes to the lower id.
    var leader: Int? {
        var most = 0
        var who: Int?
        for blob in blobs where blob.cells > most {
            most = blob.cells
            who = blob.id
        }
        return who
    }

    /// 1 means the most land. The local player takes a tie.
    var localPlacement: Int {
        let mine = blobs[0].cells
        return 1 + blobs.dropFirst().filter { $0.cells > mine }.count
    }

    func result() -> GameResult {
        let score = shareTenths(of: 0)
        let biggest = tenths(ofCells: blobs[0].biggestLoop)
        return GameResult(score: score, unit: "of the land", scoreText: InklandModel.percent(score),
                          detail: biggest > 0 ? "Biggest loop " + InklandModel.percent(biggest) : "No loops closed",
                          placement: solo ? nil : localPlacement, playerCount: solo ? nil : blobs.count)
    }

    /// "23.6%" for 236.
    static func percent(_ tenths: Int) -> String { "\(tenths / 10).\(tenths % 10)%" }

    func drainEvents() -> [Event] {
        guard !events.isEmpty else { return [] }
        defer { events.removeAll(keepingCapacity: true) }
        return events
    }

    // MARK: Input

    /// Any touch. The first one starts the round.
    func touch() {
        guard stage == .ready else { return }
        stage = .playing
        events.append(.started)
    }

    /// Points the local blob along (dx, dy). It keeps going that way until told otherwise.
    func steer(dx: Double, dy: Double) {
        guard stage == .ready || stage == .playing, blobs[0].brain == nil else { return }
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 0.0001, length.isFinite else { return }
        let way = CGVector(dx: dx / length, dy: dy / length)
        blobs[0].target = way
        // Before the round starts there is nothing to turn through, so it just faces that way.
        if stage == .ready { blobs[0].heading = way }
    }

    // MARK: Clock

    func step(dt rawDt: Double) {
        let dt = min(max(rawDt, 0), 1.0 / 30.0)
        guard dt > 0 else { return }
        clock += dt
        dropOldEffects()

        switch stage {
        case .ready, .finished:
            easeReadouts(dt)
        case .ending:
            endingAge += dt
            for i in blobs.indices { blobs[i].pace *= max(0, 1 - dt * 8) }
            easeReadouts(dt)
            if endingAge >= InklandModel.endingLength { stage = .finished }
        case .playing:
            play(dt)
        }
    }

    private func play(_ dt: Double) {
        // A tick for each of the last five seconds.
        let secondsBefore = remaining.rounded(.up)
        elapsed += dt
        let left = remaining
        if left > 0, left <= 5, left.rounded(.up) < secondsBefore { events.append(.tick) }

        for i in blobs.indices {
            if blobs[i].alive {
                if blobs[i].brain != nil { think(i, dt: dt) }
                move(i, dt: dt)
            } else {
                blobs[i].respawnIn -= dt
                if blobs[i].respawnIn <= 0 { respawn(i) }
            }
        }

        watchForThreat(dt)
        retraceOutlines()
        easeReadouts(dt)

        if elapsed >= roundLength || (solo && blobs[0].cells >= cellCount) {
            stage = .ending
            endingAge = 0
            threat = nil
            events.append(.timeUp)
        }
    }

    private func easeReadouts(_ dt: Double) {
        let pull = 1 - exp(-dt * 9)
        for i in blobs.indices {
            let trueShare = share(of: i)
            let shareGap = trueShare - blobs[i].shownShare
            blobs[i].shownShare = abs(shareGap) < 0.004 ? trueShare : blobs[i].shownShare + shareGap * pull
            let trueRank = Double(rank(of: i))
            let rankGap = trueRank - blobs[i].shownRank
            blobs[i].shownRank = abs(rankGap) < 0.01 ? trueRank : blobs[i].shownRank + rankGap * pull
        }
    }

    /// 0 means the most land. With equal land the lower id is on top.
    private func rank(of i: Int) -> Int {
        let mine = blobs[i].cells
        return blobs.filter { $0.id != i && ($0.cells > mine || ($0.cells == mine && $0.id < i)) }.count
    }

    private func dropOldEffects() {
        if let oldest = claims.first, clock - oldest.born > oldest.life { claims.removeFirst() }
        if let oldest = wipes.first, clock - oldest.born > InklandWipe.life { wipes.removeFirst() }
        if let oldest = popups.first, clock - oldest.born > oldest.life { popups.removeFirst() }
    }

    private func nextEffectID() -> Int {
        effectCount += 1
        return effectCount
    }

    // MARK: Land

    private func give(_ c: Int, to i: Int) {
        let before = Int(land[c])
        guard before != i else { return }
        if before >= 0 {
            blobs[before].cells -= 1
            blobs[before].dirty = true
        }
        land[c] = Int8(i)
        blobs[i].cells += 1
        blobs[i].dirty = true
    }

    /// The nearest cell of blob i's land, and how far away its centre is.
    func nearestOwn(_ i: Int, from p: CGPoint) -> (point: CGPoint, dist: Double) {
        let cols = grid.cols
        let me = Int8(i)
        // Measured in cells, between cell centres.
        let px = Double(p.x) / grid.cell - 0.5
        let py = Double(p.y) / grid.cell - 0.5
        var closest = Double.greatestFiniteMagnitude
        var found = -1
        land.withUnsafeBufferPointer { cells in
            for y in 0..<rows {
                let dy = Double(y) - py
                // A whole row further away than the best so far cannot help.
                guard dy * dy < closest else { continue }
                let row = y * cols
                for x in 0..<cols where cells[row + x] == me {
                    let dx = Double(x) - px
                    let d = dx * dx + dy * dy
                    if d < closest {
                        closest = d
                        found = row + x
                    }
                }
            }
        }
        guard found >= 0 else { return (p, 0) }
        return (grid.centre(of: found), closest.squareRoot() * grid.cell)
    }

    /// The middle of blob i's land.
    private func landCentre(_ i: Int) -> CGPoint {
        let cols = grid.cols
        let me = Int8(i)
        var sumX = 0
        var sumY = 0
        var n = 0
        for c in 0..<cellCount where land[c] == me {
            sumX += c % cols
            sumY += c / cols
            n += 1
        }
        guard n > 0 else { return blobs[i].pos }
        return CGPoint(x: (Double(sumX) / Double(n) + 0.5) * grid.cell, y: (Double(sumY) / Double(n) + 0.5) * grid.cell)
    }

    /// The nearest point of blob v's open trail. Its head counts as part of the trail.
    private func nearestTrailPoint(of v: Int, from p: CGPoint) -> (point: CGPoint, dist: Double) {
        var at = blobs[v].pos
        var closest = at.distance(to: p)
        let trail = blobs[v].trail
        // Every other point is plenty.
        for k in stride(from: 0, to: trail.count, by: 2) {
            let d = trail[k].distance(to: p)
            if d < closest {
                closest = d
                at = trail[k]
            }
        }
        return (at, closest)
    }

    /// Pours a wobbly round pool of blob i's ink. With noting on, the cells that change hands are
    /// written into fresh.
    private func pour(_ i: Int, at p: CGPoint, radius: Double, noting: Bool = false) {
        let cols = grid.cols
        let cell = grid.cell
        let p1 = rng.range(0, 6.283)
        let p2 = rng.range(0, 6.283)
        let p3 = rng.range(0, 6.283)
        let reach = radius * 1.25
        let px = Double(p.x)
        let py = Double(p.y)
        let x0 = max(Int((px - reach) / cell), 0)
        let x1 = min(Int((px + reach) / cell), cols - 1)
        let y0 = max(Int((py - reach) / cell), 0)
        let y1 = min(Int((py + reach) / cell), rows - 1)
        guard x0 <= x1, y0 <= y1 else { return }
        for y in y0...y1 {
            for x in x0...x1 {
                let dx = (Double(x) + 0.5) * cell - px
                let dy = (Double(y) + 0.5) * cell - py
                let edge = radius * (1 + 0.15 * InklandSceneGeo.wobble(atan2(dy, dx), p1, p2, p3))
                guard (dx * dx + dy * dy).squareRoot() <= edge else { continue }
                let c = y * cols + x
                if noting, Int(land[c]) != i { fresh[c] = 1 }
                give(c, to: i)
            }
        }
    }

    private func retraceOutlines() {
        for i in blobs.indices where blobs[i].dirty {
            blobs[i].outline = blobs[i].cells > 0 ? tracer.loops(around: Int8(i), in: land) : []
            blobs[i].outlineVersion += 1
            blobs[i].dirty = false
        }
    }

    // MARK: Movement

    private func move(_ i: Int, dt: Double) {
        let cols = grid.cols
        let cell = grid.cell
        let local = blobs[i].isLocal

        // Turn towards the target. A finger turns the blob twice as fast as a brain does.
        let facing = atan2(Double(blobs[i].heading.dy), Double(blobs[i].heading.dx))
        var turn = atan2(Double(blobs[i].target.dy), Double(blobs[i].target.dx)) - facing
        while turn > .pi { turn -= 2 * .pi }
        while turn < -.pi { turn += 2 * .pi }
        let mostTurn = (local && blobs[i].brain == nil ? 11.0 : 5.5) * dt
        let angle = facing + clamp(turn, -mostTurn, mostTurn)
        let hx = cos(angle)
        let hy = sin(angle)
        blobs[i].heading = CGVector(dx: hx, dy: hy)

        // Go in hops of two points at most, so no cell is jumped over.
        let reach = blobs[i].cruise * dt
        let hops = max(1, Int((reach / 2.0).rounded(.up)))
        let hop = reach / Double(hops)
        let wall = 2.6
        let farX = width - wall
        let farY = height - wall
        var covered = 0.0

        for _ in 0..<hops {
            guard blobs[i].alive else { break }
            let px = Double(blobs[i].pos.x)
            let py = Double(blobs[i].pos.y)
            var nx = px + hx * hop
            var ny = py + hy * hop
            // Against a wall it slides along at full speed instead of slowing down.
            let pastX = nx < wall || nx > farX
            let pastY = ny < wall || ny > farY
            if pastX, !pastY, abs(hy) > 0.12 { ny = py + (hy > 0 ? hop : -hop) }
            if pastY, !pastX, abs(hx) > 0.12 { nx = px + (hx > 0 ? hop : -hop) }
            nx = clamp(nx, wall, farX)
            ny = clamp(ny, wall, farY)
            let mx = nx - px
            let my = ny - py
            let moved = (mx * mx + my * my).squareRoot()
            covered += moved
            let from = CGPoint(x: px, y: py)
            blobs[i].pos = CGPoint(x: nx, y: ny)

            let was = Int(blobs[i].lastCell)
            let wasX = was % cols
            let wasY = was / cols
            let nowX = min(max(Int(nx / cell), 0), cols - 1)
            let nowY = min(max(Int(ny / cell), 0), rows - 1)
            if nowX != wasX || nowY != wasY {
                if nowX != wasX, nowY != wasY {
                    // A diagonal hop also passes through one of the two cells in between: the one
                    // whose border it crosses first. Without this a trail could be slipped through.
                    let borderX = Double(max(wasX, nowX)) * cell
                    let borderY = Double(max(wasY, nowY)) * cell
                    let whenX = abs(mx) > 1e-9 ? (borderX - px) / mx : 2
                    let whenY = abs(my) > 1e-9 ? (borderY - py) / my : 2
                    enter(whenX < whenY ? wasY * cols + nowX : nowY * cols + wasX, as: i, from: from)
                }
                if blobs[i].alive { enter(nowY * cols + nowX, as: i, from: from) }
                blobs[i].lastCell = Int32(nowY * cols + nowX)
            }

            if blobs[i].alive, blobs[i].drawing {
                blobs[i].trailLength += moved
                if let last = blobs[i].trail.last, last.distance(to: blobs[i].pos) >= blobs[i].trailSpacing {
                    blobs[i].trail.append(blobs[i].pos)
                    if blobs[i].trail.count > 900 { thinTrail(i) }
                }
                if solo, local { spendInk() }
            }
        }

        let made = reach > 0 ? min(covered / reach, 1) : 0
        blobs[i].pace += (made - blobs[i].pace) * min(dt * 10, 1)
    }

    /// Halves the number of points in a very long trail and doubles the gap between new ones.
    private func thinTrail(_ i: Int) {
        let dense = blobs[i].trail
        var sparse: [CGPoint] = []
        sparse.reserveCapacity(dense.count / 2 + 2)
        for k in stride(from: 0, to: dense.count, by: 2) { sparse.append(dense[k]) }
        if dense.count.isMultiple(of: 2), let head = dense.last { sparse.append(head) }
        blobs[i].trail = sparse
        blobs[i].trailSpacing *= 2
    }

    /// Blob i has just moved into cell c, coming from the point from.
    private func enter(_ c: Int, as i: Int, from: CGPoint) {
        let crossed = Int(lines[c])
        if crossed >= 0, crossed != i { cut(crossed, by: i, crossedTrail: true) }

        if Int(land[c]) == i {
            // Home ground: the ink is full again and an open trail becomes a loop.
            blobs[i].dry = false
            if blobs[i].drawing { closeLoop(i) }
            return
        }
        guard !blobs[i].dry else { return }
        if !blobs[i].drawing {
            blobs[i].drawing = true
            blobs[i].trail.removeAll(keepingCapacity: true)
            blobs[i].trail.append(from)
            blobs[i].trailCells.removeAll(keepingCapacity: true)
            blobs[i].trailLength = 0
            blobs[i].trailSpacing = 2.5
            blobs[i].lowInkWarned = false
        }
        if lines[c] < 0 {
            lines[c] = Int8(i)
            blobs[i].trailCells.append(Int32(c))
        }
    }

    private func eraseTrail(_ i: Int) {
        for c in blobs[i].trailCells where Int(lines[Int(c)]) == i { lines[Int(c)] = -1 }
        blobs[i].trailCells.removeAll(keepingCapacity: true)
        blobs[i].trail.removeAll(keepingCapacity: true)
        blobs[i].trailLength = 0
        blobs[i].drawing = false
    }

    /// Solo only. A stroke reaches only so far, and when the ink runs out the trail is lost.
    private func spendInk() {
        let level = inkLevel
        if level <= 0 {
            if wipes.count >= 6 { wipes.removeFirst() }
            wipes.append(InklandWipe(id: nextEffectID(), owner: 0, outline: [], trail: blobs[0].trail + [blobs[0].pos],
                                     at: blobs[0].pos, born: clock))
            eraseTrail(0)
            blobs[0].dry = true
            say("Ink ran out", at: blobs[0].pos, ink: 0, life: 1.3)
            events.append(.dried)
        } else if level < 0.3, !blobs[0].lowInkWarned {
            blobs[0].lowInkWarned = true
            events.append(.lowInk)
        }
    }

    // MARK: Claiming

    /// Blob i is back on its own land with a trail open: the trail and all it encloses become its land.
    private func closeLoop(_ i: Int) {
        let cols = grid.cols
        let me = Int8(i)
        for c in 0..<cellCount {
            fresh[c] = 0
            reached[c] = false
        }

        for c32 in blobs[i].trailCells {
            let c = Int(c32)
            if Int(lines[c]) == i { lines[c] = -1 }
            if land[c] != me {
                give(c, to: i)
                fresh[c] = 1
            }
        }

        // Flood inwards from the walls through everything that is not this blob's land. Whatever
        // the flood cannot get to is shut in.
        frontier.removeAll(keepingCapacity: true)
        func wade(_ c: Int) {
            guard !reached[c], land[c] != me else { return }
            reached[c] = true
            frontier.append(Int32(c))
        }
        for x in 0..<cols {
            wade(x)
            wade(cellCount - cols + x)
        }
        for y in 0..<rows {
            wade(y * cols)
            wade(y * cols + cols - 1)
        }
        while let c32 = frontier.popLast() {
            let c = Int(c32)
            let x = c % cols
            if x > 0 { wade(c - 1) }
            if x < cols - 1 { wade(c + 1) }
            if c >= cols { wade(c - cols) }
            if c < cellCount - cols { wade(c + cols) }
        }
        for c in 0..<cellCount where !reached[c] && land[c] != me {
            give(c, to: i)
            fresh[c] = 1
        }

        var gained = 0
        var sumX = 0
        var sumY = 0
        for c in 0..<cellCount where fresh[c] == 1 {
            gained += 1
            sumX += c % cols
            sumY += c / cols
        }

        let origin = blobs[i].pos
        let rim = blobs[i].trail + [origin]
        eraseTrail(i)

        if gained > 0 {
            let gain = Double(gained) * 100 / Double(cellCount)
            let centroid = CGPoint(x: (Double(sumX) / Double(gained) + 0.5) * grid.cell,
                                   y: (Double(sumY) / Double(gained) + 0.5) * grid.cell)
            let local = blobs[i].isLocal
            let big = gain >= 8
            // The local player's loops get a longer show.
            let life = local ? (big ? 1.3 : 0.9) : 0.5
            if claims.count >= 6 { claims.removeFirst() }
            claims.append(InklandClaim(id: nextEffectID(), owner: i, gain: gain, region: tracer.loops(around: 1, in: fresh),
                                       centroid: centroid, rim: rim, origin: origin, born: clock, life: life))
            blobs[i].loops += 1
            blobs[i].biggestLoop = max(blobs[i].biggestLoop, gained)
            if local {
                let tenths = Int((gain * 10).rounded())
                if tenths > 0 { say("+" + InklandModel.percent(tenths), at: centroid, ink: i, life: life, big: big) }
                events.append(.claimed(big: big))
            }
        }

        cutTheLandless(by: i, except: i)
    }

    /// Anyone left with no land at all is out.
    private func cutTheLandless(by taker: Int?, except i: Int) {
        for j in blobs.indices where j != i && blobs[j].alive && blobs[j].cells == 0 {
            cut(j, by: taker, crossedTrail: false)
        }
    }

    private func say(_ label: String, at p: CGPoint, ink: Int, life: Double, big: Bool = false) {
        if popups.count >= 6 { popups.removeFirst() }
        // Keep the words on the board.
        let at = CGPoint(x: clamp(Double(p.x), 64, width - 64), y: clamp(Double(p.y), 44, height - 16))
        popups.append(InklandPopup(id: nextEffectID(), at: at, label: label, ink: ink, born: clock, life: life, big: big))
    }

    // MARK: Cuts and respawns

    /// Blob v loses its trail and all its land, and comes back on a small pool a moment later.
    private func cut(_ v: Int, by cutter: Int?, crossedTrail: Bool) {
        guard blobs[v].alive else { return }
        let cutterIsLocal = cutter.map { blobs[$0].isLocal } ?? false
        if !crossedTrail {
            cutCauses[3] += 1
        } else if cutterIsLocal {
            cutCauses[2] += 1
        } else if let cutter, blobs[cutter].brain?.mode == .hunt {
            cutCauses[0] += 1
        } else {
            cutCauses[1] += 1
        }

        if wipes.count >= 6 { wipes.removeFirst() }
        wipes.append(InklandWipe(id: nextEffectID(), owner: v, outline: blobs[v].outline,
                                 trail: blobs[v].drawing ? blobs[v].trail + [blobs[v].pos] : blobs[v].trail,
                                 at: blobs[v].pos, born: clock))

        eraseTrail(v)
        let gone = Int8(v)
        for c in 0..<cellCount where land[c] == gone { land[c] = -1 }
        blobs[v].cells = 0
        blobs[v].outline = []
        blobs[v].outlineVersion += 1
        blobs[v].dirty = false
        blobs[v].alive = false
        blobs[v].dry = false
        blobs[v].pace = 0
        blobs[v].respawnIn = InklandModel.respawnDelay
        if let cutter { blobs[cutter].cuts += 1 }

        if blobs[v].isLocal {
            if let cutter {
                say(blobs[cutter].name + (crossedTrail ? " cut your trail" : " took your land"), at: blobs[v].pos, ink: v, life: 1.4)
            }
            events.append(.gotCut)
        } else if let cutter, cutterIsLocal {
            say("You cut " + blobs[v].name, at: blobs[v].pos, ink: cutter, life: 1.2)
            events.append(.cutRival)
        }
    }

    private func respawn(_ i: Int) {
        // Try forty spots and take the one with the most room: far from the others, on open ground.
        let middle = CGPoint(x: width / 2, y: height / 2)
        var spot = middle
        var best = -Double.greatestFiniteMagnitude
        for _ in 0..<40 {
            let p = CGPoint(x: rng.range(44, width - 44), y: rng.range(44, height - 44))
            var room = 400.0
            for other in blobs where other.alive && other.id != i { room = min(room, other.pos.distance(to: p)) }
            var open = land[grid.index(at: p)] < 0 ? 1 : 0
            for k in 0..<8 {
                let a = Double(k) * .pi / 4
                let c = grid.index(at: CGPoint(x: Double(p.x) + cos(a) * 30, y: Double(p.y) + sin(a) * 30))
                if land[c] < 0, lines[c] < 0 { open += 1 }
            }
            let score = min(room, 170) + Double(open) * 9
            if score > best {
                best = score
                spot = p
            }
        }

        let facing = spot.direction(to: middle)
        blobs[i].pos = spot
        blobs[i].lastCell = Int32(grid.index(at: spot))
        blobs[i].heading = facing
        // A player's own steering survives a respawn.
        if blobs[i].brain != nil { blobs[i].target = facing }
        blobs[i].alive = true
        blobs[i].pace = 0
        if var brain = blobs[i].brain {
            brain.mode = .inside
            brain.hasPlan = false
            brain.rest = rng.range(0.2, 0.6) * brain.dwell
            brain.goal = spot
            brain.swerveLeft = 0
            brain.think = rng.range(0.1, 0.4)
            blobs[i].brain = brain
        }

        for c in 0..<cellCount { fresh[c] = 0 }
        pour(i, at: spot, radius: 29, noting: true)
        if claims.count >= 6 { claims.removeFirst() }
        claims.append(InklandClaim(id: nextEffectID(), owner: i, gain: 0, region: tracer.loops(around: 1, in: fresh),
                                   centroid: spot, rim: [], origin: spot, born: clock, life: 0.5))
        if blobs[i].isLocal { events.append(.respawned) }
        cutTheLandless(by: nil, except: i)
    }

    // MARK: Threat marker

    private func watchForThreat(_ dt: Double) {
        var nearest: (rival: Int, index: Int, dist: Double)?
        let me = blobs[0]
        if !solo, me.alive, me.drawing, me.trailLength > 40, me.trail.count > 1 {
            let gap = max(1, me.trail.count / 160)
            for rival in blobs.dropFirst() where rival.alive {
                var dist = Double.greatestFiniteMagnitude
                var index = 0
                for k in stride(from: 0, to: me.trail.count, by: gap) {
                    let d = me.trail[k].distance(to: rival.pos)
                    if d < dist {
                        dist = d
                        index = k
                    }
                }
                guard dist < 90 else { continue }
                // A threat is a rival hunting this trail, or one very close and heading for it.
                let way = rival.pos.direction(to: me.trail[index])
                let closing = Double(rival.heading.dx * way.dx + rival.heading.dy * way.dy)
                let hunting = rival.brain?.mode == .hunt && rival.brain?.victim == 0
                guard hunting || (dist < 36 && closing > 0.5) else { continue }
                if dist < nearest?.dist ?? .greatestFiniteMagnitude { nearest = (rival.id, index, dist) }
            }
        }

        if let nearest {
            if threat == nil, clock - lastThreatEvent > 1.5 {
                lastThreatEvent = clock
                events.append(.threat)
            }
            threat = InklandThreat(rival: nearest.rival, index: nearest.index, level: min(1, (threat?.level ?? 0) + dt * 7))
        } else if var fading = threat {
            fading.level -= dt * 5
            threat = fading.level > 0 && blobs[0].drawing ? fading : nil
        }
    }

    // MARK: Rivals

    private func think(_ i: Int, dt: Double) {
        guard var brain = blobs[i].brain else { return }
        let pos = blobs[i].pos
        let drawing = blobs[i].drawing

        // First bring the mode into line with what has happened on the board.
        if brain.mode == .inside, drawing {
            if brain.hasPlan {
                setOut(&brain, from: pos)
            } else {
                runHome(i, &brain)
            }
        } else if brain.mode == .out || brain.mode == .home, !drawing {
            settle(i, &brain, rest: rng.range(0.7, 2.0) * brain.dwell)
        }
        if brain.rest > 0 { brain.rest -= dt }

        brain.think -= dt
        if brain.think <= 0 {
            // The careless ones look around less often.
            let pause = rng.range(0.10, 0.16) * (brain.caution < 0.9 ? 1.8 : 1)
            brain.think = pause
            reconsider(i, &brain, after: pause)
        }

        // Steer.
        switch brain.mode {
        case .inside:
            if brain.hasPlan {
                blobs[i].target = brain.outward
            } else if brain.goal.distance(to: pos) > 14 {
                blobs[i].target = pos.direction(to: brain.goal)
            }
        case .out:
            if brain.nextCorner < brain.corners.count, brain.corners[brain.nextCorner].distance(to: pos) < 13 {
                brain.nextCorner += 1
            }
            if brain.nextCorner < brain.corners.count {
                blobs[i].target = pos.direction(to: brain.corners[brain.nextCorner])
            } else {
                runHome(i, &brain)
                blobs[i].target = pos.direction(to: brain.goal)
            }
        case .home, .hunt:
            if brain.goal.distance(to: pos) > 1 { blobs[i].target = pos.direction(to: brain.goal) }
        }

        if brain.swerveLeft > 0 { brain.swerveLeft -= dt }
        if brain.mode != .hunt {
            mindTrails(i, &brain)
            if brain.swerveLeft > 0, brain.mode != .hunt { blobs[i].target = brain.swerve }
        }
        blobs[i].brain = brain
    }

    /// The blob has just left its land with a plan: lay out the corners of the loop from where it stands.
    private func setOut(_ brain: inout InklandBrain, from pos: CGPoint) {
        let a = brain.outLength
        let b = brain.acrossLength
        let ux = Double(brain.outward.dx)
        let uy = Double(brain.outward.dy)
        let vx = Double(brain.across.dx)
        let vy = Double(brain.across.dy)
        let px = Double(pos.x)
        let py = Double(pos.y)
        let first = CGPoint(x: px + ux * a, y: py + uy * a)
        let second = CGPoint(x: Double(first.x) + vx * b, y: Double(first.y) + vy * b)
        // The last corner leans a little outwards, so it comes home at a slant.
        let third = CGPoint(x: px + vx * b + ux * a * 0.12, y: py + vy * b + uy * a * 0.12)
        brain.corners = [first, second, third].map {
            CGPoint(x: clamp(Double($0.x), 8, width - 8), y: clamp(Double($0.y), 8, height - 8))
        }
        brain.nextCorner = 0
        brain.trailBudget = (a + b) * 2 * 1.5 + 60
        brain.mode = .out
    }

    private func runHome(_ i: Int, _ brain: inout InklandBrain) {
        brain.mode = .home
        brain.goal = nearestOwn(i, from: blobs[i].pos).point
    }

    /// Back on its own land with nothing open: drop the plan and drift to the middle.
    private func settle(_ i: Int, _ brain: inout InklandBrain, rest: Double? = nil) {
        brain.mode = .inside
        brain.hasPlan = false
        brain.planAge = 0
        if let rest { brain.rest = rest }
        brain.goal = landCentre(i)
    }

    /// One decision. pause is the time until the next one.
    private func reconsider(_ i: Int, _ brain: inout InklandBrain, after pause: Double) {
        let pos = blobs[i].pos
        let drawing = blobs[i].drawing
        switch brain.mode {
        case .inside:
            if brain.rest <= 0 {
                // Plan a loop, and plan again if this one has gone stale.
                brain.planAge += pause
                if !brain.hasPlan || brain.planAge > 3.5 { plan(i, &brain) }
            }
            considerHunt(i, &brain)
        case .out, .home:
            let home = nearestOwn(i, from: pos)
            if brain.mode == .home { brain.goal = home.point }
            if blobs[i].trailLength > brain.trailBudget || exposed(i, homeDistance: home.dist, caution: brain.caution) {
                brain.mode = .home
                brain.goal = home.point
            } else if brain.mode == .out, blobs[i].trailLength < 110 || home.dist < 50 {
                considerHunt(i, &brain)
            }
        case .hunt:
            brain.huntLeft -= pause
            let v = brain.victim
            var keep = brain.huntLeft > 0 && v >= 0 && blobs[v].alive && blobs[v].drawing
            // A hunter with its own trail open gives up sooner than it would run from a loop.
            if keep, drawing, exposed(i, homeDistance: nearestOwn(i, from: pos).dist, caution: brain.caution * 0.6) {
                keep = false
            }
            if keep {
                brain.goal = nearestTrailPoint(of: v, from: pos).point
            } else if drawing {
                runHome(i, &brain)
            } else {
                settle(i, &brain)
            }
        }
    }

    /// Looks for someone's trail in the way. Mostly the blob swerves round it; now and then it snaps it.
    private func mindTrails(_ i: Int, _ brain: inout InklandBrain) {
        let pos = blobs[i].pos
        let hx = Double(blobs[i].heading.dx)
        let hy = Double(blobs[i].heading.dy)
        guard let other = trailAhead(i, from: pos, dx: hx, dy: hy) else { return }

        let fresh = clock >= brain.shyUntil
        brain.shyUntil = clock + 0.7
        // The local player is left alone for the first ten seconds, and often after that.
        let spared = blobs[other].isLocal && (elapsed < 10 || rng.next() < 0.4)
        if fresh, !spared, brain.aggression > 0, rng.next() < 0.2 * brain.aggression {
            brain.mode = .hunt
            brain.victim = other
            brain.goal = nearestTrailPoint(of: other, from: pos).point
            brain.huntLeft = 1.2
            brain.swerveLeft = 0
            return
        }

        // Already swerving, and not yet heading the way it chose: leave it be.
        guard brain.swerveLeft <= 0 || hx * Double(brain.swerve.dx) + hy * Double(brain.swerve.dy) > 0.8 else { return }
        // Turn to whichever side is clear, trying the side nearer home first. With neither clear, turn back.
        let home = brain.mode == .inside ? brain.goal : nearestOwn(i, from: pos).point
        let homeward = pos.direction(to: home)
        let leftFirst = -hy * Double(homeward.dx) + hx * Double(homeward.dy) >= 0
        var way = CGVector(dx: -hx, dy: -hy)
        for side in leftFirst ? [1.0, -1.0] : [-1.0, 1.0] {
            let sx = -hy * side
            let sy = hx * side
            if trailAhead(i, from: pos, dx: sx, dy: sy) == nil {
                way = CGVector(dx: sx, dy: sy)
                break
            }
        }
        brain.swerve = way
        brain.swerveLeft = 0.4
        if blobs[i].drawing {
            runHome(i, &brain)
        } else {
            brain.hasPlan = false
            brain.rest = max(brain.rest, 0.3)
        }
    }

    /// Feelers: forwards at three distances, and to either side at two. Each is (along, sideways, distance).
    private static let feelers: [(Double, Double, Double)] = [(1, 0, 9), (1, 0, 17), (1, 0, 25), (0.92, 0.39, 12), (0.92, -0.39, 12),
                                                              (0.92, 0.39, 20), (0.92, -0.39, 20)]

    /// Whose open trail, if anyone's, lies just ahead of blob i along (dx, dy).
    private func trailAhead(_ i: Int, from p: CGPoint, dx: Double, dy: Double) -> Int? {
        let px = Double(p.x)
        let py = Double(p.y)
        for (along, sideways, far) in InklandModel.feelers {
            let fx = dx * along - dy * sideways
            let fy = dy * along + dx * sideways
            let tip = CGPoint(x: px + fx * far, y: py + fy * far)
            guard grid.holds(tip, margin: 0) else { continue }
            let found = Int(lines[grid.index(at: tip)])
            if found >= 0, found != i { return found }
        }
        // Someone drawing right in front counts too: their trail is about to be there.
        for other in blobs where other.alive && other.id != i && other.drawing {
            let ox = Double(other.pos.x) - px
            let oy = Double(other.pos.y) - py
            let d = (ox * ox + oy * oy).squareRoot()
            if d < 34, ox * dx + oy * dy > 0.5 * d { return other.id }
        }
        return nil
    }

    /// Could someone get to this blob's open trail before it gets home?
    private func exposed(_ i: Int, homeDistance: Double, caution: Double) -> Bool {
        let timeHome = homeDistance / blobs[i].cruise
        for other in blobs where other.alive && other.id != i {
            let d = nearestTrailPoint(of: i, from: other.pos).dist
            if d / other.cruise < timeHome * 1.15 * caution + 0.25 * caution { return true }
        }
        return false
    }

    /// Now and then, go for an open trail that happens to be close. More often as the round goes on.
    private func considerHunt(_ i: Int, _ brain: inout InklandBrain) {
        guard brain.aggression > 0 else { return }
        let heat = min(1.3, 0.55 + 0.75 * elapsed / roundLength)
        guard rng.next() < 0.09 * brain.aggression * heat else { return }
        let pos = blobs[i].pos
        var range = 30 + 45 * brain.aggression
        var prey: (id: Int, spot: CGPoint)?
        for other in blobs where other.alive && other.id != i && other.drawing {
            if other.isLocal, elapsed < 10 || rng.next() < 0.4 { continue }
            let hit = nearestTrailPoint(of: other.id, from: pos)
            if hit.dist < range {
                range = hit.dist
                prey = (other.id, hit.point)
            }
        }
        guard let prey else { return }
        brain.mode = .hunt
        brain.victim = prey.id
        brain.goal = prey.spot
        brain.huntLeft = 1.7
    }

    /// Chooses the next loop: which way to leave home, how far out, how far across, and which way to turn.
    private func plan(_ i: Int, _ brain: inout InklandBrain) {
        let cell = grid.cell
        let me = Int8(i)
        let pos = blobs[i].pos
        // Loops grow as the round goes on.
        let ramp = 0.8 + 0.5 * min(elapsed / roundLength, 1)
        let firstAngle = rng.range(0, 2 * .pi)
        var best = -Double.greatestFiniteMagnitude
        var found = false

        for k in 0..<10 {
            let angle = firstAngle + Double(k) * .pi / 5
            let ux = cos(angle)
            let uy = sin(angle)

            // Walk this way to the edge of its own land. A wall first means no loop this way.
            var edge = pos
            var walked = 0.0
            var leftHome = false
            while walked < 420 {
                edge = CGPoint(x: Double(edge.x) + ux * cell, y: Double(edge.y) + uy * cell)
                walked += cell
                if !grid.holds(edge, margin: 6) { break }
                if land[grid.index(at: edge)] != me {
                    leftHome = true
                    break
                }
            }
            guard leftHome else { continue }
            let ex = Double(edge.x)
            let ey = Double(edge.y)

            for side in [-1.0, 1.0] {
                let vx = -uy * side
                let vy = ux * side
                var a = rng.range(38, 78) * brain.bold * ramp
                var b = rng.range(46, 96) * brain.bold * ramp
                if solo {
                    // One stroke of ink has to go all the way round.
                    let most = InklandModel.inkSupply * 0.4
                    if a + b > most {
                        let squeeze = most / (a + b)
                        a *= squeeze
                        b *= squeeze
                    }
                }

                // Shrink the rectangle until it is on the board, up to three times.
                var fits = false
                for _ in 0..<4 {
                    let c1 = CGPoint(x: ex + ux * a, y: ey + uy * a)
                    let c2 = CGPoint(x: Double(c1.x) + vx * b, y: Double(c1.y) + vy * b)
                    let c3 = CGPoint(x: ex + vx * b, y: ey + vy * b)
                    if grid.holds(c1, margin: 8), grid.holds(c2, margin: 8), grid.holds(c3, margin: 8) {
                        fits = true
                        break
                    }
                    a *= 0.72
                    b *= 0.72
                }
                guard fits, a > 18, b > 18 else { continue }

                // Sample nine spots inside: open ground is good, a rival's land better, its own a waste.
                var score = 0.0
                for sy in 0..<3 {
                    for sx in 0..<3 {
                        let fa = (Double(sx) + 0.5) / 3 * a
                        let fb = (Double(sy) + 0.5) / 3 * b
                        let owner = land[grid.index(at: CGPoint(x: ex + ux * fa + vx * fb, y: ey + uy * fa + vy * fb))]
                        score += owner == me ? -0.4 : (owner < 0 ? 1.0 : 1.2)
                    }
                }
                score *= (a * b).squareRoot() / 55
                // Anyone near the loop is a risk, weighed by how careful this blob is.
                let centre = CGPoint(x: ex + ux * a / 2 + vx * b / 2, y: ey + uy * a / 2 + vy * b / 2)
                let danger = (a + b) * 0.5 + 30
                for other in blobs where other.alive && other.id != i {
                    let d = other.pos.distance(to: centre)
                    if d < danger { score -= 5 * brain.caution * (1 - d / danger) + 1 }
                }
                score -= walked / 120
                score += rng.range(0, 2)
                if score > best {
                    best = score
                    found = true
                    brain.outward = CGVector(dx: ux, dy: uy)
                    brain.across = CGVector(dx: vx, dy: vy)
                    brain.outLength = a
                    brain.acrossLength = b
                }
            }
        }

        if !found {
            // Boxed in: make for the middle of the board and take whatever is there.
            let inward = pos.direction(to: CGPoint(x: width / 2, y: height / 2))
            brain.outward = inward
            brain.across = CGVector(dx: -inward.dy, dy: inward.dx)
            brain.outLength = 40
            brain.acrossLength = 40
        }
        brain.hasPlan = true
        brain.planAge = 0
    }
}

// MARK: - Drawing

enum InklandInks {
    static let amber = InklandSceneInk(top: 0xFFD08A, base: 0xFF9A3C, side: 0xC8641C, deep: 0x8F4310, tint: 0xFFEBCF)
    static let mint = InklandSceneInk(top: 0x9CF7CF, base: 0x33D69A, side: 0x149A6C, deep: 0x0B7350, tint: 0xD9FDEE)
    /// By blob id. 0 is the local player, coral as in the clip.
    static let all = [InklandScenePalette.coral, InklandScenePalette.cyan, InklandScenePalette.lime, InklandScenePalette.violet,
                      amber, mint]

    static func of(_ index: Int) -> InklandSceneInk { all[min(max(index, 0), all.count - 1)] }
}

/// Paths made from the model's outlines, kept between frames and rebuilt only when the land changes.
final class InklandRenderCache {
    struct Land {
        var version = -1
        var path = Path()
        var box = CGRect.null
        /// The halftone dots for this box.
        var grain = Path()
    }

    private var lands: [Land] = []
    private var regions: [Int: Path] = [:]
    private var rims: [Int: InklandScenePolyline] = [:]
    private var wipes: [Int: Path] = [:]
    private var labels: [String: String] = [:]

    static func path(_ loops: [[CGPoint]]) -> Path {
        var path = Path()
        for loop in loops { InklandSceneGeo.addSmoothLoop(loop, to: &path) }
        return path
    }

    func land(_ blob: InklandBlob) -> Land {
        while lands.count <= blob.id { lands.append(Land()) }
        if lands[blob.id].version != blob.outlineVersion {
            let path = InklandRenderCache.path(blob.outline)
            let box = path.boundingRect
            lands[blob.id] = Land(version: blob.outlineVersion, path: path, box: box, grain: InklandScenePaint.grain(in: box))
        }
        return lands[blob.id]
    }

    /// Looks a value up by effect id, making it on first use. Effects are short-lived, so the
    /// store is simply emptied when it gets large.
    private static func kept<Value>(_ id: Int, in store: inout [Int: Value], make: () -> Value) -> Value {
        if let value = store[id] { return value }
        if store.count > 12 { store.removeAll() }
        let value = make()
        store[id] = value
        return value
    }

    func region(_ claim: InklandClaim) -> Path {
        InklandRenderCache.kept(claim.id, in: &regions) { InklandRenderCache.path(claim.region) }
    }

    func rim(_ claim: InklandClaim) -> InklandScenePolyline {
        InklandRenderCache.kept(claim.id, in: &rims) { InklandScenePolyline(claim.rim) }
    }

    func wipe(_ wipe: InklandWipe) -> Path {
        InklandRenderCache.kept(wipe.id, in: &wipes) { InklandRenderCache.path(wipe.outline) }
    }

    /// A name cut down, to three letters at least, until it fits a leaderboard row.
    func label(_ name: String, limit: CGFloat, fits: (String) -> CGFloat) -> String {
        let key = name + "|" + String(Int(limit.rounded()))
        if let known = labels[key] { return known }
        var short = name
        while short.count > 3, fits(short) > limit { short.removeLast() }
        if labels.count > 40 { labels.removeAll() }
        labels[key] = short
        return short
    }
}

/// Where things sit on the full-screen view.
struct InklandGameLayout {
    /// One design point: the view measured against a 402 x 874 screen.
    let u: CGFloat
    /// Screen points per board unit.
    let scale: CGFloat
    /// The board's top left corner on screen.
    let origin: CGPoint
    /// The first line under the band the app keeps for its own buttons.
    let hudTop: CGFloat

    init(size: CGSize, world: CGSize, solo: Bool) {
        u = min(size.width / 402, size.height / 874)
        hudTop = GameLayout.topBand + 6 * u
        // The board goes under the HUD (a clock alone, or a leaderboard too) and above the home indicator.
        let top = hudTop + (solo ? 34 : 109) * u
        let roomH = max(size.height - GameLayout.bottomInset - 6 - top, 10)
        let roomW = max(size.width - 20, 10)
        scale = min(u, roomW / world.width, roomH / world.height)
        origin = CGPoint(x: (size.width - world.width * scale) / 2, y: top + (roomH - world.height * scale) / 2)
    }
}

/// Draws exactly one frame from the model as it stands.
struct InklandGameCanvas: View {
    let model: InklandModel
    let cache: InklandRenderCache
    /// A new value every frame, so the canvas draws again.
    var frame: Int = 0

    var body: some View {
        Canvas(opaque: true, colorMode: .nonLinear, rendersAsynchronously: false) { context, size in
            guard size.width > 2, size.height > 2 else { return }
            var ctx = context
            InklandGameRenderer(model: model, cache: cache, size: size).draw(&ctx)
        }
    }
}

struct InklandGameRenderer {
    let model: InklandModel
    let cache: InklandRenderCache
    let size: CGSize

    typealias Pal = InklandScenePalette
    typealias Geo = InklandSceneGeo
    typealias Paint = InklandScenePaint

    func draw(_ ctx: inout GraphicsContext) {
        let world = CGSize(width: model.width, height: model.height)
        let layout = InklandGameLayout(size: size, world: world, solo: model.solo)
        let blobs = model.blobs
        let clock = model.clock
        // The painters' animations are timed for the clip, whose phase takes about six seconds to run.
        let beat = clock / 6

        var g = ctx
        g.translateBy(x: layout.origin.x, y: layout.origin.y)
        g.scaleBy(x: layout.scale, y: layout.scale)
        let visible = CGRect(x: -layout.origin.x / layout.scale, y: -layout.origin.y / layout.scale,
                             width: size.width / layout.scale, height: size.height / layout.scale)

        Paint.board(&g, visible: visible, glowCenter: CGPoint(x: world.width / 2, y: world.height * 0.45))
        drawWall(&g, visible: visible, world: world)
        drawWipes(&g)

        // Trails and land: the rivals first, the local player over them.
        for blob in blobs.dropFirst() + blobs.prefix(1) {
            let ink = InklandInks.of(blob.id)
            if blob.alive, blob.drawing, !blob.trail.isEmpty {
                var line = Path()
                line.addLines(blob.trail)
                line.addLine(to: blob.pos)
                Paint.trail(&g, path: line, ink: ink, local: blob.isLocal, clock: beat)
            }
            guard blob.cells > 0 else { continue }
            let land = cache.land(blob)
            var flashes: [InklandSceneFlashSpec] = []
            for claim in model.claims where claim.owner == blob.id {
                let e = (clock - claim.born) / claim.life
                guard e >= 0, e < 1 else { continue }
                flashes.append(InklandSceneFlashSpec(region: cache.region(claim), rim: claim.rim, origin: claim.origin,
                                                     progress: e, ripples: blob.isLocal))
            }
            Paint.territory(&g, ink: ink, path: land.path, box: land.box, splats: [], flashes: flashes, grain: land.grain)
        }

        drawThreat(&g, beat: beat)

        // Blobs lower on the screen overlap the ones above.
        let standing = blobs.filter { $0.alive }.sorted { $0.pos.y < $1.pos.y }
        for blob in standing {
            Paint.streaks(&g, position: blob.pos, heading: blob.heading, speed: blob.pace)
        }
        for blob in standing {
            Paint.avatar(&g, position: blob.pos, heading: blob.heading, speed: blob.pace, ink: InklandInks.of(blob.id),
                         local: blob.isLocal, clock: beat, meter: model.solo && blob.isLocal ? model.inkLevel : nil)
        }

        for claim in model.claims where claim.owner == 0 && claim.gain > 0 && claim.rim.count > 1 {
            let e = (clock - claim.born) / claim.life
            guard e >= 0, e < 1 else { continue }
            Paint.burst(&g, ink: InklandInks.of(0), rim: cache.rim(claim), centroid: claim.centroid, region: cache.region(claim),
                        gain: claim.gain, progress: e, big: claim.gain >= 8)
        }

        let leader = model.solo ? nil : model.leader
        for blob in standing {
            Paint.tag(&g, position: blob.pos, label: blob.isLocal ? "YOU" : blob.name, ink: InklandInks.of(blob.id),
                      local: blob.isLocal, crowned: leader == blob.id, below: blob.pos.y < 50)
        }

        // Solo: a warning beside the blob while the ink is nearly gone, on whichever side has room.
        if model.solo, let me = blobs.first, me.alive, me.drawing, model.inkLevel < 0.3 {
            let aside: CGFloat = me.pos.x > world.width - 60 ? -36 : 36
            Paint.warningBadge(&g, center: CGPoint(x: me.pos.x + aside, y: me.pos.y - 2), k: 1,
                               pulse: 0.5 + 0.5 * sin(beat * .pi * 2 * 26))
        }

        for popup in model.popups {
            let e = (clock - popup.born) / popup.life
            guard e >= 0, e < 1 else { continue }
            Paint.popup(&g, ink: InklandInks.of(popup.ink), centroid: popup.at, label: popup.label, progress: e, big: popup.big)
        }

        Paint.vignette(&ctx, size: size, top: 0.62, bottom: 0.22)
        drawHUD(&ctx, layout)

        let boardHeight = world.height * layout.scale
        switch model.stage {
        case .ready:
            drawHint(&ctx, "Drag to steer", u: layout.u,
                     at: CGPoint(x: size.width / 2, y: layout.origin.y + boardHeight * (model.solo ? 0.72 : 0.665)))
        case .ending, .finished:
            drawEnding(&ctx, at: CGPoint(x: size.width / 2, y: layout.origin.y + boardHeight * 0.5))
        case .playing:
            break
        }
    }

    // MARK: The wall

    private func drawWall(_ g: inout GraphicsContext, visible: CGRect, world: CGSize) {
        let wall = Path(roundedRect: CGRect(origin: .zero, size: world).insetBy(dx: -5, dy: -5), cornerRadius: 13,
                        style: .continuous)
        // Everything outside the wall is dimmed.
        var outside = Path(visible.insetBy(dx: -8, dy: -8))
        outside.addPath(wall)
        g.fill(outside, with: .color(Pal.night.color(0.36)), style: FillStyle(eoFill: true))
        g.stroke(wall.offsetBy(dx: 0, dy: 3), with: .color(Pal.night.color(0.4)), lineWidth: 2.6)
        g.stroke(wall, with: .color(Pal.dot.color(0.8)), lineWidth: 2.2)
    }

    // MARK: Cut blobs fading out

    private func drawWipes(_ g: inout GraphicsContext) {
        for wipe in model.wipes {
            let e = (model.clock - wipe.born) / InklandWipe.life
            guard e >= 0, e < 1 else { continue }
            let ink = InklandInks.of(wipe.owner)
            let left = 1 - e
            let fade = left * left
            let glare = fade * fade

            // The land sinks and fades, with a white glare at the first instant.
            if !wipe.outline.isEmpty {
                let land = cache.wipe(wipe)
                g.fill(land.offsetBy(dx: 0, dy: 8 * left), with: .color(ink.deep.color(0.7 * fade)))
                g.fill(land, with: .color(ink.base.color(0.8 * fade)))
                g.fill(land, with: .color(Pal.white.color(0.5 * glare)))
            }
            // The trail breaks up into dashes.
            if wipe.trail.count > 1 {
                let trail = Geo.open(wipe.trail)
                g.stroke(trail, with: .color(ink.base.color(0.8 * fade)), style: Geo.pen(10, dash: [3 + 10 * left, 2 + 14 * e]))
                g.stroke(trail, with: .color(Pal.white.color(0.7 * glare)), style: Geo.pen(10))
            }

            // A splat where it was cut: twelve drops flying out and a ring.
            var rng = InklandSceneRNG(UInt64(wipe.id) &+ 5)
            let flown = 1 - pow(left, 2.2)
            let shrink = 1 - pow(e, 2.4)
            for _ in 0..<12 {
                let angle = rng.range(0, 2 * .pi)
                let far = 8 + rng.range(12, 38) * flown
                let radius = rng.range(1.8, 4.4) * shrink
                guard radius > 0.3 else { continue }
                let drop = CGPoint(x: wipe.at.x + cos(angle) * far, y: wipe.at.y + sin(angle) * far)
                g.fill(Geo.circle(CGPoint(x: drop.x + 1.5, y: drop.y + 4), radius), with: .color(Pal.night.color(0.22)))
                g.fill(Geo.circle(drop, radius), with: .color(rng.next() < 0.3 ? Pal.white.color() : ink.base.color()))
            }
            g.stroke(Geo.circle(wipe.at, 14 + 30 * flown), with: .color(Pal.white.color(0.7 * fade)), lineWidth: 1.5 + 4 * left)
        }
    }

    // MARK: Threat marker

    private func drawThreat(_ g: inout GraphicsContext, beat: Double) {
        guard let threat = model.threat, let me = model.blobs.first, me.alive, me.drawing, me.trail.count > 1,
              threat.rival < model.blobs.count else { return }
        let rival = model.blobs[threat.rival]
        guard rival.alive else { return }
        // Nine points of trail either side of the one in danger.
        let at = min(max(threat.index, 0), me.trail.count - 1)
        var hot = Path()
        hot.addLines(Array(me.trail[max(at - 9, 0)...min(at + 9, me.trail.count - 1)]))
        Paint.threat(&g, hot: hot, spot: me.trail[at],
                     nose: CGPoint(x: rival.pos.x + rival.heading.dx * 19, y: rival.pos.y + rival.heading.dy * 19),
                     k: threat.level, clock: beat)
    }

    // MARK: HUD

    private func drawHUD(_ ctx: inout GraphicsContext, _ layout: InklandGameLayout) {
        let blobs = model.blobs
        guard let me = blobs.first else { return }
        let u = layout.u
        let margin = 16 * size.width / 402
        let midX = size.width / 2
        let ink = InklandInks.of(0)

        // The score sits top centre, between the app's two corners: a caption, then the number.
        let small = u * 0.9
        let caption = ctx.resolve(Text("YOUR INK").font(.system(size: 10.5 * small, weight: .heavy, design: .rounded))
            .kerning(1.4 * small))
        let captionWidth = 18 * small + caption.measure(in: CGSize(width: 300, height: 40)).width
        Paint.inkCaption(&ctx, origin: CGPoint(x: midX - captionWidth / 2, y: GameLayout.statusBarHeight + 1), u: small, ink: ink)
        Paint.shareNumber(&ctx, share: me.shownShare, ink: ink, x: midX, baseline: GameLayout.topBand - 3 * u, u: u,
                          size: 34, centered: true)

        // Under it, the bar of everyone's share.
        let barWidth = (model.solo ? 150 : 80) * u
        var segments = [(share: me.shownShare, ink: ink)]
        for rival in blobs.dropFirst().sorted(by: { $0.shownShare > $1.shownShare }) {
            segments.append((rival.shownShare, InklandInks.of(rival.id)))
        }
        // The clip stretches its bar because little of the board is ever claimed there. Here the
        // stretch eases off as the board fills, so the bar never overflows.
        let claimed = segments.reduce(0) { $0 + $1.share }
        let stretch = model.solo ? 1 : min(1.55, max(1, 92 / max(claimed, 1)))
        Paint.splitBar(&ctx, rect: CGRect(x: midX - barWidth / 2, y: layout.hudTop + 7 * u, width: barWidth, height: 8 * u),
                       u: u, segments: segments, gain: stretch)

        let seconds = Int(model.remaining.rounded(.up))
        Paint.timer(&ctx, rect: CGRect(x: margin, y: layout.hudTop, width: 58 * u, height: 22 * u), u: u,
                    label: "\(seconds / 60):" + (seconds % 60 < 10 ? "0" : "") + "\(seconds % 60)",
                    urgent: model.stage == .playing && model.remaining <= 10)

        guard !model.solo else { return }
        // Rows get tighter with five and six players.
        let count = blobs.count
        let rowH = (count <= 4 ? 19.5 : (count == 5 ? 17.5 : 15.2)) * u
        let padY = (count <= 4 ? 6 : 4.5) * u
        let panelW = 142 * u
        let rows = blobs.map { blob -> InklandSceneBoardRow in
            var label = blob.name
            if !blob.isLocal {
                // The top row needs room for its crown.
                let room = panelW - (blob.shownRank < 0.5 ? 86 : 72) * u
                label = cache.label(blob.name, limit: room) { candidate in
                    ctx.resolve(Text(candidate).font(.system(size: 11 * u, weight: .bold, design: .rounded)))
                        .measure(in: CGSize(width: 400, height: 40)).width
                }
            }
            return InklandSceneBoardRow(label: label, share: blob.shownShare, ink: InklandInks.of(blob.id), local: blob.isLocal,
                                        rank: blob.shownRank)
        }
        Paint.leaderboard(&ctx, panelRect: CGRect(x: size.width - margin - panelW, y: layout.hudTop, width: panelW,
                                                  height: rowH * CGFloat(count) + padY * 2),
                          u: u, rowH: rowH, padY: padY, rows: rows)
    }

    /// A pill of words that bobs gently, shown before the round starts.
    private func drawHint(_ ctx: inout GraphicsContext, _ words: String, u: CGFloat, at centre: CGPoint) {
        let bob = sin(model.clock * 3.2) * 2 * u
        let text = ctx.resolve(Text(words).font(.system(size: 15 * u, weight: .heavy, design: .rounded))
            .foregroundColor(Pal.white.color()))
        let textSize = text.measure(in: CGSize(width: 400, height: 60))
        let rect = CGRect(x: centre.x - textSize.width / 2 - 16 * u, y: centre.y - textSize.height / 2 - 8 * u + bob,
                          width: textSize.width + 32 * u, height: textSize.height + 16 * u)
        let pill = Path(roundedRect: rect, cornerRadius: rect.height / 2, style: .continuous)
        ctx.fill(pill.offsetBy(dx: 0, dy: 3 * u), with: .color(Pal.night.color(0.35)))
        ctx.fill(pill, with: .color(Pal.panel.color(0.86)))
        ctx.stroke(pill, with: .color(Pal.white.color(0.22)), lineWidth: u)
        ctx.draw(text, at: CGPoint(x: centre.x, y: centre.y + bob), anchor: .center)
    }

    /// The board dims and a word pops up in the middle and stays.
    private func drawEnding(_ ctx: inout GraphicsContext, at centre: CGPoint) {
        let t = min(model.endingAge / InklandModel.endingLength, 1)
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Pal.night.color(0.3 * min(t / 0.25, 1))))
        let filled = model.solo && model.blobs[0].cells >= model.cellCount
        var banner = ctx
        banner.translateBy(x: centre.x, y: centre.y)
        banner.scaleBy(x: 1.7, y: 1.7)
        // Holding the popup at 0.7 keeps it from rising away or fading.
        Paint.popup(&banner, ink: InklandInks.of(0), centroid: .zero, label: filled ? "Full board" : "Time",
                    progress: min(t * 1.4, 0.7), big: true)
    }
}

// MARK: - Game view

/// Everything one round owns. A class, so that stepping it does not invalidate the view.
final class InklandRun: ObservableObject {
    let model: InklandModel
    let cache = InklandRenderCache()
    private var lastDate: Date?
    private var frame = 0
    /// Where the floating stick is planted while a finger is down.
    private var anchor: CGPoint?
    private var reported = false

    init(options: GameOptions) {
        // For a demo recording the blob steers itself, and the round can be cut short.
        let demo = GameDemo.autopilot
        let length = demo ? min(max(GameDemo.loseAfter ?? 75, 1), 75) : 75
        model = InklandModel(solo: options.solo, friendNames: options.friendNames, seed: options.seed, roundLength: length,
                             autopilot: demo)
    }

    /// Brings the model up to date and returns a number that is different every frame.
    func advance(to date: Date, paused: Bool, link: GameLink) -> Int {
        defer { lastDate = date }
        guard !paused, let last = lastDate else { return frame }
        if GameDemo.autopilot { model.touch() }
        // After a slow frame, catch up in several small steps so the game keeps real time.
        var owed = min(max(date.timeIntervalSince(last), 0), 0.1)
        guard owed > 0 else { return frame }
        while owed > 1e-6 {
            let dt = min(owed, 1.0 / 60.0)
            owed -= dt
            model.step(dt: dt)
        }
        for event in model.drainEvents() { feel(event) }
        if model.stage == .finished, !reported {
            reported = true
            let result = model.result()
            DispatchQueue.main.async { link.finish(result) }
        }
        frame &+= 1
        return frame
    }

    private func feel(_ event: InklandModel.Event) {
        switch event {
        case .started, .tick, .threat, .lowInk, .respawned: GameHaptics.tap()
        case .claimed(let big): big ? GameHaptics.success() : GameHaptics.thud()
        case .cutRival, .dried: GameHaptics.heavy()
        case .gotCut: GameHaptics.fail()
        case .timeUp: GameHaptics.thud()
        }
    }

    /// A floating stick. The blob goes the way the finger has moved from where the stick is
    /// planted, and the stick is dragged along behind a long move, so a small move back is enough
    /// to turn around.
    func drag(start: CGPoint, location: CGPoint, paused: Bool) {
        guard !paused else {
            anchor = nil
            return
        }
        if anchor == nil {
            anchor = start
            model.touch()
        }
        guard let planted = anchor else { return }
        let dx = location.x - planted.x
        let dy = location.y - planted.y
        let pull = hypot(dx, dy)
        guard pull >= 7 else { return }
        model.steer(dx: dx / pull, dy: dy / pull)
        let leash: CGFloat = 38
        if pull > leash { anchor = CGPoint(x: location.x - dx / pull * leash, y: location.y - dy / pull * leash) }
    }

    func dragEnded() { anchor = nil }
}

public struct InklandGame: View {
    @ObservedObject private var link: GameLink
    @StateObject private var run: InklandRun

    public init(options: GameOptions, link: GameLink) {
        self.link = link
        _run = StateObject(wrappedValue: InklandRun(options: options))
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: link.paused)) { timeline in
            let frame = run.advance(to: timeline.date, paused: link.paused, link: link)
            InklandGameCanvas(model: run.model, cache: run.cache, frame: frame)
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { run.drag(start: $0.startLocation, location: $0.location, paused: link.paused) }
                .onEnded { _ in run.dragEnded() }
        )
        .ignoresSafeArea()
    }
}
