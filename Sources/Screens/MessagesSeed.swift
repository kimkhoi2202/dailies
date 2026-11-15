import SwiftUI

// The seeded social world: six friends, four direct chats with history, the Hackathon squad and Stanford.
// The same people and lines are in convex/seedChat.ts, so the app looks the same before and after the server answers.

enum ChatSeed {
    static let friends: [ChatPerson] = [
        ChatPerson(handle: "devon.plays", colorHex: "19B8A6",
                     online: true, bio: "Tower main. Ask me about perfect drops."),
        ChatPerson(handle: "kaz", colorHex: "7C5CFF",
                     online: true, bio: "Five Up in three tries or I log off."),
        ChatPerson(handle: "noor.runs", colorHex: "FF6B57",
                     online: true, bio: "Lane Dash, no brakes."),
        ChatPerson(handle: "tofu", colorHex: "FF9F43",
                     online: false, bio: "Eats the whole block."),
        ChatPerson(handle: "juno", colorHex: "8BC34A",
                     online: false, bio: "Inkland cartographer."),
        ChatPerson(handle: "wordnerd.sam", colorHex: "FF7AB6",
                     online: true, bio: "Words are my cardio."),
    ]

    private static func friend(_ index: Int) -> ChatPerson { friends[index] }

    private static func ago(_ minutes: Double) -> Date { Date().addingTimeInterval(-minutes * 60) }

    private static func line(_ who: ChatPerson?, _ minutes: Double, _ body: String, kind: ChatMessageKind = .text,
                             game: String? = nil, score: Int? = nil) -> ChatMessage {
        ChatMessage(id: "\(who?.handle ?? "me")-\(minutes)", kind: kind, body: body, gameID: game, score: score,
                      at: ago(minutes), mine: who == nil, author: who)
    }

    static func board(for members: [ChatPerson], game: MockGame) -> ChatBoard {
        let me = LiveStore.shared.me?.handle ?? Mock.handle
        var rows = members.filter { $0.handle != me }.enumerated().map { index, person in
            ChatBoardRow(name: person.handle, colorHex: person.colorHex, score: [58, 49, 37, 33, 29, 22, 12][index % 7], you: false)
        }
        rows.append(ChatBoardRow(name: me, colorHex: "FFC531", score: 41, you: true))
        return ChatBoard(gameID: game.id, rows: rows.sorted { $0.score > $1.score })
    }

    static func chats() -> [ChatThread] {
        let kaz = friend(1), devon = friend(0), noor = friend(2), juno = friend(4)
        var list: [ChatThread] = []

        let kazLines = [
            line(kaz, 52, "you up?"),
            line(nil, 50, "always. what are we playing"),
            line(kaz, 48, "Play Five Up with me", kind: .invite, game: "five-up"),
        ]
        list.append(ChatThread(id: "local-dm-kaz", kind: "direct", name: kaz.handle, icon: "", person: kaz, memberCount: 2,
                               preview: "Sent a game invite", at: ago(48), unread: true, messages: kazLines))

        let squad = [devon, kaz, noor, friend(3), juno, friend(5)]
        let squadLines = [
            line(kaz, 95, "demo is at six. who is still building"),
            line(friend(3), 90, "me. running on snacks"),
            line(devon, 62, "Beat it before the demo", kind: .score, game: "tippy-tower", score: 58),
            line(juno, 60, "58 floors is unreal"),
            line(noor, 24, "Quick round on the break?", kind: .invite, game: "lane-dash"),
            line(friend(5), 21, "in. last place gets coffee"),
        ]
        list.append(ChatThread(id: "local-group-squad", kind: "group", name: "Hackathon squad", icon: "hammer.fill",
                               members: squad, memberCount: 7, preview: "wordnerd.sam: in. last place gets coffee", at: ago(21),
                               unread: true, messages: squadLines, board: board(for: squad, game: Mock.tippyTower)))

        let devonLines = [
            line(devon, 130, "saw your tower. not bad"),
            line(nil, 128, "not bad? that was my best ever"),
            line(devon, 120, "I got 58 floors. Beat it?", kind: .score, game: "tippy-tower", score: 58),
        ]
        list.append(ChatThread(id: "local-dm-devon", kind: "direct", name: devon.handle, icon: "", person: devon, memberCount: 2,
                               preview: "Shared a score", at: ago(120), unread: false, messages: devonLines))

        let stanford = [kaz, juno, friend(5)]
        let stanfordLines = [
            line(kaz, 180, "library quiet floor Five Up tournament tonight?"),
            line(friend(5), 170, "Opening score", kind: .score, game: "five-up", score: 1385),
            line(juno, 150, "cs106 people are getting destroyed"),
        ]
        list.append(ChatThread(id: "local-work-stanford", kind: "workplace", name: "Stanford", icon: "graduationcap.fill",
                               domain: "stanford.edu", members: stanford, memberCount: 3,
                               preview: "juno: cs106 people are getting destroyed", at: ago(150), unread: false,
                               messages: stanfordLines, board: board(for: stanford, game: Mock.fiveUp)))

        let noorLines = [
            line(noor, 300, "the near miss at the end. I stopped breathing", kind: .post, game: "lane-dash"),
            line(noor, 299, "this clip is everything"),
            line(nil, 290, "how is that not a crash"),
        ]
        list.append(ChatThread(id: "local-dm-noor", kind: "direct", name: noor.handle, icon: "", person: noor, memberCount: 2,
                               preview: "You: how is that not a crash", at: ago(290), unread: false, messages: noorLines))

        let junoLines = [
            line(juno, 1500, "inkland later? I need revenge"),
            line(nil, 1490, "only if you stop cutting my trail"),
            line(juno, 1480, "no promises"),
        ]
        list.append(ChatThread(id: "local-dm-juno", kind: "direct", name: juno.handle, icon: "", person: juno, memberCount: 2,
                               preview: "no promises", at: ago(1480), unread: false, messages: junoLines))
        return list
    }

    static func workplaceName(_ domain: String) -> String {
        let known = ["stanford.edu": "Stanford", "meta.com": "Meta", "berkeley.edu": "Berkeley", "google.com": "Google", "mit.edu": "MIT"]
        if let name = known[domain] { return name }
        let label = domain.split(separator: ".").first.map(String.init) ?? domain
        return label.prefix(1).uppercased() + label.dropFirst()
    }
}
