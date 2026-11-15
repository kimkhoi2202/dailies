import SwiftUI

// MARK: - Lane Dash, playable
//
// Three lanes and one kart, seen from behind. Swipe, or tap the left or right third of the screen,
// to change lane. Dodge what stands on the road, collect gems, take the ramps. Leaving a dodge to
// the last moment is a near miss and adds distance. The kart gets faster all the time, and the
// round ends when it hits something.
//
//   LaneDashModel    the round: plain Swift, a seeded track, one step(dt:) per tick
//   LaneDashBot      the scripted player used for recordings (GameDemo.autopilot)
//   LaneDashRound    owns a model for one round: clock, touches, haptics, the result
//   LaneDashGame     the view; it draws each frame with the painter in LaneDashScene.swift

// MARK: - Seeded random numbers

/// SplitMix64. The same seed always lays the same track.
struct LaneDashDice {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed &* 0x9E37_79B9_7F4A_7C15 &+ 0xD1B5_4A32_D192_ED03
        _ = next()
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// 0 ..< 1
    mutating func unit() -> Double { Double(next() >> 11) / 9_007_199_254_740_992 }

    /// 0 ..< n
    mutating func below(_ n: Int) -> Int { n > 1 ? Int(next() % UInt64(n)) : 0 }

    mutating func chance(_ p: Double) -> Bool { unit() < p }
}

// MARK: - Model

struct LaneDashItem {
    var kind: LaneDashPropKind
    var lane: Int                   // -1 left, 0 centre, 1 right
    var at: Double                  // road position, in depth units
    var lift = 0.0                  // height above the road (gems)
    var seed = 0.0
    var row = 0
    var span = 0.0                  // ramp: how much road the flight covers
    var wasInPath = false           // the kart was lined up with it at the last moment
    var cleared = false
    var bumpedAt = -1.0             // clock time at which it was shaved or hit
}

struct LaneDashFriend {
    var name: String
    var distance: Int               // where this friend's round ended
    var overtaken = false
}

/// Things that happened in a step. The round turns them into haptics.
struct LaneDashNews: OptionSet {
    let rawValue: Int
    static let started = LaneDashNews(rawValue: 1)
    static let laneChange = LaneDashNews(rawValue: 2)
    static let gem = LaneDashNews(rawValue: 4)
    static let nearMiss = LaneDashNews(rawValue: 8)
    static let launch = LaneDashNews(rawValue: 16)
    static let landing = LaneDashNews(rawValue: 32)
    static let crash = LaneDashNews(rawValue: 64)
    static let overtook = LaneDashNews(rawValue: 128)
    static let newBest = LaneDashNews(rawValue: 256)
}

/// The kart's recent path by road position, for the ribbons of light behind it.
private struct LaneDashWake {
    private static let size = 96
    private static let spacing = 0.012          // road between two samples

    private var road = [Double](repeating: 0, count: size)
    private var x = [Double](repeating: 0, count: size)
    private var height = [Double](repeating: 0, count: size)
    private var newest = -1
    private var count = 0

    mutating func record(road r: Double, x kartX: Double, height h: Double) {
        if count > 0 && r - road[newest] < Self.spacing { return }
        newest = (newest + 1) % Self.size
        road[newest] = r
        x[newest] = kartX
        height[newest] = h
        count = min(count + 1, Self.size)
    }

    /// Where the kart was at road position target, given where it is now.
    func lookUp(_ target: Double, nowRoad: Double, nowX: Double, nowHeight: Double) -> (x: Double, height: Double) {
        var laterRoad = nowRoad
        var laterX = nowX
        var laterHeight = nowHeight
        for age in 0..<count {
            let i = (newest - age + Self.size) % Self.size
            if road[i] <= target {
                let gap = laterRoad - road[i]
                let f = gap > 1e-9 ? (target - road[i]) / gap : 0
                return (x[i] + (laterX - x[i]) * f, height[i] + (laterHeight - height[i]) * f)
            }
            laterRoad = road[i]
            laterX = x[i]
            laterHeight = height[i]
        }
        return (laterX, laterHeight)
    }
}

final class LaneDashModel {
    enum Stage { case ready, running, crashed, over }

    /// Tuning. One depth unit is the distance from the camera to the kart.
    enum Tune {
        static let laneWidth = 86.0
        static let metresPerUnit = 6.0
        static let startSpeed = 2.6             // depth units a second
        static let topSpeed = 9.0
        static let speedGain = 0.045            // depth units a second, every second
        static let steerRate = 20.0             // how hard the kart pulls toward its lane (1/s)
        static let hitHalfWidth = 54.0          // sideways overlap that is a hit
        static let hitFront = 0.30              // the obstacle reaches the kart's nose
        static let hitBack = -0.10              // the obstacle is behind the kart
        static let clearHeight = 30.0           // above this the kart flies over everything
        static let nearMissWindow = 0.24        // seconds before impact that still count as a late dodge
        static let nearMissMetres = 50
        static let rampMetres = 50
        static let jumpHeight = 82.0
        static let rampLip = 0.15               // the kart takes off this far past the ramp's front edge
        static let rampHalfWidth = 56.0
        static let endingSeconds = 1.15         // between the crash and the result
        static let layAhead = 13.5              // the track is laid this far in front of the kart
        static let tightestRowSeconds = 0.60    // between rows, at full difficulty
        static let gemLift = 25.0
    }

    /// Speed once this much road is behind the kart. It is startSpeed + speedGain * time, written
    /// by distance so that the track can be laid for the speed the kart will have when it gets there.
    static func speed(after road: Double) -> Double {
        let squared = Tune.startSpeed * Tune.startSpeed + 2 * Tune.speedGain * max(road, 0)
        return min(Tune.topSpeed, squared.squareRoot())
    }

