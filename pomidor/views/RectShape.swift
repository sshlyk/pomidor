import SwiftUI
import Vision

struct RectShape: Shape {
    private let rect: CGRect
    
    init(_ normalizedRect: CGRect) {
       rect = normalizedRect
    }
    
    func path(in imageCoord: CGRect) -> Path {
        let imageArea = NormalizedRect(normalizedRect: rect).toImageCoordinates(imageCoord.size, origin: .upperLeft);
        return Path(roundedRect: imageArea, cornerRadius: 3)
    }
}
