import SwiftUI

struct ViewfinderView: View {
    @Binding var image: Image?
    @ObservedObject var boxes: TextBoxes
    
    // TODO Temp variable to display recognized movie title as string for dev purposes
    @Binding var movieTitle: String
    
    var body: some View {
        GeometryReader { geometry in
            image?
            .resizable()
            .overlay {
                ForEach($boxes.boxes) { $box in
                    box.stroke(.red, lineWidth: 2)
                }
            }
            .overlay{
                Text(movieTitle)
                    .font(.largeTitle)
                    .background(.white.opacity(0.8))
                    .cornerRadius(10)
            }
            .scaledToFit()
            //.scaledToFill()
            .frame(
                width: geometry.size.width,
                height: geometry.size.height
            )
        }
    }
}

struct ViewfinderView_Previews: PreviewProvider {
    static var previews: some View {
        ViewfinderView(
            image: .constant(Image(systemName: "pencil")),
            boxes: TextBoxes(),
            movieTitle: .constant("Movie Title")
        )
    }
}
