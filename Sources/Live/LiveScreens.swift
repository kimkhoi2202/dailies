import SwiftUI

// What the app adds to the designed screens: a friends leaderboard for every game, a search that
// searches, and comments you can add to.

// MARK: Leaderboards

/// The friends leaderboard of a game: each friend's score today, and the player's own best.
enum LiveBoard {
    private struct Entry {
        let name: String
        let score: Int
        var isYou = false
    }

    /// Friends' scores today, in each game's own score.
    private static let friendScores: [String: KeyValuePairs<String, Int>] = [
        "tippy-tower": ["devon.plays": 58, "kaz": 49, "noor.runs": 37, "tofu": 33, "juno": 29, "wordnerd.sam": 22],
        "five-up": ["wordnerd.sam": 1640, "kaz": 1385, "devon.plays": 1210, "juno": 960, "tofu": 725, "noor.runs": 80],
        "lane-dash": ["noor.runs": 2410, "devon.plays": 1980, "kaz": 1650, "juno": 1180, "tofu": 760, "wordnerd.sam": 420],
        "inkland": ["juno": 342, "kaz": 281, "devon.plays": 236, "tofu": 174, "noor.runs": 152, "wordnerd.sam": 96],
        "spiral-drop": ["kaz": 742, "devon.plays": 651, "wordnerd.sam": 518, "noor.runs": 434, "tofu": 371, "juno": 196],
        "gulp-city": ["tofu": 87, "juno": 74, "noor.runs": 61, "devon.plays": 52, "kaz": 38, "wordnerd.sam": 24],
        "slip-out": ["kaz": 71, "wordnerd.sam": 64, "juno": 55, "devon.plays": 47, "noor.runs": 39, "tofu": 26],
        "wild-eights": ["kaz": 131, "juno": 112, "devon.plays": 96, "wordnerd.sam": 74, "tofu": 41, "noor.runs": 33],
        "daily-grid": ["kaz": 812, "wordnerd.sam": 690, "devon.plays": 544, "juno": 418, "tofu": 305, "noor.runs": 160],
        "letter-rush": ["wordnerd.sam": 3500, "kaz": 2900, "devon.plays": 2600, "juno": 2100, "noor.runs": 1900, "tofu": 1200],
        "pour-party": ["kaz": 1500, "wordnerd.sam": 1200, "juno": 1000, "devon.plays": 700, "tofu": 400, "noor.runs": 300],
    ]

    /// Everyone on the board, best score first. The server's board once it has answered; until then
    /// the sample scores above.
    private static func board(for game: MockGame) -> [Entry] {
        let store = LiveStore.shared
        let live = store.board(for: game.id)
        var entries = live.isEmpty
            ? (friendScores[game.id] ?? [:]).map { Entry(name: $0.key, score: $0.value) }
            : live.map { Entry(name: $0.handle, score: Int($0.score.rounded()), isYou: $0.you) }
        // The player's newest best may be a moment ahead of the server's board.
        let best = store.s.best[game.id] ?? 0
        if let mine = entries.firstIndex(where: \.isYou) {
            if best > entries[mine].score { entries[mine] = Entry(name: entries[mine].name, score: best, isYou: true) }
        } else {
            entries.append(Entry(name: Mock.handle, score: best, isYou: true))
        }
        return entries.sorted { $0.score > $1.score }
    }

    /// What a score in this game counts.
    static func unit(for game: MockGame) -> String {
        switch game.kind {
        case .tippyTower: "floors"
        case .fiveUp, .spiralDrop, .blockParty, .wildEights, .letterRush: "points"
        case .laneDash: "metres"
        case .inkland: "share of the land"
        case .gulpCity: "share of the city"
        case .slipOut: "arrows"
        case .brickOut: "points"
        case .dailyGrid: "points"
        case .pourParty: "points"
        case .deepEnd: "metres"
        case .jamSlide: "points"
        case .busRush: "riders"
        case .cornerPocket: "points"
        }
    }

    /// A score the way its game writes it. Inkland keeps its share in tenths of a percent.
    static func text(_ score: Int, _ game: MockGame) -> String {
        switch game.kind {
        case .inkland: String(format: "%.1f%%", Double(score) / 10)
        case .gulpCity: "\(score)%"
        case .brickOut: groupedNumber(score)
        case .dailyGrid: groupedNumber(score)
        case .pourParty: groupedNumber(score)
        case .deepEnd: groupedNumber(score)
        case .jamSlide: groupedNumber(score)
        case .busRush: groupedNumber(score)
        case .cornerPocket: groupedNumber(score)
        default: groupedNumber(score)
        }
    }

