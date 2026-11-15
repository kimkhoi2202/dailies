import SwiftUI

// Brick Out, playable.
//
// BrickOutModel   the rules of a round in plain Swift: step(dt:), press, fling and the boosters.
// BrickOutCanvas  paints one frame of the model with BrickOutPainter (in BrickOutScene.swift).
// BrickOutPilot   the scripted player. It only runs while GameDemo.autopilot is on.
// BrickOutRunner  keeps the clock, turns touches into moves, fires haptics, reports the result.
// BrickOutGame    the view the app shows.

// MARK: - Model

final class BrickOutModel {
    enum Stage { case ready, playing, clearing, ending, finished }

    /// What the last step or move deserves as a haptic. A stronger one replaces a weaker one.
    enum Feedback: Int { case none, slide, bump, exit, smash, praise, clear, timeUp }

    struct Friend {
        let name: String
        let pace: Double
        var score: Int
        var wait: Double
    }

    static let startClock = 60.0
    static let clearAdds = 15.0
    static let freezeLength = 8.0
    static let comboWindow = 2.4
    static let clearPause = 1.15
    static let endLength = 1.7
    static let slideSpeed = 24.0
    static let exitLength = 0.5
    static let sparkPool = 180

    let solo: Bool
    let bestScore: Int
    private let seed: UInt64
    /// Set by the runner once the view has a size. Effects need it to know where things are.
    var layout: BrickOutLayout?

    private(set) var stage = Stage.ready
    private(set) var stageAge = 0.0
    private(set) var level = 1
    private(set) var gates: [BrickOutGate] = []
    private(set) var bricks: [BrickOutBrick] = []
    private(set) var sparks: [BrickOutSpark]
    private var sparkNext = 0
    private(set) var floaters: [BrickOutFloater] = []

    private(set) var score = 0
    private(set) var shownScore = 0.0
    private(set) var clock = BrickOutModel.startClock
    private(set) var frozen = 0.0
    /// Round clock: seconds of play since the first move.
    private(set) var time = 0.0
    /// Scenery clock: runs whenever the game is not paused.
    private(set) var ambient = 0.0
    private(set) var boardsCleared = 0
    private(set) var bricksOut = 0
    private(set) var combo = 0
    private var sinceExit = 99.0
    private(set) var praise: String?
    private(set) var praiseAge = 0.0
    private(set) var boosters = [1, 1, 1]
    /// The booster waiting for a brick (only the hammer does), or -1.
    private(set) var armed = -1
    private(set) var friends: [Friend] = []
    private var friendRng: BrickOutRandom
    private var shuffles = 0
    /// Seconds since the player last moved a brick.
    private(set) var idle = 0.0
    /// A brick that can go out now, and the side it goes out through. -1 when none.
    private(set) var hintBrick = -1
    private(set) var hintSide = 0
    private var hintAge = 9.0
    private var lastTick = 99
    private var ranOut = false
    private var feedback = Feedback.none
    /// Everything the HUD draws, kept here so a frame builds no arrays.
    private(set) var hud = BrickOutHUD()

    init(options: GameOptions) {
        solo = options.solo
        bestScore = Swift.max(0, options.bestScore)
        seed = options.seed
        sparks = Array(repeating: BrickOutSpark(), count: Self.sparkPool)
        friendRng = BrickOutRandom(seed: options.seed, salt: BrickOutRandom.friends)
        floaters.reserveCapacity(16)
        if !options.solo {
            for name in options.friendNames.filter({ !$0.isEmpty }).prefix(3) {
                let pace = friendRng.range(0.75, 1.35)
                friends.append(Friend(name: name, pace: pace, score: 0, wait: friendRng.range(1.5, 3.5)))
                hud.friends.append(BrickOutFriendChip(name: name, score: 0))
            }
        }
        hud.best = bestScore
        deal()
        refreshHint()
    }

    // MARK: Reading

