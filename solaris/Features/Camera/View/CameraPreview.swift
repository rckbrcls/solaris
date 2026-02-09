import SwiftUI
import AVFoundation

struct CameraPreview: UIViewControllerRepresentable {
    @Binding var capturedImage: UIImage?
    @Binding var capturedPhotoData: (Data, String)?
    @Binding var isPhotoTaken: Bool
    @Binding var isFlashOn: Bool
    @Binding var zoomFactor: CGFloat
    @Binding var isFrontCamera: Bool

    func makeUIViewController(context: Context) -> CameraViewController {
        let controller = CameraViewController()
        controller.capturedImage = $capturedImage
        controller.capturedPhotoData = $capturedPhotoData
        controller.isPhotoTaken = $isPhotoTaken
        controller.isFlashOn = $isFlashOn
        controller.zoomFactor = $zoomFactor
        controller.isFrontCamera = $isFrontCamera
        return controller
    }

    func updateUIViewController(_ uiViewController: CameraViewController, context: Context) {
        uiViewController.updateZoomFactor()
    }
}
