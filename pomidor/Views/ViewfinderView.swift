import SwiftUI

struct ViewfinderView: View {
    @Binding var image: Image?
    
    var body: some View {
        GeometryReader { geometry in
            image?
            .resizable()
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
        ViewfinderView(image: .constant(Image(systemName: "pencil")))
    }
}
