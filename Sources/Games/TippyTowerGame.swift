import SwiftUI

// Tippy Tower, playable.
//
// TippyTowerModel   the rules of a round in plain Swift: step(dt:) and tap().
// TippyTowerCanvas  paints one frame of the model with the clip's painter.
// TippyTowerPilot   the scripted player. It only runs while GameDemo.autopilot is on.
// TippyTowerRunner  keeps the clock, passes touches on, fires haptics, reports the result.
// TippyTowerGame    the view the app shows.

// MARK: - Model

final class TippyTowerModel {
    enum Stage { case ready, playing, ending, finished }

    /// What the last step or tap deserves as a haptic. A stronger one replaces a weaker one.
    enum Feedback: Int { case none, landed, good, missed }

    struct Friend {
        let name: String
        /// The height of this friend's tower today.
        let floors: Int
        /// Seconds since the player went past. nil until then.
        var passedFor: Double?
    }

    // Tuning. Lengths are in slab units (the first slab is 2 wide), times in seconds.
    static let reach = 2.15                 // how far the slab swings to either side of the tower
    static let startSpeed = 1.9             // slab units per second
    static let calmFloors = 6               // floors before the slabs start to speed up
    static let speedPerFloor = 0.034        // from there to floor 60
    static let speedPerHighFloor = 0.012    // above floor 60
    static let topSpeed = 7.5
    static let perfectWindow = 0.10         // a drop this close snaps into place
    static let perfectSeconds = 0.016       // and the window is never tighter than one frame of travel
    static let growFrom = 3                 // perfect drops in a row before the slab grows back
    static let growBy = 0.07                // added to each side
    static let sliver = 0.05                // less overlap than this is a miss
    static let lockout = 0.15               // a new slab cannot be dropped while it fades in
    static let firstDropOverlap = 0.5       // the first slab only drops with this share of it over the tower
    static let idleLimit = 8.0              // a slab left alone this long falls at its next turn
    static let endLength = 1.25
    static let landUnit = 0.6               // seconds in one "drop" of the painter's landing animations
    static let pieceUnit = 0.55             // the same for a falling offcut
    static let noteLength = 1.9

    let solo: Bool
    let bestScore: Int
    private var rng: TippyTowerRandom

    private(set) var stage = Stage.ready
    private(set) var slabs: [TippyTowerSlab] = []
    private(set) var pieces: [TippyTowerPiece] = []
    private(set) var friends: [Friend] = []

    /// Where the sliding slab is along its axis. 0 = lined up with the tower.
    private(set) var offset = -TippyTowerModel.reach
    private(set) var dir = 1.0
    private(set) var speed = TippyTowerModel.startSpeed
    private(set) var moverAge = 0.0
    private var moverGone = false
    private var idle = 0.0

    private(set) var streak = 0
    private(set) var bestStreak = 0
    private(set) var perfects = 0
    /// One gold each time the run of perfect drops reaches another three.
    private(set) var gold = 0

    private(set) var sinceLanding = 100.0
    private(set) var cam = TippyTowerPainter.slabH
    /// Round clock: from the first drop to the miss.
    private(set) var time = 0.0
    /// Scenery clock: runs whenever the game is not paused.
    private(set) var ambient = 0.0
    private(set) var endClock = 0.0
    private(set) var note: String?
    private(set) var noteAge = 0.0

    private var feedback = Feedback.none

    init(options: GameOptions) {
        solo = options.solo
        bestScore = Swift.max(0, options.bestScore)
        rng = TippyTowerRandom(seed: options.seed, salt: TippyTowerRandom.round)
        slabs.reserveCapacity(256)
        slabs.append(TippyTowerSlab())      // the round starts with one slab already on the base

        if !options.solo {
            let names = Array(options.friendNames.filter { !$0.isEmpty }.prefix(3))
            let bands: [ClosedRange<Int>]
            switch names.count {
            case 3: bands = [12...24, 25...40, 41...60]
            case 2: bands = [12...30, 31...60]
            default: bands = [12...60]
            }
            // The seed decides who built the low, the middle and the high tower.
            var order = Array(bands.indices)
            var last = order.count - 1
            while last > 0 {
                order.swapAt(last, rng.int(0...last))
                last -= 1
            }
            for (k, name) in names.enumerated() {
                friends.append(Friend(name: name, floors: rng.int(bands[order[k]])))
            }
        }
        speed = Self.speed(atFloor: 0, wobble: 1)
    }

