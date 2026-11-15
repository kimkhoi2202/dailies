import Foundation

// A Dailie as voxels: chibi proportions (a big head on a small body), a short list of colours, and
// every item built from the same blocks. The 3D stage meshes these voxels in SceneKit and the flat
// pixel avatar draws the same grid from the front, so both always agree.
//
// The grid: x runs 0 to 15 left to right as you face the Dailie, y runs up from the soles at 0,
// z runs toward you. The head spans x 1...14, y 9...21, z 0...11. The Dailie's right hand is at x 2...3.

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
}

struct VoxelPoint: Hashable {
    var x: Int, y: Int, z: Int
}

/// Which part of the avatar a voxel belongs to, so an item can be drawn on its own.
struct VoxelPart: OptionSet, Hashable {
    let rawValue: UInt8
    static let skin = VoxelPart(rawValue: 1)
    static let face = VoxelPart(rawValue: 2)
    static let hair = VoxelPart(rawValue: 4)
    static let hat = VoxelPart(rawValue: 8)
    static let outfit = VoxelPart(rawValue: 16)
    static let gadget = VoxelPart(rawValue: 32)
    static let shoes = VoxelPart(rawValue: 64)
    static let all: VoxelPart = [.skin, .face, .hair, .hat, .outfit, .gadget, .shoes]
}

struct VoxelCell: Hashable {
    var color: VoxelColor
    var part: VoxelPart
}

struct VoxelGrid {
    var cells: [VoxelPoint: VoxelCell] = [:]

    func has(_ x: Int, _ y: Int, _ z: Int) -> Bool { cells[VoxelPoint(x: x, y: y, z: z)] != nil }

    mutating func set(_ x: Int, _ y: Int, _ z: Int, _ color: VoxelColor, _ part: VoxelPart) {
        cells[VoxelPoint(x: x, y: y, z: z)] = VoxelCell(color: color, part: part)
    }

    mutating func box(_ xs: ClosedRange<Int>, _ ys: ClosedRange<Int>, _ zs: ClosedRange<Int>,
                      _ color: VoxelColor, _ part: VoxelPart) {
        for x in xs { for y in ys { for z in zs { set(x, y, z, color, part) } } }
    }

    /// Every cell of a box with rounded edges and corners. `radius` is in voxels.
    static func rounded(_ xs: ClosedRange<Int>, _ ys: ClosedRange<Int>, _ zs: ClosedRange<Int>,
                        radius: Double) -> [VoxelPoint] {
        var points: [VoxelPoint] = []
        func out(_ v: Int, _ range: ClosedRange<Int>) -> Double {
            let low = Double(range.lowerBound) + radius, high = Double(range.upperBound) - radius
            return max(0, low - Double(v), Double(v) - high)
        }
        let limit = radius * radius + 0.5
        for x in xs { for y in ys { for z in zs {
            let dx = out(x, xs), dy = out(y, ys), dz = out(z, zs)
            if dx * dx + dy * dy + dz * dz <= limit { points.append(VoxelPoint(x: x, y: y, z: z)) }
        } } }
        return points
    }

    mutating func fill(_ points: [VoxelPoint], _ color: VoxelColor, _ part: VoxelPart) {
        for p in points { cells[p] = VoxelCell(color: color, part: part) }
    }

    /// The z of the frontmost voxel in a column, if there is one.
    func frontZ(_ x: Int, _ y: Int) -> Int? {
        for z in stride(from: 24, through: -8, by: -1) where has(x, y, z) { return z }
        return nil
    }

    /// Paints the voxel you see when you look at the Dailie straight on.
    mutating func paint(_ x: Int, _ y: Int, _ color: VoxelColor, _ part: VoxelPart) {
        guard let z = frontZ(x, y) else { return }
        set(x, y, z, color, part)
    }

    /// Paints a cell and its mirror across the middle of the face.
    mutating func paintPair(_ x: Int, _ y: Int, _ color: VoxelColor, _ part: VoxelPart) {
        paint(x, y, color, part)
        paint(15 - x, y, color, part)
    }

