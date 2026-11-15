import SceneKit
import UIKit

// The Dailie as a small low-poly figure: a big round head, big shiny eyes, a short body, and every item
// built from a handful of faceted shapes. The 3D stage shows it turning; small spots show a picture of it.

/// An sRGB colour, for the player's own colour and the avatar palette.
struct VoxelColor: Hashable {
    let r: UInt8, g: UInt8, b: UInt8

    init(_ hex: UInt32) {
        r = UInt8((hex >> 16) & 0xFF)
        g = UInt8((hex >> 8) & 0xFF)
        b = UInt8(hex & 0xFF)
    }

    init(hex: String) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        self.init(UInt32(digits, radix: 16) ?? 0x7C5CFF)
    }

    var ui: UIColor { UIColor(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1) }
}

enum VoxelPalette {
    static let purple = VoxelColor(0x7C5CFF)
}

private func hex(_ value: UInt32) -> UIColor { VoxelColor(value).ui }

enum AvatarModel {
    // palette
    static let ink = hex(0x151412), inkSoft = hex(0x2B2622), cream = hex(0xF3F0E9), white = hex(0xFFFFFF)
    static let gold = hex(0xFFC531), goldDeep = hex(0xF5B301), lip = hex(0xC48A00)
    static let teal = hex(0x1FA89A), tealDeep = hex(0x157A70), purple = hex(0x7C5CFF), coral = hex(0xFF6B57)
    static let red = hex(0xE5483A), pink = hex(0xFF7AB6), blush = hex(0xFF9AA8), denim = hex(0x4A78B8)
    static let brown = hex(0x5A3A22), auburn = hex(0xA4492B), orange = hex(0xFF9F43), lilac = hex(0xB79CFF)
    static let silver = hex(0xD9D5CC), grey = hex(0x8A8579), tan = hex(0xE3B98A), sky = hex(0x8FC1FF)
    static let green = hex(0x8BC34A), greenDeep = hex(0x5E9A2E), mouth = hex(0x8E2B2B)

    static func skin(_ id: String) -> UIColor {
        switch id {
        case "body.porcelain": hex(0xFFE3CC)
        case "body.peach": hex(0xF7C9A3)
        case "body.honey": hex(0xE0A86E)
        case "body.umber": hex(0xA9714A)
        case "body.cocoa": hex(0x6B4430)
        case "body.mint": hex(0x9BE6CF)
        case "body.sky": hex(0xA8CCFF)
        case "body.lilac": hex(0xC9B8FF)
        case "body.coral": hex(0xFF9F8F)
        case "body.gold": hex(0xFFD25A)
        default: hex(0xF7C9A3)
        }
    }

    // the head
    static let head = SCNVector3(0, 1.42, 0)
    static let headR = SCNVector3(0.6, 0.54, 0.55)
    /// Where the hand of the Dailie's right arm ends (the viewer's left).
    static let hand = SCNVector3(-0.45, 0.56, 0.08)

    /// The z of the front of the head at a point on the face.
    static func faceZ(_ x: Float, _ y: Float) -> Float {
        let nx = x / headR.x, ny = (y - head.y) / headR.y
        return headR.z * max(0, 1 - nx * nx - ny * ny).squareRoot()
    }

    /// Builds a Dailie. Parts are grouped under nodes named body, head, face, hair, hat, outfit and gadget.
    static func build(_ look: AvatarLook, shirt: VoxelColor = VoxelPalette.purple) -> SCNNode {
        let root = SCNNode()
        let skin = skin(look.body)
        let groups = ["body", "head", "face", "hair", "hat", "outfit", "gadget"].map { SCNNode().named($0) }
        for g in groups { root.addChildNode(g) }
        let body = groups[0], headNode = groups[1], face = groups[2], hair = groups[3], hat = groups[4], outfit = groups[5], gadget = groups[6]

        // head and ears
        headNode.add(LowPoly.ellipsoid(headR.x, headR.y, headR.z, segments: 12, rings: 9, color: skin).at(head.x, head.y, head.z))
        for side: Float in [-1, 1] {
            headNode.add(LowPoly.ellipsoid(0.09, 0.12, 0.08, segments: 6, rings: 4, color: skin).at(side * 0.59, 1.38, 0.02))
        }

        let clothes = Clothes.of(look.outfit, skin: skin, shirt: shirt.ui)
        // torso
        body.add(LowPoly.frustum(bottom: 0.34, top: 0.27, height: 0.44, segments: 9, depth: 0.78, color: clothes.torso).at(0, 0.54, 0))
        body.add(LowPoly.ellipsoid(0.27, 0.07, 0.21, segments: 9, rings: 3, top: 0, bottom: 0.5, color: clothes.torso).at(0, 0.98, 0))
        body.add(LowPoly.ellipsoid(0.11, 0.06, 0.1, segments: 6, rings: 3, color: skin).at(0, 1.0, 0))
        // arms
        for side: Float in [-1, 1] {
            let arm = SCNNode().at(side * 0.3, 0.94, 0).turned(z: side * 0.32)
            arm.add(LowPoly.frustum(bottom: 0.085, top: 0.1, height: 0.2, segments: 6, color: clothes.upperArm).at(0, -0.2, 0))
            arm.add(LowPoly.frustum(bottom: 0.08, top: 0.085, height: 0.2, segments: 6, color: clothes.lowerArm).at(0, -0.38, 0))
            arm.add(LowPoly.sphere(0.1, segments: 7, rings: 5, color: skin).at(0, -0.42, 0))
            body.add(arm)
        }
        // legs and shoes
        for side: Float in [-1, 1] {
            body.add(LowPoly.frustum(bottom: 0.11, top: 0.13, height: 0.4, segments: 7, color: clothes.legs).at(side * 0.14, 0.16, 0))
            body.add(LowPoly.ellipsoid(0.13, 0.1, 0.19, segments: 8, rings: 4, top: 0, bottom: 0.55, color: clothes.shoes).at(side * 0.14, 0.04, 0.04))
            body.add(LowPoly.box(0.25, 0.05, 0.36, color: cream).at(side * 0.14, 0.03, 0.04))
        }

        Clothes.extras(look.outfit, into: outfit, shirt: shirt.ui)
        Faces.build(look.face, into: face, brows: Hair.color(look.hair))
        Hair.build(look.hair, into: hair, coveredTop: Hats.coversTop(look.hat))
        Hats.build(look.hat, into: hat)
        Gadgets.build(look.gadget, into: gadget)
        return root
    }

