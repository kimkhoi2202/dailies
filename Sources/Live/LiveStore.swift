import SwiftUI
import Combine
import ConvexMobile

// The real app's state: gold, daily limits, votes, best scores and settings.
// Gold, limits, streak, bests, votes, comments and the gold history live in Convex and arrive here
// through live queries. Appearance and the settings switches stay on the phone.

/// true when the app runs as the real, interactive app. false when it runs as the screenshot
/// harness (launched with `-screen <id>`), where every screen shows its fixed demo content.
enum LiveMode {
    static var on = false
}

struct LiveTxn: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var detail: String
    var amount: Int
    var date: Date
    var gameID: String?
}

struct LiveComment: Codable, Identifiable, Equatable {
    var id = UUID()
    var clipID: String
    var text: String
    var date: Date
}

/// What the results screen shows after a round.
struct RoundSummary: Equatable {
    var gameID: String
    var result: GameResult
    var seconds: Double
    /// Gold added to the balance by this round.
    var gold: Int
    var balanceBefore: Int
    var earnedTodayAfter: Int
    var isBest: Bool
    /// The player's best in this game before this round. 0 means no rounds yet.
    var bestBefore: Int = 0
    /// This round took the game to its daily limit.
    var hitLimit: Bool
    /// The game (or its studio) had already reached its limit before the round.
    var wasFull: Bool
    var solo: Bool
}

final class LiveStore: ObservableObject {
    static let shared = LiveStore()

    static let perGameCap = 100
    static let perStudioCap = 300
    /// "Faster gold" multiplies the rate by this, so a short demo round still shows gold arriving.
    static let fastFactor = 10.0

    struct Saved: Codable, Equatable {
        var balance = 0
        var day = ""
        var earned: [String: Int] = [:]
        var secondsToday: [String: Double] = [:]
        var carry: [String: Double] = [:]
        var votes: [String: Bool] = [:]
        var best: [String: Int] = [:]
        var txns: [LiveTxn] = []
        var owned: [String] = []
        var comments: [LiveComment] = []
        var likedComments: [String] = []
        /// 0 = follow the phone, 1 = light, 2 = dark
        var appearance = 0
        var fastGold = true
        var haptics = true
        var rounds = 0
        var streak = 0
        var lastPlayDay = ""
        var pinnedSaving = true
        /// Settings switches, by title. Missing = the default for that switch.
        var toggles: [String: Bool] = [:]
        /// What each game's best score counts: "floors", "m".
        var bestUnit: [String: String] = [:]
        var bestText: [String: String] = [:]
    }

    /// The server's numbers, with any change still on its way to the server laid on top.
    @Published var s: Saved { didSet { savedChanged(from: oldValue) } }
    @Published var lastRound: RoundSummary?

    // Straight from Convex, for screens that want more than `s` holds.
    @Published private(set) var signedIn = false
    @Published private(set) var me: ConvexMe?
    @Published private(set) var catalog: [ConvexGame] = [] { didSet { if catalog != oldValue { catalogVersion += 1 } } }
    /// Goes up each time the catalog changes, so anything built from it knows to rebuild.
    private(set) var catalogVersion = 0
    @Published private(set) var boards: [String: [ConvexRank]] = [:]
    @Published private(set) var gameComments: [String: [ConvexComment]] = [:]
    /// The player's finished rounds, newest first.
    @Published private(set) var history: [ConvexHistoryRound] = []
    /// The games the player saved in the Library.
    @Published private(set) var saved: Set<String> = []
    /// The games this player is making or has made in the studio, newest first.
    @Published private(set) var creations: [ConvexCreation] = []
    @Published private(set) var creationDetails: [String: ConvexCreationDetail] = [:]

    private static let cacheKey = "dailies.live.convex.v1"

    private let link = ConvexLink.shared
    /// false in the screenshot harness, which never talks to the server.
    private let live: Bool
    private var bag = Set<AnyCancellable>()
    private var watches: [AnyCancellable] = []
    private var boardWatches: [String: AnyCancellable] = [:]
    private var commentWatches: [String: AnyCancellable] = [:]
    private var creationWatches: [String: AnyCancellable] = [:]

