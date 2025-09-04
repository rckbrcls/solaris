import SwiftUI

struct LoadingOverlay: View {
    @Binding var isVisible: Bool
    var title: String
    var systemImage: String? = "hourglass"

    var body: some View {
        if isVisible {
            ZStack {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                VStack(spacing: 12) {
                    if let systemImage {
                        Image(systemName: systemImage)
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundColor(.white.opacity(0.9))
                    }
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    Text(title)
                        .font(.callout.bold())
                        .foregroundColor(.white.opacity(0.95))
                }
                .padding(.vertical, 18)
                .padding(.horizontal, 24)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.black.opacity(0.25))
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.25), radius: 16, x: 0, y: 6)
            }
            .transition(.opacity)
        }
    }
}