    /// Only the given parts, on a body with nothing else showing, for an item card.
    static func item(_ item: AvatarItem, shirt: VoxelColor) -> (node: SCNNode, focus: [String]) {
        let base = AvatarLook(body: "body.peach", face: "face.happy", hair: "hair.short", hat: nil, outfit: "outfit.tee", gadget: nil)
        switch item.slot {
        case .body:
            return (build(base.with(.body, item.id), shirt: shirt), ["body", "head", "face", "hair", "outfit"])
        case .face, .hair:
            let look = item.slot == .hair ? base.with(.hair, item.id) : base.with(.face, item.id)
            return (build(look, shirt: shirt), ["head", "face", "hair"])
        case .hat:
            let node = build(base.with(.hat, item.id), shirt: shirt)
            return (node, ["hat"])
        case .outfit:
            return (build(base.with(.outfit, item.id), shirt: shirt), ["body", "outfit"])
        case .gadget:
            return (build(base.with(.gadget, item.id), shirt: shirt), ["gadget"])
        case .decor:
            return (SCNNode(), [])
        }
    }
}

// MARK: Faces

private enum Faces {
    typealias M = AvatarModel

    static func onFace(_ node: SCNNode, _ x: Float, _ y: Float, lift: Float = 0.005) -> SCNNode {
        let z = M.faceZ(x, y)
        let nx = x / M.headR.x
        let ny = (y - M.head.y) / M.headR.y
        return node.at(x, y, z + lift).turned(x: -ny * 0.9, y: nx * 1.0)
    }

    static func eye(_ x: Float, tall: Float = 0.1) -> SCNNode {
        let eye = SCNNode().named("eye")
        eye.add(LowPoly.ellipsoid(0.075, tall, 0.04, segments: 8, rings: 5, color: M.ink))
        eye.add(LowPoly.sphere(0.028, segments: 5, rings: 3, color: M.white).at(0.025, tall * 0.4, 0.03))
        eye.add(LowPoly.sphere(0.013, segments: 4, rings: 3, color: M.white).at(-0.03, -tall * 0.35, 0.03))
        return onFace(eye, x, 1.41)
    }

    static func closed(_ x: Float, up: Bool) -> SCNNode {
        let arc = SCNNode()
        for side: Float in [-1, 1] {
            arc.add(LowPoly.box(0.08, 0.025, 0.03, bevel: 0.3, color: M.ink).at(side * 0.035, 0, 0).turned(z: side * (up ? -0.45 : 0.45)))
        }
        return onFace(arc, x, 1.41)
    }

    static func brow(_ x: Float, tilt: Float, color: UIColor, y: Float = 1.56) -> SCNNode {
        onFace(LowPoly.box(0.12, 0.028, 0.03, bevel: 0.3, color: color), x, y).turned(z: tilt)
    }

    static func smile(open: Bool) -> SCNNode {
        if open {
            return onFace(LowPoly.ellipsoid(0.09, 0.07, 0.03, segments: 10, rings: 4, top: 0.5, bottom: 1, color: M.mouth), 0, 1.26, lift: -0.005)
        }
        let arc = SCNNode()
        for (x, tilt) in [(-0.045, Float(0.4)), (0.045, Float(-0.4))] {
            arc.add(LowPoly.box(0.065, 0.024, 0.03, bevel: 0.3, color: M.mouth).at(Float(x), 0, 0).turned(z: tilt))
        }
        return onFace(arc, 0, 1.25)
    }

