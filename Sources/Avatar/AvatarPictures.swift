import SwiftUI
import SceneKit
import Metal

// Pictures of the low-poly Dailie for small spots: the Home top bar, rows and shop cards. Each picture is
// rendered once off screen from the same model the 3D stage shows, then kept.

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

final class AvatarPictures: ObservableObject {
    static let shared = AvatarPictures()

    @Published private(set) var images: [String: UIImage] = [:]
    private var asked = Set<String>()
    private let queue = DispatchQueue(label: "dailies.avatar.pictures", qos: .userInitiated)
    private lazy var renderer: SCNRenderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)

    enum Framing { case full, head, item(AvatarItem) }

    static func key(_ look: AvatarLook, shirt: VoxelColor, framing: Framing) -> String {
        let kind: String
        switch framing {
        case .full: kind = "full"
        case .head: kind = "head"
        case .item(let item): return "item|\(item.id)|\(shirt.r).\(shirt.g).\(shirt.b)"
        }
        return [look.body, look.face, look.hair ?? "-", look.hat ?? "-", look.outfit ?? "-", look.gadget ?? "-",
                "\(shirt.r).\(shirt.g).\(shirt.b)", kind].joined(separator: "|")
    }

    /// The picture for a key, or nil while it renders. Asking starts the render.
    func image(_ key: String, look: AvatarLook, shirt: VoxelColor, framing: Framing) -> UIImage? {
        if let hit = images[key] { return hit }
        guard !asked.contains(key) else { return nil }
        asked.insert(key)
        queue.async { [weak self] in
            guard let self else { return }
            let picture = self.render(look: look, shirt: shirt, framing: framing)
            DispatchQueue.main.async {
                if self.images.count > 250 { self.images.removeAll(); self.asked.removeAll() }
                self.images[key] = picture
            }
        }
        return nil
    }

    private func render(look: AvatarLook, shirt: VoxelColor, framing: Framing) -> UIImage {
        let scene = SCNScene()
        scene.background.contents = UIColor.clear
        let figure: SCNNode
        var focus: [String] = []
        switch framing {
        case .full:
            figure = AvatarModel.build(look, shirt: shirt)
        case .head:
            figure = AvatarModel.build(look, shirt: shirt)
            focus = ["head", "face", "hair", "hat"]
        case .item(let item):
            let built = AvatarModel.item(item, shirt: shirt)
            figure = built.node
            focus = built.focus
            // Hats and gadgets show alone.
            if item.slot == .hat || item.slot == .gadget {
                for child in figure.childNodes where !focus.contains(child.name ?? "") { child.isHidden = true }
            }
        }
        scene.rootNode.addChildNode(figure)
        figure.eulerAngles.y = 0.32

        // What to frame: the focus groups, or everything.
        var lo = SCNVector3(Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude, 0)
        var hi = SCNVector3(-Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude, 0)
        let framed = focus.isEmpty ? figure.childNodes : figure.childNodes.filter { focus.contains($0.name ?? "") }
        for group in framed where !group.isHidden {
            group.enumerateHierarchy { node, _ in
                guard node.geometry != nil else { return }
                let (a, b) = node.boundingBox
                for corner in [SCNVector3(a.x, a.y, a.z), SCNVector3(b.x, b.y, b.z), SCNVector3(a.x, b.y, a.z), SCNVector3(b.x, a.y, b.z)] {
                    let p = node.convertPosition(corner, to: nil)
                    lo.x = min(lo.x, p.x); lo.y = min(lo.y, p.y)
                    hi.x = max(hi.x, p.x); hi.y = max(hi.y, p.y)
                }
            }
        }
        if lo.x > hi.x { lo = SCNVector3(-1, 0, 0); hi = SCNVector3(1, 2.3, 0) }
        if case .head = framing { lo.y = max(lo.y, 0.86) }
        let span = max(hi.x - lo.x, hi.y - lo.y) * 1.12

        let camera = SCNCamera()
        camera.usesOrthographicProjection = true
        camera.orthographicScale = Double(span / 2)
        camera.zNear = 0.1
        camera.zFar = 50
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3((lo.x + hi.x) / 2, (lo.y + hi.y) / 2 + 0.25, 10)
        cameraNode.eulerAngles.x = -0.025
        scene.rootNode.addChildNode(cameraNode)

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 450
        scene.rootNode.addChildNode(ambient)
        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.intensity = 800
        key.eulerAngles = SCNVector3(-0.6, -0.45, 0)
        scene.rootNode.addChildNode(key)

        renderer.scene = scene
        renderer.pointOfView = cameraNode
        return renderer.snapshot(atTime: 0, with: CGSize(width: 256, height: 256), antialiasingMode: .multisampling4X)
    }
}

/// A picture of the Dailie: the whole figure, or just the head for tight spots.
struct AvatarPicture: View {
    var look: AvatarLook
    var shirt: VoxelColor = VoxelPalette.purple
    var headOnly = false
    @ObservedObject private var pictures = AvatarPictures.shared

    var body: some View {
        let framing: AvatarPictures.Framing = headOnly ? .head : .full
        let key = AvatarPictures.key(look, shirt: shirt, framing: framing)
        Group {
            if let image = pictures.image(key, look: look, shirt: shirt, framing: framing) {
                Image(uiImage: image).resizable().interpolation(.high).scaledToFit()
            } else {
                Color.clear
            }
        }
        .accessibilityLabel("Avatar")
    }
}

/// The player's head in a round frame: the Home top bar and other small spots.
struct AvatarHead: View {
    var look: AvatarLook
    var shirt: VoxelColor = VoxelPalette.purple
    var size: CGFloat = 36

    var body: some View {
        AvatarPicture(look: look, shirt: shirt, headOnly: true)
            .padding(size * 0.04)
            .frame(width: size, height: size)
            .background(Color(hex: "FFC531"), in: Circle())
            .clipShape(Circle())
    }
}

/// One item drawn on its own, for shop cards.
struct ItemArt: View {
    var item: AvatarItem
    var shirt: VoxelColor = VoxelPalette.purple
    @ObservedObject private var pictures = AvatarPictures.shared

    var body: some View {
        Group {
            if item.slot == .decor {
                DecorArt(id: item.id)
            } else if item.slot == .body {
                Circle().fill(Color(uiColor: AvatarModel.skin(item.id)))
                    .overlay(Circle().strokeBorder(Color(hex: "151412"), lineWidth: 2))
                    .overlay(alignment: .topLeading) {
                        Circle().fill(.white.opacity(0.35)).frame(width: 14, height: 14).padding(10)
                    }
                    .padding(8)
            } else {
                let key = AvatarPictures.key(AvatarLook.starter(handle: ""), shirt: shirt, framing: .item(item))
                if let image = pictures.image(key, look: AvatarLook.starter(handle: ""), shirt: shirt, framing: .item(item)) {
                    Image(uiImage: image).resizable().interpolation(.high).scaledToFit()
                } else {
                    Color.clear
                }
            }
        }
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
