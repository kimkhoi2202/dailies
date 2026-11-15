import SwiftUI

// Block Party, playable.
//
// BlockPartyModel   the rules of a round in plain Swift: step(dt:), press, move, release.
// BlockPartyPilot   the scripted player. It only runs while GameDemo.autopilot is on.
// BlockPartyRunner  keeps the clock, passes touches on, fires haptics, reports the result.
// BlockPartyGame    the view the app shows.
//
// The pieces come from the round's seed alone, so friends on the same seed get the same pieces
// in the same order whatever they do with them.

// MARK: - Model

struct BlockPartyMove {
    let slot: Int
    let col: Int
    let row: Int
}

final class BlockPartyModel {
    enum Stage { case ready, playing, ending, finished }

    /// What the last input or step deserves as a haptic. A stronger one replaces a weaker one.
    enum Feedback: Int { case none, back, pick, place, clear, big, fail }

    struct Friend {
        let name: String
        var score: Int
        var shown: Double
        /// Where this friend's round ends today.
        let final: Int
        var nextAt: Double
        var out: Bool
    }

    struct Particle {
        var x = 0.0
        var y = 0.0
        var vx = 0.0
        var vy = 0.0
        var age = 9.0
        var life = 1.0
        var size = 1.0
        var color: UInt8 = 1
    }

    struct Floater {
        var x = 0.0
        var y = 0.0
        var age = 9.0
        var text = ""
        var big = false
    }

    static let size = 8
    static let endLength = 1.9
    static let comboLength = 1.2
    static let clearLength = 0.36
    static let backLength = 0.16
    static let floatLength = 0.9

    let solo: Bool
    let bestScore: Int
    private var rng: BlockPartyRandom
    private var fx: BlockPartyRandom

    private(set) var stage = Stage.ready
    private(set) var grid = [UInt8](repeating: 0, count: 64)
    private(set) var popAge = [Double](repeating: 9, count: 64)
    private(set) var clearAge = [Double](repeating: 9, count: 64)
    private(set) var clearColor = [UInt8](repeating: 0, count: 64)
    private(set) var tray: [BlockPartyPiece?] = [nil, nil, nil]
    private(set) var fits = [false, false, false]
    private(set) var dealAge = 0.0

    private(set) var dragSlot = -1
    private(set) var dragX = 0.0
    private(set) var dragY = 0.0
    private(set) var dragAge = 0.0
    private(set) var ghostCol = -1
    private(set) var ghostRow = -1
    private(set) var hotRows = [Bool](repeating: false, count: 8)
    private(set) var hotCols = [Bool](repeating: false, count: 8)

    private(set) var backSlot = -1
    private(set) var backX = 0.0
    private(set) var backY = 0.0
    private(set) var backAge = 9.0

    private(set) var score = 0
    private(set) var shown = 0.0
    private(set) var scorePop = 9.0
    private(set) var lines = 0
    private(set) var streak = 0
    private var quiet = 0
    private(set) var bestCombo = 0
    private(set) var combo = 0
    private(set) var comboAge = 9.0
    private(set) var praise: String?
    private(set) var shake = 0.0

    private(set) var particles = [Particle](repeating: Particle(), count: 240)
    private var nextParticle = 0
    private(set) var floaters = [Floater](repeating: Floater(), count: 5)
    private var nextFloater = 0
    private(set) var friends: [Friend] = []

    /// Round clock: from the first touch to the end.
    private(set) var time = 0.0
    /// Scenery clock: runs whenever the game is not paused.
    private(set) var ambient = 0.0
    private(set) var endClock = 0.0
    private(set) var layout = BlockPartyLayout(size: CGSize(width: 402, height: 874))

    private var feedback = Feedback.none

