import Vision
import SwiftUI
import Foundation

protocol PreviewHandlerDelegate {
    // broadcasts preview frame and detections oriented as if image is rotated up based on preview orientation info
    func nextPreviewFrame(capture: PreviewCapture, detections: [CGRect]?) async
}

class PreviewHandler {
    
    private let titleTrackingModel: VNCoreMLModel?
    private let stream: AsyncStream<PreviewCapture>
    private var previewTittleTrackingFramesSkipped = 0

    init(titleTrackingModel: VNCoreMLModel?, stream: AsyncStream<PreviewCapture>) {
        self.titleTrackingModel = titleTrackingModel
        self.stream = stream
    }
    
    // Video frames that are displayed in the viewfinder
    // Detect region of the screen that contains movie title
    func handleCameraPreviews(delegate: PreviewHandlerDelegate) async {
        var detections: [CGRect]?
        let titleTrackingMLRequest = titleTrackingModel.map { model in
            MLHelpers.createObjectTrackingRequest(model: model) { detections = $0 }
        }

        for await nextFrame in stream {
            guard let previewCgImage = nextFrame.image.cgImage else {
                continue
            }
            
            if previewTittleTrackingFramesSkipped > 2 {
                // submit image for movie title tracking processing
                if let cameraOrientation = nextFrame.orientation, let request = titleTrackingMLRequest {
                    try? VNImageRequestHandler(
                        cgImage: previewCgImage,
                        orientation: CGImagePropertyOrientation(cameraOrientation)
                    ).perform([request])
                }
                
                previewTittleTrackingFramesSkipped = 0
            } else {
                previewTittleTrackingFramesSkipped += 1
            }
            
            await delegate.nextPreviewFrame(capture: nextFrame, detections: detections)
        }
    }
}
