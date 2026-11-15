import SwiftUI
#if canImport(UIKit) && !os(macOS)
import UIKit
#endif

// Five Up, playable: find the hidden five-letter word in six tries, against the clock.
//
// FiveUpModel   the rules of a round in plain Swift: step(dt:) and press(_:).
// FiveUpCanvas  paints one frame of the model with the clip's painter.
// FiveUpPilot   the scripted player. It only runs while GameDemo.autopilot is on.
// FiveUpDriver  keeps the clock, turns touches into keys, fires haptics, reports the result.
// FiveUpGame    the view the app shows.

// MARK: - Words

enum FiveUpWords {
    /// Everyday words. The answer comes from here, and so do the other player's guesses.
    static let answers: [[Character]] = {
        var seen = Set<String>()
        var list: [[Character]] = []
        for piece in everyday.split(whereSeparator: { $0 == " " || $0 == "\n" }) {
            let word = piece.uppercased()
            if word.count == 5, seen.insert(word).inserted { list.append(Array(word)) }
        }
        return list
    }()

    private static let known = Set(answers.map { String($0) })

    /// Does the game take this guess? Yes when it is in the list or spelled right in English.
    /// On the Mac (test builds only) any five letters pass.
    static func accepts(_ guess: String) -> Bool {
        let word = guess.uppercased()
        guard word.count == 5, word.allSatisfy({ $0.isASCII && $0.isLetter }) else { return false }
        if known.contains(word) { return true }
        #if canImport(UIKit) && !os(macOS)
        guard let english else { return true }
        let lower = word.lowercased()
        let wrong = speller.rangeOfMisspelledWord(in: lower, range: NSRange(location: 0, length: lower.utf16.count),
                                                  startingAt: 0, wrap: false, language: english)
        return wrong.location == NSNotFound
        #else
        return true
        #endif
    }

    #if canImport(UIKit) && !os(macOS)
    private static let speller = UITextChecker()
    private static let english: String? = {
        let languages = UITextChecker.availableLanguages
        for wanted in ["en_US", "en"] where languages.contains(wanted) { return wanted }
        return languages.first { $0.hasPrefix("en") }
    }()
    #endif

    private static let everyday = """
    about above actor acute admit adopt adult after again agent agree ahead alarm album alert alike alive allow alone along
    alter among angel anger angle angry apart apple apply arena argue arise armor array arrow aside asset audio avoid awake
    award aware bacon badge baker basic basin batch beach beard beast began begin being below bench berry birth black blade
    blame blank blast blaze blend bless blind block bloom board boast boost booth bound brain brake brand brass brave bread
    break brick bride brief bring broad broke brook broom brown brush build built bunch burst buyer cabin cable camel candy
    canoe cargo carry carve catch cause chain chair chalk chart chase cheap check cheek cheer chess chest chief child chill
    chime choir chose civic claim class clean clear clerk click cliff climb clock close cloth cloud coach coast color comet
    comic coral couch could count court cover crack craft crane crash crate crawl cream creek crest crisp cross crowd crown
    crumb crush curve cycle daily dairy dance dealt debut decay delay depth diary diner dodge doubt dough dozen draft drain
    drama drank dream dress dried drift drill drink drive drove dusty eager eagle early earth eight elbow elder elect empty
    enjoy enter entry equal error essay event every exact exist extra fable faint fairy faith false fancy fault favor feast
    fence ferry fever fiber field fifth fifty fight final first flame flash fleet float flock flood floor flour fluid flute
    focus force forge forth forty forum found frame fresh front frost fruit fully funny giant given glass globe glory glove
    grace grade grain grand grant grape graph grasp grass great green greet grill grind group grove grown guard guess guest
    guide habit happy harsh haste heart heavy hedge hello honey honor horse hotel house human humor hurry ideal image index
    inner input irony issue ivory jelly jewel joint jolly judge juice kayak kneel knife knock known label labor large laser
    later laugh layer learn least leave legal lemon level light limit linen local lodge logic loose lunch magic major maker
    maple march match maybe mayor medal media melon mercy merit metal meter might minor mixer model money month moral motor
    mount mouse mouth movie music naval nerve never night noble noise north novel nurse ocean offer often olive onion opera
    orbit order other ought outer owner paint panel paper party pasta patch pause peace peach pearl pedal penny phone photo
    piano piece pilot pitch pizza place plain plane plant plate plaza point polar porch pound power press price pride prime
    print proof proud prove pulse punch pupil purse queen quest quick quiet quilt quite quote radio raise rally ranch range
    rapid ratio reach react ready realm rebel refer relax reply rider ridge right rinse risky rival river roast robin robot
    rocky rough round route royal rugby ruler rural salad sauce scale scarf scene scent scope score scout seven shade shake
    shall shape share shark sharp sheep sheet shelf shell shift shine shirt shock shore short shout shown sight silly since
    sixth sixty skate skill skirt sleep slice slide slope small smart smell smile smoke snack snake solar solid solve sorry
    sound south space spare spark speak speed spell spend spice spoon sport spray stack staff stage stair stamp stand stare
    start state steam steel steep stick still stone stood store storm story stove straw strip study stuff style sugar suite
    sunny super sweet swept swift swing sword table taste teach thank theme there thick thing think third those three threw
    throw thumb tiger tight timer tired title toast today tooth topic total touch tough towel tower trace track trade trail
    train treat trend trial tribe trick truck truly trunk trust truth tulip twice twist uncle under union unity until upper
    upset urban usage usual valid value video vigor visit vital vivid vocal voice voter wagon waste watch water weary weave
    wheat wheel where which while white whole woman world worry worth would woven wrist write wrong wrote yacht young youth
    zebra
    """
}

