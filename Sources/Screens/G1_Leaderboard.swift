import SwiftUI

// LEADERBOARD: Tippy Tower, friends, today. It is a scoreboard and not a podium: big numerals and
// plain rows. Your own row is washed in gold and says how far you are from the top. One key plays again.

enum G1Board {
    static let unit = "floors"
    /// Mira's distance from first place: 58 less 41.
    static let youContext = "17 floors behind devon.plays"

    /// The line under a name in the fixed demo board.
    static func context(for r: MockRank) -> String {
        if r.isYou { return youContext }
        if r.rank == 1 { return "Leading today" }
        if r.rank == 2 { return "9 floors off the lead" }
        return ""
    }
}

/// A row for one of the top three: a large place numeral, the player, and the score as a scoreboard figure.
struct G1TopRankRow: View {
    let rank: MockRank
    /// The line under the name. nil uses the fixed demo line.
    var context: String? = nil

    var body: some View {
        let first = rank.rank == 1
        HStack(spacing: 10) {
            Text("\(rank.rank)")
                .font(DL.display(first ? 64 : 46))
                .foregroundStyle(first || rank.isYou ? DL.ink : DL.ink3)
                .frame(width: 30, alignment: .leading)
            DLAvatar(name: rank.name, size: first ? 48 : 40)
                .frame(width: 48)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(rank.name).font(DL.text(first ? 18 : 16, .semibold)).foregroundStyle(DL.ink)
                    if rank.isYou { DLTag(text: "You", filled: true) }
                }
                Text(context ?? G1Board.context(for: rank)).font(DL.text(13)).foregroundStyle(DL.ink2)
            }
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 6)
            Text(rank.score)
                .font(DL.display(first ? 58 : 38))
                .foregroundStyle(DL.ink)
                .monospacedDigit()
                .lineLimit(1)
                // Real scores can be long ("2,410"). In the app the figure shrinks before the name does.
                .minimumScaleFactor(LiveMode.on ? 0.5 : 1)
                .layoutPriority(LiveMode.on ? 1 : 0)
        }
        .padding(.horizontal, 12)
        .frame(height: first ? 78 : 60)
        .background {
            if rank.isYou {
                RoundedRectangle(cornerRadius: 20, style: .continuous).fill(DL.goldWash)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A row for fourth place and below.
struct G1RankRow: View {
    let rank: MockRank

    var body: some View {
        HStack(spacing: 10) {
            Text("\(rank.rank)")
                .font(DL.display(24))
                .foregroundStyle(DL.ink3)
                .frame(width: 30, alignment: .leading)
            DLAvatar(name: rank.name, size: 30)
                .frame(width: 48)
            Text(rank.name).font(DL.text(15, .semibold)).foregroundStyle(DL.ink).lineLimit(1)
            Spacer(minLength: 8)
            Text(rank.score).font(DL.display(26)).foregroundStyle(DL.ink).monospacedDigit()
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
    }
}

struct G1LeaderboardScreen: View {
    var game: MockGame = Mock.tippyTower
    @ObservedObject private var live = LiveStore.shared

    private var board: [MockRank] { LiveMode.on ? LiveBoard.ranks(for: game) : Mock.leaderboard }

    var body: some View {
        DLTabs(selected: 1) {
            DLPage(spacing: 12, bottomInset: 150) {
                DLNavBar(title: game.title, trailingSymbol: "person.badge.plus", trailingAction: {
                    LiveNav.shared.share("Come and play \(game.title) with me on Dailies")
                })
                Text("LEADERBOARD")
                    .font(DL.display(44))
                    .foregroundStyle(DL.ink)
                    .frame(height: 44)
                HStack(spacing: 10) {
                    G1Segmented(options: ["Friends", "Everyone"], selected: 0)
                    G1Segmented(options: ["Today", "All time"], selected: 0)
                }
                podium
                field
            }
            .overlay(alignment: .bottom) { playAgain }
        }
    }

    /// The top three, under a line saying how many friends played and what the score counts.
    private var podium: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(board.count) friends played today").dlLabel(10.5)
                Spacer()
                Text(LiveMode.on ? LiveBoard.unit(for: game) : G1Board.unit).dlLabel(10.5)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 2)
            ForEach(board.prefix(3)) { rank in
                G1TopRankRow(rank: rank, context: LiveMode.on ? LiveBoard.context(for: rank, game: game) : nil)
            }
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: DL.cardRadius, style: .continuous).fill(DL.surface))
    }

    /// Everyone from fourth place down.
    private var field: some View {
        let rest = Array(board.dropFirst(3))
        return VStack(spacing: 0) {
            ForEach(rest.indices, id: \.self) { index in
                if index > 0 {
                    DL.line.frame(height: 1).padding(.leading, 110).padding(.trailing, 12)
                }
                G1RankRow(rank: rest[index])
            }
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: DL.cardRadius, style: .continuous).fill(DL.surface))
    }

    /// The Play key, held above the tab bar. The list runs under it and fades out behind.
    private var playAgain: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [DL.body.opacity(0), DL.body], startPoint: .top, endPoint: .bottom)
                .frame(height: 16)
            DLPlayKey(title: "PLAY", trailing: LiveMode.on ? LiveBoard.passText(for: game) : "PASS KAZ AT 50 FLOORS")
                .opens(.gameReady(game.id))
                .padding(.horizontal, DL.margin)
                .padding(.bottom, 32)
                .background(DL.body)
        }
    }
}
