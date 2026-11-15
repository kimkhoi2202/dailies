import SwiftUI

// Inkland: blobs draw loops of ink on a dotted board and keep the ground inside.
//
// This file has two halves. The first is the art: palette, geometry helpers and the painters in
// InklandScenePaint, written as functions of plain values so the playable game (InklandGame.swift)
// draws with them too. The second is the clip for the video feed: a scripted round laid out in a
// 402 x 874 space, driven by phase alone and aspect-filled onto whatever size it is given.

public struct InklandScene: View {
    public var phase: Double
    public var showHUD: Bool

    public init(phase: Double, showHUD: Bool) {
        self.phase = phase
        self.showHUD = showHUD
    }

    public var body: some View {
        Canvas(opaque: true, colorMode: .nonLinear, rendersAsynchronously: false) { context, size in
            guard size.width > 2, size.height > 2 else { return }
            var ctx = context
            let moment = phase.isFinite ? min(max(phase, 0), 1) : 0
            InklandClipRenderer(phase: moment, showHUD: showHUD, size: size).draw(&ctx)
        }
    }
}

// MARK: - Colour

struct InklandSceneRGB: Sendable {
    let r: Double
    let g: Double
    let b: Double

    init(r: Double, g: Double, b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    init(_ hex: UInt32) {
        self.init(r: Double((hex >> 16) & 0xFF) / 255, g: Double((hex >> 8) & 0xFF) / 255, b: Double(hex & 0xFF) / 255)
    }

    func color(_ alpha: Double = 1) -> Color {
        Color(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }

    func mix(_ other: InklandSceneRGB, _ t: Double) -> InklandSceneRGB {
        InklandSceneRGB(r: r + (other.r - r) * t, g: g + (other.g - g) * t, b: b + (other.b - b) * t)
    }
}

/// One player's ink: the lit top of a slab down to its darkest edge, a pale tint for highlights and
/// the painted blob that wears it.
struct InklandSceneInk: Sendable {
    let top: InklandSceneRGB
    let base: InklandSceneRGB
    let side: InklandSceneRGB
    let deep: InklandSceneRGB
    let tint: InklandSceneRGB
    let blob: String

    init(top: UInt32, base: UInt32, side: UInt32, deep: UInt32, tint: UInt32, blob: String) {
        self.top = InklandSceneRGB(top)
        self.base = InklandSceneRGB(base)
        self.side = InklandSceneRGB(side)
        self.deep = InklandSceneRGB(deep)
        self.tint = InklandSceneRGB(tint)
        self.blob = blob
    }
}

enum InklandScenePalette {
    static let boardGlow = InklandSceneRGB(0x31439A)
    static let boardMid = InklandSceneRGB(0x1F2966)
    static let boardDeep = InklandSceneRGB(0x10153C)
    static let dot = InklandSceneRGB(0x6F82DE)
    static let white = InklandSceneRGB(0xFFFFFF)
    static let night = InklandSceneRGB(0x070A22)
    static let panel = InklandSceneRGB(0x0C1136)
    static let warn = InklandSceneRGB(0xFFDD4A)
    static let warnDeep = InklandSceneRGB(0xC98A10)

    static let coral = InklandSceneInk(top: 0xFF8FA0, base: 0xFF4C77, side: 0xC2235A, deep: 0x8A1245, tint: 0xFFD3DC, blob: "inkland-blob-coral")
    static let cyan = InklandSceneInk(top: 0x86F0FF, base: 0x22C8EE, side: 0x0D8AB6, deep: 0x08668F, tint: 0xD6FAFF, blob: "inkland-blob-cyan")
    static let lime = InklandSceneInk(top: 0xDDFB78, base: 0xA6DE36, side: 0x6A9C19, deep: 0x4C7610, tint: 0xF2FEC8, blob: "inkland-blob-lime")
    static let violet = InklandSceneInk(top: 0xCDB4FF, base: 0x9B79FA, side: 0x6442C8, deep: 0x482D9F, tint: 0xECE2FF, blob: "inkland-blob-violet")
}

// MARK: - Seeded random

/// SplitMix64. The same seed always gives the same round and the same splashes.
struct InklandSceneRNG {
    var state: UInt64

    init(_ seed: UInt64) {
        state = seed &* 0x9E3779B97F4A7C15 &+ 0xD1B54A32D192ED03
    }

    /// A number in 0..<1.
    mutating func next() -> Double {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        z ^= z >> 31
        return Double(z >> 11) / 9007199254740992.0
    }

    mutating func range(_ low: Double, _ high: Double) -> Double {
        low + (high - low) * next()
    }
}

// MARK: - Geometry

enum InklandSceneGeo {
    static func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

    static func lerp(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }

    /// A round-capped, round-jointed pen.
    static func pen(_ width: CGFloat, dash: [CGFloat] = [], phase: CGFloat = 0) -> StrokeStyle {
        StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round, dash: dash, dashPhase: phase)
    }

    /// A uniform Catmull-Rom curve through the knots, as a dense polyline.
    static func spline(_ knots: [CGPoint], samples: Int) -> [CGPoint] {
        guard knots.count > 2 else { return knots }
        let last = knots.count - 1
        var out: [CGPoint] = []
        out.reserveCapacity(last * samples + 1)
        for i in 0..<last {
            let a = knots[max(i - 1, 0)]
            let b = knots[i]
            let c = knots[i + 1]
            let d = knots[min(i + 2, last)]
            for step in 0..<samples {
                let t = CGFloat(step) / CGFloat(samples)
                let t2 = t * t
                let t3 = t2 * t
                let wa = 2 * t2 - t3 - t
                let wb = 3 * t3 - 5 * t2 + 2
                let wc = 4 * t2 - 3 * t3 + t
                let wd = t3 - t2
                out.append(CGPoint(x: (a.x * wa + b.x * wb + c.x * wc + d.x * wd) / 2,
                                   y: (a.y * wa + b.y * wb + c.y * wc + d.y * wd) / 2))
            }
        }
        out.append(knots[last])
        return out
    }

    /// Twice the signed area plus the centroid sums of a closed polygon, by the shoelace rule.
    private static func shoelace(_ pts: [CGPoint]) -> (twiceArea: CGFloat, sx: CGFloat, sy: CGFloat) {
        var twice: CGFloat = 0
        var sx: CGFloat = 0
        var sy: CGFloat = 0
        var a = pts[pts.count - 1]
        for b in pts {
            let cross = a.x * b.y - b.x * a.y
            twice += cross
            sx += (a.x + b.x) * cross
            sy += (a.y + b.y) * cross
            a = b
        }
        return (twice, sx, sy)
    }

    static func signedArea(_ pts: [CGPoint]) -> CGFloat {
        pts.count > 2 ? shoelace(pts).twiceArea / 2 : 0
    }

    /// Gives every polygon the same winding, so overlapping pieces add up under the non-zero rule.
    static func oriented(_ pts: [CGPoint]) -> [CGPoint] {
        signedArea(pts) < 0 ? pts.reversed() : pts
    }

    static func centroid(_ pts: [CGPoint]) -> CGPoint {
        guard pts.count > 2 else { return pts.first ?? .zero }
        let sums = shoelace(pts)
        guard abs(sums.twiceArea) > 0.001 else { return pts[0] }
        return CGPoint(x: sums.sx / (3 * sums.twiceArea), y: sums.sy / (3 * sums.twiceArea))
    }

    /// The wobble of a pool of ink at angle a, between -1 and 1.
    static func wobble(_ a: Double, _ p1: Double, _ p2: Double, _ p3: Double) -> Double {
        0.55 * sin(2 * a + p1) + 0.30 * sin(3 * a + p2) + 0.15 * sin(5 * a + p3)
    }

    /// The outline of a wobbly round pool.
    static func blob(center: CGPoint, radius: CGFloat, seed: UInt64, wobble amount: CGFloat, count: Int = 44) -> [CGPoint] {
        var rng = InklandSceneRNG(seed)
        let p1 = rng.range(0, 6.283)
        let p2 = rng.range(0, 6.283)
        let p3 = rng.range(0, 6.283)
        return (0..<count).map { i in
            let a = Double(i) / Double(count) * 2 * .pi
            let r = radius * (1 + amount * wobble(a, p1, p2, p3))
            return CGPoint(x: center.x + cos(a) * r, y: center.y + sin(a) * r)
        }
    }

    /// Adds a closed curve that passes through the middle of every side of pts, rounding its corners.
    static func addSmoothLoop(_ pts: [CGPoint], to path: inout Path) {
        guard let last = pts.last, pts.count > 2 else { return }
        path.move(to: lerp(last, pts[0], 0.5))
        for i in pts.indices {
            let next = i + 1 < pts.count ? pts[i + 1] : pts[0]
            path.addQuadCurve(to: lerp(pts[i], next, 0.5), control: pts[i])
        }
        path.closeSubpath()
    }

    static func smoothClosed(_ pts: [CGPoint]) -> Path {
        var path = Path()
        addSmoothLoop(pts, to: &path)
        return path
    }

    static func open(_ pts: [CGPoint]) -> Path {
        var path = Path()
        if pts.count > 1 { path.addLines(pts) }
        return path
    }

    static func circle(_ c: CGPoint, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
    }

    /// A four-pointed star.
    static func sparkle(_ c: CGPoint, _ radius: CGFloat) -> Path {
        var corners: [CGPoint] = []
        for i in 0..<8 {
            let a = CGFloat(i) * .pi / 4 - .pi / 2
            let r = i.isMultiple(of: 2) ? radius : radius * 0.26
            corners.append(CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r))
        }
        var path = Path()
        path.addLines(corners)
        path.closeSubpath()
        return path
    }

