import SwiftUI

// Daily Grid, playable.
//
// DailyGridModel   the rules of a round in plain Swift: step(dt:), tap(cell:) and the three keys.
// DailyGridCanvas  paints one frame of the model with the clip's painter.
// DailyGridPilot   the scripted player. It only runs while GameDemo.autopilot is on.
// DailyGridRunner  keeps the clock, passes touches on, fires haptics, reports the result.
// DailyGridGame    the view the app shows.
//
// A round is three minutes of boards. Each solved board is worth points, more when it is solved
// quickly. A crown that breaks a rule costs one of three tries; the round ends when the tries or
// the time run out.

// MARK: - Making puzzles

extension DailyGridPuzzle {
    /// A fresh board with exactly one solution, from the round's random numbers. Falls back to a
    /// stock board when the tries run out, which the counts in practice make very rare.
    static func make(_ rng: inout DailyGridRandom, fallback: Int) -> DailyGridPuzzle {
        var tries = 0
        while tries < 700 {
            tries += 1
            var solution = Array(repeating: -1, count: size)
            var usedCol = Array(repeating: false, count: size)
            if !place(row: 0, solution: &solution, usedCol: &usedCol, rng: &rng) { continue }
            let regions = grow(solution: solution, rng: &rng)
            if solutionCount(regions: regions) == 1 {
                return DailyGridPuzzle(solution: solution, regions: regions)
            }
        }
        return stock[((fallback % stock.count) + stock.count) % stock.count]
    }

    /// Places one crown per row at random, no two in a column and none touching.
    private static func place(row: Int, solution: inout [Int], usedCol: inout [Bool], rng: inout DailyGridRandom) -> Bool {
        if row == size { return true }
        var cols: [Int] = Array(0..<size)
        rng.shuffle(&cols)
        for c in cols {
            if usedCol[c] { continue }
            if row > 0 && abs(c - solution[row - 1]) <= 1 { continue }
            solution[row] = c
            usedCol[c] = true
            if place(row: row + 1, solution: &solution, usedCol: &usedCol, rng: &rng) { return true }
            usedCol[c] = false
        }
        solution[row] = -1
        return false
    }

    /// Grows a colour region out of each crown until the board is covered.
    private static func grow(solution: [Int], rng: inout DailyGridRandom) -> [Int] {
        var regions = Array(repeating: -1, count: cells)
        for r in 0..<size { regions[r * size + solution[r]] = r }
        var left = cells - size
        var frontier: [Int] = []
        frontier.reserveCapacity(cells)
        var guardCount = 0
        while left > 0 && guardCount < 4000 {
            guardCount += 1
            let k = rng.int(size)
            frontier.removeAll(keepingCapacity: true)
            for i in 0..<cells where regions[i] == k {
                let r = i / size
                let c = i % size
                if r > 0 && regions[i - size] == -1 { frontier.append(i - size) }
                if r < size - 1 && regions[i + size] == -1 { frontier.append(i + size) }
                if c > 0 && regions[i - 1] == -1 { frontier.append(i - 1) }
                if c < size - 1 && regions[i + 1] == -1 { frontier.append(i + 1) }
            }
            if frontier.isEmpty { continue }
            regions[frontier[rng.int(frontier.count)]] = k
            left -= 1
        }
        // Only reached if the growth stalled, which it cannot on a connected board.
        for i in 0..<cells where regions[i] == -1 { regions[i] = 0 }
        return regions
    }

    /// How many ways the board can be solved, counted no further than 2.
    static func solutionCount(regions: [Int]) -> Int {
        var solution = Array(repeating: -1, count: size)
        var usedCol = Array(repeating: false, count: size)
        var usedRegion = Array(repeating: false, count: size)
        var found = 0
        count(row: 0, regions: regions, solution: &solution, usedCol: &usedCol, usedRegion: &usedRegion, found: &found)
        return found
    }

