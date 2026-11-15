import SwiftUI

// Pour Party, playable.
//
// PourPartyBoard    the rules of one level in plain Swift: which pours are legal and what they do.
// PourPartyLevels   makes a level by pouring a solved board backwards, so every level can be solved.
// PourPartySolver   finds a way through a level, for the scripted player.
// PourPartyModel    the round: levels in a row against one clock, undo, restart, the animations.
// PourPartyCanvas   paints one frame of the model with the clip's painter.
// PourPartyPilot    the scripted player. It only runs while GameDemo.autopilot is on.
// PourPartyRunner   keeps the clock, turns touches into taps, fires haptics, reports the result.
// PourPartyGame     the view the app shows.

// MARK: - Rules

struct PourPartyMove: Equatable {
    var from: Int
    var to: Int
}

struct PourPartyBoard: Equatable {
    static let capacity = 4

    /// Each tube's colours from the bottom up.
    var tubes: [[Int]]

    /// The colour on top of a tube and how many units of it sit together there. nil for an empty tube.
    func top(_ i: Int) -> (color: Int, count: Int)? {
        let tube = tubes[i]
        guard let color = tube.last else { return nil }
        var count = 0
        var k = tube.count - 1
        while k >= 0, tube[k] == color {
            count += 1
            k -= 1
        }
        return (color, count)
    }

    func isUniform(_ i: Int) -> Bool {
        guard let first = tubes[i].first else { return true }
        for color in tubes[i] where color != first { return false }
        return true
    }

    /// Full of one colour.
    func isDone(_ i: Int) -> Bool { tubes[i].count == Self.capacity && isUniform(i) }

    /// How many units a pour from one tube to another moves. 0 when it is not allowed.
    func pourAmount(from a: Int, to b: Int) -> Int {
        if a == b { return 0 }
        guard let source = top(a) else { return 0 }
        let room = Self.capacity - tubes[b].count
        if room <= 0 { return 0 }
        if let target = top(b), target.color != source.color { return 0 }
        return Swift.min(room, source.count)
    }

    @discardableResult
    mutating func pour(from a: Int, to b: Int) -> Int {
        let n = pourAmount(from: a, to: b)
        if n == 0 { return 0 }
        guard let color = tubes[a].last else { return 0 }
        tubes[a].removeLast(n)
        for _ in 0..<n { tubes[b].append(color) }
        return n
    }

    var isSolved: Bool {
        for i in tubes.indices where !tubes[i].isEmpty && !isDone(i) { return false }
        return true
    }

    var hasMove: Bool {
        for a in tubes.indices {
            for b in tubes.indices where pourAmount(from: a, to: b) > 0 { return true }
        }
        return false
    }

    /// The board as text, the same for any order of the tubes.
    var key: String {
        var parts: [String] = []
        parts.reserveCapacity(tubes.count)
        for tube in tubes {
            var s = ""
            for color in tube { s.append(Character(UnicodeScalar(UInt8(65 + Swift.max(0, Swift.min(25, color)))))) }
            parts.append(s)
        }
        parts.sort()
        return parts.joined(separator: "|")
    }
}

// MARK: - Levels

enum PourPartyLevels {
    static func colors(for level: Int) -> Int { Swift.min(7, 2 + Swift.max(1, level)) }

    static func scrambleMoves(for level: Int) -> Int { Swift.min(40, 8 + 4 * Swift.max(1, level)) }

