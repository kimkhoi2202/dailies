import SwiftUI

// Gulp City, the game. Drag to steer a hole round a small city on the water. Whatever fits goes
// down, the hole grows, and bigger things fit.
//
// GulpCityGround   lays out the city of one round.
// GulpCityRound    the rules: holes, the clock, what has gone down, the score. No SwiftUI.
// GulpCityThumb    plays a round by itself for the video feed.
// GulpCityDriver   steps the round on the frame clock, turns drags into steering, fires haptics.
// GulpCityGame     the view the app shows.

// MARK: - The city of a round

/// A small grid of blocks inside a ring road, sized so that clearing it takes about a full round
/// for the number of holes playing.
struct GulpCityGround {
    typealias Spot = (x: Double, y: Double)

    let town: GulpCityTown
    let edge: GulpCityEdge
    let home: Spot
    /// Starting places for the other holes, best first.
    let guests: [Spot]

    /// Blocks across and down for one, two, three and four holes.
    private static let grids: [(cols: Int, rows: Int)] = [(3, 5), (3, 6), (4, 5), (4, 6)]

    init(seed: UInt64, holes: Int) {
        let pitch = GulpCityTown.pitch
        let grid = Self.grids[Swift.min(Swift.max(holes, 1), Self.grids.count) - 1]
        let cols = grid.cols, rows = grid.rows
        var dice = GulpCityDice(seed: seed &* 7919 &+ 17)

        // The player's block is always a park. The rest are dealt from a shuffled deck.
        let others = cols * rows - 1
        var deck: [GulpCityLotUse] = []
        deck += [GulpCityLotUse](repeating: .park, count: Swift.max(2, Int((Double(others) * 0.2).rounded())))
        deck += [GulpCityLotUse](repeating: .plaza, count: Swift.max(2, Int((Double(others) * 0.15).rounded())))
        deck += [GulpCityLotUse](repeating: .tower, count: Swift.max(1, others / 9))
        deck += [GulpCityLotUse](repeating: .midrise, count: Int((Double(others) * 0.28).rounded()))
        deck += [GulpCityLotUse](repeating: .houses, count: Swift.max(0, others - deck.count))
        for top in stride(from: deck.count - 1, to: 0, by: -1) {
            deck.swapAt(top, dice.pick(top + 1))
        }

        let homeI = (cols - 1) / 2, homeJ = (rows - 1) / 2
        var mason = GulpCityMason()
        var lots: [GulpCityLot] = []
        var open: [Spot] = []
        var dealt = 0
        for j in 0..<rows {
            for i in 0..<cols {
                let isHome = i == homeI && j == homeJ
                var lotDice = GulpCityDice(seed: seed &* 31 &+ UInt64(1000 + i * 97 + j * 1013))
                var use = GulpCityLotUse.park
                if !isHome {
                    use = deck[dealt]
                    dealt += 1
                }
                var lot = GulpCityLot(cx: Double(i) * pitch, cy: Double(j) * pitch, use: use,
                                      style: lotDice.pick(4), pond: lotDice.pick(4))
                if isHome {
                    lot.style = 0
                    lot.pond = 1
                }
                lots.append(lot)
                mason.furnish(lot, &lotDice, showcase: isHome)
                // Parks and plazas have room for a hole to start in. A plaza's fountain is in the
                // middle, so the hole starts beside it.
                if !isHome && (use == .park || use == .plaza) {
                    open.append((lot.cx - 0.3, lot.cy + (use == .plaza ? 1.55 : -0.3)))
                }
            }
        }

        // traffic on every street, the ring road included: the east-west streets, then the north-south ones
        for j in -1..<rows {
            for i in 0..<cols {
                let street = (Double(j) + 0.5) * pitch
                for n in 0..<2 {
                    mason.lane(alongX: true, mid: Double(i) * pitch, fixed: street + (n == 0 ? -0.57 : 0.57), turns: n == 0 ? 2 : 0,
                               &dice, empty: 0.3, bus: 0.44, single: 0.8, gap: (0.95, 0.95))
                }
            }
        }
        for j in 0..<rows {
            for i in -1..<cols {
                let street = (Double(i) + 0.5) * pitch
                for n in 0..<2 {
                    mason.lane(alongX: false, mid: Double(j) * pitch, fixed: street + (n == 0 ? -0.57 : 0.57), turns: n == 0 ? 1 : 3,
                               &dice, empty: 0.34, bus: 0.46, single: 0.82, gap: (0.95, 0.95))
                }
            }
        }
        mason.stampSeeds()
        // What fits when: ordinary buildings at size 6, long ones and towers at size 7.
        for k in mason.props.indices where mason.props[k].kind == .building {
            mason.props[k].needs = Swift.max(mason.props[k].halfW, mason.props[k].halfD) > 1.2 ? 2.7 : 2.3
        }

        // The other holes take the open blocks farthest from the player and from each other.
        let start: Spot = (Double(homeI) * pitch - 0.3, Double(homeJ) * pitch - 0.3)
        var taken: [Spot] = [start]
        var guests: [Spot] = []
        while !open.isEmpty {
            var pick = 0
            var widest = -1.0
            for (k, spot) in open.enumerated() {
                var nearest = Double.infinity
                for t in taken {
                    nearest = Swift.min(nearest, (spot.x - t.x) * (spot.x - t.x) + (spot.y - t.y) * (spot.y - t.y))
                }
                if nearest > widest {
                    widest = nearest
                    pick = k
                }
            }
            let spot = open.remove(at: pick)
            taken.append(spot)
            guests.append(spot)
        }

        let margin = pitch / 2 + GulpCityTown.roadWidth / 2 + 0.45
        town = GulpCityTown(lots: lots, props: mason.props)
        edge = GulpCityEdge(west: -margin, east: Double(cols - 1) * pitch + margin,
                            north: -margin, south: Double(rows - 1) * pitch + margin, cols: cols, rows: rows)
        home = start
        self.guests = guests
    }
}

// MARK: - The round

final class GulpCityRound {
    /// The canvas draws off the main thread (several times faster for this much city), so whoever
    /// steps the round or draws from it holds this lock.
    let lock = NSLock()

    enum Stage { case waiting, live, closing, over }
    enum Ending { case clock, emptied }
    /// Things the driver answers with a haptic.
    enum Beat { case bite(Int), sizeUp, countdown, timeUp, emptied }

