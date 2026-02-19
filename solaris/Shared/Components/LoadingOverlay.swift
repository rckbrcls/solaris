import SwiftUI

struct LoadingOverlay: View {
    @Binding var isVisible: Bool
    var title: String
    var systemImage: String? = "hourglass"

    var body: some View {
        if isVisible {
            ZStack {
                Color.overlayDimming
                    .ignoresSafeArea()
                VStack(spacing: 12) {
                    if let systemImage {
                        Image(systemName: systemImage)
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundColor(Color.textOnAccent.opacity(0.9))
                    }
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    Text(title)
                        .font(.callout.bold())
                        .foregroundColor(Color.textOnAccent.opacity(0.95))
                }
                .padding(.vertical, 18)
                .padding(.horizontal, 24)
                .liquidGlass(
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous),
                    borderColor: Color.overlayGlassBorder
                )
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.overlayGlass)
                )
                .shadow(color: Color.shadowDefault, radius: 16, x: 0, y: 6)
            }
            .transition(.opacity)
        }
    }
}