    /// A level, and one way to solve it: the scramble played backwards.
    ///
    /// The board starts solved and liquid is poured backwards, with a rule that keeps every backwards
    /// pour the exact inverse of a legal forward pour: the target's top colour never matches, and the
    /// source keeps some of the colour or gives all of it. So playing the moves back in reverse order
    /// is a real solution.
    static func make(level: Int, rng: inout PourPartyRandom) -> (board: PourPartyBoard, solution: [PourPartyMove]) {
        let colorCount = colors(for: level)
        var tubes: [[Int]] = []
        for c in 0..<colorCount { tubes.append([c, c, c, c]) }
        tubes.append([])
        tubes.append([])
        var board = PourPartyBoard(tubes: tubes)
        let n = tubes.count
        var steps: [PourPartyMove] = []
        var last: PourPartyMove?
        let wanted = scrambleMoves(for: level)
        var tries = 0
        while (steps.count < wanted || board.isSolved) && tries < wanted * 60 {
            tries += 1
            let a = rng.int(n)
            let b = rng.int(n)
            if a == b { continue }
            if let previous = last, previous.from == b, previous.to == a { continue }
            guard let source = board.top(a) else { continue }
            let room = PourPartyBoard.capacity - board.tubes[b].count
            if room <= 0 { continue }
            if let target = board.top(b), target.color == source.color { continue }
            var most = source.count - 1
            if source.count == board.tubes[a].count { most = source.count }
            most = Swift.min(most, room)
            if most < 1 { continue }
            let k = rng.int(most) + 1
            board.tubes[a].removeLast(k)
            for _ in 0..<k { board.tubes[b].append(source.color) }
            let move = PourPartyMove(from: a, to: b)
            steps.append(move)
            last = move
        }

        // Shuffle the tubes so the colours do not sit in order on the shelf.
        var order = Array(0..<n)
        var k = n - 1
        while k > 0 {
            order.swapAt(k, rng.int(k + 1))
            k -= 1
        }
        var place = Array(repeating: 0, count: n)
        for (slot, old) in order.enumerated() { place[old] = slot }
        var shuffled: [[Int]] = []
        shuffled.reserveCapacity(n)
        for old in order { shuffled.append(board.tubes[old]) }

        var solution: [PourPartyMove] = []
        solution.reserveCapacity(steps.count)
        for step in steps.reversed() { solution.append(PourPartyMove(from: place[step.to], to: place[step.from])) }
        return (PourPartyBoard(tubes: shuffled), solution)
    }
}

// MARK: - Solver

/// A depth-first search with a memory of boards seen. Tubes are few and small, so it is quick.
enum PourPartySolver {
    static func solve(_ board: PourPartyBoard, nodeCap: Int = 25000) -> [PourPartyMove]? {
        var work = board
        var path: [PourPartyMove] = []
        var seen = Set<String>()
        var nodes = 0
        if dive(&work, &path, &seen, &nodes, cap: nodeCap, depth: 0) { return path }
        return nil
    }

    private static func dive(_ board: inout PourPartyBoard, _ path: inout [PourPartyMove], _ seen: inout Set<String>,
                             _ nodes: inout Int, cap: Int, depth: Int) -> Bool {
        if board.isSolved { return true }
        if depth > 90 || nodes > cap { return false }
        nodes += 1
        if !seen.insert(board.key).inserted { return false }
        let n = board.tubes.count
        var whole: [PourPartyMove] = []
        var partial: [PourPartyMove] = []
        for a in 0..<n {
            guard let source = board.top(a) else { continue }
            if board.isDone(a) { continue }
            var emptyTried = false
            for b in 0..<n where b != a {
                if board.tubes[b].isEmpty {
                    // Moving a tube of one colour into an empty tube changes nothing worth having.
                    if board.isUniform(a) || emptyTried { continue }
                    emptyTried = true
                    whole.append(PourPartyMove(from: a, to: b))
                    continue
                }
                let amount = board.pourAmount(from: a, to: b)
                if amount == 0 { continue }
                if amount == source.count {
                    whole.append(PourPartyMove(from: a, to: b))
                } else {
                    partial.append(PourPartyMove(from: a, to: b))
                }
            }
        }
        for move in whole + partial {
            let saved = board
            board.pour(from: move.from, to: move.to)
            path.append(move)
            if dive(&board, &path, &seen, &nodes, cap: cap, depth: depth + 1) { return true }
            path.removeLast()
            board = saved
        }
        return false
    }
}

// MARK: - Model

final class PourPartyModel {
    enum Stage { case ready, playing, cleared, ending, finished }

    /// What the last step or tap deserves as a haptic. A stronger one replaces a weaker one.
    enum Feedback: Int { case none, tap, pour, bad, cleared, lost }

    // Tuning, in seconds.
    static let roundLength = 120.0
    static let liftLength = 0.18
    static let pourLength = 1.0
    static let clearedLength = 1.7
    static let levelInLength = 0.45
    static let endLength = 1.6
    static let floatLength = 1.1
    static let undosPerLevel = 3

    let bestScore: Int
    private var rng: PourPartyRandom

    private(set) var stage = Stage.ready
    private(set) var board = PourPartyBoard(tubes: [])
    private(set) var levelStart = PourPartyBoard(tubes: [])
    /// One way to finish the level from its start.
    private(set) var solution: [PourPartyMove] = []
    private var history: [PourPartyBoard] = []

