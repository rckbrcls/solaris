import UIKit
import AVFoundation

/// Delegate protocol for camera events — replaces NotificationCenter-based communication.
protocol CameraServiceDelegate: AnyObject {
    func cameraDidCapturePhoto(data: Data, ext: String, thumbnail: UIImage?)
    func cameraDidSwitchPosition(isFront: Bool)
}

/// Encapsulates all AVFoundation camera logic: session management, capture, switching, focus/exposure, zoom.
final class CameraService: NSObject, AVCapturePhotoCaptureDelegate {
    weak var delegate: CameraServiceDelegate?

    let session = AVCaptureSession()
    let sessionQueue = DispatchQueue(label: "camera.session.queue")
    private(set) var photoOutput = AVCapturePhotoOutput()
    private(set) var currentPosition: AVCaptureDevice.Position = .back

    var previewLayer: AVCaptureVideoPreviewLayer?

    // MARK: - Configuration

    func configure(position: AVCaptureDevice.Position) {
        currentPosition = position
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.sessionPreset = .photo

            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
                  let input = try? AVCaptureDeviceInput(device: device) else { return }

            if self.session.canAddInput(input) {
                self.session.addInput(input)
            }

            if self.session.canAddOutput(self.photoOutput) {
                self.session.addOutput(self.photoOutput)
            }

            // Configure after output is connected — maxPhotoDimensions requires an active device format
            if let maxDimensions = device.activeFormat.supportedMaxPhotoDimensions.last {
                self.photoOutput.maxPhotoDimensions = maxDimensions
            }
            self.photoOutput.maxPhotoQualityPrioritization = .quality
            self.photoOutput.isAppleProRAWEnabled = self.photoOutput.isAppleProRAWSupported

            // Set portrait rotation on photo output connection so captured photos have correct EXIF orientation
            self.applyPortraitRotation()

            self.session.startRunning()
        }
    }

    // MARK: - Capture

    func capturePhoto(flash: Bool) {
        var settings: AVCapturePhotoSettings
        let availableFormats = photoOutput.availablePhotoCodecTypes
        if availableFormats.contains(.hevc) {
            settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
        } else if availableFormats.contains(.jpeg) {
            settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
        } else {
            settings = AVCapturePhotoSettings()
        }
        settings.maxPhotoDimensions = photoOutput.maxPhotoDimensions
        settings.photoQualityPrioritization = .quality
        settings.flashMode = flash ? .on : .off
        if let connection = photoOutput.connection(with: .video),
           connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    // AVCapturePhotoCaptureDelegate
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard let imageData = photo.fileDataRepresentation() else { return }
        let ext = detectImageExtension(data: imageData)
        let thumbnail = loadUIImageThumbnail(from: imageData, maxPixel: 512)
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.cameraDidCapturePhoto(data: imageData, ext: ext, thumbnail: thumbnail)
        }
    }

    // MARK: - Switch Camera

    func switchCamera() {
        sessionQueue.async { [weak self] in
            guard let self, let currentInput = self.session.inputs.first as? AVCaptureDeviceInput else { return }
            self.session.beginConfiguration()
            self.session.removeInput(currentInput)

            self.currentPosition = (self.currentPosition == .back) ? .front : .back

            guard let newDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: self.currentPosition),
                  let newInput = try? AVCaptureDeviceInput(device: newDevice) else {
                self.session.addInput(currentInput)
                self.session.commitConfiguration()
                return
            }
            if self.session.canAddInput(newInput) {
                self.session.addInput(newInput)
            } else {
                self.session.addInput(currentInput)
            }

            // Update maxPhotoDimensions for the new device
            if let maxDimensions = newDevice.activeFormat.supportedMaxPhotoDimensions.last {
                self.photoOutput.maxPhotoDimensions = maxDimensions
            }

            self.session.commitConfiguration()

            // Re-apply portrait rotation after switching camera (connection may change)
            self.applyPortraitRotation()

            DispatchQueue.main.async {
                self.delegate?.cameraDidSwitchPosition(isFront: self.currentPosition == .front)
            }
            self.configureSubjectAreaMonitoring(enabled: true)
        }
    }

    // MARK: - Zoom

    func setZoom(_ factor: CGFloat) {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.currentDevice() else { return }
            do {
                try device.lockForConfiguration()
                let clamped = min(max(factor, 0.5), min(5.0, device.activeFormat.videoMaxZoomFactor))
                device.videoZoomFactor = clamped
                device.unlockForConfiguration()
            } catch {}
        }
    }

    func applyPinchZoom(scale: CGFloat) {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.currentDevice() else { return }
            do {
                try device.lockForConfiguration()
                let maxZoom = device.activeFormat.videoMaxZoomFactor
                let desiredZoomFactor = min(max(device.videoZoomFactor * scale, 1.0), maxZoom)
                device.videoZoomFactor = desiredZoomFactor
                device.unlockForConfiguration()
            } catch {}
        }
    }

    // MARK: - Focus & Exposure

    func focusAndExpose(at devicePoint: CGPoint, lock: Bool) {
        setContinuousAutoFocusExposure(at: devicePoint)
        if lock {
            sessionQueue.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.lockFocusExposure()
            }
        }
    }

    func configureSubjectAreaMonitoring(enabled: Bool) {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.currentDevice() else { return }
            do {
                try device.lockForConfiguration()
                device.isSubjectAreaChangeMonitoringEnabled = enabled
                if device.isSmoothAutoFocusSupported { device.isSmoothAutoFocusEnabled = true }
                device.unlockForConfiguration()
            } catch {}
        }
    }

    private func setContinuousAutoFocusExposure(at devicePoint: CGPoint) {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.currentDevice() else { return }
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
            } catch {}
        }
    }

    private func lockFocusExposure() {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.currentDevice() else { return }
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
            } catch {}
        }
    }

    // MARK: - Session Control

    func pause() {
        sessionQueue.async { [weak self] in
            self?.session.stopRunning()
        }
    }

    func resume() {
        sessionQueue.async { [weak self] in
            guard let self, !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    // MARK: - Helpers

    func currentDevice() -> AVCaptureDevice? {
        (session.inputs.first as? AVCaptureDeviceInput)?.device
    }

    /// Sets videoRotationAngle = 90 on the photo output connection for portrait orientation.
    /// Must be called on sessionQueue after the output is added/reconnected.
    private func applyPortraitRotation() {
        if let connection = photoOutput.connection(with: .video),
           connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
    }
}
