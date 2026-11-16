import SwiftUI
import UIKit
import AVFoundation
import CoreImage
import Photos

// The edit step after a recording, laid out like a video app's editor. The clip fills the screen with a rail of
// tools down the right. Each tool opens its own small tray only while it is in use. Text is typed straight onto
// the video and then dragged into place. Next opens a sheet with the caption and Post. Trim, speed, music, crop
// and the filter are written into the video file when it is posted, saved or sent.

enum CreateTool: String, CaseIterable, Identifiable {
    case text, filters, trim, music, crop, speed, sticker, sound
    var id: String { rawValue }
}

enum CreateCrop: String, CaseIterable {
    case full, portrait, square, wide

    var title: String {
        switch self {
        case .full: "Full"
        case .portrait: "4:5"
        case .square: "Square"
        case .wide: "Wide"
        }
    }

    var symbol: String {
        switch self {
        case .full: "iphone"
        case .portrait: "rectangle.portrait"
        case .square: "square"
        case .wide: "rectangle"
        }
    }

    /// Width over height. nil keeps the whole frame.
    var ratio: CGFloat? {
        switch self {
        case .full: nil
        case .portrait: 4.0 / 5
        case .square: 1
        case .wide: 16.0 / 9
        }
    }
}

enum CreateMusic: String, CaseIterable {
    case none, arcade, chill, hype, bounce

    var title: String {
        switch self {
        case .none: "None"
        case .arcade: "Arcade"
        case .chill: "Chill"
        case .hype: "Hype"
        case .bounce: "Bounce"
        }
    }

    var symbol: String {
        switch self {
        case .none: "nosign"
        case .arcade: "gamecontroller.fill"
        case .chill: "moon.fill"
        case .hype: "flame.fill"
        case .bounce: "waveform"
        }
    }

    var url: URL? { self == .none ? nil : Bundle.main.url(forResource: "music-\(rawValue)", withExtension: "m4a") }
}

/// The cuts made to a video: the part kept as fractions of its length, its speed, its frame, the music and the sound.
struct CreateCut: Equatable {
    var start = 0.0
    var end = 1.0
    var speed = 1.0
    var crop = CreateCrop.full
    var music = CreateMusic.none
    var sound = true

    var trimmed: Bool { start > 0.001 || end < 0.999 }
    var plain: Bool { !trimmed && speed == 1 && crop == .full && music == .none && sound }
}

/// Plays the take in the editor with the cuts applied: the kept part on a loop, at its speed, with its music.
@MainActor
final class CreateEditPlayer: ObservableObject {
    let player = AVQueuePlayer()
    @Published var duration = 0.0
    private var looper: AVPlayerLooper?
    private var music: AVAudioPlayer?
    private var url: URL?
    private var cut = CreateCut()

    func load(_ url: URL) async {
        self.url = url
        duration = (try? await AVURLAsset(url: url).load(.duration).seconds) ?? 0
        restart()
    }

    func apply(_ next: CreateCut) {
        let old = cut
        cut = next
        guard url != nil else { return }
        if next.start != old.start || next.end != old.end {
            restart()
            return
        }
        player.isMuted = !next.sound
        player.defaultRate = Float(next.speed)
        if player.rate != 0 { player.rate = Float(next.speed) }
        if next.music != old.music { playMusic() }
    }

    func stop() {
        player.pause()
        music?.stop()
    }

    private func restart() {
        guard let url else { return }
        player.pause()
        looper?.disableLooping()
        player.removeAllItems()
        let item = AVPlayerItem(url: url)
        if duration > 0 && cut.trimmed {
            let range = CMTimeRange(start: CMTime(seconds: cut.start * duration, preferredTimescale: 600),
                                    end: CMTime(seconds: cut.end * duration, preferredTimescale: 600))
            looper = AVPlayerLooper(player: player, templateItem: item, timeRange: range)
        } else {
            looper = AVPlayerLooper(player: player, templateItem: item)
        }
        player.isMuted = !cut.sound
        player.defaultRate = Float(cut.speed)
        player.playImmediately(atRate: Float(cut.speed))
        playMusic()
    }

