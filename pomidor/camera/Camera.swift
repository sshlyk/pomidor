import AVFoundation
import CoreImage
import UIKit
import os.log

fileprivate let logger = Logger(subsystem: "pomidor", category: "Camera")

class Camera: NSObject {
    private let captureSession = AVCaptureSession()
    private let dispatchQueue: DispatchQueue = DispatchQueue(label: "camera queue")
    
    let previewStream: AsyncStream<PreviewCapture>
    private let previewStreamContinuation: AsyncStream<PreviewCapture>.Continuation
    
    let photoStream: AsyncStream<CameraCapture>
    private let photoStreamContinuation: AsyncStream<CameraCapture>.Continuation
    
    private var cameraSensorOrientation: CameraSensorOrientation?
    private var photoOutput: AVCapturePhotoOutput?
    private var captureDevice: AVCaptureDevice?
    
    deinit {
        // terminate stream that publish preview images and taken photos
        previewStreamContinuation.finish()
        photoStreamContinuation.finish()
    }
        
    override init() {
        (previewStream, previewStreamContinuation) = AsyncStream<PreviewCapture>.makeStream(bufferingPolicy: .bufferingNewest(1))
        (photoStream, photoStreamContinuation) = AsyncStream<CameraCapture>.makeStream(bufferingPolicy: .bufferingNewest(1))

        super.init()
    }
    
    // Public APIs. Must be thread safe -------------------------
        
    func start() async {
        return await withCheckedContinuation { continuation in
            dispatchQueue.async {
                Task {
                    defer { continuation.resume() }
                    
                    guard await self.checkAuthorization() else {
                        logger.error("Camera access was not authorized.")
                        return
                    }
                    
                    guard self.configureCaptureSession() else {
                        return
                    }
                    
                    if !self.captureSession.isRunning {
                        self.captureSession.startRunning()
                    }
                    
                    self.updateForDeviceOrientation()
                }
            }
        }
    }
    
    func stop() {
        dispatchQueue.async {
            guard self.captureSession.isRunning else { return }
            self.captureSession.stopRunning()
        }
    }
    
    func captureImage() {
        
        dispatchQueue.async {
            guard let photoOutput = self.photoOutput else { return }
            
            var photoSettings = AVCapturePhotoSettings()

            if photoOutput.availablePhotoCodecTypes.contains(.jpeg) {
                photoSettings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
            }
            
            photoSettings.flashMode = AppConfig.Camera.kDisableFlashMode ? .off : .auto
            photoSettings.isHighResolutionPhotoEnabled = AppConfig.Camera.kEnableHighResolution
//            if let previewPhotoPixelFormatType = photoSettings.availablePreviewPhotoPixelFormatTypes.first {
//                photoSettings.previewPhotoFormat = [kCVPixelBufferPixelFormatTypeKey as String: previewPhotoPixelFormatType]
//            }
            photoSettings.photoQualityPrioritization = AppConfig.Camera.kPhotoQuality
            photoOutput.capturePhoto(with: photoSettings, delegate: self)
        }
    }
    
    func zoom(zoomFactor: CGFloat) {
        dispatchQueue.async {
            do {
                guard let device = self.captureDevice else {
                    return
                }
                
                try device.lockForConfiguration()
                device.videoZoomFactor = max(1, min(zoomFactor, device.activeFormat.videoMaxZoomFactor))
                device.unlockForConfiguration()
            } catch {
                logger.error("Failed to set video zoom factor \(zoomFactor)")
            }
        }
    }
    
    // Private APIs -------------------------
    
    private func configureCaptureSession() -> Bool {
        if self.captureDevice != nil { return true }
        
        // it is probably best to try camera with optical zoom first. if not found, system default camera is used
        let availableCaptureDevices = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInTelephotoCamera],
            mediaType: .video,
            position: .back
        ).devices.filter { $0.isConnected && !$0.isSuspended }

        guard
            let device = availableCaptureDevices.first ?? AVCaptureDevice.default(for: .video),
            let deviceInput = try? AVCaptureDeviceInput(device: device)
        else {
            logger.error("Failed to obtain video input.")
            return false
        }
        
        let photoOutput = AVCapturePhotoOutput()
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.setSampleBufferDelegate(self, queue: dispatchQueue)
  
        guard captureSession.canAddInput(deviceInput) else {
            logger.error("Unable to add device input to capture session.")
            return false
        }
        guard captureSession.canAddOutput(photoOutput) else {
            logger.error("Unable to add photo output to capture session.")
            return false
        }
        guard captureSession.canAddOutput(videoOutput) else {
            logger.error("Unable to add video output to capture session.")
            return false
        }
        
        self.captureSession.beginConfiguration()
        captureSession.sessionPreset = AVCaptureSession.Preset.photo
        captureSession.addInput(deviceInput)
        captureSession.addOutput(photoOutput)
        captureSession.addOutput(videoOutput)
        self.captureSession.commitConfiguration()
        
        self.photoOutput = photoOutput
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateForDeviceOrientation),
            name: UIDevice.orientationDidChangeNotification,
            object: nil
        )
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        
        self.captureDevice = device
        return true
    }
    
    private func checkAuthorization() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            logger.debug("Camera access authorized.")
            return true
        case .notDetermined:
            logger.debug("Camera access not determined.")
            return await AVCaptureDevice.requestAccess(for: .video)
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
    
    @objc
    private func updateForDeviceOrientation() {
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
}

extension Camera: AVCapturePhotoCaptureDelegate {
    
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            logger.error("Error capturing photo: \(error.localizedDescription)")
            return
        }
        
        photoStreamContinuation.yield(CameraCapture(photo: photo, orientation: cameraSensorOrientation))
    }
}

extension Camera: AVCaptureVideoDataOutputSampleBufferDelegate {
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = sampleBuffer.imageBuffer else { return }

        previewStreamContinuation.yield(PreviewCapture(image: CIImage(cvPixelBuffer: pixelBuffer), orientation: cameraSensorOrientation))
    }
}

fileprivate extension UIScreen {
    // If camera orientation can not be obtained from device orientation, use screen orientation as a backup
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

