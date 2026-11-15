import SwiftUI

// The app's content: six games, the clips in Videos, and the story of one player, Mira.
// The rules every number here follows:
//   - gold follows play time, about 1 gold a minute, at a rate set per game by the review
//   - one game gives a player at most 100 gold a day, and one studio's games at most 300
//   - likes and dislikes belong to a game, not to a single clip, and both counts are public
//   - watching gives no gold, and gold cannot be bought or sold
// Whatever changes as the player plays (balance, today's gold, streak) is read from LiveStore.

enum GameKind: String, CaseIterable {
    case fiveUp, tippyTower, spiralDrop, laneDash, gulpCity, inkland, slipOut, blockParty, wildEights, brickOut, cornerPocket
}

struct MockGame: Identifiable {
    let id: String
    let kind: GameKind
    let title: String
    let tagline: String
    let category: String
    /// "2 to 4 players". The first thing friends look for.
    let players: String
    /// "Casual" or "Competitive".
    let mode: String
    let studio: String
    let goldPerMinute: Double
    let avgSession: String
    /// Today's gold from this game where the story starts. LiveStore holds the figure that moves.
    let seedEarned: Int
    let plays: String
    let likes: String
    let dislikes: String
    /// Percent of votes that are likes.
    let approval: Int
    let bestScore: String
    /// The moment of the gameplay loop that makes the best still, 0 to 1.
    let clipPhase: Double
    /// The main colour of the game's art.
    let tint: Color

    var capToday: Int { Mock.perGameDailyCap }
    var earnedToday: Int { LiveStore.shared.earnedToday(id) }
    /// Gold this game can still give today, after the game's limit and its studio's.
    var leftToday: Int { LiveStore.shared.room(for: self) }
    var isFullToday: Bool { leftToday == 0 }
    var rateLabel: String { String(format: "%.1f", goldPerMinute) }

    /// The gameplay, drawn in code at phone proportions. The caller crops it (see ClipStill).
    @ViewBuilder func scene(phase: Double? = nil, showHUD: Bool = true) -> some View {
        let moment = phase ?? clipPhase
        switch kind {
        case .fiveUp: FiveUpScene(phase: moment, showHUD: showHUD)
        case .tippyTower: TippyTowerScene(phase: moment, showHUD: showHUD)
        case .spiralDrop: SpiralDropScene(phase: moment, showHUD: showHUD)
        case .laneDash: LaneDashScene(phase: moment, showHUD: showHUD)
        case .gulpCity: GulpCityScene(phase: moment, showHUD: showHUD)
        case .inkland: InklandScene(phase: moment, showHUD: showHUD)
        case .slipOut: SlipOutScene(phase: moment, showHUD: showHUD)
        case .blockParty: BlockPartyScene(phase: moment, showHUD: showHUD)
        case .wildEights: WildEightsScene(phase: moment, showHUD: showHUD)
        case .brickOut: BrickOutScene(phase: moment, showHUD: showHUD)
        case .cornerPocket: CornerPocketScene(phase: moment, showHUD: showHUD)
        }
    }
}

/// One item in Videos: a short gameplay clip a player recorded.
struct MockClip: Identifiable {
    let id: String
    let game: MockGame
    let player: String
    let caption: String
    let length: String
    let comments: String
    let shares: String
}

struct MockTransaction: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    /// Above zero is gold collected, below zero is gold spent.
    let amount: Int
    let time: String
    let game: GameKind?
}

struct MockShopItem: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let price: Int
    let game: GameKind
    let symbol: String
}

struct MockRank: Identifiable {
    let id = UUID()
    let rank: Int
    let name: String
    let score: String
    let isYou: Bool
}

struct MockNotification: Identifiable {
    let id = UUID()
    let symbol: String
    let title: String
    let detail: String
    let time: String
    let unread: Bool
}

enum Mock {
    // MARK: The player

