import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// Wild Eights, playable.
//
// WildEightsModel   the rules of a round in plain Swift: step(dt:), tapHand, tapDeck, pickSuit.
// WildEightsCanvas  paints the model with the clip's painter.
// WildEightsPilot   the scripted player. It only runs while GameDemo.autopilot is on.
// WildEightsRunner  keeps the clock, turns touches into moves, fires haptics, reports the result.
// WildEightsGame    the view the app shows.

// MARK: - Model

final class WildEightsModel {
    enum Stage { case dealing, playing, ending, finished }

    /// What happened since the last frame, for haptics.
    enum Event { case lift, place, draw, eight, reject, pass, out, lost }

    struct Player {
        let name: String
        var hand: [WildEightsCard]
    }

    /// A card on its way somewhere. What happens when it lands depends on `to` and `player`.
    struct Flight {
        var card: WildEightsCard
        var from: WildEightsSpot
        var to: WildEightsSpot
        var age: Double
        var length: Double
        var faceUp: Bool
        /// Who played or drew it. nil for the deal.
        var player: Int?
        /// The suit a bot asked for with an eight, decided when the card left its hand.
        var wild: WildEightsSuit?
    }

    // Tuning, in seconds.
    static let handSize = 7
    static let dealGap = 0.085
    static let dealFlight = 0.36
    static let playFlight = 0.3
    static let drawFlight = 0.32
    static let passDelay = 0.55
    static let endLength = 2.1
    static let liftRate = 16.0

    let solo: Bool
    private var rng: WildEightsRandom

    private(set) var stage = Stage.dealing
    private(set) var players: [Player] = []
    private(set) var deck: [WildEightsCard] = []
    private(set) var pile: [WildEightsCard] = []
    private(set) var flights: [Flight] = []
    private(set) var turn = 0
    private(set) var wildSuit: WildEightsSuit?
    /// Set while the suit picker is up for an eight the player just put down.
    private(set) var pendingEight: WildEightsCard?
    private(set) var drewThisTurn = false
    private(set) var selected: Int?
    /// One lift per card in the player's hand, eased every step.
    private(set) var lifts: [Double] = []
    private(set) var dragIndex: Int?
    private(set) var dragX = 0.0
    private(set) var dragY = 0.0
    private(set) var sheet = 0.0
    private(set) var sheetPressed: WildEightsSuit?
    private(set) var score = 0
    private(set) var shownScore = 0.0
    private(set) var notes: [WildEightsNote] = []
    private(set) var praise: String?
    private(set) var praiseAge = 0.0
    private(set) var banner: String?
    private(set) var bannerAge = 0.0
    private(set) var dim = 0.0
    /// Round clock: from the end of the deal to the end of the round.
    private(set) var time = 0.0
    /// Scenery clock: runs whenever the game is not paused.
    private(set) var ambient = 0.0
    private(set) var endClock = 0.0
    private(set) var winner: Int?

    private var dealt = 0
    private var dealClock = 0.0
    private var botWait = 0.0
    private var passWait: Double?
    private var passes = 0
    private var events: [Event] = []

    init(options: GameOptions) {
        solo = options.solo
        rng = WildEightsRandom(seed: options.seed, salt: WildEightsRandom.round)
        var names: [String] = options.solo ? [] : Array(options.friendNames.filter { !$0.isEmpty }.prefix(3))
        if names.isEmpty { names = ["dealer"] }
        players.append(Player(name: options.playerName, hand: []))
        for name in names { players.append(Player(name: name, hand: [])) }

        for suit in WildEightsSuit.allCases {
            for rank in 1...13 { deck.append(WildEightsCard(rank: rank, suit: suit)) }
        }
        shuffle(&deck)
        lifts.reserveCapacity(24)
        notes.reserveCapacity(8)
        flights.reserveCapacity(4)
    }

