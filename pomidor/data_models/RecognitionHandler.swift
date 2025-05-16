import Vision
import SwiftUI
import Foundation
import os.log

fileprivate let logger = Logger(subsystem: "pomidor", category: "PhotoHandler")

actor RecognitionHandler {

    private let movieBoxModel: VNCoreMLModel
    
    init(movieBoxModel: VNCoreMLModel) {
        self.movieBoxModel = movieBoxModel
    }
    
    func handleCameraPhotos(cgImage: CGImage, orientation: CameraSensorOrientation) async -> (CGRect, String?)? {
        // for now we only consider one detection if multiple are found
        guard var detection = await detectMovieBox(cgImage: cgImage, orientation: orientation)?.first else {
            return nil
        }
        
        detection = detection.scale(widthFactor: AppConfig.OCR.kDetectedAreaWidthScale,
                                    heightFactor: AppConfig.OCR.kDetectedAreaHeightScale)
        
        let recognition = await recognizeText(cgImage: cgImage, orientation: orientation, regionOfInterest: detection)
        let words = recognition.map{ $0.first?.lowercased() ?? "" }
        return (detection, words.joined(separator: " "))
    }
    
    private func recognizeText(cgImage: CGImage,
                                      orientation: CameraSensorOrientation,
                                      regionOfInterest: CGRect) async -> [[String]] {
        await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest() { (request: VNRequest, error: Error?) in
                let observations = request.results as? [VNRecognizedTextObservation]
                let result = observations?.map { $0.topCandidates(2).map{ $0.string} }
                continuation.resume(returning: result ?? [])
            }
            
            request.automaticallyDetectsLanguage = AppConfig.OCR.kAutomaticallyDetectLanguages
            request.recognitionLanguages = AppConfig.OCR.kRecognizedLanguages.map { $0.identifier }
            request.recognitionLevel = AppConfig.OCR.kRecognitionLevel
            request.usesLanguageCorrection = AppConfig.OCR.kUseLanguageCorrection
            request.minimumTextHeight = AppConfig.OCR.kMinTextHight
            request.regionOfInterest = regionOfInterest
            
            let requestHandler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation.toCGImageOrientation())
            do {
                try requestHandler.perform([request])
            } catch {
                continuation.resume(returning: [])
            }
        }
    }
    
    func detectMovieBox(cgImage: CGImage, orientation: CameraSensorOrientation) async -> [CGRect]? {
        await withCheckedContinuation { continuation in

            let request = VNCoreMLRequest(model: movieBoxModel) { request, error in
                let observations = request.results as? [VNRecognizedObjectObservation]
                let result = observations?.map {$0.boundingBox }
                continuation.resume(returning: result)
            }
            
            do {
                try VNImageRequestHandler(cgImage: cgImage, orientation: CGImagePropertyOrientation(orientation))
                    .perform([request])
            } catch {
                logger.error("Failed to submit movie box request to a VNImageRequestHandler")
                continuation.resume(returning: nil)
            }
        }
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
