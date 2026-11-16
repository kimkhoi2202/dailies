import SwiftUI

// THE GAME PAGE, reached by tapping a game's name on the feed. The clip plays on in a shorter screen.
// Under it the page answers three questions in order: is it good, what does it give, and who plays it.

/// A clip somebody recorded in this game, for the shelf at the foot of the page.
struct G1RunClip: Identifiable {
    let id: String
    let player: String
    let length: String
    let views: String
    let phase: Double
    let focusY: CGFloat
}

enum G1GameDetailData {
    static let clips: [G1RunClip] = [
        G1RunClip(id: "r1", player: "kaz", length: "0:36", views: "41.8K", phase: 0.62, focusY: 0.34),
        G1RunClip(id: "r2", player: "noor.runs", length: "0:29", views: "12.6K", phase: 0.97, focusY: 0.22),
        G1RunClip(id: "r3", player: "juno", length: "0:44", views: "9.3K", phase: 0.36, focusY: 0.36),
        G1RunClip(id: "r4", player: "tofu", length: "0:31", views: "6.1K", phase: 0.74, focusY: 0.3),
    ]
}

/// The clip at the top of the page, on a shorter screen than the feed's.
struct G1DetailClip: View {
    let clip: MockClip
    var progress: CGFloat = 0.38

    var body: some View {
        ZStack {
            // A moment where the tower stands between the controls and clear of the clock.
            ClipStill(game: clip.game, phase: 0.80, showHUD: false, focusY: 0.44)
            LinearGradient(colors: [.black.opacity(0.5), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 130)
                .frame(maxHeight: .infinity, alignment: .top)
            LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                .frame(height: 100)
                .frame(maxHeight: .infinity, alignment: .bottom)
            VStack(spacing: 0) {
                HStack {
                    DLMediaButton(symbol: "chevron.left", size: 40).goesBack().accessibilityLabel("Back")
                    Spacer()
                    DLGoldChip()
                }
                .padding(.top, 58)
                Spacer()
                HStack(spacing: 8) {
                    Text("CLIP \(clip.length)")
                        .font(DL.label(10.5))
                        .padding(.horizontal, 7)
                        .frame(height: 20)
                        .background(Capsule().fill(.white.opacity(0.22)))
                    Text("@\(clip.player)").font(DL.text(14, .semibold))
                    Spacer()
                    DLMediaButton(symbol: "speaker.wave.2.fill", size: 34).notYet("Sound")
                }
                .foregroundStyle(.white)
                .padding(.bottom, 14)
            }
            .padding(.horizontal, 18)
            GeometryReader { geo in
                Rectangle()
                    .fill(.white.opacity(0.25))
                    .overlay(alignment: .leading) {
                        Rectangle().fill(.white).frame(width: geo.size.width * progress)
                    }
                    .frame(height: 3)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
        .clipShape(DL.screenShape)
    }
}

/// The game's name, who made it and that it is reviewed. The button opposite holds Report and Block.
struct G1DetailTitle: View {
    let game: MockGame

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(game.title.uppercased())
                    .font(DL.display(40))
                    .foregroundStyle(DL.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.seal.fill").font(.system(size: 12)).foregroundStyle(DL.goldText)
                    Text("by \(game.studio), reviewed")
                        .font(DL.text(13, .medium))
                        .foregroundStyle(DL.ink2)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            DLIconButton(symbol: "ellipsis")
                .notYet("Report and block")
                .accessibilityLabel("More: report or block")
        }
    }
}

/// What the game gives gold for, and how much of today's limit is used. Short enough to sit whole above the tab bar.
struct G1GoldCard: View {
    let game: MockGame

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            G1CardHeader(label: "Gold", link: "How gold works").opens(.fairness(game.id))
            HStack(alignment: .center, spacing: 10) {
                DLCoin(size: 30)
                Text(game.goldRule)
                    .font(DL.text(15, .semibold))
                    .foregroundStyle(DL.ink)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
            }
            HStack(alignment: .firstTextBaseline) {
                Text("\(game.earnedToday) of \(game.capToday) today").font(DL.text(13, .semibold)).foregroundStyle(DL.ink)
                Spacer(minLength: 8)
                Text("More gold in \(Mock.resetIn)").font(DL.text(12, .semibold)).foregroundStyle(DL.goldText)
            }
            .lineLimit(1)
            DLMeter(value: Double(game.earnedToday), height: 8)
        }
        .dlCard()
        .accessibilityElement(children: .combine)
    }
}

