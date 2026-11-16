import SwiftUI

// DESIGNING A GAME: a first line, a short back and forth with the studio, and a design sheet that
// fills in as they talk. The studio is an OpenAI model behind a Convex action (convex/ai.ts). It asks
// one question at a time, offers ideas when the maker has none, and settles one part of the sheet
// after another. The sheet is the plan for a game; nothing is built from it in the app.

enum G4Sheet {
    /// One word for where a design stands, for lists.
    static func statusWord(_ creation: ConvexCreation) -> String {
        switch creation.status {
        case "ready": return "Sheet complete"
        case "failed": return "Needs another go"
        default: return creation.thinking ? "The studio is thinking" : "\(Int((creation.progress * 100).rounded()))% settled"
        }
    }

    /// Where a design opens from a list: the finished sheet, else the talk.
    static func route(_ creation: ConvexCreation) -> Route {
        creation.status == "ready" ? .makePreview(creation.id) : .makeChat(creation.id)
    }

    /// The parts of the sheet in the order they read, with their labels. Empty parts are left out.
    static func parts(_ design: ConvexDesign) -> [(label: String, text: String)] {
        let single: [(String, String?)] = [
            ("Genre", design.genre), ("Setting", design.setting), ("You play", design.player), ("The goal", design.goal),
            ("Controls", design.controls), ("Scoring", design.scoring), ("Over a round", design.progression),
            ("The look", design.look), ("Sound", design.sound),
        ]
        var rows: [(String, String)] = []
        for (label, text) in single {
            if let text, !text.isEmpty { rows.append((label, text)) }
        }
        if let rules = design.rules, !rules.isEmpty {
            rows.insert(("Rules", rules.map { "- " + $0 }.joined(separator: "\n")), at: min(5, rows.count))
        }
        return rows
    }
}

/// The bar at the bottom of the talk: a growing text field with a round send button.
private struct G4Composer: View {
    @Binding var draft: String
    var placeholder = "Describe your game"
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

// MARK: The first line

struct G4CreateScreen: View {
    @ObservedObject private var store = LiveStore.shared
    @State private var draft = ""
    @State private var sending = false

    private let starters = ["A game about my cat", "Something I can play one handed", "Puzzles, but fast", "A boss fight in 60 seconds"]

    var body: some View {
        VStack(spacing: 0) {
            DLNavBar(title: "Studio", trailingSymbol: "xmark", showBack: false, trailingAction: { LiveNav.shared.closeFlow() })
            Spacer(minLength: 12)
            VStack(spacing: 18) {
                DLMonogram(size: 96)
                VStack(spacing: 2) {
                    ForEach(["Design a game", "with the studio"], id: \.self) { line in
                        Text(line.uppercased()).font(DL.display(40)).foregroundStyle(DL.ink).frame(height: 36)
                    }
                }
                Text("Bring a word, a feeling or a whole idea. The studio asks a few questions and writes the design sheet with you.")
                    .font(DL.text(15))
                    .foregroundStyle(DL.ink2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 24)
                DLTextKey(title: sending ? "Opening" : "Surprise me", symbol: "wand.and.stars")
                    .frame(width: 220)
                    .tap { begin("Surprise me. I have no idea yet.") }
                    .padding(.top, 6)
            }
            Spacer(minLength: 12)
            VStack(alignment: .leading, spacing: 8) {
                Text("Or start from one of these").dlLabel(10.5).padding(.leading, 4)
                ForEach(starters, id: \.self) { line in
                    HStack {
                        Text(line).font(DL.text(15, .medium)).foregroundStyle(DL.ink)
                        Spacer()
                        Image(systemName: "arrow.up.right").font(.system(size: 12, weight: .bold)).foregroundStyle(DL.ink3)
                    }
                    .padding(.horizontal, 16).frame(height: 44)
                    .background(Capsule().fill(DL.surface))
                    .tap { begin(line) }
                }
            }
            .padding(.bottom, 14)
            G4Composer(draft: $draft, enabled: !sending) { begin(draft) }
                .padding(.bottom, 8)
        }
        .padding(.horizontal, DL.margin)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DL.body.ignoresSafeArea())
    }

    /// Opens a design with the first line and goes to the talk.
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
                LiveNav.shared.say("The studio did not pick up. Try again.")
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

    /// The maker can answer whenever the studio is not in the middle of a reply.
    private var canSend: Bool {
        guard let detail else { return false }
        return !detail.thinking && !sending
    }

