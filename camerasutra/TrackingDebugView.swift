import SceneKit
import SwiftUI
import simd

struct TrackingDebugView: UIViewRepresentable {
    let snapshot: TrackingSnapshot

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = context.coordinator.scene
        view.backgroundColor = .black
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = false
        context.coordinator.configureScene()
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        context.coordinator.update(snapshot)
    }

    final class Coordinator {
        let scene = SCNScene()
        private let cameraNode = SCNNode()
        private let solvedNode = SCNNode()
        private let predictedNode = SCNNode()
        private let trailNode = SCNNode()
        private let pointCloudNode = SCNNode()
        private let worldRoot = SCNNode()
        private let phoneRoot = SCNNode()
        private var lastPointCloudSignature: (count: Int, first: SIMD3<Float>?, last: SIMD3<Float>?) = (0, nil, nil)

        func configureScene() {
            scene.rootNode.addChildNode(worldRoot)

            let camera = SCNCamera()
            camera.zNear = 0.01
            camera.zFar = 100
            camera.fieldOfView = 60
            cameraNode.camera = camera
            cameraNode.position = SCNVector3(0, 1.4, 3.0)
            cameraNode.eulerAngles = SCNVector3(-0.35, 0, 0)
            scene.rootNode.addChildNode(cameraNode)

            let light = SCNLight()
            light.type = .omni
            light.intensity = 700
            let lightNode = SCNNode()
            lightNode.light = light
            lightNode.position = SCNVector3(0, 2.5, 2)
            scene.rootNode.addChildNode(lightNode)

            addGrid()
            addAxes()

            solvedNode.addChildNode(phoneRoot)
            phoneRoot.geometry = cameraGlyph(color: UIColor.systemGreen)
            addPhoneAxes()
            predictedNode.geometry = cameraGlyph(color: UIColor.systemOrange)
            worldRoot.addChildNode(solvedNode)
            worldRoot.addChildNode(predictedNode)
            worldRoot.addChildNode(trailNode)
            worldRoot.addChildNode(pointCloudNode)
        }

        func update(_ snapshot: TrackingSnapshot) {
            solvedNode.simdPosition = snapshot.position
            solvedNode.simdOrientation = snapshot.rotation
            predictedNode.simdPosition = snapshot.predictedPosition
            predictedNode.simdOrientation = snapshot.rotation

            solvedNode.opacity = 0.95
            predictedNode.opacity = snapshot.status == "Rotation only" ? 0 : 0.62
            rebuildTrail(snapshot.trail)
            rebuildPointCloud(snapshot.worldPoints)
        }

        private func addGrid() {
            let size: Float = 4
            let step: Float = 0.5
            for i in stride(from: -size, through: size, by: step) {
                addLine(from: SIMD3<Float>(-size, 0, i), to: SIMD3<Float>(size, 0, i), color: UIColor.white.withAlphaComponent(0.15))
                addLine(from: SIMD3<Float>(i, 0, -size), to: SIMD3<Float>(i, 0, size), color: UIColor.white.withAlphaComponent(0.15))
            }
        }

        private func addAxes() {
            addLine(from: .zero, to: SIMD3<Float>(0.7, 0, 0), color: .systemRed)
            addLine(from: .zero, to: SIMD3<Float>(0, 0.7, 0), color: .systemGreen)
            addLine(from: .zero, to: SIMD3<Float>(0, 0, 0.7), color: .systemBlue)
        }

        private func rebuildTrail(_ points: [SIMD3<Float>]) {
            trailNode.childNodes.forEach { $0.removeFromParentNode() }
            guard points.count >= 2 else { return }
            for index in 1..<points.count {
                addLine(from: points[index - 1], to: points[index], color: UIColor.systemCyan.withAlphaComponent(0.85), parent: trailNode)
            }
        }

        private func rebuildPointCloud(_ points: [SIMD3<Float>]) {
            let signature: (count: Int, first: SIMD3<Float>?, last: SIMD3<Float>?) = (points.count, points.first, points.last)
            guard signature.count != lastPointCloudSignature.count ||
                    signature.first != lastPointCloudSignature.first ||
                    signature.last != lastPointCloudSignature.last else {
                return
            }
            lastPointCloudSignature = signature

            guard !points.isEmpty else {
                pointCloudNode.geometry = nil
                return
            }

            let source = SCNGeometrySource(vertices: points.map(SCNVector3.init))
            let indices = points.indices.map(UInt32.init)
            let element = SCNGeometryElement(indices: indices, primitiveType: .point)
            element.pointSize = 4
            element.minimumPointScreenSpaceRadius = 1
            element.maximumPointScreenSpaceRadius = 6

            let geometry = SCNGeometry(sources: [source], elements: [element])
            let material = SCNMaterial()
            material.diffuse.contents = UIColor.systemTeal.withAlphaComponent(0.92)
            material.emission.contents = UIColor.systemTeal.withAlphaComponent(0.45)
            geometry.materials = [material]
            pointCloudNode.geometry = geometry
        }

        private func cameraGlyph(color: UIColor) -> SCNGeometry {
            let phone = SCNBox(width: 0.42, height: 0.82, length: 0.04, chamferRadius: 0.025)
            let front = SCNMaterial()
            front.diffuse.contents = UIColor(white: 0.08, alpha: 1)
            front.emission.contents = UIColor(white: 0.02, alpha: 1)

            let back = SCNMaterial()
            back.diffuse.contents = color
            back.emission.contents = color.withAlphaComponent(0.25)

            let side = SCNMaterial()
            side.diffuse.contents = UIColor(white: 0.22, alpha: 1)

            phone.materials = [side, side, side, side, front, back]
            return phone
        }

        private func addPhoneAxes() {
            addLine(from: .zero, to: SIMD3<Float>(0.34, 0, 0), color: .systemRed, parent: solvedNode)
            addLine(from: .zero, to: SIMD3<Float>(0, 0.54, 0), color: .systemGreen, parent: solvedNode)
            addLine(from: .zero, to: SIMD3<Float>(0, 0, 0.24), color: .systemBlue, parent: solvedNode)
        }

        private func addLine(from: SIMD3<Float>, to: SIMD3<Float>, color: UIColor, parent: SCNNode? = nil) {
            let source = SCNGeometrySource(vertices: [SCNVector3(from), SCNVector3(to)])
            let element = SCNGeometryElement(indices: [UInt32(0), UInt32(1)], primitiveType: .line)
            let geometry = SCNGeometry(sources: [source], elements: [element])
            geometry.firstMaterial?.diffuse.contents = color
            geometry.firstMaterial?.emission.contents = color
            let node = SCNNode(geometry: geometry)
            (parent ?? worldRoot).addChildNode(node)
        }
    }
}

private extension SCNVector3 {
    nonisolated init(_ v: SIMD3<Float>) {
        self.init(v.x, v.y, v.z)
    }
}
