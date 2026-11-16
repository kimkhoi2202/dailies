import SwiftUI

// Can Cannon, playable.
//
// A shelf on a post holds a stack of cans or crates. The cannon sits at the bottom of the screen.
// Drag back to aim, let go to fire a heavy ball. Knock everything off the shelf with five balls to
// clear the level; the levels chain inside one round until a shelf is left standing.
//
// CanCannonLevels  the ten shelves.
// CanCannonModel   the rules of a round in plain Swift: a small solver for the pieces, the ball, scoring.
// CanCannonPilot   the scripted player. It runs while GameDemo.autopilot is on, and plays the clip.
// CanCannonRunner  keeps the clock, turns drags into aim, fires haptics, reports the result.
// CanCannonGame    the view the app shows. Everything is painted by CanCannonPainter (CanCannonScene.swift).
//
// The world is in shelf units: x to the right, y up from the top of the shelf, z away from the camera,
// measured from the middle of the shelf. A can is 0.86 wide and 1.2 tall.

// MARK: - Pieces

enum CanCannonKind {
    case can, crate, stone
}

enum CanCannonPose {
    case resting, falling, blasted, grounded, gone
}

struct CanCannonPiece {
    var kind: CanCannonKind
    /// The colour of a can's label. Crates and stone ignore it.
    var tint: Int
    var w: Double
    var h: Double
    var x: Double
    /// The centre.
    var y: Double
    var z: Double = 0
    var vx: Double = 0
    var vy: Double = 0
    var vz: Double = 0
    var angle: Double = 0
    var spin: Double = 0
    var pose: CanCannonPose = .resting
    /// It has left the shelf and been scored.
    var counted = false
    /// A can on its side keeps rolling.
    var rolling = false
    var age: Double = 0
    /// Painter only: how far it was turned from the angle it settled at when it landed.
    var tilt: Double = 0
    /// Painter only: when it drops in as the level opens.
    var delay: Double = 0

    init(kind: CanCannonKind, tint: Int, w: Double, h: Double, x: Double, bottom: Double) {
        self.kind = kind
        self.tint = tint
        self.w = w
        self.h = h
        self.x = x
        self.y = bottom + h / 2
    }

    /// Half the width of the box around it at its current angle.
    var halfW: Double {
        let s = abs(sin(angle))
        let c = abs(cos(angle))
        return s * h / 2 + c * w / 2
    }

    /// Half the height of the box around it at its current angle.
    var halfH: Double {
        let s = abs(sin(angle))
        let c = abs(cos(angle))
        return s * w / 2 + c * h / 2
    }
}

struct CanCannonPlank {
    var x: Double
    var half: Double
}

// MARK: - Levels

enum CanCannonLevels {
    static let count = 10
    /// Shots for three stars on each level.
    static let par: [Int] = [1, 2, 2, 2, 2, 2, 2, 3, 3, 3]

    static let canW = 0.86
    static let canH = 1.2
    static let canPitch = 0.92

    /// Lays out one level. The random numbers only pick a mirror image and a variant.
    static func build(_ index: Int, hue: Int, rng: inout CanCannonRandom,
                      pieces: inout [CanCannonPiece], planks: inout [CanCannonPlank]) {
        pieces.removeAll(keepingCapacity: true)
        planks.removeAll(keepingCapacity: true)
        let mirror: Double = rng.next() < 0.5 ? -1 : 1
        let variant = rng.next() < 0.5
        let a = hue % 6
        let b = (hue + 2) % 6
        let c = (hue + 4) % 6

        switch index {
        case 0:
            pyramid(&pieces, rows: 3, x: 0, base: 0, tint: a)
            planks.append(CanCannonPlank(x: 0, half: 2.0))
        case 1:
            pyramid(&pieces, rows: 4, x: 0, base: 0, tint: b)
            planks.append(CanCannonPlank(x: 0, half: 2.4))
        case 2:
            if variant {
                wall(&pieces, cols: 4, rows: 3, x: 0, base: 0, tint: c)
            } else {
                wall(&pieces, cols: 3, rows: 3, x: 0, base: 0, tint: c)
                wall(&pieces, cols: 1, rows: 1, x: 0, base: 3 * canH, tint: a)
            }
            planks.append(CanCannonPlank(x: 0, half: 2.4))
        case 3:
            pyramid(&pieces, rows: 3, x: -2.55, base: 0, tint: a)
            pyramid(&pieces, rows: 3, x: 2.55, base: 0, tint: b)
            planks.append(CanCannonPlank(x: -2.55, half: 1.75))
            planks.append(CanCannonPlank(x: 2.55, half: 1.75))
        case 4:
            pyramid(&pieces, rows: 5, x: 0, base: 0, tint: b)
            planks.append(CanCannonPlank(x: 0, half: 2.9))
        case 5:
            giraffe(&pieces, x: 0, scale: 1, mirror: mirror, kind: variant ? .crate : .stone)
            planks.append(CanCannonPlank(x: 0, half: 2.1))
        case 6:
            if variant {
                wall(&pieces, cols: 3, rows: 5, x: 0, base: 0, tint: c)
            } else {
                wall(&pieces, cols: 1, rows: 4, x: -0.95, base: 0, tint: c)
                wall(&pieces, cols: 1, rows: 4, x: 0.95, base: 0, tint: c)
                pieces.append(CanCannonPiece(kind: .crate, tint: 0, w: 2.8, h: 0.6, x: 0, bottom: 4 * canH))
                pyramid(&pieces, rows: 2, x: 0, base: 4 * canH + 0.6, tint: a)
            }
            planks.append(CanCannonPlank(x: 0, half: 2.0))
        case 7:
            giraffe(&pieces, x: -2.55 * mirror, scale: 0.8, mirror: mirror, kind: .crate)
            pyramid(&pieces, rows: 3, x: 2.55 * mirror, base: 0, tint: b)
            planks.append(CanCannonPlank(x: -2.55, half: 1.8))
            planks.append(CanCannonPlank(x: 2.55, half: 1.8))
        case 8:
            pyramid(&pieces, rows: 6, x: 0, base: 0, tint: c)
            planks.append(CanCannonPlank(x: 0, half: 3.2))
        default:
            let bw = 1.1
            let bh = 0.9
            for row in 0..<2 {
                for col in 0..<5 {
                    pieces.append(CanCannonPiece(kind: row == 0 ? .stone : .crate, tint: 0, w: bw - 0.04, h: bh,
                                                 x: -2.2 + Double(col) * bw, bottom: Double(row) * bh))
                }
            }
            pyramid(&pieces, rows: 4, x: 0, base: 2 * bh, tint: a)
            planks.append(CanCannonPlank(x: 0, half: 3.2))
        }

        // Lower pieces drop in first.
        for k in pieces.indices {
            let bottom = pieces[k].y - pieces[k].h / 2
            pieces[k].delay = bottom * 0.045 + abs(pieces[k].x) * 0.012
        }
    }