    // The round
    let solo: Bool
    let bestScore: Int
    private(set) var friends: [LaneDashFriend] = []
    private var dice: LaneDashDice

    // Clock and road
    private(set) var stage = Stage.ready
    private(set) var time = 0.0                 // runs in every stage; drives the animation
    private(set) var runTime = 0.0              // seconds of play
    private(set) var scroll = 0.0               // road travelled, depth units
    private(set) var startScroll = 0.0
    private(set) var speed = Tune.startSpeed

    // Kart
    private(set) var lane = 0
    private(set) var x = 0.0                    // world x, 0 = the centre lane
    private(set) var lean = 0.0                 // -1...1
    private(set) var height = 0.0
    private(set) var climb = 0.0                // 1 rising ... -1 falling
    private(set) var flight: Double? = nil      // 0...1 while in the air
    private(set) var boost = 0.0
    private(set) var landedAt = -10.0
    private(set) var spin = 0.0
    private(set) var shake = 0.0
    private(set) var rush = 1.0
    private var tookOffAt = 0.0
    private var flightRoad = 1.7
    private var wake = LaneDashWake()

    // Track
    private(set) var items: [LaneDashItem] = []
    private var nextRowAt = 9.0                 // measured from the start line
    private var lastRowAt = 0.0
    private var openBefore = [true, true, true]
    private var rows = 0
    private var rowsSinceRamp = 0
    private var rampAfter = 7
    private var seeds = 0.0

    // Score
    private(set) var gems = 0
    private(set) var nearMisses = 0
    private(set) var ramps = 0
    private(set) var extraMetres = 0
    private(set) var shownDistance = 0.0        // eased, so the gates glide
    private(set) var beatBest: Bool
    private var lastNearMissRow = -1

    // Short-lived effects
    private(set) var pickups: [(at: Double, seed: Double)] = []
    private(set) var nearMissAt = -10.0
    private(set) var nearMissX = 0.0
    private(set) var note = ""
    private(set) var noteAt = -10.0
    private(set) var crashAt = -10.0
    private(set) var crashX = 0.0
    private var spinWay = 1.0

    /// What has happened since the round last emptied this.
    var news: LaneDashNews = []

    /// Set once, when the ending has played.
    private(set) var result: GameResult? = nil

    init(options: GameOptions) {
        solo = options.solo
        bestScore = max(0, options.bestScore)
        beatBest = options.bestScore <= 0
        dice = LaneDashDice(seed: options.seed)
        items.reserveCapacity(64)
        pickups.reserveCapacity(8)
        if !options.solo { seatFriends(names: options.friendNames, seed: options.seed) }
    }

    /// Three to five friends whose rounds ended between about 300 and 2,500 m. The range is cut
    /// into one band per friend so they are spread along the road, then the bands are shuffled.
    private func seatFriends(names: [String], seed: UInt64) {
        guard !names.isEmpty else { return }
        var draw = LaneDashDice(seed: seed ^ 0xF00D_CAFE_1234_5678)
        let count = min(3 + draw.below(3), names.count)
        var ends = (0..<count).map { band -> Int in
            let along = (Double(band) + 0.12 + 0.76 * draw.unit()) / Double(count)
            return Int((300 + 2200 * along).rounded())
        }
        var i = count - 1
        while i > 0 {
            ends.swapAt(i, draw.below(i + 1))
            i -= 1
        }
        friends = zip(names, ends).map { LaneDashFriend(name: $0, distance: $1) }
    }

    // MARK: Read-outs

    var distance: Int {
        guard stage != .ready else { return 0 }
        return Int(((scroll - startScroll) * Tune.metresPerUnit).rounded(.down)) + extraMetres
    }

    var playerCount: Int { friends.count + 1 }

    /// 1 = further than every friend.
    var rank: Int {
        let mine = distance
        return 1 + friends.filter { $0.distance > mine }.count
    }

    var standing: String? {
        friends.isEmpty ? nil : "\(Self.ordinal(rank)) of \(playerCount)"
    }

    static func ordinal(_ n: Int) -> String {
        let endings = [1: "st", 2: "nd", 3: "rd"]
        return "\(n)" + (endings[n] ?? "th")
    }

    /// How far up the road (1 = level with the kart) the gate for a score stands.
    func gateDepth(for score: Int) -> Double {
        1 + (Double(score) - shownDistance) / Tune.metresPerUnit
    }

    /// Where the kart was this many depth units of road ago.
    func trail(back road: Double) -> (x: Double, height: Double) {
        wake.lookUp(scroll - road, nowRoad: scroll, nowX: x, nowHeight: height)
    }

    // MARK: Input

    /// The first touch starts the round.
    func start() {
        guard stage == .ready else { return }
        stage = .running
        startScroll = scroll
        runTime = 0
        shownDistance = 0
        news.insert(.started)
        layTrack()
    }

    /// One lane to the left (negative) or to the right (positive).
    func steer(_ direction: Int) {
        guard stage == .running, direction != 0 else { return }
        let wanted = min(1, max(-1, lane + direction.signum()))
        guard wanted != lane else { return }
        lane = wanted
        news.insert(.laneChange)
    }

    // MARK: Step

    /// exp-decay toward a target: the fraction of the gap closed in dt at this rate.
    private static func closing(_ rate: Double, _ dt: Double) -> Double { 1 - exp(-rate * dt) }

