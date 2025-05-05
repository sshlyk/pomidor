import CoreImage

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
