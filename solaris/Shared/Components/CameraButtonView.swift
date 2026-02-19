import SwiftUI
import FluidGradient

struct CameraButtonView: View {
    let ns: Namespace.ID
    var action: () -> Void

    var body: some View {
        VStack {
            Spacer()
            Button(action: action) {
                ZStack {
                    FluidGradient(
                        blobs: [
                            Color.cameraGradientDark,
                            Color.cameraGradientMid,
                            Color(white: 0.40),
                            Color.cameraGradientMid,
                            Color.cameraGradientDark,
                        ],
                        speed: 1.0,
                        blur: 0.7
                    )
                    .liquidGlass(in: RoundedRectangle(cornerRadius: .infinity, style: .continuous))
                    .frame(width: 70, height: 70)
                    .cornerRadius(.infinity)

                    Image("star")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 28, height: 28)
                }
                .matchedTransitionSource(id: "camera", in: ns)
            }
            .padding(.bottom, 30)
        }
    }
}
