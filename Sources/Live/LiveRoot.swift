import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass
import Combine

// The app itself: the tabs (Home, Videos, Messages, Library) under our own tab bar, with every other
// screen stacked on top as a layer.

struct LiveRoot: View {
    @ObservedObject private var nav = LiveNav.shared
    @ObservedObject private var store = LiveStore.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            // The system bar stays hidden. LiveTabBar draws the bar, with the Create key in its middle.
            TabView(selection: $nav.tab) {
                Tab("Home", systemImage: "house.fill", value: 0) { HomeScreen().toolbar(.hidden, for: .tabBar) }
                Tab("Reels", systemImage: "play.rectangle.on.rectangle.fill", value: 1) { LiveVideos().toolbar(.hidden, for: .tabBar) }
                Tab("You", systemImage: "person.fill", value: 2) { G2YouScreen().toolbar(.hidden, for: .tabBar) }
                Tab("Messages", systemImage: "bubble.left.and.bubble.right.fill", value: 3) { MessagesTabScreen().toolbar(.hidden, for: .tabBar) }
                Tab("Library", systemImage: "square.stack.fill", value: 4) { LibraryScreen().toolbar(.hidden, for: .tabBar) }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { LiveTabBar() }

            ForEach(Array(nav.layers.enumerated()), id: \.element.id) { depth, layer in
                LayerView(layer: layer)
                    .zIndex(Double(depth + 1))
                    .transition(layer.route.style.entrance)
            }

            if let toast = nav.toast {
                Text(toast)
                    .font(DL.text(15, .semibold)).foregroundStyle(DL.onInk)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18).padding(.vertical, 12)
                    .background(DL.ink, in: Capsule())
                    .padding(.horizontal, 24).padding(.bottom, 110)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .allowsHitTesting(false)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(999)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.rollDayIfNeeded() }
        }
        .statusBarHidden(nav.isPlaying)
        .persistentSystemOverlays(nav.isPlaying ? .hidden : .automatic)
        .defersSystemGestures(on: nav.isPlaying ? .all : [])
    }
}

private extension Route.Style {
    /// A page slides in from the right, a cover rises from the bottom, and a sheet fades in its dim
    /// while it raises itself (see DLSheet).
    var entrance: AnyTransition {
        switch self {
        case .push: .move(edge: .trailing)
        case .cover: .move(edge: .bottom)
        case .sheet: .opacity
        }
    }
}

/// One stacked screen.
struct LayerView: View {
    let layer: Layer
    /// Watched so a screen is handed its game again when the server's counts for it change.
    @ObservedObject private var store = LiveStore.shared

    var body: some View {
        switch layer.route.style {
        case .sheet:
            screen
        case .cover:
            screen.background(DL.body.ignoresSafeArea())
        case .push:
            screen
                .background(DL.body.ignoresSafeArea())
                .overlay(alignment: .leading) { backSwipeStrip }
        }
    }

