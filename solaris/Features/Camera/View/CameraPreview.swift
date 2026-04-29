import SwiftUI
import AVFoundation

/// Command bridge: allows SwiftUI buttons to trigger actions on the CameraViewController.
/// IMPORTANT: Must be held in `@State` to preserve identity across SwiftUI view updates.
/// The `controller` reference is set by CameraPreview and would be lost if a new instance is created per render.
class CameraCommands {
    weak var controller: CameraViewController?

    func capture() { controller?.capturePhoto() }
    func switchCamera() { controller?.switchCamera() }
    func pause() { controller?.pauseSession() }
    func resume() { controller?.resumeSession() }
}

/// Bridges CameraViewController (UIKit) into SwiftUI using a Coordinator as delegate.
struct CameraPreview: UIViewControllerRepresentable {
    var onPhotoCaptured: (Data, String, UIImage?) -> Void
    var onCameraSwitched: (Bool) -> Void
    var flashEnabled: Bool
    var zoomFactor: CGFloat
    var commands: CameraCommands

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> CameraViewController {
        let controller = CameraViewController()
        controller.controllerDelegate = context.coordinator
        controller.flashEnabled = flashEnabled
        commands.controller = controller
        return controller
    }

    func updateUIViewController(_ uiViewController: CameraViewController, context: Context) {
        uiViewController.flashEnabled = flashEnabled
        uiViewController.updateZoom(zoomFactor)
        // Keep commands reference fresh
        commands.controller = uiViewController
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, CameraViewControllerDelegate {
        let parent: CameraPreview

        init(parent: CameraPreview) {
            self.parent = parent
        }

        func cameraDidCapture(data: Data, ext: String, thumbnail: UIImage?) {
            parent.onPhotoCaptured(data, ext, thumbnail)
        }

        func cameraDidSwitchCamera(isFront: Bool) {
            parent.onCameraSwitched(isFront)
        }
    }
}