    var bricksLeft: Int {
        var n = 0
        for b in bricks where b.onBoard { n += 1 }
        return n
    }

    var result: GameResult {
        let line: String
        if boardsCleared > 0 {
            line = boardsCleared == 1 ? "1 board cleared" : "\(boardsCleared) boards cleared"
        } else {
            line = bricksOut == 1 ? "1 brick out" : "\(bricksOut) bricks out"
        }
        guard !friends.isEmpty else { return GameResult(score: score, unit: "points", detail: line) }
        let ahead = friends.filter { $0.score > score }.count
        return GameResult(score: score, unit: "points", detail: line, placement: 1 + ahead, playerCount: friends.count + 1)
    }

    /// Hands over the haptic owed since the last call.
    func takeFeedback() -> Feedback {
        let owed = feedback
        feedback = .none
        return owed
    }

    private func owe(_ kind: Feedback) {
        if kind.rawValue > feedback.rawValue { feedback = kind }
    }

    private var live: Bool { stage == .ready || stage == .playing }

    // MARK: Dealing

    private func deal() {
        var rng = BrickOutRandom(seed: seed &+ UInt64(level) &* 7919 &+ UInt64(shuffles) &* 104_729, salt: BrickOutRandom.deal)
        gates = BrickOutDeal.gates(level: level, rng: &rng)
        bricks = BrickOutDeal.bricks(level: level, count: BrickOutDeal.count(level: level), gates: gates, rng: &rng)
        popIn()
    }

    private func popIn() {
        for k in bricks.indices { bricks[k].appear = -0.035 * Double(k) }
        hintAge = 9
    }

    // MARK: Input

    private func begin() {
        if stage == .ready { stage = .playing }
    }

    /// A finger lands on a cell. Returns the brick it holds, if any.
    func press(col: Int, row: Int) -> Int? {
        guard live else { return nil }
        var hit: Int?
        for k in bricks.indices where bricks[k].onBoard {
            let b = bricks[k]
            if col >= b.col && col < b.col + b.w && row >= b.row && row < b.row + b.h { hit = k }
        }
        guard let i = hit else {
            armed = -1
            return nil
        }
        if armed == 1 {
            smash(i)
            return nil
        }
        bricks[i].held = true
        return i
    }

    func pressOutside() {
        armed = -1
    }

    func release() {
        for k in bricks.indices where bricks[k].held { bricks[k].held = false }
    }

    /// Sends a brick toward a side. It slides until something stops it, or out through its gate.
    func fling(_ i: Int, side: Int) {
        guard live, bricks.indices.contains(i), bricks[i].onBoard else { return }
        begin()
        idle = 0
        armed = -1
        bricks[i].held = false
        let move = BrickOutRules.travel(bricks, i, side: side, gates: gates)
        let d = BrickOutRules.step(side)
        if let g = move.gate {
            bricks[i].exitSide = side
            bricks[i].gate = g
            bricks[i].exitAge = 0
            owe(.slide)
        } else if move.steps == 0 {
            bricks[i].bumpAge = 0
            bricks[i].bumpSide = side
            owe(.bump)
        } else {
            bricks[i].col += d.dx * move.steps
            bricks[i].row += d.dy * move.steps
            owe(.slide)
        }
        hintAge = 9
    }

    func useBooster(_ k: Int) {
        guard live, boosters.indices.contains(k) else { return }
        if k == 1 && armed == 1 {
            armed = -1
            owe(.slide)
            return
        }
        guard boosters[k] > 0 else {
            owe(.bump)
            return
        }
        begin()
        idle = 0
        switch k {
        case 0:
            boosters[0] -= 1
            frozen = Self.freezeLength
            if let L = layout { floaters.append(BrickOutFloater(x: L.W * 0.5, y: L.timerY + 40 * L.u, text: "Frozen", color: -1)) }
            owe(.praise)
        case 1:
            armed = 1
            owe(.slide)
        default:
            boosters[2] -= 1
            shuffle()
            owe(.exit)
        }
    }

