import SceneKit
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// A perspective SceneKit display whose XYZ axes carry left, right, and time.
final class Oscilloscope3DScene: ObservableObject {
    let scene = SCNScene()

    private let traceNode = SCNNode()
    private let traceMaterial = SCNMaterial()
    private let gridMaterial = SCNMaterial()

    init() {
        scene.background.contents = CGColor(gray: 0.025, alpha: 1)
        traceMaterial.lightingModel = .constant
        traceMaterial.diffuse.contents = Self.accentColor
        traceMaterial.emission.contents = Self.accentColor
        gridMaterial.lightingModel = .constant
        gridMaterial.diffuse.contents = platformGridColor

        let root = scene.rootNode
        root.addChildNode(makeGrid())
        root.addChildNode(traceNode)

        let camera = SCNCamera()
        camera.fieldOfView = 48
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(2.5, 2.0, 3.6)
        cameraNode.look(at: SCNVector3Zero)
        root.addChildNode(cameraNode)

        let light = SCNNode()
        light.light = SCNLight()
        light.light?.type = .ambient
        light.light?.intensity = 500
        root.addChildNode(light)
    }

    func update(left: [Float], right: [Float]) {
        let count = min(left.count, right.count, 256)
        guard count > 1 else { return }

        let stride = max(1, min(left.count, right.count) / count)
        var vertices: [SCNVector3] = []
        vertices.reserveCapacity(count)
        for index in 0..<count {
            let sampleIndex = min(index * stride, min(left.count, right.count) - 1)
            let x = max(-1, min(1, left[sampleIndex]))
            let y = max(-1, min(1, right[sampleIndex]))
            let z = Float(index) / Float(count - 1) * 2 - 1
            vertices.append(SCNVector3(x, y, z))
        }

        var indices: [Int32] = []
        indices.reserveCapacity((vertices.count - 1) * 2)
        for index in 0..<(vertices.count - 1) {
            indices.append(Int32(index))
            indices.append(Int32(index + 1))
        }
        let source = SCNGeometrySource(vertices: vertices)
        let segments = SCNGeometryElement(indices: indices, primitiveType: .line)
        let geometry = SCNGeometry(sources: [source], elements: [segments])
        geometry.materials = [traceMaterial]
        traceNode.geometry = geometry
    }

    private func makeGrid() -> SCNNode {
        var vertices: [SCNVector3] = []
        var indices: [Int32] = []
        func line(_ start: SCNVector3, _ end: SCNVector3) {
            indices.append(Int32(vertices.count))
            vertices.append(start)
            indices.append(Int32(vertices.count))
            vertices.append(end)
        }

        for step in -4...4 {
            let v = Float(step) / 4
            line(SCNVector3(v, -1, 0), SCNVector3(v, 1, 0))
            line(SCNVector3(-1, v, 0), SCNVector3(1, v, 0))
            line(SCNVector3(v, 0, -1), SCNVector3(v, 0, 1))
            line(SCNVector3(-1, 0, v), SCNVector3(1, 0, v))
            line(SCNVector3(0, v, -1), SCNVector3(0, v, 1))
            line(SCNVector3(0, -1, v), SCNVector3(0, 1, v))
        }
        let geometry = SCNGeometry(
            sources: [SCNGeometrySource(vertices: vertices)],
            elements: [SCNGeometryElement(indices: indices, primitiveType: .line)]
        )
        geometry.materials = [gridMaterial]
        return SCNNode(geometry: geometry)
    }

    private static var accentColor: Any {
#if os(macOS)
        NSColor.systemPurple
#else
        UIColor.systemPurple
#endif
    }

    private var platformGridColor: Any {
#if os(macOS)
        NSColor.white.withAlphaComponent(0.15)
#else
        UIColor.white.withAlphaComponent(0.15)
#endif
    }
}

#if os(macOS)
struct OscilloscopeSceneHost: NSViewRepresentable {
    let scene: SCNScene

    func makeNSView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = scene
        view.allowsCameraControl = true
        view.preferredFramesPerSecond = 120
        view.backgroundColor = .black
        return view
    }

    func updateNSView(_ view: SCNView, context: Context) {
        if view.scene !== scene { view.scene = scene }
    }
}
#else
struct OscilloscopeSceneHost: UIViewRepresentable {
    let scene: SCNScene

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = scene
        view.allowsCameraControl = true
        view.preferredFramesPerSecond = 120
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        if view.scene !== scene { view.scene = scene }
    }
}
#endif
