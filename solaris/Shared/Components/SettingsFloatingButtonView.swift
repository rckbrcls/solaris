import SwiftUI

struct SettingsFloatingButtonView: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(Color.clear)
                Image(systemName: "gearshape.fill")
                    .foregroundColor(Color.textPrimary)
                    .font(.system(size: 18, weight: .semibold))
            }
            .frame(width: 52, height: 52)
            .liquidGlass(
                in: Circle(),
                borderColor: Color.borderMedium
            )
            .shadow(radius: 4, y: 2)
        }
        .buttonStyle(.plain)
    }
}
