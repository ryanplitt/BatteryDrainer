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
        
        // 2. Run multiple tracking modes simultaneously for maximum CPU/GPU load
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]
        
        // Enable all available frame semantics for maximum processing
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            configuration.frameSemantics.insert(.sceneDepth)
        }
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
            configuration.frameSemantics.insert(.smoothedSceneDepth)
        }
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.personSegmentation) {
            configuration.frameSemantics.insert(.personSegmentation)
        }
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.personSegmentationWithDepth) {
            configuration.frameSemantics.insert(.personSegmentationWithDepth)
        }
        
        configuration.environmentTexturing = .automatic
        configuration.wantsHDREnvironmentTextures = true
        
        // Enable maximum quality settings for more processing load
        configuration.videoFormat = ARWorldTrackingConfiguration.supportedVideoFormats.last ?? ARWorldTrackingConfiguration.supportedVideoFormats.first!
        
        arView.session.run(configuration)
        
        // 3. Add massive number of objects for maximum GPU stress (1000+ as specified)
        let scene = SCNScene()
        
        // Add particle system for maximum visual stress
        let particleSystem = SCNParticleSystem()
        particleSystem.particleImage = UIImage(systemName: "sparkle")
        particleSystem.birthRate = 1000
        particleSystem.particleLifeSpan = 10.0
        particleSystem.particleVelocity = 50
        particleSystem.particleVelocityVariation = 20
        particleSystem.emissionDuration = 0
        particleSystem.particleSize = 0.02
        particleSystem.particleSizeVariation = 0.01
        
        let particleNode = SCNNode()
        particleNode.addParticleSystem(particleSystem)
        scene.rootNode.addChildNode(particleNode)
        
        // Dramatically increase object count from 200 to 1200 for maximum stress
        for i in 0..<1200 {
        for i in 0..<1200 {
            // Use more complex geometries for increased GPU load
            let geometry: SCNGeometry
            let shapeType = i % 5
            
            switch shapeType {
            case 0:
                geometry = SCNBox(width: 0.1, height: 0.1, length: 0.1, chamferRadius: 0.02)
            case 1:
                geometry = SCNSphere(radius: 0.05)
            case 2:
                geometry = SCNCylinder(radius: 0.05, height: 0.1)
            case 3:
                geometry = SCNCone(topRadius: 0.02, bottomRadius: 0.08, height: 0.1)
            default:
                geometry = SCNTorus(ringRadius: 0.06, pipeRadius: 0.02)
            }
            
            // Create complex materials with multiple textures and effects
            let material = SCNMaterial()
            material.diffuse.contents = UIColor(hue: CGFloat(i)/300.0, saturation: 1, brightness: 1, alpha: 1)
            material.specular.contents = UIColor.white
            material.shininess = 0.8
            material.metalness.contents = 0.5
            material.roughness.contents = 0.3
            material.lightingModel = .physicallyBased
            
            // Add normal map for additional GPU complexity
            if i % 3 == 0 {
                material.normal.intensity = 2.0
            }
            
            geometry.materials = [material]
            
            let node = SCNNode(geometry: geometry)
            // Position objects in larger 3D space for more complex scene
            node.position = SCNVector3(
                Float.random(in: -2...2),
                Float.random(in: -2...2),
                Float.random(in: -2...2)
            )
            
            // Add physics bodies for collision detection (additional CPU load)
            if i % 10 == 0 {
                node.physicsBody = SCNPhysicsBody(type: .dynamic, shape: nil)
                node.physicsBody?.mass = 0.1
                node.physicsBody?.restitution = 0.8
            }
            
            // Multiple intensive animations running simultaneously
            let spin = CABasicAnimation(keyPath: "rotation")
            spin.fromValue = SCNVector4(Float.random(in: 0...1), Float.random(in: 0...1), Float.random(in: 0...1), 0)
            spin.toValue = SCNVector4(Float.random(in: 0...1), Float.random(in: 0...1), Float.random(in: 0...1), Float.pi*2)
            spin.duration = Double.random(in: 1...4) // Faster animations
            spin.repeatCount = .infinity
            node.addAnimation(spin, forKey: "spin")
            
            // Add scale animation with more complexity
            let scale = CABasicAnimation(keyPath: "scale")
            scale.fromValue = SCNVector3(0.8, 0.8, 0.8)
            scale.toValue = SCNVector3(1.8, 1.8, 1.8)
            scale.duration = Double.random(in: 0.5...2.0) // Faster scaling
            scale.autoreverses = true
            scale.repeatCount = .infinity
            node.addAnimation(scale, forKey: "scale")
            
            // Add complex position animation with curved paths
            let position = CAKeyframeAnimation(keyPath: "position")
            position.values = [
                node.position,
                SCNVector3(node.position.x + Float.random(in: -1...1), 
                          node.position.y + Float.random(in: -1...1), 
                          node.position.z + Float.random(in: -0.5...0.5)),
                SCNVector3(node.position.x + Float.random(in: -1.5...1.5), 
                          node.position.y + Float.random(in: -1.5...1.5), 
                          node.position.z + Float.random(in: -0.8...0.8)),
                node.position
            ]
            position.duration = Double.random(in: 2...6)
            position.repeatCount = .infinity
            node.addAnimation(position, forKey: "position")
            
            // Add rotation animation around different axes
            if i % 3 == 0 {
                let complexRotation = CABasicAnimation(keyPath: "eulerAngles")
                complexRotation.fromValue = SCNVector3(0, 0, 0)
                complexRotation.toValue = SCNVector3(Float.pi * 2, Float.pi * 2, Float.pi * 2)
                complexRotation.duration = Double.random(in: 3...8)
                complexRotation.repeatCount = .infinity
                node.addAnimation(complexRotation, forKey: "complexRotation")
            }
            
            scene.rootNode.addChildNode(node)
        }
        
        // Add physics world for collision simulation (additional CPU load)
        scene.physicsWorld.gravity = SCNVector3(0, -9.8, 0)
        scene.physicsWorld.speed = 2.0 // Faster physics simulation
        
        // Add lighting for more realistic rendering (additional GPU load)
        let lightNode = SCNNode()
        lightNode.light = SCNLight()
        lightNode.light!.type = .omni
        lightNode.light!.intensity = 2000
        lightNode.position = SCNVector3(0, 2, 0)
        scene.rootNode.addChildNode(lightNode)
        
        // Add environment lighting
        let ambientLight = SCNNode()
        ambientLight.light = SCNLight()
        ambientLight.light!.type = .ambient
        ambientLight.light!.intensity = 500
        scene.rootNode.addChildNode(ambientLight)
        
        arView.scene = scene
        
        return arView
    }
    
    func updateUIView(_ uiView: ARSCNView, context: Context) {
        uiView.preferredFramesPerSecond = 120
        uiView.contentScaleFactor = UIScreen.main.scale * 2
        // No need to reconfigure scene here
    }
}
