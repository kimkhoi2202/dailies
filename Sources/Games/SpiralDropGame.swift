import SwiftUI

// Spiral Drop, playable.
//
// Round is the game itself in plain Swift: the ball, the tower and the score. Pilot plays a round by
// itself for recordings. Driver steps a round from the display clock, and SpiralDropGame turns drags
// into turns of the tower and shows every frame with the painter from SpiralDropScene.swift.

// MARK: - Round

extension SpiralDrop {
    final class Round {
        enum Stage { case ready, playing, ending, over }

        /// landed is the first touch on a floor, bounced every later one on the same floor.
        enum Event: Equatable { case landed, bounced, fell(Int), smashed(Int), levelUp, passedFriend, died }

        static let gravity = 8 * bounceHeight
        static let bounceSpeed = 4 * bounceHeight
        /// Upward speed of the small hop after smashing through a floor.
        static let hopSpeed = 2.3
        static let topSpeed = 10.5
        static let baseBounceSeconds = 0.62
        /// Tower degrees per scene unit of finger travel.
        static let degreesPerUnit = 0.6
        /// A landing this many degrees or less inside a red tile counts for the neighbour.
        static let hazardGrace = 5.0
        static let endingLength = 1.15
        /// With no touch for this long the floor under the ball starts to turn, so a round always ends.
        static let idleLimit = 9.0

        /// What the game knows about a floor beyond its picture.
        struct Plan {
            /// Degrees per second the floor turns on its own.
            var turnRate: Double
            var endsLevel: Bool
        }

        private struct Dab {
            var slot: Double
            var time: Double
            var power: Int
            var id: Int
        }

        let solo: Bool
        let friendName: String
        let friendScore: Int

        private(set) var stage = Stage.ready
        /// In bounces.
        private(set) var time = 0.0
        private(set) var seconds = 0.0
        private(set) var playSeconds = 0.0
        private(set) var sinceDeath = 0.0
        private(set) var score = 0
        private(set) var level = 1
        private(set) var bestChain = 0
        private(set) var passedFriend = false
        private var passedFriendAt = 0.0
        private var idle = 0.0
        private var events: [Event] = []

        // The tower.
        private(set) var turn: Double
        private(set) var floors: [Floor] = []
        private(set) var plans: [Plan] = []
        /// The floor number of the first entry in floors and plans.
        private(set) var firstFloor = 0
        /// The first floor that is still whole: the one the ball meets next.
        private(set) var next = 0
        private var levelStart = 0
        private var levelFloors: Int
        private var lastSkin = 0
        private var levelUpAt = -99.0

        // The ball.
        /// Height of its underside.
        private(set) var height: Double
        /// Floors per bounce, positive is down.
        private(set) var speed = 0.0
        private var camera = 0.0
        /// Floors fallen through since the ball last touched one. Two or more is a combo.
        private(set) var chain = 0
        private var fallStart: Double
        private(set) var restFloor = -1
        private var landings = 0
        private(set) var touchIndex = 0
        private var impact = 0
        private(set) var touchedAt = -99.0
        private var brokeAt = -99.0
        private var landedAt = -99.0
        private var landedChain = 0
        private var dabs: [Dab] = []
        private var dabCount = 0

        // The floor maker.
        private var dice: Dice
        private var laid = 0
        private var makeLevel = 1
        private var makePlace = 0
        /// The tiles the ball is expected to come down on.
        private var zoneStart = 0
        private var zoneWidth = 1
        private var lastWay = 1
        private var stackLeft = 0
        private var smashFloorNext = false

        init(seed: UInt64, solo: Bool, friendName: String) {
            self.solo = solo
            self.friendName = String(friendName.prefix(14))
            var pick = Dice(seed: seed &* 2654435761 &+ 97)
            friendScore = pointsPerFloor * Int(pick.between(50, 112))
            dice = Dice(seed: seed)
            levelFloors = Self.floorCount(level: 1)
            turn = ballAngle - 15            // the ball starts over the middle of tile 0
            height = -bounceHeight
            fallStart = -bounceHeight
            layFloors()
        }

        static func floorCount(level: Int) -> Int { min(12 + 2 * level, 24) }

        /// Seconds per bounce: a touch quicker each level.
        static func bounceSeconds(level: Int) -> Double {
            baseBounceSeconds / min(1.45, 1 + 0.03 * Double(level - 1))
        }

        var bounceSeconds: Double { Self.bounceSeconds(level: level) }

        var isAlive: Bool { stage == .ready || stage == .playing }

        var result: GameResult {
            var detail = "Level \(level)"
            if bestChain >= 2 { detail += ", best combo x\(bestChain)" }
            return GameResult(score: score, unit: "points", detail: detail,
                              placement: solo ? nil : (score > friendScore ? 1 : 2),
                              playerCount: solo ? nil : 2)
        }

        func takeEvents() -> [Event] {
            let out = events
            events.removeAll(keepingCapacity: true)
            return out
        }

        private func note(_ event: Event) {
            if events.count >= 32 { events.removeFirst() }
            events.append(event)
        }

        // MARK: Input

        /// The first touch starts the round.
        func touchDown() {
            guard isAlive else { return }
            stage = .playing
            idle = 0
        }

        /// Finger travel in scene units, positive to the right.
        func drag(by dx: Double) {
            guard isAlive else { return }
            stage = .playing
            turn -= dx * Self.degreesPerUnit
            if abs(dx) > 0.2 { idle = 0 }
        }

        // MARK: Questions

        /// Where the ball is over floor n, counted in that floor's own tiles (0 ..< 12).
        func slot(on n: Int) -> Double {
            let around = (ballAngle - turn - floors[n - firstFloor].twist) / 30
            let s = around.truncatingRemainder(dividingBy: 12)
            return s < 0 ? s + 12 : s
        }

