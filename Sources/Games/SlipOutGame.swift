import SwiftUI

// Slip Out, playable.
//
// SlipOutModel   the rules of a round in plain Swift: step(dt:) and tap(x:y:).
// SlipOutCanvas  paints one frame of the model with the clip's painter.
// SlipOutPilot   the scripted player. It only runs while GameDemo.autopilot is on.
// SlipOutRunner  keeps the clock, passes touches on, fires haptics, reports the result.
// SlipOutGame    the view the app shows.

// MARK: - Model

final class SlipOutModel {
    enum Stage { case ready, playing, clearing, ending, finished }

    /// What the last step or tap deserves as a haptic. A stronger one replaces a weaker one.
    enum Feedback: Int { case none, tap, slide, clear, bump, lost }

    /// An arrow on its way off the board.
    struct Slide {
        let id: Int
        var age: Double
        let length: Double
        let distance: Double
    }

    /// An arrow that ran into another one and is on its way back.
    struct Bump {
        let id: Int
        var age: Double
        let length: Double
        /// Free cells before the arrow in the way.
        let reach: Double
    }

    // Tuning. Times in seconds, distances in cells.
    static let roundLength = 120.0
    static let startHearts = 3
    static let slideSpeed = 30.0
    static let clearLength = 1.15
    static let endLength = 1.5
    static let floatLength = 0.9
    static let urgentFrom = 10.0

    let seed: UInt64
    let bestScore: Int

    private(set) var stage = Stage.ready
    private(set) var levelIndex = 0
    private(set) var level: SlipOutLevel
    /// Arrows that have left the board or are on their way off it.
    private(set) var gone = Set<Int>()
    private(set) var slides: [Slide] = []
    private(set) var bumps: [Bump] = []
    private(set) var floats: [SlipOutFloat] = []
    private(set) var hearts = SlipOutModel.startHearts
    private(set) var heartAge = 10.0
    /// Arrows slid out over the whole round.
    private(set) var score = 0
    private(set) var levelsCleared = 0
    /// Round clock: from the first tap to the end.
    private(set) var time = 0.0
    /// Scenery clock: runs whenever the game is not paused.
    private(set) var ambient = 0.0
    private(set) var levelAge = 10.0
    private(set) var clearAge: Double? = nil
    private(set) var endAge: Double? = nil
    private(set) var endText = ""

    private var feedback = Feedback.none

    init(options: GameOptions) {
        seed = options.seed
        bestScore = Swift.max(0, options.bestScore)
        level = SlipOutLevel.make(index: 0, seed: options.seed)
        slides.reserveCapacity(16)
        bumps.reserveCapacity(8)
        floats.reserveCapacity(16)
    }

    // MARK: Reading

    var secondsLeft: Double { Swift.max(0, Self.roundLength - time) }

    var clockText: String { SlipOutClip.clock(Int(secondsLeft.rounded(.up))) }

    var clockUrgent: Bool { stage != .ready && secondsLeft <= Self.urgentFrom }

    func isBumping(_ id: Int) -> Bool {
        for bump in bumps where bump.id == id { return true }
        return false
    }

