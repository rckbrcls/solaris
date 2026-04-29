import SwiftUI

@main
struct SolarisApp: App {
    @State private var colorSchemeManager = ColorSchemeManager()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(colorSchemeManager)
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .background:
                NotificationCenter.default.post(name: .pauseCameraSession, object: nil)
            case .active:
                NotificationCenter.default.post(name: .resumeCameraSession, object: nil)
            default:
                break
            }
        }
    }
}