    /// The distance between two scores in words: "9 floors", "8.1%".
    private static func gap(_ a: Int, _ b: Int, _ game: MockGame) -> String {
        let apart = abs(a - b)
        switch game.kind {
        case .tippyTower: return apart == 1 ? "1 floor" : "\(apart) floors"
        case .fiveUp, .spiralDrop, .blockParty, .wildEights, .letterRush: return apart == 1 ? "1 point" : "\(groupedNumber(apart)) points"
        case .laneDash: return "\(groupedNumber(apart)) m"
        case .inkland, .gulpCity: return text(apart, game)
        case .slipOut: return apart == 1 ? "1 arrow" : "\(apart) arrows"
        case .brickOut: return apart == 1 ? "1 point" : "\(groupedNumber(apart)) points"
        case .dailyGrid: return apart == 1 ? "1 point" : "\(groupedNumber(apart)) points"
        case .pourParty: return apart == 1 ? "1 point" : "\(groupedNumber(apart)) points"
        case .deepEnd: return "\(groupedNumber(apart)) m"
        case .jamSlide: return apart == 1 ? "1 point" : "\(groupedNumber(apart)) points"
        case .busRush: return apart == 1 ? "1 rider" : "\(groupedNumber(apart)) riders"
        case .cornerPocket: return apart == 1 ? "1 point" : "\(groupedNumber(apart)) points"
        }
    }

    static func ranks(for game: MockGame) -> [MockRank] {
        board(for: game).enumerated().map { place, entry in
            // A player with no rounds shows a plain 0, never "0.0%".
            let score = entry.isYou && entry.score == 0 ? "0" : text(entry.score, game)
            return MockRank(rank: place + 1, name: entry.name, score: score, isYou: entry.isYou)
        }
    }

    /// Three rows for the game's page: the top of the board, with the player always among them.
    static func preview(for game: MockGame) -> [MockRank] {
        let all = ranks(for: game)
        let top = all.prefix(3)
        return top.contains(where: \.isYou) ? Array(top) : Array(all.prefix(2)) + all.filter(\.isYou)
    }

    /// The line under a name, saying where it stands against the leader.
    static func context(for rank: MockRank, game: MockGame) -> String {
        let all = board(for: game)
        guard let leader = all.first, all.indices.contains(rank.rank - 1) else { return "" }
        let entry = all[rank.rank - 1]
        if rank.isYou && entry.score == 0 { return "Play a round to get on the board" }
        switch rank.rank {
        case 1: return "Leading today"
        case _ where rank.isYou: return "\(gap(leader.score, entry.score, game)) behind \(leader.name)"
        case 2: return "\(gap(leader.score, entry.score, game)) off the lead"
        default: return ""
        }
    }

    /// The small line on the Play key: who to pass next, and the score that does it.
    static func passText(for game: MockGame) -> String {
        let all = board(for: game)
        guard let place = all.firstIndex(where: \.isYou) else { return "" }
        guard place > 0 else { return "YOU LEAD TODAY" }
        let ahead = all[place - 1]
        return "PASS \(ahead.name.uppercased()) AT \(text(ahead.score + 1, game))"
    }

    static func yourBest(_ game: MockGame) -> (value: String, detail: String) {
        let saved = LiveStore.shared.s
        guard let best = saved.best[game.id], best != 0 else { return ("0", "no rounds yet") }
        return (text(best, game), saved.bestUnit[game.id] ?? unit(for: game))
    }
}

// MARK: Search

/// Search that searches. With nothing typed and no category picked it shows the three designed shelves.
struct LiveSearchScreen: View {
    @ObservedObject private var store = LiveStore.shared
    @State private var query = ""
    @State private var category = "All"
    @FocusState private var typing: Bool

    private var words: String { query.trimmingCharacters(in: .whitespaces).lowercased() }

    /// Games in the chosen category whose title, studio, category or player count holds the typed words.
    private var matches: [MockGame] {
        let words = words
        return Mock.games.filter { game in
            guard category == "All" || game.category == category || game.mode == category else { return false }
            guard !words.isEmpty else { return true }
            return [game.title, game.studio, game.category, game.players].contains { $0.lowercased().contains(words) }
        }
    }

    var body: some View {
        DLPage(spacing: 0, bottomInset: 60) {
            HStack(alignment: .center, spacing: 10) {
                DLIconButton(symbol: "chevron.left").goesBack().accessibilityLabel("Back")
                Text("SEARCH").font(DL.display(40)).foregroundStyle(DL.ink)
                Spacer()
                DLGoldChip(onMedia: false).opens(.gold)
            }
            field.padding(.top, 10)
            categories.padding(.top, 4)
            if words.isEmpty && category == "All" { shelves } else { results }
        }
        .scrollDismissesKeyboard(.immediately)
    }

