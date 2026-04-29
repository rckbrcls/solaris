import SwiftUI
import AVFoundation
import UIKit

// Reusable shutter button with consistent style and press feedback
private struct ShutterButton: View {
    var size: CGFloat = 78
    var body: some View {
        Circle()
            .fill(Color.clear)
            .frame(width: size, height: size)
            .liquidGlass(
                in: Circle(),
                borderColor: Color.borderSubtle
            )
            .contentShape(Circle())
        .accessibilityLabel(String(localized: "Capture photo"))
        .accessibilityAddTraits(.isButton)
    }
}

private struct PressScaleStyle: ButtonStyle {
    var scale: CGFloat = 0.94
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.9), value: configuration.isPressed)
    }
}

// Icon button style consolidated in Shared/Components/GlassIconStyle.swift

enum AspectOption: String, CaseIterable, Identifiable, Codable {
    case square = "1:1"
    case ratio4x3 = "4:3"
    case ratio3x2 = "3:2"
    case ratio9x16 = "9:16"
    var id: String { rawValue }
    var width: CGFloat {
        switch self {
        case .square: return 1
        case .ratio4x3: return 3
        case .ratio3x2: return 2
        case .ratio9x16: return 9
        }
    }
    var height: CGFloat {
        switch self {
        case .square: return 1
        case .ratio4x3: return 4
        case .ratio3x2: return 3
        case .ratio9x16: return 16
        }
    }
}

