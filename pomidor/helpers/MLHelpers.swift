import Vision

struct MLHelpers {
    static func createObjectTrackingRequest(
        model: VNCoreMLModel,
        _ handler: @escaping ([CGRect]) -> Void) -> VNCoreMLRequest
    {
        let request = VNCoreMLRequest(model: model) { request, error in
            if let observations = request.results as? [VNRecognizedObjectObservation] {
                handler(observations.map {$0.boundingBox })
            }
        }
        
        // image can be rotated or region of interest selected
        //request?.imageCropAndScaleOption = .scaleFillRotate90CCW
        //request?.regionOfInterest = ...
        
        return request
    }
}

