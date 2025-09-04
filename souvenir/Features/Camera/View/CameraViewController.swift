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
    var flashOverlayView: UIView?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Configure capture session on a dedicated queue
        captureSession = AVCaptureSession()
        captureSession?.sessionPreset = .hd1920x1080

        sessionQueue.async { [weak self] in
            guard let self = self, let session = self.captureSession else { return }
            guard let videoCaptureDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let videoInput = try? AVCaptureDeviceInput(device: videoCaptureDevice) else { return }

            if session.canAddInput(videoInput) {
                session.addInput(videoInput)
            }

            let photoOutput = AVCapturePhotoOutput()
            if session.canAddOutput(photoOutput) {
                session.addOutput(photoOutput)
                DispatchQueue.main.async { self.photoOutput = photoOutput }
            }

            session.startRunning()
        }

        // Setup preview on main thread
        if let cs = captureSession {
            previewLayer = AVCaptureVideoPreviewLayer(session: cs)
            previewLayer?.videoGravity = .resizeAspect
            previewLayer?.frame = view.layer.bounds
            if let pl = previewLayer {
                view.layer.addSublayer(pl)
            }
        }
        
        flashOverlayView = UIView(frame: view.bounds)
        flashOverlayView?.backgroundColor = UIColor.white
        flashOverlayView?.alpha = 0
        view.addSubview(flashOverlayView!)
        
        let pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinchGesture(_:)))
        view.addGestureRecognizer(pinchGesture)
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTapGesture(_:)))
        view.addGestureRecognizer(tapGesture)
        
        NotificationCenter.default.addObserver(self, selector: #selector(capturePhoto), name: .capturePhoto, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(switchCamera), name: .switchCamera, object: nil)
        
        // startRunning already called on sessionQueue
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if let pl = previewLayer {
            pl.frame = view.bounds
        }
        flashOverlayView?.frame = view.bounds
    }
    
    @objc func capturePhoto() {
        let settings = AVCapturePhotoSettings()
        if isFlashOn.wrappedValue {
            settings.flashMode = .on
        } else {
            settings.flashMode = .off
        }
        guard let po = photoOutput else { return }
        po.capturePhoto(with: settings, delegate: self)
    }
    
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard let imageData = photo.fileDataRepresentation(),
              let image = UIImage(data: imageData) else { return }
        
        DispatchQueue.main.async {
            // Flash animation for visual feedback
            self.flashOverlayView?.alpha = 1.0
            UIView.animate(withDuration: 0.3, animations: {
                self.flashOverlayView?.alpha = 0.0
            })
            self.capturedImage.wrappedValue = image
            self.isPhotoTaken.wrappedValue = true
        }
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
        let focusPoint = CGPoint(x: location.y / view.bounds.height, y: 1.0 - (location.x / view.bounds.width))
        sessionQueue.async { [weak self] in
            guard let self = self, let currentInput = self.captureSession?.inputs.first as? AVCaptureDeviceInput else { return }
            let device = currentInput.device
            if device.isFocusPointOfInterestSupported && device.isExposurePointOfInterestSupported {
                do {
                    try device.lockForConfiguration()
                    device.focusPointOfInterest = focusPoint
                    device.focusMode = .autoFocus
                    device.exposurePointOfInterest = focusPoint
                    device.exposureMode = .autoExpose
                    device.unlockForConfiguration()
                } catch {
                    print("Error setting focus")
                }
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    let focusRect = CGRect(x: location.x - 50, y: location.y - 50, width: 100, height: 100)
                    let focusIndicator = UIView(frame: focusRect)
                    focusIndicator.layer.borderColor = UIColor.yellow.cgColor
                    focusIndicator.layer.borderWidth = 2.0
                    focusIndicator.backgroundColor = UIColor.clear
                    self.view.addSubview(focusIndicator)
                    UIView.animate(withDuration: 1.0, animations: {
                        focusIndicator.alpha = 0
                    }) { _ in
                        focusIndicator.removeFromSuperview()
                    }
                }
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
        }
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        sessionQueue.async { [weak self] in
            self?.captureSession?.stopRunning()
        }
        NotificationCenter.default.removeObserver(self, name: .capturePhoto, object: nil)
        NotificationCenter.default.removeObserver(self, name: .switchCamera, object: nil)
    }
}