/// SplitMix64 for the round: the answer, the other player, the scripted player.
struct FiveUpDice {
    private var state: UInt64

    init(seed: UInt64) { state = seed &* 0x9E3779B97F4A7C15 &+ 0x2545F4914F6CDD1D }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var v = state
        v = (v ^ (v >> 30)) &* 0xBF58476D1CE4E5B9
        v = (v ^ (v >> 27)) &* 0x94D049BB133111EB
        return v ^ (v >> 31)
    }

    /// 0 ..< 1
    mutating func unit() -> Double { Double(next() >> 11) / 9007199254740992.0 }
    mutating func range(_ lo: Double, _ hi: Double) -> Double { lo + (hi - lo) * unit() }
    /// 0 ..< count
    mutating func int(_ count: Int) -> Int { count <= 1 ? 0 : Int(next() % UInt64(count)) }
}

// MARK: - Model

enum FiveUpKey: Equatable {
    case letter(Character)
    case enter
    case delete
}

final class FiveUpModel {
    enum Stage { case ready, playing, settling, ending, finished }

    /// What a key press did.
    enum Press { case ignored, typed, full, deleted, empty, rejected, submitted }

    /// Moments the view may answer with a haptic.
    enum Event {
        case flip(FiveUpMark)
        case solved
        case failed
        case rivalGuessed
        case rivalSolved
        case tick
    }

    struct Guess {
        let letters: [Character]
        let marks: [FiveUpMark]
        /// On the animation clock.
        let enteredAt: Double
    }

    /// The other player's whole round, worked out from the seed before the round starts.
    struct Rival {
        var times: [Double] = []
        var marks: [[FiveUpMark]] = []
        var solveTry: Int?
    }

    static let timeLimit = 180.0
    static let maxTries = 6
    /// How long a row takes to turn over.
    static let revealSpan = 0.85
    static let endingSpan = 1.5
    static let pointsPerLetter = 20

    let answer: [Character]
    let hasRival: Bool
    let rivalName: String
    let rival: Rival
    let bestScore: Int

    private(set) var stage = Stage.ready
    /// Animation clock: runs whenever the model is stepped.
    private(set) var time = 0.0
    /// Round clock: from the first key until the round is decided.
    private(set) var elapsed = 0.0
    private(set) var guesses: [Guess] = []
    private(set) var entry: [Character] = []
    private(set) var entryTimes: [Double] = []

    private(set) var keyTimes = [Double](repeating: -10, count: 26)
    private(set) var enterTime = -10.0
    private(set) var deleteTime = -10.0
    private(set) var shakeTime = -10.0
    private(set) var toast = ""
    private(set) var toastTime = -10.0
    private(set) var startTime: Double?
    private(set) var endTime: Double?
    private(set) var solved = false
    private(set) var result: GameResult?

    private(set) var rivalShown = 0
    private(set) var rivalShownAt = -10.0
    /// Had the other player already solved it when this player's round was decided?
    private var rivalWasFirst = false

    private var settleUntil = 0.0
    private var flipsTold = 5
    private var lastTick = 11
    private var events: [Event] = []

    init(options: GameOptions, answer forced: String? = nil, words: [[Character]] = FiveUpWords.answers) {
        var dice = FiveUpDice(seed: options.seed)
        let drawn = words.isEmpty ? Array("PRINT") : words[dice.int(words.count)]
        let asked = forced.map { Array($0.uppercased()) } ?? drawn
        answer = asked.count == 5 ? asked : drawn
        hasRival = !options.solo
        rivalName = String((options.friendNames.first ?? "friend").prefix(12))
        bestScore = options.bestScore
        rival = options.solo ? Rival() : FiveUpModel.planRival(answer: answer, words: words, dice: &dice)
    }

    // MARK: The other player

    /// Plays the other player's round ahead of time: real words, each one fitting what the earlier
    /// guesses showed, solved on a try the seed picks, or not at all.
    static func planRival(answer: [Character], words: [[Character]], dice: inout FiveUpDice) -> Rival {
        var plan = Rival()
        let roll = dice.unit()
        if roll < 0.15 { plan.solveTry = 3 }
        else if roll < 0.50 { plan.solveTry = 4 }
        else if roll < 0.75 { plan.solveTry = 5 }
        else if roll < 0.87 { plan.solveTry = 6 }

        let others = words.filter { $0 != answer }
        var fitting = others
        var used: [[Character]] = []
        var clock = 0.0
        for attempt in 1...(plan.solveTry ?? maxTries) {
            clock += dice.range(12, 30)
            var guess = answer
            if attempt != plan.solveTry {
                if !fitting.isEmpty {
                    guess = fitting[dice.int(fitting.count)]
                } else {
                    // Nothing else fits: a near miss, with as many letters in place as any unused word has.
                    var closest: [[Character]] = []
                    var most = -1
                    for word in others where !used.contains(word) {
                        let placed = (0..<5).filter { word[$0] == answer[$0] }.count
                        if placed > most {
                            most = placed
                            closest = [word]
                        } else if placed == most {
                            closest.append(word)
                        }
                    }
                    if closest.isEmpty {
                        guess = Array(answer.reversed())
                        if guess == answer { guess = Array(answer == Array("QUIET") ? "ROUND" : "QUIET") }
                    } else {
                        guess = closest[dice.int(closest.count)]
                    }
                }
            }
            used.append(guess)
            let marks = FiveUpMark.grade(guess, against: answer)
            plan.marks.append(marks)
            plan.times.append(clock)
            fitting = fitting.filter { $0 != guess && FiveUpMark.grade(guess, against: $0) == marks }
        }
        return plan
    }