    static let handle = "mira"
    static let displayName = "Mira Okafor"
    static var balance: Int { LiveStore.shared.s.balance }
    static var earnedToday: Int { LiveStore.shared.earnedTodayTotal }
    /// The near goal, shown as "today's gold".
    static let dailyGoal = 10
    static var streakDays: Int { LiveStore.shared.s.streak }
    /// Sunday to Saturday.
    static let streakWeek = [false, true, true, true, true, true, true]
    static let weekInitials = ["S", "M", "T", "W", "T", "F", "S"]
    static let restDaysLeft = 2
    static var gamesPlayed: Int { 38 + LiveStore.shared.s.rounds }
    static let minutesThisWeek = 212
    static var resetIn: String { LiveStore.shared.resetIn }
    static let dateLine = "Saturday 14 November"

    // MARK: Friends

    static let friends = ["devon.plays", "kaz", "noor.runs", "tofu", "juno"]
    static let friendsOnline = 3
    /// The friends who join a round, in the order they join.
    static let playFriends = ["kaz", "devon.plays", "noor.runs", "tofu", "juno"]
    static let continuePlaying: [(game: MockGame, note: String)] = [
        (tippyTower, "Your best: 41 floors"),
        (fiveUp, "Your turn against kaz"),
        (laneDash, "devon.plays wants a rematch"),
    ]
    static let playerFilters = ["All", "2 players", "4 players", "6 players", "Casual", "Competitive"]

    // MARK: Gold rules

    static let perGameDailyCap = 100
    static let perStudioDailyCap = 300
    static let fairnessLines = [
        "About 1 gold for each minute you play.",
        "Up to 100 gold a day from one game.",
        "Up to 300 gold a day from one studio.",
        "Watching never earns gold.",
        "Gold can't be bought or sold.",
    ]

    // MARK: Games

    static let tippyTower = MockGame(
        id: "tippy-tower", kind: .tippyTower, title: "Tippy Tower", tagline: "Stack it. Don't blink.",
        category: "Arcade", players: "1 to 4 players", mode: "Casual", studio: "Wobble Works",
        goldPerMinute: 1.0, avgSession: "1m 35s", seedEarned: 12,
        plays: "1.2M", likes: "148K", dislikes: "9.6K", approval: 94,
        bestScore: "41 floors", clipPhase: 0.85, tint: Color(red: 0.36, green: 0.80, blue: 0.62))

    static let fiveUp = MockGame(
        id: "five-up", kind: .fiveUp, title: "Five Up", tagline: "Six tries. One word.",
        category: "Word", players: "2 players", mode: "Competitive", studio: "Paper Lantern",
        goldPerMinute: 1.1, avgSession: "3m 10s", seedEarned: 4,
        plays: "482K", likes: "61.2K", dislikes: "2.9K", approval: 95,
        bestScore: "3 tries", clipPhase: 0.85, tint: Color(red: 0.11, green: 0.62, blue: 0.58))

    static let laneDash = MockGame(
        id: "lane-dash", kind: .laneDash, title: "Lane Dash", tagline: "Three lanes. No brakes.",
        category: "Runner", players: "2 to 6 players", mode: "Competitive", studio: "Second Wind",
        goldPerMinute: 1.0, avgSession: "2m 20s", seedEarned: 100,
        plays: "655K", likes: "72.9K", dislikes: "9.4K", approval: 89,
        bestScore: "2,840 m", clipPhase: 0.5, tint: Color(red: 0.98, green: 0.45, blue: 0.42))

    static let inkland = MockGame(
        id: "inkland", kind: .inkland, title: "Inkland", tagline: "Draw a loop. Keep the land.",
        category: "Multiplayer", players: "4 to 6 players", mode: "Competitive", studio: "Nine Lives",
        goldPerMinute: 1.2, avgSession: "3m 30s", seedEarned: 0,
        plays: "268K", likes: "33.8K", dislikes: "7.6K", approval: 82,
        bestScore: "34.2%", clipPhase: 0.85, tint: Color(red: 0.96, green: 0.45, blue: 0.60))