    private(set) var level = 1
    private(set) var levelsCleared = 0
    private(set) var undosLeft = PourPartyModel.undosPerLevel
    private(set) var levelPours = 0
    private(set) var totalPours = 0
    private(set) var score = 0
    private(set) var shownScore = 0.0
    /// Seconds left.
    private(set) var clock: Double
    /// Seconds played since the first tap.
    private(set) var time = 0.0
    private(set) var ambient = 0.0
    /// True when no pour is possible and the level is not solved.
    private(set) var stuck = false

    private(set) var selected: Int?
    private(set) var liftAge = 0.0
    private(set) var pours: [PourPartyPourPose] = []
    private(set) var floats: [PourPartyFloat] = []
    private(set) var shaking: Int?
    private(set) var shakeAge = 0.0
    private(set) var popped: Int?
    private(set) var popAge = 10.0
    private(set) var clearedAge = 0.0
    private(set) var levelAge = 0.0
    private(set) var endClock = 0.0
    /// The tubes as the frame shows them, rebuilt in place every step.
    private(set) var poses: [[PourPartyBand]] = []
    private var layoutCache: PourPartyLayout?

    private var feedback = Feedback.none

    init(options: GameOptions) {
        bestScore = Swift.max(0, options.bestScore)
        rng = PourPartyRandom(seed: options.seed, salt: PourPartyRandom.round)
        // A demo recording ends soon after the scripted player gives up.
        if GameDemo.autopilot, let after = GameDemo.loseAfter {
            clock = Swift.min(Self.roundLength, Swift.max(after, 1) + 4)
        } else {
            clock = Self.roundLength
        }
        pours.reserveCapacity(8)
        floats.reserveCapacity(8)
        load(level: 1)
    }

    private func load(level: Int) {
        let made = PourPartyLevels.make(level: level, rng: &rng)
        board = made.board
        levelStart = made.board
        solution = made.solution
        history.removeAll(keepingCapacity: true)
        undosLeft = Self.undosPerLevel
        levelPours = 0
        selected = nil
        pours.removeAll(keepingCapacity: true)
        popped = nil
        stuck = false
        levelAge = 0
        PourPartyPoses.build(tubes: board.tubes, pours: pours, into: &poses)
    }

    // MARK: Reading

    /// The layout for a screen size, kept between frames.
    func layout(for size: CGSize) -> PourPartyLayout {
        if let cached = layoutCache, cached.W == size.width, cached.H == size.height, cached.rects.count == board.tubes.count {
            return cached
        }
        let fresh = PourPartyLayout(size: size, count: board.tubes.count)
        layoutCache = fresh
        return fresh
    }

    /// A tube that is part of a pour still in the air takes no tap.
    func isBusy(_ i: Int) -> Bool {
        for pour in pours where (pour.from == i || pour.to == i) && pour.progress < 1 { return true }
        return false
    }

    var canRestart: Bool { stage == .playing && (levelPours > 0 || board != levelStart) }

