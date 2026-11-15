import SwiftUI

// Corner Pocket, playable.
//
// CornerPocketModel   the table and the rules in plain Swift: a fixed-step physics world, turns,
//                     groups, the 8, and the friend's shots.
// CornerPocketCanvas  turns the model into a CornerPocketFrame for the painter.
// CornerPocketPilot   the scripted player. It only runs while GameDemo.autopilot is on.
// CornerPocketRunner  keeps the clock, passes touches on, fires haptics, reports the result.
// CornerPocketGame    the view the app shows.
//
// A shot is only an angle and a power. The physics has a fixed step and no randomness, so the same
// shot on the same table plays out the same on every phone.

// MARK: - Model

struct CornerPocketPlan {
    var angle: Double
    var power: Double
}

final class CornerPocketModel {
    typealias T = CornerPocketTable
    typealias M = CornerPocketMath

    enum Stage { case ready, aiming, rolling, ending, finished }

    /// What happened since the last call, as a haptic. A stronger one replaces a weaker one.
    enum Feedback: Int { case none, click, strike, pot, good, foul, won }

    // Physics. Table units and seconds.
    static let step = 1.0 / 240
    static let rollDrag = 300.0          // speed lost per second, always
    static let airDrag = 0.35            // and this share of the speed per second
    static let minSpeed = 110.0
    static let maxSpeed = 1500.0
    static let ballBounce = 0.94
    static let railBounce = 0.76
    static let stopSpeed = 5.0
    static let longestRoll = 12.0

    // Rules and pacing.
    static let startLives = 3
    static let shotCap = 70
    static let thinkLength = 1.35
    static let endLength = 1.9
    static let praiseLength = 1.3
    static let hint = "Drag to aim. Pull the meter to shoot"

    let versus: Bool
    let names: [String]
    let bestScore: Int
    private var rng: CornerPocketRandom
    private var fx: CornerPocketRandom

    private(set) var stage = Stage.ready
    private(set) var balls: [CornerPocketBall] = []
    /// 0 the player, 1 the friend.
    private(set) var turn = 0
    /// 1 solids, 2 stripes, 0 open.
    private(set) var groups = [0, 0]
    private(set) var aimAngle = -Double.pi / 2
    private(set) var pull = 0.0
    private(set) var lives = CornerPocketModel.startLives
    private(set) var score = 0
    private(set) var shown = 0.0
    private(set) var sinceScore = 10.0
    private(set) var time = 0.0
    private(set) var ambient = 0.0
    private(set) var endClock = 0.0
    private(set) var shots = 0
    private(set) var winner: Int?
    private(set) var status = CornerPocketModel.hint
    private(set) var praise: String?
    private(set) var praiseAge = 0.0
    private(set) var floats: [CornerPocketFloat] = []
    private(set) var sparks: [CornerPocketSpark] = []
    private(set) var rings: [CornerPocketRing] = []
    private(set) var endLine = ""
    private(set) var sunkByPlayer = 0

    private var pulling = false
    private var rollClock = 0.0
    private var thinkClock = 0.0
    private var accumulator = 0.0
    private var firstHit = 0
    private var potted: [Int] = []
    private var shotGroup = 0
    private var shotGroupLeft = 0
    private var playerPotsThisShot = 0
    private var run = 0
    private var clickCool = 0.0
    private var feedback = Feedback.none
    private var friendPlan: CornerPocketPlan?
    private var friendFrom = 0.0

    init(options: GameOptions) {
        versus = !options.solo
        let friend = options.friendNames.first { !$0.isEmpty } ?? "kaz"
        names = ["You", String(friend.prefix(12))]
        bestScore = Swift.max(0, options.bestScore)
        rng = CornerPocketRandom(seed: options.seed, salt: CornerPocketRandom.round)
        fx = CornerPocketRandom(seed: options.seed, salt: CornerPocketRandom.effects)
        balls.reserveCapacity(16)
        potted.reserveCapacity(16)
        floats.reserveCapacity(8)
        sparks.reserveCapacity(96)
        rings.reserveCapacity(8)
        rack()
    }

