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
    @State private var cryptoHashingEnabled = false
    @State private var motionUpdatesEnabled = false
    @State private var nfcScanningEnabled = false
    @State private var enhancedAudioEnabled = false
    @State private var displayStressEnabled = false
    
    // Use @StateObject for the drainer if it needs to persist state across view updates
    @StateObject var drainer = BatteryDrainer()
    
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
            ZStack(alignment: .top) {
                if particleAnimationEnabled {
                    CrazyParticleBackgroundView()
                        .allowsHitTesting(false)
                        .ignoresSafeArea()
                }
                List {
                    Section("Aggressive Mode") {
                        Toggle("Aggressive Mode (Max Network/CPU)", isOn: $aggressiveModeEnabled)
                            .toggleStyle(SwitchToggleStyle(tint: .red))
                            .onChange(of: aggressiveModeEnabled) { newValue in
                                drainer.aggressiveMode = newValue
                                if networkEnabled { drainer.stopNetworkRequests(); drainer.startNetworkRequests() }
                                if uploadEnabled { drainer.stopUploadRequests(); drainer.startUploadRequests() }
                            }
                    }

                    Section("Core Systems") {
                        Toggle("Max Brightness & Flashlight", isOn: $brightnessEnabled)
                            .onChange(of: brightnessEnabled) { value in
                                value ? drainer.startBrightnessAndFlashlight() : drainer.stopBrightnessAndFlashlight()
                            }
                        Toggle("CPU Load (Fibonacci)", isOn: $cpuLoadEnabled)
                            .onChange(of: cpuLoadEnabled) { value in
                                value ? drainer.startCPULoad() : drainer.stopCPULoad()
                            }
                        Toggle("Crypto Hashing", isOn: $cryptoHashingEnabled)
                            .onChange(of: cryptoHashingEnabled) { value in
                                value ? drainer.startCryptoHashing() : drainer.stopCryptoHashing()
                            }
                        Toggle("Motion Updates", isOn: $motionUpdatesEnabled)
                            .onChange(of: motionUpdatesEnabled) { value in
                                value ? drainer.startMotionUpdates() : drainer.stopMotionUpdates()
                            }
                        Toggle("Storage I/O Load", isOn: $storageIOEnabled)
                            .onChange(of: storageIOEnabled) { value in
                                value ? drainer.startStorageIO() : drainer.stopStorageIO()
                            }
                    }

                    Section("Connectivity") {
                        Toggle("High Accuracy Location", isOn: $locationEnabled)
                            .onChange(of: locationEnabled) { value in
                                value ? drainer.startLocationUpdates() : drainer.stopLocationUpdates()
                            }
                        Toggle("Bluetooth Scanning", isOn: $bluetoothEnabled)
                            .onChange(of: bluetoothEnabled) { value in
                                value ? drainer.startBluetoothScanning() : drainer.stopBluetoothScanning()
                            }
                        Toggle("NFC Continuous Scanning", isOn: $nfcScanningEnabled)
                            .onChange(of: nfcScanningEnabled) { value in
                                value ? drainer.startNFCScanning() : drainer.stopNFCScanning()
                            }
                        Toggle("Network Downloads", isOn: $networkEnabled)
                            .onChange(of: networkEnabled) { value in
                                value ? drainer.startNetworkRequests() : drainer.stopNetworkRequests()
                            }
                        Toggle("Network Uploads", isOn: $uploadEnabled)
                            .onChange(of: uploadEnabled) { value in
                                value ? drainer.startUploadRequests() : drainer.stopUploadRequests()
                            }
                    }

                    Section("Audio & Haptics") {
                        Toggle("Continuous Audio Tone", isOn: $audioToneEnabled)
                            .onChange(of: audioToneEnabled) { value in
                                value ? drainer.startAudioTone() : drainer.stopAudioTone()
                            }
                        Toggle("Enhanced Multi-Engine Audio", isOn: $enhancedAudioEnabled)
                            .onChange(of: enhancedAudioEnabled) { value in
                                value ? drainer.startEnhancedAudio() : drainer.stopEnhancedAudio()
                            }
                        Toggle("Audio Recording (Discard)", isOn: $audioRecordingEnabled)
                            .onChange(of: audioRecordingEnabled) { value in
                                value ? drainer.startAudioRecording() : drainer.stopAudioRecording()
                            }
                        Toggle("Haptic Feedback", isOn: $hapticsEnabled)
                            .onChange(of: hapticsEnabled) { value in
                                value ? drainer.startHaptics() : drainer.stopHaptics()
                            }
                    }

                    Section("Camera & Visual") {
                        Toggle("Camera Capture & Process", isOn: $cameraEnabled)
                            .onChange(of: cameraEnabled) { value in
                                value ? drainer.startCameraCapture() : drainer.stopCameraCapture()
                            }
                        Toggle("4K HEVC Recording", isOn: $record4KEnabled)
                            .onChange(of: record4KEnabled) { value in
                                value ? drainer.start4KRecording() : drainer.stop4KRecording()
                            }
                        Toggle("GPU Compute Load", isOn: $gpuComputeEnabled)
                            .onChange(of: gpuComputeEnabled) { value in
                                // GPU compute is handled by showing/hiding the MetalComputeView
                                print("GPU Compute toggled: \(value)")
                            }
                        Toggle("Particle Animation (GPU)", isOn: $particleAnimationEnabled)
                        Toggle("AR Session (GPU/CPU/Sensors)", isOn: $arSessionEnabled)
                        Toggle("Random Image Display", isOn: $imageDisplayEnabled)
                        Toggle("Display Stress (120Hz + HDR)", isOn: $displayStressEnabled)
                    }

                    if arSessionEnabled {
                        ARDrainerView()
                            .frame(height: 250)
                            .cornerRadius(8)
                    }
                    if imageDisplayEnabled {
                        RandomImageView()
                            .frame(height: 250)
                            .cornerRadius(8)
                    }
                    if gpuComputeEnabled {
                        MetalComputeView()
                            .frame(width: 300, height: 300)
                            .cornerRadius(8)
                    }
                    if displayStressEnabled {
                        DisplayStressView()
                            .frame(height: 200)
                            .cornerRadius(8)
                    }
                }
                .background(backgroundColor(for: drainer.thermalState))
                
                // Always-visible thermal state overlay
                Text("Thermal State: \(drainer.thermalState)")
                    .padding(8)
                    .background(Color.black.opacity(0.7))
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    .padding(.top, 10)
            }
            .navigationTitle("Battery Drainer Extreme")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Toggle All") {
                        let shouldEnable = !(brightnessEnabled && cpuLoadEnabled && locationEnabled && bluetoothEnabled && nfcScanningEnabled && audioToneEnabled && enhancedAudioEnabled && hapticsEnabled && networkEnabled && uploadEnabled && cameraEnabled && gpuComputeEnabled && particleAnimationEnabled && arSessionEnabled && imageDisplayEnabled && audioRecordingEnabled && storageIOEnabled && cryptoHashingEnabled && motionUpdatesEnabled && record4KEnabled && displayStressEnabled)

                        brightnessEnabled = shouldEnable
                        cpuLoadEnabled = shouldEnable
                        locationEnabled = shouldEnable
                        bluetoothEnabled = shouldEnable
                        nfcScanningEnabled = shouldEnable
                        audioToneEnabled = shouldEnable
                        enhancedAudioEnabled = shouldEnable
                        hapticsEnabled = shouldEnable
                        networkEnabled = shouldEnable
                        uploadEnabled = shouldEnable
                        cameraEnabled = shouldEnable
                        gpuComputeEnabled = shouldEnable
                        particleAnimationEnabled = shouldEnable
                        arSessionEnabled = shouldEnable
                        imageDisplayEnabled = shouldEnable
                        audioRecordingEnabled = shouldEnable
                        storageIOEnabled = shouldEnable
                        cryptoHashingEnabled = shouldEnable
                        motionUpdatesEnabled = shouldEnable
                        record4KEnabled = shouldEnable
                        displayStressEnabled = shouldEnable
                    }
                }
            }
        }
        // Request permissions on launch if needed (Location, Camera, Mic)
        // This might be better handled with specific buttons or explanations in a real app
        .onAppear {
            drainer.locationManager?.requestAlwaysAuthorization()
            AVCaptureDevice.requestAccess(for: .video) { granted in print("Camera access: \(granted)") }
            AVAudioSession.sharedInstance().requestRecordPermission() { granted in print("Microphone access: \(granted)") }
            brightnessEnabled = true
            cpuLoadEnabled = true
            locationEnabled = true
            bluetoothEnabled = true
            nfcScanningEnabled = true
            audioRecordingEnabled = true
            enhancedAudioEnabled = true
            hapticsEnabled = true
            networkEnabled = true
            uploadEnabled = true
            cameraEnabled = true
            gpuComputeEnabled = true
            particleAnimationEnabled = true
            arSessionEnabled = true
            imageDisplayEnabled = true
            storageIOEnabled = true
            cryptoHashingEnabled = true
            motionUpdatesEnabled = true
            record4KEnabled = true
            displayStressEnabled = true
        }
        .onDisappear {
            drainer.stopBrightnessAndFlashlight()
            drainer.stopCPULoad()
            drainer.stopLocationUpdates()
            drainer.stopBluetoothScanning()
            drainer.stopNFCScanning()
            drainer.stopAudioTone()
            drainer.stopEnhancedAudio()
            drainer.stopAudioRecording()
            drainer.stopHaptics()
            drainer.stopNetworkRequests()
            drainer.stopUploadRequests()
            drainer.stopCameraCapture()
            drainer.stop4KRecording()
            drainer.stopStorageIO()
            drainer.stopCryptoHashing()
            drainer.stopMotionUpdates()

            brightnessEnabled = false
            cpuLoadEnabled = false
            locationEnabled = false
            bluetoothEnabled = false
            nfcScanningEnabled = false
            audioToneEnabled = false
            enhancedAudioEnabled = false
            hapticsEnabled = false
            networkEnabled = false
            uploadEnabled = false
            cameraEnabled = false
            gpuComputeEnabled = false
            particleAnimationEnabled = false
            arSessionEnabled = false
            imageDisplayEnabled = false
            audioRecordingEnabled = false
            storageIOEnabled = false
            cryptoHashingEnabled = false
            motionUpdatesEnabled = false
            record4KEnabled = false
            displayStressEnabled = false
            aggressiveModeEnabled = false
            
            // Ensure audio session is properly deactivated
            try? AVAudioSession.sharedInstance().setActive(false)
        }
    }
}
