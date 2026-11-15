import SwiftUI

// Bus Rush, playable.
//
// BusRushModel   the rules of a round in plain Swift: step(dt:) and tap(x:y:).
// BusRushCanvas  paints one frame of the model with the clip's painter.
// BusRushPilot   the scripted player. It only runs while GameDemo.autopilot is on.
// BusRushRunner  keeps the clock, passes touches on, fires haptics, reports the result.
// BusRushGame    the view the app shows.

// MARK: - Model

final class BusRushModel {
    enum Stage { case ready, playing, clearing, ending, finished }

    /// What the last step or tap deserves as a haptic. A stronger one replaces a weaker one.
    enum Feedback: Int { case none, launch, leave, bump, clear, timeUp, lost }

    typealias Line = BusRushTimeline

    // Tuning. Times in seconds.
    static let roundLength = 150.0
    static let clearLength = 1.3
    static let endLength = 1.7
    static let urgentFrom = 10.0
    /// Five slots nobody can use must stay that way this long before the lot counts as jammed.
    static let jamDelay = 0.45
    static let noteLength = 1.3
    /// Buses leaving this close together earn a word.
    static let comboWindow = 2.0

    let seed: UInt64
    let bestScore: Int

    private(set) var stage = Stage.ready
    private(set) var levelIndex: Int
    /// The lot being played and everything that has happened on it.
    private(set) var line: BusRushTimeline
    /// The lot's clock. Holds still until the first tap.
    private(set) var now = 0.0
    /// Round clock: from the first tap to the end.
    private(set) var time = 0.0
    /// Scenery clock: runs whenever the game is not paused.
    private(set) var ambient = 0.0
    private(set) var levelAge = 0.0
    /// The rider at the front of the queue.
    private(set) var front = 0
    /// Seats promised per bus: riders on board plus riders on their way in.
    private var reserved: [Int]
    private var nextBoard = 0.0
    private(set) var ridersBefore = 0
    private(set) var levelsCleared = 0
    private(set) var clearAge: Double?
    private(set) var endAge: Double?
    private(set) var endText = ""
    private(set) var note: String?
    private(set) var noteAge = 0.0
    private(set) var jammed = false
    private var jamFor = 0.0
    private var combo = 0
    private var lastLeave = -10.0
    private(set) var clockText = BusRushMath.clock(Int(BusRushModel.roundLength))
    private var clockSecond = Int(BusRushModel.roundLength)

    private var feedback = Feedback.none

    init(options: GameOptions, firstLevel: Int = 0) {
        seed = options.seed
        bestScore = Swift.max(0, options.bestScore)
        levelIndex = Swift.max(0, firstLevel)
        let level = BusRushLevel.make(index: levelIndex, seed: options.seed)
        line = BusRushTimeline(level: level)
        reserved = [Int](repeating: 0, count: level.buses.count)
    }

    // MARK: Reading

    var level: BusRushLevel { line.level }

    /// Riders on board over the whole round.
    var score: Int { ridersBefore + front }

    var secondsLeft: Double { Swift.max(0, Self.roundLength - time) }

    var clockUrgent: Bool { stage != .ready && secondsLeft <= Self.urgentFrom }

    func inLot(_ id: Int) -> Bool { line.launch[id] == .infinity }

    /// Seats still free on a bus out of the lot.
    func freeSeats(_ id: Int) -> Int {
        if inLot(id) { return 0 }
        return level.buses[id].capacity - reserved[id]
    }

    /// Slots taken by buses parked there or on their way.
    var slotsUsed: Int {
        var used = 0
        for bus in level.buses where line.launch[bus.id] != .infinity && line.depart[bus.id] > now { used += 1 }
        return used
    }

    /// A bus out of the lot still has a seat for the rider at the front.
    var frontHasSeat: Bool {
        guard front < level.queue.count else { return true }
        let want = level.queue[front]
        for bus in level.buses where bus.color == want && line.depart[bus.id] == .infinity && freeSeats(bus.id) > 0 { return true }
        return false
    }

    func isBumping(_ id: Int) -> Bool {
        for bump in line.bumps where bump.id == id && now - bump.time < Line.bumpLength { return true }
        return false
    }