    /// "18.3" for 18.26.
    static func oneDecimal(_ value: Double) -> String {
        let tenths = Int((max(value, 0) * 10).rounded())
        return "\(tenths / 10).\(tenths % 10)"
    }
}

/// A polyline that can be measured and cut by distance along it.
struct InklandScenePolyline: Sendable {
    let points: [CGPoint]
    /// Distance from the first point to each point.
    let cumulative: [CGFloat]

    init(_ pts: [CGPoint]) {
        points = pts
        var marks: [CGFloat] = [0]
        marks.reserveCapacity(max(pts.count, 1))
        var run: CGFloat = 0
        for (a, b) in zip(pts, pts.dropFirst()) {
            run += hypot(b.x - a.x, b.y - a.y)
            marks.append(run)
        }
        cumulative = marks
    }

    var length: CGFloat { cumulative[cumulative.count - 1] }

    func sample(_ distance: CGFloat) -> (point: CGPoint, tangent: CGVector) {
        guard points.count > 1 else { return (points.first ?? .zero, CGVector(dx: 1, dy: 0)) }
        let d = min(max(distance, 0), length)
        // The first segment whose far end reaches d.
        var end = 1
        while end < points.count - 1, cumulative[end] < d { end += 1 }
        let a = points[end - 1]
        let b = points[end]
        let span = max(cumulative[end] - cumulative[end - 1], 0.0001)
        let t = (d - cumulative[end - 1]) / span
        return (CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t),
                CGVector(dx: (b.x - a.x) / span, dy: (b.y - a.y) / span))
    }

    /// The part of the line between two distances.
    func slice(from start: CGFloat, to end: CGFloat) -> [CGPoint] {
        let lo = min(max(start, 0), length)
        let hi = min(max(end, lo), length)
        var out = [sample(lo).point]
        for (mark, point) in zip(cumulative, points) where mark > lo && mark < hi { out.append(point) }
        out.append(sample(hi).point)
        return out
    }

    /// How far along the line its closest point to target is.
    func nearestDistance(to target: CGPoint) -> CGFloat {
        var closest = CGFloat.greatestFiniteMagnitude
        var along: CGFloat = 0
        for (mark, point) in zip(cumulative, points) {
            let d = hypot(point.x - target.x, point.y - target.y)
            if d < closest {
                closest = d
                along = mark
            }
        }
        return along
    }
}

// MARK: - Painter inputs

struct InklandSceneSplat: Sendable {
    let center: CGPoint
    let radius: CGFloat
}

/// A capture flash on a slab of land.
struct InklandSceneFlashSpec {
    /// The ground that was just claimed.
    var region: Path
    /// The stroke that closed the loop.
    var rim: [CGPoint]
    /// Where the ripples spread from.
    var origin: CGPoint
    /// 0 when the loop closes, 1 when the flash is gone.
    var progress: Double
    var ripples: Bool
}

struct InklandSceneBoardRow {
    var label: String
    var share: Double
    var ink: InklandSceneInk
    var local: Bool
    /// 0 is the top row. In between whole numbers while two rows trade places.
    var rank: Double
}

/// The board's dot grid, built once per visible area instead of every frame.
private final class InklandBoardDots {
    static let shared = InklandBoardDots()

    private struct Entry {
        let rect: CGRect
        let dots: Path
        let marks: Path
    }

    private var entries: [Entry] = []
    private let lock = NSLock()

    func paths(covering rect: CGRect) -> (dots: Path, marks: Path) {
        lock.lock()
        defer { lock.unlock() }
        if let hit = entries.first(where: { $0.rect == rect }) { return (hit.dots, hit.marks) }

        let step: CGFloat = 20
        var dots = Path()
        var marks = Path()
        let columns = Int((rect.minX / step).rounded(.down))...Int((rect.maxX / step).rounded(.up))
        let lines = Int((rect.minY / step).rounded(.down))...Int((rect.maxY / step).rounded(.up))
        let bend = CGSize(width: 0.9, height: 0.9)
        for iy in lines {
            for ix in columns {
                let x = CGFloat(ix) * step
                let y = CGFloat(iy) * step
                if ix % 4 == 0, iy % 4 == 0 {
                    // Every fourth crossing is a small plus sign.
                    marks.addRoundedRect(in: CGRect(x: x - 4, y: y - 0.9, width: 8, height: 1.8), cornerSize: bend)
                    marks.addRoundedRect(in: CGRect(x: x - 0.9, y: y - 4, width: 1.8, height: 8), cornerSize: bend)
                } else {
                    dots.addEllipse(in: CGRect(x: x - 1.1, y: y - 1.1, width: 2.2, height: 2.2))
                }
            }
        }
        if entries.count >= 6 { entries.removeFirst() }
        entries.append(Entry(rect: rect, dots: dots, marks: marks))
        return (dots, marks)
    }
}

// MARK: - Painters

enum InklandScenePaint {
    typealias Pal = InklandScenePalette
    typealias Geo = InklandSceneGeo

    // MARK: Board

