import SwiftUI

// LIBRARY, the last tab: everything that is yours. The games you played lately, every game with your
// best and the ones you saved, rooms to play with friends, and the clips you posted. Tapping a game
// opens its sheet, which holds everything you can do with it.

struct LibraryScreen: View {
    @ObservedObject private var store = LiveStore.shared
    @ObservedObject private var clips = CreateClips.shared
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
                                .opens(.libraryGame(game.id))
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
            clipGrid

            HomeSectionTitle(title: "Saved clips")
            savedGrid
        }
        .defaultScrollAnchor(MockArgs.value("-scroll") == "bottom" ? .bottom : .top)
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
            Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                ForEach(Array(stride(from: 0, to: games.count, by: 2)), id: \.self) { start in
                    GridRow {
                        ForEach(games[start..<min(start + 2, games.count)]) { game in
                            LibraryGameTile(game: game, saved: store.saved.contains(game.id))
                        }
                        if start + 1 == games.count { Color.clear.gridCellUnsizedAxes(.vertical) }
                    }
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
                DLTextKey(title: "Start a room", style: .ink).opens(.startRoom)
            }
        }
        .dlCard(padding: 14)
    }

    @ViewBuilder private var clipGrid: some View {
        if clips.mine.isEmpty {
            DLEmptyState(symbol: "video.fill", title: "No clips yet", detail: "Film yourself playing with the + button.",
                         key: "Open camera") { LiveNav.shared.open(.create(nil)) }
        } else {
            ClipGrid(items: clips.mine.map { .posted($0) }, source: .mine)
        }
    }

    @ViewBuilder private var savedGrid: some View {
        if clips.saved.isEmpty {
            DLEmptyState(symbol: "bookmark.fill", title: "Nothing saved yet",
                         detail: "Tap the bookmark on a clip in Videos to keep it here.",
                         key: "Go to Videos") { LiveNav.shared.goToTab(1) }
        } else {
            ClipGrid(items: clips.saved, source: .saved)
        }
    }
}

/// A game in the Library grid: its cover, title and your best. Everything else is in its sheet.
struct LibraryGameTile: View {
    let game: MockGame
    let saved: Bool

    var body: some View {
        let best = LiveBoard.yourBest(game)
        let played = best.value != "0"
        VStack(alignment: .leading, spacing: 0) {
            ClipStill(game: game, showHUD: false, focusY: 0.3)
                .frame(height: 124)
                .overlay(alignment: .topTrailing) {
                    if saved {
                        Image(systemName: "bookmark.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(DL.onGold)
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(DL.gold))
                            .padding(8)
                            .accessibilityLabel("Saved")
                    }
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(game.title.uppercased())
                    .font(DL.display(21)).foregroundStyle(DL.ink)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(played ? "Best \(best.value) \(best.detail)" : "Not played yet")
                    .font(DL.text(12, .medium)).foregroundStyle(played ? DL.ink2 : DL.ink3)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
        }
        .background(DL.surface)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .opens(.libraryGame(game.id))
    }
}

/// One of your clips in the Library grid, in the shape it plays in.
struct LibraryClipTile: View {
    let clip: ConvexClip

    var body: some View {
        Color.clear
            .aspectRatio(9 / 16, contentMode: .fit)
            .overlay {
                if clip.kind == "photo", let address = clip.url, let url = URL(string: address) {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        DL.sunken
                    }
                } else {
                    ClipStill(game: Mock.game(clip.gameSlug), showHUD: false, focusY: 0.2)
                        .overlay {
                            if let address = clip.url, let url = URL(string: address) { ClipVideoFrame(url: url) }
                        }
                }
            }
            .overlay(LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom))
            .overlay(alignment: .topTrailing) {
                if clip.visibility == "private" {
                    Image(systemName: "lock.fill").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                        .padding(7).background(Circle().fill(.black.opacity(0.6))).padding(6)
                } else if clip.visibility == "friends" {
                    Image(systemName: "person.2.fill").font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                        .padding(6).background(Circle().fill(.black.opacity(0.5))).padding(6)
                }
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(clip.gameTitle.uppercased()).font(DL.display(15)).lineLimit(1).minimumScaleFactor(0.7)
                    HStack(spacing: 4) {
                        Image(systemName: clip.kind == "photo" ? "photo.fill" : "play.fill").font(.system(size: 9, weight: .bold))
                        Text(clip.scoreText ?? groupedNumber(Int(clip.likes))).font(DL.label(10)).lineLimit(1)
                    }
                }
                .foregroundStyle(.white)
                .padding(8)
            }
            .clipShape(RoundedRectangle(cornerRadius: DL.tileRadius, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Your \(clip.gameTitle) clip")
    }
}