    static func build(_ id: String, into face: SCNNode, brows: UIColor) {
        for side: Float in [-1, 1] {
            face.add(onFace(LowPoly.ellipsoid(0.075, 0.045, 0.02, segments: 8, rings: 3, color: M.blush), side * 0.36, 1.29))
        }
        switch id {
        case "face.smirk":
            face.add(eye(-0.22), eye(0.22), brow(-0.22, tilt: 0.1, color: brows), brow(0.22, tilt: -0.25, color: brows, y: 1.58))
            face.add(onFace(LowPoly.box(0.1, 0.024, 0.03, bevel: 0.3, color: M.mouth), 0.04, 1.26).turned(z: 0.25))
        case "face.wink":
            face.add(eye(-0.22), closed(0.22, up: true), brow(-0.22, tilt: 0.1, color: brows), brow(0.22, tilt: -0.1, color: brows))
            face.add(smile(open: true))
        case "face.determined":
            face.add(eye(-0.22, tall: 0.08), eye(0.22, tall: 0.08))
            face.add(brow(-0.22, tilt: -0.4, color: brows, y: 1.54), brow(0.22, tilt: 0.4, color: brows, y: 1.54))
            face.add(onFace(LowPoly.box(0.1, 0.024, 0.03, bevel: 0.3, color: M.mouth), 0, 1.26))
        case "face.sleepy":
            face.add(closed(-0.22, up: false), closed(0.22, up: false))
            face.add(brow(-0.22, tilt: 0.15, color: brows), brow(0.22, tilt: -0.15, color: brows))
            face.add(onFace(LowPoly.ellipsoid(0.035, 0.04, 0.02, segments: 6, rings: 4, color: M.mouth), 0, 1.25))
        case "face.shades":
            let shades = SCNNode()
            for side: Float in [-1, 1] {
                shades.add(LowPoly.box(0.2, 0.13, 0.04, bevel: 0.25, color: M.ink).at(side * 0.13, 0, 0))
                shades.add(LowPoly.box(0.05, 0.025, 0.045, bevel: 0.3, color: M.gold).at(side * 0.13 + 0.05, 0.03, 0.01))
            }
            shades.add(LowPoly.box(0.08, 0.025, 0.03, color: M.ink))
            face.add(onFace(shades, 0, 1.43, lift: 0.04))
            face.add(onFace(LowPoly.box(0.1, 0.024, 0.03, bevel: 0.3, color: M.mouth), 0.03, 1.26).turned(z: 0.2))
        case "face.stars":
            for x: Float in [-0.22, 0.22] {
                face.add(onFace(LowPoly.star(0.085, color: M.gold).named("eye"), x, 1.41, lift: 0.02))
            }
            face.add(brow(-0.22, tilt: 0.1, color: brows, y: 1.58), brow(0.22, tilt: -0.1, color: brows, y: 1.58))
            face.add(smile(open: true))
        default:
            face.add(eye(-0.22), eye(0.22), brow(-0.22, tilt: 0.08, color: brows), brow(0.22, tilt: -0.08, color: brows))
            face.add(smile(open: false))
        }
    }
}

// MARK: Hair

private enum Hair {
    typealias M = AvatarModel

    static func color(_ id: String?) -> UIColor {
        switch id {
        case "hair.bob", "hair.buzz": M.inkSoft
        case "hair.spiky": M.orange
        case "hair.curly": M.auburn
        case "hair.long": M.lilac
        case "hair.mohawk": M.pink
        default: M.brown
        }
    }

    /// The part of a slightly larger head that hair covers. 0 faces the viewer.
    static func shell(_ grow: Float, top: Float = 0, bottom: Float, from: Float = 0, to: Float = 1, color: UIColor) -> SCNNode {
        LowPoly.ellipsoid(M.headR.x + grow, M.headR.y + grow, M.headR.z + grow, segments: 12, rings: 9,
                          top: top, bottom: bottom, from: from, to: to, color: color).at(M.head.x, M.head.y, M.head.z)
    }

    /// A short fringe of wedges across the forehead.
    static func fringe(_ color: UIColor, count: Int = 5, length: Float = 0.12) -> SCNNode {
        let node = SCNNode()
        for i in 0..<count {
            let t = (Float(i) + 0.5) / Float(count) - 0.5
            let x = t * 0.85
            let y: Float = 1.66
            let wedge = LowPoly.frustum(bottom: 0, top: 0.09, height: length, segments: 4, depth: 0.5, color: color)
            wedge.at(x, y - length, M.faceZ(x, y) + 0.01).turned(x: 0.35, z: -t * 0.5)
            node.add(wedge)
        }
        return node
    }

    static func build(_ id: String?, into hair: SCNNode, coveredTop: Bool) {
        guard let id else { return }
        let c = color(id)
        switch id {
        case "hair.short":
            hair.add(shell(0.04, bottom: 0.4, color: c), shell(0.04, top: 0.38, bottom: 0.68, from: 0.2, to: 0.8, color: c), fringe(c))
        case "hair.bob":
            hair.add(shell(0.05, bottom: 0.4, color: c), shell(0.05, top: 0.38, bottom: 0.82, from: 0.13, to: 0.87, color: c), fringe(c, count: 6, length: 0.14))
        case "hair.spiky":
            hair.add(shell(0.04, bottom: 0.4, color: c), shell(0.04, top: 0.38, bottom: 0.62, from: 0.22, to: 0.78, color: c), fringe(c, count: 4, length: 0.15))
            if !coveredTop {
                for (x, z, tilt) in [(-0.3, 0.1, 0.5), (-0.1, 0.0, 0.15), (0.12, 0.05, -0.15), (0.32, -0.05, -0.5), (0.0, -0.3, 0.0)] as [(Float, Float, Float)] {
                    hair.add(LowPoly.frustum(bottom: 0.13, top: 0, height: 0.3, segments: 5, color: c).at(x, 1.86, z).turned(x: z < -0.2 ? -0.5 : 0, z: tilt))
                }
            }
        case "hair.bun":
            hair.add(shell(0.04, bottom: 0.4, color: c), shell(0.04, top: 0.38, bottom: 0.7, from: 0.2, to: 0.8, color: c), fringe(c, count: 4))
            if !coveredTop { hair.add(LowPoly.sphere(0.2, segments: 8, rings: 6, color: c).at(0, 2.02, -0.12)) }
        case "hair.buzz":
            hair.add(shell(0.015, bottom: 0.33, color: c), shell(0.015, top: 0.3, bottom: 0.6, from: 0.25, to: 0.75, color: c))
        case "hair.curly":
            hair.add(shell(0.05, bottom: 0.42, color: c), shell(0.05, top: 0.4, bottom: 0.72, from: 0.18, to: 0.82, color: c))
            for i in 0..<14 {
                let phi = Float(i) / 14 * 2 * .pi
                let ring: Float = i % 2 == 0 ? 0.55 : 0.4
                let x = sin(phi) * M.headR.x * ring * 1.15, z = cos(phi) * M.headR.z * ring * 1.15
                let y = M.head.y + M.headR.y * (1 - ring * ring * 0.6) + 0.02
                if coveredTop && y > 1.85 { continue }
                hair.add(LowPoly.sphere(0.13, segments: 6, rings: 4, color: c).at(x, y, z))
            }
        case "hair.long":
            hair.add(shell(0.05, bottom: 0.4, color: c), shell(0.05, top: 0.38, bottom: 0.9, from: 0.12, to: 0.88, color: c), fringe(c, count: 6, length: 0.15))
            hair.add(LowPoly.box(0.95, 0.6, 0.18, bevel: 0.3, color: c).at(0, 1.05, -0.33))
        case "hair.mohawk":
            hair.add(shell(0.012, bottom: 0.3, color: M.inkSoft))
            if !coveredTop {
                for i in 0..<5 {
                    let t = Float(i) / 4
                    let angle = (t - 0.35) * 1.9
                    let y = M.head.y + cos(angle) * (M.headR.y + 0.02), z = sin(angle) * (M.headR.z + 0.02)
                    hair.add(LowPoly.frustum(bottom: 0.11, top: 0, height: 0.28, segments: 4, depth: 0.6, color: c).at(0, y, z).turned(x: angle))
                }
            }
        default:
            break
        }
    }
}

