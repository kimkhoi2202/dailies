import Foundation

// What the Convex backend sends and returns, as plain values.
// Convex numbers are doubles on the wire, so every number here is a Double.

enum ConvexConfig {
    /// The deployment the app talks to. `-convex <url>` on the command line points a test build elsewhere.
    static var deploymentURL: String {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-convex"), i + 1 < args.count { return args[i + 1] }
        return "https://blissful-jackal-368.convex.cloud"
    }
}

/// `users:me`: the signed-in player and what they collected today.
struct ConvexMe: Decodable, Equatable {
    struct Earning: Decodable, Equatable {
        let gameSlug: String
        let studio: String
        let gold: Double
        let playMs: Double
        let carry: Double?
    }

    let id: String
    let name: String
    let handle: String
    let color: String
    let gold: Double
    let goldAllTime: Double
    let rounds: Double
    let streak: Double
    let playedToday: Bool
    let fastGold: Bool
    let changes: Double?
    let today: Double
    let earnings: [Earning]
    let owned: [String]?

    private enum CodingKeys: String, CodingKey {
        case id = "_id"
        case name, handle, color, gold, goldAllTime, rounds, streak, playedToday, fastGold, changes, today, earnings, owned
    }
}

/// One row of `games:list`: a game in the catalog with this player's numbers for today.
struct ConvexGame: Decodable, Equatable, Identifiable {
    let slug: String
    let title: String
    let studio: String
    let pitch: String
    let how: String
    let minPlayers: Double
    let maxPlayers: Double
    let mode: String
    let category: String
    let unit: String
    let goldPerMinute: Double
    let likes: Double
    let dislikes: Double
    let plays: Double
    let comments: Double
    let today: Double
    let studioToday: Double
    let left: Double
    let best: Double?
    let bestUnit: String?
    let bestText: String?
    /// 1 liked, -1 disliked, 0 no vote.
    let vote: Double

    var id: String { slug }
}

/// One row of `ledger:list`: gold collected in a round, or gold spent.
struct ConvexLedgerRow: Decodable, Equatable {
    let id: String
    let kind: String
    let title: String
    let detail: String
    let amount: Double
    let gameSlug: String?
    let at: Double

    private enum CodingKeys: String, CodingKey {
        case id = "_id"
        case kind, title, detail, amount, gameSlug, at
    }
}

/// One row of `social:myComments`.
struct ConvexMyComment: Decodable, Equatable {
    let id: String
    let gameSlug: String
    let body: String
    let at: Double

    private enum CodingKeys: String, CodingKey {
        case id = "_id"
        case gameSlug, body, at
    }
}

/// One row of `social:comments`: a comment under a game, from anyone.
struct ConvexComment: Decodable, Equatable, Identifiable {
    let id: String
    let body: String
    let at: Double
    let handle: String
    let color: String
    let mine: Bool
    let likes: Double?
    let liked: Bool?

    private enum CodingKeys: String, CodingKey {
        case id = "_id"
        case body, at, handle, color, mine, likes, liked
    }
}

/// One row of `social:leaderboard`.
struct ConvexRank: Decodable, Equatable, Identifiable {
    let rank: Double
    let score: Double
    let handle: String
    let color: String
    let you: Bool

    var id: String { handle }
}

/// The answer to `rounds:start`.
struct ConvexRoundStart: Decodable {
    let roundId: String
    let seed: Double
    let best: Double
    let goldPerMinute: Double
    let left: Double
    let carry: Double?
}

/// The answer to `rounds:finish`: what the server decided the round was worth.
struct ConvexRoundFinish: Decodable {
    let gold: Double
    let playMs: Double?
    let carry: Double?
    let balance: Double
    let today: Double
    let left: Double
    let best: Double
    let previousBest: Double
    let newBest: Bool
    let streak: Double
    let changes: Double?
}

/// One row of `rounds:history`: a finished round of the player's.
struct ConvexHistoryRound: Decodable, Equatable, Identifiable {
    let id: String
    let gameSlug: String
    let score: Double
    let endedAt: Double

    private enum CodingKeys: String, CodingKey {
        case id = "_id"
        case gameSlug, score, endedAt
    }
}

/// `rooms:get`: a room the player is in, with everyone in it, best score first.
struct ConvexRoom: Decodable, Equatable {
    struct Player: Decodable, Equatable, Identifiable {
        let id: String
        let name: String
        let color: String
        let you: Bool
        let host: Bool
        let score: Double
        let done: Bool
        let playing: Bool
    }

    let code: String
    let slug: String
    let round: Double
    let seed: Double
    let status: String
    let host: Bool
    let players: [Player]
}

/// The design sheet of a game made in the studio. Every part is empty until the studio settles it.
struct ConvexDesign: Decodable, Equatable {
    var title: String?
    var pitch: String?
    var genre: String?
    var setting: String?
    var player: String?
    var goal: String?
    var controls: String?
    var rules: [String]?
    var scoring: String?
    var progression: String?
    var look: String?
    var sound: String?
    var tint: String?
}

/// One row of `creations:mine`: a game being designed in the studio, or designed.
struct ConvexCreation: Decodable, Equatable, Identifiable {
    let id: String
    /// talking, ready or failed.
    let status: String
    let wish: String
    let thinking: Bool
    let design: ConvexDesign?
    /// 0 to 1, how much of the sheet is settled.
    let progress: Double
    let error: String?
    let at: Double

    private enum CodingKeys: String, CodingKey {
        case id = "_id"
        case status, wish, thinking, design, progress, error, at
    }
}

/// One line of the conversation in `creations:get`.
struct ConvexCreationMessage: Decodable, Equatable, Identifiable {
    struct Idea: Decodable, Equatable {
        let title: String
        let pitch: String
    }

    let id: String
    /// maker or studio.
    let role: String
    let text: String
    let options: [String]
    let ideas: [Idea]
    let at: Double

    private enum CodingKeys: String, CodingKey {
        case id = "_id"
        case role, text, options, ideas, at
    }
}

/// `creations:get`: the design and its whole conversation.
struct ConvexCreationDetail: Decodable, Equatable {
    let id: String
    let status: String
    let wish: String
    let thinking: Bool
    let design: ConvexDesign?
    let progress: Double
    let error: String?
    let at: Double
    let messages: [ConvexCreationMessage]

    private enum CodingKeys: String, CodingKey {
        case id = "_id"
        case status, wish, thinking, design, progress, error, at, messages
    }
}

/// The answer to `shop:spend`.
struct ConvexSpend: Decodable {
    let balance: Double
    let changes: Double?
}