    private func shuffle(_ cards: inout [WildEightsCard]) {
        var last = cards.count - 1
        while last > 0 {
            cards.swapAt(last, rng.int(0...last))
            last -= 1
        }
    }

    // MARK: Reading

    var playerCount: Int { players.count }
    var hand: [WildEightsCard] { players[0].hand }
    var top: WildEightsCard? { pile.last }
    var busy: Bool { !flights.isEmpty || stage != .playing }
    var yourTurn: Bool { stage == .playing && turn == 0 }

    func canPlay(_ card: WildEightsCard) -> Bool {
        guard let top else { return true }
        if card.isEight { return true }
        if let wildSuit { return card.suit == wildSuit }
        return card.suit == top.suit || card.rank == top.rank
    }

    var hasPlay: Bool { players[0].hand.contains { canPlay($0) } }

    /// The one line under the piles.
    var pill: String {
        switch stage {
        case .dealing: return "Dealing"
        case .ending, .finished: return ""
        case .playing: break
        }
        if turn != 0 { return "\(players[turn].name) is thinking" }
        if pendingEight != nil { return "Pick a suit" }
        if hasPlay {
            if drewThisTurn { return "Play a card" }
            if let wildSuit { return "Your turn. Match \(wildSuit.symbol)" }
            if let top { return "Your turn. Match \(top.suit.symbol) or \(top.label)" }
            return "Your turn"
        }
        if drewThisTurn || (deck.isEmpty && pile.count <= 1) { return "No match. Passing" }
        return "No match. Tap the deck"
    }

    var result: GameResult {
        let count = players.count
        let left = players[0].hand.count
        if winner == 0 {
            return GameResult(score: score, unit: "points", detail: "Went out first", placement: 1, playerCount: count)
        }
        var ahead = 0
        for k in 1..<count where players[k].hand.count < left { ahead += 1 }
        let line = left == 1 ? "1 card left in hand" : "\(left) cards left in hand"
        return GameResult(score: score, unit: "points", detail: line, placement: 1 + ahead, playerCount: count)
    }

    /// Hands over the events since the last call.
    func takeEvents() -> [Event] {
        if events.isEmpty { return events }
        let owed = events
        events.removeAll(keepingCapacity: true)
        return owed
    }

    // MARK: Input

    /// A tap on a card in the player's hand: lift it, or play it when it is already up.
    func tapHand(_ index: Int) {
        guard yourTurn, flights.isEmpty, pendingEight == nil, index >= 0, index < players[0].hand.count else { return }
        if !canPlay(players[0].hand[index]) {
            selected = nil
            events.append(.reject)
            return
        }
        if selected == index {
            play(0, index: index, wild: nil)
            return
        }
        selected = index
        events.append(.lift)
    }

    /// A tap on the table: a lifted card goes back down.
    func putDown() {
        if selected != nil { selected = nil }
    }

    /// A tap on the deck: draw one card, once a turn.
    func tapDeck() {
        guard yourTurn, flights.isEmpty, pendingEight == nil else { return }
        if drewThisTurn {
            events.append(.reject)
            return
        }
        selected = nil
        refill()
        if deck.isEmpty {
            passWait = Self.passDelay
            events.append(.reject)
            return
        }
        draw(0)
    }

    /// The suit picked for an eight the player put down.
    func pickSuit(_ suit: WildEightsSuit) {
        guard pendingEight != nil else { return }
        wildSuit = suit
        pendingEight = nil
        sheetPressed = suit
        events.append(.place)
        endTurn()
    }

    func pressSuit(_ suit: WildEightsSuit?) {
        if pendingEight != nil { sheetPressed = suit }
    }

    /// A finger moving a hand card. nil ends the drag without playing.
    func drag(_ index: Int?, dx: Double, dy: Double) {
        guard let index, yourTurn, flights.isEmpty, pendingEight == nil, index < players[0].hand.count else {
            dragIndex = nil
            dragX = 0
            dragY = 0
            return
        }
        dragIndex = index
        dragX = dx
        dragY = Swift.min(dy, 0)
    }