    // The newest answer from each live query.
    private var lastMe: ConvexMe?
    private var lastGames: [ConvexGame]?
    private var lastLedger: [ConvexLedgerRow]?
    private var lastMyComments: [ConvexMyComment]?
    private var lastLiked: [String]?

    /// true while `s` is being set from here, so the change is not sent back to the server.
    private var applying = false
    /// Changes sent to the server that have not been answered yet. Server numbers wait until this is 0.
    private var pendingWrites = 0
    /// Player snapshots older than this would undo a change of ours that has already landed.
    private var minChanges = 0

    /// The round open on the server for the game being played.
    private struct OpenRound {
        var gameID: String
        var day: String
        var lastSeconds: Double
        var start: Task<ConvexRoundStart, Error>
    }
    private var openRound: OpenRound?

    private init() {
        live = !ProcessInfo.processInfo.arguments.contains("-screen")
        if let data = UserDefaults.standard.data(forKey: Self.cacheKey),
           let cached = try? JSONDecoder().decode(Saved.self, from: data) {
            s = cached
        } else {
            s = Self.fresh()
        }
        rollDayIfNeeded()
        guard live else { return }
        link.signedIn.sink { [weak self] on in self?.signedInChanged(on) }.store(in: &bag)
        link.start()
    }

    private static func fresh() -> Saved {
        var v = Saved()
        v.day = dayKey(Date())
        return v
    }

    /// Starts again with a brand new account and nothing on the phone.
    func reset() {
        forgetServer()
        setQuietly(Self.fresh())
        lastRound = nil
        if live { link.startOver() }
    }

    /// Moves this phone to another account once `prepare` has signed in to it, and drops what was kept for the old one.
    @MainActor
    func switchAccount(_ prepare: @escaping (DeviceAuth) async throws -> Void) async throws {
        try await link.switchAccount(prepare)
        forgetServer()
        setQuietly(Self.fresh())
        lastRound = nil
    }

    // MARK: Server

    private func signedInChanged(_ on: Bool) {
        signedIn = on
        closeWatches()
        if on { openWatches() }
    }

    private func closeWatches() {
        watches.removeAll()
        boardWatches.removeAll()
        commentWatches.removeAll()
        creationWatches.removeAll()
    }

    private func forgetServer() {
        lastMe = nil; lastGames = nil; lastLedger = nil; lastMyComments = nil; lastLiked = nil
        me = nil
        minChanges = 0
        openRound = nil
        boards = [:]
        gameComments = [:]
        history = []
        saved = []
        creations = []
        creationDetails = [:]
    }

    private func openWatches() {
        let day: [String: ConvexEncodable?] = ["day": s.day]
        watches = [
            link.watch("users:me", day, as: ConvexMe?.self) { [weak self] value in
                guard let self, let value else { return }
                self.lastMe = value
                self.me = value
                self.rebuild()
            },
            link.watch("games:list", day, as: [ConvexGame].self) { [weak self] value in
                guard let self else { return }
                self.lastGames = value
                self.catalog = value
                self.rebuild()
            },
            link.watch("ledger:list", as: [ConvexLedgerRow]?.self) { [weak self] value in
                guard let self, let value else { return }
                self.lastLedger = value
                self.rebuild()
            },
            link.watch("social:myComments", as: [ConvexMyComment]?.self) { [weak self] value in
                guard let self, let value else { return }
                self.lastMyComments = value
                self.rebuild()
            },
            link.watch("social:likedComments", as: [String]?.self) { [weak self] value in
                guard let self, let value else { return }
                self.lastLiked = value
                self.rebuild()
            },
            link.watch("rounds:history", as: [ConvexHistoryRound].self) { [weak self] value in
                self?.history = value
            },
            link.watch("library:mySaved", as: [String].self) { [weak self] value in
                self?.saved = Set(value)
            },
            link.watch("creations:mine", as: [ConvexCreation].self) { [weak self] value in
                self?.creations = value
            },
        ]
    }

