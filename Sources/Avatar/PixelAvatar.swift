import SwiftUI

// The flat pixel Dailie: the same voxel grid seen straight from the front, one square per voxel,
// with a dark outline around the silhouette. Used wherever the avatar is small.

extension AvatarRarity {
    var color: Color {
        switch self {
        case .common: Color(hex: "F3F0E9")
        case .rare: Color(hex: "1FA89A")
        case .epic: Color(hex: "7C5CFF")
        case .legendary: Color(hex: "FFC531")
        }
    }

    /// Text on a tag filled with the rarity colour.
    var onColor: Color {
        switch self {
        case .common, .legendary: Color(hex: "151412")
        case .rare, .epic: .white
        }
    }
}

/// The front view of a voxel grid, flattened into rows of colours with a one-voxel outline around it.
struct PixelImage {
    let width: Int
    let height: Int
    /// Row by row from the top. nil is empty.
    let pixels: [VoxelColor?]

    static let outline = VoxelColor(0x151412)

    init(_ grid: VoxelGrid) {
        let front = grid.front
        guard !front.isEmpty else { width = 0; height = 0; pixels = []; return }
        let b = grid.bounds
        let w = b.max.x - b.min.x + 3, h = b.max.y - b.min.y + 3
        var out = [VoxelColor?](repeating: nil, count: w * h)
        for row in 0..<h {
            for column in 0..<w {
                let x = b.min.x - 1 + column, y = b.max.y + 1 - row
                if let color = front[VoxelPoint(x: x, y: y, z: 0)] {
                    out[row * w + column] = color
                } else if front[VoxelPoint(x: x + 1, y: y, z: 0)] != nil || front[VoxelPoint(x: x - 1, y: y, z: 0)] != nil
                            || front[VoxelPoint(x: x, y: y + 1, z: 0)] != nil || front[VoxelPoint(x: x, y: y - 1, z: 0)] != nil {
                    out[row * w + column] = Self.outline
                }
            }
        }
        width = w; height = h; pixels = out
    }

    /// Draws the image as large as fits, centred, on whole-point squares where it can.
    func draw(in context: GraphicsContext, size: CGSize, anchorBottom: Bool = false) {
        guard width > 0, height > 0 else { return }
        var cell = min(size.width / CGFloat(width), size.height / CGFloat(height))
        if cell >= 3 { cell = cell.rounded(.down) }
        let originX = (size.width - cell * CGFloat(width)) / 2
        let originY = anchorBottom ? size.height - cell * CGFloat(height) : (size.height - cell * CGFloat(height)) / 2
        var paths: [VoxelColor: Path] = [:]
        for row in 0..<height {
            for column in 0..<width {
                guard let color = pixels[row * width + column] else { continue }
                // A hair of overlap so no seams show between squares.
                let rect = CGRect(x: originX + CGFloat(column) * cell, y: originY + CGFloat(row) * cell,
                                  width: cell + 0.35, height: cell + 0.35)
                paths[color, default: Path()].addRect(rect)
            }
        }
        for (color, path) in paths {
            context.fill(path, with: .color(Color(.sRGB, red: Double(color.r) / 255, green: Double(color.g) / 255,
                                                  blue: Double(color.b) / 255, opacity: 1)))
        }
    }
}

/// Built images, by what they show, so lists do not rebuild the same Dailie on every redraw.
enum PixelCache {
    private static var images: [String: PixelImage] = [:]

    static func image(_ key: String, build: () -> VoxelGrid) -> PixelImage {
        if let hit = images[key] { return hit }
        if images.count > 300 { images.removeAll() }
        let image = PixelImage(build())
        images[key] = image
        return image
    }

    static func key(_ look: AvatarLook, shirt: VoxelColor, head: Bool) -> String {
        [look.body, look.face, look.hair ?? "-", look.hat ?? "-", look.outfit ?? "-", look.gadget ?? "-",
         "\(shirt.r).\(shirt.g).\(shirt.b)", head ? "head" : "full"].joined(separator: "|")
    }
}

/// A Dailie as flat pixel art: the full body, or just the head for tight spots.
struct PixelAvatar: View {
    var look: AvatarLook
    var shirt: VoxelColor = VoxelPalette.purple
    var headOnly = false

    var body: some View {
        let image = PixelCache.image(PixelCache.key(look, shirt: shirt, head: headOnly)) {
            let grid = VoxelAvatar.build(look, shirt: shirt)
            return headOnly ? grid.headOnly : grid
        }
        Canvas { context, size in image.draw(in: context, size: size, anchorBottom: !headOnly) }
            .accessibilityLabel("Avatar")
    }
}

/// The player's own head in a round frame: the Home top bar and other small spots.
struct AvatarHead: View {
    var look: AvatarLook
    var shirt: VoxelColor = VoxelPalette.purple
    var size: CGFloat = 36

    var body: some View {
        PixelAvatar(look: look, shirt: shirt, headOnly: true)
            .padding(size * 0.1)
            .padding(.top, size * 0.04)
            .frame(width: size, height: size)
            .background(Color(hex: "2B2622"), in: Circle())
            .clipShape(Circle())
    }
}

/// One item drawn on its own, for shop cards.
struct ItemArt: View {
    var item: AvatarItem
    var shirt: VoxelColor = VoxelPalette.purple

    var body: some View {
        let image = PixelCache.image("item|\(item.id)|\(shirt.r).\(shirt.g).\(shirt.b)") {
            VoxelAvatar.item(item, shirt: shirt)
        }
        Canvas { context, size in image.draw(in: context, size: size) }
            .accessibilityLabel(item.name)
    }
}

/// A small capital tag in the item's rarity colour.
struct RarityTag: View {
    var rarity: AvatarRarity
    var size: CGFloat = 10

    var body: some View {
        Text(rarity.label)
            .font(DL.label(size)).tracking(0.6)
            .foregroundStyle(rarity.onColor)
            .padding(.horizontal, size * 0.7)
            .frame(height: size * 2)
            .background(rarity.color, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}
