import SwiftUI
import AVFoundation
import CoreLocation
import CoreBluetooth
import AVKit
import ARKit
import CoreImage
import MetalKit
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