    private static func count(row: Int, regions: [Int], solution: inout [Int], usedCol: inout [Bool],
                              usedRegion: inout [Bool], found: inout Int) {
        if row == size {
            found += 1
            return
        }
        for c in 0..<size {
            if found >= 2 { return }
            if usedCol[c] { continue }
            if row > 0 && abs(c - solution[row - 1]) <= 1 { continue }
            let g = regions[row * size + c]
            if g < 0 || g >= size || usedRegion[g] { continue }
            usedCol[c] = true
            usedRegion[g] = true
            solution[row] = c
            count(row: row + 1, regions: regions, solution: &solution, usedCol: &usedCol, usedRegion: &usedRegion, found: &found)
            usedCol[c] = false
            usedRegion[g] = false
        }
    }
}

// MARK: - Model

final class DailyGridModel {
    enum Stage { case ready, playing, solved, ending, finished }

    /// What the last step or input deserves as a haptic. A stronger one replaces a weaker one.
    enum Feedback: Int { case none, mark, crown, hint, conflict, solved, over }

    struct Friend {
        let name: String
        /// This friend's points today.
        let points: Int
    }

    // Tuning. Times in seconds.
    static let roundLength = 180.0
    static let tries = 3
    static let solvedPause = 1.5           // the sparkle, before the next board comes up
    static let endLength = 1.6
    static let hintCost = 15.0             // taken off the clock
    static let basePoints = 100            // for every solved board
    static let speedPoints = 60            // less one for every second the board took
    static let praiseLength = 1.4

    let solo: Bool
    private let seed: UInt64
    private var rng: DailyGridRandom

    private(set) var stage = Stage.ready
    private(set) var puzzle: DailyGridPuzzle
    private(set) var marks: [DailyGridMark] = Array(repeating: .empty, count: DailyGridPuzzle.cells)
    private(set) var conflict: [Bool] = Array(repeating: false, count: DailyGridPuzzle.cells)
    /// When each square last changed, in ambient time.
    private(set) var changedAt: [Double] = Array(repeating: -10, count: DailyGridPuzzle.cells)
    private var undoCells: [Int] = []
    private var undoMarks: [DailyGridMark] = []

    private(set) var gridNumber = 1
    private(set) var solvedCount = 0
    /// Three gold for a board solved, five when it took under 25 seconds.
    private(set) var gold = 0
    private(set) var score = 0
    private(set) var lives = DailyGridModel.tries
    private(set) var timeLeft = DailyGridModel.roundLength
    /// Seconds spent on the current board.
    private(set) var gridTime = 0.0
    /// Seconds since the current board came up.
    private(set) var boardAge = 0.0
    private(set) var fastest: Double?
    /// Scenery clock: runs whenever the game is not paused.
    private(set) var ambient = 0.0
    /// Time in the solved pause or the ending.
    private(set) var stageClock = 0.0
    private(set) var praise: String?
    private(set) var praiseAge = 0.0
    private(set) var floatText: String?
    private(set) var floatAge = 0.0
    private(set) var sparks: [DailyGridSpark] = []
    private(set) var pressedAt: [Double] = [-10, -10, -10]
    private(set) var endText: String?
    private(set) var friends: [Friend] = []

    private var feedback = Feedback.none

    init(options: GameOptions) {
        solo = options.solo
        seed = options.seed
        rng = DailyGridRandom(seed: options.seed, salt: DailyGridRandom.round)
        puzzle = DailyGridPuzzle.stock[0]
        puzzle = DailyGridPuzzle.make(&rng, fallback: 0)
        undoCells.reserveCapacity(64)
        undoMarks.reserveCapacity(64)
        sparks = DailyGridClip.sparks(seed: options.seed)

        if !options.solo {
            let names = Array(options.friendNames.filter { !$0.isEmpty }.prefix(3))
            let bands: [ClosedRange<Int>]
            switch names.count {
            case 3: bands = [120...320, 330...560, 580...900]
            case 2: bands = [120...420, 430...900]
            default: bands = [120...900]
            }
            // The seed decides who had the slow, the middle and the quick day.
            var order: [Int] = Array(bands.indices)
            rng.shuffle(&order)
            for (k, name) in names.enumerated() {
                friends.append(Friend(name: name, points: rng.int(bands[order[k]])))
            }
        }
    }

    // MARK: Reading