    // MARK: Reading

    /// Floors the player has stacked. The slab the round starts with is not one of them.
    var floors: Int { slabs.count - 1 }

    /// The axis the next slab slides along.
    var axis: Int { slabs.count % 2 }

    var hasMover: Bool { !moverGone && (stage == .ready || stage == .playing) }

    /// The width of the tower's top along the sliding slab's axis.
    var topWidth: Double { slabs[slabs.count - 1].width(along: axis) }

    /// The sliding slab as it is now.
    var moverBox: (x0: Double, x1: Double, z0: Double, z1: Double) {
        let top = slabs[slabs.count - 1]
        return axis == 0 ? (top.x0 + offset, top.x1 + offset, top.z0, top.z1)
                         : (top.x0, top.x1, top.z0 + offset, top.z1 + offset)
    }

    /// A drop this close to lined up counts as perfect.
    var tolerance: Double { Swift.max(Self.perfectWindow, speed * Self.perfectSeconds) }

    var result: GameResult {
        var line: String?
        if bestStreak >= 2 {
            line = "\(bestStreak) perfect drops in a row"
        } else if perfects >= 1 {
            line = perfects == 1 ? "1 perfect drop" : "\(perfects) perfect drops"
        }
        guard !friends.isEmpty else { return GameResult(score: floors, unit: "floors", detail: line) }
        let taller = friends.filter { $0.floors > floors }.count
        return GameResult(score: floors, unit: "floors", detail: line, placement: 1 + taller, playerCount: friends.count + 1)
    }

