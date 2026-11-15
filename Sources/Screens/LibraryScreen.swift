import SwiftUI

// LIBRARY, the last tab: everything that is yours. The games you played lately, every game with your
// best and the ones you saved, rooms to play with friends, and the clips you posted.

struct LibraryScreen: View {
    @ObservedObject private var store = LiveStore.shared
    @State private var query = ""
    @State private var filter = "All"

    private static let filters = ["All", "Played", "Saved", "Multiplayer", "Casual", "Competitive"]

    /// The games you played most recently, newest first, each once.
    private var recent: [MockGame] {
        var seen = Set<String>()
        return store.history.compactMap { round in
            guard seen.insert(round.gameSlug).inserted else { return nil }
            return Mock.games.first { $0.id == round.gameSlug }
        }
    }

    private var listed: [MockGame] {
        let words = query.trimmingCharacters(in: .whitespaces).lowercased()
        let played = Set(store.history.map(\.gameSlug)).union(store.s.best.filter { $0.value > 0 }.keys)
        return Mock.games.filter { game in
            guard words.isEmpty || game.title.lowercased().contains(words) else { return false }
            switch filter {
            case "Played": return played.contains(game.id)
            case "Saved": return store.saved.contains(game.id)
            case "Multiplayer": return game.playerRange.upperBound > 1
            case "Casual", "Competitive": return game.mode == filter
            default: return true
            }
        }
    }

    var body: some View {
        DLPage(spacing: 18) {
            HStack(alignment: .center) {
                Text("LIBRARY").font(DL.display(44)).foregroundStyle(DL.ink)
                Spacer()
                DLGoldChip(onMedia: false).opens(.gold)
            }

            searchField
            filters

            if !recent.isEmpty {
                HomeSectionTitle(title: "Jump back in")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(recent) { game in
                            let best = LiveBoard.yourBest(game)
                            ContinueCard(game: game, note: "Your best: \(best.value) \(best.detail)")
                                .opens(.gameReady(game.id))
                        }
                    }
                }
                .scrollClipDisabled()
            }

            HomeSectionTitle(title: "Your games")
            gameGrid

            HomeSectionTitle(title: "Play with friends")
            friendsCard

            HomeSectionTitle(title: "Your clips")
            DLEmptyState(symbol: "video.fill", title: "No clips yet", detail: "Film yourself playing with the + button.",
                         key: "Open camera") { LiveNav.shared.open(.create(nil)) }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 15, weight: .semibold)).foregroundStyle(DL.ink2)
            TextField("Search your games", text: $query)
                .font(DL.text(16)).foregroundStyle(DL.ink).tint(DL.ink)
                .submitLabel(.search)
            if !query.isEmpty {
                Image(systemName: "xmark.circle.fill").font(.system(size: 16)).foregroundStyle(DL.ink3)
                    .tap { query = "" }
                    .accessibilityLabel("Clear")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(DL.surface, in: Capsule())
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Self.filters, id: \.self) { name in
                    let chosen = name == filter
                    Text(name)
                        .font(DL.text(14, .semibold))
                        .foregroundStyle(chosen ? DL.onInk : DL.ink)
                        .padding(.horizontal, 13)
                        .frame(height: 36)
                        .background(Capsule().fill(chosen ? DL.ink : DL.surface))
                        .fixedSize()
                        .tap { withAnimation(.snappy(duration: 0.25)) { filter = name } }
                }
            }
        }
        .scrollClipDisabled()
    }

    @ViewBuilder private var gameGrid: some View {
        let games = listed
        if games.isEmpty {
            DLEmptyState(symbol: filter == "Saved" ? "bookmark.fill" : "square.stack.fill",
                         title: filter == "Saved" ? "Nothing saved yet" : "No games here",
                         detail: filter == "Saved" ? "Open a game and tap Save to keep it here." : "Try another filter or search.",
                         key: "Show all games") {
                withAnimation(.snappy(duration: 0.25)) { filter = "All"; query = "" }
            }
        } else {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(games) { game in
                    LibraryGameTile(game: game, saved: store.saved.contains(game.id))
                }
            }
        }
    }

    private var friendsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                HStack(spacing: -8) {
                    ForEach(Array(Mock.friends.prefix(3)), id: \.self) { friend in
                        DLAvatar(name: friend, size: 32).overlay(Circle().strokeBorder(DL.surface, lineWidth: 2))
                    }
                }
                Text("Play the same round with up to 6 friends, live.")
                    .font(DL.text(15, .medium)).foregroundStyle(DL.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 10) {
                DLTextKey(title: "Join a room", style: .neutral).opens(.join)
                DLTextKey(title: "Start a room").opens(.startRoom)
            }
        }
        .dlCard(padding: 14)
    }
}

/// A game in the Library grid: its cover, title, players, your best and the gold it still has today.
/// Tapping it opens its sheet, where you play, start a room or save it.
struct LibraryGameTile: View {
    let game: MockGame
    let saved: Bool

    var body: some View {
        let best = LiveBoard.yourBest(game)
        let played = best.value != "0"
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 0) {
                ClipStill(game: game, showHUD: false, focusY: 0.3)
                    .frame(height: 118)
                VStack(alignment: .leading, spacing: 3) {
                    Text(game.title.uppercased())
                        .font(DL.display(21)).foregroundStyle(DL.ink)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Text(game.players).font(DL.text(12, .medium)).foregroundStyle(DL.ink2).lineLimit(1)
                    Text(played ? "Best \(best.value) \(best.detail)" : "Not played yet")
                        .font(DL.text(12, .semibold)).foregroundStyle(played ? DL.ink : DL.ink3)
                        .lineLimit(1).minimumScaleFactor(0.8)
                    HStack(spacing: 6) {
                        DLMeter(value: Double(game.leftToday), total: Double(game.capToday), height: 4)
                        Text("\(game.leftToday)").font(DL.label(10)).foregroundStyle(DL.goldText).monospacedDigit()
                    }
                    .padding(.top, 5)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(game.leftToday) gold left today")
                }
                .padding(.horizontal, 11).padding(.vertical, 10)
            }
            .background(DL.surface)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .opens(.libraryGame(game.id))

            if saved {
                Image(systemName: "bookmark.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(DL.onGold)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(DL.gold))
                    .padding(8)
                    .allowsHitTesting(false)
                    .accessibilityLabel("Saved")
            }
        }
    }
}
