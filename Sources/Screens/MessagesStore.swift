import SwiftUI
import Combine
import ConvexMobile

// Messages: friends, direct chats, groups and workplace groups.
// Every list starts from seeded local data so the screens are alive offline. When the Convex functions
// in convex/chat.ts answer, their live data replaces the local copy.

struct ChatPerson: Identifiable, Equatable {
    var id: String { handle }
    var userId: String? = nil
    var handle: String
    var colorHex: String
    var online: Bool = false
    var bio: String = ""

    var name: String { handle }
}

enum ChatMessageKind: String { case text, invite, score, post }

struct ChatMessage: Identifiable, Equatable {
    var id: String
    var kind: ChatMessageKind
    var body: String
    var gameID: String? = nil
    var score: Int? = nil
    var roomCode: String? = nil
    var at: Date
    var mine: Bool
    var author: ChatPerson?
}

struct ChatBoardRow: Equatable, Identifiable {
    var id: String { name }
    var name: String
    var colorHex: String
    var score: Int
    var you: Bool
}

struct ChatBoard: Equatable {
    var gameID: String
    var rows: [ChatBoardRow]
}

struct ChatThread: Identifiable, Equatable {
    var id: String
    /// direct, group or workplace
    var kind: String
    var name: String
    var icon: String
    var domain: String? = nil
    var person: ChatPerson? = nil
    var members: [ChatPerson] = []
    var memberCount: Int
    var preview: String
    var at: Date
    var unread: Bool
    var messages: [ChatMessage] = []
    var board: ChatBoard? = nil
    var typing: [String] = []
    /// Seeded on this phone, not from the server.
    var local: Bool = true

    var isGroup: Bool { kind != "direct" }
}

// MARK: Convex rows

struct ConvexChatPerson: Decodable {
    let id: String
    let name: String
    let handle: String
    let color: String
    let online: Bool?

    private enum CodingKeys: String, CodingKey {
        case id = "_id"
        case name, handle, color, online
    }
}

struct ConvexChatRow: Decodable {
    let id: String
    let kind: String
    let name: String
    let icon: String
    let domain: String?
    let other: ConvexChatPerson?
    let memberCount: Double
    let at: Double
    let preview: String
    let unread: Bool

    private enum CodingKeys: String, CodingKey {
        case id = "_id"
        case kind, name, icon, domain, other, memberCount, at, preview, unread
    }
}

struct ConvexInbox: Decodable {
    let chats: [ConvexChatRow]
    let friends: [ConvexChatPerson]
}

struct ConvexChatAuthor: Decodable {
    let name: String
    let handle: String
    let color: String
}

struct ConvexChatMessage: Decodable {
    let id: String
    let kind: String
    let body: String
    let gameSlug: String?
    let roomCode: String?
    let score: Double?
    let at: Double
    let mine: Bool
    let author: ConvexChatAuthor?

    private enum CodingKeys: String, CodingKey {
        case id = "_id"
        case kind, body, gameSlug, roomCode, score, at, mine, author
    }
}

struct ConvexChatBoardRow: Decodable {
    let name: String
    let color: String
    let score: Double
    let you: Bool
}

struct ConvexChatBoard: Decodable {
    let slug: String
    let rows: [ConvexChatBoardRow]
}

struct ConvexConversation: Decodable {
    let id: String
    let kind: String
    let name: String
    let icon: String
    let domain: String?
    let other: ConvexChatPerson?
    let memberCount: Double
    let members: [ConvexChatPerson]
    let messages: [ConvexChatMessage]
    let typing: [String]
    let board: ConvexChatBoard?

    private enum CodingKeys: String, CodingKey {
        case id = "_id"
        case kind, name, icon, domain, other, memberCount, members, messages, typing, board
    }
}

struct ConvexWorkplaceCode: Decodable {
    let domain: String
    let name: String
    let demoCode: String
}

/// A reason a request did not go through, in words for the screen.
struct ChatProblem: Error {
    let text: String
}

// MARK: Store

