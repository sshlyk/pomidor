import AVFoundation
import SwiftUI
import os.log

fileprivate let logger = Logger(subsystem: "pomidor", category: "DataModel")

final class CameraDataModel: ObservableObject {
    let camera = Camera()
    let textRecogntion = TextRecognition()
    
    @Published var viewfinderImage: Image?
    @Published var thumbnailImage: Image?
    @Published var textBoxes: TextBoxes
    
    init() {
        textBoxes = TextBoxes()
        Task { await handleCameraPreviews() }
        Task { await handleCameraPhotos() }
    }
    
    func handleCameraPreviews() async {
        for await nextFrame in camera.previewStream {
            guard let frame = nextFrame.image else { continue }

            Task { @MainActor in
                viewfinderImage = frame
            }
        }
    }
    
    func handleCameraPhotos() async {
        
        for await capturedPhoto in camera.photoStream {
            defer {
                camera.resume()
            }
        
            
            guard let metadataOrientation = capturedPhoto.metadata[String(kCGImagePropertyOrientation)] as? UInt32,
                  let cgImageOrientation = CGImagePropertyOrientation(rawValue: metadataOrientation) else {
                return
            }
            
            guard let cgImage = capturedPhoto.cgImageRepresentation() else { continue }
            
            Task { @MainActor in
                viewfinderImage = Image(uiImage: UIImage(
                    cgImage: cgImage,
                    scale: 1,
                    orientation: UIImage.Orientation(cgImageOrientation)
                ))
            }
            
            let boxes = textRecogntion.performTextRecognition(cgImage: cgImage, orientation: cgImageOrientation)
            logger.info("Found \(boxes.count) text boxes")
            
            Task { @MainActor in
                textBoxes.boxes = boxes.map {NormalizedTextBox($0)}
            }
            
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            
            Task { @MainActor in
                textBoxes.boxes = []
            }
        }
    }

}

fileprivate extension CIImage {
    var image: Image? {
        let ciContext = CIContext()
        guard let cgImage = ciContext.createCGImage(self, from: self.extent) else { return nil }
        return Image(decorative: cgImage, scale: 1, orientation: .up)
    }
}

fileprivate extension Image.Orientation {

    init(_ cgImageOrientation: CGImagePropertyOrientation) {
        switch cgImageOrientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        }
    }
}

fileprivate extension UIImage.Orientation {
    
    init(_ cgImageOrientation: CGImagePropertyOrientation) {
        switch cgImageOrientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        case .left: self = .left
        }
    }
}
