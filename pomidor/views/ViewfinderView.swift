import SwiftUI

struct ViewfinderView: View {
    @Binding var image: Image?
    @ObservedObject var boxes: TextBoxes
    
    var body: some View {
        GeometryReader { geometry in
            image?
            .resizable()
            .overlay {
                ForEach($boxes.boxes) { $box in
                    box.stroke(.red, lineWidth: 1)
                }
            }
             //.scaledToFit()
            .scaledToFill()
            .frame(
                width: geometry.size.width,
                height: geometry.size.height
            )
        }
    }
}

struct ViewfinderView_Previews: PreviewProvider {
    static var previews: some View {
        ViewfinderView(image: .constant(Image(systemName: "pencil")), boxes: TextBoxes())
    }
}