    private static func pyramid(_ list: inout [CanCannonPiece], rows: Int, x: Double, base: Double, tint: Int) {
        for row in 0..<rows {
            let count = rows - row
            let first = x - Double(count - 1) * canPitch / 2
            for col in 0..<count {
                list.append(CanCannonPiece(kind: .can, tint: tint, w: canW, h: canH,
                                           x: first + Double(col) * canPitch, bottom: base + Double(row) * canH))
            }
        }
    }

    private static func wall(_ list: inout [CanCannonPiece], cols: Int, rows: Int, x: Double, base: Double, tint: Int) {
        let first = x - Double(cols - 1) * canPitch / 2
        for row in 0..<rows {
            for col in 0..<cols {
                list.append(CanCannonPiece(kind: .can, tint: tint, w: canW, h: canH,
                                           x: first + Double(col) * canPitch, bottom: base + Double(row) * canH))
            }
        }
    }

    /// Four legs, a body, a long neck and a head, in blocks. Each block is x, bottom, width, height.
    private static let giraffeBlocks: [[Double]] = [
        [-0.9, 0, 0.8, 0.8], [0.9, 0, 0.8, 0.8], [-0.9, 0.8, 0.8, 0.8], [0.9, 0.8, 0.8, 0.8],
        [0, 1.6, 2.6, 0.8],
        [0.8, 2.4, 1.0, 0.8], [0.8, 3.2, 0.8, 0.8], [0.8, 4.0, 0.8, 0.8], [0.8, 4.8, 0.8, 0.8],
        [1.1, 5.6, 1.6, 0.7],
    ]

    private static func giraffe(_ list: inout [CanCannonPiece], x: Double, scale s: Double, mirror m: Double,
                                kind: CanCannonKind) {
        for block in giraffeBlocks {
            list.append(CanCannonPiece(kind: kind, tint: 0, w: block[2] * s, h: block[3] * s,
                                       x: x + m * block[0] * s, bottom: block[1] * s))
        }
    }
}

// MARK: - Model

/// Things that happened since the runner last asked. It turns them into haptics.
struct CanCannonNews: OptionSet {
    let rawValue: Int
    static let fired = CanCannonNews(rawValue: 1)
    static let impact = CanCannonNews(rawValue: 2)
    static let plank = CanCannonNews(rawValue: 4)
    static let missed = CanCannonNews(rawValue: 8)
    static let rattle = CanCannonNews(rawValue: 16)
    static let cleared = CanCannonNews(rawValue: 32)
    static let failed = CanCannonNews(rawValue: 64)
    static let passed = CanCannonNews(rawValue: 128)
}

final class CanCannonModel {
    enum Stage { case playing, cleared, ending, finished }
    enum Banner { case none, smashed, outOfBalls, allClear }

    struct Friend {
        let name: String
        let score: Int
        /// Seconds since the player went past. nil until then.
        var passedFor: Double?
    }

    struct Ball {
        var active = false
        /// 0 on its way to the shelf, 1 knocked away after a hit, 2 sailing past.
        var mode = 0
        var t: Double = 0
        var length: Double = 0.5
        var tx: Double = 0
        var ty: Double = 0
        var x: Double = 0
        var y: Double = 0
        var z: Double = 0
        var vx: Double = 0
        var vy: Double = 0
        var vz: Double = 0
        var age: Double = 0
    }

    /// A chip of a piece, a puff of dust or sand. World units.
    struct Shard {
        var x: Double = 0
        var y: Double = 0
        var z: Double = 0
        var vx: Double = 0
        var vy: Double = 0
        var vz: Double = 0
        var angle: Double = 0
        var spin: Double = 0
        var size: Double = 0
        var life: Double = 0
        var span: Double = 1
        /// 0...5 a can colour, 10 wood, 11 stone, 20 sand, 21 dust.
        var colour = 0
    }

    /// "+10" over a piece that left the shelf.
    struct Popup {
        var x: Double = 0
        var y: Double = 0
        var z: Double = 0
        var age: Double = 0
        var life: Double = 0
        var text = ""
    }

    /// Confetti, in fractions of the screen.
    struct Confetto {
        var x: Double = 0
        var y: Double = 0
        var vx: Double = 0
        var vy: Double = 0
        var angle: Double = 0
        var spin: Double = 0
        var life: Double = 0
        var colour = 0
    }