    init(options: GameOptions) {
        solo = options.solo
        bestScore = Swift.max(0, options.bestScore)
        rng = BlockPartyRandom(seed: options.seed, salt: BlockPartyRandom.pieces)
        fx = BlockPartyRandom(seed: options.seed, salt: BlockPartyRandom.effects)

        // A few blocks already on the board, low down, so the first moves have something to finish.
        for _ in 0..<9 {
            let r = rng.int(4...7)
            let c = rng.int(0...7)
            let filled = (0..<8).filter { grid[r * 8 + $0] != 0 }.count
            if filled >= 6 { continue }
            grid[r * 8 + c] = UInt8(rng.int(1...7))
        }

        if !options.solo {
            let base = Double(Swift.max(1400, bestScore))
            for name in options.friendNames.filter({ !$0.isEmpty }).prefix(2) {
                let target = Int((base * fx.range(0.5, 1.3) / 10).rounded()) * 10
                friends.append(Friend(name: name, score: 0, shown: 0, final: target, nextAt: fx.range(1.2, 2.6), out: false))
            }
        }
        deal()
    }

    // MARK: Reading

    var dragPiece: BlockPartyPiece? { dragSlot >= 0 ? tray[dragSlot] : nil }

    var result: GameResult {
        var line: String?
        if lines > 0 {
            line = lines == 1 ? "1 line cleared" : "\(lines) lines cleared"
            if bestCombo >= 2 { line = (line ?? "") + ", best combo x\(bestCombo)" }
        }
        guard !friends.isEmpty else { return GameResult(score: score, unit: "points", detail: line) }
        let ahead = friends.filter { $0.final > score }.count
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

    func setSize(_ size: CGSize) {
        if abs(layout.W - Double(size.width)) > 0.5 || abs(layout.H - Double(size.height)) > 0.5 {
            layout = BlockPartyLayout(size: size)
        }
    }

    // MARK: Board rules

    static func fits(_ g: [UInt8], _ shape: BlockPartyShape, _ col: Int, _ row: Int) -> Bool {
        if col < 0 || row < 0 || col + shape.w > size || row + shape.h > size { return false }
        for k in 0..<shape.count where g[(row + shape.rows[k]) * size + col + shape.cols[k]] != 0 {
            return false
        }
        return true
    }

    static func canFit(_ g: [UInt8], _ shape: BlockPartyShape) -> Bool {
        for row in 0...(size - shape.h) {
            for col in 0...(size - shape.w) where fits(g, shape, col, row) { return true }
        }
        return false
    }

    /// Clears every full row and column. Returns how many lines went.
    static func clearFull(_ g: inout [UInt8]) -> Int {
        var rows = [Bool](repeating: false, count: size)
        var cols = [Bool](repeating: false, count: size)
        markFull(g, &rows, &cols)
        var count = 0
        for r in 0..<size where rows[r] { count += 1 }
        for c in 0..<size where cols[c] { count += 1 }
        if count == 0 { return 0 }
        for i in 0..<(size * size) where rows[i / size] || cols[i % size] { g[i] = 0 }
        return count
    }

    static func markFull(_ g: [UInt8], _ rows: inout [Bool], _ cols: inout [Bool]) {
        for r in 0..<size {
            var full = true
            for c in 0..<size where g[r * size + c] == 0 { full = false; break }
            rows[r] = full
        }
        for c in 0..<size {
            var full = true
            for r in 0..<size where g[r * size + c] == 0 { full = false; break }
            cols[c] = full
        }
    }

    private func drawShape() -> Int {
        var pick = rng.int(0...(BlockPartyShape.totalWeight - 1))
        for (k, shape) in BlockPartyShape.all.enumerated() {
            if pick < shape.weight { return k }
            pick -= shape.weight
        }
        return 0
    }

    private func deal() {
        var used: [UInt8] = []
        for k in 0..<3 {
            let shape = drawShape()
            var color = UInt8(rng.int(1...7))
            while used.contains(color) { color = color % 7 + 1 }
            used.append(color)
            tray[k] = BlockPartyPiece(shape: shape, color: color)
        }
        dealAge = 0
        refreshFits()
    }

    private func refreshFits() {
        for k in 0..<3 {
            if let piece = tray[k] {
                fits[k] = Self.canFit(grid, BlockPartyShape.all[piece.shape])
            } else {
                fits[k] = false
            }
        }
    }

    // MARK: Input

    /// A finger lands. On a piece in the tray it picks the piece up; the first pick starts the round.
    func press(x: Double, y: Double) {
        guard stage == .ready || stage == .playing, dragSlot < 0 else { return }
        guard y > layout.trayTop - 8 * layout.u else { return }
        let slot = Swift.min(2, Swift.max(0, Int(x / (layout.W / 3))))
        guard tray[slot] != nil else { return }
        if backSlot == slot { backSlot = -1 }
        stage = .playing
        dragSlot = slot
        dragAge = 0
        dragX = x
        dragY = y
        updateGhost()
        owe(.pick)
    }

    func move(x: Double, y: Double) {
        guard dragSlot >= 0 else { return }
        dragX = x
        dragY = y
        updateGhost()
    }

    /// The finger lifts: the piece lands on its ghost, or flies back to the tray.
    func release() {
        guard dragSlot >= 0 else { return }
        let slot = dragSlot
        let col = ghostCol
        let row = ghostRow
        dragSlot = -1
        clearGhost()
        if col >= 0, stage == .playing {
            place(slot, col, row)
        } else {
            sendBack(slot)
        }
    }

    /// Lets go of a held piece without placing it, as when the app pauses the game.
    func cancelDrag() {
        guard dragSlot >= 0 else { return }
        let slot = dragSlot
        dragSlot = -1
        clearGhost()
        sendBack(slot)
    }

    private func sendBack(_ slot: Int) {
        guard let piece = tray[slot] else { return }
        let shape = BlockPartyShape.all[piece.shape]
        let at = layout.dragCenter(x: dragX, y: dragY, h: shape.h)
        backSlot = slot
        backX = Double(at.x)
        backY = Double(at.y)
        backAge = 0
        owe(.back)
    }

    private func clearGhost() {
        ghostCol = -1
        ghostRow = -1
        for k in 0..<Self.size {
            hotRows[k] = false
            hotCols[k] = false
        }
    }

    private func updateGhost() {
        guard let piece = dragPiece else { return }
        let shape = BlockPartyShape.all[piece.shape]
        let center = layout.dragCenter(x: dragX, y: dragY, h: shape.h)
        let ox = Double(center.x) - Double(shape.w) * layout.cell / 2
        let oy = Double(center.y) - Double(shape.h) * layout.cell / 2
        let col = Int(((ox - layout.boardX) / layout.cell).rounded())
        let row = Int(((oy - layout.boardY) / layout.cell).rounded())
        guard Self.fits(grid, shape, col, row) else {
            if ghostCol >= 0 { clearGhost() }
            return
        }
        if col == ghostCol && row == ghostRow { return }
        ghostCol = col
        ghostRow = row
        for r in 0..<Self.size {
            var full = true
            for c in 0..<Self.size where !filledOrCovered(c, r, shape) { full = false; break }
            hotRows[r] = full
        }
        for c in 0..<Self.size {
            var full = true
            for r in 0..<Self.size where !filledOrCovered(c, r, shape) { full = false; break }
            hotCols[c] = full
        }
    }

    private func filledOrCovered(_ c: Int, _ r: Int, _ shape: BlockPartyShape) -> Bool {
        if grid[r * Self.size + c] != 0 { return true }
        let dc = c - ghostCol
        let dr = r - ghostRow
        if dc < 0 || dr < 0 || dc >= shape.w || dr >= shape.h { return false }
        for k in 0..<shape.count where shape.cols[k] == dc && shape.rows[k] == dr { return true }
        return false
    }

    // MARK: Placing

    private func place(_ slot: Int, _ col: Int, _ row: Int) {
        guard let piece = tray[slot] else { return }
        let shape = BlockPartyShape.all[piece.shape]
        for k in 0..<shape.count {
            let i = (row + shape.rows[k]) * Self.size + col + shape.cols[k]
            grid[i] = piece.color
            popAge[i] = 0
        }
        tray[slot] = nil

        let cell = layout.cell
        let cx = layout.boardX + (Double(col) + Double(shape.w) / 2) * cell
        let cy = layout.boardY + (Double(row) + Double(shape.h) / 2) * cell
        var gained = 10 * shape.count

        var rows = [Bool](repeating: false, count: Self.size)
        var cols = [Bool](repeating: false, count: Self.size)
        Self.markFull(grid, &rows, &cols)
        var cleared = 0
        for k in 0..<Self.size {
            if rows[k] { cleared += 1 }
            if cols[k] { cleared += 1 }
        }

        if cleared > 0 {
            streak += 1
            quiet = 0
            combo = cleared + streak - 1
            bestCombo = Swift.max(bestCombo, combo)
            lines += cleared
            gained += 100 * cleared * combo
            let burst = cleared >= 2 ? 5 : 3
            for i in 0..<(Self.size * Self.size) where rows[i / Self.size] || cols[i % Self.size] {
                let c = i % Self.size
                let r = i / Self.size
                let x = layout.boardX + (Double(c) + 0.5) * cell
                let y = layout.boardY + (Double(r) + 0.5) * cell
                let far = hypot(x - cx, y - cy) / cell
                clearColor[i] = grid[i]
                clearAge[i] = -0.03 * far
                spawn(x: x, y: y, color: grid[i], count: burst)
                grid[i] = 0
            }
            praise = nil
            if cleared >= 3 {
                praise = "Perfect"
            } else if cleared == 2 {
                praise = "Great"
            } else if streak >= 3 {
                praise = "Nice"
            }
            if !grid.contains(where: { $0 != 0 }) {
                gained += 300
                praise = "Board clear"
            }
            if combo >= 2 || praise != nil { comboAge = 0 }
            shake = Swift.min(1, 0.4 * Double(cleared))
            owe(cleared >= 2 ? .big : .clear)
        } else {
            quiet += 1
            if quiet >= 3 { streak = 0 }
            owe(.place)
        }

        score += gained
        scorePop = 0
        float(x: cx, y: cy - cell * 0.3, text: "+" + BlockPartyFormat.grouped(gained), big: cleared > 0)

        if tray[0] == nil && tray[1] == nil && tray[2] == nil { deal() }
        refreshFits()
        var anyFits = false
        for k in 0..<3 where tray[k] != nil && fits[k] { anyFits = true }
        if !anyFits {
            stage = .ending
            endClock = 0
            owe(.fail)
        }
    }

    private func spawn(x: Double, y: Double, color: UInt8, count: Int) {
        let u = layout.u
        for _ in 0..<count {
            let turn = fx.range(0, 2 * .pi)
            let speed = fx.range(110, 330) * u
            var p = Particle()
            p.x = x + fx.range(-0.3, 0.3) * layout.cell
            p.y = y + fx.range(-0.3, 0.3) * layout.cell
            p.vx = cos(turn) * speed
            p.vy = sin(turn) * speed - 180 * u
            p.age = 0
            p.life = fx.range(0.45, 0.85)
            p.size = fx.range(5, 10) * u
            p.color = color
            particles[nextParticle] = p
            nextParticle = (nextParticle + 1) % particles.count
        }
    }

    private func float(x: Double, y: Double, text: String, big: Bool) {
        floaters[nextFloater] = Floater(x: x, y: y, age: 0, text: text, big: big)
        nextFloater = (nextFloater + 1) % floaters.count
    }

    // MARK: Clock

    func step(dt raw: Double) {
        let dt = Swift.min(Swift.max(raw, 0), 1.0 / 30)
        if dt <= 0 { return }
        ambient += dt
        for i in 0..<64 {
            if popAge[i] < 9 { popAge[i] += dt }
            if clearAge[i] < 9 { clearAge[i] += dt }
        }
        let gravity = 900 * layout.u
        let drag = exp(-1.6 * dt)
        for k in particles.indices where particles[k].age < particles[k].life {
            particles[k].age += dt
            particles[k].vy += gravity * dt
            particles[k].vx *= drag
            particles[k].x += particles[k].vx * dt
            particles[k].y += particles[k].vy * dt
        }
        for k in floaters.indices where floaters[k].age < 9 { floaters[k].age += dt }
        if dealAge < 9 { dealAge += dt }
        if comboAge < 9 { comboAge += dt }
        if scorePop < 9 { scorePop += dt }
        if dragSlot >= 0 { dragAge += dt }
        if backSlot >= 0 {
            backAge += dt
            if backAge >= Self.backLength { backSlot = -1 }
        }
        shake = Swift.max(0, shake - dt * 2.6)
        let ease = 1 - exp(-11 * dt)
        shown += (Double(score) - shown) * ease
        if abs(Double(score) - shown) < 0.5 { shown = Double(score) }
        for k in friends.indices {
            friends[k].shown += (Double(friends[k].score) - friends[k].shown) * ease
        }

        switch stage {
        case .ready:
            break
        case .playing:
            time += dt
            playFriends()
        case .ending:
            endClock += dt
            playFriends()
            if endClock >= Self.endLength { stage = .finished }
        case .finished:
            break
        }
    }

    /// Friends play the same pieces on their own phones. Until there is a server the game plays them.
    private func playFriends() {
        for k in friends.indices where !friends[k].out && time >= friends[k].nextAt {
            var add = 10 * fx.int(2...6)
            if fx.next() < 0.38 { add += 100 * fx.int(1...2) * fx.int(1...2) }
            friends[k].score = Swift.min(friends[k].final, friends[k].score + add)
            friends[k].nextAt += fx.range(1.3, 2.7)
            if friends[k].score >= friends[k].final { friends[k].out = true }
        }
    }

    // MARK: Choosing a move

    /// The move the scripted player likes best. worst: the move that helps least, to lose on purpose.
    func plan(worst: Bool) -> BlockPartyMove? {
        var best: BlockPartyMove?
        var bestValue = -Double.infinity
        var scratch = grid
        for slot in 0..<3 {
            guard let piece = tray[slot] else { continue }
            let shape = BlockPartyShape.all[piece.shape]
            for row in 0...(Self.size - shape.h) {
                for col in 0...(Self.size - shape.w) where Self.fits(grid, shape, col, row) {
                    for i in 0..<64 { scratch[i] = grid[i] }
                    for k in 0..<shape.count { scratch[(row + shape.rows[k]) * Self.size + col + shape.cols[k]] = 1 }
                    let contact = Self.contact(scratch, shape, col, row)
                    let cleared = Self.clearFull(&scratch)
                    let holes = Self.holes(scratch)
                    var value: Double
                    if worst {
                        value = -Double(cleared) * 1000 - Double(contact) * 3 + Double(holes) * 12 + Double(row) * 0.1
                    } else {
                        value = Double(cleared) * 140 + Double(contact) * 3 - Double(holes) * 30 + Double(Self.room(scratch)) * 1.5
                        for other in 0..<3 where other != slot {
                            if let o = tray[other], !Self.canFit(scratch, BlockPartyShape.all[o.shape]) { value -= 500 }
                        }
                    }
                    if value > bestValue {
                        bestValue = value
                        best = BlockPartyMove(slot: slot, col: col, row: row)
                    }
                }
            }
        }
        return best
    }

    private static func contact(_ g: [UInt8], _ shape: BlockPartyShape, _ col: Int, _ row: Int) -> Int {
        var touching = 0
        for k in 0..<shape.count {
            let c = col + shape.cols[k]
            let r = row + shape.rows[k]
            touching += (c == 0 || g[r * size + c - 1] != 0) ? 1 : 0
            touching += (c == size - 1 || g[r * size + c + 1] != 0) ? 1 : 0
            touching += (r == 0 || g[(r - 1) * size + c] != 0) ? 1 : 0
            touching += (r == size - 1 || g[(r + 1) * size + c] != 0) ? 1 : 0
        }
        return touching
    }

    private static func holes(_ g: [UInt8]) -> Int {
        var count = 0
        for r in 0..<size {
            for c in 0..<size where g[r * size + c] == 0 {
                let left = c == 0 || g[r * size + c - 1] != 0
                let right = c == size - 1 || g[r * size + c + 1] != 0
                let up = r == 0 || g[(r - 1) * size + c] != 0
                let down = r == size - 1 || g[(r + 1) * size + c] != 0
                if left && right && up && down { count += 1 }
            }
        }
        return count
    }

    /// How many places a 3 x 3 square still fits.
    private static func room(_ g: [UInt8]) -> Int {
        var count = 0
        for row in 0...(size - 3) {
            for col in 0...(size - 3) {
                var free = true
                for k in 0..<9 where g[(row + k / 3) * size + col + k % 3] != 0 { free = false; break }
                if free { count += 1 }
            }
        }
        return count
    }
}

// MARK: - The scripted clip for covers and the Videos feed

extension BlockPartyModel {
    private static let clipBoard = [
        "1...6...",
        "11..6.33",
        "...66.3.",
        "22.36..5",
        "4..34.55",
        "14...277",
        "4413322.",
        "44133.27"
    ]