    static let spiralDrop = MockGame(
        id: "spiral-drop", kind: .spiralDrop, title: "Spiral Drop", tagline: "Fall with style.",
        category: "Arcade", players: "1 or 2 players", mode: "Casual", studio: "Wobble Works",
        goldPerMinute: 0.9, avgSession: "2m 00s", seedEarned: 0,
        plays: "903K", likes: "97.4K", dislikes: "8.1K", approval: 92,
        bestScore: "Level 23", clipPhase: 0.5, tint: Color(red: 0.10, green: 0.55, blue: 0.70))

    static let gulpCity = MockGame(
        id: "gulp-city", kind: .gulpCity, title: "Gulp City", tagline: "Eat the block.",
        category: "Casual", players: "2 to 4 players", mode: "Casual", studio: "Nine Lives",
        goldPerMinute: 1.0, avgSession: "2m 00s", seedEarned: 0,
        plays: "371K", likes: "40.3K", dislikes: "3.9K", approval: 91,
        bestScore: "87%", clipPhase: 0.85, tint: Color(red: 0.55, green: 0.80, blue: 0.70))

    static let slipOut = MockGame(
        id: "slip-out", kind: .slipOut, title: "Slip Out", tagline: "Tap the arrow. Mind the way out.",
        category: "Puzzle", players: "1 player", mode: "Casual", studio: "Paper Lantern",
        goldPerMinute: 1.0, avgSession: "2m 10s", seedEarned: 0,
        plays: "214K", likes: "27.5K", dislikes: "2.1K", approval: 93,
        bestScore: "62 arrows", clipPhase: 0.5, tint: Color(red: 0.94, green: 0.33, blue: 0.42))

    static let blockParty = MockGame(
        id: "block-party", kind: .blockParty, title: "Block Party", tagline: "Fill the line. Clear it.",
        category: "Puzzle", players: "1 player", mode: "Casual", studio: "Paper Lantern",
        goldPerMinute: 1.0, avgSession: "2m 40s", seedEarned: 0,
        plays: "612K", likes: "74.1K", dislikes: "4.2K", approval: 94,
        bestScore: "2,680 points", clipPhase: 0.85, tint: Color(red: 0.63, green: 0.42, blue: 1.0))

    static let wildEights = MockGame(
        id: "wild-eights", kind: .wildEights, title: "Wild Eights", tagline: "Match the suit. Eights go anywhere.",
        category: "Cards", players: "2 to 4 players", mode: "Competitive", studio: "Paper Lantern",
        goldPerMinute: 1.0, avgSession: "2m 30s", seedEarned: 0,
        plays: "214K", likes: "26.1K", dislikes: "2.2K", approval: 92,
        bestScore: "168 points", clipPhase: 0.85, tint: Color(red: 0.16, green: 0.64, blue: 0.57))

    static let brickOut = MockGame(
        id: "brick-out", kind: .brickOut, title: "Brick Out", tagline: "Slide every brick out.",
        category: "Puzzle", players: "1 player", mode: "Casual", studio: "Paper Lantern",
        goldPerMinute: 1.0, avgSession: "2m 30s", seedEarned: 0,
        plays: "214K", likes: "26.1K", dislikes: "2.2K", approval: 92,
        bestScore: "1,240 points", clipPhase: 0.5, tint: Color(red: 0.42, green: 0.30, blue: 0.72))

    static let cornerPocket = MockGame(
        id: "corner-pocket", kind: .cornerPocket, title: "Corner Pocket", tagline: "Sink your group. Then the 8.",
        category: "Sports", players: "1 or 2 players", mode: "Competitive", studio: "Paper Lantern",
        goldPerMinute: 1.0, avgSession: "1m 30s", seedEarned: 0,
        plays: "188K", likes: "23.4K", dislikes: "1.9K", approval: 92,
        bestScore: "100 points", clipPhase: 0.42, tint: Color(red: 0.18, green: 0.56, blue: 0.44))

