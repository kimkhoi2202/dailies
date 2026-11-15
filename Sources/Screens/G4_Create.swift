import SwiftUI

// MAKING A GAME: a wish, a short talk with the studio, then the game. The studio is an OpenAI model
// behind a Convex action (convex/ai.ts). It shapes the wish onto one of the built-in engines, and the
// app plays the result like any other game. Nothing here is public: a made game stays with its maker.

/// The built-in engine a made game plays on, by the name the server stores.
enum G4Engine {
    /// "Tippy Tower" for "tippyTower": the shipped game that runs that engine.
    static func title(_ kind: String?) -> String {
        guard let kind, let engine = GameKind(rawValue: kind) else { return "an engine" }
        return Mock.games.first { $0.kind == engine }?.title ?? "an engine"
    }

    /// One word for where a creation stands, for lists.
    static func statusWord(_ creation: ConvexCreation) -> String {
        switch creation.status {
        case "building": return "Building"
        case "ready": return "Ready to play"
        case "failed": return "Needs another go"
        default: return creation.thinking ? "The studio is thinking" : "Wishing"
        }
    }

    /// Where a creation opens from a list: the talk while it is talking, the game once it is being built.
    static func route(_ creation: ConvexCreation) -> Route {
        creation.status == "building" || creation.status == "ready" ? .makePreview(creation.id) : .makeChat(creation.id)
    }
}

/// The bar at the bottom of the wish and talk screens: a growing text field with a round send button.
private struct G4Composer: View {
    @Binding var draft: String
    var placeholder = "Tap to wish"
    var enabled = true
    var send: () -> Void
    @FocusState private var typing: Bool

    var body: some View {
        let empty = draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        HStack(alignment: .bottom, spacing: 8) {
            TextField(placeholder, text: $draft, axis: .vertical)
                .font(DL.text(16)).foregroundStyle(DL.ink).tint(DL.ink)
                .lineLimit(1...4)
                .focused($typing)
                .submitLabel(.send)
                .onSubmit(send)
                .disabled(!enabled)
                .padding(.vertical, 8)
            Image(systemName: "arrow.up").font(.system(size: 15, weight: .bold))
                .foregroundStyle(empty || !enabled ? DL.ink3 : DL.onInk)
                .frame(width: 36, height: 36)
                .background(empty || !enabled ? DL.sunken : DL.ink, in: Circle())
                .tap { if !empty && enabled { send() } }
                .accessibilityLabel("Send")
                .padding(.bottom, 2)
        }
        .padding(.leading, 18).padding(.trailing, 8).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(DL.surface))
        .onTapGesture { typing = true }
    }
}

/// Three dots while the studio is thinking.
private struct G4Thinking: View {
    var body: some View {
        Image(systemName: "ellipsis")
            .font(.system(size: 22, weight: .bold))
            .foregroundStyle(DL.ink2)
            .symbolEffect(.variableColor.iterative, options: .repeating)
            .frame(height: 24)
            .accessibilityLabel("The studio is thinking")
    }
}

// MARK: The wish

struct G4CreateScreen: View {
    @ObservedObject private var store = LiveStore.shared
    @State private var draft = ""
    @State private var sending = false

    var body: some View {
        VStack(spacing: 0) {
            DLNavBar(title: "Studio", trailingSymbol: "xmark", showBack: false, trailingAction: { LiveNav.shared.closeFlow() })
            Spacer(minLength: 12)
            VStack(spacing: 18) {
                DLMonogram(size: 96)
                VStack(spacing: 2) {
                    ForEach(["What game", "would you make?"], id: \.self) { line in
                        Text(line.uppercased()).font(DL.display(40)).foregroundStyle(DL.ink).frame(height: 36)
                    }
                }
                Text("Say a theme, a feeling or a whole idea. The studio shapes it onto one of our engines.")
                    .font(DL.text(15))
                    .foregroundStyle(DL.ink2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 24)
                DLTextKey(title: sending ? "Opening" : "Inspire me", symbol: "sparkles")
                    .frame(width: 220)
                    .tap { begin("Inspire me") }
                    .padding(.top, 6)
            }
            Spacer(minLength: 12)
            HStack(spacing: 12) {
                DL.line.frame(height: 1)
                Text("OR").dlLabel(11)
                DL.line.frame(height: 1)
            }
            .padding(.bottom, 14)
            G4Composer(draft: $draft, enabled: !sending) { begin(draft) }
                .padding(.bottom, 8)
        }
        .padding(.horizontal, DL.margin)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DL.body.ignoresSafeArea())
    }

    /// Opens a creation with the first wish and goes to the talk.
    private func begin(_ text: String) {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, !sending else { return }
        sending = true
        Task { @MainActor in
            do {
                let id = try await store.startCreation(body)
                draft = ""
                LiveNav.shared.open(.makeChat(id))
            } catch {
                LiveNav.shared.say("The studio did not answer. Try again.")
            }
            sending = false
        }
    }
}

