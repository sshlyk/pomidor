import AVFoundation
import SwiftUI
import os.log
import Vision

fileprivate let logger = Logger(subsystem: "pomidor", category: "DataModel")

final class CameraDataModel: ObservableObject, PreviewHandlerDelegate {
    
    private let camera = Camera()
    private let textRecogntion = TextRecognition()
    private let titleTrackingModel: VNCoreMLModel?
    private var previewTittleTrackingFramesSkipped = 0
    private var previewHandler: PreviewHandler?
    private let 🤷 = "🤷‍♂️"
    
    @Published var viewfinderImage: Image?
    @Published var thumbnailImage: Image?
    @Published var textBoxes: TextBoxes
    @Published var movieName: String
    
    init() {
        titleTrackingModel = try? VNCoreMLModel(for: MovieTitlePosition(configuration: .init()).model)
        textBoxes = TextBoxes()
        movieName = 🤷
        previewHandler = PreviewHandler(titleTrackingModel: titleTrackingModel, stream: camera.previewStream)
        Task { await previewHandler?.handleCameraPreviews(delegate: self) }
        Task { await handleCameraPhotos() }
    }
    
    func start() async {
        await camera.start()
    }
    
    func captureImage() {
        textBoxes.boxes = [] // clear on-screen tracking
        camera.pause() // pause viewfinder video so still picture does not feel jumping when ready
        camera.captureImage()
    }
    
    func nextPreviewFrame(capture: PreviewCapture, detections: [CGRect]?) {
        guard let previewCgImage = capture.image.cgImage else { return }
        
        let transformedDetections = capture.orientation.flatMap { orientation in
            detections?.map { $0.rotateToMatch(imageOrientation: orientation) }
        }
        
        Task { @MainActor in
            // Display image. The image is currently rotated left when rendered
            // Text boxes needs to be rotated to the left
            viewfinderImage =  Image(decorative: previewCgImage, scale: 1, orientation: .right)
            textBoxes.boxes = transformedDetections?.map {
                NormalizedTextBox($0.rotateToMatch(imageOrientation: .left))
            } ?? []
        }
    }
    
    func handleCameraPhotos() async {
        var titleBox: CGRect?
        
        let findTitleBoundingBox = createTitleTrackingRequest { observations in
            titleBox = observations.first
        }
        
        for await capturedPhoto in camera.photoStream {
            // when done processing photo, resume viewfinder and
            defer {
                camera.resume()
            }
            
            guard let cgImage = capturedPhoto.photo.cgImageRepresentation() else { continue }
            
            // find bounding box for the movie title
            if let request = findTitleBoundingBox, let cameraOrientation = capturedPhoto.orientation {
                try? VNImageRequestHandler(
                    cgImage: cgImage,
                    orientation: CGImagePropertyOrientation(cameraOrientation)
                ).perform([request])
                
                if let box = titleBox {
                    let boxAlignedWithImage = box.rotateToMatch(imageOrientation: cameraOrientation)
                    
                    let croppedImage = cgImage.cropping(to: NormalizedRect(normalizedRect: boxAlignedWithImage)
                        .toImageCoordinates(CGSize(width: cgImage.width, height: cgImage.height), origin: .upperLeft))
                    
                    
                    Task { @MainActor in
                        textBoxes.boxes = [NormalizedTextBox(boxAlignedWithImage.rotateToMatch(imageOrientation: .left))]
                        movieName = "some movie title"
                        
                        // giving orientation .right instruct view to rotate image left when displayed to restore original up position
                        viewfinderImage = Image(uiImage: UIImage(cgImage: croppedImage!, scale: 1, orientation: .right))
                    }
                }
            }
            
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            Task { @MainActor in
                movieName = ""
            }
        }
    }
    
    private func createTitleTrackingRequest(handler: @escaping ([CGRect]) -> Void) -> VNCoreMLRequest?  {
        var titleTrackingMLRequest: VNCoreMLRequest?
        
        if let model = titleTrackingModel {
            titleTrackingMLRequest = VNCoreMLRequest(model: model) { request, error in
                if let observations = request.results as? [VNRecognizedObjectObservation] {
                    // Bounding boxes returned by vision framework have origin at the bottom left (mac).
                    // iOS uses top left origin instead
                    handler(observations.map {$0.boundingBox })
                }
            }
        }
        
        // image can be rotated or region of interest selected
        //titleTrackingMLRequest?.imageCropAndScaleOption = .scaleFillRotate90CCW
        //titleTrackingMLRequest?.regionOfInterest = ...
        
        return titleTrackingMLRequest
    }
}
