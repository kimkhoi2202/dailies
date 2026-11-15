import SwiftUI

// COMMUNITY's parts: the top bar and floating tab bar every tab shares, and the cards of the Friends feed.

// MARK: Top bar

/// The top of every tab: the logo or a title, then gold, the bell and your avatar.
struct CommunityTopBar: View {
    var title: String? = nil
    var onMedia: Bool = false
    @ObservedObject private var community = CommunityStore.shared

    var body: some View {
        HStack(spacing: 8) {
            if let title {
                Text(title.uppercased()).font(DL.display(34)).foregroundStyle(onMedia ? Color.white : DL.ink)
                    .lineLimit(1).minimumScaleFactor(0.7)
            } else if !onMedia {
                DLLogo(height: 32)
            }
            Spacer(minLength: 4)
            DLGoldChip(onMedia: onMedia).opens(.gold)
            bell.opens(.notifications).accessibilityLabel("Notifications")
            DLAvatar(name: Mock.handle, size: 40)
                .overlay(Circle().strokeBorder(onMedia ? Color.white.opacity(0.5) : DL.line, lineWidth: 1.5))
                .opens(.profile("me"))
                .accessibilityLabel("Your profile")
        }
    }

    @ViewBuilder private var bell: some View {
        Group {
            if onMedia { DLMediaButton(symbol: "bell.fill", size: 40) } else { DLIconButton(symbol: "bell.fill") }
        }
        .overlay(alignment: .topTrailing) {
            if community.unreadCount > 0 {
                Circle().fill(DL.gold)
                    .frame(width: 11, height: 11)
                    .overlay(Circle().strokeBorder(onMedia ? Color.black.opacity(0.4) : DL.body, lineWidth: 2))
                    .offset(x: 1, y: -1)
                    .transition(.scale)
            }
        }
    }
}

// MARK: Small parts

/// A rating, in a gold chip shaped like the coin pill: "8.7".
struct CommunityScoreChip: View {
    let score: Double
    var size: CGFloat = 18

    var body: some View {
        Text(CommunityStore.ratingText(score))
            .font(DL.display(size)).monospacedDigit()
            .foregroundStyle(DL.onGold)
            .padding(.horizontal, size * 0.55)
            .frame(height: size * 1.55)
            .background(Capsule().fill(DL.gold))
            .background(Capsule().fill(DL.goldLip).offset(y: 2))
    }
}

/// A friend's avatar in a ring: gold while there is something new to see, a quiet line once seen.
struct CommunityStoryBubble: View {
    let name: String
    var chip: String? = nil
    var seen: Bool = false
    var size: CGFloat = 62

    var body: some View {
        VStack(spacing: 5) {
            DLAvatar(name: name, size: size)
                .padding(4)
                .overlay(Circle().strokeBorder(seen ? DL.line : DL.gold, lineWidth: 3))
                .overlay(alignment: .bottom) {
                    if let chip {
                        Text(chip)
                            .font(DL.label(10)).monospacedDigit()
                            .foregroundStyle(seen ? DL.ink : DL.onGold)
                            .lineLimit(1)
                            .padding(.horizontal, 6)
                            .frame(height: 18)
                            .background(Capsule().fill(seen ? DL.raised : DL.gold))
                            .overlay(Capsule().strokeBorder(DL.body, lineWidth: 2))
                            .offset(y: 7)
                    }
                }
            Text(name).font(DL.text(12, .medium)).foregroundStyle(DL.ink2).lineLimit(1)
                .padding(.top, 4)
        }
        .frame(width: size + 14)
    }
}

/// The small gold Play key on a card.
struct CommunityPlayKey: View {
    var title: String = "Play"
    var width: CGFloat = 92

    var body: some View {
        DLKey(style: .gold, radius: 16, depth: 4) {
            HStack(spacing: 6) {
                Image(systemName: "play.fill").font(.system(size: 12, weight: .black))
                Text(title.uppercased()).font(DL.display(18)).tracking(0.6)
            }
        }
        .frame(width: width, height: 42)
    }
}

/// "FRIENDS 8.6": what friends rate a game, as a tag beside its other tags.
struct CommunityFriendsTag: View {
    let gameID: String
    @ObservedObject private var community = CommunityStore.shared

    var body: some View {
        if let score = community.friendScores[gameID] {
            DLTag(text: "Friends \(CommunityStore.ratingText(score))", symbol: "star.fill")
        }
    }
}

// MARK: Reactions

/// GG, fire, crown and clap, each with its count. A reaction pops like a combo when it lands.
struct CommunityReactionBar: View {
    let post: CommunityPost