        /// What a ball coming down at a slot (0 ..< 12) of floor n touches. Red is forgiving at its edges.
        func ground(on n: Int, at slot: Double) -> Tile {
            let tiles = floors[n - firstFloor].tiles
            let j = Int(slot) % 12
            guard tiles[j] == .hazard else { return tiles[j] }
            let into = (slot - Double(Int(slot))) * 30
            if into < Self.hazardGrace, tiles[(j + 11) % 12] != .hazard { return tiles[(j + 11) % 12] }
            if into > 30 - Self.hazardGrace, tiles[(j + 1) % 12] != .hazard { return tiles[(j + 1) % 12] }
            return .hazard
        }

        /// Bounces until the ball reaches the next floor.
        var bouncesToFloor: Double { Self.fallTime(distance: Double(next) - height, speed: speed) }

        private var isFalling: Bool {
            if chain >= 1 { return true }
            guard isAlive, speed > 0, !plans[next - firstFloor].endsLevel else { return false }
            return ground(on: next, at: slot(on: next)) == .hole
        }

        /// Bounces a ball moving at a speed needs to come down a distance. Gravity until top speed, then steady.
        static func fallTime(distance: Double, speed: Double) -> Double {
            let d = max(0, distance)
            if speed >= topSpeed { return d / topSpeed }
            let untilTop = (topSpeed - speed) / gravity
            let coveredByThen = speed * untilTop + 0.5 * gravity * untilTop * untilTop
            if coveredByThen >= d {
                return (-speed + max(0, speed * speed + 2 * gravity * d).squareRoot()) / gravity
            }
            return untilTop + (d - coveredByThen) / topSpeed
        }

        // MARK: Clock

        func step(dt: Double) {
            let dts = min(max(dt, 0), 1.0 / 30.0)
            guard dts > 0, stage != .over else { return }
            seconds += dts
            let bounces = dts / bounceSeconds
            time += bounces
            if stage == .ending {
                sinceDeath += dts
                if sinceDeath >= Self.endingLength { stage = .over }
                return
            }
            if stage == .playing {
                playSeconds += dts
                idle += dts
                let i = next - firstFloor
                if idle > Self.idleLimit, plans[i].turnRate == 0, !plans[i].endsLevel { plans[i].turnRate = 22 }
            }

            // floors that turn on their own
            let lastTurning = min(next + 5, firstFloor + floors.count - 1)
            if next <= lastTurning {
                for n in next...lastTurning where plans[n - firstFloor].turnRate != 0 {
                    floors[n - firstFloor].twist += plans[n - firstFloor].turnRate * dts
                }
            }

            // fly to the next floor, settle what happens there, and go on with what is left of the step
            var left = bounces
            var contacts = 0
            while left > 0, contacts < 16, stage != .ending {
                let reach = bouncesToFloor
                if reach > left {
                    fly(left)
                    break
                }
                fly(reach)
                height = Double(next)
                left -= reach
                contacts += 1
                meetFloor()
            }

            guard stage != .ending else { return }
            camera += (Double(next) - camera) * (1 - exp(-bounces * 5.5))
            camera = max(camera, height - 2.2)
        }

        private func fly(_ t: Double) {
            guard t > 0 else { return }
            let g = Self.gravity
            let top = Self.topSpeed
            let wasRising = speed < 0
            if speed >= top {
                height += top * t
            } else {
                let untilTop = (top - speed) / g
                let pull = min(t, untilTop)
                height += speed * pull + 0.5 * g * pull * pull
                if t <= untilTop {
                    speed += g * t
                } else {
                    height += top * (t - untilTop)
                    speed = top
                }
            }
            // the top of the arc is where this fall began
            if wasRising, speed >= 0 { fallStart = height - speed * speed / (2 * g) }
        }

        // MARK: Contacts

        private func meetFloor() {
            if plans[next - firstFloor].endsLevel {
                finishLevel()
                return
            }
            let under = ground(on: next, at: slot(on: next))
            if under == .hole {
                chain += 1
                if chain >= 2 { bestChain = max(bestChain, chain) }
                breakFloor(place: chain)
                note(.fell(chain))
            } else if chain >= 2 {
                smash()
            } else if under == .hazard {
                die()
            } else {
                bounce()
            }
        }

        /// The next floor breaks and scores.
        private func breakFloor(place: Int) {
            let i = next - firstFloor
            floors[i].brokenAt = time
            floors[i].chain = place
            floors[i].points = pointsPerFloor * place
            score += floors[i].points
            brokeAt = time
            next += 1
            layFloors()
            if !solo, !passedFriend, score > friendScore {
                passedFriend = true
                passedFriendAt = seconds
                note(.passedFriend)
            }
        }

        /// The ball arrives on a floor it has not touched before.
        private func arrive(on n: Int, power: Int) {
            restFloor = n
            landings += 1
            touchIndex = 0
            impact = power
            dabs.removeAll(keepingCapacity: true)
            dabCount = 0
            touchedAt = time
        }

        private func touchAgain(power: Int) {
            touchIndex += 1
            impact = power
            touchedAt = time
        }

        private func smash() {
            let n = next
            let place = chain + 1
            breakFloor(place: place)
            bestChain = max(bestChain, place)
            landedChain = place
            landedAt = time
            chain = 0
            speed = -Self.hopSpeed
            arrive(on: n, power: place)
            note(.smashed(place))
        }

        private func finishLevel() {
            let n = next
            let place = chain + 1
            breakFloor(place: place)
            if chain >= 2 {
                bestChain = max(bestChain, place)
                landedChain = place
                landedAt = time
            }
            lastSkin = (level - 1) % Palette.skins.count
            level += 1
            levelStart = next
            levelFloors = Self.floorCount(level: level)
            levelUpAt = time
            chain = 0
            speed = -Self.hopSpeed * 1.2
            arrive(on: n, power: max(3, place))
            note(.levelUp)
        }

