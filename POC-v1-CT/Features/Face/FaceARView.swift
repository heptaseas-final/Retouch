//
//  FaceARView.swift
//  POC-v1-CT
//
//  Created by Davin P on 21/10/26.
//

import SwiftUI
import ARKit
import SceneKit

/// The AR filter. The outside world only decides WHAT to show:
///     FaceARView(shape: .oval, step: .contour)
/// Always shows: the dotted face-shape guide + the dotted outlines of the current step.
struct FaceARView: UIViewRepresentable {
    var shape: FaceShape
    var step: FaceARStep
    /// Green wireframe of the ARKit face mesh. Turn on while tuning outline positions.
    var showDebugMesh = false

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView(frame: .zero)
        let coordinator = context.coordinator
        coordinator.shape = shape
        coordinator.step = step
        coordinator.showDebugMesh = showDebugMesh
        view.delegate = coordinator

        guard ARFaceTrackingConfiguration.isSupported else {
            print("Face tracking is not supported on this device (needs TrueDepth camera, not the simulator).")
            return view
        }
        view.session.run(ARFaceTrackingConfiguration(),
                         options: [.resetTracking, .removeExistingAnchors])
        return view
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {
        context.coordinator.update(shape: shape, step: step)
    }

    static func dismantleUIView(_ uiView: ARSCNView, coordinator: Coordinator) {
        uiView.session.pause()
    }

    final class Coordinator: NSObject, ARSCNViewDelegate {
        var shape: FaceShape = .oval
        var step: FaceARStep = .contour
        var showDebugMesh = false

        private let dotsRoot = SCNNode()
        private var profile: FaceMeshProfile?

        override init() {
            super.init()
            // Neutral face mesh (no expression) just to measure the mesh size.
            if ARFaceTrackingConfiguration.isSupported,
               let geometry = ARFaceGeometry(blendShapes: [:]) {
                profile = FaceMeshProfile(vertices: geometry.vertices)
            }
        }

        func update(shape: FaceShape, step: FaceARStep) {
            guard shape != self.shape || step != self.step else { return }
            self.shape = shape
            self.step = step
            rebuildDots()
        }

        // MARK: ARSCNViewDelegate

        func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
            guard anchor is ARFaceAnchor else { return nil }
            let node = SCNNode()

            if showDebugMesh,
               let device = renderer.device,
               let mesh = ARSCNFaceGeometry(device: device) {
                mesh.firstMaterial?.fillMode = .lines
                mesh.firstMaterial?.diffuse.contents = UIColor.green
                node.geometry = mesh
            }

            node.addChildNode(dotsRoot)
            rebuildDots()
            return node
        }

        func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
            guard let face = anchor as? ARFaceAnchor else { return }
            node.isHidden = !face.isTracked   // hide dots when the face is lost
            if let mesh = node.geometry as? ARSCNFaceGeometry {
                mesh.update(from: face.geometry)
            }
        }

        // MARK: Dots

        private func rebuildDots() {
            guard let profile else { return }
            dotsRoot.childNodes.forEach { $0.removeFromParentNode() }

            addDots(FaceOutlineLibrary.guide(for: shape),
                    color: FaceOutlineLibrary.guideColor,
                    radius: 0.0022, profile: profile)
            addDots(FaceOutlineLibrary.outlines(for: step, shape: shape),
                    color: step.color,
                    radius: 0.0018, profile: profile)
        }

        private func addDots(_ paths: [OutlinePath], color: UIColor, radius: CGFloat, profile: FaceMeshProfile) {
            let geometry = SCNSphere(radius: radius)
            geometry.segmentCount = 8
            let material = SCNMaterial()
            material.lightingModel = .constant
            material.diffuse.contents = color
            geometry.materials = [material]

            for path in paths {
                // Convert to meters first so dot spacing is even (1 cm ~ 1 cm everywhere).
                let meters = path.points.map { profile.toMeters($0) }
                for xy in FaceOutlineLibrary.resample(meters, spacing: 0.009) {
                    let dot = SCNNode(geometry: geometry)
                    dot.position = profile.surfacePosition(atXY: xy)
                    dotsRoot.addChildNode(dot)
                }
            }
        }
    }
}

// MARK: - Face mesh helper

/// Uses ARKit's canonical face mesh to map normalized outline points onto the face surface.
struct FaceMeshProfile {
    private let vertices: [SIMD3<Float>]
    private let center: SIMD2<Float>
    private let half: SIMD2<Float>

    init?(vertices: [SIMD3<Float>]) {
        guard !vertices.isEmpty else { return nil }
        self.vertices = vertices
        let xs = vertices.map(\.x), ys = vertices.map(\.y)
        let minX = xs.min()!, maxX = xs.max()!
        let minY = ys.min()!, maxY = ys.max()!
        center = SIMD2<Float>((minX + maxX) / 2, (minY + maxY) / 2)
        half = SIMD2<Float>((maxX - minX) / 2, (maxY - minY) / 2)
    }

    /// Normalized (-1...1) -> meters in face-anchor space.
    func toMeters(_ p: SIMD2<Float>) -> SIMD2<Float> {
        center + p * half
    }

    /// Finds the mesh vertex closest in x/y and uses its depth, so dots sit on the face surface.
    func surfacePosition(atXY xy: SIMD2<Float>, lift: Float = 0.002) -> SCNVector3 {
        var bestZ = vertices[0].z
        var bestDistance = Float.greatestFiniteMagnitude
        for v in vertices {
            let d = simd_distance_squared(SIMD2<Float>(v.x, v.y), xy)
            if d < bestDistance {
                bestDistance = d
                bestZ = v.z
            }
        }
        return SCNVector3(xy.x, xy.y, bestZ + lift)
    }
}
