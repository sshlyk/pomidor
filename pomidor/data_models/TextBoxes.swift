import Foundation

class TextBoxes: ObservableObject {
    @Published var boxes: [NormalizedTextBox]
    
    init() {
        self.boxes = []
    }
}
