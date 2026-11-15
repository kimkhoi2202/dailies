import SwiftUI

// The room behind your avatar and the decor you can place in it. Everything is drawn in code so it stays
// crisp at any size, and DecorArt.draw is shared so an item looks the same on its Shop card and in the room.

private enum RoomHue {
    static let ink = Color(hex: "151412")
    static let gold = Color(hex: "FFC531")
    static let goldDeep = Color(hex: "F5B301")
    static let lip = Color(hex: "C48A00")
    static let shine = Color(hex: "FFE9A6")
    static let cream = Color(hex: "F3F0E9")
    static let teal = Color(hex: "1FA89A")
    static let tealDeep = Color(hex: "178F83")
    static let purple = Color(hex: "7C5CFF")
    static let coral = Color(hex: "FF6B57")
    static let pink = Color(hex: "FF7AB6")
    static let night = Color(hex: "16130F")
    static let dusk = Color(hex: "2B2622")
    static let umber = Color(hex: "3A332C")
    static let wood = Color(hex: "8A5A3B")
    static let woodDark = Color(hex: "6B4A33")
    static let leaf = Color(hex: "4CB86A")
    static let leafDark = Color(hex: "2E8F55")
    static let clay = Color(hex: "E8714E")
    static let clayLight = Color(hex: "F08560")
    static let orange = Color(hex: "F29A3E")
    static let orangeDeep = Color(hex: "D9772A")
    static let silver = Color(hex: "D3D8E0")
    static let silverDeep = Color(hex: "9AA3AF")
    static let bronze = Color(hex: "D98A4E")
}

/// Draws flat cartoon shapes: a fill, one shade, one highlight and an ink outline.
private struct RoomPen {
    let c: GraphicsContext
    let lw: CGFloat

    func shape(_ p: Path, _ color: Color, shade: Double = 0.2, shine: Double = 0.26) {
        c.fill(p, with: .color(color))
        let b = p.boundingRect
        let k = max(lw * 1.4, min(b.width, b.height) * 0.14)
        var inner = c
        inner.clip(to: p)
        if shade > 0 {
            var s = Path(b.insetBy(dx: -k * 2, dy: -k * 2))
            s.addPath(p.offsetBy(dx: -k, dy: -k))
            inner.fill(s, with: .color(.black.opacity(shade)), style: FillStyle(eoFill: true))
        }
        if shine > 0 {
            var s = Path(b.insetBy(dx: -k * 2, dy: -k * 2))
            s.addPath(p.offsetBy(dx: k * 0.5, dy: k * 0.5))
            inner.fill(s, with: .color(.white.opacity(shine)), style: FillStyle(eoFill: true))
        }
        outline(p)
    }

    func outline(_ p: Path, _ width: CGFloat? = nil) {
        c.stroke(p, with: .color(RoomHue.ink), style: StrokeStyle(lineWidth: width ?? lw, lineCap: .round, lineJoin: .round))
    }

    func line(_ p: Path, _ color: Color, _ width: CGFloat) {
        c.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
    }

    /// A thick rounded stroke with an ink outline, for tails, handles and cords.
    func tube(_ p: Path, _ color: Color, _ width: CGFloat) {
        line(p, RoomHue.ink, width + lw * 2)
        line(p, color, width)
    }

    func glow(_ center: CGPoint, _ radius: CGFloat, _ color: Color, _ alpha: Double) {
        let r = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        c.fill(Path(ellipseIn: r), with: .radialGradient(Gradient(colors: [color.opacity(alpha), color.opacity(0)]),
                                                         center: center, startRadius: 0, endRadius: radius))
    }

    func dot(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ color: Color) {
        c.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(color))
    }
}

