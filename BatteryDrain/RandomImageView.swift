import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

// MARK: - Enhanced 4K RandomImageView with Simultaneous Loading
struct RandomImageView: View {
    @State private var imageUrls: [URL] = []
    @State private var processedImages: [UIImage] = []
    // Faster refresh for maximum memory pressure
    let timer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 4) {
                ForEach(0..<min(processedImages.count, 4), id: \.self) { index in
                    Image(uiImage: processedImages[index])
                        .resizable()
                        .scaledToFit()
                        .cornerRadius(8)
                }
            }
        }
        .onAppear {
            loadMultiple4KImages()
        }
        .onReceive(timer) { _ in
            loadMultiple4KImages()
        }
        .onDisappear {
            imageUrls.removeAll()
            processedImages.removeAll()
        }
    }
    
    func loadMultiple4KImages() {
        // Load multiple 4K images simultaneously for maximum memory pressure
        let imageCount = 4
        var urls: [URL] = []
        
        for i in 0..<imageCount {
            let randomValue = Int.random(in: 0...100000)
            // Upgrade to 4K resolution (3840x2160) as specified
            if let url = URL(string: "https://picsum.photos/3840/2160?random=\(randomValue + i)") {
                urls.append(url)
            }
        }
        
        imageUrls = urls
        processedImages.removeAll()
        
        // Load and process images simultaneously
        Task {
            await withTaskGroup(of: UIImage?.self) { group in
                for url in urls {
                    group.addTask {
                        await loadAndProcessImage(from: url)
                    }
                }
                
                for await processedImage in group {
                    if let image = processedImage {
                        await MainActor.run {
                            processedImages.append(image)
                        }
                    }
                }
            }
        }
    }
    
    private func loadAndProcessImage(from url: URL) async -> UIImage? {
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let uiImage = UIImage(data: data) else { return nil }
            
            // Apply complex Core Image filter chains for maximum CPU/GPU load
            return await applyComplexFilters(to: uiImage)
        } catch {
            print("Failed to load image from \(url): \(error)")
            return nil
        }
    }
    
    private func applyComplexFilters(to image: UIImage) async -> UIImage? {
        guard let ciImage = CIImage(image: image) else { return image }
        
        let context = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])
        var processedImage = ciImage
        
        // Apply multiple intensive filter chains for maximum processing load
        let filters: [(CIFilter, [String: Any])] = [
            (CIFilter.gaussianBlur(), ["inputRadius": 25.0]),
            (CIFilter.exposureAdjust(), ["inputEV": 2.0]),
            (CIFilter.vibrance(), ["inputAmount": 1.5]),
            (CIFilter.sharpenLuminance(), ["inputSharpness": 2.0]),
            (CIFilter.colorControls(), ["inputSaturation": 2.0, "inputBrightness": 0.2, "inputContrast": 1.5]),
            (CIFilter.unsharpMask(), ["inputRadius": 10.0, "inputIntensity": 2.0]),
            (CIFilter.noiseReduction(), ["inputNoiseLevel": 0.02, "inputSharpness": 0.4]),
            (CIFilter.sepiaTone(), ["inputIntensity": 0.8])
        ]
        
        for (filter, parameters) in filters {
            filter.setValue(processedImage, forKey: kCIInputImageKey)
            for (key, value) in parameters {
                filter.setValue(value, forKey: key)
            }
            
            if let outputImage = filter.outputImage {
                processedImage = outputImage
            }
        }
        
        // Force GPU processing by creating CGImage
        if let cgImage = context.createCGImage(processedImage, from: processedImage.extent) {
            return UIImage(cgImage: cgImage)
        }
        
        return image
    }
}
