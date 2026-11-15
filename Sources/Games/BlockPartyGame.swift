import SwiftUI

// Block Party, playable.
//
// BlockPartyModel   the rules of a round in plain Swift: pick up, hover, drop, step(dt:).
// BlockPartyCanvas  paints one frame of the model with the clip's painter.
// BlockPartyPilot   the scripted player. It only runs while GameDemo.autopilot is on.
// BlockPartyRunner  keeps the clock, turns touches into model calls, fires haptics, reports the result.
// BlockPartyGame    the view the app shows.

// MARK: - Model

final class BlockPartyModel {
    enum Stage { case ready, playing, ending, finished }

    /// What the last step or input deserves as a haptic. A stronger one replaces a weaker one.
    enum Feedback: Int { case none, tap, placed, cleared, big, lost }

    static let endLength = 2.0
    static let noteLength = 1.3
    static let liftLength = 0.12
    static let returnLength = 0.2
    /// Placements without a clear before the combo drops back.
    static let comboGrace = 2

    let bestScore: Int
    private var rng: BlockPartyRandom

    private(set) var stage = Stage.ready
    /// 64 cells, row by row. 0 is empty, else a palette index.
    private(set) var grid: [Int] = Array(repeating: 0, count: 64)
    private(set) var placedAge: [Double] = Array(repeating: 9, count: 64)
    private(set) var flash: [Double] = Array(repeating: 9, count: 64)
    private(set) var tray: [BlockPartyShape?] = [nil, nil, nil]
    private(set) var trayAge: [Double] = [9, 9, 9]

    private(set) var score = 0
    /// The number on screen, which counts up to the score.
    private(set) var shownScore = 0.0
    private(set) var scoreAge = 9.0
    private(set) var placed = 0
    private(set) var linesCleared = 0
    private(set) var bestCombo = 0
    private var streak = 0
    private var sinceClear = 0

    private(set) var dragSlot: Int?
    private(set) var dragAge = 0.0
    private(set) var ghostCol = 0
    private(set) var ghostRow = 0
    private(set) var ghostValid = false
    private(set) var ghostLines: UInt16 = 0

    private(set) var returnShape: BlockPartyShape?
    private(set) var returnSlot = 0
    private(set) var returnAge = 9.0

    /// A ring of recent clears. Dead ones have an age past their life.
    private(set) var bursts: [BlockPartyBurst]
    private var nextBurst = 0
    private(set) var floats: [BlockPartyFloat]
    private var nextFloat = 0

    private(set) var note: String?
    private(set) var noteAge = 0.0
    private(set) var praise: String?
    private(set) var praiseAge = 0.0

    /// Round clock: from the first placement to the end.
    private(set) var time = 0.0
    /// Scenery clock: runs whenever the game is not paused.
    private(set) var ambient = 0.0
    private(set) var endClock = 0.0

    private var feedback = Feedback.none

    init(options: GameOptions) {
        bestScore = Swift.max(0, options.bestScore)
        rng = BlockPartyRandom(seed: options.seed, salt: BlockPartyRandom.round)
        bursts = Array(repeating: BlockPartyBurst(x: 0, y: 0, color: 1, age: 9), count: 72)
        floats = Array(repeating: BlockPartyFloat(text: "", x: 0, y: 0, color: 1, age: 9), count: 6)
        deal()
    }

    // MARK: Reading

    var dragShape: BlockPartyShape? {
        guard let slot = dragSlot else { return nil }
        return tray[slot]
    }

    var isOn: Bool { stage == .ready || stage == .playing }