// MARK: Hats

private enum Hats {
    typealias M = AvatarModel

    static func coversTop(_ id: String?) -> Bool {
        guard let id else { return false }
        return !["hat.catears", "hat.headset", "hat.halo", "hat.bunny", "hat.flowers"].contains(id)
    }

    static func dome(_ grow: Float, bottom: Float, color: UIColor) -> SCNNode {
        Hair.shell(grow, bottom: bottom, color: color)
    }

    static func build(_ id: String?, into hat: SCNNode) {
        guard let id else { return }
        switch id {
        case "hat.party":
            let cone = SCNNode().at(0.05, 1.86, 0).turned(z: -0.15)
            let heights: [Float] = [0, 0.18, 0.36, 0.54]
            for (i, y0) in heights.dropLast().enumerated() {
                let r0 = 0.32 * (1 - y0 / 0.6), r1 = 0.32 * (1 - heights[i + 1] / 0.6)
                cone.add(LowPoly.frustum(bottom: r0, top: r1, height: 0.18, segments: 8, color: i % 2 == 0 ? M.purple : M.gold).at(0, y0, 0))
            }
            cone.add(LowPoly.frustum(bottom: 0.32 * 0.1, top: 0, height: 0.06, segments: 6, color: M.purple).at(0, 0.54, 0))
            cone.add(LowPoly.sphere(0.07, segments: 6, rings: 4, color: M.cream).at(0, 0.62, 0))
            hat.add(cone)
        case "hat.beanie":
            hat.add(dome(0.08, bottom: 0.4, color: M.teal))
            hat.add(LowPoly.frustum(bottom: 0.66, top: 0.64, height: 0.12, segments: 12, depth: 0.93, color: M.tealDeep).at(0, 1.6, 0))
            hat.add(LowPoly.sphere(0.12, segments: 7, rings: 5, color: M.cream).at(0, 2.05, 0))
        case "hat.cap":
            hat.add(dome(0.07, bottom: 0.38, color: M.inkSoft))
            hat.add(LowPoly.ellipsoid(0.38, 0.03, 0.3, segments: 10, rings: 3, from: -0.25, to: 0.25, color: M.gold).at(0, 1.73, 0.42).turned(x: 0.12))
            hat.add(LowPoly.sphere(0.05, segments: 5, rings: 3, color: M.gold).at(0, 2.03, 0))
        case "hat.catears":
            for side: Float in [-1, 1] {
                let ear = SCNNode().at(side * 0.33, 1.84, 0.02).turned(z: -side * 0.3)
                ear.add(LowPoly.frustum(bottom: 0.15, top: 0, height: 0.3, segments: 3, depth: 0.55, color: M.inkSoft))
                ear.add(LowPoly.frustum(bottom: 0.08, top: 0, height: 0.18, segments: 3, depth: 0.4, color: M.pink).at(0, 0.03, 0.05))
                hat.add(ear)
            }
        case "hat.headset":
            hat.add(LowPoly.torus(ring: 0.66, pipe: 0.04, segments: 14, sides: 4, from: -0.25, to: 0.25, color: M.inkSoft).at(0, 1.42, 0).turned(x: -.pi / 2))
            for side: Float in [-1, 1] {
                hat.add(LowPoly.frustum(bottom: 0.15, top: 0.15, height: 0.12, segments: 8, color: M.gold).at(side * 0.6, 1.4, 0).turned(z: side * .pi / 2))
                hat.add(LowPoly.frustum(bottom: 0.1, top: 0.1, height: 0.04, segments: 8, color: M.lip).at(side * 0.73, 1.4, 0).turned(z: side * .pi / 2))
            }
            hat.add(LowPoly.box(0.035, 0.035, 0.32, color: M.inkSoft).at(-0.58, 1.3, 0.22).turned(y: -0.6))
            hat.add(LowPoly.sphere(0.045, segments: 5, rings: 3, color: M.gold).at(-0.45, 1.27, 0.38))
        case "hat.halo":
            let halo = LowPoly.torus(ring: 0.36, pipe: 0.045, segments: 14, sides: 5, color: M.gold).at(0, 2.18, 0)
            halo.runAction(.repeatForever(.sequence([.moveBy(x: 0, y: 0.05, z: 0, duration: 1.2), .moveBy(x: 0, y: -0.05, z: 0, duration: 1.2)])))
            hat.add(halo)
        case "hat.wizard":
            hat.add(LowPoly.frustum(bottom: 0.82, top: 0.8, height: 0.04, segments: 12, color: M.purple).at(0, 1.78, 0))
            hat.add(LowPoly.frustum(bottom: 0.5, top: 0.48, height: 0.08, segments: 10, color: M.gold).at(0, 1.82, 0))
            let tip = SCNNode().at(0, 1.9, 0)
            tip.add(LowPoly.frustum(bottom: 0.48, top: 0.2, height: 0.5, segments: 10, color: M.purple))
            tip.add(LowPoly.frustum(bottom: 0.2, top: 0, height: 0.35, segments: 8, color: M.purple).at(0, 0.5, 0).turned(z: -0.4))
            tip.add(LowPoly.star(0.08, color: M.gold).at(0.12, 0.25, 0.37).turned(x: -0.4, y: 0.3))
            tip.add(LowPoly.star(0.06, color: M.gold).at(-0.2, 0.12, 0.38).turned(x: -0.3, y: -0.5))
            hat.add(tip)
        case "hat.crown":
            hat.add(LowPoly.frustum(bottom: 0.38, top: 0.42, height: 0.18, segments: 10, caps: false, color: M.gold).at(0, 1.9, 0))
            for i in 0..<5 {
                let phi = Float(i) / 5 * 2 * .pi
                hat.add(LowPoly.frustum(bottom: 0.1, top: 0, height: 0.18, segments: 4, color: M.gold).at(sin(phi) * 0.39, 2.08, cos(phi) * 0.39))
                hat.add(LowPoly.sphere(0.035, segments: 5, rings: 3, color: M.goldDeep).at(sin(phi) * 0.39, 2.27, cos(phi) * 0.39))
            }
            hat.add(LowPoly.sphere(0.06, segments: 6, rings: 4, color: M.red).at(0, 1.99, 0.41))
            hat.add(LowPoly.sphere(0.045, segments: 6, rings: 4, color: M.teal).at(-0.26, 1.99, 0.32))
            hat.add(LowPoly.sphere(0.045, segments: 6, rings: 4, color: M.teal).at(0.26, 1.99, 0.32))
        case "hat.bucket":
            hat.add(LowPoly.frustum(bottom: 0.82, top: 0.62, height: 0.1, segments: 12, color: M.cream).at(0, 1.72, 0))
            hat.add(dome(0.08, bottom: 0.36, color: M.cream))
            hat.add(LowPoly.frustum(bottom: 0.64, top: 0.63, height: 0.06, segments: 12, color: M.tan).at(0, 1.79, 0))
        case "hat.chef":
            hat.add(LowPoly.frustum(bottom: 0.58, top: 0.6, height: 0.22, segments: 12, color: M.white).at(0, 1.78, 0))
            for (x, z) in [(-0.25, 0.0), (0.25, 0.0), (0.0, 0.2), (0.0, -0.2), (0.0, 0.0)] as [(Float, Float)] {
                hat.add(LowPoly.sphere(0.3, segments: 8, rings: 5, color: M.white).at(x, 2.12, z))
            }
        case "hat.bunny":
            for side: Float in [-1, 1] {
                let ear = SCNNode().at(side * 0.2, 1.88, -0.05).turned(z: -side * 0.15)
                ear.add(LowPoly.ellipsoid(0.1, 0.32, 0.06, segments: 8, rings: 5, color: M.white).at(0, 0.3, 0))
                ear.add(LowPoly.ellipsoid(0.055, 0.24, 0.03, segments: 6, rings: 4, color: M.pink).at(0, 0.3, 0.04))
                hat.add(ear)
            }
        case "hat.flowers":
            for i in 0..<8 {
                let phi = Float(i) / 8 * 2 * .pi
                let flower = LowPoly.star(0.1, points: 5, depth: 0.04, color: i % 2 == 0 ? M.pink : M.gold)
                flower.add(LowPoly.sphere(0.035, segments: 4, rings: 3, color: i % 2 == 0 ? M.gold : M.white).at(0, 0, 0.03))
                hat.add(flower.at(sin(phi) * 0.5, 1.84, cos(phi) * 0.46).turned(x: -0.5, y: phi))
            }
        case "hat.pirate":
            hat.add(dome(0.07, bottom: 0.36, color: M.inkSoft))
            hat.add(LowPoly.ellipsoid(0.82, 0.22, 0.52, segments: 6, rings: 4, top: 0, bottom: 0.5, color: M.inkSoft).at(0, 1.82, 0))
            hat.add(LowPoly.torus(ring: 0.62, pipe: 0.03, segments: 12, sides: 4, from: -0.2, to: 0.2, color: M.gold).at(0, 1.86, 0))
            hat.add(LowPoly.star(0.07, color: M.gold).at(0, 1.96, 0.55))
        case "hat.viking":
            hat.add(dome(0.07, bottom: 0.42, color: M.silver))
            hat.add(LowPoly.frustum(bottom: 0.66, top: 0.66, height: 0.08, segments: 12, depth: 0.93, color: M.lip).at(0, 1.62, 0))
            for side: Float in [-1, 1] {
                let horn = SCNNode().at(side * 0.55, 1.78, 0).turned(z: -side * 1.0)
                horn.add(LowPoly.frustum(bottom: 0.1, top: 0.06, height: 0.18, segments: 6, color: M.cream))
                horn.add(LowPoly.frustum(bottom: 0.06, top: 0, height: 0.2, segments: 6, color: M.cream).at(0, 0.18, 0).turned(z: side * 0.6))
                hat.add(horn)
            }
        default:
            break
        }
    }
}

