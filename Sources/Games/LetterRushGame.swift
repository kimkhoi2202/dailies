import SwiftUI

// Letter Rush, playable: drag through touching letters to make words before the 80 seconds run out.
//
// LetterRushSolver  finds every word on a board, for the friend, the scripted player and the results.
// LetterRushModel   the rules of a round in plain Swift: step(dt:), press, slide, lift.
// LetterRushPilot   the scripted player. It only runs while GameDemo.autopilot is on.
// LetterRushRunner  keeps the clock, turns touches into tiles, fires haptics, reports the result.
// LetterRushGame    the view the app shows.

// MARK: - Solver

struct LetterRushSolution {
    let word: String
    let path: [Int]
}

final class LetterRushSolver {
    /// The tiles touching each tile, diagonals included.
    static let neighbors: [[Int]] = (0..<16).map { index in
        var out: [Int] = []
        let row = index / 4
        let col = index % 4
        for dr in -1...1 {
            for dc in -1...1 where dr != 0 || dc != 0 {
                let r = row + dr
                let c = col + dc
                if r >= 0, r < 4, c >= 0, c < 4 { out.append(r * 4 + c) }
            }
        }
        return out
    }

    static func touching(_ a: Int, _ b: Int) -> Bool {
        a != b && abs(a / 4 - b / 4) <= 1 && abs(a % 4 - b % 4) <= 1
    }

    private let letters: [Character]
    private var used = [Bool](repeating: false, count: 16)
    private var path: [Int] = []
    private var found: [String: [Int]] = [:]

    init(letters: [Character]) {
        self.letters = letters
    }

    /// Every word on the board, longest first.
    func run() -> [LetterRushSolution] {
        for start in 0..<16 { visit(start, "") }
        return found.map { LetterRushSolution(word: $0.key, path: $0.value) }
            .sorted { $0.word.count != $1.word.count ? $0.word.count > $1.word.count : $0.word < $1.word }
    }

    private func visit(_ index: Int, _ prefix: String) {
        var next = prefix
        next.append(letters[index])
        guard LetterRushWords.prefixes.contains(next) else { return }
        used[index] = true
        path.append(index)
        if next.count >= 3, found[next] == nil, LetterRushWords.all.contains(next) { found[next] = path }
        if next.count < 8 {
            for n in Self.neighbors[index] where !used[n] { visit(n, next) }
        }
        path.removeLast()
        used[index] = false
    }
}

// MARK: - Model

final class LetterRushModel {
    typealias M = LetterRushMath

    enum Stage { case ready, playing, ending, finished }

    /// What the last step or touch deserves as a haptic. A stronger one replaces a weaker one.
    enum Feedback: Int { case none, tick, wrong, good, great, end }

    struct FriendFind {
        let time: Double
        let word: String
        let points: Int
    }

    static let roundLength = 80.0
    static let endHold = 7.5
    static let autopilotHold = 5.0
    static let continueAfter = 1.4

    /// Letter cubes, one face each. Shuffled and rolled from the seed, so friends get the same board.
    private static let dice = [
        "AAEEGN", "ABBJOO", "ACHOPS", "AFFKPS", "AOOTTW", "CIMOTU", "DEILRX", "DELRVY",
        "DISTTY", "EEGHNW", "EEINSU", "EHRTVW", "EIOSST", "ELRTTY", "HIMNSU", "HLNNRZ",
    ]

    let letters: [Character]
    let labels: [String]
    /// Every word on the board, longest first.
    let solutions: [LetterRushSolution]
    let friendName: String?
    let friendPlan: [FriendFind]
    let bestScore: Int

    var layout = LetterRushLayout(size: CGSize(width: 402, height: 874))

    private(set) var stage = Stage.ready
    private(set) var ambient = 0.0
    private(set) var elapsed = 0.0
    private(set) var endClock = 0.0

    private(set) var path: [Int] = []
    private(set) var used = [Bool](repeating: false, count: 16)
    private(set) var popAge = [Double](repeating: 9, count: 16)
    private(set) var word = ""
    private(set) var wordState = LetterRushWordState.none

    private(set) var verdict = LetterRushVerdict.none
    private(set) var verdictTiles: [Int] = []
    private(set) var verdictWord = ""
    private(set) var verdictAge = 9.0

    private(set) var found: [LetterRushWordRow] = []
    private var foundSet = Set<String>()
    private(set) var score = 0
    private(set) var shownScore = 0.0

    private(set) var friendShown = 0
    private(set) var friendScore = 0
    private(set) var friendFlash = 9.0

