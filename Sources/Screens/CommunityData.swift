import SwiftUI
import Combine
import ConvexMobile

// COMMUNITY's data: what friends played, scored and posted. It starts from a seeded story so the
// tab looks alive on first open, and takes the server's rows over once community:* answers.

enum CommunityPostKind: String {
    case best, passed, rated, streak, video, game
}

/// The four reactions a post can get. Drawn as symbols or letters, never as emoji.
enum CommunityReaction: String, CaseIterable {
    case gg, fire, crown, clap

    var symbol: String? {
        switch self {
        case .gg: nil
        case .fire: "flame.fill"
        case .crown: "crown.fill"
        case .clap: "hands.clap.fill"
        }
    }

    var label: String {
        switch self {
        case .gg: "GG"
        case .fire: "Fire"
        case .crown: "Crown"
        case .clap: "Clap"
        }
    }
}

struct CommunityPost: Identifiable, Equatable {
    let id: String
    let name: String
    let kind: CommunityPostKind
    let gameID: String
    /// "1,125", already formatted.
    let score: String
    /// "points", "floors". Empty for a rating.
    let unit: String
    let rating: Double?
    let at: Date
    var reactions: [String: Int]
    var mine: Set<String>
    var comments: Int
    /// true for a row the server knows, so reactions on it are sent on.
    var remote: Bool = false

    var game: MockGame { Mock.game(gameID) }

    /// "set a new best in Five Up"
    var action: String {
        switch kind {
        case .best: "set a new best in \(game.title)"
        case .passed: "passed you in \(game.title)"
        case .rated: "rated \(game.title) \(CommunityStore.ratingText(rating ?? 0))"
        case .streak: "is on a \(score) day streak"
        case .video: "posted a clip of \(game.title)"
        case .game: "made a new game, \(game.title)"
        }
    }
}

struct CommunityStory: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let gameID: String
    let score: String
    let unit: String
    let at: Date
    var game: MockGame { Mock.game(gameID) }
}

struct CommunityLive: Identifiable, Equatable {
    var id: String { gameID }
    let gameID: String
    let friends: [String]
    var game: MockGame { Mock.game(gameID) }
}

struct CommunityChallenge: Identifiable, Equatable {
    let id: String
    let from: String
    let gameID: String
    let target: String
    let unit: String
    let expires: Date
    var game: MockGame { Mock.game(gameID) }
}

struct CommunityNote: Identifiable, Equatable {
    let id: String
    let name: String
    let symbol: String
    let text: String
    let at: Date
    var unread: Bool
    let gameID: String?
}

/// How the player rated a game, Beli style: a band, then a place in that band's list.
enum CommunityBand: String, CaseIterable, Codable {
    case loved, fine, not

    var title: String {
        switch self {
        case .loved: "Loved it"
        case .fine: "It was fine"
        case .not: "Not for me"
        }
    }

    var symbol: String {
        switch self {
        case .loved: "heart.fill"
        case .fine: "hand.thumbsup.fill"
        case .not: "hand.thumbsdown.fill"
        }
    }

    /// The scores a band covers, best first.
    var range: (top: Double, bottom: Double) {
        switch self {
        case .loved: (10.0, 6.8)
        case .fine: (6.7, 4.0)
        case .not: (3.9, 0.5)
        }
    }
}

// MARK: Server rows

struct CommunityPostRow: Decodable {
    let _id: String
    let name: String
    let own: Bool?
    let kind: String
    let gameSlug: String
    let score: Double?
    let scoreText: String?
    let unit: String?
    let rating: Double?
    let at: Double
    let reactions: [String: Double]?
    let mine: [String]?
    let comments: Double?
}

struct CommunityHomeRow: Decodable {
    struct Live: Decodable { let gameSlug: String; let names: [String] }
    struct Challenge: Decodable {
        let _id: String; let from: String; let gameSlug: String; let targetText: String; let unit: String?; let expiresAt: Double
    }
    struct Note: Decodable {
        let _id: String; let name: String; let kind: String; let text: String; let at: Double; let read: Bool; let gameSlug: String?
    }
    struct FriendRating: Decodable { let gameSlug: String; let score: Double; let count: Double }
    let live: [Live]
    let challenges: [Challenge]
    let notifications: [Note]
    let friendRatings: [FriendRating]?
}

