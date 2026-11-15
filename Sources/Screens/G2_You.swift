import SwiftUI

// YOU: who you are here in three numbers, your studio, and the clips you have posted.

struct G2YouClip: Identifiable {
    let id: Int
    let game: MockGame
    let phase: Double
    let plays: String
}

enum G2YouData {
    /// Mira's own clips, newest first. Each count is for the clip, not for its game.
    static let clips: [G2YouClip] = [
        G2YouClip(id: 0, game: Mock.tippyTower, phase: 0.85, plays: "48.2K"),
        G2YouClip(id: 1, game: Mock.laneDash, phase: 0.5, plays: "12.1K"),
        G2YouClip(id: 2, game: Mock.fiveUp, phase: 0.85, plays: "9,304"),
        G2YouClip(id: 3, game: Mock.spiralDrop, phase: 0.5, plays: "31.6K"),
        G2YouClip(id: 4, game: Mock.inkland, phase: 0.85, plays: "5,120"),
        G2YouClip(id: 5, game: Mock.tippyTower, phase: 0.42, plays: "7,812"),
    ]
    static let studioGamesLive = 2
}

struct G2YouScreen: View {
    @ObservedObject private var live = LiveStore.shared
    /// 0 = the clips you posted, 1 = the games you liked
    @State private var segment = 0

    private let gridGap: CGFloat = 8
    private let tileHeight: CGFloat = 172

    /// Three tiles fill the row. A screenshot is always 402 points wide. The app asks the phone.
    private var tileWidth: CGFloat {
        let screen = LiveMode.on ? UIScreen.main.bounds.width : 402
        return (screen - DL.margin * 2 - gridGap * 2) / 3
    }

    private var likedGames: [MockGame] { Mock.games.filter { live.vote(for: $0.id) == true } }

    var body: some View {
        DLTabs(selected: 2) {
            DLPage(spacing: 14) {
                identity
                HStack(spacing: 10) {
                    DLStat(label: "Gold", value: groupedNumber(Mock.balance), detail: "+\(Mock.earnedToday) today")
                        .overlay(alignment: .topTrailing) { DLCoin(size: 16).padding(14) }
                        .opens(.gold)
                    DLStat(label: "Streak", value: "\(Mock.streakDays)", detail: "days running")
                        .opens(.streak)
                    DLStat(label: "Played", value: "\(Mock.gamesPlayed)", detail: "games")
                        .opens(.history)
                }
                studioRow.opens(.studio)
                G2Segmented(items: ["Clips", "Liked"], selected: segment)
                    .overlay {
                        // The control only draws itself. A clear target over each half takes the tap.
                        HStack(spacing: 0) {
                            ForEach(0..<2, id: \.self) { index in
                                Color.clear.contentShape(Rectangle()).tap { segment = index }
                            }
                        }
                    }
                    .padding(.top, 6)
                if segment == 1 && likedGames.isEmpty {
                    Text("Games you like show up here.")
                        .font(DL.text(15))
                        .foregroundStyle(DL.ink2)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 30)
                }
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(tileWidth), spacing: gridGap), count: 3), spacing: gridGap) {
                    if segment == 0 {
                        ForEach(G2YouData.clips) { clip in
                            tile(clip.game, phase: clip.phase, plays: clip.plays)
                        }
                    } else {
                        ForEach(likedGames) { game in
                            tile(game, phase: game.clipPhase, plays: game.plays)
                        }
                    }
                }
            }
        }
    }

    private func tile(_ game: MockGame, phase: Double, plays: String) -> some View {
        G2ClipTile(game: game, phase: phase, plays: plays, width: tileWidth, height: tileHeight)
            .opens(.gameReady(game.id))
    }

    private var identity: some View {
        HStack(alignment: .center, spacing: 12) {
            DLAvatar(name: Mock.handle, size: 60)
            VStack(alignment: .leading, spacing: -2) {
                Text(Mock.displayName.uppercased())
                    .font(DL.display(40))
                    .foregroundStyle(DL.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("@\(Mock.handle)").font(DL.text(15, .medium)).foregroundStyle(DL.ink2)
            }
            Spacer(minLength: 8)
            DLIconButton(symbol: "gearshape.fill").opens(.settings).accessibilityLabel("Settings")
        }
        .padding(.top, 4)
    }

    /// The way into the studio: its two live games, its name and the seal.
    private var studioRow: some View {
        let thumb: CGFloat = 44
        return HStack(spacing: 12) {
            ZStack(alignment: .leading) {
                DLThumb(game: Mock.spiralDrop, size: thumb).padding(.leading, 24)
                DLThumb(game: Mock.tippyTower, size: thumb)
                    .overlay {
                        RoundedRectangle(cornerRadius: thumb * 0.28, style: .continuous)
                            .strokeBorder(DL.surface, lineWidth: 2)
                            .padding(-1)
                    }
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(Mock.myStudio).font(DL.text(16, .semibold)).foregroundStyle(DL.ink)
                    Image(systemName: "checkmark.seal.fill").font(.system(size: 12)).foregroundStyle(DL.goldText)
                }
                Text("Your studio, \(G2YouData.studioGamesLive) games live").font(DL.text(13)).foregroundStyle(DL.ink2)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(DL.ink2)
        }
        .dlCard(padding: 12)
    }
}