    /// Seconds of the round played so far.
    var playTime: Double { DailyGridModel.roundLength - timeLeft }

    var solvedAge: Double? { stage == .solved ? stageClock : nil }

    var crownCount: Int {
        var n = 0
        for m in marks where m == .crown { n += 1 }
        return n
    }

    var timerText: String {
        let whole = Int(ceil(Swift.max(0, timeLeft)))
        return "\(whole / 60):" + String(format: "%02d", whole % 60)
    }

    var result: GameResult {
        var line: String
        switch solvedCount {
        case 0: line = "No board solved"
        case 1: line = "1 board solved"
        default: line = "\(solvedCount) boards solved"
        }
        if let best = fastest {
            let whole = Int(best.rounded())
            line += ", quickest " + (whole < 60 ? "\(whole)s" : "\(whole / 60)m \(whole % 60)s")
        }
        guard !friends.isEmpty else { return GameResult(score: score, unit: "points", detail: line) }
        let ahead = friends.filter { $0.points > score }.count
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

    // MARK: Input

    /// Cycles a square: empty, cross, crown, empty. The first tap of the round starts the clock.
    /// False when the tap did nothing.
    @discardableResult
    func tap(cell: Int) -> Bool {
        guard cell >= 0, cell < DailyGridPuzzle.cells, stage == .ready || stage == .playing else { return false }
        stage = .playing
        let before = marks[cell]
        let after: DailyGridMark
        switch before {
        case .empty: after = .cross
        case .cross: after = .crown
        case .crown: after = .empty
        }
        remember(cell)
        marks[cell] = after
        changedAt[cell] = ambient
        refreshConflicts()
        if after == .crown && conflict[cell] {
            lives -= 1
            owe(.conflict)
            if lives <= 0 {
                beginEnding("Out of tries")
                return true
            }
        } else {
            owe(after == .crown ? .crown : .mark)
        }
        checkSolved()
        return true
    }

    /// Key 0: undo, 1: hint, 2: clear. False when the key did nothing.
    @discardableResult
    func press(key: Int) -> Bool {
        guard key >= 0, key < 3, stage == .ready || stage == .playing else { return false }
        pressedAt[key] = ambient
        switch key {
        case 0:
            guard let cell = undoCells.popLast(), let mark = undoMarks.popLast() else { return false }
            marks[cell] = mark
            changedAt[cell] = ambient
            refreshConflicts()
            owe(.mark)
            checkSolved()
            return true
        case 1:
            return hint()
        default:
            if marks.allSatisfy({ $0 == .empty }) { return false }
            for i in 0..<DailyGridPuzzle.cells where marks[i] != .empty {
                marks[i] = .empty
                changedAt[i] = ambient
            }
            undoCells.removeAll(keepingCapacity: true)
            undoMarks.removeAll(keepingCapacity: true)
            refreshConflicts()
            owe(.mark)
            checkSolved()
            return true
        }
    }

    /// Puts a crown where one belongs, in the first row that has none, for fifteen seconds.
    private func hint() -> Bool {
        var target = -1
        for row in 0..<DailyGridPuzzle.size where target < 0 {
            var hasCrown = false
            for col in 0..<DailyGridPuzzle.size where marks[row * DailyGridPuzzle.size + col] == .crown { hasCrown = true }
            if !hasCrown { target = puzzle.solutionCell(row: row) }
        }
        if target < 0 {
            for row in 0..<DailyGridPuzzle.size where target < 0 && marks[puzzle.solutionCell(row: row)] != .crown {
                target = puzzle.solutionCell(row: row)
            }
        }
        if target < 0 { return false }
        stage = .playing
        remember(target)
        marks[target] = .crown
        changedAt[target] = ambient
        timeLeft = Swift.max(0, timeLeft - DailyGridModel.hintCost)
        refreshConflicts()
        owe(.hint)
        if timeLeft <= 0 {
            beginEnding("Time")
            return true
        }
        checkSolved()
        return true
    }

    private func remember(_ cell: Int) {
        if undoCells.count >= 200 {
            undoCells.removeFirst()
            undoMarks.removeFirst()
        }
        undoCells.append(cell)
        undoMarks.append(marks[cell])
    }

    // MARK: Clock

    func step(dt raw: Double) {
        let dt = Swift.min(Swift.max(raw, 0), 1.0 / 30)
        if dt <= 0 { return }
        ambient += dt
        if stage == .finished { return }

        boardAge += dt
        if praise != nil {
            praiseAge += dt
            if praiseAge >= DailyGridModel.praiseLength { praise = nil }
        }
        if floatText != nil {
            floatAge += dt
            if floatAge >= DailyGridModel.praiseLength { floatText = nil }
        }

        switch stage {
        case .ready:
            break
        case .playing:
            timeLeft -= dt
            gridTime += dt
            if timeLeft <= 0 {
                timeLeft = 0
                beginEnding("Time")
            }
        case .solved:
            stageClock += dt
            if stageClock >= DailyGridModel.solvedPause { nextBoard() }
        case .ending:
            stageClock += dt
            if stageClock >= DailyGridModel.endLength { stage = .finished }
        case .finished:
            break
        }
    }

    // MARK: Rules

    /// Marks every crown that shares a row, a column or a colour with another, or touches one.
    private func refreshConflicts() {
        let n = DailyGridPuzzle.size
        for i in 0..<DailyGridPuzzle.cells { conflict[i] = false }
        for i in 0..<DailyGridPuzzle.cells where marks[i] == .crown {
            let ri = i / n
            let ci = i % n
            for j in (i + 1)..<DailyGridPuzzle.cells where marks[j] == .crown {
                let rj = j / n
                let cj = j % n
                let touching = abs(ri - rj) <= 1 && abs(ci - cj) <= 1
                if ri == rj || ci == cj || puzzle.regions[i] == puzzle.regions[j] || touching {
                    conflict[i] = true
                    conflict[j] = true
                }
            }
        }
    }

    /// Six crowns with no conflict between them fill every row, column and colour exactly once.
    /// Runs after every change to the marks, so a board that becomes whole by taking a wrong
    /// crown away counts too.
    private func checkSolved() {
        if stage != .playing || crownCount != DailyGridPuzzle.size { return }
        for i in 0..<DailyGridPuzzle.cells where conflict[i] { return }
        let points = DailyGridModel.basePoints + Swift.max(0, DailyGridModel.speedPoints - Int(gridTime))
        score += points
        solvedCount += 1
        gold += gridTime < 25 ? 5 : 3
        fastest = Swift.min(fastest ?? gridTime, gridTime)
        praise = gridTime < 25 ? "Perfect" : (gridTime < 50 ? "Great" : "Nice")
        praiseAge = 0
        floatText = "+\(points)"
        floatAge = 0
        sparks = DailyGridClip.sparks(seed: seed &+ UInt64(solvedCount))
        stage = .solved
        stageClock = 0
        owe(.solved)
    }

    private func nextBoard() {
        gridNumber += 1
        puzzle = DailyGridPuzzle.make(&rng, fallback: gridNumber)
        for i in 0..<DailyGridPuzzle.cells {
            marks[i] = .empty
            conflict[i] = false
            changedAt[i] = -10
        }
        undoCells.removeAll(keepingCapacity: true)
        undoMarks.removeAll(keepingCapacity: true)
        gridTime = 0
        boardAge = 0
        stageClock = 0
        stage = .playing
    }

    private func beginEnding(_ words: String) {
        endText = words
        stage = .ending
        stageClock = 0
        owe(.over)
    }
}

// MARK: - From the model to a frame

extension DailyGridFrame {
    init(model: DailyGridModel) {
        self.init()
        regions = model.puzzle.regions
        marks = model.marks
        conflict = model.conflict
        clock = model.ambient
        changedAt = model.changedAt
        boardAge = model.boardAge
        timerText = model.timerText
        timerUrgent = model.stage == .playing && model.timeLeft < 10
        scoreText = model.score == 1 ? "1 point" : "\(model.score) points"
        gridText = "Grid \(model.gridNumber)"
        lives = model.lives
        switch model.stage {
        case .ready: hintAlpha = 0.85 + 0.15 * sin(model.ambient * 3)
        case .playing: hintAlpha = Swift.max(0, 1 - model.playTime / 0.25)
        default: hintAlpha = 0
        }
        praise = model.praise
        praiseAge = model.praiseAge
        floatText = model.floatText
        floatAge = model.floatAge
        solvedAge = model.solvedAge
        sparks = model.sparks
        pressedAt = model.pressedAt
        endText = model.endText
        endAge = model.stage == .ending || model.stage == .finished ? model.stageClock : 0
    }
}

/// Paints the model as it is right now.
struct DailyGridCanvas: View {
    let model: DailyGridModel
    /// A new number every frame. The model is a class, so this is what makes SwiftUI repaint.
    var frame = 0

