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
                        blobs: [.gray, .black],
                        speed: 1.0,
                        blur: 0.7
                    )
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: .infinity, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: .infinity, style: .continuous)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )
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