    func step(dt tick: Double) {
        let dt = min(max(tick, 0), 1.0 / 30)
        guard dt > 0 else { return }
        time += dt

        switch stage {
        case .ready:
            speed = Tune.startSpeed
            scroll += speed * dt
            steerKart(dt)
            rush += (1 - rush) * Self.closing(6, dt)

        case .running:
            runTime += dt
            let before = scroll
            speed = Self.speed(after: scroll - startScroll)
            scroll += speed * dt
            layTrack()
            steerKart(dt)
            fly()
            meetRoad(from: before)
            if stage == .running {
                overtake()
                items.removeAll { $0.at < scroll - 0.75 }
            }
            let wind = min(1.6, 1 + 0.3 * (speed / Tune.startSpeed - 1))
            rush += (wind - rush) * Self.closing(6, dt)

        case .crashed:
            tumble(dt)

        case .over:
            break
        }

        // the boost glow: full in the air, a little at speed, gone once the round is lost
        var glow = 0.0
        if stage == .running {
            let pace = (speed - Tune.startSpeed) / (Tune.topSpeed - Tune.startSpeed)
            glow = flight != nil ? 1 : 0.3 * min(1, max(0, pace))
        }
        boost += (glow - boost) * Self.closing(glow > boost ? 16 : 5, dt)

        shownDistance += (Double(distance) - shownDistance) * Self.closing(7, dt)
        while let oldest = pickups.first, time - oldest.at > 0.34 { pickups.removeFirst() }
        wake.record(road: scroll, x: x, height: height)
    }

    private func steerKart(_ dt: Double) {
        let goal = Double(lane) * Tune.laneWidth
        let from = x
        x += (goal - x) * Self.closing(Tune.steerRate, dt)
        if abs(goal - x) < 0.05 { x = goal }
        // lean with the sideways speed: 4.5 lanes a second is a full lean
        let lanesPerSecond = (x - from) / dt / Tune.laneWidth
        let wanted = min(1, max(-1, lanesPerSecond / 4.5))
        lean += (wanted - lean) * Self.closing(26, dt)
    }

    /// The jump is a parabola over the road the ramp gave it, so it lands in the same place at any speed.
    private func fly() {
        guard flight != nil else {
            height = 0
            climb = 0
            return
        }
        let s = (scroll - tookOffAt) / flightRoad
        if s < 1 {
            let along = max(0, s)
            flight = along
            height = Tune.jumpHeight * 4 * along * (1 - s)
            climb = 1 - 2 * s
        } else {
            flight = nil
            height = 0
            climb = 0
            landedAt = time
            news.insert(.landing)
        }
    }

    /// The crash: one hop, one small bounce, a full spin that settles a little crooked.
    private func tumble(_ dt: Double) {
        let t = time - crashAt
        if t < 0.5 {
            let s = t / 0.5
            height = 46 * 4 * s * (1 - s)
            climb = 1 - 2 * s
        } else if t < 0.78 {
            let s = (t - 0.5) / 0.28
            height = 14 * 4 * s * (1 - s)
            climb = 0.4 * (1 - 2 * s)
        } else {
            height = 0
            climb = 0
        }
        let settled = 1 - pow(1 - min(1, t / 0.85), 3)
        spin = spinWay * (2 * Double.pi + 0.26) * settled
        shake = sin(t * 58) * 10 * exp(-t * 7)
        lean -= lean * Self.closing(12, dt)
        rush -= rush * Self.closing(14, dt)
        if t >= Tune.endingSeconds {
            stage = .over
            shake = 0
            result = summary()
        }
    }

    /// Everything the kart reaches in this step: gems, ramps, and what it hits or just misses.
    private func meetRoad(from before: Double) {
        var i = 0
        while i < items.count {
            let item = items[i]
            let ahead = item.at - scroll
            if ahead > 3 {
                i += 1
                continue
            }
            let aside = abs(x - Double(item.lane) * Tune.laneWidth)

            switch item.kind {
            case .gem:
                let level = abs(height + Tune.gemLift - item.lift) < 46
                if ahead <= 0.12 && item.at - before > -0.12 && aside < 48 && level {
                    gems += 1
                    if pickups.count >= 6 { pickups.removeFirst() }
                    pickups.append((time, item.seed))
                    news.insert(.gem)
                    items.remove(at: i)
                    continue
                }

            case .ramp:
                let lip = item.at + Tune.rampLip
                if flight == nil && before < lip && scroll >= lip && aside < Tune.rampHalfWidth {
                    flight = 0
                    tookOffAt = lip
                    flightRoad = max(item.span, 0.5)
                    ramps += 1
                    extraMetres += Tune.rampMetres
                    news.insert(.launch)
                    fly()
                }

            case .barrier, .cones, .block, .hurdle:
                guard !item.cleared else { break }
                let onTheRoad = height < Tune.clearHeight
                let inLine = aside < Tune.hitHalfWidth && onTheRoad
                if inLine && ahead < Tune.hitFront && item.at - before > Tune.hitBack {
                    crash(into: i)
                    return
                }
                if inLine && ahead > 0 && ahead < Tune.hitFront + speed * Tune.nearMissWindow {
                    items[i].wasInPath = true
                } else if ahead <= Tune.hitBack {
                    items[i].cleared = true
                    let shaved = onTheRoad && (item.wasInPath || aside < 66)
                    if shaved && item.row != lastNearMissRow {
                        lastNearMissRow = item.row
                        nearMisses += 1
                        extraMetres += Tune.nearMissMetres
                        nearMissAt = time
                        let itsX = Double(item.lane) * Tune.laneWidth
                        nearMissX = itsX + (x >= itsX ? 44 : -44)
                        items[i].bumpedAt = time
                        news.insert(.nearMiss)
                    }
                }
            }
            i += 1
        }
    }

