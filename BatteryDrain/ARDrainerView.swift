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
        
        // 3. Add a bunch of rotating cubes for constant geometry/workload
        let scene = SCNScene()
        for i in 0..<100 {
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
            // Continuous rotation
            let spin = CABasicAnimation(keyPath: "rotation")
            spin.fromValue = SCNVector4(0,1,0,0)
            spin.toValue   = SCNVector4(0,1,0,Float.pi*2)
            spin.duration  = 4
            spin.repeatCount = .infinity
            node.addAnimation(spin, forKey: "spin")
            
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
