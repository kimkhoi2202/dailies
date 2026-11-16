import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// Corner Pocket, playable.
//
// CornerPocketModel    the rules of a round in plain Swift: aim, pull, release, step(dt:).
// CornerPocketPlanner  finds a good shot on a table. The friend across the table and the scripted player use it.
// CornerPocketPilot    the scripted player. It only runs while GameDemo.autopilot is on.
// CornerPocketRunner   keeps the clock, turns touches into aim and power, fires haptics, reports the result.
// CornerPocketGame     the view the app shows.
//
// A shot is only an angle and a power. The table's step has no randomness and does not depend on
// the frame rate, so the same shot on the same table always rolls out the same way: the friend's
// shots are played through exactly the same call as the player's.

/// One shot, the whole of the input.
struct CornerPocketShot {
    var angle: Double
    var power: Double
}

// MARK: - Model

final class CornerPocketModel {
    typealias M = CornerPocketMath
    typealias T = CornerPocketTable

    enum Stage { case aiming, rolling, ending, finished }

    /// Haptics owed since the last frame.
    struct Feel: OptionSet {
        let rawValue: Int
        static let tap = Feel(rawValue: 1 << 0)
        static let click = Feel(rawValue: 1 << 1)
        static let drop = Feel(rawValue: 1 << 2)
        static let good = Feel(rawValue: 1 << 3)
        static let foul = Feel(rawValue: 1 << 4)
        static let ahead = Feel(rawValue: 1 << 5)
        static let behind = Feel(rawValue: 1 << 6)
    }

    struct Player {
        let name: String
        let isBot: Bool
        /// 1 solids, 2 stripes, 0 not decided yet.
        var group = 0
    }

    // Tuning, in seconds unless noted.
    static let shotClock = 30.0
    static let soloMisses = 6
    static let missesPerRack = 3
    static let maxMisses = 9
    static let shotCap = 70
    static let minPower = 0.04
    static let pocketPoints = 10
    static let extraPoints = 10
    static let eightPoints = 50
    static let botThink = 0.65
    static let botTurn = 0.6
    static let botPull = 0.45
    static let botHold = 0.15
    static let endLength = 2.6
    static let clickGap = 0.07
    static let breakHint = "Drag to aim \u{00B7} pull the meter, release to shoot"

    let solo: Bool
    private var rng: CornerPocketRandom
    private(set) var table: CornerPocketTable
    private(set) var stage = Stage.aiming
    private(set) var players: [Player] = []
    private(set) var seats: [CornerPocketSeat] = []
    private(set) var turn = 0
    private(set) var aimAngle = -Double.pi / 2
    private(set) var power = 0.0
    private(set) var score = 0
    private(set) var shownScore = 0.0
    private(set) var scoreAge = 10.0
    private(set) var misses: Int
    private(set) var racks = 0
    private(set) var sunk = 0
    /// One gold for each ball the player sinks, five for the 8.
    private(set) var gold = 0
    private(set) var shots = 0
    private(set) var yourShots = 0
    private(set) var rackShots = 0
    private(set) var rackAge = 10.0
    private(set) var clock = CornerPocketModel.shotClock
    private(set) var notes: [CornerPocketNote] = []
    private(set) var bursts: [CornerPocketBurst] = []
    private(set) var praise: String?
    private(set) var praiseAge = 0.0
    private(set) var callout: String?
    private(set) var calloutAge = 0.0
    private(set) var banner: String?
    private(set) var hint = ""
    /// Round clock: runs while shots are being lined up and played.
    private(set) var time = 0.0
    /// Scenery clock: runs whenever the game is not paused.
    private(set) var ambient = 0.0
    private(set) var endClock = 0.0
    private(set) var winner: Int?
    private var detail = ""
    private var feel = Feel()
    private var seen = 0
    private var clickWait = 0.0
    private var shownSecond = 0
    private var botPlan: CornerPocketShot?
    private var botClock = 0.0
    private var botFrom = 0.0

    init(options: GameOptions) {
        solo = options.solo
        misses = Self.soloMisses
        var r = CornerPocketRandom(seed: options.seed, salt: CornerPocketRandom.round)
        table = T.racked(Self.rackOrder(&r), cueX: r.range(0.4, 0.6))
        rng = r

        let you = options.playerName.isEmpty ? "you" : options.playerName
        players = [Player(name: "You", isBot: false)]
        seats = [CornerPocketSeat(label: "You", letter: String(you.prefix(1)).uppercased(), color: CornerPocketPalette.lime)]
        if !solo {
            let name = options.friendNames.first { !$0.isEmpty } ?? "kaz"
            let short = String(name.prefix(12))
            players.append(Player(name: short, isBot: true))
            seats.append(CornerPocketSeat(label: short, letter: String(short.prefix(1)).uppercased(), color: CornerPocketPalette.peach))
        }
        notes.reserveCapacity(12)
        bursts.reserveCapacity(12)
        refreshSeats()
        refreshHint()
    }