    var rivalHasSolved: Bool {
        guard let needed = rival.solveTry else { return false }
        return rivalShown >= needed
    }

    // MARK: Clock

    func step(dt: Double) {
        if dt <= 0 { return }
        time += dt
        switch stage {
        case .ready, .finished:
            break
        case .playing:
            elapsed = min(elapsed + dt, Self.timeLimit)
            while rivalShown < rival.times.count, rival.times[rivalShown] <= elapsed {
                rivalShown += 1
                rivalShownAt = time
                if rivalHasSolved {
                    toast = "\(rivalName) solved it"
                    toastTime = time
                    events.append(.rivalSolved)
                } else {
                    events.append(.rivalGuessed)
                }
            }
            tellFlips()
            // A tick for each of the last ten seconds.
            let left = secondsLeft
            if left <= 10, left > 0, left < lastTick {
                lastTick = left
                events.append(.tick)
            }
            if elapsed >= Self.timeLimit {
                rivalWasFirst = rivalHasSolved
                beginEnding()
            }
        case .settling:
            tellFlips()
            if time >= settleUntil { beginEnding() }
        case .ending:
            tellFlips()
            if let end = endTime, time - end >= Self.endingSpan {
                stage = .finished
                result = makeResult()
            }
        }
    }

    private func beginEnding() {
        stage = .ending
        endTime = time
        events.append(solved ? .solved : .failed)
    }

    /// One event for each tile of the newest row as it turns its mark up.
    private func tellFlips() {
        guard let row = guesses.last else { return }
        while flipsTold < 5, flip(of: row, column: flipsTold) >= 0.5 {
            events.append(.flip(row.marks[flipsTold]))
            flipsTold += 1
        }
    }

    func takeEvents() -> [Event] {
        if events.isEmpty { return [] }
        let out = events
        events.removeAll(keepingCapacity: true)
        return out
    }

    // MARK: Input

    @discardableResult
    func press(_ key: FiveUpKey) -> Press {
        guard stage == .ready || stage == .playing else { return .ignored }
        if stage == .ready {
            stage = .playing
            startTime = time
        }
        switch key {
        case .letter(let raw):
            guard let letter = String(raw).uppercased().first, let index = FiveUpBoard.keyIndex(letter) else { return .ignored }
            keyTimes[index] = time
            if entry.count >= 5 { return .full }
            entry.append(letter)
            entryTimes.append(time)
            return .typed
        case .delete:
            deleteTime = time
            if entry.isEmpty { return .empty }
            entry.removeLast()
            entryTimes.removeLast()
            return .deleted
        case .enter:
            enterTime = time
            if entry.count < 5 { return refuse("Need five letters") }
            if !FiveUpWords.accepts(String(entry)) { return refuse("Not a word") }
            submit()
            return .submitted
        }
    }

    private func refuse(_ why: String) -> Press {
        toast = why
        toastTime = time
        shakeTime = time
        return .rejected
    }

    private func submit() {
        let marks = FiveUpMark.grade(entry, against: answer)
        guesses.append(Guess(letters: entry, marks: marks, enteredAt: time))
        entry.removeAll(keepingCapacity: true)
        entryTimes.removeAll(keepingCapacity: true)
        flipsTold = 0
        toastTime = -10
        let right = marks.allSatisfy { $0 == .exact }
        if right || guesses.count >= Self.maxTries {
            // Decided. The ending waits until the row has turned over.
            solved = right
            rivalWasFirst = rivalHasSolved
            stage = .settling
            settleUntil = time + Self.revealSpan
        }
    }

    // MARK: Row animation

    /// 0...1: how far the tile in this column has turned over.
    func flip(of row: Guess, column: Int) -> Double {
        let start = row.enteredAt + Double(column) * 0.16 * Self.revealSpan
        return min(max((time - start) / (0.36 * Self.revealSpan), 0), 1)
    }

    /// 0...1 while the tile settles after its turn, nil otherwise.
    func land(of row: Guess, column: Int) -> Double? {
        let turned = row.enteredAt + (Double(column) * 0.16 + 0.36) * Self.revealSpan
        let k = (time - turned) / (0.6 * Self.revealSpan)
        return k > 0 && k < 1 ? k : nil
    }

    // MARK: Score

    var secondsLeft: Int {
        min(max(Int((Self.timeLimit - elapsed).rounded(.up)), 0), Int(Self.timeLimit))
    }

    private static func placed(_ marks: [FiveUpMark]) -> Int { marks.filter { $0 == .exact }.count }

    /// The most letters any one guess put in the right place.
    var bestPlaced: Int { guesses.map { Self.placed($0.marks) }.max() ?? 0 }

    /// Extra points for solving: more for fewer tries and for time left on the clock.
    var solvePoints: Int {
        solved ? 400 + 150 * (Self.maxTries - guesses.count) + 5 * (secondsLeft / 2) : 0
    }

