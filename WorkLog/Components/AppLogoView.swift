import SwiftUI

struct AppLogoView: View {
    var size: CGFloat = 24
    var cornerRadius: CGFloat = 6

    var body: some View {
        Image("Logo")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}