    /// The finger let go of a dragged card. True when the card was played.
    @discardableResult
    func dropDrag(play shouldPlay: Bool) -> Bool {
        defer {
            dragIndex = nil
            dragX = 0
            dragY = 0
        }
        guard let index = dragIndex, shouldPlay, yourTurn, flights.isEmpty, index < players[0].hand.count else { return false }
        if !canPlay(players[0].hand[index]) {
            events.append(.reject)
            return false
        }
        play(0, index: index, wild: nil)
        return true
    }

    // MARK: Clock

    func step(dt raw: Double) {
        let dt = Swift.min(Swift.max(raw, 0), 1.0 / 30)
        if dt <= 0 { return }
        ambient += dt
        if stage == .finished { return }

        // Cards in the air.
        if !flights.isEmpty {
            var k = 0
            while k < flights.count {
                flights[k].age += dt
                if flights[k].age >= flights[k].length {
                    let flight = flights.remove(at: k)
                    land(flight)
                } else {
                    k += 1
                }
            }
        }

        // Lifts ease toward where each card wants to be.
        let n = players[0].hand.count
        while lifts.count < n { lifts.append(0) }
        while lifts.count > n { lifts.removeLast() }
        let ease = 1 - exp(-Self.liftRate * dt)
        for i in 0..<n {
            var goal = 0.0
            if yourTurn, pendingEight == nil {
                if selected == i { goal = 1 } else if canPlay(players[0].hand[i]) { goal = 0.22 }
            }
            lifts[i] += (goal - lifts[i]) * ease
        }

        let sheetGoal = pendingEight == nil ? 0.0 : 1.0
        sheet += (sheetGoal - sheet) * (1 - exp(-12 * dt))
        shownScore += (Double(score) - shownScore) * (1 - exp(-6 * dt))
        if abs(Double(score) - shownScore) < 0.6 { shownScore = Double(score) }

        if !notes.isEmpty {
            for k in notes.indices { notes[k].age += dt }
            notes.removeAll { $0.age >= WildEightsPainter.noteLength }
        }
        if praise != nil {
            praiseAge += dt
            if praiseAge >= WildEightsPainter.praiseLength { praise = nil }
        }

        switch stage {
        case .dealing:
            deal(dt)
        case .playing:
            time += dt
            if !flights.isEmpty || pendingEight != nil { break }
            if let wait = passWait {
                let left = wait - dt
                if left <= 0 {
                    passWait = nil
                    // Only passes with nothing left to draw count toward a stuck table.
                    passes = deck.isEmpty ? passes + 1 : 0
                    events.append(.pass)
                    endTurn()
                } else {
                    passWait = left
                }
                break
            }
            if turn != 0 {
                botWait -= dt
                if botWait <= 0 { botAct(turn) }
            } else if !drewThisTurn, !hasPlay {
                // Nothing to play and nothing to draw: the turn passes by itself.
                refill()
                if deck.isEmpty { passWait = Self.passDelay }
            }
        case .ending:
            endClock += dt
            bannerAge += dt
            dim += (0.6 - dim) * (1 - exp(-5 * dt))
            if endClock >= Self.endLength { stage = .finished }
        case .finished:
            break
        }
    }

    private func deal(_ dt: Double) {
        let total = Self.handSize * players.count
        dealClock += dt
        while dealClock >= Self.dealGap, dealt <= total {
            dealClock -= Self.dealGap
            if dealt < total {
                let who = dealt % players.count
                let card = deck.removeLast()
                if who == 0 {
                    players[0].hand.append(card)
                    lifts.append(0)
                    flights.append(Flight(card: card, from: .deck, to: .hand(players[0].hand.count - 1, players[0].hand.count),
                                          age: 0, length: Self.dealFlight, faceUp: false, player: nil, wild: nil))
                } else {
                    players[who].hand.append(card)
                    flights.append(Flight(card: card, from: .deck, to: .seat(who - 1),
                                          age: 0, length: Self.dealFlight, faceUp: false, player: nil, wild: nil))
                }
            } else {
                // The first card up is never an eight.
                if let k = deck.lastIndex(where: { !$0.isEight }), k != deck.count - 1 { deck.swapAt(k, deck.count - 1) }
                let card = deck.removeLast()
                flights.append(Flight(card: card, from: .deck, to: .pile, age: 0, length: Self.dealFlight, faceUp: true, player: nil, wild: nil))
            }
            dealt += 1
        }
    }