    struct Hole {
        var name: String
        var x: Double
        var y: Double
        var vx = 0.0
        var vy = 0.0
        /// Radius as drawn. It springs to the radius of the hole's size after a size up.
        var r: Double
        var grewFrom: Double
        var sinceGrowth = 1.0
        /// 1...sizes.count
        var size = 1
        var swallowed = 0
        // the played friends only
        var quarry = -1
        var rethink = 0.0
        var pace = 1.0
        var roamX = 0.0
        var roamY = 0.0
    }

    struct Gain {
        var x: Double
        var y: Double
        var worth: Int
        var born: Double
        var nudge: Double
    }

    struct Shout {
        var words: String
        var big: Bool
        var worth: Int
        var tall: Double
        var born: Double
        var seed: UInt64
    }

    struct Ripple {
        var hole: Int
        var born: Double
        var wide: Bool
    }

    static let roundSeconds = 75.0
    static let closingSeconds = 1.2
    /// Radius of a hole at each size.
    static let sizes: [Double] = [0.85, 1.1, 1.35, 1.7, 2.0, 2.35, 2.75, 3.15, 3.6]
    /// Worth a hole must have swallowed to reach each size. Everything fits at size 7, and sizes 6 and
    /// 7 are cheap enough that the leading hole always gets there, so a round cannot stall.
    static let ladder: [Int] = [0, 24, 80, 190, 360, 620, 960, 1400, 1950]
    /// Seconds of fall per unit of the clip's fall length.
    static let sinkScale = 6.2
    static let gainLife = 0.6
    static let shoutLife = 0.75
    static let rippleLife = 0.24
    /// The friends are a little slower than the player, and scatterbrained.
    static let friendPace: [Double] = [0.88, 0.78, 0.68]
    static let friendWhim = 0.8

    /// Ground units a second. Bigger holes are a little quicker, and the camera pulls back to match.
    static func speed(_ r: Double) -> Double { 3.0 + 0.62 * r }

    let town: GulpCityTown
    let edge: GulpCityEdge
    let alone: Bool
    let totalWorth: Int

    private(set) var stage = Stage.waiting
    private(set) var ending = Ending.clock
    /// Seconds played. Stops when the round ends.
    private(set) var played = 0.0
    /// Runs whenever the game is not paused. Every animation reads it.
    private(set) var now = 0.0
    private(set) var beganAt = -1.0
    private(set) var closing = 0.0

    private(set) var holes: [Hole] = []
    /// Per prop: 0 standing, 1 on its way down, 2 gone.
    private(set) var fate: [UInt8]
    private(set) var fellAt: [Double]
    private(set) var fellInto: [UInt8]
    private var sinking: [Int] = []
    private var standing: Int

    private(set) var eyeX: Double
    private(set) var eyeY: Double
    private(set) var span = 8.4

    private(set) var gains: [Gain] = []
    private(set) var ripples: [Ripple] = []
    private(set) var shout: Shout? = nil
    private var bestRank = 0
    private var bestName = ""
    private var beats: [Beat] = []

    private var pushX = 0.0
    private var pushY = 0.0
    private var secondShown = Int.max
    private var dice: GulpCityDice

    init(solo: Bool, playerName: String, friendNames: [String], seed: UInt64) {
        let wanted = solo ? 0 : Swift.min(3, friendNames.count)
        let ground = GulpCityGround(seed: seed, holes: 1 + wanted)
        town = ground.town
        edge = ground.edge
        dice = GulpCityDice(seed: seed &* 104729 &+ 5)
        let count = ground.town.props.count
        fate = [UInt8](repeating: 0, count: count)
        fellAt = [Double](repeating: 0, count: count)
        fellInto = [UInt8](repeating: 0, count: count)
        standing = count
        totalWorth = Swift.max(1, ground.town.props.reduce(0) { $0 + $1.worth })
        sinking.reserveCapacity(64)
        gains.reserveCapacity(12)
        ripples.reserveCapacity(10)
        beats.reserveCapacity(16)

        let r = Self.sizes[0]
        holes.append(Hole(name: playerName, x: ground.home.x, y: ground.home.y, r: r, grewFrom: r))
        let friends = friendNames.prefix(Swift.min(wanted, ground.guests.count))
        alone = friends.isEmpty
        for (k, name) in friends.enumerated() {
            let at = ground.guests[k]
            var hole = Hole(name: name, x: at.x, y: at.y, r: r, grewFrom: r)
            hole.pace = Self.friendPace[k % 3] + dice.roll(-0.03, 0.03)
            hole.rethink = dice.roll(0.1, 0.5)
            hole.roamX = at.x
            hole.roamY = at.y
            holes.append(hole)
        }
        eyeX = ground.home.x
        eyeY = ground.home.y
    }

    // MARK: Reading the round

    var player: Hole { holes[0] }
    var secondsLeft: Int { Int(Swift.max(0, Self.roundSeconds - played).rounded(.up)) }
    var atTopSize: Bool { holes[0].size >= Self.sizes.count }

    /// Radius of the size a hole has reached (what it can swallow), not the radius as drawn.
    func grip(_ hole: Hole) -> Double { Self.sizes[hole.size - 1] }

    /// Share of the city a hole has swallowed, 0...100. 100 only for all of it.
    func share(_ k: Int) -> Int {
        let got = holes[k].swallowed
        return got >= totalWorth ? 100 : Swift.min(99, got * 100 / totalWorth)
    }

    /// The player's way to the next size, 0...1.
    var sizeProgress: Double {
        let hole = holes[0]
        if hole.size >= Self.sizes.count { return 1 }
        let from = Self.ladder[hole.size - 1], to = Self.ladder[hole.size]
        return GulpCityCurve.clamp(Double(hole.swallowed - from) / Double(to - from))
    }

    /// Props pop up out of the ground as the game appears.
    var rise: Double { 0.62 + 0.38 * GulpCityCurve.spring(now / 0.4) }

    /// "Drag to move" fades in while the round waits and out once it starts.
    var hint: Double {
        if stage == .waiting { return Swift.min(1, now / 0.3) }
        return Swift.max(0, 1 - (now - beganAt) / 0.25)
    }

    var placement: Int {
        1 + holes.dropFirst().filter { $0.swallowed > holes[0].swallowed }.count
    }

    /// One gold for every tenth of the city the player swallows.
    var gold: Int { share(0) / 10 }

