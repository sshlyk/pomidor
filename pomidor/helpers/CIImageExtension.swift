import CoreImage

extension CIImage {
    var cgImage: CGImage? {
        let ciContext = CIContext()
        return ciContext.createCGImage(self, from: self.extent)
    }
}
