import SwiftUI
import UIKit
import Combine
import PhotosUI
import CoreTransferable
import UniformTypeIdentifiers
import ConvexMobile

// CREATE, the camera the gold Plus opens. Like a video app's camera, but the effects are the games:
// pick one in the carousel, record, and the recording holds your face and your round together.

/// The gold Plus that opens the camera.
struct CreatePlusButton: View {
    var body: some View {
        Image(systemName: "plus")
            .font(.system(size: 17, weight: .black))
            .foregroundStyle(DL.onGold)
            .frame(width: 40, height: 40)
            .background(DL.gold, in: Circle())
    }
}

/// A game as a round icon, for the carousel and the game pill.
struct CreateGameIcon: View {
    let game: MockGame
    var size: CGFloat = 62

    var body: some View {
        ClipStill(game: game, showHUD: false, focusY: 0.35)
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1))
    }
}

enum CreateLength: String, CaseIterable {
    case long = "60s", short = "15s", photo = "PHOTO"

    var seconds: Double { self == .short ? 15 : 60 }
}

/// A rounded dark backing for controls that sit on the camera.
private struct CreateGlass: ViewModifier {
    func body(content: Content) -> some View {
        content.background(Capsule().fill(.black.opacity(0.5)))
    }
}

struct CreateCameraScreen: View {
    let startGameID: String?

    private enum Phase: Equatable { case idle, countdown(Int), starting, recording, finishing }
    private enum Recording { case none, screen, camera }
    private enum Corner { case topLeading, topTrailing, bottomLeading, bottomTrailing }

    @StateObject private var camera = CreateCamera()
    @ObservedObject private var store = LiveStore.shared
    @Environment(\.scenePhase) private var scenePhase

    @State private var order: [MockGame] = Mock.games
    @State private var centeredID: String?
    @State private var userPicked = false
    @State private var cleared = false
    @State private var layout: CreateLayout = .cutout
    @State private var length: CreateLength = .long
    @State private var timer = 0
    @State private var flash = false
    @State private var railOpen = true
    @State private var phase: Phase = .idle
    @State private var link: GameLink
    @State private var options: GameOptions
    @State private var recording: Recording = .none
    @State private var recordGameID = ""
    @State private var recordStart = Date()
    @State private var roundID: String?
    @State private var token = UUID()
    @State private var nameShown = false
    @State private var nameToken = UUID()
    @State private var toast: String?
    @State private var toastToken = UUID()
    @State private var corner: Corner = .topTrailing
    @State private var drag: CGSize = .zero
    /// Where the cutout's centre sits, as a fraction of the card. Pinching changes its size.
    @State private var cutoutAt = CGPoint(x: 0.5, y: 0.62)
    @State private var cutoutScale: CGFloat = 0.62
    @State private var pinch: CGFloat = 1
    @State private var frozen: UIImage?
    @State private var snapping = false
    @State private var shutter = false
    @State private var cardRect: CGRect = .zero
    @State private var picked: PhotosPickerItem?
    @State private var historyWatch: AnyCancellable?

    init(startGameID: String?) {
        self.startGameID = startGameID
        let resting = GameLink()
        resting.paused = true
        _link = State(initialValue: resting)
        _options = State(initialValue: GameOptions(solo: true, playerName: Mock.handle, friendNames: Mock.playFriends, seed: 1))
        _centeredID = State(initialValue: startGameID ?? Mock.games.first?.id)
        _userPicked = State(initialValue: startGameID != nil)
    }

    private var selected: MockGame? {
        guard !cleared, let centeredID else { return nil }
        return order.first { $0.id == centeredID }
    }