    private static func rackOrder(_ r: inout CornerPocketRandom) -> [Int] {
        var order = [1, 2, 3, 4, 9, 10, 11, 12]
        var last = order.count - 1
        while last > 0 {
            order.swapAt(last, r.int(0...last))
            last -= 1
        }
        return order
    }

    // MARK: Reading

    var yourTurn: Bool { stage == .aiming && turn == 0 }
    var cue: CornerPocketBall { table.balls[0] }
    var aim: CornerPocketAim { table.trace(angle: aimAngle) }
    var isBreak: Bool { rackShots == 0 }

    static func group(of number: Int) -> Int {
        if number == 0 || number == 8 { return 0 }
        return number < 8 ? 1 : 2
    }

    /// The balls a player may legally hit first right now.
    func wanted(by p: Int) -> (Int) -> Bool {
        if solo {
            return table.colorsLeft > 0 ? { $0 != 0 && $0 != 8 } : { $0 == 8 }
        }
        let g = players[p].group
        if g == 0 { return { $0 != 0 && $0 != 8 } }
        if table.left(group: g) != 0 { return { Self.group(of: $0) == g } }
        return { $0 == 8 }
    }

    var result: GameResult {
        if solo {
            let line: String
            if racks > 0 {
                line = racks == 1 ? "Cleared 1 rack" : "Cleared \(racks) racks"
            } else {
                line = sunk == 1 ? "Sank 1 ball" : "Sank \(sunk) balls"
            }
            return GameResult(score: score, unit: "points", detail: line)
        }
        return GameResult(score: score, unit: "points", detail: detail, placement: winner == 0 ? 1 : 2, playerCount: 2)
    }

    /// Hands over the haptics owed since the last call.
    func takeFeel() -> Feel {
        let owed = feel
        feel = []
        return owed
    }

    // MARK: Input

    func aim(at angle: Double) {
        guard yourTurn else { return }
        aimAngle = angle
    }

    /// Points the cue at a spot on the table. False when the spot is too close to the cue ball to read.
    @discardableResult
    func aim(toward x: Double, _ y: Double) -> Bool {
        guard yourTurn else { return false }
        let dx = x - cue.x
        let dy = y - cue.y
        if dx * dx + dy * dy < 0.06 * 0.06 { return false }
        aimAngle = atan2(dy, dx)
        return true
    }

    func pull(_ amount: Double) {
        guard yourTurn else { return }
        power = M.clamp(amount)
    }

    /// Lets go of the cue. Too little power puts it down without a shot.
    @discardableResult
    func release() -> Bool {
        guard yourTurn else { return false }
        if power < Self.minPower {
            power = 0
            return false
        }
        yourShots += 1
        shoot(CornerPocketShot(angle: aimAngle, power: power))
        return true
    }

    private func shoot(_ shot: CornerPocketShot) {
        aimAngle = shot.angle
        table.strike(angle: shot.angle, power: shot.power)
        power = 0
        stage = .rolling
        shots += 1
        rackShots += 1
        seen = 0
        hint = ""
        owe(.tap)
    }

    private func owe(_ kind: Feel) { feel.insert(kind) }

    // MARK: Clock

    func step(dt raw: Double) {
        let dt = Swift.min(Swift.max(raw, 0), 1.0 / 30)
        if dt <= 0 { return }
        ambient += dt
        rackAge += dt
        scoreAge += dt
        clickWait = Swift.max(0, clickWait - dt)
        if !notes.isEmpty {
            for k in notes.indices { notes[k].age += dt }
            notes.removeAll { $0.age >= CornerPocketPainter.noteLength }
        }
        if !bursts.isEmpty {
            for k in bursts.indices { bursts[k].age += dt }
            bursts.removeAll { $0.age >= CornerPocketPainter.burstLength }
        }
        if praise != nil {
            praiseAge += dt
            if praiseAge >= CornerPocketPainter.praiseLength { praise = nil }
        }
        if callout != nil {
            calloutAge += dt
            if calloutAge >= CornerPocketPainter.calloutLength { callout = nil }
        }
        let goal = Double(score)
        if shownScore < goal {
            shownScore = Swift.min(goal, shownScore + Swift.max(40, (goal - shownScore) * 8) * dt)
        }

        switch stage {
        case .aiming:
            time += dt
            table.advance(dt)
            if players[turn].isBot {
                botStep(dt)
            } else {
                clock -= dt
                if clock <= 0 { timeOut() }
                let second = Int(clock.rounded(.up))
                if second != shownSecond {
                    shownSecond = second
                    refreshHint()
                }
            }
        case .rolling:
            time += dt
            table.advance(dt)
            let potted = table.potted
            while seen < potted.count {
                let number = potted[seen]
                seen += 1
                if let i = table.index(of: number) {
                    let hole = T.holes[table.balls[i].hole]
                    if bursts.count >= 10 { bursts.removeFirst() }
                    bursts.append(CornerPocketBurst(x: hole.x, y: hole.y, number: number, age: 0))
                }
                owe(.drop)
            }
            if table.impact > 0.5 && clickWait <= 0 {
                owe(.click)
                clickWait = Self.clickGap
            }
            table.impact = 0
            if !table.moving { resolve() }
        case .ending:
            table.advance(dt)
            endClock += dt
            if endClock >= Self.endLength { stage = .finished }
        case .finished:
            break
        }
        refreshSeats()
    }