    var finalScore: Int { Self.pointsPerLetter * bestPlaced + solvePoints }

    /// The score as the header shows it now: points roll in as each row finishes turning over.
    var shownScore: Int {
        if stage == .finished { return finalScore }
        var total = 0.0
        var best = 0
        for row in guesses {
            let placed = Self.placed(row.marks)
            if placed <= best { continue }
            let arrived = FiveUpEase.smooth(0, 0.35, time - (row.enteredAt + Self.revealSpan))
            total += Double(Self.pointsPerLetter * (placed - best)) * arrived
            best = placed
        }
        if solved, let end = endTime {
            total += Double(solvePoints) * FiveUpEase.smooth(0, 0.5, time - end)
        }
        return Int((total / 5).rounded()) * 5
    }

    private func makeResult() -> GameResult {
        var out = GameResult(score: finalScore, unit: "points")
        if solved {
            out.detail = guesses.count == 1 ? "Solved in 1 try" : "Solved in \(guesses.count) tries"
        } else {
            out.detail = "The word was \(String(answer))"
        }
        if hasRival {
            out.placement = solved && !rivalWasFirst ? 1 : 2
            out.playerCount = 2
        }
        return out
    }
}

// MARK: - From the model to a board

extension FiveUpBoard {
    init(model: FiveUpModel) {
        self.init()
        let now = model.time
        /// 0...1 through an animation that started at the given time, nil outside it.
        func progress(since start: Double, over span: Double) -> Double? {
            let k = (now - start) / span
            return k >= 0 && k < 1 ? max(k, 0.001) : nil
        }

        for guess in model.guesses {
            var tiles: [FiveUpTile] = []
            tiles.reserveCapacity(5)
            for c in 0..<5 {
                let flip = model.flip(of: guess, column: c)
                tiles.append(FiveUpTile(letter: guess.letters[c], mark: guess.marks[c], flip: flip,
                                        pop: nil, land: model.land(of: guess, column: c)))
                // A key takes its colour as the tile shows its own, and keeps the best it has had.
                if flip >= 0.5, let key = FiveUpBoard.keyIndex(guess.letters[c]),
                   guess.marks[c].rank > (keyMarks[key]?.rank ?? 0) {
                    keyMarks[key] = guess.marks[c]
                }
            }
            rows.append(tiles)
        }
        if !model.entry.isEmpty, model.guesses.count < FiveUpModel.maxTries {
            var tiles: [FiveUpTile] = []
            for (c, letter) in model.entry.enumerated() {
                tiles.append(FiveUpTile(letter: letter, pop: progress(since: model.entryTimes[c], over: 0.2)))
            }
            rows.append(tiles)
        }

        if model.stage == .ready || model.stage == .playing {
            activeRow = model.guesses.count
            cursor = model.entry.count
            let shake = (now - model.shakeTime) / 0.42
            if shake >= 0, shake < 1 {
                shakeRow = model.guesses.count
                shakeDX = CGFloat(sin(shake * .pi * 6) * 7 * (1 - shake))
            }
        } else {
            activeRow = nil
            cursor = -1
        }

        for k in 0..<26 { keyPress[k] = progress(since: model.keyTimes[k], over: 0.28) }
        enterPress = progress(since: model.enterTime, over: 0.28)
        deletePress = progress(since: model.deleteTime, over: 0.28)

        score = model.shownScore
        seconds = model.secondsLeft
        urgent = model.stage != .ready && seconds <= 20 && !model.solved

        if model.solved, let end = model.endTime {
            win = min(max((now - end) / FiveUpModel.endingSpan, 0.0001), 1)
            winRow = model.guesses.count - 1
            // The stamp goes on the row under the solved one, or over it when that was the last row.
            stampRow = winRow < 5 ? winRow + 1 : winRow - 1
            bonusText = "+" + FiveUpPainter.grouped(model.solvePoints)
        }
    }
}

// MARK: - What the game draws on top of the clip's picture

extension FiveUpPainter {
    func paintGame(_ ctx: inout GraphicsContext, model: FiveUpModel) {
        if model.hasRival { paintRival(&ctx, model) }
        paintHint(&ctx, model)
        paintEnterNudge(&ctx, model)
        paintToast(&ctx, model)
        paintAnswerSlip(&ctx, model)
    }