    var body: some View {
        Canvas(opaque: true, colorMode: .nonLinear, rendersAsynchronously: false) { context, size in
            if size.width <= 8 || size.height <= 8 { return }
            DailyGridPainter(size: size).draw(&context, DailyGridFrame(model: model))
        }
    }
}

// MARK: - Scripted player

/// Plays the round for recordings while GameDemo.autopilot is on.
///
/// It reads the model and queues taps on squares, which go through the same call a finger uses.
/// It knows the answer, so it marks a few crosses, slips once per board with a crown it takes
/// back, then places the crowns. Past GameDemo.loseAfter it puts crowns next to each other until
/// the tries are gone.
struct DailyGridPilot {
    static let readyHold = 0.9

    private struct Tap {
        let cell: Int
        /// How long to wait after this tap before the next.
        let delay: Double
    }

    private var rng: DailyGridRandom
    private var queue: [Tap] = []
    /// The ambient time the next tap may happen.
    private var nextAt = 0.0
    private var plannedBoard = 0
    private var losing = false

    init(seed: UInt64) {
        rng = DailyGridRandom(seed: seed ^ 0x7069_6C6F_7421, salt: DailyGridRandom.pilot)
        queue.reserveCapacity(40)
    }

    /// Call once per step, after the model has moved. Returns the square to tap now, if any.
    mutating func nextTap(_ model: DailyGridModel) -> Int? {
        guard model.stage == .ready || model.stage == .playing else { return nil }
        if model.stage == .ready, model.ambient < Self.readyHold { return nil }

        if let limit = GameDemo.loseAfter, !losing, model.stage == .playing, model.playTime >= limit {
            losing = true
            queue.removeAll(keepingCapacity: true)
        }
        if losing {
            if queue.isEmpty { planLoss(model) }
        } else if plannedBoard != model.gridNumber {
            plannedBoard = model.gridNumber
            queue.removeAll(keepingCapacity: true)
            planBoard(model)
        }
        guard model.ambient >= nextAt, !queue.isEmpty else { return nil }
        let tap = queue.removeFirst()
        nextAt = model.ambient + tap.delay
        return tap.cell
    }

