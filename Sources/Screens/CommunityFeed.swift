import SwiftUI

// COMMUNITY's Friends feed: one calm column of what friends posted. Videos lead. Each row is a header
// line, the media, and a slim row of actions, with a hairline between rows. A video plays muted while
// it is on screen, and a tap opens every friend video full screen, one to a page, like Reels.

/// One row of the feed: a clip a player posted with the camera, or a friend's post.
enum CommunityEntry: Identifiable {
    case clip(ConvexClip)
    case post(CommunityPost)

    var id: String {
        switch self {
        case .clip(let clip): "clip-" + clip.id
        case .post(let post): "post-" + post.id
        }
    }

    var at: Date {
        switch self {
        case .clip(let clip): Date(timeIntervalSince1970: clip.at / 1000)
        case .post(let post): post.at
        }
    }

    var isVideo: Bool {
        switch self {
        case .clip: true
        case .post(let post): post.kind == .video
        }
    }

    var gameID: String {
        switch self {
        case .clip(let clip): clip.gameSlug
        case .post(let post): post.gameID
        }
    }

    /// Posted clips and friends' posts together, newest first.
    static func all(clips: [ConvexClip], posts: [CommunityPost]) -> [CommunityEntry] {
        (clips.map { CommunityEntry.clip($0) } + posts.map { CommunityEntry.post($0) }).sorted { $0.at > $1.at }
    }
}

struct CommunityFriendsFeed: View {
    @ObservedObject private var community = CommunityStore.shared
    @ObservedObject private var clips = CreateClips.shared

    var body: some View {
        let entries = CommunityEntry.all(clips: clips.feed, posts: community.posts)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                CommunityStoriesRow()
                    .padding(.top, 6)
                    .padding(.bottom, 10)
                if let challenge = community.challenges.first(where: { $0.expires > Date() }) {
                    CommunityHairline()
                    CommunityChallengeLine(challenge: challenge)
                }
                if entries.isEmpty {
                    CommunityHairline()
                    DLEmptyState(symbol: "person.2.fill", title: "Nothing here yet",
                                 detail: "Follow friends to see what they play and post.", key: "Invite") {
                        LiveNav.shared.share("Come and play with me on DEGEN")
                    }
                    .padding(DL.margin)
                }
                ForEach(entries) { entry in
                    CommunityHairline()
                    CommunityFeedRow(entry: entry)
                }
            }
            .padding(.bottom, 24)
            .animation(.snappy(duration: 0.3), value: entries.map(\.id))
        }
        .scrollIndicators(.hidden)
        .background(DL.body)
    }
}

/// A line the width of the screen between rows.
struct CommunityHairline: View {
    var body: some View { DL.line.frame(height: 1) }
}

// MARK: Stories

/// You, friends who are playing now with a LIVE chip, then today's scores.
struct CommunityStoriesRow: View {
    @ObservedObject private var community = CommunityStore.shared

    var body: some View {
        let stories = community.stories
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 6) {
                VStack(spacing: 5) {
                    DLAvatar(name: Mock.handle, size: 58)
                        .padding(4)
                        .overlay(Circle().strokeBorder(DL.line, lineWidth: 2.5))
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .black)).foregroundStyle(DL.onGold)
                                .frame(width: 22, height: 22)
                                .background(Circle().fill(DL.gold))
                                .overlay(Circle().strokeBorder(DL.body, lineWidth: 2))
                        }
                    Text("You").font(DL.text(12, .medium)).foregroundStyle(DL.ink2).padding(.top, 4)
                }
                .frame(width: 72)
                .opens(.create(nil))
                ForEach(community.live) { live in
                    let friend = live.friends.first ?? "Friend"
                    CommunityStoryBubble(name: friend, chip: "LIVE", seen: false, size: 58)
                        .opens(.gameReady(live.gameID))
                        .accessibilityLabel("\(friend) is playing \(live.game.title) now")
                }
                ForEach(Array(stories.enumerated()), id: \.element.id) { index, story in
                    CommunityStoryBubble(name: story.name, chip: story.score, seen: community.seenStories.contains(story.name), size: 58)
                        .opens(.story(index))
                        .accessibilityLabel("\(story.name), \(story.score) \(story.unit) in \(story.game.title)")
                }
            }
            .padding(.horizontal, DL.margin - 4)
        }
        .scrollIndicators(.hidden)
    }
}

/// A challenge, as one slim line: who, what to beat, the time left, and Accept.
struct CommunityChallengeLine: View {
    let challenge: CommunityChallenge