    private func shuffle() {
        armed = -1
        let left = bricksLeft
        if left == 0 { return }
        shuffles += 1
        if let L = layout {
            for b in bricks where b.onBoard {
                let x = L.gridX + (b.x + Double(b.w) * 0.5) * L.cell
                let y = L.gridY + (b.y + Double(b.h) * 0.5) * L.cell
                burst(x: x, y: y, dx: 0, dy: -1, color: b.color, count: 3, spread: Double.pi, speed: 160 * L.u)
            }
        }
        var rng = BrickOutRandom(seed: seed &+ UInt64(level) &* 7919 &+ UInt64(shuffles) &* 104_729, salt: BrickOutRandom.deal)
        bricks = BrickOutDeal.bricks(level: level, count: left, gates: gates, rng: &rng)
        popIn()
    }

    private func smash(_ i: Int) {
        armed = -1
        boosters[1] -= 1
        let b = bricks[i]
        bricks[i].exitSide = 9
        bricks[i].gate = -1
        bricks[i].appear = 0
        let points = 5 * b.w * b.h
        add(points)
        bricksOut += 1
        if let L = layout {
            let x = L.gridX + (b.x + Double(b.w) * 0.5) * L.cell
            let y = L.gridY + (b.y + Double(b.h) * 0.5) * L.cell
            burst(x: x, y: y, dx: 0, dy: -1, color: b.color, count: 26, spread: Double.pi, speed: 300 * L.u)
            floaters.append(BrickOutFloater(x: x, y: y, text: "+\(points)", color: b.color))
        }
        idle = 0
        owe(.smash)
        hintAge = 9
    }

    /// The scripted player's way to lose: the clock is nearly out and nothing more goes out.
    func runOut() {
        if ranOut || stage != .playing { return }
        ranOut = true
        frozen = 0
        clock = Swift.min(clock, 2.2)
    }

    // MARK: Clock

    func step(dt raw: Double) {
        let dt = Swift.min(Swift.max(raw, 0), 1.0 / 30)
        if dt <= 0 { return }
        ambient += dt
        if stage == .finished { return }
        stageAge += dt
        moveBricks(dt)
        stepEffects(dt)

        switch stage {
        case .ready:
            break
        case .playing:
            time += dt
            idle += dt
            sinceExit += dt
            if frozen > 0 {
                frozen = Swift.max(0, frozen - dt)
            } else {
                clock -= dt
            }
            stepFriends(dt)
            let whole = Int(ceil(clock))
            if whole <= 5 && whole >= 1 && whole < lastTick { owe(.slide) }
            lastTick = whole
            if clock <= 0 {
                clock = 0
                stage = .ending
                stageAge = 0
                praise = "Time"
                praiseAge = 0
                release()
                armed = -1
                owe(.timeUp)
            } else if bricksLeft == 0 && !anyLeaving {
                clearBoard()
            }
        case .clearing:
            stepFriends(dt)
            if stageAge >= Self.clearPause {
                level += 1
                deal()
                stage = .playing
                stageAge = 0
            }
        case .ending:
            if stageAge >= Self.endLength { stage = .finished }
        case .finished:
            break
        }

        hintAge += dt
        if hintAge > 0.3 { refreshHint() }
        refreshHUD(dt)
    }

    private var anyLeaving: Bool {
        for b in bricks where b.gate >= 0 { return true }
        return false
    }

