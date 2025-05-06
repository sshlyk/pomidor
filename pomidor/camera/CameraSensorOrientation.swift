import CoreImage

enum CameraSensorOrientation {
    case up    // picture is facing up
    case down  // sensor is upside down with top of the picture facing down
    case right // sensor is on its right side with top of the picture facing right
    case left  // sensor is on its left side with top of the picture facing left
    
    func toCGImageOrientation() -> CGImagePropertyOrientation {
        return CGImagePropertyOrientation(self)
    }
}