    static func speed(atFloor floor: Int, wobble: Double) -> Double {
        let level = Double(floor)
        let low = speedPerFloor * Swift.max(0, Swift.min(level, 60) - Double(calmFloors))
        let high = speedPerHighFloor * Swift.max(0, level - 60)
        return Swift.min(topSpeed, startSpeed + low + high) * wobble
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

    /// The game's one input: let go of the sliding slab. The first drop starts the round.
    /// False when the tap did nothing.
    @discardableResult
    func tap() -> Bool {
        guard hasMover, moverAge >= Self.lockout else { return false }
        // A stray first tap must not end the round before it has begun.
        if floors == 0, topWidth - abs(offset) < topWidth * Self.firstDropOverlap { return false }
        stage = .playing
        drop(forced: false)
        return true
    }

    // MARK: Clock

    func step(dt raw: Double) {
        let dt = Swift.min(Swift.max(raw, 0), 1.0 / 30)
        if dt <= 0 { return }
        ambient += dt
        if stage == .finished { return }

        sinceLanding = Swift.min(sinceLanding + dt, 100)
        if note != nil {
            noteAge += dt
            if noteAge >= Self.noteLength { note = nil }
        }
        for k in friends.indices {
            if let since = friends[k].passedFor { friends[k].passedFor = Swift.min(since + dt, 100) }
        }
        if !pieces.isEmpty {
            for k in pieces.indices { pieces[k].age += dt / Self.pieceUnit }
            pieces.removeAll { $0.age >= 1.5 }
        }
        // The camera eases up to the top of the tower.
        let goal = Double(slabs.count) * TippyTowerPainter.slabH
        cam += (goal - cam) * (1 - exp(-7 * dt))

        switch stage {
        case .ready:
            slide(dt)
        case .playing:
            time += dt
            idle += dt
            slide(dt)
        case .ending:
            endClock += dt
            if endClock >= Self.endLength { stage = .finished }
        case .finished:
            break
        }
    }

    private func slide(_ dt: Double) {
        moverAge += dt
        offset += dir * speed * dt
        let limit = Self.reach
        var turned = false
        if offset >= limit {
            offset = Swift.max(-limit, 2 * limit - offset)
            dir = -1
            turned = true
        } else if offset <= -limit {
            offset = Swift.min(limit, -2 * limit - offset)
            dir = 1
            turned = true
        }
        // Left alone too long: the slab lets go at the end of its swing, clear of the tower.
        if turned, stage == .playing, idle >= Self.idleLimit {
            offset = dir > 0 ? -limit : limit
            drop(forced: true)
        }
    }

    // MARK: Rules

    private func drop(forced: Bool) {
        let floor = slabs.count
        let top = slabs[floor - 1]
        let along = floor % 2
        let width = top.width(along: along)
        let error = offset

        if forced || abs(error) >= width - Self.sliver {
            // Clear of the tower: the whole slab falls and the round is over.
            let box = moverBox
            let whole = TippyTowerOffcut(x0: box.x0, x1: box.x1, z0: box.z0, z1: box.z1, side: error > 0 ? 1 : -1)
            shed(TippyTowerPiece(cut: whole, axis: along, floor: floor, age: 0))
            moverGone = true
            streak = 0
            stage = .ending
            endClock = 0
            owe(.missed)
            return
        }

        var slab: TippyTowerSlab
        if abs(error) <= tolerance {
            // Perfect: it snaps into line and nothing is cut. A streak grows the slab back.
            streak += 1
            perfects += 1
            bestStreak = Swift.max(bestStreak, streak)
            if streak % 3 == 0 { gold += 1 }
            slab = TippyTowerSlab(x0: top.x0, x1: top.x1, z0: top.z0, z1: top.z1, axis: along, error: error)
            slab.perfect = true
            slab.streak = streak
            if streak >= Self.growFrom {
                if along == 0 {
                    slab.x0 = Swift.max(-1, slab.x0 - Self.growBy)
                    slab.x1 = Swift.min(1, slab.x1 + Self.growBy)
                } else {
                    slab.z0 = Swift.max(-1, slab.z0 - Self.growBy)
                    slab.z1 = Swift.min(1, slab.z1 + Self.growBy)
                }
            }
            owe(.good)
        } else {
            streak = 0
            slab = TippyTowerSlab.sliced(on: top, axis: along, error: error)
            if let cut = slab.offcut { shed(TippyTowerPiece(cut: cut, axis: along, floor: floor, age: 0)) }
            owe(.landed)
        }
        slabs.append(slab)
        sinceLanding = 0

        for k in friends.indices where friends[k].passedFor == nil && floors > friends[k].floors {
            friends[k].passedFor = 0
            note = "Passed \(friends[k].name)"
            noteAge = 0
            owe(.good)
        }

        // The next slab comes from the back again, a little faster, never at quite the same pace twice.
        offset = -Self.reach
        dir = 1
        moverAge = 0
        idle = 0
        speed = Self.speed(atFloor: floors, wobble: floors >= 6 ? rng.range(0.93, 1.09) : 1)
    }

    private func shed(_ piece: TippyTowerPiece) {
        if pieces.count >= 4 { pieces.removeFirst() }
        pieces.append(piece)
    }
}

// MARK: - Drawing

extension TippyTowerPainter {
    /// A dashed line beside the tower at the height each friend reached today.
    func drawFriendLines(_ ctx: inout GraphicsContext, _ friends: [TippyTowerModel.Friend]) {
        let towerTop = Double(n) * slabH
        let ceiling = Double(GameLayout.topBand) + 6
        let dashes: [CGFloat] = [5 * u, 5 * u]
        let line = Swift.max(1, 1.6 * u)
        for friend in friends {
            let level = Double(friend.floors + 1) * slabH
            let corner = pt(1, level, -1, leanY: Swift.min(level, towerTop))
            let y = Double(corner.y)
            if y <= ceiling || y >= H - 30 { continue }
            // It fades in under the app's buttons, flashes when passed and stays dim after that.
            var alpha = M.smooth(ceiling, ceiling + 34, y)
            var flash = 0.0
            if let since = friend.passedFor {
                flash = Swift.max(0, 1 - since / 0.9)
                alpha *= 0.42 + 0.58 * flash
            }

            let left = Swift.min(Double(corner.x) + 12 * u, W - 54 * u)
            let right = W - 12 * u
            var rule = Path()
            rule.move(to: CGPoint(x: left, y: y))
            rule.addLine(to: CGPoint(x: right, y: y))
            ctx.stroke(rule, with: .color(textShadow.color(0.35 * alpha)),
                       style: StrokeStyle(lineWidth: line + 1.6 * u, lineCap: .round, dash: dashes))
            ctx.stroke(rule, with: .color(.white.opacity(0.92 * alpha)),
                       style: StrokeStyle(lineWidth: line, lineCap: .round, dash: dashes))

            let r = (4.2 + 2.4 * flash) * u
            var gem = Path()
            gem.addLines([CGPoint(x: left - r * 1.5, y: y), CGPoint(x: left, y: y - r),
                          CGPoint(x: left + r * 1.5, y: y), CGPoint(x: left, y: y + r)])
            gem.closeSubpath()
            ctx.fill(gem, with: .color(.white.opacity(alpha)))

            let label = Text("\(String(friend.name.prefix(12))) \(friend.floors)")
                .font(.system(size: 12.5 * u, weight: .bold, design: .rounded))
            ctx.draw(label.foregroundColor(textShadow.color(0.45 * alpha)),
                     at: CGPoint(x: right, y: y + 6.4 * u), anchor: .topTrailing)
            ctx.draw(label.foregroundColor(Color.white.opacity(0.95 * alpha)),
                     at: CGPoint(x: right, y: y + 5 * u), anchor: .topTrailing)
        }
    }