struct PhotoCaptureView: View {
    var onPhotoCaptured: (Data, String, Bool) -> Void
    @State private var isFlashOn: Bool = AppSettings.shared.cameraFlashOn
    @State private var isGridOn: Bool = AppSettings.shared.cameraGridOn
    @State private var zoomFactor: CGFloat = 1.0
    @State private var isFrontCamera: Bool = AppSettings.shared.cameraUseFrontCamera
    @State private var selectedAspect: AspectOption = AppSettings.shared.cameraAspectRatio
    @State private var showAspectMenu: Bool = false
    @State private var cameraPermission: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var cameraCommands = CameraCommands()
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()
            switch cameraPermission {
            case .authorized:
                cameraContent
            case .notDetermined:
                Color.backgroundPrimary.ignoresSafeArea()
                    .onAppear { requestCameraAccess() }
            default:
                permissionDeniedView
            }
        }
    }

    private func requestCameraAccess() {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                cameraPermission = AVCaptureDevice.authorizationStatus(for: .video)
            }
        }
    }

    private var permissionDeniedView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "camera.slash")
                .font(.system(size: 56))
                .foregroundColor(Color.textSecondary)
            Text(String(localized: "Camera Access Required"))
                .font(.title3.bold())
                .foregroundColor(Color.textPrimary)
            Text(String(localized: "Solaris needs camera access to capture photos. Please enable it in Settings."))
                .font(.subheadline)
                .foregroundColor(Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button(action: {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }) {
                Text(String(localized: "Open Settings"))
                    .font(.body.bold())
                    .padding(.horizontal, 32)
                    .padding(.vertical, 12)
                    .background(Color.actionAccent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .foregroundColor(Color.textOnAccent)
            }
            Spacer()
            Button(action: { dismiss() }) {
                Text(String(localized: "Close"))
                    .font(.body)
                    .foregroundColor(Color.textSecondary)
            }
            .padding(.bottom, 40)
        }
        .accessibilityElement(children: .contain)
    }

    private var cameraContent: some View {
        GeometryReader { outerGeo in
            let previewW = outerGeo.size.width
            cameraContentInner(previewW: previewW)
        }
    }

    private func cameraContentInner(previewW: CGFloat) -> some View {
        VStack {
                ZStack {
                    let previewH: CGFloat = previewW * (selectedAspect.height / max(1, selectedAspect.width))
                    CameraPreview(
                        onPhotoCaptured: { data, ext, thumbnail in
                            dismiss()
                            onPhotoCaptured(data, ext, isFrontCamera)
                        },
                        onCameraSwitched: { isFront in
                            isFrontCamera = isFront
                        },
                        flashEnabled: isFlashOn,
                        zoomFactor: zoomFactor,
                        commands: cameraCommands
                    )
                        .frame(width: previewW, height: previewH)
                        .animation(.easeInOut(duration: 0.22), value: selectedAspect)
                        .clipped()
                        .cornerRadius(20)

                    if isGridOn {
                        GeometryReader { geo in
                            let width = geo.size.width
                            let height = geo.size.height
                            let lineWidth = max(0.4, min(0.9, min(width, height) / 500))
                            let gridColor = Color.gridLine

                            Canvas { context, size in
                                let w = size.width
                                let h = size.height
                                let columnWidth = w / 3
                                let rowHeight = h / 3

                                var path = Path()
                                path.move(to: CGPoint(x: columnWidth, y: 0))
                                path.addLine(to: CGPoint(x: columnWidth, y: h))
                                path.move(to: CGPoint(x: 2 * columnWidth, y: 0))
                                path.addLine(to: CGPoint(x: 2 * columnWidth, y: h))
                                path.move(to: CGPoint(x: 0, y: rowHeight))
                                path.addLine(to: CGPoint(x: w, y: rowHeight))
                                path.move(to: CGPoint(x: 0, y: 2 * rowHeight))
                                path.addLine(to: CGPoint(x: w, y: 2 * rowHeight))

                                context.stroke(path, with: .color(gridColor), lineWidth: lineWidth)
                            }
                            .blendMode(.overlay)
                            .allowsHitTesting(false)
                        }
                        .frame(width: previewW, height: previewH)
                        .animation(.easeInOut(duration: 0.22), value: selectedAspect)
                        .clipped()
                        .cornerRadius(20)
                    }

                    VStack(spacing: 8) {
                        HStack {
                            Button(action: { dismiss() }) {
                                Image(systemName: "xmark")
                                    .glassIconStyle()
                            }
                            .accessibilityLabel(String(localized: "Close camera"))
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        Spacer()
                        HStack(alignment: .center) {
                            Spacer()
                            Button(action: { cameraCommands.capture() }) {
                                ShutterButton()
                                    .scaleEffect(1.0)
                            }
                            .padding(20)
                            .offset(y: 14)
                            .buttonStyle(PressScaleStyle())
                            Spacer()
                        }
                    }
                    .frame(width: previewW, height: previewW * 16.0 / 9.0)
                }

                // Bottom overlay controls
                VStack {
                    if showAspectMenu {
                        HStack {
                            Spacer(minLength: 0)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 4) {
                                    ForEach(AspectOption.allCases) { opt in
                                        Button(action: { withAnimation(.easeOut(duration: 0.15)) { selectedAspect = opt; showAspectMenu = false } }) {
                                            Text(opt.rawValue)
                                                .font(.caption.bold())
                                                .foregroundColor(selectedAspect == opt ? Color.textOnAccent : Color.textPrimary)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(
                                                    selectedAspect == opt ? Color.actionAccent : Color.borderSubtle
                                                )
                                                .clipShape(Capsule())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.horizontal, 8)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    HStack(alignment: .center) {
                        Button(action: { isGridOn.toggle() }) {
                            Image(systemName: isGridOn ? "square.grid.3x3.fill" : "square.grid.3x3")
                                .glassIconStyle()
                        }
                        .accessibilityLabel(String(localized: "Toggle grid"))
                        Spacer()
                        Button(action: { isFlashOn.toggle() }) {
                            Image(systemName: isFlashOn ? "bolt.fill" : "bolt")
                                .glassIconStyle()
                        }
                        .accessibilityLabel(String(localized: "Toggle flash"))
                        Spacer()
                        Button(action: { withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) { showAspectMenu.toggle() } }) {
                            Image(systemName: "rectangle.split.2x1")
                                .glassIconStyle()
                                .accessibilityLabel(String(localized: "Aspect ratio"))
                        }
                        Spacer()
                        Button(action: { cameraCommands.switchCamera() }) {
                            Image(systemName: "camera.rotate")
                                .glassIconStyle()
                        }
                        .accessibilityLabel(String(localized: "Switch camera"))
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)

            }
                .navigationBarBackButtonHidden(true)
                .onChange(of: isFlashOn) { _, val in AppSettings.shared.cameraFlashOn = val }
                .onChange(of: isGridOn) { _, val in AppSettings.shared.cameraGridOn = val }
                .onChange(of: selectedAspect) { _, val in AppSettings.shared.cameraAspectRatio = val }
                .onChange(of: isFrontCamera) { _, val in AppSettings.shared.cameraUseFrontCamera = val }
                .padding(.top)
                .tint(Color.textPrimary)
    }
}


#Preview {
    PhotoCaptureView(onPhotoCaptured: { _, _, _ in })
}
