import AVFoundation
import SwiftUI
import os.log
import CoreML
import Vision

final class TextRecognition {
    
    func performTextRecognition(cgImage: CGImage) async {
        let requestHandler = VNImageRequestHandler(cgImage: cgImage)
        let request = VNRecognizeTextRequest() { (request: VNRequest, error: Error?) in
            guard let observations = request.results as? [VNRecognizedTextObservation] else {
                return
            }
            
            let recognizedStrings = observations.compactMap { observation  in
                return observation.topCandidates(1).first
            }
            
            for string in recognizedStrings {
                print(string.string
                
                )
            }
        }
        
        do {
            try requestHandler.perform([request])
        } catch {
            print("Unable to perform the requests: \(error).")
        }
    }
    
}
