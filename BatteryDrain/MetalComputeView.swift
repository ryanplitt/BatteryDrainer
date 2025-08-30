import SwiftUI
import MetalKit
// MARK: - Metal Compute View
class MetalComputeUIView: MTKView {
    var cmdQueue: MTLCommandQueue!
    var pipeline: MTLComputePipelineState!
    var dataBuffer: MTLBuffer!

    override init(frame: CGRect, device: MTLDevice?) {
        super.init(frame: frame, device: device ?? MTLCreateSystemDefaultDevice())
        guard let dev = self.device else { 
            print("Failed to create Metal device")
            return 
        }
        
        cmdQueue = dev.makeCommandQueue()
        guard let cmdQueue = cmdQueue else {
            print("Failed to create Metal command queue")
            return
        }
        
        // Allocate a buffer for compute shader to write into
        let elementCount = 4096 * 4096
        dataBuffer = dev.makeBuffer(length: elementCount * MemoryLayout<Float>.size, options: .storageModeShared)
        guard let dataBuffer = dataBuffer else {
            print("Failed to create Metal buffer")
            return
        }
        
        guard let lib = dev.makeDefaultLibrary() else {
            print("Failed to create Metal library")
            return
        }
        
        guard let fn = lib.makeFunction(name: "heavyCompute") else {
            print("Failed to create Metal function 'heavyCompute'")
            return
        }
        
        do {
            pipeline = try dev.makeComputePipelineState(function: fn)
        } catch {
            print("Failed to create compute pipeline: \(error)")
            return
        }
        
        isPaused = false
        enableSetNeedsDisplay = false
        preferredFramesPerSecond = 120 // Maximum ProMotion refresh rate for display stress
    }

    required init(coder: NSCoder) { fatalError() }

    override func draw(_ rect: CGRect) {
        // Run multiple compute passes for maximum GPU stress
        let passCount = 3 // Multiple passes per frame
        
        for _ in 0..<passCount {
            guard let buf = cmdQueue.makeCommandBuffer(),
                  let enc = buf.makeComputeCommandEncoder(),
                  let pipeline = pipeline else { 
                print("Failed to create Metal command buffer or encoder")
                return 
            }
            
            // Bind the buffer for index 0
            enc.setBuffer(dataBuffer, offset: 0, index: 0)
            enc.setComputePipelineState(pipeline)
            let w = pipeline.threadExecutionWidth
            let h = pipeline.maxTotalThreadsPerThreadgroup / w
            let tg = MTLSize(width: w, height: h, depth: 1)
            let threads = MTLSize(width: 4096, height: 4096, depth: 1)
            enc.dispatchThreads(threads, threadsPerThreadgroup: tg)
            enc.endEncoding()
            buf.commit()
            
            // Force synchronous execution for maximum GPU stress
            buf.waitUntilCompleted()
        }
    }
}

struct MetalComputeView: UIViewRepresentable {
    func makeUIView(context: Context) -> MetalComputeUIView {
        MetalComputeUIView(frame: .zero, device: MTLCreateSystemDefaultDevice())
    }
    func updateUIView(_ uiView: MetalComputeUIView, context: Context) { }
}
