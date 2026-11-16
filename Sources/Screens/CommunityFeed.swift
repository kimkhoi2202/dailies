import SwiftUI

// COMMUNITY's Friends feed, laid out like Instagram: who posted at the top, the post edge to edge, then
// like, comment, send and save, the likes, and the caption. Videos are tall, like Reels. A video plays muted while
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
            LazyVStack(alignment: .leading, spacing: 32) {
                VStack(alignment: .leading, spacing: 18) {
                    CommunityStoriesRow()
                    if let challenge = community.challenges.first(where: { $0.expires > Date() }) {
                        CommunityChallengeLine(challenge: challenge)
                            .padding(.horizontal, DL.margin)
                    }
                }
                if entries.isEmpty {
                    DLEmptyState(symbol: "person.2.fill", title: "Nothing here yet",
                                 detail: "Follow friends to see what they play and post.", key: "Invite") {
                        LiveNav.shared.share("Come and play with me on DEGEN")
                    }
                    .padding(.horizontal, DL.margin)
                }
                ForEach(entries) { entry in
                    CommunityFeedRow(entry: entry)
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 24)
            .animation(.snappy(duration: 0.3), value: entries.map(\.id))
        }
        .scrollIndicators(.hidden)
        .background(DL.body)
    }
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
            .padding(.horizontal, DL.margin - 3)
        }
        .scrollIndicators(.hidden)
    }
}

/// A challenge, as one quiet card: who, what to beat, the time left, and Accept.
struct CommunityChallengeLine: View {
    let challenge: CommunityChallenge

