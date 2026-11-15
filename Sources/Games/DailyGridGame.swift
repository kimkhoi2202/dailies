import SwiftUI

// Daily Grid, playable.
//
// DailyGridModel   the rules of a round in plain Swift: press, paint, undo, hint, clear, step(dt:).
// DailyGridPilot   the scripted player. It only runs while GameDemo.autopilot is on.
// DailyGridRunner  keeps the clock, turns touches into squares and keys, fires haptics, reports.
// DailyGridGame    the view the app shows.

// MARK: - Model

final class DailyGridModel {
    enum Stage { case ready, playing, solved, timeUp, finished }

    /// What the last action deserves as a haptic. A stronger one replaces a weaker one.
    enum Feedback: Int { case none, tap, place, wrong, done }

    static let timeLimit = 300.0
    static let hintCost = 10.0
    /// Solved: the board lights up, the card follows, the round is reported.
    static let cardAt = 1.5
    static let solvedLength = 5.2
    static let timeUpLength = 4.4
    static let noteLength = 2.6

    let puzzle: DailyGridPuzzle
    let number: Int
    let solo: Bool
    let limit: Double

    private(set) var board: DailyGridBoard
    private(set) var hud = DailyGridHUD()
    private(set) var chips: [DailyGridChip] = []
    private(set) var sparks: [DailyGridSpark]
    private(set) var floats: [DailyGridFloat]
    private(set) var stage = Stage.ready
    /// The solve clock, hint seconds included.
    private(set) var time = 0.0
    /// Runs whenever the game is not paused.
    private(set) var ambient = 0.0
    private(set) var endAge = 0.0
    private(set) var hints = 0
    private(set) var mistakes = 0
    private(set) var praise: String?
    private(set) var card: DailyGridCard?

    private struct Change {
        let cell: Int
        let before: DailyGridMark
        let batch: Int
    }
    private var history: [Change] = []
    private var batch = 0
    private var shownSecond = -1
    private var note: String?
    private var noteAge = 0.0
    private var feedback = Feedback.none
    private var nextSpark = 0
    private var nextFloat = 0
    private var finalSeconds = 0

    init(options: GameOptions, date: Date = Date()) {
        let day = DailyGridPuzzle.number(on: date)
        // One board a day for everyone, so the board comes from the day and not from the round's seed.
        let today = DailyGridPuzzle.make(seed: UInt64(day) &+ 0x4461_696C_79)
        number = day
        puzzle = today
        solo = options.solo
        limit = GameDemo.loseAfter.map { Swift.max(3, $0) } ?? Self.timeLimit
        board = DailyGridBoard(puzzle: today)
        sparks = Array(repeating: DailyGridSpark(), count: 96)
        floats = Array(repeating: DailyGridFloat(), count: 4)
        history.reserveCapacity(128)

        if !options.solo {
            // Friends' times today. They come from the day too, so a second round sees the same friends.
            var rng = DailyGridRandom(seed: UInt64(day), salt: 0x6672_6965)
            let names = Array(options.friendNames.filter { !$0.isEmpty }.prefix(3))
            var bands: [ClosedRange<Int>] = [38...62, 63...104, 105...170]
            var k = bands.count - 1
            while k > 0 {
                bands.swapAt(k, rng.int(k + 1))
                k -= 1
            }
            for (i, name) in names.enumerated() {
                chips.append(DailyGridChip(name: name, seconds: rng.int(bands[i]), doneAge: nil))
            }
        }
        hud.sub = "Tap a square to start"
    }

    // MARK: Reading

    var crowns: Int { board.marks.reduce(0) { $0 + ($1 == .crown ? 1 : 0) } }
    var isLive: Bool { stage == .ready || stage == .playing }
    var cardIsUp: Bool { card != nil && endAge > Self.cardAt + 0.5 }

