import SwiftUI
import Combine
import AVFoundation

// CLIPS IN A GRID AND FULL SCREEN: your clips, the clips you saved, and a player's clips on their profile.
// A tile opens the list full screen, one clip to a page, starting at the one tapped. Swipe up for the next.

/// Where a list of clips comes from.
enum ClipSource {
    case mine
    case saved
    case user(String)

    init(_ name: String) {
        switch name {
        case "mine": self = .mine
        case "saved": self = .saved
        default: self = .user(String(name.dropFirst("user:".count)))
        }
    }

    var name: String {
        switch self {
        case .mine: "mine"
        case .saved: "saved"
        case .user(let handle): "user:" + handle
        }
    }
}

/// Clips three to a row, in the shape they play in. Each opens the list full screen.
struct ClipGrid: View {
    let items: [ClipItem]
    let source: ClipSource

    var body: some View {
        Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            ForEach(Array(stride(from: 0, to: items.count, by: 3)), id: \.self) { start in
                GridRow {
                    ForEach(items[start..<min(start + 3, items.count)]) { item in
                        ClipItemTile(item: item).opens(.clipList(source.name, item.id))
                    }
                    ForEach(0..<(3 - min(3, items.count - start)), id: \.self) { _ in
                        Color.clear.gridCellUnsizedAxes(.vertical)
                    }
                }
            }
        }
    }
}

/// One clip in a grid: a real frame of a posted video, or the game's moment for a catalog clip.
struct ClipItemTile: View {
    let item: ClipItem

    var body: some View {
        switch item {
        case .posted(let clip):
            LibraryClipTile(clip: clip)
        case .sample(let clip):
            Color.clear
                .aspectRatio(9 / 16, contentMode: .fit)
                .overlay { ClipStill(game: clip.game, phase: clip.game.clipPhase, showHUD: false, focusY: 0.2) }
                .overlay(LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom))
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(clip.game.title.uppercased()).font(DL.display(15)).lineLimit(1).minimumScaleFactor(0.7)
                        Text("@\(clip.player)").font(DL.label(10)).lineLimit(1)
                    }
                    .foregroundStyle(.white)
                    .padding(8)
                }
                .clipShape(RoundedRectangle(cornerRadius: DL.tileRadius, style: .continuous))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(clip.game.title) clip by \(clip.player)")
        }
    }
}

/// A frame from the middle of a posted video, made once and kept.
struct ClipVideoFrame: View {
    let url: URL
    @State private var image: UIImage?

    private static let kept = NSCache<NSURL, UIImage>()

    var body: some View {
        ZStack {
            if let image { Image(uiImage: image).resizable().scaledToFill().transition(.opacity) }
        }
        .task(id: url) {
            if let cached = Self.kept.object(forKey: url as NSURL) { return image = cached }
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 360, height: 640)
            guard let frame = try? await generator.image(at: CMTime(seconds: 1, preferredTimescale: 600)).image else { return }
            let made = UIImage(cgImage: frame)
            Self.kept.setObject(made, forKey: url as NSURL)
            withAnimation(.easeOut(duration: 0.2)) { image = made }
        }
    }
}

/// A list of clips full screen, one to a page.
struct ClipsViewer: View {
    let source: ClipSource
    let start: String
    @ObservedObject private var clips = CreateClips.shared
    @State private var position: Int?
    @State private var userRows: [ConvexClip]?
    @State private var watch: AnyCancellable?

    init(source: ClipSource, start: String) {
        self.source = source
        self.start = start
        // Opens on the clip that was tapped. A player's clips arrive later and set it then.
        let shared = CreateClips.shared
        let known: [String] = switch source {
        case .mine: shared.mine.map(\.id)
        case .saved: shared.saved.map(\.id)
        case .user: []
        }
        _position = State(initialValue: known.firstIndex(of: start) ?? 0)
    }

    private var items: [ClipItem] {
        switch source {
        case .mine: clips.mine.map { .posted($0) }
        case .saved: clips.saved
        case .user: (userRows ?? []).map { .posted($0) }
        }
    }

    var body: some View {
        let list = items
        GeometryReader { proxy in
            let insets = proxy.safeAreaInsets
            let screen = CGSize(width: proxy.size.width + insets.leading + insets.trailing,
                                height: proxy.size.height + insets.top + insets.bottom)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(list.enumerated()), id: \.element.id) { index, item in
                        page(item, active: position == index)
                            .frame(width: screen.width, height: screen.height)
                            .id(index)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $position)
            .scrollIndicators(.hidden)
            .ignoresSafeArea()
        }
        .background(Color.black.ignoresSafeArea())
        .overlay(alignment: .topLeading) {
            DLMediaButton(symbol: "chevron.down", size: 40).goesBack().accessibilityLabel("Close")
                .padding(.horizontal, DL.margin).padding(.top, 6)
        }
        .onAppear {
            if case .user(let handle) = source {
                watch = clips.watchUser(handle) { rows in
                    let first = userRows == nil
                    userRows = rows
                    guard first else { return }
                    let at = rows.firstIndex { $0.id == start } ?? 0
                    DispatchQueue.main.async { position = at }
                }
            }
        }
        .onDisappear { watch?.cancel() }
        .onChange(of: list.count) { _, count in
            // The last clip here was deleted or unsaved.
            if count == 0 && userRows != nil || count == 0 && !isUser { LiveNav.shared.back() }
            if let at = position, at >= count, count > 0 { position = count - 1 }
        }
    }

    private var isUser: Bool {
        if case .user = source { true } else { false }
    }

    @ViewBuilder private func page(_ item: ClipItem, active: Bool) -> some View {
        switch item {
        case .posted(let clip): CreateClipPage(clip: clip, active: active)
        case .sample(let clip): LiveClipPage(clip: clip, active: active)
        }
    }
}