    static func board(_ g: inout GraphicsContext, visible: CGRect, glowCenter: CGPoint = CGPoint(x: 185, y: 410)) {
        let rect = visible.insetBy(dx: -6, dy: -6)
        // painted felt in tiles lined up with the world, so it does not slide as the camera moves
        let felt = g.resolve(Image("inkland-board"))
        let tile: CGFloat = 320
        for y in stride(from: (rect.minY / tile).rounded(.down) * tile, to: rect.maxY, by: tile) {
            for x in stride(from: (rect.minX / tile).rounded(.down) * tile, to: rect.maxX, by: tile) {
                g.draw(felt, in: CGRect(x: x, y: y, width: tile, height: tile))
            }
        }
        let glow = Gradient(stops: [
            .init(color: Pal.boardGlow.color(0.62), location: 0),
            .init(color: Pal.boardMid.color(0.2), location: 0.52),
            .init(color: Pal.boardDeep.color(0.6), location: 1),
        ])
        g.fill(Path(rect), with: .radialGradient(glow, center: glowCenter, startRadius: 10, endRadius: 600))
        let grid = InklandBoardDots.shared.paths(covering: rect)
        g.fill(grid.dots, with: .color(Pal.dot.color(0.42)))
        g.fill(grid.marks, with: .color(Pal.dot.color(0.75)))
    }

    // MARK: Territory

    /// The halftone dots printed on a slab, lined up with the board's own grid.
    static func grain(in box: CGRect) -> Path {
        let step: CGFloat = 20
        var dots = Path()
        guard !box.isNull else { return dots }
        for iy in Int((box.minY / step).rounded(.down))...Int((box.maxY / step).rounded(.up)) {
            for ix in Int((box.minX / step).rounded(.down))...Int((box.maxX / step).rounded(.up)) {
                dots.addEllipse(in: CGRect(x: CGFloat(ix) * step - 1.5, y: CGFloat(iy) * step - 1.5, width: 3, height: 3))
            }
        }
        return dots
    }

    /// A player's land as a raised slab of ink. box is the bounding box of path. Pass grain when
    /// the caller keeps the dots for this box between frames.
    static func territory(_ g: inout GraphicsContext, ink: InklandSceneInk, path: Path, box: CGRect,
                          splats: [InklandSceneSplat], flashes: [InklandSceneFlashSpec], grain: Path? = nil) {
        guard !box.isNull, box.width > 0.5, box.height > 0.5 else { return }
        let cover = Path(box.insetBy(dx: -30, dy: -30))
        let night = Pal.night.color()

        // Drops flicked off the home pool.
        for splat in splats {
            g.fill(Geo.circle(CGPoint(x: splat.center.x, y: splat.center.y + 2.4), splat.radius), with: .color(ink.side.color()))
            g.fill(Geo.circle(splat.center, splat.radius), with: .color(ink.base.color()))
        }

        // Colour soaking into the board around the slab.
        g.drawLayer { layer in
            layer.opacity = 0.16
            layer.stroke(path, with: .color(ink.base.color()), style: StrokeStyle(lineWidth: 30, lineJoin: .round))
        }

        // A soft shadow from two flat copies, a wide faint one under a tight darker one.
        let shadow = path.offsetBy(dx: 5, dy: 15)
        for (spread, strength) in [(16.0, 0.13), (6.0, 0.2)] {
            g.drawLayer { layer in
                layer.opacity = strength
                layer.fill(shadow, with: .color(night))
                layer.stroke(shadow, with: .color(night), style: StrokeStyle(lineWidth: spread, lineJoin: .round))
            }
        }

        // The side of the slab: the darkest tone at the bottom, then the wall stacked up to the face.
        g.fill(path.offsetBy(dx: 0, dy: 8), with: .color(ink.deep.color()))
        for drop in [6.6, 5.0, 3.4, 1.8] as [CGFloat] {
            g.fill(path.offsetBy(dx: 0, dy: drop), with: .color(ink.side.color()))
        }

        g.fill(path, with: .linearGradient(Gradient(colors: [ink.top.color(), ink.base.color()]),
                                           startPoint: CGPoint(x: box.minX, y: box.minY),
                                           endPoint: CGPoint(x: box.maxX, y: box.maxY)))

        var face = g
        face.clip(to: path)
        face.fill(grain ?? Self.grain(in: box), with: .color(ink.tint.color(0.26)))

        // Fresh ground flashes white, and the local player's sends ripples out from where the loop closed.
        for flash in flashes {
            let e = flash.progress
            var fresh = face
            fresh.clip(to: flash.region)
            fresh.fill(cover, with: .color(Pal.white.color(0.62 * pow(1 - e, 1.5))))
            guard flash.ripples else { continue }
            for ring in 0..<3 {
                let re = e * 1.5 - Double(ring) * 0.2
                guard re > 0, re < 1 else { continue }
                let radius = 30 + 330 * (1 - pow(1 - re, 2))
                fresh.stroke(Geo.circle(flash.origin, radius), with: .color(Pal.white.color(0.42 * (1 - re))),
                             lineWidth: 16 * (1 - re) + 3)
            }
        }

        // Bevel: whatever the face shows outside a shifted copy of itself is an edge. Light on the
        // top left, shade on the bottom right.
        var lit = face
        lit.clip(to: path.offsetBy(dx: 2.2, dy: 3.0), options: .inverse)
        lit.fill(cover, with: .color(ink.tint.color(0.9)))

        var shade = face
        shade.clip(to: path.offsetBy(dx: -2.2, dy: -2.8), options: .inverse)
        shade.fill(cover, with: .color(ink.side.color(0.38)))

        // A thin wet line set in from the lit edge.
        var gloss = face
        gloss.clip(to: path.offsetBy(dx: 6, dy: 7.5))
        gloss.clip(to: path.offsetBy(dx: 8.2, dy: 10.3), options: .inverse)
        gloss.fill(cover, with: .color(Pal.white.color(0.3)))

        // The stroke that closed each loop glows for a moment.
        for flash in flashes {
            let left = 1 - flash.progress
            g.stroke(Geo.open(flash.rim), with: .color(Pal.white.color(0.9 * left * left)), style: Geo.pen(2 + 5 * left))
        }
    }

    // MARK: Trail

    /// clock runs 0 to 1 over about six seconds and only moves the dots along the local trail.
    static func trail(_ g: inout GraphicsContext, path: Path, ink: InklandSceneInk, local: Bool, clock: Double) {
        let width: CGFloat = local ? 11 : 10
        g.stroke(path.offsetBy(dx: 3, dy: 8), with: .color(Pal.night.color(0.26)), style: Geo.pen(width + 2))
        g.stroke(path.offsetBy(dx: 0, dy: 3.4), with: .color(ink.deep.color()), style: Geo.pen(width))
        g.stroke(path.offsetBy(dx: 0, dy: 1.8), with: .color(ink.side.color()), style: Geo.pen(width))
        g.stroke(path, with: .color(ink.base.mix(ink.top, 0.45).color()), style: Geo.pen(width))
        g.stroke(path.offsetBy(dx: -0.6, dy: -1.6), with: .color(ink.tint.color(0.75)), style: Geo.pen(2.4))
        guard local else { return }
        g.stroke(path, with: .color(Pal.white.color(0.9)), style: Geo.pen(2.6, dash: [0.1, 9], phase: -clock * 900))
    }

    // MARK: Threat marker