    var result: GameResult {
        let solved = board.solveAge >= 0
        let seconds = finalSeconds
        let score = solved ? Swift.max(100, 1000 - 4 * seconds) : correctCrowns * 15
        let line = card?.line
        guard !chips.isEmpty else {
            return GameResult(score: score, unit: "points", scoreText: solved ? DailyGridEase.clock(seconds) : nil, detail: line)
        }
        let quicker = chips.filter { !solved || $0.seconds < seconds }.count
        return GameResult(score: score, unit: "points", scoreText: solved ? DailyGridEase.clock(seconds) : nil,
                          detail: line, placement: 1 + quicker, playerCount: chips.count + 1)
    }

    private var correctCrowns: Int {
        var count = 0
        for i in 0..<board.marks.count where board.marks[i] == .crown && puzzle.isAnswer(i) { count += 1 }
        return count
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

    /// A finger lands on a square: empty, cross, crown, empty again. True when the square is now a
    /// cross, so a drag from here crosses out more squares.
    @discardableResult
    func press(_ cell: Int) -> Bool {
        guard isLive, cell >= 0, cell < board.marks.count else { return false }
        start()
        batch += 1
        let after: DailyGridMark
        switch board.marks[cell] {
        case .empty: after = .cross
        case .cross: after = .crown
        case .crown: after = .empty
        }
        set(cell, after)
        if after == .crown {
            placedCrown(cell)
        } else {
            owe(.tap)
        }
        checkSolved()
        return after == .cross
    }

    /// The finger slides onto another square while crossing out.
    func paint(_ cell: Int) {
        guard stage == .playing, cell >= 0, cell < board.marks.count, board.marks[cell] == .empty else { return }
        set(cell, .cross)
        owe(.tap)
    }

    func pressKey(_ key: Int) {
        guard isLive else { return }
        hud.keyDown = key
        hud.keyAge = 0
        switch key {
        case 0: undo()
        case 1: hint()
        default: clear()
        }
        checkSolved()
    }

    /// A tap on the card ends the round a little early.
    func skip() -> Bool {
        guard cardIsUp, stage == .solved || stage == .timeUp else { return false }
        stage = .finished
        return true
    }

    private func start() {
        if stage == .ready {
            stage = .playing
            setSub()
        }
    }

    private func undo() {
        start()
        guard let last = history.last else {
            owe(.tap)
            return
        }
        while let change = history.last, change.batch == last.batch {
            history.removeLast()
            board.marks[change.cell] = change.before
            board.age[change.cell] = 0
        }
        refresh()
        owe(.tap)
    }

    private func clear() {
        start()
        batch += 1
        var any = false
        for i in 0..<board.marks.count where board.marks[i] != .empty {
            set(i, .empty)
            any = true
        }
        if any { addFloat("Cleared", x: 3, y: 3, tint: 0) }
        owe(.place)
    }

    /// Takes away a crown that cannot stay, or else puts down the next right crown. Costs seconds.
    private func hint() {
        start()
        batch += 1
        let n = DailyGridPuzzle.n
        var target = -1
        for i in 0..<board.marks.count where board.marks[i] == .crown && !puzzle.isAnswer(i) {
            target = i
            break
        }
        if target >= 0 {
            set(target, .cross)
            addFloat("Not here", x: Double(target % n) + 0.5, y: Double(target / n) + 0.2, tint: 1)
        } else {
            for row in DailyGridClip.order(for: puzzle) {
                let cell = row * n + puzzle.solution[row]
                if board.marks[cell] == .crown { continue }
                set(cell, .crown)
                burst(at: cell, count: 10)
                target = cell
                break
            }
        }
        guard target >= 0 else { return }
        hints += 1
        time += Self.hintCost
        hud.timePop = 0
        board.hintCell = target
        board.hintAge = 0
        addFloat("+10s", x: Double(target % n) + 0.5, y: Double(target / n) - 0.1, tint: 1)
        owe(.place)
    }

    // MARK: Rules

    private func set(_ cell: Int, _ mark: DailyGridMark) {
        history.append(Change(cell: cell, before: board.marks[cell], batch: batch))
        board.marks[cell] = mark
        board.age[cell] = 0
        refresh()
    }

    private func refresh() {
        DailyGridPuzzle.conflicts(board.marks, regions: puzzle.regions, into: &board.conflict)
        if stage == .playing { setSub() }
    }

    private func placedCrown(_ cell: Int) {
        let n = DailyGridPuzzle.n
        let x = Double(cell % n) + 0.5, y = Double(cell / n) + 0.1
        if board.conflict[cell] {
            mistakes += 1
            addFloat(clash(cell), x: x, y: y, tint: 1)
            owe(.wrong)
            return
        }
        burst(at: cell, count: 12)
        addFloat("\(crowns) of 6", x: x, y: y, tint: 0)
        owe(.place)
    }

    /// Why a new crown cannot stay, in two words.
    private func clash(_ cell: Int) -> String {
        let n = DailyGridPuzzle.n
        let r = cell / n, c = cell % n
        var words = "Too close"
        for other in 0..<board.marks.count where other != cell && board.marks[other] == .crown {
            let ro = other / n, co = other % n
            if ro == r { return "Same row" }
            if co == c { return "Same column" }
            if puzzle.region(other) == puzzle.region(cell) { words = "Same colour" }
        }
        return words
    }

    private func checkSolved() {
        guard stage == .playing, crowns == DailyGridPuzzle.n, !board.conflict.contains(true) else { return }
        stage = .solved
        endAge = 0
        board.solveAge = 0
        board.hintCell = -1
        finalSeconds = Int(time.rounded(.down))
        hud.timeText = DailyGridEase.clock(finalSeconds)
        hud.sub = "Solved"
        hud.pulse = 0
        praise = hints == 0 && mistakes == 0 ? "PERFECT" : (hints == 0 ? "GREAT" : "NICE")
        for i in 0..<board.marks.count where board.marks[i] == .crown { burst(at: i, count: 14, gold: true) }
        card = makeCard(solved: true)
        owe(.done)
    }

    private func runOut() {
        stage = .timeUp
        endAge = 0
        board.reveal = true
        finalSeconds = Int(limit)
        hud.sub = "Out of time"
        card = makeCard(solved: false)
        owe(.wrong)
    }

    private func makeCard(solved: Bool) -> DailyGridCard {
        let mine = finalSeconds
        var rows: [DailyGridRow] = chips.map { DailyGridRow(rank: 0, name: $0.name, time: DailyGridEase.clock($0.seconds), you: false) }
        let you = DailyGridRow(rank: 0, name: "You", time: solved ? DailyGridEase.clock(mine) : "Not yet", you: true)
        var times = chips.map { $0.seconds }
        rows.append(you)
        times.append(solved ? mine : Int.max)
        let order = times.indices.sorted { a, b in times[a] != times[b] ? times[a] < times[b] : rows[b].you }
        var ranked: [DailyGridRow] = []
        for (k, i) in order.enumerated() {
            var row = rows[i]
            row.rank = k + 1
            ranked.append(row)
        }

        let line: String
        if !solved {
            line = "\(correctCrowns) of 6 crowns in the right place"
        } else if chips.isEmpty {
            line = hints == 0 ? "Solved with no hints" : (hints == 1 ? "Solved with 1 hint" : "Solved with \(hints) hints")
        } else {
            let slower = chips.filter { $0.seconds > mine }.count
            if slower == chips.count {
                line = "Fastest of your friends today"
            } else if slower == 0 {
                line = "Your friends were quicker today"
            } else {
                line = "Faster than \(slower) of \(chips.count) friends"
            }
        }
        return DailyGridCard(title: solved ? "PUZZLE \(number) SOLVED" : "OUT OF TIME",
                             time: DailyGridEase.clock(mine), line: line,
                             rows: chips.isEmpty ? [] : ranked, age: 0)
    }

    private func setSub() {
        if let note {
            hud.sub = note
            return
        }
        hud.sub = "\(crowns) of 6 crowns"
        hud.pulse = 0
    }

    // MARK: Juice

    private func burst(at cell: Int, count: Int, gold: Bool = false) {
        let n = DailyGridPuzzle.n
        let cx = Double(cell % n) + 0.5, cy = Double(cell / n) + 0.5
        var rng = DailyGridRandom(seed: UInt64(cell * 977 + nextSpark) &+ UInt64(ambient * 1000))
        for _ in 0..<count {
            let angle = rng.range(0, 2 * Double.pi)
            let speed = rng.range(gold ? 1.4 : 0.9, gold ? 3.6 : 2.4)
            var spark = DailyGridSpark()
            spark.x = cx
            spark.y = cy
            spark.vx = cos(angle) * speed
            spark.vy = sin(angle) * speed - 0.8
            spark.age = 0
            spark.life = rng.range(0.45, gold ? 1.1 : 0.7)
            spark.size = rng.range(2.6, gold ? 6 : 4.5)
            spark.tint = gold && rng.next() < 0.5 ? -1 : puzzle.region(cell)
            sparks[nextSpark] = spark
            nextSpark = (nextSpark + 1) % sparks.count
        }
    }

    private func addFloat(_ text: String, x: Double, y: Double, tint: Int) {
        floats[nextFloat] = DailyGridFloat(text: text, x: x, y: y, age: 0, tint: tint)
        nextFloat = (nextFloat + 1) % floats.count
    }

    // MARK: Clock

    func step(dt raw: Double) {
        let dt = Swift.min(Swift.max(raw, 0), 1.0 / 30)
        if dt <= 0 { return }
        ambient += dt
        board.ambient = ambient
        for i in 0..<board.age.count where board.age[i] < 5 { board.age[i] += dt }
        board.hintAge += dt
        hud.keyAge += dt
        hud.timePop += dt
        for i in 0..<sparks.count where sparks[i].age < sparks[i].life {
            sparks[i].age += dt
            sparks[i].vy += 4.5 * dt
            sparks[i].x += sparks[i].vx * dt
            sparks[i].y += sparks[i].vy * dt
        }
        for i in 0..<floats.count where floats[i].age < 1 { floats[i].age += dt }
        for i in chips.indices { if let done = chips[i].doneAge { chips[i].doneAge = done + dt } }

        switch stage {
        case .ready:
            hud.pulse = ambient
        case .playing:
            time += dt
            tickClock()
            for i in chips.indices where chips[i].doneAge == nil && time >= Double(chips[i].seconds) {
                chips[i].doneAge = 0
                note = "\(chips[i].name) solved it in \(DailyGridEase.clock(chips[i].seconds))"
                noteAge = 0
                setSub()
            }
            if note != nil {
                noteAge += dt
                if noteAge >= Self.noteLength {
                    note = nil
                    setSub()
                }
            }
            if time >= limit { runOut() }
        case .solved:
            endAge += dt
            board.solveAge = endAge
            if endAge >= Self.cardAt { card?.age = endAge - Self.cardAt }
            if endAge >= Self.solvedLength { stage = .finished }
        case .timeUp:
            endAge += dt
            if endAge >= 1.4 { card?.age = endAge - 1.4 }
            if endAge >= Self.timeUpLength { stage = .finished }
        case .finished:
            break
        }
    }

    private func tickClock() {
        let second = Int(time.rounded(.down))
        if second == shownSecond { return }
        shownSecond = second
        hud.timeText = DailyGridEase.clock(second)
        hud.alert = limit - time <= 30
    }
}

extension DailyGridClip {
    /// The order a careful player puts the crowns down: smallest region first.
    static func order(for puzzle: DailyGridPuzzle) -> [Int] {
        let n = DailyGridPuzzle.n
        var sizes = Array(repeating: 0, count: n)
        for k in puzzle.regions { sizes[k] += 1 }
        return (0..<n).sorted { a, b in
            let ka = sizes[puzzle.regions[a * n + puzzle.solution[a]]]
            let kb = sizes[puzzle.regions[b * n + puzzle.solution[b]]]
            return ka != kb ? ka < kb : a < b
        }
    }
}

// MARK: - Drawing

/// Paints the model as it is right now, over the backdrop.
struct DailyGridCanvas: View {
    let model: DailyGridModel
    /// A new number every frame. The model is a class, so this is what makes SwiftUI repaint.
    var frame = 0