    // MARK: Rules

    private func play(_ who: Int, index: Int, wild: WildEightsSuit?) {
        let count = players[who].hand.count
        let card = players[who].hand.remove(at: index)
        if who == 0 {
            if index < lifts.count { lifts.remove(at: index) }
            selected = nil
        }
        let from: WildEightsSpot = who == 0 ? .hand(index, count) : .seat(who - 1)
        flights.append(Flight(card: card, from: from, to: .pile, age: 0, length: Self.playFlight, faceUp: true, player: who, wild: wild))
        if who == 0 {
            score += card.points
            notes.append(WildEightsNote(text: "+\(card.points)", age: 0, x: 0.63, y: 0.36))
            if card.isEight {
                praise = "Nice"
                praiseAge = 0
                events.append(.eight)
            } else {
                events.append(.place)
            }
        }
    }

    private func draw(_ who: Int) {
        refill()
        guard let card = deck.popLast() else { return }
        drewThisTurn = true
        players[who].hand.append(card)
        if who == 0 {
            lifts.append(0)
            let n = players[0].hand.count
            flights.append(Flight(card: card, from: .deck, to: .hand(n - 1, n), age: 0, length: Self.drawFlight, faceUp: false, player: 0, wild: nil))
            events.append(.draw)
        } else {
            flights.append(Flight(card: card, from: .deck, to: .seat(who - 1), age: 0, length: Self.drawFlight, faceUp: false, player: who, wild: nil))
        }
    }

    /// The deck is built again from the pile when it runs out, leaving the top card.
    private func refill() {
        guard deck.isEmpty, pile.count > 1 else { return }
        let keep = pile.removeLast()
        deck = pile
        pile = [keep]
        shuffle(&deck)
    }

    private func land(_ flight: Flight) {
        switch flight.to {
        case .pile:
            pile.append(flight.card)
            if stage == .dealing {
                stage = .playing
                turn = 0
                passes = 0
                return
            }
            guard let who = flight.player else { return }
            if flight.card.isEight {
                if who == 0 {
                    pendingEight = flight.card
                    sheetPressed = nil
                } else {
                    wildSuit = flight.wild ?? flight.card.suit
                }
            } else {
                wildSuit = nil
            }
            passes = 0
            if players[who].hand.isEmpty {
                finishRound(winner: who)
                return
            }
            if pendingEight == nil { endTurn() }
        case .hand, .seat:
            guard stage == .playing, let who = flight.player else { return }
            let playable = players[who].hand.contains { canPlay($0) }
            if who == 0 {
                if !playable { passWait = Self.passDelay }
            } else {
                botWait = playable ? rng.range(0.45, 0.7) : 0.3
                if !playable { passWait = 0.3 }
            }
        case .deck:
            break
        }
    }

    private func endTurn() {
        turn = (turn + 1) % players.count
        drewThisTurn = false
        selected = nil
        passWait = nil
        botWait = turn == 0 ? 0 : rng.range(0.75, 1.15)
        if passes >= players.count {
            finishRound(winner: nil)
        }
    }

