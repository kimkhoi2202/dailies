import SwiftUI

// STUDIO: a game maker's dashboard, pushed from the You tab. One number leads (plays today). Then
// what those plays came to in minutes and gold, how the studio's limit is being used, and the games.

struct G3StudioScreen: View {
    private let games: [MockGame] = [Mock.tippyTower, Mock.spiralDrop]
    @ObservedObject private var store = LiveStore.shared

    var body: some View {
        DLTabs(selected: 2) {
            DLPage(spacing: 10) {
                DLNavBar(title: "Studio", trailingSymbol: "ellipsis", trailingAction: {
                    LiveNav.shared.say("Studio settings are not part of this demo yet")
                })
                HStack(alignment: .lastTextBaseline) {
                    Text(Mock.myStudio.uppercased())
                        .font(DL.display(44))
                        .foregroundStyle(DL.ink)
                        .fixedSize()
                        .frame(height: 40)
                    Spacer()
                    Text("\(games.count) games live").dlLabel()
                }
                G3Segmented(options: ["Today", "7 days", "30 days"], selected: 0)
                playsToday.padding(.top, 8)
                HStack(spacing: 10) {
                    DLStat(label: "Minutes", value: Mock.studioMinutesToday)
                    DLStat(label: "Gold given", value: Mock.studioGoldPaidToday)
                    DLStat(label: "Liked", value: "\(Mock.studioApproval)%")
                }
                .padding(.top, 4)
                limitCard
                gamesCard
                if !store.creations.isEmpty { madeCard }
                DLTextKey(title: "Make a game", symbol: "sparkles").opens(.create).padding(.top, 4)
                DLTextKey(title: "Publish a game", symbol: "plus", style: .ink).opens(.publish(1))
            }
        }
    }

    /// Today's plays, with the week that led up to them alongside.
    private var playsToday: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Plays today").dlLabel()
                Text(Mock.studioPlaysToday)
                    .font(DL.display(84))
                    .foregroundStyle(DL.ink)
                    .fixedSize()
                    .frame(height: 76)
                HStack(spacing: 5) {
                    Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .black))
                    Text("Best day this week").font(DL.text(13, .semibold))
                }
                .foregroundStyle(DL.ink2)
            }
            Spacer(minLength: 0)
            G3BarChart(values: Mock.studioPlaysByDay, labels: Mock.weekInitials, barHeight: 66)
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 10)
                .frame(width: 168)
                .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(DL.surface))
        }
    }

    /// The studio's daily limit, as the average player met it today.
    private var limitCard: some View {
        let cap = Mock.perStudioDailyCap
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 6) {
                Text("Per player today").dlLabel(10.5)
                Spacer()
                Text("\(Mock.studioAvgPerPlayer)").font(DL.display(28)).foregroundStyle(DL.ink)
                Text("OF \(cap)").font(DL.display(28)).foregroundStyle(DL.ink3)
            }
            .frame(height: 24)
            DLMeter(value: Double(Mock.studioAvgPerPlayer), total: Double(cap), height: 8)
            Text("The limit is \(cap) gold a day across your games.")
                .font(DL.text(13))
                .foregroundStyle(DL.ink2)
        }
        .dlCard(padding: 14)
    }

    /// The games this player is making or has made in the studio, newest first.
    private var madeCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Made in the studio").dlLabel(10.5).padding(.top, 10).padding(.bottom, 2)
            ForEach(store.creations) { creation in
                if creation.id != store.creations.first?.id { DLDivider(inset: 56) }
                HStack(spacing: 12) {
                    if let slug = creation.gameSlug, let made = store.madeGame(slug) {
                        DLThumb(game: made, size: 44)
                    } else {
                        DLMonogram(size: 44, plain: true, ink: DL.ink, counter: DL.surface)
                            .frame(width: 44, height: 44)
                            .background(DL.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(creation.title ?? creation.wish)
                            .font(DL.text(16, .semibold)).foregroundStyle(DL.ink).lineLimit(1)
                        Text(G4Engine.statusWord(creation)).font(DL.text(13)).foregroundStyle(DL.ink2)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(DL.ink2)
                }
                .padding(.vertical, 9)
                .contentShape(Rectangle())
                .opens(G4Engine.route(creation))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: DL.cardRadius, style: .continuous).fill(DL.surface))
    }

    private var gamesCard: some View {
        VStack(spacing: 0) {
            ForEach(games.indices, id: \.self) { index in
                let game = games[index]
                if index > 0 { DLDivider(inset: 56) }
                HStack(spacing: 12) {
                    DLThumb(game: game, size: 44)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text(game.title).font(DL.text(16, .semibold)).foregroundStyle(DL.ink)
                            DLTag(text: "Live")
                        }
                        Text("\(game.plays) plays, \(game.rateText)").font(DL.text(13)).foregroundStyle(DL.ink2)
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: -3) {
                        Text("\(game.approval)%").font(DL.display(26)).foregroundStyle(DL.ink)
                        Text("liked").dlLabel(10)
                    }
                }
                .padding(.vertical, 9)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: DL.cardRadius, style: .continuous).fill(DL.surface))
    }
}