    private func crash(into index: Int) {
        let itsX = Double(items[index].lane) * Tune.laneWidth
        items[index].bumpedAt = time
        stage = .crashed
        crashAt = time
        crashX = (x + itsX) / 2
        // spin away from the thing; head on, either way
        if x < itsX - 4 {
            spinWay = -1
        } else if x > itsX + 4 {
            spinWay = 1
        } else {
            spinWay = dice.chance(0.5) ? 1 : -1
        }
        speed = 0
        flight = nil
        news.insert(.crash)
    }

    private func overtake() {
        let mine = distance
        for i in friends.indices where !friends[i].overtaken && mine >= friends[i].distance {
            friends[i].overtaken = true
            say("Passed \(friends[i].name)")
            news.insert(.overtook)
        }
        if !beatBest && mine > bestScore {
            beatBest = true
            say("New best")
            news.insert(.newBest)
        }
    }

    private func say(_ text: String) {
        note = text
        noteAt = time
    }

    private func summary() -> GameResult {
        let gemsText = gems == 1 ? "1 gem" : "\(gems) gems"
        let missText = nearMisses == 1 ? "1 near miss" : "\(nearMisses) near misses"
        return GameResult(score: distance, unit: "m", detail: "\(gemsText) and \(missText)",
                          placement: friends.isEmpty ? nil : rank,
                          playerCount: friends.isEmpty ? nil : playerCount)
    }

    // MARK: Track
    //
    // The road is laid in rows. Two rules keep it fair. From every lane that was open in one row,
    // the same lane or the one beside it is open in the next. And two rows are never closer than
    // tightestRowSeconds at the speed the kart has there. A lane change takes about a tenth of a
    // second, so there is always a way through.

    private func layTrack() {
        let until = scroll - startScroll + Tune.layAhead
        while nextRowAt < until { layRow() }
    }

    private func place(_ kind: LaneDashPropKind, lane: Int, at road: Double, lift: Double = 0, span: Double = 0) {
        seeds += 1
        items.append(LaneDashItem(kind: kind, lane: lane, at: startScroll + road, lift: lift, seed: seeds, row: rows, span: span))
    }

    /// Can a kart in any lane that was open in the last row reach an open lane here with one move?
    private func fair(_ open: [Bool]) -> Bool {
        for from in 0..<3 where openBefore[from] {
            let reach = max(0, from - 1)...min(2, from + 1)
            if !reach.contains(where: { open[$0] }) { return false }
        }
        return true
    }

    /// A short line of gems on the road that ends just past a row.
    private func trailOfGems(lane: Int, count: Int, lastAt: Double, gap: Double) {
        for back in stride(from: count - 1, through: 0, by: -1) {
            let at = lastAt - Double(back) * gap
            if at > lastRowAt + 0.7 { place(.gem, lane: lane, at: at, lift: Tune.gemLift) }
        }
    }

    private func layRow() {
        let at = nextRowAt
        let pace = Self.speed(after: at)
        let difficulty = min(1, at / 440)
        rows += 1

        if at > 90 && rowsSinceRamp >= rampAfter {
            layRamp(at: at, pace: pace)
            return
        }
        rowsSinceRamp += 1

        // block one lane, or two once the round is under way; retry until the row is fair
        let twoShut = at > 70 && dice.chance(0.1 + 0.5 * difficulty)
        var open: [Bool]? = nil
        for _ in 0..<6 where open == nil {
            var attempt = [twoShut, twoShut, twoShut].map { !$0 }
            let pick = dice.below(3)
            attempt[pick] = twoShut
            if fair(attempt) { open = attempt }
        }
        if open == nil {
            // one shut lane always leaves a way through
            var attempt = [true, true, true]
            attempt[dice.below(3)] = false
            open = attempt
        }
        let lanes = open ?? [true, true, true]

        let stock: [LaneDashPropKind] = [.barrier, .cones, .block]
        for l in 0..<3 where !lanes[l] {
            place(stock[dice.below(3)], lane: l - 1, at: at)
        }

        // gems that lead through one of the open lanes
        let gemGap = max(0.5, pace * 0.11)
        if dice.chance(0.55) {
            let ways = (0..<3).filter { lanes[$0] }
            let way = ways[dice.below(ways.count)] - 1
            trailOfGems(lane: way, count: 3 + dice.below(3), lastAt: at + gemGap, gap: gemGap)
        }

        openBefore = lanes
        lastRowAt = at
        let tight = Tune.tightestRowSeconds
        let seconds = 1.25 - (1.25 - tight) * difficulty + 0.25 * dice.unit()
        nextRowAt = at + max(2.8, pace * seconds)
    }

    /// A ramp, a hurdle to fly over and gems in the air. Every lane is clear where the kart comes down.
    private func layRamp(at: Double, pace: Double) {
        rowsSinceRamp = 0
        rampAfter = 7 + dice.below(6)

        // Half the time the other two lanes are shut, so the ramp cannot be skipped. Then its lane
        // has to be one move from every lane that was open in the last row.
        let candidates = (0..<3).filter { lane in fair((0..<3).map { $0 == lane }) }
        let mustTake = !candidates.isEmpty && dice.chance(0.5)
        let lane = (mustTake ? candidates[dice.below(candidates.count)] : dice.below(3)) - 1
        let span = max(1.7, pace * 0.62)

        place(.ramp, lane: lane, at: at, span: span)
        if mustTake {
            for other in -1...1 where other != lane { place(.barrier, lane: other, at: at - 0.08) }
        }
        let lip = at + Tune.rampLip
        place(.hurdle, lane: lane, at: lip + span * 0.5)
        let alongArc = [0.2, 0.4, 0.6, 0.8]
        for f in alongArc {
            place(.gem, lane: lane, at: lip + span * f, lift: Tune.jumpHeight * 4 * f * (1 - f) + 42)
        }
        let gemGap = max(0.5, pace * 0.11)
        for back in 1...3 {
            let gemAt = at - Double(back) * gemGap
            if gemAt > lastRowAt + 0.7 { place(.gem, lane: lane, at: gemAt, lift: Tune.gemLift) }
        }

        openBefore = [true, true, true]
        lastRowAt = lip + span
        nextRowAt = lastRowAt + max(2.8, pace * 0.7)
    }
}