    mutating func remove(where test: (VoxelPoint, VoxelCell) -> Bool) {
        cells = cells.filter { !test($0.key, $0.value) }
    }

    func only(_ parts: VoxelPart) -> VoxelGrid {
        var grid = VoxelGrid()
        grid.cells = cells.filter { !$0.value.part.isDisjoint(with: parts) }
        return grid
    }
}

/// The colours a Dailie is made of: our gold, cream and ink, the game tints, and the ten body colours.
enum VoxelPalette {
    static let ink = VoxelColor(0x151412)
    static let inkSoft = VoxelColor(0x2B2622)
    static let cream = VoxelColor(0xF3F0E9)
    static let white = VoxelColor(0xFFFFFF)
    static let gold = VoxelColor(0xFFC531)
    static let goldDeep = VoxelColor(0xF5B301)
    static let lip = VoxelColor(0xC48A00)
    static let teal = VoxelColor(0x1FA89A)
    static let tealDeep = VoxelColor(0x157A70)
    static let purple = VoxelColor(0x7C5CFF)
    static let coral = VoxelColor(0xFF6B57)
    static let red = VoxelColor(0xE5483A)
    static let pink = VoxelColor(0xFF7AB6)
    static let blush = VoxelColor(0xFF9AA8)
    static let denim = VoxelColor(0x3E6FB0)
    static let brown = VoxelColor(0x5A3A22)
    static let auburn = VoxelColor(0xA4492B)
    static let orange = VoxelColor(0xFF9F43)
    static let lilac = VoxelColor(0xB79CFF)
    static let silver = VoxelColor(0xD9D5CC)
    static let grey = VoxelColor(0x8A8579)
    static let tan = VoxelColor(0xE3B98A)

    static func skin(_ id: String) -> VoxelColor {
        switch id {
        case "body.porcelain": VoxelColor(0xFFE3CC)
        case "body.peach": VoxelColor(0xF7C9A3)
        case "body.honey": VoxelColor(0xE0A86E)
        case "body.umber": VoxelColor(0xA9714A)
        case "body.cocoa": VoxelColor(0x6B4430)
        case "body.mint": VoxelColor(0x9BE6CF)
        case "body.sky": VoxelColor(0xA8CCFF)
        case "body.lilac": VoxelColor(0xC9B8FF)
        case "body.coral": VoxelColor(0xFF9F8F)
        case "body.gold": VoxelColor(0xFFD25A)
        default: VoxelColor(0xF7C9A3)
        }
    }
}

enum VoxelAvatar {
    private typealias P = VoxelPalette

    static let headX = 1...14, headY = 9...21, headZ = 0...11
    static let headRadius = 2.6

    /// Builds a Dailie. `shirt` is the player's own colour, used by the Signature Tee.
    /// `blink` closes the eyes, for the idle blink.
    static func build(_ look: AvatarLook, shirt: VoxelColor = VoxelPalette.purple, blink: Bool = false) -> VoxelGrid {
        var g = VoxelGrid()
        let skin = P.skin(look.body)
        let head = VoxelGrid.rounded(headX, headY, headZ, radius: headRadius)
        let headSet = Set(head)

        // Body: shoes, legs, torso, arms. The outfit recolours these below.
        for left in [4, 9] {
            g.box(left...(left + 2), 0...0, 4...8, P.cream, .shoes)
            g.box(left...(left + 2), 1...1, 4...8, P.inkSoft, .shoes)
            g.box(left...(left + 2), 2...2, 4...7, skin, .skin)
        }
        g.fill(VoxelGrid.rounded(4...11, 3...8, 3...8, radius: 1.0), skin, .skin)
        for x in [2, 12] {
            g.box(x...(x + 1), 3...8, 5...6, skin, .skin)
        }
        g.fill(head, skin, .skin)

        outfit(look.outfit, in: &g, skin: skin, shirt: shirt)
        face(look.face, in: &g, blink: blink)
        hair(look.hair, in: &g, head: headSet, hat: look.hat)
        hat(look.hat, in: &g, head: headSet)
        gadget(look.gadget, in: &g)
        return g
    }