/// A game's sheet from the Library: its cover, your best, and every way to play it.
struct LibraryGameSheet: View {
    let game: MockGame
    @ObservedObject private var store = LiveStore.shared
    @State private var starting = false
    @State private var problem: String?

    var body: some View {
        let best = LiveBoard.yourBest(game)
        let played = best.value != "0"
        let saved = store.saved.contains(game.id)
        let multiplayer = game.playerRange.upperBound > 1
        DLSheet(height: multiplayer ? 640 : 572) {
            EmptyView()
        } content: {
            VStack(alignment: .leading, spacing: 14) {
                ClipStill(game: game, showHUD: false, focusY: 0.3)
                    .frame(height: 176)
                    .clipShape(RoundedRectangle(cornerRadius: DL.cardRadius, style: .continuous))
                    .overlay(alignment: .topTrailing) {
                        DLMediaButton(symbol: "xmark", size: 36).goesBack().padding(10).accessibilityLabel("Close")
                    }

                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(game.title.uppercased()).font(DL.display(38)).foregroundStyle(DL.ink)
                            .lineLimit(1).minimumScaleFactor(0.6)
                        Text("\(game.players), \(game.mode.lowercased())").font(DL.text(14)).foregroundStyle(DL.ink2)
                    }
                    Spacer(minLength: 12)
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("Your best").dlLabel()
                        Text(played ? best.value : "None yet").font(DL.display(played ? 34 : 22)).foregroundStyle(DL.ink)
                            .monospacedDigit()
                        if played { Text(best.detail).font(DL.text(12)).foregroundStyle(DL.ink2) }
                    }
                }

                HStack(spacing: 8) {
                    DLMeter(value: Double(game.leftToday), total: Double(game.capToday), height: 4)
                    Text("\(game.leftToday) gold left today").font(DL.label(10)).foregroundStyle(DL.goldText).monospacedDigit()
                }
                .accessibilityElement(children: .combine)

                if let problem {
                    Text(problem).font(DL.text(14)).foregroundStyle(DL.danger)
                }

                DLPlayKey().tap { LiveNav.shared.replaceTop(.gameReady(game.id)) }

                if multiplayer {
                    HStack(spacing: 10) {
                        DLTextKey(title: starting ? "Starting" : "Start a room", symbol: "person.2.fill", style: .ink)
                            .tap(startRoom)
                        DLTextKey(title: "Join with a code", style: .neutral)
                            .tap { LiveNav.shared.replaceTop(.join) }
                    }
                }

                HStack(spacing: 10) {
                    DLTextKey(title: saved ? "Saved" : "Save", symbol: saved ? "bookmark.fill" : "bookmark", style: .neutral)
                        .tap { store.toggleSave(game.id) }
                        .accessibilityLabel(saved ? "Unsave" : "Save")
                    DLTextKey(title: "Game page", symbol: "info.circle", style: .neutral)
                        .tap { LiveNav.shared.replaceTop(.gameDetail(game.id)) }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func startRoom() {
        guard !starting else { return }
        starting = true
        problem = nil
        Task { @MainActor in
            do {
                let code = try await ConvexLink.shared.mutate("rooms:create", ["slug": game.id], as: String.self)
                LiveNav.shared.replaceTop(.room(code))
            } catch {
                problem = LiveRoomRound.message(for: error)
            }
            starting = false
        }
    }
}

/// One of your clips from the Library, full screen, played the way Videos plays it.
struct LibraryClipScreen: View {
    let clipID: String

    var body: some View {
        ClipsViewer(source: .mine, start: clipID)
    }
}