    private func moveBricks(_ dt: Double) {
        let reach = Self.slideSpeed * dt
        for k in bricks.indices {
            if bricks[k].appear < 1 && (bricks[k].onBoard || bricks[k].exitSide != 9) {
                bricks[k].appear = Swift.min(1, bricks[k].appear + dt / 0.3)
            }
            bricks[k].bumpAge += dt
            bricks[k].landAge += dt
            if bricks[k].onBoard {
                let tx = Double(bricks[k].col)
                let ty = Double(bricks[k].row)
                let dx = tx - bricks[k].x
                let dy = ty - bricks[k].y
                let dist = abs(dx) + abs(dy)
                if dist > 0 {
                    if dist <= reach {
                        bricks[k].x = tx
                        bricks[k].y = ty
                        bricks[k].landAge = 0
                    } else {
                        bricks[k].x += dx / dist * reach
                        bricks[k].y += dy / dist * reach
                    }
                }
                continue
            }
            if bricks[k].exitSide > 3 { continue }
            let d = BrickOutRules.step(bricks[k].exitSide)
            bricks[k].x += Double(d.dx) * reach * 1.15
            bricks[k].y += Double(d.dy) * reach * 1.15
            if bricks[k].gate >= 0 && reachedEdge(bricks[k]) { leave(k) }
            if bricks[k].gate < 0 {
                bricks[k].exitAge += dt
                if bricks[k].exitAge >= Self.exitLength { bricks[k].appear = 0 }
            }
        }
    }

    private func reachedEdge(_ b: BrickOutBrick) -> Bool {
        switch b.exitSide {
        case 0: return b.y <= -0.15
        case 1: return b.x + Double(b.w) >= Double(BrickOutRules.cols) + 0.15
        case 2: return b.y + Double(b.h) >= Double(BrickOutRules.rows) + 0.15
        default: return b.x <= -0.15
        }
    }

    /// A brick reaches its gate: points, a burst, maybe a praise word.
    private func leave(_ k: Int) {
        let b = bricks[k]
        let g = b.gate
        bricks[k].gate = -1
        bricks[k].exitAge = 0
        gates[g].flash = 0
        combo = sinceExit < Self.comboWindow ? combo + 1 : 1
        sinceExit = 0
        let points = 10 * b.w * b.h + 10 * (combo - 1)
        add(points)
        bricksOut += 1
        owe(.exit)
        switch combo {
        case 2: say("Nice")
        case 3: say("Great")
        case 4: say("Superb")
        case 5...: say("On fire")
        default: break
        }
        guard let L = layout else { return }
        let gc = L.gateCenter(gates[g])
        burst(x: gc.x, y: gc.y, dx: gc.dx, dy: gc.dy, color: b.color, count: 18, spread: 1.2, speed: 260 * L.u)
        floaters.append(BrickOutFloater(x: gc.x - gc.dx * 44 * L.u, y: gc.y - gc.dy * 44 * L.u, text: "+\(points)", color: b.color))
    }

    private func say(_ words: String) {
        praise = words
        praiseAge = 0
        if words != "Nice" { owe(.praise) }
    }

    private func add(_ points: Int) {
        score += points
        hud.scorePop = 0
    }

    private func clearBoard() {
        stage = .clearing
        stageAge = 0
        boardsCleared += 1
        let points = 50 * level
        add(points)
        clock += Self.clearAdds
        say("Board clear")
        owe(.clear)
        guard let L = layout else { return }
        let cx = L.W * 0.5
        let cy = L.gridY + L.boardH * 0.5
        burst(x: cx, y: cy, dx: 0, dy: -1, color: -1, count: 22, spread: Double.pi, speed: 420 * L.u)
        floaters.append(BrickOutFloater(x: cx, y: cy + 50 * L.u, text: "+\(points)", color: 1))
        floaters.append(BrickOutFloater(x: L.W * 0.5, y: L.timerY + 40 * L.u, text: "+15s", color: -1))
    }

    private func burst(x: Double, y: Double, dx: Double, dy: Double, color: Int, count: Int, spread: Double, speed: Double) {
        var rng = BrickOutRandom(seed: UInt64(sparkNext) &+ UInt64(bricksOut) &* 31, salt: BrickOutRandom.sparks)
        let base = atan2(dy, dx)
        for _ in 0..<count {
            let a = base + rng.range(-spread, spread)
            let v = speed * rng.range(0.45, 1.1)
            var s = BrickOutSpark()
            s.x = x
            s.y = y
            s.vx = cos(a) * v
            s.vy = sin(a) * v
            s.age = 0
            s.life = rng.range(0.5, 0.95)
            s.size = rng.range(5, 11) * (layout?.u ?? 1) * (color < 0 ? 1.5 : 1)
            s.spin = rng.range(0, 6)
            s.color = color
            sparks[sparkNext] = s
            sparkNext = (sparkNext + 1) % Self.sparkPool
        }
    }

