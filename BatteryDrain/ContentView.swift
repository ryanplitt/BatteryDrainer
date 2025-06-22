import SwiftUI
import AVFoundation
import CoreLocation
import CoreBluetooth
import AVKit
import ARKit
import CoreImage
import MetalKit
import Security

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


// MARK: - ARDrainerView
struct ARDrainerView: UIViewRepresentable {
    func makeUIView(context: Context) -> ARSCNView {
        // Create and configure ARSCNView
        let arView = ARSCNView(frame: .zero)
        // 1. Configure high performance rendering
        arView.preferredFramesPerSecond = 60
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
        for i in 0..<50 {
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
        uiView.preferredFramesPerSecond = 60
        uiView.contentScaleFactor = UIScreen.main.scale * 2
        // No need to reconfigure scene here
    }
}

// MARK: - RandomImageView
struct RandomImageView: View {
    @State private var imageUrl: URL? = nil
    // Refresh every 10 seconds (consider increasing the interval or lowering resolution to reduce memory impact)
    let timer = Timer.publish(every: 10, on: .main, in: .common).autoconnect()
    
    var body: some View {
        Group {
            if let url = imageUrl {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                    case .failure:
                        Text("Failed to load image")
                    @unknown default:
                        EmptyView()
                    }
                }
            } else {
                ProgressView()
            }
        }
        .onAppear {
            updateImageUrl()
        }
        .onReceive(timer) { _ in
            updateImageUrl()
        }
        .onDisappear {
            imageUrl = nil
        }
    }
    
    func updateImageUrl() {
        // Clear the current image to free up memory.
        imageUrl = nil
        // Using Lorem Picsum with a lower resolution (1080x1080) to reduce memory usage.
        if let baseUrl = URL(string: "https://picsum.photos/1080/1080") {
            let randomValue = Int.random(in: 0...100000)
            var components = URLComponents(url: baseUrl, resolvingAgainstBaseURL: false)
            components?.queryItems = [URLQueryItem(name: "random", value: "\(randomValue)")]
            imageUrl = components?.url
        }
    }
}


// MARK: - BatteryDrainer
class BatteryDrainer: NSObject, CLLocationManagerDelegate, CBCentralManagerDelegate, AVCaptureVideoDataOutputSampleBufferDelegate {
    
    var locationManager: CLLocationManager?
    var centralManager: CBCentralManager?
    var audioEngine: AVAudioEngine?
    var cpuWorkItems: [DispatchWorkItem] = []
    var hapticTimer: Timer?
    var networkTimer: Timer?
    var uploadTimer: Timer?
    var captureSession: AVCaptureSession?
    var audioRecorder: AVAudioRecorder?
    var aggressiveMode: Bool = false
    
    var hapticGenerator: UIImpactFeedbackGenerator?
    var currentUploadTask: URLSessionUploadTask?

    // MARK: 4K HEVC Video Recording
    private var videoWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var recordSession: AVCaptureSession?
    private var recordOutput: AVCaptureVideoDataOutput?

