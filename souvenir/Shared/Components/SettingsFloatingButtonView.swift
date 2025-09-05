import SwiftUI

struct SettingsFloatingButtonView: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(.ultraThinMaterial)
                Image(systemName: "gearshape.fill")
                    .foregroundColor(.primary)
                    .font(.system(size: 18, weight: .semibold))
            }
            .frame(width: 52, height: 52)
            .overlay(Circle().stroke(Color.primary.opacity(0.15), lineWidth: 1))
            .shadow(radius: 4, y: 2)
        }
        .buttonStyle(.plain)
    }
}