    /// A strip down the left edge: drag it more than 60 points to the right to go back.
    private var backSwipeStrip: some View {
        Color.clear
            .frame(width: 22)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 16).onEnded { drag in
                if drag.translation.width > 60 { LiveNav.shared.back() }
            })
            .ignoresSafeArea()
    }

    @ViewBuilder private var screen: some View {
        switch layer.route {
        case .gameReady(let gameID):
            GameReadyScreen(game: Mock.game(gameID))
        case .play(let gameID, let solo):
            LivePlayScreen(game: Mock.game(gameID), solo: solo)
        case .results:
            LiveResultsScreen()
        case .gameDetail(let gameID):
            G1GameDetailScreen(game: Mock.game(gameID), clip: Mock.clips.first { $0.game.id == gameID } ?? Mock.clips[0])
        case .leaderboard(let gameID):
            G1LeaderboardScreen(game: Mock.game(gameID))
        case .comments(let clipID):
            LiveCommentsScreen(clip: Mock.clip(clipID))
        case .fairness(let gameID):
            FairnessSheetScreen(game: Mock.game(gameID))
        case .spend(let index):
            LiveSpendScreen(item: Mock.shop[min(max(index, 0), Mock.shop.count - 1)])
        case .shareRun(let gameID):
            G1ShareRunScreen(game: Mock.game(gameID))
        case .gold:
            TodayScreen()
        case .history:
            G2HistoryScreen()
        case .streak:
            G2StreakSheetScreen()
        case .search:
            LiveSearchScreen()
        case .inbox:
            G2InboxScreen()
        case .settings:
            G2SettingsScreen()
        case .saveGold:
            G2SaveGoldSheetScreen()
        case .notify:
            G2NotifySheetScreen()
        case .studio:
            G3StudioScreen()
        case .publish(let step):
            if step <= 1 {
                G3PublishGameScreen()
            } else if step == 2 {
                G3PublishClipScreen()
            } else {
                G3PublishSendScreen()
            }
        case .reviewProgress:
            // The review takes six seconds here, then shows its result.
            G3ReviewProgressScreen().task {
                try? await Task.sleep(for: .seconds(6))
                if LiveNav.shared.topRoute == .reviewProgress { LiveNav.shared.replaceTop(.reviewResult) }
            }
        case .reviewResult:
            G3ReviewResultScreen()
        case .reviewChanges:
            G3ReviewChangesScreen()
        case .create:
            CreatePlaceholderScreen()
        case .profile:
            ProfilePlaceholderScreen()
        case .join:
            JoinRoomSheet()
        case .startRoom:
            StartRoomSheet()
        case .room(let code):
            RoomScreen(code: code)
        }
    }
}

// MARK: Videos

/// The Videos tab: an endless column of clips, one to a screen. Only the clip on screen moves.
struct LiveVideos: View {
    @ObservedObject private var nav = LiveNav.shared
    @ObservedObject private var store = LiveStore.shared

    /// Long enough that nobody reaches the end. The six clips repeat.
    private let pageCount = 600

    var body: some View {
        GeometryReader { proxy in
            let insets = proxy.safeAreaInsets
            let screen = CGSize(width: proxy.size.width + insets.leading + insets.trailing,
                                height: proxy.size.height + insets.top + insets.bottom)
            let playing = nav.tab == 1 && nav.layers.isEmpty && store.isOn("Autoplay clips")
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(0..<pageCount, id: \.self) { index in
                        LiveClipPage(clip: Mock.clips[index % Mock.clips.count], active: playing && nav.videoIndex == index)
                            .frame(width: screen.width, height: screen.height)
                            .id(index)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $nav.videoIndex)
            .scrollIndicators(.hidden)
            .ignoresSafeArea()
        }
        .background(Color.black.ignoresSafeArea())
    }
}

/// One clip in Videos. Its gameplay loops for as long as it is the clip on screen.
struct LiveClipPage: View {
    let clip: MockClip
    let active: Bool
    @ObservedObject private var store = LiveStore.shared
    @State private var loopStart = Date()

    private static let loopSeconds = 7.0

    var body: some View {
        let vote = store.vote(for: clip.game.id)
        Group {
            if active {
                TimelineView(.animation(minimumInterval: 1.0 / 40)) { timeline in
                    let loops = timeline.date.timeIntervalSince(loopStart) / Self.loopSeconds
                    let phase = loops - loops.rounded(.towardZero)
                    VideoPage(clip: clip, progress: CGFloat(phase), voted: vote, phase: phase)
                }
            } else {
                // At rest a clip shows its opening moment.
                VideoPage(clip: clip, progress: 0, voted: vote, phase: 0.02)
            }
        }
        .onChange(of: active) { _, isActive in
            if isActive { loopStart = Date() }
        }
    }
}

// MARK: Playing

/// A running game, with the app's two controls on top of it: the way out, and the gold being collected.
struct LivePlayScreen: View {
    let game: MockGame
    let solo: Bool
    @StateObject private var link = GameLink()
    /// Held as plain state and not observed here, so its ticking redraws the gold counter and never the game.
    @State private var clock = PlayClock()
    /// Decided once, when the round opens.
    @State private var options: GameOptions
    @State private var asking = false
    @Environment(\.scenePhase) private var scenePhase

