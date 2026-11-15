import SwiftUI

// Short Stack, playable.
//
// ShortStackTable   the rules of a hand in plain Swift: blinds, turns, raises, side pots.
// ShortStackOdds    how good two cards are, from a quick sample of showdowns.
// ShortStackModel   one sitting: deals the hands, keeps the table's rhythm, plays the other seats.
// ShortStackCanvas  paints the model's frame with the clip's painter.
// ShortStackPilot   the scripted player. It only runs while GameDemo.autopilot is on.
// ShortStackRunner  keeps the clock, passes touches on, fires haptics, reports the result.
// ShortStackGame    the view the app shows.

// MARK: - Rules

/// One hand of no-limit Texas Hold'em. Nothing here knows about time or the screen: the model
/// asks what comes next and makes it happen.
struct ShortStackTable {
    enum Status { case active, folded, allIn, out }

    /// raise carries the total the seat makes its chips in front this round.
    enum Move: Equatable { case fold, check, call, raise(Int) }

    /// What the hand is waiting for.
    enum Next: Equatable {
        case idle
        /// This seat's move.
        case act(Int)
        /// The round is closed and the next board cards are due.
        case deal
        /// Two or more seats are left after the river.
        case showdown
        /// Everyone else has folded.
        case uncontested(Int)
    }

    struct Seat {
        var chips: Int
        /// Chips put in this round.
        var stake = 0
        /// Chips put in this hand.
        var paid = 0
        var status = Status.active
        /// The level this seat last answered. nil: it has not had its turn this round.
        var answered: Int?
        var hole: [ShortStackCard] = []

        var live: Bool { status == .active || status == .allIn }
    }

    struct Legal {
        /// Chips to call. 0: checking is free.
        var call = 0
        var canRaise = false
        var minTo = 0
        var maxTo = 0
    }

    struct Award {
        var seat: Int
        var amount: Int
        /// 0 is the main pot, 1 and up are side pots.
        var pot: Int
    }

    var seats: [Seat]
    var button = -1
    var small = 10
    var big = 20
    /// 0 before the flop, 1 flop, 2 turn, 3 river.
    var street = 0
    var board: [ShortStackCard] = []
    /// What a seat must have in front this round to stay in.
    var level = 0
    /// The size of the last full raise, at least the big blind.
    var minRaise = 20
    var next = Next.idle
    private var deck: [ShortStackCard] = []

    init(chips: [Int]) {
        seats = chips.map { Seat(chips: $0) }
    }

    var pot: Int { seats.reduce(0) { $0 + $1.paid } }

    private func seat(after start: Int, where fits: (Seat) -> Bool) -> Int? {
        for step in 1...seats.count {
            let k = (start + step + seats.count) % seats.count
            if fits(seats[k]) { return k }
        }
        return nil
    }

    /// Deals a new hand from a shuffled deck: the button moves on, the blinds go in. Seats with
    /// no chips sit out.
    mutating func startHand(deck fresh: [ShortStackCard], small: Int, big: Int) {
        for k in seats.indices {
            seats[k].status = seats[k].chips > 0 ? .active : .out
            seats[k].stake = 0
            seats[k].paid = 0
            seats[k].answered = nil
            seats[k].hole = []
        }
        let inHand = seats.filter { $0.status == .active }.count
        guard inHand >= 2 else {
            next = .idle
            return
        }
        self.small = small
        self.big = big
        deck = fresh
        board = []
        street = 0
        button = seat(after: button) { $0.status == .active } ?? 0
        // Heads up the button posts the small blind and acts first before the flop.
        let smallSeat = inHand == 2 ? button : (seat(after: button) { $0.status == .active } ?? button)
        let bigSeat = seat(after: smallSeat) { $0.status == .active } ?? smallSeat
        for _ in 0..<2 {
            var k = button
            for _ in 0..<inHand {
                k = seat(after: k) { $0.status == .active } ?? k
                seats[k].hole.append(deck.removeLast())
            }
        }
        put(smallSeat, small)
        put(bigSeat, big)
        level = big
        minRaise = big
        resolve(after: bigSeat)
    }

    private mutating func put(_ k: Int, _ amount: Int) {
        let paid = Swift.min(seats[k].chips, amount)
        seats[k].chips -= paid
        seats[k].stake += paid
        seats[k].paid += paid
        if seats[k].chips == 0 { seats[k].status = .allIn }
    }

    func legal(_ k: Int) -> Legal {
        let seat = seats[k]
        guard seat.status == .active else { return Legal() }
        let owed = Swift.max(0, level - seat.stake)
        let maxTo = seat.stake + seat.chips
        // A seat that has already answered may raise again only after a full raise.
        let reopened = seat.answered.map { level - $0 >= minRaise } ?? true
        let rival = seats.indices.contains { $0 != k && seats[$0].status == .active }
        return Legal(call: Swift.min(owed, seat.chips), canRaise: reopened && rival && maxTo > level,
                     minTo: Swift.min(level + minRaise, maxTo), maxTo: maxTo)
    }

