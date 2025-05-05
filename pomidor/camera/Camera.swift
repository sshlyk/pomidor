import AVFoundation
import CoreImage
import UIKit
import os.log

class Camera: NSObject {
    private let captureSession = AVCaptureSession()
    private var isCaptureSessionConfigured = false
    private var deviceInput: AVCaptureDeviceInput?
    private var photoOutput: AVCapturePhotoOutput?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var sessionQueue: DispatchQueue!
    private var cameraSensorOrientation: CameraSensorOrientation?
    
    private var backCaptureDevices: [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            // it is probably best to try camera with optical zoom first. if not found, system default camera is used
            deviceTypes: [.builtInTelephotoCamera],
            mediaType: .video,
            position: .back
        ).devices
    }
    
    private var captureDevice: AVCaptureDevice? {
        didSet {
            guard let captureDevice = captureDevice else { return }
            logger.debug("Using capture device: \(captureDevice.localizedName)")
            sessionQueue.async {
                self.updateSessionForCaptureDevice(captureDevice)
            }
        }
    }
    
    var isRunning: Bool {
        captureSession.isRunning
    }

    private var addToPhotoStream: ((CameraCapture) -> Void)?
    
    private var addToPreviewStream: ((PreviewCapture) -> Void)?
    
    var isPreviewPaused = false
    
    lazy var previewStream: AsyncStream<PreviewCapture> = AsyncStream { continuation in
        addToPreviewStream = { previewCapture in
            if !self.isPreviewPaused {
                continuation.yield(previewCapture)
            }
        }
    }
    
    lazy var photoStream: AsyncStream<CameraCapture> = {
        AsyncStream { continuation in
            addToPhotoStream = { photo in
                continuation.yield(photo)
            }
        }
    }()
        
    override init() {
        super.init()
        initialize()
    }
    
    private func initialize() {
        sessionQueue = DispatchQueue(label: "session queue")
        
        let availableCaptureDevices = backCaptureDevices.filter { $0.isConnected && !$0.isSuspended }
        captureDevice = availableCaptureDevices.first ?? AVCaptureDevice.default(for: .video)
        
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateForDeviceOrientation),
            name: UIDevice.orientationDidChangeNotification,
            object: nil
        )
    }
    
    private func configureCaptureSession(completionHandler: (_ success: Bool) -> Void) {
        
        var isSuccess = false
        
        self.captureSession.beginConfiguration()
        
        defer {
            if isSuccess {
                self.captureSession.commitConfiguration()
            }
            completionHandler(isSuccess)
        }
        
        guard
            let captureDevice = captureDevice,
            let deviceInput = try? AVCaptureDeviceInput(device: captureDevice)
        else {
            logger.error("Failed to obtain video input.")
            return
        }
        
        let photoOutput = AVCapturePhotoOutput()
                        
        captureSession.sessionPreset = AVCaptureSession.Preset.photo

        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "VideoDataOutputQueue"))
  
        guard captureSession.canAddInput(deviceInput) else {
            logger.error("Unable to add device input to capture session.")
            return
        }
        guard captureSession.canAddOutput(photoOutput) else {
            logger.error("Unable to add photo output to capture session.")
            return
        }
        guard captureSession.canAddOutput(videoOutput) else {
            logger.error("Unable to add video output to capture session.")
            return
        }
        
        captureSession.addInput(deviceInput)
        captureSession.addOutput(photoOutput)
        captureSession.addOutput(videoOutput)
        
        self.deviceInput = deviceInput
        self.photoOutput = photoOutput
        self.videoOutput = videoOutput
        
        photoOutput.isHighResolutionCaptureEnabled = true
        photoOutput.maxPhotoQualityPrioritization = .quality
        
        isCaptureSessionConfigured = true
        
        isSuccess = true
    }
    
    private func checkAuthorization() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            logger.debug("Camera access authorized.")
            return true
        case .notDetermined:
            logger.debug("Camera access not determined.")
            sessionQueue.suspend()
            let status = await AVCaptureDevice.requestAccess(for: .video)
            sessionQueue.resume()
            return status
        case .denied:
            logger.debug("Camera access denied.")
            return false
        case .restricted:
            logger.debug("Camera library access restricted.")
            return false
        @unknown default:
            return false
        }
    }
    
    private func deviceInputFor(device: AVCaptureDevice?) -> AVCaptureDeviceInput? {
        guard let validDevice = device else { return nil }
        do {
            return try AVCaptureDeviceInput(device: validDevice)
        } catch let error {
            logger.error("Error getting capture device input: \(error.localizedDescription)")
            return nil
        }
    }
    
    private func updateSessionForCaptureDevice(_ captureDevice: AVCaptureDevice) {
        guard isCaptureSessionConfigured else { return }
        
        captureSession.beginConfiguration()
        defer { captureSession.commitConfiguration() }

        for input in captureSession.inputs {
            if let deviceInput = input as? AVCaptureDeviceInput {
                captureSession.removeInput(deviceInput)
            }
        }
        
        if let deviceInput = deviceInputFor(device: captureDevice) {
            if !captureSession.inputs.contains(deviceInput), captureSession.canAddInput(deviceInput) {
                captureSession.addInput(deviceInput)
            }
        }
    }
    
    func start() async {
        let authorized = await checkAuthorization()
        guard authorized else {
            logger.error("Camera access was not authorized.")
            return
        }
        
        if isCaptureSessionConfigured {
            if !captureSession.isRunning {
                sessionQueue.async { [self] in
                    self.captureSession.startRunning()
                }
            }
            return
        }
        
        sessionQueue.async { [self] in
            self.configureCaptureSession { success in
                guard success else { return }
                self.captureSession.startRunning()
            }
        }
        
        updateForDeviceOrientation()
    }
    
    func stop() {
        guard isCaptureSessionConfigured else { return }
        
        if captureSession.isRunning {
            sessionQueue.async {
                self.captureSession.stopRunning()
            }
        }
    }
    
    @objc
    func updateForDeviceOrientation() {
        switch UIDevice.current.orientation {
        case .portrait: cameraSensorOrientation = .right
        case .portraitUpsideDown: cameraSensorOrientation = .left
        case .landscapeLeft: cameraSensorOrientation = .up
        case .landscapeRight: cameraSensorOrientation = .down
        case .unknown, .faceUp, .faceDown: logger.info("Ignoring new device orientation")
        @unknown default: logger.error("Unknown device orientation detected")
        }
        
        // if we can not camera orientation based on device, use screen
        cameraSensorOrientation = cameraSensorOrientation ?? UIScreen.main.orientation
    }
    
    func captureImage() {
        guard let photoOutput = self.photoOutput else { return }
        
        sessionQueue.async {
            var photoSettings = AVCapturePhotoSettings()

            if photoOutput.availablePhotoCodecTypes.contains(.hevc) {
                photoSettings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
            }
            
            let isFlashAvailable = self.deviceInput?.device.isFlashAvailable ?? false
            photoSettings.flashMode = isFlashAvailable ? .auto : .off
//            photoSettings.isHighResolutionPhotoEnabled = true
//            if let previewPhotoPixelFormatType = photoSettings.availablePreviewPhotoPixelFormatTypes.first {
//                photoSettings.previewPhotoFormat = [kCVPixelBufferPixelFormatTypeKey as String: previewPhotoPixelFormatType]
//            }
            photoSettings.photoQualityPrioritization = .speed
            
            photoOutput.capturePhoto(with: photoSettings, delegate: self)
        }
    }
    
    func pause() {
        sessionQueue.async {
            self.isPreviewPaused = true
        }
    }
    
    func resume() {
        sessionQueue.async {
            self.isPreviewPaused = false
        }
    }
}

extension Camera: AVCapturePhotoCaptureDelegate {
    
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        
        if let error = error {
            logger.error("Error capturing photo: \(error.localizedDescription)")
            return
        }
        
        addToPhotoStream?(CameraCapture(photo: photo, orientation: cameraSensorOrientation))
    }
}

extension Camera: AVCaptureVideoDataOutputSampleBufferDelegate {
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = sampleBuffer.imageBuffer else { return }

        addToPreviewStream?(PreviewCapture(image: CIImage(cvPixelBuffer: pixelBuffer), orientation: cameraSensorOrientation))
    }
}

fileprivate extension UIScreen {

    var orientation: CameraSensorOrientation {
        let point = coordinateSpace.convert(CGPoint.zero, to: fixedCoordinateSpace)
        if point == CGPoint.zero {
            return .right
        } else if point.x != 0 && point.y != 0 {
            return .left
        } else if point.x == 0 && point.y != 0 {
            return .up
        } else if point.x != 0 && point.y == 0 {
            return .down
        } else {
            return .up
        }
    }
}

fileprivate let logger = Logger(subsystem: "pomidor", category: "Camera")

