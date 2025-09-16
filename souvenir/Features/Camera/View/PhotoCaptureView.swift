import SwiftUI
import AVFoundation
import Foundation
import UIKit  // Adicionado para garantir que UIImage está disponível

// Reusable shutter button with consistent style and press feedback
private struct ShutterButton: View {
    var size: CGFloat = 78
    var body: some View {
        ZStack {
            // Outer ring (subtle)
            Circle()
                .fill(.ultraThinMaterial)
                .overlay(
                    Circle().stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .accessibilityLabel("Capturar foto")
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

// Estilo consistente para ícones redondos na câmera
private struct CameraIconButtonStyle: ViewModifier {
    var size: CGFloat = 44
    var background: Material = .ultraThinMaterial
    var foreground: Color = .primary

    func body(content: Content) -> some View {
        content
            .foregroundColor(foreground)
            .frame(width: size, height: size)
            .background(background, in: Circle())
            .overlay(
                Circle()
                    .stroke(Color.primary.opacity(0.2), lineWidth: 1)
            )
            .contentShape(Circle())
    }
}

private extension View {
    func cameraIconStyle(size: CGFloat = 44, background: Material = .ultraThinMaterial) -> some View {
        self.modifier(CameraIconButtonStyle(size: size, background: background))
    }
}

struct PhotoCaptureView: View {
    var onPhotoCaptured: (UIImage) -> Void
    @State private var capturedImage: UIImage? = nil
    @State private var isPhotoTaken: Bool = false
    @State private var isFlashOn: Bool = false
    @State private var isGridOn: Bool = false
    @State private var zoomFactor: CGFloat = 1.0
    @State private var isFrontCamera: Bool = false
    // Aspect ratio selection
    enum AspectOption: String, CaseIterable, Identifiable {
        case square = "1:1"
        case ratio4x3 = "4:3"   // portrait
        case ratio3x2 = "3:2"   // portrait
        case ratio9x16 = "9:16" // portrait
        var id: String { rawValue }
        // Returns width:height factors (portrait-aware)
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
    @State private var selectedAspect: AspectOption = .ratio4x3
    @State private var showAspectMenu: Bool = false
    @Environment(\.dismiss) var dismiss
    @State private var isDraggingDismiss: Bool = false
    
    var body: some View {
        ZStack {
            Color(UIColor.systemBackground).ignoresSafeArea()
            VStack {
                ZStack {
                    let previewW = UIScreen.main.bounds.width
                    let previewH: CGFloat = previewW * (selectedAspect.height / max(1, selectedAspect.width))
                    CameraPreview(capturedImage: $capturedImage, isPhotoTaken: $isPhotoTaken, isFlashOn: $isFlashOn, zoomFactor: $zoomFactor, isFrontCamera: $isFrontCamera)
                        .allowsHitTesting(!isDraggingDismiss)
                        .frame(width: previewW, height: previewH)
                        .animation(.easeInOut(duration: 0.22), value: selectedAspect)
                        .clipped()
                        .cornerRadius(20)
                
                    if isGridOn {
                        // Grid must match the preview's frame to follow aspect changes
                        GeometryReader { geo in
                            let width = geo.size.width
                            let height = geo.size.height
                            let lineWidth = max(0.4, min(0.9, min(width, height) / 500))
                            let gridColor = Color.white.opacity(0.42)

                            Canvas { context, size in
                                let w = size.width
                                let h = size.height
                                let columnWidth = w / 3
                                let rowHeight = h / 3

                                var path = Path()
                                // Vertical lines
                                path.move(to: CGPoint(x: columnWidth, y: 0))
                                path.addLine(to: CGPoint(x: columnWidth, y: h))
                                path.move(to: CGPoint(x: 2 * columnWidth, y: 0))
                                path.addLine(to: CGPoint(x: 2 * columnWidth, y: h))
                                // Horizontal lines
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
                            Button(action: {
                                dismiss()
                            }) {
                                Image(systemName: "xmark")
                                    .cameraIconStyle()
                            }
                            
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        Spacer()
                        HStack(alignment: .center) {
                            Spacer()
                            
                            Button(action: {
                                NotificationCenter.default.post(name: .capturePhoto, object: nil)
                            }) {
                                ShutterButton()
                                    .scaleEffect(1.0)
                            }
                            .padding(20)
                            .offset(y: 14)
                            .buttonStyle(PressScaleStyle())
                            
                            Spacer()
                            // Additional button or user-selected functionality can be placed here
                        }
                    }
                    .frame(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.width * 16.0 / 9.0)
                }
                
                // Bottom overlay controls: grid, flash, aspect, switch
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
                                                .foregroundColor(selectedAspect == opt ? .white : .primary)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(
                                                    selectedAspect == opt ? Color.accentColor : Color.primary.opacity(0.08)
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
                                .cameraIconStyle()
                        }
                        Spacer()
                        Button(action: { isFlashOn.toggle() }) {
                            Image(systemName: isFlashOn ? "bolt.fill" : "bolt")
                                .cameraIconStyle()
                        }
                        Spacer()
                        Button(action: { withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) { showAspectMenu.toggle() } }) {
                            Image(systemName: "rectangle.split.2x1")
                                .cameraIconStyle()
                                .accessibilityLabel("Aspect Ratio")
                        }
                        Spacer()
                        Button(action: { NotificationCenter.default.post(name: .switchCamera, object: nil) }) {
                            Image(systemName: "camera.rotate")
                                .cameraIconStyle()
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                
            }
                .navigationBarBackButtonHidden(true)
                .onChange(of: capturedImage) { newImage in
                    guard let image = newImage else { return }

                    // Dismiss immediately to keep UI responsive
                    dismiss()

                    // Process off the main thread to avoid blocking UI
                    Task(priority: .userInitiated) {
                        var processed = image.fixOrientation()

                        if isFrontCamera && AppSettings.shared.mirrorFrontCamera {
                            processed = processed.horizontallyMirrored()
                        }

                        let cropped = cropToSelectedAspect(processed, aspect: selectedAspect)

                        await MainActor.run {
                            onPhotoCaptured(cropped)
                        }
                    }
                }
                .padding(.top)
                .highPriorityGesture(
                    DragGesture(minimumDistance: 20)
                        .onChanged { value in
                            // Apenas sinaliza que está arrastando para evitar conflitos de gesto do preview
                            if value.translation.height > 0 { isDraggingDismiss = true }
                        }
                        .onEnded { value in
                            defer { isDraggingDismiss = false }
                            let threshold: CGFloat = 120
                            if value.translation.height > threshold {
                                // Não anima o conteúdo; apenas faz o mesmo dismiss do botão (animação do sistema)
                                dismiss()
                            }
                        }
                )
                .tint(.primary)
            }
        }
    }


#Preview {
    PhotoCaptureView(onPhotoCaptured: { _ in })
}

// MARK: - Helpers
extension PhotoCaptureView {
    private func cropToSelectedAspect(_ image: UIImage, aspect: AspectOption) -> UIImage {
        // Always crop to selected portrait aspect
        let w = image.size.width
        let h = image.size.height
        let targetW = aspect.width
        let targetH = aspect.height
        guard targetW > 0, targetH > 0 else { return image }
        let targetRatio = targetW / targetH
        let imageRatio = w / h
        var cropRect: CGRect
        if imageRatio > targetRatio {
            // image is wider than target; crop width
            let newW = h * targetRatio
            cropRect = CGRect(x: (w - newW) / 2.0, y: 0, width: newW, height: h)
        } else {
            // image is taller than target; crop height
            let newH = w / targetRatio
            cropRect = CGRect(x: 0, y: (h - newH) / 2.0, width: w, height: newH)
        }
        guard let cg = image.cgImage?.cropping(to: cropRect.integral) else { return image }
        // Return cropped (keeping original scale/orientation as .up)
        return UIImage(cgImage: cg, scale: image.scale, orientation: .up)
    }
}

