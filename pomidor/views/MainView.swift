import SwiftUI

struct MainView: View {
    @StateObject private var model = CameraDataModel()
    private let webView = WebView()
    @State private var currentZoom: CGFloat = 1
    
    private static let barHeightFactor = 0.15
    
    var body: some View {
        
        NavigationStack {
            GeometryReader { geometry in
                ViewfinderView(image:  $model.previewImage, boxes: model.rectBoxes, infoText: $model.infoText)
                    .overlay(alignment: .bottom) {
                        buttonsView()
                            .frame(height: geometry.size.height * Self.barHeightFactor)
                            .background(.black.opacity(0.75))
                    }
                    .background(.black)
            }.gesture(
                MagnifyGesture()
                    .onChanged { change in Task { await model.zoom(zoomFactor: clampZoomFactor(change.magnification)) } }
                    .onEnded { change in Task { currentZoom = clampZoomFactor(change.magnification) }  }
            )
            .task {
                await model.startCamera()
            }
            .navigationTitle("Camera")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarHidden(true)
            .ignoresSafeArea()
            .statusBar(hidden: true)
            .onDisappear {
                Task { await model.stopCamera() }
            }
        }
    }
    
    private func buttonsView() -> some View {
        HStack(spacing: 60) {
            
            Spacer()
            
            Button {
                Task { await model.captureImage() }
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
                WebViewContainer(query: model.webViewSearchQuery, webView: webView)
            }
            
            Spacer()
        
        }
        .buttonStyle(.plain)
        .labelStyle(.iconOnly)
        .padding()
    }
    
    private func clampZoomFactor(_ zoomFactor: CGFloat) -> CGFloat {
        return max(1, min(AppConfig.UI.kMaxZoomFactor, currentZoom * zoomFactor))
    }
}