    /// Makes the move for the seat whose turn it is and returns what it came to: a check that
    /// costs chips is a call, a raise is held to what the seat may make.
    @discardableResult
    mutating func apply(_ move: Move) -> Move {
        guard case .act(let k) = next else { return .fold }
        let rules = legal(k)
        var made = move
        switch move {
        case .fold:
            seats[k].status = .folded
        case .check, .call:
            made = rules.call > 0 ? .call : .check
            put(k, rules.call)
        case .raise(let wanted):
            if rules.canRaise {
                // All in for less than a full raise is allowed and does not reopen the round.
                let to = Swift.min(Swift.max(wanted, rules.minTo), rules.maxTo)
                if to - level >= minRaise { minRaise = to - level }
                put(k, to - seats[k].stake)
                level = to
                made = .raise(to)
            } else {
                made = rules.call > 0 ? .call : .check
                put(k, rules.call)
            }
        }
        seats[k].answered = level
        resolve(after: k)
        return made
    }

    /// Works out what the hand waits for now.
    private mutating func resolve(after k: Int) {
        let live = seats.indices.filter { seats[$0].live }
        if live.count == 1 {
            refund()
            next = .uncontested(live[0])
            return
        }
        let active = seats.indices.filter { seats[$0].status == .active }
        let top = live.map { seats[$0].stake }.max() ?? 0
        // One seat with chips left cannot raise seats that are all in. It only acts if it owes.
        if active.isEmpty || (active.count == 1 && seats[active[0]].stake >= top) {
            refund()
            next = street == 3 ? .showdown : .deal
            return
        }
        if active.count == 1 { level = top }
        let level = self.level
        if let turn = seat(after: k, where: { $0.status == .active && ($0.answered == nil || $0.stake < level) }) {
            next = .act(turn)
            return
        }
        refund()
        next = street == 3 ? .showdown : .deal
    }

    /// Chips nobody could call go back to the seat that put them in.
    private mutating func refund() {
        var first = -1, most = 0, second = 0
        for k in seats.indices {
            let stake = seats[k].stake
            if stake > most {
                second = most
                most = stake
                first = k
            } else if stake > second {
                second = stake
            }
        }
        let extra = most - second
        guard first >= 0, extra > 0 else { return }
        seats[first].stake -= extra
        seats[first].paid -= extra
        seats[first].chips += extra
        if seats[first].status == .allIn { seats[first].status = .active }
    }

    /// Turns the next board cards: three for the flop, one for the turn, one for the river.
    mutating func dealStreet() {
        guard next == .deal, street < 3 else { return }
        street += 1
        deck.removeLast()
        for _ in 0..<(street == 1 ? 3 : 1) { board.append(deck.removeLast()) }
        for k in seats.indices {
            seats[k].stake = 0
            seats[k].answered = nil
        }
        level = 0
        minRaise = big
        if seats.filter({ $0.status == .active }).count <= 1 {
            next = street == 3 ? .showdown : .deal
        } else if let first = seat(after: button, where: { $0.status == .active }) {
            next = .act(first)
        }
    }

    /// The score of a seat's best five cards. Only meaningful once the board is complete.
    func score(_ k: Int) -> Int { ShortStackRank.score(seats[k].hole + board) }

    /// Shares out the pot and returns who took what. Each layer of chips goes to the best hand
    /// among the seats that paid into it, so a seat that is all in for less only takes what it
    /// could match. Equal hands split, and an odd chip goes to the first seat left of the button.
    mutating func settle() -> [Award] {
        let live = seats.indices.filter { seats[$0].live }
        var scores = [Int](repeating: -1, count: seats.count)
        if live.count == 1 {
            scores[live[0]] = 0
        } else {
            for k in live { scores[k] = score(k) }
        }
        let layers = Set(seats.map(\.paid).filter { $0 > 0 }).sorted()
        var awards: [Award] = []
        var floor = 0
        var pot = -1
        var last: [Int] = []
        for ceiling in layers {
            let payers = seats.indices.filter { seats[$0].paid >= ceiling }
            let each = ceiling - floor
            let amount = each * payers.count
            floor = ceiling
            let able = payers.filter { scores[$0] >= 0 }
            if able.isEmpty {
                for k in payers { seats[k].chips += each }
                continue
            }
            if able != last {
                pot += 1
                last = able
            }
            let best = able.map { scores[$0] }.max() ?? 0
            let count = seats.count
            let from = button
            let takers = able.filter { scores[$0] == best }
                .sorted { ($0 - from - 1 + count) % count < ($1 - from - 1 + count) % count }
            for (n, k) in takers.enumerated() {
                let share = amount / takers.count + (n < amount % takers.count ? 1 : 0)
                seats[k].chips += share
                if let at = awards.firstIndex(where: { $0.seat == k && $0.pot == pot }) {
                    awards[at].amount += share
                } else {
                    awards.append(Award(seat: k, amount: share, pot: pot))
                }
            }
        }
        for k in seats.indices {
            seats[k].stake = 0
            seats[k].paid = 0
        }
        next = .idle
        return awards
    }
}

