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
        
        // Create multiple emitter cells for maximum GPU stress - enhanced intensity
        var cells: [CAEmitterCell] = []
        for i in 0..<50 { // Doubled particle emitters
            let cell = CAEmitterCell()
            // Create colored particles with varying sizes
            let size = CGSize(width: CGFloat.random(in: 8...15), height: CGFloat.random(in: 8...15))
            let renderer = UIGraphicsImageRenderer(size: size)
            let image = renderer.image { ctx in
                let colors = [UIColor.red, UIColor.green, UIColor.blue, UIColor.yellow, UIColor.purple, UIColor.orange]
                colors[i % colors.count].setFill()
                ctx.cgContext.fillEllipse(in: CGRect(origin: .zero, size: size))
            }
            cell.contents = image.cgImage
            
            cell.birthRate = 300 // Tripled particle count for maximum GPU stress
            cell.lifetime = 12.0 // Longer lifetime for more particles on screen
            cell.velocity = CGFloat.random(in: 150...300)
            cell.velocityRange = 100
            cell.emissionLongitude = -CGFloat.pi/2
            cell.emissionRange = CGFloat.pi/3
            cell.scale = CGFloat.random(in: 0.5...1.5)
            cell.scaleRange = 0.5
            cell.scaleSpeed = CGFloat.random(in: -0.3...0.3)
            cell.alphaSpeed = -0.1
            cell.spin = CGFloat.random(in: -4...4)
            cell.spinRange = 2.0
            
            // Add complex particle behaviors
            cell.acceleration = CGPoint(x: CGFloat.random(in: -50...50), y: CGFloat.random(in: -50...50))
            cell.xAcceleration = CGFloat.random(in: -30...30)
            cell.yAcceleration = CGFloat.random(in: -30...30)
            
            cells.append(cell)
        }
        
        emitter.emitterCells = cells
        
        // Add multiple animated properties for maximum rendering stress
        let birthRateAnimation = CABasicAnimation(keyPath: "birthRate")
        birthRateAnimation.fromValue = 200
        birthRateAnimation.toValue = 400
        birthRateAnimation.duration = 1.5
        birthRateAnimation.autoreverses = true
        birthRateAnimation.repeatCount = .infinity
        emitter.add(birthRateAnimation, forKey: "birthRateAnimation")
        
        // Add position animation for moving particle source
        let positionAnimation = CABasicAnimation(keyPath: "emitterPosition")
        positionAnimation.fromValue = CGPoint(x: view.bounds.minX, y: view.bounds.midY)
        positionAnimation.toValue = CGPoint(x: view.bounds.maxX, y: view.bounds.midY)
        positionAnimation.duration = 3.0
        positionAnimation.autoreverses = true
        positionAnimation.repeatCount = .infinity
        emitter.add(positionAnimation, forKey: "positionAnimation")
        
        // Add size animation for dynamic emission area
        let sizeAnimation = CABasicAnimation(keyPath: "emitterSize")
        sizeAnimation.fromValue = CGSize(width: view.bounds.width * 0.5, height: 50)
        sizeAnimation.toValue = CGSize(width: view.bounds.width * 1.5, height: 100)
        sizeAnimation.duration = 2.0
        sizeAnimation.autoreverses = true
        sizeAnimation.repeatCount = .infinity
        emitter.add(sizeAnimation, forKey: "sizeAnimation")
        
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