    init(game: MockGame, solo: Bool) {
        self.game = game
        self.solo = solo
        let timeSeed = UInt64(Date().timeIntervalSince1970 * 1000) & 0xFFFF_FFFF
        let roomSeed = LiveRoomRound.current.flatMap { $0.gameID == game.id ? $0.seed : nil }
        _options = State(initialValue: GameOptions(solo: solo, playerName: Mock.handle, friendNames: Mock.playFriends,
                                                   bestScore: LiveStore.shared.s.best[game.id] ?? 0,
                                                   seed: roomSeed ?? LiveLaunch.seed ?? timeSeed))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            GameSurface(scale: LiveLaunch.gameScale ?? 1) {
                GameFactory.view(for: game.kind, options: options, link: link)
            }
            .ignoresSafeArea()
            HStack {
                DLMediaButton(symbol: "xmark", size: 44)
                    .tap { pause() }
                    .accessibilityLabel("Leave the game")
                Spacer()
                PlayGoldHUD(clock: clock, link: link, game: game)
            }
            .padding(.horizontal, 18).padding(.top, 6)
            .frame(maxHeight: .infinity, alignment: .top)
            if asking { pausePrompt }
        }
        .onAppear(perform: begin)
        .onDisappear { TouchWatcher.remove() }
        .onChange(of: scenePhase) { _, phase in
            // Leaving the app pauses the round. The prompt is waiting on return.
            if phase != .active && !link.isFinished {
                link.paused = true
                asking = true
            }
        }
    }

    private func begin() {
        // Gold counts from the first touch, and a game playing itself for a recording never gets one.
        let clock = self.clock
        TouchWatcher.install { clock.start() }
        if GameDemo.autopilot { clock.start() }
        link.onFinish = { result in
            TouchWatcher.remove()
            LiveRoomRound.report(result.score)
            let summary = LiveStore.shared.finishRound(game: game, seconds: clock.seconds, result: result, solo: solo)
            if summary.gold > 0 { UINotificationFeedbackGenerator().notificationOccurred(.success) }
            LiveNav.shared.replaceTop(.results)
        }
    }

    private func pause() {
        link.paused = true
        withAnimation(.snappy(duration: 0.2)) { asking = true }
    }

    private func resume() {
        withAnimation(.snappy(duration: 0.2)) { asking = false }
        clock.lastTick = Date()
        link.paused = false
    }

    /// Leaving early still keeps the gold from the time played. The round has no score.
    private func leave() {
        LiveRoomRound.report(0)
        if clock.seconds > 0 {
            LiveStore.shared.finishRound(game: game, seconds: clock.seconds, result: GameResult(score: 0, unit: ""), solo: solo)
        }
        LiveNav.shared.back()
    }

    private var pausePrompt: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 14) {
                Text("PAUSED").font(DL.display(40)).foregroundStyle(DL.ink)
                Text("If you leave now you keep the gold you collected in this round.")
                    .font(DL.text(16)).foregroundStyle(DL.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(spacing: 10) {
                    DLTextKey(title: "Keep playing", symbol: "play.fill").tap(resume)
                    DLTextKey(title: "Leave", style: .neutral).tap(leave)
                }
                .padding(.top, 4)
            }
            .padding(22)
            .background(DL.raised, in: RoundedRectangle(cornerRadius: 34, style: .continuous))
            .padding(.horizontal, 20)
        }
        .transition(.opacity)
    }
}

/// Lays a game out on a smaller canvas and scales it up to fill the screen. A game paints every
/// pixel itself, so a smaller canvas is cheaper to draw. At scale 1 the game is left alone.
struct GameSurface<Content: View>: View {
    var scale: CGFloat
    @ViewBuilder var content: () -> Content

    var body: some View {
        if scale == 1 {
            content()
        } else {
            GeometryReader { proxy in
                let screen = proxy.size
                content()
                    .frame(width: screen.width / scale, height: screen.height / scale)
                    .scaleEffect(scale, anchor: .topLeading)
                    .frame(width: screen.width, height: screen.height, alignment: .topLeading)
            }
        }
    }
}

/// The seconds of play in a round.
final class PlayClock: ObservableObject {
    @Published var seconds: Double = 0
    var started = false
    var lastTick = Date()