    /// A rival closing in on the local trail. hot is the stretch in danger, spot its middle, nose
    /// the front of the rival, k the fade from 0 to 1.
    static func threat(_ g: inout GraphicsContext, hot: Path, spot: CGPoint, nose: CGPoint, k: Double, clock: Double) {
        let pulse = 0.5 + 0.5 * sin(clock * .pi * 2 * 26)
        g.stroke(hot, with: .color(Pal.white.color((0.45 + 0.4 * pulse) * k)), style: Geo.pen(11))

        // Two rings growing out of the spot, half a beat apart.
        for ring in 0..<2 {
            let f = (clock * 22 + Double(ring) * 0.5).truncatingRemainder(dividingBy: 1)
            g.stroke(Geo.circle(spot, 9 + 20 * f), with: .color(Pal.warn.color((1 - f) * 0.9 * k)), lineWidth: 2.6)
        }

        // Dots marching from the rival to the spot.
        var approach = Path()
        approach.move(to: nose)
        approach.addLine(to: CGPoint(x: spot.x + 8, y: spot.y))
        g.stroke(approach, with: .color(Pal.white.color(0.75 * k)),
                 style: StrokeStyle(lineWidth: 2.6, lineCap: .round, dash: [0.1, 7], dashPhase: -clock * 700))

        warningBadge(&g, center: CGPoint(x: spot.x - 31, y: spot.y - 3), k: k, pulse: pulse)
    }

    static func warningBadge(_ g: inout GraphicsContext, center c: CGPoint, k: Double, pulse: Double) {
        let grow = 1 + 0.08 * pulse
        var triangle = Path()
        triangle.addLines([CGPoint(x: c.x, y: c.y - 11 * grow), CGPoint(x: c.x + 11.5 * grow, y: c.y + 8 * grow),
                           CGPoint(x: c.x - 11.5 * grow, y: c.y + 8 * grow)])
        triangle.closeSubpath()
        let thick = Geo.pen(7)
        let under = triangle.offsetBy(dx: 0, dy: 2.6)

        var badge = g
        badge.opacity = k
        badge.stroke(triangle.offsetBy(dx: 2, dy: 5), with: .color(Pal.night.color(0.35)), style: thick)
        badge.stroke(under, with: .color(Pal.warnDeep.color()), style: thick)
        badge.fill(under, with: .color(Pal.warnDeep.color()))
        badge.stroke(triangle, with: .color(Pal.warn.color()), style: thick)
        badge.fill(triangle, with: .color(Pal.warn.color()))
        badge.draw(Text("!").font(.system(size: 15 * grow, weight: .black, design: .rounded)).foregroundColor(Pal.night.color()),
                   at: CGPoint(x: c.x, y: c.y + 0.5), anchor: .center)
    }

    // MARK: Avatars

    /// Two short lines trailing behind a blob that is moving fast.
    static func streaks(_ g: inout GraphicsContext, position c: CGPoint, heading: CGVector, speed: CGFloat) {
        guard speed > 0.3 else { return }
        let fade = Gradient(colors: [Pal.white.color(0.6 * speed), Pal.white.color(0)])
        // Each streak: how far to the side, how far behind, how long.
        for (side, back, length) in [(-10.0, 19.0, 15.0), (10.0, 21.0, 12.0)] as [(CGFloat, CGFloat, CGFloat)] {
            let head = CGPoint(x: c.x - heading.dx * back - heading.dy * side,
                               y: c.y - heading.dy * back + heading.dx * side + 3)
            let tail = CGPoint(x: head.x - heading.dx * length, y: head.y - heading.dy * length)
            var line = Path()
            line.move(to: head)
            line.addLine(to: tail)
            g.stroke(line, with: .linearGradient(fade, startPoint: head, endPoint: tail),
                     style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
        }
    }

    /// A blob: a rounded block with two eyes looking where it is going. meter (0 to 1), when given,
    /// turns the local player's ring into a gauge that empties clockwise.
    static func avatar(_ g: inout GraphicsContext, position c: CGPoint, heading: CGVector, speed: CGFloat,
                       ink: InklandSceneInk, local: Bool, clock: Double, meter: Double? = nil) {
        let half: CGFloat = local ? 14.5 : 13
        let depth: CGFloat = local ? 7 : 6
        // Speed stretches the block along its heading and flattens it across.
        let long = half * (1 + 0.14 * speed)
        let wide = half * (1 - 0.09 * speed)
        let place = CGAffineTransform(translationX: c.x, y: c.y).rotated(by: atan2(heading.dy, heading.dx))
        let face = Path(roundedRect: CGRect(x: -long, y: -wide, width: 2 * long, height: 2 * wide), cornerRadius: half * 0.58,
                        style: .continuous).applying(place)

        if local {
            let pulse = 0.5 + 0.5 * sin(clock * .pi * 2 * 9)
            let radius = half + 10 + 3 * pulse
            let ring = Geo.circle(CGPoint(x: c.x, y: c.y + depth * 0.4), radius)
            if let meter {
                let level = min(max(meter, 0), 1)
                let low = level < 0.3
                g.stroke(ring, with: .color(Pal.white.color(0.2)), lineWidth: 2.4)
                if level > 0.004 {
                    var arc = Path()
                    arc.addArc(center: CGPoint(x: c.x, y: c.y + depth * 0.4), radius: radius, startAngle: .radians(-.pi / 2),
                               endAngle: .radians(-.pi / 2 + 2 * .pi * level), clockwise: false)
                    g.stroke(arc, with: .color(low ? Pal.warn.color(0.75 + 0.25 * pulse) : Pal.white.color(0.85)),
                             style: StrokeStyle(lineWidth: low ? 3.4 : 2.8, lineCap: .round))
                }
            } else {
                g.stroke(ring, with: .color(Pal.white.color(0.7 - 0.25 * pulse)),
                         style: StrokeStyle(lineWidth: 2.4, lineCap: .round, dash: [6, 6], dashPhase: clock * 240))
            }
        }

        g.fill(face.offsetBy(dx: 3, dy: depth), with: .color(Pal.night.color(0.26)))
        g.fill(face.offsetBy(dx: 1.5, dy: depth * 0.5), with: .color(Pal.night.color(0.24)))

        var body = g
        body.concatenate(place)
        body.draw(g.resolve(Image(ink.blob)), in: CGRect(x: -1.12 * long, y: -1.12 * wide, width: 2.24 * long, height: 2.24 * wide))
    }

    /// The leader's crown, painted, centred on a point.
    static func crown(_ g: inout GraphicsContext, center c: CGPoint, width w: CGFloat) {
        let image = g.resolve(Image("inkland-crown"))
        let h = w * image.size.height / max(1, image.size.width)
        g.draw(image, in: CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h))
    }

    /// The name tag over a blob. below hangs it under the blob instead, for use near the top wall.
    static func tag(_ g: inout GraphicsContext, position c: CGPoint, label: String, ink: InklandSceneInk,
                    local: Bool, crowned: Bool, below: Bool = false) {
        let text = g.resolve(Text(label).font(.system(size: local ? 11.5 : 10, weight: .heavy, design: .rounded))
            .kerning(local ? 0.6 : 0.2).foregroundColor(local ? ink.side.color() : Pal.white.color()))
        let textSize = text.measure(in: CGSize(width: 200, height: 60))
        let crownW: CGFloat = 13
        let crownRoom: CGFloat = crowned ? crownW + 3 : 0
        let padX: CGFloat = local ? 8 : 6.5
        let height = textSize.height + (local ? 6 : 4.5)
        let width = textSize.width + padX * 2 + crownRoom
        let midY = below ? c.y + (local ? 44 : 38) : c.y - (local ? 37 : 31)
        let rect = CGRect(x: c.x - width / 2, y: midY - height / 2, width: width, height: height)
        let pill = Path(roundedRect: rect, cornerRadius: height / 2, style: .continuous)

        // A small triangle from the pill towards the blob.
        let root = below ? rect.minY + 1.5 : rect.maxY - 1.5
        let tip = below ? rect.minY - 5 : rect.maxY + 5
        var pointer = Path()
        pointer.addLines([CGPoint(x: c.x - 5, y: root), CGPoint(x: c.x + 5, y: root), CGPoint(x: c.x, y: tip)])
        pointer.closeSubpath()

        g.fill(pill.offsetBy(dx: 1.5, dy: 3.5), with: .color(Pal.night.color(0.35)))
        if local {
            g.fill(pointer.offsetBy(dx: 1.5, dy: 3.5), with: .color(Pal.night.color(0.35)))
            g.fill(pill, with: .color(Pal.white.color()))
            g.fill(pointer, with: .color(Pal.white.color()))
        } else {
            g.fill(pill, with: .color(Pal.panel.color(0.86)))
            g.fill(pointer, with: .color(Pal.panel.color(0.86)))
            g.stroke(pill, with: .color(ink.base.color(0.95)), lineWidth: 1.3)
        }

        if crowned {
            crown(&g, center: CGPoint(x: rect.minX + padX + crownW / 2 - 1, y: midY - 0.5), width: crownW)
        }
        g.draw(text, at: CGPoint(x: c.x + crownRoom / 2, y: midY), anchor: .center)
    }

