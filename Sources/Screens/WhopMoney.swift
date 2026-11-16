import SwiftUI
import Combine
import SafariServices
import ConvexMobile

// Money, all of it through Whop and all of it decided in Convex (convex/whop.ts, convex/creators.ts):
// a player gets a gold pack, a studio funds a creator program for its game, and a creator sends
// what their clips brought in to their Whop account. The app only opens Whop's page and watches
// Convex for the result. No Whop key and no Whop SDK is in the app.

/// `whop:catalog`: what can be paid for. Money is in cents.
struct WhopCatalog: Decodable, Equatable {
    struct Pack: Decodable, Equatable, Identifiable {
        let id: String
        let title: String
        let gold: Double
        let cents: Double
    }

    let packs: [Pack]
    /// Cents a studio pays for 1,000 views.
    let rates: [Double]
    /// Cents a studio can add to a program in one payment.
    let budgets: [Double]
    let sendMinimum: Double
}

/// `creators:mine`: what the player's clips brought in.
struct WhopCreator: Decodable, Equatable {
    struct Clip: Decodable, Equatable, Identifiable {
        let id: String
        let gameSlug: String
        let caption: String
        let views: Double
        let cents: Double

        private enum CodingKeys: String, CodingKey {
            case id = "_id"
            case gameSlug, caption, views, cents
        }
    }

    struct Transfer: Decodable, Equatable, Identifiable {
        let id: String
        let cents: Double
        let whopUsername: String
        /// "sending", "sent" or "failed"
        let status: String

        private enum CodingKeys: String, CodingKey {
            case id = "_id"
            case cents, whopUsername, status
        }
    }

    let cents: Double
    let centsAllTime: Double
    let whopUsername: String?
    let clips: [Clip]
    let transfers: [Transfer]
}

/// One row of `creators:programs`: a game whose studio pays creators for views.
struct WhopProgram: Decodable, Equatable, Identifiable {
    let gameSlug: String
    let rate: Double
    let left: Double
    let spent: Double
    let views: Double

    var id: String { gameSlug }
    /// true while the budget covers another view.
    var paying: Bool { left >= rate / 1000 }
}

private struct WhopCheckout: Decodable {
    let orderId: String
    let url: String
}

private struct WhopOrder: Decodable {
    let status: String
}

private struct WhopSent: Decodable {
    let sent: Bool
    let cents: Double
}

final class WhopStore: ObservableObject {
    static let shared = WhopStore()

    @Published private(set) var catalog: WhopCatalog?
    @Published private(set) var creator: WhopCreator?
    @Published private(set) var programs: [WhopProgram] = []
    /// true while a checkout is being made.
    @Published private(set) var opening = false

    private let link = ConvexLink.shared
    private var bag = Set<AnyCancellable>()
    private var watches: [AnyCancellable] = []
    private var orderWatch: AnyCancellable?
    private var seen = Set<String>()

    private init() {
        guard !ProcessInfo.processInfo.arguments.contains("-screen") else { return }
        link.signedIn.sink { [weak self] on in
            guard let self else { return }
            self.watches = on ? [
                self.link.watch("whop:catalog", as: WhopCatalog.self) { [weak self] value in self?.catalog = value },
                self.link.watch("creators:mine", as: WhopCreator?.self) { [weak self] value in self?.creator = value },
                self.link.watch("creators:programs", as: [WhopProgram].self) { [weak self] value in self?.programs = value },
            ] : []
        }
        .store(in: &bag)
    }

    func program(for gameID: String) -> WhopProgram? { programs.first { $0.gameSlug == gameID } }

    /// "$4.20" or "$1,250.00". Parts of a cent are left off.
    static func dollars(_ cents: Double) -> String {
        (cents.rounded(.down) / 100).formatted(.currency(code: "USD").locale(Locale(identifier: "en_US")))
    }

    /// "$10 per 1,000 views"
    static func rateText(_ rate: Double) -> String {
        "$\(Int(rate / 100)) per 1,000 views"
    }

    // MARK: Paying

    func buyGold(_ pack: WhopCatalog.Pack) {
        pay(done: "\(groupedNumber(Int(pack.gold))) gold added") {
            try await self.link.act("whop:buyGold", ["pack": pack.id], as: WhopCheckout.self)
        }
    }