// MARK: The talk

struct G4CreateChatScreen: View {
    let creationID: String
    @ObservedObject private var store = LiveStore.shared
    @State private var draft = ""
    @State private var sending = false

    private var detail: ConvexCreationDetail? { store.creation(creationID) }

    /// The maker can answer while the studio is listening and the game is not yet built.
    private var canSend: Bool {
        guard let detail else { return false }
        return detail.status == "talking" && !detail.thinking && !sending
    }

    var body: some View {
        VStack(spacing: 0) {
            DLNavBar(title: "Studio", trailingSymbol: "xmark", trailingAction: { LiveNav.shared.closeFlow() })
                .padding(.horizontal, DL.margin)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        if let detail {
                            ForEach(detail.messages) { message in
                                row(message, last: message.id == detail.messages.last?.id, detail: detail)
                            }
                            if detail.thinking { G4Thinking() }
                            if detail.status == "failed" { failed(detail) }
                            if detail.status == "building" || detail.status == "ready" { built(detail) }
                        } else {
                            G4Thinking()
                        }
                        Color.clear.frame(height: 1).id("end")
                    }
                    .padding(.horizontal, DL.margin)
                    .padding(.top, 14)
                    .padding(.bottom, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: detail?.messages.count) { scrollToEnd(proxy) }
                .onChange(of: detail?.thinking) { scrollToEnd(proxy) }
                .onChange(of: detail?.status) { _, status in
                    if status == "building" { LiveNav.shared.open(.makePreview(creationID)) }
                }
            }
            if detail?.status == "talking" || detail?.status == "failed" || detail == nil {
                G4Composer(draft: $draft, enabled: canSend) { send(draft) }
                    .padding(.horizontal, DL.margin)
                    .padding(.bottom, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DL.body.ignoresSafeArea())
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        withAnimation(.snappy(duration: 0.3)) { proxy.scrollTo("end", anchor: .bottom) }
    }