    /// Lays the newest server answers over `s`. Waits while a change of ours is still in flight.
    private func rebuild() {
        guard pendingWrites == 0 else { return }
        var v = s

        if let me = lastMe, Int(me.changes ?? 0) >= minChanges {
            v.balance = Int(me.gold.rounded())
            v.streak = Int(me.streak)
            v.rounds = Int(me.rounds)
            v.fastGold = me.fastGold
            v.owned = me.owned ?? []
            if me.playedToday { v.lastPlayDay = v.day } else if v.lastPlayDay == v.day { v.lastPlayDay = "" }
            v.earned = [:]; v.secondsToday = [:]; v.carry = [:]
            for row in me.earnings {
                if row.gold > 0 { v.earned[row.gameSlug] = Int(row.gold.rounded()) }
                v.secondsToday[row.gameSlug] = row.playMs / 1000
                if let carry = row.carry, carry > 0 { v.carry[row.gameSlug] = carry }
            }
        }

        if let games = lastGames {
            v.votes = [:]; v.best = [:]; v.bestUnit = [:]; v.bestText = [:]
            for game in games {
                if game.vote != 0 { v.votes[game.slug] = game.vote > 0 }
                guard let best = game.best, best > 0 else { continue }
                let score = Int(best.rounded())
                v.best[game.slug] = score
                v.bestUnit[game.slug] = game.bestUnit ?? game.unit
                v.bestText[game.slug] = game.bestText ?? groupedNumber(score)
            }
        }

        if let ledger = lastLedger {
            v.txns = ledger.map {
                LiveTxn(id: Self.stableID($0.id), title: $0.title, detail: $0.detail, amount: Int($0.amount.rounded()),
                        date: Date(timeIntervalSince1970: $0.at / 1000), gameID: $0.gameSlug)
            }
        }

        if let mine = lastMyComments {
            v.comments = mine.map { row in
                LiveComment(id: Self.stableID(row.id), clipID: Mock.clips.first { $0.game.id == row.gameSlug }?.id ?? row.gameSlug,
                            text: row.body, date: Date(timeIntervalSince1970: row.at / 1000))
            }
        }

        if let liked = lastLiked { v.likedComments = liked }

        setQuietly(v)
    }

    private func setQuietly(_ v: Saved) {
        guard v != s else { return }
        applying = true
        s = v
        applying = false
    }

    /// Sends one change to the server. The server's numbers are held back until it is answered.
    private func write(_ work: @escaping () async throws -> Void) {
        guard live else { return }
        pendingWrites += 1
        Task { @MainActor in
            try? await work()
            self.pendingWrites -= 1
            self.rebuild()
        }
    }

    private func savedChanged(from old: Saved) {
        if let data = try? JSONEncoder().encode(s) { UserDefaults.standard.set(data, forKey: Self.cacheKey) }
        guard !applying else { return }
        // A screen changed `s` directly: pass on the parts the server keeps.
        if s.fastGold != old.fastGold {
            let fast = s.fastGold
            write { try await self.link.mutate("users:update", ["fastGold": fast]) }
        }
        if s.likedComments != old.likedComments {
            let now = Set(s.likedComments), before = Set(old.likedComments)
            for key in now.symmetricDifference(before) {
                let liked = now.contains(key)
                write { try await self.link.mutate("social:likeComment", ["key": key, "liked": liked]) }
            }
        }
    }

    /// A stable local id for a row the server knows by a string id.
    static func stableID(_ text: String) -> UUID {
        var a: UInt64 = 0xcbf2_9ce4_8422_2325, b: UInt64 = 0x9e37_79b9_7f4a_7c15
        for byte in text.utf8 {
            a = (a ^ UInt64(byte)) &* 0x100_0000_01b3
            b = (b ^ UInt64(byte) ^ (a >> 29)) &* 0x100_0000_01b3
        }
        var u = [UInt8](repeating: 0, count: 16)
        for i in 0..<8 {
            u[i] = UInt8(truncatingIfNeeded: a >> UInt64(8 * i))
            u[8 + i] = UInt8(truncatingIfNeeded: b >> UInt64(8 * i))
        }
        return UUID(uuid: (u[0], u[1], u[2], u[3], u[4], u[5], u[6], u[7], u[8], u[9], u[10], u[11], u[12], u[13], u[14], u[15]))
    }

    // MARK: Days

