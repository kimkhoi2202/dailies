import SwiftUI
import UIKit
import AVFoundation
import Photos

// The preview after a recording: the take loops full screen, with the round's score on top and a
// sheet to caption it and post it to Videos.

/// Plays a video edge to edge.
struct CreatePlayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> Host {
        let view = Host()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspectFill
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ view: Host, context: Context) {
        if view.playerLayer.player !== player { view.playerLayer.player = player }
    }

    final class Host: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}

/// A video that loops. It plays only while `active`.
struct CreateLoopingVideo: View {
    let url: URL
    var active = true
    var muted = false
    @State private var player = AVQueuePlayer()
    @State private var looper: AVPlayerLooper?

    var body: some View {
        CreatePlayerView(player: player)
            .onAppear {
                if looper == nil { looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url)) }
                player.isMuted = muted
                if active { player.play() }
            }
            .onDisappear { player.pause() }
            .onChange(of: active) { _, on in on ? player.play() : player.pause() }
            .onChange(of: muted) { _, on in player.isMuted = on }
    }
}

/// The game replayed in a clip's layout, for a take that holds the camera alone or nothing at all.
struct CreateReplayStage<Camera: View>: View {
    let game: MockGame
    let layout: CreateLayout
    var moving = true
    @ViewBuilder var camera: () -> Camera
    @State private var start = Date()

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack(alignment: .topLeading) {
                Color.black
                switch layout {
                case .split:
                    VStack(spacing: 0) {
                        camera().frame(width: w, height: h / 2).clipped()
                        scene.frame(width: w, height: h / 2).clipped()
                    }
                case .bubble:
                    scene.frame(width: w, height: h)
                    camera()
                        .frame(width: 120, height: 120)
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(.white.opacity(0.8), lineWidth: 2))
                        .position(x: w - 76, y: 140)
                case .overlay:
                    camera().frame(width: w, height: h).clipped()
                    scene.frame(width: w, height: h * 2 / 3).opacity(0.85).offset(y: h / 3)
                }
            }
        }
    }

    private var scene: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !moving)) { timeline in
            let loops = timeline.date.timeIntervalSince(start) / 7
            ClipStill(game: game, phase: loops - loops.rounded(.towardZero), showHUD: true, focusY: 0.5)
        }
    }
}

/// Where the camera would be in a replay with no camera video.
struct CreateCameraPlaceholder: View {
    var body: some View {
        LinearGradient(colors: [DL.sunken, Color.black], startPoint: .top, endPoint: .bottom)
            .overlay(Image(systemName: "person.fill").font(.system(size: 30)).foregroundStyle(.white.opacity(0.35)))
            .environment(\.colorScheme, .dark)
    }
}

struct CreatePreviewScreen: View {
    @ObservedObject private var clips = CreateClips.shared

    var body: some View {
        if let take = clips.take {
            CreatePreviewContent(take: take)
        } else {
            Color.black.ignoresSafeArea().onAppear { LiveNav.shared.closeAll() }
        }
    }
}

private struct CreatePreviewContent: View {
    let take: CreateTake
    @State private var muted = false
    @State private var caption = ""
    @State private var everyone = true
    @State private var posting = false
    @State private var progress = 0.0
    @State private var burst = false
    @FocusState private var typing: Bool

    private var game: MockGame { Mock.game(take.gameID) }

    var body: some View {
        ZStack {
            media
                .ignoresSafeArea()
                .onTapGesture { typing = false }
            LinearGradient(colors: [.black.opacity(0.55), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 200)
                .frame(maxHeight: .infinity, alignment: .top)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            VStack(spacing: 0) {
                header
                Spacer()
                sheet
            }
            if burst { CreateGoldBurst().allowsHitTesting(false) }
        }
        .background(Color.black.ignoresSafeArea())
        .onAppear { try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback) }
    }