    var body: some View {
        VStack(spacing: 0) {
            DLNavBar(title: detail?.design?.title ?? "Studio", trailingSymbol: "xmark", trailingAction: { LiveNav.shared.closeFlow() })
                .padding(.horizontal, DL.margin)
            if let detail { sheetStrip(detail) }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        if let detail {
                            ForEach(detail.messages) { message in
                                row(message, last: message.id == detail.messages.last?.id, detail: detail)
                            }
                            if detail.thinking { G4Thinking() }
                            if detail.status == "failed" { failed(detail) }
                            if detail.status == "ready" {
                                DLTextKey(title: "Read the sheet", symbol: "doc.text").opens(.makePreview(creationID)).padding(.top, 4)
                            }
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
                    if status == "ready" { LiveNav.shared.open(.makePreview(creationID)) }
                }
            }
            G4Composer(draft: $draft, placeholder: detail?.status == "ready" ? "Change something" : "Describe your game", enabled: canSend) { send(draft) }
                .padding(.horizontal, DL.margin)
                .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DL.body.ignoresSafeArea())
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        withAnimation(.snappy(duration: 0.3)) { proxy.scrollTo("end", anchor: .bottom) }
    }

    /// How far the sheet has come, with a way to it. Tapping opens the sheet as it stands.
    private func sheetStrip(_ detail: ConvexCreationDetail) -> some View {
        let settled = detail.design.map { G4Sheet.parts($0).count } ?? 0
        return HStack(spacing: 10) {
            DLRing(progress: detail.progress, size: 26, line: 4, showTick: true)
            VStack(alignment: .leading, spacing: 1) {
                Text(detail.status == "ready" ? "Sheet complete" : "Design sheet").font(DL.text(14, .semibold)).foregroundStyle(DL.ink)
                Text(settled == 0 ? "Nothing settled yet" : "\(settled) of 10 parts settled").font(DL.text(12)).foregroundStyle(DL.ink2)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(DL.ink2)
        }
        .padding(.horizontal, 14).frame(height: 50)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(DL.surface))
        .padding(.horizontal, DL.margin)
        .padding(.top, 6)
        .opens(.makePreview(creationID))
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
                // Answers and ideas can only be taken from the studio's latest line.
                if last && detail.status == "talking" && !detail.thinking {
                    ForEach(message.options, id: \.self) { option in
                        answer(option).tap { send(option) }
                    }
                    ForEach(message.ideas.indices, id: \.self) { index in
                        idea(message.ideas[index])
                    }
                    if !message.options.isEmpty || !message.ideas.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "shuffle").font(.system(size: 14, weight: .bold))
                            Text(message.ideas.isEmpty ? "Other answers" : "Different ideas").font(DL.text(15, .semibold))
                        }
                        .foregroundStyle(DL.ink2)
                        .padding(.horizontal, 18)
                        .frame(height: 44)
                        .background(Capsule().fill(DL.surface))
                        .tap { send(message.ideas.isEmpty ? "Give me other answers to that." : "Show me three different ideas.") }
                    }
                }
            }
        }
    }

    /// One answer the maker can tap instead of typing.
    private func answer(_ text: String) -> some View {
        Text(text)
            .font(DL.text(16, .semibold)).foregroundStyle(DL.ink)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 18).padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(Capsule().strokeBorder(DL.ink, lineWidth: 2))
    }

    /// A game the studio suggests. Tapping it takes the idea on.
    private func idea(_ idea: ConvexCreationMessage.Idea) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(idea.title.uppercased()).font(DL.display(28)).foregroundStyle(DL.ink).frame(height: 26)
                Text(idea.pitch)
                    .font(DL.text(15)).foregroundStyle(DL.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Image(systemName: "arrow.right").font(.system(size: 15, weight: .black))
                .foregroundStyle(DL.onInk)
                .frame(width: 38, height: 38)
                .background(Circle().fill(DL.ink))
        }
        .dlCard(padding: 16)
        .tap { send("Let us go with \(idea.title): \(idea.pitch)") }
    }

    private func failed(_ detail: ConvexCreationDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("The studio lost the thread.").font(DL.text(16, .semibold)).foregroundStyle(DL.ink)
            if let error = detail.error {
                Text(error).font(DL.text(13)).foregroundStyle(DL.ink2).lineLimit(3)
            }
            DLTextKey(title: "Ask again", style: .ink)
                .tap {
                    Task { @MainActor in try? await store.retryCreation(creationID) }
                }
        }
        .dlCard(padding: 16)
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

// MARK: The sheet

struct G4CreatePreviewScreen: View {
    let creationID: String
    @ObservedObject private var store = LiveStore.shared
    @ObservedObject private var nav = LiveNav.shared
    @State private var finishing = false

    private var detail: ConvexCreationDetail? { store.creation(creationID) }
    private var design: ConvexDesign { detail?.design ?? ConvexDesign() }
    private var ready: Bool { detail?.status == "ready" }

