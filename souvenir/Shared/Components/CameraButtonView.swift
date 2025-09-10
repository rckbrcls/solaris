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
                        blobs: [.gray, .cyan, .teal],
                        speed: 1.0,
                        blur: 0.7
                    )
                    .background(.blue)
                    .frame(width: 70, height: 70)
                    .cornerRadius(.infinity)

                    Image(systemName: "eye.fill")
                        .foregroundColor(.white)
                        .font(.system(size: 20))
                }
                .matchedTransitionSource(id: "camera", in: ns)
            }
            .padding(.bottom, 30)
        }
    }
}
