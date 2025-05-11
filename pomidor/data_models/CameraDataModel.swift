import AVFoundation
import SwiftUI
import os.log
import Vision

fileprivate let logger = Logger(subsystem: "pomidor", category: "DataModel")

final class CameraDataModel: ObservableObject, PreviewHandlerDelegate, SnapshotHandlerDelegate {

    private let camera = Camera()
    private let previewHandler: PreviewHandler
    private let photoHandler: SnapshotsHandler
    private let dispatchQueue = DispatchQueue(label: "Camera model queue")
    private var isRunning = false
    
    @Published var viewfinderImage: Image?
    @Published var textBoxes: TextBoxes
    @Published var movieName: String
    
    @Published var showWebView: Bool = false
    var webViewSearchQuery: String = ""
    
    init() {
        let titleTrackingModel = try? VNCoreMLModel(for: MovieTitlePosition(configuration: .init()).model)
        textBoxes = TextBoxes()
        movieName = ""
        previewHandler = PreviewHandler(titleTrackingModel: titleTrackingModel, stream: camera.previewStream)
        photoHandler = SnapshotsHandler(titleTrackingModel: titleTrackingModel, stream: camera.photoStream)
    }
    
    deinit {
        camera.stop()
    }
    
    func start() async {
        dispatchQueue.async {
            if self.isRunning { return } // make sure we subscribe to camera stream only once
            Task { await self.camera.start() }
            Task { await self.previewHandler.handleCameraPreviews(delegate: self) }
            Task { await self.photoHandler.handleCameraPhotos(delegate: self) }
            self.isRunning = true
        }
    }
    
    func zoom(zoomFactor: CGFloat) {
        camera.zoom(zoomFactor: zoomFactor)
    }
    
    func captureImage() {
        if camera.isPreviewPaused {
            return // we are already taking a picture. once it is processed preview will resume
        }
        
        camera.pause() // pause viewfinder video so still picture does not feel jumping when ready
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
        defer {
            camera.resume()
        }
        
        if AppConfig.Debug.kShowCapturedMovieTitleCrop {
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
        } else {
            Task { @MainActor in
                webViewSearchQuery = text.joined(separator: " ")
                showWebView = true
            }
        }
    }
}