    /// One item on its own, for shop cards. Faces and bodies show on a head; outfits show on a body.
    static func item(_ item: AvatarItem, shirt: VoxelColor = VoxelPalette.purple) -> VoxelGrid {
        let base = AvatarLook(body: "body.peach", face: "face.happy", hair: nil, hat: nil, outfit: nil, gadget: nil)
        switch item.slot {
        case .body:
            return build(AvatarLook(body: item.id, face: "face.happy", hair: nil, outfit: "outfit.tee"), shirt: shirt)
        case .face:
            return build(base.with(.face, item.id).with(.body, "body.peach"), shirt: shirt).headOnly
        case .hair:
            return build(base.with(.hair, item.id), shirt: shirt).headOnly
        case .hat:
            return build(base.with(.hat, item.id), shirt: shirt).only([.hat])
        case .outfit:
            return build(base.with(.outfit, item.id), shirt: shirt).only([.outfit, .shoes]).below(9)
        case .gadget:
            return build(base.with(.gadget, item.id), shirt: shirt).only([.gadget])
        }
    }

    // MARK: Outfits

    private static func outfit(_ id: String?, in g: inout VoxelGrid, skin: VoxelColor, shirt: VoxelColor) {
        func torso(_ color: VoxelColor) {
            for (p, c) in g.cells where c.part == .skin && (3...8).contains(p.y) && (4...11).contains(p.x) {
                g.cells[p] = VoxelCell(color: color, part: .outfit)
            }
        }
        func sleeves(_ color: VoxelColor, from y0: Int) {
            for x in [2, 3, 12, 13] { for y in y0...8 { for z in 5...6 { g.set(x, y, z, color, .outfit) } } }
        }
        func legs(_ color: VoxelColor) {
            for left in [4, 9] { g.box(left...(left + 2), 2...2, 4...7, color, .outfit) }
        }
        func row(_ y: Int, _ color: VoxelColor) {
            for (p, c) in g.cells where p.y == y && c.part == .outfit && (4...11).contains(p.x) {
                g.cells[p] = VoxelCell(color: color, part: .outfit)
            }
        }
        let front = 8

        switch id {
        case "outfit.tee":
            torso(shirt); sleeves(shirt, from: 7); legs(P.denim); row(3, P.denim)
        case "outfit.overalls":
            torso(P.cream); sleeves(P.cream, from: 7); legs(P.teal)
            for y in 3...5 { row(y, P.teal) }
            g.box(5...10, 6...7, front...front, P.teal, .outfit)
            g.set(5, 8, front, P.teal, .outfit); g.set(10, 8, front, P.teal, .outfit)
            g.set(5, 7, front, P.gold, .outfit); g.set(10, 7, front, P.gold, .outfit)
        case "outfit.sweater":
            torso(P.coral); sleeves(P.coral, from: 5); legs(P.denim)
            row(4, P.cream); row(7, P.cream)
            for x in [2, 3, 12, 13] { for z in 5...6 { g.set(x, 5, z, P.cream, .outfit) } }
        case "outfit.hoodie":
            torso(P.gold); sleeves(P.gold, from: 5); legs(P.inkSoft)
            g.box(6...9, 4...5, front...front, P.lip, .outfit)
            g.box(3...12, 9...11, -1...0, P.gold, .outfit)
            g.box(4...11, 12...12, -1...0, P.goldDeep, .outfit)
            for x in [6, 9] { g.set(x, 7, front + 1, P.cream, .outfit); g.set(x, 6, front + 1, P.cream, .outfit) }
        case "outfit.tracksuit":
            torso(P.teal); sleeves(P.teal, from: 5); legs(P.teal)
            for y in 5...8 { for z in 5...6 { g.set(2, y, z, P.cream, .outfit); g.set(13, y, z, P.cream, .outfit) } }
            for z in 4...7 { g.set(4, 2, z, P.cream, .outfit); g.set(11, 2, z, P.cream, .outfit) }
            for y in 3...8 { g.set(7, y, front, P.cream, .outfit) }
        case "outfit.varsity":
            torso(P.purple); sleeves(P.cream, from: 5); legs(P.inkSoft)
            g.box(5...6, 5...7, front...front, P.gold, .outfit)
            g.set(6, 6, front, P.purple, .outfit)
            for x in 6...9 { g.set(x, 8, front, P.cream, .outfit) }
        case "outfit.cape":
            torso(P.purple); sleeves(P.purple, from: 5); legs(P.purple)
            g.box(7...8, 5...6, front...front, P.gold, .outfit)
            g.set(6, 6, front, P.gold, .outfit); g.set(9, 6, front, P.gold, .outfit)
            g.set(7, 7, front, P.gold, .outfit); g.set(8, 4, front, P.gold, .outfit)
            g.box(3...12, 0...8, 2...2, P.red, .outfit)
            g.box(4...11, 8...8, 1...1, P.red, .outfit)
        case "outfit.tux":
            torso(P.inkSoft); sleeves(P.inkSoft, from: 5); legs(P.inkSoft)
            for y in 3...8 { g.set(7, y, front, P.cream, .outfit); g.set(8, y, front, P.cream, .outfit) }
            for x in 6...9 { g.set(x, 8, front + 1, x == 7 || x == 8 ? P.lip : P.gold, .outfit) }
            g.set(7, 5, front, P.inkSoft, .outfit); g.set(8, 6, front, P.inkSoft, .outfit)
        case "outfit.astronaut":
            torso(P.cream); sleeves(P.cream, from: 3); legs(P.cream)
            g.box(6...9, 5...6, (front + 1)...(front + 1), P.gold, .outfit)
            g.set(6, 6, front + 1, P.red, .outfit); g.set(9, 5, front + 1, P.teal, .outfit)
            g.box(5...10, 3...8, 1...2, P.silver, .outfit)
            g.box(6...9, 7...7, 0...0, P.grey, .outfit)
            for left in [4, 9] { g.box(left...(left + 2), 1...1, 4...8, P.grey, .shoes) }
        default:
            row(3, P.inkSoft)
            for left in [4, 9] { g.box(left...(left + 2), 2...2, 4...7, skin, .skin) }
        }
    }