    var body: some View {
        HStack(spacing: 10) {
            DLThumb(game: challenge.game, size: 36, radius: 10)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(Text(challenge.from).fontWeight(.semibold)) challenged you")
                    .font(DL.text(14)).foregroundStyle(DL.ink).lineLimit(1)
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    Text("Beat \(challenge.target) \(challenge.unit)  \(CommunityChallengeCard.left(until: challenge.expires, now: timeline.date))")
                        .dlLabel(10, color: DL.ink2).lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            Text("Accept").font(DL.text(14, .semibold)).foregroundStyle(DL.onGold)
                .padding(.horizontal, 14).frame(height: 32)
                .background(Capsule().fill(DL.gold))
                .tap { LiveNav.shared.open(.gameReady(challenge.gameID)) }
        }
        .padding(.horizontal, DL.margin)
        .padding(.vertical, 10)
    }
}

// MARK: Rows

struct CommunityFeedRow: View {
    let entry: CommunityEntry
    @State private var onScreen = false
    @ObservedObject private var community = CommunityStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            media
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal, 10)
                .onScrollVisibilityChange(threshold: 0.55) { visible in onScreen = visible }
            if let caption, !caption.isEmpty {
                Text(caption).font(DL.text(15)).foregroundStyle(DL.ink)
                    .lineLimit(3)
                    .padding(.horizontal, DL.margin)
            }
            actions
        }
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    // MARK: Header

    private var name: String {
        switch entry {
        case .clip(let clip): clip.mine ? Mock.handle : clip.handle
        case .post(let post): post.name
        }
    }

    private var action: String {
        switch entry {
        case .clip(let clip): "posted a clip of \(clip.gameTitle)"
        case .post(let post): post.action
        }
    }

    private var caption: String? {
        switch entry {
        case .clip(let clip): clip.caption
        case .post(let post): post.caption
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            DLAvatar(name: name, size: 32)
            Text("\(Text(name == Mock.handle ? "You" : name).fontWeight(.semibold)) \(Text(action).foregroundStyle(DL.ink2))")
                .font(DL.text(14)).foregroundStyle(DL.ink)
                .lineLimit(1)
            Spacer(minLength: 6)
            Text(CommunityStore.ago(entry.at)).dlLabel(10, color: DL.ink3).fixedSize()
        }
        .padding(.horizontal, DL.margin)
    }

    // MARK: Media

    @ViewBuilder private var media: some View {
        if entry.isVideo {
            videoMedia
                .frame(height: 440)
                .frame(maxWidth: .infinity)
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "speaker.slash.fill")
                        .font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(.black.opacity(0.45)))
                        .padding(10)
                }
                .overlay(alignment: .bottomLeading) { videoTags.padding(10) }
                .contentShape(Rectangle())
                .onTapGesture { LiveNav.shared.open(.friendVideos(entry.id)) }
        } else if case .post(let post) = entry {
            scoreCover(post)
                .frame(height: 190)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { LiveNav.shared.open(.gameReady(post.gameID)) }
        }
    }

    @ViewBuilder private var videoMedia: some View {
        switch entry {
        case .clip(let clip):
            let game = Mock.game(clip.gameSlug)
            if let address = clip.url, let url = URL(string: address) {
                if clip.kind == "photo" {
                    AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: { Color.black }
                } else {
                    CreateLoopingVideo(url: url, active: onScreen, muted: true)
                }
            } else {
                CreateReplayStage(game: game, layout: CreateLayout(rawValue: clip.layout) ?? .cutout, moving: onScreen) {
                    CreateCameraPlaceholder()
                }
            }
        case .post(let post):
            CommunityCoverArt(game: post.game, moving: onScreen, focusY: 0.2)
        }
    }

    @ViewBuilder private var videoTags: some View {
        let score: String? = {
            switch entry {
            case .clip(let clip): return clip.scoreText
            case .post(let post): return post.score.isEmpty ? nil : "\(post.score) \(post.unit)"
            }
        }()
        HStack(spacing: 6) {
            DLMediaTag(text: Mock.game(entry.gameID).title, symbol: "play.fill")
            if let score { DLMediaTag(text: score) }
        }
    }

    /// A score post: the game's art with the number laid on it, not a block of its own.
    private func scoreCover(_ post: CommunityPost) -> some View {
        ZStack(alignment: .bottomLeading) {
            CommunityCoverArt(game: post.game, moving: false)
            LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                switch post.kind {
                case .rated:
                    CommunityScoreChip(score: post.rating ?? 0, size: 24)
                case .streak:
                    Text(post.score).font(DL.display(40)).foregroundStyle(.white)
                    Text("DAY STREAK").font(DL.display(18)).foregroundStyle(.white.opacity(0.9))
                case .game:
                    Text("NEW GAME").font(DL.display(26)).foregroundStyle(.white)
                default:
                    Text(post.score).font(DL.display(40)).foregroundStyle(.white)
                    Text(post.unit.uppercased()).font(DL.display(18)).foregroundStyle(.white.opacity(0.9))
                }
                Spacer(minLength: 0)
                if post.kind == .best { CommunityArtTag(text: "New best", symbol: "arrow.up", gold: true) }
                if post.kind == .passed { CommunityArtTag(text: "Passed you", symbol: "chevron.up.2", gold: true) }
            }
            .padding(12)
        }
    }

    // MARK: Actions

    private var actions: some View {
        HStack(spacing: 14) {
            switch entry {
            case .post(let post):
                ForEach(CommunityReaction.allCases, id: \.self) { reaction in
                    CommunitySlimReaction(reaction: reaction, count: post.reactions[reaction.rawValue] ?? 0,
                                          chosen: post.mine.contains(reaction.rawValue))
                        .tap { community.toggle(reaction, on: post.id) }
                }
                count("bubble.right", post.comments)
            case .clip(let clip):
                count("hand.thumbsup", Int(clip.likes))
                count("bubble.right", Int(clip.comments))
            }
            Image(systemName: "paperplane").font(.system(size: 15, weight: .semibold)).foregroundStyle(DL.ink2)
                .tap { LiveNav.shared.share("\(name) \(action) on DEGEN") }
                .accessibilityLabel("Send")
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                Image(systemName: "play.fill").font(.system(size: 10, weight: .black))
                Text("PLAY").font(DL.display(15)).tracking(0.5)
            }
            .foregroundStyle(DL.onGold)
            .padding(.horizontal, 12).frame(height: 30)
            .background(Capsule().fill(DL.gold))
            .background(Capsule().fill(DL.goldLip).offset(y: 2))
            .tap { LiveNav.shared.open(.gameReady(entry.gameID)) }
            .accessibilityLabel("Play \(Mock.game(entry.gameID).title)")
        }
        .padding(.horizontal, DL.margin)
        .frame(height: 36)
    }

    private func count(_ symbol: String, _ value: Int) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 14, weight: .semibold))
            if value > 0 { Text("\(value)").font(DL.label(11)).monospacedDigit() }
        }
        .foregroundStyle(DL.ink2)
    }
}