    private var field: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").font(.system(size: 17, weight: .semibold)).foregroundStyle(DL.ink)
            TextField("Games, studios, players", text: $query)
                .font(DL.text(16)).foregroundStyle(DL.ink).tint(DL.ink)
                .focused($typing)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .submitLabel(.search)
            if !query.isEmpty {
                Image(systemName: "xmark.circle.fill").font(.system(size: 17)).foregroundStyle(DL.ink3)
                    .tap { query = "" }
                    .accessibilityLabel("Clear")
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .background(DL.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var categories: some View {
        edgeToEdgeRow(spacing: 5) {
            ForEach(G1ExploreData.filters, id: \.self) { name in
                DLTag(text: name, filled: name == category).fixedSize()
                    // taller than the tag itself, so it is easy to hit
                    .padding(.vertical, 8)
                    .tap { withAnimation(.snappy(duration: 0.2)) { category = name } }
            }
        }
    }

    private var results: some View {
        let found = matches
        return VStack(alignment: .leading, spacing: 8) {
            G1SectionTitle(title: found.isEmpty ? "No games found" : found.count == 1 ? "1 game" : "\(found.count) games")
                .padding(.top, 10)
            if found.isEmpty {
                Text("Try a different word, or pick All.").font(DL.text(15)).foregroundStyle(DL.ink2)
            } else {
                rankedList(found)
            }
        }
    }

    @ViewBuilder private var shelves: some View {
        let open = Mock.clips.filter { !$0.game.isFullToday }.sorted { $0.game.earnedToday < $1.game.earnedToday }
        G1SectionTitle(title: "Still has gold today", link: "All \(open.count)").padding(.top, 10)
        edgeToEdgeRow(spacing: G1ExploreData.cardGap) {
            ForEach(open) { clip in
                G1GoldLeftCard(clip: clip).opens(.gameReady(clip.game.id))
            }
        }
        .padding(.top, 8)

        G1SectionTitle(title: "Most liked this week").padding(.top, 18)
        rankedList(Array(Mock.games.sorted { $0.approval > $1.approval }.prefix(4))).padding(.top, 8)

        G1SectionTitle(title: "New and reviewed").padding(.top, 18)
        edgeToEdgeRow(spacing: G1ExploreData.cardGap) {
            ForEach(G1ExploreData.newlyReviewed, id: \.game.id) { entry in
                G1NewCard(game: entry.game, when: entry.when).opens(.gameReady(entry.game.id))
            }
        }
        .padding(.top, 8)
    }

    /// Numbered rows in one card. Each row opens its game's page.
    private func rankedList(_ games: [MockGame]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(games.enumerated()), id: \.element.id) { place, game in
                if place > 0 { DLDivider(inset: 70) }
                G1LikedRow(rank: place + 1, game: game).opens(.gameDetail(game.id))
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 4)
        .dlCard(padding: 0)
    }

    /// A sideways scroller that runs to both screen edges, with its first item on the page margin.
    private func edgeToEdgeRow<Items: View>(spacing: CGFloat, @ViewBuilder _ items: () -> Items) -> some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: spacing, content: items)
                .padding(.horizontal, DL.margin)
        }
        .scrollIndicators(.hidden)
        .padding(.horizontal, -DL.margin)
    }
}

// MARK: Comments

enum LiveComments {
    /// What people said under each clip: a comment, the poster's reply, then two more.
    static func seeded(for clip: MockClip) -> [G1Comment] {
        let lines: [(name: String, time: String, text: String, likes: String)]
        switch clip.id {
        case "c2": lines = [
            ("kaz", "3h", "five still counts. I needed all six", "88"),
            (clip.player, "3h", "six counts. barely", "41"),
            ("juno", "1h", "started with the same word as you and still lost", "57"),
            ("tofu", "20m", "my group chat is also furious", "12"),
        ]
        case "c3": lines = [
            ("devon.plays", "1h", "that near miss took a year off my life", "143"),
            (clip.player, "1h", "mine too", "60"),
            ("kaz", "40m", "that distance is unreal. rematch tonight", "77"),
            ("juno", "9m", "I crash at the same barrier every time", "15"),
        ]
        case "c4": lines = [
            ("tofu", "2h", "you took my whole corner in one loop", "64"),
            (clip.player, "2h", "it was right there", "39"),
            ("noor.runs", "1h", "never leave your land for that long. unless it works", "48"),
            ("kaz", "15m", "playing this with four people is chaos", "21"),
        ]
        case "c5": lines = [
            ("devon.plays", "3h", "eleven floors with no red is not normal", "102"),
            (clip.player, "3h", "I was not breathing", "70"),
            ("wordnerd.sam", "50m", "the combo smash is the best part", "36"),
            ("tofu", "5m", "trying to beat this now", "8"),
        ]
        case "c6": lines = [
            ("juno", "2h", "you ate the bus with two seconds left", "55"),
            (clip.player, "2h", "hungry", "31"),
            ("noor.runs", "1h", "I always go for the trees first", "27"),
            ("devon.plays", "30m", "three of us on one block and you still came first", "19"),
        ]
        default: return G1CommentsData.comments
        }
        // Ids run c2a, c2b, c2c, c2d. The second line is always the poster replying to the first.
        return lines.enumerated().map { index, line in
            G1Comment(id: clip.id + ["a", "b", "c", "d"][index], name: line.name, time: line.time, text: line.text,
                      likes: line.likes, isClipOwner: index == 1, isReply: index == 1)
        }
    }
}

