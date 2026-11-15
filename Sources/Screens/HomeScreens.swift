import SwiftUI

// HOME, the first tab: games to play with friends. They can be narrowed by how many people can play
// and by mood, casual or competitive. The gold balance lives here and never on the videos.

struct HomeSectionTitle: View {
    var title: String
    var link: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title.uppercased()).font(DL.display(26)).foregroundStyle(DL.ink)
            Spacer()
            if let link {
                Text(link).font(DL.text(14, .semibold)).foregroundStyle(DL.ink2)
            }
        }
    }
}

/// A game the player was in the middle of, with a line about where things stood.
struct ContinueCard: View {
    let game: MockGame
    let note: String

    private let width: CGFloat = 164

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ClipStill(game: game, showHUD: false, focusY: 0.3)
                .frame(width: width, height: 132)
                .overlay(alignment: .bottomTrailing) {
                    DLRoundPlayKey(size: 40).padding(8)
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(game.title.uppercased())
                    .font(DL.display(20))
                    .foregroundStyle(DL.ink)
                    .lineLimit(1)
                Text(note)
                    .font(DL.text(12, .medium))
                    .foregroundStyle(DL.ink2)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .frame(width: width)
        .background(DL.surface)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

struct HomeScreen: View {
    @ObservedObject private var live = LiveStore.shared
    @State private var filter = "All"

    /// The game on the big card: the one friends are in right now.
    private let spotlight = Mock.inkland

    /// The list under the last title. The app applies the chosen filter. The screenshot shows the story's three.
    private var listed: [MockGame] {
        guard LiveMode.on else { return [Mock.laneDash, Mock.inkland, Mock.gulpCity] }
        return Mock.games.filter { game in
            switch filter {
            case "2 players": return game.playerRange.contains(2)
            case "4 players": return game.playerRange.contains(4)
            case "6 players": return game.playerRange.contains(6)
            case "Casual", "Competitive": return game.mode == filter
            default: return true
            }
        }
    }

    var body: some View {
        DLTabs(selected: 0) {
            DLPage(spacing: 18) {
                HStack(spacing: 10) {
                    DLLogo(height: 36)
                    Spacer()
                    DLGoldChip(onMedia: false).opens(.gold)
                    DLIconButton(symbol: "magnifyingglass").opens(.search).accessibilityLabel("Search")
                    DLAvatar(name: Mock.handle, size: 36).opens(.profile("me")).accessibilityLabel("Your profile")
                }
                .padding(.bottom, 2)

                filters
                spotlightCard

                HomeSectionTitle(title: "Continue playing")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(Mock.continuePlaying.indices, id: \.self) { index in
                            let entry = Mock.continuePlaying[index]
                            ContinueCard(game: entry.game, note: ownNote(for: entry.game) ?? entry.note)
                                .opens(.gameReady(entry.game.id))
                        }
                    }
                }
                .scrollClipDisabled()

                HomeSectionTitle(title: LiveMode.on && filter != "All" ? filter : "Popular with friends", link: "See all")
                    .opens(.search)
                gameList
            }
        }
    }

    /// Who you are playing with, and in what mood.
    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Mock.playerFilters, id: \.self) { name in
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

    private var spotlightCard: some View {
        ZStack(alignment: .bottomLeading) {
            ClipStill(game: spotlight, showHUD: false, focusY: 0.42)
            LinearGradient(colors: [.black.opacity(0.35), .clear, .black.opacity(0.8)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    HStack(spacing: -8) {
                        ForEach(Array(Mock.friends.prefix(3)), id: \.self) { friend in
                            DLAvatar(name: friend, size: 26)
                                .overlay(Circle().strokeBorder(.black.opacity(0.5), lineWidth: 1.5))
                        }
                    }
                    Text("\(Mock.friendsOnline) friends are playing now")
                        .font(DL.text(13, .semibold))
                        .foregroundStyle(.white)
                }
                Spacer()
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(spotlight.title.uppercased()).font(DL.display(40)).foregroundStyle(.white)
                        HStack(spacing: 6) {
                            DLMediaTag(text: spotlight.players, symbol: "person.2.fill")
                            DLMediaTag(text: spotlight.mode)
                        }
                    }
                    Spacer()
                    DLRoundPlayKey(size: 58)
                }
            }
            .padding(16)
        }
        .frame(height: 226)
        .clipShape(RoundedRectangle(cornerRadius: DL.cardRadius, style: .continuous))
        .opens(.gameReady(spotlight.id))
    }

    private var gameList: some View {
        let games = listed
        return VStack(spacing: 0) {
            ForEach(games.indices, id: \.self) { index in
                let game = games[index]
                if index > 0 { DLDivider(inset: 64) }
                HStack(spacing: 12) {
                    DLThumb(game: game, size: 52)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(game.title).font(DL.text(16, .semibold)).foregroundStyle(DL.ink)
                        Text("\(game.players), \(game.mode.lowercased())").font(DL.text(13)).foregroundStyle(DL.ink2)
                    }
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: "hand.thumbsup.fill").font(.system(size: 12, weight: .semibold))
                        Text("\(game.approval)%").font(DL.display(22))
                    }
                    .foregroundStyle(DL.ink)
                }
                .padding(.vertical, 9)
                .contentShape(Rectangle())
                .opens(.gameReady(game.id))
            }
        }
        .dlCard(padding: 14)
    }

    /// In the app, the line under a game is the player's own best once they have one.
    private func ownNote(for game: MockGame) -> String? {
        guard LiveMode.on else { return nil }
        if let best = live.s.best[game.id], best > 0 {
            return "Your best: \(LiveBoard.text(best, game)) \(live.s.bestUnit[game.id] ?? "")"
        }
        // "41 floors" belongs to the story, not to this player. Until they have a score, show the game's own line.
        return game.kind == .tippyTower ? game.tagline : nil
    }
}