    private mutating func planBoard(_ model: DailyGridModel) {
        let puzzle = model.puzzle
        var others: [Int] = []
        others.reserveCapacity(DailyGridPuzzle.cells)
        for i in 0..<DailyGridPuzzle.cells where !puzzle.isSolutionCell(i) { others.append(i) }
        rng.shuffle(&others)

        // A few crosses first, the way a person rules squares out.
        let crosses = rng.int(2...4)
        for k in 0..<Swift.min(crosses, others.count) {
            queue.append(Tap(cell: others[k], delay: rng.range(0.4, 0.7)))
        }
        // One slip: a crown on the wrong square, noticed and taken back.
        if rng.next() < 0.6, others.count > crosses {
            let slip = others[crosses]
            queue.append(Tap(cell: slip, delay: 0.22))
            queue.append(Tap(cell: slip, delay: rng.range(0.7, 1.1)))
            queue.append(Tap(cell: slip, delay: rng.range(0.4, 0.6)))
        }
        // Then the crowns, row by row in a random order.
        var rows: [Int] = Array(0..<DailyGridPuzzle.size)
        rng.shuffle(&rows)
        for row in rows {
            let cell = puzzle.solutionCell(row: row)
            queue.append(Tap(cell: cell, delay: 0.22))
            queue.append(Tap(cell: cell, delay: rng.range(0.5, 0.95)))
        }
    }

