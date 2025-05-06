import Vision
import SwiftUI
import Foundation
import os.log

protocol SnapshotHandlerDelegate {
    func nextPhotoFrame(capturedMovieTitle: CGImage?, text: [String]) async
}

fileprivate let logger = Logger(subsystem: "pomidor", category: "PhotoHandler")

class SnapshotsHandler {

    private let titleTrackingModel: VNCoreMLModel?
    private let stream: AsyncStream<CameraCapture>
    private var previewTittleTrackingFramesSkipped = 0

    init(titleTrackingModel: VNCoreMLModel?, stream: AsyncStream<CameraCapture>) {
        self.titleTrackingModel = titleTrackingModel
        self.stream = stream
    }
    
    func handleCameraPhotos(delegate: SnapshotHandlerDelegate) async {
        var detection: CGRect?
        let titleTrackingMLRequest = titleTrackingModel.map { model in
            MLHelpers.createObjectTrackingRequest(model: model) { detection = $0.first }
        }

        for await capturedPhoto in stream {

            var croppedCGImage: CGImage?
            
            if let cgImage = capturedPhoto.photo.cgImageRepresentation() {
                // find bounding box for the movie title
                if let request = titleTrackingMLRequest, let cameraOrientation = capturedPhoto.orientation {
                    try? VNImageRequestHandler(
                        cgImage: cgImage,
                        orientation: CGImagePropertyOrientation(cameraOrientation)
                    ).perform([request])
                    
                    if let box = detection {
                        let rectToCrop = box
                            // always scale first, ince rectangle is facing up when returned by ML
                            .scale(
                                widthFactor: AppConfig.OCR.kDetectedAreaWidthScale,
                                heightFactor: AppConfig.OCR.kDetectedAreaHeightScale
                            )
                            .rotateToMatch(imageOrientation: cameraOrientation)
                            .toImageCoordinates(cgImage: cgImage)
                            
                        croppedCGImage = cgImage.cropping(to: rectToCrop)
                    }
                }
            }
            
            var words: [String] = []
            if let title = croppedCGImage, let orientation = capturedPhoto.orientation {
                let result = recognizeText(cgImage: title, orientation: orientation)
                words = result.map{ $0.first?.string.lowercased() ?? "" }
            }
            
            await delegate.nextPhotoFrame(capturedMovieTitle: croppedCGImage, text: words)
        }
    }
    
    private func recognizeText(cgImage: CGImage, orientation: CameraSensorOrientation) -> [[VNRecognizedText]] {
        let requestHandler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation.toCGImageOrientation())
        
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
        
        try? requestHandler.perform([request])
        
        return out
    }
}
