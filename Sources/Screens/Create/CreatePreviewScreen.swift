import SwiftUI
import UIKit
import AVFoundation
import Photos

// The players shared by the editor after a recording (CreateEditor.swift) and the clips in Videos.

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
                scene.frame(width: w, height: h)
                switch layout {
                case .cutout, .window:
                    // A camera-only recording still has its background, so it sits as a card low on the game.
                    camera()
                        .frame(width: w * 0.42, height: w * 0.42 * 16 / 9)
                        .clipShape(RoundedRectangle(cornerRadius: DL.tileRadius, style: .continuous))
                        .position(x: w * 0.5, y: h - w * 0.42 * 8 / 9 - 40)
                case .bubble:
                    camera()
                        .frame(width: 120, height: 120)
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(.white.opacity(0.8), lineWidth: 2))
                        .position(x: w - 76, y: 140)
                case .top:
                    camera()
                        .frame(width: w, height: h * 0.34)
                        .clipped()
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
    @State private var menu = false
    @State private var editing = false
    @State private var confirmDelete = false
    @State private var draft = ""

    var body: some View {
        let game = Mock.game(clip.gameSlug)
        // Comments belong to the game, so the comment button opens the game's catalog clip.
        let shown = MockClip(id: Mock.clips.first { $0.game.id == game.id }?.id ?? Mock.clips[0].id, game: game,
                             player: clip.handle, caption: clip.caption, length: "",
                             comments: groupedNumber(Int(clip.comments)), shares: groupedNumber(Int(clip.likes)))
        VideoPage(clip: shown, progress: 0, voted: store.vote(for: game.id),
                  media: AnyView(media(game).createFilter(clip.style.filter).overlay {
                      CreateClipDecor(text: clip.overlay ?? "", look: clip.style, sticker: clip.scoreText ?? clip.gameTitle)
                  }), tag: clip.scoreText,
                  saveKey: clip.saveKey, onMore: clip.mine ? { menu = true } : nil)
            // Two seconds on screen is a view. A view of someone else's clip pays its creator when the game has a program.
            .task(id: active) {
                guard active, !clip.mine else { return }
                try? await Task.sleep(for: .seconds(2))
                if !Task.isCancelled { WhopStore.shared.saw(clip.id) }
            }
            .confirmationDialog("Your clip", isPresented: $menu, titleVisibility: .visible) {
                Button("Edit caption") {
                    draft = clip.caption
                    editing = true
                }
                if clip.visibility != "everyone" {
                    Button("Show to everyone") { change(caption: clip.caption, visibility: "everyone") }
                }
                if clip.visibility != "friends" {
                    Button("Show to friends only") { change(caption: clip.caption, visibility: "friends") }
                }
                if clip.visibility != "private" {
                    Button("Keep it just for me") { change(caption: clip.caption, visibility: "private") }
                }
                Button("Delete clip", role: .destructive) { confirmDelete = true }
                Button("Cancel", role: .cancel) {}
            }
            .alert("Edit caption", isPresented: $editing) {
                TextField("Say something about this run", text: $draft)
                Button("Save") { change(caption: draft, visibility: clip.visibility) }
                Button("Cancel", role: .cancel) {}
            }
            .alert("Delete this clip?", isPresented: $confirmDelete) {
                Button("Delete", role: .destructive, action: delete)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("It comes off Videos, your profile and everyone's saved clips.")
            }
    }

    private func change(caption: String, visibility: String) {
        let clip = clip
        Task { @MainActor in
            do {
                try await CreateClips.shared.update(clip, caption: caption, visibility: visibility)
                let said = ["everyone": "Everyone can see it", "friends": "Friends only", "private": "Just for you"]
                LiveNav.shared.say(visibility == clip.visibility ? "Caption saved" : said[visibility] ?? "Saved")
            } catch {
                LiveNav.shared.say("Could not save. Try again")
            }
        }
    }

    private func delete() {
        let clip = clip
        Task { @MainActor in
            do {
                try await CreateClips.shared.remove(clip)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                LiveNav.shared.say("Clip deleted")
            } catch {
                LiveNav.shared.say("Could not delete. Try again")
            }
        }
    }

    @ViewBuilder private func media(_ game: MockGame) -> some View {
        let layout = CreateLayout(rawValue: clip.layout) ?? .cutout
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