    var body: some View {
        Canvas(opaque: false, colorMode: .nonLinear, rendersAsynchronously: false) { context, size in
            if size.width <= 8 || size.height <= 8 { return }
            Self.paint(model, &context, size)
        }
    }

    static func paint(_ model: DailyGridModel, _ ctx: inout GraphicsContext, _ size: CGSize) {
        let painter = DailyGridPainter(size: size)
        painter.paintBoard(&ctx, model.board)
        painter.paintHUD(&ctx, model.hud)
        painter.paintChips(&ctx, model.chips, ambient: model.ambient)
        painter.paintSparks(&ctx, model.sparks)
        painter.paintFloats(&ctx, model.floats)
        if let praise = model.praise {
            painter.paintPraise(&ctx, praise, age: model.endAge - 0.15)
        }
        if let card = model.card { painter.paintCard(&ctx, card) }
    }
}

/// The page, the title, the keys at rest and the rules. Painted once.
struct DailyGridBackdrop: View, Equatable {
    var body: some View {
        Canvas(opaque: true, colorMode: .nonLinear, rendersAsynchronously: false) { context, size in
            if size.width <= 8 || size.height <= 8 { return }
            DailyGridPainter(size: size).paintBackdrop(&context, showHUD: true)
        }
    }
}

// MARK: - Scripted player

/// Plays the round for recordings while GameDemo.autopilot is on. It solves the way a person does:
/// smallest region first, a cross or two to think with, then the crown with two quick taps. With
/// GameDemo.loseAfter set it slips, puts a crown where it clashes, and lets the clock run out.
final class DailyGridPilot {
    private enum Step {
        case cell(Int)
        case key(Int)
    }