    private var isRecording: Bool { phase == .recording || phase == .finishing }
    /// Before a recording every control shows. From the countdown on only the game, the face and the stop button do.
    private var chromeShown: Bool { phase == .idle && !snapping }

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                card(geo.size)
                    .onAppear { cardRect = geo.frame(in: .global) }
                    .onChange(of: geo.frame(in: .global)) { _, rect in cardRect = rect }
            }
            .clipShape(RoundedRectangle(cornerRadius: DL.cardRadius, style: .continuous))
            modes
        }
        .background(Color.black.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .onAppear(perform: appear)
        .onDisappear(perform: disappear)
        .onChange(of: centeredID) { _, _ in gameChanged() }
        .onChange(of: picked) { _, item in if let item { importClip(item) } }
        .onChange(of: scenePhase) { _, now in
            if now != .active && phase == .recording { Task { await end(result: nil) } }
        }
    }

    // MARK: The card

    private func card(_ size: CGSize) -> some View {
        ZStack {
            Color.black
            stage(size)
            if chromeShown { idleChrome(size) }
            if phase == .recording || phase == .finishing { recordingChrome }
            if case .countdown(let beat) = phase {
                Text("\(beat)")
                    .font(DL.display(180))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.4), radius: 12)
                    .id(beat)
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
            }
            if camera.access == .denied && chromeShown { deniedCard }
            if let toast {
                Text(toast)
                    .font(DL.label(13)).foregroundStyle(.white).textCase(.uppercase)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .modifier(CreateGlass())
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    .allowsHitTesting(false)
            }
            if shutter { Color.white.opacity(0.85).allowsHitTesting(false).transition(.opacity) }
        }
    }

    /// The game fills the card. The player sits on it: cut out of the background, or in a bubble.
    private func stage(_ size: CGSize) -> some View {
        let w = size.width, h = size.height
        let bubble: CGFloat = 120
        let rect: CGRect
        switch layout {
        case .cutout:
            let width = w * min(1.1, max(0.3, cutoutScale * pinch))
            let height = width * 16 / 9
            rect = CGRect(x: cutoutAt.x * w - width / 2, y: cutoutAt.y * h - height / 2, width: width, height: height)
        case .bubble:
            let left = corner == .topLeading || corner == .bottomLeading
            let top = corner == .topLeading || corner == .topTrailing
            let x = left ? 16 + bubble / 2 : w - 16 - bubble / 2
            let y = top ? 76 + bubble / 2 : h - 210 - bubble / 2
            rect = CGRect(x: x - bubble / 2, y: y - bubble / 2, width: bubble, height: bubble)
        }
        let isBubble = layout == .bubble
        return ZStack {
            gameView.frame(width: w, height: h)
            cameraView(layout: layout)
                .frame(width: rect.width, height: rect.height)
                .clipShape(RoundedRectangle(cornerRadius: isBubble ? bubble / 2 : 0, style: .continuous))
                .overlay {
                    if isBubble { Circle().strokeBorder(.white.opacity(0.8), lineWidth: 2) }
                }
                .contentShape(isBubble ? AnyShape(Circle()) : AnyShape(Rectangle()))
                .offset(drag)
                .position(x: rect.midX, y: rect.midY)
                .gesture(isBubble ? AnyGesture(bubbleDrag(size).map { _ in () }) : cutoutMove(size))
                // While recording every touch goes to the game.
                .allowsHitTesting(phase == .idle)
        }
        .frame(width: w, height: h)
        .clipped()
        .animation(.snappy(duration: 0.4), value: layout)
        .animation(.snappy(duration: 0.35), value: corner)
    }

    /// Drag to move the cutout, pinch to size it.
    private func cutoutMove(_ size: CGSize) -> AnyGesture<Void> {
        let move = DragGesture()
            .onChanged { drag = $0.translation }
            .onEnded { value in
                cutoutAt = CGPoint(x: min(0.95, max(0.05, cutoutAt.x + value.translation.width / size.width)),
                                   y: min(0.95, max(0.1, cutoutAt.y + value.translation.height / size.height)))
                drag = .zero
            }
        let size = MagnifyGesture()
            .onChanged { pinch = $0.magnification }
            .onEnded { value in
                cutoutScale = min(1.1, max(0.3, cutoutScale * value.magnification))
                pinch = 1
            }
        return AnyGesture(move.simultaneously(with: size).map { _ in () })
    }

    @ViewBuilder private var gameView: some View {
        if let game = selected ?? (isRecording ? Mock.game(recordGameID) : nil) {
            GameFactory.view(for: game.kind, options: options, link: link)
                .allowsHitTesting(phase == .recording)
        } else {
            Text("Pick a game below")
                .font(DL.label(12)).foregroundStyle(.white.opacity(0.7)).textCase(.uppercase)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.35))
        }
    }

    @ViewBuilder private func cameraView(layout: CreateLayout) -> some View {
        if !CreateCamera.hasHardware {
            if layout == .bubble {
                LinearGradient(colors: [DL.sunken, Color.black], startPoint: .top, endPoint: .bottom)
                    .overlay(Image(systemName: "camera.fill").font(.system(size: 22, weight: .semibold)).foregroundStyle(.white.opacity(0.6)))
            } else {
                // Where the player would stand: a dark silhouette over the game.
                VStack(spacing: 10) {
                    Spacer()
                    Image(systemName: "person.fill")
                        .resizable().scaledToFit()
                        .foregroundStyle(LinearGradient(colors: [DL.sunken, Color.black], startPoint: .top, endPoint: .bottom))
                        .opacity(0.85)
                        .padding(.horizontal, 10)
                    Text("Camera needs a real phone")
                        .dlLabel(11, color: .white)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(.black.opacity(0.6)))
                        .padding(.bottom, 8)
                }
            }
        } else {
            CreateCameraView(camera: camera, cutout: layout == .cutout)
                .overlay {
                    if let frozen, layout == .bubble { Image(uiImage: frozen).resizable().scaledToFill() }
                }
        }
    }

    private func bubbleDrag(_ size: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { drag = $0.translation }
            .onEnded { value in
                let start: CGPoint = switch corner {
                case .topLeading: CGPoint(x: 0, y: 0)
                case .topTrailing: CGPoint(x: size.width, y: 0)
                case .bottomLeading: CGPoint(x: 0, y: size.height)
                case .bottomTrailing: CGPoint(x: size.width, y: size.height)
                }
                let x = start.x + value.predictedEndTranslation.width
                let y = start.y + value.predictedEndTranslation.height
                let left = x < size.width / 2, top = y < size.height / 2
                withAnimation(.snappy(duration: 0.35)) {
                    corner = top ? (left ? .topLeading : .topTrailing) : (left ? .bottomLeading : .bottomTrailing)
                    drag = .zero
                }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
    }

    // MARK: Before recording

    private func idleChrome(_ size: CGSize) -> some View {
        ZStack {
            VStack(spacing: 0) {
                topBar
                HStack(alignment: .top) {
                    Spacer()
                    rail
                }
                .padding(.trailing, 12).padding(.top, 10)
                Spacer()
            }
            if selected != nil {
                Text(length == .photo ? "TAP FOR A PHOTO" : "RECORD TO START")
                    .font(DL.display(24)).tracking(0.6)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 6)
                    .background(Capsule().fill(.black.opacity(0.8)))
                    .allowsHitTesting(false)
            }
            VStack(spacing: 12) {
                Spacer()
                if let game = selected {
                    Text(game.title.uppercased())
                        .font(DL.display(30)).foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.5), radius: 6)
                        .opacity(nameShown ? 1 : 0)
                        .animation(.easeOut(duration: 0.25), value: nameShown)
                        .allowsHitTesting(false)
                }
                lengths
                recordRow(width: size.width)
            }
            .padding(.bottom, 14)
        }
        .transition(.opacity)
    }

    private var topBar: some View {
        ZStack {
            HStack {
                DLMediaButton(symbol: "xmark", size: 40)
                    .tap { LiveNav.shared.back() }
                    .accessibilityLabel("Close")
                Spacer()
            }
            gamePill
        }
        .padding(.horizontal, 14).padding(.top, 12)
    }

    @ViewBuilder private var gamePill: some View {
        if let game = selected {
            HStack(spacing: 8) {
                CreateGameIcon(game: game, size: 24)
                Text(game.title).font(DL.text(15, .semibold)).foregroundStyle(.white).lineLimit(1)
                Rectangle().fill(.white.opacity(0.3)).frame(width: 1, height: 16)
                Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation(.snappy) { cleared = true } }
                    .accessibilityLabel("Clear the game")
            }
            .padding(.leading, 6).padding(.trailing, 10)
            .frame(height: 38)
            .modifier(CreateGlass())
        } else {
            HStack(spacing: 7) {
                Image(systemName: "gamecontroller.fill").font(.system(size: 14, weight: .semibold))
                Text("Add a game").font(DL.text(15, .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(height: 38)
            .modifier(CreateGlass())
            .tap { withAnimation(.snappy) { cleared = false } }
        }
    }

    private var rail: some View {
        VStack(spacing: 14) {
            if railOpen {
                DLMediaButton(symbol: "arrow.triangle.2.circlepath.camera", size: 44)
                    .tap(flipCamera).accessibilityLabel("Flip camera")
                DLMediaButton(symbol: flash ? "bolt.fill" : "bolt.slash.fill", size: 44)
                    .tap(toggleFlash).accessibilityLabel("Flash")
                DLMediaButton(symbol: "timer", size: 44)
                    .overlay(alignment: .bottomTrailing) {
                        if timer > 0 {
                            Text("\(timer)s").font(DL.label(9)).foregroundStyle(DL.onGold)
                                .padding(.horizontal, 4).padding(.vertical, 1)
                                .background(DL.gold, in: Capsule())
                                .offset(x: 4, y: 2)
                        }
                    }
                    .tap(cycleTimer).accessibilityLabel("Timer")
                DLMediaButton(symbol: layout.symbol, size: 44)
                    .tap(cycleLayout).accessibilityLabel("Layout")
            }
            DLMediaButton(symbol: railOpen ? "chevron.up" : "chevron.down", size: 44)
                .tap { withAnimation(.snappy(duration: 0.3)) { railOpen.toggle() } }
                .accessibilityLabel(railOpen ? "Hide tools" : "Show tools")
        }
    }

    private var lengths: some View {
        HStack(spacing: 6) {
            ForEach(CreateLength.allCases, id: \.self) { option in
                let on = option == length
                Text(option.rawValue)
                    .font(DL.label(13))
                    .foregroundStyle(on ? DL.onGold : .white)
                    .padding(.horizontal, 14)
                    .frame(height: 32)
                    .background {
                        if on { Capsule().fill(DL.surface).environment(\.colorScheme, .light) }
                    }
                    .contentShape(Capsule())
                    .onTapGesture {
                        UISelectionFeedbackGenerator().selectionChanged()
                        withAnimation(.snappy(duration: 0.25)) { length = option }
                    }
            }
        }
    }

    /// The carousel of games, with the record ring over the centre one and the camera roll at the right.
    private func recordRow(width: CGFloat) -> some View {
        let icon: CGFloat = 62
        return ZStack {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 18) {
                    ForEach(order) { game in
                        CreateGameIcon(game: game, size: icon)
                            .scrollTransition(.interactive.threshold(.centered), axis: .horizontal) { content, phase in
                                content.scaleEffect(1.2 - 0.2 * min(1, abs(phase.value)))
                            }
                            .id(game.id)
                            .onTapGesture {
                                userPicked = true
                                withAnimation(.snappy(duration: 0.35)) { centeredID = game.id }
                            }
                            .accessibilityLabel(game.title)
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, (width - icon) / 2, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: Binding(get: { centeredID }, set: { id in
                userPicked = true
                centeredID = id
            }), anchor: .center)
            .frame(height: 100)

            recordButton

            HStack {
                Spacer()
                PhotosPicker(selection: $picked, matching: .videos) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.black.opacity(0.55))
                        .overlay(Image(systemName: "photo.on.rectangle").font(.system(size: 18, weight: .semibold)).foregroundStyle(.white))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.7), lineWidth: 1.5))
                        .frame(width: 48, height: 48)
                }
                .accessibilityLabel("Post a clip from your camera roll")
            }
            .padding(.trailing, 18)
        }
        .frame(height: 100)
    }

    /// The ring around the centre game. Recording turns it into a gold stop square with the time running round it.
    private var recordButton: some View {
        let on = phase == .recording || phase == .finishing
        let fraction: (Date) -> Double = { now in min(1, now.timeIntervalSince(recordStart) / length.seconds) }
        return ZStack {
            Circle().strokeBorder(.white.opacity(on ? 0.35 : 1), lineWidth: 5)
            if on {
                TimelineView(.animation) { timeline in
                    Circle().inset(by: 2.5)
                        .trim(from: 0, to: max(0.001, fraction(timeline.date)))
                        .stroke(DL.gold, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
            }
            RoundedRectangle(cornerRadius: on ? 9 : 38, style: .continuous)
                .fill(DL.gold)
                .frame(width: on ? 34 : 76, height: on ? 34 : 76)
                .opacity(on ? 1 : 0)
        }
        .frame(width: 92, height: 92)
        .animation(.spring(duration: 0.4, bounce: 0.3), value: on)
        .contentShape(Circle())
        .onTapGesture(perform: recordTapped)
        .accessibilityLabel(on ? "Stop" : (length == .photo ? "Take a photo" : "Record"))
        .accessibilityAddTraits(.isButton)
    }

    private var deniedCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CAMERA IS OFF").font(DL.display(30)).foregroundStyle(DL.ink)
            Text("DEGEN needs your camera to film you playing")
                .font(DL.text(16)).foregroundStyle(DL.ink2)
                .fixedSize(horizontal: false, vertical: true)
            DLTextKey(title: "Open Settings", symbol: "gearshape.fill")
                .tap {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
        }
        .dlCard(padding: 20, fill: DL.raised)
        .padding(.horizontal, 28)
    }

    // MARK: While recording

    private var recordingChrome: some View {
        VStack {
            TimelineView(.periodic(from: recordStart, by: 0.5)) { timeline in
                let seconds = max(0, Int(timeline.date.timeIntervalSince(recordStart)))
                HStack(spacing: 7) {
                    Circle().fill(DL.danger).frame(width: 9, height: 9)
                    Text(String(format: "%d:%02d", seconds / 60, seconds % 60))
                        .font(DL.label(13)).monospacedDigit().foregroundStyle(.white)
                }
                .padding(.horizontal, 12).frame(height: 30)
                .modifier(CreateGlass())
            }
            .padding(.top, 14)
            Spacer()
            recordButton.padding(.bottom, 18)
        }
    }

    // MARK: Below the card

    private var modes: some View {
        HStack(spacing: 28) {
            Text("CAMERA").foregroundStyle(.white)
            Text("GAME").foregroundStyle(.white.opacity(0.5))
                .onTapGesture { if phase == .idle { LiveNav.shared.open(.makeGame) } }
            Text("LIVE").foregroundStyle(.white.opacity(0.5))
                .onTapGesture { if phase == .idle { LiveNav.shared.say("Live rooms are not part of this build yet") } }
        }
        .font(DL.label(14))
        .frame(height: 54)
        .opacity(chromeShown ? 1 : 0)
    }

    // MARK: Actions

    private func appear() {
        Task { await camera.start(ownAudio: !CreateScreenRecorder.isAvailable) }
        camera.cutout = layout == .cutout
        historyWatch = ConvexLink.shared.watch("rounds:history", as: [CreateHistoryRow].self) { rows in
            var counts: [String: Int] = [:]
            for row in rows { counts[row.gameSlug, default: 0] += 1 }
            let ranked = Mock.games.enumerated().sorted { a, b in
                let ca = counts[a.element.id] ?? 0, cb = counts[b.element.id] ?? 0
                return ca != cb ? ca > cb : a.offset < b.offset
            }.map(\.element)
            guard phase == .idle else { return }
            order = ranked
            if !userPicked { centeredID = ranked.first?.id }
        }
    }

    private func disappear() {
        historyWatch?.cancel()
        camera.stop()
        if phase == .recording { CreateScreenRecorder.discard() }
    }

    private func gameChanged() {
        cleared = false
        UISelectionFeedbackGenerator().selectionChanged()
        nameShown = true
        let mine = UUID()
        nameToken = mine
        Task {
            try? await Task.sleep(for: .seconds(1.3))
            if nameToken == mine { nameShown = false }
        }
    }

    private func say(_ text: String) {
        let mine = UUID()
        toastToken = mine
        withAnimation(.snappy(duration: 0.2)) { toast = text }
        Task {
            try? await Task.sleep(for: .seconds(1.4))
            if toastToken == mine { withAnimation(.easeOut(duration: 0.25)) { toast = nil } }
        }
    }

    private func flipCamera() {
        guard CreateCamera.hasHardware else { return say("Camera needs a real phone") }
        flash = false
        camera.flip()
    }

    private func toggleFlash() {
        guard CreateCamera.hasHardware else { return say("Camera needs a real phone") }
        if camera.setFlash(!flash) {
            flash.toggle()
            say(flash ? "Flash on" : "Flash off")
        } else {
            say("Flash works with the back camera")
        }
    }

    private func cycleTimer() {
        timer = timer == 0 ? 3 : (timer == 3 ? 10 : 0)
        say(timer == 0 ? "Timer off" : "\(timer) second timer")
    }

    private func cycleLayout() {
        layout = layout.next
        camera.cutout = layout == .cutout
        drag = .zero
        say(layout.title)
    }

    private func recordTapped() {
        switch phase {
        case .idle: Task { await begin() }
        case .recording: Task { await end(result: nil) }
        default: break
        }
    }

    private func begin() async {
        guard let game = selected else { return say("Pick a game first") }
        let mine = UUID()
        token = mine
        recordGameID = game.id
        for beat in stride(from: timer, to: 0, by: -1) {
            withAnimation(.spring(duration: 0.35, bounce: 0.45)) { phase = .countdown(beat) }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            try? await Task.sleep(for: .seconds(1))
            guard token == mine else { return }
        }
        if length == .photo { return await takePhoto(game) }
        withAnimation(.easeOut(duration: 0.2)) { phase = .starting }

        let day = LiveStore.dayKey(Date())
        async let opened = CreateWait.within(6) {
            try await ConvexLink.shared.mutate("rounds:start", ["slug": game.id, "day": day], as: ConvexRoundStart.self)
        }
        var kind: Recording = .none
        if CreateScreenRecorder.isAvailable, (try? await CreateScreenRecorder.start(mic: camera.micGranted)) != nil {
            kind = .screen
        } else if CreateCamera.hasHardware && camera.access == .granted {
            camera.startRecording()
            kind = .camera
        }
        let started = await opened
        guard token == mine else { return }

        let round = GameLink()
        round.onFinish = { result in Task { @MainActor in await end(result: result) } }
        let seed = started.map { UInt64(max(1, $0.seed)) } ?? (UInt64(Date().timeIntervalSince1970 * 1000) & 0xFFFF_FFFF)
        options = GameOptions(solo: game.playerRange.lowerBound == 1, playerName: store.me?.handle ?? Mock.handle,
                              friendNames: Mock.playFriends, bestScore: store.s.best[game.id] ?? 0, seed: seed)
        link = round
        roundID = started?.roundId
        recording = kind
        recordStart = Date()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.spring(duration: 0.4, bounce: 0.3)) { phase = .recording }

        let limit = length.seconds
        Task {
            try? await Task.sleep(for: .seconds(limit))
            if token == mine && phase == .recording { await end(result: nil) }
        }
    }

    /// Ends the recording: when the round ends, when the time runs out, or on stop.
    private func end(result: GameResult?) async {
        guard phase == .recording else { return }
        phase = .finishing
        link.paused = true
        let seconds = Date().timeIntervalSince(recordStart)
        var url: URL?
        switch recording {
        case .screen:
            do { url = try await CreateScreenRecorder.stop() } catch {
                CreateScreenRecorder.log.error("Screen recording failed: \(String(describing: error), privacy: .public)")
            }
        case .camera: url = await camera.stopRecording()
        case .none: break
        }

        // The same call the play screen makes, so gold and bests count. A round stopped early has no score.
        var isBest = false
        if let roundID {
            var args: [String: ConvexEncodable?] = [
                "roundId": roundID,
                "score": Double(result?.score ?? 0),
                "activeMs": (seconds * 1000).rounded(),
            ]
            if let result, !result.unit.isEmpty { args["unit"] = result.unit }
            if let result, result.score > 0 { args["scoreText"] = result.scoreText ?? groupedNumber(result.score) }
            let answer = await CreateWait.within(8) {
                try await ConvexLink.shared.mutate("rounds:finish", args, as: ConvexRoundFinish.self)
            }
            isBest = answer?.newBest ?? false
            if (answer?.gold ?? 0) > 0 { UINotificationFeedbackGenerator().notificationOccurred(.success) }
        }

        CreateClips.shared.take = CreateTake(gameID: recordGameID, layout: layout, videoURL: url,
                                             cameraOnly: recording == .camera, roundID: roundID, result: result,
                                             isBest: isBest, seconds: seconds)
        LiveNav.shared.replaceTop(.createPreview)
    }

    /// A still of the card: the camera and the game as they are on screen.
    private func takePhoto(_ game: MockGame) async {
        phase = .finishing
        snapping = true
        frozen = camera.still()
        try? await Task.sleep(for: .milliseconds(120))
        let shot = CreateFiles.snapshotScreen().flatMap { crop($0, to: cardRect) }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.easeOut(duration: 0.08)) { shutter = true }
        try? await Task.sleep(for: .milliseconds(140))
        withAnimation(.easeOut(duration: 0.25)) { shutter = false }
        CreateClips.shared.take = CreateTake(gameID: game.id, layout: layout, photo: shot)
        LiveNav.shared.replaceTop(.createPreview)
    }

    private func crop(_ image: UIImage, to rect: CGRect) -> UIImage? {
        guard let cg = image.cgImage, rect.width > 0 else { return image }
        let scale = image.scale
        let pixels = CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale)
        guard let cut = cg.cropping(to: pixels) else { return image }
        return UIImage(cgImage: cut, scale: scale, orientation: .up)
    }

    /// A clip from the camera roll, posted under the game in the carousel.
    private func importClip(_ item: PhotosPickerItem) {
        let gameID = selected?.id ?? order.first?.id ?? Mock.tippyTower.id
        Task {
            defer { picked = nil }
            guard let movie = try? await item.loadTransferable(type: CreateMovie.self) else {
                return say("Could not open that video")
            }
            CreateClips.shared.take = CreateTake(gameID: gameID, layout: layout, videoURL: movie.url)
            LiveNav.shared.replaceTop(.createPreview)
        }
    }
}

