import AVFoundation
import SwiftUI
import os.log
import Vision

fileprivate let logger = Logger(subsystem: "pomidor", category: "DataModel")

final class CameraDataModel: ObservableObject, PreviewHandlerDelegate, SnapshotHandlerDelegate {
    private let camera = Camera()
    private let dispatchQueue = DispatchQueue(label: "Camera model queue")
    
    @Published var viewfinderImage: Image?
    @Published var textBoxes: TextBoxes = TextBoxes()
    @Published var movieName: String = ""
    
    @Published var showWebView: Bool = false
    var webViewSearchQuery: String = ""
    
    init() {
        let model = try? VNCoreMLModel(for: MovieTitlePosition(configuration: .init()).model)
        
        Task {
            let handler = PreviewHandler(titleTrackingModel: model, stream: self.camera.previewStream)
            await handler.handleCameraPreviews(delegate: self)
        }
        
        Task {
            let handler = SnapshotsHandler(titleTrackingModel: model, stream: self.camera.photoStream)
            await handler.handleCameraPhotos(delegate: self)
        }
    }
    
    func startCamera() async {
        await camera.start()
    }
    
    func stopCamera() {
        camera.stop()
    }
    
    // Change zoom factor
    func zoom(zoomFactor: CGFloat) {
        camera.zoom(zoomFactor: zoomFactor)
    }
    
    func captureImage() {
        camera.captureImage()
    }
    
    func nextPreviewFrame(capture: PreviewCapture, detections: [CGRect]?) async {
        guard let previewCgImage = capture.image.cgImage else { return }
        
        let transformedDetections = capture.orientation.flatMap { orientation in
            detections?.map { $0.rotateToMatch(imageOrientation: orientation) }
        }
        
        Task { @MainActor in
            // Display image. The image is currently rotated left when rendered
            // Text boxes needs to be rotated to the left
            viewfinderImage =  Image(decorative: previewCgImage, scale: 1, orientation: .right)
            textBoxes.boxes = transformedDetections?.map {
                NormalizedTextBox($0.rotateToMatch(imageOrientation: .left))
            } ?? []
        }
    }
    
    func nextPhotoFrame(capturedMovieTitle: CGImage?, text: [String]) async {
        if AppConfig.Debug.kShowCapturedMovieTitleCrop {
            await debugShowCapturedTitle(capturedMovieTitle, text)
        } else {
            Task { @MainActor in
                webViewSearchQuery = text.joined(separator: " ")
                showWebView = true
            }
        }
        
        await camera.start()
    }
    
    // Used for debugging purposes. Show cropped image of the captured movie title
    private func debugShowCapturedTitle(_ capturedMovieTitle: CGImage?, _ text: [String]) async {
        Task { @MainActor in
            textBoxes.boxes = []
            if let title = capturedMovieTitle {
                if AppConfig.Debug.kShowCapturedMovieTitleCrop {
                    viewfinderImage =  Image(decorative: title, scale: 1, orientation: .right)
                }
                movieName = text.joined(separator: " ")
            } else {
                movieName = AppConfig.UI.kNotFoundText
            }
        }
        
        try? await Task.sleep(nanoseconds: AppConfig.UI.kSnapDelaySec * 1_000_000_000)
        
        Task { @MainActor in
            movieName = ""
        }
    }
}
