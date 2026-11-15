import SwiftUI

// The profile: your Dailie standing in a dark little room, your name and numbers under it, and the
// trophies you have earned. The Shop pill at the top right leads to the Shop.

struct ProfileScreen: View {
    let handle: String
    @ObservedObject private var avatars = AvatarStore.shared
    @ObservedObject private var store = LiveStore.shared
    @StateObject private var loader: ProfileLoader
    @State private var tab = 0
    @State private var bubble: String?
    @State private var bubbleTurn = 0

    init(handle: String) {
        self.handle = handle
        _loader = StateObject(wrappedValue: ProfileLoader(handle: handle))
    }

    private var isMe: Bool { handle == "me" || handle == store.me?.handle }

    private struct Shown {
        var name: String
        var handle: String
        var gold: Int
        var streak: Int
        var rounds: Int
        var look: AvatarLook
        var shirt: VoxelColor
        var decor: [String]
        var bests: [Trophy]
    }

    private struct Trophy: Identifiable {
        let game: MockGame
        let text: String
        var id: String { game.id }
    }

    private var shown: Shown {
        if isMe {
            let bests = Mock.games.compactMap { game -> Trophy? in
                guard store.s.best[game.id] != nil else { return nil }
                let text = store.s.bestText[game.id] ?? ""
                let unit = store.s.bestUnit[game.id] ?? ""
                return Trophy(game: game, text: unit.isEmpty || unit == "%" ? text : "\(text) \(unit)")
            }
            return Shown(name: Mock.displayName, handle: Mock.handle, gold: store.s.balance, streak: store.s.streak,
                         rounds: store.s.rounds, look: avatars.look, shirt: avatars.shirt, decor: avatars.decor, bests: bests)
        }
        guard let p = loader.profile else {
            return Shown(name: handle, handle: handle, gold: 0, streak: 0, rounds: 0,
                         look: AvatarLook.starter(handle: handle), shirt: VoxelPalette.purple, decor: [], bests: [])
        }
        let bests = p.bests.compactMap { best -> Trophy? in
            guard let game = Mock.games.first(where: { $0.id == best.gameSlug }) else { return nil }
            let text = best.text ?? groupedNumber(Int(best.score))
            let unit = best.unit ?? ""
            return Trophy(game: game, text: unit.isEmpty || unit == "%" ? text : "\(text) \(unit)")
        }
        return Shown(name: p.name, handle: p.handle, gold: Int(p.gold), streak: Int(p.streak), rounds: Int(p.rounds),
                     look: p.look, shirt: VoxelColor(hex: p.color), decor: p.decor ?? [], bests: bests)
    }

