import SwiftUI

// Wild Eights, playable: a shedding card game against friends the game plays itself.
//
// WildEightsModel   the rules of a round in plain Swift: step(dt:) and apply(_:).
// WildEightsPilot   the scripted player. The game runs it only while GameDemo.autopilot is on.
// WildEightsRunner  keeps the clock, turns touches into moves, fires haptics, reports the result.
// WildEightsGame    the view the app shows.
//
// The painter, the layout and the card art are in WildEightsScene.swift.

// MARK: - Cards

enum WildEightsSuit: Int, CaseIterable {
    case spades, hearts, clubs, diamonds

    var isRed: Bool { self == .hearts || self == .diamonds }

    var word: String {
        switch self {
        case .spades: return "spades"
        case .hearts: return "hearts"
        case .clubs: return "clubs"
        case .diamonds: return "diamonds"
        }
    }
}

struct WildEightsCard: Equatable {
    let rank: Int
    let suit: WildEightsSuit

    static let labels = ["A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"]

    var label: String { Self.labels[rank - 1] }
    var isEight: Bool { rank == 8 }
    /// Hand order: suits alternate colour, then by rank.
    var order: Int { suit.rawValue * 20 + rank }
}

/// SplitMix64. The same seed deals friends the same round.
struct WildEightsDice {
    private var state: UInt64

    init(seed: UInt64, salt: UInt64) { state = (seed ^ salt) &* 0x9E3779B97F4A7C15 &+ 0x2545F4914F6CDD1D }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var v = state
        v = (v ^ (v >> 30)) &* 0xBF58476D1CE4E5B9
        v = (v ^ (v >> 27)) &* 0x94D049BB133111EB
        return v ^ (v >> 31)
    }

    mutating func unit() -> Double { Double(next() >> 11) / 9007199254740992.0 }
    mutating func range(_ lo: Double, _ hi: Double) -> Double { lo + (hi - lo) * unit() }
    mutating func int(_ count: Int) -> Int { count <= 1 ? 0 : Int(next() % UInt64(count)) }
}

// MARK: - Model

final class WildEightsModel {
    enum Stage { case dealing, ready, playing, ending, finished }

    /// What the last moves deserve as a haptic. A stronger one replaces a weaker one.
    enum Beat: Int { case none, deal, tap, place, deny, good, lost, out }

    /// A move, from a finger or from the scripted player.
    enum Move { case touch, card(Int), deck, pile, suit(WildEightsSuit) }

    /// Where a card is on the table. The painter turns it into a point.
    enum Spot: Equatable {
        case deck, discard
        case seat(Int)
        /// The player's hand: the card's place in the fan and how many cards the fan had.
        case hand(Double, Int)
    }

    struct Rival {
        let name: String
        let initial: String
        var hand: [WildEightsCard] = []
        var playedAt = -10.0
    }

    struct Slot {
        let card: WildEightsCard
        var pos: Double
        var born: Double
        var lift = 0.0
    }

    struct Flight {
        let card: WildEightsCard
        let from: Spot
        let to: Spot
        let start: Double
        let length: Double
        let faceFrom: Bool
        let faceTo: Bool
        let spin: Double
    }

    struct Particle {
        var spot = Spot.discard
        var x = 0.0, y = 0.0, vx = 0.0, vy = 0.0
        var age = 1.0, life = 0.0
        var size = 4.0
        var tone = 0
    }

    struct Floater {
        let text: String
        let spot: Spot
        let born: Double
        let big: Bool
    }

    static let handSize = 7
    static let dealGap = 0.055
    static let playFlight = 0.26
    static let rivalFlight = 0.34
    static let endLength = 2.1
    static let cardPoints = 20
    static let eightPoints = 40

    let solo: Bool
    let bestScore: Int
    private var rng: WildEightsDice

    private(set) var stage = Stage.dealing
    /// Animation clock: runs whenever the game is not paused.
    private(set) var clock = 0.0
    /// Round clock: from the first touch to the moment someone goes out.
    private(set) var elapsed = 0.0
    private(set) var endClock = 0.0

    private(set) var deck: [WildEightsCard] = []
    private(set) var discard: [WildEightsCard] = []
    private(set) var rivals: [Rival] = []
    private(set) var slots: [Slot] = []
    private(set) var suit = WildEightsSuit.spades
    private(set) var suitPickedAt = -10.0

