import SwiftUI

// The edit step after a recording, like a video app's editor: a filter on the whole clip, big text in a colour
// with or without a box, and a score sticker. The text and the sticker are dragged anywhere on the video.
// The settings travel with the clip, so Videos and the feed draw them the same way.

enum CreateFilter: String, Codable, CaseIterable {
    case none, warm, cool, vivid, mono, fade, noir

    var title: String {
        switch self {
        case .none: "Normal"
        case .warm: "Warm"
        case .cool: "Cool"
        case .vivid: "Vivid"
        case .mono: "Mono"
        case .fade: "Fade"
        case .noir: "Noir"
        }
    }
}

enum CreateTextColor: String, Codable, CaseIterable {
    case white, gold, black, pink, blue, green

    var color: Color {
        switch self {
        case .white: .white
        case .gold: Color(hex: "FFC531")
        case .black: Color(hex: "151412")
        case .pink: Color(hex: "FF5FA2")
        case .blue: Color(hex: "4DA3FF")
        case .green: Color(hex: "4CD787")
        }
    }

    /// The colour that reads on top of this one: the outline round plain text, the text inside a box.
    var contrast: Color { self == .black ? .white : Color(hex: "151412") }
}

/// What the editor set on a clip. Stored on the clip as JSON, so a clip from before the editor has the defaults.
struct CreateLook: Codable, Equatable {
    var filter: CreateFilter = .none
    var color: CreateTextColor = .white
    var boxed = false
    var textX = 0.5
    var textY = 0.36
    var sticker = false
    var stickerX = 0.5
    var stickerY = 0.6

    var encoded: String? {
        guard self != CreateLook(), let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func decode(_ text: String?) -> CreateLook {
        guard let data = text?.data(using: .utf8), let look = try? JSONDecoder().decode(CreateLook.self, from: data) else {
            return CreateLook()
        }
        return look
    }
}

private struct CreateFilterModifier: ViewModifier {
    let filter: CreateFilter

    @ViewBuilder func body(content: Content) -> some View {
        switch filter {
        case .none: content
        case .warm: content.colorMultiply(Color(red: 1, green: 0.9, blue: 0.76)).saturation(1.15)
        case .cool: content.colorMultiply(Color(red: 0.8, green: 0.92, blue: 1)).saturation(1.05)
        case .vivid: content.saturation(1.6).contrast(1.15)
        case .mono: content.grayscale(1).contrast(1.05)
        case .fade: content.saturation(0.65).contrast(0.85).brightness(0.08)
        case .noir: content.grayscale(1).contrast(1.5).brightness(-0.05)
        }
    }
}

extension View {
    func createFilter(_ filter: CreateFilter) -> some View { modifier(CreateFilterModifier(filter: filter)) }
}

/// A view placed at a point given as fractions of the space it sits in. With `onMove` it can be dragged.
struct CreatePlaced<Content: View>: View {
    let x: Double
    let y: Double
    var onMove: ((Double, Double) -> Void)? = nil
    @ViewBuilder var content: () -> Content
    @State private var drag = CGSize.zero

    var body: some View {
        GeometryReader { geo in
            content()
                .position(x: x * geo.size.width + drag.width, y: y * geo.size.height + drag.height)
                .gesture(
                    DragGesture(minimumDistance: 2)
                        .onChanged { value in
                            var still = Transaction()
                            still.disablesAnimations = true
                            withTransaction(still) { drag = value.translation }
                        }
                        .onEnded { value in
                            let nx = min(0.92, max(0.08, x + value.translation.width / geo.size.width))
                            let ny = min(0.92, max(0.08, y + value.translation.height / geo.size.height))
                            var still = Transaction()
                            still.disablesAnimations = true
                            withTransaction(still) {
                                onMove?(nx, ny)
                                drag = .zero
                            }
                        }
                )
                .allowsHitTesting(onMove != nil)
        }
    }
}

/// The text and the sticker a clip carries, laid over its video.
struct CreateClipDecor: View {
    let text: String
    let look: CreateLook
    /// What the sticker says: the score, or the game.
    var sticker: String
    var onMoveText: ((Double, Double) -> Void)? = nil
    var onMoveSticker: ((Double, Double) -> Void)? = nil
    var onTapText: (() -> Void)? = nil

    var body: some View {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        ZStack {
            if look.sticker {
                CreatePlaced(x: look.stickerX, y: look.stickerY, onMove: onMoveSticker) {
                    CreateScoreSticker(text: sticker)
                }
            }
            if !trimmed.isEmpty {
                CreatePlaced(x: look.textX, y: look.textY, onMove: onMoveText) {
                    CreateOverlayLabel(text: trimmed, color: look.color, boxed: look.boxed)
                        .padding(.horizontal, 20)
                        .onTapGesture { onTapText?() }
                }
            }
        }
    }
}

/// Big text on a clip: heavy, in its colour with an outline, or inside a box of its colour.
struct CreateOverlayLabel: View {
    let text: String
    var color: CreateTextColor = .white
    var boxed = false

    var body: some View {
        let label = Text(text)
            .font(.system(size: 28, weight: .heavy))
            .multilineTextAlignment(.center)
        if boxed {
            label
                .foregroundStyle(color.contrast)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(color.color, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            let edge = color.contrast
            label
                .foregroundStyle(color.color)
                .shadow(color: edge, radius: 0, x: 1.5, y: 1.5)
                .shadow(color: edge, radius: 0, x: -1.5, y: -1.5)
                .shadow(color: edge, radius: 0, x: 1.5, y: -1.5)
                .shadow(color: edge, radius: 0, x: -1.5, y: 1.5)
        }
    }
}

/// The score as a gold sticker, tipped a little.
struct CreateScoreSticker: View {
    let text: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "trophy.fill").font(.system(size: 17, weight: .bold))
            Text(text.uppercased()).font(DL.display(26)).lineLimit(1)
        }
        .foregroundStyle(DL.onGold)
        .padding(.horizontal, 16).frame(height: 46)
        .background(DL.gold, in: Capsule())
        .background(Capsule().fill(DL.goldLip).offset(y: 3))
        .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
        .rotationEffect(.degrees(-4))
    }
}