    private func botAct(_ who: Int) {
        let cards = players[who].hand
        var best: Int?
        var bestValue = -1.0
        var eight: Int?
        for (i, card) in cards.enumerated() where canPlay(card) {
            if card.isEight {
                if eight == nil { eight = i }
                continue
            }
            // Keep the suit it holds most of, and shed heavy cards first.
            var held = 0
            for other in cards where other.suit == card.suit && !other.isEight { held += 1 }
            let value = Double(held) * 10 + Double(card.points) + rng.range(0, 3)
            if value > bestValue {
                bestValue = value
                best = i
            }
        }
        if let best {
            play(who, index: best, wild: nil)
            return
        }
        if let eight {
            play(who, index: eight, wild: Self.favouriteSuit(cards, skipping: eight, rng: &rng))
            return
        }
        if drewThisTurn {
            passWait = 0.2
            return
        }
        refill()
        if deck.isEmpty {
            passWait = 0.3
            return
        }
        draw(who)
    }

    /// The suit a hand has most of, apart from the eight being played.
    static func favouriteSuit(_ cards: [WildEightsCard], skipping: Int, rng: inout WildEightsRandom) -> WildEightsSuit {
        var counts = [0, 0, 0, 0]
        for (i, card) in cards.enumerated() where i != skipping && !card.isEight { counts[card.suit.rawValue] += 1 }
        var pick = rng.int(0...3)
        for k in 0..<4 where counts[k] > counts[pick] { pick = k }
        return WildEightsSuit(rawValue: pick) ?? .hearts
    }

    private func finishRound(winner who: Int?) {
        winner = who
        stage = .ending
        endClock = 0
        bannerAge = 0
        selected = nil
        pendingEight = nil
        dragIndex = nil
        if who == 0 {
            var sweep = 0
            for k in 1..<players.count {
                for card in players[k].hand { sweep += card.points }
            }
            score += sweep
            if sweep > 0 { notes.append(WildEightsNote(text: "+\(sweep)", age: 0, x: 0.5, y: 0.3)) }
            banner = "You went out"
            praise = "Great"
            praiseAge = 0
            events.append(.out)
        } else if let who {
            banner = "\(players[who].name) went out"
            events.append(.lost)
        } else {
            banner = "Nobody can play"
            events.append(.lost)
        }
    }

    // MARK: To the painter

    func frame() -> WildEightsFrame {
        var f = WildEightsFrame()
        f.time = ambient
        f.score = Int(shownScore.rounded())
        var seats: [WildEightsSeat] = []
        seats.reserveCapacity(3)
        for k in 1..<players.count {
            seats.append(WildEightsSeat(name: players[k].name, count: players[k].hand.count,
                                        active: stage == .playing && turn == k,
                                        color: WildEightsPalette.seats[(k - 1) % WildEightsPalette.seats.count]))
        }
        f.seats = seats
        f.pile = pile
        f.deckCount = deck.count
        f.wildSuit = wildSuit
        f.pill = pill
        f.pillHot = yourTurn && pendingEight == nil
        let n = players[0].hand.count
        var hand: [WildEightsHandCard] = []
        hand.reserveCapacity(n)
        for (i, card) in players[0].hand.enumerated() {
            var slot = WildEightsHandCard(card: card, lift: i < lifts.count ? lifts[i] : 0,
                                          playable: canPlay(card), hidden: false)
            if dragIndex == i {
                slot.dragX = dragX
                slot.dragY = dragY
            }
            hand.append(slot)
        }
        var inFlight: [WildEightsFlight] = []
        inFlight.reserveCapacity(flights.count)
        for flight in flights {
            if case .hand(let i, _) = flight.to, i < hand.count { hand[i].hidden = true }
            inFlight.append(WildEightsFlight(card: flight.card, from: flight.from, to: flight.to,
                                             progress: WildEightsMath.clamp(flight.age / flight.length), faceUp: flight.faceUp))
        }
        f.hand = hand
        f.flights = inFlight
        f.sheet = sheet
        f.sheetCard = pendingEight
        f.sheetPressed = sheetPressed
        f.notes = notes
        f.praise = praise
        f.praiseAge = praiseAge
        f.dim = dim
        f.banner = banner
        f.bannerAge = bannerAge
        return f
    }
}

