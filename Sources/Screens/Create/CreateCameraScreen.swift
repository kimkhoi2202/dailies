import SwiftUI
import UIKit
import Combine
import PhotosUI
import CoreTransferable
import UniformTypeIdentifiers
import ConvexMobile

// CREATE, the camera the gold Plus opens. Like a video app's camera, but the effects are the games:
// pick one on the rail, record, and the recording holds your face and your round together.

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

/// A game as a round icon, for the rail and its game panel.
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
    case long = "60s", short = "15s", unlimited = "UNLIMITED", photo = "PHOTO"

    /// The rail's picture for it. A timed length also wears its seconds as a badge.
    var symbol: String {
        switch self {
        case .long, .short: "hourglass"
        case .unlimited: "infinity"
        case .photo: "camera.fill"
        }
    }

    /// nil records until the player stops.
    var seconds: Double? {
        switch self {
        case .short: 15
        case .long: 60
        case .unlimited, .photo: nil
        }
    }
}

/// How the player sits on the game, picked from Layout on the rail.
enum CreateShape: CaseIterable {
    case circle, square, tall, wide, greenScreen

    var title: String {
        switch self {
        case .circle: "Circle"
        case .square: "Square"
        case .tall: "Tall"
        case .wide: "Cam on top"
        case .greenScreen: "Green screen"
        }
    }

    /// Cam on top is the band across the top, with no outline. Green screen cuts the player out of their background.
    var layout: CreateLayout {
        switch self {
        case .circle: .bubble
        case .square, .tall: .window
        case .wide: .top
        case .greenScreen: .cutout
        }
    }

    var symbol: String {
        switch self {
        case .circle: "circle"
        case .square: "square"
        case .tall: "rectangle.portrait"
        case .wide: "rectangle.tophalf.filled"
        case .greenScreen: "person.fill"
        }
    }
}

/// Where the player sits and how big they are, for each layout. Kept apart from the camera screen and read only
/// by the player's own view, so moving and sizing them redraws the player and never the game underneath.
@Observable final class CreateFace {
    var at: [CreateLayout: CGPoint] = [.cutout: CGPoint(x: 0.5, y: 0.62), .window: CGPoint(x: 0.5, y: 0.68),
                                       .bubble: CGPoint(x: 0.78, y: 0.2)]
    var scale: [CreateLayout: CGFloat] = [.cutout: 0.62, .window: 0.42, .bubble: 1]
    /// The finger's travel during a drag, and the pinch's size during a pinch.
    var drag: CGSize = .zero
    var pinch: CGFloat = 1

    func rect(_ layout: CreateLayout, square: Bool = false, in size: CGSize) -> CGRect {
        let w = size.width, h = size.height
        let at = at[layout] ?? CGPoint(x: 0.5, y: 0.5)
        let scale = scale[layout] ?? 1
        if layout == .bubble {
            let side = min(w * 0.9, max(72, 120 * scale * pinch))
            return CGRect(x: at.x * w - side / 2, y: at.y * h - side / 2, width: side, height: side)
        }
        let width = w * min(1.1, max(0.25, scale * pinch))
        let height = square ? width : width * 16 / 9
        return CGRect(x: at.x * w - width / 2, y: at.y * h - height / 2, width: width, height: height)
    }

    /// Ends a pinch: the size it reached is kept.
    func keepPinch(_ layout: CreateLayout, _ magnification: CGFloat) {
        let now = (scale[layout] ?? 1) * magnification
        scale[layout] = layout == .bubble ? min(2.6, max(0.6, now)) : min(1.1, max(0.25, now))
        pinch = 1
    }
}

/// The player over the game, dragged with one finger. Pinching is caught by the whole card.
private struct CreateFaceView<Camera: View>: View {
    let face: CreateFace
    let layout: CreateLayout
    let size: CGSize
    let movable: Bool
    var square = false
    @ViewBuilder let camera: () -> Camera

    var body: some View {
        let rect = face.rect(layout, square: square, in: size)
        let corner: CGFloat = layout == .bubble ? rect.width / 2 : (layout == .window ? (square ? 18 : 22) : 0)
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        camera()
            .frame(width: rect.width, height: rect.height)
            .clipShape(shape)
            .overlay {
                if layout != .cutout { shape.strokeBorder(.white.opacity(0.85), lineWidth: 2) }
            }
            .contentShape(shape)
            .gesture(move)
            .offset(face.drag)
            .position(x: rect.midX, y: rect.midY)
            // While recording every touch goes to the game.
            .allowsHitTesting(movable)
    }

