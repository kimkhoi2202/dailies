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

/// The round is over. A leaderboard for this game is the main thing: your row moves into its place,
/// the player just above you is the next one to beat, and a large key plays again at once.
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
    /// false while your row still sits where it started, true once it has moved to its place.
    @State private var settled = false

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

    private var board: ResultsBoard {
        ResultsBoard(game: game, score: summary?.result.score ?? Int(Mock.roundScore) ?? 0,
                     bestBefore: summary?.bestBefore ?? 33, isBest: isBest)
    }

    private func leave() {
        LiveNav.shared.closeAll()
        CommunityStore.shared.rateIfDue(game.id)
    }

    private func playAgain() {
        LiveNav.shared.replaceTop(.play(game.id, solo: summary?.solo ?? false))
    }

    var body: some View {
        let board = board
        VStack(spacing: 0) {
            header
            ResultsBoardCard(board: board, settled: settled)
                .padding(.horizontal, 16)
                .padding(.top, 14)
            if LiveMode.on, DeviceAccount.kind == nil {
                // A guest's score lives on this phone's silent account. An account keeps it.
                HStack(spacing: 10) {
                    Image(systemName: "person.crop.circle.badge.plus").font(.system(size: 18, weight: .semibold))
                    Text("Create an account to keep your score").font(DL.text(15, .semibold))
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(DL.ink2)
                }
                .foregroundStyle(DL.ink)
                .padding(.horizontal, 16)
                .frame(height: 52)
                .background(DL.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .opens(.account("Create an account to keep your score."))
                .padding(.horizontal, 16)
                .padding(.top, 10)
            }
            Spacer(minLength: 0)
        }
        .ignoresSafeArea(edges: .top)
        .safeAreaInset(edge: .bottom, spacing: 0) { actions }
        .background(DL.body.ignoresSafeArea())
        .onAppear {
            // Hold the old balance for a beat, then let the chip roll up to the new one.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { holdBalance = false }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                withAnimation(.spring(duration: 0.75, bounce: 0.25)) { settled = true }
            }
        }
    }

    /// The game's last frame, dimmed, with the round's score, the new best badge and the gold on it.
    private var header: some View {
        ZStack(alignment: .bottom) {
            ClipStill(game: game, phase: 0.95, showHUD: false, focusY: 0.2)
            Color.black.opacity(LiveMode.on ? 0.62 : 0.45)
            VStack(spacing: 0) {
                HStack {
                    DLMediaButton(symbol: "xmark", size: 40)
                        .tap(leave)
                        .accessibilityLabel("Close")
                    Spacer()
                    DLGoldChip(balance: chipBalance)
                }
                Spacer(minLength: 0)
                HStack(alignment: .bottom, spacing: 12) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(game.title.uppercased()) · \(played.uppercased())")
                            .font(DL.label(11))
                            .foregroundStyle(.white.opacity(0.8))
                            .lineLimit(1)
                        HStack(alignment: .lastTextBaseline, spacing: 8) {
                            Text(score)
                                .font(DL.display(68))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                            Text(unit.uppercased())
                                .font(DL.display(22))
                                .tracking(1)
                                .foregroundStyle(.white)
                                .lineLimit(1)
                        }
                        HStack(spacing: 6) {
                            if isBest {
                                HStack(spacing: 5) {
                                    Image(systemName: "arrow.up").font(.system(size: 10, weight: .black))
                                    Text("NEW BEST").font(DL.label(11))
                                }
                                .foregroundStyle(DL.onGold)
                                .padding(.horizontal, 10)
                                .frame(height: 24)
                                .background(Capsule().fill(DL.gold))
                            }
                            if let standing {
                                Text(standing.uppercased())
                                    .font(DL.label(11))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 10)
                                    .frame(height: 24)
                                    .background(Capsule().fill(.white.opacity(0.2)))
                            }
                        }
                    }
                    Spacer(minLength: 8)
                    goldBadge
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 58)
            .padding(.bottom, 16)
        }
        .frame(height: 250)
        .clipShape(DL.screenShape)
    }

    /// The gold this round added. Tapping it explains how gold is counted.
    private var goldBadge: some View {
        VStack(alignment: .trailing, spacing: 2) {
            HStack(spacing: 6) {
                DLCoin(size: 24)
                Text("+\(gold)").font(DL.display(40)).foregroundStyle(.white).fixedSize()
            }
            Text(summary?.wasFull == true ? "LIMIT REACHED" : "\(game.earnedToday) OF 100 TODAY")
                .font(DL.label(10))
                .foregroundStyle(.white.opacity(0.8))
        }
        .padding(.bottom, 4)
        .contentShape(Rectangle())
        .opens(.fairness(game.id))
    }

    /// The large Play again key, with Share and Leave below it. Always on screen.
    private var actions: some View {
        VStack(spacing: 10) {
            DLKey(style: .gold, radius: 26, depth: 7) {
                HStack(spacing: 12) {
                    Image(systemName: "arrow.counterclockwise").font(.system(size: 26, weight: .black))
                    Text("PLAY AGAIN").font(DL.display(40)).tracking(1)
                        .lineLimit(1).minimumScaleFactor(0.6)
                }
            }
            .frame(height: 92)
            .tap(playAgain)
            .accessibilityLabel("Play again")
            HStack(spacing: 10) {
                DLKey(style: .neutral, radius: 18, depth: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.circle.fill").font(.system(size: 15, weight: .bold))
                        Text("SHARE RUN").font(DL.display(18)).tracking(0.6)
                    }
                }
                .frame(height: 48)
                .opens(.shareRun(game.id))
                DLKey(style: .neutral, radius: 18, depth: 4) {
                    Text("LEAVE").font(DL.display(18)).tracking(0.6)
                }
                .frame(height: 48)
                .tap(leave)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }
}

