import SwiftUI

struct SettingsFloatingButtonView: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(Color.clear)
                Image(systemName: "gearshape.fill")
                    .foregroundColor(.primary)
                    .font(.system(size: 18, weight: .semibold))
            }
            .frame(width: 52, height: 52)
            .liquidGlass(
                in: Circle(),
                borderColor: Color.primary.opacity(0.15)
            )
            .shadow(radius: 4, y: 2)
        }
        .buttonStyle(.plain)
    }
}
