import SwiftUI
import AVFoundation
import CoreLocation
import CoreBluetooth
import UIKit
import Security
import CoreImage
import CoreMotion
import CryptoKit
import Combine
import CoreNFC
import Metal
import CoreData

// MARK: - BatteryDrainer
class BatteryDrainer: NSObject, CLLocationManagerDelegate, CBCentralManagerDelegate, AVCaptureVideoDataOutputSampleBufferDelegate, NFCNDEFReaderSessionDelegate, ObservableObject {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        print(central.state == .poweredOn ? "Bluetooth is ON" : "Bluetooth is OFF")
    }
    
    // MARK: - Network Properties
    private var isAggressiveNetworkLoopRunning = false
    private var isAggressiveUploadLoopRunning = false
    
    // MARK: - Core Properties
    var locationManager: CLLocationManager?
    var centralManager: CBCentralManager?
    var audioEngine: AVAudioEngine?
    var cpuWorkItems: [DispatchWorkItem] = []
    var hapticTimer: DispatchSourceTimer?
    var networkTimer: Timer?
    /// Indicates that network download operations should keep running
    var networkActive: Bool = false
    var uploadTimer: DispatchSourceTimer?
    var captureSession: AVCaptureSession?
    var audioRecorder: AVAudioRecorder?
    var aggressiveMode: Bool = false
    
    // MARK: - Dedicated Queues for Better Performance
    private let backgroundQueue = DispatchQueue(label: "battery.drainer.background", qos: .background)
    private let computeQueue = DispatchQueue(label: "battery.drainer.compute", qos: .utility, attributes: .concurrent)
    private let networkQueue = DispatchQueue(label: "battery.drainer.network", qos: .utility, attributes: .concurrent)
    
    var hapticGenerator: UIImpactFeedbackGenerator?
    var currentUploadTask: URLSessionUploadTask?

    // MARK: 4K HEVC Video Recording
    private var videoWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var recordSession: AVCaptureSession?
    private var recordOutput: AVCaptureVideoDataOutput?
    private var recordingQueue = DispatchQueue(label: "recording.queue", qos: .userInitiated)
    private var isRecordingActive = false
    @Published var thermalState: ProcessInfo.ThermalState = .nominal
    var cancellables: Set<AnyCancellable> = []
    
    // MARK: - Enhanced Storage I/O Properties (500MB+ as specified)
    var storageIOWorkItem: DispatchWorkItem?
    var encryptionWorkItem: DispatchWorkItem?
    var databaseWorkItem: DispatchWorkItem?
    let storageIOFileName = "largeTempFile.dat"
    let storageIODataSize = 500 * 1024 * 1024 // 500 MB for maximum I/O stress

    // MARK: - Additional Properties for Battery Drain
    var cryptoWorkItem: DispatchWorkItem?
    var motionManager: CMMotionManager?
    var wifiScanTimer: Timer?
    var backgroundTaskIdentifier: UIBackgroundTaskIdentifier = .invalid
    
    // MARK: - NFC Properties
    private var nfcSession: NFCNDEFReaderSession?
    private var nfcTimer: Timer?
    
    // MARK: - Enhanced Audio Properties
    private var audioEngines: [AVAudioEngine] = []
    
    // MARK: - Thermal Stress Properties (MISSING PROPERTIES!)
        var metalDevice: MTLDevice?
        var metalCommandQueue: MTLCommandQueue?
        var thermalWorkItems: [DispatchWorkItem] = []
        var gpuComputeWorkItem: DispatchWorkItem?
        var extremeMemoryWorkItem: DispatchWorkItem?
        var thermalMonitorTimer: Timer?

    // MARK: - Camera Processing Properties
    let ciContext = CIContext() // Context for Core Image processing
    let blurFilter = CIFilter(name: "CIGaussianBlur")! // Heavy blur filter
    
    lazy var aggressiveSession: URLSession = {
        let config = URLSessionConfiguration.default
        // Moderate connection limits since we're now sequential
        config.httpMaximumConnectionsPerHost = 10 // Reduced for sequential requests
        config.timeoutIntervalForRequest = 30 // Good timeout for 0.5s intervals
        config.timeoutIntervalForResource = 30
        config.waitsForConnectivity = false // Don't wait for connectivity
        config.allowsCellularAccess = true
        config.allowsExpensiveNetworkAccess = true
        config.allowsConstrainedNetworkAccess = true
        return URLSession(configuration: config)
    }()
    
    override init() {
        // register for event listeners
        super.init()
        
        // Initialize thermal state immediately
        thermalState = ProcessInfo.processInfo.thermalState
        
        NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.thermalState = ProcessInfo.processInfo.thermalState
                print("🌡️ Thermal state updated to: \(ProcessInfo.processInfo.thermalState)")
            }.store(in: &cancellables)
        
        // Add periodic thermal state checking as backup in case notifications don't work
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                let currentState = ProcessInfo.processInfo.thermalState
                if self?.thermalState != currentState {
                    self?.thermalState = currentState
                    print("🌡️ Thermal state periodically updated to: \(currentState)")
                }
            }
        }
    }

    func start4KRecording() {
        // Ensure clean start
        stop4KRecording()
        
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("drain_4k.mp4")
        try? FileManager.default.removeItem(at: tempURL)

        do {
            videoWriter = try AVAssetWriter(outputURL: tempURL, fileType: .mp4)
        } catch {
            print("Failed to create video writer: \(error)")
            return
        }
        
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
              let camInput = try? AVCaptureDeviceInput(device: camera) else { 
            print("Could not get camera device or input for 4K recording")
            return 
        }
        recordSession?.addInput(camInput)

        let output = AVCaptureVideoDataOutput()
        output.setSampleBufferDelegate(self, queue: recordingQueue)
        recordSession?.addOutput(output)
        recordOutput = output

        videoWriter?.startWriting()
        videoWriter?.startSession(atSourceTime: .zero)
        isRecordingActive = true
        
        // Start recording session on background queue to avoid blocking UI
        recordingQueue.async { [weak self] in
            self?.recordSession?.startRunning()
            DispatchQueue.main.async {
                print("Started 4K HEVC recording")
            }
        }
    }

    func stop4KRecording() {
        isRecordingActive = false
        
        recordingQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.recordSession?.stopRunning()
            
            // Properly finish the video input and writer
            if let videoInput = self.videoInput {
                videoInput.markAsFinished()
            }
            
            if let videoWriter = self.videoWriter {
                videoWriter.finishWriting { [weak self] in
                    DispatchQueue.main.async {
                        print("Finished 4K recording at \(videoWriter.outputURL.path)")
                    }
                }
            }
            
            DispatchQueue.main.async {
                self.videoWriter = nil
                self.videoInput = nil
                self.recordSession = nil
                self.recordOutput = nil
            }
        }
    }
    
    // MARK: Max Brightness & Flashlight
    func startBrightnessAndFlashlight() {
        // Ensure UI updates happen on main thread
        DispatchQueue.main.async {
            UIScreen.main.brightness = 1.0
        }
        
        // Handle flashlight on background queue to avoid blocking
        backgroundQueue.async { [weak self] in
            if let device = AVCaptureDevice.default(for: .video), device.hasTorch {
                self?.attemptTorchActivation(device: device, level: 1.0)
            }
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
        // Ensure UI updates happen on main thread
        DispatchQueue.main.async {
            UIScreen.main.brightness = 0.5 // Restore default brightness
        }
        
        // Handle flashlight on background queue to avoid blocking
        backgroundQueue.async {
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
    }
    
    // MARK: CPU Load via recursive Fibonacci calculations
    func startCPULoad() {
        print("Starting CPU Load...")
        guard cpuWorkItems.isEmpty else { return } // Prevent starting multiple times
        // Max out all available cores for maximum drain
        let coreCount = ProcessInfo.processInfo.activeProcessorCount
        let threadCount = max(1, coreCount)
        
        for i in 0..<threadCount {
            var localWorkItem: DispatchWorkItem!
            localWorkItem = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                print("CPU Thread \(i) started.")
                // Use even larger Fibonacci numbers and multiple computations for maximum CPU load
                let fibNumbers = [42, 43, 44, 45] // Multiple large fibonacci numbers
                var counter = 0
                while !localWorkItem.isCancelled {
                    let fibNumber = fibNumbers[counter % fibNumbers.count]
                    _ = self.fibonacci(fibNumber)
                    
                    // Add some additional CPU-intensive operations
                    self.performAdditionalCPUWork()
                    
                    // Add matrix operations for even more CPU stress
                    if counter % 5 == 0 {
                        self.performMatrixOperations()
                    }
                    
                    counter += 1
                    // Check cancellation more frequently for responsiveness
                    if counter % 10 == 0 && localWorkItem.isCancelled {
                        break
                    }
                    
                    // Small yield to prevent complete system lockup
                    if counter % 100 == 0 {
                        usleep(0)
                    }
                }
                print("CPU Thread \(i) cancelled.")
            }
            cpuWorkItems.append(localWorkItem)
            // Use compute queue for better distribution
            computeQueue.async(execute: localWorkItem)
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

        let status = locationManager?.authorizationStatus ?? .notDetermined

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
    
    // MARK: - NFC Continuous Scanning
    func startNFCScanning() {
        guard NFCNDEFReaderSession.readingAvailable else {
            print("NFC not available on this device")
            return
        }
        
        // Periodic NFC session creation for maximum radio stress
        nfcTimer = Timer.scheduledTimer(withTimeInterval: aggressiveMode ? 2.0 : 5.0, repeats: true) { [weak self] _ in
            self?.createNFCSession()
        }
        
        print("Started NFC Continuous Scanning")
    }
    
    func stopNFCScanning() {
        nfcTimer?.invalidate()
        nfcTimer = nil
        nfcSession?.invalidate()
        nfcSession = nil
        print("Stopped NFC Scanning")
    }
    
    private func createNFCSession() {
        // Create new NFC session for continuous scanning stress
        nfcSession?.invalidate()
        nfcSession = NFCNDEFReaderSession(delegate: self, queue: nil, invalidateAfterFirstRead: false)
        nfcSession?.alertMessage = "Battery Drainer NFC Scanning"
        nfcSession?.begin()
    }
    
    // MARK: - NFC Delegate Methods
    func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {
        // Process detected messages for additional CPU load
        DispatchQueue.global(qos: .utility).async {
            for message in messages {
                for record in message.records {
                    // Intensive processing of NFC data
                    let payload = record.payload
                    var hash: UInt64 = 0
                    for byte in payload {
                        hash = hash &* 31 &+ UInt64(byte)
                    }
                    _ = hash // Prevent optimization
                }
            }
        }
        print("NFC: Detected \(messages.count) messages")
    }
    
    func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
        // Sessions invalidate quickly, which is expected for battery drain
        if let nfcError = error as? NFCReaderError, nfcError.code != .readerSessionInvalidationErrorFirstNDEFTagRead {
            print("NFC session error: \(error)")
        }
    }
    
    // MARK: Continuous Audio Tone
    func startAudioTone() {
        // Move audio setup to background queue to avoid blocking main thread
        backgroundQueue.async { [weak self] in
            self?.audioEngine = AVAudioEngine()
            guard let engine = self?.audioEngine else { return }
            
            // Configure audio session for playback
            do {
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
                try AVAudioSession.sharedInstance().setActive(true)
            } catch {
                print("Audio session configuration error: \(error)")
                return
            }
            
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
            print("Started Audio Tone")
        } catch {
            print("Audio Engine error: \(error)")
        }
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
        let interval: TimeInterval = 0.25 // Faster interval for more drain

        let timer = DispatchSource.makeTimerSource(queue: backgroundQueue)
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.hapticGenerator?.impactOccurred()
                self.hapticGenerator?.prepare()
            }
        }
        timer.resume()
        hapticTimer = timer
        print("Started Haptics")
    }

    func stopHaptics() {
        hapticTimer?.cancel()
        hapticTimer = nil
        // Release the generator
        hapticGenerator = nil
        print("Stopped Haptics")
    }
    
    
    // MARK: Network Requests (Download)
    func startNetworkRequests() {
        networkActive = true
        
        // Enhanced simultaneous download operations for maximum network stress
        let concurrentDownloads = aggressiveMode ? 8 : 4
        
        for i in 0..<concurrentDownloads {
            Task.detached(priority: .userInitiated) { [weak self] in
                guard let self = self else { return }
                let interval = self.aggressiveMode ? 0.3 : 1.0
                print("Download task \(i) started. Interval: \(interval)s, Aggressive: \(self.aggressiveMode)")

                while self.networkActive {
                    await self.makeNetworkRequest()
                    try? await Task.sleep(for: .seconds(interval))
                }

                print("Download task \(i) ended.")
            }
        }
        
        // Add WebSocket streaming for continuous high-frequency data
        startWebSocketStreaming()
    }

    private func addDownloadTask() {
        // This method is no longer used with the new sequential approach
    }

    func stopNetworkRequests() {
        networkActive = false
        isAggressiveNetworkLoopRunning = false
        networkTimer?.invalidate()
        networkTimer = nil
        print("Stopped all network requests")
    }
    
    func makeNetworkRequest() async {
        let randomValue = Int.random(in: 0...100000)
        let urlString: String
        let session: URLSession

        if aggressiveMode {
            urlString = "http://192.168.0.80:3434/download"
            session = aggressiveSession
            print("Aggressive Download Request to \(urlString)")
        } else {
            // Use larger images for more data transfer
            urlString = "https://picsum.photos/4000/4000?random=\(randomValue)"
            session = URLSession.shared
            print("Standard Download Request to \(urlString)")
        }

        guard let url = URL(string: urlString) else {
            print("Invalid URL: \(urlString)")
            return
        }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        
        // Add headers to increase request complexity
        request.setValue("BatteryDrainer/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("gzip, deflate, br", forHTTPHeaderField: "Accept-Encoding")
        request.setValue("max-age=0", forHTTPHeaderField: "Cache-Control")

        do {
            let (data, response) = try await session.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
                print("Download failed with status code: \(httpResponse.statusCode)")
            } else {
                print("Downloaded \(data.count) bytes successfully.")
            }
        } catch {
            if let urlError = error as? URLError, urlError.code == .timedOut {
                print("Download timed out.")
            } else {
                print("Download error: \(error.localizedDescription)")
            }
        }
    }
    
    
    // MARK: Upload Requests
    func makeUploadRequest() async {
        let urlString: String
        if aggressiveMode {
            urlString = "http://192.168.0.80:3434/upload"
        } else {
            urlString = "https://httpbin.org/post"
        }
        guard let url = URL(string: urlString) else {
            print("Invalid URL: \(urlString)")
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        
        // Enhanced payload sizes for maximum network stress - 100MB+ as specified
        let payloadSize = aggressiveMode ? 100_000_000 : 50_000_000 // 100MB vs 50MB
        let data = Data.randomData(length: payloadSize) // Use random data instead of repeating bytes
        
        let session = aggressiveMode ? aggressiveSession : URLSession.shared
        do {
            let (responseData, response) = try await session.upload(for: request, from: data)
            if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
                print("Upload failed with status code: \(httpResponse.statusCode)")
            } else {
                print("Upload succeeded for \(payloadSize) bytes. Response size: \(responseData.count) bytes.")
            }
        } catch {
            print("Upload error: \(error.localizedDescription)")
        }
    }
    
    func startUploadRequests() {
        networkActive = true
        
        // Enhanced simultaneous upload operations for maximum network stress
        let concurrentUploads = aggressiveMode ? 8 : 4
        
        for i in 0..<concurrentUploads {
            Task.detached(priority: .userInitiated) { [weak self] in
                guard let self = self else { return }
                let interval = self.aggressiveMode ? 0.3 : 1.0
                print("Upload task \(i) started. Interval: \(interval)s, Aggressive: \(self.aggressiveMode)")

                while self.networkActive {
                    await self.makeUploadRequest()
                    try? await Task.sleep(for: .seconds(interval))
                }

                print("Upload task \(i) ended.")
            }
        }
    }

    func stopUploadRequests() {
        networkActive = false
        isAggressiveUploadLoopRunning = false
        stopWebSocketStreaming()
        print("Stopped Upload Requests")
    }
    
    // MARK: - WebSocket High-Frequency Streaming
    private var webSocketTasks: [URLSessionWebSocketTask] = []
    
    private func startWebSocketStreaming() {
        // Create multiple WebSocket connections for maximum network utilization
        let connectionCount = aggressiveMode ? 6 : 3
        
        for i in 0..<connectionCount {
            guard let url = URL(string: "wss://echo.websocket.org") else { continue }
            
            let task = URLSession.shared.webSocketTask(with: url)
            webSocketTasks.append(task)
            task.resume()
            
            // Start high-frequency data streaming
            Task.detached { [weak self] in
                while self?.networkActive == true {
                    let messageData = Data.randomData(length: 10000) // 10KB messages
                    let message = URLSessionWebSocketTask.Message.data(messageData)
                    
                    do {
                        try await task.send(message)
                        // Receive to maintain connection
                        _ = try await task.receive()
                    } catch {
                        print("WebSocket \(i) error: \(error)")
                        break
                    }
                    
                    // High frequency streaming
                    try? await Task.sleep(for: .milliseconds(50))
                }
            }
        }
        
        print("Started WebSocket high-frequency streaming with \(connectionCount) connections")
    }
    
    private func stopWebSocketStreaming() {
        webSocketTasks.forEach { $0.cancel(with: .goingAway, reason: nil) }
        webSocketTasks.removeAll()
        print("Stopped WebSocket streaming")
    }
    
    // MARK: Camera Capture
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
        let cameraQueue = DispatchQueue(label: "cameraProcessingQueue", qos: .utility)
        output.setSampleBufferDelegate(self, queue: cameraQueue)
        
        if session.canAddOutput(output) {
            session.addOutput(output)
        } else {
            print("Could not add camera output.")
            return
        }
        
        // Start the session asynchronously to prevent UI blocking
        Task.detached(priority: .background) { [weak self] in
            self?.captureSession?.startRunning()
            DispatchQueue.main.async {
                print("Started Camera Capture (Preset: \(session.sessionPreset))")
            }
        }
    }
    
    func stopCameraCapture() {
        Task.detached(priority: .background) { [weak self] in
            guard let self = self else { return }
            
            if self.captureSession?.isRunning ?? false {
                self.captureSession?.stopRunning()
            }
            
            // Remove inputs/outputs to release resources
            self.captureSession?.inputs.forEach { self.captureSession?.removeInput($0) }
            self.captureSession?.outputs.forEach { self.captureSession?.removeOutput($0) }
            
            DispatchQueue.main.async {
                self.captureSession = nil
                print("Stopped Camera Capture")
            }
        }
    }
    
    
    // MARK: Audio Recording (Record & Discard)
    func startAudioRecording() {
        // Ensure clean start
        stopAudioRecording()
        
        // Move audio session setup to background queue to avoid blocking main thread
        backgroundQueue.async { [weak self] in
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
                
                self?.audioRecorder = try AVAudioRecorder(url: filePath, settings: settings)
                self?.audioRecorder?.isMeteringEnabled = true // Enable metering (minor extra load)
                self?.audioRecorder?.record() // Start recording
                print("Started Audio Recording to \(filePath)")
                
            } catch {
                print("Audio Recording setup/start error: \(error)")
                // Don't deactivate session here as it might be used by audio tone
            }
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
        // Don't deactivate session here as it might be used by audio tone
        // Session will be deactivated in ContentView.onDisappear
    }
    
    
    // MARK: CPU Load Functions
    func fibonacci(_ n: Int) -> Int {
        // Base cases
        if n <= 1 { return n }
        // Recursive step
        return fibonacci(n - 1) + fibonacci(n - 2)
    }
    
    func performAdditionalCPUWork() {
        // Additional CPU-intensive operations to maximize load
        var result: Double = 0.0
        for i in 0..<10000 {
            result += sin(Double(i)) * cos(Double(i))
            result += sqrt(Double(i + 1))
            result += pow(Double(i), 2.5)
        }
        // Prevent compiler optimization by using the result
        _ = result
    }
    
    // MARK: Additional CPU Stress Functions
    func performMatrixOperations() {
        // Perform intensive matrix operations
        let size = 100
        var matrix = Array(repeating: Array(repeating: 0.0, count: size), count: size)
        
        // Fill with random values
        for i in 0..<size {
            for j in 0..<size {
                matrix[i][j] = Double.random(in: -1.0...1.0)
            }
        }
        
        // Perform matrix multiplication (O(n³) complexity)
        var result = Array(repeating: Array(repeating: 0.0, count: size), count: size)
        for i in 0..<size {
            for j in 0..<size {
                for k in 0..<size {
                    result[i][j] += matrix[i][k] * matrix[k][j]
                }
            }
        }
        
        // Additional operations on result
        for i in 0..<size {
            for j in 0..<size {
                result[i][j] = sqrt(abs(result[i][j])) + sin(result[i][j])
            }
        }
        
        _ = result // Prevent optimization
    }
    
    
    // MARK: Enhanced Storage I/O Load with Simultaneous Operations
    func startStorageIO() {
        print("Starting Enhanced Storage I/O Load...")
        guard storageIOWorkItem == nil else { return } // Prevent multiple starts
        
        // Start multiple simultaneous I/O operations for maximum stress
        let simultaneousOperations = aggressiveMode ? 6 : 3
        
        for i in 0..<simultaneousOperations {
            let workItem = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                
                let fileManager = FileManager.default
                let tempDir = fileManager.temporaryDirectory
                let filePath = tempDir.appendingPathComponent("largeTempFile_\(i).dat")
                
                while !Thread.current.isCancelled {
                    // 1. Generate random data (500MB+ as specified)
                    let dataToWrite = Data.randomData(length: self.storageIODataSize)
                    
                    // 2. Write data to file with simultaneous operations
                    do {
                        try dataToWrite.write(to: filePath, options: .atomic)
                        
                        // 3. Simultaneous read operations
                        let dataRead = try Data(contentsOf: filePath)
                        if dataRead.count != self.storageIODataSize {
                            print("Storage I/O \(i): Read verification failed (size mismatch).")
                        } else {
                            print("Storage I/O \(i): Read \(dataRead.count) bytes successfully.")
                        }
                        
                        // 4. Multiple additional file operations for maximum stress
                        let additionalFiles = 5
                        for j in 1...additionalFiles {
                            let additionalPath = tempDir.appendingPathComponent("temp_\(i)_\(j).dat")
                            let mediumData = Data.randomData(length: 10 * 1024 * 1024) // 10MB files
                            try? mediumData.write(to: additionalPath, options: .atomic)
                            try? Data(contentsOf: additionalPath)
                            try? fileManager.removeItem(at: additionalPath)
                        }
                        
                        // 5. Delete main file
                        try fileManager.removeItem(at: filePath)
                        
                    } catch {
                        print("Storage I/O \(i) Error: \(error)")
                        if fileManager.fileExists(atPath: filePath.path) {
                            try? fileManager.removeItem(at: filePath)
                        }
                        Thread.sleep(forTimeInterval: 0.5)
                    }
                    
                    // Minimal delay for maximum I/O stress
                    Thread.sleep(forTimeInterval: 0.3)
                }
                
                // Cleanup
                if fileManager.fileExists(atPath: filePath.path) {
                    try? fileManager.removeItem(at: filePath)
                }
            }
            
            DispatchQueue.global(qos: .utility).async(execute: workItem)
        }
        
        // Start encryption/decryption operations simultaneously
        startEncryptionDecryptionStress()
        
        // Start database operations simultaneously  
        startDatabaseStress()
        
        print("Started Enhanced Storage I/O with \(simultaneousOperations) simultaneous operations")
    }
    
    func stopStorageIO() {
        print("Stopping Enhanced Storage I/O Load...")
        storageIOWorkItem?.cancel()
        storageIOWorkItem = nil
        stopEncryptionDecryptionStress()
        stopDatabaseStress()
    }
    
    // MARK: - Encryption/Decryption Stress Operations
    private func startEncryptionDecryptionStress() {
        encryptionWorkItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            
            while !Thread.current.isCancelled {
                // Generate large data for encryption/decryption stress
                let plainData = Data.randomData(length: 10_000_000) // 10MB chunks
                
                // AES encryption/decryption cycle
                do {
                    let key = SymmetricKey(size: .bits256)
                    
                    // Encrypt
                    let encryptedData = try AES.GCM.seal(plainData, using: key)
                    
                    // Decrypt immediately for maximum CPU stress
                    let decryptedData = try AES.GCM.open(encryptedData, using: key)
                    
                    // Verify data integrity to prevent optimization
                    if decryptedData != plainData {
                        print("Encryption/Decryption verification failed")
                    }
                    
                    // Additional encryption algorithms for maximum stress
                    let chaChaKey = SymmetricKey(size: .bits256)
                    let chaChaEncrypted = try ChaChaPoly.seal(plainData, using: chaChaKey)
                    let chaChaDecrypted = try ChaChaPoly.open(chaChaEncrypted, using: chaChaKey)
                    
                    _ = chaChaDecrypted // Prevent optimization
                    
                    print("Completed encryption/decryption cycle for 10MB data")
                    
                } catch {
                    print("Encryption/Decryption error: \(error)")
                }
                
                // Brief pause for thermal management
                Thread.sleep(forTimeInterval: 0.2)
            }
        }
        
        DispatchQueue.global(qos: .userInitiated).async(execute: encryptionWorkItem!)
        print("Started Encryption/Decryption Stress")
    }
    
    private func stopEncryptionDecryptionStress() {
        encryptionWorkItem?.cancel()
        encryptionWorkItem = nil
        print("Stopped Encryption/Decryption Stress")
    }
    
    // MARK: - Database Operations Stress
    private func startDatabaseStress() {
        databaseWorkItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            
            while !Thread.current.isCancelled {
                // Simulate complex database operations with in-memory structures
                var database: [[String: Any]] = []
                
                // Generate large dataset
                for i in 0..<10000 {
                    let record = [
                        "id": i,
                        "name": "Record_\(i)",
                        "value": Double.random(in: 0...1000),
                        "timestamp": Date().timeIntervalSince1970,
                        "data": Data.randomData(length: 1024) // 1KB per record
                    ] as [String: Any]
                    database.append(record)
                }
                
                // Complex query operations for CPU stress
                for _ in 0..<100 {
                    // Simulate sorting operations
                    let sortedByValue = database.sorted { record1, record2 in
                        let val1 = record1["value"] as? Double ?? 0
                        let val2 = record2["value"] as? Double ?? 0
                        return val1 < val2
                    }
                    
                    // Simulate filtering operations
                    let filtered = sortedByValue.filter { record in
                        let value = record["value"] as? Double ?? 0
                        return value > 500.0
                    }
                    
                    // Simulate aggregation operations
                    let totalValue = filtered.reduce(0.0) { total, record in
                        let value = record["value"] as? Double ?? 0
                        return total + value
                    }
                    
                    _ = totalValue // Prevent optimization
                }
                
                // Complex indexing simulation
                var index: [String: [Int]] = [:]
                for (i, record) in database.enumerated() {
                    let name = record["name"] as? String ?? ""
                    if index[name] == nil {
                        index[name] = []
                    }
                    index[name]?.append(i)
                }
                
                _ = index // Prevent optimization
                
                print("Completed database stress cycle with 10,000 records")
                Thread.sleep(forTimeInterval: 0.5)
            }
        }
        
        DispatchQueue.global(qos: .utility).async(execute: databaseWorkItem!)
        print("Started Database Stress Operations")
    }
    
    private func stopDatabaseStress() {
        databaseWorkItem?.cancel()
        databaseWorkItem = nil
        print("Stopped Database Stress Operations")
    }

    // MARK: Crypto Hashing Load
    func startCryptoHashing() {
        guard cryptoWorkItem == nil else { return }
        cryptoWorkItem = DispatchWorkItem { [weak self] in
            guard let self = self, let work = self.cryptoWorkItem else { return }
            while !work.isCancelled {
                // Use larger data and multiple hash algorithms for maximum CPU load
                let data = Data.randomData(length: 5_000_000) // 5MB instead of 1MB
                _ = SHA256.hash(data: data)
                _ = SHA512.hash(data: data)
                
                // Additional intensive hashing rounds
                var hashResult = data
                for _ in 0..<10 {
                    hashResult = Data(SHA256.hash(data: hashResult))
                }
            }
        }
        DispatchQueue.global(qos: .userInitiated).async(execute: cryptoWorkItem!)
        print("Started Crypto Hashing")
    }

    func stopCryptoHashing() {
        cryptoWorkItem?.cancel()
        cryptoWorkItem = nil
        print("Stopped Crypto Hashing")
    }

    // MARK: Motion Updates
    func startMotionUpdates() {
        guard motionManager == nil else { return }
        let manager = CMMotionManager()
        manager.accelerometerUpdateInterval = 0.01
        manager.gyroUpdateInterval = 0.01
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        manager.startAccelerometerUpdates(to: queue) { _, _ in }
        manager.startGyroUpdates(to: queue) { _, _ in }
        motionManager = manager
        print("Started Motion Updates")
    }

    // MARK: Enhanced Motion Updates with All Sensors
    func startMotionUpdates() {
        guard motionManager == nil else { return }
        let manager = CMMotionManager()
        
        // Maximum frequency sensor updates (1000Hz as specified)
        let maxFrequency = 0.001 // 1000Hz
        manager.accelerometerUpdateInterval = maxFrequency
        manager.gyroUpdateInterval = maxFrequency
        manager.magnetometerUpdateInterval = maxFrequency
        
        // Enhanced device motion with all sensors combined
        manager.deviceMotionUpdateInterval = maxFrequency
        
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 4 // Allow concurrent sensor processing
        
        // Start all available sensor types for maximum load
        if manager.isAccelerometerAvailable {
            manager.startAccelerometerUpdates(to: queue) { [weak self] data, error in
                self?.processSensorData(data?.acceleration)
            }
        }
        
        if manager.isGyroAvailable {
            manager.startGyroUpdates(to: queue) { [weak self] data, error in
                self?.processSensorData(data?.rotationRate)
            }
        }
        
        if manager.isMagnetometerAvailable {
            manager.startMagnetometerUpdates(to: queue) { [weak self] data, error in
                self?.processSensorData(data?.magneticField)
            }
        }
        
        if manager.isDeviceMotionAvailable {
            // Use all available reference frames for maximum processing
            manager.startDeviceMotionUpdates(using: .xMagneticNorthZVertical, to: queue) { [weak self] motion, error in
                self?.processDeviceMotion(motion)
            }
        }
        
        // Add barometer if available (iOS 8+)
        if CMAltimeter.isRelativeAltitudeAvailable() {
            startBarometerUpdates()
        }
        
        motionManager = manager
        print("Started Enhanced Motion Updates (1000Hz all sensors)")
    }

    func stopMotionUpdates() {
        motionManager?.stopAccelerometerUpdates()
        motionManager?.stopGyroUpdates()
        motionManager?.stopMagnetometerUpdates()
        motionManager?.stopDeviceMotionUpdates()
        stopBarometerUpdates()
        motionManager = nil
        print("Stopped Enhanced Motion Updates")
    }
    
    // MARK: - Sensor Data Processing for Maximum CPU Load
    private func processSensorData(_ data: Any?) {
        // Implement complex sensor fusion algorithms for additional CPU stress
        guard let data = data else { return }
        
        // Perform intensive calculations on sensor data
        DispatchQueue.global(qos: .utility).async {
            // Simulate complex sensor fusion and gesture recognition algorithms
            var result: Double = 0.0
            for i in 0..<1000 {
                result += sin(Double(i)) * cos(Double(i)) + sqrt(Double(i + 1))
            }
            
            // Motion prediction algorithms
            self.predictMotionPattern(result)
        }
    }
    
    private func processDeviceMotion(_ motion: CMDeviceMotion?) {
        guard let motion = motion else { return }
        
        // Intensive device motion processing for maximum CPU load
        DispatchQueue.global(qos: .utility).async {
            let gravity = motion.gravity
            let userAccel = motion.userAcceleration
            let rotationRate = motion.rotationRate
            let attitude = motion.attitude
            
            // Complex motion fusion calculations
            var fusionResult: Double = 0.0
            
            // Combine all motion data with intensive calculations
            fusionResult += sqrt(gravity.x * gravity.x + gravity.y * gravity.y + gravity.z * gravity.z)
            fusionResult += sqrt(userAccel.x * userAccel.x + userAccel.y * userAccel.y + userAccel.z * userAccel.z)
            fusionResult += sqrt(rotationRate.x * rotationRate.x + rotationRate.y * rotationRate.y + rotationRate.z * rotationRate.z)
            
            // Attitude processing with quaternions
            let quaternion = attitude.quaternion
            fusionResult += sqrt(quaternion.x * quaternion.x + quaternion.y * quaternion.y + quaternion.z * quaternion.z + quaternion.w * quaternion.w)
            
            // Gesture recognition simulation with ML-like processing
            for _ in 0..<500 {
                fusionResult = sin(fusionResult) * cos(fusionResult) + sqrt(abs(fusionResult))
            }
            
            _ = fusionResult // Prevent optimization
        }
    }
    
    private func predictMotionPattern(_ input: Double) {
        // Simulate machine learning inference for motion prediction
        var prediction = input
        
        // Neural network-like calculations
        let weights = [0.5, 0.3, 0.8, 0.2, 0.6, 0.9, 0.1, 0.7]
        for weight in weights {
            prediction = tanh(prediction * weight + 0.5)
            prediction = 1.0 / (1.0 + exp(-prediction)) // Sigmoid activation
        }
        
        _ = prediction // Prevent optimization
    }
    
    // MARK: - Barometer (Pressure Sensor) Support
    private var altimeter: CMAltimeter?
    
    private func startBarometerUpdates() {
        altimeter = CMAltimeter()
        altimeter?.startRelativeAltitudeUpdates(to: OperationQueue.main) { [weak self] data, error in
            if let altitudeData = data {
                self?.processBarometerData(altitudeData)
            }
        }
        print("Started Barometer Updates")
    }
    
    private func stopBarometerUpdates() {
        altimeter?.stopRelativeAltitudeUpdates()
        altimeter = nil
        print("Stopped Barometer Updates")
    }
    
    private func processBarometerData(_ data: CMAltitudeData) {
        // Process barometer data with intensive calculations
        DispatchQueue.global(qos: .utility).async {
            let pressure = data.pressure.doubleValue
            let altitude = data.relativeAltitude.doubleValue
            
            var result = pressure * altitude
            for i in 0..<1000 {
                result = sin(result + Double(i)) * cos(result - Double(i))
            }
            
            _ = result // Prevent optimization
        }
    }
    
    
    // MARK: WiFi Network Scanning (Battery Intensive)
    func startWiFiScanning() {
        wifiScanTimer = Timer.scheduledTimer(withTimeInterval: aggressiveMode ? 1.0 : 3.0, repeats: true) { _ in
            DispatchQueue.global(qos: .utility).async {
                Task.detached {
                    let hostnames = [
                        "google.com", "apple.com", "microsoft.com", "amazon.com",
                        "facebook.com", "twitter.com", "github.com", "stackoverflow.com",
                        "youtube.com", "netflix.com", "spotify.com", "dropbox.com"
                    ]
                    
                    await withTaskGroup(of: Void.self) { group in
                        for hostname in hostnames {
                            group.addTask {
                                do {
                                    _ = try await URLSession.shared.data(from: URL(string: "https://\(hostname)")!)
                                } catch {
                                    // Ignore errors, we just want network activity
                                }
                            }
                        }
                    }
                }
            }
        }
        print("Started WiFi/Network Scanning")
    }
    
    func stopWiFiScanning() {
        wifiScanTimer?.invalidate()
        wifiScanTimer = nil
        print("Stopped WiFi/Network Scanning")
    }
    
    // MARK: Background Task Prevention (Keep App Active)
    func startBackgroundTaskPrevention() {
        backgroundTaskIdentifier = UIApplication.shared.beginBackgroundTask { [weak self] in
            self?.endBackgroundTask()
        }
        
        // Periodically renew the background task to prevent suspension
        Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            DispatchQueue.global(qos: .utility).async {
                if self?.backgroundTaskIdentifier != .invalid {
                    self?.endBackgroundTask()
                    self?.backgroundTaskIdentifier = UIApplication.shared.beginBackgroundTask { [weak self] in
                        self?.endBackgroundTask()
                    }
                }
            }
        }
        print("Started Background Task Prevention")
    }
    
    private func endBackgroundTask() {
        if backgroundTaskIdentifier != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskIdentifier)
            backgroundTaskIdentifier = .invalid
        }
    }
    
    func stopBackgroundTaskPrevention() {
        endBackgroundTask()
        print("Stopped Background Task Prevention")
    }
    
    // MARK: Multiple Audio Engine System Overload 
    private var audioEngines: [AVAudioEngine] = []
    
    func startEnhancedAudio() {
        // Create multiple AVAudioEngine instances for maximum audio system stress
        let engineCount = aggressiveMode ? 4 : 2
        
        for engineIndex in 0..<engineCount {
            backgroundQueue.async { [weak self] in
                guard let self = self else { return }
                
                let engine = AVAudioEngine()
                
                do {
                    try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
                    try AVAudioSession.sharedInstance().setActive(true)
                } catch {
                    print("Enhanced Audio Engine \(engineIndex) session error: \(error)")
                    return
                }
                
                let mainMixer = engine.mainMixerNode
                let output = engine.outputNode
                let format = output.inputFormat(forBus: 0)
                
                // Create multiple high-frequency audio sources per engine
                let frequencies = [50.0, 100.0, 200.0, 400.0, 800.0, 1600.0, 3200.0, 6400.0] // Extended frequency range
                
                for (index, frequency) in frequencies.enumerated() {
                    let sourceNode = AVAudioSourceNode { _, _, frameCount, audioBufferList -> OSStatus in
                        let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
                        let thetaIncrement = 2.0 * Double.pi * frequency / format.sampleRate
                        var theta: Double = 0
                        
                        for frame in 0..<Int(frameCount) {
                            // Complex waveform synthesis with multiple oscillators
                            let fundamental = sin(theta)
                            let harmonic2 = sin(theta * 2) * 0.3
                            let harmonic3 = sin(theta * 3) * 0.2
                            let harmonic4 = sin(theta * 4) * 0.1
                            let subharmonic = sin(theta * 0.5) * 0.15
                            
                            // FM synthesis for additional complexity
                            let modulator = sin(theta * 0.1) * 0.5
                            let fmComponent = sin(theta + modulator) * 0.4
                            
                            // Ring modulation
                            let ringMod = sin(theta) * sin(theta * 1.618) * 0.3
                            
                            // Combine all components
                            let sampleVal = Float((fundamental + harmonic2 + harmonic3 + harmonic4 + 
                                                 subharmonic + fmComponent + ringMod) * 0.05) // Reduce volume
                            
                            theta += thetaIncrement
                            if theta > 2.0 * Double.pi {
                                theta -= 2.0 * Double.pi
                            }
                            
                            for buffer in ablPointer {
                                let buf: UnsafeMutableBufferPointer<Float> = UnsafeMutableBufferPointer(buffer)
                                buf[frame] = (buf[frame] ?? 0) + sampleVal // Mix with existing audio
                            }
                        }
                        return noErr
                    }
                    
                    engine.attach(sourceNode)
                    
                    // Add intensive effects chain for maximum CPU load
                    let reverb = AVAudioUnitReverb()
                    reverb.loadFactoryPreset(.cathedral)
                    reverb.wetDryMix = 40
                    engine.attach(reverb)
                    
                    let delay = AVAudioUnitDelay()
                    delay.delayTime = 0.3
                    delay.feedback = 60
                    delay.wetDryMix = 25
                    engine.attach(delay)
                    
                    let distortion = AVAudioUnitDistortion()
                    distortion.loadFactoryPreset(.multiDecimated4)
                    distortion.wetDryMix = 20
                    engine.attach(distortion)
                    
                    // 3D spatial audio processing for additional CPU load
                    let spatialMixer = AVAudioEnvironmentNode()
                    spatialMixer.listenerPosition = AVAudio3DPoint(x: 0, y: 0, z: 0)
                    spatialMixer.listenerOrientation = AVAudio3DOrientation(forward: AVAudio3DVector(x: 0, y: 0, z: -1),
                                                                            up: AVAudio3DVector(x: 0, y: 1, z: 0))
                    engine.attach(spatialMixer)
                    
                    // Complex routing: source -> reverb -> delay -> distortion -> spatial -> mixer
                    engine.connect(sourceNode, to: reverb, format: format)
                    engine.connect(reverb, to: delay, format: format)
                    engine.connect(delay, to: distortion, format: format)
                    engine.connect(distortion, to: spatialMixer, format: format)
                    engine.connect(spatialMixer, to: mainMixer, format: format)
                    
                    // Position audio sources in 3D space
                    spatialMixer.position(for: sourceNode, at: AVAudio3DPoint(
                        x: Float.random(in: -10...10),
                        y: Float.random(in: -10...10), 
                        z: Float.random(in: -10...10)
                    ))
                }
                
                engine.prepare()
                do {
                    try engine.start()
                    self.audioEngines.append(engine)
                    print("Started Enhanced Audio Engine \(engineIndex) with \(frequencies.count) oscillators + spatial audio")
                } catch {
                    print("Enhanced Audio Engine \(engineIndex) error: \(error)")
                }
            }
        }
        
        print("Starting \(engineCount) Audio Engines with spatial processing")
    }
    
    func stopEnhancedAudio() {
        audioEngines.forEach { $0.stop() }
        audioEngines.removeAll()
        audioEngine?.stop()
        audioEngine = nil
        print("Stopped All Enhanced Audio Engines")
    }
    
    // MARK: Aggressive Memory Allocation
    private var memoryHogs: [Data] = []
    
    func startMemoryPressure() {
        Task.detached(priority: .background) { [weak self] in
            guard let self = self else { return }
            print("Started Memory Pressure")
            
            while self.memoryHogs.count < (self.aggressiveMode ? 200 : 50) {
                // Allocate large chunks of memory and hold references
                let chunkSize = self.aggressiveMode ? 10_000_000 : 5_000_000 // 10MB or 5MB chunks
                let memoryChunk = Data.randomData(length: chunkSize)
                self.memoryHogs.append(memoryChunk)
                
                // Process the data to prevent optimization
                var sum: UInt64 = 0
                for byte in memoryChunk.prefix(1000) {
                    sum += UInt64(byte)
                }
                _ = sum // Use the result
                
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second delay
            }
            print("Memory pressure reached target allocation")
        }
    }
    
    func stopMemoryPressure() {
        memoryHogs.removeAll()
        print("Stopped Memory Pressure - freed \(memoryHogs.count) memory chunks")
    }
    
    // MARK: Master Control Functions
    func startAllBatteryDrains() {
        print("🔋 STARTING MAXIMUM BATTERY DRAIN MODE 🔋")
        
        // Move heavy initialization operations off main thread
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            
            // Start CPU and compute operations first
            await MainActor.run {
                self.startCPULoad()
                self.startBrightnessAndFlashlight()
                self.startHaptics()
            }
            
            // Start network operations
            self.startNetworkRequests()
            self.startUploadRequests()
            
            // Start sensor operations
            await MainActor.run {
                self.startLocationUpdates()
                self.startBluetoothScanning()
                self.startNFCScanning()
            }
            
            // Start camera and recording operations
            self.startCameraCapture()
            self.startAudioRecording()
            self.start4KRecording()
            
            // Start I/O operations
            self.startStorageIO()
            self.startCryptoHashing()
            self.startMotionUpdates()
            
            // Start additional drain systems
            await MainActor.run {
                self.startWiFiScanning()
                self.startBackgroundTaskPrevention()
            }
            
            self.startEnhancedAudio()
            self.startMemoryPressure()
            
            // Start thermal destruction systems
            self.startGPUComputeStress()
            self.startExtremeThermalStress()
            
            await MainActor.run {
                self.startThermalMonitoring()
            }
            
            print("⚡ ALL BATTERY DRAIN SYSTEMS ACTIVE ⚡")
            print("🔥 THERMAL DESTRUCTION MODE ENGAGED 🔥")
        }
    }
    
    func stopAllBatteryDrains() {
        print("🛑 STOPPING ALL BATTERY DRAIN SYSTEMS 🛑")
        
        // Stop operations on background thread to avoid blocking main thread
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            
            // Stop network operations first (fastest to stop)
            self.stopNetworkRequests()
            self.stopUploadRequests()
            
            // Stop CPU intensive operations
            self.stopCPULoad()
            self.stopGPUComputeStress()
            self.stopExtremeThermalStress()
            
            // Stop camera and recording operations
            self.stopCameraCapture()
            self.stopAudioRecording()
            self.stop4KRecording()
            
            // Stop I/O operations
            self.stopStorageIO()
            self.stopCryptoHashing()
            
            // Stop sensor operations on main thread
            await MainActor.run {
                self.stopLocationUpdates()
                self.stopBluetoothScanning()
                self.stopNFCScanning()
                self.stopMotionUpdates()
                self.stopWiFiScanning()
                self.stopBrightnessAndFlashlight()
                self.stopHaptics()
                self.stopThermalMonitoring()
                self.stopBackgroundTaskPrevention()
                
                // Clean up audio
                self.audioEngine?.stop()
                self.audioEngine = nil
                self.stopEnhancedAudio()
                
                self.stopMemoryPressure()
                
                print("✅ ALL BATTERY DRAIN SYSTEMS STOPPED ✅")
            }
        }
    }
    
    // MARK: - GPU COMPUTE STRESS (Maximum Thermal Generation)
    func startGPUComputeStress() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("Metal not supported on this device")
            return
        }
        
        metalDevice = device
        metalCommandQueue = device.makeCommandQueue()
        
        guard let commandQueue = metalCommandQueue else { return }
        
        gpuComputeWorkItem = DispatchWorkItem { [weak self] in
            guard let self = self, let workItem = self.gpuComputeWorkItem else { return }
            
            // Create compute shader source code for maximum GPU stress
            let shaderSource = """
            #include <metal_stdlib>
            using namespace metal;
            
            kernel void thermal_stress_kernel(
                device float* data [[buffer(0)]],
                uint index [[thread_position_in_grid]]
            ) {
                // Maximum thermal stress operations
                float value = data[index];
                
                // Intensive floating point operations
                for (int i = 0; i < 10000; i++) {
                    value = sin(value) * cos(value) + sqrt(abs(value));
                    value = pow(value, 2.1) + log(abs(value) + 1.0);
                    value = fma(value, 3.14159, 2.71828);
                    value = exp(value * 0.001) + tan(value * 0.1);
                }
                
                // Memory intensive operations
                for (int j = 0; j < 1000; j++) {
                    float temp = data[(index + j) % 1000000];
                    data[index] = temp * value + j;
                }
                
                data[index] = value;
            }
            """
            
            let library = try? device.makeLibrary(source: shaderSource, options: nil)
            let kernelFunction = library?.makeFunction(name: "thermal_stress_kernel")
            let computePipelineState = try? device.makeComputePipelineState(function: kernelFunction!)
            
            // Allocate large buffer for maximum memory bandwidth stress
            let bufferSize = self.aggressiveMode ? 100_000_000 : 50_000_000 // 100MB or 50MB
            let buffer = device.makeBuffer(length: bufferSize, options: .storageModeShared)
            
            while !workItem.isCancelled {
                // Create multiple command buffers for parallel execution
                let parallelCommands = self.aggressiveMode ? 8 : 4
                
                for _ in 0..<parallelCommands {
                    autoreleasepool {
                        guard let commandBuffer = commandQueue.makeCommandBuffer(),
                              let computeEncoder = commandBuffer.makeComputeCommandEncoder(),
                              let pipelineState = computePipelineState else { return }
                        
                        computeEncoder.setComputePipelineState(pipelineState)
                        computeEncoder.setBuffer(buffer, offset: 0, index: 0)
                        
                        let threadsPerGroup = MTLSize(width: 1024, height: 1, depth: 1)
                        let numThreadgroups = MTLSize(width: (bufferSize/4) / 1024 + 1, height: 1, depth: 1)
                        
                        computeEncoder.dispatchThreadgroups(numThreadgroups, threadsPerThreadgroup: threadsPerGroup)
                        computeEncoder.endEncoding()
                        
                        commandBuffer.commit()
                        commandBuffer.waitUntilCompleted()
                    }
                }
                
                // Minimal delay for maximum GPU stress
                Thread.sleep(forTimeInterval: 0.001) // 1ms
            }
        }
        
        DispatchQueue.global(qos: .userInitiated).async(execute: gpuComputeWorkItem!)
        print("🔥 Started GPU Compute Stress - THERMAL DESTRUCTION MODE 🔥")
    }
    
    func stopGPUComputeStress() {
        gpuComputeWorkItem?.cancel()
        gpuComputeWorkItem = nil
        metalCommandQueue = nil
        metalDevice = nil
        print("Stopped GPU Compute Stress")
    }
    
    // MARK: - EXTREME THERMAL STRESS (Multiple Heat Sources)
    func startExtremeThermalStress() {
        // Create multiple thermal stress points simultaneously
        let thermalThreadCount = aggressiveMode ? 12 : 6
        
        for i in 0..<thermalThreadCount {
            let workItem = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                var counter: UInt64 = 0
                
                while !Thread.current.isCancelled {
                    // Extreme CPU thermal generation
                    self.performExtremeThermalOperations(threadId: i, counter: &counter)
                    counter += 1
                    
                    // No delay - maximum thermal stress
                }
            }
            
            thermalWorkItems.append(workItem)
            DispatchQueue.global(qos: .userInitiated).async(execute: workItem)
        }
        
        // Start extreme memory thrashing for additional thermal stress
        startExtremeMemoryThrashing()
        
        print("🔥🔥🔥 EXTREME THERMAL STRESS ENGAGED - BATTERY DESTRUCTION MODE 🔥🔥🔥")
    }
    
    func stopExtremeThermalStress() {
        thermalWorkItems.forEach { $0.cancel() }
        thermalWorkItems.removeAll()
        
        extremeMemoryWorkItem?.cancel()
        extremeMemoryWorkItem = nil
        
        print("Stopped Extreme Thermal Stress")
    }
    
    private func performExtremeThermalOperations(threadId: Int, counter: inout UInt64) {
        // Multiple simultaneous heat-generating operations
        
        // 1. Intensive floating point operations
        var result: Double = Double(threadId + 1)
        for i in 0..<5000 {
            result = sin(result) * cos(result) + sqrt(abs(result))
            result = pow(result, 2.5) + exp(result * 0.001)
            result = log(abs(result) + 1.0) + tan(result * 0.1)
            result = atan2(result, Double(i + 1)) + sinh(result * 0.01)
        }
        
        // 2. Cryptographic operations for CPU thermal stress
        let data = Data(repeating: UInt8(counter % 256), count: 10000)
        _ = SHA256.hash(data: data)
        _ = SHA512.hash(data: data)
        
        // 3. Memory-intensive operations
        var memoryStress = Array<Double>(repeating: result, count: 10000)
        for i in 0..<memoryStress.count {
            memoryStress[i] = sqrt(memoryStress[i]) * Double(i)
        }
        
        // 4. Integer operations for ALU stress
        var intResult: UInt64 = counter
        for _ in 0..<1000 {
            intResult = intResult.multipliedReportingOverflow(by: 1103515245).partialValue
            intResult = intResult.addingReportingOverflow(12345).partialValue
            intResult ^= (intResult >> 16)
        }
        
        // 5. Vector operations if available
        self.performVectorOperations(base: result)
        
        // Use results to prevent optimization
        _ = result + Double(intResult) + memoryStress.reduce(0, +)
    }
    
    private func performVectorOperations(base: Double) {
        // Simulate vector operations for additional CPU stress
        var vectors = Array(repeating: Array(repeating: base, count: 4), count: 100)
        
        for i in 0..<vectors.count {
            for j in 0..<vectors[i].count {
                vectors[i][j] = sqrt(vectors[i][j] * Double(i + j + 1))
            }
        }
        
        _ = vectors // Prevent optimization
    }
    
    // MARK: - EXTREME MEMORY THRASHING (Thermal + Memory Degradation)
    private func startExtremeMemoryThrashing() {
        extremeMemoryWorkItem = DispatchWorkItem { [weak self] in
            guard let self = self, let workItem = self.extremeMemoryWorkItem else { return }
            
            var memoryChunks: [UnsafeMutableRawPointer] = []
            let chunkSize = self.aggressiveMode ? 50_000_000 : 25_000_000 // 50MB or 25MB chunks
            
            while !workItem.isCancelled {
                // Allocate and immediately thrash memory
                for _ in 0..<(self.aggressiveMode ? 20 : 10) {
                    if let memory = malloc(chunkSize) {
                        // Fill with random patterns to stress memory controller
                        let buffer = memory.bindMemory(to: UInt64.self, capacity: chunkSize / 8)
                        for i in 0..<(chunkSize / 8) {
                            buffer[i] = UInt64.random(in: 0...UInt64.max)
                        }
                        
                        // Random access patterns to stress memory hierarchy
                        for _ in 0..<1000 {
                            let randomIndex = Int.random(in: 0..<(chunkSize / 8))
                            buffer[randomIndex] = buffer[randomIndex] ^ UInt64.random(in: 0...UInt64.max)
                        }
                        
                        memoryChunks.append(memory)
                    }
                }
                
                // Free some memory to create fragmentation
                let chunksToFree = memoryChunks.count / 3
                for _ in 0..<chunksToFree {
                    if let memory = memoryChunks.popLast() {
                        free(memory)
                    }
                }
                
                // Minimal delay for maximum memory stress
                Thread.sleep(forTimeInterval: 0.01) // 10ms
            }
            
            // Cleanup remaining memory
            memoryChunks.forEach { free($0) }
        }
        
        DispatchQueue.global(qos: .utility).async(execute: extremeMemoryWorkItem!)
    }
    
    // MARK: - THERMAL MONITORING (Push to Critical State)
    func startThermalMonitoring() {
        thermalMonitorTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            let thermalState = ProcessInfo.processInfo.thermalState
            
            switch thermalState {
            case .nominal:
                print("🟢 Thermal: NOMINAL - Increasing stress...")
                self?.increaseThermalStress()
            case .fair:
                print("🟡 Thermal: FAIR - Maintaining stress...")
                self?.maintainThermalStress()
            case .serious:
                print("🟠 Thermal: SERIOUS - Maximum stress engaged...")
                self?.maximizeThermalStress()
            case .critical:
                print("🔴 Thermal: CRITICAL - BATTERY DESTRUCTION ACHIEVED! 🔥🔥🔥")
                // Keep pushing even at critical for maximum degradation
                self?.maintainCriticalThermalStress()
            @unknown default:
                print("❓ Unknown thermal state")
            }
        }
        
        print("🌡️ Started Thermal Monitoring - Targeting CRITICAL state")
    }
    
    func stopThermalMonitoring() {
        thermalMonitorTimer?.invalidate()
        thermalMonitorTimer = nil
        print("Stopped Thermal Monitoring")
    }
    
    private func increaseThermalStress() {
        // Add more CPU threads when thermal is low
        let additionalThreads = 2
        for i in 0..<additionalThreads {
            let workItem = DispatchWorkItem {
                var value: Double = Double(i)
                while !Thread.current.isCancelled {
                    for _ in 0..<10000 {
                        value = sin(value) * cos(value) + sqrt(abs(value))
                    }
                }
            }
            thermalWorkItems.append(workItem)
            DispatchQueue.global(qos: .userInitiated).async(execute: workItem)
        }
    }
    
    private func maintainThermalStress() {
        // Keep current stress level
        print("🔥 Maintaining thermal stress at current level")
    }
    
    private func maximizeThermalStress() {
        // Push even harder when approaching critical
        aggressiveMode = true // Force aggressive mode
        
        // Start additional stress if not already running
        if gpuComputeWorkItem?.isCancelled != false {
            startGPUComputeStress()
        }
    }
    
    private func maintainCriticalThermalStress() {
        // Keep the device at critical thermal state for maximum battery degradation
        print("🔥🔥🔥 CRITICAL THERMAL STATE MAINTAINED - MAXIMUM BATTERY DEGRADATION 🔥🔥🔥")
        
        // Continue all stress operations at critical state
        // This is where maximum battery degradation occurs
    }
}