    private func stepEffects(_ dt: Double) {
        let gravity = 900 * (layout?.u ?? 1)
        for k in sparks.indices where sparks[k].alive {
            sparks[k].age += dt
            sparks[k].vy += gravity * dt
            sparks[k].vx *= 1 - 1.5 * dt
            sparks[k].x += sparks[k].vx * dt
            sparks[k].y += sparks[k].vy * dt
        }
        for k in floaters.indices { floaters[k].age += dt }
        if let first = floaters.first, first.age > 1 { floaters.removeAll { $0.age > 1 } }
        for k in gates.indices { gates[k].flash += dt }
        if praise != nil {
            praiseAge += dt
            if praiseAge > 1.1 && stage != .ending { praise = nil }
        }
    }

    private func stepFriends(_ dt: Double) {
        for k in friends.indices {
            friends[k].wait -= dt
            if friends[k].wait > 0 { continue }
            friends[k].score += 10 * friendRng.int(2...3) + (friendRng.next() < 0.08 ? 50 : 0)
            friends[k].wait = friendRng.range(2.0, 4.0) / friends[k].pace
        }
    }

    /// Finds a brick that can go out right now, newest of the deal first.
    private func refreshHint() {
        hintAge = 0
        hintBrick = -1
        var best = -1
        for k in bricks.indices where bricks[k].onBoard && bricks[k].order > best {
            for side in 0..<4 where BrickOutRules.travel(bricks, k, side: side, gates: gates).gate != nil {
                hintBrick = k
                hintSide = side
                best = bricks[k].order
                break
            }
        }
    }

    private func refreshHUD(_ dt: Double) {
        let target = Double(score)
        if shownScore < target {
            shownScore = Swift.min(target, shownScore + Swift.max(40 * dt, (target - shownScore) * 9 * dt))
        }
        hud.score = Int(shownScore.rounded(.down))
        hud.scorePop += dt
        hud.clock = clock
        hud.frozen = frozen
        hud.level = level
        hud.left = bricksLeft
        for k in 0..<3 where hud.boosters[k] != boosters[k] { hud.boosters[k] = boosters[k] }
        hud.armed = armed
        hud.ambient = ambient
        for k in friends.indices where hud.friends[k].score != friends[k].score { hud.friends[k].score = friends[k].score }
    }
}

// MARK: - Drawing

struct BrickOutCanvas: View {
    let model: BrickOutModel
    /// A new number every frame. The model is a class, so this is what makes SwiftUI repaint.
    var frame = 0

    var body: some View {
        Canvas(opaque: true, colorMode: .nonLinear, rendersAsynchronously: false) { context, size in
            if size.width <= 8 || size.height <= 8 { return }
            Self.paint(model, &context, size)
        }
    }

