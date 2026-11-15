import SwiftUI

// MESSAGES: friends who are online, then direct chats and groups. Search narrows both.

struct MessagesInboxScreen: View {
    /// false when Messages is a tab rather than a pushed page.
    var showsBack: Bool = true
    @ObservedObject private var social = MessagesStore.shared
    @State private var query = ""

    private func matches(_ chat: ChatThread) -> Bool {
        query.isEmpty || chat.name.localizedCaseInsensitiveContains(query) || chat.preview.localizedCaseInsensitiveContains(query)
    }

    var body: some View {
        let chats = social.chats.sorted { $0.at > $1.at }.filter(matches)
        let direct = chats.filter { !$0.isGroup }
        let groups = chats.filter(\.isGroup)
        DLPage(spacing: 14) {
            HStack(spacing: 10) {
                if showsBack { DLIconButton(symbol: "chevron.left").goesBack().accessibilityLabel("Back") }
                Text("MESSAGES").font(DL.display(40)).foregroundStyle(DL.ink)
                Spacer()
                if !showsBack { DLGoldChip(onMedia: false).opens(.gold) }
                DLIconButton(symbol: "square.and.pencil").opens(.newGroup).accessibilityLabel("New group")
            }
            search
            online
            if !direct.isEmpty { section("Direct", direct) }
            if !groups.isEmpty { section("Groups", groups) }
            if chats.isEmpty {
                Text("No chats match \"\(query)\".").font(DL.text(15)).foregroundStyle(DL.ink2)
                    .frame(maxWidth: .infinity).padding(.vertical, 24)
            }
            workplaceRow
        }
    }

    private var search: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").font(.system(size: 17, weight: .semibold)).foregroundStyle(DL.ink2)
            TextField("Search friends and groups", text: $query)
                .font(DL.text(16)).foregroundStyle(DL.ink)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
        }
        .padding(.horizontal, 16)
        .frame(height: 50)
        .background(Capsule().fill(DL.surface))
    }

    private var online: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 14) {
                ForEach(social.onlineFriends) { friend in
                    VStack(spacing: 6) {
                        MessagesAvatar(person: friend, size: 60, ring: friend.online)
                            .overlay(alignment: .bottomTrailing) {
                                if friend.online {
                                    Circle().fill(DL.success).frame(width: 15, height: 15)
                                        .overlay(Circle().strokeBorder(DL.body, lineWidth: 3))
                                }
                            }
                        Text(friend.handle).font(DL.text(12, .medium)).foregroundStyle(DL.ink2).lineLimit(1)
                            .frame(width: 70)
                    }
                    .tap {
                        if let chat = social.chats.first(where: { $0.person?.handle == friend.handle }) {
                            LiveNav.shared.open(.chat(chat.id))
                        }
                    }
                }
            }
            .padding(.horizontal, DL.margin)
        }
        .scrollIndicators(.hidden)
        .padding(.horizontal, -DL.margin)
    }

    private func section(_ title: String, _ chats: [ChatThread]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).dlLabel(10.5).padding(.bottom, 2)
            ForEach(Array(chats.enumerated()), id: \.element.id) { index, chat in
                if index > 0 { DLDivider(inset: 64) }
                MessagesChatRow(chat: chat).opens(.chat(chat.id))
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 4)
        .dlCard(padding: 0)
    }

    private var workplaceRow: some View {
        HStack(spacing: 12) {
            G2SymbolTile(symbol: "building.2.fill", size: 44, tint: DL.goldText)
            VStack(alignment: .leading, spacing: 2) {
                Text("Join your work or school").font(DL.text(16, .semibold)).foregroundStyle(DL.ink)
                Text("Everyone with your email domain lands in one group.").font(DL.text(13)).foregroundStyle(DL.ink2)
            }
            Spacer(minLength: 6)
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(DL.ink2)
        }
        .dlCard(padding: 14)
        .opens(.workplace)
    }
}

/// One chat in the inbox: avatar or group tile, name, last line, time and an unread dot.
struct MessagesChatRow: View {
    var chat: ChatThread

    var body: some View {
        HStack(spacing: 12) {
            MessagesChatIcon(chat: chat, size: 50)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(chat.name).font(DL.text(16, .semibold)).foregroundStyle(DL.ink).lineLimit(1)
                    if chat.isGroup {
                        Text("\(chat.memberCount)").font(DL.label(10)).foregroundStyle(DL.ink3)
                    }
                }
                Text(chat.preview).font(DL.text(14, chat.unread ? .semibold : .regular))
                    .foregroundStyle(chat.unread ? DL.ink : DL.ink2).lineLimit(1)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 6) {
                Text(MessagesTime.short(chat.at)).dlLabel(10, color: DL.ink3)
                Circle().fill(chat.unread ? DL.gold : .clear).frame(width: 10, height: 10)
            }
        }
        .padding(.vertical, 10)
    }
}

/// A chat's picture: the friend's avatar, or the group's symbol on a gold-edged tile.
struct MessagesChatIcon: View {
    var chat: ChatThread
    var size: CGFloat = 44

    var body: some View {
        if let person = chat.person {
            MessagesAvatar(person: person, size: size)
                .overlay(alignment: .bottomTrailing) {
                    if person.online {
                        Circle().fill(DL.success).frame(width: size * 0.26, height: size * 0.26)
                            .overlay(Circle().strokeBorder(DL.surface, lineWidth: 2.5))
                    }
                }
        } else {
            Image(systemName: chat.icon)
                .font(.system(size: size * 0.4, weight: .bold))
                .foregroundStyle(DL.onGold)
                .frame(width: size, height: size)
                .background(RoundedRectangle(cornerRadius: size * 0.32, style: .continuous).fill(DL.gold))
                .background(RoundedRectangle(cornerRadius: size * 0.32, style: .continuous).fill(DL.goldLip).offset(y: 3))
        }
    }
}

enum MessagesTime {
    /// "2M AGO", "3H AGO", "YESTERDAY", "MON"
    static func short(_ date: Date) -> String {
        let seconds = Date().timeIntervalSince(date)
        if seconds < 60 { return "Now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m ago" }
        if seconds < 86400 { return "\(Int(seconds / 3600))h ago" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        let format = DateFormatter()
        format.dateFormat = "EEE"
        return format.string(from: date)
    }

    static func clock(_ date: Date) -> String {
        let format = DateFormatter()
        format.dateFormat = "HH:mm"
        return format.string(from: date)
    }
}

/// A friend's picture: their initial on their colour, with a gold ring for friends who are online.
struct MessagesAvatar: View {
    var person: ChatPerson
    var size: CGFloat = 44
    var ring: Bool = false

    var body: some View {
        DLAvatar(name: person.handle, size: size)
            .overlay {
                if ring { Circle().strokeBorder(DL.gold, lineWidth: max(2, size * 0.05)).padding(-size * 0.06) }
            }
            .accessibilityHidden(true)
    }
}