    private var plan: [(at: Double, step: Step)] = []
    private var next = 0

    init(model: DailyGridModel, seed: UInt64) {
        var rng = DailyGridRandom(seed: seed ^ 0x7069_6C6F_74)
        let puzzle = model.puzzle
        let n = DailyGridPuzzle.n
        let losing = GameDemo.loseAfter != nil
        var t = 0.9
        var crosses = Set<Int>()
        for (k, row) in DailyGridClip.order(for: puzzle).enumerated() {
            let answer = row * n + puzzle.solution[row]
            if k < 4 && rng.next() < 0.6 {
                let region = puzzle.region(answer)
                let spare = (0..<(n * n)).filter { $0 != answer && puzzle.region($0) == region && !crosses.contains($0) }
                if !spare.isEmpty {
                    let cell = spare[rng.int(spare.count)]
                    crosses.insert(cell)
                    plan.append((at: t, step: Step.cell(cell)))
                    t += rng.range(0.45, 0.7)
                }
            }
            if losing && k == 3 {
                // The slip: a crown right next to the last one, then it stops to think for good.
                let prev = DailyGridClip.order(for: puzzle)[k - 1]
                let col = puzzle.solution[prev]
                let wrong = prev * n + (col + 1 < n ? col + 1 : col - 1)
                if !crosses.contains(wrong) { plan.append((at: t, step: Step.cell(wrong))) }
                plan.append((at: t + 0.16, step: Step.cell(wrong)))
                return
            }
            plan.append((at: t, step: Step.cell(answer)))
            plan.append((at: t + 0.16, step: Step.cell(answer)))
            t += rng.range(1.0, 1.6)
        }
    }

