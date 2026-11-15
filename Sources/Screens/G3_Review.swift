import SwiftUI

// THE REVIEW: under way, passed, and "not yet". The review is what makes gold fair, so each screen
// shows its working: how many sessions were played, what was checked, and what was found.

private let reviewed = Mock.reviewGame

/// The game under review on one quiet line: its art, its name and a few words about where it stands.
private struct G3SubjectLine: View {
    var detail: String

    var body: some View {
        HStack(spacing: 10) {
            DLThumb(game: reviewed, size: 32)
            Text(reviewed.title).font(DL.text(15, .semibold)).foregroundStyle(DL.ink)
            Text(detail).font(DL.text(15)).foregroundStyle(DL.ink2)
            Spacer(minLength: 0)
        }
    }
}

private extension View {
    /// A list of checks sits on a surface card with tighter padding than the standard card.
    func g3ListCard(vertical: CGFloat = 3) -> some View {
        padding(.horizontal, 14)
            .padding(.vertical, vertical)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: DL.cardRadius, style: .continuous).fill(DL.surface))
    }
}

// MARK: Under way

struct G3ReviewProgressScreen: View {
    private struct Check {
        let title: String
        let detail: String
        let state: G3CheckState

        var stateWord: String {
            switch state {
            case .done: return "Done"
            case .running: return "Running"
            case .waiting: return "Waiting"
            }
        }
    }

    private let played = 148

    /// The checks in the order the review runs them. The last two are not finished, so they say so.
    private var checks: [Check] {
        let all = Mock.reviewChecks
        return [
            Check(title: all[3].title, detail: all[3].detail, state: .done),
            Check(title: all[0].title, detail: all[0].detail, state: .done),
            Check(title: all[1].title, detail: "None so far. Still trying to collect gold without playing.", state: .running),
            Check(title: all[2].title, detail: "Starts once the long runs are in.", state: .waiting),
        ]
    }

    var body: some View {
        G3Flow(spacing: 0) {
            G3Title(lines: ["Playing", "your game"])
            G3SubjectLine(detail: "sent 6 minutes ago").padding(.top, 12)
            tally.padding(.top, 22)
            checkList.padding(.top, 20)
        } footer: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(DL.ink2)
                        .padding(.top, 1)
                    Text("You can leave. We will send a notification when the review is done.")
                        .font(DL.text(14))
                        .foregroundStyle(DL.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 4)
                DLTextKey(title: "Close for now", style: .neutral).tap { LiveNav.shared.closeFlow() }
            }
        }
    }

    /// 148 of 240, with the session being played this minute beside it.
    private var tally: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .bottom, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(played)").font(DL.display(104)).foregroundStyle(DL.ink)
                        Text("OF \(Mock.reviewSessions)").font(DL.display(40)).foregroundStyle(DL.ink3)
                    }
                    .fixedSize()
                    .frame(height: 90)
                    Text("Test sessions played").dlLabel(12)
                }
                Spacer(minLength: 12)
                ClipStill(game: reviewed, phase: 0.3, showHUD: true, focusY: 0.12)
                    .overlay(alignment: .bottom) {
                        Text("SESSION \(played + 1)")
                            .font(DL.label(8.5))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .frame(height: 18)
                            .background(Capsule().fill(.black.opacity(0.5)))
                            .padding(.bottom, 6)
                    }
                    .frame(width: 84, height: 116)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            DLMeter(value: Double(played), total: Double(Mock.reviewSessions), height: 10)
            HStack {
                Text("About 4 minutes left").dlLabel(10.5)
                Spacer()
                Text("62%").dlLabel(10.5, color: DL.ink)
            }
        }
    }

    private var checkList: some View {
        let checks = self.checks
        return VStack(spacing: 0) {
            ForEach(checks.indices, id: \.self) { index in
                let check = checks[index]
                if index > 0 { DLDivider(inset: 38) }
                HStack(alignment: .top, spacing: 12) {
                    G3StateMark(state: check.state).padding(.top, 1)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(check.title)
                                .font(DL.text(16, .semibold))
                                .foregroundStyle(check.state == .waiting ? DL.ink2 : DL.ink)
                            Spacer(minLength: 8)
                            Text(check.stateWord).dlLabel(10, color: check.state == .running ? DL.goldText : DL.ink3)
                        }
                        Text(check.detail)
                            .font(DL.text(13))
                            .foregroundStyle(DL.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 11)
            }
        }
        .g3ListCard()
    }
}

// MARK: Passed

struct G3ReviewResultScreen: View {
    var body: some View {
        G3Flow(spacing: 12) {
            G3Title(lines: ["Reviewed.", "Now in Videos"]) { G3Seal(size: 34) }
            rateCard.padding(.top, 6)
            HStack(spacing: 10) {
                dailyLimit(Mock.perGameDailyCap, for: "Per player, this game")
                dailyLimit(Mock.perStudioDailyCap, for: "Per player, \(Mock.myStudio)")
            }
            checkList
        } footer: {
            DLTextKey(title: "See it in Videos", symbol: "play.fill")
                .tap {
                    // Spiral Drop's clip is the fifth in the feed.
                    LiveNav.shared.closeAll()
                    LiveNav.shared.tab = 1
                    LiveNav.shared.videoIndex = 4
                }
        }
    }

