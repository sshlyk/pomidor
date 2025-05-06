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
            
            let photo = capturedPhoto.photo.cgImageRepresentation()
            var wordRecognitions: [[VNRecognizedText]]?
            
            // extract image crop area and perfrom text recognition
            if let p = photo, let orientation = capturedPhoto.orientation, let request = titleTrackingMLRequest {
                try? VNImageRequestHandler(
                    cgImage: p,
                    orientation: CGImagePropertyOrientation(orientation)
                ).perform([request])
                
                detection = detection?.scale(
                    widthFactor: AppConfig.OCR.kDetectedAreaWidthScale,
                    heightFactor: AppConfig.OCR.kDetectedAreaHeightScale
                )
                
                wordRecognitions = detection.map { crop in
                    recognizeText(cgImage: p, orientation: orientation, regionOfInterest: crop)
                }
            }

            var imageCrop: CGImage? // cropped area extracted for debugging purposes
            if AppConfig.Debug.kShowCapturedMovieTitleCrop,
                let p = photo, let crop = detection, let orientation = capturedPhoto.orientation {
                imageCrop = p.cropping(to: crop
                    .rotateToMatch(imageOrientation: orientation)
                    .toImageCoordinates(cgImage: p)
                )
            }
            
            let words = wordRecognitions?.map{ $0.first?.string.lowercased() ?? ""}
            await delegate.nextPhotoFrame(capturedMovieTitle: imageCrop, text: words ?? [])
        }
    }
    
    private func recognizeText(cgImage: CGImage, orientation: CameraSensorOrientation, regionOfInterest: CGRect) -> [[VNRecognizedText]] {
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