    var result: GameResult {
        let levels = levelsCleared
        let line: String
        if levels == 0 {
            line = "Level 1 not cleared"
        } else if levels == 1 {
            line = "1 level cleared"
        } else {
            line = "\(levels) levels cleared"
        }
        return GameResult(score: score, unit: "arrows", detail: line)
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

    /// The game's one input: a tap at a point on the board, in cells. The first tap starts the
    /// round. False when the tap hit nothing.
    @discardableResult
    func tap(x: Double, y: Double) -> Bool {
        guard stage == .ready || stage == .playing else { return false }
        guard let arrow = level.arrow(at: x, y, gone: gone) else { return false }
        if isBumping(arrow.id) { return false }
        stage = .playing

        if let block = level.blocker(for: arrow, gone: gone) {
            // Something is in the way: it goes as far as it can, comes back and costs a heart.
            let reach = Double(block.free) + 0.38
            bumps.append(Bump(id: arrow.id, age: 0, length: 0.42 + 0.06 * Double(block.free), reach: reach))
            hearts -= 1
            heartAge = 0
            owe(.bump)
            if hearts <= 0 { end("Out of hearts") }
            return true
        }

        gone.insert(arrow.id)
        let distance = arrow.exitDistance(cols: level.cols, rows: level.rows)
        let length = Swift.min(0.55, Swift.max(0.26, distance / Self.slideSpeed))
        slides.append(Slide(id: arrow.id, age: 0, length: length, distance: distance))
        score += 1
        let head = arrow.head
        if floats.count >= 12 { floats.removeFirst() }
        floats.append(SlipOutFloat(x: Double(head.x) + 0.5, y: Double(head.y) + 0.5, text: "+1", age: 0))
        owe(.slide)
        return true
    }

    // MARK: Clock

    func step(dt raw: Double) {
        let dt = Swift.min(Swift.max(raw, 0), 1.0 / 30)
        if dt <= 0 { return }
        ambient += dt
        if stage == .finished { return }

        heartAge = Swift.min(heartAge + dt, 100)
        levelAge = Swift.min(levelAge + dt, 100)
        if !slides.isEmpty {
            for k in slides.indices { slides[k].age += dt }
            slides.removeAll { $0.age >= $0.length }
        }
        if !bumps.isEmpty {
            for k in bumps.indices { bumps[k].age += dt }
            bumps.removeAll { $0.age >= $0.length }
        }
        if !floats.isEmpty {
            for k in floats.indices { floats[k].age += dt }
            floats.removeAll { $0.age >= Self.floatLength }
        }

        switch stage {
        case .ready:
            break
        case .playing:
            time += dt
            if time >= Self.roundLength {
                end("Time is up")
            } else if gone.count == level.arrows.count, slides.isEmpty {
                stage = .clearing
                clearAge = 0
                levelsCleared += 1
                hearts = Swift.min(Self.startHearts, hearts + 1)
                owe(.clear)
            }
        case .clearing:
            time += dt
            if let age = clearAge {
                clearAge = age + dt
                if age + dt >= Self.clearLength { nextLevel() }
            }
            if time >= Self.roundLength { end("Time is up") }
        case .ending:
            if let age = endAge {
                endAge = age + dt
                if age + dt >= Self.endLength { stage = .finished }
            }
        case .finished:
            break
        }
    }

    private func nextLevel() {
        levelIndex += 1
        level = SlipOutLevel.make(index: levelIndex, seed: seed)
        gone.removeAll(keepingCapacity: true)
        slides.removeAll(keepingCapacity: true)
        bumps.removeAll(keepingCapacity: true)
        floats.removeAll(keepingCapacity: true)
        clearAge = nil
        levelAge = 0
        stage = .playing
    }

    private func end(_ text: String) {
        stage = .ending
        endAge = 0
        endText = text
        clearAge = nil
        owe(.lost)
    }
}

// MARK: - Drawing

/// Paints the model as it is right now.
struct SlipOutCanvas: View {
    let model: SlipOutModel
    /// A new number every frame. The model is a class, so this is what makes SwiftUI repaint.
    var frame = 0

    var body: some View {
        Canvas(opaque: true, colorMode: .nonLinear, rendersAsynchronously: false) { context, size in
            if size.width <= 8 || size.height <= 8 { return }
            let frame = Self.frame(of: model)
            SlipOutPainter(size: size, frame: frame, showHUD: true).draw(&context)
        }
    }

    static func frame(of model: SlipOutModel) -> SlipOutFrame {
        typealias M = SlipOutMath
        var frame = SlipOutFrame()
        frame.cols = model.level.cols
        frame.rows = model.level.rows
        frame.hearts = model.hearts
        frame.heartAge = model.heartAge
        frame.level = model.levelIndex + 1
        frame.score = model.score
        frame.clockText = model.clockText
        frame.clockUrgent = model.clockUrgent
        frame.floats = model.floats
        frame.clearAge = model.clearAge
        frame.levelAge = model.levelAge
        frame.endAge = model.endAge
        frame.endText = model.endText
        if model.stage == .ready {
            frame.hint = "Tap an arrow to slide it out"
            frame.hintAlpha = 0.75 + 0.25 * sin(model.ambient * 3)
        }

        frame.arrows.reserveCapacity(model.level.arrows.count)
        for arrow in model.level.arrows {
            var item = SlipOutArrowFrame(arrow: arrow)
            if model.gone.contains(arrow.id) {
                var sliding: SlipOutModel.Slide? = nil
                for slide in model.slides where slide.id == arrow.id {
                    sliding = slide
                    break
                }
                guard let slide = sliding else { continue }
                item.offset = M.easeIn(slide.age / slide.length) * slide.distance
                item.swell = Swift.max(0, 1 - slide.age / 0.25)
            } else {
                for bump in model.bumps where bump.id == arrow.id {
                    let t = M.clamp(bump.age / bump.length)
                    item.offset = bump.reach * sin(.pi * M.clamp(t * 1.4))
                    item.hot = 1 - M.smooth(0.45, 1, t)
                    break
                }
            }
            frame.arrows.append(item)
        }
        return frame
    }
}

// MARK: - Scripted player

/// Plays the round for recordings while GameDemo.autopilot is on.
///
/// It reads the model and answers one question a frame: where to tap, if anywhere. The tap then
/// goes through the same call a finger uses. Its random numbers are its own, so the level the
/// model deals is the same with it or without it.
struct SlipOutPilot {
    static let readyHold = 1.0