    var result: GameResult {
        let line: String
        if levelsCleared == 0 {
            line = "Lot 1 not cleared"
        } else if levelsCleared == 1 {
            line = "1 lot cleared"
        } else {
            line = "\(levelsCleared) lots cleared"
        }
        return GameResult(score: score, unit: "riders", detail: line)
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

    /// The game's one input: a tap at a point on the lot, in cells. The first tap starts the round.
    /// False when the tap hit no bus.
    @discardableResult
    func tap(x: Double, y: Double) -> Bool {
        guard stage == .ready || stage == .playing else { return false }
        guard let id = busNear(x, y) else { return false }
        if isBumping(id) { return false }
        stage = .playing

        if let block = level.blocker(for: id, launch: line.launch) {
            // Something is in the way: it rolls up to it and back.
            bump(BusRushBump(id: id, time: now, reach: Double(block.free) + 0.1, blocker: block.id))
            return true
        }
        guard let k = freeSlot() else {
            bump(BusRushBump(id: id, time: now, reach: 0.14, blocker: -1))
            note = "Every slot is taken"
            noteAge = 0
            return true
        }
        line.launch[id] = now
        line.slot[id] = k
        owe(.launch)
        return true
    }

    /// The bus under a point, or on the cell next to it when the point is close to the edge.
    private func busNear(_ x: Double, _ y: Double) -> Int? {
        if !x.isFinite || !y.isFinite { return nil }
        if x < -0.4 || y < -0.4 || x > Double(level.cols) + 0.4 || y > Double(level.rows) + 0.4 { return nil }
        let cx = Int(x.rounded(.down))
        let cy = Int(y.rounded(.down))
        if let id = level.bus(atX: cx, y: cy, launch: line.launch) { return id }
        let rx = x - Double(cx) - 0.5
        let ry = y - Double(cy) - 0.5
        if abs(rx) >= abs(ry) {
            if abs(rx) > 0.2, let id = level.bus(atX: cx + (rx > 0 ? 1 : -1), y: cy, launch: line.launch) { return id }
            if abs(ry) > 0.2, let id = level.bus(atX: cx, y: cy + (ry > 0 ? 1 : -1), launch: line.launch) { return id }
        } else {
            if abs(ry) > 0.2, let id = level.bus(atX: cx, y: cy + (ry > 0 ? 1 : -1), launch: line.launch) { return id }
            if abs(rx) > 0.2, let id = level.bus(atX: cx + (rx > 0 ? 1 : -1), y: cy, launch: line.launch) { return id }
        }
        return nil
    }

    private func freeSlot() -> Int? {
        for k in 0..<Line.slots {
            var taken = false
            for bus in level.buses where line.slot[bus.id] == k && line.launch[bus.id] != .infinity && line.depart[bus.id] > now {
                taken = true
                break
            }
            if !taken { return k }
        }
        return nil
    }

    private func bump(_ bump: BusRushBump) {
        if line.bumps.count >= 8 { line.bumps.removeFirst() }
        line.bumps.append(bump)
        owe(.bump)
    }

    // MARK: Clock

    func step(dt raw: Double) {
        let dt = Swift.min(Swift.max(raw, 0), 1.0 / 30)
        if dt <= 0 { return }
        ambient += dt
        if stage == .finished { return }
        levelAge = Swift.min(levelAge + dt, 1000)
        if note != nil {
            noteAge += dt
            if noteAge >= Self.noteLength { note = nil }
        }

        switch stage {
        case .ready:
            break
        case .playing:
            time += dt
            advance(dt)
            if time >= Self.roundLength {
                end("Time is up", .timeUp)
            } else if isCleared() {
                stage = .clearing
                clearAge = 0
                levelsCleared += 1
                owe(.clear)
            } else if isJammed() {
                jamFor += dt
                if jamFor >= Self.jamDelay {
                    jammed = true
                    end("Lot jammed", .lost)
                }
            } else {
                jamFor = 0
            }
        case .clearing:
            time += dt
            advance(dt)
            let age = (clearAge ?? 0) + dt
            clearAge = age
            if time >= Self.roundLength {
                end("Time is up", .timeUp)
            } else if age >= Self.clearLength {
                nextLevel()
            }
        case .ending:
            now += dt
            let age = (endAge ?? 0) + dt
            endAge = age
            if age >= Self.endLength { stage = .finished }
        case .finished:
            break
        }

        let second = Int(secondsLeft.rounded(.up))
        if second != clockSecond {
            clockSecond = second
            clockText = BusRushMath.clock(second)
        }
    }

    private func advance(_ dt: Double) {
        let before = now
        now += dt
        board()
        for bus in level.buses {
            let at = line.depart[bus.id]
            if at > before && at <= now { owe(.leave) }
        }
    }

    // MARK: Rules

    /// The rider at the front steps into the parked bus of their colour that came first. One rider
    /// at a time, in queue order; a rider with no bus to take holds up everyone behind.
    private func board() {
        while front < line.board.count, now >= nextBoard {
            let color = level.queue[front]
            var pick = -1
            var first = Double.infinity
            for bus in level.buses where bus.color == color {
                let id = bus.id
                let launched = line.launch[id]
                if launched + Line.drive > now || line.depart[id] != .infinity || reserved[id] >= bus.capacity { continue }
                if launched < first {
                    first = launched
                    pick = id
                }
            }
            if pick < 0 { return }
            line.board[front] = now
            line.rider[front] = pick
            reserved[pick] += 1
            front += 1
            nextBoard = now + Line.gap
            if reserved[pick] == level.buses[pick].capacity {
                // Full: it leaves once the last rider has sat down.
                let at = now + Line.walk + Line.hold
                line.depart[pick] = at
                combo = at - lastLeave <= Self.comboWindow ? combo + 1 : 1
                lastLeave = at
                if combo >= 2 {
                    let word = combo == 2 ? "Nice" : (combo == 3 ? "Great" : "Perfect")
                    line.praises.append(BusRushPraise(text: word, time: at))
                }
            }
        }
    }

    private func isCleared() -> Bool {
        if front < line.board.count { return false }
        for bus in level.buses where !(line.depart[bus.id] + Line.leave <= now) { return false }
        return true
    }

    /// Every slot holds a parked bus that is not leaving, and none of them takes the rider in front.
    private func isJammed() -> Bool {
        guard front < line.board.count else { return false }
        let want = level.queue[front]
        var used = 0
        for bus in level.buses {
            let id = bus.id
            if line.launch[id] == .infinity || line.depart[id] <= now { continue }
            if line.depart[id] != .infinity { return false }
            if line.launch[id] + Line.drive > now { return false }
            if bus.color == want && reserved[id] < bus.capacity { return false }
            used += 1
        }
        return used >= Line.slots
    }

    private func nextLevel() {
        ridersBefore += front
        levelIndex += 1
        let level = BusRushLevel.make(index: levelIndex, seed: seed)
        line = BusRushTimeline(level: level)
        reserved = [Int](repeating: 0, count: level.buses.count)
        front = 0
        nextBoard = 0
        now = 0
        levelAge = 0
        clearAge = nil
        combo = 0
        lastLeave = -10
        jamFor = 0
        stage = .playing
    }

    private func end(_ text: String, _ kind: Feedback) {
        stage = .ending
        endAge = 0
        endText = text
        clearAge = nil
        note = nil
        owe(kind)
    }
}

// MARK: - Drawing

/// Paints the model as it is right now.
struct BusRushCanvas: View {
    let model: BusRushModel
    /// A new number every frame. The model is a class, so this is what makes SwiftUI repaint.
    var frame = 0

