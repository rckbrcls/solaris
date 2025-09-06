import UIKit
import AVFoundation
import SwiftUI

class CameraViewController: UIViewController, AVCapturePhotoCaptureDelegate {
    var captureSession: AVCaptureSession?
    var photoOutput: AVCapturePhotoOutput?
    var previewLayer: AVCaptureVideoPreviewLayer?
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    var capturedImage: Binding<UIImage?> = .constant(nil)
    var isPhotoTaken: Binding<Bool> = .constant(false)
    var isFlashOn: Binding<Bool> = .constant(false)
    var zoomFactor: Binding<CGFloat> = .constant(1.0)
    var currentCameraPosition: AVCaptureDevice.Position = .back
    var isFrontCamera: Binding<Bool> = .constant(false)
    var flashOverlayView: UIView?
    // Focus state and UI
    private var isFocusLocked: Bool = false
    private var focusIndicatorView: UIView?
    private var subjectAreaObserver: NSObjectProtocol?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Configure capture session on a dedicated queue
        captureSession = AVCaptureSession()
        // Highest quality for still photos
        captureSession?.sessionPreset = .photo

        sessionQueue.async { [weak self] in
            guard let self = self, let session = self.captureSession else { return }
            guard let videoCaptureDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let videoInput = try? AVCaptureDeviceInput(device: videoCaptureDevice) else { return }

            if session.canAddInput(videoInput) {
                session.addInput(videoInput)
            }

            let photoOutput = AVCapturePhotoOutput()
            photoOutput.isHighResolutionCaptureEnabled = true
            if #available(iOS 15.0, *) {
                photoOutput.maxPhotoQualityPrioritization = .quality
            }
            if session.canAddOutput(photoOutput) {
                session.addOutput(photoOutput)
                DispatchQueue.main.async { self.photoOutput = photoOutput }
            }