    private(set) var floaters: [LetterRushFloater] = []
    private(set) var particles: [LetterRushParticle] = []
    private(set) var praise = ""
    private(set) var praiseAge = 9.0

    private(set) var results = LetterRushResults()
    private var continueAsked = false
    private var lastTick = 11
    private var feedback = Feedback.none
    private var sparks: LetterRushRandom

    init(options: GameOptions) {
        bestScore = Swift.max(0, options.bestScore)
        let board = Self.makeBoard(seed: options.seed)
        letters = board.letters
        labels = board.letters.map { String($0) }
        solutions = board.solutions
        sparks = LetterRushRandom(seed: options.seed, salt: LetterRushRandom.pilot ^ 0x5A5A)

        let name = options.friendNames.first { !$0.isEmpty }
        if options.solo || name == nil {
            friendName = nil
            friendPlan = []
        } else {
            friendName = name
            friendPlan = Self.planFriend(solutions: board.solutions, seed: options.seed)
        }
        path.reserveCapacity(16)
        verdictTiles.reserveCapacity(16)
        floaters.reserveCapacity(8)
        particles.reserveCapacity(140)
    }

    // MARK: Setting up

    private static func makeBoard(seed: UInt64) -> (letters: [Character], solutions: [LetterRushSolution]) {
        var rng = LetterRushRandom(seed: seed, salt: LetterRushRandom.board)
        var best: (letters: [Character], solutions: [LetterRushSolution])?
        for _ in 0..<24 {
            var order = Array(0..<16)
            var last = 15
            while last > 0 {
                order.swapAt(last, rng.int(last + 1))
                last -= 1
            }
            let letters: [Character] = order.map { die in
                let faces = Array(dice[die])
                return faces[rng.int(faces.count)]
            }
            let solutions = LetterRushSolver(letters: letters).run()
            let longest = solutions.first?.word.count ?? 0
            if solutions.count >= 45, longest >= 6 { return (letters, solutions) }
            if solutions.count > (best?.solutions.count ?? -1) { best = (letters, solutions) }
        }
        return best ?? (Array("PLAOENTSRIMEDCHK"), [])
    }

    /// The friend's whole round, worked out from the seed: real words from this board, short ones
    /// more often, found at a person's pace.
    private static func planFriend(solutions: [LetterRushSolution], seed: UInt64) -> [FriendFind] {
        var rng = LetterRushRandom(seed: seed, salt: LetterRushRandom.friend)
        let skill = rng.range(0.8, 1.2)
        var picks: [FriendFind] = []
        for s in solutions {
            let n = s.word.count
            let chance: Double
            switch n {
            case 3: chance = 0.5
            case 4: chance = 0.42
            case 5: chance = 0.27
            case 6: chance = 0.15
            default: chance = 0.07
            }
            if rng.next() < chance * skill {
                picks.append(FriendFind(time: rng.range(3, 78), word: s.word, points: M.points(n)))
            }
        }
        picks.sort { $0.time < $1.time }
        return Array(picks.prefix(30))
    }

    // MARK: Reading

    var timeLeft: Double { Self.roundLength - elapsed }
    var shown: Int { Int(shownScore.rounded()) }
    var friendWords: Int { friendShown }
    var canContinue: Bool { stage == .ending && endClock >= Self.continueAfter }