    // MARK: Faces

    private static func face(_ id: String, in g: inout VoxelGrid, blink: Bool) {
        let f = VoxelPart.face
        func openEyes(height: Int = 3) {
            for x in [4, 5, 10, 11] { for y in 13..<(13 + height) { g.paint(x, y, P.ink, f) } }
            g.paint(4, 12 + height, P.white, f); g.paint(10, 12 + height, P.white, f)
        }
        func closedEye(_ x: Int) {
            g.paint(x, 14, P.ink, f); g.paint(x + 1, 14, P.ink, f)
        }
        func eyes(height: Int = 3) {
            if blink { closedEye(4); closedEye(10) } else { openEyes(height: height) }
        }
        func smile(open: Bool) {
            g.paint(6, 11, P.ink, f); g.paint(9, 11, P.ink, f)
            g.paint(7, 10, P.ink, f); g.paint(8, 10, P.ink, f)
            if open { g.paint(7, 11, P.red, f); g.paint(8, 11, P.red, f) }
        }
        // blush
        g.paintPair(2, 12, P.blush, f); g.paintPair(3, 12, P.blush, f)

        switch id {
        case "face.smirk":
            eyes()
            g.paint(7, 10, P.ink, f); g.paint(8, 10, P.ink, f); g.paint(9, 11, P.ink, f)
        case "face.wink":
            if blink { closedEye(4) } else {
                for y in 13...15 { g.paint(4, y, P.ink, f); g.paint(5, y, P.ink, f) }
                g.paint(4, 15, P.white, f)
            }
            g.paint(9, 13, P.ink, f); g.paint(10, 14, P.ink, f); g.paint(11, 14, P.ink, f); g.paint(12, 13, P.ink, f)
            smile(open: true)
        case "face.determined":
            eyes(height: 2)
            g.paint(3, 17, P.ink, f); g.paint(4, 17, P.ink, f); g.paint(5, 16, P.ink, f); g.paint(6, 16, P.ink, f)
            g.paint(9, 16, P.ink, f); g.paint(10, 16, P.ink, f); g.paint(11, 17, P.ink, f); g.paint(12, 17, P.ink, f)
            g.paint(7, 11, P.ink, f); g.paint(8, 11, P.ink, f)
        case "face.sleepy":
            closedEye(4); closedEye(10)
            g.paint(3, 15, P.ink, f); g.paint(12, 15, P.ink, f)
            g.paint(7, 11, P.ink, f); g.paint(8, 11, P.ink, f); g.paint(7, 10, P.ink, f); g.paint(8, 10, P.ink, f)
        case "face.shades":
            for x in [3, 4, 5, 6, 9, 10, 11, 12] { for y in 13...15 { g.paint(x, y, P.ink, f) } }
            g.paint(7, 15, P.ink, f); g.paint(8, 15, P.ink, f)
            g.paint(4, 15, P.gold, f); g.paint(10, 15, P.gold, f)
            for z in 4...8 { g.set(1, 15, z, P.ink, f); g.set(14, 15, z, P.ink, f) }
            g.paint(7, 10, P.ink, f); g.paint(8, 10, P.ink, f); g.paint(9, 11, P.ink, f)
        case "face.stars":
            if blink { closedEye(4); closedEye(10) } else {
                for (cx, cy) in [(4, 14), (11, 14)] {
                    g.paint(cx, cy, P.gold, f)
                    g.paint(cx - 1, cy, P.gold, f); g.paint(cx + 1, cy, P.gold, f)
                    g.paint(cx, cy - 1, P.gold, f); g.paint(cx, cy + 1, P.gold, f)
                    g.paint(cx - 1, cy + 1, P.lip, f); g.paint(cx + 1, cy - 1, P.lip, f)
                }
            }
            smile(open: true)
        default:
            eyes()
            smile(open: false)
        }
    }