    /// The one instruction, up until the first drop.
    func drawHint(_ ctx: inout GraphicsContext, _ words: String, alpha: Double, pulse: Double) {
        if alpha <= 0.01 { return }
        let strength = alpha * (0.78 + 0.22 * pulse)
        let text = Text(words).font(.system(size: 21 * u, weight: .heavy, design: .rounded)).kerning(0.6 * u)
        let x = W * 0.5
        let y = H * 0.815
        ctx.draw(text.foregroundColor(textShadow.color(0.42 * strength)), at: CGPoint(x: x, y: y + 2.2 * u), anchor: .center)
        ctx.draw(text.foregroundColor(Color.white.opacity(strength)), at: CGPoint(x: x, y: y), anchor: .center)
    }

    /// A short line under the score, where the best score usually sits.
    func drawNote(_ ctx: inout GraphicsContext, _ words: String, age: Double, length: Double) {
        let arrive = M.easeOut(M.clamp(age / 0.16))
        let alpha = arrive * (1 - M.smooth(length - 0.35, length, age))
        if alpha <= 0.01 { return }
        let size = 14.5 * u * (0.8 + 0.2 * arrive + 0.14 * exp(-9 * age))
        let text = Text(words).font(.system(size: size, weight: .heavy, design: .rounded)).kerning(0.5 * u)
        let x = W * 0.5
        let y = H * 0.183 + 56 * u
        ctx.draw(text.foregroundColor(textShadow.color(0.45 * alpha)), at: CGPoint(x: x, y: y + 1.8 * u), anchor: .center)
        ctx.draw(text.foregroundColor(Color.white.opacity(alpha)), at: CGPoint(x: x, y: y), anchor: .center)
    }
}

/// Paints the model as it is right now.
struct TippyTowerCanvas: View {
    let model: TippyTowerModel
    /// A new number every frame. The model is a class, so this is what makes SwiftUI repaint.
    var frame = 0

    var body: some View {
        Canvas(opaque: true, colorMode: .nonLinear, rendersAsynchronously: false) { context, size in
            if size.width <= 8 || size.height <= 8 { return }
            Self.paint(model, &context, size)
        }
    }

