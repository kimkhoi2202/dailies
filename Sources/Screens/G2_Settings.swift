import SwiftUI

// SETTINGS: how the app looks, what may nudge you, how the feed plays, your account, and help.

/// The app in miniature, in whichever appearance the environment gives it: page, a title, a card and the gold key.
private struct G2TinyApp: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Capsule().fill(DL.ink).frame(width: 12, height: 3)
            RoundedRectangle(cornerRadius: 3, style: .continuous).fill(DL.surface).frame(height: 15)
            RoundedRectangle(cornerRadius: 2.5, style: .continuous).fill(DL.gold).frame(height: 7)
        }
        .padding(5)
        .frame(width: 32, height: 44, alignment: .top)
        .background(DL.body)
    }
}

/// The triangle below the diagonal that runs from top right to bottom left.
private struct G2LowerTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.addLines([
                CGPoint(x: rect.maxX, y: rect.minY),
                CGPoint(x: rect.maxX, y: rect.maxY),
                CGPoint(x: rect.minX, y: rect.maxY),
            ])
            path.closeSubpath()
        }
    }
}

enum G2Appearance: String, CaseIterable { case system = "System", light = "Light", dark = "Dark" }

/// One way the app can look: a small preview beside its name. The chosen one is outlined in ink.
struct G2AppearanceTile: View {
    var mode: G2Appearance
    var selected: Bool = false

    var body: some View {
        let outline = RoundedRectangle(cornerRadius: 22, style: .continuous)
        HStack(spacing: 9) {
            preview
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(DL.line))
            Text(mode.rawValue)
                .font(DL.text(14, .semibold))
                .foregroundStyle(DL.ink)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.leading, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 66)
        .background(outline.fill(DL.surface))
        .overlay(outline.strokeBorder(selected ? DL.ink : .clear, lineWidth: 2))
        .accessibilityLabel(selected ? "\(mode.rawValue), selected" : mode.rawValue)
    }

    @ViewBuilder private var preview: some View {
        switch mode {
        case .light:
            G2TinyApp().environment(\.colorScheme, .light)
        case .dark:
            G2TinyApp().environment(\.colorScheme, .dark)
        case .system:
            // Following the phone: light, with the dark version showing across the diagonal.
            G2TinyApp().environment(\.colorScheme, .light)
                .overlay(G2TinyApp().environment(\.colorScheme, .dark).clipShape(G2LowerTriangle()))
        }
    }
}

struct G2SettingsScreen: View {
    @ObservedObject private var live = LiveStore.shared

    var body: some View {
        DLTabs(selected: 2) {
            DLPage(spacing: 14) {
                DLNavBar(title: "Settings")
                group("Appearance") {
                    HStack(spacing: 8) {
                        // The store keeps the choice as a number: 0 follows the phone, 1 light, 2 dark.
                        ForEach(Array(G2Appearance.allCases.enumerated()), id: \.offset) { index, mode in
                            G2AppearanceTile(mode: mode, selected: LiveMode.on ? live.s.appearance == index : mode == .system)
                                .tap { live.s.appearance = index }
                        }
                    }
                }
                if LiveMode.on {
                    group("This demo") { demoCard }
                }
                group("Notifications") {
                    card {
                        toggle("Daily gold reset", startsOn: true)
                        G2Hairline()
                        toggle("Streak reminder", startsOn: true)
                        G2Hairline()
                        toggle("Friends pass your score", startsOn: true)
                    }
                }
                group("Play") {
                    card {
                        toggle("Autoplay clips", startsOn: true)
                        G2Hairline()
                        toggle("Sound", startsOn: false)
                        G2Hairline()
                        toggle("Streaks", startsOn: true)
                    }
                }
                group("Account") { accountCard }
                group("Help") {
                    card {
                        link("How gold works").contentShape(Rectangle()).opens(.fairness(Mock.tippyTower.id))
                        G2Hairline()
                        link("Report a problem").contentShape(Rectangle()).notYet("Reporting a problem")
                    }
                }
                HStack {
                    Text("Delete account")
                        .font(DL.text(14, .medium))
                        .foregroundStyle(DL.ink2)
                        .notYet("Deleting your account")
                    Spacer()
                    Text("DEGEN 1.0").dlLabel(10, color: DL.ink3)
                }
                .padding(.horizontal, 16)
                .padding(.top, -2)
            }
        }
    }

    /// Only in the app: quicker gold for a short demo, and a way back to the starting story.
    private var demoCard: some View {
        card {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Faster gold").font(DL.text(16, .medium)).foregroundStyle(DL.ink)
                    Text("10 times the real rate, so short rounds show gold").font(DL.text(12)).foregroundStyle(DL.ink2)
                }
                Spacer()
                G2Switch(isOn: live.s.fastGold).tap { live.s.fastGold.toggle() }
            }
            .frame(height: 52)
            G2Hairline()
            HStack {
                Text("Start over").font(DL.text(16, .medium)).foregroundStyle(DL.ink)
                Spacer()
                Text("A new account with 0 gold").font(DL.text(13)).foregroundStyle(DL.ink2)
            }
            .frame(height: 42)
            .contentShape(Rectangle())
            .tap {
                live.reset()
                LiveNav.shared.say("Started over with a new account")
            }
        }
    }

    private var accountCard: some View {
        card {
            HStack(spacing: 12) {
                Image(systemName: "apple.logo")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DL.onInk)
                    .offset(y: -1)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(DL.ink))
                VStack(alignment: .leading, spacing: 0) {
                    Text(Mock.displayName).font(DL.text(16, .medium)).foregroundStyle(DL.ink)
                    Text("Signed in with Apple").font(DL.text(13)).foregroundStyle(DL.ink2)
                }
                Spacer()
                Text("Sign out").font(DL.text(14, .semibold)).foregroundStyle(DL.ink).notYet("Signing out")
            }
            .frame(height: 52)
        }
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).dlLabel(10.5).padding(.leading, 16)
            content()
        }
    }

    private func card<Content: View>(@ViewBuilder rows: () -> Content) -> some View {
        VStack(spacing: 0, content: rows)
            .padding(.horizontal, 16)
            .dlCard(padding: 0)
    }

    /// A switch the store remembers by its title.
    private func toggle(_ title: String, startsOn: Bool) -> some View {
        HStack {
            Text(title).font(DL.text(16, .medium)).foregroundStyle(DL.ink)
            Spacer()
            G2Switch(isOn: LiveMode.on ? live.isOn(title, default: startsOn) : startsOn)
                .tap { live.flip(title, default: startsOn) }
        }
        .frame(height: 42)
    }

    private func link(_ title: String) -> some View {
        HStack {
            Text(title).font(DL.text(16, .medium)).foregroundStyle(DL.ink)
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(DL.ink2)
        }
        .frame(height: 42)
    }
}