/// A reaction as a quiet icon and count, gold once it is yours. It pops when it lands.
struct CommunitySlimReaction: View {
    let reaction: CommunityReaction
    let count: Int
    let chosen: Bool
    @State private var pop = false

    var body: some View {
        HStack(spacing: 3) {
            Group {
                if let symbol = reaction.symbol {
                    Image(systemName: symbol).font(.system(size: 14, weight: .semibold))
                } else {
                    Text("GG").font(DL.display(15))
                }
            }
            if count > 0 {
                Text("\(count)").font(DL.label(11)).monospacedDigit()
                    .contentTransition(.numericText(value: Double(count)))
            }
        }
        .foregroundStyle(chosen ? DL.goldText : DL.ink2)
        .scaleEffect(pop ? 1.3 : 1)
        .animation(.snappy(duration: 0.2), value: count)
        .onChange(of: chosen) { _, now in
            guard now else { return }
            withAnimation(.spring(response: 0.18, dampingFraction: 0.4)) { pop = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) { pop = false }
            }
        }
        .accessibilityLabel("\(reaction.label), \(count)")
    }
}

// MARK: Full screen

/// Every friend video, full screen and one to a page, starting at the one tapped. Swipe up for the next.
struct CommunityVideoPlayer: View {
    let start: String
    @ObservedObject private var community = CommunityStore.shared
    @ObservedObject private var clips = CreateClips.shared
    @State private var position: Int?
    @State private var videos: [CommunityEntry] = []

    var body: some View {
        GeometryReader { proxy in
            let insets = proxy.safeAreaInsets
            let screen = CGSize(width: proxy.size.width + insets.leading + insets.trailing,
                                height: proxy.size.height + insets.top + insets.bottom)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(videos.enumerated()), id: \.offset) { index, entry in
                        page(entry, active: position == index)
                            .frame(width: screen.width, height: screen.height)
                            .id(index)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $position)
            .scrollIndicators(.hidden)
            .ignoresSafeArea()
        }
        .background(Color.black.ignoresSafeArea())
        .overlay(alignment: .topLeading) {
            DLMediaButton(symbol: "chevron.down", size: 40).goesBack().accessibilityLabel("Close")
                .padding(.horizontal, DL.margin).padding(.top, 6)
        }
        .onAppear {
            let list = CommunityEntry.all(clips: clips.feed, posts: community.posts).filter(\.isVideo)
            videos = list
            position = list.firstIndex { $0.id == start } ?? 0
        }
    }

    @ViewBuilder private func page(_ entry: CommunityEntry, active: Bool) -> some View {
        switch entry {
        case .clip(let clip):
            CreateClipPage(clip: clip, active: active)
        case .post(let post):
            let commentsID = Mock.clips.first { $0.game.id == post.gameID }?.id ?? Mock.clips[0].id
            LiveClipPage(clip: MockClip(id: commentsID, game: post.game, player: post.name, caption: post.caption,
                                        length: "", comments: groupedNumber(post.comments),
                                        shares: groupedNumber(post.reactions.values.reduce(0, +))),
                         active: active, saveable: false)
        }
    }
}