    static func paint(_ model: TippyTowerModel, _ ctx: inout GraphicsContext, _ size: CGSize) {
        typealias Model = TippyTowerModel
        typealias M = TippyTowerMath
        var live = TippyTowerLiveFrame()
        live.slabs = model.slabs
        live.pieces = model.pieces
        live.landAge = model.sinceLanding / Model.landUnit
        live.camLevel = model.cam
        live.sway = model.ambient / 0.9
        live.ambient = model.ambient
        live.score = model.floors
        if model.stage == .ending || model.stage == .finished {
            live.zoomOut = M.smooth(0.12, 0.95, model.endClock / Model.endLength)
        }
        if model.hasMover {
            let box = model.moverBox
            live.mover = TippyTowerMover(x0: box.x0, x1: box.x1, z0: box.z0, z1: box.z1, axis: model.axis,
                                         appear: M.smooth(0, Model.lockout, model.moverAge), dir: model.dir)
        }
        if model.note == nil, model.bestScore > 0 {
            live.bestText = "BEST \(Swift.max(model.bestScore, model.floors))"
        }

        let painter = TippyTowerPainter(size: size, live: live)
        painter.draw(&ctx)
        if !model.friends.isEmpty { painter.drawFriendLines(&ctx, model.friends) }
        if let note = model.note {
            painter.drawNote(&ctx, note, age: model.noteAge, length: Model.noteLength)
        }
        if model.stage == .ready {
            painter.drawHint(&ctx, "Tap to drop", alpha: 1, pulse: 0.5 + 0.5 * sin(model.ambient * 3.2))
        } else if model.stage == .playing, model.floors == 1, model.sinceLanding < 0.3 {
            painter.drawHint(&ctx, "Tap to drop", alpha: 1 - model.sinceLanding / 0.3, pulse: 1)
        }
    }
}

// MARK: - Scripted player

/// Plays the round for recordings while GameDemo.autopilot is on.
///
/// It reads the model and answers one question a frame: tap now or not. The tap then goes through
/// the same call a finger uses. Its random numbers are its own, so the round the model deals is
/// the same with it or without it.
struct TippyTowerPilot {
    static let readyHold = 0.8          // how long the hint is left up before the first drop
    static let healthyWidth = 1.35      // it never cuts the slab narrower than this on purpose
    static let loseReaction = 0.4       // when losing, a new slab is held at least this long

    private var rng: TippyTowerRandom
    /// The slab count the current aim was picked for.
    private var aimedAt = -1
    /// Where to let go, as a model offset. 0 = lined up.
    private var aim = 0.0
    /// Clean drops still to come before the next slip.
    private var cleanLeft = 0
    /// Which drop of the opening is the one that is plainly off.
    private let slipDrop: Int

    init(seed: UInt64) {
        rng = TippyTowerRandom(seed: seed ^ 0x7069_6C6F_7421, salt: TippyTowerRandom.round)
        slipDrop = rng.int(5...6)
    }

    /// Call once per step, after the model has moved. True = tap now.
    mutating func wantsTap(_ model: TippyTowerModel, dt: Double) -> Bool {
        guard model.hasMover, model.moverAge >= TippyTowerModel.lockout else { return false }
        if model.stage == .ready, model.ambient < Self.readyHold { return false }
        let width = model.topWidth
        let travel = model.speed * dt

        if let limit = GameDemo.loseAfter, model.stage == .playing, model.time >= limit {
            // Lose the way a person does: hold on too long and let go with the slab clear of the tower.
            let out = abs(model.offset)
            let clear = width - TippyTowerModel.sliver + 0.01
            if out >= Swift.min(width + 0.16, TippyTowerModel.reach - 0.03) {
                return model.moverAge >= Self.loseReaction
            }
            // Already on its way back in: let go before it is over the tower again.
            return model.dir < 0 && model.offset > 0 && out >= clear && out - travel < clear
        }

        if aimedAt != model.slabs.count {
            aimedAt = model.slabs.count
            chooseAim(model, width: width)
        }
        // Let go on the frame nearest the aim. "ahead" is the distance still to go.
        let ahead = (aim - model.offset) * model.dir
        return ahead <= travel * 0.5 && ahead >= -(travel + 0.02)
    }