    func fundProgram(gameID: String, rate: Double, budget: Double) {
        pay(done: "Your creator program is funded") {
            try await self.link.act("whop:fundProgram", ["slug": gameID, "rate": rate, "budget": budget], as: WhopCheckout.self)
        }
    }

    /// Makes the checkout in Convex, shows Whop's page over the app, and closes it when Convex says the payment landed.
    private func pay(done: String, _ start: @escaping () async throws -> WhopCheckout) {
        guard !opening else { return }
        opening = true
        Task { @MainActor in
            defer { self.opening = false }
            guard let checkout = try? await start(), let url = URL(string: checkout.url), let front = Self.frontController() else {
                LiveNav.shared.say("Whop did not answer. Try again.")
                return
            }
            let page = SFSafariViewController(url: url)
            front.present(page, animated: true)
            self.orderWatch = self.link.watch("whop:order", ["orderId": checkout.orderId], as: WhopOrder?.self) { [weak self, weak page] order in
                guard let self, order?.status == "paid" else { return }
                self.orderWatch = nil
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                page?.dismiss(animated: true)
                switch LiveNav.shared.topRoute {
                case .buyGold, .program: LiveNav.shared.back()
                default: break
                }
                LiveNav.shared.say(done)
            }
        }
    }

    private static func frontController() -> UIViewController? {
        let windows = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }
        guard var front = windows.first?.rootViewController else { return nil }
        while let above = front.presentedViewController { front = above }
        return front
    }

    // MARK: Creators

    /// Tells the server this phone watched a clip. The server keeps one view per player for each clip.
    func saw(_ clipID: String) {
        guard seen.insert(clipID).inserted else { return }
        Task { try? await link.mutate("creators:view", ["clipId": clipID]) }
    }

    /// Sends the creator's earnings to their Whop account. Returns the line to show them.
    @MainActor
    func sendEarnings(to username: String) async -> String {
        do {
            let answer = try await link.act("whop:sendEarnings", ["username": username], as: WhopSent.self)
            return answer.sent
                ? "\(Self.dollars(answer.cents)) sent to @\(username) on Whop"
                : "Whop could not send it. Your earnings are still here."
        } catch let error as ClientError {
            if case .ConvexError(let data) = error { return data.trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
            return "Could not reach Whop. Try again."
        } catch {
            return "Could not reach Whop. Try again."
        }
    }
}

// MARK: Gold packs

/// The sheet that sells gold packs. Each row opens Whop's checkout.
struct WhopBuyGoldSheet: View {
    @ObservedObject private var whop = WhopStore.shared
    @ObservedObject private var live = LiveStore.shared

