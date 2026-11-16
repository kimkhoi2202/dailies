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
                    .tap { withAnimation(.interpolatingSpring(mass: 1, stiffness: 1200, damping: 120)) { selected = index } }
            }
        }
        .background {
            // One pill that slides to the chosen item.
            GeometryReader { proxy in
                let width = (proxy.size.width - 4 * CGFloat(items.count - 1)) / CGFloat(items.count)
                Capsule().fill(DL.ink).frame(width: width).offset(x: CGFloat(selected) * (width + 4))
            }
        }
        .padding(4)
        .background(Capsule().fill(DL.surface))
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
