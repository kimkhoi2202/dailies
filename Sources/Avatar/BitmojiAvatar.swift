import SwiftUI

// The Dailie as a Bitmoji-style character: one of the full-body pictures in Resources/Avatars.xcassets,
// with the hat and gadget the player wears drawn over it.

enum Bitmoji {
    static let names = ["me", "khoi", "ben", "dylan", "nyx", "kiko", "vanessa", "kaz", "devon", "noor", "tofu", "juno", "sam", "blond"]

    /// The seeded players have their own character.
    private static let known = ["devon.plays": "devon", "kaz": "kaz", "noor.runs": "noor", "tofu": "tofu", "juno": "juno",
                                "wordnerd.sam": "sam", "khoi": "khoi", "ben": "ben", "vanessa": "vanessa"]

    /// The item id of the character a handle starts with.
    static func character(handle: String) -> String {
        if let name = known[handle] { return "char.\(name)" }
        var sum = 0
        for unit in handle.utf16 { sum = (sum * 31 + Int(unit)) % 100003 }
        return "char.\(names[sum % names.count])"
    }

    /// The picture name for a look, falling back to the handle's character for looks from before characters.
    static func name(_ look: AvatarLook, handle: String) -> String {
        let id = look.body.hasPrefix("char.") ? look.body : character(handle: handle)
        let name = String(id.dropFirst(5))
        return names.contains(name) ? name : "me"
    }
}

/// The full-body character, standing, with its hat and gadget on. Taps make it hop.
struct BitmojiFigure: View {
    var look: AvatarLook
    var handle: String
    var shirt: VoxelColor = VoxelPalette.purple
    var onTap: (() -> Void)? = nil
    @State private var hop = 0
    @State private var breathe = false

    var body: some View {
        GeometryReader { proxy in
            let h = proxy.size.height, w = h * 0.3
            ZStack(alignment: .top) {
                Ellipse().fill(.black.opacity(0.35)).frame(width: w * 0.9, height: h * 0.05)
                    .blur(radius: 4).offset(y: h * 0.95)
                Image("avatar-\(Bitmoji.name(look, handle: handle))")
                    .resizable().interpolation(.high).scaledToFit()
                    .frame(height: h)
                if let gadget = AvatarCatalog.item(look.gadget) {
                    ItemArt(item: gadget, shirt: shirt)
                        .frame(width: w * 0.42, height: w * 0.42)
                        .scaleEffect(1.6)
                        .offset(x: -w * 0.5, y: h * 0.42)
                }
                if let hat = AvatarCatalog.item(look.hat) {
                    ItemArt(item: hat, shirt: shirt)
                        .frame(width: w * 1.2, height: w * 0.8)
                        .scaleEffect(2)
                        .offset(y: -h * 0.06)
                }
            }
            .frame(width: proxy.size.width, height: h, alignment: .top)
            .scaleEffect(x: 1, y: breathe ? 1.012 : 1, anchor: .bottom)
            .keyframeAnimator(initialValue: 0.0, trigger: hop) { content, lift in
                content.offset(y: -lift)
            } keyframes: { _ in
                SpringKeyframe(h * 0.06, duration: 0.16)
                SpringKeyframe(0, duration: 0.4, spring: .bouncy)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                hop += 1
                onTap?()
            }
        }
        .onAppear { withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { breathe = true } }
        .accessibilityLabel("Avatar")
    }
}