    /// The other player: a small copy of the board, marks only, at the right end of the header
    /// row, with their name beside it.
    private func paintRival(_ ctx: inout GraphicsContext, _ model: FiveUpModel) {
        let card = CGRect(x: gridRect.maxX - 58 * u, y: layout.headerTop, width: 58 * u, height: 43 * u)
        let done = model.rivalHasSolved
        let fresh = (model.time - model.rivalShownAt) / 0.7
        let radius = 7 * u

        label(&ctx, model.rivalName, size: 9.5 * u, weight: .bold, design: .serif, tracking: 0.3 * u,
              color: done ? Ink.tealLo : Ink.hex(0x211D33, 0.72),
              at: CGPoint(x: card.minX - 7 * u, y: card.midY), anchor: .trailing)

        ctx.fill(soft(card.offsetBy(dx: 0, dy: 1.2 * u), radius), with: .color(Color.white.opacity(0.85)))
        ctx.fill(soft(card, radius), with: .linearGradient(Gradient(colors: [Ink.hex(0xE0CDAC), Ink.hex(0xE9D9BC)]),
                                                           startPoint: CGPoint(x: 0, y: card.minY), endPoint: CGPoint(x: 0, y: card.maxY)))
        ctx.stroke(soft(card, radius), with: .color(Ink.hex(0x6E4F22, 0.3)), lineWidth: 1.1 * u)

        // A ring spreads from the card each time they guess.
        if fresh >= 0, fresh < 1 {
            let out = (2 + 4 * CGFloat(Ease.outCubic(fresh))) * u
            ctx.stroke(soft(card.insetBy(dx: -out, dy: -out), radius + out),
                       with: .color((done ? Ink.teal : Ink.coral).opacity(0.8 * (1 - fresh))),
                       lineWidth: 2.6 * u - 1.8 * (out - 2 * u) / 4)
        }

        let pad = 4 * u, gapX = 1.8 * u, gapY = 1.7 * u
        let cellW = (card.width - pad * 2 - gapX * 4) / 5
        let cellH = (card.height - pad * 2 - gapY * 5 - 1.2 * u) / 6
        let corner = 1.8 * u
        for r in 0..<6 {
            let shown = r < model.rivalShown && r < model.rival.marks.count
            // The newest row pops in.
            let grow: CGFloat = shown && r == model.rivalShown - 1 && fresh >= 0 && fresh < 0.45
                ? CGFloat(Ease.outBack(fresh / 0.45)) : 1
            for c in 0..<5 {
                let cell = CGRect(x: card.minX + pad + CGFloat(c) * (cellW + gapX),
                                  y: card.minY + pad + CGFloat(r) * (cellH + gapY), width: cellW, height: cellH)
                ctx.fill(soft(cell.offsetBy(dx: 0, dy: 0.6 * u), corner), with: .color(Ink.hex(0xCDB893)))
                if !shown { continue }
                let face = FiveUpFace.of(model.rival.marks[r][c])
                let chip = cell.insetBy(dx: cell.width * (1 - grow) / 2, dy: cell.height * (1 - grow) / 2)
                ctx.fill(soft(chip.offsetBy(dx: 0, dy: 1.2 * u), corner), with: .color(face.side))
                ctx.fill(soft(chip, corner), with: .color(face.top))
            }
        }
    }

    /// One line that says what to do, until the first key.
    private func paintHint(_ ctx: inout GraphicsContext, _ model: FiveUpModel) {
        let alpha = model.startTime.map { 1 - Ease.unit((model.time - $0) / 0.25) } ?? 1
        if alpha <= 0.01 { return }
        let centre = CGPoint(x: layout.midX, y: tileCenter(1, 0).y + 2 * b)
        let rect = CGRect(x: centre.x - 118 * u, y: centre.y - 17 * u, width: 236 * u, height: 34 * u)
        var g = ctx
        g.opacity = alpha
        g.fill(pill(rect.offsetBy(dx: 0, dy: 2.4 * u)), with: .color(Ink.hex(0x6E4F22, 0.22)))
        g.fill(pill(rect), with: .color(Ink.hex(0xFFF9EC)))
        g.stroke(pill(rect.insetBy(dx: 1.1 * u, dy: 1.1 * u)), with: .color(Ink.ink), lineWidth: 2.2 * u)
        label(&g, "Type a five letter word", size: 15.5 * u, weight: .bold, design: .serif, color: Ink.ink, at: centre)
    }

    /// A soft ring beats around ENTER once five letters are in.
    private func paintEnterNudge(_ ctx: inout GraphicsContext, _ model: FiveUpModel) {
        guard model.stage == .playing, model.entry.count == 5, let last = model.entryTimes.last else { return }
        let age = model.time - last
        let appear = Ease.unit(age / 0.2)
        let beat = 0.5 + 0.5 * sin(age * 6.0)
        let out = (1.6 + 1.6 * CGFloat(beat)) * u
        let ring = keyCap(center: enterKeyCenter, width: wideKeyWidth).insetBy(dx: -out, dy: -out).offsetBy(dx: 0, dy: 1.2 * u)
        ctx.stroke(soft(ring, keyCorner + out), with: .color(Ink.teal.opacity(appear * (0.95 - 0.45 * beat))), lineWidth: 2.6 * u)
    }

    /// "Not a word" and the like, above the row it is about. Under it for the first row, to stay
    /// off the header.
    private func paintToast(_ ctx: inout GraphicsContext, _ model: FiveUpModel) {
        let age = model.time - model.toastTime
        guard age >= 0, age < 1.25, !model.toast.isEmpty else { return }
        let pop = CGFloat(Ease.outBack(age / 0.16))
        let row = min(model.guesses.count, 5)
        let words = ctx.resolve(styled(model.toast, size: 14 * u, weight: .heavy, design: .rounded, color: Ink.cream))
        let width = words.measure(in: CGSize(width: 400 * u, height: 60 * u)).width + 30 * u
        var g = ctx
        g.opacity = 1 - Ease.smooth(1.0, 1.25, age)
        g.translateBy(x: layout.midX, y: tileCenter(row, 0).y + (row == 0 ? 40 : -33) * b)
        g.scaleBy(x: pop, y: pop)
        paintChip(&g, rect: CGRect(x: -width / 2, y: -14 * u, width: width, height: 28 * u),
                  top: Ink.inkHi, bottom: Ink.ink, side: Ink.inkLo)
        g.draw(words, at: .zero, anchor: .center)
    }

