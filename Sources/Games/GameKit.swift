import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// What the app and a playable game agree on. Nothing here depends on the rest of the app, so this
// file and one game's files build on their own, on the Mac too.
//
// A game is a SwiftUI view made with `init(options: GameOptions, link: GameLink)`. The app shows it
// edge to edge, lays a close button (top left) and the gold counter (top right) over it, keeps the
// play time, and moves to the results screen when the game calls `link.finish(_:)`.

/// The outcome of one round, handed to the app when the round is over.
public struct GameResult: Equatable {
    /// The headline number. Higher is better. The app compares it with `GameOptions.bestScore`.
    public var score: Int
    /// What the number counts, in lower case: "floors", "m", "points".
    public var unit: String
    /// Set only when the headline is more than the bare number, such as "34.2%".
    public var scoreText: String?
    /// One short plain line about the round.
    public var detail: String?
    /// 1 = ahead of everyone in the round, bots included. nil when nobody else played.
    public var placement: Int?
    /// Everyone in the round, bots included. nil when nobody else played.
    public var playerCount: Int?

    public init(score: Int, unit: String, scoreText: String? = nil, detail: String? = nil,
                placement: Int? = nil, playerCount: Int? = nil) {
        self.score = score
        self.unit = unit
        self.scoreText = scoreText
        self.detail = detail
        self.placement = placement
        self.playerCount = playerCount
    }
}

/// What a game is told when a round opens.
public struct GameOptions {
    /// true: the player is alone, no other players of any kind.
    /// false: the player is with friends. Until there is a server the game plays the friends itself.
    public var solo: Bool
    /// The player's name, for labels.
    public var playerName: String
    /// Names for the other players, in order. A game takes as many as it needs.
    public var friendNames: [String]
    /// The player's best `GameResult.score` in this game so far. 0 means no rounds yet.
    public var bestScore: Int
    /// Seeds the round's random numbers.
    public var seed: UInt64

    public init(solo: Bool = false, playerName: String = "mira",
                friendNames: [String] = ["kaz", "devon.plays", "noor.runs", "tofu", "juno"],
                bestScore: Int = 0, seed: UInt64 = 1) {
        self.solo = solo
        self.playerName = playerName
        self.friendNames = friendNames
        self.bestScore = bestScore
        self.seed = seed
    }
}

/// Connects a running game to the app.
public final class GameLink: ObservableObject {
    /// The app raises this while its own UI is over the game (the leave prompt, the app in the
    /// background). While it is true the game holds its clock and takes no input.
    @Published public var paused: Bool = false

    /// The app's handler for the end of the round.
    public var onFinish: (GameResult) -> Void = { _ in }

    public private(set) var isFinished = false

    public init() {}

    /// Called by the game once, after the round has ended and its short ending has played.
    /// Only the first call counts.
    public func finish(_ result: GameResult) {
        if isFinished { return }
        isFinished = true
        onFinish(result)
    }
}

/// Room the app keeps for its own controls over a game, in points on the full-screen view.
public enum GameLayout {
    /// The close button and the gold counter live inside this band at the top.
    public static let topBand: CGFloat = 108
    /// Width of each reserved top corner. A game may draw between the corners (its score, say),
    /// but not above `statusBarHeight`.
    public static let cornerWidth: CGFloat = 124
    /// Above this line sit the status bar and the Dynamic Island: background art only.
    public static let statusBarHeight: CGFloat = 62
    /// Controls and text that matter stay this far above the bottom edge, clear of the home indicator.
    public static let bottomInset: CGFloat = 38
}

/// Haptics for games. Call on the main thread. A no-op on the Mac.
public enum GameHaptics {
    /// Light: a key, a lane change.
    public static func tap() {
        #if canImport(UIKit) && !os(macOS)
        light.impactOccurred()
        #endif
    }

    /// Firmer: a block landing, a bounce.
    public static func thud() {
        #if canImport(UIKit) && !os(macOS)
        medium.impactOccurred()
        #endif
    }

    /// Heavy: a crash, a smash.
    public static func heavy() {
        #if canImport(UIKit) && !os(macOS)
        strong.impactOccurred()
        #endif
    }

    /// Something went well: a perfect drop, a closed loop, a solved word.
    public static func success() {
        #if canImport(UIKit) && !os(macOS)
        notice.notificationOccurred(.success)
        #endif
    }

    /// The round was lost.
    public static func fail() {
        #if canImport(UIKit) && !os(macOS)
        notice.notificationOccurred(.error)
        #endif
    }

    #if canImport(UIKit) && !os(macOS)
    // Made on first use and kept, so a haptic in the middle of a frame allocates nothing.
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)
    private static let strong = UIImpactFeedbackGenerator(style: .heavy)
    private static let notice = UINotificationFeedbackGenerator()
    #endif
}

/// Switches for recording a game. All off in normal play.
public enum GameDemo {
    /// true: the game starts by itself and a scripted player gives the input.
    public static var autopilot = false
    /// After this many seconds of play the scripted player loses on purpose, so the ending and the
    /// results can be recorded. nil: it keeps playing well.
    public static var loseAfter: Double? = nil
}
