import AVFoundation
import SwiftUI
import os.log
import Vision

fileprivate let logger = Logger(subsystem: "pomidor", category: "DataModel")

final class CameraDataModel: ObservableObject {
    let camera = Camera()
    let textRecogntion = TextRecognition()
    var titleTrackingMLRequest: VNCoreMLRequest?
    var previewTittleTrackingFramesSkipped = 0
    
    @Published var viewfinderImage: Image?
    @Published var thumbnailImage: Image?
    @Published var textBoxes: TextBoxes
    
    init() {
        textBoxes = TextBoxes()
        Task { await handleCameraPreviews() }
        Task { await handleCameraPhotos() }
    }
    
    // Video frames that are displayed in the viewfinder
    // Detect region of the screen that contains movie title
    func handleCameraPreviews() async {
        if let model = try? MovieTitlePosition(configuration: .init()),
           let visionModel = try? VNCoreMLModel(for: model.model) {
            titleTrackingMLRequest = VNCoreMLRequest(model: visionModel) { request, error in
                if let observations = request.results as? [VNRecognizedObjectObservation] {
                    // publish detected boxes to be displayed
                    Task { @MainActor in
                        self.textBoxes.boxes = observations.map {NormalizedTextBox($0.boundingBox)}
                    }
                }
              }
            }
        
        // image can be rotated or region of interest selected
        //titleTrackingMLRequest?.imageCropAndScaleOption = .scaleFillRotate90CCW
        //imagePreProcessingRequst?.regionOfInterest = ...

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
        
        for await capturedPhoto in camera.photoStream {
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
            
            let boxes = textRecogntion.performTextRecognition(cgImage: cgImage, orientation: cgImageOrientation)
            logger.info("Found \(boxes.count) text boxes")
            
            Task { @MainActor in
                textBoxes.boxes = boxes.map {NormalizedTextBox($0)}
            }
            
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            
            Task { @MainActor in
                textBoxes.boxes = []
            }
        }
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