    /// The translation is measured on the screen, not on the moving view, so the view follows the finger
    /// without feeding its own movement back into the gesture.
    private var move: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { value in
                guard face.pinch == 1 else { return }
                var still = Transaction()
                still.disablesAnimations = true
                withTransaction(still) { face.drag = value.translation }
            }
            .onEnded { _ in
                let from = face.at[layout] ?? CGPoint(x: 0.5, y: 0.5)
                let moved = face.drag
                var still = Transaction()
                still.disablesAnimations = true
                withTransaction(still) {
                    face.at[layout] = CGPoint(x: from.x + moved.width / size.width, y: from.y + moved.height / size.height)
                    face.drag = .zero
                }
                // Pulled back on screen with a spring if it was let go past an edge.
                let to = face.at[layout] ?? from
                let kept = CGPoint(x: min(0.92, max(0.08, to.x)), y: min(0.92, max(0.08, to.y)))
                if kept != to {
                    withAnimation(.spring(duration: 0.35, bounce: 0.25)) { face.at[layout] = kept }
                }
            }
    }
}

/// A rounded dark backing for controls that sit on the camera.
private struct CreateGlass: ViewModifier {
    func body(content: Content) -> some View {
        content.background(Capsule().fill(.black.opacity(0.5)))
    }
}

/// What shows while a recording runs: a small gold stop key, whose ring is the time running, and the clock when
/// there is no limit for the ring to show. It is drawn in `CreateOverWindow`, so it is on the screen and never
/// in the clip.
private struct CreateRecordingControls: View {
    private static let ring: CGFloat = 92
    private static let scale: CGFloat = 0.7
    private static let inset: CGFloat = 14

    /// The safe part of the screen.
    let area: CGRect
    let start: Date
    /// nil records until the player stops, and the ring goes round once a minute.
    let limit: Double?
    let stop: () -> Void

    /// Where the stop key sits on the screen.
    static func stopRect(in area: CGRect) -> CGRect {
        let side = ring * scale
        return CGRect(x: area.midX - side / 2, y: area.maxY - inset - side, width: side, height: side)
    }

    var body: some View {
        VStack {
            if limit == nil {
                TimelineView(.periodic(from: start, by: 0.5)) { timeline in
                    let seconds = max(0, Int(timeline.date.timeIntervalSince(start)))
                    HStack(spacing: 6) {
                        Circle().fill(DL.danger).frame(width: 7, height: 7)
                        Text(String(format: "%d:%02d", seconds / 60, seconds % 60))
                            .font(DL.label(11)).monospacedDigit().foregroundStyle(.white)
                    }
                    .padding(.horizontal, 9).frame(height: 22)
                    .modifier(CreateGlass())
                }
                .padding(.top, 6)
            }
            Spacer()
            stopKey.scaleEffect(Self.scale, anchor: .bottom).padding(.bottom, Self.inset)
        }
        .frame(width: area.width, height: area.height)
        .position(x: area.midX, y: area.midY)
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
    }

