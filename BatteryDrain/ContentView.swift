import SwiftUI
import AVFoundation
import CoreLocation
import CoreBluetooth
import AVKit
import ARKit

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
        let arView = ARSCNView(frame: .zero)
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]
        arView.session.run(configuration)
        return arView
    }
    
    func updateUIView(_ uiView: ARSCNView, context: Context) { }
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
    
    lazy var aggressiveSession: URLSession = {
        let config = URLSessionConfiguration.default
        // Increase the number of allowed concurrent connections.
        config.httpMaximumConnectionsPerHost = 20
        return URLSession(configuration: config)
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
                let nextLevel = level - 0.1
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
        UIScreen.main.brightness = 0.5
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
        for _ in 0..<4 {
            var localWorkItem: DispatchWorkItem!
            localWorkItem = DispatchWorkItem {
                while !localWorkItem.isCancelled {
                    _ = self.fibonacci(35)
                }
            }
            cpuWorkItems.append(localWorkItem)
            DispatchQueue.global(qos: .userInitiated).async(execute: localWorkItem)
        }
    }
    
    func stopCPULoad() {
        cpuWorkItems.forEach { $0.cancel() }
        cpuWorkItems.removeAll()
    }
    
    // MARK: High Accuracy Location Updates
    func startLocationUpdates() {
        locationManager = CLLocationManager()
        locationManager?.delegate = self
        locationManager?.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager?.requestAlwaysAuthorization()
        locationManager?.startUpdatingLocation()
    }
    
    func stopLocationUpdates() {
        locationManager?.stopUpdatingLocation()
        locationManager = nil
    }
    
    // MARK: Bluetooth Scanning
    func startBluetoothScanning() {
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    func stopBluetoothScanning() {
        if let central = centralManager, central.isScanning {
            central.stopScan()
        }
        centralManager = nil
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
            let thetaIncrement = 2.0 * Double.pi * 440.0 / format.sampleRate
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
        // Create and prepare the generator once
        hapticGenerator = UIImpactFeedbackGenerator(style: .heavy)
        hapticGenerator?.prepare()
        
        hapticTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            self.hapticGenerator?.impactOccurred()
            // Prepare it for the next event
            self.hapticGenerator?.prepare()
        }
    }
    
    func stopHaptics() {
        hapticTimer?.invalidate()
        hapticTimer = nil
        hapticGenerator = nil
    }
    
    // MARK: Network Requests (Download)
    func startNetworkRequests() {
        networkTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            self.makeNetworkRequest()
        }
    }
    
    func stopNetworkRequests() {
        networkTimer?.invalidate()
        networkTimer = nil
    }
    
    func makeNetworkRequest() {
        // Use home server for aggressive mode; otherwise use Picsum.
        let randomValue = Int.random(in: 0...100000)
        let urlString: String
        if aggressiveMode {
            urlString = "http://192.168.0.80:3434/download"
        } else {
            urlString = "https://picsum.photos/2000/2000?random=\(randomValue)"
        }
        guard let url = URL(string: urlString) else { return }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Download error: \(error)")
            } else {
                print("Downloaded \(data?.count ?? 0) bytes")
            }
        }
        task.resume()
    }
    
    // MARK: Upload Requests
    func startUploadRequests() {
        // In aggressive mode, reduce interval and increase payload size.
        let interval: TimeInterval = aggressiveMode ? 0.25 : 1.0
        let payloadSize = aggressiveMode ? 20_000_000 : 5_000_000
        
        uploadTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            // Choose the correct URL based on aggressiveMode
            let urlString: String
            if self.aggressiveMode {
                // Replace with your Mac mini's local upload endpoint
                urlString = "http://192.168.0.80:3434/upload"
            } else {
                urlString = "https://httpbin.org/post"
            }
            
            guard let url = URL(string: urlString) else { return }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            
            let data = Data(repeating: 0xDE, count: payloadSize)
            
            let task = self.aggressiveSession.uploadTask(with: request, from: data) { data, response, error in
                if let error = error {
                    print("Upload error: \(error)")
                } else {
                    print("Upload succeeded")
                }
            }
            task.resume()
        }
    }
    
    func stopUploadRequests() {
        uploadTimer?.invalidate()
        uploadTimer = nil
    }
    
    // MARK: Camera Capture
    func startCameraCapture() {
        captureSession = AVCaptureSession()
        guard let session = captureSession else { return }
        session.sessionPreset = .high
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else { return }
        do {
            let input = try AVCaptureDeviceInput(device: camera)
            if session.canAddInput(input) {
                session.addInput(input)
            }
            let output = AVCaptureVideoDataOutput()
            output.setSampleBufferDelegate(self, queue: DispatchQueue(label: "cameraQueue"))
            if session.canAddOutput(output) {
                session.addOutput(output)
            }
            DispatchQueue.global(qos: .userInitiated).async {
                session.startRunning()
            }
        } catch {
            print("Camera capture error: \(error)")
        }
    }
    
    func stopCameraCapture() {
        captureSession?.stopRunning()
        captureSession = nil
    }
    
    // MARK: Audio Recording (Record & Discard)
    func startAudioRecording() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 12000,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            let tempDir = NSTemporaryDirectory()
            let filePath = tempDir + "/tempRecording.m4a"
            let url = URL(fileURLWithPath: filePath)
            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder?.record()
        } catch {
            print("Audio Recording error: \(error)")
        }
    }
    
    func stopAudioRecording() {
        audioRecorder?.stop()
        audioRecorder = nil
    }
    
    // MARK: Recursive Fibonacci for heavy CPU load
    func fibonacci(_ n: Int) -> Int {
        if n <= 1 { return n }
        return fibonacci(n - 1) + fibonacci(n - 2)
    }
    
    // MARK: - CBCentralManagerDelegate
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            central.scanForPeripherals(withServices: nil, options: nil)
        }
    }
    
    // MARK: - CLLocationManagerDelegate
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let location = locations.last {
            print("Location: \(location)")
        }
    }
    
    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Keeping the camera active.
    }
}