extension MockGame {
    /// The player counts in the label: "1 to 4 players" gives 1...4 and "2 players" gives 2...2.
    var playerRange: ClosedRange<Int> {
        let counts = players.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        guard let fewest = counts.first, let most = counts.last, fewest <= most else { return 1...1 }
        return fewest...most
    }

    /// true for a game that works alone and with others, such as "1 to 4 players".
    var playsBothWays: Bool { playerRange.lowerBound == 1 && playerRange.upperBound > 1 }

    /// The friends shown waiting on the game's screen: as many as the game has room for, two at most.
    var readyFriends: [String] {
        let seats = max(0, playerRange.upperBound - 1)
        return Array(Mock.playFriends.prefix(min(2, seats)))
    }
}

// THE GAME'S OWN SCREEN, where the Play button on a video leads. It shows the gold on offer and who
// can play, and friends can be brought in before the round starts.

struct GameReadyScreen: View {
    var game: MockGame = Mock.tippyTower
    @ObservedObject private var live = LiveStore.shared

    var body: some View {
        ZStack(alignment: .top) {
            DL.body.ignoresSafeArea()
            VStack(spacing: 0) {
                still
                VStack(alignment: .leading, spacing: 14) {
                    titleRow
                    HStack(spacing: 6) {
                        DLTag(text: game.players, symbol: "person.2.fill")
                        DLTag(text: game.mode)
                        DLTag(text: game.category)
                        CommunityFriendsTag(gameID: game.id)
                    }
                    goldRow
                    friendsRow
                    playKeys
                }
                .padding(.horizontal, 18)
                .padding(.top, 20)
                Spacer(minLength: 0)
            }
        }
        .ignoresSafeArea()
    }

    private var still: some View {
        ZStack {
            ClipStill(game: game, phase: 0.3, showHUD: false, focusY: 0.12)
            LinearGradient(colors: [.black.opacity(0.45), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 150)
                .frame(maxHeight: .infinity, alignment: .top)
            HStack {
                DLMediaButton(symbol: "chevron.down", size: 40).goesBack().accessibilityLabel("Close")
                Spacer()
                DLGoldChip()
            }
            .padding(.horizontal, 16)
            .padding(.top, 58)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(height: 404)
        .clipShape(DL.screenShape)
    }

    private var titleRow: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(game.title.uppercased())
                    .font(DL.display(40))
                    .foregroundStyle(DL.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                HStack(spacing: 5) {
                    Text("by \(game.studio)").font(DL.text(14, .medium)).foregroundStyle(DL.ink2)
                    Image(systemName: "checkmark.seal.fill").font(.system(size: 12)).foregroundStyle(DL.goldText)
                }
            }
            .layoutPriority(1)
            Spacer(minLength: 4)
            DLVotePill(game: game)
        }
    }

    private var goldRow: some View {
        HStack(spacing: 10) {
            DLCoin(size: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text("Earn \(game.rateText)ute").font(DL.text(16, .semibold)).foregroundStyle(DL.ink)
                Text(game.isFullToday
                     ? "Limit reached. More gold in \(Mock.resetIn)"
                     : "\(game.leftToday) of 100 still to collect here today")
                    .font(DL.text(13))
                    .foregroundStyle(DL.ink2)
            }
            Spacer()
            Image(systemName: "info.circle").font(.system(size: 17, weight: .medium)).foregroundStyle(DL.ink2)
        }
        .dlCard(padding: 14, radius: 22)
        .opens(.fairness(game.id))
    }

    private var friendsRow: some View {
        let friends = game.readyFriends
        let who: String
        switch friends.count {
        case 2: who = "You, \(friends[0]) and \(friends[1])"
        case 1: who = "You and \(friends[0])"
        default: who = "Just you"
        }
        return HStack(spacing: 12) {
            HStack(spacing: -8) {
                ForEach([Mock.handle] + friends, id: \.self) { name in
                    DLAvatar(name: name, size: 38)
                        .overlay(Circle().strokeBorder(DL.surface, lineWidth: 2))
                }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(who).font(DL.text(15, .semibold)).foregroundStyle(DL.ink)
                Text("\(friends.count + 1) of \(game.playerRange.upperBound) players")
                    .font(DL.text(13))
                    .foregroundStyle(DL.ink2)
            }
            Spacer(minLength: 4)
            HStack(spacing: 5) {
                Image(systemName: "plus").font(.system(size: 12, weight: .bold))
                Text("Invite").font(DL.text(14, .semibold))
            }
            .foregroundStyle(DL.ink)
            .padding(.horizontal, 13)
            .frame(height: 36)
            .background(Capsule().fill(DL.body))
            .tap { LiveNav.shared.share("Come and play \(game.title) with me on Dailies") }
        }
        .dlCard(padding: 12, radius: 22)
    }

    @ViewBuilder private var playKeys: some View {
        if game.playsBothWays {
            // Works alone and with others: playing alone on the left, with friends on the right.
            HStack(spacing: 10) {
                DLTextKey(title: "Play Singleplayer", style: .neutral)
                    .tap { LiveNav.shared.replaceTop(.play(game.id, solo: true)) }
                DLTextKey(title: "Play Multiplayer")
                    .tap { LiveNav.shared.replaceTop(.play(game.id, solo: false)) }
            }
        } else {
            // One way to play it, so one key.
            DLTextKey(title: "Play", symbol: "play.fill")
                .tap { LiveNav.shared.replaceTop(.play(game.id, solo: game.playerRange.upperBound == 1)) }
        }
    }
}
