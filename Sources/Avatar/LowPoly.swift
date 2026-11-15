import SceneKit
import UIKit

// Low-poly building blocks for the Dailie: shapes with few faces and one normal per face, so each facet
// catches the light on its own. Everything a Dailie wears is made from these.

enum LowPoly {
    /// One shape of triangles with flat normals.
    static func geometry(_ triangles: [(SCNVector3, SCNVector3, SCNVector3)], color: UIColor) -> SCNGeometry {
        var vertices: [SCNVector3] = [], normals: [SCNVector3] = [], indices: [UInt32] = []
        vertices.reserveCapacity(triangles.count * 3)
        for (a, b, c) in triangles {
            let u = SCNVector3(b.x - a.x, b.y - a.y, b.z - a.z), v = SCNVector3(c.x - a.x, c.y - a.y, c.z - a.z)
            var n = SCNVector3(u.y * v.z - u.z * v.y, u.z * v.x - u.x * v.z, u.x * v.y - u.y * v.x)
            let length = (n.x * n.x + n.y * n.y + n.z * n.z).squareRoot()
            if length < 1e-9 { continue }
            n = SCNVector3(n.x / length, n.y / length, n.z / length)
            let base = UInt32(vertices.count)
            vertices.append(contentsOf: [a, b, c])
            normals.append(contentsOf: [n, n, n])
            indices.append(contentsOf: [base, base + 1, base + 2])
        }
        let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices), SCNGeometrySource(normals: normals)],
                                   elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
        geometry.materials = [material(color)]
        return geometry
    }

    private static var materials: [UInt32: SCNMaterial] = [:]
    private static let lock = NSLock()

    static func material(_ color: UIColor) -> SCNMaterial {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        let key = UInt32(r * 255) << 16 | UInt32(g * 255) << 8 | UInt32(b * 255)
        lock.lock(); defer { lock.unlock() }
        if let hit = materials[key] { return hit }
        let m = SCNMaterial()
        m.lightingModel = .lambert
        m.diffuse.contents = color
        m.isDoubleSided = true
        materials[key] = m
        return m
    }

    /// A surface from a grid: `point(u, v)` with u and v from 0 to 1, `columns` by `rows` quads.
    static func grid(columns: Int, rows: Int, _ point: (Float, Float) -> SCNVector3) -> [(SCNVector3, SCNVector3, SCNVector3)] {
        var out: [(SCNVector3, SCNVector3, SCNVector3)] = []
        for row in 0..<rows {
            for column in 0..<columns {
                let u0 = Float(column) / Float(columns), u1 = Float(column + 1) / Float(columns)
                let v0 = Float(row) / Float(rows), v1 = Float(row + 1) / Float(rows)
                let a = point(u0, v0), b = point(u1, v0), c = point(u1, v1), d = point(u0, v1)
                out.append((a, d, c))
                out.append((a, c, b))
            }
        }
        return out
    }

    /// An ellipsoid, or part of one. `top` and `bottom` cut it from the north pole (0) to the south pole (1).
    /// `from` and `to` cut it around, with 0 facing the viewer (+z) and going toward +x.
    static func ellipsoid(_ rx: Float, _ ry: Float, _ rz: Float, segments: Int = 10, rings: Int = 7,
                          top: Float = 0, bottom: Float = 1, from: Float = 0, to: Float = 1,
                          color: UIColor) -> SCNNode {
        let around = max(3, Int((Float(segments) * (to - from)).rounded()))
        let down = max(1, Int((Float(rings) * (bottom - top)).rounded()))
        let tris = grid(columns: around, rows: down) { u, v in
            let theta = (top + (bottom - top) * v) * .pi
            let phi = (from + (to - from) * u) * 2 * .pi
            return SCNVector3(rx * sin(theta) * sin(phi), ry * cos(theta), rz * sin(theta) * cos(phi))
        }
        return SCNNode(geometry: geometry(tris, color: color))
    }

    static func sphere(_ r: Float, segments: Int = 8, rings: Int = 5, color: UIColor) -> SCNNode {
        ellipsoid(r, r, r, segments: segments, rings: rings, color: color)
    }

    /// A tube from y 0 to `height`, wider or narrower at either end, with flat caps. `rTop` 0 is a cone.
    static func frustum(bottom rb: Float, top rt: Float, height: Float, segments: Int = 8, depth: Float = 1,
                        caps: Bool = true, color: UIColor) -> SCNNode {
        var tris = grid(columns: segments, rows: 1) { u, v in
            let phi = u * 2 * .pi
            let r = rb + (rt - rb) * v
            return SCNVector3(r * sin(phi), height * v, r * depth * cos(phi))
        }
        if caps {
            for i in 0..<segments {
                let p0 = Float(i) / Float(segments) * 2 * .pi, p1 = Float(i + 1) / Float(segments) * 2 * .pi
                if rb > 0 {
                    tris.append((SCNVector3(0, 0, 0), SCNVector3(rb * sin(p1), 0, rb * depth * cos(p1)), SCNVector3(rb * sin(p0), 0, rb * depth * cos(p0))))
                }
                if rt > 0 {
                    tris.append((SCNVector3(0, height, 0), SCNVector3(rt * sin(p0), height, rt * depth * cos(p0)), SCNVector3(rt * sin(p1), height, rt * depth * cos(p1))))
                }
            }
        }
        return SCNNode(geometry: geometry(tris, color: color))
    }

    /// A ring lying flat in the x-z plane. `from` and `to` keep part of it, 0 facing the viewer.
    static func torus(ring R: Float, pipe r: Float, segments: Int = 14, sides: Int = 5, from: Float = 0, to: Float = 1,
                      color: UIColor) -> SCNNode {
        let around = max(3, Int((Float(segments) * (to - from)).rounded()))
        let tris = grid(columns: around, rows: sides) { u, v in
            let phi = (from + (to - from) * u) * 2 * .pi
            let theta = v * 2 * .pi
            let d = R + r * cos(theta)
            return SCNVector3(d * sin(phi), r * sin(theta), d * cos(phi))
        }
        return SCNNode(geometry: geometry(tris, color: color))
    }

    /// A box with bevelled edges cut at one angle.
    static func box(_ w: Float, _ h: Float, _ d: Float, bevel: Float = 0.2, color: UIColor) -> SCNNode {
        let shape = SCNBox(width: CGFloat(w), height: CGFloat(h), length: CGFloat(d),
                           chamferRadius: CGFloat(min(w, h, d) * bevel))
        shape.chamferSegmentCount = 1
        shape.materials = [material(color)]
        return SCNNode(geometry: shape)
    }

    /// A flat shape pushed out to `depth` along z, centred on z 0.
    static func prism(_ outline: [(Float, Float)], depth: Float, color: UIColor) -> SCNNode {
        var tris: [(SCNVector3, SCNVector3, SCNVector3)] = []
        let half = depth / 2
        var cx: Float = 0, cy: Float = 0
        for (x, y) in outline { cx += x; cy += y }
        cx /= Float(outline.count); cy /= Float(outline.count)
        for i in 0..<outline.count {
            let (x0, y0) = outline[i], (x1, y1) = outline[(i + 1) % outline.count]
            tris.append((SCNVector3(cx, cy, half), SCNVector3(x0, y0, half), SCNVector3(x1, y1, half)))
            tris.append((SCNVector3(cx, cy, -half), SCNVector3(x1, y1, -half), SCNVector3(x0, y0, -half)))
            tris.append((SCNVector3(x0, y0, half), SCNVector3(x0, y0, -half), SCNVector3(x1, y1, -half)))
            tris.append((SCNVector3(x0, y0, half), SCNVector3(x1, y1, -half), SCNVector3(x1, y1, half)))
        }
        return SCNNode(geometry: geometry(tris, color: color))
    }

    /// A star with `points` points, `r` across.
    static func star(_ r: Float, points: Int = 5, depth: Float = 0.04, color: UIColor) -> SCNNode {
        var outline: [(Float, Float)] = []
        for i in 0..<(points * 2) {
            let angle = Float(i) / Float(points * 2) * 2 * .pi + .pi / 2
            let radius = i % 2 == 0 ? r : r * 0.45
            outline.append((radius * cos(angle), radius * sin(angle)))
        }
        return prism(outline, depth: depth, color: color)
    }
}

extension SCNNode {
    @discardableResult
    func at(_ x: Float, _ y: Float, _ z: Float) -> SCNNode {
        position = SCNVector3(x, y, z)
        return self
    }

    @discardableResult
    func turned(x: Float = 0, y: Float = 0, z: Float = 0) -> SCNNode {
        eulerAngles = SCNVector3(x, y, z)
        return self
    }

    @discardableResult
    func named(_ name: String) -> SCNNode {
        self.name = name
        return self
    }

    @discardableResult
    func add(_ children: SCNNode...) -> SCNNode {
        for child in children { addChildNode(child) }
        return self
    }
}