    /// The round ended without a solve: a slip of paper with the answer, laid on the grid.
    private func paintAnswerSlip(_ ctx: inout GraphicsContext, _ model: FiveUpModel) {
        guard !model.solved, let end = model.endTime else { return }
        let u = b
        let age = model.time - end
        let arrive = Ease.unit(age / 0.14)
        let slam = 1 + CGFloat(pow(1 - arrive, 2)) * 0.9
        let give = arrive >= 1 ? 1 + CGFloat(sin(.pi * Ease.unit((age - 0.14) / 0.12))) * 0.04 : 1
        let row = min(max(model.guesses.count, 0), 4)

        var g = ctx
        g.translateBy(x: layout.midX, y: (tileCenter(row, 0).y + tileCenter(row + 1, 0).y) / 2 + 3 * u)
        g.rotate(by: .degrees(-3.5))
        g.scaleBy(x: slam * give, y: slam * give)
        g.opacity = arrive

        let w = 252 * u, h = 96 * u
        let slip = CGRect(x: -w / 2, y: -h / 2, width: w, height: h)
        for k in 1...3 {
            let spread = CGFloat(k) * 2.2 * u
            g.fill(soft(slip.insetBy(dx: -spread, dy: -spread).offsetBy(dx: 0, dy: 3 * u), 12 * u + spread),
                   with: .color(Ink.hex(0x3C2A10, 0.10)))
        }
        g.fill(soft(slip, 12 * u), with: .color(Ink.hex(0xFFF7E8)))
        g.stroke(soft(slip, 12 * u), with: .color(Ink.ink), lineWidth: 3.4 * u)
        g.stroke(soft(slip.insetBy(dx: 5.4 * u, dy: 5.4 * u), 7.5 * u), with: .color(Ink.ink), lineWidth: 1.1 * u)
        label(&g, "THE WORD WAS", size: 10 * u, weight: .heavy, expanded: true, tracking: 2.6 * u,
              color: Ink.ink, at: CGPoint(x: 1.3 * u, y: -29 * u))

        let art = FiveUpTileArt(g)
        for (k, letter) in model.answer.enumerated() {
            var tile = g
            tile.translateBy(x: CGFloat(k - 2) * 43 * u, y: 9 * u)
            tile.scaleBy(x: 0.7, y: 0.7)
            paintTile(&tile, TilePose(center: .zero, face: .exact, letter: letter, mark: .exact), art: art)
        }
    }
}

// MARK: - Finding the key under a touch

enum FiveUpKeyboard {
    /// Uses the painter's key positions. Every key answers for its whole cell, and the keyboard
    /// reaches a little past the caps of its first and last rows.
    static func key(at point: CGPoint, in size: CGSize) -> FiveUpKey? {
        let layout = FiveUpLayout(size: size)
        guard layout.showsKeys, layout.keyPitch > 0, layout.keyRowPitch > 0 else { return nil }
        let reach = layout.keyRowPitch / 2 + 8 * layout.u
        if point.y < layout.keysY - reach || point.y > layout.keysY + 2 * layout.keyRowPitch + reach { return nil }
        let row = min(max(Int(((point.y - layout.keysY) / layout.keyRowPitch).rounded()), 0), 2)
        let fromMiddle = (point.x - layout.midX) / layout.keyPitch
        if row == 2 {
            if fromMiddle < -3.5 { return .enter }
            if fromMiddle > 3.5 { return .delete }
        }
        let letters = FiveUpPainter.keyRows[row]
        let slot = fromMiddle + CGFloat(letters.count - 1) / 2
        let index = min(max(Int(slot.rounded()), 0), letters.count - 1)
        return abs(slot - CGFloat(index)) <= 1.4 ? .letter(letters[index]) : nil
    }
}

// MARK: - Views

/// The part of the picture that never changes in a round: the paper. Painted once.
struct FiveUpBackdrop: View, Equatable {
    var body: some View {
        Canvas(opaque: true, colorMode: .nonLinear, rendersAsynchronously: false) { context, size in
            if size.width <= 2 || size.height <= 2 { return }
            FiveUpPainter(board: FiveUpBoard(), showHUD: true, size: size).paint(&context, pass: .still)
        }
    }
}

/// Paints the model as it is right now, over the backdrop.
struct FiveUpCanvas: View {
    let model: FiveUpModel
    /// Any value that is new every frame. The model is a class, so without it SwiftUI would see the
    /// same inputs and skip the repaint.
    var tick = 0.0

    var body: some View {
        Canvas(opaque: false, colorMode: .nonLinear, rendersAsynchronously: false) { context, size in
            guard size.width > 2, size.height > 2, tick.isFinite else { return }
            let painter = FiveUpPainter(board: FiveUpBoard(model: model), showHUD: true, size: size)
            painter.paint(&context, pass: .live)
            painter.paintGame(&context, model: model)
        }
    }
}

/// Holds the round between frames: steps the model once a frame and turns touches into keys.
final class FiveUpDriver: ObservableObject {
    let model: FiveUpModel
    private let seed: UInt64
    private var lastDate: Date?
    private var reported = false
    /// Made on the first frame GameDemo.autopilot is on, never otherwise.
    private var pilot: FiveUpPilot?

    init(options: GameOptions) {
        model = FiveUpModel(options: options)
        seed = options.seed
    }

