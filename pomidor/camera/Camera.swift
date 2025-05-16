import AVFoundation
import CoreImage
import UIKit
import os.log

fileprivate let logger = Logger(subsystem: "pomidor", category: "Camera")

actor Camera {
    let previewStream: AsyncStream<CGImage>
    let photoStream: AsyncStream<CGImage>
    
    private let captureSession = AVCaptureSession()
    private let photoCaptureDelegate: PhotoCaptureDelegate
    private let previewCaptureDelegate: PreviewCaptureDelegate
    private let videoPreviewDelegateQueue = DispatchQueue(label: "video queue delegate")
    
    private var photoOutput: AVCapturePhotoOutput?
    private var captureDevice: AVCaptureDevice?
    private var cameraSensorOrientation: CameraSensorOrientation?
        
    init() {
        let (previewStream, previewStreamContinuation) = AsyncStream<CGImage>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let (photoStream, photoStreamContinuation) = AsyncStream<CGImage>.makeStream(bufferingPolicy: .bufferingNewest(1))
        
        photoCaptureDelegate = PhotoCaptureDelegate(photoStreamContinuation)
        previewCaptureDelegate = PreviewCaptureDelegate(previewStreamContinuation)
        
        self.previewStream = previewStream
        self.photoStream = photoStream
    }
    
    // Public APIs
        
    func start() async {
        guard await self.checkAuthorization() else {
            logger.error("Camera access was not authorized.")
            return
        }

        if self.captureDevice == nil {
            guard configureCaptureSession() else {
                return
            }
        }

        if !self.captureSession.isRunning {
            self.captureSession.startRunning()
        }
    }
    
    func stop() async {
        guard self.captureSession.isRunning else { return }
        self.captureSession.stopRunning()
    }
    
    func captureImage() async {
        guard let photoOutput = photoOutput else { return }
        
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
        photoOutput.capturePhoto(with: photoSettings, delegate: photoCaptureDelegate)
    }
    
    func zoom(zoomFactor: CGFloat) async {
        guard let device = captureDevice else { return }
        
        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = max(1, min(zoomFactor, device.activeFormat.videoMaxZoomFactor))
            device.unlockForConfiguration()
        } catch {
            logger.error("Failed to set video zoom factor \(zoomFactor)")
        }
    }
    
    // Private APIs -------------------------
    
    private func configureCaptureSession() -> Bool {
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
        
        videoOutput.setSampleBufferDelegate(previewCaptureDelegate, queue: videoPreviewDelegateQueue)
  
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
        
        self.captureDevice = device
        self.photoOutput = photoOutput

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
}

fileprivate class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private let continuation: AsyncStream<CGImage>.Continuation
    
    init(_ continuation: AsyncStream<CGImage>.Continuation) {
        self.continuation = continuation
    }
    
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        // by default, this delegate is dispatched on main queue
        assert(Thread.isMainThread)
        
        if let error = error {
            logger.error("Error capturing photo: \(error.localizedDescription)")
            return
        }
        
        guard let cgImage = photo.cgImageRepresentation() else {
            logger.error("Could not convert AVCapturePhoto to CGImage")
            return
        }
        
        continuation.yield(cgImage)
    }
}

class PreviewCaptureDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let continuation: AsyncStream<CGImage>.Continuation
    private var orientation: CameraSensorOrientation?
    
    init(_ continuation: AsyncStream<CGImage>.Continuation) {
        self.continuation = continuation
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        assert(!Thread.isMainThread)
        guard let pixelBuffer = sampleBuffer.imageBuffer else { return }

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = CIContext().createCGImage(ciImage, from: ciImage.extent) else { return }
        
        continuation.yield(cgImage)
    }
}