    static let games = [tippyTower, fiveUp, laneDash, inkland, spiralDrop, gulpCity, slipOut, blockParty, wildEights, brickOut, cornerPocket]

    // MARK: Videos

    static let clips = [
        MockClip(id: "c1", game: tippyTower, player: "devon.plays",
                 caption: "nine perfect drops in a row, then this", length: "0:42", comments: "312", shares: "1.9K"),
        MockClip(id: "c2", game: fiveUp, player: "wordnerd.sam",
                 caption: "got it in five. my group chat is furious", length: "0:31", comments: "540", shares: "2.2K"),
        MockClip(id: "c3", game: laneDash, player: "noor.runs",
                 caption: "the near miss at the end. I stopped breathing", length: "0:38", comments: "121", shares: "640"),
        MockClip(id: "c4", game: inkland, player: "juno",
                 caption: "took a fifth of the map in one loop", length: "0:27", comments: "76", shares: "305"),
        MockClip(id: "c5", game: spiralDrop, player: "kaz",
                 caption: "eleven floors without touching red", length: "0:35", comments: "198", shares: "977"),
        MockClip(id: "c6", game: gulpCity, player: "tofu",
                 caption: "swallowed the whole block with two seconds left", length: "0:29", comments: "88", shares: "412"),
    ]

    // MARK: A finished round of Tippy Tower

    static let roundGame = tippyTower
    static let roundScore = "41"
    static let roundScoreLabel = "floors"
    static let roundLength = "2m 48s"
    static let roundGold = 3
    static let roundBalanceBefore = 409
    static let roundIsBest = true

    // MARK: A round that reaches the daily limit, in Lane Dash

    static let capGame = laneDash
    static let capRoundGold = 2
    static let capBalanceAfter = 400
    static var capOtherGamesWithGold: Int { games.filter { !$0.isFullToday }.count }

    // MARK: Today

    /// The games that gave gold today, most gold first, each with the time played.
    static var todayGames: [(game: MockGame, minutes: String)] {
        let played = LiveStore.shared.s.secondsToday
        return games.filter { $0.earnedToday > 0 }
            .sorted { $0.earnedToday > $1.earnedToday }
            .map { ($0, LiveStore.playedText(played[$0.id] ?? 0)) }
    }

    /// Each studio that gave gold today, most gold first, with the names of its games.
    static var studioCapsToday: [(studio: String, earned: Int, games: String)] {
        var rows: [(studio: String, earned: Int, games: String)] = []
        for game in games where !rows.contains(where: { $0.studio == game.studio }) {
            let earned = LiveStore.shared.studioEarned(game.studio)
            guard earned > 0 else { continue }
            let titles = games.filter { $0.studio == game.studio }.map(\.title).joined(separator: ", ")
            rows.append((game.studio, earned, titles))
        }
        return rows.sorted { $0.earned > $1.earned }
    }

    // The thing Mira is saving for
    static let savingTitle = "Gilded tower"
    static let savingDetail = "A skin for Tippy Tower"
    static let savingPrice = 500
    static let savingEta = "About two more days"

    /// Everything collected or spent, newest first: the player's own rounds, then the story so far.
    /// The story's rows add up to the starting numbers (Lane Dash 98, Tippy Tower 12, Five Up 4).
    static var transactions: [MockTransaction] {
        let own = LiveStore.shared.s.txns.map { entry in
            MockTransaction(title: entry.title, detail: entry.detail, amount: entry.amount,
                            time: LiveStore.timeText(entry.date), game: games.first { $0.id == entry.gameID }?.kind)
        }
        return own + [
            MockTransaction(title: "Extra guess", detail: "Spent in Five Up", amount: -5, time: "11:20", game: .fiveUp),
            MockTransaction(title: "Five Up", detail: "4m played", amount: 4, time: "11:18", game: .fiveUp),
            MockTransaction(title: "Lane Dash", detail: "1h 38m played", amount: 98, time: "10:02", game: .laneDash),
            MockTransaction(title: "Tippy Tower", detail: "12m played", amount: 12, time: "08:40", game: .tippyTower),
            MockTransaction(title: "Comet trail", detail: "Spent in Lane Dash", amount: -40, time: "Yesterday", game: .laneDash),
            MockTransaction(title: "Spiral Drop", detail: "8m played", amount: 7, time: "Yesterday", game: .spiralDrop),
        ]
    }

