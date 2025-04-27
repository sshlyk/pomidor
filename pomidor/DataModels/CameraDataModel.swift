import AVFoundation
import SwiftUI
import os.log
import CoreML
import Vision

fileprivate let logger = Logger(subsystem: "pomidor", category: "DataModel")

final class CameraDataModel: ObservableObject {
    let camera = Camera()
    let textRecogntion = TextRecognition()
    
    @Published var viewfinderImage: Image?
    @Published var thumbnailImage: Image?
    
    init() {
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
//        let unpackedPhotoStream = camera.photoStream
//            .compactMap { self.unpackPhoto($0) }
        
        for await capturedPhoto in camera.photoStream {
            guard let cgImage = capturedPhoto.cgImageRepresentation() else { continue }
            
            await textRecogntion.performTextRecognition(cgImage: cgImage)
            
//            Task { @MainActor in
//                thumbnailImage = photoData.thumbnailImage
//            }
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