    private func botStep(_ dt: Double) {
        botClock += dt
        guard let plan = botPlan else {
            if botClock >= Self.botThink {
                // While the scripted player is losing on purpose, the friend hands the turn straight back
                // so it can sink the 8 early. Once the player's group is gone that can no longer happen,
                // so the friend plays on and closes the match itself.
                let mine = players[0].group
                let throwing = GameDemo.autopilot && (GameDemo.loseAfter.map { time >= $0 } ?? false)
                    && (mine == 0 || table.left(group: mine) != 0)
                botPlan = throwing ? CornerPocketPlanner.miss(table)
                    : CornerPocketPlanner.plan(table, wanted: wanted(by: turn), isBreak: isBreak,
                                               skill: CornerPocketPlanner.friend, rng: &rng)
                botFrom = aimAngle
                botClock = 0
            }
            return
        }
        aimAngle = botFrom + M.turn(from: botFrom, to: plan.angle) * M.smooth(0, Self.botTurn, botClock)
        let pullFrom = Self.botTurn + 0.1
        if botClock > pullFrom {
            power = plan.power * M.easeOut((botClock - pullFrom) / Self.botPull)
        }
        if botClock >= pullFrom + Self.botPull + Self.botHold {
            botPlan = nil
            shoot(plan)
        }
    }

    private func timeOut() {
        power = 0
        shots += 1
        owe(.foul)
        if solo {
            misses -= 1
            if misses <= 0 {
                end(winner: nil, banner: "Out of misses", line: "")
                return
            }
            say("Out of time")
        } else {
            say("Out of time. \(players[1].name) to shoot")
            turn = 1
        }
        beginTurn()
    }

    // MARK: Rules

    private func resolve() {
        let me = turn
        let potted = table.potted
        let scratch = potted.contains(0)
        var eightIn = potted.contains(8)
        let first = table.firstHit
        let opening = rackShots == 1
        if scratch { table.respot(0, x: 0.5, y: T.headY) }
        if eightIn && opening {
            // The 8 on the break goes back on the spot.
            table.respot(8, x: 0.5, y: T.footY)
            eightIn = false
            say("The 8 goes back on the spot")
        }
        var colors = 0
        for n in potted where n != 0 && n != 8 { colors += 1 }
        if solo {
            resolveSolo(scratch: scratch, eightIn: eightIn, first: first, colors: colors, potted: potted)
        } else {
            resolveMatch(me: me, scratch: scratch, eightIn: eightIn, first: first, opening: opening, potted: potted)
        }
    }

    private func resolveMatch(me: Int, scratch: Bool, eightIn: Bool, first: Int?, opening: Bool, potted: [Int]) {
        let other = 1 - me
        let g = players[me].group
        var groupDown = 0
        for n in potted where g != 0 && Self.group(of: n) == g { groupDown += 1 }
        let clearedBefore = g != 0 && table.left(group: g) == 0 && groupDown == 0

        var why: String?
        if scratch {
            why = "Scratch"
        } else if let first {
            if g == 0 {
                if first == 8 && !opening { why = "The 8 came first" }
            } else if clearedBefore ? first != 8 : Self.group(of: first) != g {
                why = "Wrong ball first"
            }
        } else {
            why = "No ball hit"
        }

        if eightIn {
            let clean = clearedBefore && why == nil
            if clean {
                if me == 0 {
                    award(1, points: Self.eightPoints, ball: 8)
                    praiseWith("Perfect")
                    end(winner: 0, banner: "You sank the 8", line: "Sank the 8 to close it out")
                } else {
                    end(winner: 1, banner: "\(players[1].name) sank the 8", line: "\(players[1].name) sank the 8 first")
                }
            } else if me == 0 {
                end(winner: 1, banner: scratch ? "Scratch on the 8" : "The 8 went in early",
                    line: scratch ? "Scratched on the 8" : "Sank the 8 too early")
            } else {
                end(winner: 0, banner: "\(players[1].name) sank the 8 early", line: "\(players[1].name) sank the 8 too early")
            }
            return
        }

        if g == 0 && why == nil, let firstIn = potted.first(where: { $0 != 0 && $0 != 8 }) {
            let mine = Self.group(of: firstIn)
            players[me].group = mine
            players[other].group = 3 - mine
            let yours = me == 0 ? mine : 3 - mine
            say(yours == 1 ? "You have solids" : "You have stripes")
            relabel()
        }
        let mine = players[me].group
        var own = 0
        for n in potted where mine != 0 && Self.group(of: n) == mine { own += 1 }
        if me == 0 && why == nil && own > 0 {
            award(own, points: Self.pocketPoints, ball: -1)
            if own >= 3 { praiseWith("Great") } else if own == 2 { praiseWith("Nice") }
            if table.left(group: mine) == 0 && own >= 1 && praise == nil { praiseWith("Nice") }
        }

        if let why {
            if me == 0 {
                say("\(why). \(players[other].name) to shoot")
                owe(.foul)
            } else {
                say("\(why). Your shot")
            }
        }
        if shots >= Self.shotCap {
            let open = players[0].group == 0
            let you = open ? table.colorsLeft : table.left(group: players[0].group).nonzeroBitCount
            let them = open ? table.colorsLeft : table.left(group: players[1].group).nonzeroBitCount
            let side = open ? "on the table" : "on your side"
            end(winner: you <= them ? 0 : 1, banner: "Out of shots", line: you == 1 ? "1 ball left \(side)" : "\(you) balls left \(side)")
            return
        }
        if why != nil || own == 0 { turn = other }
        beginTurn()
    }