    var body: some View {
        HStack(spacing: 6) {
            ForEach(CommunityReaction.allCases, id: \.self) { reaction in
                CommunityReactionPill(reaction: reaction, count: post.reactions[reaction.rawValue] ?? 0,
                                      chosen: post.mine.contains(reaction.rawValue))
                    .tap { CommunityStore.shared.toggle(reaction, on: post.id) }
            }
        }
    }
}

struct CommunityReactionPill: View {
    let reaction: CommunityReaction
    let count: Int
    let chosen: Bool
    @State private var pop = false
    @State private var rise = false

    var body: some View {
        HStack(spacing: 4) {
            icon
            if count > 0 {
                Text("\(count)").font(DL.label(11)).monospacedDigit()
                    .contentTransition(.numericText(value: Double(count)))
            }
        }
        .foregroundStyle(chosen ? DL.onGold : DL.ink)
        .padding(.horizontal, 9)
        .frame(height: 32)
        .background(Capsule().fill(chosen ? DL.gold : DL.raised))
        .scaleEffect(pop ? 1.22 : 1)
        .overlay(alignment: .top) {
            Text("+1").font(DL.display(16)).foregroundStyle(DL.goldText)
                .offset(y: rise ? -30 : -4)
                .opacity(rise ? 0 : (pop ? 1 : 0))
                .allowsHitTesting(false)
        }
        .animation(.snappy(duration: 0.2), value: count)
        .onChange(of: chosen) { _, now in
            guard now else { return }
            withAnimation(.spring(response: 0.18, dampingFraction: 0.4)) { pop = true }
            withAnimation(.easeOut(duration: 0.6)) { rise = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) { pop = false }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.62) { rise = false }
        }
        .accessibilityLabel("\(reaction.label), \(count)")
    }

    @ViewBuilder private var icon: some View {
        if let symbol = reaction.symbol {
            Image(systemName: symbol).font(.system(size: 13, weight: .bold))
        } else {
            Text("GG").font(DL.display(16))
        }
    }
}

// MARK: Activity

/// One friend's post, built around the game's art with the score as the hero.
struct CommunityActivityCard: View {
    let post: CommunityPost
    @ObservedObject private var community = CommunityStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            cover
            HStack(spacing: 8) {
                CommunityReactionBar(post: post)
                Spacer(minLength: 0)
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(DL.ink2)
                    .frame(width: 32, height: 32)
                    .tap { LiveNav.shared.share("\(post.name) \(post.action) on DEGEN") }
                    .accessibilityLabel("Send")
            }
            HStack(spacing: 10) {
                if post.comments > 0 {
                    HStack(spacing: 5) {
                        Image(systemName: "bubble.fill").font(.system(size: 11))
                        Text(post.comments == 1 ? "1 COMMENT" : "\(post.comments) COMMENTS").font(DL.label(10.5))
                    }
                    .foregroundStyle(DL.ink2)
                }
                if let friends = community.friendScores[post.gameID] {
                    Text("FRIENDS RATE IT \(CommunityStore.ratingText(friends))").dlLabel(10.5)
                }
                Spacer(minLength: 0)
                CommunityPlayKey()
                    .tap { LiveNav.shared.open(.gameReady(post.gameID)) }
                    .accessibilityLabel("Play \(post.game.title)")
            }
        }
        .dlCard(padding: 14)
    }

    private var header: some View {
        HStack(spacing: 10) {
            DLAvatar(name: post.name, size: 38)
            Text("\(Text(post.name == Mock.handle ? "You" : post.name).fontWeight(.semibold)) \(post.action)")
                .font(DL.text(15)).foregroundStyle(DL.ink)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Text(CommunityStore.ago(post.at)).dlLabel(10, color: DL.ink3).fixedSize()
        }
    }

    private var cover: some View {
        ZStack(alignment: .bottomLeading) {
            CommunityCoverArt(game: post.game, moving: post.kind == .video)
            LinearGradient(colors: [.clear, .black.opacity(0.35), .black.opacity(0.85)], startPoint: .center, endPoint: .bottom)
            heroText.padding(16)
        }
        .frame(height: 236)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(alignment: .topLeading) { badge.padding(12) }
        .contentShape(Rectangle())
        .onTapGesture { LiveNav.shared.open(.gameReady(post.gameID)) }
    }

    @ViewBuilder private var heroText: some View {
        switch post.kind {
        case .rated:
            VStack(alignment: .leading, spacing: 4) {
                Text(post.game.title.uppercased()).font(DL.display(28)).foregroundStyle(.white)
                CommunityScoreChip(score: post.rating ?? 0, size: 34)
            }
        case .streak:
            VStack(alignment: .leading, spacing: -6) {
                Text(post.score).font(DL.display(84)).foregroundStyle(.white)
                Text("DAY STREAK").font(DL.display(26)).foregroundStyle(.white)
            }
        case .game:
            VStack(alignment: .leading, spacing: 0) {
                Text("NEW GAME").font(DL.label(11)).foregroundStyle(.white.opacity(0.8))
                Text(post.game.title.uppercased()).font(DL.display(52)).foregroundStyle(.white)
            }
        default:
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text(post.score).font(DL.display(72)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.5)
                Text(post.unit.uppercased()).font(DL.display(24)).foregroundStyle(.white.opacity(0.9)).lineLimit(1)
            }
        }
    }

    @ViewBuilder private var badge: some View {
        switch post.kind {
        case .best:
            CommunityArtTag(text: "New best", symbol: "arrow.up", gold: true)
        case .passed:
            CommunityArtTag(text: "Passed you", symbol: "chevron.up.2", gold: true)
        case .video:
            CommunityArtTag(text: "Clip", symbol: "play.fill", gold: false)
        case .streak:
            CommunityArtTag(text: "Streak", symbol: "flame.fill", gold: true)
        default:
            EmptyView()
        }
    }
}