    // Tuning. Lengths in shelf units, times in seconds.
    static let ballsPerLevel = 5
    static let pointsPerPiece = 10
    static let pointsPerBall = 50
    static let gravity = 30.0
    static let ballR = 0.6
    static let nudgeReach = 1.0
    static let shelfDepth = 0.55
    static let groundY = -2.3
    static let plankThick = 0.32
    static let touch = 0.05
    static let overlap = 0.04
    static let margin = 0.03
    static let slideX = 6.0
    static let slideZ = 4.5
    static let roll = 1.2
    static let kickFrom = 4.0
    static let kick = 0.45
    static let toppleSpeed = 1.1
    static let toppleSpin = 3.2
    /// The shelf's distance from the camera, and where the ball leaves the cannon.
    static let shelfZ = 12.0
    static let muzzleZ = 7.0
    static let muzzleY = 0.4
    /// Where the aim sits before the finger has pulled back.
    static let aimBase = 0.2
    static let substep = 1.0 / 120
    static let introLength = 0.55
    static let bannerLength = 1.7
    static let endLength = 1.7
    static let quietBeforeFail = 0.7
    static let noteLength = 1.9

    let solo: Bool
    let bestScore: Int
    private let hue: Int
    private var rng: CanCannonRandom
    private var fx: CanCannonRandom

    private(set) var stage = Stage.playing
    private(set) var level = 0
    private(set) var pieces: [CanCannonPiece] = []
    private(set) var planks: [CanCannonPlank] = []
    private(set) var ball = Ball()
    private(set) var balls = CanCannonModel.ballsPerLevel
    /// Shots on this level, and in the round.
    private(set) var shots = 0
    private(set) var shotsTotal = 0
    private(set) var score = 0
    private(set) var shownScore: Double = 0
    private(set) var sinceScore: Double = 100
    private(set) var levelsCleared = 0
    private(set) var stars = 0
    /// One gold for each star.
    var gold: Int { stars }
    private(set) var levelStars = 0
    private(set) var praise = ""
    private(set) var ballPoints = 0
    private(set) var banner = Banner.none
    private(set) var bannerAge: Double = 0
    private(set) var aiming = false
    private(set) var aimX: Double = 0
    private(set) var aimY: Double = CanCannonModel.aimBase
    /// 1 right after an impact, easing to 0.
    private(set) var shake: Double = 0
    private(set) var sinceFire: Double = 100
    private(set) var levelAge: Double = 0
    /// Round clock. Holds while paused.
    private(set) var time: Double = 0
    /// Scenery clock.
    private(set) var ambient: Double = 0
    private(set) var endClock: Double = 0
    private(set) var friends: [Friend] = []
    private(set) var note: String?
    private(set) var noteAge: Double = 0
    private(set) var shards: [Shard]
    private(set) var popups: [Popup]
    private(set) var confetti: [Confetto]

    private var shardCursor = 0
    private var popupCursor = 0
    private var confettoCursor = 0
    private var dirty = true
    private var quiet: Double = 0
    private var sinceRattle: Double = 100
    private var carry: Double = 0
    private var owed = CanCannonNews()

    init(options: GameOptions, startLevel: Int = 0, startScore: Int = 0) {
        solo = options.solo
        bestScore = Swift.max(0, options.bestScore)
        hue = Int(options.seed % 6)
        rng = CanCannonRandom(seed: options.seed, salt: CanCannonRandom.round)
        fx = CanCannonRandom(seed: options.seed, salt: CanCannonRandom.scenery)
        shards = Array(repeating: Shard(), count: 64)
        popups = Array(repeating: Popup(), count: 24)
        confetti = Array(repeating: Confetto(), count: 80)
        pieces.reserveCapacity(48)
        planks.reserveCapacity(2)
        score = startScore
        shownScore = Double(startScore)

        if !options.solo {
            let names = Array(options.friendNames.filter { !$0.isEmpty }.prefix(3))
            let bands: [ClosedRange<Int>]
            switch names.count {
            case 3: bands = [200...600, 601...1100, 1101...1700]
            case 2: bands = [250...800, 801...1500]
            default: bands = [300...1400]
            }
            var order = Array(bands.indices)
            var last = order.count - 1
            while last > 0 {
                order.swapAt(last, fx.int(0...last))
                last -= 1
            }
            for (k, name) in names.enumerated() {
                friends.append(Friend(name: name, score: fx.int(bands[order[k]]), passedFor: nil))
            }
        }
        begin(level: Swift.min(Swift.max(startLevel, 0), CanCannonLevels.count - 1))
    }

    // MARK: Reading

    /// Pieces still on a shelf: standing there, or falling but not yet below it.
    var onShelf: Int {
        var n = 0
        for p in pieces where p.pose == .resting || (p.pose == .falling && !p.counted) { n += 1 }
        return n
    }

    var isMoving: Bool {
        if ball.active { return true }
        for p in pieces {
            if p.pose == .falling { return true }
            if p.pose == .resting && (p.vx != 0 || p.vz != 0) { return true }
        }
        return false
    }

    var ballFlying: Bool { ball.active && ball.mode == 0 }

    var canFire: Bool {
        stage == .playing && balls > 0 && levelAge >= Self.introLength && !ballFlying
    }

    var par: Int { CanCannonLevels.par[Swift.min(level, CanCannonLevels.par.count - 1)] }

    /// How high the ball climbs above the straight line to its target.
    static func arc(_ ty: Double) -> Double { 1.0 + 0.22 * Swift.max(0, ty - muzzleY) }

    /// The ball's flight: u = 0 at the cannon, 1 at the shelf, beyond 1 when it sails past.
    static func path(_ u: Double, tx: Double, ty: Double) -> (x: Double, y: Double, z: Double) {
        let lift = arc(ty) * 4 * u * (1 - u)
        let y = muzzleY + (ty - muzzleY) * u + lift
        let z = muzzleZ + (shelfZ - muzzleZ) * u
        return (tx * u, y, z)
    }

    /// Hands over what happened since the last call.
    func takeNews() -> CanCannonNews {
        let news = owed
        owed = []
        return news
    }

    // MARK: Input

    func setAim(x: Double, y: Double) {
        guard stage == .playing else { return }
        aimX = CanCannonMath.clamp(x, -5.5, 5.5)
        aimY = CanCannonMath.clamp(y, -0.9, 10)
        aiming = true
    }

