import SwiftUI

// SYSTEM MOMENTS: the reasons to come back, as they show outside the app. Both screens here are
// pictures of system surfaces (the Lock Screen, Home Screen widgets). Neither is a screen of the app.

/// The app icon as the Home Screen draws it.
struct AppIconTile: View {
    var size: CGFloat = 64
    var dark: Bool = false

    var body: some View {
        // Fixed colours, not tokens: an icon does not follow the screen it is drawn on.
        let gold = Color(hex: dark ? "FFC531" : "F5B301")
        let ground = dark ? Color(hex: "0E0E0F") : gold
        DLMonogram(size: size, plain: true, ink: dark ? gold : Color(hex: "151412"), counter: ground)
            .background(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous).fill(ground))
    }
}

/// Tomorrow morning, on the Lock Screen: the limits have reset.
struct LockScreenMoment: View {
    var body: some View {
        ZStack {
            ClipStill(game: Mock.tippyTower, phase: 0.3, showHUD: false, focusY: 0.5)
                .blur(radius: 28)
                .scaleEffect(1.2)
            Color.black.opacity(0.35)
            VStack(spacing: 0) {
                Text("Sunday, November 15")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.top, 86)
                Text("8:00")
                    .font(.system(size: 108, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.top, -10)
                widgets
                Spacer()
                notification
            }
        }
        .ignoresSafeArea()
    }

    /// The Lock Screen widgets: today's gold as a ring, and three lines beside it.
    private var widgets: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().stroke(.white.opacity(0.3), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: 0.02)
                    .stroke(.white, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: -2) {
                    Text("0").font(DL.display(22))
                    Text("OF 10").font(.system(size: 8, weight: .bold))
                }
            }
            .frame(width: 58, height: 58)
            VStack(alignment: .leading, spacing: 1) {
                Text("412 gold").font(.system(size: 16, weight: .bold))
                Group {
                    Text("You can collect gold again")
                    Text("Day 7 if you play today")
                }
                .font(.system(size: 14, weight: .medium))
                .opacity(0.85)
            }
            Spacer()
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 44)
        .padding(.top, 6)
    }

    private var notification: some View {
        HStack(alignment: .top, spacing: 12) {
            AppIconTile(size: 40)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("You can collect gold again").font(.system(size: 16, weight: .semibold))
                    Spacer()
                    Text("now").font(.system(size: 14)).opacity(0.6)
                }
                Text("Your limits reset. 3 new clips since yesterday.")
                    .font(.system(size: 15))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(.white)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(.ultraThinMaterial))
        .environment(\.colorScheme, .dark)
        .padding(.horizontal, 12)
        .padding(.bottom, 150)
    }
}

/// The Home Screen: the icon among others, and two widgets.
struct WidgetsMoment: View {
    @Environment(\.colorScheme) private var scheme

    private let gap: CGFloat = 22
    private let widgetSide: CGFloat = 162

    var body: some View {
        let wallpaper = scheme == .dark ? ["1B1B1F", "0A0A0B"] : ["E9E3D8", "CFC7B8"]
        ZStack {
            LinearGradient(colors: wallpaper.map { Color(hex: $0) }, startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(alignment: .leading, spacing: gap) {
                HStack(alignment: .top, spacing: gap) {
                    goalWidget
                    VStack(spacing: gap) {
                        HStack(spacing: gap) {
                            homeIcon(isDailies: true)
                            homeIcon(isDailies: false)
                        }
                        HStack(spacing: gap) {
                            homeIcon(isDailies: false)
                            homeIcon(isDailies: false)
                        }
                    }
                }
                balanceWidget
                Spacer()
            }
            .padding(.horizontal, 28)
            .padding(.top, 78)
        }
    }

    private func homeIcon(isDailies: Bool) -> some View {
        VStack(spacing: 5) {
            if isDailies {
                AppIconTile(size: 64, dark: scheme == .dark)
            } else {
                RoundedRectangle(cornerRadius: 14.5, style: .continuous)
                    .fill(DL.ink.opacity(0.1))
                    .frame(width: 64, height: 64)
            }
            // A blank name keeps the other icons the same height as ours.
            Text(isDailies ? "DEGEN" : " ").font(.system(size: 12, weight: .medium)).foregroundStyle(DL.ink)
        }
    }

    /// The small widget: today's gold against the goal.
    private var goalWidget: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                DLRing(progress: 0.6, size: 46, line: 6)
                Spacer()
                DLCoin(size: 18)
            }
            Spacer()
            Text("6").font(DL.display(44)).foregroundStyle(DL.ink) + Text(" OF 10").font(DL.label(11)).foregroundStyle(DL.ink2)
            Text("Today's gold").font(DL.text(13, .semibold)).foregroundStyle(DL.ink2)
        }
        .padding(16)
        .frame(width: widgetSide, height: widgetSide)
        .background(RoundedRectangle(cornerRadius: 30, style: .continuous).fill(DL.surface))
    }

    /// The medium widget: the balance on one side, the streak on the other.
    private var balanceWidget: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Balance").dlLabel(10)
                HStack(spacing: 8) {
                    DLCoin(size: 24)
                    Text("\(Mock.balance)").font(DL.display(52)).foregroundStyle(DL.ink)
                }
                Spacer()
                Text("More gold in \(Mock.resetIn)").font(DL.text(12, .semibold)).foregroundStyle(DL.goldText)
            }
            DL.line.frame(width: 1)
            VStack(alignment: .leading, spacing: 9) {
                Text("Streak").dlLabel(10)
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text("\(Mock.streakDays)").font(DL.display(34)).foregroundStyle(DL.ink)
                    Text("days").font(DL.text(13, .semibold)).foregroundStyle(DL.ink2)
                }
                HStack(spacing: 5) {
                    ForEach(Mock.streakWeek.indices, id: \.self) { day in
                        Circle().fill(Mock.streakWeek[day] ? DL.gold : DL.sunken).frame(width: 13, height: 13)
                    }
                }
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(height: widgetSide)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 30, style: .continuous).fill(DL.surface))
    }
}
