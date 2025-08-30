import SwiftUI
import UIKit

// MARK: - Display and Visual Stress View
struct DisplayStressView: UIViewRepresentable {
    func makeUIView(context: Context) -> DisplayStressUIView {
        DisplayStressUIView()
    }
    
    func updateUIView(_ uiView: DisplayStressUIView, context: Context) {
        // Trigger continuous updates for maximum refresh rate utilization
        uiView.setNeedsDisplay()
    }
}

class DisplayStressUIView: UIView {
    private var displayLink: CADisplayLink?
    private var animationLayers: [CALayer] = []
    private var frameCounter: Int = 0
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupDisplayStress()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupDisplayStress()
    }
    
    private func setupDisplayStress() {
        backgroundColor = .black
        
        // Create multiple animated layers for maximum rendering stress
        createAnimatedLayers()
        
        // Setup display link for 120Hz ProMotion utilization
        displayLink = CADisplayLink(target: self, selector: #selector(displayLinkUpdate))
        if #available(iOS 15.0, *) {
            displayLink?.preferredFrameRateRange = CAFrameRateRange(minimum: 120, maximum: 120, preferred: 120)
        } else {
            displayLink?.preferredFramesPerSecond = 120
        }
        displayLink?.add(to: .main, forMode: .default)
    }
    
    private func createAnimatedLayers() {
        // Create 50 complex animated layers for maximum GPU stress
        for i in 0..<50 {
            let layer = CALayer()
            layer.backgroundColor = UIColor(hue: CGFloat(i) / 50.0, saturation: 1.0, brightness: 1.0, alpha: 0.8).cgColor
            layer.cornerRadius = CGFloat.random(in: 5...20)
            layer.frame = CGRect(x: CGFloat.random(in: 0...300), 
                               y: CGFloat.random(in: 0...600), 
                               width: CGFloat.random(in: 20...80), 
                               height: CGFloat.random(in: 20...80))
            
            // Add complex transform animations
            let positionAnimation = CABasicAnimation(keyPath: "position")
            positionAnimation.fromValue = layer.position
            positionAnimation.toValue = CGPoint(x: CGFloat.random(in: 0...400), y: CGFloat.random(in: 0...800))
            positionAnimation.duration = Double.random(in: 1...3)
            positionAnimation.autoreverses = true
            positionAnimation.repeatCount = .infinity
            layer.add(positionAnimation, forKey: "position")
            
            let scaleAnimation = CABasicAnimation(keyPath: "transform.scale")
            scaleAnimation.fromValue = 0.5
            scaleAnimation.toValue = 2.0
            scaleAnimation.duration = Double.random(in: 0.5...2.0)
            scaleAnimation.autoreverses = true
            scaleAnimation.repeatCount = .infinity
            layer.add(scaleAnimation, forKey: "scale")
            
            let rotationAnimation = CABasicAnimation(keyPath: "transform.rotation")
            rotationAnimation.fromValue = 0
            rotationAnimation.toValue = Double.pi * 2
            rotationAnimation.duration = Double.random(in: 1...4)
            rotationAnimation.repeatCount = .infinity
            layer.add(rotationAnimation, forKey: "rotation")
            
            // Color animation for additional GPU load
            let colorAnimation = CABasicAnimation(keyPath: "backgroundColor")
            colorAnimation.fromValue = layer.backgroundColor
            colorAnimation.toValue = UIColor(hue: CGFloat.random(in: 0...1), saturation: 1.0, brightness: 1.0, alpha: 0.8).cgColor
            colorAnimation.duration = Double.random(in: 2...5)
            colorAnimation.autoreverses = true
            colorAnimation.repeatCount = .infinity
            layer.add(colorAnimation, forKey: "color")
            
            animationLayers.append(layer)
            self.layer.addSublayer(layer)
        }
    }
    
    @objc private func displayLinkUpdate() {
        frameCounter += 1
        
        // High-frequency screen updates with dynamic content
        if frameCounter % 2 == 0 { // Update every other frame for 60Hz content updates
            updateDynamicContent()
        }
        
        // Force HDR-like content updates if supported
        if frameCounter % 5 == 0 {
            updateHDRContent()
        }
    }
    
    private func updateDynamicContent() {
        // Continuously update layer properties for maximum rendering stress
        for (index, layer) in animationLayers.enumerated() {
            // Dynamic opacity changes
            layer.opacity = Float.random(in: 0.3...1.0)
            
            // Dynamic border changes
            if index % 3 == 0 {
                layer.borderWidth = CGFloat.random(in: 0...5)
                layer.borderColor = UIColor(hue: CGFloat.random(in: 0...1), saturation: 1.0, brightness: 1.0, alpha: 1.0).cgColor
            }
            
            // Dynamic shadow for additional rendering complexity
            if index % 5 == 0 {
                layer.shadowOpacity = Float.random(in: 0...1)
                layer.shadowRadius = CGFloat.random(in: 0...10)
                layer.shadowOffset = CGSize(width: CGFloat.random(in: -5...5), height: CGFloat.random(in: -5...5))
            }
        }
    }
    
    private func updateHDRContent() {
        // Simulate HDR content rendering with high brightness values
        for layer in animationLayers {
            // Create high-intensity colors that stress the display
            let hdr = UIColor(red: CGFloat.random(in: 0.8...1.0), 
                             green: CGFloat.random(in: 0.8...1.0), 
                             blue: CGFloat.random(in: 0.8...1.0), 
                             alpha: 1.0)
            layer.backgroundColor = hdr.cgColor
        }
    }
    
    deinit {
        displayLink?.invalidate()
        displayLink = nil
    }
}