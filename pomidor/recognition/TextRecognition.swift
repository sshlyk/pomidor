import AVFoundation
import os.log
import CoreML
import Vision

fileprivate let logger = Logger(subsystem: "pomidor", category: "TextRecognition")

final class TextRecognition {
    
    func performTextRecognition(cgImage: CGImage) async {
        let requestHandler = VNImageRequestHandler(cgImage: cgImage)
        let request = VNRecognizeTextRequest() { (request: VNRequest, error: Error?) in
            guard var observations = request.results as? [VNRecognizedTextObservation] else {
                return
            }
            
            observations.sort { l, r in
                if l.boundingBox.size.height > r.boundingBox.size.height {
                    return true
                }
                
                if l.boundingBox.size.height == r.boundingBox.size.height {
                    return l.boundingBox.size.width > r.boundingBox.width
                }
                
                return false
            }
            
            for observation in observations {
                let size = observation.boundingBox.size
                let text = observation.topCandidates(1).first
                print("box size: \(size) text: \(text?.string)")
            }
            
            
            
//            let recognizedStrings = observations.compactMap { observation  in
//                return observation.topCandidates(1).first
//            }
//            
//            for string in recognizedStrings {
//                print(string.string)
//            }
        }
        
        do {
            try requestHandler.perform([request])
        } catch {
            logger.info("Unable to perform text reconition request")
        }
    }
    
}