/// A small tag on art: gold for news, glass for anything else.
struct CommunityArtTag: View {
    let text: String
    var symbol: String? = nil
    var gold: Bool = false

    var body: some View {
        HStack(spacing: 5) {
            if let symbol { Image(systemName: symbol).font(.system(size: 10, weight: .black)) }
            Text(text.uppercased()).font(DL.label(10.5))
        }
        .foregroundStyle(gold ? DL.onGold : Color.white)
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background(Capsule().fill(gold ? DL.gold : Color.black.opacity(0.45)))
    }
}

/// A game's art. A clip loops its gameplay; anything else holds the best still.
struct CommunityCoverArt: View {
    let game: MockGame
    var moving: Bool = false
    var focusY: CGFloat = 0.3
    @State private var start = Date()

    var body: some View {
        if moving {
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
                let loops = timeline.date.timeIntervalSince(start) / 7
                ClipStill(game: game, phase: loops - loops.rounded(.towardZero), showHUD: false, focusY: focusY)
            }
        } else {
            ClipStill(game: game, showHUD: false, focusY: focusY)
        }
    }
}

// MARK: Streak

/// The daily streak: how many days running, the last seven days as dots, and today's play time.
struct CommunityStreakCard: View {
    @ObservedObject private var live = LiveStore.shared

    var body: some View {
        let streak = live.s.streak
        let playedToday = live.s.lastPlayDay == live.s.day
        let seconds = live.s.secondsToday.values.reduce(0, +)
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill").font(.system(size: 20, weight: .bold)).foregroundStyle(DL.goldText)
                    Text(streak > 0 ? "\(streak) day streak".uppercased() : "Start a streak".uppercased())
                        .font(DL.display(30)).foregroundStyle(DL.ink)
                }
                dots(streak: streak, playedToday: playedToday)
                Text(playedToday ? "Play tomorrow to make it \(streak + 1)." : "One round today keeps it going.")
                    .font(DL.text(13)).foregroundStyle(DL.ink2)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                Text("Today").dlLabel(10)
                Text(LiveStore.playedText(seconds)).font(DL.display(30)).foregroundStyle(DL.ink).monospacedDigit()
                Text("played").dlLabel(10)
            }
        }
        .dlCard(padding: 16)
        .opens(.streak)
    }

    private func dots(streak: Int, playedToday: Bool) -> some View {
        let calendar = Calendar.current
        // The last seven days, today on the right. A streak reaches back from today, or from yesterday until today is played.
        let lit = Set((0..<min(streak, 7)).map { $0 + (playedToday ? 0 : 1) })
        return HStack(spacing: 7) {
            ForEach((0..<7).reversed(), id: \.self) { back in
                let day = calendar.date(byAdding: .day, value: -back, to: Date()) ?? Date()
                let initial = Mock.weekInitials[(calendar.component(.weekday, from: day) - 1) % 7]
                VStack(spacing: 3) {
                    Circle().fill(lit.contains(back) ? DL.gold : DL.sunken)
                        .frame(width: 18, height: 18)
                        .overlay(Circle().strokeBorder(back == 0 ? DL.ink : Color.clear, lineWidth: 1.5))
                    Text(initial).font(DL.label(9)).foregroundStyle(DL.ink3)
                }
            }
        }
    }
}

// MARK: Live now