// MARK: Clothes

private struct Clothes {
    typealias M = AvatarModel
    var torso: UIColor
    var upperArm: UIColor
    var lowerArm: UIColor
    var legs: UIColor
    var shoes: UIColor

    static func of(_ id: String?, skin: UIColor, shirt: UIColor) -> Clothes {
        switch id {
        case "outfit.tee": Clothes(torso: shirt, upperArm: shirt, lowerArm: skin, legs: M.denim, shoes: M.inkSoft)
        case "outfit.overalls": Clothes(torso: M.cream, upperArm: M.cream, lowerArm: skin, legs: M.teal, shoes: M.inkSoft)
        case "outfit.sweater": Clothes(torso: M.coral, upperArm: M.coral, lowerArm: M.coral, legs: M.denim, shoes: M.cream)
        case "outfit.hoodie": Clothes(torso: M.gold, upperArm: M.gold, lowerArm: M.gold, legs: M.inkSoft, shoes: M.white)
        case "outfit.tracksuit": Clothes(torso: M.teal, upperArm: M.teal, lowerArm: M.teal, legs: M.teal, shoes: M.white)
        case "outfit.varsity": Clothes(torso: M.purple, upperArm: M.cream, lowerArm: M.cream, legs: M.inkSoft, shoes: M.white)
        case "outfit.cape": Clothes(torso: M.purple, upperArm: M.purple, lowerArm: M.purple, legs: M.purple, shoes: M.red)
        case "outfit.tux": Clothes(torso: M.inkSoft, upperArm: M.inkSoft, lowerArm: M.inkSoft, legs: M.inkSoft, shoes: M.ink)
        case "outfit.astronaut": Clothes(torso: M.white, upperArm: M.white, lowerArm: M.white, legs: M.white, shoes: M.grey)
        case "outfit.pajamas": Clothes(torso: M.sky, upperArm: M.sky, lowerArm: M.sky, legs: M.sky, shoes: M.cream)
        case "outfit.denim": Clothes(torso: M.denim, upperArm: M.denim, lowerArm: M.denim, legs: M.inkSoft, shoes: M.white)
        case "outfit.jersey": Clothes(torso: M.gold, upperArm: M.gold, lowerArm: skin, legs: M.inkSoft, shoes: M.white)
        case "outfit.puffer": Clothes(torso: M.coral, upperArm: M.coral, lowerArm: M.coral, legs: M.denim, shoes: M.inkSoft)
        case "outfit.dino": Clothes(torso: M.green, upperArm: M.green, lowerArm: M.green, legs: M.green, shoes: M.greenDeep)
        default: Clothes(torso: M.silver, upperArm: M.silver, lowerArm: skin, legs: M.denim, shoes: M.inkSoft)
        }
    }