    private func resolveSolo(scratch: Bool, eightIn: Bool, first: Int?, colors: Int, potted: [Int]) {
        let clearedBefore = table.colorsLeft == 0 && colors == 0
        var why: String?
        if scratch {
            why = "Scratch"
        } else if let first {
            if first == 8 && !clearedBefore && rackShots > 1 { why = "The 8 came first" }
        } else {
            why = "No ball hit"
        }

        if eightIn {
            if clearedBefore && !scratch {
                award(1, points: Self.eightPoints, ball: 8)
                praiseWith("Perfect")
                racks += 1
                misses = Swift.min(Self.maxMisses, misses + Self.missesPerRack)
                newRack()
                say("New rack")
                beginTurn()
            } else {
                end(winner: nil, banner: scratch ? "Scratch on the 8" : "The 8 went in early", line: "")
            }
            return
        }

        if why == nil && colors > 0 {
            award(colors, points: Self.pocketPoints, ball: -1)
            if colors >= 3 { praiseWith("Great") } else if colors == 2 { praiseWith("Nice") }
        } else {
            misses -= 1
            if let why {
                owe(.foul)
                say(why)
            }
            if misses <= 0 {
                end(winner: nil, banner: "Out of misses", line: "")
                return
            }
        }
        beginTurn()
    }

    /// Points for the player, a note over each pocket the balls went into.
    private func award(_ count: Int, points: Int, ball: Int) {
        let gained = count * points + Swift.max(0, count - 1) * Self.extraPoints
        score += gained
        scoreAge = 0
        if ball != 8 { sunk += count }
        gold += ball == 8 ? 5 : count
        for n in table.potted where n != 0 && (ball == 8 ? n == 8 : n != 8) {
            guard let i = table.index(of: n) else { continue }
            if solo == false && Self.group(of: n) != players[0].group && ball != 8 { continue }
            let hole = T.holes[table.balls[i].hole]
            if notes.count >= 10 { notes.removeFirst() }
            notes.append(CornerPocketNote(text: "+\(points)", x: hole.x, y: hole.y, age: 0))
        }
    }

    private func praiseWith(_ word: String) {
        praise = word
        praiseAge = 0
        owe(.good)
    }

    private func say(_ words: String) {
        callout = words
        calloutAge = 0
    }

    private func newRack() {
        let old = table.cue
        var next = T.racked(Self.rackOrder(&rng), cueX: 0.5)
        if old.live && next.isFree(old.x, old.y, except: 0) {
            next.balls[0].x = old.x
            next.balls[0].y = old.y
        }
        table = next
        rackShots = 0
        rackAge = 0
    }

    private func beginTurn() {
        stage = .aiming
        clock = Self.shotClock
        shownSecond = 0
        power = 0
        botPlan = nil
        botClock = 0
        refreshHint()
    }

    private func end(winner who: Int?, banner words: String, line: String) {
        winner = who
        banner = words
        detail = line
        stage = .ending
        endClock = 0
        power = 0
        hint = ""
        if who == 0 { owe(.ahead) } else { owe(.behind) }
    }

    // MARK: Labels

    private func relabel() {
        for k in seats.indices {
            let g = players[k].group
            seats[k].group = g
            if g != 0 { seats[k].label = "\(players[k].name) \u{00B7} \(g == 1 ? "solids" : "stripes")" }
        }
    }

    private func refreshSeats() {
        let live = stage == .aiming || stage == .rolling
        for k in seats.indices {
            seats[k].active = live && turn == k
            let g = players[k].group
            if g != 0 {
                let mask = table.left(group: g)
                if seats[k].left != mask { seats[k].left = mask }
            }
            seats[k].clock = live && stage == .aiming && turn == k && !players[k].isBot ? clock / Self.shotClock : -1
        }
    }

    private func refreshHint() {
        guard stage == .aiming else {
            hint = ""
            return
        }
        if players[turn].isBot {
            hint = "\(players[turn].name) is lining up a shot"
            return
        }
        if yourShots == 0 {
            hint = Self.breakHint
            return
        }
        var line: String
        if solo {
            line = table.colorsLeft > 0 ? "Sink every ball. The 8 goes last" : "Sink the 8"
        } else {
            let g = players[0].group
            if g == 0 {
                line = "Your turn. Any ball but the 8"
            } else if table.left(group: g) == 0 {
                line = "Your turn. Sink the 8"
            } else {
                line = g == 1 ? "Your turn. Sink a solid" : "Your turn. Sink a stripe"
            }
        }
        if clock <= 10 { line += " \u{00B7} \(Int(clock.rounded(.up)))s" }
        hint = line
    }

