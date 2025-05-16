import Vision
import SwiftUI
import Foundation
import os.log

fileprivate let logger = Logger(subsystem: "pomidor", category: "PhotoHandler")

struct RecognitionHandler {

    static func handleCameraPhotos(cgImage: CGImage, orientation: CameraSensorOrientation, model: VNCoreMLModel) -> (CGRect, String?)? {
        // for now we only consider one detection if multiple are found
        guard var detection = MLHelpers.detectMovieBox(cgImage: cgImage, orientation: orientation, model: model)?.first else {
            return nil
        }
        
        detection = detection.scale(widthFactor: AppConfig.OCR.kDetectedAreaWidthScale,
                                    heightFactor: AppConfig.OCR.kDetectedAreaHeightScale)
        
        let recognition = recognizeText(cgImage: cgImage, orientation: orientation, regionOfInterest: detection)
        
        let words = recognition.map{ $0.first?.string.lowercased() ?? "" }
        
        return (detection, words.joined(separator: " "))
    }
    
    static private func recognizeText(cgImage: CGImage, orientation: CameraSensorOrientation, regionOfInterest: CGRect) -> [[VNRecognizedText]] {
        var out: [[VNRecognizedText]] = []
        
        let request = VNRecognizeTextRequest() { (request: VNRequest, error: Error?) in
            guard let observations = request.results as? [VNRecognizedTextObservation] else {
                return
            }
            
            for observation in observations {
                out.append(observation.topCandidates(2))
            }
        }
        
        request.automaticallyDetectsLanguage = AppConfig.OCR.kAutomaticallyDetectLanguages
        request.recognitionLanguages = AppConfig.OCR.kRecognizedLanguages.map { $0.identifier }
        request.recognitionLevel = AppConfig.OCR.kRecognitionLevel
        request.usesLanguageCorrection = AppConfig.OCR.kUseLanguageCorrection
        request.minimumTextHeight = AppConfig.OCR.kMinTextHight
        request.regionOfInterest = regionOfInterest
        
        let requestHandler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation.toCGImageOrientation())
        try? requestHandler.perform([request])
        
        return out
    }
}
