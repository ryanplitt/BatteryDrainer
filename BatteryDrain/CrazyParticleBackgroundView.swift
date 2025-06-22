import SwiftUI
import UIKit
// MARK: - IntenseAnimatedView
struct CrazyParticleBackgroundView: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .black // for contrast
        
        let emitter = CAEmitterLayer()
        emitter.frame = view.bounds
        emitter.emitterShape = .line
        emitter.emitterPosition = CGPoint(x: view.bounds.midX, y: view.bounds.maxY)
        emitter.emitterSize = CGSize(width: view.bounds.width, height: 1)
        
        // Create multiple emitter cells for a crazy effect
        var cells: [CAEmitterCell] = []
        for _ in 0..<10 {
            let cell = CAEmitterCell()
            // Create a white circle programmatically
            let size = CGSize(width: 10, height: 10)
            let renderer = UIGraphicsImageRenderer(size: size)
            let image = renderer.image { ctx in
                UIColor.white.setFill()
                ctx.cgContext.fillEllipse(in: CGRect(origin: .zero, size: size))
            }
            cell.contents = image.cgImage
            
            cell.birthRate = 50
            cell.lifetime = 5.0
            cell.velocity = CGFloat.random(in: 100...200)
            cell.velocityRange = 50
            cell.emissionLongitude = -CGFloat.pi/2
            cell.emissionRange = CGFloat.pi/4
            cell.scale = CGFloat.random(in: 0.1...0.2)
            cell.scaleRange = 0.1
            cell.alphaSpeed = -0.2
            cell.spin = CGFloat.random(in: -2...2)
            cells.append(cell)
        }
        
        emitter.emitterCells = cells
        
        // Optional: Animate the birth rate to add intensity
        let animation = CABasicAnimation(keyPath: "birthRate")
        animation.fromValue = 50
        animation.toValue = 100
        animation.duration = 2.0
        animation.autoreverses = true
        animation.repeatCount = .infinity
        emitter.add(animation, forKey: "birthRateAnimation")
        
        view.layer.addSublayer(emitter)
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        if let emitter = uiView.layer.sublayers?.first as? CAEmitterLayer {
            emitter.frame = uiView.bounds
            emitter.emitterPosition = CGPoint(x: uiView.bounds.midX, y: uiView.bounds.maxY)
            emitter.emitterSize = CGSize(width: uiView.bounds.width, height: 1)
        }
    }
}