    /// A short round at a moment from 0 to 1: a three-block piece is dragged in, hovers with two
    /// lines lit, lands and clears both.
    static func clip(phase: Double, size: CGSize) -> BlockPartyModel {
        let model = BlockPartyModel(options: GameOptions(solo: false, playerName: "mira", friendNames: ["kaz", "noor.runs"],
                                                         bestScore: 2480, seed: 7))
        model.setSize(size)
        model.stageClip()
        let p = phase.isFinite ? BlockPartyMath.clamp(phase) : 0
        let end = 3.4 * p
        let layout = model.layout
        let from = CGPoint(x: layout.slotX(1), y: layout.trayY)
        let to = layout.finger(col: 2, row: 5, w: 3, h: 1)
        var clock = 0.0
        var pressed = false
        var released = false
        while clock < end {
            let dt = Swift.min(1.0 / 60, end - clock)
            clock += dt
            model.step(dt: dt)
            if !pressed && clock >= 0.2 {
                pressed = true
                model.press(x: Double(from.x), y: Double(from.y))
            }
            if pressed && !released {
                let t = BlockPartyMath.smooth(0.25, 1.3, clock)
                let x = BlockPartyMath.lerp(Double(from.x), Double(to.x), t)
                let y = BlockPartyMath.lerp(Double(from.y), Double(to.y), t) - 40 * layout.u * sin(.pi * t)
                model.move(x: x, y: y)
                if clock >= 1.75 {
                    released = true
                    model.release()
                }
            }
        }
        return model
    }