    var body: some View {
        HStack(spacing: 12) {
            DLThumb(game: challenge.game, size: 40, radius: DL.tileRadius)
            VStack(alignment: .leading, spacing: 2) {
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
        .dlCard(padding: 12)
    }
}

// MARK: Rows

struct CommunityFeedRow: View {
    let entry: CommunityEntry
    @State private var onScreen = false
    @State private var sending = false
    @State private var heart = false
    @ObservedObject private var memory = CommunityFeedMemory.shared
    @ObservedObject private var clips = CreateClips.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, 10)
            media
                .onScrollVisibilityChange(threshold: 0.55) { visible in onScreen = visible }
            actions
                .padding(.top, 8)
            details
                .padding(.top, 4)
        }
        .sheet(isPresented: $sending) {
            CommunitySendSheet(game: Mock.game(entry.gameID), message: shareText)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(DL.raised)
        }
    }

    // MARK: Words

    private var name: String {
        switch entry {
        case .clip(let clip): clip.mine ? Mock.handle : clip.handle
        case .post(let post): post.name
        }
    }

    private var caption: String {
        switch entry {
        case .clip(let clip): clip.caption.isEmpty ? "Played \(clip.gameTitle)" : clip.caption
        case .post(let post): post.caption.isEmpty ? post.action : post.caption
        }
    }

    private var comments: Int {
        switch entry {
        case .clip(let clip): Int(clip.comments)
        case .post(let post): post.comments
        }
    }

    private var likes: Int {
        let base: Int = switch entry {
        case .clip(let clip): Int(clip.likes)
        case .post(let post): post.reactions.values.reduce(0, +)
        }
        return base + (memory.liked.contains(entry.id) ? 1 : 0)
    }

    /// Saved clips live in Convex. A friend's post is saved as its game's clip, so it shows in the Library.
    private var saveKey: String {
        switch entry {
        case .clip(let clip): clip.saveKey
        case .post(let post): "sample:" + (Mock.clips.first { $0.game.id == post.gameID }?.id ?? Mock.clips[0].id)
        }
    }

    private var shareText: String {
        let game = Mock.game(entry.gameID)
        var text = "\(name) posted \(game.title) on DEGEN"
        if case .clip(let clip) = entry, let url = clip.url { text += "\n" + url }
        return text
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            DLAvatar(name: name, size: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(Text(name).fontWeight(.semibold)) posted")
                    .font(DL.text(14)).foregroundStyle(DL.ink)
                    .lineLimit(1)
                Text(Mock.game(entry.gameID).title)
                    .font(DL.text(12)).foregroundStyle(DL.ink2)
                    .lineLimit(1)
                    .tap { LiveNav.shared.open(.gameReady(entry.gameID)) }
            }
            Spacer(minLength: 6)
            Text("Play")
                .font(DL.text(14, .semibold)).foregroundStyle(DL.goldText)
                .padding(.horizontal, 6).frame(height: 32)
                .tap { LiveNav.shared.open(.gameReady(entry.gameID)) }
                .accessibilityLabel("Play \(Mock.game(entry.gameID).title)")
        }
        .padding(.horizontal, DL.margin)
    }

    // MARK: Media

    @ViewBuilder private var media: some View {
        Group {
            if entry.isVideo {
                Color.black
                    .aspectRatio(9 / 16, contentMode: .fit)
                    .overlay { videoMedia }
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "speaker.slash.fill")
                            .font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(.black.opacity(0.45)))
                            .padding(12)
                    }
                    .overlay(alignment: .topTrailing) {
                        Image(systemName: "play.rectangle.on.rectangle.fill")
                            .font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.4), radius: 4)
                            .padding(12)
                    }
            } else if case .post(let post) = entry {
                Color.black
                    .aspectRatio(1, contentMode: .fit)
                    .overlay { scoreCover(post) }
            }
        }
        .frame(maxWidth: .infinity)
        .clipped()
        .overlay {
            Image(systemName: "heart.fill")
                .font(.system(size: 96)).foregroundStyle(.white)
                .shadow(color: .black.opacity(0.3), radius: 12)
                .scaleEffect(heart ? 1 : 0.4)
                .opacity(heart ? 1 : 0)
                .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { like(only: true) }
        .onTapGesture { open() }
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
                        .createFilter(clip.style.filter)
                        .overlay {
                            CreateClipDecor(text: clip.overlay ?? "", look: clip.style, sticker: clip.scoreText ?? clip.gameTitle)
                        }
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

    /// A score post: the game's art with the number laid on it.
    private func scoreCover(_ post: CommunityPost) -> some View {
        ZStack(alignment: .bottomLeading) {
            CommunityCoverArt(game: post.game, moving: false)
            LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                switch post.kind {
                case .rated:
                    CommunityScoreChip(score: post.rating ?? 0, size: 24)
                case .streak:
                    Text(post.score).font(DL.display(48)).foregroundStyle(.white)
                    Text("DAY STREAK").font(DL.display(20)).foregroundStyle(.white.opacity(0.9))
                case .game:
                    Text("NEW GAME").font(DL.display(30)).foregroundStyle(.white)
                default:
                    Text(post.score).font(DL.display(48)).foregroundStyle(.white)
                    Text(post.unit.uppercased()).font(DL.display(20)).foregroundStyle(.white.opacity(0.9))
                }
                Spacer(minLength: 0)
            }
            .padding(16)
        }
    }

    // MARK: Actions

    private var actions: some View {
        let liked = memory.liked.contains(entry.id)
        let saved = clips.isSaved(saveKey)
        return HStack(spacing: 18) {
            Image(systemName: liked ? "heart.fill" : "heart")
                .foregroundStyle(liked ? DL.danger : DL.ink)
                .contentTransition(.symbolEffect(.replace))
                .tap { like(only: false) }
                .accessibilityLabel(liked ? "Unlike" : "Like")
            Image(systemName: "bubble.right")
                .tap { openComments() }
                .accessibilityLabel("Comments")
            Image(systemName: "paperplane")
                .tap { sending = true }
                .accessibilityLabel("Send")
            Spacer(minLength: 0)
            Image(systemName: saved ? "bookmark.fill" : "bookmark")
                .contentTransition(.symbolEffect(.replace))
                .tap { clips.toggleSave(saveKey) }
                .accessibilityLabel(saved ? "Saved" : "Save")
        }
        .font(.system(size: 23, weight: .regular))
        .foregroundStyle(DL.ink)
        .padding(.horizontal, DL.margin)
        .frame(height: 40)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 5) {
            if likes > 0 {
                Text(likes == 1 ? "1 like" : "\(groupedNumber(likes)) likes")
                    .font(DL.text(14, .semibold)).foregroundStyle(DL.ink)
                    .contentTransition(.numericText(value: Double(likes)))
            }
            Text("\(Text(name).fontWeight(.semibold)) \(caption)")
                .font(DL.text(14)).foregroundStyle(DL.ink)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            if comments > 0 {
                Text(comments == 1 ? "View 1 comment" : "View all \(comments) comments")
                    .font(DL.text(14)).foregroundStyle(DL.ink3)
                    .tap { openComments() }
            }
            Text(CommunityStore.ago(entry.at).lowercased())
                .font(DL.text(11)).foregroundStyle(DL.ink3)
                .padding(.top, 1)
        }
        .padding(.horizontal, DL.margin)
        .animation(.snappy(duration: 0.2), value: likes)
    }

    // MARK: Doing

    private func like(only: Bool) {
        guard LiveNav.shared.hasAccount(to: "like posts") else { return }
        let liked = memory.liked.contains(entry.id)
        if only {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.55)) { heart = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                withAnimation(.easeOut(duration: 0.25)) { heart = false }
            }
            if liked { return }
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        memory.toggleLike(entry.id)
    }

    private func open() {
        if entry.isVideo {
            LiveNav.shared.open(.friendVideos(entry.id))
        } else {
            LiveNav.shared.open(.gameReady(entry.gameID))
        }
    }

    private func openComments() {
        switch entry {
        case .clip:
            LiveNav.shared.open(.friendVideos(entry.id))
        case .post(let post):
            LiveNav.shared.open(.comments(Mock.clips.first { $0.game.id == post.gameID }?.id ?? Mock.clips[0].id))
        }
    }
}

