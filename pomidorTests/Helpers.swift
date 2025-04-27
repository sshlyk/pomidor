import Foundation
import UIKit

struct Helpers {
    
    static func loadScreenshot(name: String) -> CGImage? {
        let bundle = Bundle(for: PomidorTests.self)
        let path = bundle.bundlePath
            
        guard let img = bundle.url(forResource: name, withExtension: "png") else {
            return nil
        }
        
        guard let imgData = try? Data.init(contentsOf: img) else {
            return nil
        }
        
        return UIImage.init(data: imgData)?.cgImage
    }
    
}