/// The head of the friends leaderboard. Your own row is washed in gold.
struct G1BoardPreview: View {
    var game: MockGame = Mock.tippyTower
    var ranks: [MockRank] = Array(Mock.leaderboard.prefix(3))

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            G1CardHeader(label: "Friends today, \(LiveMode.on ? LiveBoard.unit(for: game) : "floors")", link: "Leaderboard")
                .opens(.leaderboard(game.id))
                .padding(.horizontal, 16)
                .padding(.top, 16)
            VStack(spacing: 0) {
                ForEach(ranks) { rank in row(rank) }
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DL.cardRadius, style: .continuous).fill(DL.surface))
    }

    private func row(_ rank: MockRank) -> some View {
        HStack(spacing: 12) {
            Text("\(rank.rank)")
                .font(DL.display(28))
                .foregroundStyle(rank.isYou ? DL.ink : DL.ink3)
                .frame(width: 18, alignment: .leading)
            DLAvatar(name: rank.name, size: 36)
            VStack(alignment: .leading, spacing: 1) {
                Text(rank.isYou ? "You" : rank.name).font(DL.text(16, .semibold)).foregroundStyle(DL.ink)
                if rank.isYou {
                    Text(LiveMode.on ? LiveBoard.context(for: rank, game: game) : G1Board.youContext)
                        .font(DL.text(13))
                        .foregroundStyle(DL.ink2)
                }
            }
            Spacer(minLength: 8)
            Text(rank.score).font(DL.display(28)).foregroundStyle(DL.ink).monospacedDigit()
        }
        .padding(.horizontal, 10)
        .frame(height: 54)
        .background {
            if rank.isYou {
                RoundedRectangle(cornerRadius: 20, style: .continuous).fill(DL.goldWash)
            }
        }
    }
}

/// A clip from this game as a tall tile: how long it is, who played, and how often it was watched.
struct G1RunTile: View {
    let game: MockGame
    let clip: G1RunClip
    var width: CGFloat = 132
    var height: CGFloat = 216

    var body: some View {
        ZStack {
            ClipStill(game: game, phase: clip.phase, showHUD: false, focusY: clip.focusY)
            LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 2) {
                G1MediaLabel(text: clip.length)
                Spacer()
                Text("@\(clip.player)")
                    .font(DL.text(14, .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Image(systemName: "play.fill").font(.system(size: 8, weight: .bold))
                    Text(clip.views).font(DL.label(10))
                }
                .foregroundStyle(.white.opacity(0.85))
            }
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

/// Clips recorded in this game. The row runs off the right edge to show there are more.
struct G1ClipsShelf: View {
    let game: MockGame

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            G1SectionTitle(title: "Clips from \(game.title)", link: "All clips")
                .padding(.horizontal, DL.margin)
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(G1GameDetailData.clips) { clip in
                        G1RunTile(game: game, clip: clip).opens(.gameReady(game.id))
                    }
                }
                .padding(.horizontal, DL.margin)
            }
            .scrollIndicators(.hidden)
        }
    }
}

/// A short bar that holds the top of the screen once the big Play key has scrolled out of sight.
struct G1DetailPinnedBar: View {
    let game: MockGame

