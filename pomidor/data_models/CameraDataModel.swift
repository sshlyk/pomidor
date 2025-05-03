import AVFoundation
import SwiftUI
import os.log
import Vision

fileprivate let logger = Logger(subsystem: "pomidor", category: "DataModel")

final class CameraDataModel: ObservableObject {
    private let camera = Camera()
    let textRecogntion = TextRecognition()
    let titleTrackingModel: VNCoreMLModel?

    var previewTittleTrackingFramesSkipped = 0
    
    @Published var viewfinderImage: Image?
    @Published var thumbnailImage: Image?
    @Published var textBoxes: TextBoxes
    
    init() {
        titleTrackingModel = try? VNCoreMLModel(for: MovieTitlePosition(configuration: .init()).model)
        textBoxes = TextBoxes()
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
        let titleTrackingMLRequest: VNCoreMLRequest? = createTitleTrackingRequest { observations in
            Task { @MainActor in
                self.textBoxes.boxes = observations.map {NormalizedTextBox($0.boundingBox)}
            }
        }

        for await nextFrame in camera.previewStream {
            guard let previewCgImage = nextFrame.cgImage else {
                return
            }
            
            if previewTittleTrackingFramesSkipped > 2 {
                // submit image for movie title tracking processing
                if let request = titleTrackingMLRequest {
                    try? VNImageRequestHandler(cgImage: previewCgImage).perform([request])
                    previewTittleTrackingFramesSkipped = 0
                }
                
            } else {
                previewTittleTrackingFramesSkipped += 1
            }
            
            Task { @MainActor in
                // TODO orientation is fixed to up. This creates problems rendering boxes in landscape
                viewfinderImage = Image(decorative: previewCgImage, scale: 1, orientation: .up)
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
            
            guard let metadataOrientation = capturedPhoto.metadata[String(kCGImagePropertyOrientation)] as? UInt32,
                  let cgImageOrientation = CGImagePropertyOrientation(rawValue: metadataOrientation) else {
                return
            }
            
            guard let cgImage = capturedPhoto.cgImageRepresentation() else { continue }
            
            Task { @MainActor in
                viewfinderImage = Image(uiImage: UIImage(
                    cgImage: cgImage,
                    scale: 1,
                    orientation: UIImage.Orientation(cgImageOrientation)
                ))
            }
            
            // find bounding box for the movie title
            if let request = findTitleBoundingBox {
                try? VNImageRequestHandler(cgImage: cgImage, orientation: cgImageOrientation).perform([request])
            }
            
            if let movieBox = titleBox {
                Task { @MainActor in
                    textBoxes.boxes = [NormalizedTextBox(movieBox)]
                }
            }
            
            try? await Task.sleep(nanoseconds: 3_000_000_000)
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