    static func paint(_ model: BrickOutModel, _ ctx: inout GraphicsContext, _ size: CGSize) {
        let painter = BrickOutPainter(size: size)
        let ambient = model.ambient
        painter.drawBackground(&ctx, ambient: ambient)
        painter.drawBoard(&ctx, gates: model.gates, ambient: ambient)
        let guide = model.stage == .ready || (model.stage == .playing && model.idle > 4)
        let hint = guide ? model.hintBrick : -1
        painter.drawBricks(&ctx, model.bricks, hint: hint, ambient: ambient)
        if hint >= 0 && model.armed < 0 {
            painter.drawSwipeGuide(&ctx, model.bricks[hint], side: model.hintSide, ambient: ambient)
        }
        painter.drawSparks(&ctx, model.sparks)
        painter.drawFloaters(&ctx, model.floaters)
        if model.stage == .ending || model.stage == .finished {
            let k = BrickOutMath.smooth(0, 0.5, model.stageAge)
            ctx.fill(Path(painter.L.gridRect.insetBy(dx: -painter.L.frame, dy: -painter.L.frame)),
                     with: .color(BrickOutInk.shadow.opacity(0.35 * k)))
            painter.drawPraise(&ctx, "Time", age: Swift.min(model.stageAge, 0.5))
        } else if let words = model.praise {
            painter.drawPraise(&ctx, words, age: model.praiseAge)
        }
        painter.drawHUD(&ctx, model.hud)
        painter.drawBoosters(&ctx, model.hud)

        let pulse = 0.5 + 0.5 * sin(ambient * 3.2)
        if model.stage == .ready {
            painter.drawHint(&ctx, "Swipe each brick out through its gate", pulse: pulse)
        } else if model.armed == 1 {
            painter.drawHint(&ctx, "Tap a brick to break it", pulse: pulse)
        } else if model.stage == .playing && model.idle > 4 && model.hintBrick < 0 && model.boosters[1] + model.boosters[2] > 0 {
            painter.drawHint(&ctx, "Stuck? Try the hammer or a shuffle", pulse: pulse)
        }
    }
}

// MARK: - Scripted player

/// Plays the round for recordings while GameDemo.autopilot is on. Its moves go through the same
/// calls a finger uses, and its random numbers are its own.
struct BrickOutPilot {
    enum Move {
        case fling(Int, Int)
        case booster(Int)
        case press(Int, Int)
    }

    private var rng: BrickOutRandom
    private var wait = 1.1

    init(seed: UInt64) {
        rng = BrickOutRandom(seed: seed, salt: BrickOutRandom.pilot)
    }

    mutating func move(_ m: BrickOutModel, dt: Double) -> Move? {
        guard m.stage == .ready || m.stage == .playing else { return nil }
        if let limit = GameDemo.loseAfter, m.time >= limit { return nil }
        wait -= dt
        if wait > 0 { return nil }
        wait = rng.range(0.42, 0.8)

        if m.armed == 1 {
            for b in m.bricks where b.onBoard { return .press(b.col, b.row) }
        }
        if m.time > 14 && m.boosters[0] > 0 && rng.next() < 0.3 { return .booster(0) }
        if m.hintBrick >= 0 { return .fling(m.hintBrick, m.hintSide) }
        if m.boosters[2] > 0 { return .booster(2) }
        if m.boosters[1] > 0 { return .booster(1) }
        var choices: [Int] = []
        for k in m.bricks.indices where m.bricks[k].onBoard { choices.append(k) }
        guard !choices.isEmpty else { return nil }
        return .fling(choices[rng.int(0...(choices.count - 1))], rng.int(0...3))
    }
}

// MARK: - Game view

/// Holds the round between frames. Nothing is published: the timeline repaints every frame anyway.
final class BrickOutRunner: ObservableObject {
    let model: BrickOutModel
    private let seed: UInt64
    private var lastDate: Date?
    private var frame = 0
    private var reported = false
    private var pilot: BrickOutPilot?
    private var size = CGSize.zero
    private var touchStart: CGPoint?
    private var touchBrick: Int?
    private var flung = false

    init(options: GameOptions) {
        model = BrickOutModel(options: options)
        seed = options.seed
    }

    func resize(_ s: CGSize) {
        if s == size || s.width <= 8 || s.height <= 8 { return }
        size = s
        model.layout = BrickOutLayout(size: s)
    }