// MARK: Store

final class CommunityStore: ObservableObject {
    static let shared = CommunityStore()

    @Published private(set) var posts: [CommunityPost]
    @Published private(set) var live: [CommunityLive]
    @Published private(set) var challenges: [CommunityChallenge]
    @Published private(set) var notes: [CommunityNote]
    @Published private(set) var seenStories: Set<String> = []
    /// The player's own ranked lists, best first, by band.
    @Published private(set) var ranked: [String: [String]]
    @Published private(set) var myScores: [String: Double]
    /// What friends rate each game, out of 10.
    @Published private(set) var friendScores: [String: Double]

    private var bag = Set<AnyCancellable>()
    private var watches: [AnyCancellable] = []
    private var serverPosts: [CommunityPost]?
    private var localPosts: [CommunityPost] = []
    private var ratedToday: [String: String]
    private static let ratingsKey = "dailies.community.ratings.v1"

    private struct SavedRatings: Codable {
        var ranked: [String: [String]]
        var scores: [String: Double]
        var ratedDay: [String: String]
    }

    private init() {
        posts = CommunitySeed.posts
        live = CommunitySeed.live
        challenges = CommunitySeed.challenges
        notes = CommunitySeed.notes
        friendScores = CommunitySeed.friendScores
        if let data = UserDefaults.standard.data(forKey: Self.ratingsKey),
           let saved = try? JSONDecoder().decode(SavedRatings.self, from: data) {
            ranked = saved.ranked
            myScores = saved.scores
            ratedToday = saved.ratedDay
        } else {
            ranked = CommunitySeed.myRanked
            myScores = CommunitySeed.myScores
            ratedToday = [:]
        }
        guard !ProcessInfo.processInfo.arguments.contains("-screen") else { return }
        ConvexLink.shared.signedIn.sink { [weak self] on in
            guard let self else { return }
            self.watches.removeAll()
            if on { self.openWatches() }
        }.store(in: &bag)
    }

    // MARK: Reading the server

    private func openWatches() {
        let link = ConvexLink.shared
        watches = [
            link.watch("community:feed", as: [CommunityPostRow].self) { [weak self] rows in
                self?.takeFeed(rows)
            },
            link.watch("community:home", as: CommunityHomeRow.self) { [weak self] home in
                self?.takeHome(home)
            },
        ]
    }

    private func takeFeed(_ rows: [CommunityPostRow]) {
        guard !rows.isEmpty else { return }
        serverPosts = rows.map { row in
            var counts: [String: Int] = [:]
            for (key, value) in row.reactions ?? [:] { counts[key] = Int(value) }
            let scoreText = row.scoreText ?? row.score.map { groupedNumber(Int($0.rounded())) } ?? ""
            return CommunityPost(id: row._id, name: row.own == true ? Mock.handle : row.name, kind: CommunityPostKind(rawValue: row.kind) ?? .best,
                                 gameID: row.gameSlug, score: scoreText, unit: row.unit ?? "", rating: row.rating,
                                 at: Date(timeIntervalSince1970: row.at / 1000), reactions: counts,
                                 mine: Set(row.mine ?? []), comments: Int(row.comments ?? 0), remote: true)
        }
        rebuildPosts()
    }

    private func takeHome(_ home: CommunityHomeRow) {
        if !home.live.isEmpty {
            live = home.live.map { CommunityLive(gameID: $0.gameSlug, friends: $0.names) }
        }
        if !home.challenges.isEmpty {
            challenges = home.challenges.map {
                CommunityChallenge(id: $0._id, from: $0.from, gameID: $0.gameSlug, target: $0.targetText, unit: $0.unit ?? "",
                                   expires: Date(timeIntervalSince1970: $0.expiresAt / 1000))
            }
        }
        let remoteNotes = home.notifications.map {
            CommunityNote(id: $0._id, name: $0.name, symbol: Self.noteSymbol($0.kind), text: $0.text,
                          at: Date(timeIntervalSince1970: $0.at / 1000), unread: !$0.read, gameID: $0.gameSlug)
        }
        if !remoteNotes.isEmpty {
            let seeded = CommunitySeed.notes.map { note -> CommunityNote in
                var copy = note
                copy.unread = notes.first { $0.id == note.id }?.unread ?? note.unread
                return copy
            }
            notes = (remoteNotes + seeded).sorted { $0.at > $1.at }
        }
        for row in home.friendRatings ?? [] { friendScores[row.gameSlug] = row.score }
    }