    // MARK: Capture burst

    /// Drops of ink and sparkles for a loop the local player has just closed. gain is in percent of the board.
    static func burst(_ g: inout GraphicsContext, ink: InklandSceneInk, rim: InklandScenePolyline, centroid center: CGPoint,
                      region: Path, gain: Double, progress e: Double, big: Bool) {
        var rng = InklandSceneRNG(UInt64(max(gain, 0) * 100) &+ 17)

        // Drops thrown outwards from all along the new border.
        let drops = big ? 34 : 14
        let flown = 1 - pow(1 - e, 2.2)
        let shrink = 1 - pow(e, 2.4)
        for i in 0..<drops {
            let edge = rim.sample(rim.length * ((Double(i) + rng.next() * 0.8) / Double(drops))).point
            let away = hypot(edge.x - center.x, edge.y - center.y)
            let out = CGVector(dx: (edge.x - center.x) / max(away, 0.001), dy: (edge.y - center.y) / max(away, 0.001))
            let reach = rng.range(14, big ? 58 : 30)
            let radius = rng.range(1.8, big ? 5.2 : 3.6) * shrink
            let tone = rng.next()
            guard radius > 0.3 else { continue }
            let far = 6 + reach * flown
            let head = CGPoint(x: edge.x + out.dx * far, y: edge.y + out.dy * far)
            let tail = (1 - e) * reach * 0.34
            var drop = Path()
            drop.move(to: head)
            drop.addLine(to: CGPoint(x: head.x - out.dx * tail, y: head.y - out.dy * tail))
            let colour = tone < 0.22 ? Pal.white : (tone < 0.6 ? ink.top : ink.base)
            let blot = StrokeStyle(lineWidth: radius * 2, lineCap: .round)
            g.stroke(drop.offsetBy(dx: 1.5, dy: 4), with: .color(Pal.night.color(0.22)), style: blot)
            g.stroke(drop, with: .color(colour.color()), style: blot)
        }

        // Sparkles over the new ground, each with its own short moment.
        let box = region.boundingRect
        var wanted = big ? 11 : 4
        var tries = 0
        while wanted > 0, tries < 80 {
            tries += 1
            let x = box.minX + box.width * rng.next()
            let y = box.minY + box.height * rng.next()
            let delay = rng.range(0, 0.45)
            let size = rng.range(4, big ? 10 : 7)
            guard region.contains(CGPoint(x: x, y: y)) else { continue }
            wanted -= 1
            let t = (e - delay) / 0.5
            guard t > 0, t < 1 else { continue }
            g.fill(Geo.sparkle(CGPoint(x: x, y: y), size * sin(t * .pi)), with: .color(Pal.white.color(0.95)))
        }
    }

    /// An outlined label that pops in, rises and fades: "+18.3%".
    static func popup(_ g: inout GraphicsContext, ink: InklandSceneInk, centroid: CGPoint, label: String,
                      progress e: Double, big: Bool) {
        let rise = (1 - pow(1 - e, 3)) * (big ? 30 : 18)
        // Overshoot to 1.15 in the first moments, then settle at 1.
        let pop = e < 0.14 ? 0.6 + 0.55 * (e / 0.14) : 1.15 - 0.15 * min((e - 0.14) / 0.12, 1)
        let words = Text(label).font(.system(size: (big ? 30 : 17) * pop, weight: .black, design: .rounded))
        let at = CGPoint(x: centroid.x + (big ? 4 : 0), y: centroid.y - (big ? 8 : 0) - rise)

        var layer = g
        layer.opacity = e > 0.78 ? max(1 - (e - 0.78) / 0.22, 0) : 1
        // The outline is the same words in the dark tone, stamped in a ring around the centre.
        let outline = layer.resolve(words.foregroundColor(ink.deep.color()))
        let spread: CGFloat = big ? 3.2 : 2.2
        for i in 0..<14 {
            let a = CGFloat(i) / 14 * 2 * .pi
            layer.draw(outline, at: CGPoint(x: at.x + cos(a) * spread, y: at.y + sin(a) * spread + 1.5), anchor: .center)
        }
        layer.draw(layer.resolve(words.foregroundColor(Pal.white.color())), at: at, anchor: .center)
    }

    // MARK: Vignette

    /// Darkens the top fifth and the bottom third of the view so the HUD and the app's buttons read.
    static func vignette(_ ctx: inout GraphicsContext, size: CGSize, top: Double = 0.62, bottom: Double = 0.7) {
        let topEnd = size.height * 0.2
        ctx.fill(Path(CGRect(x: 0, y: 0, width: size.width, height: topEnd)),
                 with: .linearGradient(Gradient(colors: [Pal.night.color(top), Pal.night.color(0)]),
                                       startPoint: .zero, endPoint: CGPoint(x: 0, y: topEnd)))
        let bottomStart = size.height * 0.66
        ctx.fill(Path(CGRect(x: 0, y: bottomStart, width: size.width, height: size.height - bottomStart)),
                 with: .linearGradient(Gradient(colors: [Pal.night.color(0), Pal.night.color(bottom)]),
                                       startPoint: CGPoint(x: 0, y: bottomStart), endPoint: CGPoint(x: 0, y: size.height)))
    }

    // MARK: HUD pieces

    /// A panel behind HUD pieces: a shadow, a dark fill and a thin edge.
    private static func plate(_ ctx: inout GraphicsContext, _ shape: Path, u: CGFloat, edge: Color, edgeWidth: CGFloat) {
        ctx.fill(shape.offsetBy(dx: 0, dy: 3 * u), with: .color(Pal.night.color(0.35)))
        ctx.fill(shape, with: .color(Pal.panel.color(0.8)))
        ctx.stroke(shape, with: .color(edge), lineWidth: edgeWidth)
    }

    /// A chip of the player's colour and the words "YOUR INK". origin is the chip's top left corner.
    static func inkCaption(_ ctx: inout GraphicsContext, origin: CGPoint, u: CGFloat, ink: InklandSceneInk) {
        let chip = Path(roundedRect: CGRect(x: origin.x, y: origin.y, width: 12 * u, height: 12 * u), cornerRadius: 3.8 * u,
                        style: .continuous)
        ctx.fill(chip.offsetBy(dx: 0, dy: 2 * u), with: .color(ink.side.color()))
        ctx.fill(chip, with: .color(ink.base.color()))
        ctx.stroke(chip, with: .color(Pal.white.color()), lineWidth: 1.5 * u)
        ctx.draw(Text("YOUR INK").font(.system(size: 10.5 * u, weight: .heavy, design: .rounded)).kerning(1.4 * u)
            .foregroundColor(Pal.white.color(0.78)), at: CGPoint(x: origin.x + 18 * u, y: origin.y + 6.5 * u), anchor: .leading)
    }