// MARK: - Odds

enum ShortStackOdds {
    /// The share of showdowns two cards take against one unseen hand, from a quick sample. It only
    /// looks at the seat's own cards and the board.
    static func strength(hole: [ShortStackCard], board: [ShortStackCard], samples: Int,
                         rng: inout ShortStackRandom) -> Double {
        var rest = ShortStackCard.fresh().filter { !hole.contains($0) && !board.contains($0) }
        let missing = 5 - board.count
        var mine = hole + board
        var theirs = board
        mine.reserveCapacity(7)
        theirs.reserveCapacity(7)
        var taken = 0.0
        for _ in 0..<samples {
            for k in 0..<(missing + 2) { rest.swapAt(k, k + rng.below(rest.count - k)) }
            mine.removeLast(mine.count - 2 - board.count)
            theirs.removeLast(theirs.count - board.count)
            for k in 0..<missing {
                mine.append(rest[k])
                theirs.append(rest[k])
            }
            theirs.append(rest[missing])
            theirs.append(rest[missing + 1])
            let a = ShortStackRank.score(mine), b = ShortStackRank.score(theirs)
            taken += a > b ? 1 : a == b ? 0.5 : 0
        }
        return taken / Double(Swift.max(1, samples))
    }
}

// MARK: - Model

final class ShortStackModel {
    typealias M = ShortStackMath

    enum Stage { case playing, ending, finished }

    /// What the last step deserves as a haptic. A stronger one replaces a weaker one.
    enum Feedback: Int { case none, thud, success, fail }

    private enum Beat { case deal, turn, gather, reveal, show, award }

    /// How one of the other seats leans.
    private struct Style {
        /// Added to what a hand must be worth to call.
        var caution: Double
        /// Added to how strong the seat thinks its hand is when it comes to raising.
        var push: Double
        /// How often it raises with nothing.
        var bluff: Double
    }

    // Tuning. Times are in seconds.
    static let seatCount = ShortStackLayout.seatCount
    static let hands = 7
    static let handsPerLevel = 3            // the blinds double after this many hands
    static let startChips = 1000
    static let firstSmall = 10
    static let turnLimit = 20.0
    static let thinkShort = 0.6
    static let thinkLong = 0.9
    static let alwaysStays = 0.72           // the share of showdowns a hand must take to call any raise
    static let watchPace = 3.0              // how much faster the table goes once the player is out of a hand
    static let dealGap = 0.07
    static let dealSlide = 0.26
    static let revealGap = 0.13
    static let revealSlide = 0.42
    static let gatherLength = 0.4
    static let showLength = 1.0
    static let showdownHold = 2.6
    static let foldedHold = 1.5
    static let endLength = 2.2
    static let house = ["Moss", "Pip", "Odette", "Bram", "Sol"]

    let solo: Bool
    private(set) var table: ShortStackTable
    private(set) var frame = ShortStackFrame()
    private(set) var stage = Stage.playing
    /// Play clock: runs from the first deal until the sitting is over.
    private(set) var time = 0.0
    private(set) var hand = 0
    /// Goes up each time the player's turn comes round.
    private(set) var turnSerial = 0
    /// What the player may do on their turn.
    private(set) var legal = ShortStackTable.Legal()
    /// The raise sizes on offer, smallest first. The last is all in.
    private(set) var sizes: [Int] = []
    private(set) var menuOpen = false

    private var deckRandom: ShortStackRandom
    private var othersRandom: ShortStackRandom
    private var styles: [Style]
    private var beat = Beat.deal
    private var clock = 0.0
    private var length = 0.0
    private var actor = -1
    private var think = 0.0
    private var chipGoal: [Int]
    private var chipShown: [Double]
    private var raises: [Int]
    private var dealOrder: [Int] = []
    private var revealFrom = 0
    private var revealCount = 0
    private var landed = false
    private var bestShown = -1
    private var potsTaken = 0
    private var feedback = Feedback.none
    private var endClock = 0.0

