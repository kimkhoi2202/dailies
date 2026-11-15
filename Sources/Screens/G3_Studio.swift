import SwiftUI

// STUDIO: a game maker's dashboard, pushed from the You tab. One number leads (plays today). Then
// what those plays came to in minutes and gold, how the studio's limit is being used, and the games.

struct G3StudioScreen: View {
    private let games: [MockGame] = [Mock.tippyTower, Mock.spiralDrop]

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
                DLTextKey(title: "Publish a game", symbol: "plus").opens(.publish(1)).padding(.top, 4)
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