// MARK: - Drawing

/// Paints the model as it is right now.
struct WildEightsCanvas: View {
    let model: WildEightsModel
    /// A new number every frame. The model is a class, so this is what makes SwiftUI repaint.
    var frame = 0

    var body: some View {
        Canvas(opaque: true, colorMode: .nonLinear, rendersAsynchronously: false) { context, size in
            if size.width <= 8 || size.height <= 8 { return }
            WildEightsPainter(size: size).draw(model.frame(), &context)
        }
    }
}

// MARK: - Scripted player

/// Plays the round for recordings while GameDemo.autopilot is on.
///
/// It reads the model and makes the same calls a finger makes: lift a card, tap it again, tap the
/// deck, pick a suit. It plays well with the odd second-best card, and once GameDemo.loseAfter has
/// passed it draws when it could play and sheds its cheapest cards, so the others go out first.
struct WildEightsPilot {
    private var rng: WildEightsRandom
    private var nextAt = 0.0
    /// True once the suit picker has been seen up, so the pick comes a moment after it opens.
    private var sawSheet = false

    init(seed: UInt64) {
        rng = WildEightsRandom(seed: seed ^ 0x7069_6C6F_7421, salt: WildEightsRandom.round)
    }

    /// Call once per step, after the model has moved.
    mutating func play(_ model: WildEightsModel) {
        guard model.yourTurn, model.flights.isEmpty else { return }
        if model.time < nextAt { return }
        let now = model.time
        let hand = model.hand

        if let eight = model.pendingEight {
            if !sawSheet {
                if model.sheet < 0.9 { return }
                sawSheet = true
                nextAt = now + rng.range(0.6, 0.9)
                return
            }
            sawSheet = false
            let wanted: WildEightsSuit
            if rng.chance(0.2) {
                wanted = WildEightsSuit(rawValue: rng.int(0...3)) ?? .hearts
            } else {
                var counts = [0, 0, 0, 0]
                for card in hand where !card.isEight { counts[card.suit.rawValue] += 1 }
                var pick = eight.suit.rawValue
                for k in 0..<4 where counts[k] > counts[pick] { pick = k }
                wanted = WildEightsSuit(rawValue: pick) ?? .hearts
            }
            model.pickSuit(wanted)
            nextAt = now + rng.range(0.4, 0.6)
            return
        }

        if let selected = model.selected {
            model.tapHand(selected)
            nextAt = now + rng.range(0.5, 0.8)
            return
        }

        let losing = GameDemo.loseAfter.map { now >= $0 } ?? false
        // While a loss is planned it never goes out: a draw first keeps the hand at two or more.
        let holdBack = GameDemo.loseAfter != nil && hand.count <= 2
        if (losing || holdBack), !model.drewThisTurn, model.hasPlay {
            model.tapDeck()
            nextAt = now + rng.range(0.6, 0.9)
            return
        }

        var legal: [Int] = []
        for (i, card) in hand.enumerated() where model.canPlay(card) { legal.append(i) }
        if legal.isEmpty {
            if !model.drewThisTurn { model.tapDeck() }
            nextAt = now + rng.range(0.5, 0.8)
            return
        }

        var choice = legal[0]
        if losing {
            // The cheapest card goes, and eights stay in the hand.
            var cheapest = 1000
            for i in legal {
                let cost = hand[i].isEight ? 500 : hand[i].points
                if cost < cheapest {
                    cheapest = cost
                    choice = i
                }
            }
        } else if rng.chance(0.2) {
            choice = legal[rng.int(0...(legal.count - 1))]
        } else {
            var bestValue = -1.0
            for i in legal {
                let card = hand[i]
                var held = 0
                for other in hand where other.suit == card.suit && !other.isEight { held += 1 }
                // An eight is kept for when nothing else fits, unless the hand is nearly done.
                let value: Double = card.isEight ? (hand.count <= 2 ? 100.0 : -5.0) : Double(held) * 10 + Double(card.points)
                if value > bestValue {
                    bestValue = value
                    choice = i
                }
            }
        }
        model.tapHand(choice)
        nextAt = now + rng.range(0.35, 0.55)
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
    /// Made the first time it is needed, which is only when GameDemo.autopilot is on.
    private var pilot: WildEightsPilot?
    /// The touch in progress: where it started and the hand card under it, if any.
    private var touchStart = CGPoint.zero
    private var touchCard: Int?
    private var touchMoved = false
    private var touchSuit: WildEightsSuit?

    init(options: GameOptions) {
        model = WildEightsModel(options: options)
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
            if GameDemo.autopilot {
                if pilot == nil { pilot = WildEightsPilot(seed: seed) }
                pilot?.play(model)
            }
            settle(link)
        }
        frame &+= 1
        return frame
    }

