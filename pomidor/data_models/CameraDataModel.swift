import AVFoundation
import SwiftUI
import os.log
import Vision

fileprivate let logger = Logger(subsystem: "pomidor", category: "DataModel")

final class CameraDataModel: ObservableObject {
    private let camera = Camera()
    private let textRecogntion = TextRecognition()
    private let titleTrackingModel: VNCoreMLModel?
    private var previewTittleTrackingFramesSkipped = 0
    private let 🤷 = "🤷‍♂️"
    
    @Published var viewfinderImage: Image?
    @Published var thumbnailImage: Image?
    @Published var textBoxes: TextBoxes
    @Published var movieName: String
    
    init() {
        titleTrackingModel = try? VNCoreMLModel(for: MovieTitlePosition(configuration: .init()).model)
        textBoxes = TextBoxes()
        movieName = 🤷
        Task { await handleCameraPreviews() }
        Task { await handleCameraPhotos() }
    }
    
    func start() async {
        await camera.start()
    }
    
    func captureImage() {
        textBoxes.boxes = [] // clear on-screen tracking
        camera.pause() // pause viewfinder video so still picture does not feel jumping when ready
        camera.captureImage()
    }
    
    // Video frames that are displayed in the viewfinder
    // Detect region of the screen that contains movie title
    func handleCameraPreviews() async {
        var detectionsBoxes: [CGRect]?
        let titleTrackingMLRequest: VNCoreMLRequest? = createTitleTrackingRequest { observations in
            detectionsBoxes = observations
        }

        for await nextFrame in camera.previewStream {
            guard let previewCgImage = nextFrame.image.cgImage else {
                return
            }
            
            if previewTittleTrackingFramesSkipped > 2 {
                // submit image for movie title tracking processing
                if let request = titleTrackingMLRequest {
                    if let cameraOrientation = nextFrame.orientation {
                        try? VNImageRequestHandler(
                            cgImage: previewCgImage,
                            orientation: CGImagePropertyOrientation(cameraOrientation)
                        ).perform([request])
                        
                        let adjustedToOrientationBoxes = detectionsBoxes?
                            .map {
                                return $0.rotateToMatch(imageOrientation: cameraOrientation).rotateToMatch(imageOrientation: .left)
                            }
                            .map { NormalizedTextBox($0) }
                        
                        Task { @MainActor in
                            self.textBoxes.boxes = adjustedToOrientationBoxes ?? []
                        }
                    }
                    
                    previewTittleTrackingFramesSkipped = 0
                }
            } else {
                previewTittleTrackingFramesSkipped += 1
            }
            
            Task { @MainActor in
                // we pick one orientation to freeze the image so it does not jump when phone is rotated
                // chosen orientation maximizes the screen as well
                viewfinderImage = Image(decorative: previewCgImage, scale: 1, orientation: .right)
            }
        }
    }
    
    func handleCameraPhotos() async {
        var titleBox: CGRect?
        
        let findTitleBoundingBox = createTitleTrackingRequest { observations in
            titleBox = observations.first
        }
        
        for await capturedPhoto in camera.photoStream {
            // when done processing photo, resume viewfinder and
            defer {
                camera.resume()
            }
            
            guard let cgImage = capturedPhoto.photo.cgImageRepresentation() else { continue }
            
            // find bounding box for the movie title
            if let request = findTitleBoundingBox, let cameraOrientation = capturedPhoto.orientation {
                try? VNImageRequestHandler(
                    cgImage: cgImage,
                    orientation: CGImagePropertyOrientation(cameraOrientation)
                ).perform([request])
                
                if let box = titleBox {
                    let boxAlignedWithImage = box.rotateToMatch(imageOrientation: cameraOrientation)
                    
                    let croppedImage = cgImage.cropping(to: NormalizedRect(normalizedRect: boxAlignedWithImage)
                        .toImageCoordinates(CGSize(width: cgImage.width, height: cgImage.height), origin: .upperLeft))
                    
                    
                    Task { @MainActor in
                        textBoxes.boxes = [NormalizedTextBox(boxAlignedWithImage.rotateToMatch(imageOrientation: .left))]
                        movieName = "some movie title"
                        
                        // giving orientation .right instruct view to rotate image left when displayed to restore original up position
                        viewfinderImage = Image(uiImage: UIImage(cgImage: croppedImage!, scale: 1, orientation: .right))
                    }
                }
            }
            
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            Task { @MainActor in
                movieName = ""
            }
        }
    }
    
    private func createTitleTrackingRequest(handler: @escaping ([CGRect]) -> Void) -> VNCoreMLRequest?  {
        var titleTrackingMLRequest: VNCoreMLRequest?
        
        if let model = titleTrackingModel {
            titleTrackingMLRequest = VNCoreMLRequest(model: model) { request, error in
                if let observations = request.results as? [VNRecognizedObjectObservation] {
                    // Bounding boxes returned by vision framework have origin at the bottom left (mac).
                    // iOS uses top left origin instead
                    handler(observations.map {$0.boundingBox })
                }
            }
        }
        
        // image can be rotated or region of interest selected
        //titleTrackingMLRequest?.imageCropAndScaleOption = .scaleFillRotate90CCW
        //titleTrackingMLRequest?.regionOfInterest = ...
        
        return titleTrackingMLRequest
    }
}
