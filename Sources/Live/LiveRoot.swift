import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass
import Combine

// The app itself: the tabs (Reels, Community, Messages, Library) under our own tab bar, with every other
// screen stacked on top as a layer.

struct LiveRoot: View {
    @ObservedObject private var nav = LiveNav.shared
    @ObservedObject private var store = LiveStore.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            // The system bar stays hidden. LiveTabBar draws the bar, with the Create key in its middle.
            TabView(selection: $nav.tab) {
                Tab("Reels", systemImage: "play.rectangle.on.rectangle.fill", value: 1) { LiveVideos().toolbar(.hidden, for: .tabBar) }
                Tab("Community", systemImage: "person.2.fill", value: 0) { CommunityScreen().underTabBar() }
                Tab("You", systemImage: "person.fill", value: 2) { G2YouScreen().underTabBar() }
                Tab("Messages", systemImage: "bubble.left.and.bubble.right.fill", value: 3) { MessagesInboxScreen(showsBack: false).underTabBar() }
                Tab("Library", systemImage: "books.vertical.fill", value: 4) { LibraryScreen().underTabBar() }
            }
            // An inset on the TabView never reaches the pages inside its tabs, so the bar floats over
            // them and each page keeps its own room for it (underTabBar).
            .overlay(alignment: .bottom) { LiveTabBar() }

            // Sheets are presented by iOS below, so they swipe down like any other sheet.
            ForEach(Array(nav.layers.enumerated()), id: \.element.id) { depth, layer in
                if layer.route.style != .sheet {
                    LayerView(layer: layer)
                        .zIndex(Double(depth + 1))
                        .transition(layer.route.style.entrance)
                }
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
        .onAppear { AppTime.shared.start() }
        .sheet(item: Binding(get: { nav.layers.last.flatMap { $0.route.style == .sheet ? $0 : nil } },
                             set: { shown in
                                 // Swiped away: drop the sheet's layer, unless something already took it off.
                                 if shown == nil, nav.layers.last?.route.style == .sheet { nav.layers.removeLast() }
                             })) { layer in
            LayerView(layer: layer).environment(\.dlInSystemSheet, true)
        }
        .statusBarHidden(nav.isPlaying)
        .persistentSystemOverlays(nav.isPlaying ? .hidden : .automatic)
        .defersSystemGestures(on: nav.isPlaying ? .all : [])
    }
}

private extension View {
    /// A tab's page: the system bar hidden, and room at the bottom so the last row scrolls clear of LiveTabBar.
    func underTabBar() -> some View {
        toolbar(.hidden, for: .tabBar)
            .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: LiveTabBar.height) }
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
        case .account(let reason):
            AccountScreen(reason: reason)
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
        case .create(let gameID):
            CreateCameraScreen(startGameID: gameID)
        case .createPreview:
            CreatePreviewScreen()
        case .makeGame:
            G4CreateScreen()
        case .profile(let handle):
            ProfileScreen(handle: handle)
        case .shop(let focus):
            ShopScreen(focus: focus)
        case .join:
            JoinRoomSheet()
        case .startRoom:
            StartRoomSheet()
        case .room(let code):
            RoomScreen(code: code)
        case .libraryGame(let gameID):
            LibraryGameSheet(game: Mock.game(gameID))
        case .myClip(let clipID):
            LibraryClipScreen(clipID: clipID)
        case .clipList(let source, let start):
            ClipsViewer(source: ClipSource(source), start: start)
        case .makeChat(let creationID):
            G4CreateChatScreen(creationID: creationID)
        case .makePreview(let creationID):
            G4CreatePreviewScreen(creationID: creationID)
        case .notifications:
            CommunityNotificationsScreen()
        case .story(let index):
            CommunityStoryScreen(start: index)
        case .rate(let gameID):
            CommunityRatingSheet(gameID: gameID)
        case .friendVideos(let start):
            CommunityVideoPlayer(start: start)
        case .messages:
            MessagesInboxScreen()
        case .chat(let id):
            MessagesChatScreen(chatID: id)
        case .newGroup:
            MessagesNewGroupScreen()
        case .workplace:
            MessagesWorkplaceScreen()
        case .playTogether(let id):
            MessagesPlayTogetherSheet(chatID: id)
        case .buyGold:
            WhopBuyGoldSheet()
        case .earnings:
            WhopEarningsScreen()
        case .sendEarnings:
            WhopSendSheet()
        case .program(let gameID):
            WhopProgramSheet(game: Mock.game(gameID))
        }
    }
}

