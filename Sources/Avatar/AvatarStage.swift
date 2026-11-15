import SwiftUI
import SceneKit
import UIKit

// The 3D Dailie: the voxel grid as one mesh in SceneKit, standing on a small stage. Drag to turn it
// all the way round, drag up and down to move the camera, pinch to zoom. It idles with a slow squash,
// blinks, and pops with sparkles when it puts something on.

enum VoxelMesh {
    private static let faces: [(normal: (Int, Int, Int), corners: [(Float, Float, Float)])] = [
        ((1, 0, 0), [(1, 0, 0), (1, 1, 0), (1, 1, 1), (1, 0, 1)]),
        ((-1, 0, 0), [(0, 0, 0), (0, 0, 1), (0, 1, 1), (0, 1, 0)]),
        ((0, 1, 0), [(0, 1, 0), (0, 1, 1), (1, 1, 1), (1, 1, 0)]),
        ((0, -1, 0), [(0, 0, 0), (1, 0, 0), (1, 0, 1), (0, 0, 1)]),
        ((0, 0, 1), [(0, 0, 1), (1, 0, 1), (1, 1, 1), (0, 1, 1)]),
        ((0, 0, -1), [(0, 0, 0), (0, 1, 0), (1, 1, 0), (1, 0, 0)]),
    ]

    /// The middle of the Dailie's footprint, in voxels. The mesh is moved so this sits at the origin.
    static let center = (x: Float(8), z: Float(6))

    private static func linear(_ byte: UInt8) -> Float {
        let c = Float(byte) / 255
        return c <= 0.04045 ? c / 12.92 : powf((c + 0.055) / 1.055, 2.4)
    }

    /// The coloured mesh, and an ink shell a little larger with its front faces culled, which shows as an outline.
    static func build(_ grid: VoxelGrid, outline: Float = 0.16) -> (body: SCNGeometry, shell: SCNGeometry) {
        var vertices: [SCNVector3] = [], normals: [SCNVector3] = [], colors: [Float] = [], indices: [UInt32] = []
        var shellVertices: [SCNVector3] = [], shellIndices: [UInt32] = []
        vertices.reserveCapacity(grid.cells.count * 8)
        for (p, cell) in grid.cells {
            let r = linear(cell.color.r), g = linear(cell.color.g), b = linear(cell.color.b)
            let ox = Float(p.x) - center.x, oy = Float(p.y), oz = Float(p.z) - center.z
            for face in faces {
                let (nx, ny, nz) = face.normal
                if grid.has(p.x + nx, p.y + ny, p.z + nz) { continue }
                let base = UInt32(vertices.count)
                let normal = SCNVector3(Float(nx), Float(ny), Float(nz))
                for (cx, cy, cz) in face.corners {
                    vertices.append(SCNVector3(ox + cx, oy + cy, oz + cz))
                    normals.append(normal)
                    colors.append(contentsOf: [r, g, b])
                    let grow: (Float) -> Float = { $0 == 0 ? -outline : 1 + outline }
                    shellVertices.append(SCNVector3(ox + grow(cx), oy + grow(cy), oz + grow(cz)))
                }
                indices.append(contentsOf: [base, base + 1, base + 2, base, base + 2, base + 3])
                shellIndices.append(contentsOf: [base, base + 1, base + 2, base, base + 2, base + 3])
            }
        }
        let colorData = colors.withUnsafeBufferPointer { Data(buffer: $0) }
        let colorSource = SCNGeometrySource(data: colorData, semantic: .color, vectorCount: vertices.count,
                                            usesFloatComponents: true, componentsPerVector: 3,
                                            bytesPerComponent: MemoryLayout<Float>.size, dataOffset: 0,
                                            dataStride: MemoryLayout<Float>.size * 3)
        let body = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices), SCNGeometrySource(normals: normals), colorSource],
                               elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
        let skin = SCNMaterial()
        skin.lightingModel = .lambert
        skin.diffuse.contents = UIColor.white
        body.materials = [skin]

        let shell = SCNGeometry(sources: [SCNGeometrySource(vertices: shellVertices)],
                                elements: [SCNGeometryElement(indices: shellIndices, primitiveType: .triangles)])
        let ink = SCNMaterial()
        ink.lightingModel = .constant
        ink.diffuse.contents = UIColor(red: 0.082, green: 0.078, blue: 0.071, alpha: 1)
        ink.cullMode = .front
        shell.materials = [ink]
        return (body, shell)
    }
}