    // MARK: Touches

    func touchBegan(at p: CGPoint, in size: CGSize, link: GameLink) {
        if link.paused || link.isFinished { return }
        touchStart = p
        touchMoved = false
        touchCard = nil
        touchSuit = nil
        let painter = WildEightsPainter(size: size)
        if model.pendingEight != nil {
            let top = painter.sheetTop(model.sheet)
            for suit in WildEightsSuit.allCases where painter.suitButtonRect(suit.rawValue, top: top).contains(p) {
                touchSuit = suit
                model.pressSuit(suit)
                GameHaptics.tap()
            }
            return
        }
        guard model.yourTurn else { return }
        if let index = painter.handIndex(at: p, lifts: model.lifts) {
            touchCard = index
        }
    }

    func touchMoved(to p: CGPoint, in size: CGSize, link: GameLink) {
        if link.paused { return }
        let dx = Double(p.x - touchStart.x)
        let dy = Double(p.y - touchStart.y)
        if touchSuit != nil {
            let painter = WildEightsPainter(size: size)
            let top = painter.sheetTop(model.sheet)
            let still = touchSuit.map { painter.suitButtonRect($0.rawValue, top: top).contains(p) } ?? false
            model.pressSuit(still ? touchSuit : nil)
            return
        }
        guard let card = touchCard else { return }
        if !touchMoved, dx * dx + dy * dy < 100 { return }
        touchMoved = true
        model.drag(card, dx: dx, dy: dy)
    }

    func touchEnded(at p: CGPoint, in size: CGSize, cancelled: Bool, link: GameLink) {
        defer {
            touchCard = nil
            touchSuit = nil
            touchMoved = false
        }
        if link.paused || link.isFinished { return }
        let painter = WildEightsPainter(size: size)
        if let suit = touchSuit {
            model.pressSuit(nil)
            let top = painter.sheetTop(model.sheet)
            if !cancelled, painter.suitButtonRect(suit.rawValue, top: top).contains(p) { model.pickSuit(suit) }
            settle(link)
            return
        }
        if model.pendingEight != nil { return }
        if let card = touchCard {
            if touchMoved {
                // Let go well above the hand: the card goes to the pile.
                let above = Double(p.y) < painter.handBase - painter.handH - 50 * painter.u
                model.dropDrag(play: !cancelled && above)
            } else if !cancelled {
                model.tapHand(card)
            }
            settle(link)
            return
        }
        if cancelled || touchMoved { return }
        if painter.deckRect.contains(p) {
            model.tapDeck()
        } else {
            // A tap on the table puts a lifted card back down.
            model.putDown()
        }
        settle(link)
    }