    var result: GameResult {
        var line: String?
        if bestCombo >= 2 {
            line = "Best combo x\(bestCombo)"
        } else if linesCleared >= 1 {
            line = linesCleared == 1 ? "1 line cleared" : "\(linesCleared) lines cleared"
        }
        return GameResult(score: score, unit: "points", detail: line)
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

    /// True when the piece can sit with its top left corner at the cell.
    func fits(_ shape: BlockPartyShape, col: Int, row: Int) -> Bool {
        if col < 0 || row < 0 || col + shape.w > 8 || row + shape.h > 8 { return false }
        for c in shape.cells where grid[(row + c.y) * 8 + col + c.x] != 0 { return false }
        return true
    }

    /// True when any piece left in the tray fits somewhere.
    func anyFits() -> Bool {
        for slot in 0..<3 {
            guard let shape = tray[slot] else { continue }
            for row in 0...(8 - shape.h) {
                for col in 0...(8 - shape.w) where fits(shape, col: col, row: row) { return true }
            }
        }
        return false
    }

    /// Rows (bits 0...7) and columns (bits 8...15) that are full in the given grid.
    static func fullLines(_ cells: [Int]) -> UInt16 {
        var mask: UInt16 = 0
        for r in 0..<8 {
            var full = true
            for c in 0..<8 where cells[r * 8 + c] == 0 {
                full = false
                break
            }
            if full { mask |= UInt16(1 << r) }
        }
        for c in 0..<8 {
            var full = true
            for r in 0..<8 where cells[r * 8 + c] == 0 {
                full = false
                break
            }
            if full { mask |= UInt16(1 << (8 + c)) }
        }
        return mask
    }

    /// The lines a piece would complete at the cell. The piece must fit.
    func linesIfPlaced(_ shape: BlockPartyShape, col: Int, row: Int) -> UInt16 {
        for c in shape.cells { grid[(row + c.y) * 8 + col + c.x] = shape.color }
        let mask = Self.fullLines(grid)
        for c in shape.cells { grid[(row + c.y) * 8 + col + c.x] = 0 }
        return mask
    }

    // MARK: Input

    /// A finger lands on a tray slot. False when there was nothing to pick up.
    @discardableResult
    func pickUp(slot: Int) -> Bool {
        guard isOn, dragSlot == nil, slot >= 0, slot < 3, tray[slot] != nil else { return false }
        dragSlot = slot
        dragAge = 0
        ghostValid = false
        ghostLines = 0
        owe(.tap)
        return true
    }

    /// The held piece is over this cell, which may be off the board.
    func hover(col: Int, row: Int) {
        guard let shape = dragShape else { return }
        if ghostValid, col == ghostCol, row == ghostRow { return }
        ghostCol = col
        ghostRow = row
        ghostValid = fits(shape, col: col, row: row)
        ghostLines = ghostValid ? linesIfPlaced(shape, col: col, row: row) : 0
    }

    /// The finger lifts. True when the piece was placed, false when it goes back to the tray.
    @discardableResult
    func drop() -> Bool {
        guard let slot = dragSlot, let shape = tray[slot] else {
            dragSlot = nil
            return false
        }
        dragSlot = nil
        if ghostValid {
            place(shape, slot: slot, col: ghostCol, row: ghostRow)
            ghostValid = false
            ghostLines = 0
            return true
        }
        returnShape = shape
        returnSlot = slot
        returnAge = 0
        return false
    }

    // MARK: Rules

    private func deal() {
        for slot in 0..<3 {
            tray[slot] = BlockPartyShape.deal(&rng)
            trayAge[slot] = 0
        }
    }

    private func place(_ shape: BlockPartyShape, slot: Int, col: Int, row: Int) {
        for c in shape.cells {
            let k = (row + c.y) * 8 + col + c.x
            grid[k] = shape.color
            placedAge[k] = 0
        }
        tray[slot] = nil
        placed += shape.cells.count
        stage = .playing

        var points = shape.cells.count * 10
        let mask = Self.fullLines(grid)
        if mask != 0 {
            var lines = 0
            for bit in 0..<16 where (mask & UInt16(1 << bit)) != 0 { lines += 1 }
            for r in 0..<8 {
                for c in 0..<8 {
                    let inRow = (mask & UInt16(1 << r)) != 0
                    let inCol = (mask & UInt16(1 << (8 + c))) != 0
                    if !inRow && !inCol { continue }
                    let k = r * 8 + c
                    bursts[nextBurst] = BlockPartyBurst(x: Double(c) + 0.5, y: Double(r) + 0.5, color: grid[k], age: 0)
                    nextBurst = (nextBurst + 1) % bursts.count
                    grid[k] = 0
                    flash[k] = 0
                }
            }
            if sinceClear >= Self.comboGrace { streak = 0 }
            streak += 1
            sinceClear = 0
            let combo = lines + streak - 1
            bestCombo = Swift.max(bestCombo, combo)
            points += lines * 100 * combo
            linesCleared += lines
            praise = lines >= 3 || combo >= 4 ? "Perfect" : (lines == 2 || combo >= 2 ? "Great" : "Nice")
            praiseAge = 0
            note = combo >= 2 ? "Combo x\(combo)" : nil
            noteAge = 0
            owe(lines >= 2 || combo >= 2 ? .big : .cleared)
        } else {
            sinceClear += 1
            owe(.placed)
        }

        score += points
        scoreAge = 0
        floats[nextFloat] = BlockPartyFloat(text: "+\(points)", x: Double(col) + Double(shape.w) / 2,
                                            y: Double(row) + Double(shape.h) / 2, color: shape.color, age: 0)
        nextFloat = (nextFloat + 1) % floats.count

        if tray[0] == nil, tray[1] == nil, tray[2] == nil { deal() }
        if !anyFits() {
            stage = .ending
            endClock = 0
            owe(.lost)
        }
    }

    // MARK: Clock

    func step(dt raw: Double) {
        let dt = Swift.min(Swift.max(raw, 0), 1.0 / 30)
        if dt <= 0 { return }
        ambient += dt
        if stage == .finished { return }

        scoreAge = Swift.min(scoreAge + dt, 9)
        let gap = Double(score) - shownScore
        shownScore = abs(gap) < 0.6 ? Double(score) : shownScore + gap * Swift.min(1, dt * 9)
        dragAge += dt
        for k in 0..<64 {
            if placedAge[k] < 9 { placedAge[k] += dt }
            if flash[k] < 9 { flash[k] += dt }
        }
        for k in 0..<3 where trayAge[k] < 9 { trayAge[k] += dt }
        for k in bursts.indices where bursts[k].age < 9 { bursts[k].age += dt }
        for k in floats.indices where floats[k].age < 9 { floats[k].age += dt }
        if returnShape != nil {
            returnAge += dt
            if returnAge >= Self.returnLength { returnShape = nil }
        }
        if note != nil || praise != nil {
            noteAge += dt
            praiseAge += dt
            if praiseAge >= Self.noteLength {
                note = nil
                praise = nil
            }
        }

        switch stage {
        case .ready:
            break
        case .playing:
            time += dt
        case .ending:
            endClock += dt
            if endClock >= Self.endLength { stage = .finished }
        case .finished:
            break
        }
    }
}

// MARK: - Drawing

/// Paints the model as it is right now.
struct BlockPartyCanvas: View {
    let runner: BlockPartyRunner
    /// A new number every frame. The model is a class, so this is what makes SwiftUI repaint.
    var frame = 0