/// How much of the stage the player can move.
enum AvatarStageControl {
    /// Turn, camera height and zoom: the Shop.
    case full
    /// Only sideways drags turn the Dailie, so the page around it still scrolls: the Profile.
    case turnOnly
}

struct AvatarStage: UIViewRepresentable {
    var look: AvatarLook
    var shirt: VoxelColor = VoxelPalette.purple
    var control: AvatarStageControl = .full
    /// Starting distance of the camera, in metres of a Dailie about 2.6 tall.
    var distance: Float = 7.4
    /// Goes up to turn the Dailie to show its back, or front again.
    var turnRequest: Int = 0
    var onTap: (() -> Void)? = nil

    func makeCoordinator() -> AvatarStageCoordinator {
        AvatarStageCoordinator(control: control, distance: distance)
    }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.backgroundColor = .clear
        view.isOpaque = false
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 60
        view.scene = context.coordinator.scene
        view.pointOfView = context.coordinator.cameraNode
        view.isPlaying = true
        context.coordinator.attach(to: view)
        context.coordinator.onTap = onTap
        context.coordinator.show(look, shirt: shirt)
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        context.coordinator.onTap = onTap
        context.coordinator.show(look, shirt: shirt)
        context.coordinator.turn(to: turnRequest)
    }

    static func dismantleUIView(_ view: SCNView, coordinator: AvatarStageCoordinator) {
        view.isPlaying = false
        view.scene = nil
    }
}

final class AvatarStageCoordinator: NSObject, UIGestureRecognizerDelegate {
    let scene = SCNScene()
    let cameraNode = SCNNode()
    var onTap: (() -> Void)?

    private let control: AvatarStageControl
    private let turntable = SCNNode()
    private let hopper = SCNNode()
    private let model = SCNNode()
    private let shellNode = SCNNode()
    private let target = SCNNode()
    private var shown: (look: AvatarLook, shirt: VoxelColor)?
    private var openMesh: (SCNGeometry, SCNGeometry)?
    private var closedMesh: (SCNGeometry, SCNGeometry)?
    private var yaw: Float = 0
    private var height: Float = 1.5
    private var distance: Float
    private var pinchStart: Float = 7.4
    private var lastTurnRequest = 0
    private var touching = false

    /// One voxel is this many scene units.
    private let voxel: Float = 0.1