    // MARK: Hair

    private static func hair(_ id: String?, in g: inout VoxelGrid, head: Set<VoxelPoint>, hat: String?) {
        guard let id else { return }
        let h = VoxelPart.hair
        let shell = VoxelGrid.rounded(0...15, 9...22, -1...12, radius: 3.0).filter { !head.contains($0) }
        func cover(_ color: VoxelColor, sidesTo: Int, backTo: Int, fringe: (Int, Int) -> Bool) {
            for p in shell {
                let isFront = p.z >= 10
                let isSide = p.x <= 1 || p.x >= 14
                let isBack = p.z <= 4
                var keep = false
                if isFront { keep = fringe(p.x, p.y) || (isSide && p.y >= sidesTo && p.z <= 10) }
                else if isBack { keep = p.y >= backTo }
                else if isSide { keep = p.y >= sidesTo }
                else { keep = p.y >= 17 }
                if keep { g.set(p.x, p.y, p.z, color, h) }
            }
        }
        let jagged: (Int, Int) -> Bool = { x, y in y >= 19 || (y == 18 && x % 3 != 1) }
        switch id {
        case "hair.short":
            cover(P.brown, sidesTo: 15, backTo: 12, fringe: jagged)
        case "hair.bob":
            cover(P.inkSoft, sidesTo: 10, backTo: 9, fringe: { _, y in y >= 18 })
        case "hair.spiky":
            cover(P.orange, sidesTo: 16, backTo: 13, fringe: jagged)
            for x in [2, 5, 8, 11] {
                g.box(x...(x + 1), 22...23, 3...7, P.orange, h)
                g.box(x...(x + 1), 24...24, 4...5, P.orange, h)
            }
        case "hair.bun":
            cover(P.brown, sidesTo: 14, backTo: 11, fringe: { x, y in y >= 19 || (y == 18 && x >= 8) })
            g.fill(VoxelGrid.rounded(5...10, 22...26, 2...7, radius: 1.6), P.brown, h)
        case "hair.buzz":
            for p in head where p.y >= 19 && p.z <= 10 { g.set(p.x, p.y, p.z, P.inkSoft, h) }
        case "hair.curly":
            cover(P.auburn, sidesTo: 12, backTo: 10, fringe: jagged)
            for p in VoxelGrid.rounded(-1...16, 15...23, -2...13, radius: 3.4)
            where p.y >= 16 && (p.x + p.y + p.z) % 2 == 0 && !head.contains(p) && !g.has(p.x, p.y, p.z) && p.z <= 11 {
                g.set(p.x, p.y, p.z, P.auburn, h)
            }
        case "hair.long":
            cover(P.lilac, sidesTo: 9, backTo: 9, fringe: { x, y in y >= 18 && x != 7 && x != 8 || y >= 20 })
            g.box(1...14, 4...9, -1...0, P.lilac, h)
            for x in [0, 15] { g.box(x...x, 5...9, 1...8, P.lilac, h) }
        case "hair.mohawk":
            for p in VoxelGrid.rounded(6...9, 15...26, -1...11, radius: 1.5) where !head.contains(p) && p.y >= 19 {
                g.set(p.x, p.y, p.z, P.pink, h)
            }
        default:
            break
        }
        // Tall hair would poke through a hat that covers the top of the head.
        if let hat, ["hat.party", "hat.beanie", "hat.cap", "hat.wizard", "hat.crown"].contains(hat) {
            g.remove { p, c in c.part == h && p.y >= 22 }
        }
    }