    var result: GameResult {
        let percent = share(0)
        return GameResult(score: percent, unit: "of the city", scoreText: "\(percent)%",
                          detail: bestRank > 0 ? "Biggest bite: \(bestName)" : "Nothing swallowed",
                          placement: alone ? nil : placement, playerCount: alone ? nil : holes.count)
    }

    func sinkTime(_ prop: GulpCityProp) -> Double { prop.sink * Self.sinkScale }

    func takeBeats() -> [Beat] {
        if beats.isEmpty { return [] }
        let out = beats
        beats.removeAll(keepingCapacity: true)
        return out
    }

    // MARK: Input

    /// The first touch starts the round.
    func begin() {
        guard stage == .waiting else { return }
        stage = .live
        beganAt = now
    }

    /// A drag vector on screen (x right, y down). Its length, up to 1, is how hard the player pushes.
    func steer(dx: Double, dy: Double) {
        let length = (dx * dx + dy * dy).squareRoot()
        pushX = length > 1 ? dx / length : dx
        pushY = length > 1 ? dy / length : dy
    }

    func letGo() {
        pushX = 0
        pushY = 0
    }

    // MARK: Stepping

    func step(_ dt: Double) {
        guard dt > 0, stage != .over else { return }
        now += dt
        switch stage {
        case .waiting, .over:
            break
        case .live:
            played += dt
            drivePlayer(dt)
            for k in holes.indices.dropFirst() { driveFriend(k, dt) }
            makeRoom()
            catchProps()
            landProps(counting: true)
            let seconds = secondsLeft
            if seconds != secondShown {
                if (1...3).contains(seconds) && secondShown != Int.max { beats.append(.countdown) }
                secondShown = seconds
            }
            if standing == 0 {
                close(.emptied)
            } else if played >= Self.roundSeconds {
                close(.clock)
            }
        case .closing:
            makeRoom()      // a hole that grew on the last bite still pushes the others back
            landProps(counting: false)
            closing += dt
            if closing >= Self.closingSeconds { stage = .over }
        }
        for k in holes.indices {
            holes[k].sinceGrowth += dt
            let goal = Self.sizes[holes[k].size - 1]
            holes[k].r = holes[k].grewFrom + (goal - holes[k].grewFrom) * GulpCityCurve.spring(holes[k].sinceGrowth / 0.38)
        }
        follow(dt)
        while let first = gains.first, now - first.born > Self.gainLife { gains.removeFirst() }
        while let first = ripples.first, now - first.born > Self.rippleLife * 1.6 { ripples.removeFirst() }
        if let s = shout, now - s.born > Self.shoutLife { shout = nil }
    }

    private func close(_ why: Ending) {
        // whatever is already tipping in still counts
        for i in sinking { count(i) }
        letGo()
        ending = why
        stage = .closing
        closing = 0
        beats.append(why == .emptied ? .emptied : .timeUp)
    }

    private func drivePlayer(_ dt: Double) {
        var hole = holes[0]
        // undo the camera's squash and turn: screen drag -> direction on the ground
        let sx = pushX, sy = pushY / GulpCityLens.squash
        var gx = sx * GulpCityLens.cosTurn + sy * GulpCityLens.sinTurn
        var gy = -sx * GulpCityLens.sinTurn + sy * GulpCityLens.cosTurn
        let length = (gx * gx + gy * gy).squareRoot()
        let push = Swift.min(1, (pushX * pushX + pushY * pushY).squareRoot())
        if length > 1e-6 {
            gx *= push / length
            gy *= push / length
        } else {
            gx = 0
            gy = 0
        }
        let top = Self.speed(hole.r)
        // quick to answer the thumb, quicker still to stop
        let ease = 1 - exp(-dt * (push > 0.01 ? 13 : 18))
        hole.vx += (gx * top - hole.vx) * ease
        hole.vy += (gy * top - hole.vy) * ease
        hole.x += hole.vx * dt
        hole.y += hole.vy * dt
        holes[0] = kept(hole)
    }

    private func driveFriend(_ k: Int, _ dt: Double) {
        var hole = holes[k]
        hole.rethink -= dt
        let beaten = hole.quarry >= 0 && fate[hole.quarry] != 0
        if hole.rethink <= 0 || beaten {
            hole.quarry = bestBite(for: hole, whim: Self.friendWhim)
            hole.rethink = beaten ? dice.roll(0.15, 0.4) : dice.roll(0.5, 0.9)
            if hole.quarry < 0 {
                // nothing fits: wander
                let dx = hole.roamX - hole.x, dy = hole.roamY - hole.y
                if dx * dx + dy * dy < 1 || dice.roll() < 0.1 {
                    hole.roamX = dice.roll(edge.west + 3, edge.east - 3)
                    hole.roamY = dice.roll(edge.north + 3, edge.south - 3)
                }
            }
        }
        var dx = hole.roamX - hole.x, dy = hole.roamY - hole.y
        if hole.quarry >= 0 {
            dx = town.props[hole.quarry].x - hole.x
            dy = town.props[hole.quarry].y - hole.y
        }
        let away = (dx * dx + dy * dy).squareRoot()
        var want = 0.0
        if away > 0.05 {
            dx /= away
            dy /= away
            // slows as it arrives
            want = Self.speed(hole.r) * hole.pace * Swift.min(1, away / 0.4 + 0.25)
        }
        let ease = 1 - exp(-dt * 5.5)
        hole.vx += (dx * want - hole.vx) * ease
        hole.vy += (dy * want - hole.vy) * ease
        hole.x += hole.vx * dt
        hole.y += hole.vy * dt
        holes[k] = kept(hole)
    }

    /// The thing most worth going for: valuable and close. -1 when nothing fits.
    private func bestBite(for hole: Hole, whim: Double) -> Int {
        let fits = grip(hole) + 1e-6
        let props = town.props
        var best = -1
        var bestScore = 0.0
        for i in props.indices where fate[i] == 0 {
            let prop = props[i]
            if prop.needs > fits { continue }
            let dx = prop.x - hole.x, dy = prop.y - hole.y
            let away = (dx * dx + dy * dy).squareRoot()
            var score = (Double(prop.worth) + 1.5) / (away + 1.0 + 0.06 * away * away)
            if whim > 0 { score *= 1 - whim / 2 + whim * dice.roll() }
            if score > bestScore {
                bestScore = score
                best = i
            }
        }
        return best
    }

