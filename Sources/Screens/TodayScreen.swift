import SwiftUI

// YOUR GOLD, opened from the balance on Home. One balance, what today added to it and from where,
// the streak, and the thing being saved for.

struct TodayScreen: View {
    @ObservedObject private var live = LiveStore.shared

    var body: some View {
        DLTabs(selected: 0) {
            DLPage {
                DLNavBar(title: "Your gold", trailingSymbol: "bell.fill", trailingAction: { LiveNav.shared.open(.inbox) })
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .center, spacing: 12) {
                        DLCoin(size: 50)
                        Text(groupedNumber(Mock.balance)).font(DL.display(118)).foregroundStyle(DL.ink)
                    }
                    .frame(height: 104)
                    Text("+\(Mock.earnedToday) gold today").dlLabel(12)
                }
                if LiveMode.on { DLTextKey(title: "Get gold", symbol: "plus").opens(.buyGold) }
                HStack(spacing: 12) {
                    goalCard
                    streakCard
                }
                sourcesCard
                savingCard
            }
        }
    }

    /// Today's gold against the daily goal.
    private var goalCard: some View {
        let earned = Mock.earnedToday
        // The screenshot's story has the goal long passed. The app shows the real state.
        let short = LiveMode.on && earned < Mock.dailyGoal
        return VStack(alignment: .leading, spacing: 10) {
            Text("Today's gold").dlLabel(10.5)
            HStack(spacing: 10) {
                DLRing(progress: LiveMode.on ? Double(earned) / Double(Mock.dailyGoal) : 1, size: 54)
                VStack(alignment: .leading, spacing: -2) {
                    Text("\(earned)").font(DL.display(38)).foregroundStyle(DL.ink)
                    Text("goal \(short ? "is" : "was") \(Mock.dailyGoal)")
                        .font(DL.text(12, .medium))
                        .foregroundStyle(DL.ink2)
                }
            }
            Text("More gold in \(Mock.resetIn)").font(DL.text(12, .semibold)).foregroundStyle(DL.goldText)
        }
        .dlCard()
    }

    private var streakCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Streak").dlLabel(10.5)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(Mock.streakDays)").font(DL.display(54)).foregroundStyle(DL.ink)
                Text("days").font(DL.text(15, .semibold)).foregroundStyle(DL.ink2)
            }
            .frame(height: 54)
            HStack(spacing: 4) {
                ForEach(Mock.streakWeek.indices, id: \.self) { day in
                    VStack(spacing: 3) {
                        Circle()
                            .fill(Mock.streakWeek[day] ? DL.gold : DL.sunken)
                            .frame(width: 15, height: 15)
                        Text(Mock.weekInitials[day])
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(DL.ink3)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .dlCard()
        .opens(.streak)
    }

    /// Each game that gave gold today, with how much of its 100 has been collected.
    private var sourcesCard: some View {
        let sources = Mock.todayGames
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Where it came from").dlLabel(10.5)
                Spacer()
                HStack(spacing: LiveMode.on ? 4 : nil) {
                    Text("History").font(DL.text(13, .semibold)).foregroundStyle(DL.ink)
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(DL.ink2)
                }
                // In the app the link is a taller target, pulled up so the card keeps its height.
                .frame(height: LiveMode.on ? 30 : nil)
                .contentShape(Rectangle())
                .opens(.history)
            }
            .padding(.bottom, LiveMode.on ? 0 : 6)
            .padding(.top, LiveMode.on ? -8 : 0)

            if LiveMode.on && sources.isEmpty {
                Text("Nothing yet today. Play a game to collect gold.")
                    .font(DL.text(15))
                    .foregroundStyle(DL.ink2)
                    .padding(.vertical, 10)
            }
            ForEach(sources.indices, id: \.self) { index in
                let game = sources[index].game
                if index > 0 { DLDivider() }
                HStack(spacing: 12) {
                    DLThumb(game: game)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(game.title).font(DL.text(16, .semibold)).foregroundStyle(DL.ink)
                        HStack(spacing: 8) {
                            DLMeter(value: Double(game.earnedToday)).frame(width: 84)
                            Text(game.isFullToday ? "Limit reached" : "\(game.earnedToday) of 100").dlLabel(10)
                        }
                    }
                    Spacer()
                    DLAmount(amount: game.earnedToday)
                }
                .padding(.vertical, 10)
                .contentShape(Rectangle())
                .opens(.gameReady(game.id))
            }
        }
        .dlCard()
    }

    private var savingCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Saving for").dlLabel(10.5)
            HStack(spacing: 12) {
                DLThumb(game: Mock.tippyTower)
                VStack(alignment: .leading, spacing: 2) {
                    Text(Mock.savingTitle).font(DL.text(16, .semibold)).foregroundStyle(DL.ink)
                    Text("\(Mock.savingDetail). \(Mock.savingEta).").font(DL.text(13)).foregroundStyle(DL.ink2)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: -2) {
                    Text("\(Mock.balance)").font(DL.display(26)).foregroundStyle(DL.ink)
                    Text("of \(Mock.savingPrice)").dlLabel(10)
                }
            }
            DLMeter(value: Double(Mock.balance), total: Double(Mock.savingPrice), height: 8)
        }
        .dlCard()
        // The saving goal is the last item in the shop.
        .opens(.spend(4))
    }
}

/// How gold works: the rules, on one sheet, one tap from any game.
struct FairnessSheetScreen: View {
    var game: MockGame = Mock.tippyTower

    var body: some View {
        DLSheet(height: 528) {
            FeedScreen()
        } content: {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("HOW GOLD WORKS").font(DL.display(34)).foregroundStyle(DL.ink)
                    Spacer()
                    DLIconButton(symbol: "xmark", size: 36).goesBack().accessibilityLabel("Close")
                }
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill").font(.system(size: 22)).foregroundStyle(DL.goldText)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(game.title) is reviewed").font(DL.text(16, .semibold)).foregroundStyle(DL.ink)
                        Text("It gives \(game.rateText)ute. The same for everyone.")
                            .font(DL.text(14))
                            .foregroundStyle(DL.ink2)
                    }
                }
                .dlCard(padding: 14, fill: DL.goldWash, radius: 20)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Mock.fairnessLines.indices, id: \.self) { index in
                        if index > 0 { DL.line.frame(height: 1) }
                        HStack(spacing: 12) {
                            Text("\(index + 1)")
                                .font(DL.display(22))
                                .foregroundStyle(DL.ink3)
                                .frame(width: 18, alignment: .leading)
                            Text(Mock.fairnessLines[index]).font(DL.text(16, .medium)).foregroundStyle(DL.ink)
                            Spacer()
                        }
                        .padding(.vertical, 13)
                    }
                }
                DLTextKey(title: "Got it", style: .ink).goesBack()
            }
            .padding(.horizontal, 20)
        }
    }
}