    init(options: GameOptions) {
        let count = Self.seatCount
        solo = options.solo
        deckRandom = ShortStackRandom(seed: options.seed, salt: ShortStackRandom.deck)
        othersRandom = ShortStackRandom(seed: options.seed, salt: ShortStackRandom.others)
        table = ShortStackTable(chips: [Int](repeating: Self.startChips, count: count))
        chipGoal = [Int](repeating: Self.startChips, count: count)
        chipShown = [Double](repeating: Double(Self.startChips), count: count)
        raises = [Int](repeating: 0, count: count)

        var names = options.solo ? [] : Array(options.friendNames.filter { !$0.isEmpty }.prefix(count - 1))
        for name in Self.house where names.count < count - 1 && !names.contains(name) { names.append(name) }
        let player = options.playerName.isEmpty ? "You" : options.playerName

        // The seed decides which seat plays which way and where the button starts.
        var kinds = [Style(caution: 0, push: 0, bluff: 0.05), Style(caution: 0.05, push: -0.03, bluff: 0.02),
                     Style(caution: -0.05, push: 0.04, bluff: 0.09)]
        var last = kinds.count - 1
        while last > 0 {
            kinds.swapAt(last, othersRandom.below(last + 1))
            last -= 1
        }
        styles = (0..<count).map { kinds[$0 % kinds.count] }
        table.button = othersRandom.below(count)

        for (k, name) in ([player] + names).enumerated() {
            var seat = ShortStackSeatView()
            seat.name = k == 0 ? player : name
            seat.chips = Self.startChips
            frame.seats.append(seat)
        }
        frame.hands = Self.hands
        frame.board.reserveCapacity(5)
        startHand()
    }

    // MARK: Reading

    /// true while the game waits for the player's move.
    var playerTurn: Bool { stage == .playing && beat == .turn && actor == 0 }

    /// Seconds into the turn that is going on.
    var turnAge: Double { clock }