    @ViewBuilder private func row(_ message: ConvexCreationMessage, last: Bool, detail: ConvexCreationDetail) -> some View {
        if message.role == "maker" {
            Text(message.text)
                .font(DL.text(16)).foregroundStyle(DL.ink)
                .padding(.horizontal, 16).padding(.vertical, 11)
                .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(DL.surface))
                .frame(maxWidth: 290, alignment: .trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text(message.text)
                    .font(DL.text(17)).foregroundStyle(DL.ink)
                    .fixedSize(horizontal: false, vertical: true)
                // Choices and ideas can only be taken from the studio's latest line.
                if last && detail.status == "talking" {
                    ForEach(message.options, id: \.self) { option in
                        choice(option).tap { send(option) }
                    }
                    ForEach(message.ideas.indices, id: \.self) { index in
                        idea(message.ideas[index])
                    }
                    if !message.options.isEmpty || !message.ideas.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.2.squarepath").font(.system(size: 14, weight: .bold))
                            Text("More options").font(DL.text(15, .semibold))
                        }
                        .foregroundStyle(DL.ink2)
                        .padding(.horizontal, 18)
                        .frame(height: 44)
                        .background(Capsule().fill(DL.surface))
                        .tap { send("More options") }
                    }
                }
            }
        }
    }

    /// One answer the maker can tap instead of typing.
    private func choice(_ text: String) -> some View {
        Text(text)
            .font(DL.text(16, .semibold)).foregroundStyle(DL.ink)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 18).padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(Capsule().strokeBorder(DL.ink, lineWidth: 2))
    }

    /// A game the studio suggests. The arrow asks for it to be built.
    private func idea(_ idea: ConvexCreationMessage.Idea) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(idea.title.uppercased()).font(DL.display(30)).foregroundStyle(DL.ink).frame(height: 28)
            Text(idea.pitch)
                .font(DL.text(15)).foregroundStyle(DL.ink2)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Image(systemName: "arrow.down").font(.system(size: 16, weight: .black))
                    .foregroundStyle(DL.onInk)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(DL.ink))
                Spacer()
            }
            .padding(.top, 2)
        }
        .dlCard(padding: 16)
        .tap { send("Make \(idea.title). \(idea.pitch)") }
    }

    private func failed(_ detail: ConvexCreationDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("The studio lost its thread.").font(DL.text(16, .semibold)).foregroundStyle(DL.ink)
            if let error = detail.error {
                Text(error).font(DL.text(13)).foregroundStyle(DL.ink2).lineLimit(3)
            }
            DLTextKey(title: "Try again", style: .ink)
                .tap {
                    Task { @MainActor in try? await store.retryCreation(creationID) }
                }
        }
        .dlCard(padding: 16)
    }

    private func built(_ detail: ConvexCreationDetail) -> some View {
        DLTextKey(title: detail.status == "ready" ? "Open the game" : "Watch it being built", symbol: "arrow.right")
            .opens(.makePreview(creationID))
            .padding(.top, 4)
    }

    private func send(_ text: String) {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, canSend else { return }
        sending = true
        draft = ""
        Task { @MainActor in
            do {
                try await store.sendWish(body, to: creationID)
            } catch {
                draft = body
                LiveNav.shared.say("That did not reach the studio. Try again.")
            }
            sending = false
        }
    }
}

// MARK: The game

struct G4CreatePreviewScreen: View {
    let creationID: String
    @ObservedObject private var store = LiveStore.shared
    @ObservedObject private var nav = LiveNav.shared
    @State private var breathing = false

    private var detail: ConvexCreationDetail? { store.creation(creationID) }
    private var status: String { detail?.status ?? "building" }
    private var made: MockGame? { detail?.gameSlug.flatMap { store.madeGame($0) } }

    var body: some View {
        VStack(spacing: 0) {
            DLNavBar(title: detail?.title ?? "New game", trailingSymbol: "xmark", trailingAction: { LiveNav.shared.closeFlow() })
                .padding(.horizontal, DL.margin)
            if status == "ready", let made {
                preview(made)
            } else if status == "failed" {
                failed
            } else {
                progress
            }
            bottomBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DL.body.ignoresSafeArea())
    }

    // MARK: Being built

    private var progress: some View {
        ScrollView {
            VStack(spacing: 0) {
                DLMonogram(size: 112)
                    .scaleEffect(breathing ? 1.06 : 0.96)
                    .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: breathing)
                    .onAppear { breathing = true }
                    .padding(.top, 28)
                Text("BUILDING YOUR GAME").font(DL.display(34)).foregroundStyle(DL.ink).padding(.top, 22)
                Text(progressLine)
                    .font(DL.text(15)).foregroundStyle(DL.ink2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 24)
                    .padding(.top, 6)
                Text("While you wait").dlLabel(11).padding(.top, 30).padding(.bottom, 10)
                VStack(spacing: 10) {
                    waitCard("coin", "How gold is collected", "About a gold a minute, up to 100 a day in one game")
                        .opens(.fairness(Mock.tippyTower.id))
                    waitCard("checkmark.seal.fill", "What the review checks", "Every game is played 240 times before it goes live")
                        .opens(.reviewResult)
                    waitCard("clock", "Your gold today", "See what today's play came to")
                        .opens(.gold)
                }
            }
            .padding(.horizontal, DL.margin)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
    }

    private var progressLine: String {
        guard let detail, let title = detail.title else { return "The studio is settling the design." }
        return "\(title) is being laid out on the \(G4Engine.title(detail.kind)) engine."
    }