    var body: some View {
        Canvas(opaque: true, colorMode: .nonLinear, rendersAsynchronously: false) { context, size in
            if size.width <= 8 || size.height <= 8 { return }
            let layout = runner.layout(for: size)
            BlockPartyPainter(layout: layout, frame: runner.frame(layout)).draw(&context)
        }
    }
}

// MARK: - Scripted player

/// Plays the round for recordings while GameDemo.autopilot is on.
///
/// It reads the model, picks a placement, and then moves a pretend finger from the tray to the
/// board through the same calls a real touch makes. Its random numbers are its own, so the pieces
/// the model deals are the same with it or without it.
struct BlockPartyPilot {
    enum Act { case idle, press(CGPoint), move(CGPoint), release }

    static let readyHold = 0.9
    static let travelTime = 0.5

    private var rng: BlockPartyRandom
    private var wait = BlockPartyPilot.readyHold
    /// 0: waiting between moves. 1: carrying a piece. 2: holding over the target before letting go.
    private var phase = 0
    private var start = CGPoint.zero
    private var end = CGPoint.zero
    private var travel = 0.0
    private var hold = 0.0
    private var scratch: [Int] = Array(repeating: 0, count: 64)

    init(seed: UInt64) {
        rng = BlockPartyRandom(seed: seed ^ 0x7069_6C6F_7421, salt: BlockPartyRandom.pilot)
    }