    private func stageClip() {
        for (r, line) in Self.clipBoard.enumerated() {
            for (c, ch) in line.enumerated() {
                grid[r * Self.size + c] = UInt8(ch.wholeNumberValue ?? 0)
            }
        }
        tray = [BlockPartyPiece(shape: 9, color: 2), BlockPartyPiece(shape: 3, color: 6), BlockPartyPiece(shape: 25, color: 7)]
        refreshFits()
        dealAge = 9
        stage = .playing
        time = 60
        score = 1460
        shown = 1460
        streak = 1
        lines = 9
        for k in friends.indices {
            friends[k].score = k == 0 ? 1320 : 1710
            friends[k].shown = Double(friends[k].score)
            friends[k].nextAt = 99
        }
    }
}

// MARK: - Scripted player

/// Plays the round for recordings while GameDemo.autopilot is on. It picks a move, picks the piece
/// up, carries it to the board and lets go, all through the calls a finger uses.
struct BlockPartyPilot {
    static let readyHold = 0.9
    static let carry = 0.48

    private var rng: BlockPartyRandom
    private var plan: BlockPartyMove?
    private var wait = 0.0
    private var pause = 0.35
    private var carried = 0.0
    private var fromX = 0.0
    private var fromY = 0.0
    private var toX = 0.0
    private var toY = 0.0