    func clearAim() {
        aiming = false
    }

    /// Fires at the current aim. False when there was nothing to fire or it was not the moment.
    @discardableResult
    func fire() -> Bool {
        guard aiming, canFire else { return false }
        var shot = Ball()
        shot.active = true
        shot.mode = 0
        shot.tx = aimX
        shot.ty = aimY
        shot.length = 0.42 + 0.02 * (aimX * aimX + aimY * aimY).squareRoot()
        shot.x = 0
        shot.y = Self.muzzleY
        shot.z = Self.muzzleZ
        ball = shot
        balls -= 1
        shots += 1
        shotsTotal += 1
        aiming = false
        sinceFire = 0
        owe(.fired)
        return true
    }

    // MARK: Clock

    func step(dt raw: Double) {
        let dt = Swift.min(Swift.max(raw, 0), 0.05)
        if dt <= 0 { return }
        ambient += dt
        if stage == .finished { return }

        sinceScore = Swift.min(sinceScore + dt, 100)
        sinceFire = Swift.min(sinceFire + dt, 100)
        shake *= exp(-6 * dt)
        if shake < 0.01 { shake = 0 }
        let gap = Double(score) - shownScore
        shownScore = abs(gap) < 0.5 ? Double(score) : shownScore + gap * (1 - exp(-12 * dt))
        if note != nil {
            noteAge += dt
            if noteAge >= Self.noteLength { note = nil }
        }
        for k in friends.indices {
            if let since = friends[k].passedFor { friends[k].passedFor = Swift.min(since + dt, 100) }
        }
        effects(dt)

        carry += dt
        while carry >= Self.substep - 1e-9 {
            carry -= Self.substep
            tick(Self.substep)
            if stage == .finished { break }
        }
    }

    private func tick(_ dt: Double) {
        time += dt
        levelAge += dt
        sinceRattle = Swift.min(sinceRattle + dt, 100)
        physics(dt)

        switch stage {
        case .playing:
            if onShelf == 0 {
                clearLevel()
            } else if balls == 0 && !isMoving {
                quiet += dt
                if quiet >= Self.quietBeforeFail { fail() }
            } else {
                quiet = 0
            }
        case .cleared:
            bannerAge += dt
            if bannerAge >= Self.bannerLength {
                if level + 1 >= CanCannonLevels.count {
                    stage = .ending
                    banner = .allClear
                    bannerAge = 0
                    endClock = 0
                } else {
                    begin(level: level + 1)
                }
            }
        case .ending:
            bannerAge += dt
            endClock += dt
            if endClock >= Self.endLength { stage = .finished }
        case .finished:
            break
        }
    }

    // MARK: Rules

    private func begin(level index: Int) {
        level = index
        CanCannonLevels.build(index, hue: hue, rng: &rng, pieces: &pieces, planks: &planks)
        balls = Self.ballsPerLevel
        shots = 0
        levelAge = 0
        stage = .playing
        banner = .none
        bannerAge = 0
        ball = Ball()
        aiming = false
        aimX = 0
        aimY = Self.aimBase
        dirty = true
        quiet = 0
    }

    private func clearLevel() {
        levelsCleared += 1
        let target = par
        levelStars = shots <= target ? 3 : (shots <= target + 1 ? 2 : 1)
        stars += levelStars
        praise = shots == 1 ? "Perfect" : (levelStars == 3 ? "Great" : "Nice")
        ballPoints = balls * Self.pointsPerBall
        if ballPoints > 0 { addScore(ballPoints) }
        stage = .cleared
        banner = .smashed
        bannerAge = 0
        aiming = false
        spawnConfetti()
        owe(.cleared)
    }

    private func fail() {
        stage = .ending
        banner = .outOfBalls
        bannerAge = 0
        endClock = 0
        aiming = false
        owe(.failed)
    }

    private func addScore(_ points: Int) {
        score += points
        sinceScore = 0
        for k in friends.indices where friends[k].passedFor == nil && score > friends[k].score {
            friends[k].passedFor = 0
            note = "Passed \(friends[k].name)"
            noteAge = 0
            owe(.passed)
        }
    }

    private func count(_ p: inout CanCannonPiece) {
        if p.counted { return }
        p.counted = true
        addScore(Self.pointsPerPiece)
        var popup = Popup()
        popup.x = p.x
        popup.y = p.y + p.halfH + fx.range(0, 0.6)
        popup.z = Swift.min(p.z, 1.5)
        popup.life = 0.8
        popup.text = "+\(Self.pointsPerPiece)"
        popups[popupCursor] = popup
        popupCursor = (popupCursor + 1) % popups.count
        if sinceRattle > 0.07 {
            owe(.rattle)
            sinceRattle = 0
        }
    }

    private func owe(_ news: CanCannonNews) {
        owed.formUnion(news)
    }

    // MARK: Physics

    private func physics(_ dt: Double) {
        if ball.active { advanceBall(dt) }

        for i in pieces.indices {
            var p = pieces[i]
            p.age += dt
            switch p.pose {
            case .resting:
                if p.vx != 0 || p.vz != 0 {
                    p.x += p.vx * dt
                    p.z += p.vz * dt
                    p.vx = Self.towardZero(p.vx, (p.rolling ? Self.roll : Self.slideX) * dt)
                    p.vz = Self.towardZero(p.vz, Self.slideZ * dt)
                    dirty = true
                }
            case .falling, .blasted:
                let prevBottom = p.y - p.halfH
                p.vy -= Self.gravity * dt
                p.x += p.vx * dt
                p.y += p.vy * dt
                p.z += p.vz * dt
                p.angle += p.spin * dt
                if p.pose == .blasted {
                    if p.age > 1.4 { p.pose = .gone }
                } else {
                    let bottom = p.y - p.halfH
                    if !p.counted && bottom < -0.1 { count(&p) }
                    if p.vy < 0 { land(&p, index: i, prevBottom: prevBottom, bottom: bottom) }
                }
            case .grounded:
                if p.age > 2.5 { p.pose = .gone }
            case .gone:
                break
            }
            pieces[i] = p
        }

        if dirty {
            dirty = false
            supportPass()
        }
    }