    // MARK: Spending

    static let shop = [
        MockShopItem(title: "Extra guess", detail: "A seventh try, this round only", price: 5, game: .fiveUp, symbol: "plus.square.fill"),
        MockShopItem(title: "Slow slab", detail: "Next 3 slabs slide at half speed", price: 8, game: .tippyTower, symbol: "tortoise.fill"),
        MockShopItem(title: "Second chance", detail: "Carry on from where you fell", price: 6, game: .spiralDrop, symbol: "arrow.uturn.up"),
        MockShopItem(title: "Comet trail", detail: "Cosmetic. Yours to keep", price: 40, game: .laneDash, symbol: "sparkles"),
        MockShopItem(title: "Gilded tower", detail: "Cosmetic. Yours to keep", price: 500, game: .tippyTower, symbol: "building.2.fill"),
    ]
    static let spendItem = shop[1]

    // MARK: Leaderboard (Tippy Tower, friends, today)

    static let leaderboard = [
        MockRank(rank: 1, name: "devon.plays", score: "58", isYou: false),
        MockRank(rank: 2, name: "kaz", score: "49", isYou: false),
        MockRank(rank: 3, name: "mira", score: "41", isYou: true),
        MockRank(rank: 4, name: "noor.runs", score: "37", isYou: false),
        MockRank(rank: 5, name: "tofu", score: "33", isYou: false),
        MockRank(rank: 6, name: "juno", score: "29", isYou: false),
        MockRank(rank: 7, name: "wordnerd.sam", score: "22", isYou: false),
    ]

    // MARK: Studio (Mira also publishes Spiral Drop, as Wobble Works)

    static let myStudio = "Wobble Works"
    static let studioPlaysToday = "12.4K"
    static let studioMinutesToday = "19.6K"
    static let studioGoldPaidToday = "17.9K"
    /// What an average player collected from the studio today, out of its 300.
    static let studioAvgPerPlayer = 41
    static let studioApproval = 93
    static let studioPlaysByDay = [5.2, 6.1, 5.8, 7.9, 9.4, 11.0, 12.4]

    // The review of a submitted game
    static let reviewGame = spiralDrop
    static let reviewSessions = 240
    static let reviewMedianSession = "2m 04s"
    static let reviewRate = "0.9"
    static let reviewPerRound = "About 2 gold a round"
    static let reviewChecks: [(title: String, detail: String)] = [
        ("Gold needs real play", "Gold comes from playing. Standing still gives none."),
        ("No shortcuts found", "240 test plays. No way to collect gold without playing."),
        ("Fair difficulty", "It gets harder after level 8, so long runs take real skill."),
        ("Original work", "Name and art are not copied from another game."),
    ]

    // MARK: Inbox

    static let notifications = [
        MockNotification(symbol: "sun.max.fill", title: "You can collect gold again",
                         detail: "Your limits reset. 3 new clips since yesterday.", time: "08:00", unread: true),
        MockNotification(symbol: "trophy.fill", title: "devon.plays passed your tower",
                         detail: "58 floors. You are on 41.", time: "08:20", unread: true),
        MockNotification(symbol: "checkmark.seal.fill", title: "Spiral Drop is live",
                         detail: "Reviewed at 0.9 gold a minute. It is in Videos now.", time: "Yesterday", unread: false),
        MockNotification(symbol: "hand.thumbsup.fill", title: "1,204 new likes on Spiral Drop",
                         detail: "92% of votes are likes.", time: "Yesterday", unread: false),
        MockNotification(symbol: "flame.fill", title: "Six days running",
                         detail: "One round today keeps it going.", time: "Yesterday", unread: false),
    ]
}
