import SwiftUI

// IN A GAME, and when the round is over: everything after the gold key is pressed.

/// Floats on a running game: the gold collected this round, inside a ring that fills toward the next one.
struct SessionGoldHUD: View {
    var collected: Int = 2
    var toNext: Double = 0.65

    var body: some View {
        HStack(spacing: 8) {
            DLCoin(size: 16)
                .frame(width: 28, height: 28)
                .background(Circle().stroke(.white.opacity(0.25), lineWidth: 3))
                .overlay {
                    Circle()
                        .trim(from: 0, to: toNext)
                        .stroke(DL.gold, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
            Text("+\(collected)")
                .font(DL.display(24))
                .foregroundStyle(.white)
                .monospacedDigit()
        }
        .padding(.leading, 8)
        .padding(.trailing, 14)
        .frame(height: 44)
        .background {
            Capsule().fill(.black.opacity(0.42))
                .background(Capsule().fill(.ultraThinMaterial))
                .environment(\.colorScheme, .dark)
        }
        .accessibilityLabel("\(collected) gold this round")
    }
}

/// A game being played. The app adds two things on top of it: a way out, and the gold being collected.
struct GameScreen: View {
    var game: MockGame = Mock.tippyTower
    var phase: Double = 0.5
    var hint: String? = "TAP TO DROP"
    var collected: Int = 2
    var toNext: Double = 0.65
    /// Room above the two controls. 14 suits a hidden status bar, which is how a game normally runs.
    var topInset: CGFloat = 14

    var body: some View {
        ZStack {
            game.scene(phase: phase, showHUD: true).ignoresSafeArea()
            VStack {
                HStack {
                    DLMediaButton(symbol: "xmark", size: 44)
                    Spacer()
                    SessionGoldHUD(collected: collected, toNext: toNext)
                }
                .padding(.horizontal, 18)
                .padding(.top, topInset)
                Spacer()
                if let hint {
                    Text(hint)
                        .font(DL.label(13))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .frame(height: 36)
                        .background(Capsule().fill(.black.opacity(0.4)))
                        .padding(.bottom, 54)
                }
            }
        }
    }
}

/// The shape both end-of-round screens share: the game's last frame, dimmed, with a headline on it and
/// a close button and the balance above, then a column of rows on the page below.
private struct RoundOverLayout<Headline: View, Rows: View>: View {
    let game: MockGame
    let stillPhase: Double
    let dim: Double
    /// nil = the player's own balance.
    let chipBalance: Int?
    let rowSpacing: CGFloat
    @ViewBuilder var headline: () -> Headline
    @ViewBuilder var rows: () -> Rows

    var body: some View {
        ZStack(alignment: .top) {
            DL.body.ignoresSafeArea()
            VStack(spacing: 0) {
                ZStack {
                    ClipStill(game: game, phase: stillPhase, showHUD: false, focusY: 0.2)
                    Color.black.opacity(dim)
                    headline()
                    HStack {
                        DLMediaButton(symbol: "xmark", size: 40)
                            .tap { LiveNav.shared.closeAll() }
                            .accessibilityLabel("Close")
                        Spacer()
                        DLGoldChip(balance: chipBalance)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 58)
                    .frame(maxHeight: .infinity, alignment: .top)
                }
                .frame(height: 410)
                .clipShape(DL.screenShape)

                VStack(alignment: .leading, spacing: rowSpacing, content: rows)
                    .padding(.horizontal, 18)
                    .padding(.top, 20)
                Spacer(minLength: 0)
            }
        }
        .ignoresSafeArea()
    }
}

/// The round is over. Its score, the gold it added, where today stands with this game, and a vote.
struct ResultsScreen: View {
    var game: MockGame = Mock.roundGame
    var balance: Int? = nil
    /// nil = no vote yet, true = liked, false = disliked
    var voted: Bool? = nil
    /// The round that was actually played. nil shows the fixed demo round.
    var summary: RoundSummary? = nil
    @ObservedObject private var live = LiveStore.shared
    /// While true the chip shows the balance from before the round, so the gold is seen to arrive.
    @State private var holdBalance = true

    private var score: String {
        guard let result = summary?.result else { return Mock.roundScore }
        return result.scoreText ?? groupedNumber(result.score)
    }
    private var unit: String { summary?.result.unit ?? Mock.roundScoreLabel }
    private var played: String {
        guard let summary else { return Mock.roundLength }
        return LiveStore.playedText(summary.seconds)
    }
    private var gold: Int { summary?.gold ?? Mock.roundGold }
    private var isBest: Bool { summary?.isBest ?? Mock.roundIsBest }

    /// "2nd of 4", when the round had other players in it.
    private var standing: String? {
        guard let result = summary?.result, let place = result.placement,
              let players = result.playerCount, players > 1 else { return nil }
        let ending: String
        switch place {
        case 1: ending = "st"
        case 2: ending = "nd"
        case 3: ending = "rd"
        default: ending = "th"
        }
        return "\(place)\(ending) of \(players)"
    }

    private var chipBalance: Int? {
        if let summary, holdBalance { return summary.balanceBefore }
        return balance
    }

    var body: some View {
        RoundOverLayout(game: game, stillPhase: 0.95, dim: LiveMode.on ? 0.62 : 0.45,
                        chipBalance: chipBalance, rowSpacing: 16) {
            headline
        } rows: {
            goldRow
            voteRow
            HStack(spacing: 10) {
                DLTextKey(title: "Again", symbol: "arrow.counterclockwise")
                    .tap { LiveNav.shared.replaceTop(.play(game.id, solo: summary?.solo ?? false)) }
                DLTextKey(title: "Next clip", symbol: "chevron.down", style: .neutral)
                    .tap { LiveNav.shared.nextClip() }
            }
            postRow
        }
        .onAppear {
            // Hold the old balance for a beat, then let the chip roll up to the new one.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { holdBalance = false }
        }
    }

    private var headline: some View {
        VStack(spacing: 4) {
            Text("ROUND TIME \(played.uppercased())")
                .font(DL.label(11))
                .foregroundStyle(.white.opacity(0.8))
            Text(score)
                .font(DL.display(132))
                .foregroundStyle(.white)
                .padding(.top, -6)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .padding(.horizontal, 24)
            Text(unit.uppercased())
                .font(DL.display(28))
                .tracking(2)
                .foregroundStyle(.white)
                .padding(.top, -22)
            HStack(spacing: 6) {
                if isBest {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.up").font(.system(size: 10, weight: .black))
                        Text("NEW BEST").font(DL.label(11))
                    }
                    .foregroundStyle(DL.onGold)
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(Capsule().fill(DL.gold))
                }
                if let standing {
                    Text(standing.uppercased())
                        .font(DL.label(11))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(Capsule().fill(.white.opacity(0.2)))
                }
            }
            .padding(.top, 8)
            if let line = summary?.result.detail {
                Text(line)
                    .font(DL.text(14, .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 28)
                    .padding(.top, 6)
            }
        }
        .padding(.top, 40)
    }

    /// The gold this round added, and how much of today's 100 this game has now given.
    private var goldRow: some View {
        let todayLine = summary?.wasFull == true
            ? "Limit reached. More gold in \(Mock.resetIn)."
            : "\(game.earnedToday) of 100 from \(game.title) today"
        return HStack(alignment: .center, spacing: 14) {
            HStack(alignment: .center, spacing: 10) {
                DLCoin(size: 46)
                Text("+\(gold)").font(DL.display(92)).foregroundStyle(DL.ink)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("GOLD COLLECTED").dlLabel(10.5)
                Text(todayLine)
                    .font(DL.text(14, .medium))
                    .foregroundStyle(DL.ink)
                    .fixedSize(horizontal: false, vertical: true)
                DLMeter(value: Double(game.earnedToday))
            }
        }
        .frame(height: 84)
        .contentShape(Rectangle())
        .opens(.fairness(game.id))
    }

    private var voteRow: some View {
        HStack(spacing: 10) {
            Text("Was it good?").font(DL.text(16, .semibold)).foregroundStyle(DL.ink)
            Spacer()
            VoteKey(symbol: "hand.thumbsup.fill", label: "LIKE", chosen: voted == true, celebrates: true)
                .tap { live.setVote(game.id, like: true) }
            VoteKey(symbol: "hand.thumbsdown.fill", label: "DISLIKE", chosen: voted == false, celebrates: false)
                .tap { live.setVote(game.id, like: false) }
        }
        .dlCard(padding: 12, radius: 22)
    }

    /// Posting the run as a clip. This is where the feed's videos come from.
    private var postRow: some View {
        HStack(spacing: 12) {
            ClipStill(game: game, phase: 0.85, showHUD: true, focusY: 0.15)
                .frame(width: 44, height: 62)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("Post this run").font(DL.text(16, .semibold)).foregroundStyle(DL.ink)
                Text("Your best 42 seconds, ready as a clip.").font(DL.text(13)).foregroundStyle(DL.ink2)
            }
            Spacer()
            Image(systemName: "arrow.up.circle.fill").font(.system(size: 28)).foregroundStyle(DL.ink)
        }
        .dlCard(padding: 12, radius: 22)
        .opens(.shareRun(game.id))
    }
}

/// Like or Dislike on the results screen. The chosen one fills with ink.
private struct VoteKey: View {
    let symbol: String
    let label: String
    let chosen: Bool
    /// Only a like gets the small kick when it lands.
    let celebrates: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .bold))
                .likeCelebration(chosen && celebrates, tint: DL.ink, burst: false)
            Text(label).font(DL.label(11))
        }
        .foregroundStyle(chosen ? DL.onInk : DL.ink)
        .padding(.horizontal, 13)
        .frame(height: 40)
        .background(Capsule().fill(chosen ? DL.ink : DL.body))
        .overlay(Capsule().strokeBorder(chosen ? Color.clear : DL.line))
    }
}