    /// The big share number and its percent sign. x is the left edge, or the middle when centered.
    /// size is the number's point size before u.
    static func shareNumber(_ ctx: inout GraphicsContext, share: Double, ink: InklandSceneInk, x: CGFloat,
                            baseline: CGFloat, u: CGFloat, size: CGFloat = 44, centered: Bool = false) {
        let k = size / 44
        let digits = Text(Geo.oneDecimal(share)).font(.system(size: size * u, weight: .black, design: .rounded)).monospacedDigit()
        let number = ctx.resolve(digits.foregroundColor(Pal.white.color()))
        let numberSize = number.measure(in: CGSize(width: 400 * u, height: 120 * u))
        let sign = ctx.resolve(Text("%").font(.system(size: 24 * k * u, weight: .heavy, design: .rounded))
            .foregroundColor(ink.top.color()))
        let signSize = sign.measure(in: CGSize(width: 100 * u, height: 80 * u))
        let gap = 2 * u

        let left = centered ? x - (numberSize.width + gap + signSize.width) / 2 : x
        let top = baseline - number.firstBaseline(in: numberSize)
        ctx.draw(ctx.resolve(digits.foregroundColor(Pal.night.color(0.55))), at: CGPoint(x: left, y: top + 3 * k * u),
                 anchor: .topLeading)
        ctx.draw(number, at: CGPoint(x: left, y: top), anchor: .topLeading)
        ctx.draw(sign, at: CGPoint(x: left + numberSize.width + gap, y: baseline - sign.firstBaseline(in: signSize)),
                 anchor: .topLeading)
    }

    /// Everyone's share of the board as one bar, the local player first. gain stretches the
    /// segments so small shares still show.
    static func splitBar(_ ctx: inout GraphicsContext, rect: CGRect, u: CGFloat,
                         segments: [(share: Double, ink: InklandSceneInk)], gain: CGFloat = 1.55) {
        let track = Path(roundedRect: rect, cornerRadius: 4 * u, style: .continuous)
        ctx.fill(track.offsetBy(dx: 0, dy: 1.5 * u), with: .color(Pal.night.color(0.45)))
        ctx.fill(track, with: .color(Pal.white.color(0.16)))

        var bar = ctx
        bar.clip(to: track)
        var x = rect.minX
        for segment in segments {
            let width = rect.width * (segment.share / 100) * gain
            bar.fill(Path(CGRect(x: x, y: rect.minY, width: width, height: rect.height)), with: .color(segment.ink.base.color()))
            x += width + 1.2 * u
        }
        // A sheen across the top of the whole bar.
        bar.fill(Path(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height * 0.42)),
                 with: .color(Pal.white.color(0.22)))
    }

    static func leaderboard(_ ctx: inout GraphicsContext, panelRect: CGRect, u: CGFloat, rowH: CGFloat, padY: CGFloat,
                            rows: [InklandSceneBoardRow]) {
        plate(&ctx, Path(roundedRect: panelRect, cornerRadius: 14 * u, style: .continuous), u: u,
              edge: Pal.white.color(0.14), edgeWidth: u)

        for row in rows {
            let band = CGRect(x: panelRect.minX + 4 * u, y: panelRect.minY + padY + row.rank * rowH + u,
                              width: panelRect.width - 8 * u, height: rowH - 2 * u)
            let midY = band.midY
            if row.local {
                ctx.fill(Path(roundedRect: band, cornerRadius: 9 * u, style: .continuous),
                         with: .linearGradient(Gradient(colors: [row.ink.top.color(), row.ink.base.color()]),
                                               startPoint: CGPoint(x: band.minX, y: band.minY),
                                               endPoint: CGPoint(x: band.maxX, y: band.maxY)))
            }

            let swatch = CGRect(x: band.minX + 6 * u, y: midY - 4.5 * u, width: 9 * u, height: 9 * u)
            ctx.fill(Path(roundedRect: swatch, cornerRadius: 3 * u, style: .continuous),
                     with: .color(row.local ? Pal.white.color() : row.ink.base.color()))

            let tone = row.local ? Pal.white.color() : Pal.white.color(0.86)
            let nameX = swatch.maxX + 6 * u
            let name = ctx.resolve(Text(row.label).font(.system(size: 11 * u, weight: row.local ? .heavy : .bold, design: .rounded))
                .foregroundColor(tone))
            ctx.draw(name, at: CGPoint(x: nameX, y: midY), anchor: .leading)

            // The top row wears a crown after its name.
            if row.rank < 0.5 {
                let nameW = name.measure(in: CGSize(width: 200 * u, height: 40 * u)).width
                crown(&ctx, center: CGPoint(x: nameX + nameW + 9 * u, y: midY - 0.5 * u), width: 11 * u)
            }

            ctx.draw(Text(Geo.oneDecimal(row.share) + "%").font(.system(size: 10.5 * u, weight: .heavy, design: .rounded))
                .monospacedDigit().foregroundColor(tone), at: CGPoint(x: band.maxX - 6 * u, y: midY), anchor: .trailing)
        }
    }

    /// The clock pill. urgent turns it yellow for the last seconds of a round.
    static func timer(_ ctx: inout GraphicsContext, rect: CGRect, u: CGFloat, label: String, urgent: Bool = false) {
        plate(&ctx, Path(roundedRect: rect, cornerRadius: rect.height / 2, style: .continuous), u: u,
              edge: urgent ? Pal.warn.color(0.9) : Pal.white.color(0.14), edgeWidth: (urgent ? 1.6 : 1) * u)

        // A tiny clock face showing about four.
        let tone = urgent ? Pal.warn.color() : Pal.white.color(0.9)
        let hub = CGPoint(x: rect.minX + 12.5 * u, y: rect.midY)
        ctx.stroke(Geo.circle(hub, 5.2 * u), with: .color(tone), lineWidth: 1.6 * u)
        var hands = Path()
        hands.addLines([CGPoint(x: hub.x, y: hub.y - 3 * u), hub, CGPoint(x: hub.x + 2.4 * u, y: hub.y + 1.2 * u)])
        ctx.stroke(hands, with: .color(tone), style: Geo.pen(1.5 * u))

        ctx.draw(Text(label).font(.system(size: 12 * u, weight: .heavy, design: .rounded)).monospacedDigit()
            .foregroundColor(urgent ? Pal.warn.color() : Pal.white.color()),
                 at: CGPoint(x: rect.minX + 22 * u, y: rect.midY), anchor: .leading)
    }
}

// MARK: - The clip's script

/// One loop a player draws in the clip: out from its land along a curve and back.
private struct InklandClipLoop: Sendable {
    /// Phase at which the player sets off and at which the loop closes.
    let start: Double
    let close: Double
    /// Percent of the board the loop adds.
    let gain: Double
    let line: InklandScenePolyline
    let polygon: [CGPoint]
    let polygonPath: Path
    let centroid: CGPoint

    init(_ start: Double, _ close: Double, gain: Double, through knots: [(CGFloat, CGFloat)]) {
        self.start = start
        self.close = close
        self.gain = gain
        let curve = InklandSceneGeo.spline(knots.map { CGPoint(x: $0.0, y: $0.1) }, samples: 12)
        line = InklandScenePolyline(curve)
        polygon = InklandSceneGeo.oriented(curve)
        var closed = Path()
        closed.addLines(polygon)
        closed.closeSubpath()
        polygonPath = closed
        centroid = InklandSceneGeo.centroid(polygon)
    }