    init(seed: UInt64) {
        rng = BlockPartyRandom(seed: seed, salt: BlockPartyRandom.pilot)
    }

    mutating func act(_ model: BlockPartyModel, dt: Double) {
        guard model.stage == .ready || model.stage == .playing else { return }
        if model.stage == .ready, model.ambient < Self.readyHold { return }
        let layout = model.layout

        if plan == nil {
            wait += dt
            if wait < pause { return }
            let losing = GameDemo.loseAfter.map { model.time >= $0 } ?? false
            guard let next = model.plan(worst: losing), let piece = model.tray[next.slot] else { return }
            let shape = BlockPartyShape.all[piece.shape]
            fromX = layout.slotX(next.slot)
            fromY = layout.trayY
            let target = layout.finger(col: next.col, row: next.row, w: shape.w, h: shape.h)
            toX = Double(target.x)
            toY = Double(target.y)
            carried = 0
            plan = next
            model.press(x: fromX, y: fromY)
            return
        }

        carried += dt
        let t = BlockPartyMath.smooth(0, Self.carry, carried)
        let arc = 30 * layout.u * sin(.pi * t)
        model.move(x: BlockPartyMath.lerp(fromX, toX, t), y: BlockPartyMath.lerp(fromY, toY, t) - arc)
        if carried >= Self.carry + 0.1 {
            model.release()
            plan = nil
            wait = 0
            pause = rng.range(0.12, 0.4)
        }
    }
}

// MARK: - Game view

/// Holds the round between frames. Nothing is published: the timeline repaints every frame anyway.
final class BlockPartyRunner: ObservableObject {
    let model: BlockPartyModel
    private let seed: UInt64
    private var lastDate: Date?
    private var frame = 0
    private var reported = false
    private var touching = false
    /// Made the first time it is needed, which is only when GameDemo.autopilot is on.
    private var pilot: BlockPartyPilot?