    var body: some View {
        Canvas(opaque: true, colorMode: .nonLinear, rendersAsynchronously: false) { context, size in
            if size.width <= 8 || size.height <= 8 { return }
            BusRushPainter(size: size, frame: Self.frame(of: model), showHUD: true).draw(&context)
        }
    }

    static func frame(of model: BusRushModel) -> BusRushFrame {
        var frame = BusRushFrame(line: model.line)
        frame.t = model.now
        frame.ambient = model.ambient
        frame.levelAge = model.levelAge
        frame.levelNumber = model.levelIndex + 1
        frame.scoreBase = model.ridersBefore
        frame.clockText = model.clockText
        frame.clockUrgent = model.clockUrgent
        frame.note = model.note
        frame.noteAge = model.noteAge
        frame.clearAge = model.clearAge
        frame.endAge = model.endAge
        frame.endText = model.endText
        frame.jammed = model.jammed
        if model.stage == .ready {
            frame.hint = "Tap a bus to send it out"
            frame.hintAlpha = 0.8 + 0.2 * sin(model.ambient * 3)
        }
        return frame
    }
}

// MARK: - Scripted player

/// Plays the round for recordings while GameDemo.autopilot is on.
///
/// It reads the model and answers one question a frame: which bus to tap, if any. The tap then goes
/// through the same call a finger uses. Mostly it sends out the bus the lot was built to give up
/// next, sometimes a bus the riders up front want, and now and then a blocked one, the way a person
/// misreads the lot. Its random numbers are its own, so the lot is the same with it or without it.
struct BusRushPilot {
    static let readyHold = 0.9

