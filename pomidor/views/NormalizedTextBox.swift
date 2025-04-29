import SwiftUI
import Vision

struct NormalizedTextBox: Shape, Identifiable {
    var id: String {
        rect.debugDescription // TODO do better for id
    }
    
    private let rect: CGRect
    
    init(_ normalizedRect: CGRect) {
       rect = normalizedRect
    }
    
    func path(in imageCoord: CGRect) -> Path {
        return Path(NormalizedRect(normalizedRect: rect).toImageCoordinates(imageCoord.size, origin: .upperLeft))
    }

}
