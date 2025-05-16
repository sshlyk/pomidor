import Vision
import CoreImage

struct MLHelpers {
    
    static func detectMovieBox(cgImage: CGImage, orientation: CameraSensorOrientation, model: VNCoreMLModel) -> [CGRect]? {
        
        var result: [CGRect]?
        
        let request = VNCoreMLRequest(model: model) { request, error in
            if let observations = request.results as? [VNRecognizedObjectObservation] {
                result = observations.map {$0.boundingBox }
            }
        }
        
        try? VNImageRequestHandler(
            cgImage: cgImage,
            orientation: CGImagePropertyOrientation(orientation)
        ).perform([request])
        
        return result
    }
}

// Image transformation needed relative to camera physical position when photo was taken to correctly pass it to ML
extension CGImagePropertyOrientation {
    init(_ cameraOrientation: CameraSensorOrientation) {
        switch cameraOrientation {
        case .up: self = .up
        case .down: self = .down
        case .right: self = .right
        case .left: self = .left
        }
    }
}