    private func playMusic() {
        music?.stop()
        music = nil
        guard let url = cut.music.url, let next = try? AVAudioPlayer(contentsOf: url) else { return }
        next.numberOfLoops = -1
        next.volume = 0.7
        next.play()
        music = next
    }
}

/// Writes the edits into the media itself, so a saved or posted clip looks the way it did in the editor.
enum CreateRender {
    /// The take with its cuts written in, and the look to post beside it. A video's filter is written into the
    /// file, so the look that goes with it has none.
    static func finish(_ take: CreateTake, cut: CreateCut, look: CreateLook) async throws -> (CreateTake, CreateLook) {
        var take = take, look = look
        if let photo = take.photo {
            take.photo = CreateRender.photo(photo, crop: cut.crop)
            return (take, look)
        }
        guard let url = take.videoURL, !take.cameraOnly, !(cut.plain && look.filter == .none) else { return (take, look) }
        take.videoURL = try await video(url, cut: cut, filter: look.filter)
        take.seconds = take.seconds * (cut.end - cut.start) / cut.speed
        look.filter = .none
        return (take, look)
    }

    static func photo(_ image: UIImage, crop: CreateCrop) -> UIImage {
        guard let ratio = crop.ratio else { return image }
        let w = image.size.width, h = image.size.height
        var size = image.size
        if w / h > ratio { size.width = h * ratio } else { size.height = w / ratio }
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(at: CGPoint(x: (size.width - w) / 2, y: (size.height - h) / 2))
        }
    }

    static func video(_ url: URL, cut: CreateCut, filter: CreateFilter) async throws -> URL {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        guard let source = try await asset.loadTracks(withMediaType: .video).first else { throw CreateError.noMedia }
        let natural = try await source.load(.naturalSize)
        let transform = try await source.load(.preferredTransform)
        let mixed = AVMutableComposition()
        let range = CMTimeRange(start: CMTimeMultiplyByFloat64(duration, multiplier: cut.start),
                                end: CMTimeMultiplyByFloat64(duration, multiplier: cut.end))
        guard let video = mixed.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw CreateError.noMedia
        }
        try video.insertTimeRange(range, of: source, at: .zero)
        video.preferredTransform = transform
        var inputs: [AVMutableAudioMixInputParameters] = []
        if cut.sound, let sound = try await asset.loadTracks(withMediaType: .audio).first,
           let track = mixed.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            try track.insertTimeRange(range, of: sound, at: .zero)
            let input = AVMutableAudioMixInputParameters(track: track)
            input.setVolume(1, at: .zero)
            inputs.append(input)
        }
        if cut.speed != 1 {
            mixed.scaleTimeRange(CMTimeRange(start: .zero, duration: range.duration),
                                 toDuration: CMTimeMultiplyByFloat64(range.duration, multiplier: 1 / cut.speed))
        }
        let total = mixed.duration
        if let tuneURL = cut.music.url {
            let tune = AVURLAsset(url: tuneURL)
            let length = try await tune.load(.duration)
            if length.seconds > 0.5, let notes = try await tune.loadTracks(withMediaType: .audio).first,
               let track = mixed.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
                var at = CMTime.zero
                while at < total {
                    let piece = CMTimeMinimum(length, total - at)
                    try track.insertTimeRange(CMTimeRange(start: .zero, duration: piece), of: notes, at: at)
                    at = at + piece
                }
                let input = AVMutableAudioMixInputParameters(track: track)
                input.setVolume(cut.sound ? 0.45 : 0.9, at: .zero)
                inputs.append(input)
            }
        }

        let turned = CGRect(origin: .zero, size: natural).applying(transform)
        let full = CGSize(width: abs(turned.width), height: abs(turned.height))
        var size = full
        if let ratio = cut.crop.ratio {
            if full.width / full.height > ratio { size.width = full.height * ratio } else { size.height = full.width / ratio }
            size = CGSize(width: (size.width / 2).rounded(.down) * 2, height: (size.height / 2).rounded(.down) * 2)
        }
        let crop = CGRect(x: ((full.width - size.width) / 2).rounded(), y: ((full.height - size.height) / 2).rounded(),
                          width: size.width, height: size.height)
        let frames = AVMutableVideoComposition(asset: mixed) { request in
            let image = filtered(request.sourceImage, filter)
                .cropped(to: crop)
                .transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
            request.finish(with: image, context: nil)
        }
        frames.renderSize = crop.size

        guard let export = AVAssetExportSession(asset: mixed, presetName: AVAssetExportPresetHighestQuality) else {
            throw CreateError.noMedia
        }
        export.videoComposition = frames
        if !inputs.isEmpty {
            let mix = AVMutableAudioMix()
            mix.inputParameters = inputs
            export.audioMix = mix
        }
        let out = CreateFiles.newURL("mp4")
        try await export.export(to: out, as: .mp4)
        return out
    }

    static func filtered(_ image: CIImage, _ filter: CreateFilter) -> CIImage {
        switch filter {
        case .none:
            return image
        case .warm:
            return image.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 1.05, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 0.93, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 0.78, w: 0),
            ]).applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.15])
        case .cool:
            return image.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0.82, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 0.94, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 1.05, w: 0),
            ])
        case .vivid:
            return image.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.6, kCIInputContrastKey: 1.15])
        case .mono:
            return image.applyingFilter("CIPhotoEffectMono")
        case .fade:
            return image.applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: 0.65, kCIInputContrastKey: 0.85, kCIInputBrightnessKey: 0.08,
            ])
        case .noir:
            return image.applyingFilter("CIPhotoEffectNoir")
        }
    }

    static func thumbnails(_ url: URL, count: Int) async -> [UIImage] {
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration), duration.seconds > 0 else { return [] }
        let maker = AVAssetImageGenerator(asset: asset)
        maker.appliesPreferredTrackTransform = true
        maker.maximumSize = CGSize(width: 120, height: 200)
        var images: [UIImage] = []
        for index in 0..<count {
            let at = CMTimeMultiplyByFloat64(duration, multiplier: (Double(index) + 0.5) / Double(count))
            if let frame = try? await maker.image(at: at) { images.append(UIImage(cgImage: frame.image)) }
        }
        return images
    }
}