    /// The seed decides the order of the balls in the rack. The 8 sits in the middle, and the two
    /// back corners hold one solid and one stripe.
    private func rack() {
        var solids = [1, 2, 3, 4, 5, 6, 7]
        var stripes = [9, 10, 11, 12, 13, 14, 15]
        shuffle(&solids)
        shuffle(&stripes)
        let cornerSolid = solids.removeLast()
        let cornerStripe = stripes.removeLast()
        var rest = solids + stripes
        shuffle(&rest)
        var slots = [Int](repeating: 0, count: 15)
        slots[4] = 8
        let solidLeft = rng.next() < 0.5
        slots[10] = solidLeft ? cornerSolid : cornerStripe
        slots[14] = solidLeft ? cornerStripe : cornerSolid
        var k = 0
        for i in 0..<15 where slots[i] == 0 {
            slots[i] = rest[k]
            k += 1
        }
        balls = [CornerPocketBall(number: 0, x: T.headX, y: T.headY)]
        let gap = 2 * T.r + 0.15
        var slot = 0
        for row in 0..<5 {
            for i in 0...row {
                let x = T.w / 2 + (Double(i) - Double(row) / 2) * gap
                let y = T.footY - Double(row) * gap * 0.8660254
                balls.append(CornerPocketBall(number: slots[slot], x: x, y: y))
                slot += 1
            }
        }
    }

    private func shuffle(_ list: inout [Int]) {
        var last = list.count - 1
        while last > 0 {
            list.swapAt(last, rng.int(0...last))
            last -= 1
        }
    }

    // MARK: Reading

    var playerTurn: Bool { (stage == .ready || stage == .aiming) && turn == 0 }
    var friendTurn: Bool { stage == .aiming && turn == 1 }

    /// Balls of a group still on the table. Group 0 counts every ball but the cue ball and the 8.
    func left(group g: Int) -> Int {
        var count = 0
        for b in balls where !b.sunk && b.number != 0 && b.number != 8 {
            if g == 0 || T.group(b.number) == g { count += 1 }
        }
        return count
    }

    /// May this side hit this ball first?
    func legal(_ n: Int, side: Int) -> Bool {
        if n == 0 { return false }
        if !versus { return n != 8 || left(group: 0) == 0 }
        let g = groups[side]
        if g == 0 { return n != 8 }
        if left(group: g) > 0 { return T.group(n) == g }
        return n == 8
    }

    var result: GameResult {
        let line = endLine.isEmpty ? nil : endLine
        guard versus else { return GameResult(score: score, unit: "points", detail: line) }
        return GameResult(score: score, unit: "points", detail: line, placement: winner == 0 ? 1 : 2, playerCount: 2)
    }

    func takeFeedback() -> Feedback {
        let owed = feedback
        feedback = .none
        return owed
    }

    private func owe(_ kind: Feedback) {
        if kind.rawValue > feedback.rawValue { feedback = kind }
    }

    // MARK: Input

    /// Point the cue at a spot on the table.
    func aim(at x: Double, _ y: Double) {
        guard playerTurn, !balls[0].sunk else { return }
        let dx = x - balls[0].x
        let dy = y - balls[0].y
        if dx * dx + dy * dy < 14 * 14 { return }
        begin()
        aimAngle = atan2(dy, dx)
    }

    /// Point the cue along an angle, for the slingshot and the scripted player.
    func aim(angle: Double) {
        guard playerTurn else { return }
        begin()
        aimAngle = angle
    }

    /// Draw the cue back, 0...1.
    func setPull(_ power: Double) {
        guard playerTurn else { return }
        begin()
        let next = M.clamp(power)
        if Int(next * 10) != Int(pull * 10) { owe(.click) }
        pull = next
        pulling = true
    }

    /// Let go of the cue. A pull too small to matter puts it back.
    func release() {
        guard playerTurn, pulling else { return }
        pulling = false
        if pull < 0.04 {
            pull = 0
            return
        }
        shoot(CornerPocketPlan(angle: aimAngle, power: pull))
    }

    private func begin() {
        if stage == .ready {
            stage = .aiming
            status = ""
        }
    }