    private func kept(_ hole: Hole) -> Hole {
        var out = hole
        let margin = hole.r + 0.08
        out.x = Swift.min(Swift.max(out.x, edge.west + margin), edge.east - margin)
        out.y = Swift.min(Swift.max(out.y, edge.north + margin), edge.south - margin)
        return out
    }

    /// Holes never swallow each other. They push apart. The player shoves the others aside, and is
    /// only held back by one that is cornered.
    private func makeRoom() {
        guard holes.count > 1 else { return }
        for _ in 0..<2 {
            for a in 0..<(holes.count - 1) {
                for b in (a + 1)..<holes.count {
                    let room = holes[a].r + holes[b].r + 0.12
                    let dx = holes[b].x - holes[a].x, dy = holes[b].y - holes[a].y
                    let apart = (dx * dx + dy * dy).squareRoot()
                    if apart >= room { continue }
                    if a != 0 {
                        // two friends each give way by half
                        let back = (room - apart) * 0.5
                        let ux = apart > 1e-4 ? dx / apart : 1, uy = apart > 1e-4 ? dy / apart : 0
                        holes[a].x -= ux * back
                        holes[a].y -= uy * back
                        holes[a] = kept(holes[a])
                    }
                    pushOut(b, from: holes[a].x, holes[a].y, room)
                    // b had its back to the edge: a gives way instead
                    pushOut(a, from: holes[b].x, holes[b].y, room)
                }
            }
        }
    }

    /// Moves hole k out to "room" from a point. Against the edge of the city it slides along the edge.
    private func pushOut(_ k: Int, from px: Double, _ py: Double, _ room: Double) {
        var dx = holes[k].x - px, dy = holes[k].y - py
        var apart = (dx * dx + dy * dy).squareRoot()
        if apart >= room { return }
        if apart < 1e-4 {
            dx = 1
            dy = 0
            apart = 1
        }
        var hole = holes[k]
        let wantX = px + dx / apart * room, wantY = py + dy / apart * room
        hole.x = wantX
        hole.y = wantY
        hole = kept(hole)
        if abs(hole.x - wantX) > 1e-6 {
            let side = hole.x - px
            let rest = room * room - side * side
            if rest > 0 { hole.y = py + (hole.y >= py ? 1 : -1) * rest.squareRoot() }
            hole = kept(hole)
        } else if abs(hole.y - wantY) > 1e-6 {
            let side = hole.y - py
            let rest = room * room - side * side
            if rest > 0 { hole.x = px + (hole.x >= px ? 1 : -1) * rest.squareRoot() }
            hole = kept(hole)
        }
        holes[k] = hole
    }

    /// Anything that fits and is over a hole starts to tip in.
    private func catchProps() {
        let props = town.props
        // per hole: x, y, what it can take, reach squared
        var mouths: [(x: Double, y: Double, fits: Double, reach2: Double)] = []
        mouths.reserveCapacity(holes.count)
        for hole in holes {
            let reach = hole.r * 0.9
            mouths.append((hole.x, hole.y, grip(hole) + 1e-6, reach * reach))
        }
        for i in props.indices where fate[i] == 0 {
            let prop = props[i]
            for (k, mouth) in mouths.enumerated() {
                if prop.needs > mouth.fits { continue }
                let dx = prop.x - mouth.x, dy = prop.y - mouth.y
                if dx * dx + dy * dy > mouth.reach2 { continue }
                fate[i] = 1
                fellAt[i] = now
                fellInto[i] = UInt8(k)
                sinking.append(i)
                if k == 0 { announce(prop) }
                break
            }
        }
    }

    private func landProps(counting: Bool) {
        var k = 0
        while k < sinking.count {
            let i = sinking[k]
            if now - fellAt[i] < sinkTime(town.props[i]) {
                k += 1
                continue
            }
            if counting { count(i) }
            fate[i] = 2
            sinking.swapAt(k, sinking.count - 1)
            sinking.removeLast()
        }
    }

    /// A prop is down: it counts for the hole it fell into.
    private func count(_ i: Int) {
        standing -= 1
        let prop = town.props[i]
        let k = Int(fellInto[i])
        holes[k].swallowed += prop.worth
        if prop.worth >= 4 && ripples.count < 10 { ripples.append(Ripple(hole: k, born: now, wide: false)) }
        if k == 0 {
            beats.append(.bite(prop.worth))
            let rank = Self.rank(prop)
            if rank > bestRank {
                bestRank = rank
                bestName = Self.name(prop)
            }
            // the numbers get pickier as the hole grows
            let least = holes[0].size < 3 ? 2 : (holes[0].size < 5 ? 4 : 8)
            if prop.worth >= least {
                if gains.count >= 10 { gains.removeFirst() }
                let hole = holes[0]
                gains.append(Gain(x: prop.x + (hole.x - prop.x) * 0.55, y: prop.y + (hole.y - prop.y) * 0.55,
                                  worth: prop.worth, born: now, nudge: Double(Int(prop.seed % 7) - 3)))
            }
        }
        while holes[k].size < Self.sizes.count && holes[k].swallowed >= Self.ladder[holes[k].size] {
            holes[k].size += 1
            holes[k].grewFrom = holes[k].r
            holes[k].sinceGrowth = 0
            if ripples.count < 10 { ripples.append(Ripple(hole: k, born: now, wide: true)) }
            if k == 0 {
                beats.append(.sizeUp)
                shout = Shout(words: "SIZE UP", big: false, worth: 1000, tall: 0, born: now, seed: 1)
            }
        }
    }

    private func announce(_ prop: GulpCityProp) {
        guard let words = GulpCityArtist.shout(for: prop) else { return }
        // a fresh shout about something bigger stays up
        if let s = shout, now - s.born < 0.4, s.worth > prop.worth { return }
        shout = Shout(words: words, big: prop.worth >= 40, worth: prop.worth, tall: prop.tall, born: now, seed: prop.seed)
    }

    private func follow(_ dt: Double) {
        let hole = holes[0]
        let ease = 1 - exp(-dt * 9)
        eyeX += (hole.x - eyeX) * ease
        eyeY += (hole.y - eyeY) * ease
        // pull back as the hole grows, like the clip, and further for the two biggest sizes
        let goal = grip(hole)
        let want = 8.4 + 6.6 * GulpCityCurve.ramp(0.85, 3.2, goal) + Swift.max(0, goal - 3.2) * 4
        span += (want - span) * (1 - exp(-dt * 2.6))
    }

    // MARK: Words

