import CoreFoundation
import CoreGraphics
import Vision

extension CGRect {
    // rotates rectangular box to match image orientation
    func rotateToMatch(imageOrientation: CameraSensorOrientation) -> CGRect {
        switch imageOrientation {
        case .up: return self // image is facing up. box is already positioned correctly
        case .down: return self.rotatePlaneUpsideDown() // image is upside down. rotate box upside down
        case .right: return self.rotatePlaneRight() // image is facing right. rotate box to face right
        case .left: return self.rotatePlaneLeft() // image is facing left. rotate box to face left
        }
    }
    
    // convert normalized rectangle to actual image coordinates
    func toImageCoordinates(cgImage: CGImage) -> CGRect {
        let size = CGSize(width: cgImage.width, height: cgImage.height);
        return NormalizedRect(normalizedRect: self).toImageCoordinates(size, origin: .upperLeft)
    }
    
    func scale(widthFactor wFactor: Double, heightFactor hFactor: Double) -> CGRect {
        return self.insetBy(dx: -self.size.width * wFactor, dy: -self.size.height * hFactor)
    }
    
    // ---------------------------------------------
    
    // move origin from top left corner to bottom left (rotating plane to the left)
    private func rotatePlaneLeft() -> CGRect {
        return CGRect(
            origin: CGPoint(x: self.origin.y, y: 1 - self.origin.x - self.size.width),
            size: CGSize(width: self.size.height, height: self.size.width))
    }
    
    // move origin from top left to top right (rotating plane to the right)
    private func rotatePlaneRight() -> CGRect {
        return CGRect(
            origin: CGPoint(x: 1 - self.origin.y - self.size.height, y: self.origin.x),
            size: CGSize(width: self.size.height, height: self.size.width))
    }
    
    // move origin from top left corner to bottom right (horizontal reflection of the plane)
    private func rotatePlaneUpsideDown() ->CGRect {
        return CGRect(
            origin: CGPoint(x: 1 - self.origin.x - self.width, y: 1 - self.origin.y - self.height),
            size: self.size)
    }
}
