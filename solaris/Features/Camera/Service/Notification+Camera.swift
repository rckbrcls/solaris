import Foundation

/// Camera session lifecycle notifications (used only for app scene phase changes).
/// Photo capture and camera switching now use delegate pattern via CameraViewControllerDelegate.
extension Notification.Name {
    static let pauseCameraSession = Notification.Name("pauseCameraSession")
    static let resumeCameraSession = Notification.Name("resumeCameraSession")
}