    func advance(to date: Date, paused: Bool, link: GameLink) {
        if paused {
            lastDate = nil
            return
        }
        let dt = lastDate.map { min(max(date.timeIntervalSince($0), 0), 1.0 / 30) } ?? 0
        lastDate = date
        model.step(dt: dt)
        if GameDemo.autopilot {
            if pilot == nil { pilot = FiveUpPilot(seed: seed) }
            pilot?.play(self)
        }
        for event in model.takeEvents() {
            switch event {
            case .flip(let mark):
                if mark == .exact { GameHaptics.thud() } else { GameHaptics.tap() }
            case .solved: GameHaptics.success()
            case .failed: GameHaptics.fail()
            case .rivalSolved: GameHaptics.thud()
            case .rivalGuessed: break
            case .tick: GameHaptics.tap()
            }
        }
        if !reported, let result = model.result {
            reported = true
            DispatchQueue.main.async { link.finish(result) }
        }
    }

    func touch(at point: CGPoint, in size: CGSize, paused: Bool) {
        guard !paused, let key = FiveUpKeyboard.key(at: point, in: size) else { return }
        switch model.press(key) {
        case .ignored: break
        case .rejected: GameHaptics.thud()
        case .typed, .full, .deleted, .empty, .submitted: GameHaptics.tap()
        }
    }
}

// MARK: - Scripted player

/// Plays a round for recordings while GameDemo.autopilot is on. It picks real words from the
/// game's list, each fitting the marks on the board so far, and types them on the game's own keys
/// at a person's pace. It reads the model and never writes to it: every key goes through
/// FiveUpDriver.touch, the call a finger makes.
final class FiveUpPilot {
    /// The screen it lays the keyboard out on to find where to touch. The touch is tested against
    /// this same size, so it lands on the same key whatever size the game is shown at.
    static let touchSize = CGSize(width: 402, height: 874)
    /// How long the hint is left up before the first key.
    static let readySpan = 0.8
    /// From ENTER until the row has turned over and its tiles are at rest.
    static let watchSpan = FiveUpModel.revealSpan * 1.6

    /// First guesses a decent player might open with. Only those in the game's list are used.
    private static let openers = """
    STARE RAISE ARISE CRANE TRACE CRATE STONE LEARN HEART EARTH ALONE LEAST TRAIN LATER ALERT REACT
    NOISE OCEAN HOUSE AUDIO PAINT STEAM ROAST SOLAR TIRED SHORE CLEAR SNAKE PLANT POINT SOUND MOUSE
    CHAIR BREAD STORE SHARE SCALE ROUTE OUTER RATIO RADIO MEDIA
    """

    private var dice: FiveUpDice
    private let keys = FiveUpPainter(board: FiveUpBoard(), showHUD: true, size: FiveUpPilot.touchSize)
    /// The guesses it means to make, the answer last. Empty until the first frame.
    private var plan: [[Character]] = []
    private var nextAt = 0.0
    /// Its one typing slip: on which row, and after how many letters.
    private var slipRow = 1
    private var slipColumn = 2
    private var slipped = false
    /// Set when the game turned a planned word down. From then on it types the answer.
    private var offPlan = false

    init(seed: UInt64) {
        dice = FiveUpDice(seed: seed ^ 0x50494C4F54)
    }

    /// Call once a frame, after the model has stepped. Presses one key at most.
    func play(_ driver: FiveUpDriver) {
        let model = driver.model
        guard model.stage == .ready || model.stage == .playing, model.guesses.count < FiveUpModel.maxTries else { return }
        if plan.isEmpty {
            plan = Self.plan(answer: model.answer, words: FiveUpWords.answers, dice: &dice)
            slipRow = 1 + dice.int(2)
            slipColumn = 1 + dice.int(3)
            nextAt = model.time + Self.readySpan
        }
        let now = model.time
        if now < nextAt { return }

        let word = target(model)
        let typed = model.entry
        if !word.starts(with: typed) {
            // A wrong letter is on the row: take it back.
            touch(.delete, driver)
            nextAt = now + dice.range(0.30, 0.42)
        } else if typed.count == 5 {
            let before = model.guesses.count
            touch(.enter, driver)
            if model.guesses.count > before {
                // Watch the row turn over, then think about the next word.
                nextAt = now + Self.watchSpan + dice.range(1.15, 1.5)
            } else {
                offPlan = true
                nextAt = now + dice.range(0.9, 1.2)
            }
        } else if !slipped, model.guesses.count == slipRow, typed.count == slipColumn,
                  let wrong = neighbour(of: word[typed.count]) {
            // The slip: the key beside the right one, noticed a moment later.
            slipped = true
            touch(.letter(wrong), driver)
            nextAt = now + dice.range(0.45, 0.65)
        } else {
            touch(.letter(word[typed.count]), driver)
            nextAt = now + (typed.count == 4 ? dice.range(0.5, 0.75) : dice.range(0.22, 0.35))
        }
    }

    /// The word for the open row: the planned one for as long as the board matches the plan.
    private func target(_ model: FiveUpModel) -> [Character] {
        let row = model.guesses.count
        guard !offPlan, row < plan.count else { return model.answer }
        for k in 0..<row where model.guesses[k].letters != plan[k] { return model.answer }
        return plan[row]
    }