    var result: GameResult {
        var line = "No words this time"
        if let longest = found.max(by: { $0.word.count < $1.word.count }) {
            let count = found.count == 1 ? "1 word" : "\(found.count) words"
            line = "\(count). Longest: \(longest.word)"
        }
        guard friendName != nil else { return GameResult(score: score, unit: "points", detail: line) }
        let place = score >= friendScore ? 1 : 2
        return GameResult(score: score, unit: "points", detail: line, placement: place, playerCount: 2)
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

    /// A finger lands on a tile. The first touch starts the round.
    func press(_ tile: Int) {
        guard stage == .ready || stage == .playing else { return }
        stage = .playing
        clearPath()
        add(tile)
    }

    /// The finger moves onto a tile.
    func slide(_ tile: Int) {
        guard stage == .playing else { return }
        guard let last = path.last else {
            add(tile)
            return
        }
        if tile == last { return }
        if path.count >= 2, tile == path[path.count - 2] {
            // Back over the tile before: the last one lets go.
            used[last] = false
            path.removeLast()
            popAge[tile] = 0
            refreshWord()
            owe(.tick)
            return
        }
        if used[tile] || !LetterRushSolver.touching(last, tile) { return }
        add(tile)
    }

    /// The finger lifts: the word is scored.
    func lift() {
        guard stage == .playing, !path.isEmpty else { return }
        let submitted = word
        verdictTiles.removeAll(keepingCapacity: true)
        verdictTiles.append(contentsOf: path)
        clearPath()
        if submitted.count < 3 {
            verdict = .none
            return
        }
        verdictWord = submitted
        verdictAge = 0
        if foundSet.contains(submitted) {
            verdict = .dup
            owe(.wrong)
        } else if LetterRushWords.all.contains(submitted) {
            verdict = .good
            award(submitted)
        } else {
            verdict = .bad
            owe(.wrong)
        }
    }

    /// The touch was taken away (the app paused): the word is dropped.
    func cancel() {
        clearPath()
    }

    func askToContinue() {
        if canContinue { continueAsked = true }
    }

    /// Ends the round now, as if the clock had run out.
    func timeUp() {
        guard stage == .playing else { return }
        elapsed = Self.roundLength
        endRound()
    }

    private func add(_ tile: Int) {
        path.append(tile)
        used[tile] = true
        popAge[tile] = 0
        refreshWord()
        owe(.tick)
    }

    private func clearPath() {
        for t in path { used[t] = false }
        path.removeAll(keepingCapacity: true)
        refreshWord()
    }

    private func refreshWord() {
        word = String(path.map { letters[$0] })
        if word.count < 3 {
            wordState = word.isEmpty ? .none : .short
        } else if foundSet.contains(word) {
            wordState = .found
        } else if LetterRushWords.all.contains(word) {
            wordState = .valid
        } else {
            wordState = .unknown
        }
    }

    private func award(_ submitted: String) {
        let n = submitted.count
        let points = M.points(n)
        score += points
        foundSet.insert(submitted)
        found.append(LetterRushWordRow(word: submitted, points: points))
        owe(n >= 5 ? .great : .good)

        let pillHalf = Swift.max(84 * layout.u, Double(n) * 30 * layout.u * 0.82 + 44 * layout.u) / 2
        if floaters.count >= 6 { floaters.removeFirst() }
        floaters.append(LetterRushFloater(text: "+\(points)", x: layout.width / 2 + pillHalf + 42 * layout.u,
                                          y: layout.pillY, age: 0))
        switch n {
        case 5: praise = "Nice"
        case 6: praise = "Great"
        case 7: praise = "Superb"
        case 8...: praise = "Amazing"
        default: praise = ""
        }
        praiseAge = 0

        let burst = n >= 5 ? 8 : 5
        for tile in verdictTiles {
            let c = layout.center(tile)
            for _ in 0..<burst {
                let a = sparks.range(0, 2 * Double.pi)
                let v = sparks.range(110, 320) * layout.u
                particles.append(LetterRushParticle(
                    x: Double(c.x), y: Double(c.y), vx: cos(a) * v, vy: sin(a) * v - 120 * layout.u,
                    age: 0, life: sparks.range(0.55, 0.9), turn: sparks.range(0, 6),
                    size: sparks.range(7, 12), tone: sparks.int(4)))
            }
        }
        if particles.count > 130 { particles.removeFirst(particles.count - 130) }
    }

    // MARK: Clock

    func step(dt raw: Double, autopilot: Bool) {
        let dt = Swift.min(Swift.max(raw, 0), 1.0 / 30)
        if dt <= 0 { return }
        ambient += dt
        for i in 0..<16 { popAge[i] += dt }
        verdictAge += dt
        praiseAge += dt
        friendFlash += dt
        if !floaters.isEmpty {
            for k in floaters.indices { floaters[k].age += dt }
            floaters.removeAll { $0.age >= 1 }
        }
        if !particles.isEmpty {
            let gravity = 900 * layout.u
            for k in particles.indices {
                particles[k].vy += gravity * dt
                particles[k].x += particles[k].vx * dt
                particles[k].y += particles[k].vy * dt
                particles[k].age += dt
            }
            particles.removeAll { $0.age >= $0.life }
        }
        let gap = Double(score) - shownScore
        shownScore = abs(gap) < 1 ? Double(score) : shownScore + gap * (1 - exp(-9 * dt))

        switch stage {
        case .ready, .finished:
            break
        case .playing:
            elapsed += dt
            while friendShown < friendPlan.count, friendPlan[friendShown].time <= elapsed {
                friendScore += friendPlan[friendShown].points
                friendShown += 1
                friendFlash = 0
            }
            let left = Int(timeLeft.rounded(.up))
            if left <= 10, left > 0, left < lastTick {
                lastTick = left
                owe(.tick)
            }
            if elapsed >= Self.roundLength {
                elapsed = Self.roundLength
                endRound()
            }
        case .ending:
            endClock += dt
            let hold = autopilot ? Self.autopilotHold : Self.endHold
            if endClock >= hold || continueAsked { stage = .finished }
        }
    }

    private func endRound() {
        clearPath()
        stage = .ending
        endClock = 0
        var r = LetterRushResults()
        r.youScore = score
        r.youWords = found.count
        r.friendName = friendName
        r.friendScore = friendScore
        r.friendWords = friendShown
        r.top = found.enumerated()
            .sorted { $0.element.points != $1.element.points ? $0.element.points > $1.element.points : $0.offset < $1.offset }
            .map { $0.element }
        var theirs = Set<String>()
        for k in 0..<friendShown { theirs.insert(friendPlan[k].word) }
        r.bestMissed = solutions.first(where: { !foundSet.contains($0.word) && !theirs.contains($0.word) })?.word
        results = r
        owe(.end)
    }

    // MARK: Drawing

    func fill(_ f: inout LetterRushFrame) {
        f.letters = labels
        f.path = path
        f.selected = used
        f.popAge = popAge
        f.verdict = verdict
        f.verdictTiles = verdictTiles
        f.verdictWord = verdictWord
        f.verdictAge = verdictAge
        f.word = word
        f.wordState = wordState
        f.score = shown
        f.words = found.count
        f.timeLeft = timeLeft
        f.roundLength = Self.roundLength
        f.friendName = friendName
        f.friendScore = friendScore
        f.friendWords = friendShown
        f.friendFlash = friendFlash
        f.floaters = floaters
        f.particles = particles
        f.praise = praise
        f.praiseAge = praiseAge
        f.hint = "Drag through touching letters. Lift to submit."
        f.hintAlpha = stage == .ready ? 0.75 + 0.25 * sin(ambient * 3.2) : 0.7
        f.recent = found
        f.ambient = ambient
        f.ending = stage == .ending || stage == .finished ? endClock : nil
        f.results = results
        f.canContinue = canContinue
    }
}

// MARK: - Scripted player

/// Plays the round for recordings while GameDemo.autopilot is on. It traces real words from the
/// board at a person's pace, with now and then a slip, through the same calls a finger makes.
struct LetterRushPilot {
    private var rng: LetterRushRandom
    private var plan: [Int] = []
    private var cursor = 0
    private var step = 0
    private var nextAt = 0.9
    private var planned = false