    // MARK: Hats

    private static func hat(_ id: String?, in g: inout VoxelGrid, head: Set<VoxelPoint>) {
        guard let id else { return }
        let t = VoxelPart.hat
        func disc(y: Int, radius: Double, _ color: (Int, Int) -> VoxelColor?) {
            let span = Int(radius.rounded(.up)) + 1
            for x in (8 - span)...(8 + span) { for z in (6 - span)...(6 + span) {
                let dx = Double(x) + 0.5 - 8, dz = Double(z) + 0.5 - 6
                if dx * dx + dz * dz <= radius * radius, let c = color(x, z) { g.set(x, y, z, c, t) }
            } }
        }
        switch id {
        case "hat.party":
            for y in 21...29 {
                let r = 4.6 * Double(29 - y) / 8 + 0.8
                disc(y: y, radius: r) { _, _ in (y / 2) % 2 == 0 ? P.purple : P.gold }
            }
            g.box(7...8, 30...31, 5...6, P.cream, t)
        case "hat.beanie":
            for p in VoxelGrid.rounded(0...15, 15...24, -1...12, radius: 3.4) where p.y >= 18 && !head.contains(p) {
                g.set(p.x, p.y, p.z, p.y <= 19 ? P.tealDeep : P.teal, t)
            }
            g.fill(VoxelGrid.rounded(6...9, 25...27, 4...7, radius: 1.2), P.cream, t)
        case "hat.cap":
            for p in VoxelGrid.rounded(0...15, 15...24, -1...12, radius: 3.2) where p.y >= 20 && !head.contains(p) {
                g.set(p.x, p.y, p.z, P.inkSoft, t)
            }
            g.box(2...13, 20...20, 12...15, P.gold, t)
            g.box(3...12, 20...20, 16...16, P.lip, t)
            g.box(7...8, 25...25, 5...6, P.gold, t)
        case "hat.catears":
            for (x0, inner) in [(2, 3), (10, 11)] {
                g.box(x0...(x0 + 3), 21...22, 4...7, P.inkSoft, t)
                g.box((x0 + 0)...(x0 + 2), 23...23, 5...6, P.inkSoft, t)
                g.box((x0 + 1)...(x0 + 2), 24...24, 5...6, P.inkSoft, t)
                g.box(inner...(inner + 1), 22...23, 7...7, P.pink, t)
            }
            for x in 6...9 { g.set(x, 22, 5, P.inkSoft, t); g.set(x, 22, 6, P.inkSoft, t) }
        case "hat.headset":
            g.box(1...14, 23...23, 5...6, P.inkSoft, t)
            for x in [0, 15] { g.box(x...x, 21...22, 5...6, P.inkSoft, t) }
            for x in [-1, 16] { g.box(x...x, 18...20, 5...6, P.inkSoft, t) }
            g.box(-2...(-1), 12...17, 3...8, P.gold, t)
            g.box(16...17, 12...17, 3...8, P.gold, t)
            g.box(-2...(-2), 13...16, 4...7, P.lip, t)
            g.box(17...17, 13...16, 4...7, P.lip, t)
            g.set(-1, 12, 9, P.inkSoft, t); g.set(-1, 11, 10, P.inkSoft, t); g.set(0, 11, 11, P.inkSoft, t)
            g.set(1, 11, 12, P.inkSoft, t); g.set(2, 11, 12, P.gold, t)
        case "hat.halo":
            for x in 1...14 { for z in -1...12 {
                let dx = Double(x) + 0.5 - 8, dz = Double(z) + 0.5 - 6
                let d = (dx * dx + dz * dz).squareRoot()
                if d >= 3.8 && d <= 5.4 { g.set(x, 26, z, P.gold, t) }
            } }
        case "hat.wizard":
            disc(y: 21, radius: 9.6) { _, _ in P.purple }
            for y in 22...33 {
                let r = 5.6 * Double(33 - y) / 11 + 0.7
                disc(y: y, radius: r) { x, z in (x * 3 + y * 5 + z * 7) % 11 == 0 ? P.gold : P.purple }
            }
            disc(y: 22, radius: 6.4) { _, _ in P.gold }
            g.box(9...10, 34...34, 6...7, P.purple, t)
            g.box(10...10, 35...35, 7...7, P.gold, t)
        case "hat.crown":
            for y in 21...23 {
                for x in 0...15 { for z in -1...12 {
                    let dx = Double(x) + 0.5 - 8, dz = Double(z) + 0.5 - 6
                    let d = (dx * dx + dz * dz).squareRoot()
                    if d >= 4.6 && d <= 6.2 { g.set(x, y, z, y == 21 ? P.lip : P.gold, t) }
                } }
            }
            for x in 0...15 { for z in -1...12 {
                let dx = Double(x) + 0.5 - 8, dz = Double(z) + 0.5 - 6
                let d = (dx * dx + dz * dz).squareRoot()
                guard d >= 4.6 && d <= 6.2 else { continue }
                let angle = atan2(dz, dx)
                let step = Int(((angle + .pi) / (2 * .pi) * 8).rounded()) % 8
                let near = abs(angle + .pi - Double(step) * .pi / 4) < 0.28
                if near { g.set(x, 24, z, P.gold, t) }
                if near && step % 2 == 0 { g.set(x, 25, z, P.gold, t) }
            } }
            g.paint(7, 22, P.red, t); g.paint(8, 22, P.red, t)
            g.paint(3, 22, P.teal, t); g.paint(12, 22, P.teal, t)
        default:
            break
        }
    }