    private func shoot(_ plan: CornerPocketPlan) {
        let speed = Self.minSpeed + (Self.maxSpeed - Self.minSpeed) * M.clamp(plan.power)
        aimAngle = plan.angle
        balls[0].vx = cos(plan.angle) * speed
        balls[0].vy = sin(plan.angle) * speed
        pull = 0
        pulling = false
        stage = .rolling
        rollClock = 0
        accumulator = 0
        firstHit = 0
        playerPotsThisShot = 0
        potted.removeAll(keepingCapacity: true)
        shotGroup = groups[turn]
        shotGroupLeft = left(group: shotGroup)
        shots += 1
        status = ""
        owe(.strike)
    }

    // MARK: Clock

    func step(dt raw: Double) {
        let dt = Swift.min(Swift.max(raw, 0), 1.0 / 30)
        if dt <= 0 { return }
        ambient += dt
        stepEffects(dt)
        if stage == .finished { return }
        if stage != .ready { time += dt }

        switch stage {
        case .ready:
            break
        case .aiming:
            if turn == 1 { think(dt) }
        case .rolling:
            rollClock += dt
            accumulator += dt
            while accumulator >= Self.step {
                accumulator -= Self.step
                physics(Self.step)
            }
            if stopped() || rollClock > Self.longestRoll { settleShot() }
        case .ending:
            endClock += dt
            if endClock >= Self.endLength { stage = .finished }
        case .finished:
            break
        }
    }

    private func stepEffects(_ dt: Double) {
        sinceScore = Swift.min(sinceScore + dt, 100)
        clickCool -= dt
        if praise != nil {
            praiseAge += dt
            if praiseAge > Self.praiseLength { praise = nil }
        }
        for i in balls.indices where balls[i].sunk { balls[i].sinkAge = Swift.min(balls[i].sinkAge + dt, 100) }
        if !floats.isEmpty {
            for k in floats.indices { floats[k].age += dt }
            floats.removeAll { $0.age > 1.1 }
        }
        if !sparks.isEmpty {
            let drag = exp(-3.2 * dt)
            for k in sparks.indices {
                sparks[k].age += dt
                sparks[k].x += sparks[k].vx * dt
                sparks[k].y += sparks[k].vy * dt
                sparks[k].vx *= drag
                sparks[k].vy *= drag
            }
            sparks.removeAll { $0.age >= $0.life }
        }
        if !rings.isEmpty {
            for k in rings.indices { rings[k].age += dt }
            rings.removeAll { $0.age > 0.6 }
        }
        let goal = Double(score)
        if shown < goal { shown = Swift.min(goal, shown + Swift.max(90 * dt, (goal - shown) * 7 * dt)) }
    }

    // MARK: Physics

    private func stopped() -> Bool {
        for b in balls where !b.sunk && (b.vx != 0 || b.vy != 0) { return false }
        return true
    }