    /// Which bite counts as the biggest of the round.
    private static func rank(_ prop: GulpCityProp) -> Int {
        switch prop.kind {
        case .person: return 1
        case .cone: return 2
        case .bin: return 3
        case .flowers: return 4
        case .bush: return 5
        case .lamp: return 6
        case .bench: return 7
        case .parasol: return 8
        case .tree: return 9
        case .car: return 10
        case .kiosk: return 11
        case .bus: return 12
        case .house: return 13
        case .fountain: return 14
        case .building: return Swift.max(prop.halfW, prop.halfD) > 1.2 ? 16 : 15
        }
    }

    private static func name(_ prop: GulpCityProp) -> String {
        switch prop.kind {
        case .person: return "a bystander"
        case .cone: return "a traffic cone"
        case .bin: return "a bin"
        case .flowers: return "a flower bed"
        case .bush: return "a bush"
        case .lamp: return "a street lamp"
        case .bench: return "a bench"
        case .parasol: return "a parasol"
        case .tree: return "a tree"
        case .car: return "a car"
        case .kiosk: return "a snack stand"
        case .bus: return "a bus"
        case .house: return "a house"
        case .fountain: return "a fountain"
        case .building: return prop.isTower ? "a tower" : "a building"
        }
    }
}

// MARK: - Drawing a frame

extension GulpCityArtist {
    /// One frame of the game.
    func drawRound(_ ctx: inout GraphicsContext, _ round: GulpCityRound) {
        drawGround(&ctx)
        let poses = poses(of: round)
        drawShadows(&ctx, poses)
        let turn = round.now * 2 * Double.pi * 0.42
        let inView = round.holes.map { visible($0) }
        for (k, hole) in round.holes.enumerated() where inView[k] {
            drawWhirl(&ctx, hole.x, hole.y, hole.r, turn: turn * 1.3)
            drawHole(&ctx, hole.x, hole.y, hole.r, turn: turn)
        }
        drawCracks(&ctx, poses)
        drawProps(&ctx, poses)
        drawDebris(&ctx, poses)
        for ripple in round.ripples where inView[ripple.hole] {
            let hole = round.holes[ripple.hole]
            let age = (round.now - ripple.born) / (GulpCityRound.rippleLife * (ripple.wide ? 1.6 : 1))
            if age < 0 || age > 1 { continue }
            drawRipple(&ctx, hole.x, hole.y, hole.r * (ripple.wide ? 1.0 + 0.5 * age : 1), age: age)
        }
        drawHaze(&ctx)
        if round.holes.count > 1 {
            for (k, hole) in round.holes.enumerated() where inView[k] { drawName(&ctx, hole, k) }
        }
        for gain in round.gains {
            let age = (round.now - gain.born) / GulpCityRound.gainLife
            if age < 0 || age > 1 { continue }
            let base = spot(gain.x, gain.y, 0.5)
            drawGain(&ctx, gain.worth, at: CGPoint(x: Double(base.x) + gain.nudge * 7 * u, y: Double(base.y)), age: age)
        }
        let player = round.player
        let centre = spot(player.x, player.y)
        let rimY = player.r * s * Lens.squash
        if let shout = round.shout {
            let age = (round.now - shout.born) / GulpCityRound.shoutLife
            if age >= 0 && age <= 1 {
                // a tall building lifts the words clear of its roof
                let top = Double(centre.y) - rimY - (shout.big ? Swift.max(0, shout.tall - 1.6) * Lens.lift * s : 0)
                drawShout(&ctx, shout.words, big: shout.big,
                          x: Curve.clamp(Double(centre.x) + (shout.big ? 14 : 0) * u, 92 * u, W - 92 * u),
                          top: top, lift: round.holes.count > 1 ? 16 : 0, age: age, seed: shout.seed)
            }
        }
        let seconds = round.secondsLeft
        drawHUD(&ctx, score: "\(round.share(0))%", seconds: seconds, urgent: seconds <= 10,
                size: player.size, progress: round.sizeProgress, showNext: !round.atTopSize)
        let hint = round.hint
        if hint > 0.01 {
            let bob = sin(round.now * 3.2) * 3 * u
            caption(&ctx, "Drag to move", at: CGPoint(x: W * 0.5, y: Double(centre.y) + rimY + 54 * u + bob),
                    size: 24 * u, fill: .white, rim: Tone.ink, rimWidth: Swift.max(1, 2.4 * u), drop: 3 * u, alpha: hint)
        }
        if round.stage == .closing || round.stage == .over {
            drawBanner(&ctx, round.ending == .emptied ? "ALL GONE" : "TIME UP", shown: Curve.ramp(0, 0.3, round.closing))
        }
    }

    private func visible(_ hole: GulpCityRound.Hole) -> Bool {
        let c = spot(hole.x, hole.y)
        let reach = hole.r * s * 1.7
        return Double(c.x) + reach > 0 && Double(c.x) - reach < W && Double(c.y) + reach > 0 && Double(c.y) - reach < H
    }

    /// Every prop still in the city that is on screen, standing, leaning or falling.
    private func poses(of round: GulpCityRound) -> [Pose] {
        var out: [Pose] = []
        out.reserveCapacity(320)
        let props = town.props
        let holes = round.holes
        let seen = lens.seen
        // per hole: what it can take, where a prop is taken, where one starts to lean
        var pulls: [(fits: Double, near: Double, far: Double)] = []
        pulls.reserveCapacity(holes.count)
        for hole in holes {
            pulls.append((round.grip(hole) + 1e-6, hole.r * 0.9, hole.r * 1.3 + 0.2))
        }
        for k in props.indices {
            let fate = round.fate[k]
            if fate == 2 { continue }
            let prop = props[k]
            // tall props south of the frame still reach up into it
            if prop.x < seen.x0 - 2 || prop.x > seen.x1 + 2 || prop.y < seen.y0 - 2 || prop.y > seen.y1 + 7 { continue }
            if fate == 1 {
                let hole = holes[Int(round.fellInto[k])]
                let fall = (round.now - round.fellAt[k]) / round.sinkTime(prop)
                if fall >= 1 { continue }
                if let pose = pose(k, prop, fall: Swift.max(0, fall), nudge: 0, holeX: hole.x, holeY: hole.y, holeR: hole.r) {
                    out.append(pose)
                }
                continue
            }
            // a prop that fits leans towards a hole that comes close
            var nudge = 0.0
            var toward = 0
            for (h, hole) in holes.enumerated() where prop.needs <= pulls[h].fits {
                let dx = prop.x - hole.x, dy = prop.y - hole.y
                let d2 = dx * dx + dy * dy
                if d2 >= pulls[h].far * pulls[h].far { continue }
                let pull = 1 - Curve.ramp(pulls[h].near, pulls[h].far, d2.squareRoot())
                if pull > nudge {
                    nudge = pull
                    toward = h
                }
            }
            let hole = holes[toward]
            if let pose = pose(k, prop, fall: -1, nudge: nudge, holeX: hole.x, holeY: hole.y, holeR: hole.r) {
                out.append(pose)
            }
        }
        return out
    }

