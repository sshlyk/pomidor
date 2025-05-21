import Foundation

actor TextBoxes: ObservableObject {
    @MainActor @Published var boxes: [CGRect] = []
}