    /// 0 is the player, k is rivals[k - 1].
    private(set) var turn = 0
    private(set) var turnStartedAt = 0.0
    private(set) var selected: Int?
    private(set) var drewThisTurn = false
    private(set) var choosing = false
    private(set) var sheetCard = WildEightsCard(rank: 8, suit: .spades)
    private(set) var sheet = 0.0
    private var wait = 0.0
    private var dealt = 0
    private var dealTimer = 0.4

    private(set) var flights: [Flight] = []
    private(set) var particles: [Particle] = Array(repeating: Particle(), count: 96)
    private var nextParticle = 0
    private(set) var floaters: [Floater] = []
    private(set) var praise: String?
    private(set) var praiseAt = -10.0

    private(set) var score = 0
    private(set) var shownScore = 0.0
    private(set) var scorePoppedAt = -10.0
    private(set) var played = 0
    private(set) var draws = 0
    private var streak = 0
    private(set) var shakeCard: WildEightsCard?
    private(set) var shakeAt = -10.0

    private(set) var winner: Int?
    private(set) var pill = "Dealing"
    private(set) var endTitle = ""
    private(set) var endLine = ""
    private(set) var result: GameResult?

    private var beat = Beat.none

    init(options: GameOptions) {
        solo = options.solo
        bestScore = Swift.max(0, options.bestScore)
        rng = WildEightsDice(seed: options.seed, salt: 0x5741_4C44_3845)

        var names = options.solo ? [] : Array(options.friendNames.filter { !$0.isEmpty }.prefix(3))
        if names.isEmpty { names = ["pip"] }
        rivals = names.map { Rival(name: $0, initial: String($0.prefix(1)).uppercased()) }

        deck.reserveCapacity(52)
        discard.reserveCapacity(52)
        flights.reserveCapacity(16)
        slots.reserveCapacity(32)
        for suit in WildEightsSuit.allCases {
            for rank in 1...13 { deck.append(WildEightsCard(rank: rank, suit: suit)) }
        }
        shuffle(&deck)
    }

    // MARK: Reading

    var seatCount: Int { rivals.count + 1 }
    var top: WildEightsCard? { discard.last }
    var isPlayerTurn: Bool { turn == 0 && (stage == .ready || stage == .playing) }
    var canAct: Bool { isPlayerTurn && !choosing }
    var canDraw: Bool { deck.count + discard.count > 1 }

    func isPlayable(_ card: WildEightsCard) -> Bool {
        guard let top else { return false }
        return card.isEight || card.suit == suit || card.rank == top.rank
    }

    var hasPlayable: Bool { slots.contains { isPlayable($0.card) } }

    /// Discard cards still in the air, so the pile shows what was under them.
    var discardInFlight: Int {
        var n = 0
        for flight in flights where flight.to == .discard && clock - flight.start < flight.length { n += 1 }
        return n
    }

    func cardsLeft(_ seat: Int) -> Int { seat == 0 ? slots.count : rivals[seat - 1].hand.count }

    func name(_ seat: Int) -> String { seat == 0 ? "You" : rivals[seat - 1].name }

    func takeBeat() -> Beat {
        let owed = beat
        beat = .none
        return owed
    }

    private func owe(_ kind: Beat) {
        if kind.rawValue > beat.rawValue { beat = kind }
    }

    // MARK: Moves

    func apply(_ move: Move) {
        switch move {
        case .touch:
            if stage == .ready { stage = .playing }
        case .card(let index):
            tapCard(index)
        case .deck:
            tapDeck()
        case .pile:
            if canAct, let index = selected { tapCard(index) }
        case .suit(let picked):
            chooseSuit(picked)
        }
        refreshPill()
    }

    private func tapCard(_ index: Int) {
        guard canAct, slots.indices.contains(index) else { return }
        if stage == .ready { stage = .playing }
        let card = slots[index].card
        guard isPlayable(card) else {
            shakeCard = card
            shakeAt = clock
            owe(.deny)
            return
        }
        if selected == index {
            playPlayer(index)
        } else {
            selected = index
            owe(.tap)
        }
    }

