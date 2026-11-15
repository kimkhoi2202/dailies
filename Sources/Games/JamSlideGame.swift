import SwiftUI

// Jam Slide, playable.
//
// JamSlideModel   the rules of a round in plain Swift: touches in, a frame out.
// JamSlideCanvas  paints one frame of the model with the painter in JamSlideScene.swift.
// JamSlidePilot   the scripted player. It only runs while GameDemo.autopilot is on.
// JamSlideRunner  keeps the clock, passes touches on, fires haptics, reports the result.
// JamSlideGame    the view the app shows.

// MARK: - Model

/// A finger on a block.
struct JamSlideDrag {
    var index: Int
    /// Where the finger landed, in cells.
    var fingerX: Double
    var fingerY: Double
    /// 0 along x, 1 along y, -1 until the finger has moved enough to tell.
    var axis = -1
    /// How far the block is from its cell along the axis, in cells.
    var shift = 0.0
    /// The shift range inside the board.
    var inLo = 0.0
    var inHi = 0.0
    /// The block may leave through the gate at that end of its lane.
    var outLo = false
    var outHi = false
    var bumped = false
    var age = 0.0
}

/// A block easing into its cell after it was let go.
struct JamSlideGlide {
    var id: Int
    var axis: Int
    var offset: Double
    var age: Double
}

final class JamSlideModel {
    enum Stage { case ready, playing, clearing, ending, finished }

    /// What the last step or touch deserves as a haptic. A stronger one replaces a weaker one.
    enum Feedback: Int { case none, tap, spark, bump, shut, out, stuck, cleared, lost }

    static let roundTime = 120.0
    static let clearTimes = [12.0, 10, 8, 6, 4]   // seconds given back for each cleared board, then the last one
    static let holdLength = 6.0          // the clock stands still this long
    static let endLength = 1.6
    static let glideLength = 0.16
    static let calloutLength = 1.5
    static let pointsPerCell = 10
    static let quickWindow = 1.6         // blocks out this close together count as quick

    private var rng: JamSlideRandom

    private(set) var stage = Stage.ready
    private(set) var level: JamSlideLevel
    private(set) var gates: [JamSlideGate] = []
    private(set) var blocks: [JamSlideBlock] = []
    /// Block index in each cell, or -1.
    private var grid: [Int] = []

    private(set) var timeLeft = JamSlideModel.roundTime
    private(set) var heldFor = 0.0
    private(set) var score = 0
    /// The number on the points counter, which counts up to the score.
    private var shown = 0.0
    private(set) var scoreAge = 10.0
    private(set) var movesUsed = 0
    private(set) var levelsCleared = 0
    private(set) var blocksOut = 0
    private(set) var boosters = [1, 1, 1]
    private(set) var armed = -1

    /// Round clock: from the first slide to the end.
    private(set) var time = 0.0
    /// Scenery clock: runs whenever the game is not paused.
    private(set) var ambient = 0.0
    private(set) var levelAge = 10.0
    private(set) var clearClock = 0.0
    private var chestGain = 0
    private var chestPaid = 0
    private var sparksLanded = 0
    private(set) var endClock = 0.0
    private(set) var endReason = ""

    private(set) var drag: JamSlideDrag?
    private var glides: [JamSlideGlide] = []
    private(set) var particles: [JamSlideParticle] = []
    private(set) var floats: [JamSlideFloat] = []
    private(set) var callout: String?
    private(set) var calloutSub: String?
    private(set) var calloutAge = 0.0
    private var sprites: [JamSlideSprite] = []

    private var lastOutAt = -10.0
    private var quick = 0
    private var feedback = Feedback.none

    init(options: GameOptions) {
        rng = JamSlideRandom(seed: options.seed, salt: JamSlideRandom.round)
        level = JamSlideLevel.make(number: 1, seed: options.seed)
        particles.reserveCapacity(200)
        floats.reserveCapacity(16)
        glides.reserveCapacity(16)
        sprites.reserveCapacity(48)
        deal(level)
    }

    // MARK: Reading

    var movesLeft: Int { level.moveBudget - movesUsed }

