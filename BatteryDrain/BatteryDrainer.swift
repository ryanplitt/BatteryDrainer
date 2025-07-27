import Foundation
import SwiftUI
import AVFoundation
import CoreLocation
import CoreBluetooth
import UIKit
import Security
import CoreImage
import CoreMotion
import CryptoKit

// MARK: - BatteryDrainer
class BatteryDrainer: NSObject, CLLocationManagerDelegate, CBCentralManagerDelegate, AVCaptureVideoDataOutputSampleBufferDelegate, ObservableObject {
    
    // MARK: - Network Properties
    private var downloadQueue = OperationQueue()
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
    
    var hapticGenerator: UIImpactFeedbackGenerator?
    var currentUploadTask: URLSessionUploadTask?

    // MARK: 4K HEVC Video Recording
    private var videoWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var recordSession: AVCaptureSession?
    private var recordOutput: AVCaptureVideoDataOutput?

    // MARK: - Storage I/O Properties
    var storageIOWorkItem: DispatchWorkItem?
    let storageIOFileName = "largeTempFile.dat"
    let storageIODataSize = 50 * 1024 * 1024 // 50 MB for more intensive I/O

    // MARK: - Additional Properties for Battery Drain
    var cryptoWorkItem: DispatchWorkItem?
    var motionManager: CMMotionManager?
    
    // MARK: - Camera Processing Properties
    let ciContext = CIContext() // Context for Core Image processing
    let blurFilter = CIFilter(name: "CIGaussianBlur")! // Heavy blur filter
    
    lazy var aggressiveSession: URLSession = {
        let config = URLSessionConfiguration.default
        // Increase the number of allowed concurrent connections.
        config.httpMaximumConnectionsPerHost = 50 // Keep this high for aggressive mode
        config.timeoutIntervalForRequest = 30 // Shorter timeout to keep requests cycling
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config)
    }()
    
    override init() {
        super.init()
        downloadQueue.maxConcurrentOperationCount = 3
        downloadQueue.qualityOfService = .background
    }

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
        let interval: TimeInterval = 0.25 // Faster interval for more drain

        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .background))
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
        // Cancel any existing operations.
        downloadQueue.cancelAllOperations()
        // Set the maximum concurrent operations based on aggressive mode.
        downloadQueue.maxConcurrentOperationCount = aggressiveMode ? 10 : 3
        
        // Fill the queue to the desired number of operations.
        refillQueueIfNeeded()
        
        // Ensure operations keep running even if the queue empties or drops below target.
        networkTimer?.invalidate()
        networkTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            print("Timer tick. Queue count: \(self.downloadQueue.operationCount)")
            self.refillQueueIfNeeded()
        }
        print("Started continuous queued Download Requests (Mode: \(aggressiveMode ? "Aggressive" : "Normal"))")
    }

    private func addDownloadOperation() {
        let op = BlockOperation { [weak self] in
            guard let self = self else { return }
            let semaphore = DispatchSemaphore(value: 0)
            
            Task {
                await self.makeNetworkRequest()
                semaphore.signal()
            }
            semaphore.wait()
            print("Download operation finished. Queue count: \(self.downloadQueue.operationCount)")
            
            // Immediately queue another download while active
            if self.networkActive && !op.isCancelled {
                self.addDownloadOperation()
            }
        }
        downloadQueue.addOperation(op)
    }

    private func refillQueueIfNeeded() {
        let desiredCount = aggressiveMode ? 10 : 3
        let missing = desiredCount - downloadQueue.operationCount
        
        if downloadQueue.operationCount == 0 {
            print("Queue went empty! Refilling to \(desiredCount)")
            for _ in 0..<desiredCount {
                addDownloadOperation()
            }
            return
        }
        
        if missing > 0 {
            print("Refilling download queue: adding \(missing) (count now \(downloadQueue.operationCount))")
            for _ in 0..<missing {
                addDownloadOperation()
            }
        }
    }

    func stopNetworkRequests() {
        networkActive = false
        downloadQueue.cancelAllOperations()
        networkTimer?.invalidate()
        networkTimer = nil
        print("Stopped Network Requests")
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
            urlString = "https://picsum.photos/3000/3000?random=\(randomValue)"
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

        do {
            let (data, response) = try await session.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
                print("Download failed with status code: \(httpResponse.statusCode)")
            } else {
                print("Downloaded \(data.count) bytes successfully.")
                
                // Additional processing of downloaded data to increase CPU load
                if aggressiveMode && data.count > 1000 {
                    // Process the data to add CPU load
                    let processedData = data.withUnsafeBytes { bytes in
                        var checksum: UInt32 = 0
                        for byte in bytes {
                            checksum = checksum &+ UInt32(byte)
                        }
                        return checksum
                    }
                    _ = processedData // Prevent optimization
                }
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
        
        let payloadSize = aggressiveMode ? 50_000_000 : 5_000_000
        let data = Data(repeating: 0xDE, count: payloadSize)
        
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
        stopUploadRequests()
        if aggressiveMode {
            isAggressiveUploadLoopRunning = true
            Task {
                while self.isAggressiveUploadLoopRunning {
                    await self.makeUploadRequest()
                    // Small delay in aggressive mode to prevent overwhelming
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                }
            }
        } else {
            let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .background))
            timer.schedule(deadline: .now() + 3.0, repeating: 3.0)
            timer.setEventHandler { [weak self] in
                guard let self = self else { return }
                Task { await self.makeUploadRequest() }
            }
            timer.resume()
            uploadTimer = timer
        }
        print("Started Upload Requests (Mode: \(aggressiveMode ? "Aggressive" : "Normal"))")
    }

    func stopUploadRequests() {
        isAggressiveUploadLoopRunning = false
        uploadTimer?.cancel()
        uploadTimer = nil
        print("Stopped Upload Requests")
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
            // Don't deactivate session here as it might be used by audio tone
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
                    
                    // 4. Additional file operations for more stress
                    let additionalFiles = 3
                    for i in 1...additionalFiles {
                        let additionalPath = tempDir.appendingPathComponent("temp_\(i).dat")
                        let smallData = Data.randomData(length: 1024 * 1024) // 1MB files
                        try? smallData.write(to: additionalPath, options: .atomic)
                        try? Data(contentsOf: additionalPath)
                        try? fileManager.removeItem(at: additionalPath)
                    }
                    
                    // 5. Delete main file
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
                
                // Minimal delay for maximum I/O stress
                Thread.sleep(forTimeInterval: 0.01) // 10 milliseconds - more aggressive
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

    func stopMotionUpdates() {
        motionManager?.stopAccelerometerUpdates()
        motionManager?.stopGyroUpdates()
        motionManager = nil
        print("Stopped Motion Updates")
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
            print("Unknown location authorization status: \(manager.authorizationStatus)")
            // Handle gracefully instead of crashing
            stopLocationUpdates()
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