/// The rows of the round's leaderboard: this game's best scores from the server, filled out with
/// friends so the board is never empty, and your round placed among them.
struct ResultsBoard {
    struct Row: Identifiable, Equatable {
        let id: String
        let name: String
        let score: Int
        let isYou: Bool
    }

    let game: MockGame
    /// The players around you, best first, without you.
    let others: [Row]
    /// Your score this round.
    let score: Int
    /// Where your row starts before it moves: your best before this round, or nil to rise from the bottom.
    let start: Int?

    init(game: MockGame, score: Int, bestBefore: Int, isBest: Bool) {
        self.game = game
        self.score = score
        start = isBest && bestBefore > 0 ? bestBefore : nil
        let store = LiveStore.shared
        let me = Mock.handle
        var rows = store.board(for: game.id)
            .filter { !$0.you && $0.handle != me }
            .map { Row(id: $0.handle, name: $0.handle, score: Int($0.score.rounded()), isYou: false) }
        if rows.count < 5 {
            for (name, value) in LiveBoard.sampleScores(for: game) where rows.count < 6 && !rows.contains(where: { $0.name == name }) {
                rows.append(Row(id: name, name: name, score: value, isYou: false))
            }
        }
        if rows.count < 5 {
            // A game with no sample scores gets friends spread around the player's own score.
            let base = max(score, bestBefore, 10)
            let factors = [1.6, 1.22, 1.07, 0.84, 0.58]
            let top = game.kind == .gulpCity ? 100 : (game.kind == .inkland ? 1000 : Int.max)
            for (index, name) in GameOptions().friendNames.enumerated() where rows.count < 6 && index < factors.count
                && !rows.contains(where: { $0.name == name }) {
                let value = min(top, max(1, Int((Double(base) * factors[index]).rounded()) + (index < 3 ? 1 : 0)))
                rows.append(Row(id: name, name: name, score: value, isYou: false))
            }
        }
        others = rows.sorted { $0.score > $1.score }
    }

    /// How many players are ahead of a score. A tie stays ahead: you need more to pass.
    private func ahead(of value: Int) -> Int { others.filter { $0.score >= value }.count }

    /// Your place on the board once your row has moved, from 1.
    var rank: Int { ahead(of: score) + 1 }