    var result: GameResult {
        let out = blocksOut == 1 ? "1 block out" : "\(blocksOut) blocks out"
        let line: String
        switch levelsCleared {
        case 0: line = out
        case 1: line = "1 board cleared, \(out)"
        default: line = "\(levelsCleared) boards cleared, \(out)"
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

    private func cellFree(_ x: Int, _ y: Int) -> Bool {
        if x < 0 || y < 0 || x >= level.cols || y >= level.rows { return false }
        return grid[y * level.cols + x] < 0
    }

    /// The block under a cell, or -1.
    func block(atX x: Double, y: Double) -> Int {
        let cx = Int(x.rounded(.down))
        let cy = Int(y.rounded(.down))
        if cx < 0 || cy < 0 || cx >= level.cols || cy >= level.rows { return -1 }
        return grid[cy * level.cols + cx]
    }

    /// The lowest and highest position a block can slide to along an axis, with nothing else moving.
    func range(of index: Int, axis: Int) -> (lo: Int, hi: Int) {
        let b = blocks[index]
        if axis == 0 {
            var lo = b.x
            while lo > 0, columnFree(lo - 1, b.y, b.h) { lo -= 1 }
            var hi = b.x
            while hi + b.w < level.cols, columnFree(hi + b.w, b.y, b.h) { hi += 1 }
            return (lo, hi)
        }
        var lo = b.y
        while lo > 0, rowFree(lo - 1, b.x, b.w) { lo -= 1 }
        var hi = b.y
        while hi + b.h < level.rows, rowFree(hi + b.h, b.x, b.w) { hi += 1 }
        return (lo, hi)
    }

    private func columnFree(_ x: Int, _ y0: Int, _ h: Int) -> Bool {
        for y in y0..<(y0 + h) where !cellFree(x, y) { return false }
        return true
    }

    private func rowFree(_ y: Int, _ x0: Int, _ w: Int) -> Bool {
        for x in x0..<(x0 + w) where !cellFree(x, y) { return false }
        return true
    }

    /// The color of the open gate at one edge cell, or -1 where the frame is solid or the gate has shut.
    func gateColor(side: JamSlideSide, at index: Int) -> Int {
        for gate in gates where gate.side == side && !gate.shut {
            if index >= gate.start && index < gate.start + gate.length { return gate.color }
        }
        return -1
    }

    /// True when every edge cell from start, length long, is an open gate of this color.
    private func run(_ side: JamSlideSide, from start: Int, length: Int, color: Int) -> Bool {
        for k in 0..<length where gateColor(side: side, at: start + k) != color { return false }
        return true
    }

    /// True when every edge cell the block would cover on that side is an open gate of its color.
    func gateOpen(for b: JamSlideBlock, side: JamSlideSide) -> Bool {
        if b.lane >= 0 && side.axis != b.lane { return false }
        return run(side, from: side.axis == 0 ? b.y : b.x, length: side.axis == 0 ? b.h : b.w, color: b.color)
    }

    /// True when the block can leave in one slide along its lane toward a side.
    func canLeave(_ index: Int, side: JamSlideSide) -> Bool {
        let b = blocks[index]
        if !gateOpen(for: b, side: side) { return false }
        let r = range(of: index, axis: side.axis)
        switch side {
        case .left, .top: return r.lo == 0
        case .right: return r.hi + b.w == level.cols
        case .bottom: return r.hi + b.h == level.rows
        }
    }

    /// False when no open gate is left that this block could ever fit through.
    private func hasWayOut(_ b: JamSlideBlock) -> Bool {
        for side in JamSlideSide.allCases {
            if b.lane >= 0 {
                if side.axis == b.lane, gateOpen(for: b, side: side) { return true }
                continue
            }
            let edge = side.axis == 0 ? level.rows : level.cols
            let span = side.axis == 0 ? b.h : b.w
            if span > edge { continue }
            for start in 0...(edge - span) where run(side, from: start, length: span, color: b.color) { return true }
        }
        return false
    }

    // MARK: Input

    /// A finger lands on the board, in cells.
    func touchDown(cx: Double, cy: Double) {
        guard stage == .ready || stage == .playing else { return }
        let index = block(atX: cx, y: cy)
        if armed == 1 {
            if index >= 0 {
                boosters[1] -= 1
                armed = -1
                begin()
                remove(index, slid: false)
            }
            return
        }
        if index < 0 { return }
        begin()
        drag = JamSlideDrag(index: index, fingerX: cx, fingerY: cy)
        owe(.tap)
    }

    func touchMove(cx: Double, cy: Double) {
        guard var d = drag, stage == .playing, d.index < blocks.count else { return }
        let dx = cx - d.fingerX
        let dy = cy - d.fingerY
        let b = blocks[d.index]
        if d.axis < 0 {
            if abs(dx) < 0.12, abs(dy) < 0.12 { return }
            // A block with a lane arrow only ever slides along it.
            d.axis = b.lane >= 0 ? b.lane : (abs(dx) >= abs(dy) ? 0 : 1)
            let r = range(of: d.index, axis: d.axis)
            let pos = d.axis == 0 ? b.x : b.y
            let size = d.axis == 0 ? b.w : b.h
            let edge = d.axis == 0 ? level.cols : level.rows
            d.inLo = Double(r.lo - pos)
            d.inHi = Double(r.hi - pos)
            d.outLo = r.lo == 0 && gateOpen(for: b, side: d.axis == 0 ? .left : .top)
            d.outHi = r.hi + size == edge && gateOpen(for: b, side: d.axis == 0 ? .right : .bottom)
        }
        let pos = Double(d.axis == 0 ? b.x : b.y)
        let size = Double(d.axis == 0 ? b.w : b.h)
        let edge = Double(d.axis == 0 ? level.cols : level.rows)
        let want = d.axis == 0 ? dx : dy
        let lo = d.outLo ? d.inLo - size - 0.6 : d.inLo
        let hi = d.outHi ? d.inHi + size + 0.6 : d.inHi
        var shift = want
        if want < lo {
            shift = lo - Swift.min(0.3, (lo - want) * 0.22)
        } else if want > hi {
            shift = hi + Swift.min(0.3, (want - hi) * 0.22)
        }
        let blocked = (want < lo - 0.05 && !d.outLo) || (want > hi + 0.05 && !d.outHi)
        if blocked {
            if !d.bumped {
                d.bumped = true
                owe(.bump)
            }
        } else {
            d.bumped = false
        }
        d.shift = shift
        drag = d

        // More than half way through the gate: it is out.
        if d.outLo, pos + shift <= -size * 0.5 {
            leave(d.index, side: d.axis == 0 ? .left : .top)
        } else if d.outHi, pos + shift + size >= edge + size * 0.5 {
            leave(d.index, side: d.axis == 0 ? .right : .bottom)
        }
    }

    func touchUp() {
        guard let d = drag else { return }
        drag = nil
        guard stage == .playing, d.axis >= 0, d.index < blocks.count else { return }
        let b = blocks[d.index]
        let pos = d.axis == 0 ? b.x : b.y
        let size = Double(d.axis == 0 ? b.w : b.h)
        let edge = Double(d.axis == 0 ? level.cols : level.rows)
        let placed = Double(pos) + d.shift

        // Let go part way through the gate: it still goes out if most of it is through.
        if d.outLo, -placed >= size * 0.3 {
            leave(d.index, side: d.axis == 0 ? .left : .top)
            return
        }
        if d.outHi, placed + size - edge >= size * 0.3 {
            leave(d.index, side: d.axis == 0 ? .right : .bottom)
            return
        }
        let lowest = pos + Int(d.inLo.rounded())
        let highest = pos + Int(d.inHi.rounded())
        let target = Swift.max(lowest, Swift.min(highest, Int(placed.rounded())))
        if target != pos {
            if d.axis == 0 { blocks[d.index].x = target } else { blocks[d.index].y = target }
            rebuildGrid()
            movesUsed += 1
            owe(.tap)
        }
        glides.append(JamSlideGlide(id: b.id, axis: d.axis, offset: placed - Double(target), age: 0))
        if movesLeft <= 0 { end("Out of moves") }
    }

    /// The touch was taken away (the app paused the game, the system cancelled it). The block
    /// eases back to its cell, nothing goes through a gate and no move is spent.
    func cancelDrag() {
        guard let d = drag else { return }
        drag = nil
        guard d.axis >= 0, d.index < blocks.count else { return }
        glides.append(JamSlideGlide(id: blocks[d.index].id, axis: d.axis, offset: d.shift, age: 0))
    }

    /// One of the three buttons at the bottom: freeze the clock, break a block, a new board.
    func useBooster(_ k: Int) {
        guard stage == .ready || stage == .playing, k >= 0, k < 3 else { return }
        if k == 1 {
            // The hammer waits for a tap on a block. A second tap on the button puts it away.
            guard boosters[1] > 0 else { return }
            armed = armed == 1 ? -1 : 1
            owe(.tap)
            return
        }
        guard boosters[k] > 0 else { return }
        armed = -1
        begin()
        boosters[k] -= 1
        if k == 0 {
            heldFor = Self.holdLength
            float("Clock frozen", x: Double(level.cols) / 2, y: 0.9, big: false)
            owe(.tap)
        } else {
            drag = nil
            deal(JamSlideLevel.make(number: level.number, seed: rng.bits()))
            float("New board", x: Double(level.cols) / 2, y: Double(level.rows) / 2, big: true)
            owe(.bump)
        }
    }

    // MARK: Clock

    func step(dt raw: Double) {
        let dt = Swift.min(Swift.max(raw, 0), 1.0 / 30)
        if dt <= 0 { return }
        ambient += dt
        if stage == .finished { return }

        scoreAge = Swift.min(scoreAge + dt, 100)
        levelAge = Swift.min(levelAge + dt, 100)
        let goal = Double(score)
        shown += (goal - shown) * (1 - exp(-12 * dt))
        if abs(goal - shown) < 0.5 { shown = goal }
        if callout != nil {
            calloutAge += dt
            if calloutAge >= Self.calloutLength { callout = nil }
        }
        if drag != nil { drag?.age += dt }
        for k in gates.indices where gates[k].age < 10 { gates[k].age += dt }
        if !glides.isEmpty {
            for k in glides.indices { glides[k].age += dt }
            glides.removeAll { $0.age >= Self.glideLength }
        }
        if !floats.isEmpty {
            for k in floats.indices { floats[k].age += dt }
            floats.removeAll { $0.age >= 1.1 }
        }
        if !particles.isEmpty {
            for k in particles.indices {
                particles[k].age += dt
                particles[k].vy += 14 * dt
                particles[k].x += particles[k].vx * dt
                particles[k].y += particles[k].vy * dt
            }
            particles.removeAll { $0.age >= $0.life }
        }

        switch stage {
        case .ready:
            break
        case .playing:
            time += dt
            if heldFor > 0 {
                heldFor = Swift.max(0, heldFor - dt)
            } else {
                timeLeft -= dt
                if timeLeft <= 0 {
                    timeLeft = 0
                    end("Time is up")
                }
            }
        case .clearing:
            time += dt
            clearClock += dt
            // The chest's sparks pay out one by one as they reach the counter.
            let landed = JamSlideChest.landed(at: clearClock)
            if landed > sparksLanded {
                sparksLanded = landed
                let due = chestGain * landed / JamSlideChest.sparks
                score += due - chestPaid
                chestPaid = due
                scoreAge = 0
                owe(.spark)
            }
            if clearClock >= JamSlideChest.length {
                deal(JamSlideLevel.make(number: level.number + 1, seed: rng.bits()))
                stage = .playing
            }
        case .ending:
            endClock += dt
            if endClock >= Self.endLength { stage = .finished }
        case .finished:
            break
        }
    }

    // MARK: Rules

    private func begin() {
        if stage == .ready {
            stage = .playing
            time = 0
        }
    }

    private func deal(_ next: JamSlideLevel) {
        level = next
        blocks = next.blocks
        gates = next.gates
        movesUsed = 0
        levelAge = 0
        glides.removeAll(keepingCapacity: true)
        rebuildGrid()
    }

    private func rebuildGrid() {
        let count = level.cols * level.rows
        if grid.count != count { grid = [Int](repeating: -1, count: count) }
        for k in grid.indices { grid[k] = -1 }
        for (i, b) in blocks.enumerated() {
            for y in b.y..<(b.y + b.h) {
                for x in b.x..<(b.x + b.w) where x >= 0 && y >= 0 && x < level.cols && y < level.rows {
                    grid[y * level.cols + x] = i
                }
            }
        }
    }

    /// The block goes out through a gate. Numbered gates it passes count down, and shut at zero.
    private func leave(_ index: Int, side: JamSlideSide) {
        let b = blocks[index]
        let start = side.axis == 0 ? b.y : b.x
        let end = start + (side.axis == 0 ? b.h : b.w)
        var shutNow = false
        for g in gates.indices where gates[g].side == side && gates[g].counted && !gates[g].shut {
            if Swift.max(start, gates[g].start) >= Swift.min(end, gates[g].start + gates[g].length) { continue }
            gates[g].left -= 1
            gates[g].age = 0
            if gates[g].left <= 0 {
                gates[g].left = 0
                gates[g].shut = true
                shutNow = true
            }
        }

        let cx = side.axis == 0 ? (side.dir < 0 ? 0.0 : Double(level.cols)) : Double(b.x) + Double(b.w) / 2
        let cy = side.axis == 1 ? (side.dir < 0 ? 0.0 : Double(level.rows)) : Double(b.y) + Double(b.h) / 2
        if time - lastOutAt < Self.quickWindow { quick += 1 } else { quick = 0 }
        lastOutAt = time
        let points = Self.pointsPerCell * b.cells + 5 * quick
        burst(x: cx, y: cy, color: b.color, count: 16)
        float("+\(points)", x: Double(b.x) + Double(b.w) / 2, y: Double(b.y) + Double(b.h) / 2, big: false)
        if quick == 2 { say("Quick", sub: nil) }
        owe(shutNow ? .shut : .out)
        remove(index, slid: true, points: points)

        // A gate shut on a block that had no other way out: that board cannot be cleared any more.
        if shutNow, stage == .playing, blocks.contains(where: { !hasWayOut($0) }) {
            say("No way out", sub: "Here is a new board")
            deal(JamSlideLevel.make(number: level.number, seed: rng.bits()))
            owe(.stuck)
        }
    }

    /// Takes a block off the board, for a slide out or the hammer.
    private func remove(_ index: Int, slid: Bool, points: Int? = nil) {
        let b = blocks[index]
        if !slid {
            let x = Double(b.x) + Double(b.w) / 2
            let y = Double(b.y) + Double(b.h) / 2
            burst(x: x, y: y, color: b.color, count: 20)
            float("+\(Self.pointsPerCell * b.cells)", x: x, y: y, big: false)
            owe(.out)
        }
        score += points ?? (Self.pointsPerCell * b.cells)
        scoreAge = 0
        blocksOut += 1
        if slid { movesUsed += 1 }
        drag = nil
        blocks.remove(at: index)
        rebuildGrid()

        if blocks.isEmpty {
            cleared()
        } else if movesLeft <= 0 {
            end("Out of moves")
        }
    }

    private func cleared() {
        stage = .clearing
        clearClock = 0
        sparksLanded = 0
        chestPaid = 0
        chestGain = 50 * level.number + 50
        levelsCleared += 1
        let gift = Self.clearTimes[Swift.min(levelsCleared, Self.clearTimes.count) - 1]
        timeLeft += gift
        let spare = level.moveBudget - movesUsed
        let praise = movesUsed <= level.blocks.count ? "Perfect" : (spare >= level.blocks.count / 3 ? "Great" : "Nice")
        say(praise, sub: "Board \(level.number) clear, +\(Int(gift))s")
        for k in 0..<6 {
            burst(x: Double(level.cols) * (0.15 + 0.14 * Double(k)), y: Double(level.rows) * (k % 2 == 0 ? 0.3 : 0.7),
                  color: k % JamSlidePalette.blocks.count, count: 10)
        }
        owe(.cleared)
    }

    private func end(_ reason: String) {
        if stage == .ending || stage == .finished { return }
        stage = .ending
        endClock = 0
        endReason = reason
        drag = nil
        armed = -1
        owe(.lost)
    }

    private func say(_ words: String, sub: String?) {
        callout = words
        calloutSub = sub
        calloutAge = 0
    }

    private func float(_ text: String, x: Double, y: Double, big: Bool) {
        if floats.count >= 12 { floats.removeFirst() }
        floats.append(JamSlideFloat(text: text, x: x, y: y, age: 0, big: big))
    }

    private func burst(x: Double, y: Double, color: Int, count: Int) {
        for _ in 0..<count {
            if particles.count >= 200 { particles.removeFirst() }
            let t = rng.range(0, 2 * .pi)
            let v = rng.range(2, 7)
            particles.append(JamSlideParticle(x: x, y: y, vx: cos(t) * v, vy: sin(t) * v - 3, age: 0, life: rng.range(0.5, 0.9),
                                              size: rng.range(0.14, 0.28), color: rng.chance(0.3) ? -1 : color, spin: rng.range(-7, 7)))
        }
    }

    // MARK: The frame

    /// The model as the painter wants it. The sprite array is kept between frames.
    func frame() -> JamSlideFrame {
        sprites.removeAll(keepingCapacity: true)
        for (i, b) in blocks.enumerated() {
            var s = JamSlideSprite(x: Double(b.x), y: Double(b.y), w: b.w, h: b.h, color: b.color, lane: b.lane)
            if let d = drag, d.index == i {
                s.lift = JamSlideMath.smooth(0, 0.12, d.age)
                if d.axis == 0 { s.x += d.shift } else if d.axis == 1 { s.y += d.shift }
            }
            for g in glides where g.id == b.id {
                let k = 1 - JamSlideMath.easeOut(g.age / Self.glideLength)
                if g.axis == 0 { s.x += g.offset * k } else { s.y += g.offset * k }
            }
            let born = levelAge - Double(i) * 0.03
            if born < 0 {
                s.scale = 0
            } else if born < 0.3 {
                s.scale = 0.5 + 0.5 * JamSlideMath.easeOut(born / 0.22) * JamSlideMath.pop(born / 0.3)
            }
            sprites.append(s)
        }

        var f = JamSlideFrame()
        f.cols = level.cols
        f.rows = level.rows
        f.gates = gates
        f.sprites = sprites
        f.particles = particles
        f.floats = floats
        f.timeLeft = timeLeft
        f.frozen = heldFor > 0
        f.score = Int(shown.rounded())
        f.scoreAge = scoreAge
        f.level = level.number
        f.movesLeft = movesLeft
        f.callout = callout
        f.calloutSub = calloutSub
        f.calloutAge = calloutAge
        f.boosters = boosters
        f.armed = armed
        f.ambient = ambient
        if stage == .clearing { f.chestAge = clearClock }
        let teach = "Drag a block out through its color gate"
        if stage == .ready {
            f.hint = teach
            f.hintAlpha = 1
            f.hintPulse = 0.5 + 0.5 * sin(ambient * 3)
        } else if armed == 1 {
            f.hint = "Tap a block to break it"
            f.hintAlpha = 1
            f.hintPulse = 0.5 + 0.5 * sin(ambient * 5)
        } else if stage == .playing, time < 1.2, levelsCleared == 0 {
            f.hint = teach
            f.hintAlpha = 1 - JamSlideMath.smooth(0.6, 1.2, time)
            f.hintPulse = 1
        }
        if stage == .ending || stage == .finished {
            f.endFade = JamSlideMath.smooth(0.05, 0.5, endClock)
            f.endText = endReason
        }
        return f
    }
}

// MARK: - Drawing

/// Paints the model as it is right now.
struct JamSlideCanvas: View {
    let model: JamSlideModel
    /// A new number every frame. The model is a class, so this is what makes SwiftUI repaint.
    var frame = 0

    var body: some View {
        Canvas(opaque: true, colorMode: .nonLinear, rendersAsynchronously: false) { context, size in
            if size.width <= 8 || size.height <= 8 { return }
            JamSlidePainter(size: size).draw(&context, model.frame())
        }
    }
}

// MARK: - Scripted player

/// Plays the round for recordings while GameDemo.autopilot is on.
///
/// It drives the model through the same touch calls a finger uses: it picks a block, slides it
/// over a few frames and lets go. It follows the board's own solving order, so numbered gates
/// never shut early, now and then slides a block the wrong way, and once GameDemo.loseAfter has
/// passed it only wastes moves, so the board runs out of them.
struct JamSlidePilot {
    static let readyHold = 0.9
    static let speed = 7.0              // cells per second while sliding

    private struct Slide {
        var index: Int
        var axis: Int
        var target: Double
        var fingerX: Double
        var fingerY: Double
        var shift = 0.0
    }

    private var rng: JamSlideRandom
    private var wait = JamSlidePilot.readyHold
    private var slide: Slide?
    private var moves = 0

    init(seed: UInt64) {
        rng = JamSlideRandom(seed: seed, salt: JamSlideRandom.pilot)
    }

    /// Call once per step, after the model has moved.
    mutating func play(_ model: JamSlideModel, dt: Double) {
        if model.stage == .ending || model.stage == .finished { return }
        var losing = false
        if let limit = GameDemo.loseAfter, model.stage == .playing, model.time >= limit { losing = true }

        if var s = slide {
            if model.drag == nil || s.index >= model.blocks.count {
                // The block went out, or something took the finger away.
                slide = nil
                model.touchUp()
                wait = losing ? 0.15 : rng.range(0.45, 0.85)
                return
            }
            let step = (losing ? 2.0 : 1.0) * Self.speed * dt
            let done = abs(s.shift) + step >= abs(s.target)
            s.shift = done ? s.target : s.shift + step * (s.target < 0 ? -1 : 1)
            slide = s
            model.touchMove(cx: s.fingerX + (s.axis == 0 ? s.shift : 0), cy: s.fingerY + (s.axis == 1 ? s.shift : 0))
            if done {
                model.touchUp()
                slide = nil
                wait = losing ? 0.15 : rng.range(0.45, 0.9)
            }
            return
        }

        if model.stage == .clearing { return }
        wait -= dt
        if wait > 0 { return }
        if model.blocks.isEmpty { return }

        if !losing, model.timeLeft < 25, model.boosters[0] > 0 {
            model.useBooster(0)
            wait = 0.4
            return
        }

        if losing || (moves >= 2 && rng.chance(0.1)) {
            if let s = wasted(model, anyway: losing) {
                start(s, model)
                return
            }
            if losing {
                wait = 0.2
                return
            }
        }
        if let s = solving(model) {
            start(s, model)
            return
        }
        if let s = wasted(model, anyway: false) {
            start(s, model)
            return
        }
        wait = 0.5
    }

    private mutating func start(_ s: Slide, _ model: JamSlideModel) {
        model.touchDown(cx: s.fingerX, cy: s.fingerY)
        if model.drag == nil {
            wait = 0.3
            return
        }
        slide = s
        moves += 1
    }

    /// A slide of a block toward its gate.
    private mutating func solving(_ model: JamSlideModel) -> Slide? {
        let level = model.level
        // Blocks that can go straight out, earliest in the solving order first.
        for id in level.solution {
            guard let index = model.blocks.firstIndex(where: { $0.id == id }) else { continue }
            let b = model.blocks[index]
            if model.canLeave(index, side: b.exit) {
                let lane = b.exit.axis == 0 ? level.cols : level.rows
                let pos = b.exit.axis == 0 ? b.x : b.y
                let size = b.exit.axis == 0 ? b.w : b.h
                let before = Double(pos) + Double(size) * 0.5 + 0.4
                let after = Double(lane - pos - size) + Double(size) * 0.5 + 0.4
                return make(index, b, axis: b.exit.axis, target: b.exit.dir * (b.exit.dir < 0 ? before : after))
            }
        }
        // Otherwise a block that can at least get closer to its gate.
        for id in level.solution {
            guard let index = model.blocks.firstIndex(where: { $0.id == id }) else { continue }
            let b = model.blocks[index]
            let r = model.range(of: index, axis: b.exit.axis)
            let pos = b.exit.axis == 0 ? b.x : b.y
            let to = b.exit.dir < 0 ? r.lo : r.hi
            if to != pos { return make(index, b, axis: b.exit.axis, target: Double(to - pos)) }
        }
        return nil
    }

    /// A slide that changes nothing for the better: a block moved away from its gate. anyway: when
    /// there is none, any slide that stops inside the board, even one that spoils the solving order.
    private mutating func wasted(_ model: JamSlideModel, anyway: Bool) -> Slide? {
        let count = model.blocks.count
        if count == 0 { return nil }
        let from = rng.int(0...(count - 1))
        for k in 0..<count {
            let index = (from + k) % count
            let b = model.blocks[index]
            let r = model.range(of: index, axis: b.exit.axis)
            let pos = b.exit.axis == 0 ? b.x : b.y
            let away = b.exit.dir < 0 ? r.hi : r.lo
            if away != pos { return make(index, b, axis: b.exit.axis, target: Double(away - pos)) }
        }
        if !anyway { return nil }
        for k in 0..<count {
            let index = (from + k) % count
            let b = model.blocks[index]
            for axis in 0...1 where b.lane < 0 || b.lane == axis {
                let r = model.range(of: index, axis: axis)
                let pos = axis == 0 ? b.x : b.y
                if r.hi != pos { return make(index, b, axis: axis, target: Double(r.hi - pos)) }
                if r.lo != pos { return make(index, b, axis: axis, target: Double(r.lo - pos)) }
            }
        }
        return nil
    }

    private mutating func make(_ index: Int, _ b: JamSlideBlock, axis: Int, target: Double) -> Slide {
        let fx = Double(b.x) + Double(b.w) * rng.range(0.3, 0.7)
        let fy = Double(b.y) + Double(b.h) * rng.range(0.3, 0.7)
        return Slide(index: index, axis: axis, target: target, fingerX: fx, fingerY: fy)
    }
}

// MARK: - Game view

/// Holds the round between frames. Nothing is published: the timeline repaints every frame anyway.
final class JamSlideRunner: ObservableObject {
    let model: JamSlideModel
    private let seed: UInt64
    private var lastDate: Date?
    private var frame = 0
    private var reported = false
    /// Made the first time it is needed, which is only when GameDemo.autopilot is on.
    private var pilot: JamSlidePilot?
    /// A finger is down and its gesture has not ended normally yet.
    private var fingerDown = false

    init(options: GameOptions) {
        model = JamSlideModel(options: options)
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
                if pilot == nil { pilot = JamSlidePilot(seed: seed) }
                pilot?.play(model, dt: dt)
            }
            settle(link)
        }
        frame &+= 1
        return frame
    }