    private func tapDeck() {
        guard canAct else { return }
        if stage == .ready { stage = .playing }
        if drewThisTurn {
            owe(.tap)
            endTurn()
            return
        }
        guard let card = drawOne() else {
            owe(.tap)
            endTurn()
            return
        }
        var index = slots.count
        for (k, slot) in slots.enumerated() where slot.card.order > card.order {
            index = k
            break
        }
        slots.insert(Slot(card: card, pos: Double(index), born: clock), at: index)
        draws += 1
        streak = 0
        drewThisTurn = true
        owe(.tap)
        if isPlayable(card) {
            selected = index
        } else {
            endTurn()
        }
    }

    private func playPlayer(_ index: Int) {
        let slot = slots.remove(at: index)
        selected = nil
        let card = slot.card
        let under = top
        flights.append(Flight(card: card, from: .hand(slot.pos, slots.count + 1), to: .discard, start: clock,
                              length: Self.playFlight, faceFrom: true, faceTo: true, spin: rng.range(-0.25, 0.25)))
        discard.append(card)
        played += 1
        streak += 1

        let gain = card.isEight ? Self.eightPoints : Self.cardPoints
        addScore(gain, at: .discard, delay: Self.playFlight, big: false)
        burst(at: .discard, count: card.isEight ? 22 : 12, delay: Self.playFlight, speed: card.isEight ? 260 : 190)
        owe(.place)

        if slots.isEmpty {
            goOut(0)
            return
        }
        if card.isEight {
            say("Wild")
            choosing = true
            sheetCard = card
            return
        }
        if slots.count == 1 {
            say("Last card")
        } else if streak >= 4 && streak % 2 == 0 {
            say("Great")
        } else if let under, under.rank == card.rank, under.suit != card.suit {
            say("Nice")
        }
        suit = card.suit
        endTurn()
    }

    private func chooseSuit(_ picked: WildEightsSuit) {
        guard choosing else { return }
        choosing = false
        suit = picked
        suitPickedAt = clock
        owe(.good)
        endTurn()
    }

    private func endTurn() {
        selected = nil
        drewThisTurn = false
        turn = (turn + 1) % seatCount
        turnStartedAt = clock
        if turn != 0 { wait = rng.range(0.7, 1.05) }
    }

    // MARK: Rivals

    private func rivalAct() {
        let r = turn - 1
        if let index = rivalChoice(r) {
            rivalPlay(r, index)
            refreshPill()
            return
        }
        if drewThisTurn {
            endTurn()
            refreshPill()
            return
        }
        guard let card = drawOne() else {
            endTurn()
            refreshPill()
            return
        }
        rivals[r].hand.append(card)
        flights.append(Flight(card: card, from: .deck, to: .seat(turn), start: clock, length: 0.3,
                              faceFrom: false, faceTo: false, spin: rng.range(-0.4, 0.4)))
        drewThisTurn = true
        wait = 0.45
        refreshPill()
    }

    private func rivalChoice(_ r: Int) -> Int? {
        let hand = rivals[r].hand
        var best: Int?
        var bestKeep = -1
        var eight: Int?
        for (k, card) in hand.enumerated() where isPlayable(card) {
            if card.isEight {
                if eight == nil { eight = k }
                continue
            }
            // Keep the suit it holds most of, with a little doubt so rivals differ.
            var keep = 0
            for other in hand where other.suit == card.suit && !other.isEight { keep += 2 }
            keep += rng.int(2)
            if keep > bestKeep {
                bestKeep = keep
                best = k
            }
        }
        return best ?? eight
    }

    private func rivalPlay(_ r: Int, _ index: Int) {
        let card = rivals[r].hand.remove(at: index)
        let seat = r + 1
        flights.append(Flight(card: card, from: .seat(seat), to: .discard, start: clock, length: Self.rivalFlight,
                              faceFrom: false, faceTo: true, spin: rng.range(-0.5, 0.5)))
        discard.append(card)
        rivals[r].playedAt = clock
        burst(at: .discard, count: 6, delay: Self.rivalFlight, speed: 140)
        owe(.tap)
        if rivals[r].hand.isEmpty {
            goOut(seat)
            return
        }
        if card.isEight {
            suit = Self.favourite(rivals[r].hand) ?? card.suit
            suitPickedAt = clock + Self.rivalFlight
        } else {
            suit = card.suit
        }
        endTurn()
    }