    var result: GameResult {
        let detail: String
        if levelsCleared == 0 {
            detail = "No level solved"
        } else {
            let levels = levelsCleared == 1 ? "1 level" : "\(levelsCleared) levels"
            detail = levels + (totalPours == 1 ? " in 1 pour" : " in \(totalPours) pours")
        }
        return GameResult(score: score, unit: "points", detail: detail)
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

    // MARK: Input

    /// A tap on a tube: lift it, put it down, or pour the lifted one into it.
    func tap(tube i: Int) {
        guard stage == .ready || stage == .playing, i >= 0, i < board.tubes.count else { return }
        if stage == .ready { stage = .playing }
        if isBusy(i) { return }
        if let s = selected {
            if s == i {
                selected = nil
                owe(.tap)
                return
            }
            let n = board.pourAmount(from: s, to: i)
            guard n > 0, let color = board.tubes[s].last else {
                shaking = i
                shakeAge = 0
                owe(.bad)
                return
            }
            history.append(board)
            board.pour(from: s, to: i)
            pours.append(PourPartyPourPose(from: s, to: i, color: color, units: n, progress: 0))
            selected = nil
            levelPours += 1
            totalPours += 1
            owe(.pour)
            if board.isDone(i) {
                popped = i
                popAge = 0
            }
            stuck = !board.isSolved && !board.hasMove
            if board.isSolved { clearLevel() }
            return
        }
        if board.tubes[i].isEmpty {
            shaking = i
            shakeAge = 0
            owe(.tap)
            return
        }
        selected = i
        liftAge = 0
        owe(.tap)
    }

    /// A tap on nothing puts a lifted tube down.
    func deselect() {
        guard selected != nil else { return }
        selected = nil
        owe(.tap)
    }

    func undo() {
        guard stage == .playing, undosLeft > 0, let previous = history.popLast() else {
            if stage == .playing { owe(.bad) }
            return
        }
        board = previous
        undosLeft -= 1
        levelPours = Swift.max(0, levelPours - 1)
        totalPours = Swift.max(0, totalPours - 1)
        selected = nil
        pours.removeAll(keepingCapacity: true)
        stuck = !board.isSolved && !board.hasMove
        owe(.tap)
    }

    func restart() {
        guard canRestart else { return }
        board = levelStart
        history.removeAll(keepingCapacity: true)
        undosLeft = Self.undosPerLevel
        levelPours = 0
        selected = nil
        pours.removeAll(keepingCapacity: true)
        stuck = false
        levelAge = 0
        owe(.tap)
    }

    private func clearLevel() {
        stage = .cleared
        clearedAge = 0
        selected = nil
        let gained = 100 * level
        score += gained
        levelsCleared += 1
        if floats.count >= 6 { floats.removeFirst() }
        floats.append(PourPartyFloat(text: "+\(gained)", tube: -1, age: 0))
        owe(.cleared)
    }

    // MARK: Clock

    func step(dt raw: Double) {
        let dt = Swift.min(Swift.max(raw, 0), 1.0 / 30)
        if dt <= 0 { return }
        ambient += dt
        if stage == .finished { return }

        liftAge += dt
        shakeAge += dt
        popAge += dt
        levelAge += dt
        if !pours.isEmpty {
            for k in pours.indices { pours[k].progress = Swift.min(1, pours[k].progress + dt / Self.pourLength) }
            pours.removeAll { $0.progress >= 1 }
        }
        if !floats.isEmpty {
            for k in floats.indices { floats[k].age += dt }
            floats.removeAll { $0.age >= Self.floatLength }
        }
        let goal = Double(score)
        shownScore += (goal - shownScore) * (1 - exp(-7 * dt))
        if abs(goal - shownScore) < 0.6 { shownScore = goal }

        switch stage {
        case .ready:
            break
        case .playing:
            time += dt
            clock = Swift.max(0, clock - dt)
            if clock <= 0 { lose() }
        case .cleared:
            clearedAge += dt
            if clearedAge >= Self.clearedLength {
                if clock <= 0 {
                    lose()
                } else {
                    level += 1
                    load(level: level)
                    stage = .playing
                }
            }
        case .ending:
            endClock += dt
            if endClock >= Self.endLength { stage = .finished }
        case .finished:
            break
        }
        PourPartyPoses.build(tubes: board.tubes, pours: pours, into: &poses)
    }

    private func lose() {
        stage = .ending
        endClock = 0
        selected = nil
        owe(.lost)
    }
}

// MARK: - Drawing

/// Paints the model as it is right now.
struct PourPartyCanvas: View {
    let model: PourPartyModel
    /// A new number every frame. The model is a class, so this is what makes SwiftUI repaint.
    var frame = 0

    var body: some View {
        Canvas(opaque: true, colorMode: .nonLinear, rendersAsynchronously: false) { context, size in
            if size.width <= 8 || size.height <= 8 { return }
            Self.paint(model, &context, size)
        }
    }