    var result: GameResult {
        let chips = table.seats[0].chips
        let line: String
        if bestShown >= 0 {
            line = "Your best hand was \(ShortStackRank.phrase(bestShown))"
        } else if potsTaken > 0 {
            line = potsTaken == 1 ? "You took 1 pot" : "You took \(potsTaken) pots"
        } else {
            line = hand == 1 ? "You played 1 hand" : "You played \(hand) hands"
        }
        if solo { return GameResult(score: chips, unit: "chips", detail: line) }
        let ahead = table.seats.dropFirst().filter { $0.chips > chips }.count
        return GameResult(score: chips, unit: "chips", detail: line, placement: 1 + ahead, playerCount: table.seats.count)
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

    /// The rest of a hand goes quickly once the player has no part in it.
    private var pace: Double {
        let me = table.seats[0].status
        return me == .folded || me == .out ? Self.watchPace : 1
    }

    // MARK: Input

    /// The player's keys. False when the key did nothing.
    @discardableResult
    func press(_ key: ShortStackKey) -> Bool {
        guard playerTurn else { return false }
        switch key {
        case .fold:
            flash(key)
            act(0, .fold)
        case .call:
            flash(key)
            act(0, legal.call == 0 ? .check : .call)
        case .raise:
            guard legal.canRaise else { return false }
            flash(key)
            menuOpen.toggle()
        case .size(let k):
            guard menuOpen, k >= 0, k < sizes.count else { return false }
            flash(key)
            act(0, .raise(sizes[k]))
        }
        return true
    }

    /// A touch off the keys puts the raise sizes away.
    func closeMenu() { menuOpen = false }

    private func flash(_ key: ShortStackKey) {
        frame.controls.pressed = key
        frame.controls.pressedAge = 0
    }

    // MARK: Clock

    func step(dt raw: Double) {
        let dt = Swift.min(Swift.max(raw, 0), 1.0 / 30)
        if dt <= 0 { return }
        frame.clock += dt
        settle(dt)
        switch stage {
        case .playing:
            time += dt
            run(dt)
        case .ending:
            endClock += dt
            frame.fade = M.smooth(0, 0.35, endClock)
            if endClock >= Self.endLength { stage = .finished }
        case .finished:
            break
        }
    }

    /// The small motions that run whatever the hand is doing: labels, chip counts, slides.
    private func settle(_ dt: Double) {
        for k in frame.seats.indices {
            frame.seats[k].labelAge = Swift.min(frame.seats[k].labelAge + dt, 100)
            frame.seats[k].stakeSlide = Swift.min(1, frame.seats[k].stakeSlide + dt / 0.22)
            if frame.seats[k].glow > 0 { frame.seats[k].glow = Swift.max(0, frame.seats[k].glow - dt / 1.2) }
            if table.seats[k].status == .folded, frame.seats[k].folded < 1 {
                frame.seats[k].folded = Swift.min(1, frame.seats[k].folded + dt / 0.3)
            }
            let gap = Double(chipGoal[k]) - chipShown[k]
            if gap != 0 {
                let move = Swift.max(abs(gap) * dt * 7, 60 * dt)
                chipShown[k] = abs(gap) <= move ? Double(chipGoal[k]) : chipShown[k] + (gap > 0 ? move : -move)
                frame.seats[k].chips = Int(chipShown[k].rounded())
            }
        }
        frame.messageAge = Swift.min(frame.messageAge + dt, 100)
        frame.controls.pressedAge = Swift.min(frame.controls.pressedAge + dt, 100)
        let menu = frame.controls.menu + (menuOpen ? dt : -dt) / 0.12
        frame.controls.menu = M.clamp(menu)
    }

    private func run(_ dt: Double) {
        let quick = dt * pace
        switch beat {
        case .deal:
            let before = clock
            clock += quick
            let count = dealOrder.count
            for (k, seat) in dealOrder.enumerated() {
                let first = Double(k) * Self.dealGap
                let second = Double(k + count) * Self.dealGap
                frame.seats[seat].dealt = M.clamp((clock - first) / Self.dealSlide) + M.clamp((clock - second) / Self.dealSlide)
                if seat == 0 {
                    frame.seats[0].face = M.clamp((clock - second - Self.dealSlide) / 0.25)
                    if (before < first && clock >= first) || (before < second && clock >= second) { owe(.thud) }
                }
            }
            if clock >= length { turn() }

        case .turn:
            if actor == 0 {
                clock += dt
                frame.controls.clock = M.clamp(1 - clock / Self.turnLimit)
                frame.seats[0].turn = frame.controls.clock
                // Left alone too long: check when that is free, fold when it is not.
                if clock >= Self.turnLimit { act(0, legal.call == 0 ? .check : .fold) }
            } else {
                clock += quick
                frame.seats[actor].turn = M.clamp(1 - clock / think)
                if clock >= think { act(actor, choose(actor)) }
            }

        case .gather:
            clock += quick
            frame.gather = M.clamp(clock / length)
            if clock >= length { gathered() }

        case .reveal:
            let before = clock
            clock += quick
            for k in 0..<revealCount {
                let start = Self.revealGap * Double(k)
                frame.shown[revealFrom + k] = M.clamp((clock - start) / Self.revealSlide)
                if before <= start && clock > start { owe(.thud) }
            }
            if clock >= length {
                nameHand()
                turn()
            }

        case .show:
            clock += Swift.min(quick, dt * 1.5)
            for k in 1..<table.seats.count where table.seats[k].live {
                frame.seats[k].face = M.clamp(clock / 0.35)
            }
            if clock >= length { award() }

        case .award:
            clock += Swift.min(quick, dt * 1.5)
            frame.awardAge = clock
            if !landed, clock >= ShortStackLayout.awardSlide {
                landed = true
                frame.pot = 0
                frame.total = 0
                var mine = false
                for k in table.seats.indices { chipGoal[k] = table.seats[k].chips }
                for award in frame.awards {
                    frame.seats[award.seat].glow = 1
                    if award.seat == 0 { mine = true }
                }
                if mine {
                    potsTaken += 1
                    owe(.success)
                } else {
                    owe(.thud)
                }
            }
            if clock >= length { closeHand() }
        }
    }

    // MARK: The hand

    private func startHand() {
        hand += 1
        let small = Self.firstSmall << Swift.min((hand - 1) / Self.handsPerLevel, 4)
        var deck = ShortStackCard.fresh()
        var last = deck.count - 1
        while last > 0 {
            deck.swapAt(last, deckRandom.below(last + 1))
            last -= 1
        }
        table.startHand(deck: deck, small: small, big: small * 2)

        let count = table.seats.count
        dealOrder.removeAll(keepingCapacity: true)
        for step in 1...count {
            let k = (table.button + step) % count
            if table.seats[k].status != .out { dealOrder.append(k) }
        }
        for k in 0..<count {
            frame.seats[k].cards = table.seats[k].hole
            frame.seats[k].dealt = 0
            frame.seats[k].face = 0
            frame.seats[k].folded = 0
            frame.seats[k].label = ""
            frame.seats[k].hand = ""
            frame.seats[k].turn = -1
            frame.seats[k].stakeSlide = 0
            frame.seats[k].out = table.seats[k].status == .out
            frame.seats[k].button = k == table.button
            raises[k] = 0
        }
        frame.board.removeAll(keepingCapacity: true)
        for k in 0..<5 { frame.shown[k] = 0 }
        frame.hand = hand
        frame.small = small
        frame.big = small * 2
        frame.awards.removeAll(keepingCapacity: true)
        frame.awardAge = -1
        frame.gather = 0
        sync()
        if hand > 1, (hand - 1) % Self.handsPerLevel == 0 {
            say("Blinds go up to \(small) and \(small * 2)", life: 1.5)
        }
        beat = .deal
        clock = 0
        length = Self.dealGap * Double(dealOrder.count * 2) + Self.dealSlide + 0.4
        owe(.thud)
    }

    private func say(_ words: String, life: Double) {
        frame.message = words
        frame.messageAge = 0
        frame.messageLife = life
    }

    /// Copies the chips on the table into the picture.
    private func sync() {
        var inFront = 0
        for k in table.seats.indices {
            frame.seats[k].stake = table.seats[k].stake
            chipGoal[k] = table.seats[k].chips
            inFront += table.seats[k].stake
        }
        frame.total = table.pot
        frame.pot = table.pot - inFront
    }

    /// Starts whatever the hand waits for.
    private func turn() {
        clock = 0
        switch table.next {
        case .act(let seat):
            beat = .turn
            actor = seat
            frame.seats[seat].turn = 1
            if seat == 0 {
                openControls()
            } else {
                think = othersRandom.range(Self.thinkShort, Self.thinkLong)
            }
        case .deal, .showdown, .uncontested:
            beat = .gather
            length = frame.seats.contains(where: { $0.stake > 0 }) ? Self.gatherLength : 0.05
        case .idle:
            break
        }
    }

    private func openControls() {
        legal = table.legal(0)
        turnSerial += 1
        menuOpen = false
        sizes.removeAll(keepingCapacity: true)
        var titles: [String] = []
        if legal.canRaise {
            let pot = table.pot + legal.call
            let unit = table.small
            let offers = [("Min", legal.minTo), ("Half pot", table.level + pot / 2), ("Pot", table.level + pot)]
            for (title, raw) in offers {
                let to = Swift.min(Swift.max(raw / unit * unit, legal.minTo), legal.maxTo)
                if to >= legal.maxTo || sizes.contains(to) { continue }
                sizes.append(to)
                titles.append(title)
            }
            sizes.append(legal.maxTo)
            titles.append("All in")
        }
        frame.controls.live = true
        frame.controls.call = legal.call == 0 ? "Check" : "Call"
        frame.controls.callSub = legal.call == 0 ? "" : M.grouped(legal.call)
        frame.controls.canRaise = legal.canRaise
        frame.controls.sizeTitles = titles
        frame.controls.sizeAmounts = sizes
        frame.controls.clock = 1
    }

    private func act(_ seat: Int, _ move: ShortStackTable.Move) {
        let owed = table.legal(seat).call
        let made = table.apply(move)
        let allIn = table.seats[seat].chips == 0
        let label: String
        switch made {
        case .fold: label = "Fold"
        case .check: label = "Check"
        case .call: label = allIn ? "All in" : "Call \(M.grouped(owed))"
        case .raise(let to):
            label = allIn ? "All in" : "Raise \(M.grouped(to))"
            raises[seat] += 1
        }
        frame.seats[seat].label = label
        frame.seats[seat].labelAge = 0
        frame.seats[seat].turn = -1
        if made != .fold, made != .check {
            frame.seats[seat].stakeSlide = 0
            owe(.thud)
        }
        if seat == 0 {
            frame.controls.live = false
            menuOpen = false
        }
        sync()
        turn()
    }

    /// The chips in front have reached the middle.
    private func gathered() {
        if frame.seats.contains(where: { $0.stake > 0 }) { owe(.thud) }
        frame.gather = 0
        for k in frame.seats.indices { frame.seats[k].stake = 0 }
        frame.pot = table.pot
        frame.total = table.pot
        clock = 0
        switch table.next {
        case .deal:
            revealFrom = table.board.count
            table.dealStreet()
            revealCount = table.board.count - revealFrom
            for k in revealFrom..<table.board.count { frame.board.append(table.board[k]) }
            for k in table.seats.indices {
                raises[k] = 0
                if table.seats[k].live { frame.seats[k].label = "" }
            }
            beat = .reveal
            length = Self.revealGap * Double(revealCount - 1) + Self.revealSlide + 0.3
        case .showdown:
            for k in table.seats.indices where table.seats[k].live {
                frame.seats[k].hand = ShortStackRank.name(table.score(k))
                frame.seats[k].label = ""
            }
            beat = .show
            length = Self.showLength
            owe(.thud)
        case .uncontested:
            award()
        case .act, .idle:
            turn()
        }
    }

    /// Tells the player what they hold, once there is a board to make a hand with.
    private func nameHand() {
        guard table.seats[0].live, table.board.count >= 3 else { return }
        frame.seats[0].hand = ShortStackRank.name(table.score(0))
    }

    private func award() {
        let showdown = table.next == .showdown
        if showdown, table.seats[0].live { bestShown = Swift.max(bestShown, table.score(0)) }
        let best = showdown ? table.seats.indices.filter { table.seats[$0].live }.map { table.score($0) } : []
        let awards = table.settle()
        frame.awards.removeAll(keepingCapacity: true)
        for award in awards {
            if let at = frame.awards.firstIndex(where: { $0.seat == award.seat }) {
                frame.awards[at].amount += award.amount
            } else {
                frame.awards.append(ShortStackAward(seat: award.seat, amount: award.amount))
            }
        }
        frame.awardAge = 0
        landed = false
        beat = .award
        clock = 0
        length = ShortStackLayout.awardSlide + (showdown ? Self.showdownHold : Self.foldedHold)

        // "kaz takes the pot. Two pair"
        func name(_ k: Int) -> String { k == 0 ? "You" : frame.seats[k].name }
        let main = awards.filter { $0.pot == 0 }.map(\.seat)
        var line: String
        if main.count == 1 {
            line = main[0] == 0 ? "You take the pot" : "\(name(main[0])) takes the pot"
        } else if main.count == 2 {
            line = "\(name(main[0])) and \(name(main[1])) split the pot"
        } else {
            line = "The pot is split \(main.count) ways"
        }
        if showdown, let top = best.max() { line += ". " + ShortStackRank.name(top) }
        if let side = awards.first(where: { $0.pot > 0 && !main.contains($0.seat) }) {
            line += side.seat == 0 ? ". You take a side pot" : ". \(name(side.seat)) takes a side pot"
        }
        say(line, life: length / Swift.min(pace, 1.5))
    }

    /// The sitting ends after its last hand, or sooner when the player has no chips or all of them.
    private func closeHand() {
        let mine = table.seats[0].chips
        let theirs = table.seats.dropFirst().reduce(0) { $0 + $1.chips }
        guard mine == 0 || theirs == 0 || hand >= Self.hands else {
            startHand()
            return
        }
        stage = .ending
        endClock = 0
        frame.controls.live = false
        frame.message = ""
        frame.endTitle = mine == 0 ? "Out of chips" : "Sitting over"
        frame.endScore = mine == 0 ? "" : "\(M.grouped(mine)) chips"
        if mine == 0 { owe(.fail) }
    }

    // MARK: The other seats

    /// One of the other seats makes up its mind: how good its cards are against what staying costs,
    /// with a lean of its own and a little chance.
    private func choose(_ seat: Int) -> ShortStackTable.Move {
        let rules = table.legal(seat)
        let me = table.seats[seat]
        let style = styles[seat]
        let strength = ShortStackOdds.strength(hole: me.hole, board: table.board, samples: 120, rng: &othersRandom)
        let roll = othersRandom.next()
        let chance = othersRandom.next()
        let pot = Double(table.pot)
        let owed = Double(rules.call)
        let price = owed / Swift.max(1, pot + owed)
        let pressure = owed / Swift.max(1, Double(me.chips))
        let rivals = table.seats.indices.filter { $0 != seat && table.seats[$0].live }.count
        // However big the raise, a hand this good always stays, so pushing all in every hand does not pay.
        let need = Swift.min(price + pressure * 0.34 + 0.1 + 0.02 * Double(rivals - 1), Self.alwaysStays) + style.caution
        if rules.call > 0, strength + (roll - 0.5) * 0.16 < need { return .fold }

        let quiet: ShortStackTable.Move = rules.call > 0 ? .call : .check
        guard rules.canRaise else { return quiet }
        let nerve = strength + style.push
        let again = raises[seat] > 0
        let bluff = chance < style.bluff && owed < Double(me.chips) * 0.15 && !again
        let strong = nerve > 0.8 && roll > 0.22 && (!again || nerve > 0.9)
        let fair = nerve > 0.66 && roll > 0.74 && !again
        guard strong || fair || bluff else { return quiet }

        let size = Swift.max(Double(table.minRaise), (pot + owed) * (0.4 + roll * 0.35))
        var to = table.level + Int((size / Double(table.small)).rounded(.up)) * table.small
        to = Swift.min(Swift.max(to, rules.minTo), rules.maxTo)
        // Never leave a crumb behind.
        if rules.maxTo - to < table.big * 2 { to = rules.maxTo }
        if to == rules.maxTo, nerve < 0.82, me.chips > table.big * 6 { return quiet }
        return .raise(to)
    }
}

// MARK: - Drawing

/// The table, painted once. It never changes in a sitting.
struct ShortStackBackdrop: View, Equatable {
    var body: some View {
        Canvas(opaque: true, colorMode: .nonLinear, rendersAsynchronously: false) { context, size in
            if size.width <= 8 || size.height <= 8 { return }
            ShortStackPainter(size: size, context: context).drawStill(&context)
        }
    }
}

/// Paints the model as it is right now, over the backdrop.
struct ShortStackCanvas: View {
    let model: ShortStackModel
    /// A new number every frame. The model is a class, so this is what makes SwiftUI repaint.
    var frame = 0

