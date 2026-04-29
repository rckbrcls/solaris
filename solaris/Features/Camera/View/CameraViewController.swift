import UIKit
import AVFoundation

/// Delegate for CameraViewController events — used by the Coordinator.
protocol CameraViewControllerDelegate: AnyObject {
    func cameraDidCapture(data: Data, ext: String, thumbnail: UIImage?)
    func cameraDidSwitchCamera(isFront: Bool)
}

/// Slim view controller: manages gestures, overlays, and delegates camera logic to CameraService.
class CameraViewController: UIViewController, CameraServiceDelegate {
    weak var controllerDelegate: CameraViewControllerDelegate?
    let cameraService = CameraService()

    var flashEnabled: Bool = false
    private var isFocusLocked: Bool = false
    private var focusIndicatorView: UIView?
    private var flashOverlayView: UIView?
    private var subjectAreaObserver: NSObjectProtocol?

    override func viewDidLoad() {
        super.viewDidLoad()

        cameraService.delegate = self

        // Setup preview layer
        let previewLayer = AVCaptureVideoPreviewLayer(session: cameraService.session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.layer.bounds
        if let connection = previewLayer.connection, connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        view.layer.addSublayer(previewLayer)
        cameraService.previewLayer = previewLayer

        // Flash overlay
        flashOverlayView = UIView(frame: view.bounds)
        flashOverlayView?.backgroundColor = UIColor.white
        flashOverlayView?.alpha = 0
        flashOverlayView?.isUserInteractionEnabled = false
        view.addSubview(flashOverlayView!)

        // Gestures
        let pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinchGesture(_:)))
        view.addGestureRecognizer(pinchGesture)

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTapGesture(_:)))
        tapGesture.numberOfTapsRequired = 1
        let doubleTapGesture = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTapGesture(_:)))
        doubleTapGesture.numberOfTapsRequired = 2
        tapGesture.require(toFail: doubleTapGesture)
        view.addGestureRecognizer(doubleTapGesture)
        view.addGestureRecognizer(tapGesture)

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPressGesture(_:)))
        longPress.minimumPressDuration = 0.5
        view.addGestureRecognizer(longPress)

        // Configure camera and subject area monitoring
        let initialPosition: AVCaptureDevice.Position = AppSettings.shared.cameraUseFrontCamera ? .front : .back
        cameraService.configure(position: initialPosition)
        cameraService.configureSubjectAreaMonitoring(enabled: true)

        // Listen for app lifecycle notifications (pause/resume camera when app backgrounds)
        NotificationCenter.default.addObserver(self, selector: #selector(handlePauseSession), name: .pauseCameraSession, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleResumeSession), name: .resumeCameraSession, object: nil)

        // Initialize AF/AE to center
        let center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
        let devicePoint = cameraService.previewLayer?.captureDevicePointConverted(fromLayerPoint: center) ?? CGPoint(x: 0.5, y: 0.5)
        cameraService.focusAndExpose(at: devicePoint, lock: false)

        // Subject area change observer
        setupSubjectAreaObserver()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        cameraService.previewLayer?.frame = view.bounds
        if let connection = cameraService.previewLayer?.connection, connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        flashOverlayView?.frame = view.bounds
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        cameraService.pause()
        NotificationCenter.default.removeObserver(self, name: .pauseCameraSession, object: nil)
        NotificationCenter.default.removeObserver(self, name: .resumeCameraSession, object: nil)
        if let observer = subjectAreaObserver {
            NotificationCenter.default.removeObserver(observer)
            subjectAreaObserver = nil
        }
    }

    @objc private func handlePauseSession() { pauseSession() }
    @objc private func handleResumeSession() { resumeSession() }

    // MARK: - CameraServiceDelegate

    func cameraDidCapturePhoto(data: Data, ext: String, thumbnail: UIImage?) {
        flashOverlayView?.layer.removeAllAnimations()
        flashOverlayView?.alpha = 0.0
        controllerDelegate?.cameraDidCapture(data: data, ext: ext, thumbnail: thumbnail)
    }

    func cameraDidSwitchPosition(isFront: Bool) {
        controllerDelegate?.cameraDidSwitchCamera(isFront: isFront)
        setupSubjectAreaObserver()
    }

    // MARK: - Public API (called from Coordinator)

    func capturePhoto() {
        // Tactile + visual feedback
        Haptics.light()
        quickFlash()
        cameraService.capturePhoto(flash: flashEnabled)
    }

    func switchCamera() {
        cameraService.switchCamera()
    }

    func updateZoom(_ factor: CGFloat) {
        cameraService.setZoom(factor)
    }

    func pauseSession() {
        cameraService.pause()
    }

    func resumeSession() {
        cameraService.resume()
    }

    // MARK: - Gestures

    @objc private func handlePinchGesture(_ gesture: UIPinchGestureRecognizer) {
        cameraService.applyPinchZoom(scale: gesture.scale)
        DispatchQueue.main.async { gesture.scale = 1.0 }
    }

    @objc private func handleTapGesture(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: view)
        let devicePoint = cameraService.previewLayer?.captureDevicePointConverted(fromLayerPoint: location) ?? CGPoint(x: 0.5, y: 0.5)
        isFocusLocked = false
        cameraService.focusAndExpose(at: devicePoint, lock: false)
        showFocusIndicator(at: location, locked: false)
    }

    @objc private func handleDoubleTapGesture(_ gesture: UITapGestureRecognizer) {
        let center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
        let devicePoint = cameraService.previewLayer?.captureDevicePointConverted(fromLayerPoint: center) ?? CGPoint(x: 0.5, y: 0.5)
        isFocusLocked = false
        cameraService.focusAndExpose(at: devicePoint, lock: false)
        removeFocusIndicator()
        showFocusIndicator(at: center, locked: false)
    }

    @objc private func handleLongPressGesture(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began {
            let location = gesture.location(in: view)
            let devicePoint = cameraService.previewLayer?.captureDevicePointConverted(fromLayerPoint: location) ?? CGPoint(x: 0.5, y: 0.5)
            isFocusLocked = true
            cameraService.focusAndExpose(at: devicePoint, lock: true)
            showFocusIndicator(at: location, locked: true)
        }
    }

    // MARK: - UI Helpers

    private func quickFlash() {
        guard let overlay = flashOverlayView else { return }
        overlay.layer.removeAllAnimations()
        overlay.alpha = 0.0
        UIView.animateKeyframes(withDuration: 0.18, delay: 0, options: [.calculationModeLinear], animations: {
            UIView.addKeyframe(withRelativeStartTime: 0.0, relativeDuration: 0.2) {
                overlay.alpha = 1.0
            }
            UIView.addKeyframe(withRelativeStartTime: 0.2, relativeDuration: 0.8) {
                overlay.alpha = 0.0
            }
        }, completion: nil)
    }

    private func showFocusIndicator(at location: CGPoint, locked: Bool) {
        if !locked { removeFocusIndicator() }
        let size: CGFloat = 90
        let rect = CGRect(x: location.x - size/2, y: location.y - size/2, width: size, height: size)
        let v = UIView(frame: rect)
        v.isUserInteractionEnabled = false
        v.backgroundColor = .clear
        let shape = CAShapeLayer()
        shape.path = UIBezierPath(roundedRect: v.bounds, cornerRadius: 10).cgPath
        shape.lineWidth = 2
        shape.strokeColor = (locked ? UIColor.systemGreen : UIColor.systemYellow).cgColor
        shape.fillColor = UIColor.clear.cgColor
        v.layer.addSublayer(shape)
        if locked {
            let lockIcon = UIImageView(image: UIImage(systemName: "lock.fill"))
            lockIcon.tintColor = .systemGreen
            lockIcon.frame = CGRect(x: (size-20)/2, y: (size-20)/2, width: 20, height: 20)
            v.addSubview(lockIcon)
            focusIndicatorView = v
        }
        view.addSubview(v)
        let pulse = CABasicAnimation(keyPath: "transform.scale")
        pulse.fromValue = 1.2
        pulse.toValue = 1.0
        pulse.duration = 0.2
        v.layer.add(pulse, forKey: "pulse")
        if !locked {
            UIView.animate(withDuration: 0.8, delay: 0.6, options: [.curveEaseOut], animations: {
                v.alpha = 0
            }) { _ in v.removeFromSuperview() }
        }
    }

    private func removeFocusIndicator() {
        focusIndicatorView?.removeFromSuperview()
        focusIndicatorView = nil
    }

    private func setupSubjectAreaObserver() {
        if let obs = subjectAreaObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        guard let device = cameraService.currentDevice() else { return }
        subjectAreaObserver = NotificationCenter.default.addObserver(
            forName: AVCaptureDevice.subjectAreaDidChangeNotification,
            object: device, queue: .main
        ) { [weak self] _ in
            guard let self, !self.isFocusLocked else { return }
            let center = CGPoint(x: self.view.bounds.midX, y: self.view.bounds.midY)
            let devicePoint = self.cameraService.previewLayer?.captureDevicePointConverted(fromLayerPoint: center) ?? CGPoint(x: 0.5, y: 0.5)
            self.cameraService.focusAndExpose(at: devicePoint, lock: false)
        }
    }
}