    static func paint(_ model: PourPartyModel, _ ctx: inout GraphicsContext, _ size: CGSize) {
        typealias Model = PourPartyModel
        typealias M = PourPartyMath
        var f = PourPartyFrame()
        f.tubes = model.poses
        f.lifted = model.selected
        f.lift = M.clamp(model.liftAge / Model.liftLength)
        f.pours = model.pours
        f.shaking = model.shaking
        f.shakeAge = model.shakeAge
        f.popped = model.popped
        f.popAge = model.popAge
        f.levelIn = M.clamp(model.levelAge / Model.levelInLength)
        f.level = model.level
        f.score = Int(model.shownScore.rounded())
        f.best = model.bestScore
        f.clock = model.clock
        f.undos = model.undosLeft
        f.canRestart = model.canRestart
        f.floats = model.floats
        f.bannerLength = Model.clearedLength

        switch model.stage {
        case .ready:
            f.hint = "Tap a tube to lift it"
            f.hintAlpha = 0.75 + 0.25 * sin(model.ambient * 3)
        case .playing:
            if model.stuck {
                f.hint = model.undosLeft > 0 ? "No pour left. Undo or restart" : "No pour left. Restart"
                f.hintAlpha = 1
            } else if model.totalPours == 0, model.selected != nil {
                f.hint = "Tap another tube to pour"
                f.hintAlpha = 1
            }
        case .cleared:
            f.banner = .solved
            f.bannerAge = model.clearedAge
            f.confettiAge = model.clearedAge
        case .ending, .finished:
            f.banner = .timeUp
            f.bannerAge = model.endClock
            f.bannerLength = Model.endLength + 2
            f.dim = M.smooth(0, 0.5, model.endClock)
        }
        PourPartyPainter(layout: model.layout(for: size)).draw(&ctx, f)
    }
}

// MARK: - Scripted player

/// Plays the round for recordings while GameDemo.autopilot is on.
///
/// It reads the model and answers at most one action a step, which then goes through the same calls
/// a finger uses. It solves each level with the solver, now and then takes one pour it did not mean
/// and undoes it, and once GameDemo.loseAfter has passed it stops and lets the clock run out.
struct PourPartyPilot {
    enum Action {
        case tap(Int)
        case undo
        case restart
    }

    static let readyHold = 0.9

    private var rng: PourPartyRandom
    private var wait = PourPartyPilot.readyHold
    /// Actions still to take for the current pour, in order.
    private var queue: [Action] = []
    private var plan: [PourPartyMove] = []
    /// The board the plan was made for.
    private var planKey = ""
    /// The level in which the stray pour has been taken.
    private var strayedOn = 0

    init(seed: UInt64) {
        rng = PourPartyRandom(seed: seed ^ 0x7069_6C6F_7421, salt: PourPartyRandom.round)
    }

    /// Call once per step, after the model has moved.
    mutating func act(_ model: PourPartyModel, dt: Double) -> Action? {
        wait -= dt
        if wait > 0 { return nil }
        guard model.stage == .ready || model.stage == .playing else {
            wait = 0.2
            return nil
        }
        if let limit = GameDemo.loseAfter, model.time >= limit { return nil }

        if !queue.isEmpty {
            let next = queue[0]
            if case .tap(let i) = next, model.isBusy(i) {
                wait = 0.12
                return nil
            }
            queue.removeFirst()
            wait = queue.isEmpty ? rng.range(0.45, 0.8) : rng.range(0.3, 0.42)
            return next
        }
        if model.selected != nil {
            // A lifted tube that is not part of a pour of ours: put it down.
            wait = 0.3
            return .tap(model.selected ?? 0)
        }

        let key = model.board.key
        if plan.isEmpty || planKey != key {
            plan = PourPartySolver.solve(model.board) ?? (model.board == model.levelStart ? model.solution : [])
            planKey = key
            if plan.isEmpty {
                wait = 0.6
                return model.canRestart ? .restart : nil
            }
        }
        guard let move = plan.first else { return nil }
        if model.isBusy(move.from) || model.isBusy(move.to) {
            wait = 0.15
            return nil
        }
        plan.removeFirst()

        // Now and then a pour that was not meant, taken back with Undo.
        if strayedOn != model.level, model.undosLeft > 0, rng.next() < 0.3, let slip = stray(model.board, instead: move) {
            strayedOn = model.level
            plan.insert(move, at: 0)
            queue = [.tap(slip.to), .undo]
            wait = rng.range(0.3, 0.42)
            return .tap(slip.from)
        }

        var after = model.board
        after.pour(from: move.from, to: move.to)
        planKey = after.key
        queue = [.tap(move.to)]
        wait = rng.range(0.28, 0.4)
        return .tap(move.from)
    }