    static func dayKey(_ d: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Daily limits reset at local midnight.
    func rollDayIfNeeded() {
        let today = Self.dayKey(Date())
        guard s.day != today else { return }
        var v = s
        v.day = today
        v.earned = [:]
        v.secondsToday = [:]
        v.carry = [:]
        lastMe = nil
        setQuietly(v)
        // The live queries are asked per day, so ask again for the new one.
        if signedIn {
            watches.removeAll()
            openWatches()
        }
    }

    /// "5h 12m": time until the limits reset.
    var resetIn: String {
        let now = Date()
        let midnight = Calendar.current.nextDate(after: now, matching: DateComponents(hour: 0, minute: 0),
                                                 matchingPolicy: .nextTime) ?? now.addingTimeInterval(3600)
        let minutes = max(1, Int(midnight.timeIntervalSince(now) / 60))
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }

    // MARK: Gold

    func earnedToday(_ gameID: String) -> Int { s.earned[gameID] ?? 0 }

    var earnedTodayTotal: Int { s.earned.values.reduce(0, +) }

    func studioEarned(_ studio: String) -> Int {
        s.earned.reduce(0) { sum, entry in
            let owner = catalog.first { $0.slug == entry.key }?.studio ?? Mock.games.first { $0.id == entry.key }?.studio
            return owner == studio ? sum + entry.value : sum
        }
    }

    /// How much more gold this game can still give today, after both limits.
    func room(for game: MockGame) -> Int {
        max(0, min(Self.perGameCap - earnedToday(game.id), Self.perStudioCap - studioEarned(game.studio)))
    }

    /// Gold per second of play.
    func rate(for game: MockGame) -> Double {
        let perMinute = catalog.first { $0.slug == game.id }?.goldPerMinute ?? game.goldPerMinute
        return perMinute * (s.fastGold ? Self.fastFactor : 1) / 60
    }

    /// Gold a round has collected so far, and progress (0 to 1) toward the next one.
    func pending(for game: MockGame, seconds: Double) -> (gold: Int, toNext: Double) {
        noteRound(game.id, seconds: seconds)
        let room = room(for: game)
        let raw = (s.carry[game.id] ?? 0) + seconds * rate(for: game)
        let whole = Int(raw.rounded(.down))
        if whole >= room { return (room, room == 0 ? 0 : 1) }
        return (whole, raw - Double(whole))
    }

    /// Tells the server a round is starting, so it can time it. Safe to call more than once for one round.
    func beginRound(_ game: MockGame) {
        noteRound(game.id, seconds: 0)
    }

    /// The gold counter asks for `pending` all through a round. The first ask of a round opens it on the server.
    private func noteRound(_ gameID: String, seconds: Double) {
        guard live else { return }
        let today = Self.dayKey(Date())
        if var round = openRound, round.gameID == gameID, round.day == today, seconds + 0.01 >= round.lastSeconds {
            round.lastSeconds = seconds
            openRound = round
            return
        }
        // A clock that is already running with no open round is the round that just ended, still on screen.
        guard seconds < 1 else { return }
        openRound = OpenRound(gameID: gameID, day: today, lastSeconds: seconds, start: startRound(gameID, day: today))
    }

    private func startRound(_ gameID: String, day: String) -> Task<ConvexRoundStart, Error> {
        Task { try await self.link.mutate("rounds:start", ["slug": gameID, "day": day], as: ConvexRoundStart.self) }
    }

    /// Ends a round: adds its gold to the balance and records it.
    /// The numbers shown at once are worked out here the way the server does it; the server's answer then replaces them.
    @discardableResult
    func finishRound(game: MockGame, seconds: Double, result: GameResult, solo: Bool) -> RoundSummary {
        rollDayIfNeeded()
        var v = s
        let room = room(for: game)
        let raw = (v.carry[game.id] ?? 0) + seconds * rate(for: game)
        let whole = Int(raw.rounded(.down))
        let gold = min(whole, room)
        v.carry[game.id] = gold < whole ? 0 : raw - Double(whole)
        let before = v.balance
        v.balance += gold
        v.earned[game.id, default: 0] += gold
        v.secondsToday[game.id, default: 0] += seconds
        let bestBefore = v.best[game.id] ?? 0
        let isBest = result.score > 0 && result.score > bestBefore
        if isBest {
            v.best[game.id] = result.score
            v.bestUnit[game.id] = result.unit
            v.bestText[game.id] = result.scoreText ?? groupedNumber(result.score)
        }
        v.rounds += 1
        let nowFull = room - gold <= 0
        if gold > 0 {
            if v.lastPlayDay != v.day {
                v.streak += 1
                v.lastPlayDay = v.day
            }
            let detail = nowFull ? "Daily limit reached" : "\(Self.playedText(seconds)) played"
            v.txns.insert(LiveTxn(title: game.title, detail: detail, amount: gold, date: Date(), gameID: game.id), at: 0)
            if v.txns.count > 60 { v.txns.removeLast(v.txns.count - 60) }
        }
        setQuietly(v)
        let summary = RoundSummary(gameID: game.id, result: result, seconds: seconds, gold: gold,
                                   balanceBefore: before, earnedTodayAfter: earnedToday(game.id), isBest: isBest, bestBefore: bestBefore,
                                   hitLimit: nowFull && gold > 0, wasFull: room == 0, solo: solo)
        lastRound = summary
        settle(summary)
        return summary
    }

    /// Sends a finished round to the server and takes the server's word for what it was worth.
    private func settle(_ summary: RoundSummary) {
        guard live else { return }
        let gameID = summary.gameID, day = s.day
        let opened = openRound?.gameID == gameID ? openRound?.start : nil
        openRound = nil
        pendingWrites += 1
        Task { @MainActor in
            do {
                var started = try? await opened?.value
                if started == nil { started = try await self.startRound(gameID, day: day).value }
                var args: [String: ConvexEncodable?] = [
                    "roundId": started?.roundId ?? "",
                    "score": Double(summary.result.score),
                    "activeMs": (summary.seconds * 1000).rounded(),
                ]
                if !summary.result.unit.isEmpty { args["unit"] = summary.result.unit }
                if summary.result.score > 0 { args["scoreText"] = summary.result.scoreText ?? groupedNumber(summary.result.score) }
                let answer = try await self.link.mutate("rounds:finish", args, as: ConvexRoundFinish.self)
                self.minChanges = max(self.minChanges, Int(answer.changes ?? 0))
                if var shown = self.lastRound, shown == summary {
                    shown.gold = Int(answer.gold)
                    shown.balanceBefore = Int(answer.balance - answer.gold)
                    shown.earnedTodayAfter = Int(answer.today)
                    shown.isBest = answer.newBest
                    shown.hitLimit = answer.gold > 0 && answer.left <= 0
                    if shown != summary { self.lastRound = shown }
                }
            } catch {
                // The round did not reach the server. The numbers fall back to the server's below.
            }
            self.pendingWrites -= 1
            self.rebuild()
        }
    }

    /// Spends gold. Returns false when the balance is too low.
    @discardableResult
    func spend(_ item: MockShopItem) -> Bool {
        guard s.balance >= item.price else { return false }
        let game = Mock.games.first { $0.kind == item.game }
        var v = s
        v.balance -= item.price
        if !v.owned.contains(item.title) { v.owned.append(item.title) }
        v.txns.insert(LiveTxn(title: item.title, detail: "Spent in \(game?.title ?? "a game")", amount: -item.price,
                              date: Date(), gameID: game?.id), at: 0)
        setQuietly(v)
        let title = item.title
        write {
            // The server checks the balance and sets the price itself.
            let answer = try await self.link.mutate("shop:spend", ["item": title], as: ConvexSpend.self)
            self.minChanges = max(self.minChanges, Int(answer.changes ?? 0))
        }
        return true
    }

    /// Saves a game to the Library, or takes it out again.
    func toggleSave(_ gameID: String) {
        if saved.contains(gameID) { saved.remove(gameID) } else { saved.insert(gameID) }
        guard live else { return }
        Task { _ = try? await self.link.mutate("library:toggleSave", ["slug": gameID], as: Bool.self) }
    }

    // MARK: Settings switches

    func isOn(_ title: String, default d: Bool = true) -> Bool { s.toggles[title] ?? d }
    func flip(_ title: String, default d: Bool = true) { s.toggles[title] = !isOn(title, default: d) }

    // MARK: Votes, comments, leaderboards

    /// nil = not voted, true = liked, false = disliked
    func vote(for gameID: String) -> Bool? { s.votes[gameID] }

    /// Tapping the same vote again takes it back.
    func setVote(_ gameID: String, like: Bool) {
        guard LiveNav.shared.hasAccount(to: "like games") else { return }
        var v = s
        let next: Bool? = v.votes[gameID] == like ? nil : like
        v.votes[gameID] = next
        setQuietly(v)
        let value: Double = next == nil ? 0 : (like ? 1 : -1)
        write { try await self.link.mutate("social:vote", ["slug": gameID, "value": value]) }
    }

    func addComment(_ text: String, clipID: String) {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        var v = s
        v.comments.insert(LiveComment(clipID: clipID, text: body, date: Date()), at: 0)
        setQuietly(v)
        let slug = Mock.clip(clipID).game.id
        write { try await self.link.mutate("social:addComment", ["slug": slug, "body": String(body.prefix(280))]) }
    }

    /// The game's leaderboard from the server, best first. Empty until the first answer arrives.
    func board(for gameID: String) -> [ConvexRank] {
        if signedIn, boardWatches[gameID] == nil {
            boardWatches[gameID] = link.watch("social:leaderboard", ["slug": gameID], as: [ConvexRank].self) { [weak self] rows in
                self?.boards[gameID] = rows
            }
        }
        return boards[gameID] ?? []
    }

    /// Everyone's comments under a game from the server, newest first. Empty until the first answer arrives.
    func comments(forGame gameID: String) -> [ConvexComment] {
        if signedIn, commentWatches[gameID] == nil {
            commentWatches[gameID] = link.watch("social:comments", ["slug": gameID], as: [ConvexComment].self) { [weak self] rows in
                self?.gameComments[gameID] = rows
            }
        }
        return gameComments[gameID] ?? []
    }

    // MARK: Making games

    /// A game in the making with its whole conversation, from the server. nil until the first answer arrives.
    func creation(_ id: String) -> ConvexCreationDetail? {
        if signedIn, creationWatches[id] == nil {
            creationWatches[id] = link.watch("creations:get", ["creationId": id], as: ConvexCreationDetail?.self) { [weak self] value in
                guard let self, let value else { return }
                self.creationDetails[id] = value
            }
        }
        return creationDetails[id]
    }

    /// Opens a creation with the maker's first wish. Returns its id once the server has it.
    func startCreation(_ text: String) async throws -> String {
        try await link.mutate("creations:start", ["text": text], as: String.self)
    }

    /// Adds the maker's next line to a creation.
    func sendWish(_ text: String, to creationID: String) async throws {
        try await link.mutate("creations:send", ["creationId": creationID, "text": text])
    }

    /// Asks the studio again after it failed to answer.
    func retryCreation(_ creationID: String) async throws {
        try await link.mutate("creations:retry", ["creationId": creationID])
    }

    /// Throws a creation away, with the game it became.
    func removeCreation(_ creationID: String) {
        creations.removeAll { $0.id == creationID }
        creationDetails[creationID] = nil
        creationWatches[creationID] = nil
        write { try await self.link.mutate("creations:remove", ["creationId": creationID]) }
    }

    /// The maker is happy with the sheet: the studio writes it out in full.
    func finishCreation(_ creationID: String) async throws {
        try await link.mutate("creations:finish", ["creationId": creationID])
    }

    // MARK: Text helpers

    /// "2m 48s"
    static func playedText(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        if total >= 3600 { return "\(total / 3600)h \(total % 3600 / 60)m" }
        if total >= 60 { return "\(total / 60)m \(String(format: "%02d", total % 60))s" }
        return "\(total)s"
    }

    static func timeText(_ d: Date) -> String {
        if Date().timeIntervalSince(d) < 90 { return "Just now" }
        let calendar = Calendar.current
        if calendar.isDateInYesterday(d) { return "Yesterday" }
        let format = DateFormatter()
        format.dateFormat = calendar.isDateInToday(d) ? "HH:mm" : "d MMM"
        return format.string(from: d)
    }

    var colorScheme: ColorScheme? {
        switch s.appearance {
        case 1: return .light
        case 2: return .dark
        default: return nil
        }
    }
}

extension Mock {
    static func game(_ id: String) -> MockGame { games.first { $0.id == id } ?? tippyTower }
    static func clip(_ id: String) -> MockClip { clips.first { $0.id == id } ?? clips[0] }
}