final class MessagesStore: ObservableObject {
    static let shared = MessagesStore()

    @Published private(set) var friends: [ChatPerson] = ChatSeed.friends
    @Published private(set) var localChats: [ChatThread] = ChatSeed.chats()
    @Published private(set) var serverChats: [ChatThread]?
    @Published private(set) var threads: [String: ChatThread] = [:]

    private var bag = Set<AnyCancellable>()
    private var watches: [AnyCancellable] = []
    private var threadWatches: [String: AnyCancellable] = [:]
    private var pinging: Timer?

    private init() {
        guard !ProcessInfo.processInfo.arguments.contains("-screen") else { return }
        ConvexLink.shared.signedIn.sink { [weak self] on in self?.signedInChanged(on) }.store(in: &bag)
    }

    // MARK: Me

    var me: ChatPerson {
        let live = LiveStore.shared
        return ChatPerson(handle: live.me?.handle ?? Mock.handle, colorHex: live.me?.color ?? "FFC531", online: true)
    }

    // MARK: Chats

    var chats: [ChatThread] { (serverChats ?? []).isEmpty ? localChats : serverChats ?? [] }

    func chat(_ id: String) -> ChatThread? {
        if let live = threads[id] { return live }
        return chats.first { $0.id == id } ?? localChats.first { $0.id == id }
    }

    var onlineFriends: [ChatPerson] { friends.filter(\.online) + friends.filter { !$0.online } }

    /// Opens the live query for one server chat. Local chats need nothing.
    func open(_ id: String) {
        if let index = localChats.firstIndex(where: { $0.id == id }) {
            localChats[index].unread = false
            return
        }
        guard threadWatches[id] == nil else { return }
        threadWatches[id] = ConvexLink.shared.watch("chat:conversation", ["conversationId": id], as: ConvexConversation?.self) { [weak self] row in
            guard let self, let row else { return }
            self.threads[id] = Self.chat(from: row)
        }
        Task { try? await ConvexLink.shared.mutate("chat:markRead", ["conversationId": id]) }
    }

    func send(_ text: String, to id: String) {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        GameHaptics.tap()
        post(ChatMessage(id: UUID().uuidString, kind: .text, body: String(body.prefix(500)), at: Date(), mine: true, author: me), to: id)
    }

    /// Sends a game invite or a score into a chat.
    func share(kind: ChatMessageKind, game: MockGame, body: String, score: Int? = nil, roomCode: String? = nil, to id: String) {
        GameHaptics.success()
        post(ChatMessage(id: UUID().uuidString, kind: kind, body: body, gameID: game.id, score: score, roomCode: roomCode,
                           at: Date(), mine: true, author: me), to: id)
    }

    private func post(_ message: ChatMessage, to id: String) {
        if let index = localChats.firstIndex(where: { $0.id == id }) {
            localChats[index].messages.append(message)
            localChats[index].preview = "You: " + Self.previewText(message)
            localChats[index].at = message.at
            replyLater(in: id)
            return
        }
        if var thread = threads[id] {
            thread.messages.append(message)
            threads[id] = thread
        }
        var args: [String: ConvexEncodable?] = ["conversationId": id, "kind": message.kind.rawValue, "body": message.body]
        if let game = message.gameID { args["gameSlug"] = game }
        if let score = message.score { args["score"] = Double(score) }
        if let code = message.roomCode { args["roomCode"] = code }
        Task { try? await ConvexLink.shared.mutate("chat:send", args) }
    }

