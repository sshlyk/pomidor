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
            detectionsBoxes = observations.map {$0.boundingBox}
        }

        for await nextFrame in camera.previewStream {
            guard let previewCgImage = nextFrame.image.cgImage else {
                return
            }
            
            if previewTittleTrackingFramesSkipped > 2 {
                // submit image for movie title tracking processing
                if let request = titleTrackingMLRequest {
                    if let cameraOrientation = nextFrame.cameraOrientation {
                        try? VNImageRequestHandler(
                            cgImage: previewCgImage,
                            orientation: CGImagePropertyOrientation(cameraOrientation)
                        ).perform([request])
                        
                        let adjustedToOrientationBoxes = detectionsBoxes?
                            .map { $0.reAdjust(originalCameraOrientation: cameraOrientation) }
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
                viewfinderImage = Image(decorative: previewCgImage, scale: 1, orientation: .right)
            }
        }
    }
    
    func handleCameraPhotos() async {
        var titleBox: CGRect?
        
        let findTitleBoundingBox = createTitleTrackingRequest { observations in
            titleBox = observations.first?.boundingBox
        }
        
        for await capturedPhoto in camera.photoStream {
            // when done processing photo, resume viewfinder and
            defer {
                camera.resume()
            }
            
            guard let cgImage = capturedPhoto.photo.cgImageRepresentation() else { continue }
            
            // find bounding box for the movie title
            if let request = findTitleBoundingBox, let cameraOrientation = capturedPhoto.cameraOrientation {
                try? VNImageRequestHandler(
                    cgImage: cgImage,
                    orientation: CGImagePropertyOrientation(cameraOrientation)
                ).perform([request])
                
                if let box = titleBox {
                    Task { @MainActor in
                        textBoxes.boxes = [NormalizedTextBox(box.reAdjust(originalCameraOrientation: cameraOrientation))]
                        movieName = "some movie title"
                        print(titleBox.debugDescription)
                    }
                }
            }
            
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            Task { @MainActor in
                movieName = ""
            }
        }
    }
    
    private func createTitleTrackingRequest(handler: @escaping ([VNRecognizedObjectObservation]) -> Void) -> VNCoreMLRequest?  {
        var titleTrackingMLRequest: VNCoreMLRequest?
        
        if let model = titleTrackingModel {
            titleTrackingMLRequest = VNCoreMLRequest(model: model) { request, error in
                if let observations = request.results as? [VNRecognizedObjectObservation] {
                    handler(observations)
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
    init(_ cameraOrientation: CameraOrientation) {
        switch cameraOrientation {
        case .up: self = .right
        case .down: self = .left
        case .right: self = .down
        case .left: self = .up
        }
    }
}

fileprivate extension CGRect {
    func reAdjust(originalCameraOrientation: CameraOrientation) -> CGRect {
        switch originalCameraOrientation {
        case .up: return self
            
        case .down: return CGRect(
            origin: CGPoint(x: 1 - self.origin.x - self.width, y: 1 - self.origin.y - self.height),
            size: self.size)
            
        case .right: return CGRect(
            origin: CGPoint(x: 1 - self.origin.y - self.height, y: self.origin.x),
            size: CGSize(width: self.height, height: self.width))
            
        case .left: return CGRect(
                origin: CGPoint(x: self.origin.y, y: 1 - self.origin.x - self.width),
                size: CGSize(width: self.height, height: self.width))
        }
    }
}