    private static func noteSymbol(_ kind: String) -> String {
        switch kind {
        case "reaction": "flame.fill"
        case "comment": "bubble.fill"
        case "challenge": "flag.checkered"
        case "follow": "person.badge.plus"
        case "live": "dot.radiowaves.left.and.right"
        default: "bell.fill"
        }
    }

    private func rebuildPosts() {
        let base = serverPosts ?? CommunitySeed.posts
        let ids = Set(base.map(\.id))
        posts = (localPosts.filter { !ids.contains($0.id) } + base).sorted { $0.at > $1.at }
    }

    // MARK: Stories

    /// One bubble per friend: their newest scored post from the last day, newest first.
    var stories: [CommunityStory] {
        var seen = Set<String>()
        var out: [CommunityStory] = []
        let dayAgo = Date().addingTimeInterval(-36 * 3600)
        for post in posts where post.name != Mock.handle && post.at > dayAgo && !seen.contains(post.name) {
            guard [.best, .passed, .video].contains(post.kind), !post.score.isEmpty else { continue }
            seen.insert(post.name)
            out.append(CommunityStory(name: post.name, gameID: post.gameID, score: post.score, unit: post.unit, at: post.at))
        }
        // Friends who have not played today still show, so the row is never thin.
        if out.count < 4 { out += CommunitySeed.stories.filter { story in !seen.contains(story.name) } }
        // Unseen stories come first.
        return out.filter { !seenStories.contains($0.name) } + out.filter { seenStories.contains($0.name) }
    }

    func markSeen(_ name: String) {
        if !seenStories.contains(name) { seenStories.insert(name) }
    }

    // MARK: Reactions

    func toggle(_ reaction: CommunityReaction, on postID: String) {
        guard let index = posts.firstIndex(where: { $0.id == postID }) else { return }
        var post = posts[index]
        let key = reaction.rawValue
        if post.mine.contains(key) {
            post.mine.remove(key)
            post.reactions[key] = max(0, (post.reactions[key] ?? 1) - 1)
        } else {
            post.mine.insert(key)
            post.reactions[key, default: 0] += 1
            if LiveStore.shared.s.haptics { GameHaptics.thud() }
        }
        posts[index] = post
        if let local = localPosts.firstIndex(where: { $0.id == postID }) { localPosts[local] = post }
        if let remote = serverPosts?.firstIndex(where: { $0.id == postID }) { serverPosts?[remote] = post }
        guard post.remote else { return }
        Task { try? await ConvexLink.shared.mutate("community:react", ["postId": postID, "kind": key]) }
    }

    // MARK: Notifications

    var unreadCount: Int { notes.filter(\.unread).count }

    func markAllRead() {
        guard unreadCount > 0 else { return }
        notes = notes.map { var n = $0; n.unread = false; return n }
        Task { try? await ConvexLink.shared.mutate("community:markRead", [:]) }
    }

    // MARK: Rounds and ratings