    func start4KRecording() {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("drain_4k.mp4")
        try? FileManager.default.removeItem(at: tempURL)

        videoWriter = try? AVAssetWriter(outputURL: tempURL, fileType: .mp4)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: 3840,
            AVVideoHeightKey: 2160,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 50_000_000
            ]
        ]
        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        videoInput?.expectsMediaDataInRealTime = true

        if let writer = videoWriter, let input = videoInput, writer.canAdd(input) {
            writer.add(input)
        }

        recordSession = AVCaptureSession()
        recordSession?.sessionPreset = .inputPriority

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let camInput = try? AVCaptureDeviceInput(device: camera) else { return }
        recordSession?.addInput(camInput)

        let output = AVCaptureVideoDataOutput()
        output.setSampleBufferDelegate(self, queue: DispatchQueue(label: "recordQueue"))
        recordSession?.addOutput(output)
        recordOutput = output

        videoWriter?.startWriting()
        videoWriter?.startSession(atSourceTime: .zero)
        recordSession?.startRunning()
        print("Started 4K HEVC recording")
    }

    func stop4KRecording() {
        recordSession?.stopRunning()
        videoInput?.markAsFinished()
        videoWriter?.finishWriting { [weak self] in
            print("Finished 4K recording at \(self?.videoWriter?.outputURL.path ?? "")")
        }
        videoWriter = nil
        videoInput = nil
        recordSession = nil
        recordOutput = nil
    }
    
    // MARK: Added - Properties for Storage I/O Load
    var storageIOWorkItem: DispatchWorkItem?
    let storageIOFileName = "largeTempFile.dat"
    let storageIODataSize = 10 * 1024 * 1024 // 10 MB
    
    // MARK: Added - Properties for Camera Processing
    let ciContext = CIContext() // Context for Core Image processing
    let blurFilter = CIFilter(name: "CIGaussianBlur")! // Heavy blur filter
    
    lazy var aggressiveSession: URLSession = {
        let config = URLSessionConfiguration.default
        // Increase the number of allowed concurrent connections.
        config.httpMaximumConnectionsPerHost = 50 // Keep this high for aggressive mode
        config.timeoutIntervalForRequest = 40 // Shorter timeout for aggressive mode
        config.timeoutIntervalForResource = 40
        return URLSession(configuration: config)
    }()
    
    lazy var uploadQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 5  // Limit to 5 concurrent uploads
        return queue
    }()
    
    lazy var downloadQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 5  // Limit to 5 concurrent downloads
        return queue
    }()
    
    // MARK: Max Brightness & Flashlight
    func startBrightnessAndFlashlight() {
        UIScreen.main.brightness = 1.0
        if let device = AVCaptureDevice.default(for: .video), device.hasTorch {
            attemptTorchActivation(device: device, level: 1.0)
        }
    }
    
    // Recursively attempt to activate torch with decreasing brightness until success
    private func attemptTorchActivation(device: AVCaptureDevice, level: Float) {
        do {
            try device.lockForConfiguration()
            // Try setting the torch at the given level
            try device.setTorchModeOn(level: level)
            device.unlockForConfiguration()
            print("Torch activated at level \(level)")
        } catch {
            device.unlockForConfiguration()
            print("Torch activation failed at level \(level): \(error)")
            // Retry with a lower level if possible
            if level > 0.1 {
                let nextLevel = max(0, level - 0.1) // Ensure level doesn't go below 0
                // Try again after a short delay to avoid tight looping
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
                    self.attemptTorchActivation(device: device, level: nextLevel)
                }
            } else {
                print("Unable to activate torch even at minimum level.")
            }
        }
    }
    
    func stopBrightnessAndFlashlight() {
        UIScreen.main.brightness = 0.5 // Restore default brightness
        if let device = AVCaptureDevice.default(for: .video), device.hasTorch {
            do {
                try device.lockForConfiguration()
                device.torchMode = .off
                device.unlockForConfiguration()
            } catch {
                print("Flashlight off error: \(error)")
            }
        }
    }
    
    // MARK: CPU Load via recursive Fibonacci calculations
    func startCPULoad() {
        print("Starting CPU Load...")
        guard cpuWorkItems.isEmpty else { return } // Prevent starting multiple times
        // Use slightly more threads if possible, up to active core count - 1 or 2
        let coreCount = ProcessInfo.processInfo.activeProcessorCount
        let threadCount = max(1, coreCount - 1) // Leave one core for UI/System if possible
        
        for i in 0..<threadCount {
            var localWorkItem: DispatchWorkItem!
            localWorkItem = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                print("CPU Thread \(i) started.")
                // Use a slightly larger number for more intensity, but monitor for hangs
                let fibNumber = 36 // Increased slightly
                while !localWorkItem.isCancelled {
                    _ = self.fibonacci(fibNumber)
                    // Optional: Add a tiny sleep if it completely freezes the UI,
                    // but for pure drain, no sleep is better.
                    // Thread.sleep(forTimeInterval: 0.001)
                }
                print("CPU Thread \(i) cancelled.")
            }
            cpuWorkItems.append(localWorkItem)
            // Use .userInitiated or .utility - .userInitiated is higher priority
            DispatchQueue.global(qos: .userInitiated).async(execute: localWorkItem)
        }
    }
    func stopCPULoad() {
        print("Stopping CPU Load...")
        cpuWorkItems.forEach { $0.cancel() }
        cpuWorkItems.removeAll()
    }
    
    // MARK: High Accuracy Location Updates
    func startLocationUpdates() {
        locationManager = CLLocationManager()
        locationManager?.delegate = self
        locationManager?.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager?.allowsBackgroundLocationUpdates = true

        let status = CLLocationManager.authorizationStatus()

        if status == .notDetermined {
            locationManager?.requestAlwaysAuthorization() // or requestWhenInUseAuthorization()
        } else if status == .authorizedAlways || status == .authorizedWhenInUse {
            locationManager?.startUpdatingLocation()
        } else {
            print("Location permission not granted")
        }
    }
    
    func stopLocationUpdates() {
        locationManager?.stopUpdatingLocation()
        locationManager = nil
        print("Stopped Location Updates")
    }
    
    
    // MARK: Bluetooth Scanning
    func startBluetoothScanning() {
        // Ensure state is reset if previously stopped
        if centralManager == nil {
            centralManager = CBCentralManager(delegate: self, queue: nil, options: [CBCentralManagerOptionShowPowerAlertKey: false])
            print("Started Bluetooth Scanning")
        } else if centralManager?.state == .poweredOn {
            centralManager?.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]) // Scan aggressively
            centralManager?.delegate = self
            print("Restarted Bluetooth Scan")
        }
    }
    
    func stopBluetoothScanning() {
        if let central = centralManager, central.isScanning {
            central.stopScan()
            print("Stopped Bluetooth Scanning")
        }
        // Don't nil out centralManager immediately if you want to restart scanning easily
        // centralManager = nil
    }
    
    // MARK: Continuous Audio Tone
    func startAudioTone() {
        audioEngine = AVAudioEngine()
        guard let engine = audioEngine else { return }
        let mainMixer = engine.mainMixerNode
        let output = engine.outputNode
        let format = output.inputFormat(forBus: 0)
        let sourceNode = AVAudioSourceNode { _, _, frameCount, audioBufferList -> OSStatus in
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let thetaIncrement = 2.0 * Double.pi * 100.0 / format.sampleRate
            var theta: Double = 0
            for frame in 0..<Int(frameCount) {
                let sampleVal = Float(sin(theta))
                theta += thetaIncrement
                if theta > 2.0 * Double.pi {
                    theta -= 2.0 * Double.pi
                }
                for buffer in ablPointer {
                    let buf: UnsafeMutableBufferPointer<Float> = UnsafeMutableBufferPointer(buffer)
                    buf[frame] = sampleVal
                }
            }
            return noErr
        }
        engine.attach(sourceNode)
        engine.connect(sourceNode, to: mainMixer, format: format)
        engine.prepare()
        do {
            try engine.start()
        } catch {
            print("Audio Engine error: \(error)")
        }
    }
    
    func stopAudioTone() {
        audioEngine?.stop()
        audioEngine = nil
    }
    
    // MARK: Haptic Feedback
    func startHaptics() {
        // Ensure clean start
        stopHaptics()
        
        // Use heaviest impact possible
        hapticGenerator = UIImpactFeedbackGenerator(style: .heavy)
        hapticGenerator?.prepare() // Prepare initially
        
        // Use a faster interval for more drain
        let interval: TimeInterval = 0.5 // Reduced from 1.0
        
        hapticTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            // Trigger impact
            self.hapticGenerator?.impactOccurred()
            
            // Re-prepare immediately after for the next potential impact.
            // This keeps the Taptic engine primed, potentially using more power.
            self.hapticGenerator?.prepare()
        }
        print("Started Haptics")
    }
    
    func stopHaptics() {
        hapticTimer?.invalidate()
        hapticTimer = nil
        // Release the generator
        hapticGenerator = nil
        print("Stopped Haptics")
    }
    
    
    // MARK: Network Requests (Download)
    func startNetworkRequests() {
        // Cancel any existing operations.
        downloadQueue.cancelAllOperations()
        // Set the maximum concurrent operations based on aggressive mode.
        downloadQueue.maxConcurrentOperationCount = aggressiveMode ? 10 : 1
        // Start the desired number of operations.
        let desiredCount = aggressiveMode ? 10 : 1
        for _ in 0..<desiredCount {
            addDownloadOperation()
        }
        print("Started continuous queued Download Requests (Mode: \(aggressiveMode ? "Aggressive" : "Normal"))")
    }

    private func addDownloadOperation() {
        let op = BlockOperation { [weak self] in
            guard let self = self else { return }
            // Use a semaphore so that the operation doesn’t finish until the network call is done.
            let semaphore = DispatchSemaphore(value: 0)
            self.makeNetworkRequest {
                semaphore.signal()
            }
            semaphore.wait()
            // Once done, if the queue is still active, add another operation to keep the desired count.
            if !self.downloadQueue.isSuspended && !self.downloadQueue.operations.contains(where: { $0.isCancelled }) {
                self.addDownloadOperation()
            }
        }
        downloadQueue.addOperation(op)
    }

    func stopNetworkRequests() {
        downloadQueue.cancelAllOperations()
        print("Stopped continuous Download Requests")
    }
    
    func makeNetworkRequest(completion: @escaping () -> Void) {
        let randomValue = Int.random(in: 0...100000)
        let urlString: String
        let session: URLSession

        if aggressiveMode {
            urlString = "http://192.168.0.80:3434/download"
            session = aggressiveSession
            print("Aggressive Download Request to \(urlString)")
        } else {
            urlString = "https://picsum.photos/3000/3000?random=\(randomValue)"
            session = URLSession.shared
            print("Standard Download Request to \(urlString)")
        }

        guard let url = URL(string: urlString) else {
            print("Invalid URL: \(urlString)")
            completion()
            return
        }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let task = session.dataTask(with: request) { data, response, error in
            if let error = error {
                if let urlError = error as? URLError, urlError.code == .timedOut {
                    print("Download timed out.")
                } else {
                    print("Download error: \(error.localizedDescription)")
                }
            } else if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
                print("Download failed with status code: \(httpResponse.statusCode)")
            } else {
                print("Downloaded \(data?.count ?? 0) bytes successfully.")
            }
            // Call completion to signal that the operation is finished.
            completion()
        }
        task.resume()
    }
    
    
    // MARK: Upload Requests
    func makeUploadRequest(completion: @escaping () -> Void) {
        let urlString: String
        if aggressiveMode {
            urlString = "http://192.168.0.80:3434/upload"
        } else {
            urlString = "https://httpbin.org/post"
        }
        guard let url = URL(string: urlString) else {
            completion()
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        
        let payloadSize = aggressiveMode ? 30_000_000 : 5_000_000
        let data = Data(repeating: 0xDE, count: payloadSize)
        
        let session = aggressiveMode ? aggressiveSession : URLSession.shared
        let task = session.uploadTask(with: request, from: data) { data, response, error in
            if let error = error {
                print("Upload error: \(error.localizedDescription)")
            } else {
                print("Upload succeeded for \(payloadSize) bytes.")
            }
            completion()
        }
        task.resume()
    }
    
    func startUploadRequests() {
        // Cancel any existing upload operations.
        uploadQueue.cancelAllOperations()
        // Set the maximum concurrent operations.
        uploadQueue.maxConcurrentOperationCount = aggressiveMode ? 10 : 1
        let desiredCount = aggressiveMode ? 10 : 1
        for _ in 0..<desiredCount {
            addUploadOperation()
        }
        print("Started continuous queued Upload Requests (Mode: \(aggressiveMode ? "Aggressive" : "Normal"))")
    }

    private func addUploadOperation() {
        let op = BlockOperation { [weak self] in
            guard let self = self else { return }
            let semaphore = DispatchSemaphore(value: 0)
            self.makeUploadRequest {
                semaphore.signal()
            }
            semaphore.wait()
            if !self.uploadQueue.isSuspended && !self.uploadQueue.operations.contains(where: { $0.isCancelled }) {
                self.addUploadOperation()
            }
        }
        uploadQueue.addOperation(op)
    }

    func stopUploadRequests() {
        uploadQueue.cancelAllOperations()
        print("Stopped continuous Upload Requests")
    }
    
    // MARK: Camera Capture
    // ... (startCameraCapture remains  setup) ...
    func startCameraCapture() {
        // Ensure clean start
        stopCameraCapture()
        
        captureSession = AVCaptureSession()
        guard let session = captureSession else { return }
        
        // Use a preset known for higher power consumption if available, otherwise high.
        if session.canSetSessionPreset(.photo) {
            session.sessionPreset = .photo // Often higher resolution/processing than .high
        } else {
            session.sessionPreset = .high
        }
        
        
        // Prefer front camera as it's often used with screen on
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: camera) else {
            print("Could not get camera device or input.")
            return
        }
        
        if session.canAddInput(input) {
            session.addInput(input)
        } else {
            print("Could not add camera input.")
            return
        }
        
        let output = AVCaptureVideoDataOutput()
        // Specify pixel format that CoreImage can work with easily
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
        output.alwaysDiscardsLateVideoFrames = true // Don't buffer, process immediately
        
        // Set the delegate to self, using a dedicated serial queue for processing
        let cameraQueue = DispatchQueue(label: "cameraProcessingQueue", qos: .userInitiated)
        output.setSampleBufferDelegate(self, queue: cameraQueue)
        
        if session.canAddOutput(output) {
            session.addOutput(output)
        } else {
            print("Could not add camera output.")
            return
        }
        
        // Start the session asynchronously
        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
            print("Started Camera Capture (Preset: \(session.sessionPreset))")
        }
    }
    
    func stopCameraCapture() {
        if captureSession?.isRunning ?? false {
            captureSession?.stopRunning()
            print("Stopped Camera Capture")
        }
        // Remove inputs/outputs to release resources
        captureSession?.inputs.forEach { captureSession?.removeInput($0) }
        captureSession?.outputs.forEach { captureSession?.removeOutput($0) }
        captureSession = nil
    }
    
    
    // MARK: Audio Recording (Record & Discard)
    func startAudioRecording() {
        // Ensure clean start
        stopAudioRecording()
        
        let session = AVAudioSession.sharedInstance()
        do {
            // Use playAndRecord to potentially conflict/load more with audio tone playback
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .mixWithOthers])
            try session.setActive(true)
            
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC), // Standard compressed format
                AVSampleRateKey: 44100, // Standard sample rate
                AVNumberOfChannelsKey: 1, // Mono
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue // High quality encoding uses more CPU
            ]
            
            let tempDir = FileManager.default.temporaryDirectory
            let filePath = tempDir.appendingPathComponent("tempRecording_\(UUID().uuidString).m4a") // Unique name
            
            audioRecorder = try AVAudioRecorder(url: filePath, settings: settings)
            audioRecorder?.isMeteringEnabled = true // Enable metering (minor extra load)
            audioRecorder?.record() // Start recording
            print("Started Audio Recording to \(filePath)")
            
        } catch {
            print("Audio Recording setup/start error: \(error)")
            try? session.setActive(false) // Try to deactivate session on error
        }
    }
    
    func stopAudioRecording() {
        if audioRecorder?.isRecording ?? false {
            audioRecorder?.stop()
            print("Stopped Audio Recording")
        }
        // Delete the temporary file
        if let url = audioRecorder?.url {
            try? FileManager.default.removeItem(at: url)
            // print("Deleted temporary recording file: \(url.lastPathComponent)")
        }
        audioRecorder = nil
        // Deactivate session if no longer needed by other components (like audio tone)
        // Note: This might conflict if audio tone is also running. Manage session state carefully.
        // try? AVAudioSession.sharedInstance().setActive(false)
    }
    
    
    // MARK: Recursive Fibonacci for heavy CPU load
    // ... (fibonacci remains ) ...
    func fibonacci(_ n: Int) -> Int {
        // Base cases
        if n <= 1 { return n }
        // Recursive step
        return fibonacci(n - 1) + fibonacci(n - 2)
    }
    
    
    // MARK: Added - Storage I/O Load
    func startStorageIO() {
        print("Starting Storage I/O Load...")
        guard storageIOWorkItem == nil else { return } // Prevent multiple starts
        
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory
        let filePath = tempDir.appendingPathComponent(storageIOFileName)
        
        storageIOWorkItem = DispatchWorkItem { [weak self] in
            guard let self = self, let workItem = self.storageIOWorkItem else { return }
            
            while !workItem.isCancelled {
                // 1. Generate random data
                let dataToWrite = Data.randomData(length: self.storageIODataSize)
                
                // 2. Write data to file
                do {
                    try dataToWrite.write(to: filePath, options: .atomic) // Atomic write for safety
                    // print("Storage I/O: Wrote \(self.storageIODataSize) bytes.")
                    
                    // 3. Read data back (optional but adds load)
                    let dataRead = try Data(contentsOf: filePath)
                    if dataRead.count != self.storageIODataSize {
                        print("Storage I/O: Read verification failed (size mismatch).")
                    } else {
                        print("Storage I/O: Read \(dataRead.count) bytes successfully.")
                    }
                    
                    // 4. Delete file
                    try fileManager.removeItem(at: filePath)
                    // print("Storage I/O: Deleted file.")
                    
                } catch {
                    print("Storage I/O Error: \(error)")
                    // If write failed, file might not exist for deletion, handle gracefully
                    if fileManager.fileExists(atPath: filePath.path) {
                        try? fileManager.removeItem(at: filePath)
                    }
                    // Pause briefly on error to avoid spamming logs
                    Thread.sleep(forTimeInterval: 0.5)
                }
                
                // Add a small delay to prevent overwhelming the system completely
                // and allow cancellation check to be more responsive. Adjust as needed.
                Thread.sleep(forTimeInterval: 0.05) // 50 milliseconds
            }
            print("Storage I/O Load cancelled.")
            // Cleanup file if it exists when cancelled
            if fileManager.fileExists(atPath: filePath.path) {
                try? fileManager.removeItem(at: filePath)
                print("Storage I/O: Cleaned up temp file on cancel.")
            }
        }
        // Run on a background thread
        DispatchQueue.global(qos: .utility).async(execute: storageIOWorkItem!)
    }
    
    func stopStorageIO() {
        print("Stopping Storage I/O Load...")
        storageIOWorkItem?.cancel()
        storageIOWorkItem = nil
        // File cleanup happens within the work item cancellation check or on next start
    }
    
    
    // MARK: - CBCentralManagerDelegate
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            print("Bluetooth Powered On - Starting Scan")
            // Start scanning immediately when powered on, allow duplicates for constant activity
            central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        } else {
            print("Bluetooth state changed: \(central.state)")
            if central.isScanning {
                central.stopScan()
                print("Stopped scan due to Bluetooth state change.")
            }
        }
    }
    
    // Optional: Log discovered peripherals to confirm scanning is active
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        // print("Discovered BT Peripheral: \(peripheral.name ?? "Unknown") RSSI: \(RSSI)")
        // Don't connect, just keep scanning
    }
    
    
    // MARK: - CLLocationManagerDelegate
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let location = locations.last {
            // Log less frequently to avoid spamming console
            // print("Location Update: \(location.coordinate.latitude), \(location.coordinate.longitude) Accuracy: \(location.horizontalAccuracy)m")
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location Manager Error: \(error.localizedDescription)")
        // Consider restarting location updates if it fails?
        // stopLocationUpdates()
        // DispatchQueue.main.asyncAfter(deadline: .now() + 5) { self.startLocationUpdates() }
    }
    
    // Handle authorization changes
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            print("Location authorization granted.")
            if self.locationManager?.delegate == nil {
                self.locationManager?.delegate = self
            }
            self.locationManager?.startUpdatingLocation()
        case .denied, .restricted:
            print("Location authorization denied or restricted.")
            stopLocationUpdates() // Stop trying if denied
        case .notDetermined:
            print("Location authorization not determined.")
            // Request again if appropriate for the UI flow
            // manager.requestAlwaysAuthorization()
        @unknown default:
            fatalError("Unknown CLLocationManagerAuthorizationStatus")
        }
    }
    
    
    // MARK: Modified - AVCaptureVideoDataOutputSampleBufferDelegate
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Process the frame to add CPU/GPU load
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        
        // Create a CIImage from the pixel buffer
        let cameraImage = CIImage(cvPixelBuffer: pixelBuffer)
        
        // Apply a heavy Gaussian blur filter
        blurFilter.setValue(cameraImage, forKey: kCIInputImageKey)
        blurFilter.setValue(20.0, forKey: kCIInputRadiusKey) // Increase radius for more load
        
        // Get the blurred output image
        guard let blurredImage = blurFilter.outputImage else {
            // print("Failed to apply blur filter.")
            return
        }
        
        // Render the output image using the CIContext. This forces the GPU to do the work.
        // We don't need the resulting CGImage, just the act of rendering is important.
        // Render to a small offscreen bitmap context for efficiency if not displaying.
        let outputRect = blurredImage.extent // Use the extent of the blurred image
        if let _ = ciContext.createCGImage(blurredImage, from: outputRect) {
            // Successfully rendered the blurred image, adding load. Discard the result.
            // print("Processed camera frame with blur.")
        } else {
            // print("Failed to render blurred CIImage.")
        }
        
        // The pixelBuffer and images are released automatically.
    }
}