    private func physics(_ h: Double) {
        let r = T.r
        for i in balls.indices where !balls[i].sunk {
            var b = balls[i]
            if b.vx == 0 && b.vy == 0 { continue }
            b.x += b.vx * h
            b.y += b.vy * h
            let nearCornerX = b.x < T.cornerMouth || b.x > T.w - T.cornerMouth
            let nearCornerY = b.y < T.cornerMouth || b.y > T.h - T.cornerMouth
            let nearSide = abs(b.y - T.h / 2) < T.sideMouth
            if !nearCornerY && !nearSide {
                if b.x < r {
                    b.x = r
                    b.vx = abs(b.vx) * Self.railBounce
                    b.vy *= 0.96
                } else if b.x > T.w - r {
                    b.x = T.w - r
                    b.vx = -abs(b.vx) * Self.railBounce
                    b.vy *= 0.96
                }
            }
            if !nearCornerX {
                if b.y < r {
                    b.y = r
                    b.vy = abs(b.vy) * Self.railBounce
                    b.vx *= 0.96
                } else if b.y > T.h - r {
                    b.y = T.h - r
                    b.vy = -abs(b.vy) * Self.railBounce
                    b.vx *= 0.96
                }
            }
            balls[i] = b
        }

        let reach = 2 * r
        let count = balls.count
        for i in 0..<count where !balls[i].sunk {
            for j in (i + 1)..<count where !balls[j].sunk {
                let dx = balls[j].x - balls[i].x
                let dy = balls[j].y - balls[i].y
                let d2 = dx * dx + dy * dy
                if d2 >= reach * reach || d2 < 1e-9 { continue }
                let d = d2.squareRoot()
                let nx = dx / d
                let ny = dy / d
                let push = (reach - d) / 2
                balls[i].x -= nx * push
                balls[i].y -= ny * push
                balls[j].x += nx * push
                balls[j].y += ny * push
                let closing = (balls[i].vx - balls[j].vx) * nx + (balls[i].vy - balls[j].vy) * ny
                if closing <= 0 { continue }
                let impulse = closing * (1 + Self.ballBounce) / 2
                balls[i].vx -= impulse * nx
                balls[i].vy -= impulse * ny
                balls[j].vx += impulse * nx
                balls[j].vy += impulse * ny
                if i == 0 && firstHit == 0 { firstHit = balls[j].number }
                if closing > 70 && clickCool <= 0 {
                    clickCool = 0.05
                    owe(.click)
                }
            }
        }

        for i in balls.indices where !balls[i].sunk {
            let b = balls[i]
            var into = -1
            for p in 0..<6 {
                let dx = b.x - T.pocketX[p]
                let dy = b.y - T.pocketY[p]
                if dx * dx + dy * dy < T.pocketR[p] * T.pocketR[p] {
                    into = p
                    break
                }
            }
            if into < 0 && (b.x < -14 || b.x > T.w + 14 || b.y < -14 || b.y > T.h + 14) {
                // Through a mouth and off the felt: it went down the nearest pocket.
                var best = 1e9
                for p in 0..<6 {
                    let dx = b.x - T.pocketX[p]
                    let dy = b.y - T.pocketY[p]
                    if dx * dx + dy * dy < best {
                        best = dx * dx + dy * dy
                        into = p
                    }
                }
            }
            if into >= 0 { drop(i, into) }
        }

        for i in balls.indices where !balls[i].sunk {
            let vx = balls[i].vx
            let vy = balls[i].vy
            if vx == 0 && vy == 0 { continue }
            let speed = (vx * vx + vy * vy).squareRoot()
            let next = speed - Self.rollDrag * h - Self.airDrag * speed * h
            if next < Self.stopSpeed {
                balls[i].vx = 0
                balls[i].vy = 0
            } else {
                balls[i].vx = vx / speed * next
                balls[i].vy = vy / speed * next
            }
        }
    }

    private func drop(_ i: Int, _ p: Int) {
        balls[i].sunk = true
        balls[i].vx = 0
        balls[i].vy = 0
        balls[i].sinkAge = 0
        balls[i].pocket = p
        let n = balls[i].number
        potted.append(n)
        let px = T.pocketX[p]
        let py = T.pocketY[p]
        if n == 0 {
            owe(.foul)
            return
        }
        if rings.count >= 6 { rings.removeFirst() }
        rings.append(CornerPocketRing(x: px, y: py, age: 0))
        burst(px, py, tint: n)
        owe(.pot)

        // Points go to the player for their own balls, the moment they drop.
        guard turn == 0, n != 8 else { return }
        let mine = !versus || groups[0] == 0 || T.group(n) == groups[0]
        if !mine { return }
        playerPotsThisShot += 1
        sunkByPlayer += 1
        let points = 100 * playerPotsThisShot + 50 * Swift.min(run, 4)
        addPoints(points, at: px, py)
    }

    private func addPoints(_ points: Int, at x: Double, _ y: Double) {
        score += points
        sinceScore = 0
        if floats.count >= 6 { floats.removeFirst() }
        floats.append(CornerPocketFloat(x: x, y: y, text: "+\(points)", age: 0))
    }

    private func burst(_ x: Double, _ y: Double, tint: Int) {
        for k in 0..<14 {
            if sparks.count >= 90 { sparks.removeFirst() }
            let a = fx.range(0, 2 * Double.pi)
            let speed = fx.range(60, 200)
            sparks.append(CornerPocketSpark(x: x, y: y, vx: cos(a) * speed, vy: sin(a) * speed,
                                            age: 0, life: fx.range(0.45, 0.85), tint: k % 3 == 0 ? 0 : tint))
        }
    }

    private func say(_ word: String) {
        praise = word
        praiseAge = 0
    }

    // MARK: Rules

