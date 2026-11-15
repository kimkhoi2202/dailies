import SwiftUI

// A CHAT: bubbles, game invites, shared scores and clips, a typing line and the composer.
// Groups add a member count, a Play together key and the week's group leaderboard pinned on top.

struct MessagesChatScreen: View {
    var chatID: String
    @ObservedObject private var social = MessagesStore.shared
    @State private var draft = ""
    @FocusState private var typing: Bool

    var body: some View {
        let chat = social.chat(chatID)
        VStack(spacing: 0) {
            if let chat {
                topBar(chat).padding(.horizontal, DL.margin).padding(.top, 6).padding(.bottom, 8)
                ScrollViewReader { reader in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            if let board = chat.board { MessagesBoardCard(board: board).padding(.bottom, 8) }
                            ForEach(Array(chat.messages.enumerated()), id: \.element.id) { index, message in
                                if showsTime(chat.messages, index) {
                                    Text(MessagesTime.short(message.at)).dlLabel(10, color: DL.ink3)
                                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                                }
                                MessagesBubble(message: message, group: chat.isGroup,
                                               showAuthor: chat.isGroup && !message.mine && (index == 0 || chat.messages[index - 1].author?.handle != message.author?.handle))
                                    .id(message.id)
                                    .transition(.move(edge: .bottom).combined(with: .opacity))
                            }
                            if let who = chat.typing.first {
                                MessagesTypingLine(handle: who).id("typing").transition(.opacity)
                            }
                            Color.clear.frame(height: 4).id("end")
                        }
                        .padding(.horizontal, DL.margin)
                        .animation(.snappy(duration: 0.3), value: chat.messages.count)
                        .animation(.snappy(duration: 0.3), value: chat.typing)
                    }
                    .scrollIndicators(.hidden)
                    .defaultScrollAnchor(.bottom)
                    .scrollDismissesKeyboard(.interactively)
                    .onAppear { reader.scrollTo("end", anchor: .bottom) }
                    .onChange(of: chat.messages.count) { _, _ in
                        withAnimation(.snappy) { reader.scrollTo("end", anchor: .bottom) }
                    }
                    .onChange(of: chat.typing) { _, _ in
                        withAnimation(.snappy) { reader.scrollTo("end", anchor: .bottom) }
                    }
                    .onChange(of: typing) { _, focused in
                        guard focused else { return }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            withAnimation(.snappy) { reader.scrollTo("end", anchor: .bottom) }
                        }
                    }
                }
                composer
            } else {
                DLNavBar(title: "Chat").padding(.horizontal, DL.margin)
                Spacer()
                Text("Loading this chat").font(DL.text(15)).foregroundStyle(DL.ink2)
                Spacer()
            }
        }
        .background(DL.body.ignoresSafeArea())
        .onAppear { social.open(chatID) }
    }

    private func showsTime(_ messages: [ChatMessage], _ index: Int) -> Bool {
        index == 0 || messages[index].at.timeIntervalSince(messages[index - 1].at) > 15 * 60
    }

    private func topBar(_ chat: ChatThread) -> some View {
        HStack(spacing: 10) {
            DLIconButton(symbol: "chevron.left").goesBack().accessibilityLabel("Back")
            HStack(spacing: 10) {
                MessagesChatIcon(chat: chat, size: 40)
                VStack(alignment: .leading, spacing: 1) {
                    Text(chat.name).font(DL.text(17, .semibold)).foregroundStyle(DL.ink).lineLimit(1)
                    Text(subtitle(chat)).dlLabel(10, color: chat.person?.online == true ? DL.success : DL.ink2)
                }
            }
            Spacer(minLength: 6)
            if chat.isGroup {
                DLKey(style: .gold, radius: 16, depth: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill").font(.system(size: 12, weight: .black))
                        Text("PLAY TOGETHER").font(DL.display(16))
                    }
                    .padding(.horizontal, 12)
                }
                .frame(width: 148, height: 42)
                .opens(.playTogether(chatID))
            } else {
                DLIconButton(symbol: "gamecontroller.fill").opens(.playTogether(chatID)).accessibilityLabel("Invite to a game")
            }
        }
    }

    private func subtitle(_ chat: ChatThread) -> String {
        if let person = chat.person { return person.online ? "Online now" : "@" + person.handle }
        if let domain = chat.domain { return "\(chat.memberCount) members, @\(domain)" }
        return "\(chat.memberCount) members"
    }

    private var composer: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus")
                .font(.system(size: 18, weight: .bold)).foregroundStyle(DL.ink)
                .frame(width: 44, height: 44)
                .background(Circle().fill(DL.surface))
                .opens(.playTogether(chatID))
                .accessibilityLabel("Invite or share a score")
            TextField("Message", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .font(DL.text(16)).foregroundStyle(DL.ink)
                .focused($typing)
                .submitLabel(.send)
                .onSubmit(send)
                .padding(.horizontal, 16).padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(DL.surface))
            Image(systemName: "arrow.up")
                .font(.system(size: 18, weight: .black)).foregroundStyle(DL.onGold)
                .frame(width: 44, height: 44)
                .background(Circle().fill(draft.isEmpty ? DL.sunken : DL.gold))
                .tap(send)
                .accessibilityLabel("Send")
        }
        .padding(.horizontal, DL.margin)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(DL.body.ignoresSafeArea(edges: .bottom))
    }

    private func send() {
        guard !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let text = draft
        draft = ""
        withAnimation(.snappy) { social.send(text, to: chatID) }
    }
}

