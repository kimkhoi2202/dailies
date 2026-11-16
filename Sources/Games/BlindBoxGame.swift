import SwiftUI

// Blind Box, the playable round. The art, the timings and the painter are in BlindBoxScene.swift.
//
// BlindBoxModel   the rules of a round in plain Swift: step(dt:) and tap(at:).
// BlindBoxRunner  keeps the clock, turns touches into taps, fires haptics, reports the result.
// BlindBoxGame    the view the app shows.

final class BlindBoxModel {
    enum Stage { case shelf, tease, cut, beat, reveal, finished }
    enum Event { case pick, cut(heavy: Bool), whiteout, reveal, nope, skip }

    private(set) var stage: Stage = .shelf
    private(set) var clock = 0.0
    private(set) var stageTime = 0.0
    private(set) var picked = -1
    private(set) var item = 0
    private(set) var cutTime = 0.0
    private(set) var noteTime = -1.0
    private(set) var feedback: [Event] = []
    private var lastShot = -1
    private var size = CGSize(width: 402, height: 874)
    private let seed: UInt64
    private let salt: UInt64

    /// The item the last round showed, so two rounds in a row never show the same thing.
    private static var lastItem = -1

    init(options: GameOptions) {
        seed = options.seed
        salt = GameDemo.autopilot ? 0 : UInt64.random(in: 0...UInt64.max)
        feedback.reserveCapacity(8)
    }

    func resize(to size: CGSize) { self.size = size }

    func clearFeedback() { feedback.removeAll(keepingCapacity: true) }

    func step(dt: Double) {
        clock += dt
        stageTime += dt
        if noteTime >= 0 {
            noteTime += dt
            if noteTime > BlindBoxRules.noteTime { noteTime = -1 }
        }
        switch stage {
        case .shelf, .finished:
            break
        case .tease:
            if stageTime >= BlindBoxRules.teaseTime {
                enter(.cut)
                cutTime = 0
                lastShot = -1
            }
        case .cut:
            cutTime += dt
            let shot = BlindBoxRules.shotIndex(at: cutTime)
            if shot != lastShot {
                lastShot = shot
                feedback.append(.cut(heavy: BlindBoxRules.shots[shot].shake > 0))
            }
            if cutTime >= BlindBoxRules.cutLength {
                enter(.beat)
                feedback.append(.whiteout)
            }
        case .beat:
            if stageTime >= BlindBoxRules.beatTime {
                enter(.reveal)
                feedback.append(.reveal)
            }
        case .reveal:
            if stageTime >= BlindBoxRules.holdTime { enter(.finished) }
        }
    }

    func tap(at point: CGPoint) {
        switch stage {
        case .shelf:
            if let i = BlindBoxLayout.box(at: point, size) { pick(i) }
        case .cut:
            if cutTime < BlindBoxRules.skipAfter {
                noteTime = 0
                feedback.append(.nope)
            } else if cutTime < BlindBoxRules.skipTo {
                cutTime = BlindBoxRules.skipTo
                noteTime = -1
                feedback.append(.skip)
            }
        default:
            break
        }
    }

    func pick(_ box: Int) {
        guard stage == .shelf else { return }
        picked = box
        var x = seed ^ salt ^ (UInt64(box + 1) &* 0x9E37_79B9_7F4A_7C15)
        x = (x ^ (x >> 30)) &* 0xBF58_476D_1CE4_E5B9
        x = (x ^ (x >> 27)) &* 0x94D0_49BB_1331_11EB
        x ^= x >> 31
        let count = BlindBoxRules.items.count
        var choice = Int(x % UInt64(count))
        if choice == BlindBoxModel.lastItem { choice = (choice + 1) % count }
        BlindBoxModel.lastItem = choice
        item = choice
        enter(.tease)
        feedback.append(.pick)
    }

    private func enter(_ next: Stage) {
        stage = next
        stageTime = 0
    }