// MARK: - From the round to a frame

extension LaneDashModel {
    static let clipLoopSeconds = 6.0        // the cosmetic clock runs at the feed clip's pace

    /// What the painter should draw right now.
    func frame() -> LaneDashFrame {
        var f = LaneDashFrame()
        f.clock = CGFloat(time / Self.clipLoopSeconds)
        f.roadClock = CGFloat(scroll / 12)
        f.scroll = CGFloat(scroll)
        f.kartX = CGFloat(x)
        f.lean = CGFloat(lean)
        f.height = CGFloat(height)
        f.climb = CGFloat(climb)
        f.boost = CGFloat(boost)
        f.roll = CGFloat(spin)
        f.rush = CGFloat(rush)
        f.shake = CGFloat(shake)

        let landing = (time - landedAt) / 0.24
        if landing >= 0 && landing < 1 {
            f.squash = CGFloat(sin(landing * .pi))
            f.landRing = CGFloat(landing)
        }

        f.props.reserveCapacity(items.count)
        for item in items {
            let depth = 1 + item.at - scroll
            if depth < 0.3 || depth > 11.3 { continue }
            var wobble = 0.0
            if item.bumpedAt >= 0 {
                let a = (time - item.bumpedAt) / 0.42
                if a > 0 && a < 1 { wobble = sin(a * 3 * .pi) * 0.09 * (1 - a) }
            }
            f.props.append(LaneDashProp(kind: item.kind, lane: CGFloat(item.lane), depth: CGFloat(depth),
                                        lift: CGFloat(item.lift), seed: CGFloat(item.seed), wobble: CGFloat(wobble)))
        }

        for pickup in pickups {
            let age = (time - pickup.at) / 0.33
            if age >= 0 && age <= 1 { f.pops.append((CGFloat(age), CGFloat(pickup.seed))) }
        }

        let miss = (time - nearMissAt) / 0.6
        if miss > 0 && miss < 1 { f.nearMiss = CGFloat(miss) }
        f.nearMissX = CGFloat(nearMissX)
        f.nearMissNote = "+\(Tune.nearMissMetres)"

        if let air = flight, air > 0, air < 1 { f.flight = CGFloat(air) }
        f.flightNote = "+\(Tune.rampMetres)"

        f.wake = { [unowned self] back in
            let was = self.trail(back: Double(back))
            return (CGFloat(was.x), CGFloat(was.height))
        }

        f.distance = distance
        f.gems = gems
        f.pill = standing

        // gates: where each friend's round ended, and the player's own best
        if stage != .ready {
            func raise(_ name: String, at score: Int, gold: Bool) {
                let depth = gateDepth(for: score)
                if depth > 1 && depth < 11.3 { f.gates.append(LaneDashGate(depth: CGFloat(depth), name: name, gold: gold)) }
            }
            for friend in friends { raise(friend.name, at: friend.distance, gold: false) }
            if bestScore > 0 { raise("Your best", at: bestScore, gold: true) }
        }

        if stage == .crashed || stage == .over {
            f.crash = (CGFloat(time - crashAt), CGFloat(crashX))
        }

        let noteAge = time - noteAt
        if noteAge >= 0 && noteAge < 1.7 && !note.isEmpty { f.notice = (note, CGFloat(noteAge)) }

        // the one hint, until the first touch
        if stage == .ready {
            f.hint = ("Swipe to change lane", CGFloat(0.78 + 0.22 * sin(time * 3.2)))
        }
        return f
    }
}

// MARK: - Scripted player
//
// For recordings (GameDemo.autopilot). It plays the way a good player would, and its only inputs
// are start() and steer(_:), the calls a touch makes. All it knows it reads from the model: what
// is on the road ahead, where the kart is, how fast it is going.
//
// It groups the obstacles ahead into rows and scores every way through the next few. Gems on the
// way and ramps score, lane changes cost a little, and a move only counts if a person would have
// time to make it. Then it swipes toward the lane the best way starts in, after a short thinking
// pause and with a rest between swipes. Now and then it sits behind an obstacle on purpose and
// swerves at the last moment, which the game scores as a near miss.

struct LaneDashBot {
    /// One row of the road that the kart has still to get past.
    private struct Row {
        var id: Int
        var at: Double                      // road position of its obstacles, or of its ramp
        var shut = [false, false, false]    // by lane index 0...2
        var ramp = -1                       // lane index of a ramp here, or -1
        var steerAgainAt = 0.0              // a kart that takes the ramp can steer again from here
        var isHurdle = false                // the hurdle under a ramp's flight
        var gems = [0.0, 0.0, 0.0]          // gems that lead through each lane
        var lateGems = [0.0, 0.0, 0.0]      // the ones a last-moment swerve still reaches

        var hasObstacle: Bool { shut.contains(true) }
    }

    private typealias Move = (score: Double, lane: Int, late: Bool)

    static let readyPause = 0.8             // seconds on the ready screen before it starts
    static let swerveLate = 0.14            // a late dodge starts this long before impact, or up to
    static let swerveSpread = 0.06          //   this much earlier (the game allows 0.24 s)
    static let lastCall = 0.12              // closer than this, swipe now whatever else is going on
    private static let hitFront = LaneDashModel.Tune.hitFront

