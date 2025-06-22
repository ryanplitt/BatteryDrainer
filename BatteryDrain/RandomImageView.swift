import SwiftUI
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