    /// A falling piece meets the highest surface under its middle: another piece, a shelf, or the sand.
    private func land(_ p: inout CanCannonPiece, index: Int, prevBottom: Double, bottom: Double) {
        var surface = Self.groundY
        var kind = 0
        var supportX = p.x
        if abs(p.z) <= Self.shelfDepth && prevBottom >= -0.02 {
            for plank in planks where abs(p.x - plank.x) <= plank.half && 0 > surface {
                surface = 0
                kind = 1
                supportX = plank.x
            }
        }
        for j in pieces.indices where j != index {
            let q = pieces[j]
            if q.pose != .resting { continue }
            let top = q.y + q.halfH
            if top > prevBottom + 0.02 || top <= surface { continue }
            if abs(p.x - q.x) <= q.halfW && abs(p.z - q.z) < Self.shelfDepth {
                surface = top
                kind = 2
                supportX = q.x
            }
        }
        if bottom > surface { return }

        let hitSpeed = -p.vy
        let quarter = Double.pi / 2
        let turns = (p.angle / quarter).rounded()
        let before = p.angle
        p.angle = turns * quarter
        p.tilt = before - p.angle
        p.y = surface + p.halfH
        p.vy = 0
        p.spin = 0
        p.age = 0
        if kind == 0 {
            p.pose = .grounded
            p.vx = 0
            p.vz = 0
            return
        }
        p.pose = .resting
        let lying = Int(abs(turns)) % 2 == 1
        p.rolling = p.kind == .can && lying
        let dir: Double
        if abs(p.vx) > 0.1 {
            dir = p.vx > 0 ? 1 : -1
        } else {
            dir = p.x >= supportX ? 1 : -1
        }
        if p.rolling {
            p.vx = dir * Swift.max(abs(p.vx), 0.25 * hitSpeed, 0.6)
            p.vz *= 0.5
        } else if kind == 1 {
            p.vx *= 0.35
            p.vz *= 0.5
        } else {
            p.vx = 0
            p.vz = 0
        }
        if hitSpeed > Self.kickFrom { p.vx += dir * (hitSpeed - Self.kickFrom) * Self.kick }
        dirty = true
    }

    /// Every resting piece whose middle is no longer over what holds it starts to fall, tipping
    /// toward the open side when something still holds part of it.
    private func supportPass() {
        for i in pieces.indices where pieces[i].pose == .resting {
            let side = support(i)
            if side == 2 { continue }
            pieces[i].pose = .falling
            pieces[i].rolling = false
            pieces[i].age = 0
            pieces[i].vy = 0
            if side != 0 {
                pieces[i].vx = Double(side) * Self.toppleSpeed
                pieces[i].spin = -Double(side) * Self.toppleSpin
            }
            dirty = true
        }
    }

    /// 2 held, 0 nothing under it, -1 or 1 the side it tips to.
    private func support(_ i: Int) -> Int {
        let p = pieces[i]
        let ew = p.halfW
        let eh = p.halfH
        let bottom = p.y - eh
        let left = p.x - ew
        let right = p.x + ew
        var lo = Double.infinity
        var hi = -Double.infinity
        if abs(bottom) < Self.touch && abs(p.z) <= Self.shelfDepth {
            for plank in planks {
                let a = Swift.max(left, plank.x - plank.half)
                let b = Swift.min(right, plank.x + plank.half)
                if b - a > Self.overlap {
                    lo = Swift.min(lo, a)
                    hi = Swift.max(hi, b)
                }
            }
        }
        for j in pieces.indices where j != i {
            let q = pieces[j]
            if q.pose != .resting { continue }
            let qw = q.halfW
            let qh = q.halfH
            if abs(q.y + qh - bottom) >= Self.touch || abs(q.z - p.z) >= Self.shelfDepth { continue }
            let a = Swift.max(left, q.x - qw)
            let b = Swift.min(right, q.x + qw)
            if b - a > Self.overlap {
                lo = Swift.min(lo, a)
                hi = Swift.max(hi, b)
            }
        }
        if lo > hi { return 0 }
        if p.x < lo - Self.margin { return -1 }
        if p.x > hi + Self.margin { return 1 }
        return 2
    }

    private func advanceBall(_ dt: Double) {
        ball.t += dt
        if ball.mode == 0 {
            if ball.t >= ball.length {
                ball.x = ball.tx
                ball.y = ball.ty
                ball.z = Self.shelfZ
                impact()
            } else {
                let at = Self.path(ball.t / ball.length, tx: ball.tx, ty: ball.ty)
                ball.x = at.x
                ball.y = at.y
                ball.z = at.z
            }
            return
        }
        ball.age += dt
        let wasAbove = ball.y > Self.groundY
        if ball.mode == 1 {
            ball.vy -= Self.gravity * dt
            ball.x += ball.vx * dt
            ball.y += ball.vy * dt
            ball.z += ball.vz * dt
        } else {
            let at = Self.path(ball.t / ball.length, tx: ball.tx, ty: ball.ty)
            ball.x = at.x
            ball.y = at.y
            ball.z = at.z
        }
        if ball.y <= Self.groundY {
            if wasAbove { puff(x: ball.x, y: Self.groundY, z: ball.z - Self.shelfZ, colour: 20, count: 6) }
            ball.y = Self.groundY
            ball.mode = 1
            ball.vy = 0
            ball.vx = 0
            ball.vz = 0
        }
        if ball.age > 0.6 { ball.active = false }
    }