    private let seed: UInt64
    private var fingerFreeAt = 0.0          // model clock
    private var mindMadeUpAbout = Int.min
    private var swipeNotBefore = 0.0
    private var lastSwipeRow = -1
    private var lastSwipeWay = 0
    private var lastSwipeAt = 0.0
    private var lateRow = -1                // the row it is leaving late on purpose
    private var lateLane = 1
    private var nearMissesSeen = 0
    private var hungryFrom = 0.0            // play time from which it looks for a near miss again

    init(seed: UInt64) {
        self.seed = seed
        hungryFrom = 1.5 + 2 * roll(0, 9)
    }

    /// 0 ..< 1, fixed by the round's seed and by what is being decided, not by how often it is asked.
    private func roll(_ about: Int, _ salt: UInt64) -> Double {
        var z = seed ^ (UInt64(truncatingIfNeeded: about) &* 0x9E37_79B9_7F4A_7C15) ^ (salt &* 0xC2B2_AE3D_27D4_EB4F)
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Double(z >> 11) / 9_007_199_254_740_992
    }

    /// Called once a frame, before the model steps.
    mutating func play(_ m: LaneDashModel) {
        if m.stage == .ready {
            if m.time >= Self.readyPause {
                m.start()
                lastSwipeAt = m.time
            }
            return
        }
        guard m.stage == .running else { return }

        let now = m.time
        if m.nearMisses != nearMissesSeen {
            nearMissesSeen = m.nearMisses
            hungryFrom = m.runTime + 5 + 5 * roll(nearMissesSeen, 3)
        }

        // in the air it stays over the ramp's line of gems until the last one is in
        if let air = m.flight, air < 0.84 { return }

        let rows = read(m)
        guard let first = rows.first else { return }
        let lane = m.lane + 1
        let speed = max(m.speed, 0.5)
        let untilHit = (first.at - Self.hitFront - m.scroll) / speed

        if let after = GameDemo.loseAfter, m.runTime >= after {
            giveUp(m, first, lane: lane, untilHit: untilHit)
            return
        }

        // a late dodge it has settled on: hold the lane, then swerve
        if lateRow == first.id && first.shut[lane] {
            if untilHit <= Self.swerveLate + Self.swerveSpread * roll(first.id, 2) {
                swipe(lateLane > lane ? 1 : -1, m, row: first.id)
            }
            return
        }

        // How much it wants a near miss: nothing for a while after one, then more and more. The
        // same a row further on, so it does not wander off just before it would line one up.
        func hunger(at playTime: Double) -> Double {
            playTime >= hungryFrom ? min(16, 4 + 2 * (playTime - hungryFrom)) : 0
        }
        // after a couple of seconds in one lane it likes to move, when that costs it nothing
        let restless = max(0, min(0.9, 0.45 * (now - lastSwipeAt - 1.8)))
        let freeAt = m.scroll + max(0, fingerFreeAt - now) * speed

        var choice = plan(rows, depth: min(rows.count, 4), from: lane, freeAt: freeAt, speed: speed,
                          hunger: hunger(at: m.runTime), hungerSoon: hunger(at: m.runTime + 1.2), restless: restless)
        if choice == nil {
            choice = plan(rows, depth: 1, from: lane, freeAt: freeAt, speed: speed, hunger: 0, hungerSoon: 0, restless: 0)
        }
        guard let best = choice else {
            // no way through with a comfortable margin: get out of the way all the same
            if first.shut[lane] {
                let way = wayOut(first, from: lane)
                if way != 0 { swipe(way, m, row: first.id) }
            }
            return
        }

        if best.late {
            lateRow = first.id
            lateLane = best.lane
            return
        }
        guard best.lane != lane else {
            mindMadeUpAbout = Int.min
            return
        }

        let way = best.lane > lane ? 1 : -1
        let stuck = first.shut[lane]
        let fingerFree = now >= fingerFreeAt

        if stuck && untilHit <= 0.3 {
            if fingerFree || untilHit <= Self.lastCall { swipe(way, m, row: first.id) }
            return
        }

        // a short pause between seeing where to go and the swipe
        let about = first.id * 8 + best.lane
        if about != mindMadeUpAbout {
            mindMadeUpAbout = about
            swipeNotBefore = now + 0.05 + 0.11 * roll(about, 4)
        }
        guard fingerFree, now >= swipeNotBefore else { return }

        let secondHalfOfTwoLaneMove = lastSwipeRow == first.id && lastSwipeWay == way
        var go = true
        if !secondHalfOfTwoLaneMove {
            let gemFirst = untilHit > 0.9 && gemInFront(m)      // take the gem right in front first
            if stuck {
                // gems or a ramp to reach: go now. Otherwise dodge in good time, not at once.
                let worthGoingEarly = first.gems[best.lane] > first.lateGems[best.lane] || first.ramp == best.lane
                let comfort = 0.45 + 0.45 * roll(first.id, 1) + (abs(best.lane - lane) == 2 ? 0.3 : 0)
                go = (worthGoingEarly || untilHit <= comfort) && !gemFirst
            } else {
                go = !gemFirst
            }
        }
        if go { swipe(way, m, row: first.id) }
    }

    private mutating func swipe(_ way: Int, _ m: LaneDashModel, row: Int) {
        m.steer(way)
        fingerFreeAt = m.time + 0.17 + 0.09 * roll(row &* 8 &+ m.lane &+ 1, 5)
        lastSwipeRow = row
        lastSwipeWay = way
        lastSwipeAt = m.time
    }

