import Foundation
import UIKit

struct Helpers {
    
    static func loadScreenshot(name: String, withExtension extenstion: String) -> UIImage? {
        let bundle = Bundle(for: PomidorTests.self)
            
        guard let img = bundle.url(forResource: name, withExtension: extenstion) else {
            return nil
        }
        
        guard let imgData = try? Data.init(contentsOf: img) else {
            return nil
        }
        
        return UIImage.init(data: imgData)
    }
    
}