    private var stopKey: some View {
        ZStack {
            Circle().strokeBorder(.white.opacity(0.35), lineWidth: 5)
            TimelineView(.animation) { timeline in
                Circle().inset(by: 2.5)
                    .trim(from: 0, to: max(0.001, fraction(timeline.date)))
                    .stroke(DL.gold, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(DL.gold)
                .frame(width: 34, height: 34)
        }
        .frame(width: Self.ring, height: Self.ring)
        .contentShape(Circle())
        .onTapGesture(perform: stop)
        .accessibilityLabel("Stop")
        .accessibilityAddTraits(.isButton)
    }

    private func fraction(_ now: Date) -> Double {
        let elapsed = now.timeIntervalSince(start)
        guard let limit else { return elapsed.truncatingRemainder(dividingBy: 60) / 60 }
        return min(1, elapsed / limit)
    }
}

struct CreateCameraScreen: View {
    let startGameID: String?

    private enum Phase: Equatable { case idle, countdown(Int), starting, recording, finishing }
    private enum Recording { case none, screen, camera }
    /// The rail buttons that open a panel of choices.
    private enum Tool { case game, layout, length, timer, more }

    @StateObject private var camera = CreateCamera()
    @ObservedObject private var store = LiveStore.shared
    @Environment(\.scenePhase) private var scenePhase

    @State private var order: [MockGame] = Mock.games
    @State private var centeredID: String?
    @State private var userPicked = false
    @State private var cleared = false
    @State private var shape: CreateShape = .circle
    /// How much of the card the camera band takes in Cam on top. Drag its edge or pinch to change it.
    @State private var topBand: CGFloat = 0.26
    @State private var bandStart: CGFloat?
    @State private var length: CreateLength = .long
    @State private var timer = 0
    @State private var flash = false
    /// The rail tool whose panel is open.
    @State private var open: Tool?
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
    /// Held as plain state and never read in this body, so dragging the player does not redraw the game.
    @State private var face = CreateFace()
    /// Game Off films only you, with the game you picked tagged on the clip. Game On films you over the game.
    @State private var gameOn = true
    /// Camera Off records only the game, for people who do not want to film themselves.
    @State private var cameraOn = false
    /// Whether the recording under way has the game in it, and the player.
    @State private var recordPlaying = false
    @State private var recordCamera = false
    @State private var frozen: UIImage?
    @State private var snapping = false
    @State private var shutter = false
    @State private var cardRect: CGRect = .zero
    /// The safe part of the screen, where the controls sit.
    @State private var chromeRect: CGRect = .zero
    @State private var picked: PhotosPickerItem?
    @State private var historyWatch: AnyCancellable?

    init(startGameID: String?) {
        self.startGameID = startGameID
        let resting = GameLink()
        resting.paused = true
        _link = State(initialValue: resting)
        _options = State(initialValue: Self.playOptions(Mock.game(startGameID ?? Mock.games.first?.id ?? ""), seed: 1))
        _centeredID = State(initialValue: startGameID ?? Mock.games.first?.id)
        _userPicked = State(initialValue: startGameID != nil)
        // `-gameOn 1` opens with the game on and `-layout <name>` picks the layout, for checking the camera without tapping.
        _gameOn = State(initialValue: MockArgs.value("-gameOn").map { $0 == "1" } ?? true)
        _shape = State(initialValue: MockArgs.value("-layout").flatMap { name in CreateShape.allCases.first { $0.layout.rawValue == name } } ?? .circle)
    }

    private var selected: MockGame? {
        guard !cleared, let centeredID else { return nil }
        return order.first { $0.id == centeredID }
    }

    private var isRecording: Bool { phase == .recording || phase == .finishing }
    private var layout: CreateLayout { shape.layout }
    /// Before a recording every control shows. From the countdown on only the game and the face do: the stop key
    /// and the clock sit in a window of their own, which the recording leaves out.
    private var chromeShown: Bool { phase == .idle && !snapping }

    var body: some View {
        // The picture runs edge to edge, under the status bar and down to the bottom of the screen, because a
        // recording is the whole screen. Only the controls keep to the safe area.
        GeometryReader { geo in
            let insets = geo.safeAreaInsets
            let screen = CGSize(width: geo.size.width + insets.leading + insets.trailing,
                                height: geo.size.height + insets.top + insets.bottom)
            let origin = geo.frame(in: .global).origin
            let full = CGRect(x: origin.x - insets.leading, y: origin.y - insets.top, width: screen.width, height: screen.height)
            ZStack(alignment: .topLeading) {
                stage(screen).offset(x: -insets.leading, y: -insets.top)
                chrome(geo.size)
                if shutter {
                    Color.white.opacity(0.85)
                        .frame(width: screen.width, height: screen.height)
                        .offset(x: -insets.leading, y: -insets.top)
                        .allowsHitTesting(false).transition(.opacity)
                }
            }
            .onAppear {
                cardRect = full
                chromeRect = geo.frame(in: .global)
            }
            .onChange(of: full) { _, rect in cardRect = rect }
            .onChange(of: geo.frame(in: .global)) { _, rect in chromeRect = rect }
        }
        .simultaneousGesture(facePinch, including: phase == .idle ? .all : .subviews)
        .background(Color.black.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .onAppear(perform: appear)
        .onDisappear(perform: disappear)
        .onChange(of: centeredID) { _, _ in gameChanged() }
        .onChange(of: picked) { _, item in if let item { importClip(item) } }
        .onChange(of: scenePhase) { _, now in
            if now != .active && phase == .recording { Task { await end(result: nil) } }
        }
        .onChange(of: phase) { _, now in
            if now == .recording {
                CreateOverWindow.show(CreateRecordingControls(area: chromeRect, start: recordStart, limit: length.seconds,
                                                              stop: recordTapped),
                                      touch: CreateRecordingControls.stopRect(in: chromeRect))
            } else if now != .finishing {
                CreateOverWindow.hide()
            }
        }
    }

    // MARK: Over the picture

    private func chrome(_ size: CGSize) -> some View {
        ZStack {
            if chromeShown { idleChrome(size) }
            if case .countdown(let beat) = phase {
                Text("\(beat)")
                    .font(DL.display(180))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.4), radius: 12)
                    .id(beat)
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
            }
            if camera.access == .denied && cameraOn && chromeShown { deniedCard }
            if let toast {
                Text(toast)
                    .font(DL.label(13)).foregroundStyle(.white).textCase(.uppercase)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .modifier(CreateGlass())
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    .allowsHitTesting(false)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    /// Game Off: the camera fills the screen. Game On: the game fills it and the player sits on it, cut out of
    /// their background, in a card with their background, in a bubble, or in a band across the top.
    /// Before recording, drag the player anywhere, and pinch with two fingers anywhere on the card to size them.
    private func stage(_ size: CGSize) -> some View {
        let w = size.width, h = size.height
        return ZStack(alignment: .top) {
            if !showsGame {
                cameraView(cutout: false).frame(width: w, height: h)
            } else if !showsCamera {
                gameView.frame(width: w, height: h)
            } else if layout == .top {
                VStack(spacing: 0) {
                    cameraView(cutout: false)
                        .frame(width: w, height: h * topBand).clipped()
                        .overlay(alignment: .bottom) { if phase == .idle { bandHandle(height: h) } }
                        .zIndex(1)
                    gameView.frame(width: w, height: h * (1 - topBand)).clipped()
                }
            } else {
                gameView.frame(width: w, height: h)
                CreateFaceView(face: face, layout: layout, size: size, movable: phase == .idle, square: shape == .square) {
                    cameraView(cutout: layout == .cutout)
                }
            }
        }
        .frame(width: w, height: h)
        .clipped()
        .animation(.snappy(duration: 0.4), value: showsGame)
        .animation(.snappy(duration: 0.4), value: showsCamera)
        .animation(.snappy(duration: 0.4), value: shape)
    }

    /// The game is on the card: Game On before recording, or a recording made with it.
    private var showsGame: Bool { isRecording ? recordPlaying : gameOn }
    private var showsCamera: Bool { isRecording ? recordCamera : cameraOn }

    /// The edge between the camera band and the game, dragged up or down.
    private func bandHandle(height: CGFloat) -> some View {
        Capsule().fill(.white).frame(width: 44, height: 5)
            .shadow(color: .black.opacity(0.4), radius: 3)
            .frame(maxWidth: .infinity).frame(height: 30)
            .contentShape(Rectangle())
            .offset(y: 15)
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        let start = bandStart ?? topBand
                        bandStart = start
                        var still = Transaction()
                        still.disablesAnimations = true
                        withTransaction(still) { topBand = Self.band(start + value.translation.height / height) }
                    }
                    .onEnded { _ in bandStart = nil }
            )
            .accessibilityLabel("Camera size")
    }

    private static func band(_ value: CGFloat) -> CGFloat { min(0.6, max(0.15, value)) }

    /// Two fingers anywhere on the card size the player, or the camera band in Cam on top.
    private var facePinch: some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.01)
            .onChanged { value in
                guard gameOn, cameraOn else { return }
                if layout == .top {
                    let start = bandStart ?? topBand
                    bandStart = start
                    var still = Transaction()
                    still.disablesAnimations = true
                    withTransaction(still) { topBand = Self.band(start * value.magnification) }
                    return
                }
                guard layout.movable else { return }
                var still = Transaction()
                still.disablesAnimations = true
                withTransaction(still) { face.pinch = value.magnification }
            }
            .onEnded { value in
                bandStart = nil
                guard gameOn, cameraOn, layout.movable else { return }
                var still = Transaction()
                still.disablesAnimations = true
                withTransaction(still) { face.keepPinch(layout, value.magnification) }
            }
    }