// MARK: Bubbles and cards

struct MessagesBubble: View {
    var message: ChatMessage
    var group: Bool
    var showAuthor: Bool
    @State private var reaction: String?

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.mine { Spacer(minLength: 56) }
            if group && !message.mine {
                if showAuthor, let author = message.author {
                    MessagesAvatar(person: author, size: 30)
                } else {
                    Color.clear.frame(width: 30, height: 1)
                }
            }
            VStack(alignment: message.mine ? .trailing : .leading, spacing: 3) {
                if showAuthor, let author = message.author {
                    Text(author.handle).dlLabel(10, color: DL.ink3).padding(.leading, 4)
                }
                content
                    .overlay(alignment: message.mine ? .bottomLeading : .bottomTrailing) {
                        if let reaction {
                            MessagesReactionChip(text: reaction).offset(x: message.mine ? -10 : 10, y: 12)
                                .transition(.scale(scale: 0.3).combined(with: .opacity))
                        }
                    }
                    .padding(.bottom, reaction == nil ? 0 : 12)
                    .onTapGesture(count: 2) { react() }
            }
            if !message.mine { Spacer(minLength: 56) }
        }
    }

    /// Double tap gives a game reaction: GG, then fire, skull and crown.
    private func react() {
        let all = ["GG", "flame.fill", "skull", "crown.fill"]
        let next = reaction.flatMap { all.firstIndex(of: $0) }.map { all[($0 + 1) % all.count] } ?? all[0]
        GameHaptics.thud()
        withAnimation(.spring(duration: 0.35, bounce: 0.55)) { reaction = next }
    }

    @ViewBuilder private var content: some View {
        switch message.kind {
        case .text:
            Text(message.body)
                .font(DL.text(16)).foregroundStyle(DL.ink)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(message.mine ? DL.goldWash : DL.surface))
        case .invite:
            MessagesInviteCard(message: message)
        case .score:
            MessagesScoreCard(message: message)
        case .post:
            MessagesPostCard(message: message)
        }
    }
}

struct MessagesReactionChip: View {
    var text: String

    var body: some View {
        Group {
            if text == "GG" {
                Text("GG").font(DL.display(15))
            } else {
                Image(systemName: text).font(.system(size: 12, weight: .black))
            }
        }
        .foregroundStyle(DL.onGold)
        .frame(minWidth: 30, minHeight: 24)
        .padding(.horizontal, 4)
        .background(Capsule().fill(DL.gold))
        .overlay(Capsule().strokeBorder(DL.body, lineWidth: 2))
    }
}

/// "Play Five Up with me": the game's cover, the room, and a Join key that opens the game.
struct MessagesInviteCard: View {
    var message: ChatMessage

    var body: some View {
        let game = Mock.game(message.gameID ?? "five-up")
        VStack(alignment: .leading, spacing: 0) {
            ClipStill(game: game, showHUD: false, focusY: 0.3)
                .frame(height: 120)
                .overlay(alignment: .topLeading) {
                    DLMediaTag(text: "Game invite", symbol: "gamecontroller.fill").padding(10)
                }
                .clipped()
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(message.body).font(DL.text(16, .semibold)).foregroundStyle(DL.ink)
                    Text(message.roomCode.map { "Room \($0), \(game.players)" } ?? game.players).dlLabel(10)
                }
                DLKey(style: .gold, radius: 16, depth: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill").font(.system(size: 13, weight: .black))
                        Text(message.mine ? "OPEN LOBBY" : "JOIN").font(DL.display(20))
                    }
                }
                .frame(height: 46)
                .opens(.gameReady(game.id))
            }
            .padding(12)
        }
        .frame(width: 244)
        .background(DL.surface)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