    private func settleShot() {
        for i in balls.indices {
            balls[i].vx = 0
            balls[i].vy = 0
        }
        let shooter = turn
        let scratch = balls[0].sunk
        let eight = potted.contains(8)
        var objects = 0
        for n in potted where n != 0 && n != 8 { objects += 1 }

        var wrongFirst = firstHit == 0
        if versus && firstHit != 0 {
            if shotGroup == 0 {
                wrongFirst = firstHit == 8
            } else if shotGroupLeft > 0 {
                wrongFirst = T.group(firstHit) != shotGroup
            } else {
                wrongFirst = firstHit != 8
            }
        }
        let foul = scratch || wrongFirst

        if eight {
            let cleared = versus ? (groups[shooter] != 0 && left(group: groups[shooter]) == 0) : left(group: 0) == 0
            let clean = cleared && !scratch
            if versus {
                winner = clean ? shooter : 1 - shooter
                if clean && shooter == 0 {
                    addPoints(1000, at: T.w / 2, T.h / 2)
                    say("Perfect")
                    endLine = "You sank the 8 against \(names[1])"
                } else if clean {
                    say("\(names[1]) sank the 8")
                    endLine = "\(names[1]) sank the 8 first"
                } else {
                    say(shooter == 0 ? "Early 8" : "\(names[1]) slipped")
                    endLine = shooter == 0 ? "The 8 dropped too early" : "\(names[1]) dropped the 8 too early"
                }
            } else if clean {
                addPoints(1000, at: T.w / 2, T.h / 2)
                say("Table clear")
                endLine = "Cleared the whole table"
            } else {
                say("Early 8")
                endLine = "\(sunkByPlayer) balls down before the 8 fell"
            }
            finish(good: versus ? winner == 0 : clean)
            return
        }

        if scratch { respot() }

        if !versus {
            if foul || objects == 0 {
                lives -= 1
                run = 0
                owe(.foul)
                if lives <= 0 {
                    endLine = sunkByPlayer == 1 ? "1 ball down" : "\(sunkByPlayer) balls down"
                    say("Out of misses")
                    finish(good: false)
                    return
                }
                status = scratch ? "Scratch. One miss gone" : "One miss gone"
            } else {
                run += 1
                cheer(objects)
                status = left(group: 0) == 0 ? "Now the 8" : ""
            }
            stage = .aiming
            return
        }

        if groups[shooter] == 0 && !foul {
            if let n = potted.first(where: { $0 != 0 && $0 != 8 }) {
                groups[shooter] = T.group(n)
                groups[1 - shooter] = 3 - T.group(n)
            }
        }
        var own = 0
        for n in potted where n != 0 && n != 8 && T.group(n) == groups[shooter] { own += 1 }
        let keep = !foul && own > 0

        if shooter == 0 && keep { cheer(own) }
        if keep {
            run += shooter == 0 ? 1 : 0
            if groups[shooter] != 0 && left(group: groups[shooter]) == 0 {
                status = shooter == 0 ? "Now the 8" : "\(names[1]) is on the 8"
            } else {
                status = shooter == 0 ? "Shoot again" : "\(names[1]) shoots again"
            }
        } else {
            run = 0
            turn = 1 - shooter
            if turn == 1 {
                status = foul ? "Foul. \(names[1]) shoots" : "\(names[1]) is shooting"
                if foul { owe(.foul) }
            } else {
                status = foul ? "\(names[1]) fouled. Your shot" : "Your shot"
            }
        }

        if shots >= Self.shotCap {
            let mine = left(group: groups[0])
            let theirs = left(group: groups[1])
            winner = mine <= theirs ? 0 : 1
            endLine = winner == 0 ? "Fewer balls left than \(names[1])" : "\(names[1]) had fewer balls left"
            say(winner == 0 ? "Yours" : "\(names[1]) took it")
            finish(good: winner == 0)
            return
        }
        thinkClock = 0
        friendPlan = nil
        stage = .aiming
    }

    private func cheer(_ pots: Int) {
        if pots >= 3 {
            say("Great")
            owe(.good)
        } else if pots == 2 {
            say("Double")
            owe(.good)
        } else if run >= 3 {
            say("On a roll")
            owe(.good)
        } else if run == 2 {
            say("Nice")
        }
    }

