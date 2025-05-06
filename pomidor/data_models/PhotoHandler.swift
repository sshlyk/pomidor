import Vision
import SwiftUI
import Foundation

protocol PhotoHandlerDelegate {
    func nextPhotoFrame(capturedMovieTitle: CGImage?, text: [String]) async
}

class PhotoHandler {
    
    private let titleTrackingModel: VNCoreMLModel?
    private let stream: AsyncStream<CameraCapture>
    private var previewTittleTrackingFramesSkipped = 0

    init(titleTrackingModel: VNCoreMLModel?, stream: AsyncStream<CameraCapture>) {
        self.titleTrackingModel = titleTrackingModel
        self.stream = stream
    }
    
    func handleCameraPhotos(delegate: PhotoHandlerDelegate) async {
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
                        let boxAlignedWithImage = box.rotateToMatch(imageOrientation: cameraOrientation)
                        croppedCGImage = cgImage.cropping(to: boxAlignedWithImage.toImageCoordinates(cgImage: cgImage))
                    }
                }
                
                await delegate.nextPhotoFrame(capturedMovieTitle: croppedCGImage, text: [])
            }
        }
    }
}