        private func bounce() {
            speed = -Self.bounceSpeed
            chain = 0
            if restFloor != next {
                arrive(on: next, power: 1)
            } else {
                touchAgain(power: 0)
            }
            dab(power: impact)
            note(touchIndex == 0 ? .landed : .bounced)
        }

        private func die() {
            speed = 0
            chain = 0
            if restFloor != next {
                arrive(on: next, power: 4)
            } else {
                touchAgain(power: 4)
            }
            dab(power: 3)
            stage = .ending
            sinceDeath = 0
            note(.died)
        }

        private func dab(power: Int) {
            let at = slot(on: next)
            // a bounce on the same spot keeps its old paint, so it does not pile up
            if let i = dabs.firstIndex(where: { abs($0.slot - at) < 0.15 }) {
                dabs.append(dabs.remove(at: i))
                return
            }
            dabs.append(Dab(slot: at, time: time, power: power, id: dabCount))
            dabCount += 1
            if dabs.count > 6 { dabs.removeFirst() }
        }

        // MARK: Floors

        /// Keeps sixteen floors ready below the ball and drops the ones far above it.
        private func layFloors() {
            while laid < next + 16 { layFloor() }
            let above = next - firstFloor
            if above > 14 {
                floors.removeFirst(above - 8)
                plans.removeFirst(above - 8)
                firstFloor += above - 8
            }
        }

        private func holeWidth(_ hard: Double) -> Int {
            if laid < 3 { return 3 }
            if hard < 1 { return dice.unit() < 0.6 ? 3 : 2 }
            if hard < 2.5 { return dice.unit() < 0.25 ? 3 : 2 }
            return dice.unit() < min(0.45, 0.12 + 0.1 * (hard - 2.5)) ? 1 : 2
        }

        private func hazardCount(_ hard: Double) -> Int {
            if laid < 3 { return 0 }
            return min(7, max(1, Int((1.0 + 1.25 * hard + dice.between(-0.6, 0.6)).rounded())))
        }

        /// Turns some of the solid tiles at the given places red, in runs of one to three.
        private func scatter(_ count: Int, over places: [Int], in tiles: inout [Tile]) {
            guard count > 0, !places.isEmpty else { return }
            var left = min(count, places.count)
            var at = dice.index(below: places.count)
            for _ in 0..<24 where left > 0 {
                let run = min(left, 1 + dice.index(below: 3))
                for k in 0..<run {
                    let j = places[(at + k) % places.count]
                    if tiles[j] == .solid {
                        tiles[j] = .hazard
                        left -= 1
                    }
                }
                at += run + 1
            }
        }

        /// Makes sure no solid tile is cut off: from each one the ball can get to a hole by crossing at most
        /// reach - 1 red tiles at a time. Red in the way is turned solid.
        private func openWays(in tiles: inout [Tile], reach: Int) {
            let holes = (0..<12).filter { tiles[$0] == .hole }
            guard !holes.isEmpty else { return }
            for _ in 0..<12 {
                // hops from every solid tile to a hole
                var hops = [Int](repeating: 99, count: 12)
                for j in holes { hops[j] = 0 }
                var settled = false
                while !settled {
                    settled = true
                    for j in 0..<12 where tiles[j] == .solid {
                        for step in -reach...reach where hops[tile(j + step)] + 1 < hops[j] {
                            hops[j] = hops[tile(j + step)] + 1
                            settled = false
                        }
                    }
                }
                guard let stuck = (0..<12).first(where: { tiles[$0] == .solid && hops[$0] == 99 }) else { return }
                // clear the first red on the short way from there to a hole
                var way = 1
                var nearest = 99
                for hole in holes {
                    let ahead = tile(hole - stuck)
                    if ahead < nearest {
                        nearest = ahead
                        way = 1
                    }
                    if 12 - ahead < nearest {
                        nearest = 12 - ahead
                        way = -1
                    }
                }
                if let red = (1..<12).first(where: { tiles[tile(stuck + way * $0)] == .hazard }) {
                    tiles[tile(stuck + way * red)] = .solid
                }
            }
        }