    /// A name over a hole, when friends are playing.
    private func drawName(_ ctx: inout GraphicsContext, _ hole: GulpCityRound.Hole, _ k: Int) {
        let fills: [Hue] = [.white, Tone.sun, Hue(0xFFB3D1), Hue(0x9CEBDD)]
        let c = spot(hole.x, hole.y)
        let x = Double(c.x), y = Double(c.y) - hole.r * s * Lens.squash - 13 * u
        let text = Text(hole.name).font(.system(size: 14 * u, weight: .heavy, design: .rounded))
        let back = ctx.resolve(text.foregroundColor(Tone.ink.paint()))
        let front = ctx.resolve(text.foregroundColor(fills[k % fills.count].paint()))
        let rim = Swift.max(0.9, 1.8 * u)
        for q in 0..<8 {
            let a = Double(q) / 8 * 2 * Double.pi
            ctx.draw(back, at: CGPoint(x: x + cos(a) * rim, y: y + sin(a) * rim + 0.8 * u), anchor: .center)
        }
        ctx.draw(front, at: CGPoint(x: x, y: y), anchor: .center)
    }
}

/// Draws one frame from the round as it stands.
struct GulpCityBoard: View {
    let round: GulpCityRound
    /// Changes every frame so the canvas draws again.
    let frame: Int

    var body: some View {
        Canvas(opaque: true, colorMode: .nonLinear, rendersAsynchronously: true) { context, size in
            guard size.width > 8, size.height > 8 else { return }
            round.lock.lock()
            defer { round.lock.unlock() }
            let lens = GulpCityLens(size: size, eyeX: round.eyeX, eyeY: round.eyeY, span: Swift.max(1, round.span))
            GulpCityArtist(lens: lens, town: round.town, rise: round.rise, edge: round.edge, art: GulpCityArt(context))
                .drawRound(&context, round)
        }
    }
}

// MARK: - The scripted player

/// Plays a round by itself for the video feed (GameDemo.autopilot). It only reads the round and
/// steers through GulpCityRound.steer, the same input a drag gives.
///
/// Several times a second it looks around. It tries a fan of directions, follows each a couple of
/// seconds ahead the way the hole would really travel, and adds up what would fall in on the way,
/// plus how rich the city is where that path ends. Between looks the thumb swings towards the
/// chosen direction at a limited rate, so the hole draws curves, not corners.
struct GulpCityThumb {
    /// Seconds the "Drag to move" state shows before the round starts by itself.
    static let waitSeconds = 0.8
    /// How far ahead a look follows each direction, seconds.
    private static let foresight = 2.2
    /// Directions tried per look.
    private static let fan = 32
    /// A bite is worth less the longer it takes to reach: halved after this many seconds.
    private static let patience = 1.2
    /// The far view sums the city into squares this wide.
    private static let squareSize = 2.8
    private static let swingGain = 6.5

    private struct Morsel {
        var x: Double
        var y: Double
        var worth: Double
        var square: Int
    }

    /// A hole that will not give way, to keep clear of for a while.
    private struct Block {
        var x = 0.0
        var y = 0.0
        var r = 0.0
        var until = -1.0
    }

    private var dice: GulpCityDice
    /// Direction on the ground the thumb is pushing, radians.
    private var heading = 0.0
    /// Direction the last look chose.
    private var aim = 0.0
    private var swing = 0.0
    private var push = 0.0
    private var untilLook = 0.0
    private var sizeSeen = 0
    private var hasAim = false
    /// Nothing left that fits.
    private var resting = false
    private var clock = 0.0
    private let wobble: (slow: Double, fast: Double)
    private var lastX = 0.0
    private var lastY = 0.0
    private var held = 0.0
    private var block = Block()

    private var morsels: [Morsel] = []
    /// Per morsel: the number of the path that last took it.
    private var takenBy: [Int] = []
    private var path = 0
    private let across: Int
    private let down: Int
    private var squareWorth: [Double]
    private var squareX: [Double]
    private var squareY: [Double]
    private var squareTaken: [Double]

    init(round: GulpCityRound, seed: UInt64) {
        dice = GulpCityDice(seed: seed &* 2971 &+ 77)
        let slow = dice.roll(0, 6.28)
        wobble = (slow, dice.roll(0, 6.28))
        across = Swift.max(1, Int(((round.edge.east - round.edge.west) / Self.squareSize).rounded(.up)))
        down = Swift.max(1, Int(((round.edge.south - round.edge.north) / Self.squareSize).rounded(.up)))
        squareWorth = [Double](repeating: 0, count: across * down)
        squareX = squareWorth
        squareY = squareWorth
        squareTaken = squareWorth
        morsels.reserveCapacity(256)
        takenBy.reserveCapacity(256)
    }

    /// An angle brought back into -pi...pi.
    private static func wrapped(_ angle: Double) -> Double {
        var a = angle.truncatingRemainder(dividingBy: 2 * Double.pi)
        if a > Double.pi { a -= 2 * Double.pi }
        if a < -Double.pi { a += 2 * Double.pi }
        return a
    }

    /// A thumb eases off a little while it swings round.
    private static func pushWhileTurning(_ off: Double) -> Double {
        1 - 0.42 * GulpCityCurve.ramp(0.7, 2.4, abs(off))
    }

    /// Fastest swing, radians a second. Bigger holes turn in wider curves.
    private static func swingLimit(_ r: Double) -> Double { Swift.max(2.6, 4.4 - 0.55 * (r - 0.85)) }