    var body: some View {
        let info = shown
        GeometryReader { proxy in
            let top = proxy.safeAreaInsets.top
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    room(info, top: top)
                    identity(info)
                        .padding(.horizontal, DL.margin).padding(.top, 16)
                    G2Segmented(items: ["Trophies", "Clips", "Ranked"], selected: tab)
                        .overlay {
                            HStack(spacing: 0) {
                                ForEach(0..<3, id: \.self) { index in
                                    Color.clear.contentShape(Rectangle()).tap { tab = index }
                                }
                            }
                        }
                        .padding(.horizontal, DL.margin).padding(.top, 18)
                    tabContent(info)
                        .padding(.horizontal, DL.margin).padding(.top, 14).padding(.bottom, 40)
                }
            }
            .scrollIndicators(.hidden)
            .ignoresSafeArea(edges: .top)
        }
        .background(DL.body.ignoresSafeArea())
    }

    // MARK: Room

    private func room(_ info: Shown, top: CGFloat) -> some View {
        ZStack(alignment: .top) {
            AvatarRoom(floorAt: 0.72, decor: info.decor, trophies: info.bests.map(\.game.id))
            AvatarStage(look: info.look, shirt: info.shirt, control: .turnOnly, distance: 9.0) {
                say(info)
            }
            .padding(.top, top + 40)
            if let bubble {
                Text(bubble)
                    .font(DL.text(15, .semibold)).foregroundStyle(DL.onGold)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(Color(hex: "FFC531"), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(Color(hex: "FFC531")).frame(width: 12, height: 12)
                            .rotationEffect(.degrees(45)).offset(y: 5)
                    }
                    .padding(.top, top + 64)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
            topBar(top: top)
        }
        .frame(height: top + 400)
        .clipShape(DL.screenShape)
    }

    private func topBar(top: CGFloat) -> some View {
        HStack(spacing: 8) {
            DLMediaButton(symbol: "chevron.left").goesBack().accessibilityLabel("Back")
            Spacer()
            if isMe {
                DLMediaButton(symbol: "square.and.arrow.up", size: 40)
                    .tap { LiveNav.shared.share("Come and see my Dailie. I am @\(Mock.handle) on DEGEN.") }
                    .accessibilityLabel("Share")
                DLMediaButton(symbol: "gearshape.fill", size: 40).opens(.settings).accessibilityLabel("Settings")
                ShopPill().opens(.shop(nil))
            } else {
                DLMediaButton(symbol: "square.and.arrow.up", size: 40)
                    .tap { LiveNav.shared.share("Come and play with @\(handle) on DEGEN.") }
                    .accessibilityLabel("Share")
            }
        }
        .padding(.horizontal, DL.margin)
        .padding(.top, top + 6)
    }

    /// The Dailie says something about you when you tap it.
    private func say(_ info: Shown) {
        let lines: [String] = {
            var lines: [String] = []
            if info.streak > 0 { lines.append("\(info.streak) day streak") }
            if let best = info.bests.first { lines.append("Beat my \(best.text)?") }
            lines.append("Nice to see you")
            return lines
        }()
        bubbleTurn += 1
        let turn = bubbleTurn
        withAnimation(.spring(duration: 0.35, bounce: 0.4)) { bubble = lines[(turn - 1) % lines.count] }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            guard turn == bubbleTurn else { return }
            withAnimation(.easeOut(duration: 0.25)) { bubble = nil }
        }
    }

    // MARK: Name and numbers

    private func identity(_ info: Shown) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(info.name.uppercased())
                .font(DL.display(42)).foregroundStyle(DL.ink)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text("@\(info.handle)").font(DL.text(15, .medium)).foregroundStyle(DL.ink2)
            HStack(spacing: 14) {
                HStack(spacing: 5) {
                    DLCoin(size: 14)
                    Text("\(groupedNumber(info.gold)) GOLD")
                }
                .opens(.gold)
                HStack(spacing: 5) {
                    Image(systemName: "flame.fill").foregroundStyle(DL.goldText)
                    Text("\(info.streak) DAY STREAK")
                }
                HStack(spacing: 5) {
                    Image(systemName: "trophy.fill").foregroundStyle(DL.goldText)
                    Text("\(info.bests.count)")
                }
            }
            .font(DL.label(11.5)).foregroundStyle(DL.ink2)
            .padding(.top, 8)
        }
    }

    // MARK: Tabs

    @ViewBuilder
    private func tabContent(_ info: Shown) -> some View {
        switch tab {
        case 0:
            if info.bests.isEmpty {
                Text(isMe ? "Play a game and your best score lands here as a trophy." : "No trophies yet.")
                    .font(DL.text(15)).foregroundStyle(DL.ink2)
                    .frame(maxWidth: .infinity).padding(.vertical, 30)
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(info.bests) { best in
                        trophy(best.game, text: best.text)
                    }
                }
            }
        default:
            VStack(spacing: 8) {
                Image(systemName: tab == 1 ? "film.stack" : "chart.bar.fill")
                    .font(.system(size: 34, weight: .semibold)).foregroundStyle(DL.ink3)
                Text("COMING SOON").font(DL.display(26)).foregroundStyle(DL.ink)
                Text(tab == 1 ? "Clips you post show up here." : "Ranked seasons are on the way.")
                    .font(DL.text(14)).foregroundStyle(DL.ink2)
            }
            .frame(maxWidth: .infinity)
            .dlCard(padding: 22)
        }
    }

    private func trophy(_ game: MockGame, text: String) -> some View {
        HStack(spacing: 10) {
            DLThumb(game: game, size: 44)
            VStack(alignment: .leading, spacing: 1) {
                Text(game.title).font(DL.text(14, .semibold)).foregroundStyle(DL.ink).lineLimit(1)
                Text(text.uppercased()).font(DL.label(11)).foregroundStyle(DL.goldText).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .dlCard(padding: 10, radius: 18)
        .opens(.leaderboard(game.id))
    }
}

/// The gold Shop pill: a bag with a small coin.
struct ShopPill: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "bag.fill").font(.system(size: 15, weight: .bold))
                .overlay(alignment: .bottomTrailing) { DLCoin(size: 9).offset(x: 4, y: 3) }
            Text("SHOP").font(DL.display(19)).tracking(0.6)
        }
        .foregroundStyle(DL.onGold)
        .padding(.horizontal, 13)
        .frame(height: 40)
        .background(Capsule().fill(Color(hex: "FFC531")))
        .background(Capsule().fill(Color(hex: "C48A00")).offset(y: 3))
        .accessibilityLabel("Shop")
    }
}

/// Your own head, for the Home top bar.
struct MyAvatarHead: View {
    var size: CGFloat = 36
    @ObservedObject private var avatars = AvatarStore.shared

    var body: some View {
        AvatarHead(look: avatars.look, shirt: avatars.shirt, size: size)
    }
}