    private func neighbour(of letter: Character) -> Character? {
        for row in FiveUpPainter.keyRows {
            guard let k = row.firstIndex(of: letter) else { continue }
            var beside: [Character] = []
            if k > 0 { beside.append(row[k - 1]) }
            if k + 1 < row.count { beside.append(row[k + 1]) }
            return beside.isEmpty ? nil : beside[dice.int(beside.count)]
        }
        return nil
    }

    private func touch(_ key: FiveUpKey, _ driver: FiveUpDriver) {
        guard let point = point(of: key) else { return }
        driver.touch(at: point, in: Self.touchSize, paused: false)
    }

    /// The middle of a key's cap.
    private func point(of key: FiveUpKey) -> CGPoint? {
        switch key {
        case .enter: return keys.enterKeyCenter
        case .delete: return keys.deleteKeyCenter
        case .letter(let letter):
            for (r, row) in FiveUpPainter.keyRows.enumerated() {
                if let k = row.firstIndex(of: letter) { return keys.keyCenter(r, k) }
            }
            return nil
        }
    }

    // MARK: Choosing the words

    /// Three wrong guesses and then the answer. Each guess fits every mark the earlier ones got,
    /// so it is a word a careful player could have tried, and between them the first two guesses
    /// show all three kinds of mark. The rules loosen only when the list leaves no such path.
    static func plan(answer: [Character], words: [[Character]], dice: inout FiveUpDice) -> [[Character]] {
        func count(_ marks: [FiveUpMark], _ kind: FiveUpMark) -> Int { marks.filter { $0 == kind }.count }

        var others = words.filter { $0.count == 5 && $0 != answer }
        var last = others.count - 1
        while last > 0 {
            others.swapAt(last, dice.int(last + 1))
            last -= 1
        }
        let liked = Set(openers.split(whereSeparator: { $0 == " " || $0 == "\n" }).map { Array(String($0)) })
        let favourites = others.filter { liked.contains($0) }

        // Strictness 0: a favourite opener that lights one to three letters. 1: any tidy opener
        // that does. 2: any opener, still all three marks in two rows. 3: any path of fitting words.
        for strictness in 0..<4 {
            var tried = 0
            for first in strictness == 0 ? favourites : others {
                let marks1 = FiveUpMark.grade(first, against: answer)
                if strictness <= 1 {
                    let lit = 5 - count(marks1, .absent)
                    if Set(first).count < 5 || lit < 1 || lit > 3 || count(marks1, .exact) > 2 { continue }
                }
                tried += 1
                if tried > 60 { break }
                let fits1 = others.filter { $0 != first && FiveUpMark.grade(first, against: $0) == marks1 }
                if fits1.count < 2 { continue }
                for second in fits1 {
                    let marks2 = FiveUpMark.grade(second, against: answer)
                    if strictness <= 2 {
                        let both = marks1 + marks2
                        if !both.contains(.absent) || !both.contains(.present) || !both.contains(.exact) { continue }
                    }
                    if strictness <= 1, count(marks2, .exact) > 3 { continue }
                    // The third guess is the near miss: the fitting word closest to the answer.
                    var third: [Character]?
                    var most = -1
                    for word in fits1 where word != second && FiveUpMark.grade(second, against: word) == marks2 {
                        let placed = count(FiveUpMark.grade(word, against: answer), .exact)
                        if placed > most {
                            most = placed
                            third = word
                        }
                    }
                    if let third { return [first, second, third, answer] }
                }
            }
        }
        return Array(others.prefix(3)) + [answer]
    }
}

// MARK: - Touches

#if canImport(UIKit) && !os(macOS)
/// Reports every finger the moment it lands, so two thumbs can type as fast as they like.
private struct FiveUpTouchPad: UIViewRepresentable {
    var onTouch: (CGPoint, CGSize) -> Void

    func makeUIView(context: Context) -> FiveUpTouchView {
        let view = FiveUpTouchView()
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = true
        view.onTouch = onTouch
        return view
    }

    func updateUIView(_ view: FiveUpTouchView, context: Context) {
        view.onTouch = onTouch
    }
}

final class FiveUpTouchView: UIView {
    var onTouch: ((CGPoint, CGSize) -> Void)?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches { onTouch?(touch.location(in: self), bounds.size) }
    }
}
#else
private struct FiveUpTouchPad: View {
    var onTouch: (CGPoint, CGSize) -> Void
    @State private var isDown = false

    var body: some View {
        GeometryReader { geo in
            Color.clear
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if isDown { return }
                        isDown = true
                        onTouch(value.startLocation, geo.size)
                    }
                    .onEnded { _ in isDown = false })
        }
    }
}
#endif

public struct FiveUpGame: View {
    @ObservedObject private var link: GameLink
    @StateObject private var driver: FiveUpDriver

    public init(options: GameOptions, link: GameLink) {
        self.link = link
        _driver = StateObject(wrappedValue: FiveUpDriver(options: options))
    }

    public var body: some View {
        ZStack {
            FiveUpBackdrop()
            TimelineView(.animation(minimumInterval: nil, paused: link.paused)) { timeline in
                let _ = driver.advance(to: timeline.date, paused: link.paused, link: link)
                FiveUpCanvas(model: driver.model, tick: timeline.date.timeIntervalSinceReferenceDate)
            }
            FiveUpTouchPad { point, size in
                driver.touch(at: point, in: size, paused: link.paused)
            }
        }
        .ignoresSafeArea()
    }
}