    private func impact() {
        let ex = ball.tx
        let ey = ball.ty
        let reach = Self.ballR + Self.nudgeReach
        var hit = false
        for i in pieces.indices {
            var p = pieces[i]
            if p.pose != .resting && p.pose != .falling { continue }
            if p.z > 0.9 { continue }
            let dx = Swift.max(0, abs(ex - p.x) - p.halfW)
            let dy = Swift.max(0, abs(ey - p.y) - p.halfH)
            let d = (dx * dx + dy * dy).squareRoot()
            if d <= Self.ballR {
                hit = true
                p.pose = .blasted
                p.age = 0
                p.rolling = false
                let side: Double = p.x >= ex ? 1 : -1
                p.vx = (p.x - ex) * 2.2 + side * rng.range(0.2, 1.2)
                p.vy = rng.range(3, 6) + (p.y - ey) * 1.2
                p.vz = rng.range(6.5, 9)
                let turn = rng.range(5, 10)
                p.spin = rng.next() < 0.5 ? -turn : turn
                count(&p)
                chips(from: p, ex: ex)
            } else if d <= reach {
                let k = 1 - d / reach
                p.vz += 0.8 + 3.2 * k
                let push: Double = p.x >= ex ? 1 : -1
                p.vx += push * 0.8 * k
            }
            pieces[i] = p
        }

        ball.mode = 1
        ball.age = 0
        if hit {
            dirty = true
            shake = 1
            ball.vx = 0
            ball.vy = 2
            ball.vz = 3
            puff(x: ex, y: ey, z: -0.4, colour: 21, count: 7)
            owe(.impact)
            return
        }
        for plank in planks {
            let nearX = abs(ex - plank.x) <= plank.half + Self.ballR * 0.5
            let nearY = ey <= Self.ballR * 0.3 && ey >= -0.45 - Self.ballR * 0.5
            if !nearX || !nearY { continue }
            shake = 0.45
            ball.vx = 0
            ball.vy = 3
            ball.vz = -2.5
            puff(x: ex, y: ey, z: -0.6, colour: 10, count: 4)
            owe(.plank)
            return
        }
        ball.mode = 2
        owe(.missed)
    }

    private static func towardZero(_ v: Double, _ by: Double) -> Double {
        if v > 0 { return Swift.max(0, v - by) }
        return Swift.min(0, v + by)
    }

    // MARK: Effects

    private func chips(from p: CanCannonPiece, ex: Double) {
        let colour: Int
        switch p.kind {
        case .can: colour = p.tint
        case .crate: colour = 10
        case .stone: colour = 11
        }
        for _ in 0..<5 {
            var s = Shard()
            s.x = p.x + fx.range(-0.3, 0.3)
            s.y = p.y + fx.range(-0.3, 0.3)
            s.z = p.z - 0.3
            s.vx = (p.x - ex) * 2 + fx.range(-3, 3)
            s.vy = fx.range(2, 7)
            s.vz = fx.range(-2.5, 1.5)
            s.angle = fx.range(0, 6.28)
            s.spin = fx.range(-14, 14)
            s.size = fx.range(0.12, 0.26)
            s.life = fx.range(0.6, 1.0)
            s.span = s.life
            s.colour = colour
            shards[shardCursor] = s
            shardCursor = (shardCursor + 1) % shards.count
        }
    }

    /// Soft round puffs: dust where the ball hits, sand where it lands. z is from the shelf.
    private func puff(x: Double, y: Double, z: Double, colour: Int, count: Int) {
        for k in 0..<count {
            let a = Double(k) / Double(Swift.max(1, count)) * 6.283 + fx.range(-0.3, 0.3)
            var s = Shard()
            s.x = x
            s.y = y
            s.z = z
            s.vx = cos(a) * fx.range(1.5, 3.2)
            s.vy = abs(sin(a)) * fx.range(1.0, 2.6) + 0.6
            s.vz = 0
            s.size = fx.range(0.25, 0.45)
            s.life = fx.range(0.4, 0.65)
            s.span = s.life
            s.colour = colour
            shards[shardCursor] = s
            shardCursor = (shardCursor + 1) % shards.count
        }
    }

    private func spawnConfetti() {
        for _ in 0..<confetti.count {
            var c = Confetto()
            c.x = 0.5 + fx.range(-0.12, 0.12)
            c.y = 0.34 + fx.range(-0.03, 0.03)
            c.vx = fx.range(-0.62, 0.62)
            c.vy = fx.range(-1.25, -0.35)
            c.angle = fx.range(0, 6.28)
            c.spin = fx.range(-9, 9)
            c.life = fx.range(1.6, 2.4)
            c.colour = fx.int(0...5)
            confetti[confettoCursor] = c
            confettoCursor = (confettoCursor + 1) % confetti.count
        }
    }

    private func effects(_ dt: Double) {
        for k in shards.indices where shards[k].life > 0 {
            shards[k].life -= dt
            let puffy = shards[k].colour >= 20
            shards[k].vy -= (puffy ? 2.0 : 22.0) * dt
            if puffy {
                let drag = exp(-4 * dt)
                shards[k].vx *= drag
                shards[k].vy *= drag
            }
            shards[k].x += shards[k].vx * dt
            shards[k].y += shards[k].vy * dt
            shards[k].z += shards[k].vz * dt
            shards[k].angle += shards[k].spin * dt
        }
        for k in popups.indices where popups[k].life > 0 {
            popups[k].age += dt
            if popups[k].age >= popups[k].life { popups[k].life = 0 }
        }
        let drag = exp(-1.6 * dt)
        for k in confetti.indices where confetti[k].life > 0 {
            confetti[k].life -= dt
            confetti[k].vy += 1.15 * dt
            confetti[k].vx *= drag
            confetti[k].vy *= drag
            confetti[k].x += confetti[k].vx * dt
            confetti[k].y += confetti[k].vy * dt
            confetti[k].angle += confetti[k].spin * dt
        }
    }

    // MARK: Result