    /// Losing on request: drift into the next obstacle the way a late or wrong swipe does.
    private mutating func giveUp(_ m: LaneDashModel, _ row: Row, lane: Int, untilHit: Double) {
        guard row.hasObstacle, !row.shut[lane] else { return }      // already behind one: just stay
        let shutLeft = lane > 0 && row.shut[lane - 1]
        let shutRight = lane < 2 && row.shut[lane + 1]
        var way = lane == 0 ? 1 : -1
        var twoLanesAway = true
        if shutLeft && shutRight {
            way = roll(row.id, 11) < 0.5 ? -1 : 1
            twoLanesAway = false
        } else if shutLeft || shutRight {
            way = shutLeft ? -1 : 1
            twoLanesAway = false
        }
        let aim = 0.32 + 0.16 * roll(row.id, 12) + (twoLanesAway ? 0.3 : 0)
        if untilHit <= aim && m.time >= fingerFreeAt { swipe(way, m, row: row.id) }
    }

    /// Which way to swipe out of a shut lane when nothing better is known.
    private func wayOut(_ row: Row, from lane: Int) -> Int {
        if lane > 0 && !row.shut[lane - 1] { return -1 }
        if lane < 2 && !row.shut[lane + 1] { return 1 }
        return 1 - lane
    }

    /// A gem on the road just in front of the kart, in its lane.
    private func gemInFront(_ m: LaneDashModel) -> Bool {
        let reach = 0.28 * m.speed
        return m.items.contains { item in
            guard item.kind == .gem, item.lane == m.lane, item.lift < 40 else { return false }
            let ahead = item.at - m.scroll
            return ahead > -0.1 && ahead < reach
        }
    }

    /// The rows ahead that can still be hit or used, nearest first, with their gems.
    private func read(_ m: LaneDashModel) -> [Row] {
        var rows: [Row] = []
        rows.reserveCapacity(8)
        let flying = m.flight != nil

        /// The row an obstacle or ramp belongs to: the last one if it is the same row of the track.
        func index(row id: Int, at: Double) -> Int {
            if let last = rows.last, last.id == id, !last.isHurdle, abs(last.at - at) < 0.3 {
                return rows.count - 1
            }
            rows.append(Row(id: id, at: at))
            return rows.count - 1
        }

        for item in m.items {
            switch item.kind {
            case .gem:
                break
            case .ramp:
                let lip = item.at + LaneDashModel.Tune.rampLip
                if lip - m.scroll > 0.01 {
                    let i = index(row: item.row, at: item.at)
                    rows[i].ramp = item.lane + 1
                    rows[i].steerAgainAt = lip + 0.84 * max(item.span, 0.5)
                }
            case .hurdle:
                // in the air the kart is over it
                if !item.cleared && !(flying && item.at - m.scroll < 4) {
                    var row = Row(id: item.row, at: item.at)
                    row.isHurdle = true
                    row.shut[item.lane + 1] = true
                    rows.append(row)
                }
            case .barrier, .cones, .block:
                if !item.cleared {
                    let i = index(row: item.row, at: item.at)
                    rows[i].shut[item.lane + 1] = true
                    rows[i].at = min(rows[i].at, item.at)
                }
            }
        }

        for item in m.items where item.kind == .gem && item.at - m.scroll > 0.05 {
            guard let i = rows.firstIndex(where: { $0.id == item.row }) else { continue }
            rows[i].gems[item.lane + 1] += 1
            if item.at >= rows[i].at - 0.3 { rows[i].lateGems[item.lane + 1] += 1 }
        }
        return rows
    }

    /// The best way through the first few rows, as the lane to be in at the first one. late means:
    /// stay put and swerve there at the last moment. nil means no way was found.
    private func plan(_ rows: [Row], depth: Int, from lane: Int, freeAt: Double, speed: Double,
                      hunger: Double, hungerSoon: Double, restless: Double) -> (lane: Int, late: Bool)? {
        guard depth > 0 else { return nil }
        let leftFirst = roll(rows[0].id, 6) < 0.5

        func best(_ j: Int, _ lane: Int, _ freeAt: Double, _ usedLate: Bool) -> Move {
            // past the rows it looks at, the middle lane keeps the most choices open
            if j >= depth { return (lane == 1 ? 0 : -0.1, lane, false) }
            let row = rows[j]
            let seconds = (row.at - Self.hitFront - freeAt) / speed
            let reach = seconds >= 0.62 ? 2 : (seconds >= 0.14 ? 1 : 0)     // lane changes a person fits in
            var top: Move = (-Double.infinity, lane, false)

            // what follows if it goes through this row in lane l
            func after(_ l: Int, _ late: Bool) -> Double {
                let fliesOverHurdle = row.ramp == l && j + 1 < rows.count && rows[j + 1].isHurdle && rows[j + 1].id == row.id
                if fliesOverHurdle { return best(j + 2, l, row.steerAgainAt, late).score }
                return best(j + 1, l, row.at + 0.12, late).score
            }

            // its own lane first, then the ones beside it
            let order: [Int]
            switch lane {
            case 0: order = [0, 1, 2]
            case 2: order = [2, 1, 0]
            default: order = leftFirst ? [1, 0, 2] : [1, 2, 0]
            }
            let appetite = j == 0 ? hunger : 0.5 * hungerSoon
            for l in order where !row.shut[l] {
                let moves = abs(l - lane)
                if moves <= reach {
                    let forRamp: Double = row.ramp == l ? 12 : 0
                    let forMoving = j == 0 && moves > 0 ? restless : 0
                    let score = row.gems[l] - 0.2 * Double(moves) + forRamp + forMoving + after(l, usedLate)
                    if score > top.score { top = (score, l, false) }
                }
                let canWait = moves == 1 && !usedLate && appetite > 0 && row.shut[lane]
                    && row.ramp < 0 && !row.isHurdle && seconds >= 0.3
                if canWait {
                    let score = appetite + row.lateGems[l] - 0.2 + after(l, true)
                    if score > top.score { top = (score, l, true) }
                }
            }
            return top
        }

        let top = best(0, lane, freeAt, false)
        return top.score.isFinite ? (top.lane, top.late) : nil
    }
}