    /// Call once per step, after the model has moved.
    mutating func act(_ model: BlockPartyModel, layout: BlockPartyLayout, dt: Double) -> Act {
        guard model.isOn else { return .idle }
        let losing: Bool
        if let limit = GameDemo.loseAfter, model.stage == .playing, model.time >= limit {
            losing = true
        } else {
            losing = false
        }

        switch phase {
        case 1:
            travel += dt / Self.travelTime
            if travel >= 1 {
                phase = 2
                hold = 0
                return .move(end)
            }
            let k = BlockPartyMath.easeInOut(travel)
            let arc = sin(k * Double.pi) * 18 * layout.u
            return .move(CGPoint(x: BlockPartyMath.lerp(Double(start.x), Double(end.x), k) + arc,
                                 y: BlockPartyMath.lerp(Double(start.y), Double(end.y), k)))
        case 2:
            hold += dt
            if hold < 0.08 { return .idle }
            phase = 0
            wait = losing ? 0.2 : rng.range(0.3, 0.6)
            return .release
        default:
            break
        }

        if model.dragSlot != nil { return .idle }
        wait -= dt
        if wait > 0 { return .idle }
        guard let choice = choose(model, losing: losing) else { return .idle }
        guard let shape = model.tray[choice.slot] else { return .idle }
        start = layout.slotCenter(choice.slot)
        let center = layout.center(of: shape, col: choice.col, row: choice.row)
        end = CGPoint(x: Double(center.x) + rng.range(-3, 3) * layout.u,
                      y: Double(center.y) + layout.lift + rng.range(-3, 3) * layout.u)
        travel = 0
        phase = 1
        return .press(start)
    }

    /// The placement it likes most, or least when losing on purpose. nil when nothing fits.
    private mutating func choose(_ model: BlockPartyModel, losing: Bool) -> (slot: Int, col: Int, row: Int)? {
        var best: (slot: Int, col: Int, row: Int)?
        var bestValue = -1e9
        var second: (slot: Int, col: Int, row: Int)?
        var secondValue = -1e9
        for slot in 0..<3 {
            guard let shape = model.tray[slot] else { continue }
            for row in 0...(8 - shape.h) {
                for col in 0...(8 - shape.w) {
                    if !model.fits(shape, col: col, row: row) { continue }
                    var value = judge(model, shape, col: col, row: row)
                    value += rng.range(0, 12)
                    if losing { value = -value }
                    if value > bestValue {
                        second = best
                        secondValue = bestValue
                        best = (slot: slot, col: col, row: row)
                        bestValue = value
                    } else if value > secondValue {
                        second = (slot: slot, col: col, row: row)
                        secondValue = value
                    }
                }
            }
        }
        // Now and then it takes its second choice, like a person would.
        if !losing, let other = second, rng.next() < 0.15 { return other }
        return best
    }

