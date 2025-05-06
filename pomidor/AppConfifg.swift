import Foundation
import AVFoundation
import Vision

struct AppConfig {
    typealias Language = Locale.LanguageCode
    
    struct OCR {
        static let kRecognizedLanguages: [Language] = [.english]
        static let kRecognitionLevel: VNRequestTextRecognitionLevel = .accurate
        static let kUseLanguageCorrection = true
        static let kMinTextHight: Float = 0.05 // relative to image
        static let kDetectedAreaScale = 0.05 // increase detected rectangular before cropping
        static let kAutomaticallyDetectLanguages = false
    }
    
    struct Camera {
        static let kPhotoQuality: AVCapturePhotoOutput.QualityPrioritization = .balanced
        static let kEnableHighResolution = true
        static let kDisableFlashMode = true
    }
    
    struct UI {
        static let kNotFoundText = "🤷"
        static let kSnapDelaySec:UInt64 = 2
    }

}
