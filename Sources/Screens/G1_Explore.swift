import SwiftUI

// EXPLORE, behind Search: the feed's back catalogue. Every card is a clip that drops you into a game.
// There are three ways in: what still has gold today, what people liked this week, and what is newly reviewed.

enum G1ExploreData {
    static let filters = ["All", "Arcade", "Word", "Runner", "Multiplayer", "Casual"]
    /// Clips whose games are under today's limit. The least played today comes first.
    static let stillHasGold: [MockClip] = [Mock.clips[3], Mock.clips[1], Mock.clips[4]]
    /// In order of the share of votes that are likes.
    static let mostLiked: [MockGame] = [Mock.fiveUp, Mock.tippyTower, Mock.spiralDrop]
    static let newlyReviewed: [(game: MockGame, when: String)] = [
        (Mock.spiralDrop, "Yesterday"), (Mock.inkland, "3 days ago"), (Mock.laneDash, "Last week"),
    ]
    /// At this width and gap three cards fill a row exactly, so no title is cut off by the screen edge.
    static let cardWidth: CGFloat = 116
    static let cardGap: CGFloat = 11
}

/// The search field as it rests, before anyone taps it.
struct G1SearchField: View {
    var placeholder: String = "Games, studios, players"

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(DL.ink)
            Text(placeholder).font(DL.text(16)).foregroundStyle(DL.ink3)
            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(DL.surface))
        .accessibilityLabel("Search games, studios and players")
    }
}

/// A symbol and a few mono characters on a dark capsule, laid over a card's art.
private struct G1ArtBadge: View {
    let symbol: String
    let text: String
    var textSize: CGFloat = 10.5
    var dim: Double = 0.4

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 9, weight: .bold))
            Text(text).font(DL.label(textSize))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 7)
        .frame(height: 20)
        .background(Capsule().fill(.black.opacity(dim)))
    }
}

/// A game's name under a shelf card.
private struct G1ShelfName: View {
    let game: MockGame

    var body: some View {
        Text(game.title.uppercased())
            .font(DL.display(20))
            .foregroundStyle(DL.ink)
            .lineLimit(1)
            .frame(height: 22)
            .padding(.top, 8)
    }
}

/// A clip, with how much of today's gold its game has left. The name and a meter sit under the art.
struct G1GoldLeftCard: View {
    let clip: MockClip
    var width: CGFloat = G1ExploreData.cardWidth
    var height: CGFloat = 144

    var body: some View {
        let game = clip.game
        VStack(alignment: .leading, spacing: 0) {
            DLClipCard(game: game, width: width, height: height, showTitle: false)
                .overlay(alignment: .topLeading) {
                    G1MediaLabel(text: clip.length).padding(8)
                }
                .overlay(alignment: .bottomLeading) {
                    G1ArtBadge(symbol: "hand.thumbsup.fill", text: "\(game.approval)%").padding(8)
                }
            G1ShelfName(game: game)
            HStack(spacing: 6) {
                DLMeter(value: Double(game.earnedToday), height: 5).frame(width: 34)
                Text("\(game.leftToday) left").dlLabel(10)
            }
            .padding(.top, 3)
        }
        .frame(width: width, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(game.title), \(game.approval) percent liked it, \(game.leftToday) gold left today")
    }
}

/// A row of "Most liked this week": its place, the game, and the share that liked it with the split drawn under.
struct G1LikedRow: View {
    let rank: Int
    let game: MockGame

    var body: some View {
        HStack(spacing: 12) {
            Text("\(rank)")
                .font(DL.display(28))
                .foregroundStyle(DL.ink3)
                .frame(width: 16, alignment: .leading)
            DLThumb(game: game, size: 42)
            VStack(alignment: .leading, spacing: 1) {
                Text(game.title).font(DL.text(16, .semibold)).foregroundStyle(DL.ink).lineLimit(1)
                Text("\(game.players), \(game.mode.lowercased())").font(DL.text(13)).foregroundStyle(DL.ink2).lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                HStack(alignment: .center, spacing: 5) {
                    Image(systemName: "hand.thumbsup.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(DL.ink2)
                    Text("\(game.approval)%")
                        .font(DL.display(26))
                        .foregroundStyle(DL.ink)
                        .monospacedDigit()
                }
                .frame(height: 24)
                G1ApprovalMini(approval: game.approval)
            }
        }
        .frame(height: 54)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(rank). \(game.title), \(game.approval) percent liked it")
    }
}

/// A clip of a game fresh out of review. The seal and when it passed sit at the top of the art.
struct G1NewCard: View {
    let game: MockGame
    let when: String
    var width: CGFloat = G1ExploreData.cardWidth
    var height: CGFloat = 144

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DLClipCard(game: game, width: width, height: height, showTitle: false)
                .overlay(alignment: .topLeading) {
                    G1ArtBadge(symbol: "checkmark.seal.fill", text: when.uppercased(), textSize: 10, dim: 0.45)
                        .padding(8)
                }
            G1ShelfName(game: game)
            Text(game.rateText).dlLabel(10).padding(.top, 3)
        }
        .frame(width: width, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// A row that scrolls sideways and runs out to both edges of the screen, past the page margins.
private struct G1EdgeToEdgeRow<Content: View>: View {
    var spacing: CGFloat
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: spacing, content: content)
                .padding(.horizontal, DL.margin)
        }
        .scrollIndicators(.hidden)
        .padding(.horizontal, -DL.margin)
    }
}

struct G1ExploreScreen: View {
    var body: some View {
        DLTabs(selected: 0) {
            DLPage(spacing: 0) {
                DLHeader(title: "Search") {
                    DLGoldChip(onMedia: false).padding(.bottom, 8)
                }
                G1SearchField().padding(.top, 6)
                // The tags scroll rather than shorten.
                G1EdgeToEdgeRow(spacing: 5) {
                    ForEach(G1ExploreData.filters, id: \.self) { name in
                        DLTag(text: name, filled: name == G1ExploreData.filters[0]).fixedSize()
                    }
                }
                .padding(.top, 12)

                G1SectionTitle(title: "Still has gold today", link: "All \(Mock.capOtherGamesWithGold)")
                    .padding(.top, 18)
                G1EdgeToEdgeRow(spacing: G1ExploreData.cardGap) {
                    ForEach(G1ExploreData.stillHasGold) { clip in
                        G1GoldLeftCard(clip: clip)
                    }
                }
                .padding(.top, 8)

                G1SectionTitle(title: "Most liked this week", link: "Top 50")
                    .padding(.top, 18)
                VStack(spacing: 0) {
                    ForEach(G1ExploreData.mostLiked.indices, id: \.self) { index in
                        if index > 0 { DLDivider(inset: 70) }
                        G1LikedRow(rank: index + 1, game: G1ExploreData.mostLiked[index])
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
                .dlCard(padding: 0)
                .padding(.top, 8)

                G1SectionTitle(title: "New and reviewed", link: "See all")
                    .padding(.top, 18)
                G1EdgeToEdgeRow(spacing: G1ExploreData.cardGap) {
                    ForEach(G1ExploreData.newlyReviewed.indices, id: \.self) { index in
                        let entry = G1ExploreData.newlyReviewed[index]
                        G1NewCard(game: entry.game, when: entry.when)
                    }
                }
                .padding(.top, 8)
            }
        }
    }
}