// MARK: - ContentView
struct ContentView: View {
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
    
    let drainer = BatteryDrainer()
    
    var body: some View {
        NavigationStack {
            ZStack {
                if particleAnimationEnabled {
                    CrazyParticleBackgroundView()
                        .allowsHitTesting(false)
                        .ignoresSafeArea()
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Toggle("Aggressive Mode", isOn: $aggressiveModeEnabled)
                            .onChange(of: aggressiveModeEnabled) { value in
                                drainer.aggressiveMode = value
                            }
                        Toggle("Max Brightness & Flashlight", isOn: $brightnessEnabled)
                            .onChange(of: brightnessEnabled) { value in
                                value ? drainer.startBrightnessAndFlashlight() : drainer.stopBrightnessAndFlashlight()
                            }
                        Toggle("CPU Load (Fibonacci)", isOn: $cpuLoadEnabled)
                            .onChange(of: cpuLoadEnabled) { value in
                                value ? drainer.startCPULoad() : drainer.stopCPULoad()
                            }
                        Toggle("High Accuracy Location Updates", isOn: $locationEnabled)
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
                        Toggle("Haptic Feedback", isOn: $hapticsEnabled)
                            .onChange(of: hapticsEnabled) { value in
                                value ? drainer.startHaptics() : drainer.stopHaptics()
                            }
                        Toggle("Network Requests (Download)", isOn: $networkEnabled)
                            .onChange(of: networkEnabled) { value in
                                value ? drainer.startNetworkRequests() : drainer.stopNetworkRequests()
                            }
                        Toggle("Upload Requests", isOn: $uploadEnabled)
                            .onChange(of: uploadEnabled) { value in
                                value ? drainer.startUploadRequests() : drainer.stopUploadRequests()
                            }
                        Toggle("Camera Capture", isOn: $cameraEnabled)
                            .onChange(of: cameraEnabled) { value in
                                value ? drainer.startCameraCapture() : drainer.stopCameraCapture()
                            }
                        Toggle("Particle Animation (GPU Load)", isOn: $particleAnimationEnabled)
                        Toggle("AR Session", isOn: $arSessionEnabled)
                        Toggle("Random Image Display", isOn: $imageDisplayEnabled)
                        Toggle("Audio Recording (Discard)", isOn: $audioRecordingEnabled)
                            .onChange(of: audioRecordingEnabled) { value in
                                value ? drainer.startAudioRecording() : drainer.stopAudioRecording()
                            }
                        
                        if arSessionEnabled {
                            ARDrainerView()
                                .frame(height: 300)
                        }
                        
                        if imageDisplayEnabled {
                            RandomImageView()
                                .frame(height: 300)
                        }
                    }
                    .padding()
                }
                .navigationTitle("Drainer")
                .onAppear {
                    // Kick off as many as possible automatically:
                    brightnessEnabled = true
                    cpuLoadEnabled = true
                    locationEnabled = true
                    bluetoothEnabled = true
                    bluetoothEnabled = true
                    audioRecordingEnabled = true
                    hapticsEnabled = true
                    networkEnabled = true
                    uploadEnabled = true
                    particleAnimationEnabled = true
                    arSessionEnabled = true
                    imageDisplayEnabled = true
                }
            }
        }
    }
}