    var body: some View {
        DLSheet(height: 452) {
            EmptyView()
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Get gold").dlLabel(10.5)
                    Spacer()
                }
                .frame(height: 36)
                HStack(alignment: .center, spacing: 10) {
                    DLCoin(size: 30)
                    Text(groupedNumber(live.s.balance)).font(DL.display(52)).foregroundStyle(DL.ink).monospacedDigit()
                    Text("now").dlLabel(10.5).padding(.top, 14)
                }
                .frame(height: 52)
                VStack(spacing: 8) {
                    ForEach(whop.catalog?.packs ?? []) { pack in
                        row(pack)
                    }
                }
                .padding(.top, 12)
                Text(whop.opening ? "Opening Whop" : whop.catalog == nil ? "Loading the packs" : "You pay on Whop. The gold lands here when the payment clears.")
                    .font(DL.text(13))
                    .foregroundStyle(DL.ink3)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 14)
            }
            .padding(.horizontal, 20)
        }
    }

    private func row(_ pack: WhopCatalog.Pack) -> some View {
        HStack(spacing: 12) {
            DLCoin(size: 34)
            VStack(alignment: .leading, spacing: 0) {
                Text("\(groupedNumber(Int(pack.gold))) GOLD").font(DL.display(28)).foregroundStyle(DL.ink)
                Text(pack.title).dlLabel(10.5)
            }
            Spacer(minLength: 8)
            Text(WhopStore.dollars(pack.cents))
                .font(DL.display(22))
                .foregroundStyle(DL.onInk)
                .padding(.horizontal, 14)
                .frame(height: 40)
                .background(DL.ink, in: Capsule())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(DL.body, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .tap { whop.buyGold(pack) }
        .accessibilityLabel("\(Int(pack.gold)) gold for \(WhopStore.dollars(pack.cents))")
    }
}

// MARK: Creator earnings

/// What the player's clips brought in, the games that pay for views, and the way to send it to Whop.
struct WhopEarningsScreen: View {
    @ObservedObject private var whop = WhopStore.shared

    var body: some View {
        let cents = whop.creator?.cents ?? 0
        let minimum = whop.catalog?.sendMinimum ?? 100
        DLPage {
            DLNavBar(title: "Creator earnings")
            VStack(alignment: .leading, spacing: 6) {
                Text(WhopStore.dollars(cents))
                    .font(DL.display(96))
                    .foregroundStyle(DL.ink)
                    .tracking(2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(height: 96, alignment: .leading)
                Text("\(WhopStore.dollars(whop.creator?.centsAllTime ?? 0)) from your clips so far")
                    .font(DL.text(15))
                    .foregroundStyle(DL.ink2)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if cents >= minimum {
                DLTextKey(title: "Send to Whop", symbol: "arrow.up.right").opens(.sendEarnings)
            } else {
                DLTextKey(title: "Send from \(WhopStore.dollars(minimum))", style: .neutral)
                    .tap { LiveNav.shared.say("You can send once you reach \(WhopStore.dollars(minimum))") }
            }
            payingCard
            clipsCard
            if let transfers = whop.creator?.transfers, !transfers.isEmpty { transfersCard(transfers) }
        }
    }

    /// Games whose studio pays for views right now. Each row opens the camera on that game.
    private var payingCard: some View {
        let paying = whop.programs.filter(\.paying)
        return VStack(alignment: .leading, spacing: 0) {
            Text("Games paying for views").dlLabel(10.5).padding(.bottom, 4)
            if paying.isEmpty {
                Text("No game is paying for views right now.")
                    .font(DL.text(15))
                    .foregroundStyle(DL.ink2)
                    .padding(.vertical, 8)
            }
            ForEach(paying.indices, id: \.self) { index in
                let program = paying[index]
                let game = Mock.game(program.gameSlug)
                if index > 0 { DLDivider(inset: 56) }
                HStack(spacing: 12) {
                    DLThumb(game: game, size: 44)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(game.title).font(DL.text(16, .semibold)).foregroundStyle(DL.ink)
                        Text(WhopStore.rateText(program.rate)).font(DL.text(13)).foregroundStyle(DL.ink2)
                    }
                    Spacer(minLength: 8)
                    DLTag(text: "Film", symbol: "video.fill", filled: true)
                }
                .padding(.vertical, 9)
                .opens(.create(game.id))
            }
        }
        .dlCard(padding: 14)
    }

    private var clipsCard: some View {
        let clips = whop.creator?.clips ?? []
        return VStack(alignment: .leading, spacing: 0) {
            Text("Your clips").dlLabel(10.5).padding(.bottom, 4)
            if clips.isEmpty {
                Text("Post a clip with the Create key. Each new viewer counts once.")
                    .font(DL.text(15))
                    .foregroundStyle(DL.ink2)
                    .padding(.vertical, 8)
            }
            ForEach(clips.indices, id: \.self) { index in
                if index > 0 { DLDivider(inset: 56) }
                WhopClipRow(clip: clips[index])
            }
        }
        .dlCard(padding: 14)
    }

    private func transfersCard(_ transfers: [WhopCreator.Transfer]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Sent to Whop").dlLabel(10.5).padding(.bottom, 4)
            ForEach(transfers.indices, id: \.self) { index in
                let row = transfers[index]
                if index > 0 { DLDivider(inset: 0) }
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(WhopStore.dollars(row.cents)).font(DL.text(16, .semibold)).foregroundStyle(DL.ink).lineLimit(1)
                        Text("to @\(row.whopUsername)").font(DL.text(13)).foregroundStyle(DL.ink2)
                    }
                    Spacer(minLength: 8)
                    DLTag(text: row.status == "sent" ? "Sent" : row.status == "sending" ? "Sending" : "Not sent",
                          filled: row.status == "sent")
                }
                .padding(.vertical, 9)
            }
        }
        .dlCard(padding: 14)
    }
}