    // MARK: Gadgets

    private static func gadget(_ id: String?, in g: inout VoxelGrid) {
        guard let id else { return }
        let d = VoxelPart.gadget
        switch id {
        case "gadget.phone":
            g.box(1...3, 2...7, 7...7, P.inkSoft, d)
            g.box(2...2, 3...6, 7...7, P.teal, d)
            g.set(3, 3, 7, P.teal, d); g.set(3, 4, 7, P.teal, d); g.set(3, 5, 7, P.teal, d); g.set(3, 6, 7, P.teal, d)
        case "gadget.controller", "gadget.goldpad":
            let body = id == "gadget.goldpad" ? P.gold : P.inkSoft
            let accent = id == "gadget.goldpad" ? P.inkSoft : P.gold
            g.box(0...5, 3...4, 7...8, body, d)
            g.box(0...1, 2...2, 7...8, body, d); g.box(4...5, 2...2, 7...8, body, d)
            g.set(1, 4, 8, P.cream, d); g.set(1, 3, 8, P.cream, d)
            g.set(4, 4, 8, accent, d); g.set(5, 3, 8, id == "gadget.goldpad" ? P.red : P.teal, d)
        case "gadget.joystick":
            g.box(0...4, 2...3, 7...9, P.inkSoft, d)
            g.set(1, 3, 9, P.gold, d); g.set(3, 3, 9, P.teal, d)
            g.box(2...2, 4...5, 8...8, P.silver, d)
            g.fill(VoxelGrid.rounded(1...3, 6...8, 7...9, radius: 1.0), P.red, d)
        case "gadget.boba":
            g.box(1...3, 2...6, 7...9, P.tan, d)
            g.set(1, 2, 9, P.inkSoft, d); g.set(3, 3, 9, P.inkSoft, d); g.set(2, 2, 9, P.inkSoft, d)
            g.box(1...3, 7...7, 7...9, P.cream, d)
            g.box(2...2, 8...10, 8...8, P.pink, d)
        case "gadget.mic":
            g.box(2...3, 2...5, 7...8, P.inkSoft, d)
            g.fill(VoxelGrid.rounded(1...4, 6...9, 6...9, radius: 1.2), P.silver, d)
            g.box(1...4, 6...6, 6...9, P.gold, d)
        case "gadget.trophy":
            g.box(0...5, 1...1, 6...10, P.lip, d)
            g.box(2...3, 2...3, 7...9, P.gold, d)
            g.fill(VoxelGrid.rounded(0...5, 4...8, 5...11, radius: 1.4), P.gold, d)
            g.box(1...4, 8...8, 6...10, P.goldDeep, d)
            g.box(-1...(-1), 5...7, 8...8, P.gold, d); g.box(6...6, 5...7, 8...8, P.gold, d)
            g.paint(2, 6, P.lip, d); g.paint(3, 6, P.lip, d)
        default:
            break
        }
    }
}

