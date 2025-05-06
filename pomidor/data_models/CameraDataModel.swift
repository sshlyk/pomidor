import AVFoundation
import SwiftUI
import os.log
import Vision

fileprivate let logger = Logger(subsystem: "pomidor", category: "DataModel")

final class CameraDataModel: ObservableObject, PreviewHandlerDelegate, PhotoHandlerDelegate {

    private let camera = Camera()
    private var previewHandler: PreviewHandler?
    private var photoHandler: PhotoHandler?
    
    @Published var viewfinderImage: Image?
    @Published var textBoxes: TextBoxes
    @Published var movieName: String
    
    init() {
        let titleTrackingModel = try? VNCoreMLModel(for: MovieTitlePosition(configuration: .init()).model)
        textBoxes = TextBoxes()
        movieName = ""
        previewHandler = PreviewHandler(titleTrackingModel: titleTrackingModel, stream: camera.previewStream)
        photoHandler = PhotoHandler(titleTrackingModel: titleTrackingModel, stream: camera.photoStream)
        Task { await previewHandler?.handleCameraPreviews(delegate: self) }
        Task { await photoHandler?.handleCameraPhotos(delegate: self) }
    }
    
    func start() async {
        await camera.start()
    }
    
    func captureImage() {
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
        
        Task { @MainActor in
            textBoxes.boxes = []
            if let title = capturedMovieTitle {
                viewfinderImage =  Image(decorative: title, scale: 1, orientation: .right)
                // movieName = text.joined(separator: " ")
                movieName = "👍"
            } else {
                movieName = "💩"
            }
        }
        
        
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        
        Task { @MainActor in
            movieName = ""
        }
    }
}