/// A game friends are in right now, like Home's big card: the art, who is in, and Join now.
struct CommunityLiveCard: View {
    let live: CommunityLive

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            ClipStill(game: live.game, showHUD: false, focusY: 0.42)
            LinearGradient(colors: [.black.opacity(0.3), .clear, .black.opacity(0.8)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    HStack(spacing: -8) {
                        ForEach(Array(live.friends.prefix(3)), id: \.self) { friend in
                            DLAvatar(name: friend, size: 26).overlay(Circle().strokeBorder(.black.opacity(0.5), lineWidth: 1.5))
                        }
                    }
                    HStack(spacing: 5) {
                        Circle().fill(DL.gold).frame(width: 7, height: 7)
                        Text("LIVE").font(DL.label(10.5)).foregroundStyle(.white)
                    }
                    .padding(.horizontal, 8).frame(height: 22)
                    .background(Capsule().fill(.black.opacity(0.45)))
                }
                Spacer()
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(live.game.title) is live".uppercased()).font(DL.display(28)).foregroundStyle(.white)
                            .lineLimit(1).minimumScaleFactor(0.7)
                        Text(live.friends.count == 1 ? "1 friend playing" : "\(live.friends.count) friends playing")
                            .font(DL.text(13, .semibold)).foregroundStyle(.white.opacity(0.9))
                    }
                    Spacer(minLength: 6)
                    CommunityPlayKey(title: "Join", width: 86)
                        .tap { LiveNav.shared.open(.gameReady(live.gameID)) }
                }
            }
            .padding(14)
        }
        .frame(width: 300, height: 176)
        .clipShape(RoundedRectangle(cornerRadius: DL.cardRadius, style: .continuous))
    }
}

// MARK: Challenge

/// A friend's challenge: who, what to beat, the time left, and Accept.
struct CommunityChallengeCard: View {
    let challenge: CommunityChallenge

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                DLAvatar(name: challenge.from, size: 34)
                Text("\(Text(challenge.from).fontWeight(.semibold)) challenged you")
                    .font(DL.text(15)).foregroundStyle(DL.ink)
                Spacer(minLength: 4)
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    Text(Self.left(until: challenge.expires, now: timeline.date)).dlLabel(10.5, color: DL.goldText)
                        .monospacedDigit()
                }
            }
            HStack(spacing: 12) {
                DLThumb(game: challenge.game, size: 60)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Beat \(challenge.target) \(challenge.unit)".uppercased())
                        .font(DL.display(26)).foregroundStyle(DL.ink).lineLimit(1).minimumScaleFactor(0.6)
                    Text("in \(challenge.game.title)").font(DL.text(14)).foregroundStyle(DL.ink2)
                }
                Spacer(minLength: 4)
            }
            DLTextKey(title: "Accept", symbol: "flag.checkered")
                .tap { LiveNav.shared.open(.gameReady(challenge.gameID)) }
        }
        .dlCard(padding: 16)
    }

    /// "5:42:10 LEFT"
    static func left(until end: Date, now: Date) -> String {
        let total = max(0, Int(end.timeIntervalSince(now)))
        return String(format: "%d:%02d:%02d LEFT", total / 3600, total % 3600 / 60, total % 60)
    }
}

// MARK: Ranked

/// What friends rank highest, Beli style: three games with their score out of ten.
struct CommunityRankCard: View {
    @ObservedObject private var community = CommunityStore.shared

    var body: some View {
        let top = Mock.games.sorted { (community.friendScores[$0.id] ?? 0) > (community.friendScores[$1.id] ?? 0) }.prefix(3)
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("YOUR FRIENDS RANK").font(DL.display(24)).foregroundStyle(DL.ink)
                Spacer()
                Text("Out of 10").dlLabel(10)
            }
            .padding(.bottom, 4)
            ForEach(Array(top.enumerated()), id: \.element.id) { place, game in
                if place > 0 { DLDivider(inset: 70) }
                HStack(spacing: 12) {
                    Text("\(place + 1)").font(DL.display(28)).foregroundStyle(DL.ink3).frame(width: 16, alignment: .leading)
                    DLThumb(game: game, size: 42)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(game.title).font(DL.text(16, .semibold)).foregroundStyle(DL.ink)
                        if let mine = community.myScores[game.id] {
                            Text("You rate it \(CommunityStore.ratingText(mine))").font(DL.text(13)).foregroundStyle(DL.ink2)
                        } else {
                            Text("\(game.players), \(game.mode.lowercased())").font(DL.text(13)).foregroundStyle(DL.ink2)
                        }
                    }
                    Spacer(minLength: 6)
                    CommunityScoreChip(score: community.friendScores[game.id] ?? 0, size: 20)
                }
                .frame(height: 56)
                .contentShape(Rectangle())
                .opens(.gameReady(game.id))
            }
        }
        .dlCard(padding: 16)
    }
}