        /// Adds the next floor. It gets harder with the level and with how far through the level it is.
        private func layFloor() {
            let count = Self.floorCount(level: makeLevel)
            let endsLevel = makePlace == count - 1
            let hard = 0.85 * (Double(makeLevel - 1) + Double(makePlace) / Double(count))
            let skins = Palette.skins.count
            var tiles = [Tile](repeating: .solid, count: 12)
            var skin = (makeLevel - 1) % skins
            var turnRate = 0.0

            if endsLevel {
                // no hole and no red: it breaks on any landing, and it already wears the next level's rims
                for j in stride(from: 0, to: 12, by: 2) { tiles[j] = .finish }
                skin = makeLevel % skins
                stackLeft = 0
                smashFloorNext = false
            } else if smashFloorNext {
                // the floor a combo smashes through: often red right where the ball arrives
                smashFloorNext = false
                let hole = zoneStart + zoneWidth + 2 + dice.index(below: 3)
                tiles[tile(hole)] = .hole
                tiles[tile(hole + 1)] = .hole
                var reds = hazardCount(hard)
                var kept = Set([tile(hole - 1), tile(hole + 2)])
                for k in -1...zoneWidth { kept.insert(tile(zoneStart + k)) }
                if hard >= 1.4, dice.unit() < 0.75 {
                    for k in 0..<zoneWidth { tiles[tile(zoneStart + k)] = .hazard }
                    reds -= zoneWidth
                }
                let places = (0..<12).filter { tiles[$0] == .solid && !kept.contains($0) }
                scatter(reds, over: places, in: &tiles)
            } else if stackLeft > 0 {
                // a hole straight under the one above: falling through both starts a combo
                stackLeft -= 1
                if stackLeft == 0 { smashFloorNext = true }
                for k in 0..<zoneWidth { tiles[tile(zoneStart + k)] = .hole }
                let places = (0..<(12 - zoneWidth - 2)).map { tile(zoneStart + zoneWidth + 1 + $0) }
                scatter(hazardCount(hard) - 1, over: places, in: &tiles)
            } else {
                let width = holeWidth(hard)
                let way = dice.unit() < 0.5 ? 1 : -1
                var walk = 1 + dice.index(below: 4)
                if laid == 0 { walk = max(walk, 2) }
                let hole = way > 0 ? zoneStart + zoneWidth + walk : zoneStart - walk - width
                for k in 0..<width { tiles[tile(hole + k)] = .hole }

                // the way from the landing spot to the hole
                let path = (0..<walk).map { tile(way > 0 ? zoneStart + zoneWidth + $0 : zoneStart - 1 - $0) }
                // the rest of the floor, from the far lip of the hole round to the landing spot
                var places = (0..<(12 - zoneWidth - walk - width)).map { tile(way > 0 ? hole + width + $0 : hole - 1 - $0) }

                let startsStack = laid >= 2 && makePlace < count - 2 && dice.unit() < (hard < 1 ? 0.24 : 0.2)
                let turns = !startsStack && laid > 0 && hard >= 1
                    && dice.unit() < min(0.6, 0.14 + 0.1 * (hard - 1))
                if turns {
                    turnRate = min(48, 10 + 4.5 * hard) * dice.between(0.75, 1.15) * (dice.unit() < 0.5 ? 1 : -1)
                }

                var reds = hazardCount(hard)
                if turns { reds = Int((Double(reds) * 0.6).rounded()) }
                if hard < 0.6, !places.isEmpty { places.removeFirst() }
                if hard < 2.0, !places.isEmpty { places.removeLast() }
                if !turns, hard >= 1.5, walk >= 2, dice.unit() < min(0.55, 0.15 + 0.18 * (hard - 1.5)) {
                    // a red tile to hop over on the way to the hole
                    let i = 1 + dice.index(below: walk - 1)
                    tiles[path[i]] = .hazard
                    reds -= 1
                    if hard >= 3.5, i + 1 < walk, dice.unit() < 0.3 { tiles[path[i + 1]] = .hazard }
                }
                if !turns, hard >= 2.2, zoneWidth >= 2, dice.unit() < min(0.4, 0.1 + 0.12 * (hard - 2.2)) {
                    // red under the far half of the hole above
                    tiles[tile(lastWay > 0 ? zoneStart + zoneWidth - 1 : zoneStart)] = .hazard
                }
                scatter(reds, over: places, in: &tiles)

                zoneStart = tile(hole)
                zoneWidth = width
                lastWay = way
                if startsStack {
                    let r = dice.unit()
                    stackLeft = r < 0.5 ? 1 : (r < 0.8 ? 2 : 3)
                }
            }

            if !endsLevel { openWays(in: &tiles, reach: hard < 2.6 ? 2 : 3) }
            floors.append(Floor(tiles: tiles, skin: skin))
            plans.append(Plan(turnRate: turnRate, endsLevel: endsLevel))
            laid += 1
            makePlace += 1
            if endsLevel {
                makeLevel += 1
                makePlace = 0
            }
        }

        // MARK: Picture

        /// The round as the painter wants it.
        func shot() -> Shot {
            var shot = Shot()
            shot.time = time
            shot.drift = seconds / 9
            shot.turn = turn
            shot.floors = floors
            shot.firstFloor = firstFloor
            shot.skinFrom = lastSkin
            shot.depthFrom = 1
            shot.skinTo = (level - 1) % Palette.skins.count
            shot.depthTo = ramp(0, 1, (camera - Double(levelStart)) / (0.8 * Double(levelFloors)))
            shot.skinBlend = ramp(0, 1.6, time - levelUpAt)
            shot.level = level
            shot.levelProgress = clamp((camera - Double(levelStart) + 0.5) / Double(levelFloors), 0.03, 1)
            shot.sinceLevelUp = time - levelUpAt
            if !isAlive { shot.shake = sin(sinceDeath * 60) * 7 * exp(-sinceDeath * 7) }

            var ball = Ball()
            ball.height = height
            ball.camera = camera
            ball.speed = speed
            ball.visit = landings - 1
            ball.restFloor = restFloor
            ball.nextFloor = next
            ball.falling = isFalling
            ball.fallStart = fallStart
            ball.fallFloors = chain >= 2 ? chain : 0
            ball.chain = chain
            ball.sinceTouch = time - touchedAt
            ball.touchIndex = touchIndex
            ball.impact = impact
            ball.marks = dabs.map { Mark(slot: $0.slot, age: time - $0.time, power: $0.power, id: $0.id) }
            ball.sinceLanding = time - landedAt
            ball.landedChain = landedChain
            ball.sinceBreak = time - brokeAt
            ball.score = score
            ball.hidden = !isAlive
            shot.ball = ball
            return shot
        }

        /// The few things the game shows on top of the clip's picture.
        func extras() -> Extras {
            var extras = Extras()
            extras.seconds = seconds
            if stage == .ready {
                extras.hint = 1
            } else if stage == .playing {
                extras.hint = clamp(1 - playSeconds / 0.25)
            }
            if !solo {
                let sincePassing = seconds - passedFriendAt
                if !passedFriend {
                    extras.chip = "\(friendName) \(friendScore)"
                    extras.chipAlpha = 1
                } else if sincePassing < 2.6 {
                    extras.chip = "Passed \(friendName)"
                    extras.chipAlpha = 1 - ramp(2.1, 2.6, sincePassing)
                    extras.chipPop = exp(-sincePassing * 6)
                    extras.chipLit = true
                }
            }
            if !isAlive { extras.flash = exp(-sinceDeath * 4.5) }
            return extras
        }
    }