    /// After a round: a post for a new best, and the rating sheet once a day per game.
    func roundEnded(_ summary: RoundSummary) {
        let game = Mock.game(summary.gameID)
        if summary.isBest && summary.result.score > 0 {
            let post = CommunityPost(id: "local-\(UUID().uuidString)", name: Mock.handle, kind: .best, gameID: game.id,
                                     score: summary.result.scoreText ?? groupedNumber(summary.result.score),
                                     unit: summary.result.unit, rating: nil, at: Date(), reactions: [:], mine: [], comments: 0)
            localPosts.insert(post, at: 0)
            rebuildPosts()
        }
        let today = LiveStore.dayKey(Date())
        guard ratedToday[game.id] != today else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            if LiveNav.shared.topRoute == .results { LiveNav.shared.open(.rate(game.id)) }
        }
    }

    /// The games already in a band's list, best first, without the one being rated.
    func list(_ band: CommunityBand, excluding gameID: String) -> [String] {
        (ranked[band.rawValue] ?? []).filter { $0 != gameID }
    }

    /// Puts the game at its place in the band and works out its score. Returns the score.
    @discardableResult
    func save(_ gameID: String, band: CommunityBand, at place: Int) -> Double {
        var lists = ranked
        for key in lists.keys { lists[key]?.removeAll { $0 == gameID } }
        var list = lists[band.rawValue] ?? []
        let index = min(max(0, place), list.count)
        list.insert(gameID, at: index)
        lists[band.rawValue] = list
        var scores = myScores
        // Every game in the band moves with the new one, so each score follows its place.
        for (position, slug) in list.enumerated() {
            scores[slug] = Self.score(position: position, count: list.count, band: band)
        }
        ranked = lists
        myScores = scores
        let score = scores[gameID] ?? band.range.top
        ratedToday[gameID] = LiveStore.dayKey(Date())
        if let data = try? JSONEncoder().encode(SavedRatings(ranked: lists, scores: scores, ratedDay: ratedToday)) {
            UserDefaults.standard.set(data, forKey: Self.ratingsKey)
        }
        let post = CommunityPost(id: "local-\(UUID().uuidString)", name: Mock.handle, kind: .rated, gameID: gameID, score: "",
                                 unit: "", rating: score, at: Date(), reactions: [:], mine: [], comments: 0)
        localPosts.insert(post, at: 0)
        rebuildPosts()
        let args: [String: ConvexEncodable?] = ["slug": gameID, "band": band.rawValue, "rank": Double(index), "score": score]
        Task { try? await ConvexLink.shared.mutate("community:rate", args) }
        return score
    }

    // MARK: Presence

    private var presence: Task<Void, Never>?

    /// Tells the server every 30 seconds that the player is in this game, so friends see it under Live now.
    func startPresence(_ gameID: String) {
        presence?.cancel()
        guard ConvexLink.shared.isSignedIn else { return }
        presence = Task {
            while !Task.isCancelled {
                try? await ConvexLink.shared.mutate("community:heartbeat", ["slug": gameID])
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    func stopPresence() {
        presence?.cancel()
        presence = nil
    }

    func skipRating(_ gameID: String) {
        ratedToday[gameID] = LiveStore.dayKey(Date())
    }

    static func score(position: Int, count: Int, band: CommunityBand) -> Double {
        let range = band.range
        let step = count > 1 ? (range.top - range.bottom) / Double(count - 1) : 0
        return ((range.top - step * Double(position)) * 10).rounded() / 10
    }

    static func ratingText(_ score: Double) -> String { String(format: "%.1f", score) }

    /// "12M AGO", "3H AGO"
    static func ago(_ date: Date) -> String {
        let minutes = max(0, Int(Date().timeIntervalSince(date) / 60))
        if minutes < 1 { return "NOW" }
        if minutes < 60 { return "\(minutes)M AGO" }
        if minutes < 60 * 24 { return "\(minutes / 60)H AGO" }
        return "\(minutes / 1440)D AGO"
    }
}

// MARK: Seed

/// The story on first open: six friends and a day of play across our games.
enum CommunitySeed {
    static let friends = ["Khoi", "Ben", "Dylan", "Nyx", "Kiko", "Vanessa"]

    private static func minutes(_ m: Double) -> Date { Date().addingTimeInterval(-m * 60) }

    private static func post(_ id: Int, _ name: String, _ kind: CommunityPostKind, _ game: String, _ score: String, _ unit: String,
                             rating: Double? = nil, _ ago: Double, _ reactions: [String: Int], comments: Int = 0) -> CommunityPost {
        CommunityPost(id: "seed-\(id)", name: name, kind: kind, gameID: game, score: score, unit: unit, rating: rating,
                      at: minutes(ago), reactions: reactions, mine: [], comments: comments)
    }

    static let posts: [CommunityPost] = [
        post(1, "Dylan", .best, "five-up", "1,125", "points", 12, ["gg": 6, "fire": 9, "crown": 2, "clap": 3], comments: 4),
        post(2, "Ben", .passed, "spiral-drop", "23", "floors", 34, ["gg": 3, "fire": 4, "crown": 0, "clap": 1], comments: 2),
        post(3, "Khoi", .rated, "gulp-city", "", "", rating: 8.7, 51, ["gg": 1, "fire": 2, "crown": 0, "clap": 5]),
        post(4, "Vanessa", .streak, "tippy-tower", "5", "", 75, ["gg": 0, "fire": 12, "crown": 1, "clap": 4], comments: 1),
        post(5, "Nyx", .video, "lane-dash", "2,840", "m", 96, ["gg": 8, "fire": 15, "crown": 3, "clap": 2], comments: 7),
        post(6, "Kiko", .best, "tippy-tower", "76", "floors", 130, ["gg": 4, "fire": 6, "crown": 5, "clap": 1], comments: 3),
        post(7, "Khoi", .best, "inkland", "34.2%", "of the map", 170, ["gg": 2, "fire": 3, "crown": 1, "clap": 0]),
        post(8, "Ben", .rated, "five-up", "", "", rating: 9.4, 215, ["gg": 2, "fire": 1, "crown": 0, "clap": 3]),
        post(9, "Dylan", .video, "gulp-city", "87%", "of the block", 260, ["gg": 5, "fire": 7, "crown": 0, "clap": 2], comments: 2),
        post(10, "Vanessa", .best, "spiral-drop", "31", "floors", 330, ["gg": 3, "fire": 2, "crown": 1, "clap": 1]),
        post(11, "Nyx", .rated, "tippy-tower", "", "", rating: 8.9, 420, ["gg": 1, "fire": 1, "crown": 0, "clap": 2]),
        post(12, "Kiko", .passed, "lane-dash", "3,110", "m", 510, ["gg": 6, "fire": 2, "crown": 1, "clap": 0], comments: 5),
        post(13, "Khoi", .game, "spiral-drop", "", "", 640, ["gg": 9, "fire": 11, "crown": 4, "clap": 8], comments: 12),
        post(14, "Ben", .best, "gulp-city", "92%", "of the block", 800, ["gg": 2, "fire": 3, "crown": 0, "clap": 1]),
    ]

    static let stories: [CommunityStory] = [
        CommunityStory(name: "Nyx", gameID: "lane-dash", score: "2,840", unit: "m", at: minutes(96)),
        CommunityStory(name: "Vanessa", gameID: "spiral-drop", score: "31", unit: "floors", at: minutes(330)),
    ]

    static let live: [CommunityLive] = [
        CommunityLive(gameID: "inkland", friends: ["Dylan", "Kiko", "Nyx"]),
        CommunityLive(gameID: "five-up", friends: ["Ben", "Khoi"]),
    ]

    static let challenges: [CommunityChallenge] = [
        CommunityChallenge(id: "seed-c1", from: "Khoi", gameID: "tippy-tower", target: "76", unit: "floors",
                           expires: Date().addingTimeInterval(5 * 3600 + 42 * 60)),
        CommunityChallenge(id: "seed-c2", from: "Vanessa", gameID: "five-up", target: "1,200", unit: "points",
                           expires: Date().addingTimeInterval(20 * 3600)),
    ]

    static let notes: [CommunityNote] = [
        CommunityNote(id: "seed-n1", name: "Khoi", symbol: "flag.checkered", text: "Khoi challenged you to beat 76 floors in Tippy Tower",
                      at: minutes(18), unread: true, gameID: "tippy-tower"),
        CommunityNote(id: "seed-n2", name: "Dylan", symbol: "dot.radiowaves.left.and.right", text: "Dylan is playing Inkland now",
                      at: minutes(26), unread: true, gameID: "inkland"),
        CommunityNote(id: "seed-n3", name: "Nyx", symbol: "flame.fill", text: "Nyx reacted to your Lane Dash run",
                      at: minutes(64), unread: true, gameID: "lane-dash"),
        CommunityNote(id: "seed-n4", name: "Ben", symbol: "bubble.fill", text: "Ben commented: how is that even possible",
                      at: minutes(140), unread: false, gameID: nil),
        CommunityNote(id: "seed-n5", name: "Kiko", symbol: "person.badge.plus", text: "Kiko started following you",
                      at: minutes(300), unread: false, gameID: nil),
    ]

    static let friendScores: [String: Double] = [
        "five-up": 9.1, "tippy-tower": 8.6, "spiral-drop": 8.4, "gulp-city": 8.7, "lane-dash": 7.9, "inkland": 7.6,
    ]

    static let myRanked: [String: [String]] = [
        "loved": ["five-up", "spiral-drop"],
        "fine": ["lane-dash"],
    ]
    static let myScores: [String: Double] = ["five-up": 10.0, "spiral-drop": 6.8, "lane-dash": 6.7]
}