    /// The board's rows at one moment: up to six, around where your row ends.
    func rows(settled: Bool) -> (first: Int, rows: [Row]) {
        let final = ahead(of: score)
        let low = max(0, min(final - 3, others.count - 5))
        let window = Array(others[low..<min(others.count, low + 5)])
        let shown = settled ? score : (start ?? -1)
        let you = Row(id: "you", name: Mock.handle, score: shown, isYou: true)
        var all = window
        all.insert(you, at: window.filter { $0.score >= shown }.count)
        return (low + 1, all)
    }

    /// The player just above your row, the next one to pass.
    var target: Row? {
        let count = ahead(of: score)
        return count > 0 ? others[count - 1] : nil
    }

    /// "3 more floors": what it takes to pass the player above.
    var targetText: String? {
        guard let target else { return nil }
        let gap = LiveBoard.gap(target.score + 1, score, game)
        guard let space = gap.firstIndex(of: " "), gap[gap.index(after: space)...].count > 1 else { return "\(gap) more" }
        return "\(gap[..<space]) more\(gap[space...])"
    }

    /// "You passed kaz": the players this round's new best moved you past.
    var passedText: String? {
        guard let start else { return nil }
        let passed = others.filter { $0.score >= start && $0.score < score }
        guard let first = passed.first else { return nil }
        return passed.count == 1 ? "You passed \(first.name)" : "You passed \(first.name) and \(passed.count - 1) more"
    }
}

/// The round's leaderboard: a short ranked list with your row in gold and the next player to beat called out.
private struct ResultsBoardCard: View {
    let board: ResultsBoard
    let settled: Bool

    var body: some View {
        let shown = board.rows(settled: settled)
        VStack(spacing: 4) {
            HStack {
                Text("LEADERBOARD").dlLabel(10.5)
                Spacer()
                Text(LiveBoard.unit(for: board.game).uppercased()).dlLabel(10.5)
            }
            .padding(.horizontal, 10)
            .padding(.top, 6)
            .padding(.bottom, 2)
            ForEach(Array(shown.rows.enumerated()), id: \.element.id) { index, row in
                rowView(row, place: shown.first + index)
            }
            if settled, let passed = board.passedText {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.right").font(.system(size: 12, weight: .black))
                    Text(passed).font(DL.text(14, .semibold))
                }
                .foregroundStyle(DL.goldText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: DL.cardRadius, style: .continuous).fill(DL.surface))
    }

    private func rowView(_ row: ResultsBoard.Row, place: Int) -> some View {
        let isTarget = settled && row.id == board.target?.id
        return HStack(spacing: 10) {
            Text("\(place)")
                .font(DL.display(26))
                .foregroundStyle(row.isYou ? DL.ink : DL.ink3)
                .contentTransition(.numericText(value: Double(place)))
                .frame(width: 30, alignment: .leading)
            DLAvatar(name: row.name, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(row.name).font(DL.text(15, .semibold)).foregroundStyle(DL.ink).lineLimit(1)
                    if row.isYou { DLTag(text: "You", filled: true) }
                }
                if isTarget, let text = board.targetText {
                    Text("Beat \(row.name): \(text)")
                        .font(DL.text(12, .bold))
                        .foregroundStyle(DL.onGold)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, 8)
                        .frame(height: 20)
                        .background(Capsule().fill(DL.gold))
                        .transition(.opacity)
                } else if row.isYou && settled && board.target == nil {
                    Text("Top of the board").font(DL.text(12, .semibold)).foregroundStyle(DL.goldText)
                }
            }
            Spacer(minLength: 8)
            Text(row.score < 0 ? "-" : LiveBoard.text(max(0, row.score), board.game))
                .font(DL.display(row.isYou ? 34 : 28))
                .foregroundStyle(DL.ink)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .contentTransition(.numericText(value: Double(row.score)))
        }
        .padding(.horizontal, 10)
        .frame(height: row.isYou || isTarget ? 58 : 48)
        .background {
            if row.isYou {
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(DL.goldWash)
            } else if isTarget {
                RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(DL.gold, lineWidth: 2)
            }
        }
        .zIndex(row.isYou ? 1 : 0)
        .accessibilityElement(children: .combine)
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