    struct Extras {
        var hint = 0.0
        var seconds = 0.0
        var chip: String?
        var chipAlpha = 0.0
        var chipPop = 0.0
        var chipLit = false
        var flash = 0.0
    }
}

// MARK: - The game's own drawing

extension SpiralDrop.Painter {
    typealias Palette = SpiralDrop.Palette

    /// One frame of the playable game: the world, a red flash when the round ends, the score, the friend's
    /// score to beat and the hint.
    func drawGame(_ ctx: inout GraphicsContext, _ extras: SpiralDrop.Extras) {
        drawWorld(&ctx)
        if extras.flash > 0.01 { drawFlash(&ctx, extras.flash) }
        drawCallouts(&ctx)
        drawScore(&ctx)
        drawChip(&ctx, extras)
        drawHint(&ctx, extras)
    }

    func drawFlash(_ ctx: inout GraphicsContext, _ amount: Double) {
        let red = Gradient(stops: [
            .init(color: Palette.hazard.color(0.20 * amount), location: 0),
            .init(color: Palette.hazardLo.color(0.42 * amount), location: 0.6),
            .init(color: Palette.hazardSeam.color(0.78 * amount), location: 1)
        ])
        ctx.fill(Path(CGRect(x: 0, y: 0, width: width, height: height)),
                 with: .radialGradient(red, center: CGPoint(x: width * 0.5, y: height * 0.5),
                                       startRadius: 0, endRadius: max(width, height) * 0.72))
    }

    /// The friend's score, in a small pill under the level bar.
    func drawChip(_ ctx: inout GraphicsContext, _ extras: SpiralDrop.Extras) {
        guard let string = extras.chip, extras.chipAlpha > 0.02 else { return }
        let middle = CGPoint(x: width * 0.5, y: hudY + 86 * unit)
        let size = 13.5 * unit * (1 + 0.35 * extras.chipPop)
        let text = ctx.resolve(Text(string).font(.system(size: size, weight: .black, design: .rounded)))
        let measured = text.measure(in: CGSize(width: width, height: 80 * unit))
        let pillHeight = measured.height + 6 * unit
        let pillWidth = measured.width + 20 * unit
        let pill = Path(roundedRect: CGRect(x: middle.x - pillWidth / 2, y: middle.y - pillHeight / 2,
                                            width: pillWidth, height: pillHeight), cornerRadius: pillHeight / 2)
        var faded = ctx
        faded.opacity = extras.chipAlpha
        faded.fill(pill, with: .color(Palette.ink.color(0.46)))
        if extras.chipLit {
            faded.stroke(pill, with: .color(Palette.ballLit.color(0.9)), lineWidth: max(0.6, 1.5 * unit))
        }
        write(&faded, string, size: size, at: middle,
              fill: .color(extras.chipLit ? Palette.ballLit.color() : Color.white.opacity(0.95)))
    }

    /// What to do, with an arrow on each side that rocks in and out.
    func drawHint(_ ctx: inout GraphicsContext, _ extras: SpiralDrop.Extras) {
        guard extras.hint > 0.02 else { return }
        let string = "Drag to turn"
        let size = 25 * unit
        let middle = CGPoint(x: width * 0.5, y: height * 0.80)
        let text = ctx.resolve(Text(string).font(.system(size: size, weight: .black, design: .rounded)))
        let half = text.measure(in: CGSize(width: width, height: 100 * unit)).width / 2
        var faded = ctx
        faded.opacity = extras.hint
        write(&faded, string, size: size, at: middle, fill: .color(.white),
              outline: Palette.ink.color(0.9), outlineWidth: 2.2 * unit, shadow: Palette.ink.color(0.5), shadowDrop: 3 * unit)
        let rock = 5 * unit * sin(extras.seconds * 3.4)
        for side in [-1.0, 1.0] {
            let x = middle.x + side * (half + 20 * unit + rock)
            var arrow = Path()
            arrow.move(to: CGPoint(x: x - side * 5 * unit, y: middle.y - 9 * unit))
            arrow.addLine(to: CGPoint(x: x + side * 5 * unit, y: middle.y))
            arrow.addLine(to: CGPoint(x: x - side * 5 * unit, y: middle.y + 9 * unit))
            faded.stroke(arrow, with: .color(Palette.ink.color(0.9)),
                         style: StrokeStyle(lineWidth: 8.4 * unit, lineCap: .round, lineJoin: .round))
            faded.stroke(arrow, with: .color(.white),
                         style: StrokeStyle(lineWidth: 4.2 * unit, lineCap: .round, lineJoin: .round))
        }
    }
}

// MARK: - Scripted player

extension SpiralDrop {
    /// Plays a round by itself for recordings (GameDemo.autopilot).
    ///
    /// It only reads the round and gives input through touchDown() and drag(by:), the calls a finger makes.
    /// Its thumb moves in eased strokes that may overlap. Before each one it works out where the ball would
    /// come down for a spread of possible strokes and takes the one it likes best.
    final class Pilot {
        /// One stroke of the thumb: a turn of the tower that starts and ends gently.
        struct Stroke {
            var start: Double
            var length: Double
            /// Degrees of tower turn.
            var amount: Double
            /// 0 is an even stroke. More is quicker off the mark with a longer tail.
            var lean: Double

            var end: Double { start + length }

            /// Roughly the fastest the tower turns during the stroke, in degrees per second.
            var peakSpeed: Double { (1.9 + 0.95 * lean) * abs(amount) / length }