    /// A thin band around the torso at height \`y\`.
    static func band(_ y: Float, _ color: UIColor, grow: Float = 0.012) -> SCNNode {
        let t = (y - 0.54) / 0.44
        let r = 0.34 + (0.27 - 0.34) * t + grow
        return LowPoly.frustum(bottom: r, top: r - 0.005, height: 0.05, segments: 9, depth: 0.78, caps: false, color: color).at(0, y, 0)
    }

    /// A patch on the front of the torso.
    static func front(_ w: Float, _ h: Float, x: Float = 0, y: Float, _ color: UIColor) -> SCNNode {
        let t = (y - 0.54) / 0.44
        let r = 0.34 + (0.27 - 0.34) * t
        return LowPoly.box(w, h, 0.03, bevel: 0.2, color: color).at(x, y, r * 0.78 + 0.005).turned(x: -0.16)
    }

    static func extras(_ id: String?, into o: SCNNode, shirt: UIColor) {
        switch id {
        case "outfit.overalls":
            o.add(front(0.34, 0.26, y: 0.72, M.teal))
            for side: Float in [-1, 1] {
                o.add(front(0.06, 0.2, x: side * 0.15, y: 0.88, M.teal))
                o.add(LowPoly.sphere(0.03, segments: 5, rings: 3, color: M.gold).at(side * 0.15, 0.82, 0.29))
            }
            o.add(band(0.55, M.teal, grow: 0.01))
        case "outfit.sweater":
            o.add(band(0.66, M.cream), band(0.82, M.cream))
        case "outfit.hoodie":
            o.add(LowPoly.torus(ring: 0.25, pipe: 0.08, segments: 10, sides: 5, from: 0.25, to: 0.75, color: M.gold).at(0, 1.0, 0.02).turned(x: 0.3))
            o.add(LowPoly.ellipsoid(0.3, 0.22, 0.12, segments: 8, rings: 4, color: M.goldDeep).at(0, 1.1, -0.28))
            o.add(front(0.26, 0.12, y: 0.65, M.lip))
            for side: Float in [-1, 1] { o.add(front(0.025, 0.14, x: side * 0.07, y: 0.88, M.cream)) }
        case "outfit.tracksuit":
            o.add(front(0.025, 0.42, y: 0.76, M.cream))
            for side: Float in [-1, 1] {
                o.add(LowPoly.box(0.03, 0.4, 0.03, color: M.cream).at(side * 0.25, 0.37, 0.0).turned(z: 0))
            }
        case "outfit.varsity":
            o.add(front(0.11, 0.13, x: -0.13, y: 0.82, M.gold))
            o.add(band(0.55, M.cream))
            o.add(front(0.025, 0.4, y: 0.76, M.cream))
        case "outfit.cape":
            o.add(LowPoly.frustum(bottom: 0.55, top: 0.3, height: 0.8, segments: 8, depth: 0.5, caps: false, color: M.red)
                .at(0, 0.18, -0.08))
            o.add(LowPoly.star(0.1, color: M.gold).at(0, 0.8, 0.27).turned(x: -0.16))
        case "outfit.tux":
            o.add(front(0.14, 0.4, y: 0.76, M.white))
            o.add(LowPoly.frustum(bottom: 0.05, top: 0, height: 0.07, segments: 3, color: M.gold).at(-0.04, 0.94, 0.26).turned(z: .pi / 2))
            o.add(LowPoly.frustum(bottom: 0.05, top: 0, height: 0.07, segments: 3, color: M.gold).at(0.04, 0.94, 0.26).turned(z: -.pi / 2))
            o.add(LowPoly.sphere(0.03, segments: 4, rings: 3, color: M.lip).at(0, 0.94, 0.27))
        case "outfit.astronaut":
            o.add(front(0.2, 0.16, y: 0.75, M.gold))
            o.add(LowPoly.sphere(0.03, segments: 4, rings: 3, color: M.red).at(-0.05, 0.77, 0.3))
            o.add(LowPoly.sphere(0.03, segments: 4, rings: 3, color: M.teal).at(0.05, 0.73, 0.3))
            o.add(LowPoly.torus(ring: 0.3, pipe: 0.06, segments: 10, sides: 4, color: M.silver).at(0, 1.0, 0))
            o.add(LowPoly.box(0.42, 0.42, 0.18, color: M.silver).at(0, 0.78, -0.3))
        case "outfit.pajamas":
            for (x, y) in [(-0.14, 0.86), (0.12, 0.74), (-0.06, 0.62), (0.18, 0.92)] as [(Float, Float)] {
                o.add(LowPoly.star(0.04, depth: 0.02, color: M.gold).at(x, y, 0.27).turned(x: -0.16))
            }
        case "outfit.denim":
            o.add(front(0.14, 0.4, y: 0.76, M.cream))
            o.add(band(0.56, M.denim, grow: 0.02))
            for y: Float in [0.86, 0.74, 0.62] { o.add(LowPoly.sphere(0.022, segments: 4, rings: 3, color: M.gold).at(0.1, y, 0.29)) }
        case "outfit.jersey":
            o.add(front(0.04, 0.2, x: 0.01, y: 0.76, M.inkSoft))
            o.add(front(0.05, 0.03, x: -0.02, y: 0.85, M.inkSoft))
            o.add(band(0.94, M.inkSoft))
        case "outfit.puffer":
            for y: Float in [0.6, 0.72, 0.84] { o.add(band(y, M.coral, grow: 0.04)) }
            o.add(LowPoly.torus(ring: 0.22, pipe: 0.07, segments: 10, sides: 4, color: M.coral).at(0, 1.0, 0))
        case "outfit.dino":
            o.add(front(0.3, 0.32, y: 0.74, M.cream))
            for i in 0..<5 {
                let angle = -0.2 - Float(i) * 0.38
                let y = M.head.y + cos(angle) * (M.headR.y + 0.02), z = sin(angle) * (M.headR.z + 0.02)
                o.add(LowPoly.frustum(bottom: 0.1, top: 0, height: 0.18, segments: 4, depth: 0.5, color: M.greenDeep).at(0, y, z).turned(x: angle))
            }
            for y: Float in [0.95, 0.75, 0.55] { o.add(LowPoly.frustum(bottom: 0.08, top: 0, height: 0.14, segments: 4, depth: 0.5, color: M.greenDeep).at(0, y, -0.28).turned(x: -1.5)) }
        default:
            break
        }
    }
}