    private var rng: BusRushRandom
    /// Seconds until the next tap.
    private var wait = BusRushPilot.readyHold
    private var taps = 0
    private let slipEvery: Int
    private let loseAfter: Double?

    init(seed: UInt64, loseAfter: Double?) {
        rng = BusRushRandom(seed: seed ^ 0x7069_6C6F_7421, salt: BusRushRandom.pilot)
        slipEvery = rng.int(8...11)
        self.loseAfter = loseAfter
    }

    /// Call once per step, after the model has moved. A point on the lot, in cells, to tap now.
    mutating func nextTap(_ model: BusRushModel, dt: Double) -> (x: Double, y: Double)? {
        guard model.stage == .ready || model.stage == .playing else { return nil }
        if model.levelAge < 0.6 { return nil }
        wait -= dt
        if wait > 0 { return nil }

        var losing = false
        if let limit = loseAfter, model.time >= limit { losing = true }
        let used = model.slotsUsed
        if used >= BusRushTimeline.slots || (!losing && used >= 3 && model.frontHasSeat) {
            // Full, or no need to fill another slot while the queue keeps moving.
            wait = 0.15
            return nil
        }

        let level = model.level
        // The bus laid last of those still in the lot always has a clear road out.
        var latest = -1
        var blocked: [Int] = []
        for bus in level.buses where model.inLot(bus.id) {
            latest = bus.id
            if level.blocker(for: bus.id, launch: model.line.launch) != nil { blocked.append(bus.id) }
        }
        if latest < 0 {
            wait = 0.3
            return nil
        }

        taps += 1
        var pick = latest
        if !losing, taps % slipEvery == 0, !blocked.isEmpty {
            pick = blocked[rng.int(0...(blocked.count - 1))]
        } else if losing {
            // Fill the slots with buses nobody near the front wants.
            pick = choose(model, wanted: false) ?? latest
        } else if used <= 1, rng.next() < 0.4 {
            pick = choose(model, wanted: true) ?? latest
        }
        wait = losing ? rng.range(0.25, 0.4) : rng.range(0.45, 0.8)

        let bus = level.buses[pick]
        let k = rng.int(0...(bus.length - 1))
        let x = Double(bus.headX - bus.dir.dx * k) + 0.5 + rng.range(-0.2, 0.2)
        let y = Double(bus.headY - bus.dir.dy * k) + 0.5 + rng.range(-0.2, 0.2)
        return (x, y)
    }