    @ViewBuilder private var media: some View {
        if let photo = take.photo {
            Image(uiImage: photo).resizable().scaledToFill()
        } else if let url = take.videoURL, !take.cameraOnly {
            CreateLoopingVideo(url: url, muted: muted)
        } else {
            CreateReplayStage(game: game, layout: take.layout) {
                if let url = take.videoURL {
                    CreateLoopingVideo(url: url, muted: muted)
                } else {
                    CreateCameraPlaceholder()
                }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            HStack {
                DLMediaButton(symbol: "xmark", size: 40)
                    .tap { LiveNav.shared.closeAll() }
                    .accessibilityLabel("Close")
                Spacer()
                if take.videoURL != nil && take.photo == nil {
                    DLMediaButton(symbol: muted ? "speaker.slash.fill" : "speaker.wave.2.fill", size: 40)
                        .tap { muted.toggle() }
                        .accessibilityLabel(muted ? "Sound on" : "Sound off")
                }
            }
            Text(game.title.uppercased())
                .font(DL.display(22)).foregroundStyle(.white.opacity(0.85))
            if let line = take.scoreLine {
                Text(line).font(DL.display(56)).foregroundStyle(.white)
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            if take.isBest {
                Text("NEW BEST").font(DL.label(12)).foregroundStyle(DL.onGold)
                    .padding(.horizontal, 10).frame(height: 26)
                    .background(DL.gold, in: Capsule())
            }
        }
        .padding(.horizontal, 14).padding(.top, 8)
        .environment(\.colorScheme, .dark)
    }

    private var sheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .trailing, spacing: 4) {
                TextField("Say something about this run", text: $caption, axis: .vertical)
                    .font(DL.text(16))
                    .foregroundStyle(DL.ink)
                    .lineLimit(1...3)
                    .focused($typing)
                    .submitLabel(.done)
                    .onChange(of: caption) { _, text in
                        if text.count > 140 { caption = String(text.prefix(140)) }
                    }
                    .padding(12)
                    .background(DL.body, in: RoundedRectangle(cornerRadius: DL.tileRadius, style: .continuous))
                Text("\(caption.count)/140").dlLabel(10, color: DL.ink3)
            }

            HStack(spacing: 8) {
                DLTag(text: game.title, symbol: "gamecontroller.fill", filled: true)
                if let line = take.scoreLine { DLTag(text: line, symbol: "trophy.fill") }
                Spacer()
            }

            HStack(spacing: 8) {
                Text("Who can see it").dlLabel(11)
                Spacer()
                pill("Friends", on: !everyone) { everyone = false }
                pill("Everyone", on: everyone) { everyone = true }
            }

            if posting {
                Capsule().fill(DL.sunken)
                    .overlay(alignment: .leading) {
                        GeometryReader { bar in
                            Capsule().fill(DL.gold).frame(width: max(8, bar.size.width * progress))
                        }
                    }
                    .frame(height: 6)
                    .animation(.easeOut(duration: 0.2), value: progress)
            }

            DLTextKey(title: posting ? "Posting" : "Post", symbol: "arrow.up")
                .tap { if !posting { post() } }
                .opacity(posting ? 0.7 : 1)

            HStack(spacing: 8) {
                action("Save to Photos", symbol: "square.and.arrow.down", run: save)
                action("Send to a friend", symbol: "paperplane.fill", run: send)
                action("Retake", symbol: "arrow.counterclockwise") {
                    LiveNav.shared.replaceTop(.create(take.gameID))
                }
            }
        }
        .padding(16)
        .background(DL.surface, in: RoundedRectangle(cornerRadius: DL.cardRadius, style: .continuous))
        .padding(.horizontal, 8)
        .padding(.bottom, 6)
    }

    private func pill(_ title: String, on: Bool, _ pick: @escaping () -> Void) -> some View {
        Text(title)
            .font(DL.text(14, .semibold))
            .foregroundStyle(on ? DL.onInk : DL.ink)
            .padding(.horizontal, 14).frame(height: 32)
            .background(on ? DL.ink : DL.body, in: Capsule())
            .tap { withAnimation(.snappy(duration: 0.2)) { pick() } }
    }

    private func action(_ title: String, symbol: String, run: @escaping () -> Void) -> some View {
        VStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 17, weight: .semibold))
            Text(title).font(DL.label(9.5)).textCase(.uppercase).lineLimit(1).minimumScaleFactor(0.7)
        }
        .foregroundStyle(DL.ink)
        .frame(maxWidth: .infinity)
        .frame(height: 58)
        .background(DL.body, in: RoundedRectangle(cornerRadius: DL.tileRadius, style: .continuous))
        .tap(run)
    }

    private func post() {
        typing = false
        posting = true
        progress = 0.02
        let take = take, caption = caption, everyone = everyone
        Task { @MainActor in
            do {
                _ = try await CreateClips.shared.post(take, caption: caption, everyone: everyone) { progress = $0 }
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                burst = true
                LiveNav.shared.say("Posted")
                try? await Task.sleep(for: .seconds(1.1))
                LiveNav.shared.goToTab(1)
                withAnimation(.snappy(duration: 0.3)) { LiveNav.shared.videoIndex = 0 }
            } catch {
                posting = false
                LiveNav.shared.say("Could not post. Try again")
            }
        }
    }

    private func save() {
        guard take.photo != nil || take.videoURL != nil else {
            return LiveNav.shared.say("There is no video to save on this phone")
        }
        let photo = take.photo, url = take.videoURL
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async { LiveNav.shared.say("Allow Photos in Settings to save") }
                return
            }
            PHPhotoLibrary.shared().performChanges {
                if let photo {
                    PHAssetChangeRequest.creationRequestForAsset(from: photo)
                } else if let url {
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
                }
            } completionHandler: { saved, _ in
                DispatchQueue.main.async {
                    if saved { UINotificationFeedbackGenerator().notificationOccurred(.success) }
                    LiveNav.shared.say(saved ? "Saved to Photos" : "Could not save")
                }
            }
        }
    }

    private func send() {
        let line = take.scoreLine.map { "\($0) in \(game.title) on Dailies" } ?? "Watch me play \(game.title) on Dailies"
        if let photo = take.photo {
            CreateFiles.share([photo, line])
        } else if let url = take.videoURL {
            CreateFiles.share([url, line])
        } else {
            CreateFiles.share([line])
        }
    }
}

