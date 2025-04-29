import AVFoundation
import os.log
import CoreML
import Vision

fileprivate let logger = Logger(subsystem: "pomidor", category: "TextRecognition")

final class TextRecognition {
    
    func performSaliencyRequest(image: CGImage?) -> [CGRect] {
        guard let cgImage = image else {
            return []
        }
        
        let request = VNGenerateAttentionBasedSaliencyImageRequest()
        
        let requestHandler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
        try? requestHandler.perform([request])
        
        guard let results = request.results else {
            return []
        }
    
       var out: [CGRect] = []
        for result in results {
            guard let salientObjects = result.salientObjects else {
                continue
            }
            for salientObject in salientObjects {
                out.append(salientObject.boundingBox)
            }
        }
        
        logger.info("Bounding boxes found: \(out.count)")
        
        return out
    }
    
    func performTextRecognition(cgImage: CGImage, orientation: CGImagePropertyOrientation) -> [CGRect] {
        let requestHandler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation)
        
        var out: [CGRect] = []
        
        let request = VNRecognizeTextRequest() { (request: VNRequest, error: Error?) in
            guard var observations = request.results as? [VNRecognizedTextObservation] else {
                return
            }
            
            for observation in observations {
                out.append(observation.boundingBox)
            }
        }
        
        do {
            try requestHandler.perform([request])
        } catch {
            logger.info("Unable to perform text reconition request")
        }
        
        return out
    }
    
}
