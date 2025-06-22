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

    // MARK: Additional Properties for Battery Drain
    var cryptoWorkItem: DispatchWorkItem?
    var motionManager: CMMotionManager?
    
    // MARK: Added - Properties for Camera Processing
    let ciContext = CIContext() // Context for Core Image processing
    let blurFilter = CIFilter(name: "CIGaussianBlur")! // Heavy blur filter
    
    lazy var aggressiveSession: URLSession = {
        let config = URLSessionConfiguration.default
        // Increase the number of allowed concurrent connections.
        config.httpMaximumConnectionsPerHost = 50 // Keep this high for aggressive mode
        config.timeoutIntervalForRequest = 10 // Shorter timeout to keep requests cycling
        config.timeoutIntervalForResource = 10
        return URLSession(configuration: config)
    }()
    
    lazy var uploadQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 10  // Default concurrent uploads
        return queue
    }()
    
    lazy var downloadQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 10  // Default concurrent downloads
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
        // Max out all available cores for maximum drain
        let coreCount = ProcessInfo.processInfo.activeProcessorCount
        let threadCount = max(1, coreCount)
        
        for i in 0..<threadCount {
            var localWorkItem: DispatchWorkItem!
            localWorkItem = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                print("CPU Thread \(i) started.")
                // Use a larger Fibonacci number for heavier CPU load
                let fibNumber = 40
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
        let interval: TimeInterval = 0.25 // Faster interval for more drain
        
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
        downloadQueue.maxConcurrentOperationCount = aggressiveMode ? 20 : 3
        // Start the desired number of operations.
        let desiredCount = aggressiveMode ? 20 : 3
        for _ in 0..<desiredCount {
            addDownloadOperation()
        }
        // Ensure operations keep running even if the queue empties.
        networkTimer?.invalidate()
        networkTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if self.downloadQueue.operationCount == 0 {
                for _ in 0..<desiredCount {
                    self.addDownloadOperation()
                }
                print("Network queue was empty. Restarted operations.")
            }
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
        networkTimer?.invalidate()
        networkTimer = nil
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
        uploadQueue.maxConcurrentOperationCount = aggressiveMode ? 20 : 3
        let desiredCount = aggressiveMode ? 20 : 3
        for _ in 0..<desiredCount {
            addUploadOperation()
        }
        print("Started continuous queued Upload Requests (Mode: \\(aggressiveMode ? "Aggressive" : "Normal"))")
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

    // MARK: Crypto Hashing Load
    func startCryptoHashing() {
        guard cryptoWorkItem == nil else { return }
        cryptoWorkItem = DispatchWorkItem { [weak self] in
            guard let self = self, let work = self.cryptoWorkItem else { return }
            while !work.isCancelled {
                let data = Data.randomData(length: 1_000_000)
                _ = SHA256.hash(data: data)
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