/// Coins bursting out from the middle of the screen when a clip is posted.
struct CreateGoldBurst: View {
    @State private var out = false

    var body: some View {
        ZStack {
            ForEach(0..<16, id: \.self) { index in
                let angle = Double(index) / 16 * 2 * .pi
                let reach: CGFloat = index.isMultiple(of: 2) ? 170 : 120
                DLCoin(size: index.isMultiple(of: 3) ? 26 : 18)
                    .offset(x: out ? cos(angle) * reach : 0, y: out ? sin(angle) * reach : 0)
                    .scaleEffect(out ? 1 : 0.2)
                    .opacity(out ? 0 : 1)
            }
        }
        .onAppear { withAnimation(.easeOut(duration: 0.9)) { out = true } }
    }
}

// MARK: Videos

/// A clip a player posted, in Videos. The same page as a catalog clip, with the recording instead of the replay.
struct CreateClipPage: View {
    let clip: ConvexClip
    let active: Bool
    @ObservedObject private var store = LiveStore.shared

    var body: some View {
        let game = Mock.game(clip.gameSlug)
        // Comments belong to the game, so the comment button opens the game's catalog clip.
        let shown = MockClip(id: Mock.clips.first { $0.game.id == game.id }?.id ?? Mock.clips[0].id, game: game,
                             player: clip.handle, caption: clip.caption, length: "",
                             comments: groupedNumber(Int(clip.comments)), shares: groupedNumber(Int(clip.likes)))
        VideoPage(clip: shown, progress: 0, voted: store.vote(for: game.id), media: AnyView(media(game)), tag: clip.scoreText)
    }

    @ViewBuilder private func media(_ game: MockGame) -> some View {
        let layout = CreateLayout(rawValue: clip.layout) ?? .split
        if let address = clip.url, let url = URL(string: address) {
            if clip.kind == "photo" {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color.black
                }
            } else {
                CreateLoopingVideo(url: url, active: active)
            }
        } else {
            CreateReplayStage(game: game, layout: layout, moving: active) { CreateCameraPlaceholder() }
        }
    }
}