    var result: GameResult {
        let detail: String
        if levelsCleared >= CanCannonLevels.count {
            detail = "Cleared all \(CanCannonLevels.count) levels with \(stars) stars."
        } else if levelsCleared == 0 {
            detail = "Out of balls on level 1."
        } else {
            let levelWord = levelsCleared == 1 ? "level" : "levels"
            let starWord = stars == 1 ? "star" : "stars"
            detail = "Cleared \(levelsCleared) \(levelWord) with \(stars) \(starWord)."
        }
        if friends.isEmpty {
            return GameResult(score: score, unit: "points", detail: detail)
        }
        let ahead = friends.filter { $0.score > score }.count
        return GameResult(score: score, unit: "points", detail: detail,
                          placement: ahead + 1, playerCount: friends.count + 1)
    }
}

// MARK: - Scripted player

enum CanCannonPilotMove {
    case none
    case aim(Double, Double)
    case fire
}

/// Plays for recordings while GameDemo.autopilot is on, and plays the clip in the Videos feed.
///
/// It aims at the lowest piece that holds up the most, pulls back over half a second the way a
/// thumb does, and lets go. Its aim is a little off, now and then a lot. Its random numbers are
/// its own, so the round is the same with it or without it.
struct CanCannonPilot {
    private let firstWait: Double
    private let think: Double
    private let aimTime: Double
    private let hold: Double
    private let maxWait: Double
    /// The clip: dead on, never loses, quicker between shots.
    private let careful: Bool

    private var rng: CanCannonRandom
    private var aiming = false
    private var clock: Double = 0
    private var calm: Double = 0
    private var sinceShot: Double = 100
    private var goalX: Double = 0
    private var goalY: Double = 0
    /// Losing on purpose: shots come quickly so the round ends soon after GameDemo.loseAfter.
    private var hurried = false

    init(seed: UInt64, careful: Bool = false) {
        rng = CanCannonRandom(seed: seed ^ 0x70_696C_6F74, salt: 3)
        self.careful = careful
        if careful {
            firstWait = 0.6
            think = 0.2
            aimTime = 0.45
            hold = 0.12
            maxWait = 1.1
        } else {
            firstWait = 0.9
            think = 0.35
            aimTime = 0.55
            hold = 0.18
            maxWait = 1.8
        }
    }

    /// Call once per step, after the model has moved.
    mutating func next(_ model: CanCannonModel, dt: Double) -> CanCannonPilotMove {
        sinceShot += dt
        guard model.stage == .playing else {
            aiming = false
            calm = 0
            return .none
        }
        if !aiming {
            if !model.canFire {
                calm = 0
                return .none
            }
            calm = model.isMoving && sinceShot < maxWait ? 0 : calm + dt
            hurried = losing(model)
            let wait = model.shotsTotal == 0 ? firstWait : (hurried ? 0.1 : think)
            if calm < wait { return .none }
            guard chooseGoal(model) else { return .none }
            aiming = true
            clock = 0
        }
        clock += dt
        let reach = hurried ? 0.3 : aimTime
        let still = hurried ? 0.08 : hold
        if clock < reach {
            let k = CanCannonMath.easeOut(clock / reach)
            return .aim(goalX * k, CanCannonModel.aimBase + (goalY - CanCannonModel.aimBase) * k)
        }
        if clock < reach + still { return .aim(goalX, goalY) }
        aiming = false
        sinceShot = 0
        calm = 0
        return .fire
    }

    private func losing(_ model: CanCannonModel) -> Bool {
        guard !careful, let limit = GameDemo.loseAfter else { return false }
        return model.time >= limit
    }

    private mutating func chooseGoal(_ model: CanCannonModel) -> Bool {
        if losing(model) {
            // Losing on purpose: every ball sails wide of the shelves.
            let side: Double = rng.next() < 0.5 ? -1 : 1
            goalX = side * rng.range(5.0, 5.4)
            goalY = rng.range(1.5, 4.0)
            return true
        }
        guard let target = Self.target(model) else { return false }
        if careful {
            goalX = target.x
            goalY = target.y
            return true
        }
        let spread = rng.next() < 0.12 ? 0.7 : 0.18
        goalX = target.x + rng.range(-spread, spread)
        goalY = target.y + rng.range(-spread, spread)
        return true
    }

    /// The resting piece with the most pieces standing above it, nearer the middle on a tie.
    static func target(_ model: CanCannonModel) -> (x: Double, y: Double)? {
        let list = model.pieces
        var best = -1
        var bestScore = -1e9
        for i in list.indices {
            let p = list[i]
            if p.pose != .resting { continue }
            let ew = p.halfW
            var weight = 1.0
            for j in list.indices where j != i {
                let q = list[j]
                if q.pose != .resting || q.y <= p.y + 0.01 { continue }
                let qw = q.halfW
                if Swift.min(p.x + ew, q.x + qw) - Swift.max(p.x - ew, q.x - qw) > 0.05 { weight += 1 }
            }
            weight -= abs(p.x) * 0.05
            if weight > bestScore {
                bestScore = weight
                best = i
            }
        }
        if best < 0 {
            for i in list.indices where list[i].pose == .falling && !list[i].counted {
                best = i
                break
            }
        }
        if best < 0 { return nil }
        return (list[best].x, list[best].y)
    }
}

// MARK: - Game view

/// Holds the round between frames. Nothing is published: the timeline repaints every frame anyway.
final class CanCannonRunner: ObservableObject {
    /// Screen points of aim on the shelf for each screen point of pull.
    static let pullGain = 1.35
    /// A pull shorter than this is not a shot.
    static let minPull = 16.0

    let model: CanCannonModel
    private let seed: UInt64
    private var lastDate: Date?
    private var frame = 0
    private var reported = false
    private var pulling = false
    /// The view's size at the last drag, for turning the pull into aim when the finger lifts.
    private var lastSize = CGSize(width: 402, height: 874)
    /// Made the first time it is needed, which is only when GameDemo.autopilot is on.
    private var pilot: CanCannonPilot?

