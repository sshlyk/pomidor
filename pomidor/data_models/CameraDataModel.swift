import AVFoundation
import SwiftUI
import os.log
import Vision

fileprivate let logger = Logger(subsystem: "pomidor", category: "DataModel")

final actor CameraDataModel: ObservableObject {
    @MainActor @Published var previewImage: Image?
    @MainActor @Published var rectBoxes: TextBoxes = TextBoxes()
    @MainActor @Published var infoText: String = ""
    @MainActor @Published var showWebView: Bool = false
    @MainActor @Published var webViewSearchQuery: String = ""
    
    private let camera = Camera()
    private let recognitionHandler: RecognitionHandler?
    private var currentOrientation: CameraSensorOrientation = .right // portrait mode. TODO better way to detect/set it
    
    init() {
        if let model = try? VNCoreMLModel(for: MovieTitlePosition(configuration: .init()).model) {
            recognitionHandler = RecognitionHandler(movieBoxModel: model)
        } else {
            recognitionHandler = nil
        }
        
        Task { await UIDevice.current.beginGeneratingDeviceOrientationNotifications() }
        Task { await self.consumeCameraPreview() }
        Task { await self.consumePhotoStream() }
        
        // track device orientation. if self is destroyed, the loop in this task will exit
        Task { @MainActor [weak self] in 
            for await notification in NotificationCenter.default.notifications(named: UIDevice.orientationDidChangeNotification) {
                guard let strongSelf = self, let orientation = (notification.object as? UIDevice)?.orientation else { return }
                Task { await strongSelf.setOrientation(deviceOrientation: orientation) }
            }
        }
    }
    
    private func consumeCameraPreview() async {
        var frameCount = 0
        var movieBoxes: [CGRect]?
        
        for await image in camera.previewStream {
            defer { frameCount += 1 }
            let orientation = currentOrientation
            
            if frameCount > AppConfig.ML.kFramesBetweenMovieBoxTracking {
                movieBoxes = await recognitionHandler?.detectMovieBox(cgImage: image, orientation: orientation)
                frameCount = 0
            }

            await setPreview(image: image, orientation: orientation, movieBoxes: movieBoxes)
        }
    }
    
    private func consumePhotoStream() async {
        guard let handler = recognitionHandler else { return }
        
        for await image in camera.photoStream {
            let orientation = currentOrientation
            
            let result = await handler.handleCameraPhotos(cgImage: image, orientation: orientation)
            guard let (detection, title) = result else {
                await setFoundMovie(result: nil)
                continue
            }
            
            if AppConfig.Debug.kShowCapturedMovieTitleCrop {
                let cropRect =  detection.rotateToMatch(imageOrientation: orientation).toImageCoordinates(cgImage: image)
                guard let crop = image.cropping(to: cropRect) else {
                    await setFoundMovie(result: nil)
                    continue
                }
                
                await camera.stop()
                await setPreview(image: crop, orientation: orientation, movieBoxes: nil)
                try? await Task.sleep(nanoseconds: AppConfig.UI.kSnapDelaySec * 1_000_000_000)
                await camera.start()
                
            } else {
                await setFoundMovie(result: title)
            }
        }
    }
    
    @MainActor
    private func setFoundMovie(result: String?) {
        if let movieTitle = result {
            webViewSearchQuery = movieTitle
            showWebView = true
            infoText = ""
        } else {
            infoText = AppConfig.UI.kNotFoundText
        }
    }
    
    @MainActor
    private func setPreview(image: CGImage, orientation: CameraSensorOrientation, movieBoxes: [CGRect]?) async {
        rectBoxes.boxes = movieBoxes?
            .map{ $0.rotateToMatch(imageOrientation: orientation) }
            // UI image will be rotated left (by specifying original rotation is right), as a result, rotate boxes to the left
            .map { NormalizedTextBox($0.rotateToMatch(imageOrientation: .left)) } ?? []
        previewImage = Image(decorative: image, scale: 1, orientation: .right)
    }
    
    func startCamera() async {
        await camera.start()
    }
    
    func stopCamera() async {
        await camera.stop()
    }
    
    func zoom(zoomFactor: CGFloat) async {
        await camera.zoom(zoomFactor: zoomFactor)
    }
    
    func captureImage() async {
        await camera.captureImage()
    }
    
    private func setOrientation(deviceOrientation: UIDeviceOrientation) async {
        switch deviceOrientation {
        case .portrait: currentOrientation = .right
        case .portraitUpsideDown: currentOrientation = .left
        case .landscapeLeft: currentOrientation = .up
        case .landscapeRight: currentOrientation = .down
        case .unknown, .faceUp, .faceDown: logger.info("Ignoring new device orientation")
        @unknown default: logger.error("Unknown device orientation detected")
        }
    }
}