    var body: some View {
        Canvas(opaque: false, colorMode: .nonLinear, rendersAsynchronously: false) { context, size in
            if size.width <= 8 || size.height <= 8 { return }
            ShortStackPainter(size: size, context: context).drawLive(&context, model.frame, showHUD: true)
        }
    }
}

// MARK: - Scripted player

/// Plays the sitting for recordings while GameDemo.autopilot is on.
///
/// It reads the model on the player's turn and presses the same keys a finger does. Its random
/// numbers are its own, so the cards the model deals are the same with it or without it.
struct ShortStackPilot {
    private var rng: ShortStackRandom
    /// The turn the plan was made for.
    private var serial = -1
    private var keys: [ShortStackKey] = []
    private var sent = 0
    /// How long it looks at its cards before the first key.
    private var hold = 0.0

    init(seed: UInt64) {
        rng = ShortStackRandom(seed: seed, salt: ShortStackRandom.pilot)
    }

    /// Call once per step. Returns the key to press now, if any.
    mutating func key(_ model: ShortStackModel) -> ShortStackKey? {
        guard model.playerTurn else { return nil }
        if serial != model.turnSerial {
            serial = model.turnSerial
            sent = 0
            plan(model)
        }
        guard sent < keys.count, model.turnAge >= hold + 0.45 * Double(sent) else { return nil }
        sent += 1
        return keys[sent - 1]
    }

