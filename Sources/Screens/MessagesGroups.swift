import SwiftUI

// GROUPS: make a group with friends, join your workplace or school by email domain, and the Play together sheet.

struct MessagesNewGroupScreen: View {
    @ObservedObject private var social = MessagesStore.shared
    @State private var name = ""
    @State private var icon = "gamecontroller.fill"
    @State private var picked: Set<String> = []
    @State private var making = false

    private let icons = ["gamecontroller.fill", "hammer.fill", "flame.fill", "bolt.fill", "star.fill", "music.note", "cup.and.saucer.fill", "moon.fill"]

    private var ready: Bool { name.trimmingCharacters(in: .whitespaces).count >= 2 && !picked.isEmpty && !making }

    var body: some View {
        DLPage(spacing: 14) {
            DLNavBar(title: "New group")
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .bold)).foregroundStyle(DL.onGold)
                    .frame(width: 60, height: 60)
                    .background(RoundedRectangle(cornerRadius: 19, style: .continuous).fill(DL.gold))
                    .background(RoundedRectangle(cornerRadius: 19, style: .continuous).fill(DL.goldLip).offset(y: 4))
                TextField("Group name", text: $name)
                    .font(DL.display(30)).foregroundStyle(DL.ink)
                    .padding(.horizontal, 16).frame(height: 60)
                    .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(DL.surface))
            }
            Text("Pick a symbol").dlLabel(10.5)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                ForEach(icons, id: \.self) { symbol in
                    let chosen = symbol == icon
                    Image(systemName: symbol)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(chosen ? DL.onGold : DL.ink)
                        .frame(maxWidth: .infinity).frame(height: 52)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(chosen ? DL.gold : DL.surface))
                        .tap { icon = symbol }
                }
            }
            Text("Friends, \(picked.count) picked").dlLabel(10.5).padding(.top, 4)
            VStack(spacing: 0) {
                ForEach(Array(social.friends.enumerated()), id: \.element.id) { index, friend in
                    if index > 0 { DLDivider(inset: 58) }
                    DLRow(title: friend.handle, detail: friend.online ? "Online now" : friend.bio) {
                        MessagesAvatar(person: friend, size: 44)
                    } trailing: {
                        let on = picked.contains(friend.handle)
                        Image(systemName: on ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(on ? DL.goldText : DL.ink3)
                    }
                    .contentShape(Rectangle())
                    .tap {
                        if picked.contains(friend.handle) { picked.remove(friend.handle) } else { picked.insert(friend.handle) }
                    }
                }
            }
            .padding(.horizontal, 14)
            .dlCard(padding: 0)
            DLTextKey(title: "Make group", symbol: "person.3.fill", style: ready ? .gold : .neutral)
                .tap(make)
                .opacity(ready ? 1 : 0.6)
                .padding(.top, 4)
        }
    }

    private func make() {
        guard ready else {
            LiveNav.shared.say(picked.isEmpty ? "Pick at least one friend" : "Give the group a name")
            return
        }
        making = true
        let clean = name.trimmingCharacters(in: .whitespaces)
        Task { @MainActor in
            let id = await social.createGroup(name: clean, icon: icon, handles: Array(picked))
            GameHaptics.success()
            LiveNav.shared.replaceTop(.chat(id))
        }
    }
}

/// Join by work or school email. A 6 digit code is sent; for the demo it is shown on screen.
struct MessagesWorkplaceScreen: View {
    @ObservedObject private var social = MessagesStore.shared
    @State private var email = ""
    @State private var sent: ConvexWorkplaceCode?
    @State private var code = ""
    @State private var problem: String?
    @State private var busy = false
    @FocusState private var codeFocused: Bool

    var body: some View {
        DLPage(spacing: 14) {
            DLNavBar(title: "Work or school")
            VStack(alignment: .leading, spacing: 6) {
                Text("PLAY WITH YOUR PEOPLE").font(DL.display(38)).foregroundStyle(DL.ink)
                Text("Everyone with the same email domain lands in one group, like @stanford.edu or @meta.com.")
                    .font(DL.text(15)).foregroundStyle(DL.ink2)
            }
            if let sent {
                codeStep(sent)
            } else {
                emailStep
            }
            if let problem {
                Text(problem).font(DL.text(14, .semibold)).foregroundStyle(DL.danger)
            }
        }
    }