/// The strip of frames with a handle at each end to cut the start and the end off.
struct CreateTrimBar: View {
    let thumbs: [UIImage]
    let duration: Double
    let speed: Double
    @Binding var start: Double
    @Binding var end: Double
    @State private var liveStart: Double?
    @State private var liveEnd: Double?

    var body: some View {
        let s = liveStart ?? start, e = liveEnd ?? end
        let gap = duration > 1 ? 1 / duration : 0.2
        VStack(spacing: 10) {
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    HStack(spacing: 0) {
                        ForEach(thumbs.indices, id: \.self) { index in
                            Image(uiImage: thumbs[index]).resizable().scaledToFill()
                                .frame(width: w / CGFloat(thumbs.count), height: 58)
                                .clipped()
                        }
                    }
                    .frame(width: w, height: 58, alignment: .leading)
                    .background(Color.white.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    Rectangle().fill(.black.opacity(0.62)).frame(width: w * s, height: 58)
                    Rectangle().fill(.black.opacity(0.62)).frame(width: w * (1 - e), height: 58).offset(x: w * e)
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(DL.gold, lineWidth: 3)
                        .frame(width: max(6, w * (e - s)), height: 64)
                        .offset(x: w * s)
                        .allowsHitTesting(false)
                    handle
                        .offset(x: w * s - 14)
                        .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("trim"))
                            .onChanged { value in liveStart = min(max(0, value.location.x / w), (liveEnd ?? end) - gap) }
                            .onEnded { _ in
                                if let value = liveStart { start = value }
                                liveStart = nil
                                UISelectionFeedbackGenerator().selectionChanged()
                            })
                    handle
                        .offset(x: w * e - 14)
                        .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("trim"))
                            .onChanged { value in liveEnd = max(min(1, value.location.x / w), (liveStart ?? start) + gap) }
                            .onEnded { _ in
                                if let value = liveEnd { end = value }
                                liveEnd = nil
                                UISelectionFeedbackGenerator().selectionChanged()
                            })
                }
                .coordinateSpace(.named("trim"))
            }
            .frame(height: 64)
            Text(duration > 0 ? String(format: "%.1f s", (e - s) * duration / speed) : "Drag the ends to cut")
                .font(DL.text(13, .semibold))
                .foregroundStyle(.white.opacity(0.8))
        }
        .padding(.horizontal, 14)
    }

    private var handle: some View {
        Capsule().fill(DL.gold)
            .frame(width: 10, height: 46)
            .overlay(Capsule().fill(DL.onGold.opacity(0.5)).frame(width: 2, height: 18))
            .frame(width: 28, height: 76)
            .contentShape(Rectangle())
    }
}