    // MARK: Frame

    func fill(_ f: inout CornerPocketFrame) {
        f.balls = table.balls
        f.aim = stage == .aiming ? aim : nil
        f.power = power
        f.meterLive = yourTurn
        f.seats = seats
        f.misses = solo ? Swift.max(0, misses) : nil
        f.score = Int(shownScore.rounded(.down))
        f.scoreAge = scoreAge
        f.notes = notes
        f.bursts = bursts
        f.praise = praise
        f.praiseAge = praiseAge
        f.callout = callout
        f.calloutAge = calloutAge
        f.hint = hint
        f.rackAge = rackAge
        f.time = ambient
        if stage == .ending || stage == .finished {
            f.dim = M.smooth(0, 0.4, endClock)
            f.banner = banner
            f.bannerAge = endClock
        }
    }
}

// MARK: - Planner

/// Picks a shot the way a decent player does: the easiest clear pot, struck hard enough to drop.
enum CornerPocketPlanner {
    typealias T = CornerPocketTable

    struct Skill {
        /// Spread of the aim, in radians.
        let aim: Double
        /// Spread of the power, as a share.
        let power: Double
    }

    static let friend = Skill(aim: 0.011, power: 0.1)
    static let pilot = Skill(aim: 0.006, power: 0.06)

    static func plan(_ table: CornerPocketTable, wanted: (Int) -> Bool, isBreak: Bool, skill: Skill,
                     rng: inout CornerPocketRandom) -> CornerPocketShot {
        var shot: CornerPocketShot
        if isBreak {
            shot = straightAt(table, wanted: { $0 != 0 }, power: 0.95)
        } else if let pot = bestPot(table, wanted: wanted) {
            shot = pot
        } else {
            shot = straightAt(table, wanted: wanted, power: 0.55)
        }
        shot.angle += rng.gauss() * skill.aim
        shot.power = CornerPocketMath.clamp(shot.power * (1 + rng.gauss() * skill.power), 0.08, 1)
        return shot
    }

    /// The easiest open pot on a wanted ball, or nil when there is none.
    static func bestPot(_ table: CornerPocketTable, wanted: (Int) -> Bool) -> CornerPocketShot? {
        let r = T.radius
        let cue = table.cue
        var best: CornerPocketShot?
        var bestScore = 0.0
        for (i, b) in table.balls.enumerated() where i > 0 && b.live && wanted(b.number) {
            for (k, hole) in T.holes.enumerated() {
                var dx = hole.x - b.x
                var dy = hole.y - b.y
                let d2 = (dx * dx + dy * dy).squareRoot()
                if d2 < 1e-6 { continue }
                dx /= d2
                dy /= d2
                // Side pockets only take balls coming in fairly square.
                if (k == 2 || k == 3) && abs(dx) < 0.8 { continue }
                let gx = b.x - dx * 2 * r
                let gy = b.y - dy * 2 * r
                if gx < r * 0.9 || gx > 1 - r * 0.9 || gy < r * 0.9 || gy > T.length - r * 0.9 { continue }
                var ux = gx - cue.x
                var uy = gy - cue.y
                let d1 = (ux * ux + uy * uy).squareRoot()
                if d1 < 1e-6 { continue }
                ux /= d1
                uy /= d1
                let cut = ux * dx + uy * dy
                if cut < 0.25 { continue }
                var open = true
                for (j, o) in table.balls.enumerated() where j > 0 && j != i && o.live {
                    if gap(cue.x, cue.y, gx, gy, o.x, o.y) < 2 * r || gap(b.x, b.y, hole.x, hole.y, o.x, o.y) < 2 * r * 0.98 {
                        open = false
                        break
                    }
                }
                if !open { continue }
                let objectSpeed = need(d2, end: 0.55)
                let cueSpeed = need(d1, end: objectSpeed / ((1 + T.ballBounce) / 2 * cut))
                let power = T.power(forSpeed: cueSpeed)
                var score = cut * cut / (0.5 + d1 + 1.6 * d2)
                if power > 1 { score *= 0.3 }
                if score > bestScore {
                    bestScore = score
                    best = CornerPocketShot(angle: atan2(uy, ux), power: CornerPocketMath.clamp(power, 0.12, 1))
                }
            }
        }
        return best
    }

    /// The table once a shot has rolled out and every ball has stopped.
    static func rollOut(_ table: CornerPocketTable, _ shot: CornerPocketShot) -> CornerPocketTable {
        var copy = table
        copy.strike(angle: shot.angle, power: shot.power)
        var steps = 0
        while copy.moving && steps < 2880 {
            copy.advance(T.step)
            steps += 1
        }
        return copy
    }