    func start() {
        guard !started else { return }
        started = true
        lastTick = Date()
    }

    /// Moves the clock to `now`. A long gap between ticks counts as half a second at most, so time
    /// the app spent stalled is not paid as play.
    func tick(_ now: Date, counting: Bool) {
        let step = min(0.5, now.timeIntervalSince(lastTick))
        lastTick = now
        if started && counting { seconds += step }
    }
}

/// The gold counter on a running game. It drives the clock, so nothing else redraws five times a second.
struct PlayGoldHUD: View {
    @ObservedObject var clock: PlayClock
    @ObservedObject var link: GameLink
    let game: MockGame
    @ObservedObject private var store = LiveStore.shared
    private let ticks = Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()

    var body: some View {
        let pending = store.pending(for: game, seconds: clock.seconds)
        SessionGoldHUD(collected: pending.gold, toNext: pending.toNext)
            .onReceive(ticks) { now in
                clock.tick(now, counting: !link.paused && !link.isFinished)
            }
    }
}

/// Tells the app that a finger has landed anywhere on the screen. It sits on the window and only
/// listens: it fails at once, so the touch goes on to whoever would have had it anyway.
final class TouchWatcher: UIGestureRecognizer {
    private static weak var installed: TouchWatcher?
    private var onTouch: () -> Void = {}

    static func install(_ onTouch: @escaping () -> Void) {
        remove()
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let window = scenes.first?.keyWindow else { return }
        let watcher = TouchWatcher(target: nil, action: nil)
        watcher.onTouch = onTouch
        watcher.cancelsTouchesInView = false
        watcher.delaysTouchesBegan = false
        watcher.delaysTouchesEnded = false
        window.addGestureRecognizer(watcher)
        installed = watcher
    }

    static func remove() {
        guard let watcher = installed else { return }
        watcher.view?.removeGestureRecognizer(watcher)
        installed = nil
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        onTouch()
        state = .failed
    }
}

/// Shows the right results screen for the round that just ended.
struct LiveResultsScreen: View {
    @ObservedObject private var store = LiveStore.shared

    var body: some View {
        if let round = store.lastRound {
            let game = Mock.game(round.gameID)
            if round.hitLimit {
                ResultsFullScreen(game: game, summary: round)
            } else {
                ResultsScreen(game: game, voted: store.vote(for: game.id), summary: round)
            }
        } else {
            // Nothing to show, which only happens if results is opened without a round.
            DL.body.ignoresSafeArea().onAppear { LiveNav.shared.closeAll() }
        }
    }
}

// MARK: Launch arguments

/// Launch arguments, for testing and for recording the app. Normal use needs none of them.
///   -fresh 1            start over with a new account
///   -scheme light|dark  appearance
///   -tab <0...4>        open on a tab: 0 Home, 1 Videos, 2 You, 3 Messages, 4 Library
///   -video <n>          the clip showing in Videos
///   -play <game id>     open straight into a game (-solo 1 to play alone, -seed <n> for a fixed round)
///   -route <name>       open a screen: gold, history, streak, search, inbox, settings, saveGold, notify, studio,
///                       reviewProgress, reviewResult, reviewChanges, or one that takes a value:
///                       gameReady:<game id>, gameDetail:<game id>, leaderboard:<game id>, comments:<clip id>,
///                       fairness:<game id>, spend:<n>, shareRun:<game id>, publish:<step>,
///                       create, join, startRoom, profile:<handle>, room:<code>
///   -demo 1             games play themselves (-lose <seconds> has the scripted player lose after that long)
///   -gamescale <x>      draw games on a canvas x times smaller and scale it up, to measure drawing cost
enum LiveLaunch {
    static var seed: UInt64? { MockArgs.value("-seed").flatMap { UInt64($0) } }

    static var gameScale: CGFloat? { MockArgs.value("-gamescale").flatMap { Double($0) }.map { CGFloat($0) } }

