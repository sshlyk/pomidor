//
//  pomidorTests.swift
//  pomidorTests
//
//  Created by Mr S on 4/26/25.
//

import Testing

@testable import pomidor
import Foundation
import UIKit

class PomidorTests {

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
        
        guard let screenshot = Helpers.loadScreenshot(name: "yellowstone-city-netflix-tv", withExtension: "HEIC") else {
            Issue.record("could not load image file")
            return
        }
        
        let dataModel = pomidor.TextRecognition()
        
        let heatMap = dataModel.performTextRecognition(cgImage: screenshot.cgImage!, orientation: .up)
        
    }
}