    /// How good a placement is: clears count a lot, a tidy board a little, trapped holes against it.
    private mutating func judge(_ model: BlockPartyModel, _ shape: BlockPartyShape, col: Int, row: Int) -> Double {
        for k in 0..<64 { scratch[k] = model.grid[k] }
        var touching = 0
        for c in shape.cells {
            let x = col + c.x
            let y = row + c.y
            scratch[y * 8 + x] = shape.color
            if x == 0 || scratch[y * 8 + x - 1] != 0 { touching += 1 }
            if x == 7 || scratch[y * 8 + x + 1] != 0 { touching += 1 }
            if y == 0 || scratch[(y - 1) * 8 + x] != 0 { touching += 1 }
            if y == 7 || scratch[(y + 1) * 8 + x] != 0 { touching += 1 }
        }
        let mask = BlockPartyModel.fullLines(scratch)
        var lines = 0
        if mask != 0 {
            for r in 0..<8 where (mask & UInt16(1 << r)) != 0 {
                lines += 1
                for c in 0..<8 { scratch[r * 8 + c] = 0 }
            }
            for c in 0..<8 where (mask & UInt16(1 << (8 + c))) != 0 {
                lines += 1
                for r in 0..<8 { scratch[r * 8 + c] = 0 }
            }
        }
        var filled = 0
        var holes = 0
        for y in 0..<8 {
            for x in 0..<8 {
                if scratch[y * 8 + x] != 0 {
                    filled += 1
                    continue
                }
                let left = x == 0 || scratch[y * 8 + x - 1] != 0
                let right = x == 7 || scratch[y * 8 + x + 1] != 0
                let up = y == 0 || scratch[(y - 1) * 8 + x] != 0
                let down = y == 7 || scratch[(y + 1) * 8 + x] != 0
                if left && right && up && down { holes += 1 }
            }
        }
        return Double(lines) * 120 + Double(touching) * 3 - Double(filled) * 2.5 - Double(holes) * 28
    }
}

// MARK: - Game view

/// Holds the round between frames. Nothing is published: the timeline repaints every frame anyway.
final class BlockPartyRunner: ObservableObject {
    let model: BlockPartyModel
    private let seed: UInt64
    private var lastDate: Date?
    private var frameCount = 0
    private var reported = false
    private var cachedLayout = BlockPartyLayout(size: CGSize(width: 402, height: 874))
    /// Where the finger is, in view points.
    private var finger = CGPoint.zero
    private var returnFrom = CGPoint.zero
    private var hintAlpha = 0.0
    /// Made the first time it is needed, which is only when GameDemo.autopilot is on.
    private var pilot: BlockPartyPilot?

    init(options: GameOptions) {
        model = BlockPartyModel(options: options)
        seed = options.seed
    }

    func layout(for size: CGSize) -> BlockPartyLayout {
        if cachedLayout.size != size { cachedLayout = BlockPartyLayout(size: size) }
        return cachedLayout
    }

    /// Brings the model up to the given date. Returns a number that changes when there is a new frame to paint.
    func advance(to date: Date, size: CGSize, link: GameLink) -> Int {
        let layout = self.layout(for: size)
        if link.paused {
            lastDate = nil
            return frameCount
        }
        defer { lastDate = date }
        guard let before = lastDate else { return frameCount }
        // When frames are slow the model still covers real time, in several small steps.
        var owed = Swift.min(Swift.max(date.timeIntervalSince(before), 0), 0.1)
        if owed <= 0 { return frameCount }
        while owed > 1e-6 {
            let dt = Swift.min(owed, 1.0 / 60)
            owed -= dt
            model.step(dt: dt)
            let wantHint = model.stage == .ready && model.dragSlot == nil
            hintAlpha += ((wantHint ? 1.0 : 0.0) - hintAlpha) * Swift.min(1, dt * 8)
            settle(link)
            if GameDemo.autopilot {
                if pilot == nil { pilot = BlockPartyPilot(seed: seed) }
                let act: BlockPartyPilot.Act = pilot?.act(model, layout: layout, dt: dt) ?? .idle
                switch act {
                case .idle: break
                case .press(let p): press(at: p, link: link)
                case .move(let p): move(to: p, link: link)
                case .release: release(link: link)
                }
            }
        }
        frameCount &+= 1
        return frameCount
    }

    // MARK: Touches