// MARK: Gadgets

private enum Gadgets {
    typealias M = AvatarModel

    static func build(_ id: String?, into g: SCNNode) {
        guard let id else { return }
        let hand = SCNNode().at(M.hand.x, M.hand.y, M.hand.z + 0.06)
        g.add(hand)
        switch id {
        case "gadget.phone":
            hand.add(LowPoly.box(0.13, 0.22, 0.03, color: M.inkSoft).at(0, 0.06, 0.02))
            hand.add(LowPoly.box(0.1, 0.17, 0.01, bevel: 0.1, color: M.teal).at(0, 0.07, 0.04))
        case "gadget.controller", "gadget.goldpad":
            let body = id == "gadget.goldpad" ? M.gold : M.inkSoft
            let pad = SCNNode().at(0.02, 0.0, 0.08).turned(x: 0.5)
            pad.add(LowPoly.box(0.32, 0.12, 0.1, bevel: 0.4, color: body))
            for side: Float in [-1, 1] { pad.add(LowPoly.sphere(0.075, segments: 6, rings: 4, color: body).at(side * 0.14, -0.04, 0)) }
            pad.add(LowPoly.box(0.07, 0.022, 0.02, color: M.cream).at(-0.09, 0.01, 0.055))
            pad.add(LowPoly.box(0.022, 0.07, 0.02, color: M.cream).at(-0.09, 0.01, 0.055))
            pad.add(LowPoly.sphere(0.022, segments: 5, rings: 3, color: id == "gadget.goldpad" ? M.inkSoft : M.gold).at(0.08, 0.025, 0.055))
            pad.add(LowPoly.sphere(0.022, segments: 5, rings: 3, color: id == "gadget.goldpad" ? M.red : M.teal).at(0.12, -0.01, 0.055))
            hand.add(pad)
        case "gadget.joystick":
            hand.add(LowPoly.box(0.24, 0.08, 0.18, color: M.inkSoft).at(0, -0.06, 0.04))
            hand.add(LowPoly.frustum(bottom: 0.02, top: 0.02, height: 0.16, segments: 5, color: M.silver).at(0, -0.02, 0.04))
            hand.add(LowPoly.sphere(0.065, segments: 7, rings: 5, color: M.red).at(0, 0.17, 0.04))
            hand.add(LowPoly.sphere(0.025, segments: 5, rings: 3, color: M.gold).at(0.08, -0.01, 0.1))
        case "gadget.boba":
            hand.add(LowPoly.frustum(bottom: 0.08, top: 0.1, height: 0.24, segments: 8, color: M.tan).at(0, -0.06, 0.03))
            hand.add(LowPoly.ellipsoid(0.1, 0.05, 0.1, segments: 8, rings: 3, top: 0, bottom: 0.5, color: M.cream).at(0, 0.18, 0.03))
            hand.add(LowPoly.frustum(bottom: 0.015, top: 0.015, height: 0.18, segments: 5, color: M.pink).at(0.02, 0.18, 0.03).turned(z: -0.2))
            for (x, z) in [(-0.04, 0.09), (0.03, 0.1), (0.0, 0.11)] as [(Float, Float)] {
                hand.add(LowPoly.sphere(0.02, segments: 4, rings: 3, color: M.inkSoft).at(x, -0.03, z))
            }
        case "gadget.mic":
            hand.add(LowPoly.frustum(bottom: 0.03, top: 0.04, height: 0.2, segments: 6, color: M.inkSoft).at(0, -0.06, 0.03))
            hand.add(LowPoly.frustum(bottom: 0.05, top: 0.05, height: 0.03, segments: 8, color: M.gold).at(0, 0.14, 0.03))
            hand.add(LowPoly.sphere(0.08, segments: 7, rings: 5, color: M.silver).at(0, 0.22, 0.03))
        case "gadget.trophy", "gadget.wand":
            if id == "gadget.trophy" {
                hand.add(LowPoly.box(0.16, 0.05, 0.12, color: M.lip).at(0, -0.05, 0.04))
                hand.add(LowPoly.frustum(bottom: 0.03, top: 0.03, height: 0.1, segments: 6, color: M.gold).at(0, -0.03, 0.04))
                hand.add(LowPoly.frustum(bottom: 0.05, top: 0.15, height: 0.18, segments: 8, color: M.gold).at(0, 0.07, 0.04))
                for side: Float in [-1, 1] {
                    hand.add(LowPoly.torus(ring: 0.05, pipe: 0.015, segments: 8, sides: 4, color: M.gold).at(side * 0.15, 0.17, 0.04).turned(z: .pi / 2))
                }
            } else {
                hand.add(LowPoly.frustum(bottom: 0.015, top: 0.015, height: 0.36, segments: 5, color: M.inkSoft).at(0, -0.06, 0.04).turned(z: 0.15))
                let star = LowPoly.star(0.11, depth: 0.05, color: M.gold).at(-0.05, 0.34, 0.04)
                star.runAction(.repeatForever(.rotateBy(x: 0, y: 2 * .pi, z: 0, duration: 3)))
                hand.add(star)
            }
        case "gadget.icecream":
            hand.add(LowPoly.frustum(bottom: 0, top: 0.08, height: 0.2, segments: 7, color: M.tan).at(0, -0.06, 0.04))
            hand.add(LowPoly.sphere(0.085, segments: 7, rings: 5, color: M.pink).at(0, 0.18, 0.04))
            hand.add(LowPoly.sphere(0.075, segments: 7, rings: 5, color: M.cream).at(0, 0.29, 0.04))
        case "gadget.balloon":
            hand.add(LowPoly.frustum(bottom: 0.006, top: 0.006, height: 0.95, segments: 3, caps: false, color: M.ink).at(0, 0, 0))
            let balloon = LowPoly.ellipsoid(0.17, 0.21, 0.17, segments: 9, rings: 6, color: M.gold).at(-0.04, 1.12, 0)
            balloon.add(LowPoly.frustum(bottom: 0.03, top: 0, height: 0.04, segments: 4, color: M.goldDeep).at(0, -0.24, 0))
            balloon.runAction(.repeatForever(.sequence([.rotateTo(x: 0, y: 0, z: 0.12, duration: 1.4), .rotateTo(x: 0, y: 0, z: -0.12, duration: 1.4)])))
            hand.add(balloon)
        case "gadget.plush":
            let bear = SCNNode().at(0, 0.02, 0.1)
            bear.add(LowPoly.sphere(0.11, segments: 7, rings: 5, color: M.tan))
            bear.add(LowPoly.sphere(0.09, segments: 7, rings: 5, color: M.tan).at(0, 0.16, 0))
            for side: Float in [-1, 1] { bear.add(LowPoly.sphere(0.035, segments: 5, rings: 3, color: M.tan).at(side * 0.07, 0.24, 0)) }
            bear.add(LowPoly.sphere(0.035, segments: 5, rings: 3, color: M.cream).at(0, 0.14, 0.08))
            for side: Float in [-1, 1] { bear.add(LowPoly.sphere(0.014, segments: 4, rings: 3, color: M.ink).at(side * 0.035, 0.19, 0.08)) }
            hand.add(bear)
        case "gadget.camera":
            hand.add(LowPoly.box(0.22, 0.15, 0.1, color: M.inkSoft).at(0, 0.04, 0.06))
            hand.add(LowPoly.frustum(bottom: 0.05, top: 0.05, height: 0.06, segments: 8, color: M.silver).at(0, 0.04, 0.1).turned(x: .pi / 2))
            hand.add(LowPoly.sphere(0.02, segments: 4, rings: 3, color: M.gold).at(0.07, 0.13, 0.06))
        default:
            break
        }
    }
}