extension VoxelGrid {
    /// The head and whatever sits on it, for small round spots.
    var headOnly: VoxelGrid {
        var grid = VoxelGrid()
        grid.cells = cells.filter { $0.key.y >= 9 && $0.value.part != .gadget && $0.value.part != .outfit }
        return grid
    }

    func below(_ y: Int) -> VoxelGrid {
        var grid = VoxelGrid()
        grid.cells = cells.filter { $0.key.y < y }
        return grid
    }

    /// The smallest box around every voxel.
    var bounds: (min: VoxelPoint, max: VoxelPoint) {
        var lo = VoxelPoint(x: .max, y: .max, z: .max), hi = VoxelPoint(x: .min, y: .min, z: .min)
        for p in cells.keys {
            lo.x = Swift.min(lo.x, p.x); lo.y = Swift.min(lo.y, p.y); lo.z = Swift.min(lo.z, p.z)
            hi.x = Swift.max(hi.x, p.x); hi.y = Swift.max(hi.y, p.y); hi.z = Swift.max(hi.z, p.z)
        }
        if cells.isEmpty { return (VoxelPoint(x: 0, y: 0, z: 0), VoxelPoint(x: 0, y: 0, z: 0)) }
        return (lo, hi)
    }

    /// What you see from the front: the colour of the frontmost voxel in each column.
    var front: [VoxelPoint: VoxelColor] {
        var best: [VoxelPoint: (z: Int, color: VoxelColor)] = [:]
        for (p, c) in cells {
            let key = VoxelPoint(x: p.x, y: p.y, z: 0)
            if let current = best[key], current.z >= p.z { continue }
            best[key] = (p.z, c.color)
        }
        return best.mapValues { $0.color }
    }
}