/// One of the player's clips: its game, its caption, its views and what they paid.
struct WhopClipRow: View {
    let clip: WhopCreator.Clip

    var body: some View {
        let game = Mock.game(clip.gameSlug)
        HStack(spacing: 12) {
            DLThumb(game: game, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(clip.caption.isEmpty ? game.title : clip.caption)
                    .font(DL.text(16, .semibold))
                    .foregroundStyle(DL.ink)
                    .lineLimit(1)
                Text("\(game.title), \(groupedNumber(Int(clip.views))) \(clip.views == 1 ? "view" : "views")")
                    .font(DL.text(13))
                    .foregroundStyle(DL.ink2)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(WhopStore.dollars(clip.cents))
                .font(DL.display(26))
                .foregroundStyle(DL.ink)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.vertical, 9)
    }
}

/// The sheet that sends earnings: a Whop username and one key.
struct WhopSendSheet: View {
    @ObservedObject private var whop = WhopStore.shared
    @State private var username = ""
    @State private var sending = false
    @FocusState private var typing: Bool

    var body: some View {
        let cents = whop.creator?.cents ?? 0
        DLSheet(height: 318) {
            EmptyView()
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Send to Whop").dlLabel(10.5)
                    Spacer()
                }
                .frame(height: 36)
                Text(WhopStore.dollars(cents))
                    .font(DL.display(64))
                    .foregroundStyle(DL.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(height: 64, alignment: .leading)
                HStack(spacing: 6) {
                    Text("@").font(DL.text(17, .semibold)).foregroundStyle(DL.ink2)
                    TextField("Your Whop username", text: $username)
                        .font(DL.text(17))
                        .foregroundStyle(DL.ink)
                        .tint(DL.ink)
                        .focused($typing)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.send)
                        .onSubmit(send)
                }
                .padding(.horizontal, 16)
                .frame(height: 52)
                .background(DL.body, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .padding(.top, 12)
                DLTextKey(title: sending ? "Sending" : "Send \(WhopStore.dollars(cents))", symbol: sending ? nil : "arrow.up.right")
                    .padding(.top, 14)
                    .tap(send)
                Text("It lands in your Whop balance.")
                    .font(DL.text(13))
                    .foregroundStyle(DL.ink3)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
            }
            .padding(.horizontal, 20)
        }
        .onAppear { username = whop.creator?.whopUsername ?? "" }
    }

    private func send() {
        let name = username.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "@", with: "")
        guard !sending, !name.isEmpty else { return }
        sending = true
        typing = false
        Task { @MainActor in
            let line = await whop.sendEarnings(to: name)
            sending = false
            LiveNav.shared.back()
            LiveNav.shared.say(line)
        }
    }
}

/// On your own profile, under Clips: what your clips brought in, the way to the studio, and the clips.
struct WhopProfileClips: View {
    /// false when the profile shows the clips itself, as a grid above the earnings.
    var showsClips = true
    @ObservedObject private var whop = WhopStore.shared

    var body: some View {
        let clips = whop.creator?.clips ?? []
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Creator earnings").dlLabel(10.5)
                    Text(WhopStore.dollars(whop.creator?.cents ?? 0))
                        .font(DL.display(44))
                        .foregroundStyle(DL.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .frame(height: 40, alignment: .leading)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(DL.ink2)
            }
            .dlCard(padding: 14)
            .opens(.earnings)
            HStack(spacing: 12) {
                Image(systemName: "hammer.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(DL.ink)
                    .frame(width: 44, height: 44)
                    .background(DL.body, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Your studio").font(DL.text(16, .semibold)).foregroundStyle(DL.ink)
                    Text("Pay creators who post clips of your games").font(DL.text(13)).foregroundStyle(DL.ink2)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(DL.ink2)
            }
            .dlCard(padding: 14)
            .opens(.studio)
            if !showsClips {
                EmptyView()
            } else if clips.isEmpty {
                Text("Clips you post show up here.")
                    .font(DL.text(15))
                    .foregroundStyle(DL.ink2)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(clips.indices, id: \.self) { index in
                        if index > 0 { DLDivider(inset: 56) }
                        WhopClipRow(clip: clips[index])
                    }
                }
                .dlCard(padding: 14)
            }
        }
    }
}