/// What this phone liked in the feed, kept between launches.
final class CommunityFeedMemory: ObservableObject {
    static let shared = CommunityFeedMemory()
    private static let key = "degen.feed.liked"

    @Published private(set) var liked: Set<String>

    private init() {
        liked = Set(UserDefaults.standard.stringArray(forKey: Self.key) ?? [])
    }

    func toggleLike(_ id: String) {
        if liked.contains(id) { liked.remove(id) } else { liked.insert(id) }
        UserDefaults.standard.set(Array(liked), forKey: Self.key)
    }
}

/// Send a post to someone: iMessage, the system share sheet, or straight into a DEGEN chat.
struct CommunitySendSheet: View {
    let game: MockGame
    let message: String
    @ObservedObject private var social = MessagesStore.shared
    @State private var sent: Set<String> = []
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Send")
                .font(DL.text(17, .semibold)).foregroundStyle(DL.ink)
                .frame(maxWidth: .infinity)
                .padding(.top, 22)
            HStack(spacing: 22) {
                target("message.fill", "iMessage", fill: DL.success) { openMessages() }
                target("square.and.arrow.up", "More", fill: DL.sunken) {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { LiveNav.shared.share(message) }
                }
                target("link", "Copy", fill: DL.sunken) {
                    UIPasteboard.general.string = message
                    LiveNav.shared.say("Copied")
                }
            }
            .padding(.horizontal, 20)
            Text("Your chats").dlLabel(11, color: DL.ink2).padding(.horizontal, 20)
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(social.chats) { chat in row(chat) }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func target(_ symbol: String, _ title: String, fill: Color, action: @escaping () -> Void) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(fill == DL.sunken ? DL.ink : .white)
                .frame(width: 58, height: 58)
                .background(Circle().fill(fill))
            Text(title).font(DL.text(12)).foregroundStyle(DL.ink2)
        }
        .tap(action)
    }

    private func row(_ chat: ChatThread) -> some View {
        let done = sent.contains(chat.id)
        return HStack(spacing: 12) {
            if let person = chat.person {
                DLAvatar(name: person.name, size: 44)
            } else {
                Image(systemName: chat.icon)
                    .font(.system(size: 17, weight: .semibold)).foregroundStyle(DL.ink)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(DL.sunken))
            }
            Text(chat.name).font(DL.text(15, .semibold)).foregroundStyle(DL.ink).lineLimit(1)
            Spacer(minLength: 6)
            Text(done ? "Sent" : "Send")
                .font(DL.text(14, .semibold))
                .foregroundStyle(done ? DL.ink2 : DL.onGold)
                .padding(.horizontal, 16).frame(height: 32)
                .background(Capsule().fill(done ? DL.sunken : DL.gold))
                .tap {
                    guard !done else { return }
                    social.share(kind: .post, game: game, body: message, to: chat.id)
                    sent.insert(chat.id)
                }
        }
        .padding(.vertical, 6)
    }

    private func openMessages() {
        let body = message.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard let url = URL(string: "sms:&body=" + body) else { return }
        UIApplication.shared.open(url)
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