    /// A bus with a clear road whose colour the riders up front want, or with wanted false, do not.
    private mutating func choose(_ model: BusRushModel, wanted: Bool) -> Int? {
        let level = model.level
        let queue = level.queue
        var need = [Int](repeating: 0, count: BusRushInk.busHex.count)
        var k = model.front
        while k < queue.count, k < model.front + (wanted ? 8 : 6) {
            need[queue[k]] += 1
            k += 1
        }
        if wanted {
            for bus in level.buses { need[bus.color] -= model.freeSeats(bus.id) }
        }
        var options: [Int] = []
        for bus in level.buses where model.inLot(bus.id) && level.blocker(for: bus.id, launch: model.line.launch) == nil {
            if (need[bus.color] > 0) != wanted { continue }
            if wanted {
                // Of a colour, the bus the lot gives up first, so its riders are the ones coming.
                var later = false
                for other in level.buses where other.id > bus.id && other.color == bus.color && model.inLot(other.id) {
                    later = true
                    break
                }
                if later { continue }
            }
            options.append(bus.id)
        }
        if options.isEmpty, !wanted, model.front < queue.count {
            // Anything but the colour the rider in front is waiting for.
            for bus in level.buses where model.inLot(bus.id) && bus.color != queue[model.front]
                && level.blocker(for: bus.id, launch: model.line.launch) == nil {
                options.append(bus.id)
            }
        }
        if options.isEmpty { return nil }
        return options[rng.int(0...(options.count - 1))]
    }
}

// MARK: - Game view

/// Holds the round between frames. Nothing is published: the timeline repaints every frame anyway.
final class BusRushRunner: ObservableObject {
    let model: BusRushModel
    private let seed: UInt64
    private var lastDate: Date?
    private var frame = 0
    private var reported = false
    /// Made the first time it is needed, which is only when GameDemo.autopilot is on.
    private var pilot: BusRushPilot?

    init(options: GameOptions) {
        model = BusRushModel(options: options)
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
                if pilot == nil { pilot = BusRushPilot(seed: seed, loseAfter: GameDemo.loseAfter) }
                if let at = pilot?.nextTap(model, dt: dt) {
                    model.tap(x: at.x, y: at.y)
                    settle(link)
                }
            }
        }
        frame &+= 1
        return frame
    }

    /// A touch on the screen. The layout says which cell of the lot that is.
    func tap(at point: CGPoint, in size: CGSize, link: GameLink) {
        if link.paused || link.isFinished { return }
        let layout = BusRushLayout(size: size, cols: model.level.cols, rows: model.level.rows, showHUD: true)
        let at = layout.lotCell(point)
        if !model.tap(x: at.x, y: at.y) {
            // A touch that hits no bus is still felt.
            GameHaptics.tap()
        }
        settle(link)
    }

    /// Plays the haptic the model owes and reports the round once it is over.
    private func settle(_ link: GameLink) {
        switch model.takeFeedback() {
        case .lost: GameHaptics.fail()
        case .timeUp: GameHaptics.success()
        case .clear:
            GameHaptics.heavy()
            GameHaptics.success()
        case .bump: GameHaptics.heavy()
        case .leave: GameHaptics.thud()
        case .launch: GameHaptics.tap()
        case .none: break
        }
        if model.stage == .finished, !reported {
            reported = true
            let result = model.result
            DispatchQueue.main.async { link.finish(result) }
        }
    }
}

public struct BusRushGame: View {
    private let options: GameOptions
    private let link: GameLink

    public init(options: GameOptions, link: GameLink) {
        self.options = options
        self.link = link
    }

    public var body: some View {
        // A new link is a new round, so the round's state lives and dies with the link.
        BusRushRound(options: options, link: link)
            .id(ObjectIdentifier(link))
    }
}

private struct BusRushRound: View {
    @ObservedObject var link: GameLink
    @StateObject private var runner: BusRushRunner
    @GestureState private var touching = false

    init(options: GameOptions, link: GameLink) {
        self.link = link
        _runner = StateObject(wrappedValue: BusRushRunner(options: options))
    }

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: nil, paused: link.paused)) { timeline in
                BusRushCanvas(model: runner.model, frame: runner.advance(to: timeline.date, link: link))
            }
            .contentShape(Rectangle())
            .gesture(
                // Fires as the finger lands, once per touch. The flag clears itself when the touch
                // ends or is cancelled.
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .updating($touching) { value, down, _ in
                        if down { return }
                        down = true
                        runner.tap(at: value.startLocation, in: geo.size, link: link)
                    }
            )
        }
        .ignoresSafeArea()
        .accessibilityElement()
        .accessibilityLabel("Bus Rush. Tap a bus to drive it out to a slot.")
        .accessibilityAddTraits(.allowsDirectInteraction)
    }
}