    private func layout(_ size: CGSize) -> JamSlideLayout {
        JamSlideLayout(size: size, cols: model.level.cols, rows: model.level.rows)
    }

    func down(at p: CGPoint, in size: CGSize, link: GameLink) {
        if link.paused || link.isFinished || GameDemo.autopilot { return }
        // A touch the system cancelled never reached up(), so its drag may still be held.
        model.cancelDrag()
        fingerDown = true
        let lay = layout(size)
        let k = lay.booster(at: p)
        if k >= 0 {
            model.useBooster(k)
        } else {
            let c = lay.position(at: p)
            model.touchDown(cx: c.x, cy: c.y)
        }
        settle(link)
    }

    func move(to p: CGPoint, in size: CGSize, link: GameLink) {
        if link.paused || link.isFinished || GameDemo.autopilot { return }
        let c = layout(size).position(at: p)
        model.touchMove(cx: c.x, cy: c.y)
        settle(link)
    }

    func up(link: GameLink) {
        if GameDemo.autopilot { return }
        fingerDown = false
        model.touchUp()
        settle(link)
    }

    /// The touch flag went back to false. When the gesture did not end normally (the system took
    /// the touch away), the block goes back instead of being dropped. Checked on the next pass so a
    /// normal end has had its say first.
    func released(link: GameLink) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.fingerDown else { return }
            self.cancel(link: link)
        }
    }

    /// The app paused the game, or the touch was cancelled.
    func cancel(link: GameLink) {
        fingerDown = false
        model.cancelDrag()
        settle(link)
    }

    /// Plays the haptic the model owes and reports the round once it is over.
    private func settle(_ link: GameLink) {
        switch model.takeFeedback() {
        case .lost, .stuck: GameHaptics.fail()
        case .cleared:
            GameHaptics.heavy()
            GameHaptics.success()
        case .out, .shut: GameHaptics.thud()
        case .bump, .tap, .spark: GameHaptics.tap()
        case .none: break
        }
        if model.stage == .finished, !reported {
            reported = true
            let result = model.result
            DispatchQueue.main.async { link.finish(result) }
        }
    }
}