    /// Queues one crown that breaks the touching rule, given the board as it is now.
    private mutating func planLoss(_ model: DailyGridModel) {
        let n = DailyGridPuzzle.size
        var anchor = -1
        for i in 0..<DailyGridPuzzle.cells where model.marks[i] == .crown {
            anchor = i
            break
        }
        if anchor < 0 {
            let cell = model.puzzle.solutionCell(row: 0)
            queue.append(Tap(cell: cell, delay: 0.22))
            queue.append(Tap(cell: cell, delay: 0.8))
            return
        }
        let r = anchor / n
        let c = anchor % n
        var target = -1
        for dr in -1...1 where target < 0 {
            for dc in -1...1 where target < 0 {
                if dr == 0 && dc == 0 { continue }
                let rr = r + dr
                let cc = c + dc
                if rr < 0 || rr >= n || cc < 0 || cc >= n { continue }
                let cell = rr * n + cc
                if model.marks[cell] != .crown { target = cell }
            }
        }
        if target < 0 {
            for i in 0..<DailyGridPuzzle.cells where target < 0 && model.marks[i] != .crown && i / n == r { target = i }
        }
        if target < 0 { return }
        if model.marks[target] == .empty { queue.append(Tap(cell: target, delay: 0.22)) }
        queue.append(Tap(cell: target, delay: rng.range(0.9, 1.3)))
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
    /// Made the first time it is needed, which is only when GameDemo.autopilot is on.
    private var pilot: DailyGridPilot?

    init(options: GameOptions) {
        model = DailyGridModel(options: options)
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
        var owed = Swift.min(Swift.max(date.timeIntervalSince(before), 0), 0.1)
        if owed <= 0 { return frame }
        while owed > 1e-6 {
            let dt = Swift.min(owed, 1.0 / 60)
            owed -= dt
            model.step(dt: dt)
            settle(link)
            if GameDemo.autopilot {
                if pilot == nil { pilot = DailyGridPilot(seed: seed) }
                if let cell = pilot?.nextTap(model) { tap(cell: cell, link: link) }
            }
        }
        frame &+= 1
        return frame
    }

    /// A finger landing anywhere on the screen.
    func touch(at point: CGPoint, in size: CGSize, link: GameLink) {
        if link.paused || link.isFinished { return }
        let layout = DailyGridLayout(size: size)
        if let cell = layout.cell(at: point) {
            tap(cell: cell, link: link)
        } else if let key = layout.key(at: point) {
            if model.press(key: key) {
                settle(link)
            } else {
                GameHaptics.tap()
            }
        }
    }

    func tap(cell: Int, link: GameLink) {
        if link.paused || link.isFinished { return }
        model.tap(cell: cell)
        settle(link)
    }

    /// Plays the haptic the model owes and reports the round once it is over.
    private func settle(_ link: GameLink) {
        switch model.takeFeedback() {
        case .over: GameHaptics.heavy()
        case .solved: GameHaptics.success()
        case .conflict: GameHaptics.fail()
        case .hint, .crown: GameHaptics.thud()
        case .mark: GameHaptics.tap()
        case .none: break
        }
        link.collect(model.gold)
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
    @GestureState private var touching = false

    init(options: GameOptions, link: GameLink) {
        self.link = link
        _runner = StateObject(wrappedValue: DailyGridRunner(options: options))
    }

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: nil, paused: link.paused)) { timeline in
                DailyGridCanvas(model: runner.model, frame: runner.advance(to: timeline.date, link: link))
            }
            .contentShape(Rectangle())
            .gesture(
                // Fires as the finger lands, once per touch. The flag clears itself when the touch
                // ends or is cancelled.
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .updating($touching) { value, down, _ in
                        if down { return }
                        down = true
                        runner.touch(at: value.startLocation, in: geo.size, link: link)
                    }
            )
        }
        .ignoresSafeArea()
        .accessibilityElement()
        .accessibilityLabel("Daily Grid. Tap a square once for a cross, twice for a crown.")
        .accessibilityAddTraits(.allowsDirectInteraction)
    }
}