// MARK: Added - Helper extension for random data
extension Data {
    static func randomData(length: Int) -> Data {
        var data = Data(count: length)
        _ = data.withUnsafeMutableBytes { bufferPointer in
            // Ensure the buffer is not nil and has memory bound
            guard let baseAddress = bufferPointer.baseAddress, bufferPointer.count > 0 else {
                return -1
            }
            // Fill the buffer with random bytes
            return Int(SecRandomCopyBytes(kSecRandomDefault, length, baseAddress))
        }
        return data
    }
}

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


// MARK: - ContentView
struct ContentView: View {
    @State private var record4KEnabled = false
    @State private var gpuComputeEnabled = false
    @State private var thermalState: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState
    @State private var brightnessEnabled = false
    @State private var cpuLoadEnabled = false
    @State private var locationEnabled = false
    @State private var bluetoothEnabled = false
    @State private var audioToneEnabled = false
    @State private var hapticsEnabled = false
    @State private var networkEnabled = false
    @State private var uploadEnabled = false
    @State private var cameraEnabled = false
    @State private var particleAnimationEnabled = false
    @State private var arSessionEnabled = false
    @State private var imageDisplayEnabled = false
    @State private var audioRecordingEnabled = false
    @State private var aggressiveModeEnabled = false
    @State private var storageIOEnabled = false
    