    private mutating func plan(_ model: ShortStackModel) {
        let rules = model.legal
        // Giving up: every chip goes in, every turn, until the sitting is over.
        if let limit = GameDemo.loseAfter, model.time >= limit {
            hold = 0.5
            keys = rules.canRaise ? [.raise, .size(model.sizes.count - 1)] : [.call]
            return
        }
        hold = rng.range(0.9, 1.8)
        let table = model.table
        let me = table.seats[0]
        let strength = ShortStackOdds.strength(hole: me.hole, board: table.board, samples: 120, rng: &rng)
        let owed = Double(rules.call)
        let price = owed / Swift.max(1, Double(table.pot) + owed)
        let pressure = owed / Swift.max(1, Double(me.chips))
        if rules.call > 0, strength < price + pressure * 0.4 + 0.13 {
            keys = [.fold]
            return
        }
        if rules.canRaise, strength > 0.76, rng.next() > 0.25 {
            let pick = Swift.min(strength > 0.9 ? 2 : 1, model.sizes.count - 1)
            // All in only with a very good hand or very few chips.
            if pick < model.sizes.count - 1 || strength > 0.9 || me.chips <= table.big * 5 {
                keys = [.raise, .size(pick)]
                return
            }
        }
        keys = [.call]
    }
}

// MARK: - Game view

/// Holds the sitting between frames. Nothing is published: the timeline repaints every frame anyway.
final class ShortStackRunner: ObservableObject {
    let model: ShortStackModel
    private let seed: UInt64
    private var lastDate: Date?
    private var frame = 0
    private var reported = false
    /// Made the first time it is needed, which is only when GameDemo.autopilot is on.
    private var pilot: ShortStackPilot?