    init(seed: UInt64) {
        rng = LetterRushRandom(seed: seed, salt: LetterRushRandom.pilot)
    }

    mutating func play(_ runner: LetterRushRunner) {
        let model = runner.model
        guard model.stage == .ready || model.stage == .playing else { return }
        if !planned {
            planned = true
            // Mostly words of four to six letters, in no particular order, a long one early.
            var mid = model.solutions.indices.filter { (4...6).contains(model.solutions[$0].word.count) }
            var short = model.solutions.indices.filter { model.solutions[$0].word.count == 3 }
            shuffle(&mid)
            shuffle(&short)
            var mixed: [Int] = []
            while !mid.isEmpty || !short.isEmpty {
                if !mid.isEmpty { mixed.append(mid.removeLast()) }
                if !mid.isEmpty, rng.next() < 0.6 { mixed.append(mid.removeLast()) }
                if !short.isEmpty, rng.next() < 0.5 { mixed.append(short.removeLast()) }
            }
            if let long = model.solutions.indices.first, model.solutions[long].word.count >= 6 {
                mixed.removeAll { $0 == long }
                mixed.insert(long, at: Swift.min(2, mixed.count))
            }
            plan = mixed
        }
        if model.ambient < nextAt || cursor >= plan.count { return }
        let solution = model.solutions[plan[cursor]]
        if step < solution.path.count {
            if step == 0 { runner.press(solution.path[0]) } else { runner.slide(solution.path[step]) }
            step += 1
            nextAt = model.ambient + rng.range(0.1, 0.17)
        } else {
            runner.release()
            cursor += 1
            step = 0
            nextAt = model.ambient + rng.range(0.6, 1.5)
        }
    }

    private mutating func shuffle(_ list: inout [Int]) {
        var last = list.count - 1
        while last > 0 {
            list.swapAt(last, rng.int(last + 1))
            last -= 1
        }
    }
}

// MARK: - Runner

/// Holds the round between frames. Nothing is published: the timeline repaints every frame anyway.
final class LetterRushRunner: ObservableObject {
    let model: LetterRushModel
    private(set) var picture = LetterRushFrame()
    private let seed: UInt64
    private var lastDate: Date?
    private var frame = 0
    private var reported = false
    private var dragging = false
    private var size = CGSize(width: 402, height: 874)
    private var pilot: LetterRushPilot?
    private weak var link: GameLink?