    /// Brings the model up to the given date. Returns a number that changes when there is a new frame to paint.
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
            if GameDemo.autopilot { drive(dt: dt) }
            settle(link)
        }
        frame &+= 1
        return frame
    }

    private func drive(dt: Double) {
        if pilot == nil { pilot = BrickOutPilot(seed: seed) }
        if let limit = GameDemo.loseAfter, model.time >= limit { model.runOut() }
        guard let move = pilot?.move(model, dt: dt) else { return }
        switch move {
        case let .fling(i, side): model.fling(i, side: side)
        case let .booster(k): model.useBooster(k)
        case let .press(c, r): _ = model.press(col: c, row: r)
        }
    }

    func touch(start: CGPoint, at point: CGPoint, link: GameLink) {
        if link.paused || link.isFinished { return }
        guard let L = model.layout else { return }
        if touchStart != start {
            touchStart = start
            touchBrick = nil
            flung = false
            begin(start, L)
            settle(link)
        }
        guard let i = touchBrick, !flung else { return }
        let dx = Double(point.x - start.x)
        let dy = Double(point.y - start.y)
        if dx * dx + dy * dy < 196 * L.u * L.u { return }
        flung = true
        let side = abs(dx) > abs(dy) ? (dx > 0 ? 1 : 3) : (dy > 0 ? 2 : 0)
        model.fling(i, side: side)
        settle(link)
    }

    private func begin(_ p: CGPoint, _ L: BrickOutLayout) {
        for k in 0..<3 {
            let c = L.boosterCenter(k)
            let dx = Double(p.x - c.x)
            let dy = Double(p.y - c.y)
            if abs(dx) < L.boosterSize * 0.62 && abs(dy) < L.boosterSize * 0.62 {
                GameHaptics.tap()
                model.useBooster(k)
                return
            }
        }
        guard let cell = L.cell(at: p) else {
            model.pressOutside()
            return
        }
        let before = model.boosters[1]
        touchBrick = model.press(col: cell.col, row: cell.row)
        if touchBrick != nil || model.boosters[1] != before { GameHaptics.tap() }
    }

    func touchEnded(link: GameLink) {
        touchStart = nil
        touchBrick = nil
        model.release()
    }

    /// Plays the haptic the model owes and reports the round once it is over.
    private func settle(_ link: GameLink) {
        switch model.takeFeedback() {
        case .timeUp: GameHaptics.fail()
        case .clear:
            GameHaptics.heavy()
            GameHaptics.success()
        case .praise: GameHaptics.success()
        case .smash: GameHaptics.heavy()
        case .exit, .bump: GameHaptics.thud()
        case .slide: GameHaptics.tap()
        case .none: break
        }
        if model.stage == .finished, !reported {
            reported = true
            let result = model.result
            DispatchQueue.main.async { link.finish(result) }
        }
    }
}

public struct BrickOutGame: View {
    private let options: GameOptions
    private let link: GameLink

    public init(options: GameOptions, link: GameLink) {
        self.options = options
        self.link = link
    }

    public var body: some View {
        // A new link is a new round, so the round's state lives and dies with the link.
        BrickOutRound(options: options, link: link)
            .id(ObjectIdentifier(link))
    }
}

private struct BrickOutRound: View {
    @ObservedObject var link: GameLink
    @StateObject private var runner: BrickOutRunner

    init(options: GameOptions, link: GameLink) {
        self.link = link
        _runner = StateObject(wrappedValue: BrickOutRunner(options: options))
    }

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: nil, paused: link.paused)) { timeline in
                let _ = runner.resize(geo.size)
                BrickOutCanvas(model: runner.model, frame: runner.advance(to: timeline.date, link: link))
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { value in runner.touch(start: value.startLocation, at: value.location, link: link) }
                .onEnded { _ in runner.touchEnded(link: link) }
        )
        .onChange(of: link.paused) { _, paused in
            if paused { runner.touchEnded(link: link) }
        }
        .ignoresSafeArea()
        .accessibilityElement()
        .accessibilityLabel("Brick Out. Swipe each brick out through the gate of its own color.")
        .accessibilityAddTraits(.allowsDirectInteraction)
    }
}