    func play(_ runner: DailyGridRunner, link: GameLink) {
        let model = runner.model
        guard model.isLive else { return }
        while next < plan.count && model.ambient >= plan[next].at {
            switch plan[next].step {
            case .cell(let cell): runner.tapCell(cell, link: link)
            case .key(let key): runner.tapKey(key, link: link)
            }
            next += 1
        }
    }
}

// MARK: - Game view

/// Holds the round between frames. Nothing is published: the timeline repaints every frame anyway.
final class DailyGridRunner: ObservableObject {
    let model: DailyGridModel
    private let seed: UInt64
    private var lastDate: Date?
    private var frame = 0
    private var reported = false
    private var pilot: DailyGridPilot?
    /// The touch in progress: whether it crosses out what it slides over, and the last square it was on.
    private var touching = false
    private var crossing = false
    private var lastCell = -1

    init(options: GameOptions) {
        model = DailyGridModel(options: options)
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
        while owed > 1e-6 {
            let dt = Swift.min(owed, 1.0 / 60)
            owed -= dt
            model.step(dt: dt)
            if GameDemo.autopilot {
                if pilot == nil { pilot = DailyGridPilot(model: model, seed: seed) }
                pilot?.play(self, link: link)
            }
            settle(link)
        }
        frame &+= 1
        return frame
    }