struct CreatePreviewContent: View {
    let take: CreateTake
    @StateObject private var player = CreateEditPlayer()
    @State private var cut = CreateCut()
    @State private var look = CreateLook()
    @State private var overlay = ""
    @State private var tool: CreateTool?
    @State private var writing = false
    @State private var draft = ""
    @FocusState private var keyboard: Bool
    @FocusState private var captioning: Bool
    @State private var thumbs: [UIImage] = []
    @State private var sharing = false
    @State private var caption = ""
    @State private var everyone = true
    @State private var posting = false
    @State private var keeping = false
    @State private var progress = 0.0
    @State private var burst = false
    @State private var busy = false

    private var game: MockGame { Mock.game(take.gameID) }
    /// The recording itself, when it is a video the editor can cut.
    private var playable: URL? { take.photo == nil && !take.cameraOnly ? take.videoURL : nil }

    private var tools: [CreateTool] {
        var list: [CreateTool] = [.text, .filters]
        if playable != nil { list += [.trim, .music, .speed] }
        if playable != nil || take.photo != nil { list.append(.crop) }
        list.append(.sticker)
        if playable != nil { list.append(.sound) }
        return list
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            stage
            if !writing {
                VStack(spacing: 0) {
                    topBar
                    HStack(alignment: .top) {
                        Spacer()
                        if tool == nil { rail.transition(.move(edge: .trailing).combined(with: .opacity)) }
                    }
                    .padding(.top, 14)
                    Spacer()
                    if let tool {
                        tray(for: tool).transition(.move(edge: .bottom).combined(with: .opacity))
                    } else {
                        bottomBar.transition(.opacity)
                    }
                }
                .animation(.snappy(duration: 0.28), value: tool)
                .environment(\.colorScheme, .dark)
            }
            if writing { textEntry.transition(.opacity) }
            if busy {
                ProgressView().tint(.white).scaleEffect(1.4)
                    .frame(width: 84, height: 84)
                    .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            if burst { CreateGoldBurst().allowsHitTesting(false) }
        }
        .animation(.easeOut(duration: 0.2), value: writing)
        .sheet(isPresented: $sharing) { postSheet }
        .task {
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            guard let url = playable else { return }
            await player.load(url)
            thumbs = await CreateRender.thumbnails(url, count: 8)
        }
        .onChange(of: cut) { _, next in player.apply(next) }
        .onDisappear { player.stop() }
    }

    // MARK: The clip