    static func favourite(_ hand: [WildEightsCard]) -> WildEightsSuit? {
        var counts = [0, 0, 0, 0]
        for card in hand where !card.isEight { counts[card.suit.rawValue] += 1 }
        guard let most = counts.max(), most > 0, let k = counts.firstIndex(of: most) else { return nil }
        return WildEightsSuit(rawValue: k)
    }

    // MARK: Deck

    private func drawOne() -> WildEightsCard? {
        if deck.isEmpty && discard.count > 1 {
            let keep = discard.removeLast()
            deck = discard
            discard.removeAll(keepingCapacity: true)
            discard.append(keep)
            shuffle(&deck)
        }
        return deck.popLast()
    }

    private func shuffle(_ cards: inout [WildEightsCard]) {
        var last = cards.count - 1
        while last > 0 {
            cards.swapAt(last, rng.int(last + 1))
            last -= 1
        }
    }

    private func dealOne() {
        let total = Self.handSize * seatCount
        if dealt < total {
            let seat = dealt % seatCount
            dealt += 1
            guard let card = deck.popLast() else { return }
            if seat == 0 {
                slots.append(Slot(card: card, pos: Double(slots.count), born: clock))
                owe(.deal)
            } else {
                rivals[seat - 1].hand.append(card)
                flights.append(Flight(card: card, from: .deck, to: .seat(seat), start: clock, length: 0.28,
                                      faceFrom: false, faceTo: false, spin: rng.range(-0.6, 0.6)))
            }
            dealTimer += Self.dealGap
            return
        }
        if discard.isEmpty {
            // Sort the hand, then turn the first card that is not an eight.
            slots.sort { $0.card.order < $1.card.order }
            var guardCount = 0
            while let last = deck.last, last.isEight, guardCount < 8 {
                deck.insert(deck.removeLast(), at: 0)
                guardCount += 1
            }
            if let card = deck.popLast() {
                discard.append(card)
                suit = card.suit
                flights.append(Flight(card: card, from: .deck, to: .discard, start: clock, length: 0.32,
                                      faceFrom: false, faceTo: true, spin: 0.3))
            }
            owe(.place)
            dealTimer += 0.4
            return
        }
        stage = .ready
        turn = 0
        turnStartedAt = clock
        refreshPill()
    }

    // MARK: Score and juice

    private func addScore(_ points: Int, at spot: Spot, delay: Double, big: Bool) {
        if points == 0 { return }
        score = Swift.max(0, score + points)
        scorePoppedAt = clock + delay
        if floaters.count >= 6 { floaters.removeFirst() }
        floaters.append(Floater(text: points > 0 ? "+\(points)" : "\(points)", spot: spot, born: clock + delay, big: big))
    }

    private func say(_ word: String) {
        praise = word
        praiseAt = clock + Self.playFlight * 0.6
    }

    private func burst(at spot: Spot, count: Int, delay: Double, speed: Double) {
        for _ in 0..<count {
            let angle = rng.range(0, 2 * Double.pi)
            let pace = speed * rng.range(0.45, 1.0)
            var p = Particle()
            p.spot = spot
            p.vx = cos(angle) * pace
            p.vy = sin(angle) * pace - speed * 0.35
            p.age = -delay
            p.life = rng.range(0.45, 0.8)
            p.size = rng.range(3, 6.5)
            p.tone = rng.int(5)
            particles[nextParticle] = p
            nextParticle = (nextParticle + 1) % particles.count
        }
    }

    // MARK: The end

    private func goOut(_ seat: Int) {
        winner = seat
        stage = .ending
        endClock = 0
        choosing = false
        selected = nil
        let seconds = Int(elapsed.rounded())
        let time = seconds >= 60 ? "\(seconds / 60)m \(String(format: "%02d", seconds % 60))s" : "\(seconds)s"
        if seat == 0 {
            let bonus = 300 + Swift.max(0, 300 - Int(elapsed * 2))
            addScore(bonus, at: .discard, delay: Self.playFlight + 0.15, big: true)
            burst(at: .discard, count: 40, delay: Self.playFlight, speed: 340)
            say(draws == 0 ? "Perfect" : "Out first")
            endTitle = "You went out first"
            endLine = "in \(time)"
            owe(.out)
        } else {
            let left = slots.count
            addScore(-10 * left, at: .hand(Double(left - 1) / 2, left), delay: 0.5, big: false)
            endTitle = "\(rivals[seat - 1].name) went out first"
            endLine = left == 1 ? "You had 1 card left" : "You had \(left) cards left"
            owe(.lost)
        }
        refreshPill()

        let placement: Int
        if seat == 0 {
            placement = 1
        } else {
            placement = 1 + rivals.filter { $0.hand.count < slots.count }.count
        }
        let detail = seat == 0 ? "Out first in \(time)" : "\(rivals[seat - 1].name) went out first. \(endLine)"
        result = GameResult(score: score, unit: "points", detail: detail, placement: placement, playerCount: seatCount)
    }