    var frame: BlindBoxFrame {
        var f = BlindBoxFrame()
        f.clock = clock
        f.picked = picked
        f.item = item
        f.noteTime = noteTime
        switch stage {
        case .shelf:
            f.stage = .shelf
        case .tease:
            f.stage = .shelf
            f.pickTime = stageTime
        case .cut:
            f.stage = .cut
            f.cutTime = cutTime
        case .beat:
            f.stage = .beat
            f.beatTime = stageTime
        case .reveal:
            f.stage = .reveal
            f.revealTime = stageTime
        case .finished:
            f.stage = .reveal
            f.revealTime = BlindBoxRules.holdTime
        }
        return f
    }

    var result: GameResult {
        let thing = BlindBoxRules.items[item]
        return GameResult(score: thing.points, unit: "points", detail: "Box " + String(picked + 1) + " held " + thing.said + ".")
    }
}

final class BlindBoxRunner: ObservableObject {
    let model: BlindBoxModel
    private var lastDate: Date?
    private var frame = 0
    private var reported = false

    init(options: GameOptions) {
        model = BlindBoxModel(options: options)
    }

    /// Brings the model up to the given date. Returns a number that changes when there is a new frame to paint.
    func advance(to date: Date, size: CGSize, link: GameLink) -> Int {
        model.resize(to: size)
        if link.paused {
            lastDate = nil
            return frame
        }
        defer { lastDate = date }
        guard let before = lastDate else { return frame }
        var owed = min(max(date.timeIntervalSince(before), 0), 0.1)
        if owed <= 0 { return frame }
        while owed > 1e-6 {
            let dt = min(owed, 1.0 / 60)
            owed -= dt
            model.step(dt: dt)
            if GameDemo.autopilot, model.stage == .shelf, model.clock > 0.9 { model.pick(4) }
            settle(link)
        }
        frame &+= 1
        return frame
    }

    func touch(at point: CGPoint, size: CGSize, link: GameLink) {
        if link.paused || link.isFinished { return }
        model.resize(to: size)
        model.tap(at: point)
        settle(link)
    }

    /// Plays the haptics the model owes and reports the round once it is over.
    private func settle(_ link: GameLink) {
        for event in model.feedback {
            switch event {
            case .pick, .skip: GameHaptics.thud()
            case .cut(let heavy): if heavy { GameHaptics.heavy() } else { GameHaptics.tap() }
            case .whiteout: GameHaptics.heavy()
            case .reveal, .nope: GameHaptics.tap()
            }
        }
        model.clearFeedback()
        if model.stage == .finished, !reported {
            reported = true
            let result = model.result
            DispatchQueue.main.async { link.finish(result) }
        }
    }
}

struct BlindBoxCanvas: View {
    let model: BlindBoxModel
    /// Changes every frame. The model is a class, so without it SwiftUI would skip the repaint.
    let frame: Int

    var body: some View {
        Canvas(opaque: true, colorMode: .nonLinear, rendersAsynchronously: false) { context, size in
            guard size.width > 8, size.height > 8, frame >= 0 else { return }
            BlindBoxPainter(size: size, frame: model.frame, showHUD: true).draw(&context)
        }
    }
}

/// Reports a finger the moment it lands.
private struct BlindBoxTouchPad: View {
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

public struct BlindBoxGame: View {
    private let options: GameOptions
    private let link: GameLink

    public init(options: GameOptions, link: GameLink) {
        self.options = options
        self.link = link
    }

    public var body: some View {
        // A new link is a new round, so the round's state lives and dies with the link.
        BlindBoxRound(options: options, link: link)
            .id(ObjectIdentifier(link))
    }
}

private struct BlindBoxRound: View {
    @ObservedObject var link: GameLink
    @StateObject private var runner: BlindBoxRunner

    init(options: GameOptions, link: GameLink) {
        self.link = link
        _runner = StateObject(wrappedValue: BlindBoxRunner(options: options))
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                TimelineView(.animation(minimumInterval: nil, paused: link.paused)) { timeline in
                    BlindBoxCanvas(model: runner.model, frame: runner.advance(to: timeline.date, size: geo.size, link: link))
                }
                BlindBoxTouchPad { point, size in
                    runner.touch(at: point, size: size, link: link)
                }
            }
        }
        .ignoresSafeArea()
        .accessibilityElement()
        .accessibilityLabel("Blind Box. Tap a box on the shelf, watch what happens, see what was inside.")
        .accessibilityAddTraits(.allowsDirectInteraction)
    }
}
