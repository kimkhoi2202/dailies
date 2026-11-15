import SwiftUI

// INBOX: what happened while you were away. One calm line each, newest first.

enum G2InboxData {
    /// Today's, newest first.
    static let today: [MockNotification] = [Mock.notifications[1], Mock.notifications[0]]
    /// Before today: the rest of the shared story and two more that belong to it.
    static let earlier: [MockNotification] = Array(Mock.notifications.dropFirst(2)) + [
        MockNotification(symbol: "sparkles", title: "Comet trail is yours", detail: "You spent 40 gold in Lane Dash.", time: "Yesterday", unread: false),
        MockNotification(symbol: "bubble.fill", title: "noor.runs replied to your clip", detail: "Nine in a row and then that. Teach me.", time: "Thu", unread: false),
    ]

    /// The house style has no trophies. A passed score is drawn as a leaderboard.
    static func symbol(_ n: MockNotification) -> String {
        n.symbol == "trophy.fill" ? "chart.bar.fill" : n.symbol
    }

    /// Stamps stay short: a time for today, a weekday before it. In the story today is a Saturday.
    static func stamp(_ n: MockNotification) -> String {
        n.time == "Yesterday" ? "Fri" : n.time
    }

    /// Each detail is held to one line. One that would wrap keeps only its first sentence.
    static func line(_ n: MockNotification) -> String {
        guard n.detail.count > 48, let stop = n.detail.range(of: ". ") else { return n.detail }
        return n.detail[..<stop.lowerBound] + "."
    }

    /// News about gold is the one place a symbol is gold.
    static func isGold(_ n: MockNotification) -> Bool { n.symbol == "sun.max.fill" }
}

struct G2InboxScreen: View {
    var body: some View {
        let unread = G2InboxData.today.filter(\.unread).count
        DLTabs(selected: 0) {
            DLPage(spacing: 14) {
                DLNavBar(title: "Inbox", trailingSymbol: "gearshape.fill", trailingAction: { LiveNav.shared.open(.settings) })
                messagesRow
                card(title: "Today, \(unread) new", notes: G2InboxData.today, action: "Mark all read")
                card(title: "Earlier", notes: G2InboxData.earlier, action: nil)
                Text("Notifications clear themselves after 30 days.")
                    .font(DL.text(13))
                    .foregroundStyle(DL.ink3)
                    .padding(.leading, 16)
                    .padding(.top, 2)
            }
        }
    }

    /// The way into Messages, with how many chats have something new.
    private var messagesRow: some View {
        let unread = MessagesStore.shared.chats.filter(\.unread).count
        return HStack(spacing: 12) {
            G2SymbolTile(symbol: "bubble.left.and.bubble.right.fill", size: 40, tint: DL.goldText)
            VStack(alignment: .leading, spacing: 2) {
                Text("Messages").font(DL.text(16, .semibold)).foregroundStyle(DL.ink)
                Text(unread > 0 ? "\(unread) chats with something new" : "Friends and groups").font(DL.text(13)).foregroundStyle(DL.ink2)
            }
            Spacer(minLength: 8)
            if unread > 0 { Circle().fill(DL.gold).frame(width: 10, height: 10) }
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(DL.ink2)
        }
        .dlCard(padding: 14)
        .opens(.messages)
    }

    private func card(title: String, notes: [MockNotification], action: String?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title).dlLabel(10.5)
                Spacer()
                if let action {
                    Text(action).font(DL.text(13, .semibold)).foregroundStyle(DL.ink)
                }
            }
            .padding(.bottom, 4)
            ForEach(notes.indices, id: \.self) { index in
                if index > 0 { DLDivider(inset: 52) }
                row(notes[index])
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 6)
        .dlCard(padding: 0)
    }

    private func row(_ note: MockNotification) -> some View {
        HStack(alignment: .top, spacing: 12) {
            G2SymbolTile(symbol: G2InboxData.symbol(note), size: 40, tint: G2InboxData.isGold(note) ? DL.goldText : DL.ink)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(note.title)
                        .font(DL.text(15, .semibold))
                        .foregroundStyle(DL.ink)
                        .lineLimit(1)
                        .layoutPriority(1)
                    Spacer(minLength: 0)
                    Text(G2InboxData.stamp(note)).dlLabel(10, color: DL.ink3).fixedSize()
                    if note.unread {
                        Circle()
                            .fill(DL.ink)
                            .frame(width: 8, height: 8)
                            // A dot has no baseline. This sits it on the stamp's.
                            .alignmentGuide(.firstTextBaseline) { $0[.bottom] + 0.5 }
                            .accessibilityLabel("Unread")
                    }
                }
                Text(G2InboxData.line(note))
                    .font(DL.text(13))
                    .foregroundStyle(DL.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 11)
    }
}
