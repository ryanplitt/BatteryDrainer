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
    @State private var cryptoHashingEnabled = false
    @State private var motionUpdatesEnabled = false
    
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
                if particleAnimationEnabled {
                    CrazyParticleBackgroundView()
                        .allowsHitTesting(false)
                        .ignoresSafeArea()
                }
                Form {
                    Section {
                        Text("Thermal State: \(thermalState)")
                            .foregroundColor(backgroundColor(for: thermalState))
                    }

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
                        Toggle("Particle Animation (GPU)", isOn: $particleAnimationEnabled)
                        Toggle("AR Session (GPU/CPU/Sensors)", isOn: $arSessionEnabled)
                        Toggle("Random Image Display", isOn: $imageDisplayEnabled)
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
                }
                .navigationTitle("Battery Drainer Extreme")
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Toggle All") {
                            let shouldEnable = !(brightnessEnabled && cpuLoadEnabled && locationEnabled && bluetoothEnabled && audioToneEnabled && hapticsEnabled && networkEnabled && uploadEnabled && cameraEnabled && particleAnimationEnabled && arSessionEnabled && imageDisplayEnabled && audioRecordingEnabled && storageIOEnabled && cryptoHashingEnabled && motionUpdatesEnabled)

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
                            storageIOEnabled = shouldEnable
                            cryptoHashingEnabled = shouldEnable
                            motionUpdatesEnabled = shouldEnable
                        }
                    }
                }
                .onAppear {
                    cpuLoadEnabled = true
                    locationEnabled = true
                    bluetoothEnabled = true
                    audioRecordingEnabled = true
                    hapticsEnabled = true
                    networkEnabled = true
                    uploadEnabled = true
                    particleAnimationEnabled = true
                    arSessionEnabled = true
                    imageDisplayEnabled = true
                    storageIOEnabled = true
                    cryptoHashingEnabled = true
                    motionUpdatesEnabled = true
                }
                .onDisappear {
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
                    drainer.stopStorageIO()
                    drainer.stopCryptoHashing()
                    drainer.stopMotionUpdates()

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
                    cryptoHashingEnabled = false
                    motionUpdatesEnabled = false
                    aggressiveModeEnabled = false
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