            /// The share of the stroke that is done at a time, 0 ... 1.
            func progress(at t: Double) -> Double {
                let u = (t - start) / length
                if u <= 0 { return 0 }
                if u >= 1 { return 1 }
                let bulge = u * (1 - u)
                let w = u + lean * 4 * bulge * bulge
                return w * w * w * (10 + w * (6 * w - 15))
            }
        }

        /// What it expects to happen if it moves a certain way.
        struct Outlook {
            var dies = false
            var diesAt = 0.0
            /// The ball comes down well inside red, not near its edge.
            var surelyDies = false
            /// Some landing is too close to an edge to call.
            var unsure = false
            var floors = 0
            var worth = 0.0
            /// Grows when the ball bounces close to red.
            var crowding = 0.0
            /// Degrees from where the ball ends up bouncing to the nearest hole of that floor.
            var holeAway = 0.0
        }

        /// How long the ready state shows before the first move.
        static let readySeconds = 0.8
        /// Spacing of the tower angles it considers, in degrees.
        static let aimStep = 7.5
        static let strokeLengths = [0.20, 0.28, 0.38, 0.50, 0.64, 0.80]
        /// How long into a round it goes out of its way for a first combo, in seconds of play.
        static let showSeconds = 11.5
        /// Degrees it keeps between a landing and the edge of a hole or of red, plus more when the tower moves.
        static let edgeRoom = 3.2
        static let edgeRoomPerSpeed = 0.016

        private var dice: Dice
        private var clock = 0.0
        private var waited = 0.0
        private var started = false
        private var losing = false
        /// Early in the round and still without a combo of three: it swipes a little harder to get one.
        private var keen = false
        /// It never turns the tower faster than this, in degrees per second.
        private var speedLimit: Double { keen ? 560 : 450 }
        private var easySpeed: Double { keen ? 340 : 280 }

        private var strokes: [Stroke] = []
        /// Tower angle from the strokes that are finished. The running ones add their share on top.
        private var settled = 0.0
        /// Tower angle after its last input, to notice when something else turned the tower.
        private var applied = 0.0

        private var seenTouch = -99.0
        private var seenNext = 0
        /// Bounces it still lets go by before its next move.
        private var watching = 0

        init(seed: UInt64) {
            dice = Dice(seed: seed &* 0x2545F4914F6CDD1D &+ 0x5D)
        }

        /// Call once per frame, before the round steps by the same dt.
        func steer(_ round: Round, dt: Double) {
            guard round.isAlive, dt > 0 else { return }
            if started {
                // a real finger may have turned the tower too: carry on from where it is
                settled += round.turn - applied
                for stroke in strokes where stroke.end <= clock { settled += stroke.amount }
                strokes.removeAll { $0.end <= clock }
                look(at: round)
            } else {
                if round.stage == .ready {
                    waited += dt
                    guard waited >= Self.readySeconds else { return }
                }
                started = true
                settled = round.turn
                seenTouch = round.touchedAt
                seenNext = round.next
                round.touchDown()
                choose(for: round, delay: 0)
            }
            let target = angle(at: clock + dt * 0.5, with: nil)
            round.drag(by: (round.turn - target) / Round.degreesPerUnit)
            applied = round.turn
            clock += dt
        }

        /// Notices what the ball just did and decides whether to move.
        private func look(at round: Round) {
            if !losing, let limit = GameDemo.loseAfter, round.playSeconds >= limit {
                losing = true
                watching = 0
                seenTouch = round.touchedAt
                seenNext = round.next
                choose(for: round, delay: 0.04)
                return
            }
            if round.touchedAt != seenTouch {
                seenTouch = round.touchedAt
                seenNext = round.next
                var delay = dice.between(0.03, 0.09)
                if round.restFloor != round.next {
                    // in the hop after a smash
                    watching = 0
                    delay = dice.between(0.03, 0.08)
                } else if round.touchIndex == 0 {
                    // a new floor: now and then, watch a bounce or two first
                    delay = dice.between(0.04, 0.14)
                    let showing = round.playSeconds < Self.showSeconds
                    watching = 0
                    if !losing, !(showing && round.bestChain < 3), round.plans[round.next - round.firstFloor].turnRate == 0,
                       dice.unit() < (showing ? 0.1 : 0.26) {
                        watching = dice.unit() < 0.72 ? 1 : 2
                    }
                } else if watching > 0 {
                    watching -= 1
                }
                choose(for: round, delay: delay)
            } else if round.next != seenNext {
                // the ball fell through a hole: step in only if carrying on would end badly
                seenNext = round.next
                let ahead = outlook(round, with: nil, until: clock + 0.3, care: 0.5)
                if ahead.dies != losing { choose(for: round, delay: 0) }
            }
        }

        // MARK: The thumb

        private func angle(at t: Double, with extra: Stroke?) -> Double {
            var a = settled
            for stroke in strokes { a += stroke.amount * stroke.progress(at: t) }
            if let extra { a += extra.amount * extra.progress(at: t) }
            return a
        }

        private func turnSpeed(at t: Double, with extra: Stroke?) -> Double {
            (angle(at: t + 0.004, with: extra) - angle(at: t - 0.004, with: extra)) / 0.008
        }

        /// True when a stroke on top of the ones still running would turn the tower faster than a thumb does.
        private func tooFast(_ extra: Stroke) -> Bool {
            (1...7).contains { abs(turnSpeed(at: extra.start + extra.length * Double($0) / 8, with: extra)) > speedLimit }
        }

        // MARK: Looking ahead

        private static func wrapped(_ slot: Double) -> Double {
            let r = slot.truncatingRemainder(dividingBy: 12)
            return r < 0 ? min(r + 12, 11.999999) : r
        }