    func covers(_ phase: Double) -> Bool { phase >= start && phase < close }

    /// How far round the loop the player is, 0 to 1.
    func progress(at phase: Double) -> CGFloat { (phase - start) / (close - start) }
}

private struct InklandClipPlayer: Sendable {
    let id: Int
    let name: String
    let ink: InklandSceneInk
    let isLocal: Bool
    let homePath: Path
    let splats: [InklandSceneSplat]
    let loops: [InklandClipLoop]
    /// Where the player is at given phases while not drawing, in time order.
    let stops: [(time: Double, point: CGPoint)]
    /// Share of the board in percent after each change, in time order.
    let shares: [(time: Double, value: Double)]

    init(id: Int, name: String, ink: InklandSceneInk, home: (CGFloat, CGFloat), radius: CGFloat, seed: UInt64,
         loops: [InklandClipLoop], strolls: [(Double, CGFloat, CGFloat)] = [], finish: (CGFloat, CGFloat),
         shares: [(Double, Double)]) {
        self.id = id
        self.name = name
        self.ink = ink
        self.loops = loops
        self.shares = shares.map { (time: $0.0, value: $0.1) }
        isLocal = id == 0
        let home = CGPoint(x: home.0, y: home.1)
        homePath = InklandSceneGeo.smoothClosed(InklandSceneGeo.blob(center: home, radius: radius, seed: seed, wobble: 0.15))

        var rng = InklandSceneRNG(seed &+ 991)
        splats = (0..<7).map { _ in
            let angle = rng.range(0, 6.283)
            let away = radius * rng.range(1.22, 1.5)
            let size = rng.range(1.6, 3.6)
            return InklandSceneSplat(center: CGPoint(x: home.x + cos(angle) * away, y: home.y + sin(angle) * away), radius: size)
        }

        var stops: [(time: Double, point: CGPoint)] = [(0, home)]
        for loop in loops {
            stops.append((loop.start, loop.line.points.first ?? home))
            stops.append((loop.close, loop.line.points.last ?? home))
        }
        for stroll in strolls { stops.append((stroll.0, CGPoint(x: stroll.1, y: stroll.2))) }
        stops.append((1.0001, CGPoint(x: finish.0, y: finish.1)))
        self.stops = stops.sorted { $0.time < $1.time }
    }

    func activeLoop(at phase: Double) -> InklandClipLoop? {
        loops.first { $0.covers(phase) }
    }

    func position(at phase: Double) -> CGPoint {
        if let loop = activeLoop(at: phase) {
            return loop.line.sample(loop.line.length * loop.progress(at: phase)).point
        }
        // Between loops it walks in a straight line from one stop to the next.
        guard let next = stops.firstIndex(where: { $0.time > phase }), next > 0 else {
            return stops[stops.count - 1].point
        }
        let from = stops[next - 1]
        let to = stops[next]
        let span = to.time - from.time
        guard span > 0.00001 else { return from.point }
        return InklandSceneGeo.lerp(from.point, to.point, min(max((phase - from.time) / span, 0), 1))
    }

    /// The share counts up over a short moment after each change.
    func share(at phase: Double) -> Double {
        var value = shares[0].value
        for (before, after) in zip(shares, shares.dropFirst()) where phase >= after.time {
            let t = min((phase - after.time) / 0.05, 1)
            value = before.value + (after.value - before.value) * (1 - pow(1 - t, 3))
        }
        return value
    }
}

private enum InklandClipScript {
    /// The cyan rival's second run passes close to the local player's open trail.
    static let threatRival = 1
    static let threatWindow = 0.405...0.565
    static let threatTarget = CGPoint(x: 291, y: 414)

    /// In drawing order: rivals first, the local player on top.
    static let players: [InklandClipPlayer] = [
        InklandClipPlayer(
            id: 3, name: "Nyx", ink: InklandScenePalette.violet, home: (46, 270), radius: 44, seed: 33,
            loops: [
                InklandClipLoop(0.07, 0.31, gain: 5.6,
                                through: [(66, 284), (112, 290), (138, 322), (128, 362), (88, 372), (52, 344), (46, 300)]),
                InklandClipLoop(0.80, 1.06, gain: 3.0,
                                through: [(62, 258), (98, 236), (134, 246), (150, 276), (130, 296), (96, 296)]),
            ],
            strolls: [(0.45, 70, 322), (0.60, 44, 266)],
            finish: (62, 258),
            shares: [(0, 2.3), (0.31, 7.9), (0.76, 5.6)]),
        InklandClipPlayer(
            id: 1, name: "Kiko", ink: InklandScenePalette.cyan, home: (320, 250), radius: 42, seed: 21,
            loops: [
                InklandClipLoop(0.07, 0.23, gain: 4.2,
                                through: [(304, 246), (270, 234), (246, 258), (256, 292), (290, 302), (306, 274)]),
                InklandClipLoop(0.40, 0.75, gain: 6.6,
                                through: [(322, 280), (330, 320), (322, 362), (300, 392), (291, 414), (296, 440),
                                          (322, 452), (352, 420), (358, 360), (345, 300), (335, 275)]),
            ],
            finish: (318, 340),
            shares: [(0, 2.6), (0.23, 6.8), (0.75, 13.4)]),
        InklandClipPlayer(
            id: 2, name: "Bolt", ink: InklandScenePalette.lime, home: (312, 600), radius: 42, seed: 45,
            loops: [
                InklandClipLoop(0.09, 0.29, gain: 4.2,
                                through: [(304, 588), (286, 548), (300, 508), (336, 498), (360, 530), (338, 582)]),
                InklandClipLoop(0.58, 0.92, gain: 3.8,
                                through: [(292, 612), (262, 640), (252, 690), (290, 722), (336, 700), (330, 640)]),
            ],
            strolls: [(0.42, 312, 540)],
            finish: (318, 600),
            shares: [(0, 1.8), (0.29, 6.0), (0.92, 9.8)]),
        InklandClipPlayer(
            id: 0, name: "You", ink: InklandScenePalette.coral, home: (140, 540), radius: 44, seed: 7,
            loops: [
                InklandClipLoop(0.03, 0.20, gain: 3.3,
                                through: [(160, 532), (198, 508), (236, 520), (246, 560), (214, 594), (158, 568)]),
                InklandClipLoop(0.245, 0.76, gain: 18.3,
                                through: [(216, 548), (250, 502), (270, 442), (268, 378), (242, 328), (192, 304),
                                          (132, 302), (82, 324), (54, 372), (52, 432), (72, 487), (114, 527)]),
            ],
            finish: (176, 418),
            shares: [(0, 2.0), (0.20, 5.3), (0.76, 23.6)]),
    ]
}

/// Everything about one player at one phase of the clip.
private struct InklandClipState {
    let player: InklandClipPlayer
    let position: CGPoint
    let heading: CGVector
    let speed: CGFloat
    let trail: [CGPoint]
    let territory: Path
    let bounds: CGRect
    let share: Double
    /// Loops closed a moment ago, with how far through its flash each one is.
    let flashes: [(loop: InklandClipLoop, progress: Double)]