    func press(at p: CGPoint, link: GameLink) {
        if link.paused || link.isFinished { return }
        finger = p
        guard let slot = cachedLayout.slot(at: p) else { return }
        if model.pickUp(slot: slot) {
            hover()
            settle(link)
        }
    }

    func move(to p: CGPoint, link: GameLink) {
        if link.paused || link.isFinished { return }
        finger = p
        if model.dragSlot != nil { hover() }
    }

    func release(link: GameLink) {
        if link.isFinished { return }
        guard model.dragSlot != nil else { return }
        hover()
        if !model.drop() { returnFrom = heldCenter() }
        settle(link)
    }

    private func heldCenter() -> CGPoint {
        let k = BlockPartyMath.smooth(0, BlockPartyModel.liftLength, model.dragAge)
        return cachedLayout.heldCenter(finger: finger, lift: k)
    }

    private func hover() {
        guard let shape = model.dragShape else { return }
        let landing = cachedLayout.landing(of: shape, center: heldCenter())
        model.hover(col: landing.col, row: landing.row)
    }

    /// Plays the haptic the model owes and reports the round once it is over.
    private func settle(_ link: GameLink) {
        switch model.takeFeedback() {
        case .lost: GameHaptics.fail()
        case .big:
            GameHaptics.heavy()
            GameHaptics.success()
        case .cleared: GameHaptics.success()
        case .placed: GameHaptics.thud()
        case .tap: GameHaptics.tap()
        case .none: break
        }
        if model.stage == .finished, !reported {
            reported = true
            let result = model.result
            DispatchQueue.main.async { link.finish(result) }
        }
    }

    // MARK: Frame

    /// What the painter needs, read off the model.
    func frame(_ layout: BlockPartyLayout) -> BlockPartyFrame {
        var f = BlockPartyFrame()
        f.grid = model.grid
        f.placedAge = model.placedAge
        f.flash = model.flash
        f.tray = model.tray
        f.trayAge = model.trayAge
        if let slot = model.dragSlot, let shape = model.tray[slot] {
            f.dragSlot = slot
            f.dragShape = shape
            f.dragLift = BlockPartyMath.smooth(0, BlockPartyModel.liftLength, model.dragAge)
            f.dragCenter = layout.heldCenter(finger: finger, lift: f.dragLift)
            f.ghostCol = model.ghostCol
            f.ghostRow = model.ghostRow
            f.ghostValid = model.ghostValid
            f.ghostLines = model.ghostLines
        }
        if let shape = model.returnShape {
            f.returnShape = shape
            f.returnSlot = model.returnSlot
            f.returnFrom = returnFrom
            f.returnAge = model.returnAge
        }
        f.bursts = model.bursts
        f.floats = model.floats
        f.score = Int(model.shownScore.rounded())
        f.best = model.bestScore
        f.scoreAge = model.scoreAge
        f.note = model.note
        f.noteAge = model.noteAge
        f.praise = model.praise
        f.praiseAge = model.praiseAge
        f.ambient = model.ambient
        if hintAlpha > 0.01 {
            f.hint = "Drag a piece onto the board"
            f.hintAlpha = hintAlpha * (0.8 + 0.2 * sin(model.ambient * 3))
        }
        if model.stage == .ending || model.stage == .finished { f.endClock = model.endClock }
        f.showHUD = true
        return f
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
                BlockPartyCanvas(runner: runner, frame: runner.advance(to: timeline.date, size: geo.size, link: link))
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        if runner.model.dragSlot == nil {
                            runner.press(at: value.startLocation, link: link)
                        }
                        runner.move(to: value.location, link: link)
                    }
                    .onEnded { _ in
                        runner.release(link: link)
                    }
            )
        }
        .onChange(of: link.paused) { _, paused in
            if paused { runner.release(link: link) }
        }
        .ignoresSafeArea()
        .accessibilityElement()
        .accessibilityLabel("Block Party. Drag a piece onto the board.")
        .accessibilityAddTraits(.allowsDirectInteraction)
    }
}