    private func refreshPill() {
        switch stage {
        case .dealing:
            pill = "Dealing"
        case .ending, .finished:
            pill = endTitle
        case .ready, .playing:
            if turn != 0 {
                pill = "\(rivals[turn - 1].name) is playing"
            } else if choosing {
                pill = "Pick the next suit"
            } else if drewThisTurn && selected != nil {
                pill = "Play it, or tap the deck to pass"
            } else if hasPlayable {
                if let top, !top.isEight {
                    pill = "Your turn \u{00B7} match \(suit.word) or \(top.label)"
                } else {
                    pill = "Your turn \u{00B7} play \(suit.word) or an 8"
                }
            } else {
                pill = canDraw ? "No match. Tap the deck to draw" : "No match. Tap the deck to pass"
            }
        }
    }

    // MARK: Clock

    func step(dt raw: Double) {
        let dt = Swift.min(Swift.max(raw, 0), 1.0 / 30)
        if dt <= 0 { return }
        clock += dt
        if stage == .finished { return }
        if stage == .playing { elapsed += dt }

        if !flights.isEmpty {
            let now = clock
            flights.removeAll { now - $0.start >= $0.length }
        }
        for k in particles.indices where particles[k].age < particles[k].life {
            particles[k].age += dt
            if particles[k].age > 0 {
                particles[k].x += particles[k].vx * dt
                particles[k].y += particles[k].vy * dt
                particles[k].vy += 520 * dt
                particles[k].vx *= 1 - 1.6 * dt
            }
        }
        if let first = floaters.first, clock - first.born > 1.3 { floaters.removeFirst() }
        if praise != nil, clock - praiseAt > 1.1 { praise = nil }

        let goal = Double(score)
        shownScore += (goal - shownScore) * (1 - exp(-9 * dt))
        if abs(goal - shownScore) < 0.5 { shownScore = goal }

        let ease = 1 - exp(-16 * dt)
        let myTurn = canAct
        for k in slots.indices {
            slots[k].pos += (Double(k) - slots[k].pos) * ease
            var lift = 0.0
            if selected == k {
                lift = 1
            } else if myTurn && isPlayable(slots[k].card) {
                lift = 0.35
            }
            slots[k].lift += (lift - slots[k].lift) * ease
        }
        sheet += ((choosing ? 1 : 0) - sheet) * (1 - exp(-15 * dt))

        switch stage {
        case .dealing:
            dealTimer -= dt
            while dealTimer <= 0 && stage == .dealing { dealOne() }
        case .ready:
            break
        case .playing:
            if turn != 0 {
                wait -= dt
                if wait <= 0 { rivalAct() }
            }
        case .ending:
            endClock += dt
            if endClock >= Self.endLength { stage = .finished }
        case .finished:
            break
        }
    }
}

// MARK: - Scripted player

/// Plays the round for recordings and for the cover. Reads the model and answers with one move at a time,
/// through the same calls a finger uses. Its random numbers are its own.
struct WildEightsPilot {
    private var rng: WildEightsDice
    private var cooldown = 0.0

    init(seed: UInt64) {
        rng = WildEightsDice(seed: seed, salt: 0x7069_6C6F_7438)
    }