            session.startRunning()
        }

        // Setup preview on main thread
        if let cs = captureSession {
            previewLayer = AVCaptureVideoPreviewLayer(session: cs)
            previewLayer?.videoGravity = .resizeAspectFill
            previewLayer?.frame = view.layer.bounds
            if let connection = previewLayer?.connection, connection.isVideoOrientationSupported {
                connection.videoOrientation = .portrait
            }
            if let pl = previewLayer {
                view.layer.addSublayer(pl)
            }
        }
        
        flashOverlayView = UIView(frame: view.bounds)
        flashOverlayView?.backgroundColor = UIColor.white
        flashOverlayView?.alpha = 0
        flashOverlayView?.isUserInteractionEnabled = false
        view.addSubview(flashOverlayView!)
        if let overlay = flashOverlayView { view.bringSubviewToFront(overlay) }
        
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
        
        NotificationCenter.default.addObserver(self, selector: #selector(capturePhoto), name: .capturePhoto, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(switchCamera), name: .switchCamera, object: nil)
        
        // Enable subject-area monitoring for adaptive AF/AE
        configureSubjectAreaMonitoring(enabled: true)
        // Initialize AF/AE to center
        let center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
        let devicePoint = previewLayer?.captureDevicePointConverted(fromLayerPoint: center) ?? CGPoint(x: 0.5, y: 0.5)
        setContinuousAutoFocusExposure(at: devicePoint)
        // startRunning already called on sessionQueue
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if let pl = previewLayer {
            pl.frame = view.bounds
            if let connection = pl.connection, connection.isVideoOrientationSupported {
                connection.videoOrientation = .portrait
            }
        }
        flashOverlayView?.frame = view.bounds
    }
    
    @objc func capturePhoto() {
        let settings = AVCapturePhotoSettings()
        settings.isHighResolutionPhotoEnabled = true
        if #available(iOS 15.0, *) {
            settings.photoQualityPrioritization = .quality
        }
        if isFlashOn.wrappedValue {
            settings.flashMode = .on
        } else {
            settings.flashMode = .off
        }
        guard let po = photoOutput else { return }
        // Immediate tactile + visual feedback
        DispatchQueue.main.async {
            let gen = UIImpactFeedbackGenerator(style: .light)
            gen.impactOccurred()
            self.quickFlash()
        }
        po.capturePhoto(with: settings, delegate: self)
    }
    
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard let imageData = photo.fileDataRepresentation(),
              let image = UIImage(data: imageData) else { return }
        
        DispatchQueue.main.async {
            // Ensure overlay is cleared and deliver result
            self.flashOverlayView?.layer.removeAllAnimations()
            self.flashOverlayView?.alpha = 0.0
            self.capturedImage.wrappedValue = image
            self.isPhotoTaken.wrappedValue = true
        }
    }

    // Faster, snappier flash feedback
    private func quickFlash() {
        guard let overlay = self.flashOverlayView else { return }
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
    
    func updateZoomFactor() {
        let desiredZoom = zoomFactor.wrappedValue
        sessionQueue.async { [weak self] in
            guard let self = self, let currentInput = self.captureSession?.inputs.first as? AVCaptureDeviceInput else { return }
            let device = currentInput.device
            do {
                try device.lockForConfiguration()
                let clamped = min(max(desiredZoom, 0.5), min(5.0, device.activeFormat.videoMaxZoomFactor))
                device.videoZoomFactor = clamped
                device.unlockForConfiguration()
            } catch {
                print("Error setting zoom factor: \(error)")
            }
        }
    }
    
    @objc func handlePinchGesture(_ gesture: UIPinchGestureRecognizer) {
        let scale = gesture.scale
        sessionQueue.async { [weak self] in
            guard let self = self, let currentInput = self.captureSession?.inputs.first as? AVCaptureDeviceInput else { return }
            let device = currentInput.device
            do {
                try device.lockForConfiguration()
                let maxZoom = device.activeFormat.videoMaxZoomFactor
                let desiredZoomFactor = min(max(device.videoZoomFactor * scale, 1.0), maxZoom)
                device.videoZoomFactor = desiredZoomFactor
                device.unlockForConfiguration()
            } catch {
                print("Error setting zoom factor")
            }
            DispatchQueue.main.async { gesture.scale = 1.0 }
        }
    }
    
    @objc func handleTapGesture(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: view)
        let devicePoint = previewLayer?.captureDevicePointConverted(fromLayerPoint: location) ?? CGPoint(x: 0.5, y: 0.5)
        isFocusLocked = false
        setContinuousAutoFocusExposure(at: devicePoint)
        showFocusIndicator(at: location, locked: false)
    }

    @objc func handleDoubleTapGesture(_ gesture: UITapGestureRecognizer) {
        // Reset AF/AE to center and unlock
        let center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
        let devicePoint = previewLayer?.captureDevicePointConverted(fromLayerPoint: center) ?? CGPoint(x: 0.5, y: 0.5)
        isFocusLocked = false
        setContinuousAutoFocusExposure(at: devicePoint)
        removeFocusIndicator()
        showFocusIndicator(at: center, locked: false)
    }

    @objc func handleLongPressGesture(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began {
            let location = gesture.location(in: view)
            let devicePoint = previewLayer?.captureDevicePointConverted(fromLayerPoint: location) ?? CGPoint(x: 0.5, y: 0.5)
            isFocusLocked = true
            setContinuousAutoFocusExposure(at: devicePoint)
            showFocusIndicator(at: location, locked: true)
            // Lock after a short settling time
            sessionQueue.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.lockFocusExposure()
            }
        }
    }
    
    @objc func switchCamera() {
        sessionQueue.async { [weak self] in
            guard let self = self, let cs = self.captureSession, let currentInput = cs.inputs.first as? AVCaptureDeviceInput else { return }
            cs.beginConfiguration()
            cs.removeInput(currentInput)

            self.currentCameraPosition = (self.currentCameraPosition == .back) ? .front : .back

            guard let newDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: self.currentCameraPosition),
                  let newInput = try? AVCaptureDeviceInput(device: newDevice) else {
                cs.addInput(currentInput)
                cs.commitConfiguration()
                return
            }
            if cs.canAddInput(newInput) {
                cs.addInput(newInput)
            } else {
                cs.addInput(currentInput)
            }
            cs.commitConfiguration()
            
            // Atualiza o binding para indicar se é câmera frontal
            DispatchQueue.main.async {
                self.isFrontCamera.wrappedValue = (self.currentCameraPosition == .front)
            }
            self.configureSubjectAreaMonitoring(enabled: true)
        }
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        sessionQueue.async { [weak self] in
            self?.captureSession?.stopRunning()
        }
        NotificationCenter.default.removeObserver(self, name: .capturePhoto, object: nil)
        NotificationCenter.default.removeObserver(self, name: .switchCamera, object: nil)
        if let observer = subjectAreaObserver {
            NotificationCenter.default.removeObserver(observer)
            subjectAreaObserver = nil
        }
    }

    // MARK: - Focus helpers
    private func currentDevice() -> AVCaptureDevice? {
        return (captureSession?.inputs.first as? AVCaptureDeviceInput)?.device
    }

    private func configureSubjectAreaMonitoring(enabled: Bool) {
        sessionQueue.async { [weak self] in
            guard let self = self, let device = self.currentDevice() else { return }
            do {
                try device.lockForConfiguration()
                device.isSubjectAreaChangeMonitoringEnabled = enabled
                if device.isSmoothAutoFocusSupported { device.isSmoothAutoFocusEnabled = true }
                device.unlockForConfiguration()
            } catch {
                print("Error configuring subject-area monitoring: \(error)")
            }
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                if enabled {
                    if let obs = self.subjectAreaObserver { NotificationCenter.default.removeObserver(obs) }
                    self.subjectAreaObserver = NotificationCenter.default.addObserver(forName: .AVCaptureDeviceSubjectAreaDidChange, object: device, queue: .main) { [weak self] _ in
                        guard let self = self, !self.isFocusLocked else { return }
                        let center = CGPoint(x: self.view.bounds.midX, y: self.view.bounds.midY)
                        let devicePoint = self.previewLayer?.captureDevicePointConverted(fromLayerPoint: center) ?? CGPoint(x: 0.5, y: 0.5)
                        self.setContinuousAutoFocusExposure(at: devicePoint)
                    }
                } else if let obs = self.subjectAreaObserver {
                    NotificationCenter.default.removeObserver(obs)
                    self.subjectAreaObserver = nil
                }
            }
        }
    }

    private func setContinuousAutoFocusExposure(at devicePoint: CGPoint) {
        sessionQueue.async { [weak self] in
            guard let self = self, let device = self.currentDevice() else { return }
            do {
                try device.lockForConfiguration()
                if device.isFocusPointOfInterestSupported && device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusPointOfInterest = devicePoint
                    device.focusMode = .continuousAutoFocus
                } else if device.isFocusModeSupported(.autoFocus) {
                    device.focusMode = .autoFocus
                }
                if device.isExposurePointOfInterestSupported && device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposurePointOfInterest = devicePoint
                    device.exposureMode = .continuousAutoExposure
                } else if device.isExposureModeSupported(.autoExpose) {
                    device.exposureMode = .autoExpose
                }
                if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                    device.whiteBalanceMode = .continuousAutoWhiteBalance
                }
                if device.isSmoothAutoFocusSupported { device.isSmoothAutoFocusEnabled = true }
                device.unlockForConfiguration()
            } catch {
                print("Focus configuration error: \(error)")
            }
        }
    }

    private func lockFocusExposure() {
        sessionQueue.async { [weak self] in
            guard let self = self, let device = self.currentDevice() else { return }
            do {
                try device.lockForConfiguration()
                if device.isFocusModeSupported(.locked) {
                    device.setFocusModeLocked(lensPosition: device.lensPosition, completionHandler: nil)
                }
                if device.isExposureModeSupported(.locked) {
                    device.exposureMode = .locked
                }
                device.isSubjectAreaChangeMonitoringEnabled = false
                device.unlockForConfiguration()
            } catch {
                print("Lock focus/exposure error: \(error)")
            }
        }
    }

    private func showFocusIndicator(at location: CGPoint, locked: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if !locked { self.removeFocusIndicator() }
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
                self.focusIndicatorView = v
            }
            self.view.addSubview(v)
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
    }

    private func removeFocusIndicator() {
        DispatchQueue.main.async { [weak self] in
            self?.focusIndicatorView?.removeFromSuperview()
            self?.focusIndicatorView = nil
        }
    }
}