    /// A soft shot that drops nothing, so the turn passes. Only the scripted round asks for one.
    static func miss(_ table: CornerPocketTable) -> CornerPocketShot {
        for k in 0..<24 {
            let shot = CornerPocketShot(angle: Double(k) * Double.pi / 12 + 0.13, power: 0.16)
            if table.trace(angle: shot.angle).target < 0 && rollOut(table, shot).potted.isEmpty { return shot }
        }
        return CornerPocketShot(angle: Double.pi / 2, power: 0.08)
    }

    /// Straight at the nearest wanted ball.
    static func straightAt(_ table: CornerPocketTable, wanted: (Int) -> Bool, power: Double) -> CornerPocketShot {
        let cue = table.cue
        var best = Double.infinity
        var angle = -Double.pi / 2
        for (i, b) in table.balls.enumerated() where i > 0 && b.live && wanted(b.number) {
            let d = (b.x - cue.x) * (b.x - cue.x) + (b.y - cue.y) * (b.y - cue.y)
            if d < best {
                best = d
                angle = atan2(b.y - cue.y, b.x - cue.x)
            }
        }
        return CornerPocketShot(angle: angle, power: power)
    }

    /// The speed a ball needs to roll a distance and still be moving at the end speed.
    static func need(_ distance: Double, end: Double) -> Double {
        var v = Swift.max(end, 0.05)
        var s = 0.0
        let ds = 0.01
        while s < distance {
            v += (T.rollDrag + T.speedDrag * v) / v * ds
            s += ds
        }
        return v
    }

    /// How far a point is from a segment.
    static func gap(_ ax: Double, _ ay: Double, _ bx: Double, _ by: Double, _ px: Double, _ py: Double) -> Double {
        let vx = bx - ax
        let vy = by - ay
        let len2 = vx * vx + vy * vy
        let k = len2 > 0 ? CornerPocketMath.clamp(((px - ax) * vx + (py - ay) * vy) / len2) : 0
        let dx = ax + vx * k - px
        let dy = ay + vy * k - py
        return (dx * dx + dy * dy).squareRoot()
    }
}

// MARK: - Scripted player

/// Plays the round for recordings while GameDemo.autopilot is on. It turns the cue, pulls the meter and
/// lets go through the same calls a finger makes. Once GameDemo.loseAfter has passed it goes for the 8
/// too early, or misses on purpose, so the round ends the way a person loses it.
struct CornerPocketPilot {
    typealias M = CornerPocketMath

    static let firstHold = 1.4
    static let hold = 0.55
    static let turnTime = 0.7
    static let pullTime = 0.5

    /// Seconds of each frame the search may take. A Release build tries dozens of shots in that time.
    static let searchBudget = 0.004

    private var rng: CornerPocketRandom
    private var plan: CornerPocketShot?
    private var clock = 0.0
    private var from = 0.0
    /// Shots still to try while looking for one that loses. The table step is exact, so a shot that
    /// loses on a copy of the table loses on the real one.
    private var tries: [CornerPocketShot] = []
    private var tried = 0
    private var searching = false
    /// The tried shot that leaves the 8 nearest a pocket, for when none loses outright.
    private var closest: CornerPocketShot?
    private var closestGap = Double.infinity

    init(seed: UInt64) {
        rng = CornerPocketRandom(seed: seed ^ 0x706F_6F6C, salt: CornerPocketRandom.pilot)
    }

    mutating func play(_ model: CornerPocketModel, dt: Double) {
        guard model.yourTurn else {
            plan = nil
            searching = false
            clock = 0
            return
        }
        clock += dt
        guard let shot = plan else {
            if clock < (model.shots == 0 ? Self.firstHold : Self.hold) { return }
            let losing = GameDemo.loseAfter.map { model.time >= $0 } ?? false
            if losing && !model.isBreak {
                guard let found = searchLosingShot(model) else { return }
                plan = found
            } else {
                plan = CornerPocketPlanner.plan(model.table, wanted: model.wanted(by: 0), isBreak: model.isBreak,
                                                skill: CornerPocketPlanner.pilot, rng: &rng)
            }
            from = model.aimAngle
            clock = 0
            return
        }
        model.aim(at: from + M.turn(from: from, to: shot.angle) * M.smooth(0, Self.turnTime, clock))
        let pullFrom = Self.turnTime + 0.15
        if clock > pullFrom { model.pull(shot.power * M.easeOut((clock - pullFrom) / Self.pullTime)) }
        if clock >= pullFrom + Self.pullTime + 0.12 {
            model.pull(shot.power)
            model.release()
            plan = nil
            clock = 0
        }
    }

