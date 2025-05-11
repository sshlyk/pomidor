import SwiftUI

struct MainView: View {
    @StateObject private var model = CameraDataModel()
    private let webView = WebView()
 
    private static let barHeightFactor = 0.15
    
    
    var body: some View {
        
        NavigationStack {
            GeometryReader { geometry in
                ViewfinderView(image:  $model.viewfinderImage, boxes: model.textBoxes, movieTitle: $model.movieName)
                    .overlay(alignment: .bottom) {
                        buttonsView()
                            .frame(height: geometry.size.height * Self.barHeightFactor)
                            .background(.black.opacity(0.75))
                    }
                    .background(.black)
            }
            .task {
                await model.start()
            }
            .navigationTitle("Camera")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarHidden(true)
            .ignoresSafeArea()
            .statusBar(hidden: true)
        }
    }
    
    private func buttonsView() -> some View {
        HStack(spacing: 60) {
            
            Spacer()
            
            Button {
                model.captureImage()
            } label: {
                Label {
                    Text("Take Photo")
                } icon: {
                    ZStack {
                        Circle()
                            .strokeBorder(.white, lineWidth: 3)
                            .frame(width: 62, height: 62)
                        Circle()
                            .fill(.white)
                            .frame(width: 50, height: 50)
                    }
                }
            }
            .navigationDestination(isPresented: $model.showWebView) {
                WebViewContainer(url: model.webViewSearchQuery, webView: webView)
            }
            
            Spacer()
        
        }
        .buttonStyle(.plain)
        .labelStyle(.iconOnly)
        .padding()
    }
}
