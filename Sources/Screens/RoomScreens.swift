import SwiftUI
import Combine
import ConvexMobile

// Rooms: friends play the same round of one game together, live. A room has a 4 letter code.
// Start one from the Library by picking a game, or join one with a friend's code.

/// The room round being played, so the play screen uses the room's level and sends the score back.
enum LiveRoomRound {
    static var current: (code: String, round: Int, gameID: String, seed: UInt64)?

    static func report(_ score: Int) {
        guard let room = current else { return }
        current = nil
        let args: [String: ConvexEncodable?] = ["code": room.code, "round": Double(room.round), "score": Double(score), "done": true]
        Task { try? await ConvexLink.shared.mutate("rooms:score", args) }
    }

    /// The server's words for a failed room call, or a plain line when the server was not reached.
    static func message(for error: Error) -> String {
        if let failure = error as? ClientError, case .ConvexError(let data) = failure {
            return data.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }
        return "Could not reach the server. Try again."
    }
}

/// Type a friend's code to join their room.
struct JoinRoomSheet: View {
    @State private var code = ""
    @State private var problem: String?
    @State private var joining = false
    @FocusState private var typing: Bool

    var body: some View {
        DLSheet(height: 380) {
            EmptyView()
        } content: {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("JOIN A ROOM").font(DL.display(34)).foregroundStyle(DL.ink)
                    Spacer()
                    DLIconButton(symbol: "xmark", size: 32).goesBack().accessibilityLabel("Close")
                }
                Text("Type the 4 letter code your friend sees in their room.")
                    .font(DL.text(15)).foregroundStyle(DL.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                TextField("CODE", text: $code)
                    .font(DL.display(44)).tracking(10).multilineTextAlignment(.center)
                    .foregroundStyle(DL.ink).tint(DL.ink)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .focused($typing)
                    .submitLabel(.join)
                    .onSubmit(join)
                    .onChange(of: code) { _, value in
                        let clean = String(value.uppercased().filter(\.isLetter).prefix(4))
                        if clean != value { code = clean }
                        problem = nil
                    }
                    .frame(height: 70)
                    .background(DL.body, in: RoundedRectangle(cornerRadius: DL.tileRadius, style: .continuous))
                Text(problem ?? " ").font(DL.text(14, .medium)).foregroundStyle(DL.danger)
                DLTextKey(title: joining ? "Joining" : "Join").tap(join)
                    .opacity(code.count == 4 ? 1 : 0.5)
            }
            .padding(.horizontal, 20)
        }
        .onAppear { typing = true }
    }

    private func join() {
        guard code.count == 4, !joining else { return }
        joining = true
        let typed = code
        Task { @MainActor in
            do {
                let joined = try await ConvexLink.shared.mutate("rooms:join", ["code": typed], as: String.self)
                if LiveStore.shared.s.haptics { UINotificationFeedbackGenerator().notificationOccurred(.success) }
                LiveNav.shared.replaceTop(.room(joined))
            } catch {
                problem = LiveRoomRound.message(for: error)
            }
            joining = false
        }
    }
}

/// Pick a game to start a room with it.
struct StartRoomSheet: View {
    @State private var starting: String?
    @State private var problem: String?

    private var games: [MockGame] { Mock.games.filter { $0.playerRange.upperBound > 1 } }

    var body: some View {
        DLSheet(height: 560) {
            EmptyView()
        } content: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("START A ROOM").font(DL.display(34)).foregroundStyle(DL.ink)
                    Spacer()
                    DLIconButton(symbol: "xmark", size: 32).goesBack().accessibilityLabel("Close")
                }
                Text(problem ?? "Pick a game. Friends join with your room code.")
                    .font(DL.text(15)).foregroundStyle(problem == nil ? DL.ink2 : DL.danger)
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(games) { game in
                            DLRow(title: game.title, detail: "\(game.players), \(game.mode.lowercased())") {
                                DLThumb(game: game, size: 48)
                            } trailing: {
                                if starting == game.id {
                                    ProgressView().tint(DL.ink)
                                } else {
                                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(DL.ink2)
                                }
                            }
                            .tap { start(game) }
                            if game.id != games.last?.id { DLDivider() }
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
            .padding(.horizontal, 20)
        }
    }

    private func start(_ game: MockGame) {
        guard starting == nil else { return }
        starting = game.id
        problem = nil
        Task { @MainActor in
            do {
                let code = try await ConvexLink.shared.mutate("rooms:create", ["slug": game.id], as: String.self)
                LiveNav.shared.replaceTop(.room(code))
            } catch {
                problem = LiveRoomRound.message(for: error)
            }
            starting = nil
        }
    }
}