    /// One frame of thumb. Call before the round steps.
    mutating func play(_ round: GulpCityRound, _ dt: Double) {
        guard round.stage == .live else { return }
        clock += dt
        untilLook -= dt
        let hole = round.player
        if hasAim { noticeBlock(round, hole, dt) }
        lastX = hole.x
        lastY = hole.y
        if untilLook <= 0 || hole.size != sizeSeen {
            sizeSeen = hole.size
            look(round)
            untilLook = dice.roll(0.11, 0.17)
        }
        let off = Self.wrapped(aim - heading)
        let limit = Self.swingLimit(round.grip(hole))
        let rate = Swift.min(limit, Swift.max(-limit, off * Self.swingGain))
        swing += (rate - swing) * (1 - exp(-dt * 12))
        heading = Self.wrapped(heading + swing * dt)
        let wanted = resting ? 0.0 : Self.pushWhileTurning(off)
        push += (wanted - push) * (1 - exp(-dt * (wanted > push ? 5.5 : 9)))

        // no thumb holds a perfectly straight line
        let a = heading + 0.045 * sin(clock * 2.3 + wobble.slow) + 0.025 * sin(clock * 5.9 + wobble.fast)
        // direction on the ground -> drag on screen: the camera's turn, then its squash
        let gx = cos(a), gy = sin(a)
        let sx = gx * GulpCityLens.cosTurn - gy * GulpCityLens.sinTurn
        let sy = (gx * GulpCityLens.sinTurn + gy * GulpCityLens.cosTurn) * GulpCityLens.squash
        let length = (sx * sx + sy * sy).squareRoot()
        if push < 0.02 || length < 1e-9 {
            round.letGo()
        } else {
            round.steer(dx: sx / length * push, dy: sy / length * push)
        }
    }

    /// A hole with its back to the edge of the city does not give way, and the player is held back.
    /// A person would see they are getting nowhere and go for something else for a while.
    private mutating func noticeBlock(_ round: GulpCityRound, _ hole: GulpCityRound.Hole, _ dt: Double) {
        guard round.holes.count > 1 else { return }
        let moved = ((hole.x - lastX) * (hole.x - lastX) + (hole.y - lastY) * (hole.y - lastY)).squareRoot()
        let meant = (hole.vx * hole.vx + hole.vy * hole.vy).squareRoot() * dt
        if push > 0.6 && moved < 0.3 * meant {
            held += dt
        } else {
            held = Swift.max(0, held - 2 * dt)
        }
        guard held > 0.4 else { return }
        held = 0
        for other in round.holes.dropFirst() {
            let dx = other.x - hole.x, dy = other.y - hole.y
            let touching = hole.r + other.r + 0.12
            if dx * dx + dy * dy > (touching + 0.1) * (touching + 0.1) { continue }
            block = Block(x: other.x, y: other.y, r: touching + 0.5, until: clock + 8)
            untilLook = 0
            return
        }
    }

    /// Chooses the direction to head in.
    private mutating func look(_ round: GulpCityRound) {
        let hole = round.player
        let edge = round.edge
        let grip = round.grip(hole)
        // aim to pass well over things, not to clip them
        let reach = grip * 0.9 * 0.86
        let reach2 = reach * reach
        let speed = GulpCityRound.speed(grip)
        let horizon = speed * Self.foresight + reach

        // What fits right now: one by one close by, summed by square for the far view.
        for q in squareWorth.indices {
            squareWorth[q] = 0
            squareX[q] = 0
            squareY[q] = 0
        }
        morsels.removeAll(keepingCapacity: true)
        let props = round.town.props
        let fate = round.fate
        let dodging = clock < block.until
        var anything = false
        for i in props.indices where fate[i] == 0 {
            let prop = props[i]
            if prop.needs > grip + 1e-6 { continue }
            anything = true
            if dodging {
                let bx = prop.x - block.x, by = prop.y - block.y
                if bx * bx + by * by < block.r * block.r { continue }
            }
            let worth = Double(prop.worth)
            let col = Swift.min(across - 1, Swift.max(0, Int((prop.x - edge.west) / Self.squareSize)))
            let row = Swift.min(down - 1, Swift.max(0, Int((prop.y - edge.north) / Self.squareSize)))
            let square = row * across + col
            squareWorth[square] += worth
            squareX[square] += worth * prop.x
            squareY[square] += worth * prop.y
            let dx = prop.x - hole.x, dy = prop.y - hole.y
            if dx * dx + dy * dy < horizon * horizon {
                morsels.append(Morsel(x: prop.x, y: prop.y, worth: worth, square: square))
            }
        }
        resting = !anything
        if resting {
            // the others took what was left: drift back to the middle of the city and wait there
            let dx = (edge.west + edge.east) / 2 - hole.x, dy = (edge.north + edge.south) / 2 - hole.y
            if dx * dx + dy * dy > 4 {
                aim = atan2(dy, dx)
                resting = false
            }
            settleFirstAim()
            return
        }
        for q in squareWorth.indices where squareWorth[q] > 0 {
            squareX[q] /= squareWorth[q]
            squareY[q] /= squareWorth[q]
        }
        if takenBy.count < morsels.count {
            takenBy += [Int](repeating: 0, count: morsels.count - takenBy.count)
        }

        let limit = Self.swingLimit(grip)
        let stride = Swift.min(0.1, Swift.max(0.04, reach * 0.3 / speed))
        let strides = Swift.max(1, Int(Self.foresight / stride))
        let margin = grip + 0.08
        let west = edge.west + margin, east = edge.east - margin
        let north = edge.north + margin, south = edge.south - margin
        var bestScore = -1.0
        var bestAim = aim
        for k in 0..<Self.fan {
            let toward = aim + Double(k) * 2 * Double.pi / Double(Self.fan)
            var x = hole.x, y = hole.y
            var facing = hasAim ? heading : toward
            var haul = 0.0
            path += 1
            for q in squareTaken.indices { squareTaken[q] = 0 }
            for n in 1...strides {
                let off = Self.wrapped(toward - facing)
                facing += Swift.min(limit, Swift.max(-limit, off * Self.swingGain)) * stride
                let go = speed * Self.pushWhileTurning(off) * stride
                x = Swift.min(east, Swift.max(west, x + cos(facing) * go))
                y = Swift.min(south, Swift.max(north, y + sin(facing) * go))
                let fresh = 1 / (1 + Double(n) * stride / Self.patience)
                for j in morsels.indices where takenBy[j] != path {
                    let dx = morsels[j].x - x, dy = morsels[j].y - y
                    if dx * dx + dy * dy < reach2 {
                        takenBy[j] = path
                        haul += morsels[j].worth * fresh
                        squareTaken[morsels[j].square] += morsels[j].worth
                    }
                }
            }
            // where this path ends: how soon is the next good patch
            var after = 0.0
            for q in squareWorth.indices {
                let left = squareWorth[q] - squareTaken[q]
                if left < 0.5 { continue }
                let dx = squareX[q] - x, dy = squareY[q] - y
                let gap = Swift.max(0, (dx * dx + dy * dy).squareRoot() - reach)
                after = Swift.max(after, left / (1 + (Self.foresight + gap / speed) / Self.patience))
            }
            var score = haul + 0.6 * after
            if hasAim {
                // keep to the present line unless another is clearly better
                score *= 1 + 0.15 * Swift.max(0, 1 - abs(Self.wrapped(toward - aim)) / 0.6)
            }
            if score > bestScore {
                bestScore = score
                bestAim = toward
            }
        }
        aim = Self.wrapped(bestAim)
        settleFirstAim()
    }