    private func respot() {
        var x = T.headX
        let y = T.headY
        for _ in 0..<12 {
            var clear = true
            for b in balls.dropFirst() where !b.sunk {
                let dx = b.x - x
                let dy = b.y - y
                if dx * dx + dy * dy < 4 * T.r * T.r * 1.1 {
                    clear = false
                    break
                }
            }
            if clear { break }
            x += x >= T.headX ? 24 : -24
            if x > T.w - T.r { x = T.headX - 24 }
        }
        balls[0] = CornerPocketBall(number: 0, x: x, y: y)
    }

    private func finish(good: Bool) {
        stage = .ending
        endClock = 0
        status = ""
        owe(good ? .won : .foul)
    }

    // MARK: The friend

    private func think(_ dt: Double) {
        thinkClock += dt
        if friendPlan == nil {
            var plan = choosePlan(side: 1, eightOnly: false)
            plan.angle += (rng.next() + rng.next() - 1) * 0.03
            friendPlan = plan
            friendFrom = aimAngle
        }
        guard let plan = friendPlan else { return }
        let k = thinkClock / Self.thinkLength
        aimAngle = friendFrom + M.turn(from: friendFrom, to: plan.angle) * M.smooth(0.1, 0.62, k)
        pull = plan.power * M.smooth(0.66, 0.94, k)
        if thinkClock >= Self.thinkLength {
            friendPlan = nil
            shoot(plan)
        }
    }

    /// The best shot a careful player would see: a ball it may hit, a pocket with a clear path, and
    /// the least cut. With nothing clear it rolls into the nearest ball it may hit.
    func choosePlan(side: Int, eightOnly: Bool) -> CornerPocketPlan {
        let cue = balls[0]
        if shots == 0 {
            let apex = balls[1]
            return CornerPocketPlan(angle: atan2(apex.y - cue.y, apex.x - cue.x), power: 1)
        }
        var best = -1.0
        var plan = CornerPocketPlan(angle: aimAngle, power: 0.4)
        var nearest = 1e9
        for i in 1..<balls.count where !balls[i].sunk {
            let n = balls[i].number
            let allowed = eightOnly ? n == 8 : legal(n, side: side)
            if !allowed { continue }
            let t = balls[i]
            let fx = t.x - cue.x
            let fy = t.y - cue.y
            let fd = (fx * fx + fy * fy).squareRoot()
            if fd < nearest {
                nearest = fd
                if best < 0 { plan = CornerPocketPlan(angle: atan2(fy, fx), power: 0.5) }
            }
            for p in 0..<6 {
                var ox = T.aimX[p] - t.x
                var oy = T.aimY[p] - t.y
                let d2 = (ox * ox + oy * oy).squareRoot()
                if d2 < 1 { continue }
                ox /= d2
                oy /= d2
                if p >= 4 && abs(oy) > 0.72 { continue }
                let gx = t.x - ox * 2 * T.r
                let gy = t.y - oy * 2 * T.r
                var cx = gx - cue.x
                var cy = gy - cue.y
                let d1 = (cx * cx + cy * cy).squareRoot()
                if d1 < 1 { continue }
                cx /= d1
                cy /= d1
                let cut = cx * ox + cy * oy
                if cut < 0.3 { continue }
                if blocked(cue.x, cue.y, gx, gy, skip: i) { continue }
                if blocked(t.x, t.y, T.aimX[p], T.aimY[p], skip: i) { continue }
                let value = cut * cut / (1 + (d1 + d2) / 650)
                if value <= best { continue }
                best = value
                plan = CornerPocketPlan(angle: atan2(cy, cx), power: power(d1, d2, cut))
            }
        }
        return plan
    }

    private func power(_ d1: Double, _ d2: Double, _ cut: Double) -> Double {
        let objectSpeed = (2 * Self.rollDrag * (d2 + 50)).squareRoot() * 1.3
        let contact = objectSpeed / Swift.max(0.35, cut) / ((1 + Self.ballBounce) / 2)
        let start = (contact * contact + 2 * Self.rollDrag * d1).squareRoot() * 1.2
        return M.clamp((start - Self.minSpeed) / (Self.maxSpeed - Self.minSpeed), 0.14, 1)
    }

