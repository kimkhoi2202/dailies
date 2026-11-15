import SwiftUI

// COMMUNITY, the social tab: what friends are playing, scoring and posting, and a way into each game.
// Friends is the feed. Explore is the game browsing that used to sit behind Search.

struct CommunityScreen: View {
    @State private var section = 0

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                CommunityTopBar()
                CommunitySegment(items: ["Friends", "Explore"], selected: $section)
            }
            .padding(.horizontal, DL.margin)
            .padding(.top, 6)
            .padding(.bottom, 6)
            .background(DL.body.ignoresSafeArea(edges: .top))
            .zIndex(1)

            if section == 0 {
                CommunityFriendsFeed()
                    .transition(.move(edge: .leading).combined(with: .opacity))
            } else {
                LiveSearchScreen(embedded: true)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .background(DL.body.ignoresSafeArea())
    }
}

/// Two choices in our pill style: dark track, cream for the chosen one.
struct CommunitySegment: View {
    let items: [String]
    @Binding var selected: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(items.indices, id: \.self) { index in
                let chosen = index == selected
                Text(items[index])
                    .font(DL.text(15, .semibold))
                    .foregroundStyle(chosen ? DL.onInk : DL.ink)
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .background(Capsule().fill(chosen ? DL.ink : Color.clear))
                    .tap { withAnimation(.snappy(duration: 0.28)) { selected = index } }
            }
        }
        .padding(4)
        .background(Capsule().fill(DL.surface))
    }
}

/// Friends: stories, the streak, who is live, a challenge, then everyone's posts.
struct CommunityFriendsFeed: View {
    @ObservedObject private var community = CommunityStore.shared

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                stories
                CommunityStreakCard()
                if !community.live.isEmpty { liveNow }
                if let challenge = community.challenges.first(where: { $0.expires > Date() }) {
                    CommunityChallengeCard(challenge: challenge)
                }
                HomeSectionTitle(title: "Friends", link: nil).padding(.top, 4)
                if community.posts.isEmpty {
                    empty
                } else {
                    ForEach(Array(community.posts.enumerated()), id: \.element.id) { index, post in
                        CommunityActivityCard(post: post)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                            .scrollTransition(.animated(.snappy(duration: 0.35))) { content, phase in
                                content
                                    .opacity(phase.isIdentity ? 1 : 0.55)
                                    .scaleEffect(phase.isIdentity ? 1 : 0.96)
                            }
                        if index == 2 { continuePlaying }
                        if index % 5 == 4 { CommunityRankCard() }
                    }
                }
            }
            .padding(.horizontal, DL.margin)
            .padding(.top, 8)
            .padding(.bottom, 24)
            .animation(.snappy(duration: 0.3), value: community.posts.map(\.id))
        }
        .scrollIndicators(.hidden)
        .background(DL.body)
    }

    private var stories: some View {
        let list = community.stories
        return ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 8) {
                VStack(spacing: 5) {
                    DLAvatar(name: Mock.handle, size: 62)
                        .padding(4)
                        .overlay(Circle().strokeBorder(DL.line, lineWidth: 3))
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "plus")
                                .font(.system(size: 12, weight: .black)).foregroundStyle(DL.onGold)
                                .frame(width: 24, height: 24)
                                .background(Circle().fill(DL.gold))
                                .overlay(Circle().strokeBorder(DL.body, lineWidth: 2))
                        }
                    Text("You").font(DL.text(12, .medium)).foregroundStyle(DL.ink2).padding(.top, 4)
                }
                .frame(width: 76)
                .opens(.create(nil))
                ForEach(Array(list.enumerated()), id: \.element.id) { index, story in
                    CommunityStoryBubble(name: story.name, chip: story.score, seen: community.seenStories.contains(story.name))
                        .opens(.story(index))
                        .accessibilityLabel("\(story.name), \(story.score) \(story.unit) in \(story.game.title)")
                }
            }
            .padding(.horizontal, DL.margin)
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
        .padding(.horizontal, -DL.margin)
    }

    private var liveNow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HomeSectionTitle(title: "Live now")
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(community.live.prefix(3)) { live in CommunityLiveCard(live: live) }
                }
                .padding(.horizontal, DL.margin)
            }
            .scrollIndicators(.hidden)
            .padding(.horizontal, -DL.margin)
        }
    }

    private var continuePlaying: some View {
        VStack(alignment: .leading, spacing: 10) {
            HomeSectionTitle(title: "Continue playing")
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(Mock.continuePlaying.indices, id: \.self) { index in
                        let entry = Mock.continuePlaying[index]
                        ContinueCard(game: entry.game, note: continueNote(entry.game) ?? entry.note)
                            .opens(.gameReady(entry.game.id))
                    }
                }
                .padding(.horizontal, DL.margin)
            }
            .scrollIndicators(.hidden)
            .padding(.horizontal, -DL.margin)
        }
        .padding(.vertical, 4)
    }

    private func continueNote(_ game: MockGame) -> String? {
        guard let best = LiveStore.shared.s.best[game.id], best > 0 else { return nil }
        return "Your best: \(LiveStore.shared.s.bestText[game.id] ?? groupedNumber(best)) \(LiveStore.shared.s.bestUnit[game.id] ?? "")"
    }

    private var empty: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.2.fill").font(.system(size: 30)).foregroundStyle(DL.ink3)
            Text("Follow friends to see what they're playing.").font(DL.text(15)).foregroundStyle(DL.ink2)
                .multilineTextAlignment(.center)
            DLTextKey(title: "Invite", symbol: "person.badge.plus", style: .neutral)
                .tap { LiveNav.shared.share("Come and play with me on DEGEN") }
                .frame(width: 180)
        }
        .frame(maxWidth: .infinity)
        .dlCard(padding: 24)
    }
}

// MARK: Notifications

struct CommunityNotificationsScreen: View {
    @ObservedObject private var community = CommunityStore.shared

    var body: some View {
        DLPage(spacing: 14) {
            DLNavBar(title: "Notifications")
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(community.notes.enumerated()), id: \.element.id) { index, note in
                    if index > 0 { DLDivider(inset: 56) }
                    row(note)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 6)
            .dlCard(padding: 0)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                withAnimation(.snappy(duration: 0.3)) { community.markAllRead() }
            }
        }
    }

    private func row(_ note: CommunityNote) -> some View {
        HStack(alignment: .center, spacing: 12) {
            DLAvatar(name: note.name, size: 42)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: note.symbol)
                        .font(.system(size: 9, weight: .bold)).foregroundStyle(DL.onGold)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(DL.gold))
                        .overlay(Circle().strokeBorder(DL.surface, lineWidth: 2))
                        .offset(x: 4, y: 4)
                }
            VStack(alignment: .leading, spacing: 3) {
                Text(note.text).font(DL.text(15, note.unread ? .semibold : .regular)).foregroundStyle(DL.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(CommunityStore.ago(note.at)).dlLabel(10, color: DL.ink3)
            }
            Spacer(minLength: 4)
            if note.unread { Circle().fill(DL.gold).frame(width: 9, height: 9) }
        }
        .padding(.vertical, 11)
        .contentShape(Rectangle())
        .tap { if let game = note.gameID { LiveNav.shared.open(.gameReady(game)) } }
    }
}