    // Use @StateObject for the drainer if it needs to persist state across view updates
    var drainer = BatteryDrainer()
    
    func backgroundColor(for state: ProcessInfo.ThermalState) -> Color {
        switch state {
        case .nominal:
            return Color.green
        case .fair:
            return Color.yellow
        case .serious:
            return Color.orange
        case .critical:
            return Color.red
        @unknown default:
            return Color.gray
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background elements
                if particleAnimationEnabled {
                    CrazyParticleBackgroundView()
                        .allowsHitTesting(false)
                        .ignoresSafeArea()
                }
                // Main Scrollable Content
                ScrollView {
                    VStack(alignment: .leading, spacing: 15) {
                        Text("Thermal State: \(thermalState)")
                            .font(.headline)
                            .padding()
                            .foregroundColor(backgroundColor(for: thermalState))
                        // Aggressive Mode Toggle (Top)
                        Toggle("Aggressive Mode (Max Network/CPU)", isOn: $aggressiveModeEnabled)
                            .font(.headline)
                            .foregroundColor(aggressiveModeEnabled ? .red : .primary)
                            .padding(.bottom, 10)
                            .onChange(of: aggressiveModeEnabled) { newValue in
                                drainer.aggressiveMode = newValue
                                // Re-trigger network starts to apply new intervals/settings
                                if networkEnabled {
                                    drainer.stopNetworkRequests()
                                    drainer.startNetworkRequests()
                                }
                                if uploadEnabled {
                                    drainer.stopUploadRequests()
                                    drainer.startUploadRequests()
                                }
                                // Maybe restart CPU load too if aggressive changes intensity?
                                // if cpuLoadEnabled {
                                //     drainer.stopCPULoad()
                                //     drainer.startCPULoad()
                                // }
                            }
                        
                        // --- Individual Toggles ---
                        Group {
                            Toggle("Max Brightness & Flashlight", isOn: $brightnessEnabled)
                                .onChange(of: brightnessEnabled) { value in
                                    value ? drainer.startBrightnessAndFlashlight() : drainer.stopBrightnessAndFlashlight()
                                }
                            Toggle("CPU Load (Fibonacci)", isOn: $cpuLoadEnabled)
                                .onChange(of: cpuLoadEnabled) { value in
                                    value ? drainer.startCPULoad() : drainer.stopCPULoad()
                                }
                            Toggle("High Accuracy Location", isOn: $locationEnabled)
                                .onChange(of: locationEnabled) { value in
                                    value ? drainer.startLocationUpdates() : drainer.stopLocationUpdates()
                                }
                            Toggle("Bluetooth Scanning", isOn: $bluetoothEnabled)
                                .onChange(of: bluetoothEnabled) { value in
                                    value ? drainer.startBluetoothScanning() : drainer.stopBluetoothScanning()
                                }
                            Toggle("Continuous Audio Tone", isOn: $audioToneEnabled)
                                .onChange(of: audioToneEnabled) { value in
                                    value ? drainer.startAudioTone() : drainer.stopAudioTone()
                                }
                            Toggle("Audio Recording (Discard)", isOn: $audioRecordingEnabled)
                                .onChange(of: audioRecordingEnabled) { value in
                                    value ? drainer.startAudioRecording() : drainer.stopAudioRecording()
                                }
                            Toggle("Haptic Feedback", isOn: $hapticsEnabled)
                                .onChange(of: hapticsEnabled) { value in
                                    value ? drainer.startHaptics() : drainer.stopHaptics()
                                }
                            Toggle("Network Downloads", isOn: $networkEnabled)
                                .onChange(of: networkEnabled) { value in
                                    // Pass aggressive mode state when starting/stopping
                                    if value { drainer.startNetworkRequests() } else { drainer.stopNetworkRequests() }
                                }
                            Toggle("Network Uploads", isOn: $uploadEnabled)
                                .onChange(of: uploadEnabled) { value in
                                    // Pass aggressive mode state when starting/stopping
                                    if value { drainer.startUploadRequests() } else { drainer.stopUploadRequests() }
                                }
                            Toggle("Camera Capture & Process", isOn: $cameraEnabled) // Renamed slightly
                                .onChange(of: cameraEnabled) { value in
                                    value ? drainer.startCameraCapture() : drainer.stopCameraCapture()
                                }
                            // MARK: Added - Storage I/O Toggle
                            Toggle("Storage I/O Load", isOn: $storageIOEnabled)
                                .onChange(of: storageIOEnabled) { value in
                                    value ? drainer.startStorageIO() : drainer.stopStorageIO()
                                }
                            Toggle("4K HEVC Recording", isOn: $record4KEnabled)
                                .onChange(of: record4KEnabled) { value in
                                    value ? drainer.start4KRecording() : drainer.stop4KRecording()
                                }
                            Toggle("GPU Compute Load", isOn: $gpuComputeEnabled)
                                .onChange(of: gpuComputeEnabled) { value in
                                    // Nothing to start/stop; view draws continuously
                                }
                        }
                        
                        Divider()
                        
                        // --- GPU/Visual Load Toggles ---
                        Group {
                            Toggle("Particle Animation (GPU)", isOn: $particleAnimationEnabled)
                            Toggle("AR Session (GPU/CPU/Sensors)", isOn: $arSessionEnabled)
                            Toggle("Random Image Display (Network/Mem)", isOn: $imageDisplayEnabled)
                        }
                        
                        
                        // Conditional Views (AR and Image)
                        if arSessionEnabled {
                            ARDrainerView()
                                .frame(height: 250) // Reduced height slightly
                                .cornerRadius(8)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray, lineWidth: 1))
                                .padding(.top, 5)
                        }

                        if imageDisplayEnabled {
                            RandomImageView()
                                .frame(height: 250) // Reduced height slightly
                                .cornerRadius(8)
                                .clipped()
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray, lineWidth: 1))
                                .padding(.top, 5)
                        }