    init(options: GameOptions) {
        model = BlockPartyModel(options: options)
        seed = options.seed
    }

    /// Brings the model up to the given date. Returns a number that changes when there is a new frame to paint.
    func advance(to date: Date, size: CGSize, link: GameLink) -> Int {
        model.setSize(size)
        if link.paused {
            lastDate = nil
            if touching || model.dragSlot >= 0 {
                touching = false
                model.cancelDrag()
            }
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
                if pilot == nil { pilot = BlockPartyPilot(seed: seed) }
                pilot?.act(model, dt: dt)
            }
            settle(link)
        }
        frame &+= 1
        return frame
    }

    func touch(at point: CGPoint, link: GameLink) {
        if link.paused || link.isFinished || GameDemo.autopilot { return }
        if touching {
            model.move(x: Double(point.x), y: Double(point.y))
        } else {
            touching = true
            model.press(x: Double(point.x), y: Double(point.y))
            model.move(x: Double(point.x), y: Double(point.y))
        }
        settle(link)
    }

    func lift(link: GameLink) {
        if !touching { return }
        touching = false
        model.release()
        settle(link)
    }

    /// Plays the haptic the model owes and reports the round once it is over.
    private func settle(_ link: GameLink) {
        switch model.takeFeedback() {
        case .fail: GameHaptics.fail()
        case .big:
            GameHaptics.heavy()
            GameHaptics.success()
        case .clear: GameHaptics.thud()
        case .place, .pick, .back: GameHaptics.tap()
        case .none: break
        }
        if model.stage == .finished, !reported {
            reported = true
            let result = model.result
            DispatchQueue.main.async { link.finish(result) }
        }
    }
}