// MARK: Videos

/// The Videos tab: an endless column of clips, one to a screen. Only the clip on screen moves.
struct LiveVideos: View {
    @ObservedObject private var nav = LiveNav.shared
    @ObservedObject private var store = LiveStore.shared
    @ObservedObject private var made = CreateClips.shared

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
                    // Clips players posted come first, newest at the top, then the catalog clips.
                    let posted = made.feed
                    ForEach(0..<pageCount, id: \.self) { index in
                        Group {
                            if index < posted.count {
                                CreateClipPage(clip: posted[index], active: playing && nav.videoIndex == index)
                            } else {
                                LiveClipPage(clip: Mock.clips[(index - posted.count) % Mock.clips.count],
                                             active: playing && nav.videoIndex == index)
                            }
                        }
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
    /// A catalog clip can be saved. A friend's post shown on the same page cannot.
    var saveable = true
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
                    VideoPage(clip: clip, progress: CGFloat(phase), voted: vote, phase: phase, saveKey: saveKey)
                }
            } else {
                // At rest a clip shows its opening moment.
                VideoPage(clip: clip, progress: 0, voted: vote, phase: 0.02, saveKey: saveKey)
            }
        }
        .onChange(of: active) { _, isActive in
            if isActive { loopStart = Date() }
        }
    }

    private var saveKey: String? { saveable ? CreateClips.sampleKey(clip.id) : nil }
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
    /// Set for a room round the player chose to film.
    @State private var film: CreateFilmSession?
    @Environment(\.scenePhase) private var scenePhase

    init(game: MockGame, solo: Bool) {
        self.game = game
        self.solo = solo
        let timeSeed = UInt64(Date().timeIntervalSince1970 * 1000) & 0xFFFF_FFFF
        let roomSeed = LiveRoomRound.current.flatMap { $0.gameID == game.id ? $0.seed : nil }
        _options = State(initialValue: GameOptions(solo: solo, playerName: Mock.handle, friendNames: Mock.playFriends,
                                                   bestScore: LiveStore.shared.s.best[game.id] ?? 0,
                                                   seed: roomSeed ?? LiveLaunch.seed ?? timeSeed))
        _film = State(initialValue: roomSeed != nil && CreateFilm.wanted ? CreateFilmSession() : nil)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            GameSurface(scale: LiveLaunch.gameScale ?? 1) {
                GameFactory.view(for: game.kind, options: options, link: link)
            }
            .ignoresSafeArea()
            if let film { CreateFilmBubble(session: film) }
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
        .onDisappear {
            TouchWatcher.remove()
            CommunityStore.shared.stopPresence()
        }
        .onChange(of: scenePhase) { _, phase in
            // Leaving the app pauses the round. The prompt is waiting on return.
            if phase != .active && !link.isFinished {
                link.paused = true
                asking = true
            }
        }
    }

    private func begin() {
        // Play time counts from the first touch, and a game playing itself for a recording never gets one.
        let clock = self.clock
        TouchWatcher.install { clock.start() }
        if GameDemo.autopilot { clock.start() }
        CommunityStore.shared.startPresence(game.id)
        if let film { Task { await film.begin() } }
        link.onFinish = { [weak link = self.link] result in
            TouchWatcher.remove()
            LiveRoomRound.report(result.score)
            let summary = LiveStore.shared.finishRound(game: game, seconds: clock.seconds, gold: link?.gold ?? 0, result: result,
                                                       solo: solo, completed: true)
            if summary.gold > 0 { UINotificationFeedbackGenerator().notificationOccurred(.success) }
            CommunityStore.shared.roundEnded(summary)
            guard let film else { return LiveNav.shared.replaceTop(.results) }
            // A filmed round goes to its clip, ready to caption and post.
            let seconds = clock.seconds
            Task { @MainActor in
                let url = await film.finish()
                CreateClips.shared.take = CreateTake(gameID: game.id, layout: .bubble, videoURL: url,
                                                     cameraOnly: film.cameraOnly, result: result,
                                                     isBest: summary.isBest, seconds: seconds)
                LiveNav.shared.replaceTop(.createPreview)
            }
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

    /// Leaving early still keeps the gold the round has given. The round has no score and does not count for the streak.
    private func leave() {
        film?.discard()
        LiveRoomRound.report(0)
        if clock.seconds > 0 {
            LiveStore.shared.finishRound(game: game, seconds: clock.seconds, gold: link.gold,
                                         result: GameResult(score: 0, unit: ""), solo: solo, completed: false)
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

/// The gold counter on a running game. It drives the clock, so nothing else redraws five times a second,
/// and each tick of the clock is when it reads the gold the game has given.
struct PlayGoldHUD: View {
    @ObservedObject var clock: PlayClock
    @ObservedObject var link: GameLink
    let game: MockGame
    @ObservedObject private var store = LiveStore.shared
    private let ticks = Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()

    var body: some View {
        let pending = store.pending(for: game, seconds: clock.seconds, gold: link.gold)
        SessionGoldHUD(collected: pending.gold, dayShare: pending.dayShare)
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
///   -tab <0...4>        open on a tab: 0 Community, 1 Reels (the default), 2 You, 3 Messages, 4 Library
///   -scroll bottom      in the Library, open scrolled to the end
///   -video <n>          the clip showing in Videos
///   -play <game id>     open straight into a game (-solo 1 to play alone, -seed <n> for a fixed round)
///   -route <name>       open a screen: gold, history, streak, search, inbox, settings, saveGold, notify, studio,
///                       reviewProgress, reviewResult, reviewChanges, makeGame, or one that takes a value:
///                       gameReady:<game id>, gameDetail:<game id>, leaderboard:<game id>, comments:<clip id>,
///                       fairness:<game id>, spend:<n>, shareRun:<game id>, publish:<step>,
///                       create[:<game id>], join, startRoom, profile:<handle>, room:<code>,
///                       libraryGame:<game id>, myClip:<clip id>,
///                       messages, chat:<chat id>, newGroup, workplace,
///                       makeChat:<creation id>, makePreview:<creation id>,
///                       shop, shop:closet, shop:<item id> (opens that item's sheet),
///                       buyGold, earnings, sendEarnings, program:<game id>
///   -tryon <item id>    in the Shop, try an item on without opening its sheet
///   -shopturn 1         in the Shop, turn the Dailie round to show its back
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
        case "account": return .account(nil)
        case "saveGold": return .saveGold
        case "notify": return .notify
        case "studio": return .studio
        case "reviewProgress": return .reviewProgress
        case "reviewResult": return .reviewResult
        case "reviewChanges": return .reviewChanges
        case "makeGame": return .makeGame
        case "makeChat": return .makeChat(value)
        case "makePreview": return .makePreview(value)
        case "gameReady": return .gameReady(value)
        case "gameDetail": return .gameDetail(value)
        case "leaderboard": return .leaderboard(value)
        case "comments": return .comments(value)
        case "fairness": return .fairness(value)
        case "shareRun": return .shareRun(value)
        case "spend": return .spend(Int(value) ?? 1)
        case "publish": return .publish(Int(value) ?? 1)
        case "create": return .create(value.isEmpty ? nil : value)
        case "join": return .join
        case "startRoom": return .startRoom
        case "profile": return .profile(value.isEmpty ? "me" : value)
        case "room": return .room(value)
        case "friendVideos": return .friendVideos(value)
        case "libraryGame": return .libraryGame(value)
        case "myClip": return .myClip(value)
        case "shop": return .shop(value.isEmpty ? nil : value)
        case "messages": return .messages
        case "chat": return .chat(value)
        case "newGroup": return .newGroup
        case "workplace": return .workplace
        case "buyGold": return .buyGold
        case "earnings": return .earnings
        case "sendEarnings": return .sendEarnings
        case "program": return .program(value)
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
        case .gameReady, .play, .results, .gameDetail, .profile, .shop, .create, .createPreview, .story, .friendVideos: .lightContent
        case nil: LiveNav.shared.tab == 1 ? .lightContent : .default
        default: .default
        }
    }

    override var prefersStatusBarHidden: Bool { LiveNav.shared.isPlaying }
    override var prefersHomeIndicatorAutoHidden: Bool { LiveNav.shared.isPlaying }
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { LiveNav.shared.isPlaying ? .all : [] }
}
