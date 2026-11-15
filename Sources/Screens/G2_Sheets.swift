import SwiftUI

// SHEETS: the streak explained, keeping a guest's gold, and asking about notifications in the app's
// own words before the system asks in its.

// MARK: Streak

enum G2StreakData {
    /// Saturday, in a week that starts on Sunday.
    static let todayIndex = 6
    static let rules: [String] = [
        "A day counts once you collect 1 gold.",
        "A missed day uses a rest day.",
        "Missed anyway? Play within 48 hours to get it back. It is never for sale.",
    ]
}

struct G2StreakSheetScreen: View {
    var body: some View {
        DLSheet(height: 544) {
            TodayScreen()
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                Text(Mock.streakDays == 1 ? "1 DAY" : "\(Mock.streakDays) DAYS")
                    .font(DL.display(112))
                    .foregroundStyle(DL.ink)
                    .lineLimit(1).minimumScaleFactor(0.5)
                    .frame(height: 98)
                    // Pulled left so the numeral's stem lines up with the rows below it.
                    .padding(.leading, -4)
                weekCard.padding(.top, 14)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(G2StreakData.rules.indices, id: \.self) { index in
                        if index > 0 { G2Hairline() }
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text("\(index + 1)")
                                .font(DL.display(22))
                                .foregroundStyle(DL.ink3)
                                .frame(width: 18, alignment: .leading)
                            Text(G2StreakData.rules[index])
                                .font(DL.text(15, .medium))
                                .foregroundStyle(DL.ink)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 12)
                    }
                }
                .padding(.top, 8)
                G2Hairline()
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Streaks").font(DL.text(16, .semibold)).foregroundStyle(DL.ink)
                        Text("Shown on Today and on your profile.").font(DL.text(13)).foregroundStyle(DL.ink2)
                    }
                    Spacer()
                    G2Switch(isOn: true)
                }
                .padding(.top, 14)
            }
            .padding(.horizontal, 20)
        }
    }

    /// The week as seven days, then the rest days still in hand.
    private var weekCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 0) {
                ForEach(Mock.streakWeek.indices, id: \.self) { day in
                    dayMark(day)
                }
            }
            .padding(.top, 4)
            G2Hairline()
            HStack(spacing: 10) {
                HStack(spacing: 3) {
                    ForEach(0..<Mock.restDaysLeft, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 3, style: .continuous).fill(DL.ink).frame(width: 9, height: 18)
                    }
                }
                Text("\(Mock.restDaysLeft) rest days in hand").font(DL.text(16, .semibold)).foregroundStyle(DL.ink)
                Spacer()
                Text("None used").dlLabel(10, color: DL.ink2)
            }
        }
        .dlCard(padding: 14, fill: DL.body, radius: 22)
    }

    private func dayMark(_ day: Int) -> some View {
        let counted = Mock.streakWeek[day]
        let isToday = day == G2StreakData.todayIndex
        return VStack(spacing: 7) {
            Circle()
                .fill(counted ? DL.gold : DL.sunken)
                .frame(width: 36, height: 36)
                .overlay {
                    if counted {
                        Image(systemName: "checkmark").font(.system(size: 15, weight: .black)).foregroundStyle(DL.onGold)
                    }
                }
                .overlay {
                    // Today wears a ring a little outside its circle.
                    if isToday { Circle().strokeBorder(DL.ink, lineWidth: 2.5).padding(-4) }
                }
            Text(isToday ? "Today" : Mock.weekInitials[day])
                .dlLabel(10, color: isToday ? DL.ink : DL.ink2)
                .fixedSize()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: Keep your gold (a guest, after their first gold)

struct G2SaveGoldSheetScreen: View {
    var guestGold: Int = Mock.roundGold

    var body: some View {
        // At 440 points the sheet covers the round's own gold row, so nothing shows over its edge.
        DLSheet(height: 440) {
            ResultsScreen(balance: guestGold)
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                Text("KEEP YOUR GOLD")
                    .font(DL.display(52))
                    .foregroundStyle(DL.ink)
                    .frame(height: 50)
                Text("You have \(guestGold) gold as a guest. Sign in and it follows you to every game.")
                    .font(DL.text(17))
                    .foregroundStyle(DL.ink2)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
                // The gold in question, and where it lives for now.
                HStack(alignment: .center, spacing: 12) {
                    DLCoin(size: 46)
                    Text("\(guestGold)")
                        .font(DL.display(92))
                        .foregroundStyle(DL.ink)
                        .frame(height: 80)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 8) {
                        DLTag(text: "Guest", symbol: "person.fill")
                        Text("On this phone only").dlLabel(10)
                    }
                }
                .dlCard(padding: 16, fill: DL.body, radius: 22)
                .padding(.top, 18)
                Spacer(minLength: 12)
                G2AppleButton()
                    .tap {
                        LiveNav.shared.back()
                        LiveNav.shared.say("Signed in. Your gold is saved")
                    }
                G2QuietButton(title: "Not now").goesBack().padding(.top, 4)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 10)
        }
    }
}

// MARK: Notifications, asked in our own words first

struct G2NotifySheetScreen: View {
    private let sample = Mock.notifications[0]
    private let promises = ["One a day at most.", "Off whenever you like."]

    var body: some View {
        DLSheet(height: 470) {
            ResultsScreen()
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                Text("WANT A NUDGE WHEN YOUR GOLD RESETS?")
                    .font(DL.display(40))
                    .foregroundStyle(DL.ink)
                    .lineSpacing(-6)
                    .fixedSize(horizontal: false, vertical: true)
                sampleNotification.padding(.top, 16)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(promises, id: \.self) { promise in
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .black))
                                .foregroundStyle(DL.ink)
                                .frame(width: 20)
                            Text(promise).font(DL.text(16, .medium)).foregroundStyle(DL.ink)
                        }
                    }
                }
                .padding(.top, 16)
                .padding(.leading, 4)
                Spacer(minLength: 12)
                DLTextKey(title: "Turn on", style: .ink)
                    .tap {
                        LiveNav.shared.back()
                        LiveNav.shared.say("Reminders are on")
                    }
                G2QuietButton(title: "Not now").goesBack().padding(.top, 4)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 10)
        }
    }

    /// The nudge itself, drawn the way it will arrive.
    private var sampleNotification: some View {
        HStack(alignment: .top, spacing: 12) {
            DLMonogram(size: 44)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(sample.title).font(DL.text(17, .semibold)).foregroundStyle(DL.ink)
                    Spacer(minLength: 8)
                    Text(sample.time).dlLabel(10)
                }
                Text(sample.detail)
                    .font(DL.text(15))
                    .foregroundStyle(DL.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .dlCard(padding: 16, fill: DL.body, radius: 22)
    }
}