    var body: some View {
        VStack(spacing: 0) {
            DLNavBar(title: ready ? "Design sheet" : "Sheet so far", trailingSymbol: "xmark", trailingAction: { LiveNav.shared.closeFlow() })
                .padding(.horizontal, DL.margin)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    cover
                    if let detail, !ready { standing(detail) }
                    ForEach(G4Sheet.parts(design), id: \.label) { part in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(part.label).dlLabel(10.5)
                            Text(part.text)
                                .font(DL.text(15)).foregroundStyle(DL.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .dlCard(padding: 16)
                    }
                    if ready {
                        Text("This sheet is the plan for your game. Share it, or keep talking to change any part of it.")
                            .font(DL.text(13)).foregroundStyle(DL.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 4)
                        DLTextKey(title: "Share the sheet", symbol: "square.and.arrow.up", style: .ink)
                            .tap { LiveNav.shared.share(shareText) }
                    }
                }
                .padding(.horizontal, DL.margin)
                .padding(.top, 8)
                .padding(.bottom, 20)
            }
            .scrollIndicators(.hidden)
            bottomBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DL.body.ignoresSafeArea())
    }

    /// The title and pitch on the game's own colour.
    private var cover: some View {
        let tint = Color(hex: design.tint ?? "F5B301")
        return VStack(alignment: .leading, spacing: 6) {
            Spacer(minLength: 0)
            Text((design.title ?? "Untitled").uppercased())
                .font(DL.display(42)).foregroundStyle(.white)
                .lineLimit(2).minimumScaleFactor(0.6)
            Text(design.pitch ?? (ready ? "" : "The pitch comes once the idea is settled."))
                .font(DL.text(15, .medium)).foregroundStyle(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
            if let genre = design.genre, !genre.isEmpty {
                DLMediaTag(text: genre).padding(.top, 6)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 220, alignment: .bottomLeading)
        .background(
            LinearGradient(colors: [tint.opacity(0.85), tint.opacity(0.55), Color.black.opacity(0.7)], startPoint: .top, endPoint: .bottom)
                .background(tint)
        )
        .clipShape(RoundedRectangle(cornerRadius: DL.cardRadius, style: .continuous))
    }

    /// While the talk is on: how much is settled and the key that finishes the sheet.
    private func standing(_ detail: ConvexCreationDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 6) {
                Text("Settled so far").dlLabel(10.5)
                Spacer()
                Text("\(Int((detail.progress * 100).rounded()))%").font(DL.display(28)).foregroundStyle(DL.ink)
            }
            .frame(height: 24)
            DLMeter(value: detail.progress, total: 1, height: 8)
            Text(detail.thinking ? "The studio is writing the next part." : "Keep answering the studio, or finish the sheet with what is here.")
                .font(DL.text(13)).foregroundStyle(DL.ink2)
                .fixedSize(horizontal: false, vertical: true)
            if !detail.thinking && detail.status == "talking" && detail.progress >= 0.5 {
                DLTextKey(title: finishing ? "Writing it up" : "Finish the sheet", symbol: "checkmark", style: .ink)
                    .tap {
                        guard !finishing else { return }
                        finishing = true
                        Task { @MainActor in
                            try? await store.finishCreation(creationID)
                            finishing = false
                        }
                    }
            }
        }
        .dlCard(padding: 14)
    }

    private var shareText: String {
        var lines = [(design.title ?? "Untitled").uppercased(), design.pitch ?? "", ""]
        for part in G4Sheet.parts(design) { lines.append("\(part.label): \(part.text)") }
        lines.append("")
        lines.append("Designed in the DEGEN studio")
        return lines.joined(separator: "\n")
    }

    // MARK: The bar

    /// Start over, the two sides of a design, and a way to throw it away.
    private var bottomBar: some View {
        HStack(spacing: 10) {
            DLIconButton(symbol: "plus")
                .tap {
                    LiveNav.shared.closeFlow()
                    LiveNav.shared.open(.makeGame)
                }
                .accessibilityLabel("Start another")
            HStack(spacing: 0) {
                Text("Talk")
                    .font(DL.text(14, .semibold)).foregroundStyle(DL.ink2)
                    .frame(maxWidth: .infinity).frame(height: 34)
                    .contentShape(Rectangle())
                    .tap(showTalk)
                Text("Sheet")
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
    private func showTalk() {
        if case .makeChat(let id)? = nav.layers.dropLast().last?.route, id == creationID {
            LiveNav.shared.back()
        } else {
            LiveNav.shared.open(.makeChat(creationID))
        }
    }
}