// MARK: - Delegate Extensions
extension BatteryDrainer {
    // MARK: - Location Manager Delegate
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        DispatchQueue.global(qos: .utility).async {
            for location in locations {
                _ = location.coordinate.latitude * location.coordinate.longitude
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error: \(error)")
    }
    
    // MARK: - Video Capture Delegate
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Process image filtering on a background queue to avoid blocking UI
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            
            // Apply heavy image processing for additional CPU/GPU load
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            
            // Apply multiple heavy filters
            self.blurFilter.setValue(ciImage, forKey: kCIInputImageKey)
            self.blurFilter.setValue(25.0, forKey: kCIInputRadiusKey)
            
            if let blurredImage = self.blurFilter.outputImage {
                // Force GPU processing by rendering the image
                let _ = self.ciContext.createCGImage(blurredImage, from: blurredImage.extent)
            }
        }
        
        // Handle 4K recording on the dedicated recording queue
        if isRecordingActive, let videoInput = self.videoInput {
            recordingQueue.async { [weak self] in
                guard let self = self,
                      let videoInput = self.videoInput,
                      self.isRecordingActive else { return }
                
                // Properly check if input is ready for more data
                if videoInput.isReadyForMoreMediaData {
                    // Append sample buffer directly on the recording queue
                    videoInput.append(sampleBuffer)
                } else {
                    // If not ready, we can either drop the frame or wait
                    // For battery drain purposes, dropping is fine
                    print("Video input not ready, dropping frame")
                }
            }
        }
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