    private var rng: SlipOutRandom
    /// Seconds until the next tap.
    private var wait = SlipOutPilot.readyHold
    private var taps = 0
    /// Every so many taps it picks an arrow that is blocked, the way a person misreads one.
    private let slipEvery: Int

    init(seed: UInt64) {
        rng = SlipOutRandom(seed: seed ^ 0x7069_6C6F_7421, salt: SlipOutRandom.pilot)
        slipEvery = rng.int(7...10)
    }

    /// Call once per step, after the model has moved. A point on the board, in cells, to tap now.
    mutating func nextTap(_ model: SlipOutModel, dt: Double) -> (x: Double, y: Double)? {
        guard model.stage == .ready || model.stage == .playing else { return nil }
        if model.levelAge < 0.6 { return nil }
        wait -= dt
        if wait > 0 { return nil }

        var losing = false
        if let limit = GameDemo.loseAfter, model.time >= limit { losing = true }
        taps += 1
        let wantBlocked = losing || taps % slipEvery == 0

        var free: [SlipOutArrow] = []
        var blocked: [SlipOutArrow] = []
        for arrow in model.level.arrows {
            if model.gone.contains(arrow.id) || model.isBumping(arrow.id) { continue }
            if model.level.blocker(for: arrow, gone: model.gone) == nil {
                free.append(arrow)
            } else {
                blocked.append(arrow)
            }
        }
        let pool: [SlipOutArrow] = (wantBlocked && !blocked.isEmpty) ? blocked : free
        if pool.isEmpty {
            wait = 0.3
            return nil
        }
        let pick = pool[rng.int(0...(pool.count - 1))]
        wait = losing ? rng.range(0.5, 0.8) : rng.range(0.3, 0.55)
        let cell = pick.cells[rng.int(0...(pick.cells.count - 1))]
        return (Double(cell.x) + 0.5 + rng.range(-0.2, 0.2), Double(cell.y) + 0.5 + rng.range(-0.2, 0.2))
    }
}

// MARK: - Game view

/// Holds the round between frames. Nothing is published: the timeline repaints every frame anyway.
final class SlipOutRunner: ObservableObject {
    let model: SlipOutModel
    private let seed: UInt64
    private var lastDate: Date?
    private var frame = 0
    private var reported = false
    /// Made the first time it is needed, which is only when GameDemo.autopilot is on.
    private var pilot: SlipOutPilot?

    init(options: GameOptions) {
        model = SlipOutModel(options: options)
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
                if pilot == nil { pilot = SlipOutPilot(seed: seed) }
                if let at = pilot?.nextTap(model, dt: dt) {
                    model.tap(x: at.x, y: at.y)
                    settle(link)
                }
            }
        }
        frame &+= 1
        return frame
    }

    /// A touch on the screen. The painter says which cell that is.
    func tap(at point: CGPoint, in size: CGSize, link: GameLink) {
        if link.paused || link.isFinished { return }
        var layout = SlipOutFrame()
        layout.cols = model.level.cols
        layout.rows = model.level.rows
        let painter = SlipOutPainter(size: size, frame: layout, showHUD: true)
        let at = painter.board(point)
        if !model.tap(x: at.x, y: at.y) {
            // A touch on empty paper is still felt.
            GameHaptics.tap()
        }
        settle(link)
    }

    /// Plays the haptic the model owes and reports the round once it is over.
    private func settle(_ link: GameLink) {
        switch model.takeFeedback() {
        case .lost: GameHaptics.fail()
        case .bump: GameHaptics.heavy()
        case .clear: GameHaptics.success()
        case .slide: GameHaptics.thud()
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

public struct SlipOutGame: View {
    private let options: GameOptions
    private let link: GameLink

    public init(options: GameOptions, link: GameLink) {
        self.options = options
        self.link = link
    }

    public var body: some View {
        // A new link is a new round, so the round's state lives and dies with the link.
        SlipOutRound(options: options, link: link)
            .id(ObjectIdentifier(link))
    }
}

private struct SlipOutRound: View {
    @ObservedObject var link: GameLink
    @StateObject private var runner: SlipOutRunner
    @GestureState private var touching = false

    init(options: GameOptions, link: GameLink) {
        self.link = link
        _runner = StateObject(wrappedValue: SlipOutRunner(options: options))
    }

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: nil, paused: link.paused)) { timeline in
                SlipOutCanvas(model: runner.model, frame: runner.advance(to: timeline.date, link: link))
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
        .accessibilityLabel("Slip Out. Tap an arrow to slide it off the board.")
        .accessibilityAddTraits(.allowsDirectInteraction)
    }
}