    @ViewBuilder private var gameView: some View {
        if let game = selected ?? (isRecording ? Mock.game(recordGameID) : nil) {
            GameFactory.view(for: game.kind, options: options, link: link)
                .allowsHitTesting(phase == .recording)
        } else {
            Text("Pick a game")
                .font(DL.label(12)).foregroundStyle(.white.opacity(0.7)).textCase(.uppercase)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.35))
        }
    }

    @ViewBuilder private func cameraView(cutout: Bool) -> some View {
        if !CreateCamera.hasHardware {
            if !cutout {
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
            CreateCameraView(camera: camera, cutout: cutout)
                .overlay {
                    // A photo freezes the frame, so the still of the screen holds it.
                    if let frozen, !cutout { Image(uiImage: frozen).resizable().scaledToFill() }
                }
                .overlay {
                    // While the camera turns round, the last frame stays up, blurred, until the other camera is ready.
                    if camera.flipping, let still = camera.flipStill {
                        Group {
                            if cutout {
                                Image(uiImage: still).resizable().scaledToFit()
                            } else {
                                Image(uiImage: still).resizable().scaledToFill()
                            }
                        }
                        .blur(radius: 22, opaque: !cutout)
                        .transition(.opacity)
                    }
                }
                .animation(.easeOut(duration: 0.22), value: camera.flipping)
        }
    }

    // MARK: Before recording

    /// Close at the top left, one rail of round buttons down the right, and the record key at the bottom.
    private func idleChrome(_ size: CGSize) -> some View {
        ZStack {
            if open != nil {
                // Tapping the picture closes the open panel.
                Color.clear.contentShape(Rectangle()).onTapGesture { toggle(nil) }
            }
            VStack(spacing: 8) {
                Spacer()
                if let game = selected {
                    Text(game.title.uppercased())
                        .font(DL.display(30)).foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.5), radius: 6)
                        .opacity(nameShown ? 1 : 0)
                        .animation(.easeOut(duration: 0.25), value: nameShown)
                        .allowsHitTesting(false)
                }
                recordButton.frame(height: 100)
            }
            .padding(.bottom, 14)
            if selected != nil && gameOn {
                // At the top, level with Close, because games write their own first line low on the screen.
                Text(length == .photo ? "Tap for a photo" : "Record to start")
                    .font(DL.label(11)).foregroundStyle(.white).textCase(.uppercase)
                    .padding(.horizontal, 12).frame(height: 26)
                    .modifier(CreateGlass())
                    .allowsHitTesting(false)
                    .padding(.top, 13)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
            HStack(alignment: .top) {
                DLMediaButton(symbol: "xmark", size: 40)
                    .tap { LiveNav.shared.back() }
                    .accessibilityLabel("Close")
                Spacer()
                rail(size)
            }
            .padding(.leading, 14).padding(.trailing, 8).padding(.top, 6)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .transition(.opacity)
    }

    /// Every tool, top to bottom. The ones with choices open a panel beside the rail, one at a time.
    private func rail(_ size: CGSize) -> some View {
        // A short phone gets smaller buttons, so the rail ends above the record key.
        let side: CGFloat = size.height < 700 ? 38 : 44
        let room = size.width - 90
        return VStack(spacing: size.height < 700 ? 8 : 12) {
            toolItem(.game, "Game") {
                if let game = selected {
                    CreateGameIcon(game: game, size: side)
                } else {
                    DLMediaButton(symbol: "gamecontroller.fill", size: side)
                }
            } panel: {
                gamePanel(width: room - 46)
            }
            toolItem(.layout, "Layout") {
                DLMediaButton(symbol: "rectangle.on.rectangle", size: side)
            } panel: {
                layoutPanel(width: min(300, room))
            }
            toolItem(.length, "Length", badge: length.seconds.map { "\(Int($0))s" }) {
                DLMediaButton(symbol: length.symbol, size: side)
            } panel: {
                choices(CreateLength.allCases, picked: length, title: { $0.rawValue }) { length = $0 }
            }
            toolItem(.timer, "Timer", badge: timer > 0 ? "\(timer)s" : nil) {
                DLMediaButton(symbol: "timer", size: side)
            } panel: {
                choices([0, 3, 10], picked: timer, title: { $0 == 0 ? "Off" : "\($0)s" }, pick: setTimer)
            }
            railItem { DLMediaButton(symbol: "arrow.triangle.2.circlepath.camera", size: side) }
                .tap(flipCamera).accessibilityLabel("Flip camera")
            railItem { DLMediaButton(symbol: "rotate.right", size: side) }
                .tap(rotateCamera).accessibilityLabel("Rotate camera")
            railItem { DLMediaButton(symbol: flash ? "bolt.fill" : "bolt.slash.fill", size: side) }
                .tap(toggleFlash).accessibilityLabel("Flash")
            PhotosPicker(selection: $picked, matching: .videos) {
                railItem { DLMediaButton(symbol: "square.and.arrow.up", size: side) }
            }
            .accessibilityLabel("Upload a video and tag it with the game")
            toolItem(.more, "More") {
                DLMediaButton(symbol: "ellipsis", size: side)
            } panel: {
                choices(["Make a game", "Live"], picked: nil, title: { $0 }) { choice in
                    if choice == "Live" {
                        LiveNav.shared.say("Live rooms are not part of this build yet")
                    } else {
                        LiveNav.shared.open(.makeGame)
                    }
                }
            }
        }
    }

    /// One round button on the rail, ringed in gold while its panel is open.
    private func railItem<Icon: View>(badge: String? = nil, lit: Bool = false, @ViewBuilder icon: () -> Icon) -> some View {
        icon()
            .overlay { if lit { Circle().strokeBorder(DL.gold, lineWidth: 2.5) } }
            .overlay(alignment: .bottomTrailing) {
                if let badge {
                    Text(badge).font(DL.label(9)).foregroundStyle(DL.onGold)
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(DL.gold, in: Capsule())
                        .offset(x: 6, y: 2)
                }
            }
            .frame(width: 58)
    }

    /// A rail button that opens a panel to its left. Tapping it again closes the panel.
    private func toolItem<Icon: View, Panel: View>(_ tool: Tool, _ name: String, badge: String? = nil,
                                                   @ViewBuilder icon: () -> Icon,
                                                   @ViewBuilder panel: () -> Panel) -> some View {
        railItem(badge: badge, lit: open == tool, icon: icon)
            .tap { toggle(tool) }
            .accessibilityLabel(name)
            .overlay(alignment: .topTrailing) {
                if open == tool {
                    panel()
                        .fixedSize()
                        .offset(x: -66)
                        .transition(.scale(scale: 0.4, anchor: .topTrailing).combined(with: .opacity))
                }
            }
            .zIndex(open == tool ? 1 : 0)
    }

    private func toggle(_ tool: Tool?) {
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(.spring(duration: 0.35, bounce: 0.3)) { open = open == tool ? nil : tool }
    }

    /// A row of choices in a glass capsule, with the picked one in gold.
    private func choices<T: Hashable>(_ all: [T], picked: T?, title: @escaping (T) -> String,
                                      pick: @escaping (T) -> Void) -> some View {
        HStack(spacing: 4) {
            ForEach(all, id: \.self) { option in
                let on = option == picked
                Text(title(option))
                    .font(DL.label(13)).textCase(.uppercase)
                    .foregroundStyle(on ? DL.onGold : .white)
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .background { if on { Capsule().fill(DL.gold) } }
                    .contentShape(Capsule())
                    .onTapGesture {
                        UISelectionFeedbackGenerator().selectionChanged()
                        withAnimation(.snappy(duration: 0.25)) { pick(option) }
                    }
                    .accessibilityAddTraits(.isButton)
            }
        }
        .padding(5)
        .background(MediaGlass(shape: Capsule()))
    }

    /// Every game, and None to film with no game picked.
    private func gamePanel(width: CGFloat) -> some View {
        ScrollViewReader { scroll in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    gameChip("None", on: selected == nil) { DLMediaButton(symbol: "nosign", size: 50) }
                        .onTapGesture { pickGame(nil) }
                        .accessibilityLabel("Clear the game")
                    ForEach(order) { game in
                        gameChip(game.title, on: selected?.id == game.id) { CreateGameIcon(game: game, size: 50) }
                            .id(game.id)
                            .onTapGesture { pickGame(game.id) }
                            .accessibilityLabel(game.title)
                    }
                }
                .padding(.horizontal, 10)
            }
            .onAppear { if let id = selected?.id { scroll.scrollTo(id, anchor: .center) } }
        }
        .frame(width: width, height: 94)
        .background(MediaGlass(shape: RoundedRectangle(cornerRadius: DL.cardRadius, style: .continuous)))
        .clipShape(RoundedRectangle(cornerRadius: DL.cardRadius, style: .continuous))
    }

    private func gameChip<Icon: View>(_ title: String, on: Bool, @ViewBuilder icon: () -> Icon) -> some View {
        VStack(spacing: 5) {
            icon().overlay { if on { Circle().strokeBorder(DL.gold, lineWidth: 3) } }
            Text(title)
                .font(DL.label(9)).foregroundStyle(on ? DL.gold : .white).textCase(.uppercase)
                .lineLimit(1)
        }
        .frame(width: 64)
        .contentShape(Rectangle())
        .accessibilityAddTraits(.isButton)
    }

    private func pickGame(_ id: String?) {
        guard let id else { return withAnimation(.snappy) { cleared = true } }
        userPicked = true
        if centeredID == id {
            withAnimation(.snappy) { cleared = false }
        } else {
            withAnimation(.snappy(duration: 0.35)) { centeredID = id }
        }
    }

    /// The game and the camera, each on or off, and with both on, how you sit on the game.
    private func layoutPanel(width: CGFloat) -> some View {
        let both = gameOn && cameraOn
        return VStack(spacing: 12) {
            HStack(spacing: 8) {
                modeSwitch(symbol: "gamecontroller.fill", title: "Game", on: gameOn, action: toggleGame)
                modeSwitch(symbol: cameraOn ? "video.fill" : "video.slash.fill", title: "Camera", on: cameraOn,
                           action: toggleCamera)
            }
            // The first and last shapes line up with the outer edges of the two switches above.
            HStack(spacing: 0) {
                ForEach(Array(CreateShape.allCases.enumerated()), id: \.element) { index, option in
                    let on = both && option == shape
                    if index > 0 { Spacer(minLength: 0) }
                    Image(systemName: option.symbol)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(on ? DL.onGold : .white)
                        .frame(width: 42, height: 42)
                        .background(on ? DL.gold : Color.white.opacity(0.14), in: Circle())
                        .contentShape(Circle())
                        .onTapGesture { pickShape(option) }
                        .accessibilityLabel(option.title)
                        .accessibilityAddTraits(.isButton)
                }
            }
            .opacity(both ? 1 : 0.45)
        }
        .padding(12)
        .frame(width: width)
        .background(MediaGlass(shape: RoundedRectangle(cornerRadius: DL.cardRadius, style: .continuous)))
        .animation(.snappy(duration: 0.3), value: gameOn)
        .animation(.snappy(duration: 0.3), value: cameraOn)
        .animation(.snappy(duration: 0.3), value: shape)
    }

    private func modeSwitch(symbol: String, title: String, on: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 7) {
            Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
            Text(title).font(DL.label(12)).textCase(.uppercase).lineLimit(1).minimumScaleFactor(0.8)
            Capsule()
                .fill(on ? DL.onGold.opacity(0.85) : .white.opacity(0.3))
                .frame(width: 30, height: 18)
                .overlay(alignment: on ? .trailing : .leading) {
                    Circle().fill(on ? DL.gold : .white).frame(width: 14, height: 14).padding(2)
                }
        }
        .foregroundStyle(on ? DL.onGold : .white)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .frame(height: 36)
        .background(Capsule().fill(on ? DL.gold : .white.opacity(0.14)))
        .contentShape(Capsule())
        .onTapGesture(perform: action)
        .accessibilityLabel(on ? "\(title) on" : "\(title) off")
        .accessibilityAddTraits(.isButton)
    }

    /// The gold record key in its ring.
    private var recordButton: some View {
        ZStack {
            Circle().strokeBorder(.white, lineWidth: 5)
            Circle().fill(DL.gold).frame(width: 76, height: 76)
        }
        .frame(width: 92, height: 92)
        .contentShape(Circle())
        .onTapGesture(perform: recordTapped)
        .accessibilityLabel(length == .photo ? "Take a photo" : "Record")
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

    // MARK: Actions

    private func appear() {
        syncCamera()
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
        CreateOverWindow.hide()
        if phase == .recording { CreateScreenRecorder.discard() }
    }

    /// The same round the game's Play key opens: alone only for a game that is only played alone.
    static func playOptions(_ game: MockGame, seed: UInt64) -> GameOptions {
        let store = LiveStore.shared
        return GameOptions(solo: game.playerRange.upperBound == 1, playerName: store.me?.handle ?? Mock.handle,
                           friendNames: Mock.playFriends, bestScore: store.s.best[game.id] ?? 0, seed: seed)
    }

    private func gameChanged() {
        if phase == .idle, let game = selected {
            // The waiting game is the same game, at rest on its start screen.
            let resting = GameLink()
            resting.paused = true
            options = Self.playOptions(game, seed: 1)
            link = resting
        }
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
        guard cameraOn else { return say("Turn the camera on first") }
        flash = false
        camera.flip()
    }

    private func rotateCamera() {
        guard CreateCamera.hasHardware else { return say("Camera needs a real phone") }
        guard cameraOn else { return say("Turn the camera on first") }
        camera.rotate()
    }

    private func toggleFlash() {
        guard CreateCamera.hasHardware else { return say("Camera needs a real phone") }
        guard cameraOn else { return say("Turn the camera on first") }
        if camera.setFlash(!flash) {
            flash.toggle()
            say(flash ? "Flash on" : "Flash off")
        } else {
            say("Flash works with the back camera")
        }
    }

    private func setTimer(_ seconds: Int) {
        timer = seconds
        say(timer == 0 ? "Timer off" : "\(timer) second timer")
    }

    private func toggleGame() {
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(.snappy(duration: 0.35)) {
            gameOn.toggle()
            if !gameOn { cameraOn = true }
        }
        syncCamera()
    }

    /// With the game off the camera is all there is, so turning the camera off turns the game on.
    private func toggleCamera() {
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(.snappy(duration: 0.35)) {
            cameraOn.toggle()
            if !cameraOn { gameOn = true }
        }
        syncCamera()
    }

    /// Runs the camera only while it is on, and cuts the player out only for the green screen.
    private func syncCamera() {
        camera.cutout = gameOn && cameraOn && layout == .cutout
        if cameraOn {
            Task { await camera.start(ownAudio: !CreateScreenRecorder.isAvailable) }
        } else {
            flash = false
            camera.stop()
        }
    }

    /// Picks a shape from the rail. It shows once the game and the camera are both on.
    private func pickShape(_ picked: CreateShape) {
        guard gameOn, cameraOn else { return say("Turn the game and camera on first") }
        UISelectionFeedbackGenerator().selectionChanged()
        face.drag = .zero
        face.pinch = 1
        shape = picked
        camera.cutout = layout == .cutout
        say(shape.title)
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
        let playing = gameOn
        recordPlaying = playing
        recordCamera = cameraOn
        withAnimation(.easeOut(duration: 0.2)) { phase = .starting }

        // Game Off films only the player, so no round is started and no gold is counted.
        let day = LiveStore.dayKey(Date())
        let opening = playing ? Task {
            await CreateWait.within(6) {
                try await ConvexLink.shared.mutate("rounds:start", ["slug": game.id, "day": day], as: ConvexRoundStart.self)
            }
        } : nil
        var kind: Recording = .none
        if CreateScreenRecorder.isAvailable, (try? await CreateScreenRecorder.start(mic: camera.micGranted)) != nil {
            kind = .screen
        } else if cameraOn && CreateCamera.hasHardware && camera.access == .granted {
            camera.startRecording()
            kind = .camera
        }
        let started = await opening?.value ?? nil
        guard token == mine else { return }

        if playing {
            let round = GameLink()
            round.onFinish = { result in Task { @MainActor in await end(result: result) } }
            let seed = started.map { UInt64(max(1, $0.seed)) } ?? (UInt64(Date().timeIntervalSince1970 * 1000) & 0xFFFF_FFFF)
            options = Self.playOptions(game, seed: seed)
            link = round
        }
        roundID = started?.roundId
        recording = kind
        recordStart = Date()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.spring(duration: 0.4, bounce: 0.3)) { phase = .recording }

        guard let limit = length.seconds else { return }
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

        // A Game Off recording is the camera alone, which is the whole clip.
        CreateClips.shared.take = CreateTake(gameID: recordGameID, layout: recordPlaying ? layout : .window, videoURL: url,
                                             cameraOnly: recordPlaying && recording == .camera, roundID: roundID,
                                             result: result, isBest: isBest, seconds: seconds)
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
        CreateClips.shared.take = CreateTake(gameID: game.id, layout: gameOn ? layout : .window, photo: shot)
        LiveNav.shared.replaceTop(.createPreview)
    }

    private func crop(_ image: UIImage, to rect: CGRect) -> UIImage? {
        guard let cg = image.cgImage, rect.width > 0 else { return image }
        let scale = image.scale
        let pixels = CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale)
        guard let cut = cg.cropping(to: pixels) else { return image }
        return UIImage(cgImage: cut, scale: scale, orientation: .up)
    }

    /// A clip from the camera roll, posted under the picked game.
    private func importClip(_ item: PhotosPickerItem) {
        let gameID = selected?.id ?? order.first?.id ?? Mock.tippyTower.id
        Task {
            defer { picked = nil }
            guard let movie = try? await item.loadTransferable(type: CreateMovie.self) else {
                return say("Could not open that video")
            }
            CreateClips.shared.take = CreateTake(gameID: gameID, layout: .window, videoURL: movie.url)
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