    /// Does any ball but the cue ball and the skipped one sit in the way of a ball rolling from a to b?
    private func blocked(_ ax: Double, _ ay: Double, _ bx: Double, _ by: Double, skip: Int) -> Bool {
        let dx = bx - ax
        let dy = by - ay
        let len2 = dx * dx + dy * dy
        if len2 < 1e-6 { return false }
        let room = (2 * T.r - 0.5) * (2 * T.r - 0.5)
        for k in 1..<balls.count where k != skip && !balls[k].sunk {
            let px = balls[k].x - ax
            let py = balls[k].y - ay
            let along = M.clamp((px * dx + py * dy) / len2)
            let qx = px - dx * along
            let qy = py - dy * along
            if qx * qx + qy * qy < room { return true }
        }
        return false
    }
}

// MARK: - Drawing

struct CornerPocketCanvas: View {
    let model: CornerPocketModel
    /// A new number every frame. The model is a class, so this is what makes SwiftUI repaint.
    var frame = 0

    var body: some View {
        Canvas(opaque: true, colorMode: .nonLinear, rendersAsynchronously: false) { context, size in
            if size.width <= 8 || size.height <= 8 { return }
            Self.paint(model, &context, size)
        }
    }

    static func paint(_ model: CornerPocketModel, _ ctx: inout GraphicsContext, _ size: CGSize) {
        typealias Model = CornerPocketModel
        var f = CornerPocketFrame()
        f.balls = model.balls
        f.clock = model.ambient
        let aiming = model.stage == .ready || model.stage == .aiming
        f.showCue = aiming
        f.showGuide = aiming
        f.guideAlpha = model.turn == 0 ? 1 : 0.55
        f.aimAngle = model.aimAngle
        f.pull = model.pull
        f.score = Int(model.shown)
        f.sinceScore = model.sinceScore
        if model.bestScore > 0 { f.bestText = "BEST \(Swift.max(model.bestScore, model.score))" }
        f.names = model.names
        f.groups = model.groups
        f.versus = model.versus
        f.active = model.turn
        f.lives = model.lives
        f.status = model.status
        f.statusPulse = model.stage == .ready
        f.meterPower = model.pull
        f.meterLive = model.playerTurn
        f.praise = model.praise
        f.praiseAge = model.praiseAge
        f.floats = model.floats
        f.sparks = model.sparks
        f.rings = model.rings
        if model.stage == .ending || model.stage == .finished {
            f.dim = CornerPocketMath.smooth(0.9, Model.endLength, model.endClock)
        }
        CornerPocketPainter(size: size, frame: f).draw(&ctx)
    }
}

// MARK: - Scripted player

/// Plays the player's turns for recordings while GameDemo.autopilot is on. It turns the cue,
/// draws it back and lets go through the same calls a finger uses. Its random numbers are its own.
struct CornerPocketPilot {
    static let readyHold = 0.9
    static let aimLength = 1.15

    private var rng: CornerPocketRandom
    private var plan: CornerPocketPlan?
    private var clock = 0.0
    private var from = 0.0

    init(seed: UInt64) {
        rng = CornerPocketRandom(seed: seed, salt: CornerPocketRandom.pilot)
    }

    mutating func drive(_ model: CornerPocketModel, dt: Double) {
        guard model.playerTurn else {
            plan = nil
            return
        }
        if model.stage == .ready && model.ambient < Self.readyHold { return }
        if plan == nil {
            plan = choose(model)
            clock = 0
            from = model.aimAngle
        }
        guard let shot = plan else { return }
        clock += dt
        let k = clock / Self.aimLength
        let turn = CornerPocketMath.turn(from: from, to: shot.angle)
        model.aim(angle: from + turn * CornerPocketMath.smooth(0.08, 0.55, k))
        if k > 0.58 { model.setPull(shot.power * CornerPocketMath.smooth(0.58, 0.92, k)) }
        if k >= 1 {
            model.setPull(shot.power)
            model.release()
            plan = nil
        }
    }