private func rr(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> Path {
    Path(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: r, style: .continuous)
}

private func oval(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> Path {
    Path(ellipseIn: CGRect(x: x, y: y, width: w, height: h))
}

private func poly(_ points: [(CGFloat, CGFloat)]) -> Path {
    var p = Path()
    p.addLines(points.map { CGPoint(x: $0.0, y: $0.1) })
    p.closeSubpath()
    return p
}

private func sparkle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) -> Path {
    var p = Path()
    p.move(to: CGPoint(x: cx, y: cy - r))
    p.addQuadCurve(to: CGPoint(x: cx + r, y: cy), control: CGPoint(x: cx, y: cy))
    p.addQuadCurve(to: CGPoint(x: cx, y: cy + r), control: CGPoint(x: cx, y: cy))
    p.addQuadCurve(to: CGPoint(x: cx - r, y: cy), control: CGPoint(x: cx, y: cy))
    p.addQuadCurve(to: CGPoint(x: cx, y: cy - r), control: CGPoint(x: cx, y: cy))
    p.closeSubpath()
    return p
}

private func star(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) -> Path {
    var p = Path()
    for i in 0..<10 {
        let a = CGFloat(i) * .pi / 5 - .pi / 2
        let d = i.isMultiple(of: 2) ? r : r * 0.45
        let pt = CGPoint(x: cx + cos(a) * d, y: cy + sin(a) * d)
        if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
    }
    p.closeSubpath()
    return p
}

// MARK: - Decor

/// One decor item alone, centred on a transparent background and fitted to its frame.
struct DecorArt: View {
    let id: String

    var body: some View {
        if DecorArt.animates(id) {
            TimelineView(.animation(minimumInterval: 1.0 / 15)) { timeline in
                canvas(timeline.date.timeIntervalSinceReferenceDate)
            }
        } else {
            canvas(0)
        }
    }

    private func canvas(_ time: Double) -> some View {
        Canvas { context, size in
            DecorArt.draw(id, in: &context, rect: CGRect(origin: .zero, size: size), time: time)
        }
    }

    /// Width over height of each item's drawing. Nil for an id that is not decor.
    static func aspect(_ id: String) -> CGFloat? {
        switch id {
        case "decor.plant": 0.8
        case "decor.lamp": 0.56
        case "decor.rug": 2.0
        case "decor.beanbag": 1.2
        case "decor.poster": 0.78
        case "decor.fridge": 0.7
        case "decor.lavalamp": 0.46
        case "decor.bookshelf": 0.8
        case "decor.neon": 1.4
        case "decor.arcade": 0.62
        case "decor.cat": 1.5
        case "decor.robot": 0.8
        case "decor.goldtrophy": 0.62
        default: nil
        }
    }

    /// Items that hang on the wall instead of standing on the floor.
    static func hangs(_ id: String) -> Bool { id == "decor.neon" || id == "decor.poster" }

    /// Items that move: the lava lamp's blobs and the robot's antenna light.
    static func animates(_ id: String) -> Bool { id == "decor.lavalamp" || id == "decor.robot" }

    /// Draws one item aspect-fitted and centred in `rect`. An unknown id draws nothing.
    static func draw(_ id: String, in context: inout GraphicsContext, rect: CGRect, time: Double = 0) {
        guard let a = aspect(id) else { return }
        let bw = 100 * a
        let s = min(rect.width / bw, rect.height / 100)
        guard s > 0 else { return }
        var c = context
        c.translateBy(x: rect.midX - bw * s / 2, y: rect.midY - 50 * s)
        c.scaleBy(x: s, y: s)
        let p = RoomPen(c: c, lw: max(1.7, 1.1 / s))
        switch id {
        case "decor.plant": plant(p)
        case "decor.lamp": lamp(p)
        case "decor.rug": rug(p, CGRect(x: 6, y: 18, width: 188, height: 66), striped: true)
        case "decor.beanbag": beanbag(p)
        case "decor.poster": poster(p)
        case "decor.fridge": fridge(p)
        case "decor.lavalamp": lavalamp(p, time)
        case "decor.bookshelf": bookshelf(p)
        case "decor.neon": neon(p)
        case "decor.arcade": arcade(p)
        case "decor.cat": cat(p)
        case "decor.robot": robot(p, time)
        case "decor.goldtrophy": goldTrophy(p)
        default: break
        }
    }

    private static func plant(_ p: RoomPen) {
        let leaves: [(CGFloat, CGFloat, CGFloat, Color)] = [
            (-62, 38, 16, RoomHue.leafDark), (62, 38, 16, RoomHue.leafDark),
            (-30, 50, 19, RoomHue.leaf), (30, 50, 19, RoomHue.leaf), (0, 56, 20, RoomHue.leaf),
        ]
        for (deg, len, wid, col) in leaves {
            let a = deg * .pi / 180
            let shape = oval(-wid / 2, -len, wid, len).applying(CGAffineTransform(translationX: 40, y: 62).rotated(by: a))
            p.shape(shape, col, shine: 0.22)
            var vein = Path()
            vein.move(to: CGPoint(x: 40 + sin(a) * len * 0.2, y: 62 - cos(a) * len * 0.2))
            vein.addLine(to: CGPoint(x: 40 + sin(a) * len * 0.75, y: 62 - cos(a) * len * 0.75))
            p.line(vein, RoomHue.ink.opacity(0.45), p.lw * 0.7)
        }
        p.shape(poly([(22, 64), (58, 64), (53, 97), (27, 97)]), RoomHue.clay)
        p.shape(rr(17, 57, 46, 11, 4), RoomHue.clayLight)
        p.dot(33, 78, 2, RoomHue.ink)
        p.dot(47, 78, 2, RoomHue.ink)
        var smile = Path()
        smile.move(to: CGPoint(x: 37, y: 83))
        smile.addQuadCurve(to: CGPoint(x: 43, y: 83), control: CGPoint(x: 40, y: 87))
        p.line(smile, RoomHue.ink, p.lw * 0.8)
        p.dot(29, 83, 2.6, RoomHue.pink.opacity(0.7))
        p.dot(51, 83, 2.6, RoomHue.pink.opacity(0.7))
    }

    private static func lamp(_ p: RoomPen) {
        p.glow(CGPoint(x: 28, y: 34), 34, RoomHue.gold, 0.5)
        p.shape(oval(10, 86, 36, 11), RoomHue.goldDeep)
        p.shape(rr(25.5, 34, 5, 56, 2.5), RoomHue.lip, shine: 0.3)
        p.shape(poly([(17, 6), (39, 6), (50, 36), (6, 36)]), RoomHue.cream)
        p.c.fill(oval(9, 32, 38, 7), with: .color(RoomHue.shine))
        p.outline(oval(9, 32, 38, 7), p.lw * 0.7)
        var chain = Path()
        chain.move(to: CGPoint(x: 38, y: 36))
        chain.addLine(to: CGPoint(x: 38, y: 48))
        p.line(chain, RoomHue.ink, p.lw * 0.7)
        p.shape(oval(35.5, 47, 5, 5), RoomHue.gold, shade: 0, shine: 0)
    }

    /// A round rug seen at an angle, filling r. The room draws its own rug with it too.
    fileprivate static func rug(_ p: RoomPen, _ r: CGRect, striped: Bool) {
        p.c.fill(Path(ellipseIn: r.offsetBy(dx: 0, dy: r.height * 0.07)), with: .color(.black.opacity(0.3)))
        if striped {
            var fringe = Path()
            for i in 0..<5 {
                let y = r.midY + (CGFloat(i) - 2) * r.height * 0.1
                fringe.move(to: CGPoint(x: r.minX + r.width * 0.01, y: y))
                fringe.addLine(to: CGPoint(x: r.minX - r.width * 0.035, y: y))
                fringe.move(to: CGPoint(x: r.maxX - r.width * 0.01, y: y))
                fringe.addLine(to: CGPoint(x: r.maxX + r.width * 0.035, y: y))
            }
            p.line(fringe, RoomHue.cream, p.lw * 0.9)
        }
        let rings: [Color] = striped
            ? [RoomHue.coral, RoomHue.cream, RoomHue.gold, RoomHue.cream, RoomHue.pink]
            : [RoomHue.teal, RoomHue.tealDeep, RoomHue.cream, RoomHue.teal, RoomHue.tealDeep]
        for (i, color) in rings.enumerated() {
            let f = CGFloat(i) * 0.17
            let ring = Path(ellipseIn: r.insetBy(dx: r.width * f / 2, dy: r.height * f / 2))
            p.c.fill(ring, with: .color(color))
            if i > 0 { p.outline(ring, p.lw * 0.5) }
        }
        let whole = Path(ellipseIn: r)
        var inner = p.c
        inner.clip(to: whole)
        var shade = Path(r.insetBy(dx: -20, dy: -20))
        shade.addPath(whole.offsetBy(dx: 0, dy: -r.height * 0.1))
        inner.fill(shade, with: .color(.black.opacity(0.18)), style: FillStyle(eoFill: true))
        p.outline(whole)
    }

    private static func beanbag(_ p: RoomPen) {
        var bag = Path()
        bag.move(to: CGPoint(x: 14, y: 93))
        bag.addCurve(to: CGPoint(x: 20, y: 42), control1: CGPoint(x: 2, y: 82), control2: CGPoint(x: 4, y: 54))
        bag.addCurve(to: CGPoint(x: 70, y: 12), control1: CGPoint(x: 32, y: 26), control2: CGPoint(x: 50, y: 8))
        bag.addCurve(to: CGPoint(x: 112, y: 62), control1: CGPoint(x: 94, y: 16), control2: CGPoint(x: 117, y: 38))
        bag.addCurve(to: CGPoint(x: 102, y: 94), control1: CGPoint(x: 110, y: 80), control2: CGPoint(x: 114, y: 90))
        bag.addQuadCurve(to: CGPoint(x: 14, y: 93), control: CGPoint(x: 58, y: 101))
        bag.closeSubpath()
        p.c.fill(oval(10, 88, 100, 10), with: .color(.black.opacity(0.25)))
        p.shape(bag, RoomHue.purple, shade: 0.24, shine: 0.24)
        p.c.fill(oval(38, 30, 46, 18), with: .color(Color(hex: "5F42DA")))
        var seam = Path()
        seam.move(to: CGPoint(x: 22, y: 60))
        seam.addQuadCurve(to: CGPoint(x: 104, y: 70), control: CGPoint(x: 62, y: 84))
        p.line(seam, RoomHue.ink.opacity(0.35), p.lw * 0.8)
    }

    private static func poster(_ p: RoomPen) {
        p.shape(rr(4, 3, 70, 94, 5), RoomHue.woodDark, shade: 0.25)
        p.c.fill(rr(10, 9, 58, 82, 3), with: .linearGradient(Gradient(colors: [RoomHue.teal, RoomHue.tealDeep]),
                                                               startPoint: CGPoint(x: 0, y: 9), endPoint: CGPoint(x: 0, y: 91)))
        p.outline(rr(10, 9, 58, 82, 3), p.lw * 0.8)
        p.c.fill(sparkle(20, 20, 4), with: .color(RoomHue.shine))
        p.c.fill(sparkle(58, 30, 3), with: .color(RoomHue.shine))
        p.shape(rr(15, 80, 48, 6, 2), RoomHue.umber, shine: 0)
        let blocks: [(CGFloat, CGFloat, CGFloat, Color)] = [
            (19, 68, 40, RoomHue.coral), (23, 56, 34, RoomHue.gold), (18, 44, 32, RoomHue.purple), (28, 32, 28, RoomHue.pink),
        ]
        for (x, y, w, col) in blocks { p.shape(rr(x, y, w, 12, 2.5), col) }
        let top = rr(-13, -6, 26, 12, 2.5).applying(CGAffineTransform(translationX: 40, y: 24).rotated(by: 0.22))
        p.shape(top, RoomHue.cream)
    }

    private static func fridge(_ p: RoomPen) {
        p.shape(rr(14, 90, 9, 7, 2), RoomHue.umber, shine: 0)
        p.shape(rr(47, 90, 9, 7, 2), RoomHue.umber, shine: 0)
        p.shape(rr(8, 5, 54, 88, 10), RoomHue.cream, shade: 0.16)
        var split = Path()
        split.move(to: CGPoint(x: 8, y: 35))
        split.addLine(to: CGPoint(x: 62, y: 35))
        p.line(split, RoomHue.ink, p.lw)
        p.shape(rr(51, 16, 5, 13, 2.5), RoomHue.silverDeep, shine: 0.4)
        p.shape(rr(51, 42, 5, 22, 2.5), RoomHue.silverDeep, shine: 0.4)
        let note = rr(-7, -7, 14, 14, 1.5).applying(CGAffineTransform(translationX: 25, y: 20).rotated(by: -0.15))
        p.shape(note, RoomHue.gold, shade: 0.12, shine: 0)
        p.shape(oval(16, 48, 10, 10), RoomHue.pink)
        p.shape(star(33, 66, 6.5), RoomHue.gold, shine: 0)
        p.shape(oval(18, 72, 9, 9), RoomHue.teal)
    }

    private static func lavalamp(_ p: RoomPen, _ t: Double) {
        p.glow(CGPoint(x: 23, y: 48), 36, RoomHue.pink, 0.45)
        let glass = poly([(15, 20), (31, 20), (40, 72), (6, 72)])
        p.c.fill(glass, with: .linearGradient(Gradient(colors: [RoomHue.purple, Color(hex: "B04FD8")]),
                                              startPoint: CGPoint(x: 0, y: 20), endPoint: CGPoint(x: 0, y: 72)))
        var inner = p.c
        inner.clip(to: glass)
        let rise = CGFloat(sin(t * 0.9)) * 6
        let fall = CGFloat(cos(t * 0.7)) * 5
        inner.fill(oval(13, 52 + rise, 16, 18), with: .color(RoomHue.pink))
        inner.fill(oval(22, 33 + fall, 10, 12), with: .color(RoomHue.pink))
        inner.fill(oval(10, 66, 26, 12), with: .color(RoomHue.pink))
        inner.fill(rr(14, 24, 3, 40, 1.5), with: .color(.white.opacity(0.3)))
        p.outline(glass)
        p.shape(poly([(17, 7), (29, 7), (31, 20), (15, 20)]), RoomHue.silver)
        p.shape(poly([(6, 72), (40, 72), (44, 97), (2, 97)]), RoomHue.silver)
    }

    private static func bookshelf(_ p: RoomPen) {
        p.shape(rr(6, 4, 68, 94, 4), RoomHue.wood, shade: 0.22)
        let colors = [RoomHue.coral, RoomHue.teal, RoomHue.gold, RoomHue.purple, RoomHue.pink, RoomHue.cream]
        let widths: [CGFloat] = [7, 6, 8, 6, 7, 7]
        let heights: [CGFloat] = [20, 17, 22, 18, 21, 16]
        for row in 0..<3 {
            let y = 10 + CGFloat(row) * 29
            p.c.fill(rr(11, y, 58, 24, 2), with: .color(RoomHue.night))
            p.outline(rr(11, y, 58, 24, 2), p.lw * 0.7)
            if row == 1 {
                p.shape(rr(14, y + 17, 30, 7, 1.5), RoomHue.purple, shine: 0)
                p.shape(rr(16, y + 10, 26, 7, 1.5), RoomHue.coral, shine: 0)
                p.shape(oval(53, y + 3, 8, 13), RoomHue.leaf)
                p.shape(rr(51, y + 14, 12, 10, 2), RoomHue.clay, shine: 0)
                continue
            }
            var x: CGFloat = 13
            for i in 0..<6 {
                let bw = widths[(i + row) % 6]
                let bh = heights[(i + row * 2) % 6]
                let color = colors[(i + row) % 6]
                if row == 2 && i == 5 {
                    let leaning = rr(-bw / 2, -bh, bw, bh, 1.5).applying(CGAffineTransform(translationX: x + bw / 2 + 4, y: y + 24).rotated(by: 0.3))
                    p.shape(leaning, color, shine: 0)
                } else {
                    p.shape(rr(x, y + 24 - bh, bw, bh, 1.5), color, shine: 0)
                }
                x += bw + 1.5
            }
        }
    }

    private static func neon(_ p: RoomPen) {
        var wires = Path()
        wires.move(to: CGPoint(x: 34, y: 2))
        wires.addLine(to: CGPoint(x: 44, y: 18))
        wires.move(to: CGPoint(x: 106, y: 2))
        wires.addLine(to: CGPoint(x: 96, y: 18))
        p.line(wires, RoomHue.ink, p.lw)
        p.glow(CGPoint(x: 70, y: 54), 76, RoomHue.gold, 0.35)
        p.shape(rr(8, 18, 124, 72, 18), RoomHue.night, shade: 0, shine: 0.08)
        p.c.stroke(rr(13, 23, 114, 62, 14), with: .color(RoomHue.gold.opacity(0.35)), lineWidth: 1.2)
        let label = Text("GG").font(DL.display(62))
        var blur = p.c
        blur.addFilter(.blur(radius: 6))
        blur.draw(label.foregroundStyle(RoomHue.gold), at: CGPoint(x: 70, y: 55))
        p.c.draw(label.foregroundStyle(RoomHue.gold), at: CGPoint(x: 70, y: 55))
        var core = p.c
        core.opacity = 0.7
        core.draw(label.foregroundStyle(RoomHue.shine), at: CGPoint(x: 70, y: 54))
    }

    private static func arcade(_ p: RoomPen) {
        p.shape(rr(8, 92, 11, 6, 2), RoomHue.umber, shine: 0)
        p.shape(rr(43, 92, 11, 6, 2), RoomHue.umber, shine: 0)
        p.shape(rr(6, 4, 50, 90, 7), RoomHue.purple, shade: 0.24)
        p.glow(CGPoint(x: 31, y: 16), 26, RoomHue.gold, 0.35)
        p.shape(rr(10, 9, 42, 13, 4), RoomHue.gold, shine: 0.3)
        p.c.fill(star(20, 15.5, 3.4), with: .color(RoomHue.coral))
        p.c.fill(star(31, 15.5, 3.4), with: .color(RoomHue.pink))
        p.c.fill(star(42, 15.5, 3.4), with: .color(RoomHue.teal))
        p.shape(rr(10, 26, 42, 31, 5), RoomHue.night, shade: 0, shine: 0)
        p.glow(CGPoint(x: 31, y: 41), 30, RoomHue.teal, 0.4)
        p.c.fill(rr(14, 30, 34, 23, 3), with: .linearGradient(Gradient(colors: [Color(hex: "39D6C4"), RoomHue.tealDeep]),
                                                                startPoint: CGPoint(x: 0, y: 30), endPoint: CGPoint(x: 0, y: 53)))
        let invaders: [(CGFloat, CGFloat, Color)] = [(19, 35, RoomHue.gold), (28, 33, RoomHue.pink), (37, 35, RoomHue.gold)]
        for (x, y, col) in invaders {
            p.c.fill(rr(x, y, 6, 4.5, 1), with: .color(col))
            p.c.fill(rr(x + 1, y + 4.5, 1.4, 1.6, 0.3), with: .color(col))
            p.c.fill(rr(x + 3.6, y + 4.5, 1.4, 1.6, 0.3), with: .color(col))
        }
        p.c.fill(rr(28, 47, 6, 3, 1), with: .color(RoomHue.cream))
        p.c.fill(rr(14, 30, 34, 7, 3), with: .color(.white.opacity(0.18)))
        p.shape(poly([(4, 61), (58, 61), (60, 71), (2, 71)]), RoomHue.umber, shine: 0.15)
        var stick = Path()
        stick.move(to: CGPoint(x: 18, y: 64))
        stick.addLine(to: CGPoint(x: 18, y: 55))
        p.line(stick, RoomHue.ink, p.lw * 1.3)
        p.shape(oval(14, 50, 8, 8), RoomHue.coral)
        p.shape(oval(30, 62, 8, 5), RoomHue.pink, shine: 0.35)
        p.shape(oval(41, 62, 8, 5), RoomHue.gold, shine: 0.35)
        p.shape(rr(22, 77, 18, 12, 2), RoomHue.night, shade: 0, shine: 0)
        p.c.fill(rr(26, 80, 2.4, 6, 1), with: .color(RoomHue.gold))
        p.c.fill(rr(33.6, 80, 2.4, 6, 1), with: .color(RoomHue.gold))
    }

    private static func cat(_ p: RoomPen) {
        p.c.fill(oval(18, 88, 124, 10), with: .color(.black.opacity(0.25)))
        p.shape(rr(36, 48, 94, 46, 23), RoomHue.orange)
        var stripes = Path()
        for x in [70, 84, 98] as [CGFloat] {
            stripes.move(to: CGPoint(x: x, y: 49))
            stripes.addLine(to: CGPoint(x: x + 4, y: 60))
        }
        p.line(stripes, RoomHue.orangeDeep, 3.2)
        var tail = Path()
        tail.move(to: CGPoint(x: 124, y: 76))
        tail.addCurve(to: CGPoint(x: 114, y: 95), control1: CGPoint(x: 150, y: 72), control2: CGPoint(x: 148, y: 98))
        tail.addQuadCurve(to: CGPoint(x: 88, y: 93), control: CGPoint(x: 100, y: 96))
        p.tube(tail, RoomHue.orange, 10)
        p.dot(88, 93, 5, RoomHue.orangeDeep)
        p.shape(poly([(15, 50), (17, 21), (36, 36)]), RoomHue.orange, shine: 0)
        p.shape(poly([(41, 36), (58, 21), (60, 50)]), RoomHue.orange, shine: 0)
        p.c.fill(poly([(20, 43), (21, 29), (30, 37)]), with: .color(RoomHue.pink))
        p.c.fill(poly([(46, 37), (55, 29), (55, 43)]), with: .color(RoomHue.pink))
        p.shape(oval(9, 32, 56, 50), RoomHue.orange)
        p.c.fill(oval(22, 60, 30, 18), with: .color(Color(hex: "FFD9A8")))
        var face = Path()
        face.move(to: CGPoint(x: 21, y: 55))
        face.addQuadCurve(to: CGPoint(x: 30, y: 55), control: CGPoint(x: 25.5, y: 60))
        face.move(to: CGPoint(x: 44, y: 55))
        face.addQuadCurve(to: CGPoint(x: 53, y: 55), control: CGPoint(x: 48.5, y: 60))
        face.move(to: CGPoint(x: 33, y: 68))
        face.addQuadCurve(to: CGPoint(x: 37, y: 68), control: CGPoint(x: 35, y: 71))
        face.addQuadCurve(to: CGPoint(x: 41, y: 68), control: CGPoint(x: 39, y: 71))
        p.line(face, RoomHue.ink, p.lw)
        p.c.fill(poly([(34.5, 63), (39.5, 63), (37, 66.5)]), with: .color(RoomHue.pink))
        p.dot(17, 65, 3.5, RoomHue.pink.opacity(0.6))
        p.dot(57, 65, 3.5, RoomHue.pink.opacity(0.6))
        var whiskers = Path()
        whiskers.move(to: CGPoint(x: 13, y: 66))
        whiskers.addLine(to: CGPoint(x: 2, y: 64))
        whiskers.move(to: CGPoint(x: 13, y: 70))
        whiskers.addLine(to: CGPoint(x: 3, y: 72))
        whiskers.move(to: CGPoint(x: 61, y: 66))
        whiskers.addLine(to: CGPoint(x: 72, y: 64))
        p.line(whiskers, RoomHue.ink.opacity(0.7), p.lw * 0.6)
        p.shape(oval(48, 84, 17, 11), Color(hex: "FFB866"), shade: 0.12)
        p.shape(oval(64, 85, 17, 10), Color(hex: "FFB866"), shade: 0.12)
    }

    private static func robot(_ p: RoomPen, _ t: Double) {
        let on = Int(t * 1.5) % 2 == 0
        var mast = Path()
        mast.move(to: CGPoint(x: 40, y: 21))
        mast.addLine(to: CGPoint(x: 40, y: 10))
        p.line(mast, RoomHue.ink, p.lw * 1.4)
        if on { p.glow(CGPoint(x: 40, y: 7), 16, RoomHue.coral, 0.7) }
        p.shape(oval(35, 2, 10, 10), on ? RoomHue.coral : Color(hex: "8A3A30"), shine: 0.35)
        p.shape(rr(8, 31, 8, 14, 3), RoomHue.teal, shine: 0)
        p.shape(rr(64, 31, 8, 14, 3), RoomHue.teal, shine: 0)
        p.shape(rr(14, 20, 52, 36, 13), RoomHue.silver, shade: 0.18)
        p.shape(rr(21, 27, 38, 22, 8), RoomHue.night, shade: 0, shine: 0)
        p.glow(CGPoint(x: 40, y: 38), 18, RoomHue.teal, 0.35)
        p.c.fill(rr(28, 32, 7, 10, 3.5), with: .color(Color(hex: "5FF2DF")))
        p.c.fill(rr(45, 32, 7, 10, 3.5), with: .color(Color(hex: "5FF2DF")))
        var mouth = Path()
        mouth.move(to: CGPoint(x: 36, y: 44.5))
        mouth.addQuadCurve(to: CGPoint(x: 44, y: 44.5), control: CGPoint(x: 40, y: 47.5))
        p.line(mouth, Color(hex: "5FF2DF"), p.lw * 0.8)
        p.dot(26, 45, 2.2, RoomHue.pink.opacity(0.8))
        p.dot(54, 45, 2.2, RoomHue.pink.opacity(0.8))
        p.shape(rr(10, 62, 10, 19, 5), RoomHue.silver)
        p.shape(rr(60, 62, 10, 19, 5), RoomHue.silver)
        p.shape(rr(34, 54, 12, 6, 2), RoomHue.umber, shine: 0)
        p.shape(rr(20, 58, 40, 29, 10), RoomHue.teal)
        p.shape(oval(34, 64, 12, 12), RoomHue.gold, shine: 0.35)
        p.dot(27, 78, 2, RoomHue.pink)
        p.dot(53, 78, 2, RoomHue.purple)
        p.shape(rr(22, 86, 15, 10, 4), RoomHue.umber, shine: 0.15)
        p.shape(rr(43, 86, 15, 10, 4), RoomHue.umber, shine: 0.15)
    }

    private static func goldTrophy(_ p: RoomPen) {
        p.glow(CGPoint(x: 31, y: 34), 40, RoomHue.gold, 0.32)
        p.shape(rr(5, 85, 52, 13, 3), RoomHue.woodDark)
        p.shape(rr(21, 88, 20, 7, 1.5), RoomHue.gold, shade: 0, shine: 0.3)
        p.shape(rr(12, 74, 38, 12, 3), RoomHue.wood)
        p.tube(oval(3, 16, 20, 26), RoomHue.goldDeep, 4.5)
        p.tube(oval(39, 16, 20, 26), RoomHue.goldDeep, 4.5)
        p.shape(poly([(26, 58), (36, 58), (41, 74), (21, 74)]), RoomHue.gold)
        p.shape(oval(22, 56, 18, 7), RoomHue.lip, shine: 0.3)
        var bowl = Path()
        bowl.move(to: CGPoint(x: 9, y: 10))
        bowl.addLine(to: CGPoint(x: 53, y: 10))
        bowl.addCurve(to: CGPoint(x: 31, y: 59), control1: CGPoint(x: 53, y: 40), control2: CGPoint(x: 44, y: 58))
        bowl.addCurve(to: CGPoint(x: 9, y: 10), control1: CGPoint(x: 18, y: 58), control2: CGPoint(x: 9, y: 40))
        bowl.closeSubpath()
        p.shape(bowl, RoomHue.gold, shade: 0.22, shine: 0.32)
        p.shape(oval(8, 6, 46, 9), RoomHue.lip, shade: 0, shine: 0.2)
        p.shape(star(31, 31, 8.5), RoomHue.shine, shade: 0, shine: 0)
        p.c.fill(sparkle(6, 6, 4.5), with: .color(RoomHue.shine))
        p.c.fill(sparkle(56, 52, 3.5), with: .color(RoomHue.shine))
    }
}

// MARK: - Room

private enum RoomSpot: Hashable {
    case floorLeft, floorRight, frontLeft, frontRight, wallLeft, wallRight, rug
}

/// The room behind the avatar on the Profile and the Shop stage: wallpaper, a night window, a DEGEN poster,
/// a trophy shelf, a plank floor with a rug, and the decor you placed. The middle of the floor stays clear.
struct AvatarRoom: View {
    /// How far down the room the floor starts, 0 to 1.
    var floorAt: CGFloat = 0.7
    /// Placed decor ids, drawn in order at fixed spots.
    var decor: [String] = []
    /// Game ids of earned trophies, one cup each on the shelf.
    var trophies: [String] = []
    /// The wall colour the player picked, or nil for the default.
    var wall: Color? = nil

    var body: some View {
        if decor.contains(where: DecorArt.animates) {
            TimelineView(.animation(minimumInterval: 1.0 / 15)) { timeline in
                room(timeline.date.timeIntervalSinceReferenceDate)
            }
        } else {
            room(0)
        }
    }

    private func room(_ time: Double) -> some View {
        Canvas { context, size in paint(&context, size, time) }
            .clipped()
    }

    /// Floor items take the two floor spots first, then the front corners. Wall items hang on the side whose
    /// floor spot is free when they can, so nothing overlaps.
    private func layout() -> [(String, RoomSpot)] {
        var used = Set<RoomSpot>()
        var out: [(String, RoomSpot)] = []
        let ids = Array(decor.filter { DecorArt.aspect($0) != nil }.prefix(AvatarCatalog.roomSpots))
        func place(_ id: String, _ options: [RoomSpot]) {
            guard let spot = options.first(where: { !used.contains($0) }) else { return }
            used.insert(spot)
            out.append((id, spot))
        }
        for id in ids where !DecorArt.hangs(id) {
            place(id, id == "decor.rug" ? [.rug] : [.floorLeft, .floorRight, .frontLeft, .frontRight])
        }
        for id in ids where DecorArt.hangs(id) {
            let rightFirst = used.contains(.floorLeft) && !used.contains(.floorRight)
            place(id, rightFirst ? [.wallRight, .wallLeft] : [.wallLeft, .wallRight])
        }
        return out
    }

    private func paint(_ ctx: inout GraphicsContext, _ size: CGSize, _ time: Double) {
        let w = size.width, h = size.height
        guard w > 0, h > 0 else { return }
        let fy = h * floorAt, fd = h - fy
        let u = min(w, h) / 100
        let p = RoomPen(c: ctx, lw: max(1.2, u * 0.6))
        let placed = layout()
        let spots = Set(placed.map { $0.1 })

        // the back wall, warm at the bottom, with a soft diamond wallpaper
        ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: fy)),
                 with: .linearGradient(Gradient(colors: [Color(hex: "1E1A16"), RoomHue.dusk, RoomHue.umber]),
                                       startPoint: .zero, endPoint: CGPoint(x: 0, y: fy)))
        if let wall {
            ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: fy)), with: .color(wall))
            ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: fy)),
                     with: .linearGradient(Gradient(colors: [.black.opacity(0.45), .black.opacity(0.05)]),
                                           startPoint: .zero, endPoint: CGPoint(x: 0, y: fy)))
        }
        let step = max(18, w / 15)
        var paper = Path()
        var dots = Path()
        var row = 0
        var y = step * 0.5
        while y < fy {
            var x = row.isMultiple(of: 2) ? step * 0.5 : step
            while x < w + step {
                let d = step * 0.13
                paper.addLines([CGPoint(x: x, y: y - d), CGPoint(x: x + d, y: y), CGPoint(x: x, y: y + d), CGPoint(x: x - d, y: y)])
                paper.closeSubpath()
                dots.addEllipse(in: CGRect(x: x + step * 0.5 - 1.2, y: y - 1.2, width: 2.4, height: 2.4))
                x += step
            }
            y += step * 0.5
            row += 1
        }
        ctx.fill(paper, with: .color(RoomHue.cream.opacity(0.05)))
        ctx.fill(dots, with: .color(RoomHue.gold.opacity(0.06)))

        // warm lamp light from the shelf, spilling down the wall
        p.glow(CGPoint(x: w * 0.5, y: fy * 0.3), max(w, h) * 0.62, RoomHue.gold, 0.2)

        // the window, top left, with a night sky
        let ww = w * 0.23, wh = min(fy * 0.34, ww * 1.15)
        let win = CGRect(x: w * 0.05, y: fy * 0.09, width: ww, height: wh)
        let ft = max(3, w * 0.014)
        p.shape(Path(roundedRect: win.insetBy(dx: -ft, dy: -ft), cornerRadius: ft * 2), RoomHue.woodDark, shade: 0.25, shine: 0.15)
        let pane = Path(roundedRect: win, cornerRadius: ft)
        ctx.fill(pane, with: .linearGradient(Gradient(colors: [Color(hex: "141B3D"), Color(hex: "3B2C6E")]),
                                             startPoint: CGPoint(x: 0, y: win.minY), endPoint: CGPoint(x: 0, y: win.maxY)))
        var sky = ctx
        sky.clip(to: pane)
        let moonR = ww * 0.13
        let moonC = CGPoint(x: win.minX + ww * 0.7, y: win.minY + wh * 0.28)
        p.glow(moonC, moonR * 3, RoomHue.cream, 0.25)
        let moon = Path(ellipseIn: CGRect(x: moonC.x - moonR, y: moonC.y - moonR, width: moonR * 2, height: moonR * 2))
        var moonCut = moon
        moonCut.addPath(moon.offsetBy(dx: moonR * 0.7, dy: -moonR * 0.4))
        var moonCtx = sky
        moonCtx.clip(to: moon)
        moonCtx.fill(moonCut, with: .color(RoomHue.cream), style: FillStyle(eoFill: true))
        let stars: [(CGFloat, CGFloat, CGFloat)] = [(0.2, 0.2, 0.06), (0.42, 0.55, 0.045), (0.82, 0.68, 0.05), (0.15, 0.72, 0.04), (0.5, 0.18, 0.035)]
        for (fx, fyy, r) in stars {
            sky.fill(sparkle(win.minX + ww * fx, win.minY + wh * fyy, ww * r), with: .color(RoomHue.gold))
        }
        var hill = Path()
        hill.move(to: CGPoint(x: win.minX, y: win.maxY))
        hill.addQuadCurve(to: CGPoint(x: win.maxX, y: win.maxY - wh * 0.08), control: CGPoint(x: win.midX, y: win.maxY - wh * 0.34))
        hill.addLine(to: CGPoint(x: win.maxX, y: win.maxY))
        sky.fill(hill, with: .color(Color(hex: "0E1430")))
        sky.fill(poly([(win.minX + ww * 0.15, win.minY), (win.minX + ww * 0.32, win.minY), (win.minX, win.minY + wh * 0.55), (win.minX, win.minY + wh * 0.3)]),
                 with: .color(.white.opacity(0.06)))
        ctx.fill(Path(CGRect(x: win.midX - ft / 2, y: win.minY, width: ft, height: wh)), with: .color(RoomHue.woodDark))
        ctx.fill(Path(CGRect(x: win.minX, y: win.midY - ft / 2, width: ww, height: ft)), with: .color(RoomHue.woodDark))
        p.outline(pane, p.lw * 0.8)
        p.shape(Path(roundedRect: CGRect(x: win.minX - ft * 2.2, y: win.maxY + ft * 0.6, width: ww + ft * 4.4, height: ft * 1.8), cornerRadius: ft * 0.6),
                RoomHue.wood, shine: 0.2)

        // the DEGEN poster, top right, with a gold key
        let pw = w * 0.19, ph = min(pw * 1.32, fy * 0.4)
        let frame = CGRect(x: w * 0.75, y: fy * 0.08, width: pw, height: ph)
        p.glow(CGPoint(x: frame.midX, y: frame.midY), pw * 0.9, RoomHue.gold, 0.14)
        p.shape(Path(roundedRect: frame, cornerRadius: pw * 0.06), RoomHue.gold, shade: 0.24, shine: 0.3)
        let card = frame.insetBy(dx: pw * 0.09, dy: pw * 0.09)
        ctx.fill(Path(roundedRect: card, cornerRadius: pw * 0.03), with: .color(RoomHue.night))
        p.outline(Path(roundedRect: card, cornerRadius: pw * 0.03), p.lw * 0.7)
        p.glow(CGPoint(x: card.midX, y: card.minY + card.height * 0.32), card.width * 0.6, RoomHue.gold, 0.22)
        let kr = min(card.width * 0.15, card.height * 0.11)
        let kc = CGPoint(x: card.midX, y: card.minY + card.height * 0.08 + kr * 1.2)
        let keyParts = [
            Path(ellipseIn: CGRect(x: kc.x - kr, y: kc.y - kr, width: kr * 2, height: kr * 2)),
            Path(roundedRect: CGRect(x: kc.x - kr * 0.22, y: kc.y + kr * 0.8, width: kr * 0.44, height: kr * 2), cornerRadius: kr * 0.1),
            Path(CGRect(x: kc.x + kr * 0.1, y: kc.y + kr * 1.9, width: kr * 0.62, height: kr * 0.32)),
            Path(CGRect(x: kc.x + kr * 0.1, y: kc.y + kr * 2.4, width: kr * 0.46, height: kr * 0.32)),
        ]
        for part in keyParts { p.outline(part, p.lw * 2) }
        for part in keyParts { ctx.fill(part, with: .color(RoomHue.gold)) }
        let hole = Path(ellipseIn: CGRect(x: kc.x - kr * 0.45, y: kc.y - kr * 0.45, width: kr * 0.9, height: kr * 0.9))
        ctx.fill(hole, with: .color(RoomHue.night))
        p.outline(hole, p.lw * 0.8)
        ctx.fill(Path(ellipseIn: CGRect(x: kc.x - kr * 0.75, y: kc.y - kr * 0.8, width: kr * 0.4, height: kr * 0.3)), with: .color(.white.opacity(0.45)))
        ctx.draw(Text("DEGEN").font(DL.display(card.width * 0.27)).foregroundStyle(RoomHue.gold),
                 at: CGPoint(x: card.midX, y: card.maxY - card.height * 0.17))
        ctx.draw(Text("GG").font(DL.display(card.width * 0.14)).foregroundStyle(RoomHue.pink),
                 at: CGPoint(x: card.maxX - card.width * 0.14, y: card.minY + card.width * 0.13))

        // the trophy shelf, high in the middle, with a cup per trophy and light underneath
        let shelfY = fy * 0.24
        let sx0 = w * 0.36, sx1 = w * 0.64
        let st = max(4, h * 0.016)
        p.glow(CGPoint(x: w * 0.5, y: shelfY + st * 2), (sx1 - sx0) * 0.55, RoomHue.gold, 0.3)
        for bx in [sx0 + (sx1 - sx0) * 0.15, sx1 - (sx1 - sx0) * 0.15] {
            p.shape(Path(roundedRect: CGRect(x: bx - st * 0.4, y: shelfY + st * 0.6, width: st * 0.8, height: st * 2.6), cornerRadius: st * 0.3),
                    RoomHue.woodDark, shine: 0)
        }
        let cups = Array(trophies.prefix(6))
        if !cups.isEmpty {
            let ch = min(fy * 0.17, (sx1 - sx0) * 0.92 / (CGFloat(max(cups.count, 3)) * 1.03))
            let cw = ch * 0.78
            let gap = cw * 1.32
            let start = w * 0.5 - gap * CGFloat(cups.count - 1) / 2
            for i in cups.indices {
                let face = i == 0 ? RoomHue.gold : i == 1 ? RoomHue.silver : RoomHue.bronze
                let deep = i == 0 ? RoomHue.lip : i == 1 ? RoomHue.silverDeep : Color(hex: "9C5A2C")
                cup(p, cx: start + gap * CGFloat(i), base: shelfY, w: cw, h: ch, face: face, deep: deep)
            }
        }
        p.shape(Path(roundedRect: CGRect(x: sx0, y: shelfY, width: sx1 - sx0, height: st), cornerRadius: st * 0.35), RoomHue.wood, shine: 0.3)

        // skirting board
        let sk = max(5, h * 0.025)
        ctx.fill(Path(CGRect(x: 0, y: fy - sk, width: w, height: sk)), with: .color(Color(hex: "4A3F35")))
        ctx.fill(Path(CGRect(x: 0, y: fy - sk, width: w, height: max(1, sk * 0.2))), with: .color(Color(hex: "5E5144")))

        // the floor: wooden planks running toward the wall
        ctx.fill(Path(CGRect(x: 0, y: fy, width: w, height: fd)), with: .color(Color(hex: "3A2A1F")))
        let vp = CGPoint(x: w * 0.5, y: fy - fd * 1.6)
        func edge(_ xf: CGFloat, _ y: CGFloat) -> CGFloat { vp.x + (xf - vp.x) * (y - vp.y) / (h - vp.y) }
        let plank = w / 7
        let woods = [Color(hex: "4A3426"), Color(hex: "54392A"), Color(hex: "45301F")]
        var seams = Path()
        var joints = Path()
        for i in -6...5 {
            let a = w * 0.5 + (CGFloat(i) - 0.5) * plank, b = a + plank
            ctx.fill(poly([(edge(a, fy), fy), (edge(b, fy), fy), (b, h), (a, h)]), with: .color(woods[(i + 6) % 3]))
            seams.move(to: CGPoint(x: edge(a, fy), y: fy))
            seams.addLine(to: CGPoint(x: a, y: h))
            for d in [0.18, 0.62] as [CGFloat] {
                let jy = fy + fd * (d + CGFloat((i + 6) % 3) * 0.12)
                joints.move(to: CGPoint(x: edge(a, jy), y: jy))
                joints.addLine(to: CGPoint(x: edge(b, jy), y: jy))
            }
        }
        ctx.stroke(seams, with: .color(RoomHue.ink.opacity(0.5)), lineWidth: max(1, u * 0.45))
        ctx.stroke(joints, with: .color(RoomHue.ink.opacity(0.35)), lineWidth: max(1, u * 0.4))
        ctx.fill(Path(CGRect(x: 0, y: fy, width: w, height: fd)),
                 with: .linearGradient(Gradient(colors: [.black.opacity(0.4), .clear]), startPoint: CGPoint(x: 0, y: fy), endPoint: CGPoint(x: 0, y: fy + fd * 0.4)))
        ctx.fill(Path(CGRect(x: 0, y: fy - 1, width: w, height: max(1.5, u * 0.5))), with: .color(RoomHue.ink))

        // light pooling on the floor and the rug the avatar stands on
        var pool = ctx
        pool.translateBy(x: w * 0.5, y: fy + fd * 0.5)
        pool.scaleBy(x: 1, y: max(0.2, fd * 0.8 / (w * 0.9)))
        pool.fill(Path(ellipseIn: CGRect(x: -w * 0.45, y: -w * 0.45, width: w * 0.9, height: w * 0.9)),
                  with: .radialGradient(Gradient(colors: [RoomHue.gold.opacity(0.28), .clear]), center: .zero, startRadius: 0, endRadius: w * 0.45))
        let rugW = w * 0.58, rugH = min(fd * 0.62, rugW * 0.36)
        DecorArt.rug(p, CGRect(x: w * 0.5 - rugW / 2, y: fy + fd * 0.56 - rugH / 2, width: rugW, height: rugH), striped: spots.contains(.rug))

        // placed decor: wall items, then the floor spots, then the front corners
        let order: [RoomSpot] = [.wallLeft, .wallRight, .floorLeft, .floorRight, .frontLeft, .frontRight]
        for spot in order {
            guard let id = placed.first(where: { $0.1 == spot })?.0, let a = DecorArt.aspect(id) else { continue }
            if spot == .wallLeft || spot == .wallRight {
                let floorBelow = spots.contains(spot == .wallLeft ? .floorLeft : .floorRight)
                let x = spot == .wallLeft ? w * 0.04 : w * 0.71
                let area = CGRect(x: x, y: fy * 0.52, width: w * 0.25, height: fy * (floorBelow ? 0.22 : 0.36))
                DecorArt.draw(id, in: &ctx, rect: area, time: time)
                continue
            }
            let front = spot == .frontLeft || spot == .frontRight
            let left = spot == .floorLeft || spot == .frontLeft
            let wallUsed = spots.contains(left ? .wallLeft : .wallRight)
            let base = front ? h - fd * 0.06 : fy + fd * 0.24
            let top = front ? fy + fd * 0.46 : fy * (wallUsed ? 0.76 : 0.48)
            let maxW = w * (front ? 0.24 : 0.27)
            let cx = left ? w * (front ? 0.13 : 0.155) : w * (front ? 0.87 : 0.845)
            var ih = min(base - top, h * 0.4)
            var iw = ih * a
            if iw > maxW {
                iw = maxW
                ih = iw / a
            }
            ctx.fill(Path(ellipseIn: CGRect(x: cx - iw * 0.46, y: base - iw * 0.07, width: iw * 0.92, height: iw * 0.14)),
                     with: .color(.black.opacity(0.35)))
            DecorArt.draw(id, in: &ctx, rect: CGRect(x: cx - iw / 2, y: base - ih, width: iw, height: ih), time: time)
        }

        // soft vignette
        let far = max(w, h)
        ctx.fill(Path(CGRect(origin: .zero, size: size)),
                 with: .radialGradient(Gradient(colors: [.clear, .black.opacity(0.5)]), center: CGPoint(x: w * 0.5, y: h * 0.45),
                                       startRadius: far * 0.3, endRadius: far * 0.85))
    }

    private func cup(_ p: RoomPen, cx: CGFloat, base: CGFloat, w: CGFloat, h: CGFloat, face: Color, deep: Color) {
        let handle = max(1.5, w * 0.11)
        p.tube(Path(ellipseIn: CGRect(x: cx - w * 0.68, y: base - h * 0.98, width: w * 0.42, height: h * 0.4)), deep, handle)
        p.tube(Path(ellipseIn: CGRect(x: cx + w * 0.26, y: base - h * 0.98, width: w * 0.42, height: h * 0.4)), deep, handle)
        p.shape(Path(CGRect(x: cx - w * 0.09, y: base - h * 0.4, width: w * 0.18, height: h * 0.28)), face, shine: 0)
        p.shape(Path(roundedRect: CGRect(x: cx - w * 0.36, y: base - h * 0.16, width: w * 0.72, height: h * 0.16), cornerRadius: h * 0.04), deep, shine: 0.2)
        var bowl = Path()
        bowl.move(to: CGPoint(x: cx - w * 0.5, y: base - h))
        bowl.addLine(to: CGPoint(x: cx + w * 0.5, y: base - h))
        bowl.addQuadCurve(to: CGPoint(x: cx, y: base - h * 0.38), control: CGPoint(x: cx + w * 0.5, y: base - h * 0.4))
        bowl.addQuadCurve(to: CGPoint(x: cx - w * 0.5, y: base - h), control: CGPoint(x: cx - w * 0.5, y: base - h * 0.4))
        bowl.closeSubpath()
        p.shape(bowl, face, shade: 0.22, shine: 0.35)
    }
}