    private var stage: some View {
        GeometryReader { geo in
            let size = frame(in: geo.size)
            ZStack {
                media.createFilter(look.filter)
                CreateClipDecor(text: overlay, look: look, sticker: take.scoreLine ?? game.title,
                                onMoveText: { x, y in look.textX = x; look.textY = y },
                                onMoveSticker: { x, y in look.stickerX = x; look.stickerY = y },
                                onTapText: startWriting)
            }
            .frame(width: size.width, height: size.height)
            .clipped()
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
            .animation(.snappy(duration: 0.3), value: cut.crop)
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { if tool != nil { tool = nil } }
    }

    private func frame(in box: CGSize) -> CGSize {
        guard let ratio = cut.crop.ratio else { return box }
        let height = min(box.height, box.width / ratio)
        return CGSize(width: height * ratio, height: height)
    }

    @ViewBuilder private var media: some View {
        if let photo = take.photo {
            Image(uiImage: photo).resizable().scaledToFill()
        } else if playable != nil {
            CreatePlayerView(player: player.player)
        } else {
            CreateReplayStage(game: game, layout: take.layout) {
                if let url = take.videoURL {
                    CreateLoopingVideo(url: url)
                } else {
                    CreateCameraPlaceholder()
                }
            }
        }
    }

    @ViewBuilder private var cover: some View {
        if let photo = take.photo {
            Image(uiImage: photo).resizable().scaledToFill()
        } else if !thumbs.isEmpty {
            Image(uiImage: thumbs[thumbs.count / 2]).resizable().scaledToFill()
        } else {
            ClipStill(game: game, phase: 0.3, showHUD: false, focusY: 0.4)
        }
    }

    // MARK: Chrome

    private var topBar: some View {
        HStack(spacing: 10) {
            DLMediaButton(symbol: "xmark", size: 40)
                .tap { LiveNav.shared.back() }
                .accessibilityLabel("Close")
            Spacer()
            HStack(spacing: 6) {
                Text(game.title.uppercased()).font(DL.label(11)).foregroundStyle(.white.opacity(0.8))
                if let line = take.scoreLine {
                    Text(line).font(DL.display(18)).foregroundStyle(take.isBest ? DL.gold : .white).lineLimit(1)
                }
            }
            .padding(.horizontal, 12).frame(height: 34)
            .background(.black.opacity(0.35), in: Capsule())
            Spacer()
            DLMediaButton(symbol: "arrow.counterclockwise", size: 40)
                .tap { LiveNav.shared.replaceTop(.create(take.gameID)) }
                .accessibilityLabel("Retake")
        }
        .padding(.horizontal, 14).padding(.top, 8)
    }

    private var rail: some View {
        VStack(spacing: 16) {
            ForEach(tools) { item in
                VStack(spacing: 3) {
                    Image(systemName: symbol(item))
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(isOn(item) ? DL.gold : .white)
                        .frame(width: 44, height: 30)
                    Text(title(item)).font(DL.text(10.5, .semibold)).foregroundStyle(.white)
                }
                .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
                .contentShape(Rectangle())
                .tap { pick(item) }
                .accessibilityLabel(title(item))
            }
        }
        .padding(.vertical, 14).padding(.horizontal, 4)
        .background(.black.opacity(0.22), in: Capsule())
        .padding(.trailing, 10)
    }

    private var bottomBar: some View {
        HStack(spacing: 10) {
            roundKey("square.and.arrow.down", label: "Save to Photos", run: save)
            roundKey("paperplane.fill", label: "Send", run: send)
            DLTextKey(title: "Next", symbol: "arrow.right")
                .tap { sharing = true }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }

    private func roundKey(_ symbol: String, label: String, run: @escaping () -> Void) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 52, height: 52)
            .background(.white.opacity(0.16), in: Circle())
            .tap(run)
            .accessibilityLabel(label)
    }

    private func title(_ item: CreateTool) -> String {
        switch item {
        case .text: "Text"
        case .filters: "Filters"
        case .trim: "Trim"
        case .music: cut.music == .none ? "Music" : cut.music.title
        case .crop: "Crop"
        case .speed: cut.speed == 1 ? "Speed" : speedTitle(cut.speed)
        case .sticker: "Sticker"
        case .sound: cut.sound ? "Sound" : "Muted"
        }
    }