/// The daily limit as a finish line: this game has given all 100 for today. Playing on is never blocked.
struct ResultsFullScreen: View {
    var game: MockGame = Mock.capGame
    /// The round that was actually played. nil shows the fixed demo round.
    var summary: RoundSummary? = nil
    @ObservedObject private var live = LiveStore.shared

    /// Three games to try instead. In the app, the ones that can still give gold today come first.
    private var suggestions: [MockGame] {
        guard LiveMode.on else { return [Mock.inkland, Mock.fiveUp, Mock.gulpCity] }
        let others = Mock.games.filter { $0.id != game.id }
        let ordered = others.filter { !$0.isFullToday } + others.filter(\.isFullToday)
        return Array(ordered.prefix(3))
    }

    var body: some View {
        RoundOverLayout(game: game, stillPhase: 0.85, dim: 0.5,
                        chipBalance: LiveMode.on ? nil : Mock.capBalanceAfter, rowSpacing: 14) {
            VStack(spacing: 14) {
                DLRing(progress: 1, size: 132, line: 14, showTick: false)
                    .overlay {
                        Image(systemName: "checkmark")
                            .font(.system(size: 50, weight: .black))
                            .foregroundStyle(.white)
                    }
                    .environment(\.colorScheme, .dark)
                Text("100 OF 100").font(DL.display(44)).foregroundStyle(.white)
            }
            .padding(.top, 44)
        } rows: {
            Text("THAT'S ALL 100 FROM \(game.title.uppercased()) TODAY")
                .font(DL.display(34))
                .foregroundStyle(DL.ink)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(-4)
            HStack(spacing: 10) {
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(DL.goldText)
                VStack(alignment: .leading, spacing: 1) {
                    Text("More gold in \(Mock.resetIn)")
                        .font(DL.text(16, .semibold))
                        .foregroundStyle(DL.ink)
                    Text("\(Mock.capOtherGamesWithGold) other games still have gold today.")
                        .font(DL.text(14))
                        .foregroundStyle(DL.ink2)
                }
            }
            .dlCard(padding: 14, radius: 22)
            HStack(spacing: 10) {
                ForEach(suggestions) { other in
                    DLClipCard(game: other, width: 114, height: 124)
                        .tap { LiveNav.shared.replaceTop(.gameReady(other.id)) }
                }
            }
            DLTextKey(title: "Find another game", symbol: "chevron.down")
                .tap { LiveNav.shared.nextClip() }
            Text("Keep playing for fun")
                .font(DL.text(16, .semibold))
                .foregroundStyle(DL.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .contentShape(Rectangle())
                .tap { LiveNav.shared.replaceTop(.play(game.id, solo: summary?.solo ?? false)) }
        }
    }
}
