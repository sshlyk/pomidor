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
        static let kDetectedAreaScale: Double = 0 // increase detected rectangular before cropping
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