    var body: some View {
        HStack(spacing: 12) {
            DLIconButton(symbol: "chevron.left").goesBack().accessibilityLabel("Back")
            VStack(alignment: .leading, spacing: 0) {
                Text(game.title.uppercased())
                    .font(DL.display(24))
                    .foregroundStyle(DL.ink)
                    .lineLimit(1)
                    .frame(height: 24)
                HStack(spacing: 4) {
                    Image(systemName: "hand.thumbsup.fill").font(.system(size: 9, weight: .bold))
                    Text("\(game.approval)% liked it").font(DL.label(10)).textCase(.uppercase)
                }
                .foregroundStyle(DL.ink2)
            }
            Spacer(minLength: 8)
            DLKey(style: .gold, radius: 16, depth: 4) {
                HStack(spacing: 7) {
                    Image(systemName: "play.fill").font(.system(size: 13, weight: .black))
                    Text("PLAY").font(DL.display(22)).tracking(0.8)
                }
            }
            .frame(width: 108, height: 46)
            .opens(.gameReady(game.id))
            .accessibilityLabel("Play \(game.title)")
        }
        .padding(.horizontal, DL.margin)
        .padding(.top, 68)
        .padding(.bottom, 10)
        .background(DL.body)
        .overlay(alignment: .bottom) { DL.line.frame(height: 1) }
    }
}

struct G1GameDetailScreen: View {
    @ObservedObject private var live = LiveStore.shared
    var game: MockGame = Mock.tippyTower
    var clip: MockClip = Mock.clips[0]
    /// Shows the lower half of the page: scrolled to the end, with the short bar in place.
    var scrolled: Bool = false
    /// In the app: true once the big Play key has gone off the top.
    @State private var pinned = false

    /// The gap under the last row. The screenshot needs room for its tab bar. The app's page ends sooner.
    private var bottomGap: CGFloat {
        if scrolled { return 55 }
        return LiveMode.on ? 24 : 120
    }

    var body: some View {
        DLTabs(selected: 1) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    G1DetailClip(clip: clip).frame(height: 286)
                    VStack(alignment: .leading, spacing: 10) {
                        G1DetailTitle(game: game)
                        DLPlayKey(title: "PLAY", trailing: "\(game.leftToday) GOLD LEFT TODAY")
                            .opens(.gameReady(game.id))
                        DLApprovalBar(game: game).dlCard()
                        stats
                        G1GoldCard(game: game)
                        G1BoardPreview(game: game, ranks: LiveMode.on ? LiveBoard.preview(for: game) : Array(Mock.leaderboard.prefix(3)))
                    }
                    .padding(.horizontal, DL.margin)
                    .padding(.top, 14)
                    G1ClipsShelf(game: game).padding(.top, 20)
                }
                .padding(.bottom, bottomGap)
            }
            .scrollIndicators(.hidden)
            .defaultScrollAnchor(scrolled ? .bottom : .top)
            .background(DL.body.ignoresSafeArea())
            .ignoresSafeArea(edges: .top)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y > 250
            } action: { _, pastPlayKey in
                guard LiveMode.on else { return }
                withAnimation(.easeOut(duration: 0.15)) { pinned = pastPlayKey }
            }
            .overlay(alignment: .top) {
                if scrolled || pinned {
                    G1DetailPinnedBar(game: game)
                        .ignoresSafeArea(edges: .top)
                        .transition(.opacity)
                }
            }
        }
    }

    /// Three figures. The screenshot shows the story's numbers. The app shows the game's and the player's own.
    private var stats: some View {
        let best = LiveMode.on ? LiveBoard.yourBest(game) : (value: "41", detail: "floors")
        return HStack(spacing: 10) {
            DLStat(label: "Plays", value: game.plays, detail: "all time")
            DLStat(label: "Avg round", value: LiveMode.on ? game.avgSession : "1:35", detail: LiveMode.on ? "a round" : "minutes")
            DLStat(label: "Your best", value: best.value, detail: best.detail)
        }
    }
}