        /// Follows the ball from where it is now, with the thumb doing what it is doing plus one more stroke,
        /// up to the first bounce after softEnd. care scales the room it wants at the edges.
        private func outlook(_ round: Round, with extra: Stroke?, until softEnd: Double, care: Double) -> Outlook {
            var out = Outlook()
            var height = round.height
            var speed = round.speed
            var chain = round.chain
            var n = round.next
            var t = clock
            var level = round.level
            var bounce = round.bounceSeconds
            var resting = false
            /// In the small hop after a smash there is time to steer before the ball comes down.
            var hopping = false
            let hardEnd = softEnd + 2.5

            func under(_ slot: Double) -> Tile { round.ground(on: n, at: Self.wrapped(slot)) }

            for _ in 0..<14 {
                let i = n - round.firstFloor
                guard i < round.floors.count else { break }
                let flight = Round.fallTime(distance: Double(n) - height, speed: speed)
                let hit = t + flight * bounce
                if hit > hardEnd || (hit > softEnd && resting) { break }
                if speed < Round.topSpeed { speed = min(Round.topSpeed, speed + Round.gravity * flight) }
                height = Double(n)
                t = hit
                let soon = max(6, 10 - 4 * (t - clock))
                let comboWorth = chain >= 2 ? 10 + 5 * Double(chain - 2) : 0

                if round.plans[i].endsLevel {
                    out.floors += 1
                    out.worth += soon + comboWorth
                    chain = 0
                    speed = -Round.hopSpeed * 1.2
                    n += 1
                    level += 1
                    bounce = Round.bounceSeconds(level: level)
                    resting = false
                    hopping = true
                    continue
                }

                let rate = round.plans[i].turnRate
                let slot = (ballAngle - angle(at: t, with: extra) - round.floors[i].twist - rate * (t - clock)) / 30
                let moving = abs(turnSpeed(at: t, with: extra) + rate)
                let room = care * (Self.edgeRoom + Self.edgeRoomPerSpeed * moving) / 30
                let mid = under(slot)
                let low = room > 0 ? under(slot - room) : mid
                let high = room > 0 ? under(slot + room) : mid

                if hopping {
                    hopping = false
                    if mid == .hazard || low == .hazard || high == .hazard {
                        // red where the hop comes down: fine as long as other ground is a short turn away
                        var near = 9.0
                        for k in 1...8 {
                            let d = Double(k) * 0.25
                            for side in [-1.0, 1.0] where near > d && under(slot + side * d) != .hazard
                                && under(slot + side * (d + 0.3)) != .hazard {
                                near = d
                            }
                        }
                        if near > 8 {
                            out.dies = true
                            out.diesAt = t
                        } else {
                            out.crowding += 1.5 + near
                            out.holeAway = 60
                        }
                        return out
                    }
                }
                if (low == .hole) != (mid == .hole) || (high == .hole) != (mid == .hole) { out.unsure = true }

                if mid == .hole {
                    chain += 1
                    out.floors += 1
                    out.worth += soon + (chain == 2 ? (keen ? 12 : 3) : 0)
                    n += 1
                    resting = false
                    continue
                }
                if chain >= 2 {
                    out.floors += 1
                    out.worth += soon + comboWorth
                    chain = 0
                    speed = -Round.hopSpeed
                    n += 1
                    resting = false
                    hopping = true
                    continue
                }
                if mid == .hazard {
                    out.dies = true
                    out.diesAt = t
                    out.surelyDies = low == .hazard && high == .hazard
                    return out
                }
                if low == .hazard || high == .hazard { out.unsure = true }
                speed = -Round.bounceSpeed
                chain = 0
                resting = true
                for (reach, cost) in [(6.5, 4.0), (10.0, 2.4), (15.0, 1.1)] {
                    if under(slot - reach / 30) == .hazard || under(slot + reach / 30) == .hazard {
                        out.crowding += cost
                        break
                    }
                }
                out.holeAway = 180
                for k in 1...24 {
                    let d = Double(k) * 0.25
                    if under(slot - d) == .hole || under(slot + d) == .hole {
                        out.holeAway = d * 30
                        break
                    }
                }
            }
            if !resting { out.holeAway = 0 }
            return out
        }

        // MARK: Choosing a stroke

        private func effort(_ stroke: Stroke) -> Double {
            let size = abs(stroke.amount)
            let natural = min(0.85, max(0.2, 0.17 + size / 240))
            return 0.006 * size + 0.04 * max(0, stroke.peakSpeed - easySpeed) + 1.5 * abs(log(stroke.length / natural))
        }

