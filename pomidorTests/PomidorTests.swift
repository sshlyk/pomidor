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
import XCTest

class PomidorTests {

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
        
        guard let screenshot = Helpers.loadScreenshot(name: "netflix-screenshot-1") else {
            XCTExpectFailure("could not load screenshot")
            return
        }
        
        let dataModel = pomidor.TextRecognition()
        
        await dataModel.performTextRecognition(cgImage: screenshot)
    }


}