    private func waitCard(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if symbol == "coin" {
                DLCoin(size: 20).padding(.top, 1)
            } else {
                Image(systemName: symbol).font(.system(size: 17, weight: .semibold)).foregroundStyle(DL.ink).frame(width: 22)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(DL.text(16, .semibold)).foregroundStyle(DL.ink)
                Text(detail).font(DL.text(13)).foregroundStyle(DL.ink2).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(DL.ink2)
        }
        .dlCard(padding: 16)
    }

    // MARK: Ready

    private func preview(_ made: MockGame) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ClipStill(game: made, phase: 0.5, showHUD: false, focusY: 0.2)
                    .overlay(alignment: .bottomLeading) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(made.title.uppercased())
                                .font(DL.display(38)).foregroundStyle(.white)
                                .lineLimit(1).minimumScaleFactor(0.6)
                            Text(made.tagline).font(DL.text(15, .medium)).foregroundStyle(.white.opacity(0.9))
                        }
                        .padding(18)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        .background(LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom))
                    }
                    .frame(height: 300)
                    .clipShape(RoundedRectangle(cornerRadius: DL.cardRadius, style: .continuous))
                    .padding(.top, 8)
                HStack(spacing: 8) {
                    DLTag(text: made.category)
                    DLTag(text: "Plays like \(G4Engine.title(detail?.kind))")
                    DLTag(text: "Private", symbol: "eye.slash")
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("How to play").dlLabel(10.5)
                    Text(detail?.how ?? "")
                        .font(DL.text(15)).foregroundStyle(DL.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .dlCard(padding: 16)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Who can play it").dlLabel(10.5)
                    Text("Only you, for now. Publishing sends it to the review, and gold starts once the review is done.")
                        .font(DL.text(15)).foregroundStyle(DL.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .dlCard(padding: 16)
                DLPlayKey(trailing: "ALONE, NO GOLD YET")
                    .opens(.play(made.id, solo: true))
                    .padding(.top, 4)
            }
            .padding(.horizontal, DL.margin)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
    }

    private var failed: some View {
        VStack(spacing: 14) {
            Spacer()
            Text("The studio lost its thread.").font(DL.text(17, .semibold)).foregroundStyle(DL.ink)
            Text(detail?.error ?? "Something went wrong on the way to an answer.")
                .font(DL.text(14)).foregroundStyle(DL.ink2)
                .multilineTextAlignment(.center)
                .lineLimit(4)
            DLTextKey(title: "Try again", style: .ink)
                .frame(width: 200)
                .tap {
                    Task { @MainActor in try? await store.retryCreation(creationID) }
                    LiveNav.shared.replaceTop(.makeChat(creationID))
                }
            Spacer()
        }
        .padding(.horizontal, DL.margin)
    }

    // MARK: The bar

    /// Back to the wish, the two sides of a creation, and a way to throw it away.
    private var bottomBar: some View {
        HStack(spacing: 10) {
            DLIconButton(symbol: "arrow.counterclockwise")
                .tap {
                    LiveNav.shared.closeFlow()
                    LiveNav.shared.open(.makeGame)
                }
                .accessibilityLabel("Start another")
            HStack(spacing: 0) {
                Text("Wish")
                    .font(DL.text(14, .semibold)).foregroundStyle(DL.ink2)
                    .frame(maxWidth: .infinity).frame(height: 34)
                    .contentShape(Rectangle())
                    .tap(showWish)
                Text("Preview")
                    .font(DL.text(14, .semibold)).foregroundStyle(DL.onInk)
                    .frame(maxWidth: .infinity).frame(height: 34)
                    .background(Capsule().fill(DL.ink))
            }
            .padding(3)
            .background(Capsule().fill(DL.surface))
            DLIconButton(symbol: "trash")
                .tap {
                    store.removeCreation(creationID)
                    LiveNav.shared.closeFlow()
                }
                .accessibilityLabel("Throw away")
        }
        .padding(.horizontal, DL.margin)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    /// The talk is usually the screen under this one. If it is not, it opens on top.
    private func showWish() {
        if case .makeChat(let id)? = nav.layers.dropLast().last?.route, id == creationID {
            LiveNav.shared.back()
        } else {
            LiveNav.shared.open(.makeChat(creationID))
        }
    }
}