    init(control: AvatarStageControl, distance: Float) {
        self.control = control
        self.distance = distance
        super.init()
        scene.background.contents = UIColor.clear

        // stage: a dark disc with a gold rim and a soft shadow
        let disc = SCNCylinder(radius: 1.25, height: 0.14)
        let discMaterial = SCNMaterial()
        discMaterial.lightingModel = .lambert
        discMaterial.diffuse.contents = UIColor(red: 0.17, green: 0.15, blue: 0.13, alpha: 1)
        disc.materials = [discMaterial]
        let discNode = SCNNode(geometry: disc)
        discNode.position = SCNVector3(0, -0.07, 0)
        scene.rootNode.addChildNode(discNode)

        let rim = SCNTube(innerRadius: 1.22, outerRadius: 1.3, height: 0.15)
        let rimMaterial = SCNMaterial()
        rimMaterial.lightingModel = .constant
        rimMaterial.diffuse.contents = UIColor(red: 1, green: 0.773, blue: 0.192, alpha: 1)
        rim.materials = [rimMaterial]
        let rimNode = SCNNode(geometry: rim)
        rimNode.position = SCNVector3(0, -0.07, 0)
        scene.rootNode.addChildNode(rimNode)

        let shadow = SCNPlane(width: 1.9, height: 1.9)
        let shadowMaterial = SCNMaterial()
        shadowMaterial.lightingModel = .constant
        shadowMaterial.diffuse.contents = Self.shadowImage()
        shadowMaterial.writesToDepthBuffer = false
        shadow.materials = [shadowMaterial]
        let shadowNode = SCNNode(geometry: shadow)
        shadowNode.eulerAngles.x = -.pi / 2
        shadowNode.position = SCNVector3(0, 0.004, 0)
        scene.rootNode.addChildNode(shadowNode)

        // the Dailie: turntable (drag) > hopper (pops and jumps) > model (idle squash)
        scene.rootNode.addChildNode(turntable)
        turntable.addChildNode(hopper)
        hopper.addChildNode(model)
        model.scale = SCNVector3(voxel, voxel, voxel)
        model.addChildNode(shellNode)
        model.runAction(.repeatForever(.customAction(duration: 1.6) { node, elapsed in
            let wave = Float(sin(Double(elapsed) / 1.6 * 2 * .pi))
            let squash = 0.018 * wave
            node.scale = SCNVector3(0.1 * (1 + squash * 0.6), 0.1 * (1 - squash), 0.1 * (1 + squash * 0.6))
        }), forKey: "idle")

        // lights: soft fill, a warm key from the front and a gold rim from behind
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 520
        ambient.light?.color = UIColor(white: 1, alpha: 1)
        scene.rootNode.addChildNode(ambient)

        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.intensity = 620
        key.light?.color = UIColor(red: 1, green: 0.97, blue: 0.92, alpha: 1)
        key.eulerAngles = SCNVector3(-0.6, -0.45, 0)
        scene.rootNode.addChildNode(key)

        let back = SCNNode()
        back.light = SCNLight()
        back.light?.type = .directional
        back.light?.intensity = 380
        back.light?.color = UIColor(red: 1, green: 0.8, blue: 0.4, alpha: 1)
        back.eulerAngles = SCNVector3(-0.3, .pi * 0.85, 0)
        scene.rootNode.addChildNode(back)

        // camera: always looks at the middle of the Dailie
        target.position = SCNVector3(0, 1.25, 0)
        scene.rootNode.addChildNode(target)
        let camera = SCNCamera()
        camera.fieldOfView = 30
        camera.zNear = 0.1
        camera.zFar = 100
        cameraNode.camera = camera
        let look = SCNLookAtConstraint(target: target)
        look.isGimbalLockEnabled = true
        cameraNode.constraints = [look]
        scene.rootNode.addChildNode(cameraNode)
        placeCamera()

        if control == .turnOnly {
            turntable.runAction(.repeatForever(.sequence([
                .rotateTo(x: 0, y: 0.35, z: 0, duration: 2.6, usesShortestUnitArc: true),
                .rotateTo(x: 0, y: -0.35, z: 0, duration: 2.6, usesShortestUnitArc: true),
            ])), forKey: "sway")
        }
        scheduleBlink()
    }