    /// Looks a few shots further each frame for one that sinks the 8 too early or with the cue ball.
    /// nil while still looking. When nothing loses outright it plays the shot that leaves the 8 nearest a
    /// pocket, so the next look finds one.
    private mutating func searchLosingShot(_ model: CornerPocketModel) -> CornerPocketShot? {
        let table = model.table
        if !searching {
            searching = true
            tried = 0
            closest = nil
            closestGap = Double.infinity
            tries.removeAll(keepingCapacity: true)
            let cue = table.cue
            var toward = -Double.pi / 2
            if let i = table.index(of: 8), table.balls[i].live {
                toward = atan2(table.balls[i].y - cue.y, table.balls[i].x - cue.x)
            }
            for k in 0..<90 {
                let off = Double((k + 1) / 2) * (2 * Double.pi / 90) * (k % 2 == 0 ? 1 : -1)
                for power in [0.55, 0.85, 0.3, 1] { tries.append(CornerPocketShot(angle: toward + off, power: power)) }
            }
        }
        let g = model.players[0].group
        let early = model.solo ? table.colorsLeft > 0 : g == 0 || table.left(group: g) != 0
        let start = ProcessInfo.processInfo.systemUptime
        while tried < tries.count {
            if tried > 0 && ProcessInfo.processInfo.systemUptime - start > Self.searchBudget { break }
            let shot = tries[tried]
            tried += 1
            let after = CornerPocketPlanner.rollOut(table, shot)
            let potted = after.potted
            if potted.contains(8) && (early || potted.contains(0)) {
                searching = false
                return shot
            }
            guard !potted.contains(8), let i = after.index(of: 8) else { continue }
            let eight = after.balls[i]
            for hole in CornerPocketTable.holes {
                let gap = (eight.x - hole.x) * (eight.x - hole.x) + (eight.y - hole.y) * (eight.y - hole.y)
                if gap < closestGap {
                    closestGap = gap
                    closest = shot
                }
            }
        }
        if tried < tries.count { return nil }
        searching = false
        return closest ?? CornerPocketPlanner.miss(table)
    }
}

// MARK: - Game view

/// Paints the model as it is right now.
struct CornerPocketCanvas: View {
    let runner: CornerPocketRunner
    /// A new number every frame. The model is a class, so this is what makes SwiftUI repaint.
    var frame = 0

    var body: some View {
        Canvas(opaque: true, colorMode: .nonLinear, rendersAsynchronously: false) { context, size in
            if size.width <= 8 || size.height <= 8 { return }
            runner.paint(&context, size)
        }
    }
}

/// Holds the round between frames. Nothing is published: the timeline repaints every frame anyway.
final class CornerPocketRunner: ObservableObject {
    private enum Touch { case none, aim, meter, sling }

    let model: CornerPocketModel
    private let seed: UInt64
    private var lastDate: Date?
    private var frame = 0
    private var reported = false
    /// Made the first time it is needed, which is only when GameDemo.autopilot is on.
    private var pilot: CornerPocketPilot?
    private var touch = Touch.none
    private var touchY = 0.0
    private var touchPower = 0.0
    private var notch = 0

    init(options: GameOptions) {
        model = CornerPocketModel(options: options)
        seed = options.seed
    }

    /// The frame borrows the model's arrays and lets go of them when painting is done, so the model
    /// keeps changing them in place instead of copying.
    func paint(_ ctx: inout GraphicsContext, _ size: CGSize) {
        var frame = CornerPocketFrame()
        model.fill(&frame)
        CornerPocketPainter(size: size).draw(frame, &ctx)
    }

    /// Brings the model up to the given date. Returns a number that changes when there is a new frame to paint.
    func advance(to date: Date, link: GameLink) -> Int {
        if link.paused {
            lastDate = nil
            if touch != .none {
                touch = .none
                model.pull(0)
            }
            return frame
        }
        defer { lastDate = date }
        guard let before = lastDate else { return frame }
        var owed = Swift.min(Swift.max(date.timeIntervalSince(before), 0), 0.1)
        if owed <= 0 { return frame }
        while owed > 1e-6 {
            let dt = Swift.min(owed, 1.0 / 60)
            owed -= dt
            model.step(dt: dt)
            if GameDemo.autopilot {
                if pilot == nil { pilot = CornerPocketPilot(seed: seed) }
                pilot?.play(model, dt: dt)
            }
            settle(link)
        }
        frame &+= 1
        return frame
    }

    // MARK: Touches

    func touchBegan(at p: CGPoint, in size: CGSize, link: GameLink) {
        touch = .none
        if link.paused || link.isFinished || !model.yourTurn { return }
        let L = CornerPocketLayout(size: size)
        let cue = model.cue
        let dx = Double(p.x) - L.px(cue.x)
        let dy = Double(p.y) - L.py(cue.y)
        if L.inMeter(p) {
            touch = .meter
            touchY = Double(p.y)
            touchPower = model.power
            notch = Int(model.power * 5)
        } else if dx * dx + dy * dy < 34 * L.u * 34 * L.u {
            touch = .sling
            notch = 0
        } else {
            touch = .aim
            let at = L.table(p)
            model.aim(toward: at.x, at.y)
        }
        GameHaptics.tap()
    }