/// A room: its code to share, who is in it, and the host's key to start a round for everyone.
struct RoomScreen: View {
    let code: String
    @State private var room: ConvexRoom?
    @State private var watching: AnyCancellable?
    /// The last round this phone opened, so each round opens once.
    @State private var openedRound = -1

    var body: some View {
        VStack(spacing: 0) {
            DLNavBar(title: "Room", trailingSymbol: "square.and.arrow.up") {
                LiveNav.shared.share("Join my room on DEGEN with the code \(code)")
            }
            .padding(.horizontal, DL.margin).padding(.top, 4)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    codeCard
                    if let room {
                        let game = Mock.game(room.slug)
                        HStack(spacing: 12) {
                            DLThumb(game: game, size: 56)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(game.title.uppercased()).font(DL.display(26)).foregroundStyle(DL.ink)
                                Text(room.round > 0 ? "Round \(Int(room.round))" : "Nobody has played yet")
                                    .font(DL.text(14)).foregroundStyle(DL.ink2)
                            }
                        }
                        players(room)
                    } else {
                        ProgressView().tint(DL.ink).frame(maxWidth: .infinity).padding(.vertical, 30)
                    }
                }
                .padding(.horizontal, DL.margin).padding(.top, 12).padding(.bottom, 20)
            }
            .scrollIndicators(.hidden)

            if let room { startKey(room).padding(.horizontal, DL.margin).padding(.bottom, 8) }
        }
        .onAppear {
            watching = ConvexLink.shared.watch("rooms:get", ["code": code], as: ConvexRoom?.self) { value in
                room = value
                if let value { follow(value) }
            }
        }
        .onDisappear { watching = nil }
    }

    private var codeCard: some View {
        VStack(spacing: 4) {
            Text("ROOM CODE").dlLabel()
            Text(code).font(DL.display(64)).tracking(12).foregroundStyle(DL.ink).monospacedDigit()
            Text("Friends join from their Library").font(DL.text(13)).foregroundStyle(DL.ink2)
        }
        .frame(maxWidth: .infinity)
        .dlCard(padding: 18)
    }

    private func players(_ room: ConvexRoom) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(room.players.count) OF 6 PLAYERS").dlLabel().padding(.bottom, 4)
            ForEach(room.players) { player in
                DLRow(title: player.you ? "\(player.name) (you)" : player.name,
                      detail: player.playing ? "Playing now" : (player.done ? "Done" : nil)) {
                    DLAvatar(name: player.name, size: 40)
                } trailing: {
                    HStack(spacing: 8) {
                        if player.host { DLTag(text: "Host") }
                        if room.round > 0 {
                            Text(LiveBoard.text(Int(player.score.rounded()), Mock.game(room.slug)))
                                .font(DL.display(24)).foregroundStyle(DL.ink).monospacedDigit()
                        }
                    }
                }
                if player.id != room.players.last?.id { DLDivider(inset: 52) }
            }
        }
        .dlCard(padding: 14)
    }

    @ViewBuilder private func startKey(_ room: ConvexRoom) -> some View {
        if room.host {
            DLTextKey(title: room.round > 0 ? "Play again" : "Start round", symbol: "play.fill")
                .tap { start() }
                .opacity(room.status == "playing" ? 0.5 : 1)
        } else {
            Text(room.status == "playing" ? "A round is on" : "Waiting for the host to start")
                .font(DL.text(15, .semibold)).foregroundStyle(DL.ink2)
                .frame(maxWidth: .infinity).frame(height: 58)
        }
    }

    private func start() {
        guard room?.status != "playing" else { return }
        Task { try? await ConvexLink.shared.mutate("rooms:start", ["code": code]) }
    }

    /// When the host starts a round, everyone in the room goes into it.
    private func follow(_ room: ConvexRoom) {
        let round = Int(room.round)
        if openedRound < 0 { openedRound = room.status == "playing" ? round - 1 : round }
        guard room.status == "playing", round > openedRound, LiveNav.shared.topRoute == .room(code) else { return }
        openedRound = round
        LiveRoomRound.current = (code: room.code, round: round, gameID: room.slug, seed: UInt64(room.seed))
        LiveNav.shared.open(.play(room.slug, solo: false))
    }
}