    init(_ player: InklandClipPlayer, at phase: Double) {
        self.player = player
        position = player.position(at: phase)
        share = player.share(at: phase)

        // Heading and speed come from where it was a moment ago and where it will be.
        let behind = player.position(at: max(phase - 0.004, 0))
        let ahead = player.position(at: min(phase + 0.004, 1))
        let moved = hypot(ahead.x - behind.x, ahead.y - behind.y)
        heading = moved > 0.05 ? CGVector(dx: (ahead.x - behind.x) / moved, dy: (ahead.y - behind.y) / moved)
            : CGVector(dx: 1, dy: 0)
        speed = min(moved / 7, 1)

        if let loop = player.activeLoop(at: phase) {
            trail = loop.line.slice(from: 0, to: loop.line.length * loop.progress(at: phase))
        } else {
            trail = []
        }

        var land = player.homePath
        var recent: [(loop: InklandClipLoop, progress: Double)] = []
        for loop in player.loops where phase >= loop.close {
            land.addPath(loop.polygonPath)
            let flashLength = player.isLocal ? (loop.gain > 10 ? 0.22 : 0.15) : 0.09
            let e = (phase - loop.close) / flashLength
            if e < 1 { recent.append((loop, e)) }
        }
        territory = land
        bounds = land.boundingRect
        flashes = recent
    }
}

// MARK: - Clip renderer

private struct InklandClipRenderer {
    let phase: Double
    let showHUD: Bool
    let size: CGSize

    typealias Paint = InklandScenePaint
    typealias Geo = InklandSceneGeo

    func draw(_ ctx: inout GraphicsContext) {
        // Fill the view, keeping the middle of the action at the same relative spot.
        let scale = max(size.width / 402, size.height / 874)
        let focus = CGPoint(x: 190, y: 420)
        let shift = CGPoint(x: size.width * focus.x / 402 - focus.x * scale, y: size.height * focus.y / 874 - focus.y * scale)
        let visible = CGRect(x: -shift.x / scale, y: -shift.y / scale, width: size.width / scale, height: size.height / scale)

        let states = InklandClipScript.players.map { InklandClipState($0, at: phase) }
        let leader = states.max { $0.share < $1.share }?.player.id ?? 0
        let backToFront = states.sorted { $0.position.y < $1.position.y }
        let me = states.first { $0.player.isLocal }

        var g = ctx
        g.translateBy(x: shift.x, y: shift.y)
        g.scaleBy(x: scale, y: scale)

        Paint.board(&g, visible: visible)
        for state in states {
            if state.trail.count > 1 {
                Paint.trail(&g, path: Geo.open(state.trail), ink: state.player.ink, local: state.player.isLocal, clock: phase)
            }
            let flashes = state.flashes.map { flash in
                InklandSceneFlashSpec(region: flash.loop.polygonPath, rim: flash.loop.line.points,
                                      origin: flash.loop.line.points.last ?? flash.loop.centroid,
                                      progress: flash.progress, ripples: state.player.isLocal)
            }
            Paint.territory(&g, ink: state.player.ink, path: state.territory, box: state.bounds, splats: state.player.splats,
                            flashes: flashes)
        }
        if let me { drawThreat(&g, me: me, states: states) }

        for state in backToFront {
            Paint.streaks(&g, position: state.position, heading: state.heading, speed: state.speed)
        }
        for state in backToFront {
            Paint.avatar(&g, position: state.position, heading: state.heading, speed: state.speed, ink: state.player.ink,
                         local: state.player.isLocal, clock: phase)
        }
        if let me {
            for flash in me.flashes {
                Paint.burst(&g, ink: me.player.ink, rim: flash.loop.line, centroid: flash.loop.centroid,
                            region: flash.loop.polygonPath, gain: flash.loop.gain, progress: flash.progress,
                            big: flash.loop.gain > 10)
            }
        }
        for state in backToFront {
            Paint.tag(&g, position: state.position, label: state.player.isLocal ? "YOU" : state.player.name,
                      ink: state.player.ink, local: state.player.isLocal, crowned: state.player.id == leader)
        }
        if let me {
            for flash in me.flashes {
                Paint.popup(&g, ink: me.player.ink, centroid: flash.loop.centroid,
                            label: "+" + Geo.oneDecimal(flash.loop.gain) + "%", progress: flash.progress,
                            big: flash.loop.gain > 10)
            }
        }

        Paint.vignette(&ctx, size: size)
        if showHUD, let me { drawHUD(&ctx, me: me, states: states) }
    }

    private func drawThreat(_ g: inout GraphicsContext, me: InklandClipState, states: [InklandClipState]) {
        let window = InklandClipScript.threatWindow
        guard phase > window.lowerBound, phase < window.upperBound,
              let rival = states.first(where: { $0.player.id == InklandClipScript.threatRival }),
              let loop = me.player.activeLoop(at: phase) else { return }
        // Fades in and out over the ends of its window.
        let k = min((phase - window.lowerBound) / 0.03, (window.upperBound - phase) / 0.03, 1)
        let along = loop.line.nearestDistance(to: InklandClipScript.threatTarget)
        Paint.threat(&g, hot: Geo.open(loop.line.slice(from: along - 26, to: along + 26)), spot: loop.line.sample(along).point,
                     nose: CGPoint(x: rival.position.x + rival.heading.dx * 19, y: rival.position.y + rival.heading.dy * 19),
                     k: k, clock: phase)
    }

    private func drawHUD(_ ctx: inout GraphicsContext, me: InklandClipState, states: [InklandClipState]) {
        let w = size.width
        let u = min(w / 402, size.height / 640)
        let margin = 16 * w / 402
        let top = size.height * 124 / 874
        let ink = me.player.ink

        Paint.inkCaption(&ctx, origin: CGPoint(x: margin, y: top), u: u, ink: ink)
        Paint.shareNumber(&ctx, share: me.share, ink: ink, x: margin - 1.5 * u, baseline: top + 55 * u, u: u)

        let bar = CGRect(x: margin, y: top + 64 * u, width: 124 * u, height: 8 * u)
        let rivals = states.filter { !$0.player.isLocal }.sorted { $0.share > $1.share }
        Paint.splitBar(&ctx, rect: bar, u: u, segments: ([me] + rivals).map { (share: $0.share, ink: $0.player.ink) })

        let rowH = 19.5 * u
        let padY = 6 * u
        let panelW = 108 * u
        let panel = CGRect(x: w - 68 * w / 402 - panelW, y: top - 2 * u, width: panelW,
                           height: rowH * CGFloat(states.count) + padY * 2)
        let rows = states.map { state in
            // A row's place is how many others are ahead of it. Counting each one softly lets two
            // rows slide past each other while their shares cross.
            var rank = 0.0
            for other in states where other.player.id != state.player.id {
                let nudge = other.player.id < state.player.id ? 0.0005 : -0.0005
                rank += min(max((other.share - state.share + nudge) / 0.08 + 0.5, 0), 1)
            }
            return InklandSceneBoardRow(label: state.player.isLocal ? "You" : state.player.name, share: state.share,
                                        ink: state.player.ink, local: state.player.isLocal, rank: rank)
        }
        Paint.leaderboard(&ctx, panelRect: panel, u: u, rowH: rowH, padY: padY, rows: rows)

        // The clock sits between the bar and the leaderboard and counts down from 1:36.
        let seconds = max(Int((96 - phase * 72).rounded()), 0)
        let label = "\(seconds / 60):" + (seconds % 60 < 10 ? "0" : "") + "\(seconds % 60)"
        let pillW = 58 * u
        Paint.timer(&ctx, rect: CGRect(x: (bar.maxX + panel.minX) / 2 - pillW / 2 + 4 * u, y: top - 2 * u, width: pillW, height: 22 * u),
                    u: u, label: label)
    }
}