    private func symbol(_ item: CreateTool) -> String {
        switch item {
        case .text: "textformat"
        case .filters: "camera.filters"
        case .trim: "scissors"
        case .music: "music.note"
        case .crop: "crop"
        case .speed: "speedometer"
        case .sticker: "trophy.fill"
        case .sound: cut.sound ? "speaker.wave.2.fill" : "speaker.slash.fill"
        }
    }

    private func isOn(_ item: CreateTool) -> Bool {
        switch item {
        case .text: !overlay.isEmpty
        case .filters: look.filter != .none
        case .trim: cut.trimmed
        case .music: cut.music != .none
        case .crop: cut.crop != .full
        case .speed: cut.speed != 1
        case .sticker: look.sticker
        case .sound: !cut.sound
        }
    }

    private func speedTitle(_ speed: Double) -> String {
        speed.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(speed))x" : "\(speed)x"
    }

    private func pick(_ item: CreateTool) {
        UISelectionFeedbackGenerator().selectionChanged()
        switch item {
        case .text:
            startWriting()
        case .sticker:
            withAnimation(.snappy(duration: 0.25)) { look.sticker.toggle() }
        case .sound:
            cut.sound.toggle()
            LiveNav.shared.say(cut.sound ? "Sound on" : "Sound off")
        default:
            tool = item
        }
    }

    // MARK: Trays

    @ViewBuilder private func tray(for item: CreateTool) -> some View {
        switch item {
        case .filters:
            tray("Filters") {
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(CreateFilter.allCases, id: \.self) { filter in
                            let on = look.filter == filter
                            VStack(spacing: 6) {
                                cover
                                    .createFilter(filter)
                                    .frame(width: 58, height: 78)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(on ? DL.gold : .clear, lineWidth: 3))
                                Text(filter.title).font(DL.text(11, on ? .semibold : .regular))
                                    .foregroundStyle(on ? .white : .white.opacity(0.7))
                            }
                            .tap {
                                UISelectionFeedbackGenerator().selectionChanged()
                                look.filter = filter
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                }
                .scrollIndicators(.hidden)
            }
        case .trim:
            tray("Trim") {
                CreateTrimBar(thumbs: thumbs, duration: player.duration, speed: cut.speed, start: $cut.start, end: $cut.end)
            }
        case .music:
            tray("Music") {
                VStack(spacing: 12) {
                    HStack(spacing: 8) {
                        ForEach(CreateMusic.allCases, id: \.self) { track in
                            let on = cut.music == track
                            VStack(spacing: 6) {
                                Image(systemName: track.symbol)
                                    .font(.system(size: 19, weight: .semibold))
                                    .foregroundStyle(on ? DL.onGold : .white)
                                    .frame(width: 54, height: 54)
                                    .background(on ? DL.gold : Color.white.opacity(0.14), in: Circle())
                                Text(track.title).font(DL.text(11, on ? .semibold : .regular))
                                    .foregroundStyle(on ? .white : .white.opacity(0.7))
                            }
                            .frame(maxWidth: .infinity)
                            .tap {
                                UISelectionFeedbackGenerator().selectionChanged()
                                cut.music = track
                            }
                        }
                    }
                    chip(cut.sound ? "Original sound on" : "Original sound off",
                         symbol: cut.sound ? "speaker.wave.2.fill" : "speaker.slash.fill", on: cut.sound) { cut.sound.toggle() }
                }
                .padding(.horizontal, 14)
            }
        case .crop:
            tray("Crop") {
                HStack(spacing: 8) {
                    ForEach(CreateCrop.allCases, id: \.self) { crop in
                        chip(crop.title, symbol: crop.symbol, on: cut.crop == crop) { cut.crop = crop }
                    }
                }
                .padding(.horizontal, 14)
            }
        case .speed:
            tray("Speed") {
                HStack(spacing: 8) {
                    ForEach([0.5, 1, 1.5, 2], id: \.self) { speed in
                        chip(speedTitle(speed), on: cut.speed == speed) { cut.speed = speed }
                    }
                }
                .padding(.horizontal, 14)
            }
        default:
            EmptyView()
        }
    }

    private func tray<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 14) {
            HStack {
                Text(title).font(DL.text(16, .semibold)).foregroundStyle(.white)
                Spacer()
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(DL.onGold)
                    .frame(width: 36, height: 36)
                    .background(DL.gold, in: Circle())
                    .tap { tool = nil }
                    .accessibilityLabel("Done")
            }
            .padding(.horizontal, 16)
            content()
        }
        .padding(.top, 14).padding(.bottom, 18)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .gesture(DragGesture(minimumDistance: 16).onEnded { value in
            if value.translation.height > 40 { tool = nil }
        })
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
    }

    private func chip(_ title: String, symbol: String? = nil, on: Bool, _ pick: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            if let symbol { Image(systemName: symbol).font(.system(size: 13, weight: .bold)) }
            Text(title).font(DL.text(14, .semibold)).lineLimit(1).minimumScaleFactor(0.8)
        }
        .foregroundStyle(on ? DL.onGold : .white)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .frame(height: 40)
        .background(on ? DL.gold : Color.white.opacity(0.14), in: Capsule())
        .tap {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.snappy(duration: 0.25)) { pick() }
        }
    }

    // MARK: Text on the video

    private func startWriting() {
        draft = overlay
        tool = nil
        writing = true
    }

    private func finishWriting() {
        keyboard = false
        overlay = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        writing = false
    }

    private var textEntry: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea().onTapGesture(perform: finishWriting)
            VStack(spacing: 0) {
                HStack {
                    Text("A")
                        .font(.system(size: 18, weight: .heavy))
                        .foregroundStyle(look.boxed ? look.color.contrast : .white)
                        .frame(width: 40, height: 40)
                        .background(look.boxed ? look.color.color : Color.white.opacity(0.18),
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .tap { look.boxed.toggle() }
                        .accessibilityLabel(look.boxed ? "Text without a box" : "Text in a box")
                    Spacer()
                    Text("Done")
                        .font(DL.text(17, .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14).frame(height: 40)
                        .tap(finishWriting)
                }
                .padding(.horizontal, 16).padding(.top, 8)
                Spacer()
                TextField("", text: $draft, prompt: Text("Type here").foregroundStyle(.white.opacity(0.5)), axis: .vertical)
                    .font(.system(size: 30, weight: .heavy))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(look.boxed ? look.color.contrast : look.color.color)
                    .tint(DL.gold)
                    .lineLimit(1...4)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(look.boxed && !draft.isEmpty ? look.color.color : .clear,
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .fixedSize(horizontal: false, vertical: true)
                    .focused($keyboard)
                    .padding(.horizontal, 24)
                    .onChange(of: draft) { _, text in
                        if text.count > 80 { draft = String(text.prefix(80)) }
                    }
                Spacer()
                HStack(spacing: 12) {
                    ForEach(CreateTextColor.allCases, id: \.self) { color in
                        Circle().fill(color.color)
                            .frame(width: 28, height: 28)
                            .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                            .scaleEffect(look.color == color ? 1.2 : 1)
                            .tap {
                                UISelectionFeedbackGenerator().selectionChanged()
                                withAnimation(.snappy(duration: 0.2)) { look.color = color }
                            }
                            .accessibilityLabel(color.rawValue)
                    }
                }
                .padding(.bottom, 14)
            }
        }
        .onAppear { keyboard = true }
    }

    // MARK: Post

    private var postSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                cover
                    .createFilter(look.filter)
                    .frame(width: 76, height: 104)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .trailing, spacing: 4) {
                    TextField("Say something about this run", text: $caption, axis: .vertical)
                        .font(DL.text(16))
                        .foregroundStyle(DL.ink)
                        .lineLimit(3...5)
                        .focused($captioning)
                        .onChange(of: caption) { _, text in
                            if text.count > 140 { caption = String(text.prefix(140)) }
                        }
                    Spacer(minLength: 0)
                    Text("\(caption.count)/140").dlLabel(10, color: DL.ink3)
                }
                .frame(height: 104)
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
            HStack(spacing: 8) {
                DLTextKey(title: keeping ? "Saving" : "Save", symbol: "lock.fill", style: .neutral)
                    .tap { if !posting { post(privately: true) } }
                    .frame(maxWidth: 150)
                DLTextKey(title: posting && !keeping ? "Posting" : "Post", symbol: "arrow.up")
                    .tap { if !posting { post(privately: false) } }
            }
            .opacity(posting ? 0.7 : 1)
            Text("Save keeps it in your clips, just for you.").dlLabel(10, color: DL.ink3)
                .frame(maxWidth: .infinity)
            Spacer(minLength: 0)
        }
        .padding(20)
        .padding(.top, 8)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .presentationBackground(DL.surface)
        .interactiveDismissDisabled(posting)
    }

    private func pill(_ title: String, on: Bool, _ pick: @escaping () -> Void) -> some View {
        Text(title)
            .font(DL.text(14, .semibold))
            .foregroundStyle(on ? DL.onInk : DL.ink)
            .padding(.horizontal, 14).frame(height: 32)
            .background(on ? DL.ink : DL.body, in: Capsule())
            .tap { withAnimation(.snappy(duration: 0.2)) { pick() } }
    }

    private func post(privately: Bool) {
        captioning = false
        posting = true
        keeping = privately
        progress = 0.02
        let take = take, caption = caption, overlay = overlay, look = look, cut = cut
        let visibility = privately ? "private" : (everyone ? "everyone" : "friends")
        Task { @MainActor in
            do {
                let (ready, style) = try await CreateRender.finish(take, cut: cut, look: look)
                progress = 0.08
                _ = try await CreateClips.shared.post(ready, caption: caption, overlay: overlay, look: style,
                                                      visibility: visibility) { progress = max(0.08, $0) }
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                sharing = false
                player.stop()
                if privately {
                    LiveNav.shared.say("Saved to your clips")
                    CreateClips.shared.showClips = true
                    LiveNav.shared.closeAll()
                    LiveNav.shared.open(.profile("me"))
                    return
                }
                burst = true
                LiveNav.shared.say("Posted")
                try? await Task.sleep(for: .seconds(1.1))
                LiveNav.shared.goToTab(1)
                withAnimation(.snappy(duration: 0.3)) { LiveNav.shared.videoIndex = 0 }
            } catch {
                CreateScreenRecorder.log.error("Posting a clip failed: \(String(describing: error), privacy: .public)")
                posting = false
                keeping = false
                LiveNav.shared.say(privately ? "Could not save. Try again" : "Could not post. Try again")
            }
        }
    }

    /// The take with the edits written in, for Photos and for sending.
    private func finished(_ use: @escaping (CreateTake) -> Void) {
        guard !busy else { return }
        busy = true
        let take = take, cut = cut, look = look
        Task { @MainActor in
            let ready = try? await CreateRender.finish(take, cut: cut, look: look)
            busy = false
            guard let ready else { return LiveNav.shared.say("Could not get the video ready") }
            use(ready.0)
        }
    }

    private func save() {
        guard take.photo != nil || take.videoURL != nil else {
            return LiveNav.shared.say("There is no video to save on this phone")
        }
        finished { ready in
            let photo = ready.photo, url = ready.videoURL
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
    }

    private func send() {
        let line = take.scoreLine.map { "\($0) in \(game.title) on DEGEN" } ?? "Watch me play \(game.title) on DEGEN"
        finished { ready in
            if let photo = ready.photo {
                CreateFiles.share([photo, line])
            } else if let url = ready.videoURL {
                CreateFiles.share([url, line])
            } else {
                CreateFiles.share([line])
            }
        }
    }
}