    private var emailStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "envelope.fill").foregroundStyle(DL.ink2)
                TextField(text: $email, prompt: Text(verbatim: "you@stanford.edu").foregroundStyle(DL.ink3)) { Text("Email") }
                    .font(DL.text(17)).foregroundStyle(DL.ink)
                    .keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
            }
            .padding(.horizontal, 16).frame(height: 56)
            .background(Capsule().fill(DL.surface))
            DLTextKey(title: busy ? "Sending" : "Send my code", symbol: "paperplane.fill").tap(request)
            Text("We only use the part after the @. Personal email addresses do not count.")
                .font(DL.text(13)).foregroundStyle(DL.ink3)
        }
    }

    private func codeStep(_ sent: ConvexWorkplaceCode) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                G2SymbolTile(symbol: "building.2.fill", size: 44, tint: DL.goldText)
                VStack(alignment: .leading, spacing: 1) {
                    Text(sent.name).font(DL.text(17, .semibold)).foregroundStyle(DL.ink)
                    Text("@" + sent.domain).dlLabel(10.5)
                }
            }
            .dlCard(padding: 12)
            Text("Enter the 6 digit code we sent to \(email.lowercased())").font(DL.text(15)).foregroundStyle(DL.ink2)
            ZStack {
                HStack(spacing: 8) {
                    ForEach(0..<6, id: \.self) { index in
                        let digits = Array(code)
                        Text(index < digits.count ? String(digits[index]) : "")
                            .font(DL.display(34)).foregroundStyle(DL.ink)
                            .frame(maxWidth: .infinity).frame(height: 62)
                            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(DL.surface))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(index == digits.count ? DL.gold : DL.line, lineWidth: index == digits.count ? 2 : 1))
                    }
                }
                TextField("", text: $code)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .focused($codeFocused)
                    .foregroundStyle(.clear).tint(.clear)
                    .frame(height: 62)
                    .onChange(of: code) { _, value in
                        let digits = String(value.filter(\.isNumber).prefix(6))
                        if digits != value { code = digits }
                        if digits.count == 6 { verify() }
                    }
            }
            .onAppear { codeFocused = true }
            HStack(spacing: 8) {
                Text("Demo code").dlLabel(10.5)
                Text(sent.demoCode).font(DL.label(15)).foregroundStyle(DL.goldText)
                Spacer()
                Text("Fill it in").font(DL.text(14, .semibold)).foregroundStyle(DL.ink)
                    .tap { code = sent.demoCode }
            }
            .padding(.horizontal, 14).frame(height: 46)
            .background(Capsule().fill(DL.goldWash))
            DLTextKey(title: busy ? "Checking" : "Join \(sent.name)", symbol: "checkmark").tap(verify)
        }
    }

    private func request() {
        guard !busy else { return }
        busy = true
        problem = nil
        Task { @MainActor in
            let answer = await social.requestWorkplaceCode(email)
            busy = false
            switch answer {
            case .success(let value): withAnimation(.snappy) { sent = value }
            case .failure(let reason): problem = reason.text
            }
        }
    }

    private func verify() {
        guard !busy, code.count == 6 else { return }
        busy = true
        problem = nil
        Task { @MainActor in
            let answer = await social.verifyWorkplaceCode(code)
            busy = false
            switch answer {
            case .success(let id):
                GameHaptics.success()
                LiveNav.shared.replaceTop(.chat(id))
                LiveNav.shared.say("You are in. Say hi.")
            case .failure(let reason):
                GameHaptics.heavy()
                problem = reason.text
                code = ""
            }
        }
    }
}

/// Pick a game: Play together posts an invite into the chat and opens the lobby. A best score can be shared too.
struct MessagesPlayTogetherSheet: View {
    var chatID: String
    @ObservedObject private var social = MessagesStore.shared
    @ObservedObject private var live = LiveStore.shared

    var body: some View {
        DLSheet(height: 560) {
            EmptyView()
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("PLAY TOGETHER").font(DL.display(34)).foregroundStyle(DL.ink)
                    Spacer()
                }
                Text("Pick a game. Everyone in the chat gets the invite.").font(DL.text(14)).foregroundStyle(DL.ink2)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                    ForEach(Mock.games) { game in
                        VStack(spacing: 6) {
                            DLThumb(game: game, size: 96, radius: 22)
                            Text(game.title).font(DL.text(13, .semibold)).foregroundStyle(DL.ink).lineLimit(1)
                        }
                        .tap { invite(game) }
                    }
                }
                if let best = bestGame {
                    HStack(spacing: 10) {
                        DLThumb(game: best.game, size: 40)
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Share your best").font(DL.text(15, .semibold)).foregroundStyle(DL.ink)
                            Text("\(best.text) in \(best.game.title)").dlLabel(10)
                        }
                        Spacer()
                        Text("SHARE").font(DL.display(18)).foregroundStyle(DL.ink)
                            .padding(.horizontal, 14).frame(height: 36)
                            .background(Capsule().fill(DL.surface))
                    }
                    .dlCard(padding: 10, fill: DL.body, radius: 20)
                    .tap { shareBest(best) }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private var bestGame: (game: MockGame, score: Int, text: String)? {
        if let entry = live.s.best.max(by: { $0.value < $1.value }) {
            let game = Mock.game(entry.key)
            let unit = live.s.bestUnit[entry.key] ?? ""
            return (game, entry.value, (live.s.bestText[entry.key] ?? groupedNumber(entry.value)) + (unit.isEmpty ? "" : " " + unit))
        }
        return (Mock.tippyTower, 41, "41 floors")
    }

    private func invite(_ game: MockGame) {
        social.playTogether(game, in: chatID)
        LiveNav.shared.back()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { LiveNav.shared.open(.gameReady(game.id)) }
    }

    private func shareBest(_ best: (game: MockGame, score: Int, text: String)) {
        social.share(kind: .score, game: best.game, body: "I got \(best.text). Beat it?", score: best.score, to: chatID)
        LiveNav.shared.back()
    }
}