    /// Plays the haptics the model owes and reports the round once it is over.
    private func settle(_ link: GameLink) {
        for event in model.takeEvents() {
            switch event {
            case .lift, .draw, .pass: GameHaptics.tap()
            case .place: GameHaptics.thud()
            case .eight: GameHaptics.success()
            case .reject: GameHaptics.thud()
            case .out:
                GameHaptics.heavy()
                GameHaptics.success()
            case .lost: GameHaptics.fail()
            }
        }
        if model.stage == .finished, !reported {
            reported = true
            let result = model.result
            DispatchQueue.main.async { link.finish(result) }
        }
    }
}

// MARK: - Touches

#if canImport(UIKit) && !os(macOS)
/// Reports a finger the moment it lands, as it moves and when it lifts, so a card can be tapped or dragged.
private struct WildEightsTouchPad: UIViewRepresentable {
    var began: (CGPoint, CGSize) -> Void
    var moved: (CGPoint, CGSize) -> Void
    var ended: (CGPoint, CGSize, Bool) -> Void

    func makeUIView(context: Context) -> WildEightsTouchView {
        let view = WildEightsTouchView()
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = false
        view.began = began
        view.moved = moved
        view.ended = ended
        return view
    }

    func updateUIView(_ view: WildEightsTouchView, context: Context) {
        view.began = began
        view.moved = moved
        view.ended = ended
    }
}

final class WildEightsTouchView: UIView {
    var began: ((CGPoint, CGSize) -> Void)?
    var moved: ((CGPoint, CGSize) -> Void)?
    var ended: ((CGPoint, CGSize, Bool) -> Void)?
    private var tracked: UITouch?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard tracked == nil, let touch = touches.first else { return }
        tracked = touch
        began?(touch.location(in: self), bounds.size)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = tracked, touches.contains(touch) else { return }
        moved?(touch.location(in: self), bounds.size)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = tracked, touches.contains(touch) else { return }
        tracked = nil
        ended?(touch.location(in: self), bounds.size, false)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = tracked, touches.contains(touch) else { return }
        tracked = nil
        ended?(touch.location(in: self), bounds.size, true)
    }
}
#else
private struct WildEightsTouchPad: View {
    var began: (CGPoint, CGSize) -> Void
    var moved: (CGPoint, CGSize) -> Void
    var ended: (CGPoint, CGSize, Bool) -> Void
    @State private var isDown = false

    var body: some View {
        GeometryReader { geo in
            Color.clear
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isDown {
                            isDown = true
                            began(value.startLocation, geo.size)
                        }
                        moved(value.location, geo.size)
                    }
                    .onEnded { value in
                        isDown = false
                        ended(value.location, geo.size, false)
                    })
        }
    }
}
#endif

public struct WildEightsGame: View {
    private let options: GameOptions
    private let link: GameLink

    public init(options: GameOptions, link: GameLink) {
        self.options = options
        self.link = link
    }

    public var body: some View {
        // A new link is a new round, so the round's state lives and dies with the link.
        WildEightsRound(options: options, link: link)
            .id(ObjectIdentifier(link))
    }
}

private struct WildEightsRound: View {
    @ObservedObject var link: GameLink
    @StateObject private var runner: WildEightsRunner

    init(options: GameOptions, link: GameLink) {
        self.link = link
        _runner = StateObject(wrappedValue: WildEightsRunner(options: options))
    }

    var body: some View {
        ZStack {
            TimelineView(.animation(minimumInterval: nil, paused: link.paused)) { timeline in
                WildEightsCanvas(model: runner.model, frame: runner.advance(to: timeline.date, link: link))
            }
            WildEightsTouchPad(
                began: { p, size in runner.touchBegan(at: p, in: size, link: link) },
                moved: { p, size in runner.touchMoved(to: p, in: size, link: link) },
                ended: { p, size, cancelled in runner.touchEnded(at: p, in: size, cancelled: cancelled, link: link) })
        }
        .ignoresSafeArea()
        .accessibilityElement()
        .accessibilityLabel("Wild Eights. Tap a card to lift it, tap again to play it. Tap the deck to draw.")
        .accessibilityAddTraits(.allowsDirectInteraction)
    }
}