                        if gpuComputeEnabled {
                            MetalComputeView()
                                .background(Color.green)
                                .frame(width: 300, height: 300)
                                .cornerRadius(8)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray, lineWidth: 1))
                                .padding(.top, 5)
                        }
                    }
                    .padding()
                }
                .navigationTitle("Battery Drainer Extreme") // Updated title
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Toggle All") {
                            // Determine target state (turn ON if any are OFF, else turn OFF all)
                            let shouldEnable = !(brightnessEnabled && cpuLoadEnabled && locationEnabled && bluetoothEnabled && audioToneEnabled && hapticsEnabled && networkEnabled && uploadEnabled && cameraEnabled && particleAnimationEnabled && arSessionEnabled && imageDisplayEnabled && audioRecordingEnabled && storageIOEnabled)
                            
                            brightnessEnabled = shouldEnable
                            cpuLoadEnabled = shouldEnable
                            locationEnabled = shouldEnable
                            bluetoothEnabled = shouldEnable
                            audioToneEnabled = shouldEnable
                            hapticsEnabled = shouldEnable
                            networkEnabled = shouldEnable
                            uploadEnabled = shouldEnable
                            cameraEnabled = shouldEnable
                            particleAnimationEnabled = shouldEnable
                            arSessionEnabled = shouldEnable
                            imageDisplayEnabled = shouldEnable
                            audioRecordingEnabled = shouldEnable
                            storageIOEnabled = shouldEnable // Added storage IO to toggle all
                        }
                    }
                }
                .onAppear {
                    // Default state on appear - maybe start with less? Or keep all on?
                    // Comment out ones you don't want to start automatically.
                    //                    brightnessEnabled = true
                    cpuLoadEnabled = true
                    locationEnabled = true
                    bluetoothEnabled = true
                    //                    audioToneEnabled = true // Be careful with audio auto-start
                    audioRecordingEnabled = true // Be careful with audio auto-start
                    hapticsEnabled = true
                    networkEnabled = true
                    uploadEnabled = true
                    //                    cameraEnabled = true
                    particleAnimationEnabled = true
                    arSessionEnabled = true
                    imageDisplayEnabled = true
                    storageIOEnabled = true // Added storage IO auto-start
                }
                .onDisappear {
                    // Ensure everything stops when the view disappears
                    print("View disappearing, stopping all drainers...")
                    drainer.stopBrightnessAndFlashlight()
                    drainer.stopCPULoad()
                    drainer.stopLocationUpdates()
                    drainer.stopBluetoothScanning()
                    drainer.stopAudioTone()
                    drainer.stopAudioRecording()
                    drainer.stopHaptics()
                    drainer.stopNetworkRequests()
                    drainer.stopUploadRequests()
                    drainer.stopCameraCapture()
                    drainer.stopStorageIO() // Added storage IO stop
                    
                    // Reset state variables as well
                    brightnessEnabled = false
                    cpuLoadEnabled = false
                    locationEnabled = false
                    bluetoothEnabled = false
                    audioToneEnabled = false
                    hapticsEnabled = false
                    networkEnabled = false
                    uploadEnabled = false
                    cameraEnabled = false
                    particleAnimationEnabled = false
                    arSessionEnabled = false
                    imageDisplayEnabled = false
                    audioRecordingEnabled = false
                    storageIOEnabled = false
                    aggressiveModeEnabled = false // Reset aggressive mode too
                }
            }
        }
        // Request permissions on launch if needed (Location, Camera, Mic)
        // This might be better handled with specific buttons or explanations in a real app
        .onAppear {
            drainer.locationManager?.requestAlwaysAuthorization()
            AVCaptureDevice.requestAccess(for: .video) { granted in print("Camera access: \(granted)") }
            AVAudioSession.sharedInstance().requestRecordPermission() { granted in print("Microphone access: \(granted)") }
        }
        .onReceive(NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)) { _ in
            thermalState = ProcessInfo.processInfo.thermalState
            print("Thermal state updated to \(thermalState)")
        }
    }
}