    mutating func next(_ m: WildEightsModel, dt: Double, loseAfter: Double?) -> WildEightsModel.Move? {
        cooldown -= dt
        if cooldown > 0 { return nil }
        if m.choosing, m.sheet > 0.85 {
            cooldown = rng.range(0.35, 0.55)
            return .suit(WildEightsModel.favourite(m.slots.map(\.card)) ?? .hearts)
        }
        guard m.canAct else { return nil }
        if m.stage == .ready && m.clock - m.turnStartedAt < 0.7 { return nil }
        if m.clock - m.turnStartedAt < 0.25 { return nil }

        if let limit = loseAfter, m.elapsed >= limit, m.canDraw || m.drewThisTurn {
            cooldown = rng.range(0.4, 0.6)
            return .deck
        }
        if let index = m.selected {
            cooldown = rng.range(0.35, 0.5)
            return .card(index)
        }
        var best: Int?
        var bestKeep = -1
        var eight: Int?
        for (k, slot) in m.slots.enumerated() where m.isPlayable(slot.card) {
            if slot.card.isEight {
                if eight == nil { eight = k }
                continue
            }
            var keep = 0
            for other in m.slots where other.card.suit == slot.card.suit { keep += 1 }
            if keep > bestKeep {
                bestKeep = keep
                best = k
            }
        }
        if let pick = best ?? eight {
            cooldown = rng.range(0.25, 0.4)
            return .card(pick)
        }
        cooldown = rng.range(0.45, 0.65)
        return .deck
    }
}

// MARK: - Game view

/// Holds the round between frames. Nothing is published: the timeline repaints every frame anyway.
final class WildEightsRunner: ObservableObject {
    let model: WildEightsModel
    private let seed: UInt64
    private var lastDate: Date?
    private var frame = 0
    private var reported = false
    private var pilot: WildEightsPilot?

    init(options: GameOptions) {
        model = WildEightsModel(options: options)
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
                if pilot == nil { pilot = WildEightsPilot(seed: seed) }
                if let move = pilot?.next(model, dt: dt, loseAfter: GameDemo.loseAfter) {
                    model.apply(.touch)
                    model.apply(move)
                }
            }
            settle(link)
        }
        frame &+= 1
        return frame
    }

    func touch(at point: CGPoint, in size: CGSize, link: GameLink) {
        if link.paused || link.isFinished { return }
        let layout = WildEightsLayout(size: size)
        let m = model
        m.apply(.touch)
        if m.choosing {
            if m.sheet > 0.6, let suit = layout.suitButton(at: point, sheet: m.sheet) { m.apply(.suit(suit)) }
        } else if let index = layout.handIndex(at: point, model: m) {
            m.apply(.card(index))
        } else if layout.deckRect.contains(point) {
            m.apply(.deck)
        } else if layout.discardRect.contains(point) {
            m.apply(.pile)
        }
        settle(link)
    }

    private func settle(_ link: GameLink) {
        switch model.takeBeat() {
        case .none: break
        case .deal, .tap: GameHaptics.tap()
        case .place: GameHaptics.thud()
        case .deny: GameHaptics.fail()
        case .good: GameHaptics.success()
        case .lost: GameHaptics.fail()
        case .out:
            GameHaptics.heavy()
            GameHaptics.success()
        }
        if model.stage == .finished, !reported, let result = model.result {
            reported = true
            DispatchQueue.main.async { link.finish(result) }
        }
    }
}

public struct WildEightsGame: View {
    private let options: GameOptions
    private let link: GameLink

    public init(options: GameOptions, link: GameLink) {
        self.options = options
        self.link = link
    }

    public var body: some View {
        WildEightsRound(options: options, link: link)
            .id(ObjectIdentifier(link))
    }
}

private struct WildEightsRound: View {
    @ObservedObject var link: GameLink
    @StateObject private var runner: WildEightsRunner
    @GestureState private var touching = false

    init(options: GameOptions, link: GameLink) {
        self.link = link
        _runner = StateObject(wrappedValue: WildEightsRunner(options: options))
    }

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: nil, paused: link.paused)) { timeline in
                WildEightsCanvas(model: runner.model, frame: runner.advance(to: timeline.date, link: link))
            }
            .contentShape(Rectangle())
            .gesture(
                // Fires as the finger lands, once per touch.
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
        .accessibilityLabel("Wild Eights. Tap a card twice to play it, or tap the deck to draw.")
        .accessibilityAddTraits(.allowsDirectInteraction)
    }
}

/// Paints the model as it is right now.
struct WildEightsCanvas: View {
    let model: WildEightsModel
    /// A new number every frame. The model is a class, so this is what makes SwiftUI repaint.
    var frame = 0

    var body: some View {
        Canvas(opaque: true, colorMode: .nonLinear, rendersAsynchronously: false) { context, size in
            if size.width <= 8 || size.height <= 8 { return }
            WildEightsPainter(model: model, size: size, showHUD: true, live: true).paint(&context)
        }
    }
}
