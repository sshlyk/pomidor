import Foundation
import AVFoundation
import Vision

struct AppConfig {
    typealias Language = Locale.LanguageCode
    
    struct OCR {
        static let kRecognizedLanguages: [Language] = [.english]
        static let kRecognitionLevel: VNRequestTextRecognitionLevel = .accurate
        static let kUseLanguageCorrection = true
        static let kMinTextHight: Float = 0.5 // relative to image
        static let kDetectedAreaWidthScale: Double = 0.15 // increase detected rectangular width before cropping
        static let kDetectedAreaHeightScale: Double = 0.05 // increase detected rectangular height before cropping
        static let kAutomaticallyDetectLanguages = false
    }
    
    struct Camera {
        static let kPhotoQuality: AVCapturePhotoOutput.QualityPrioritization = .balanced
        static let kEnableHighResolution = false
        static let kDisableFlashMode = true
    }
    
    struct UI {
        static let kNotFoundText = "🤷"
        static let kSnapDelaySec:UInt64 = 2 // delay after snapshot take to display the result

    }
    
    struct Debug {
        static let kShowCapturedMovieTitleCrop = true // show captured cropped movie title image
    }

}
