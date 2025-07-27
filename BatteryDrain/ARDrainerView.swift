import SwiftUI
import ARKit


// MARK: - ARDrainerView
struct ARDrainerView: UIViewRepresentable {
    func makeUIView(context: Context) -> ARSCNView {
        // Create and configure ARSCNView
        let arView = ARSCNView(frame: .zero)
        // 1. Configure high performance rendering
        arView.preferredFramesPerSecond = 120
        arView.contentScaleFactor = UIScreen.main.scale * 2
        arView.antialiasingMode = .multisampling4X
        arView.rendersContinuously = true
        
        // 2. Run world-tracking with environment texturing for extra GPU work
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            configuration.frameSemantics.insert(.sceneDepth)
        }
        configuration.environmentTexturing = .automatic
        arView.session.run(configuration)
        
        // 3. Add more rotating cubes for constant geometry/workload - increased for more GPU stress
        let scene = SCNScene()
        for i in 0..<200 {
            let box = SCNBox(width: 0.1, height: 0.1, length: 0.1, chamferRadius: 0)
            let material = SCNMaterial()
            material.diffuse.contents = UIColor(hue: CGFloat(i)/50.0, saturation: 1, brightness: 1, alpha: 1)
            box.materials = [material]
            
            let node = SCNNode(geometry: box)
            // Position cubes randomly around camera
            node.position = SCNVector3(
                Float.random(in: -1...1),
                Float.random(in: -1...1),
                Float.random(in: -1...1) - 0.5
            )
            // Multiple continuous animations for more GPU load
            let spin = CABasicAnimation(keyPath: "rotation")
            spin.fromValue = SCNVector4(0,1,0,0)
            spin.toValue   = SCNVector4(0,1,0,Float.pi*2)
            spin.duration  = Double.random(in: 2...6) // Varied speeds
            spin.repeatCount = .infinity
            node.addAnimation(spin, forKey: "spin")
            
            // Add scale animation
            let scale = CABasicAnimation(keyPath: "scale")
            scale.fromValue = SCNVector3(1, 1, 1)
            scale.toValue = SCNVector3(1.5, 1.5, 1.5)
            scale.duration = Double.random(in: 1...3)
            scale.autoreverses = true
            scale.repeatCount = .infinity
            node.addAnimation(scale, forKey: "scale")
            
            // Add position animation
            let position = CABasicAnimation(keyPath: "position")
            position.fromValue = node.position
            position.toValue = SCNVector3(
                node.position.x + Float.random(in: -0.5...0.5),
                node.position.y + Float.random(in: -0.5...0.5),
                node.position.z + Float.random(in: -0.2...0.2)
            )
            position.duration = Double.random(in: 3...8)
            position.autoreverses = true
            position.repeatCount = .infinity
            node.addAnimation(position, forKey: "position")
            
            scene.rootNode.addChildNode(node)
        }
        arView.scene = scene
        
        return arView
    }
    
    func updateUIView(_ uiView: ARSCNView, context: Context) {
        uiView.preferredFramesPerSecond = 120
        uiView.contentScaleFactor = UIScreen.main.scale * 2
        // No need to reconfigure scene here
    }
}