    /// The rate the review set, and the play it was measured from.
    private var rateCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                DLThumb(game: reviewed, size: 32)
                Text(reviewed.title).font(DL.text(16, .semibold)).foregroundStyle(DL.ink)
                Text(reviewed.studio).font(DL.text(14)).foregroundStyle(DL.ink2)
                Spacer(minLength: 8)
                DLTag(text: "Live", filled: true)
            }
            HStack(alignment: .center, spacing: 12) {
                DLCoin(size: 44)
                Text(Mock.reviewRate)
                    .font(DL.display(108))
                    .foregroundStyle(DL.ink)
                    .fixedSize()
                    .frame(height: 88)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(["GOLD", "A MINUTE"], id: \.self) { word in
                        Text(word).font(DL.display(26)).foregroundStyle(DL.ink).frame(height: 26)
                    }
                    Text("Same for everyone").font(DL.text(12, .medium)).foregroundStyle(DL.ink2).padding(.top, 4)
                }
                .fixedSize()
                Spacer(minLength: 0)
            }
            .padding(.top, 10)
            DL.ink.opacity(0.12).frame(height: 1).padding(.top, 8)
            HStack(alignment: .top, spacing: 12) {
                measure("\(Mock.reviewSessions)", "Test sessions")
                measure(Mock.reviewMedianSession, "Median round")
                measure("About 2", "Gold a round")
            }
            .padding(.top, 10)
        }
        .dlCard(padding: 14, fill: DL.goldWash)
    }

    private func measure(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value.uppercased()).font(DL.display(26)).foregroundStyle(DL.ink).fixedSize().frame(height: 26)
            Text(label).dlLabel(10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// One of the two daily limits, stated plainly.
    private func dailyLimit(_ amount: Int, for label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(amount)").font(DL.display(32)).foregroundStyle(DL.ink)
                Text("A DAY").font(DL.display(20)).foregroundStyle(DL.ink3)
            }
            .fixedSize()
            .frame(height: 30)
            Text(label).dlLabel(9.5).lineLimit(1)
        }
        .dlCard(padding: 12, radius: 22)
    }

    private var checkList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("What the review checked").dlLabel(10.5).padding(.top, 10).padding(.bottom, 2)
            ForEach(Mock.reviewChecks.indices, id: \.self) { index in
                let check = Mock.reviewChecks[index]
                if index > 0 { DLDivider(inset: 34) }
                HStack(alignment: .top, spacing: 10) {
                    G3StateMark(state: .done, size: 24).padding(.top, 1)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(check.title).font(DL.text(15, .semibold)).foregroundStyle(DL.ink)
                        Text(check.detail)
                            .font(DL.text(13))
                            .foregroundStyle(DL.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 7)
            }
        }
        .g3ListCard()
    }
}

// MARK: Not yet

struct G3ReviewChangesScreen: View {
    private let flagged = 31
    private let fixes = [
        "Pause gold when the screen has not been touched for 10 seconds.",
        "End the round if the ball has not dropped a floor in 20 seconds.",
    ]

    var body: some View {
        G3Flow(spacing: 0) {
            G3Title(lines: ["Not yet"], size: 64)
            Text("Gold could be collected while standing still.")
                .font(DL.text(22, .semibold))
                .foregroundStyle(DL.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
            G3SubjectLine(detail: "is not in Videos yet").padding(.top, 14)
            evidence.padding(.top, 18)
            fixList.padding(.top, 12)
        } footer: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(DL.ink2)
                    Text("Fair difficulty and original work both passed.")
                        .font(DL.text(14))
                        .foregroundStyle(DL.ink2)
                }
                .padding(.horizontal, 4)
                DLTextKey(title: "Fix and resend", style: .ink).tap { LiveNav.shared.closeFlow() }
            }
        }
    }

    /// What the reviewer saw, as a count and as the sessions themselves.
    private var evidence: some View {
        let total = Mock.reviewSessions
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(DL.danger)
                Text("What the reviewer saw").dlLabel(10.5)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(flagged)").font(DL.display(60)).foregroundStyle(DL.ink)
                Text("OF \(total) SESSIONS").font(DL.display(28)).foregroundStyle(DL.ink3)
            }
            .fixedSize()
            .frame(height: 54)
            .padding(.top, 6)
            G3SessionGrid(total: total, flagged: flagged).padding(.top, 10)
            Text("In \(flagged) of \(total) sessions the reviewer collected gold without touching the screen after level 2.")
                .font(DL.text(15))
                .foregroundStyle(DL.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
        }
        .dlCard()
    }

    private var fixList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("What to change").dlLabel(10.5).padding(.bottom, 4)
            ForEach(fixes.indices, id: \.self) { index in
                if index > 0 { DL.line.frame(height: 1) }
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("\(index + 1)")
                        .font(DL.display(22))
                        .foregroundStyle(DL.ink3)
                        .frame(width: 16, alignment: .leading)
                    Text(fixes[index])
                        .font(DL.text(15, .medium))
                        .foregroundStyle(DL.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 10)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DL.cardRadius, style: .continuous).fill(DL.surface))
    }
}