/// Paints the model as it is right now.
struct BlockPartyCanvas: View {
    let model: BlockPartyModel
    /// A new number every frame. The model is a class, so this is what makes SwiftUI repaint.
    var frame = 0

    var body: some View {
        Canvas(opaque: true, colorMode: .nonLinear, rendersAsynchronously: false) { context, size in
            if size.width <= 8 || size.height <= 8 { return }
            BlockPartyPainter(model: model, showHUD: true).draw(&context)
        }
    }
}

public struct BlockPartyGame: View {
    private let options: GameOptions
    private let link: GameLink

    public init(options: GameOptions, link: GameLink) {
        self.options = options
        self.link = link
    }

    public var body: some View {
        // A new link is a new round, so the round's state lives and dies with the link.
        BlockPartyRound(options: options, link: link)
            .id(ObjectIdentifier(link))
    }
}

private struct BlockPartyRound: View {
    @ObservedObject var link: GameLink
    @StateObject private var runner: BlockPartyRunner

    init(options: GameOptions, link: GameLink) {
        self.link = link
        _runner = StateObject(wrappedValue: BlockPartyRunner(options: options))
    }

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: nil, paused: link.paused)) { timeline in
                BlockPartyCanvas(model: runner.model, frame: runner.advance(to: timeline.date, size: geo.size, link: link))
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { value in runner.touch(at: value.location, link: link) }
                .onEnded { _ in runner.lift(link: link) }
        )
        .ignoresSafeArea()
        .accessibilityElement()
        .accessibilityLabel("Block Party. Drag a block onto the board.")
        .accessibilityAddTraits(.allowsDirectInteraction)
    }
}