    static func apply() {
        let nav = LiveNav.shared, store = LiveStore.shared
        if MockArgs.value("-fresh") != nil { store.reset() }
        if let scheme = MockArgs.value("-scheme") {
            store.s.appearance = ["light": 1, "dark": 2][scheme] ?? 0
        }
        if let tab = MockArgs.value("-tab").flatMap({ Int($0) }) { nav.tab = tab }
        if let video = MockArgs.value("-video").flatMap({ Int($0) }) { nav.videoIndex = video }
        if MockArgs.value("-demo") != nil { GameDemo.autopilot = true }
        if let seconds = MockArgs.value("-lose").flatMap({ Double($0) }) { GameDemo.loseAfter = seconds }

        if let gameID = MockArgs.value("-play") {
            nav.layers = [Layer(route: .play(gameID, solo: MockArgs.value("-solo") != nil))]
        } else if let route = MockArgs.value("-route").flatMap(route(named:)) {
            nav.layers = [Layer(route: route)]
        }
    }

    /// "gold", or "gameDetail:lane-dash" for a route that takes a value.
    private static func route(named text: String) -> Route? {
        let parts = text.split(separator: ":", maxSplits: 1).map(String.init)
        guard let name = parts.first else { return nil }
        let value = parts.count > 1 ? parts[1] : ""
        switch name {
        case "gold": return .gold
        case "history": return .history
        case "streak": return .streak
        case "search": return .search
        case "inbox": return .inbox
        case "settings": return .settings
        case "saveGold": return .saveGold
        case "notify": return .notify
        case "studio": return .studio
        case "reviewProgress": return .reviewProgress
        case "reviewResult": return .reviewResult
        case "reviewChanges": return .reviewChanges
        case "gameReady": return .gameReady(value)
        case "gameDetail": return .gameDetail(value)
        case "leaderboard": return .leaderboard(value)
        case "comments": return .comments(value)
        case "fairness": return .fairness(value)
        case "shareRun": return .shareRun(value)
        case "spend": return .spend(Int(value) ?? 1)
        case "publish": return .publish(Int(value) ?? 1)
        case "create": return .create
        case "join": return .join
        case "startRoom": return .startRoom
        case "profile": return .profile(value.isEmpty ? "me" : value)
        case "room": return .room(value)
        default: return nil
        }
    }
}

// MARK: Hosting

/// The window's root controller. It owns what SwiftUI cannot reach from inside the layer stack:
/// the status bar, the home indicator, the screen-edge gestures and the appearance.
final class LiveHost: UIHostingController<LiveRoot> {
    private var watching: AnyCancellable?

    init() {
        // Nothing in the app rubber-bands. A page stops at its first and last row, and a page that
        // fits on the screen does not move at all.
        UIScrollView.appearance().bounces = false
        LiveLaunch.apply()
        super.init(rootView: LiveRoot())
        // Both objects announce a change before it lands, so read them on the next turn of the main queue.
        watching = LiveNav.shared.objectWillChange.merge(with: LiveStore.shared.objectWillChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.syncSystemChrome() }
    }

    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("LiveHost is created in code")
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        syncSystemChrome()
    }

    private func syncSystemChrome() {
        let wanted: UIUserInterfaceStyle = switch LiveStore.shared.s.appearance {
        case 1: .light
        case 2: .dark
        default: .unspecified
        }
        if let window = view.window, window.overrideUserInterfaceStyle != wanted { window.overrideUserInterfaceStyle = wanted }
        setNeedsStatusBarAppearanceUpdate()
        setNeedsUpdateOfHomeIndicatorAutoHidden()
        setNeedsUpdateOfScreenEdgesDeferringSystemGestures()
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        // A sheet leaves the screen under it showing, so the top screen that is not a sheet decides.
        switch LiveNav.shared.layers.last(where: { $0.route.style != .sheet })?.route {
        case .gameReady, .play, .results, .gameDetail: .lightContent
        case nil: LiveNav.shared.tab == 1 ? .lightContent : .default
        default: .default
        }
    }

    override var prefersStatusBarHidden: Bool { LiveNav.shared.isPlaying }
    override var prefersHomeIndicatorAutoHidden: Bool { LiveNav.shared.isPlaying }
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { LiveNav.shared.isPlaying ? .all : [] }
}