    init(options: GameOptions) {
        model = ShortStackModel(options: options)
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
                if pilot == nil { pilot = ShortStackPilot(seed: seed) }
                if let key = pilot?.key(model) { press(key, link: link) }
            }
        }
        frame &+= 1
        return frame
    }

    /// A finger has landed. Keys answer at once; anywhere else puts the raise sizes away.
    func touch(at point: CGPoint, in size: CGSize, link: GameLink) {
        if link.paused || link.isFinished { return }
        let layout = ShortStackLayout(size: size)
        if let key = layout.key(at: point, sizes: model.menuOpen ? model.sizes.count : 0) {
            press(key, link: link)
        } else {
            model.closeMenu()
        }
    }

    func press(_ key: ShortStackKey, link: GameLink) {
        if link.paused || link.isFinished { return }
        if model.press(key) { GameHaptics.tap() }
        settle(link)
    }

    /// Plays the haptic the model owes and reports the sitting once it is over.
    private func settle(_ link: GameLink) {
        switch model.takeFeedback() {
        case .fail: GameHaptics.fail()
        case .success: GameHaptics.success()
        case .thud: GameHaptics.thud()
        case .none: break
        }
        if model.stage == .finished, !reported {
            reported = true
            let result = model.result
            DispatchQueue.main.async { link.finish(result) }
        }
    }
}

public struct ShortStackGame: View {
    private let options: GameOptions
    private let link: GameLink

    public init(options: GameOptions, link: GameLink) {
        self.options = options
        self.link = link
    }

    public var body: some View {
        // A new link is a new sitting, so the sitting's state lives and dies with the link.
        ShortStackRound(options: options, link: link)
            .id(ObjectIdentifier(link))
    }
}

private struct ShortStackRound: View {
    @ObservedObject var link: GameLink
    @StateObject private var runner: ShortStackRunner
    @GestureState private var touching = false

    init(options: GameOptions, link: GameLink) {
        self.link = link
        _runner = StateObject(wrappedValue: ShortStackRunner(options: options))
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ShortStackBackdrop().equatable()
                TimelineView(.animation(minimumInterval: nil, paused: link.paused)) { timeline in
                    ShortStackCanvas(model: runner.model, frame: runner.advance(to: timeline.date, link: link))
                }
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
        .accessibilityLabel("Short Stack. Fold, check or call, and raise are along the bottom.")
        .accessibilityAddTraits(.allowsDirectInteraction)
    }
}
