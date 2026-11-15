import SwiftUI

// A friend's story is today's score, drawn like a round-end screen with a Beat it key.
// Tap the right side for the next friend, the left for the one before. Each runs five seconds.

struct CommunityStoryScreen: View {
    let start: Int
    @ObservedObject private var community = CommunityStore.shared
    @State private var index: Int
    @State private var list: [CommunityStory] = []
    @State private var shownAt = Date()
    @State private var appeared = false

    private static let seconds = 5.0

    init(start: Int) {
        self.start = start
        _index = State(initialValue: start)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let story = current {
                page(story)
            }
        }
        .task(id: index) {
            try? await Task.sleep(for: .seconds(Self.seconds))
            if !Task.isCancelled { move(1) }
        }
        .scaleEffect(appeared ? 1 : 0.92)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            list = community.stories
            index = min(start, max(0, list.count - 1))
            shownAt = Date()
            if let story = current { community.markSeen(story.name) }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { appeared = true }
        }
        .environment(\.colorScheme, .dark)
    }

    private var current: CommunityStory? { list.indices.contains(index) ? list[index] : nil }

    private func page(_ story: CommunityStory) -> some View {
        ZStack {
            ClipStill(game: story.game, phase: 0.95, showHUD: false, focusY: 0.3)
                .ignoresSafeArea()
            Color.black.opacity(0.5).ignoresSafeArea()
            HStack(spacing: 0) {
                Color.clear.contentShape(Rectangle()).onTapGesture { move(-1) }
                Color.clear.contentShape(Rectangle()).onTapGesture { move(1) }
            }
            .ignoresSafeArea()
            VStack(spacing: 0) {
                top(story)
                Spacer()
                VStack(spacing: 2) {
                    Text("TODAY'S SCORE IN \(story.game.title.uppercased())").font(DL.label(11)).foregroundStyle(.white.opacity(0.8))
                    Text(story.score)
                        .font(DL.display(150)).foregroundStyle(.white)
                        .lineLimit(1).minimumScaleFactor(0.4)
                        .padding(.horizontal, 20)
                    Text(story.unit.uppercased()).font(DL.display(30)).tracking(2).foregroundStyle(.white)
                        .padding(.top, -26)
                }
                .allowsHitTesting(false)
                Spacer()
                VStack(spacing: 10) {
                    if let mine = LiveStore.shared.s.bestText[story.gameID] {
                        Text("Your best is \(mine) \(LiveStore.shared.s.bestUnit[story.gameID] ?? "")")
                            .font(DL.text(14, .semibold)).foregroundStyle(.white.opacity(0.85))
                    }
                    DLTextKey(title: "Beat it", symbol: "play.fill")
                        .tap { LiveNav.shared.replaceTop(.gameReady(story.gameID)) }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
        }
    }

    private func top(_ story: CommunityStory) -> some View {
        VStack(spacing: 12) {
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
                let elapsed = timeline.date.timeIntervalSince(shownAt)
                bars(progress: min(1, max(0, elapsed / Self.seconds)))
            }
            HStack(spacing: 10) {
                DLAvatar(name: story.name, size: 38).overlay(Circle().strokeBorder(DL.gold, lineWidth: 2))
                VStack(alignment: .leading, spacing: 1) {
                    Text(story.name).font(DL.text(15, .semibold)).foregroundStyle(.white)
                    Text(CommunityStore.ago(story.at)).font(DL.label(10)).foregroundStyle(.white.opacity(0.75))
                }
                Spacer()
                DLMediaButton(symbol: "xmark", size: 40).goesBack().accessibilityLabel("Close")
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
    }

    private func bars(progress: Double) -> some View {
        HStack(spacing: 4) {
            ForEach(list.indices, id: \.self) { i in
                Capsule().fill(.white.opacity(0.3))
                    .overlay(alignment: .leading) {
                        GeometryReader { proxy in
                            let fill: Double = i < index ? 1 : (i == index ? progress : 0)
                            Capsule().fill(DL.gold).frame(width: proxy.size.width * fill)
                        }
                    }
                    .frame(height: 3)
            }
        }
    }

    private func move(_ step: Int) {
        let next = index + step
        guard list.indices.contains(next) else {
            if step > 0 { LiveNav.shared.back() } else { shownAt = Date() }
            return
        }
        index = next
        shownAt = Date()
        community.markSeen(list[next].name)
    }
}

// MARK: Rating

/// After a round: how was it, then one or two quick comparisons, then a score out of ten.
struct CommunityRatingSheet: View {
    let gameID: String
    @ObservedObject private var community = CommunityStore.shared
    @State private var band: CommunityBand?
    /// The binary search through the band's list: the place is somewhere in low..<high.
    @State private var low = 0
    @State private var high = 0
    @State private var asked = 0
    @State private var score: Double?

    private var game: MockGame { Mock.game(gameID) }
    private static let maxComparisons = 2

    var body: some View {
        DLSheet(height: 520) {
            EmptyView()
        } content: {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(stepLabel).dlLabel(10.5)
                    Spacer()
                    if score == nil {
                        Text("Skip").font(DL.text(15, .semibold)).foregroundStyle(DL.ink2)
                            .padding(.horizontal, 8).frame(height: 32)
                            .tap {
                                community.skipRating(gameID)
                                LiveNav.shared.back()
                            }
                    }
                }
                Group {
                    if let score {
                        done(score)
                    } else if let band, let rival = rival(band) {
                        compare(rival)
                    } else {
                        choose
                    }
                }
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
            .animation(.snappy(duration: 0.3), value: stepKey)
        }
    }

    private var stepKey: String { "\(band?.rawValue ?? "")-\(low)-\(high)-\(score ?? -1)" }

    private var stepLabel: String {
        if score != nil { return "Rated" }
        if let band { return band.title }
        return "Rate this game"
    }

    // Step 1
    private var choose: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                DLThumb(game: game, size: 56)
                Text("How was \(game.title)?".uppercased())
                    .font(DL.display(34)).foregroundStyle(DL.ink)
                    .lineLimit(2).minimumScaleFactor(0.7)
            }
            VStack(spacing: 10) {
                ForEach(CommunityBand.allCases, id: \.self) { option in
                    HStack(spacing: 12) {
                        Image(systemName: option.symbol).font(.system(size: 18, weight: .bold))
                            .foregroundStyle(option == .loved ? DL.onGold : DL.ink)
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(option == .loved ? DL.gold : DL.sunken))
                        Text(option.title).font(DL.text(17, .semibold)).foregroundStyle(DL.ink)
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(DL.ink3)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 64)
                    .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(DL.surface))
                    .tap { pick(option) }
                }
            }
        }
    }

    // Step 2
    private func compare(_ rival: String) -> some View {
        let other = Mock.game(rival)
        return VStack(alignment: .leading, spacing: 14) {
            Text("WHICH DID YOU LIKE MORE?").font(DL.display(32)).foregroundStyle(DL.ink)
            HStack(spacing: 12) {
                side(game, subtitle: "Just played").tap { answer(newIsBetter: true) }
                Text("OR").font(DL.display(20)).foregroundStyle(DL.ink3)
                side(other, subtitle: community.myScores[rival].map { "You rated it \(CommunityStore.ratingText($0))" } ?? "Rated before")
                    .tap { answer(newIsBetter: false) }
            }
            Text("Too close to call").font(DL.text(15, .semibold)).foregroundStyle(DL.ink2)
                .frame(maxWidth: .infinity).frame(height: 40)
                .tap { finish(at: (low + high) / 2) }
        }
    }

    private func side(_ game: MockGame, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ClipStill(game: game, showHUD: false, focusY: 0.3)
                .frame(height: 170)
                .clipped()
            VStack(alignment: .leading, spacing: 1) {
                Text(game.title.uppercased()).font(DL.display(20)).foregroundStyle(DL.ink).lineLimit(1).minimumScaleFactor(0.7)
                Text(subtitle).font(DL.text(12)).foregroundStyle(DL.ink2).lineLimit(1)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
        }
        .frame(maxWidth: .infinity)
        .background(DL.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // Step 3
    private func done(_ score: Double) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                DLThumb(game: game, size: 56)
                VStack(alignment: .leading, spacing: 0) {
                    Text(game.title.uppercased()).font(DL.display(30)).foregroundStyle(DL.ink)
                    Text("Posted to your friends").font(DL.text(14)).foregroundStyle(DL.ink2)
                }
            }
            HStack(alignment: .center, spacing: 14) {
                CommunityScoreChip(score: score, size: 58)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your score").dlLabel(10.5)
                    if let friends = community.friendScores[gameID] {
                        Text("Friends rate it \(CommunityStore.ratingText(friends))").font(DL.text(15, .semibold)).foregroundStyle(DL.ink)
                    }
                }
            }
            .padding(.vertical, 8)
            DLTextKey(title: "Done", style: .ink).goesBack()
        }
    }

    // MARK: Ranking

    private func rival(_ band: CommunityBand) -> String? {
        let list = community.list(band, excluding: gameID)
        guard low < high, asked < Self.maxComparisons else { return nil }
        let mid = (low + high) / 2
        return list.indices.contains(mid) ? list[mid] : nil
    }

    private func pick(_ option: CommunityBand) {
        if LiveStore.shared.s.haptics { GameHaptics.tap() }
        low = 0
        high = community.list(option, excluding: gameID).count
        asked = 0
        band = option
        if high == 0 { finish(at: 0) }
    }

    private func answer(newIsBetter: Bool) {
        if LiveStore.shared.s.haptics { GameHaptics.tap() }
        let mid = (low + high) / 2
        if newIsBetter { high = mid } else { low = mid + 1 }
        asked += 1
        if low >= high || asked >= Self.maxComparisons { finish(at: low >= high ? low : (low + high) / 2) }
    }

    private func finish(at place: Int) {
        guard let band, score == nil else { return }
        let value = community.save(gameID, band: band, at: place)
        if LiveStore.shared.s.haptics { GameHaptics.success() }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { score = value }
    }
}