// MARK: Creator programs

/// In the studio: each of the studio's games with its creator program, or the way to start one.
struct WhopStudioPrograms: View {
    let games: [MockGame]
    @ObservedObject private var whop = WhopStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Creator programs").dlLabel(10.5).padding(.bottom, 4)
            ForEach(games.indices, id: \.self) { index in
                let game = games[index]
                let program = whop.program(for: game.id)
                if index > 0 { DLDivider(inset: 56) }
                HStack(spacing: 12) {
                    DLThumb(game: game, size: 44)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(game.title).font(DL.text(16, .semibold)).foregroundStyle(DL.ink)
                        Text(program.map { "\(WhopStore.rateText($0.rate)), \(groupedNumber(Int($0.views))) paid" }
                             ?? "Pay creators who post clips of it")
                            .font(DL.text(13))
                            .foregroundStyle(DL.ink2)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    if let program {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(WhopStore.dollars(program.left)).font(DL.display(26)).foregroundStyle(DL.ink).lineLimit(1).fixedSize()
                            Text("left").dlLabel(10)
                        }
                    } else {
                        DLTag(text: "Start", symbol: "plus", filled: true)
                    }
                }
                .padding(.vertical, 9)
                .opens(.program(game.id))
            }
        }
        .dlCard(padding: 14)
    }
}

/// The sheet where a studio sets a game's creator program: what a view pays, and how much to put in.
struct WhopProgramSheet: View {
    let game: MockGame
    @ObservedObject private var whop = WhopStore.shared
    @State private var rate: Double = 1000
    @State private var budget: Double = 2000

    var body: some View {
        let program = whop.program(for: game.id)
        DLSheet(height: 470) {
            EmptyView()
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Creator program").dlLabel(10.5)
                    Spacer()
                }
                .frame(height: 36)
                HStack(spacing: 12) {
                    DLThumb(game: game, size: 52)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(game.title.uppercased())
                            .font(DL.display(34))
                            .foregroundStyle(DL.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text(program.map { "\(WhopStore.dollars($0.left)) left, \(groupedNumber(Int($0.views))) views paid" }
                             ?? "Creators post clips. You pay for the views.")
                            .font(DL.text(14))
                            .foregroundStyle(DL.ink2)
                    }
                }
                .padding(.top, 6)
                Text("For 1,000 views").dlLabel(10.5).padding(.top, 18)
                choices(whop.catalog?.rates ?? [], selected: rate) { rate = $0 }.padding(.top, 8)
                Text(program == nil ? "Budget" : "Add to the budget").dlLabel(10.5).padding(.top, 16)
                choices(whop.catalog?.budgets ?? [], selected: budget) { budget = $0 }.padding(.top, 8)
                Text("Enough for about \(groupedNumber(Int(budget / rate * 1000))) views.")
                    .font(DL.text(15, .semibold))
                    .foregroundStyle(DL.ink)
                    .padding(.top, 14)
                DLTextKey(title: whop.opening ? "Opening Whop" : "Fund \(WhopStore.dollars(budget)) on Whop")
                    .padding(.top, 14)
                    .tap { whop.fundProgram(gameID: game.id, rate: rate, budget: budget) }
            }
            .padding(.horizontal, 20)
        }
        .onAppear {
            if let program { rate = program.rate }
        }
    }

    private func choices(_ values: [Double], selected: Double, pick: @escaping (Double) -> Void) -> some View {
        HStack(spacing: 8) {
            ForEach(values, id: \.self) { value in
                Text("$\(Int(value / 100))")
                    .font(DL.display(24))
                    .foregroundStyle(value == selected ? DL.onInk : DL.ink)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(value == selected ? DL.ink : DL.body, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .tap { pick(value) }
            }
        }
    }
}