public struct JamSlideGame: View {
    private let options: GameOptions
    private let link: GameLink

    public init(options: GameOptions, link: GameLink) {
        self.options = options
        self.link = link
    }

    public var body: some View {
        // A new link is a new round, so the round's state lives and dies with the link.
        JamSlideRound(options: options, link: link)
            .id(ObjectIdentifier(link))
    }
}

private struct JamSlideRound: View {
    @ObservedObject var link: GameLink
    @StateObject private var runner: JamSlideRunner
    @GestureState private var touching = false

    init(options: GameOptions, link: GameLink) {
        self.link = link
        _runner = StateObject(wrappedValue: JamSlideRunner(options: options))
    }

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: nil, paused: link.paused)) { timeline in
                JamSlideCanvas(model: runner.model, frame: runner.advance(to: timeline.date, link: link))
            }
            .contentShape(Rectangle())
            .gesture(
                // The flag clears itself when the touch ends or is cancelled, so a new touch always
                // starts with down().
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .updating($touching) { value, down, _ in
                        if !down {
                            down = true
                            runner.down(at: value.startLocation, in: geo.size, link: link)
                        }
                        runner.move(to: value.location, in: geo.size, link: link)
                    }
                    .onEnded { _ in
                        runner.up(link: link)
                    }
            )
        }
        .onChange(of: touching) { _, down in
            if !down { runner.released(link: link) }
        }
        .onChange(of: link.paused) { _, paused in
            if paused { runner.cancel(link: link) }
        }
        .ignoresSafeArea()
        .accessibilityElement()
        .accessibilityLabel("Jam Slide. Drag each block out through a gate of its own color.")
        .accessibilityAddTraits(.allowsDirectInteraction)
    }
}
