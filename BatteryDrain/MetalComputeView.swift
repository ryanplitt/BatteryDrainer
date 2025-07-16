import SwiftUI
import MetalKit
// MARK: - Metal Compute View
class MetalComputeUIView: MTKView {
    var cmdQueue: MTLCommandQueue!
    var pipeline: MTLComputePipelineState!
    var dataBuffer: MTLBuffer!

    override init(frame: CGRect, device: MTLDevice?) {
        super.init(frame: frame, device: device ?? MTLCreateSystemDefaultDevice())
        guard let dev = self.device else { return }
        cmdQueue = dev.makeCommandQueue()
        // Allocate a buffer for compute shader to write into
        let elementCount = 4096 * 4096
        dataBuffer = dev.makeBuffer(length: elementCount * MemoryLayout<Float>.size, options: .storageModeShared)
        let lib = dev.makeDefaultLibrary()!
        let fn = lib.makeFunction(name: "heavyCompute")!
        pipeline = try! dev.makeComputePipelineState(function: fn)
        isPaused = false
        enableSetNeedsDisplay = false
        preferredFramesPerSecond = 60
    }

    required init(coder: NSCoder) { fatalError() }

    override func draw(_ rect: CGRect) {
        guard let buf = cmdQueue.makeCommandBuffer(),
              let enc = buf.makeComputeCommandEncoder() else { return }
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
    }
}

struct MetalComputeView: UIViewRepresentable {
    func makeUIView(context: Context) -> MetalComputeUIView {
        MetalComputeUIView(frame: .zero, device: MTLCreateSystemDefaultDevice())
    }
    func updateUIView(_ uiView: MetalComputeUIView, context: Context) { }
}