/// "I got 58 floors. Beat it?": the score as the hero, on the game's art.
struct MessagesScoreCard: View {
    var message: ChatMessage

    var body: some View {
        let game = Mock.game(message.gameID ?? "tippy-tower")
        VStack(alignment: .leading, spacing: 0) {
            ClipStill(game: game, showHUD: false, focusY: 0.5)
                .frame(height: 150)
                .overlay(Color.black.opacity(0.45))
                .overlay {
                    VStack(spacing: -4) {
                        Text(groupedNumber(message.score ?? 0)).font(DL.display(64)).foregroundStyle(.white)
                        Text(game.title).font(DL.label(11)).textCase(.uppercase).foregroundStyle(.white.opacity(0.85))
                    }
                }
                .clipped()
            VStack(alignment: .leading, spacing: 10) {
                Text(message.body).font(DL.text(15, .semibold)).foregroundStyle(DL.ink)
                DLKey(style: message.mine ? .neutral : .gold, radius: 16, depth: 4) {
                    Text(message.mine ? "PLAY AGAIN" : "BEAT IT").font(DL.display(20))
                }
                .frame(height: 46)
                .opens(.gameReady(game.id))
            }
            .padding(12)
        }
        .frame(width: 230)
        .background(DL.surface)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

/// A clip shared from the feed.
struct MessagesPostCard: View {
    var message: ChatMessage

    var body: some View {
        let game = Mock.game(message.gameID ?? "lane-dash")
        DLClipCard(game: game, width: 180, height: 250)
            .overlay(alignment: .topLeading) {
                Text(message.body).font(DL.text(13, .semibold)).foregroundStyle(.white)
                    .lineLimit(3).padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(LinearGradient(colors: [.black.opacity(0.6), .clear], startPoint: .top, endPoint: .bottom))
                    .clipShape(UnevenRoundedRectangle(cornerRadii: RectangleCornerRadii(topLeading: 22, topTrailing: 22)))
            }
            .overlay { DLRoundPlayKey(size: 50) }
            .opens(.gameReady(game.id))
    }
}

struct MessagesTypingLine: View {
    var handle: String
    @State private var bounce = false

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { index in
                    Circle().fill(DL.ink2).frame(width: 7, height: 7)
                        .offset(y: bounce ? -3 : 3)
                        .animation(.easeInOut(duration: 0.45).repeatForever().delay(Double(index) * 0.15), value: bounce)
                }
            }
            .padding(.horizontal, 14).frame(height: 36)
            .background(Capsule().fill(DL.surface))
            Text("\(handle) is typing").dlLabel(10, color: DL.ink3)
        }
        .onAppear { bounce = true }
    }
}

/// This week's group leaderboard, pinned at the top of a group chat.
struct MessagesBoardCard: View {
    var board: ChatBoard

    var body: some View {
        let game = Mock.game(board.gameID)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                DLThumb(game: game, size: 36)
                VStack(alignment: .leading, spacing: 0) {
                    Text("This week").dlLabel(10)
                    Text(game.title.uppercased()).font(DL.display(22)).foregroundStyle(DL.ink)
                }
                Spacer()
                Image(systemName: "pin.fill").font(.system(size: 12, weight: .bold)).foregroundStyle(DL.ink3)
            }
            ForEach(Array(board.rows.prefix(3).enumerated()), id: \.element.id) { index, row in
                HStack(spacing: 10) {
                    Text("\(index + 1)").font(DL.display(20)).foregroundStyle(index == 0 ? DL.goldText : DL.ink3).frame(width: 18)
                    Text(row.you ? "You" : row.name).font(DL.text(15, row.you ? .bold : .medium)).foregroundStyle(DL.ink)
                    if index == 0 {
                        Image(systemName: "crown.fill").font(.system(size: 11, weight: .bold)).foregroundStyle(DL.goldText)
                    }
                    Spacer()
                    Text(groupedNumber(row.score)).font(DL.display(22)).monospacedDigit().foregroundStyle(DL.ink)
                }
            }
            DLMeter(value: Double(board.rows.first { $0.you }?.score ?? 0), total: Double(max(1, board.rows.first?.score ?? 1)), height: 6)
        }
        .dlCard(padding: 14)
        .overlay(RoundedRectangle(cornerRadius: DL.cardRadius, style: .continuous).strokeBorder(DL.gold.opacity(0.5), lineWidth: 1.5))
        .opens(.leaderboard(game.id))
    }
}