/// One row of `rounds:history`; only the game counts here.
struct CreateHistoryRow: Decodable {
    let gameSlug: String
}

/// A video picked from the camera roll, copied somewhere the app can read it.
struct CreateMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let copy = CreateFiles.newURL(received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension)
            try FileManager.default.copyItem(at: received.file, to: copy)
            return CreateMovie(url: copy)
        }
    }
}

enum CreateWait {
    /// The answer of `work`, or nil if it fails or takes longer than `seconds`.
    static func within<T>(_ seconds: Double, _ work: @escaping () async throws -> T) async -> T? {
        let gate = Gate()
        return await withCheckedContinuation { (done: CheckedContinuation<T?, Never>) in
            Task {
                let value = try? await work()
                gate.once { done.resume(returning: value) }
            }
            Task {
                try? await Task.sleep(for: .seconds(seconds))
                gate.once { done.resume(returning: nil) }
            }
        }
    }

    private final class Gate {
        private let lock = NSLock()
        private var passed = false

        func once(_ action: () -> Void) {
            lock.lock()
            defer { lock.unlock() }
            guard !passed else { return }
            passed = true
            action()
        }
    }
}

/// GAME under the camera: making games is coming.
struct CreateMakeGameScreen: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            DLIconButton(symbol: "xmark").goesBack().accessibilityLabel("Close")
            Spacer()
            Text("MAKE A GAME").font(DL.display(48)).foregroundStyle(DL.ink)
            Text("Soon you can make a small game here and send it to friends. For now, film yourself playing one.")
                .font(DL.text(17)).foregroundStyle(DL.ink2)
                .fixedSize(horizontal: false, vertical: true)
            DLTextKey(title: "Back to the camera", symbol: "camera.fill", style: .neutral).goesBack()
            Spacer()
        }
        .padding(.horizontal, DL.margin)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(DL.body.ignoresSafeArea())
    }
}