    private mutating func choose(_ model: CornerPocketModel) -> CornerPocketPlan {
        if let limit = GameDemo.loseAfter, model.time >= limit {
            if model.versus { return model.choosePlan(side: 0, eightOnly: true) }
            // A soft tap into open felt: nothing drops and a miss is gone.
            return CornerPocketPlan(angle: model.aimAngle + Double.pi, power: 0.05)
        }
        var shot = model.choosePlan(side: 0, eightOnly: false)
        shot.angle += (rng.next() - 0.5) * 0.008
        return shot
    }
}

// MARK: - Game view

/// Holds the round between frames. Nothing is published: the timeline repaints every frame anyway.
final class CornerPocketRunner: ObservableObject {
    let model: CornerPocketModel
    private let seed: UInt64
    private var lastDate: Date?
    private var frame = 0
    private var reported = false
    private var pilot: CornerPocketPilot?
    /// The size of the view, for turning touches into table units.
    var size = CGSize(width: 402, height: 874)
    /// 0 none, 1 aiming on the felt, 2 pulling the meter, 3 a slingshot from the cue ball.
    private var touchMode = 0

    init(options: GameOptions) {
        model = CornerPocketModel(options: options)
        seed = options.seed
    }

    func advance(to date: Date, link: GameLink) -> Int {
        if link.paused {
            lastDate = nil
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
                pilot?.drive(model, dt: dt)
            }
            settle(link)
        }
        frame &+= 1
        return frame
    }

    func touch(start: CGPoint, at point: CGPoint, link: GameLink) {
        if link.paused || link.isFinished || GameDemo.autopilot { return }
        guard model.playerTurn else { return }
        let L = CornerPocketLayout(size: size)
        if touchMode == 0 {
            let cue = model.balls[0]
            let cx = L.sx(cue.x) - Double(start.x)
            let cy = L.sy(cue.y) - Double(start.y)
            if Double(start.x) >= L.meterHitX {
                touchMode = 2
            } else if cx * cx + cy * cy < 34 * L.u * 34 * L.u {
                touchMode = 3
            } else {
                touchMode = 1
            }
            GameHaptics.tap()
        }
        switch touchMode {
        case 1:
            model.aim(at: (Double(point.x) - L.ox) / L.s, (Double(point.y) - L.oy) / L.s)
        case 2:
            model.setPull(Double(point.y - start.y) / (L.meterH * 0.85))
        case 3:
            let dx = Double(start.x - point.x)
            let dy = Double(start.y - point.y)
            let length = (dx * dx + dy * dy).squareRoot()
            if length > 12 * L.u {
                model.aim(angle: atan2(dy, dx))
                model.setPull((length - 12 * L.u) / (170 * L.u))
            }
        default:
            break
        }
        settle(link)
    }

    func lift(link: GameLink) {
        if touchMode == 2 || touchMode == 3 { model.release() }
        touchMode = 0
        settle(link)
    }

    private func settle(_ link: GameLink) {
        switch model.takeFeedback() {
        case .won:
            GameHaptics.heavy()
            GameHaptics.success()
        case .foul: GameHaptics.fail()
        case .good: GameHaptics.success()
        case .pot: GameHaptics.thud()
        case .strike: GameHaptics.thud()
        case .click: GameHaptics.tap()
        case .none: break
        }
        if model.stage == .finished, !reported {
            reported = true
            let result = model.result
            DispatchQueue.main.async { link.finish(result) }
        }
    }
}

public struct CornerPocketGame: View {
    private let options: GameOptions
    private let link: GameLink

    public init(options: GameOptions, link: GameLink) {
        self.options = options
        self.link = link
    }

    public var body: some View {
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
        GeometryReader { proxy in
            TimelineView(.animation(minimumInterval: nil, paused: link.paused)) { timeline in
                CornerPocketCanvas(model: runner.model, frame: tick(timeline.date, proxy.size))
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in runner.touch(start: value.startLocation, at: value.location, link: link) }
                    .onEnded { _ in runner.lift(link: link) }
            )
        }
        .ignoresSafeArea()
        .accessibilityElement()
        .accessibilityLabel("Corner Pocket. Drag to aim, pull the power meter down and let go to shoot.")
        .accessibilityAddTraits(.allowsDirectInteraction)
    }

    private func tick(_ date: Date, _ size: CGSize) -> Int {
        runner.size = size
        return runner.advance(to: date, link: link)
    }
}
