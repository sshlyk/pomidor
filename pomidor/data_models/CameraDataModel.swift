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

fileprivate extension CIImage {
    
    var cgImage: CGImage? {
        let ciContext = CIContext()
        return ciContext.createCGImage(self, from: self.extent)
    }
}

fileprivate extension Image.Orientation {

    init(_ cgImageOrientation: CGImagePropertyOrientation) {
        switch cgImageOrientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        }
    }
}

fileprivate extension UIImage.Orientation {
    
    init(_ cgImageOrientation: CGImagePropertyOrientation) {
        switch cgImageOrientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        case .left: self = .left
        }
    }
}

// Image transformation needed relative to camera physical position when photo was taken to correctly pass it to ML
fileprivate extension CGImagePropertyOrientation {
    init(_ cameraOrientation: CameraSensorOrientation) {
        switch cameraOrientation {
        case .up: self = .up
        case .down: self = .down
        case .right: self = .right
        case .left: self = .left
        }
    }
}

fileprivate extension CGRect {
    // rotates rectangular box to match image orientation
    func rotateToMatch(imageOrientation: CameraSensorOrientation) -> CGRect {
        switch imageOrientation {
        case .up: return self // image is facing up. box is already positioned correctly
        case .down: return self.rotatePlaneUpsideDown() // image is upside down. rotate box upside down
        case .right: return self.rotatePlaneRight() // image is facing right. rotate box to face right
        case .left: return self.rotatePlaneLeft() // image is facing left. rotate box to face left
        }
    }
    
    // move origin from top left corner to bottom left (rotating plane to the left)
    private func rotatePlaneLeft() -> CGRect {
        return CGRect(
            origin: CGPoint(x: self.origin.y, y: 1 - self.origin.x - self.size.width),
            size: CGSize(width: self.size.height, height: self.size.width))
    }
    
    // move origin from top left to top right (rotating plane to the right)
    private func rotatePlaneRight() -> CGRect {
        return CGRect(
            origin: CGPoint(x: 1 - self.origin.y - self.size.height, y: self.origin.x),
            size: CGSize(width: self.size.height, height: self.size.width))
    }
    
    // move origin from top left corner to bottom right (horizontal reflection of the plane)
    private func rotatePlaneUpsideDown() ->CGRect {
        return CGRect(
            origin: CGPoint(x: 1 - self.origin.x - self.width, y: 1 - self.origin.y - self.height),
            size: self.size)
    }
}