    /// The very first look sets the thumb down already pointing the right way.
    private mutating func settleFirstAim() {
        if hasAim { return }
        heading = aim
        hasAim = true
    }
}

// MARK: - The game

/// Steps the round on the frame clock and turns touches into steering.
final class GulpCityDriver: ObservableObject {
    let round: GulpCityRound
    private let seed: UInt64
    private var lastFrame: Date? = nil
    private var frame = 0
    /// Where the steering stick is centred: where the finger landed, dragged along behind it.
    private var anchor: CGPoint? = nil
    private var reported = false
    private var lastTick = -1.0
    private var thumb: GulpCityThumb? = nil

    /// Points the finger travels from the anchor for full speed.
    private static let throwLength = 46.0
    /// Within this of the anchor the hole stays put.
    private static let deadZone = 4.0

    init(options: GameOptions) {
        seed = options.seed
        round = GulpCityRound(solo: options.solo, playerName: options.playerName,
                              friendNames: options.friendNames, seed: options.seed)
    }

    /// Steps the round up to this frame's time. Returns a number that changes with every frame drawn.
    func advance(to date: Date, link: GameLink) -> Int {
        if link.paused || reported {
            lastFrame = nil
            return frame
        }
        var elapsed = 0.0
        if let last = lastFrame { elapsed = Swift.min(0.1, Swift.max(0, date.timeIntervalSince(last))) }
        lastFrame = date
        guard elapsed > 0 else { return frame }
        // A slow frame is made up with several small steps, so the game keeps real time.
        var beats: [GulpCityRound.Beat] = []
        round.lock.lock()
        while elapsed > 1e-6 && round.stage != .over {
            let dt = Swift.min(elapsed, 1.0 / 60.0)
            elapsed -= dt
            if GameDemo.autopilot { selfPlay(dt) }
            round.step(dt)
            beats += round.takeBeats()
        }
        let over = round.stage == .over
        let result = over ? round.result : nil
        let now = round.now
        let gold = round.gold
        round.lock.unlock()
        buzz(beats, at: now)
        link.collect(gold)
        if let result {
            reported = true
            // not in the middle of a view update
            DispatchQueue.main.async { link.finish(result) }
        }
        frame &+= 1
        return frame
    }

    /// For the video feed: the round starts by itself and the scripted thumb steers.
    private func selfPlay(_ dt: Double) {
        switch round.stage {
        case .waiting:
            if round.now >= GulpCityThumb.waitSeconds { round.begin() }
        case .live:
            if thumb == nil { thumb = GulpCityThumb(round: round, seed: seed) }
            thumb?.play(round, dt)
        case .closing, .over:
            break
        }
    }

    /// One haptic a frame at most: the strongest thing that happened.
    private func buzz(_ beats: [GulpCityRound.Beat], at now: Double) {
        if beats.isEmpty { return }
        var biggest = 0
        var grew = false, counted = false, timeUp = false, emptied = false
        for beat in beats {
            switch beat {
            case .bite(let worth): biggest = Swift.max(biggest, worth)
            case .sizeUp: grew = true
            case .countdown: counted = true
            case .timeUp: timeUp = true
            case .emptied: emptied = true
            }
        }
        if emptied || grew {
            GameHaptics.success()
        } else if timeUp {
            GameHaptics.thud()
        } else if biggest >= 40 {
            GameHaptics.heavy()
        } else if biggest >= 8 {
            // small bites come in bursts: space the ticks out
            if now - lastTick < 0.09 { return }
            GameHaptics.thud()
        } else if biggest > 0 || counted {
            if now - lastTick < 0.07 { return }
            GameHaptics.tap()
        }
        lastTick = now
    }

    func drag(to finger: CGPoint, paused: Bool) {
        if paused {
            drop()
            return
        }
        guard let centre = anchor else {
            anchor = finger
            round.begin()
            round.letGo()
            return
        }
        var dx = Double(finger.x - centre.x), dy = Double(finger.y - centre.y)
        var length = (dx * dx + dy * dy).squareRoot()
        if length > Self.throwLength {
            // the anchor trails the finger, so turning back takes effect at once
            dx *= Self.throwLength / length
            dy *= Self.throwLength / length
            length = Self.throwLength
            anchor = CGPoint(x: Double(finger.x) - dx, y: Double(finger.y) - dy)
        }
        if length < Self.deadZone {
            round.letGo()
            return
        }
        let push = 0.3 + 0.7 * (length - Self.deadZone) / (Self.throwLength - Self.deadZone)
        round.steer(dx: dx / length * push, dy: dy / length * push)
    }

    /// The finger lifted, or the app covered the game.
    func drop() {
        anchor = nil
        round.letGo()
    }
}

public struct GulpCityGame: View {
    @ObservedObject private var link: GameLink
    @StateObject private var driver: GulpCityDriver

    public init(options: GameOptions, link: GameLink) {
        self.link = link
        _driver = StateObject(wrappedValue: GulpCityDriver(options: options))
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: link.paused)) { timeline in
            GulpCityBoard(round: driver.round, frame: driver.advance(to: timeline.date, link: link))
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { value in
                    locked { driver.drag(to: value.location, paused: link.paused) }
                }
                .onEnded { _ in
                    locked { driver.drop() }
                }
        )
        .onChange(of: link.paused) { _, paused in
            if paused { locked { driver.drop() } }
        }
        .ignoresSafeArea()
    }

    private func locked(_ change: () -> Void) {
        driver.round.lock.lock()
        change()
        driver.round.lock.unlock()
    }
}