/// The comments sheet: it scrolls, and the player can add a comment.
struct LiveCommentsScreen: View {
    let clip: MockClip
    @ObservedObject private var store = LiveStore.shared
    @State private var draft = ""
    @FocusState private var typing: Bool

    /// Everyone's comments on this clip's game from the server, newest first. nil until the first answer.
    private var posted: [ConvexComment]? {
        _ = store.comments(forGame: clip.game.id)
        return store.gameComments[clip.game.id]
    }

    /// The player's own comments first while they are on their way, then everyone's. Before the
    /// server answers, the sample lines stand in.
    private var comments: [G1Comment] {
        let own = store.s.comments.filter { $0.clipID == clip.id }
        guard let posted else {
            return own.map { G1Comment(id: $0.id.uuidString, name: Mock.handle, time: "now", text: $0.text, likes: "0") }
                + LiveComments.seeded(for: clip)
        }
        let landed = Set(posted.filter(\.mine).map { LiveStore.stableID($0.id) })
        let sending = own.filter { mine in !landed.contains(mine.id) && !posted.contains { $0.mine && $0.body == mine.text } }
        return sending.map { G1Comment(id: $0.id.uuidString, name: Mock.handle, time: "now", text: $0.text, likes: "0") }
            + posted.map {
                G1Comment(id: $0.id, name: $0.handle, time: Self.ago($0.at), text: $0.body,
                          likes: Mock.compact($0.likes ?? 0), isClipOwner: $0.handle == clip.player)
            }
    }

    /// "now", "12m", "3h", "2d": how long ago a comment was posted.
    private static func ago(_ milliseconds: Double) -> String {
        let minutes = Int(max(0, Date().timeIntervalSince1970 - milliseconds / 1000) / 60)
        if minutes < 1 { return "now" }
        if minutes < 60 { return "\(minutes)m" }
        if minutes < 24 * 60 { return "\(minutes / 60)h" }
        return "\(minutes / (24 * 60))d"
    }

    var body: some View {
        DLSheet(height: 560) {
            EmptyView()
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 8) {
                    Text("Comments").font(DL.text(17, .semibold)).foregroundStyle(DL.ink)
                    Text(posted.map { "\($0.count)" } ?? clip.comments).font(DL.text(17)).foregroundStyle(DL.ink2)
                    Spacer()
                    DLIconButton(symbol: "xmark", size: 32).goesBack().accessibilityLabel("Close")
                }
                .padding(.horizontal, 20)

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(comments) { G1CommentRow(comment: $0) }
                    }
                    .padding(.horizontal, 20).padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)

                DL.line.frame(height: 1)
                composer
            }
        }
    }

    private var composer: some View {
        let empty = draft.isEmpty
        return HStack(spacing: 10) {
            DLAvatar(name: Mock.handle, size: 36)
            HStack(spacing: 8) {
                TextField("Add a comment", text: $draft)
                    .font(DL.text(15)).foregroundStyle(DL.ink).tint(DL.ink)
                    .focused($typing)
                    .submitLabel(.send)
                    .onSubmit(send)
                Image(systemName: "arrow.up").font(.system(size: 14, weight: .bold))
                    .foregroundStyle(empty ? DL.ink3 : DL.onInk)
                    .frame(width: 32, height: 32)
                    .background(empty ? DL.sunken : DL.ink, in: Circle())
                    .tap(send)
                    .accessibilityLabel("Send")
            }
            .padding(.leading, 16).padding(.trailing, 6)
            .frame(height: 44)
            .background(DL.body, in: Capsule())
        }
        // With the keyboard up the field sits right on it. Otherwise it clears the home indicator.
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, typing ? 12 : 28)
    }

    private func send() {
        guard !draft.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        store.addComment(draft, clipID: clip.id)
        draft = ""
    }
}