    private mutating func chooseAim(_ model: TippyTowerModel, width: Double) {
        let drop = model.floors + 1
        let side = rng.next() < 0.5 ? -1.0 : 1.0
        let clean = rng.range(-0.03, 0.03)      // inside the perfect window, so the slab snaps into line

        // The opening: a perfect streak, one drop that is plainly off, then a longer streak.
        if drop <= 11 {
            aim = drop == slipDrop ? side * rng.range(0.30, 0.38) : clean
            if drop == 11 { cleanLeft = rng.int(1...3) }
            return
        }

        // From then on: runs of clean drops, and now and then a slip, most of them small.
        if cleanLeft > 0 {
            cleanLeft -= 1
            aim = clean
            return
        }
        cleanLeft = rng.int(3...8)
        let small = model.tolerance + rng.range(0.05, 0.14)
        let big = model.tolerance + rng.range(0.18, 0.28)
        var slip = rng.next() < 0.25 ? big : small
        if width - slip < Self.healthyWidth { slip = small }
        // A narrow slab makes a careful player: no slip until it has grown back.
        aim = width - slip < Self.healthyWidth ? clean : side * slip
    }
}

// MARK: - Game view

/// Holds the round between frames. Nothing is published: the timeline repaints every frame anyway.
final class TippyTowerRunner: ObservableObject {
    let model: TippyTowerModel
    private let seed: UInt64
    private var lastDate: Date?
    private var frame = 0
    private var reported = false
    /// Made the first time it is needed, which is only when GameDemo.autopilot is on.
    private var pilot: TippyTowerPilot?

    init(options: GameOptions) {
        model = TippyTowerModel(options: options)
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
        // When frames are slow the model still covers real time, in several small steps.
        var owed = Swift.min(Swift.max(date.timeIntervalSince(before), 0), 0.1)
        if owed <= 0 { return frame }
        while owed > 1e-6 {
            let dt = Swift.min(owed, 1.0 / 60)
            owed -= dt
            model.step(dt: dt)
            settle(link)
            if GameDemo.autopilot {
                if pilot == nil { pilot = TippyTowerPilot(seed: seed) }
                if pilot?.wantsTap(model, dt: dt) == true { tap(link: link) }
            }
        }
        frame &+= 1
        return frame
    }

    func tap(link: GameLink) {
        if link.paused || link.isFinished { return }
        // A first touch that comes before the slab is over the tower is still felt.
        if !model.tap(), model.stage == .ready { GameHaptics.tap() }
        settle(link)
    }

    /// Plays the haptic the model owes and reports the round once it is over.
    private func settle(_ link: GameLink) {
        switch model.takeFeedback() {
        case .missed: GameHaptics.fail()
        case .good: GameHaptics.success()
        case .landed: GameHaptics.thud()
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

public struct TippyTowerGame: View {
    private let options: GameOptions
    private let link: GameLink

    public init(options: GameOptions, link: GameLink) {
        self.options = options
        self.link = link
    }

    public var body: some View {
        // A new link is a new round, so the round's state lives and dies with the link.
        TippyTowerRound(options: options, link: link)
            .id(ObjectIdentifier(link))
    }
}

private struct TippyTowerRound: View {
    @ObservedObject var link: GameLink
    @StateObject private var runner: TippyTowerRunner
    @GestureState private var touching = false

    init(options: GameOptions, link: GameLink) {
        self.link = link
        _runner = StateObject(wrappedValue: TippyTowerRunner(options: options))
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: link.paused)) { timeline in
            TippyTowerCanvas(model: runner.model, frame: runner.advance(to: timeline.date, link: link))
        }
        .contentShape(Rectangle())
        .gesture(
            // Fires as the finger lands, once per touch. The flag clears itself when the touch ends
            // or is cancelled.
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .updating($touching) { _, down, _ in
                    if down { return }
                    down = true
                    runner.tap(link: link)
                }
        )
        .ignoresSafeArea()
        .accessibilityElement()
        .accessibilityLabel("Tippy Tower. Tap to drop the slab.")
        .accessibilityAddTraits(.allowsDirectInteraction)
    }
}