    init(options: GameOptions) {
        model = CanCannonModel(options: options)
        seed = options.seed
    }

    /// Brings the model up to the given date. Returns a number that changes when there is a new frame to paint.
    func advance(to date: Date, link: GameLink) -> Int {
        if link.paused {
            lastDate = nil
            if pulling || model.aiming {
                pulling = false
                model.clearAim()
            }
            return frame
        }
        defer { lastDate = date }
        guard let before = lastDate else { return frame }
        var owedTime = Swift.min(Swift.max(date.timeIntervalSince(before), 0), 0.1)
        if owedTime <= 0 { return frame }
        while owedTime > 1e-6 {
            let dt = Swift.min(owedTime, 1.0 / 60)
            owedTime -= dt
            model.step(dt: dt)
            if GameDemo.autopilot && !link.isFinished {
                if pilot == nil { pilot = CanCannonPilot(seed: seed) }
                if var driver = pilot {
                    let move = driver.next(model, dt: dt)
                    pilot = driver
                    switch move {
                    case .none:
                        break
                    case .aim(let x, let y):
                        model.setAim(x: x, y: y)
                    case .fire:
                        model.fire()
                    }
                }
            }
            settle(link)
        }
        frame &+= 1
        return frame
    }

    /// The finger has moved. Pulling down raises the aim, pulling left sends it right.
    func drag(from start: CGPoint, to point: CGPoint, size: CGSize, link: GameLink) {
        if link.paused || link.isFinished || GameDemo.autopilot { return }
        if model.stage != .playing { return }
        let dx = Double(point.x - start.x)
        let dy = Double(point.y - start.y)
        if !pulling {
            if (dx * dx + dy * dy).squareRoot() < 4 { return }
            pulling = true
            GameHaptics.tap()
        }
        lastSize = size
        aim(dx: dx, dy: dy)
    }

    private func aim(dx: Double, dy: Double) {
        let stage = CanCannonStage(size: lastSize)
        let x = -dx * Self.pullGain / stage.ppu
        let y = CanCannonModel.aimBase + dy * Self.pullGain / stage.ppu
        model.setAim(x: x, y: y)
    }

    /// The finger has lifted: fire if it pulled far enough. The aim is worked out again from the
    /// pull, so the shot does not depend on the order SwiftUI reports the end of the gesture in.
    func release(from start: CGPoint, to point: CGPoint, link: GameLink) {
        pulling = false
        if link.paused || link.isFinished || GameDemo.autopilot {
            if !GameDemo.autopilot { model.clearAim() }
            return
        }
        let dx = Double(point.x - start.x)
        let dy = Double(point.y - start.y)
        let far = (dx * dx + dy * dy).squareRoot() >= Self.minPull
        if far && model.stage == .playing { aim(dx: dx, dy: dy) }
        if !far || !model.fire() {
            model.clearAim()
        }
        settle(link)
    }

    /// The touch ended without a release, such as when the system took it. Drops the aim.
    func cancelDrag() {
        if GameDemo.autopilot { return }
        pulling = false
        model.clearAim()
    }

    /// Plays the haptics the model owes and reports the round once it is over.
    private func settle(_ link: GameLink) {
        let news = model.takeNews()
        if news.contains(.failed) {
            GameHaptics.fail()
        } else if news.contains(.cleared) {
            GameHaptics.heavy()
            GameHaptics.success()
        } else if news.contains(.impact) {
            GameHaptics.heavy()
        } else if news.contains(.passed) {
            GameHaptics.success()
        } else if news.contains(.plank) {
            GameHaptics.thud()
        } else if !news.isEmpty {
            GameHaptics.tap()
        }
        link.collect(model.gold)
        if model.stage == .finished, !reported {
            reported = true
            let result = model.result
            DispatchQueue.main.async { link.finish(result) }
        }
    }
}

public struct CanCannonGame: View {
    private let options: GameOptions
    private let link: GameLink

    public init(options: GameOptions, link: GameLink) {
        self.options = options
        self.link = link
    }

    public var body: some View {
        // A new link is a new round, so the round's state lives and dies with the link.
        CanCannonRound(options: options, link: link)
            .id(ObjectIdentifier(link))
    }
}

private struct CanCannonRound: View {
    @ObservedObject var link: GameLink
    @StateObject private var runner: CanCannonRunner
    /// True while a finger is down. It clears itself when the touch ends or the system cancels it.
    @GestureState private var dragging = false

    init(options: GameOptions, link: GameLink) {
        self.link = link
        _runner = StateObject(wrappedValue: CanCannonRunner(options: options))
    }

    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation(minimumInterval: nil, paused: link.paused)) { timeline in
                CanCannonCanvas(model: runner.model, frame: runner.advance(to: timeline.date, link: link))
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .updating($dragging) { _, state, _ in state = true }
                    .onChanged { value in
                        runner.drag(from: value.startLocation, to: value.location, size: proxy.size, link: link)
                    }
                    .onEnded { value in
                        runner.release(from: value.startLocation, to: value.location, link: link)
                    }
            )
            .onChange(of: dragging) { _, down in
                if !down { runner.cancelDrag() }
            }
        }
        .ignoresSafeArea()
        .accessibilityElement()
        .accessibilityLabel("Can Cannon. Drag back to aim, let go to fire.")
        .accessibilityAddTraits(.allowsDirectInteraction)
    }
}

/// Paints the model as it is right now.
struct CanCannonCanvas: View {
    let model: CanCannonModel
    /// A new number every frame. The model is a class, so this is what makes SwiftUI repaint.
    var frame = 0

    var body: some View {
        Canvas(opaque: true, colorMode: .nonLinear, rendersAsynchronously: false) { context, size in
            if size.width <= 8 || size.height <= 8 { return }
            CanCannonPainter(model: model, size: size, showHUD: true).draw(&context)
        }
    }
}