    init(options: GameOptions) {
        model = LetterRushModel(options: options)
        seed = options.seed
    }

    func resize(_ newSize: CGSize) {
        if newSize == size || newSize.width < 8 || newSize.height < 8 { return }
        size = newSize
        model.layout = LetterRushLayout(size: newSize)
    }

    /// Brings the model up to the given date. Returns a number that changes when there is a new frame to paint.
    func advance(to date: Date, link: GameLink) -> Int {
        self.link = link
        if link.paused {
            lastDate = nil
            if dragging {
                dragging = false
                model.cancel()
            }
            return frame
        }
        defer { lastDate = date }
        if let before = lastDate {
            var owed = Swift.min(Swift.max(date.timeIntervalSince(before), 0), 0.1)
            while owed > 1e-6 {
                let dt = Swift.min(owed, 1.0 / 60)
                owed -= dt
                model.step(dt: dt, autopilot: GameDemo.autopilot)
                if let limit = GameDemo.loseAfter, model.stage == .playing, model.elapsed >= limit { model.timeUp() }
                if GameDemo.autopilot {
                    if pilot == nil { pilot = LetterRushPilot(seed: seed) }
                    pilot?.play(self)
                }
                settle(link)
            }
        }
        model.fill(&picture)
        frame &+= 1
        return frame
    }

    // MARK: Fingers

    func drag(at point: CGPoint, link: GameLink) {
        if link.paused || link.isFinished { return }
        let layout = model.layout
        if !dragging {
            dragging = true
            if model.stage == .ending {
                model.askToContinue()
                return
            }
            if let cell = layout.cell(at: point) { press(cell) }
            return
        }
        if let tile = layout.tile(at: point) { slide(tile) }
    }

    func lift(link: GameLink) {
        dragging = false
        if link.paused { model.cancel() } else { release() }
    }

    // MARK: Moves, from a finger or the scripted player

    func press(_ tile: Int) {
        model.press(tile)
        flush()
    }

    func slide(_ tile: Int) {
        model.slide(tile)
        flush()
    }

    func release() {
        model.lift()
        flush()
    }

    private func flush() {
        if let link { settle(link) }
    }

    /// Plays the haptic the model owes and reports the round once it is over.
    private func settle(_ link: GameLink) {
        switch model.takeFeedback() {
        case .tick: GameHaptics.tap()
        case .wrong: GameHaptics.thud()
        case .good: GameHaptics.success()
        case .great:
            GameHaptics.success()
            GameHaptics.thud()
        case .end: GameHaptics.heavy()
        case .none: break
        }
        if model.stage == .finished, !reported {
            reported = true
            let result = model.result
            DispatchQueue.main.async { link.finish(result) }
        }
    }
}

// MARK: - Game view

struct LetterRushCanvas: View {
    let picture: LetterRushFrame
    /// A new number every frame, so SwiftUI repaints.
    var frame = 0

    var body: some View {
        Canvas(opaque: true, colorMode: .nonLinear, rendersAsynchronously: false) { context, size in
            if size.width <= 8 || size.height <= 8 { return }
            LetterRushPainter(size: size, frame: picture).draw(&context)
        }
    }
}

public struct LetterRushGame: View {
    private let options: GameOptions
    private let link: GameLink

    public init(options: GameOptions, link: GameLink) {
        self.options = options
        self.link = link
    }

    public var body: some View {
        // A new link is a new round, so the round's state lives and dies with the link.
        LetterRushRound(options: options, link: link)
            .id(ObjectIdentifier(link))
    }
}

private struct LetterRushRound: View {
    @ObservedObject var link: GameLink
    @StateObject private var runner: LetterRushRunner

    init(options: GameOptions, link: GameLink) {
        self.link = link
        _runner = StateObject(wrappedValue: LetterRushRunner(options: options))
    }

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: nil, paused: link.paused)) { timeline in
                let tick = runner.advance(to: timeline.date, link: link)
                LetterRushCanvas(picture: runner.picture, frame: tick)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in runner.drag(at: value.location, link: link) }
                    .onEnded { _ in runner.lift(link: link) }
            )
            .onAppear { runner.resize(geo.size) }
            .onChange(of: geo.size) { _, newSize in runner.resize(newSize) }
        }
        .ignoresSafeArea()
        .accessibilityElement()
        .accessibilityLabel("Letter Rush. Drag through touching letters to make words.")
        .accessibilityAddTraits(.allowsDirectInteraction)
    }
}