        /// Picks the next stroke, or none, and starts it after a delay.
        private func choose(for round: Round, delay: Double) {
            keen = !losing && round.playSeconds < Self.showSeconds && round.bestChain < 3
            let bounce = round.bounceSeconds
            let firstHit = clock + round.bouncesToFloor * bounce
            let start = clock + delay
            let offset = dice.unit() * Self.aimStep
            let stretch = dice.between(0.92, 1.08)
            let lean = dice.between(0.05, 0.6)

            // strokes that start now, and strokes that wait for the next bounce first
            var starts = [start]
            let later = firstHit + dice.between(0.02, 0.07)
            if keen {
                // more ways to time a swipe through two holes
                for t in stride(from: start + 0.13, to: later - 0.06, by: 0.13) { starts.append(t) }
            }
            if later > start + 0.12 { starts.append(later) }
            var options: [Stroke?] = [nil]
            for amount in stride(from: -180 + offset, to: 180, by: Self.aimStep) where abs(amount) >= 3 {
                for begin in starts {
                    for base in Self.strokeLengths {
                        let stroke = Stroke(start: begin, length: base * stretch, amount: amount, lean: lean)
                        if stroke.peakSpeed <= speedLimit, stroke.length <= 0.3 + abs(amount) / 70 {
                            options.append(stroke)
                        }
                    }
                }
            }

            // how picky to be: 0 = just watch a bounce, 1 ... 3 = play on with less and less room at the
            // edges, 4 and 5 = find red on purpose, 6 = red whatever it does, so put it off
            var moods = [1, 2, 3, 6]
            if losing {
                moods = [4, 5, 1, 2, 3, 6]
            } else if watching > 0 {
                moods = [0, 1, 2, 3, 6]
            }

            for mood in moods {
                let care = mood == 2 ? 0.45 : (mood == 3 ? 0 : 1)
                var best: Stroke?
                var bestScore = -Double.infinity
                var found = false
                for option in options {
                    let size = abs(option?.amount ?? 0)
                    if mood == 0, size > 20 { continue }
                    if let option, !strokes.isEmpty, tooFast(option) { continue }
                    var softEnd = firstHit + (mood == 0 ? 0.05 : 1.15 * bounce)
                    if let option { softEnd = max(softEnd, option.end + 0.02) }
                    let ahead = outlook(round, with: option, until: softEnd, care: care)
                    var score = -(option.map(effort) ?? 0)
                    switch mood {
                    case 0:
                        if ahead.dies || ahead.unsure || ahead.floors > 0 { continue }
                        score = -ahead.crowding - 0.08 * size + 0.5 * dice.unit()
                    case 4, 5:
                        guard ahead.dies, ahead.surelyDies || mood == 5 else { continue }
                        score -= 30 * (ahead.diesAt - clock)
                    case 6:
                        score += 30 * (ahead.dies ? ahead.diesAt - clock : 9)
                    default:
                        if ahead.dies || (ahead.unsure && care > 0) { continue }
                        score += ahead.worth - ahead.crowding - 0.035 * ahead.holeAway + 0.8 * dice.unit()
                        if option == nil { score += strokes.isEmpty ? 0.6 : 1.5 }
                    }
                    if score > bestScore {
                        bestScore = score
                        best = option
                        found = true
                    }
                }
                guard found else { continue }
                if let best {
                    strokes.append(best)
                    round.touchDown()
                }
                return
            }
        }
    }
}

// MARK: - Game

extension SpiralDrop {
    /// Steps a round from the display clock, one per game view. Not observed, so changing it never
    /// redraws anything by itself.
    final class Driver {
        let round: Round
        var lastTick: Double?
        var lastX: CGFloat?
        private var reported = false
        private let seed: UInt64
        /// Only made when the game plays itself.
        private var pilot: Pilot?

        init(options: GameOptions) {
            seed = options.seed
            round = Round(seed: options.seed, solo: options.solo, friendName: options.friendNames.first ?? "friend")
        }

        /// Brings the round up to now and passes on what happened.
        func tick(_ now: Double, link: GameLink) {
            defer { lastTick = now }
            guard !link.paused, let last = lastTick else { return }
            // a slow frame is made up in several small steps, so the game keeps real time
            var left = min(max(now - last, 0), 0.1)
            while left > 1e-6 {
                let dt = min(left, 1.0 / 60.0)
                left -= dt
                if GameDemo.autopilot {
                    if pilot == nil { pilot = Pilot(seed: seed) }
                    pilot?.steer(round, dt: dt)
                }
                round.step(dt: dt)
            }
            // the ball bounces before the first touch too, but silently
            let events = round.takeEvents()
            if round.stage != .ready {
                for event in events {
                    switch event {
                    case .landed: GameHaptics.tap()
                    case .bounced: break
                    case .fell(let count): if count >= 2 { GameHaptics.thud() } else { GameHaptics.tap() }
                    case .smashed: GameHaptics.heavy()
                    case .levelUp, .passedFriend: GameHaptics.success()
                    case .died: GameHaptics.fail()
                    }
                }
            }
            if round.stage == .over, !reported {
                reported = true
                let result = round.result
                DispatchQueue.main.async { link.finish(result) }
            }
        }
    }

    /// Draws exactly one frame from the round as it is now.
    struct Board: View {
        let round: Round
        /// Changes every frame, so the canvas draws again.
        var stamp = 0.0

        var body: some View {
            Canvas(opaque: true, colorMode: .nonLinear, rendersAsynchronously: false) { context, size in
                guard size.width > 8, size.height > 8 else { return }
                let painter = Painter(size: size, shot: round.shot(), hud: true)
                painter.drawGame(&context, round.extras())
            }
        }
    }
}

public struct SpiralDropGame: View {
    @ObservedObject private var link: GameLink
    @State private var driver: SpiralDrop.Driver

    public init(options: GameOptions, link: GameLink) {
        self.link = link
        _driver = State(initialValue: SpiralDrop.Driver(options: options))
    }

    public var body: some View {
        GeometryReader { geo in
            // points per scene unit, as the painter has it
            let unit = max(0.1, min(geo.size.width / 402, geo.size.height / 640))
            TimelineView(.animation(minimumInterval: nil, paused: link.paused)) { timeline in
                let now = timeline.date.timeIntervalSinceReferenceDate
                let _ = driver.tick(now, link: link)
                SpiralDrop.Board(round: driver.round, stamp: now)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        guard !link.paused else {
                            driver.lastX = nil
                            return
                        }
                        if let from = driver.lastX {
                            driver.round.drag(by: Double(value.location.x - from) / Double(unit))
                        } else {
                            driver.round.touchDown()
                        }
                        driver.lastX = value.location.x
                    }
                    .onEnded { _ in driver.lastX = nil }
            )
        }
        .ignoresSafeArea()
        .onChange(of: link.paused) { _, _ in
            driver.lastTick = nil
            driver.lastX = nil
        }
    }
}