    func touchMoved(to p: CGPoint, in size: CGSize, link: GameLink) {
        if link.paused || !model.yourTurn { return }
        let L = CornerPocketLayout(size: size)
        switch touch {
        case .none:
            return
        case .aim:
            let at = L.table(p)
            model.aim(toward: at.x, at.y)
        case .meter:
            let travel = Double(L.meter.height) * 0.85
            model.pull(touchPower + (Double(p.y) - touchY) / travel)
        case .sling:
            let cue = model.cue
            let vx = L.px(cue.x) - Double(p.x)
            let vy = L.py(cue.y) - Double(p.y)
            let len = (vx * vx + vy * vy).squareRoot()
            if len > 14 * L.u {
                model.aim(at: atan2(vy, vx))
                model.pull((len - 14 * L.u) / (150 * L.u))
            } else {
                model.pull(0)
            }
        }
        // A light tick every fifth of the meter.
        let level = Int(model.power * 5)
        if level != notch {
            notch = level
            GameHaptics.tap()
        }
    }

    func touchEnded(cancelled: Bool, link: GameLink) {
        defer { touch = .none }
        if link.paused {
            model.pull(0)
            return
        }
        guard touch == .meter || touch == .sling, model.yourTurn else { return }
        if cancelled || !model.release() { model.pull(0) }
        settle(link)
    }

    /// Plays the haptics the model owes and reports the round once it is over.
    private func settle(_ link: GameLink) {
        let feel = model.takeFeel()
        if feel.contains(.ahead) {
            GameHaptics.heavy()
            GameHaptics.success()
        } else if feel.contains(.behind) || feel.contains(.foul) {
            GameHaptics.fail()
        } else if feel.contains(.good) {
            GameHaptics.success()
        } else if feel.contains(.drop) {
            GameHaptics.thud()
        } else if feel.contains(.click) || feel.contains(.tap) {
            GameHaptics.tap()
        }
        link.collect(model.gold)
        if model.stage == .finished, !reported {
            reported = true
            let result = model.result
            DispatchQueue.main.async { link.finish(result) }
        }
    }
}

// MARK: - Touches

#if canImport(UIKit) && !os(macOS)
/// Reports a finger the moment it lands, as it moves and when it lifts.
private struct CornerPocketTouchPad: UIViewRepresentable {
    var began: (CGPoint, CGSize) -> Void
    var moved: (CGPoint, CGSize) -> Void
    var ended: (Bool) -> Void

    func makeUIView(context: Context) -> CornerPocketTouchView {
        let view = CornerPocketTouchView()
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = false
        view.began = began
        view.moved = moved
        view.ended = ended
        return view
    }

    func updateUIView(_ view: CornerPocketTouchView, context: Context) {
        view.began = began
        view.moved = moved
        view.ended = ended
    }
}

final class CornerPocketTouchView: UIView {
    var began: ((CGPoint, CGSize) -> Void)?
    var moved: ((CGPoint, CGSize) -> Void)?
    var ended: ((Bool) -> Void)?
    private var tracked: UITouch?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard tracked == nil, let touch = touches.first else { return }
        tracked = touch
        began?(touch.location(in: self), bounds.size)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = tracked, touches.contains(touch) else { return }
        moved?(touch.location(in: self), bounds.size)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = tracked, touches.contains(touch) else { return }
        tracked = nil
        ended?(false)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = tracked, touches.contains(touch) else { return }
        tracked = nil
        ended?(true)
    }
}
#else
private struct CornerPocketTouchPad: View {
    var began: (CGPoint, CGSize) -> Void
    var moved: (CGPoint, CGSize) -> Void
    var ended: (Bool) -> Void
    @State private var isDown = false

    var body: some View {
        GeometryReader { geo in
            Color.clear
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isDown {
                            isDown = true
                            began(value.startLocation, geo.size)
                        }
                        moved(value.location, geo.size)
                    }
                    .onEnded { _ in
                        isDown = false
                        ended(false)
                    })
        }
    }
}
#endif

public struct CornerPocketGame: View {
    private let options: GameOptions
    private let link: GameLink

    public init(options: GameOptions, link: GameLink) {
        self.options = options
        self.link = link
    }

    public var body: some View {
        // A new link is a new round, so the round's state lives and dies with the link.
        CornerPocketRound(options: options, link: link)
            .id(ObjectIdentifier(link))
    }
}

private struct CornerPocketRound: View {
    @ObservedObject var link: GameLink
    @StateObject private var runner: CornerPocketRunner

    init(options: GameOptions, link: GameLink) {
        self.link = link
        _runner = StateObject(wrappedValue: CornerPocketRunner(options: options))
    }

    var body: some View {
        ZStack {
            TimelineView(.animation(minimumInterval: nil, paused: link.paused)) { timeline in
                CornerPocketCanvas(runner: runner, frame: runner.advance(to: timeline.date, link: link))
            }
            CornerPocketTouchPad(
                began: { p, size in runner.touchBegan(at: p, in: size, link: link) },
                moved: { p, size in runner.touchMoved(to: p, in: size, link: link) },
                ended: { cancelled in runner.touchEnded(cancelled: cancelled, link: link) })
        }
        .ignoresSafeArea()
        .accessibilityElement()
        .accessibilityLabel("Corner Pocket. Drag on the table to aim. Pull the meter on the right down and let go to shoot.")
        .accessibilityAddTraits(.allowsDirectInteraction)
    }
}