    /// In a seeded chat a friend answers after a short pause, so the demo has someone on the other end.
    private func replyLater(in id: String) {
        guard let chat = localChats.first(where: { $0.id == id }) else { return }
        let friend = chat.person ?? chat.members.first { $0.handle != me.handle } ?? ChatSeed.friends[0]
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            guard let index = self.localChats.firstIndex(where: { $0.id == id }) else { return }
            withAnimation(.snappy) { self.localChats[index].typing = [friend.handle] }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
            guard let index = self.localChats.firstIndex(where: { $0.id == id }) else { return }
            let lines = ["ok you are on", "give me two minutes", "running it back now", "no way. rematch", "deal"]
            let line = lines[self.localChats[index].messages.count % lines.count]
            let reply = ChatMessage(id: UUID().uuidString, kind: .text, body: line, at: Date(), mine: false, author: friend)
            withAnimation(.snappy) {
                self.localChats[index].typing = []
                self.localChats[index].messages.append(reply)
                self.localChats[index].preview = (chat.isGroup ? friend.handle + ": " : "") + line
            }
            GameHaptics.tap()
        }
    }

    /// Play together: opens a room for the game on the server when it can, and posts the invite.
    func playTogether(_ game: MockGame, in id: String) {
        let fallback = String((0..<4).map { _ in "BCDFGHJKLMNPQRSTVWXZ".randomElement()! })
        let isLocal = localChats.contains { $0.id == id }
        Task { @MainActor in
            var code = fallback
            if !isLocal, let made = try? await ConvexLink.shared.mutate("rooms:create", ["slug": game.id], as: String.self) { code = made }
            self.share(kind: .invite, game: game, body: "Play \(game.title) with me", roomCode: code, to: id)
        }
    }

    /// Makes a group with friends. Returns the new chat's id.
    func createGroup(name: String, icon: String, handles: [String]) async -> String {
        let members = friends.filter { handles.contains($0.handle) }
        let ids = members.compactMap(\.userId)
        if serverChats != nil, ids.count == members.count, !ids.isEmpty {
            let made = try? await ConvexLink.shared.mutate("chat:createGroup", ["name": name, "icon": icon, "userIds": ids.map { $0 as ConvexEncodable? }], as: String.self)
            if let made { return made }
        }
        let id = "local-group-\(UUID().uuidString.prefix(6))"
        let hello = ChatMessage(id: UUID().uuidString, kind: .text, body: "Made \(name). First one to beat my score picks the next game.",
                                  at: Date(), mine: true, author: me)
        let chat = ChatThread(id: id, kind: "group", name: name, icon: icon, members: [me] + members, memberCount: members.count + 1,
                              preview: "You: " + hello.body, at: Date(), unread: false, messages: [hello],
                              board: ChatSeed.board(for: [me] + members, game: Mock.tippyTower))
        localChats.insert(chat, at: 0)
        return id
    }

    /// Asks for the 6 digit code for a work or school email. The demo shows the code on screen.
    func requestWorkplaceCode(_ email: String) async -> Result<ConvexWorkplaceCode, ChatProblem> {
        let clean = email.trimmingCharacters(in: .whitespaces).lowercased()
        let parts = clean.split(separator: "@")
        guard parts.count == 2, parts[1].contains(".") else { return .failure(ChatProblem(text: "That does not look like an email")) }
        let domain = String(parts[1])
        if ["gmail.com", "yahoo.com", "outlook.com", "hotmail.com", "icloud.com", "me.com", "proton.me"].contains(domain) {
            return .failure(ChatProblem(text: "Use a work or school email"))
        }
        if let answer = try? await ConvexLink.shared.mutate("chat:requestWorkplaceCode", ["email": clean], as: ConvexWorkplaceCode.self) {
            return .success(answer)
        }
        let code = String(format: "%06d", Int.random(in: 100_000...999_999))
        localCode = (domain, code)
        return .success(ConvexWorkplaceCode(domain: domain, name: ChatSeed.workplaceName(domain), demoCode: code))
    }

    private var localCode: (domain: String, code: String)?

    /// Checks the code and puts the player in their workplace group. Returns the group's id.
    func verifyWorkplaceCode(_ code: String) async -> Result<String, ChatProblem> {
        if let pending = localCode {
            guard pending.code == code else { return .failure(ChatProblem(text: "That code is not right")) }
            localCode = nil
            return .success(joinLocalWorkplace(pending.domain))
        }
        do {
            let id = try await ConvexLink.shared.mutate("chat:verifyWorkplaceCode", ["code": code], as: String.self)
            return .success(id)
        } catch {
            return .failure(ChatProblem(text: "\(error)".contains("not right") ? "That code is not right" : "That code expired. Ask for a new one"))
        }
    }

    private func joinLocalWorkplace(_ domain: String) -> String {
        let joined = ChatMessage(id: UUID().uuidString, kind: .text, body: "Just joined. Who is up for a round?", at: Date(), mine: true, author: me)
        if let index = localChats.firstIndex(where: { $0.domain == domain }) {
            localChats[index].messages.append(joined)
            localChats[index].memberCount += 1
            localChats[index].members.append(me)
            localChats[index].preview = "You: " + joined.body
            localChats[index].at = Date()
            return localChats[index].id
        }
        let id = "local-work-\(domain)"
        localChats.insert(ChatThread(id: id, kind: "workplace", name: ChatSeed.workplaceName(domain), icon: "building.2.fill",
                                     domain: domain, members: [me], memberCount: 1, preview: "You: " + joined.body, at: Date(),
                                     unread: false, messages: [joined]), at: 0)
        return id
    }

    static func previewText(_ message: ChatMessage) -> String {
        switch message.kind {
        case .invite: "Sent a game invite"
        case .score: "Shared a score"
        case .post: "Shared a clip"
        case .text: message.body
        }
    }

    // MARK: Server

    private func signedInChanged(_ on: Bool) {
        watches.removeAll()
        threadWatches.removeAll()
        pinging?.invalidate()
        guard on else { return }
        let link = ConvexLink.shared
        watches = [
            link.watch("chat:inbox", as: ConvexInbox?.self) { [weak self] value in
                guard let self, let value else { return }
                self.serverChats = value.chats.map(Self.chat(from:))
                if !value.friends.isEmpty {
                    let seeded = ChatSeed.friends
                    self.friends = value.friends.map { row in
                        var person = Self.person(from: row)
                        if let local = seeded.first(where: { $0.handle == row.handle }) {
                            person.bio = local.bio
                            person.online = person.online || local.online
                        }
                        return person
                    }
                }
            },
        ]
        ping()
        pinging = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.ping() }
    }

    private func ping() {
        Task { try? await ConvexLink.shared.mutate("chat:ping") }
    }

    private static func person(from row: ConvexChatPerson) -> ChatPerson {
        ChatPerson(userId: row.id, handle: row.handle, colorHex: row.color, online: row.online ?? false)
    }

    private static func chat(from row: ConvexChatRow) -> ChatThread {
        ChatThread(id: row.id, kind: row.kind, name: row.name, icon: row.icon.isEmpty ? "person.2.fill" : row.icon, domain: row.domain,
                   person: row.other.map(person(from:)), memberCount: Int(row.memberCount), preview: row.preview,
                   at: Date(timeIntervalSince1970: row.at / 1000), unread: row.unread, local: false)
    }

    private static func chat(from row: ConvexConversation) -> ChatThread {
        let messages = row.messages.map { message in
            ChatMessage(id: message.id, kind: ChatMessageKind(rawValue: message.kind) ?? .text, body: message.body,
                          gameID: message.gameSlug, score: message.score.map { Int($0) }, roomCode: message.roomCode,
                          at: Date(timeIntervalSince1970: message.at / 1000), mine: message.mine,
                          author: message.author.map { ChatPerson(handle: $0.handle, colorHex: $0.color) })
        }
        let board = row.board.map { board in
            ChatBoard(gameID: board.slug, rows: board.rows.map {
                ChatBoardRow(name: $0.name, colorHex: $0.color, score: Int($0.score), you: $0.you)
            })
        }
        return ChatThread(id: row.id, kind: row.kind, name: row.name, icon: row.icon.isEmpty ? "person.2.fill" : row.icon,
                          domain: row.domain, person: row.other.map(person(from:)), members: row.members.map(person(from:)),
                          memberCount: Int(row.memberCount), preview: "", at: messages.last?.at ?? Date(), unread: false,
                          messages: messages, board: board, typing: row.typing, local: false)
    }
}