// MARK: - One round

/// Owns the model for one round: steps it with the display, turns touches into input, fires the
/// haptics and reports the result. Nothing here is published; the timeline redraws every frame anyway.
final class LaneDashRound: ObservableObject {
    let model: LaneDashModel
    private var lastFrameAt: Date? = nil
    private var reported = false

    // the finger
    private var down = false
    private var anchorX: CGFloat = 0
    private var swiped = false

    // recordings only: the scripted player, made the first time it is needed
    private let seed: UInt64
    private var bot: LaneDashBot? = nil

    init(options: GameOptions) {
        model = LaneDashModel(options: options)
        seed = options.seed
    }

    /// Called once per frame from the timeline. Returns the model's clock.
    func advance(to date: Date, paused: Bool, link: GameLink) -> Double {
        if paused {
            lastFrameAt = nil
            down = false
            return model.time
        }
        if GameDemo.autopilot {
            if bot == nil { bot = LaneDashBot(seed: seed) }
            bot?.play(model)
        }
        if let last = lastFrameAt {
            var owed = min(date.timeIntervalSince(last), 0.1)
            if owed > 0 {
                // a slow frame is made up in several small steps, so the game keeps real time
                while owed > 1e-6 {
                    let dt = min(owed, 1.0 / 60)
                    model.step(dt: dt)
                    owed -= dt
                }
                lastFrameAt = date
            }
        } else {
            lastFrameAt = date
        }
        buzz()
        if !reported, let result = model.result {
            reported = true
            DispatchQueue.main.async { link.finish(result) }
        }
        return model.time
    }

    /// One haptic per frame at most: the strongest thing that happened.
    private func buzz() {
        let news = model.news
        guard !news.isEmpty else { return }
        model.news = []
        if news.contains(.crash) {
            GameHaptics.heavy()
            GameHaptics.fail()
        } else if !news.isDisjoint(with: [.nearMiss, .overtook, .newBest]) {
            GameHaptics.success()
        } else if !news.isDisjoint(with: [.launch, .landing]) {
            GameHaptics.thud()
        } else if !news.isDisjoint(with: [.laneChange, .gem, .started]) {
            GameHaptics.tap()
        }
    }

    func fingerMoved(from start: CGPoint, to point: CGPoint, paused: Bool) {
        guard !paused else {
            down = false
            return
        }
        if !down {
            down = true
            swiped = false
            anchorX = start.x
            model.start()
        }
        let slid = point.x - anchorX
        if abs(slid) >= 20 {
            model.steer(slid > 0 ? 1 : -1)
            anchorX = point.x               // keep sliding for a second lane
            swiped = true
        }
    }

    /// A touch that never became a swipe is a tap: the outer thirds of the screen steer.
    func fingerLifted(from start: CGPoint, at point: CGPoint, width: CGFloat, paused: Bool) {
        let wasTap = down && !swiped && !paused
        down = false
        guard wasTap, width > 0, hypot(point.x - start.x, point.y - start.y) < 16 else { return }
        if point.x < width / 3 {
            model.steer(-1)
        } else if point.x > width * 2 / 3 {
            model.steer(1)
        }
    }
}

// MARK: - Views

/// The sky and the skyline. They only move with the cosmetic clock, slowly, so this layer redraws
/// twelve times a second and SwiftUI leaves it alone in between.
private struct LaneDashSkyLayer: View, Equatable {
    static let ticksPerSecond = 12.0
    let tick: Int

    var body: some View {
        Canvas(opaque: true, rendersAsynchronously: false) { context, size in
            guard size.width > 8, size.height > 8 else { return }
            var frame = LaneDashFrame()
            frame.clock = CGFloat(Double(tick) / Self.ticksPerSecond / LaneDashModel.clipLoopSeconds)
            LaneDashPainter(size: size, frame: frame, showHUD: false).backdrop(context)
        }
    }
}

/// One frame of the round. time is the model's clock at that frame; passing it in is what makes
/// SwiftUI draw again when the model has moved on.
private struct LaneDashPlayfield: View {
    let model: LaneDashModel
    let time: Double

    var body: some View {
        ZStack {
            LaneDashSkyLayer(tick: Int((time * LaneDashSkyLayer.ticksPerSecond).rounded(.down)))
                .equatable()
            Canvas(opaque: false, rendersAsynchronously: false) { context, size in
                guard size.width > 8, size.height > 8 else { return }
                LaneDashPainter(size: size, frame: model.frame(), showHUD: true).front(context)
            }
        }
    }
}

public struct LaneDashGame: View {
    @ObservedObject private var link: GameLink
    @StateObject private var round: LaneDashRound

    public init(options: GameOptions, link: GameLink) {
        _link = ObservedObject(wrappedValue: link)
        _round = StateObject(wrappedValue: LaneDashRound(options: options))
    }

    public var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation(minimumInterval: nil, paused: link.paused)) { timeline in
                let time = round.advance(to: timeline.date, paused: link.paused, link: link)
                LaneDashPlayfield(model: round.model, time: time)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { drag in
                        round.fingerMoved(from: drag.startLocation, to: drag.location, paused: link.paused)
                    }
                    .onEnded { drag in
                        round.fingerLifted(from: drag.startLocation, at: drag.location,
                                           width: geometry.size.width, paused: link.paused)
                    }
            )
        }
        .background(Color(.sRGB, red: 0.106, green: 0.071, blue: 0.314, opacity: 1))     // the top of the sky
        .ignoresSafeArea()
    }
}