    /// A legal pour other than the planned one that does not finish the level.
    private mutating func stray(_ board: PourPartyBoard, instead move: PourPartyMove) -> PourPartyMove? {
        var options: [PourPartyMove] = []
        for a in board.tubes.indices {
            for b in board.tubes.indices where a != b {
                if a == move.from && b == move.to { continue }
                if board.pourAmount(from: a, to: b) == 0 { continue }
                var after = board
                after.pour(from: a, to: b)
                if after.isSolved { continue }
                options.append(PourPartyMove(from: a, to: b))
            }
        }
        if options.isEmpty { return nil }
        return options[rng.int(options.count)]
    }
}

// MARK: - Game view

/// Holds the round between frames. Nothing is published: the timeline repaints every frame anyway.
final class PourPartyRunner: ObservableObject {
    let model: PourPartyModel
    private let seed: UInt64
    private var lastDate: Date?
    private var frame = 0
    private var reported = false
    /// Made the first time it is needed, which is only when GameDemo.autopilot is on.
    private var pilot: PourPartyPilot?

    init(options: GameOptions) {
        model = PourPartyModel(options: options)
        seed = options.seed
    }

    /// Brings the model up to the given date. Returns a number that changes when there is a new frame to paint.
    func advance(to date: Date, link: GameLink) -> Int {
        if link.paused {
            lastDate = nil
            return frame
        }
        defer { lastDate = date }
        guard let before = lastDate else { return frame }
        // When frames are slow the model still covers real time, in several small steps.
        var owed = Swift.min(Swift.max(date.timeIntervalSince(before), 0), 0.1)
        if owed <= 0 { return frame }
        while owed > 1e-6 {
            let dt = Swift.min(owed, 1.0 / 60)
            owed -= dt
            model.step(dt: dt)
            settle(link)
            if GameDemo.autopilot {
                if pilot == nil { pilot = PourPartyPilot(seed: seed) }
                if let action = pilot?.act(model, dt: dt) {
                    apply(action)
                    settle(link)
                }
            }
        }
        frame &+= 1
        return frame
    }

    private func apply(_ action: PourPartyPilot.Action) {
        switch action {
        case .tap(let i): model.tap(tube: i)
        case .undo: model.undo()
        case .restart: model.restart()
        }
    }

    /// A finger landed somewhere on the screen.
    func tap(at point: CGPoint, size: CGSize, link: GameLink) {
        if link.paused || link.isFinished { return }
        let layout = model.layout(for: size)
        if layout.restart.insetBy(dx: -8, dy: -8).contains(point) {
            model.restart()
        } else if layout.undo.insetBy(dx: -8, dy: -8).contains(point) {
            model.undo()
        } else if let i = layout.tube(at: point) {
            model.tap(tube: i)
        } else {
            model.deselect()
        }
        settle(link)
    }

    /// Plays the haptic the model owes and reports the round once it is over.
    private func settle(_ link: GameLink) {
        switch model.takeFeedback() {
        case .lost: GameHaptics.fail()
        case .cleared: GameHaptics.success()
        case .bad: GameHaptics.heavy()
        case .pour: GameHaptics.thud()
        case .tap: GameHaptics.tap()
        case .none: break
        }
        if model.stage == .finished, !reported {
            reported = true
            let result = model.result
            DispatchQueue.main.async { link.finish(result) }
        }
    }
}

public struct PourPartyGame: View {
    private let options: GameOptions
    private let link: GameLink

    public init(options: GameOptions, link: GameLink) {
        self.options = options
        self.link = link
    }

    public var body: some View {
        // A new link is a new round, so the round's state lives and dies with the link.
        PourPartyRound(options: options, link: link)
            .id(ObjectIdentifier(link))
    }
}

private struct PourPartyRound: View {
    @ObservedObject var link: GameLink
    @StateObject private var runner: PourPartyRunner
    @GestureState private var touching = false

    init(options: GameOptions, link: GameLink) {
        self.link = link
        _runner = StateObject(wrappedValue: PourPartyRunner(options: options))
    }

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: nil, paused: link.paused)) { timeline in
                PourPartyCanvas(model: runner.model, frame: runner.advance(to: timeline.date, link: link))
            }
            .contentShape(Rectangle())
            .gesture(
                // Fires as the finger lands, once per touch. The flag clears itself when the touch ends
                // or is cancelled.
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .updating($touching) { value, down, _ in
                        if down { return }
                        down = true
                        runner.tap(at: value.startLocation, size: geo.size, link: link)
                    }
            )
        }
        .ignoresSafeArea()
        .accessibilityElement()
        .accessibilityLabel("Pour Party. Tap a tube to lift it, tap another to pour.")
        .accessibilityAddTraits(.allowsDirectInteraction)
    }
}