    func touchBegan(at point: CGPoint, size: CGSize, link: GameLink) {
        if touching { return }
        touching = true
        crossing = false
        lastCell = -1
        if link.paused || link.isFinished { return }
        if model.skip() {
            settle(link)
            return
        }
        let layout = DailyGridLayout(size: size)
        if let cell = layout.cell(at: point) {
            lastCell = cell
            crossing = model.press(cell)
        } else if let key = layout.key(at: point) {
            model.pressKey(key)
        } else if model.stage == .ready {
            GameHaptics.tap()
        }
        settle(link)
    }

    func touchMoved(to point: CGPoint, size: CGSize, link: GameLink) {
        guard touching, crossing, !link.paused else { return }
        guard let cell = DailyGridLayout(size: size).cell(at: point), cell != lastCell else { return }
        lastCell = cell
        model.paint(cell)
        settle(link)
    }

    func touchEnded() {
        touching = false
        crossing = false
        lastCell = -1
    }

    /// The scripted player's taps go through the same calls a finger uses.
    func tapCell(_ cell: Int, link: GameLink) {
        if link.paused || link.isFinished { return }
        model.press(cell)
        settle(link)
    }

    func tapKey(_ key: Int, link: GameLink) {
        if link.paused || link.isFinished { return }
        model.pressKey(key)
        settle(link)
    }

    /// Plays the haptic the model owes and reports the round once it is over.
    private func settle(_ link: GameLink) {
        switch model.takeFeedback() {
        case .done:
            GameHaptics.heavy()
            GameHaptics.success()
        case .wrong: GameHaptics.fail()
        case .place: GameHaptics.thud()
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

public struct DailyGridGame: View {
    private let options: GameOptions
    private let link: GameLink

    public init(options: GameOptions, link: GameLink) {
        self.options = options
        self.link = link
    }

    public var body: some View {
        // A new link is a new round, so the round's state lives and dies with the link.
        DailyGridRound(options: options, link: link)
            .id(ObjectIdentifier(link))
    }
}

private struct DailyGridRound: View {
    @ObservedObject var link: GameLink
    @StateObject private var runner: DailyGridRunner

    init(options: GameOptions, link: GameLink) {
        self.link = link
        _runner = StateObject(wrappedValue: DailyGridRunner(options: options))
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                DailyGridBackdrop().equatable()
                TimelineView(.animation(minimumInterval: nil, paused: link.paused)) { timeline in
                    DailyGridCanvas(model: runner.model, frame: runner.advance(to: timeline.date, link: link))
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        runner.touchBegan(at: value.startLocation, size: size, link: link)
                        runner.touchMoved(to: value.location, size: size, link: link)
                    }
                    .onEnded { _ in runner.touchEnded() }
            )
        }
        .ignoresSafeArea()
        .accessibilityElement()
        .accessibilityLabel("Daily Grid. Place one crown in every row, column and colour.")
        .accessibilityAddTraits(.allowsDirectInteraction)
    }
}