    func attach(to view: SCNView) {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
        pan.delegate = self
        view.addGestureRecognizer(pan)
        if control == .full {
            view.addGestureRecognizer(UIPinchGestureRecognizer(target: self, action: #selector(pinched(_:))))
        }
        view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
    }

    /// Shows a look. A change after the first one pops the Dailie with sparkles.
    func show(_ look: AvatarLook, shirt: VoxelColor) {
        if let shown, shown.look == look, shown.shirt == shirt { return }
        let first = shown == nil
        shown = (look, shirt)
        let openGrid = VoxelAvatar.build(look, shirt: shirt)
        let built = VoxelMesh.build(openGrid)
        let blink = VoxelMesh.build(VoxelAvatar.build(look, shirt: shirt, blink: true))
        openMesh = (built.body, built.shell)
        closedMesh = (blink.body, blink.shell)
        model.geometry = built.body
        shellNode.geometry = built.shell
        if !first { pop() }
    }

    func turn(to request: Int) {
        guard request != lastTurnRequest else { return }
        lastTurnRequest = request
        turntable.removeAction(forKey: "sway")
        yaw += .pi
        let spin = SCNAction.rotateTo(x: 0, y: CGFloat(yaw), z: 0, duration: 0.7, usesShortestUnitArc: false)
        spin.timingMode = .easeInEaseOut
        turntable.runAction(spin, forKey: "spin")
    }

    private func scheduleBlink() {
        model.runAction(.repeatForever(.sequence([
            .wait(duration: 4, withRange: 2),
            .run { [weak self] _ in self?.setEyes(open: false) },
            .wait(duration: 0.13),
            .run { [weak self] _ in self?.setEyes(open: true) },
        ])), forKey: "blink")
    }

    private func setEyes(open isOpen: Bool) {
        guard let pair = isOpen ? openMesh : closedMesh else { return }
        model.geometry = pair.0
        shellNode.geometry = pair.1
    }

    private func pop() {
        hopper.removeAction(forKey: "pop")
        let up = SCNAction.scale(to: 1.14, duration: 0.11)
        up.timingMode = .easeOut
        let down = SCNAction.scale(to: 0.96, duration: 0.12)
        down.timingMode = .easeInEaseOut
        let settle = SCNAction.scale(to: 1, duration: 0.16)
        settle.timingMode = .easeOut
        hopper.runAction(.sequence([up, down, settle]), forKey: "pop")
        sparkle()
    }

    /// Six little gold voxels that burst out around the Dailie and fade.
    private func sparkle() {
        for index in 0..<6 {
            let angle = Float(index) / 6 * 2 * .pi + yaw
            let box = SCNBox(width: 0.12, height: 0.12, length: 0.12, chamferRadius: 0)
            let material = SCNMaterial()
            material.lightingModel = .constant
            material.diffuse.contents = index % 2 == 0 ? UIColor(red: 1, green: 0.773, blue: 0.192, alpha: 1) : UIColor.white
            box.materials = [material]
            let node = SCNNode(geometry: box)
            let height: Float = 1.2 + Float(index % 3) * 0.45
            node.position = SCNVector3(cos(angle) * 0.6, height, sin(angle) * 0.6)
            scene.rootNode.addChildNode(node)
            let move = SCNAction.move(by: SCNVector3(cos(angle) * 0.7, 0.35, sin(angle) * 0.7), duration: 0.6)
            move.timingMode = .easeOut
            node.runAction(.sequence([
                .group([move, .fadeOut(duration: 0.6), .rotateBy(x: 1.5, y: 2, z: 0, duration: 0.6)]),
                .removeFromParentNode(),
            ]))
        }
    }

    private func placeCamera() {
        cameraNode.position = SCNVector3(0, height, distance)
        target.position = SCNVector3(0, 0.9 + height * 0.22, 0)
    }

    @objc private func panned(_ pan: UIPanGestureRecognizer) {
        guard let view = pan.view else { return }
        let delta = pan.translation(in: view)
        pan.setTranslation(.zero, in: view)
        switch pan.state {
        case .began:
            turntable.removeAction(forKey: "sway")
            turntable.removeAction(forKey: "spin")
            yaw = turntable.eulerAngles.y
        case .changed:
            yaw += Float(delta.x) * 0.012
            turntable.eulerAngles.y = yaw
            if control == .full {
                height = min(4.2, max(0.15, height - Float(delta.y) * 0.012))
                placeCamera()
            }
        case .ended, .cancelled:
            // A flick keeps turning for a moment.
            let fling = Float(pan.velocity(in: view).x) * 0.0016
            yaw += fling
            let coast = SCNAction.rotateTo(x: 0, y: CGFloat(yaw), z: 0, duration: 0.7, usesShortestUnitArc: false)
            coast.timingMode = .easeOut
            turntable.runAction(coast, forKey: "spin")
        default:
            break
        }
    }

    @objc private func pinched(_ pinch: UIPinchGestureRecognizer) {
        if pinch.state == .began { pinchStart = distance }
        distance = min(11, max(3.6, pinchStart / Float(max(0.2, pinch.scale))))
        placeCamera()
    }

    @objc private func tapped() {
        let up = SCNAction.moveBy(x: 0, y: 0.45, z: 0, duration: 0.18)
        up.timingMode = .easeOut
        let down = SCNAction.moveBy(x: 0, y: -0.45, z: 0, duration: 0.2)
        down.timingMode = .easeIn
        if hopper.action(forKey: "jump") == nil {
            hopper.runAction(.sequence([up, down]), forKey: "jump")
        }
        onTap?()
    }

    func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
        guard control == .turnOnly, let pan = gesture as? UIPanGestureRecognizer, let view = pan.view else { return true }
        let velocity = pan.velocity(in: view)
        return abs(velocity.x) > abs(velocity.y)
    }

    private static func shadowImage() -> UIImage {
        let size = CGSize(width: 128, height: 128)
        return UIGraphicsImageRenderer(size: size).image { context in
            let colors = [UIColor(white: 0, alpha: 0.55).cgColor, UIColor(white: 0, alpha: 0).cgColor] as CFArray
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) else { return }
            context.cgContext.drawRadialGradient(gradient, startCenter: CGPoint(x: 64, y: 64), startRadius: 0,
                                                 endCenter: CGPoint(x: 64, y: 64), endRadius: 64, options: [])
        }
    }
}
